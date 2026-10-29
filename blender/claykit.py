"""claykit - shared helpers for building Tattletale's clay assets in Blender 5.2.

Every asset script does:

    import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import claykit as ck
    ck.reset()
    ... build with ck.box / ck.cyl / ck.sph / ck.text ... (GAME coordinates)
    ck.export("asset_id")          # -> godot/assets/models/asset_id.glb  + blender/blend/asset_id.blend
    ck.preview("asset_id")         # -> .work/previews/asset_id.png (2x2 contact sheet)

Run headless:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python blender/assets/<script>.py

COORDINATES. All helpers take GAME coordinates, the same numbers as the JS:
x east along the street, y up, z toward the viewer (houses at z<0, street z 0..14).
Internally Blender is Z-up: game (x, y, z) -> Blender (x, -z, y). glTF export converts
back, so a model built here lands in Godot exactly where the JS put it.
"Front" of an asset = the side facing game +z (what you see in Blender's Front view).
Rotations: rot=(rx, ry, rz) is a three.js Euler XYZ in radians, converted for you.
Sizes: box(w, h, d) is width (x), height (y), depth (z) like THREE.BoxGeometry.

MATERIALS. Name encodes the look; Godot rebuilds every material from its name:
    clay_RRGGBB_rNN   matte plasticine (NN = roughness*100). The default.
    gloss_RRGGBB_rNN  smooth/varnished clay: car paint, glass windows, plastic.
    metal_RRGGBB_rNN  metal look (aluminium walker, chain, poles if you like).
    glow_RRGGBB_eNN   emissive (NN = strength*10): lamps, ember, light bars.
    glass_RRGGBB_aNN  transparent (NN = opacity*100): fence mesh, pipe glass.
Use ck.mat(...) or the shortcuts ck.clay("#8a4a3a"), ck.gloss(...), ck.glow(...).
Never use image textures: the clay surface detail is added in Godot from the name.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MODELS = os.path.join(ROOT, "godot", "assets", "models")
BLENDS = os.path.join(ROOT, "blender", "blend")
PREVIEWS = os.path.join(ROOT, ".work", "previews")
CLAY_NORMAL = os.path.join(ROOT, "godot", "assets", "materials", "clay_normal.png")
CLAY_MOTTLE = os.path.join(ROOT, "godot", "assets", "materials", "clay_mottle.png")
FONTS = {
    "impact": r"C:\Windows\Fonts\impact.ttf",      # signs, graffiti (JS: Impact / Bungee)
    "black": r"C:\Windows\Fonts\ariblk.ttf",       # chunky lettering (Arial Black)
    "mono": r"C:\Windows\Fonts\courbd.ttf",        # plates, OUT OF ORDER (Courier New Bold)
    "mono_reg": r"C:\Windows\Fonts\cour.ttf",
}
SKY = "#b9d0e4"

# The JS palette, by name, so assets agree with each other.
PAL = {
    "asphalt": "#3a3a40", "sidewalk": "#a8a49a", "curb": "#c8c4b8", "grass": "#6a8a3a", "lawn_brown": "#8a6a3a",
    "lane_yellow": "#f2c21a", "crack": "#5a5a54", "crosswalk": "#e8e4d6", "roof_trim": "#2a2624",
    "window": "#1a2230", "board": "#8a6a3a", "board_light": "#9a7a4a", "door": "#3a2414",
    "tp_house": "#b8a070", "tp_door": "#c4162a", "blind": "#f4f0e6", "watch_blue": "#1a3a8a",
    "store": "#4a6a4a", "bank": "#c8c0a8", "liquor": "#6a4a7a", "precinct": "#5a6a8a", "precinct_sign": "#1a2a5a",
    "sign_white": "#f4f0e6", "police_blue_glow": "#3a8aff", "pole": "#2a2a2e", "hydrant": "#c4162a", "trash": "#5a6a5a",
    "wire": "#141414", "insulator": "#f4f4f4", "phone_blue": "#2c5bd6", "phone_post": "#6a7078", "phone_plate": "#c8ccd4",
    "wood": "#c8a060", "lemon": "#f8e04a", "post_brown": "#7a4a24", "mailbox_blue": "#2a3a6a", "maildrop_blue": "#1f4fa8",
    "alu": "#c8ccd4", "black": "#141414", "tire": "#121214", "red": "#c4162a", "pink": "#e84a9a", "cyan": "#2ad0e8",
    "gold": "#f2c230", "orange": "#ff8a1a", "fence": "#9aa0a8", "bark": "#5a3a24", "pine": "#2f5a3a", "wall": "#4a4a52",
    "fire_red": "#c4162a", "navy": "#14203f", "cream": "#f4f0e6", "iron": "#3a3a3e", "concrete": "#8a8a90",
    "white_clay": "#f8f6f0", "eye_black": "#0a0a0c", "mouth": "#3a1414",
}


# ------------------------------------------------------------------ coordinates
def G(x, y=0.0, z=0.0):
    """Game coords -> Blender location Vector."""
    if hasattr(x, "__len__"):
        x, y, z = x
    return Vector((x, -z, y))


def gscale(sx, sy, sz):
    """Game-axis scale (x, y-up, z-depth) -> Blender scale tuple."""
    return (sx, sz, sy)


def grot(rx=0.0, ry=0.0, rz=0.0):
    """three.js Euler XYZ (game axes) -> Blender rotation Matrix (3x3).
    three.js composes Rx*Ry*Rz; game Y = Blender Z, game Z = Blender -Y."""
    return (Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Z") @ Matrix.Rotation(-rz, 3, "Y"))


def _place(obj, pos, rot, parent):
    """pos/rot are LOCAL to parent when a parent is given (same as adding to a THREE.Group)."""
    if rot is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = grot(*rot).to_quaternion()
    obj.location = G(pos) if pos is not None else Vector()
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
    return obj


# ------------------------------------------------------------------ scene
def reset():
    """Empty scene, metric units, no leftovers from --factory-startup."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    random.seed(7)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    return sc


def _link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def empty(name, pos=(0, 0, 0), rot=None, parent=None, size=0.1):
    """A pivot / attach point. Exported as a plain node with this exact name."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = size
    _link(e)
    return _place(e, pos, rot, parent)


pivot = empty


def set_parent(child, parent):
    """Re-parent an existing object WITHOUT moving it in world space (clean local transform)."""
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = (parent.matrix_world.inverted() @ mw) if parent else mw
    bpy.context.view_layer.update()
    return child


def local_to(parent, x, y, z):
    """Game-space offset (x, y, z) in a parent's frame -> world game coords tuple.
    Handy for 'M(geo, mat, x, y, z, parentGroup)' calls from the JS."""
    bpy.context.view_layer.update()
    w = parent.matrix_world @ G(x, y, z)
    return (w.x, w.z, -w.y)


# ------------------------------------------------------------------ materials
def _hex(h):
    h = h.lstrip("#")
    return h.lower()


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb(h):
    h = _hex(h)
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def mat(kind="clay", hex_="#808080", rough=0.86, emit=1.5, alpha=1.0):
    """Get-or-create a material named by the convention in the module docstring."""
    hx = _hex(PAL.get(hex_, hex_))
    if kind == "glow":
        name = f"glow_{hx}_e{int(round(emit * 10))}"
    elif kind == "glass":
        name = f"glass_{hx}_a{int(round(alpha * 100))}"
    else:
        name = f"{kind}_{hx}_r{int(round(rough * 100))}"
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        outn = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], outn.inputs["Surface"])
    col = _rgb(hx)
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough if kind != "glow" else 0.4
    bsdf.inputs["Metallic"].default_value = 1.0 if kind == "metal" else 0.0
    if kind == "glow":
        bsdf.inputs["Emission Color"].default_value = (*col, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    if kind == "glass":
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            m.blend_method = "BLEND"
    m.diffuse_color = (*col, alpha)
    return m


def clay(h, rough=0.86):
    return mat("clay", h, rough)


def gloss(h, rough=0.3):
    return mat("gloss", h, rough)


def metal(h, rough=0.3):
    return mat("metal", h, rough)


def glow(h, emit=1.5):
    return mat("glow", h, emit=emit)


def glass(h, alpha=0.45):
    return mat("glass", h, alpha=alpha)


def _material(m):
    if m is None:
        return clay("#808080")
    if isinstance(m, str):
        return clay(m)
    return m


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(_material(m))
    return obj


# ------------------------------------------------------------------ primitives (game coords)
def _mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    return _link(obj)


def box(w, h, d, pos=(0, 0, 0), m=None, rot=None, parent=None, name="box", bevel=0.0, bevel_segs=3):
    """THREE.BoxGeometry(w, h, d) at game pos. bevel>0 rounds the edges (clay never has knife edges)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, v.co.z * h))
    obj = _mesh_obj(name, bm)
    assign(obj, m)
    if bevel > 0:
        bevel_obj(obj, min(bevel, 0.49 * min(w, h, d)), bevel_segs)
    return _place(obj, pos, rot, parent)


def cyl(rt, rb, h, pos=(0, 0, 0), m=None, rot=None, parent=None, name="cyl", segs=32, cap=True, bevel=0.0):
    """THREE.CylinderGeometry(radiusTop, radiusBottom, height): axis = game Y (up), centered."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=rb, radius2=rt, depth=h)
    obj = _mesh_obj(name, bm)
    assign(obj, m)
    if bevel > 0:
        bevel_obj(obj, bevel, 3)
    smooth(obj)
    return _place(obj, pos, rot, parent)


def cone(r, h, pos=(0, 0, 0), m=None, rot=None, parent=None, name="cone", segs=32):
    """THREE.ConeGeometry(r, h): tip up (+game Y), centered at half height."""
    return cyl(0.0, r, h, pos, m, rot, parent, name, segs)


def sph(r, pos=(0, 0, 0), m=None, scale=(1, 1, 1), rot=None, parent=None, name="sph", segs=32, rings=20):
    """Sphere radius r; scale=(sx, sy, sz) in GAME axes (like mesh.scale.set in the JS). Scale is baked into the mesh."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    sx, sy, sz = scale
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sz, v.co.z * sy))
    obj = _mesh_obj(name, bm)
    assign(obj, m)
    smooth(obj, 180)
    return _place(obj, pos, rot, parent)


def tor(R, r, pos=(0, 0, 0), m=None, rot=None, parent=None, name="torus", major_segs=48, minor_segs=16):
    """THREE.TorusGeometry(R, r): the ring lies in the game XY plane (axis along game Z), like three.js."""
    bm = bmesh.new()
    # build ring around Blender Y (= game -Z axis)
    for i in range(major_segs):
        a = 2 * math.pi * i / major_segs
        for j in range(minor_segs):
            b = 2 * math.pi * j / minor_segs
            x = (R + r * math.cos(b)) * math.cos(a)
            zz = (R + r * math.cos(b)) * math.sin(a)
            y = r * math.sin(b)
            bm.verts.new((x, y, zz))
    bm.verts.ensure_lookup_table()
    for i in range(major_segs):
        for j in range(minor_segs):
            a = i * minor_segs + j
            b2 = ((i + 1) % major_segs) * minor_segs + j
            c = ((i + 1) % major_segs) * minor_segs + (j + 1) % minor_segs
            d = i * minor_segs + (j + 1) % minor_segs
            bm.faces.new((bm.verts[a], bm.verts[b2], bm.verts[c], bm.verts[d]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _mesh_obj(name, bm)
    assign(obj, m)
    smooth(obj, 180)
    return _place(obj, pos, rot, parent)


def plane(w, d, pos=(0, 0, 0), m=None, rot=None, parent=None, name="plane"):
    """Flat horizontal quad w (x) by d (z), facing up."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, 0))
    obj = _mesh_obj(name, bm)
    assign(obj, m)
    return _place(obj, pos, rot, parent)


def text(s, size=0.3, depth=0.02, pos=(0, 0, 0), m=None, rot=None, parent=None, name="text",
         font="impact", align="CENTER", line_spacing=1.0, fit_width=None, bevel=0.004, resolution=4):
    """Raised clay lettering. Faces game +z (toward the street) by default; pass rot to turn it.
    size = cap height-ish in meters; fit_width shrinks the text to fit a board width.
    resolution = curve steps per glyph segment (Blender's default 12 is far too heavy for signs).
    Multi-line with \\n. Converted to a mesh (no fonts needed downstream)."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    path = FONTS.get(font, font)
    try:
        cu.font = bpy.data.fonts.load(path, check_existing=True)
    except Exception:
        pass
    cu.resolution_u = resolution
    cu.size = size
    cu.extrude = depth / 2
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.space_line = line_spacing
    obj = bpy.data.objects.new(name, cu)
    _link(obj)
    bpy.context.view_layer.update()
    if fit_width:
        wnow = obj.dimensions.x
        if wnow > fit_width > 0:
            cu.size = size * fit_width / wnow
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    tobj = bpy.data.objects.new(name, me)
    _link(tobj)
    # text lies in Blender XY facing +Z; stand it up to face game +z (Blender -Y)
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    assign(tobj, m)
    return _place(tobj, pos, rot, parent)


# ------------------------------------------------------------------ shaping
def _apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def bevel_obj(obj, width=0.02, segments=3, angle_deg=40):
    """Rounded edges, applied immediately."""
    md = obj.modifiers.new("bevel", "BEVEL")
    md.width = width
    md.segments = segments
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(angle_deg)
    md.harden_normals = False
    _apply_modifiers(obj)
    smooth(obj)
    return obj


def subdivide(obj, levels=1):
    md = obj.modifiers.new("subd", "SUBSURF")
    md.levels = levels
    md.render_levels = levels
    _apply_modifiers(obj)
    return obj


def smooth(obj, angle_deg=40):
    """Smooth shading with sharp edges above angle_deg (180 = fully smooth)."""
    me = obj.data
    if not hasattr(me, "polygons"):
        return obj
    for p in me.polygons:
        p.use_smooth = True
    if angle_deg < 180:
        try:
            me.set_sharp_from_angle(angle=math.radians(angle_deg))
        except Exception:
            pass
    return obj


def lumpy(obj, amount=0.006, freq=6.0, seed=0, subdiv=0):
    """Push vertices along their normals with smooth noise: the hand-squished clay look.
    amount in meters (keep it 0.002-0.02); freq = bumps per meter; subdiv adds vertices first."""
    if subdiv:
        subdivide(obj, subdiv)
    me = obj.data
    off = Vector((seed * 13.17, seed * 7.31, seed * 3.77))
    for v in me.vertices:
        n = noise.noise(v.co * freq + off)
        v.co += v.normal * amount * n
    me.update()
    return obj


def wobble(obj, amount=0.01, freq=1.5, seed=0):
    """Low-frequency bend so long straight things look hand made (not along normals)."""
    me = obj.data
    off = Vector((seed * 5.1, seed * 2.3, seed * 9.7))
    for v in me.vertices:
        p = v.co * freq + off
        v.co += Vector((noise.noise(p), noise.noise(p + Vector((31, 0, 0))), noise.noise(p + Vector((0, 47, 0))))) * amount
    me.update()
    return obj


def join(objs, name=None):
    """Join meshes into the first one (keeps its transform/parent). Returns the joined object."""
    objs = [o for o in objs if o and o.type == "MESH"]
    if not objs:
        return None
    base = objs[0]
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=base, selected_editable_objects=objs, object=base):
            bpy.ops.object.join()
    if name:
        base.name = name
        base.data.name = name
    return base


def apply_scale(obj):
    """Bake object scale into the mesh (keeps children where they are)."""
    if obj.type != "MESH":
        return obj
    s = obj.scale.copy()
    if s == Vector((1, 1, 1)):
        return obj
    obj.data.transform(Matrix.Diagonal((*s, 1.0)))
    for c in obj.children:
        c.matrix_parent_inverse = Matrix.Diagonal((*s, 1.0)) @ c.matrix_parent_inverse
    obj.scale = (1, 1, 1)
    return obj


def mirror_x(obj, name=None):
    """Duplicate a mesh object mirrored across x=0 of its parent (for left/right parts).
    The mirror is baked into the mesh, so the copy has a normal (positive) scale."""
    dup = obj.copy()
    dup.data = obj.data.copy()
    _link(dup)
    rot = obj.rotation_quaternion.to_matrix().to_4x4() if obj.rotation_mode == "QUATERNION" else obj.rotation_euler.to_matrix().to_4x4()
    flip = Matrix.Diagonal((-1, 1, 1, 1))
    # mesh' = R^-1 * F * R * mesh, then mirror the object's location; rotation stays the same
    dup.data.transform(rot.inverted() @ flip @ rot)
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(dup.data)
    bm.free()
    dup.location.x = -obj.location.x
    if name:
        dup.name = name
    return dup


# ------------------------------------------------------------------ export
def _clean_for_export():
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            apply_scale(o)
            for i, m in enumerate(o.data.materials):
                if m is None:
                    o.data.materials[i] = clay("#808080")


def export(asset_id, subdir="", save_blend=True):
    """Write godot/assets/models/[subdir/]asset_id.glb and blender/blend/asset_id.blend."""
    _clean_for_export()
    out_dir = os.path.join(MODELS, subdir) if subdir else MODELS
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, asset_id + ".glb")
    kw = dict(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
              export_extras=True, export_cameras=False, export_lights=False, export_animations=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("export_lights", None)
        bpy.ops.export_scene.gltf(**kw)
    if save_blend:
        os.makedirs(BLENDS, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLENDS, asset_id + ".blend"), compress=True)
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in o.evaluated_get(dg).data.polygons)
    print(f"[claykit] exported {path}  ({tris} tris, {len([o for o in bpy.context.scene.objects if o.type == 'MESH'])} meshes)")
    return path


# ------------------------------------------------------------------ preview renders
def _engine(sc):
    for e in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = e
            return e
        except TypeError:
            continue
    sc.render.engine = "BLENDER_WORKBENCH"
    return "BLENDER_WORKBENCH"


def _preview_materials():
    """Add the same triplanar thumbprint normal + mottle Godot uses, so renders match the game.
    Only call after export()."""
    nimg = bpy.data.images.load(CLAY_NORMAL, check_existing=True) if os.path.exists(CLAY_NORMAL) else None
    mimg = bpy.data.images.load(CLAY_MOTTLE, check_existing=True) if os.path.exists(CLAY_MOTTLE) else None
    if nimg:
        nimg.colorspace_settings.name = "Non-Color"
    for m in bpy.data.materials:
        if not m.use_nodes or not (m.name.startswith("clay_") or m.name.startswith("gloss_")):
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf or bsdf.inputs["Normal"].is_linked:
            continue
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (2.2, 2.2, 2.2)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        if nimg:
            it = nt.nodes.new("ShaderNodeTexImage")
            it.image = nimg
            it.projection = "BOX"
            it.projection_blend = 0.25
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.55 if m.name.startswith("clay_") else 0.18
            nt.links.new(mp.outputs["Vector"], it.inputs["Vector"])
            nt.links.new(it.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        if mimg and m.name.startswith("clay_"):
            mt = nt.nodes.new("ShaderNodeTexImage")
            mt.image = mimg
            mt.projection = "BOX"
            mt.projection_blend = 0.25
            mx = nt.nodes.new("ShaderNodeMix")
            mx.data_type = "RGBA"
            mx.blend_type = "MULTIPLY"
            mx.inputs["Factor"].default_value = 1.0
            mx.inputs["A"].default_value = bsdf.inputs["Base Color"].default_value
            nt.links.new(mp.outputs["Vector"], mt.inputs["Vector"])
            nt.links.new(mt.outputs["Color"], mx.inputs["B"])
            nt.links.new(mx.outputs["Result"], bsdf.inputs["Base Color"])


def _bounds(objs=None):
    bpy.context.view_layer.update()
    pts = []
    for o in (objs or bpy.context.scene.objects):
        if o.type in ("MESH",) and o.visible_get():
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    if not pts:
        return Vector(), 1.0
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (lo + hi) / 2, max((hi - lo).length / 2, 0.05)


def _look_at(cam, eye, target):
    cam.location = eye
    d = (target - eye).normalized()
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = d.to_track_quat("-Z", "Y")


AUTO_VIEWS = [  # game-space directions from the target toward the camera
    ("front 3/4", (0.62, 0.42, 1.0)),
    ("back 3/4", (-0.75, 0.5, -1.0)),
    ("front", (0.0, 0.12, 1.0)),
    ("side", (1.0, 0.18, 0.02)),
]


def preview(asset_id, views=None, size=(900, 700), focus=None, ground=True, samples=24):
    """Render a 2x2 contact sheet to .work/previews/<asset_id>.png and return its path.
    views: None for 4 automatic angles, or a list of up to 4 dicts in GAME coords:
        {"eye": (x, y, z), "look": (x, y, z), "lens": 35}  or  {"dir": (dx, dy, dz)} (auto distance)
    focus: list of objects to frame (default: everything). Call AFTER export()."""
    import numpy as np
    sc = bpy.context.scene
    # safe to call preview() several times: drop the previous call's stage first
    for o in [o for o in sc.objects if o.name.split(".")[0] in ("_ground", "_pv_sun", "_pv_cam")]:
        bpy.data.objects.remove(o, do_unlink=True)
    _preview_materials()
    _engine(sc)
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    try:
        sc.view_settings.view_transform = "AgX"
    except Exception:
        pass
    # sky + sun like the game (sun comes from game direction (14, 26, 12))
    w = bpy.data.worlds.new("sky")
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = next((n for n in w.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is None:
        bg = w.node_tree.nodes.new("ShaderNodeBackground")
        wo = next((n for n in w.node_tree.nodes if n.type == "OUTPUT_WORLD"), None) or w.node_tree.nodes.new("ShaderNodeOutputWorld")
        w.node_tree.links.new(bg.outputs["Background"], wo.inputs["Surface"])
    bg.inputs["Color"].default_value = (*_rgb(SKY), 1)
    bg.inputs["Strength"].default_value = 0.9
    sc.world = w
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 3.2
    sun_d.color = (1.0, 0.94, 0.85)
    sun_d.angle = math.radians(4)
    sun = bpy.data.objects.new("_pv_sun", sun_d)
    _link(sun)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = G(14, 26, 12).normalized().to_track_quat("Z", "Y")
    center, radius = _bounds(focus)
    if ground:
        gp = plane(max(radius * 8, 20), max(radius * 8, 20), (center.x, -0.002, -center.y), clay("#7d7a70", 0.95), name="_ground")
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("_pv_cam", cam_d)
    _link(cam)
    sc.camera = cam
    vlist = views or [{"dir": d, "label": l} for l, d in AUTO_VIEWS]
    os.makedirs(PREVIEWS, exist_ok=True)
    tiles = []
    for i, v in enumerate(vlist[:4]):
        cam_d.lens = v.get("lens", 50)
        if "eye" in v:
            _look_at(cam, G(v["eye"]), G(v["look"]))
        else:
            d = G(v["dir"]).normalized()
            fov = 2 * math.atan(18.0 / cam_d.lens) * min(1.0, size[1] / size[0]) * 1.0
            dist = radius / math.sin(fov / 2) * 1.08
            _look_at(cam, center + d * dist, center)
        cam_d.clip_end = 1000
        tmp = os.path.join(PREVIEWS, f"_{asset_id}_{i}.png")
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.empty(size[0] * size[1] * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        tiles.append(px.reshape(size[1], size[0], 4))
        bpy.data.images.remove(img)
        os.remove(tmp)
    while len(tiles) < 4:
        tiles.append(np.ones_like(tiles[0]))
    sheet = np.concatenate([np.concatenate([tiles[2], tiles[3]], 1), np.concatenate([tiles[0], tiles[1]], 1)], 0)
    out = bpy.data.images.new(f"sheet_{asset_id}", size[0] * 2, size[1] * 2, alpha=True)
    out.pixels.foreach_set(np.ascontiguousarray(sheet, dtype=np.float32).ravel())
    path = os.path.join(PREVIEWS, asset_id + ".png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print(f"[claykit] preview {path}")
    return path
