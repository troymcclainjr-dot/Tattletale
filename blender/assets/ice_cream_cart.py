"""Ice-cream push cart on the sidewalk: enamel body, freezer lids, chrome trim, push handle and bell, striped umbrella, menu board."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math, random
import bpy, bmesh
from mathutils import Matrix
import claykit as ck


# ---------------------------------------------------------------- local helpers (not in claykit)
def lathe(prof, pos=(0, 0, 0), m=None, rot=None, parent=None, name="lathe", segs=24, angle=50):
    """Revolve [(r, y), ...] (bottom to top) around the local game-y axis. r=0 closes a pole."""
    bm = bmesh.new()
    rings = []
    for r, y in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, y))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), y))
                          for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1 and len(b) == 1:
                break
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, angle)
    return ck._place(obj, pos, rot, parent)


def tube(pts, r, m=None, parent=None, name="tube", res=1, closed=False, curved=False, path_res=4):
    """Round tube through game-coord points (local to parent)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.use_fill_caps = not closed
    cu.resolution_u = path_res
    if curved:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(pts) - 1)
        for bp, p in zip(sp.bezier_points, pts):
            bp.co = ck.G(p)
            bp.handle_left_type = bp.handle_right_type = "AUTO"
    else:
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for pt, p in zip(sp.points, pts):
            v = ck.G(p)
            pt.co = (v.x, v.y, v.z, 1.0)
    sp.use_cyclic_u = closed
    cobj = bpy.data.objects.new(name, cu)
    ck._link(cobj)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(cobj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(cobj)
    obj = bpy.data.objects.new(name, me)
    ck._link(obj)
    ck.assign(obj, m)
    ck.smooth(obj, 60)
    return ck._place(obj, (0, 0, 0), None, parent)


def slab(poly, thick, pos=(0, 0, 0), m=None, rot=None, parent=None, name="slab"):
    """Flat shape [(x, y), ...] in the game XY plane, extruded `thick` along game z (faces +z)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -thick / 2, y)) for x, y in poly]
    bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    bmesh.ops.translate(bm, vec=(0, thick, 0), verts=[e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    return ck._place(obj, pos, rot, parent)


def label(s, size, depth, pos, m, rot=None, font="impact", fit=None, max_h=None, res=2, name="Text"):
    """Raised lettering facing +z (before rot), centered exactly on pos by its mesh bounds.
    The back faces (pressed against the cart) are dropped to save triangles."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size = size
    cu.extrude = depth / 2
    cu.resolution_u = res
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    obj = bpy.data.objects.new(name, cu)
    ck._link(obj)
    bpy.context.view_layer.update()
    k = 1.0
    if fit and obj.dimensions.x > fit:
        k = fit / obj.dimensions.x
    if max_h and obj.dimensions.y * k > max_h:
        k = max_h / obj.dimensions.y
    cu.size = size * k
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    me.transform(Matrix.Translation((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0)))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.9], context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    tobj = bpy.data.objects.new(name, me)
    ck._link(tobj)
    ck.assign(tobj, m)
    return ck._place(tobj, pos, rot, None)


def solidify(obj, thick):
    md = obj.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = 0.0
    ck._apply_modifiers(obj)
    return obj


def rounded_rect(hx, hz, rc, y, n=4):
    """Closed loop of points around a rounded rectangle (half sizes hx, hz, corner radius rc) at height y."""
    pts = []
    for cx, cz, a0 in ((hx - rc, hz - rc, 0), (-(hx - rc), hz - rc, 90), (-(hx - rc), -(hz - rc), 180), (hx - rc, -(hz - rc), 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + rc * math.cos(a), y, cz + rc * math.sin(a)))
    return pts


def bake(obj, keep_loc=False):
    """Bake the object's transform into its mesh so the exported node sits at the asset origin (or keeps only its location)."""
    bpy.context.view_layer.update()
    mw = obj.matrix_world.copy()
    t = Matrix.Translation(mw.to_translation()) if keep_loc else Matrix.Identity(4)
    obj.data.transform(t.inverted() @ mw)
    obj.parent = None
    obj.rotation_mode = "QUATERNION"
    obj.matrix_world = t
    return obj


# ---------------------------------------------------------------- build (local to the cart origin on the sidewalk)
ck.reset()
random.seed(24)
ENAMEL = ck.gloss("#f4f2ee", 0.35)
CHROME = ck.gloss("alu", 0.25)          # #c8ccd4 polished (metal_ renders too dark under the game's flat sky)
PINK = ck.clay("pink", 0.8)             # #e84a9a
WHITE = ck.clay("cream", 0.85)          # #f4f0e6
TIRE = ck.clay("black", 0.6)            # #141414
BRASS = ck.metal("#d8b040", 0.3)
WAFFLE = ck.clay("#d8a050", 0.9)
WAFFLE_LINE = ck.clay("#a8702e", 0.9)
STRAWB = ck.clay("#f08ab8", 0.85)
CHOC = ck.clay("#6a3a24", 0.85)
MINT = ck.clay("#9ad8b8", 0.85)
CHERRY = ck.gloss("#c4162a", 0.35)
STICK = ck.clay("#d8b078", 0.9)
CHALK = ck.clay("#2e3a34", 0.95)
CHALK_LINE = ck.clay("#e8e4d6", 0.95)
FRAME = ck.clay("wood", 0.85)           # #c8a060
parts = []

# ---- body 1.1 x 0.85 x 0.9 at y .62 (spans y .195..1.045), soft enamel box
body = ck.box(1.1, 0.85, 0.9, (0, 0.62, 0), ENAMEL, name="CartBody", bevel=0.06, bevel_segs=3)
ck.lumpy(body, 0.002, 4, seed=1)
parts.append(body)
# chrome rim round the top edge, bumper round the bottom, pink pinstripe, chrome corner guards
parts.append(tube(rounded_rect(0.556, 0.456, 0.065, 1.03), 0.016, CHROME, name="TopRim", closed=True))
parts.append(tube(rounded_rect(0.562, 0.462, 0.065, 0.245), 0.022, CHROME, name="Bumper", closed=True))
for y in (0.37, 0.965):
    parts.append(tube(rounded_rect(0.553, 0.453, 0.065, y), 0.01, PINK, name="Pinstripe", closed=True))
for sx in (-1, 1):
    for sz in (-1, 1):
        parts.append(tube([(sx * 0.534, 0.27, sz * 0.434), (sx * 0.534, 1.01, sz * 0.434)], 0.011, CHROME, name="CornerGuard"))

# ---- freezer: two round hatches on top, chrome rims, little U handles and hinges
for sx in (-1, 1):
    cx = sx * 0.27
    parts.append(lathe([(0, 1.04), (0.168, 1.04), (0.172, 1.05), (0.168, 1.062), (0.15, 1.07), (0.08, 1.074), (0, 1.075)],
                       (cx, 0, 0), ENAMEL, segs=24, name="Lid"))
    parts.append(ck.tor(0.172, 0.009, (cx, 1.052, 0), CHROME, rot=(math.pi / 2, 0, 0), major_segs=20, minor_segs=4, name="LidRim"))
    parts.append(tube([(cx - 0.055, 1.07, 0), (cx - 0.05, 1.1, 0), (cx + 0.05, 1.1, 0), (cx + 0.055, 1.07, 0)], 0.009, CHROME,
                      name="LidHandle", curved=True, path_res=4))
    for dz in (-0.06, 0.06):
        parts.append(ck.cyl(0.009, 0.009, 0.05, (cx + dz, 1.058, -0.178), CHROME, rot=(0, 0, math.pi / 2), segs=8, name="LidHinge"))

# ---- umbrella pole (r .04, y .9..2.2, chrome), collar at the top, tilt knuckle with a thumbscrew
parts.append(ck.cyl(0.04, 0.04, 1.3, (0, 1.55, 0), CHROME, segs=14, name="Pole"))
parts.append(lathe([(0, 1.04), (0.075, 1.04), (0.075, 1.055), (0.055, 1.075), (0.05, 1.1), (0, 1.1)], m=CHROME, segs=16, name="PoleCollar"))
parts.append(lathe([(0, 1.66), (0.05, 1.66), (0.055, 1.67), (0.055, 1.71), (0.05, 1.72), (0, 1.72)], m=CHROME, segs=14, name="PoleKnuckle"))
parts.append(ck.cyl(0.012, 0.012, 0.06, (0.075, 1.69, 0), CHROME, rot=(0, 0, math.pi / 2), segs=8, name="Thumbscrew"))
parts.append(ck.sph(0.02, (0.108, 1.69, 0), CHROME, scale=(0.6, 1, 1), segs=10, rings=6, name="ThumbscrewKnob"))

# ---- umbrella: cone r 1.1, 0.45 tall at y 2.25 -> 12 alternating pink/white gores that sag between the ribs,
# a scalloped valance, ribs and stretchers underneath, rib tips and a finial. A rib points at the vendor (+x).
APEX, RIM_Y, R_UMB, NG = 2.475, 2.025, 1.1, 12


def canopy_pt(s, t, k):
    """s: 0 apex -> 1 rim, t: 0..1 across gore k."""
    phi = 2 * math.pi * (k + t) / NG
    sag = math.sin(math.pi * t)
    rho = R_UMB * s * (1 - 0.035 * sag * s)
    y = APEX - (APEX - RIM_Y) * s - 0.022 * sag * s ** 1.3
    return (rho * math.cos(phi), y, rho * math.sin(phi))


bm = bmesh.new()
NS, NT = 5, 4
for k in range(NG):
    grid = [[bm.verts.new(ck.G(canopy_pt(max(i / NS, 0.0), j / NT, k))) for j in range(NT + 1)] for i in range(NS + 1)]
    for i in range(NS):
        for j in range(NT):
            f = bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
            f.material_index = k % 2
    # valance: hangs from the rim, scalloped bottom edge
    top = [canopy_pt(1.0, j / NT, k) for j in range(NT + 1)]
    vrows = [[bm.verts.new(ck.G(x, y - (0.045 + 0.035 * math.sin(math.pi * j / NT)) * q, z)) for j, (x, y, z) in enumerate(top)]
             for q in (0.0, 1.0)]
    for r0, r1 in zip(vrows, vrows[1:]):
        for j in range(NT):
            f = bm.faces.new((r0[j], r1[j], r1[j + 1], r0[j + 1]))
            f.material_index = k % 2
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
canopy = ck._mesh_obj("Canopy", bm)
canopy.data.materials.append(PINK)
canopy.data.materials.append(WHITE)
solidify(canopy, 0.012)
ck.smooth(canopy, 55)
parts.append(canopy)
parts.append(lathe([(0, APEX - 0.01), (0.03, APEX - 0.01), (0.022, APEX + 0.02), (0.012, APEX + 0.04), (0.035, APEX + 0.06),
                    (0.042, APEX + 0.085), (0.032, APEX + 0.11), (0, APEX + 0.12)], m=WHITE, segs=14, name="Finial"))
parts.append(lathe([(0, 2.17), (0.05, 2.17), (0.055, 2.19), (0.05, 2.21), (0, 2.21)], m=CHROME, segs=12, name="Runner"))
for k in range(NG):
    tip = canopy_pt(1.0, 0.0, k)
    mid = canopy_pt(0.55, 0.0, k)
    parts.append(tube([(0, APEX - 0.04, 0), (tip[0] * 0.985, tip[1] - 0.012, tip[2] * 0.985)], 0.007, CHROME, name="Rib", res=0))
    parts.append(tube([(0, 2.19, 0), (mid[0], mid[1] - 0.012, mid[2])], 0.006, CHROME, name="Stretcher", res=0))
    parts.append(ck.sph(0.016, (tip[0], tip[1] - 0.006, tip[2]), WHITE, segs=6, rings=4, name="RibTip"))

# ---- wheels: four black tires with chrome hubcaps, axles along z so it rolls toward the push handle (+x)
for sx in (-1, 1):
    for sz in (-1, 1):
        rot = (math.pi / 2, 0, 0) if sz > 0 else (-math.pi / 2, 0, 0)
        parts.append(lathe([(0.065, -0.03), (0.104, -0.03), (0.117, -0.021), (0.12, 0.0), (0.117, 0.021), (0.104, 0.03), (0.065, 0.03)],
                           (sx * 0.4, 0.12, sz * 0.35), TIRE, rot=rot, segs=16, name="Tire", angle=60))
        parts.append(lathe([(0, 0.026), (0.066, 0.026), (0.062, 0.034), (0.045, 0.042), (0.02, 0.046), (0, 0.047)],
                           (sx * 0.4, 0.12, sz * 0.35), CHROME, rot=rot, segs=12, name="Hubcap"))
    parts.append(ck.cyl(0.014, 0.014, 0.68, (sx * 0.4, 0.12, 0), CHROME, rot=(math.pi / 2, 0, 0), segs=8, name="Axle"))
    for sz in (-1, 1):
        parts.append(ck.box(0.05, 0.1, 0.022, (sx * 0.4, 0.17, sz * 0.3), CHROME, name="AxleBracket", bevel=0.006, bevel_segs=1))

# ---- push handle on the vendor's side (+x), black grip and a brass bell
handle = [(0.53, 0.84, -0.36), (0.64, 0.88, -0.36), (0.685, 0.905, -0.33), (0.685, 0.905, 0.33), (0.64, 0.88, 0.36), (0.53, 0.84, 0.36)]
parts.append(tube(handle, 0.017, CHROME, name="PushHandle", curved=True, path_res=3))
parts.append(ck.cyl(0.025, 0.025, 0.36, (0.685, 0.905, -0.05), TIRE, rot=(math.pi / 2, 0, 0), segs=12, name="Grip", bevel=0.008))
parts.append(lathe([(0, 0.0), (0.03, 0.0), (0.03, 0.008), (0.026, 0.022), (0.016, 0.032), (0, 0.035)],
                   (0.685, 0.917, 0.22), BRASS, segs=16, name="Bell"))
parts.append(ck.box(0.03, 0.006, 0.01, (0.705, 0.93, 0.22), BRASS, rot=(0, 0, 0.3), name="BellLever"))

# ---- "ICE CREAM" in pink on the -x face (the line of customers is to the west)
parts.append(label("ICE CREAM", 0.2, 0.012, (-0.555, 0.75, 0), PINK, rot=(0, -math.pi / 2, 0), font=r"C:\Windows\Fonts\COOPBL.TTF",
                   fit=0.74, max_h=0.19, name="IceCreamText"))


# ---- painted (raised clay) decorations on both long sides: a cone with two scoops and a cherry, a dipped popsicle
def decorations(sz):
    zf = sz * 0.45               # face plane
    rot = (0, 0, 0) if sz > 0 else (0, math.pi, 0)
    xs = -1 if sz > 0 else 1     # cone on the viewer's left on both sides

    def P(x, y, dz):
        return (x, y, zf + sz * dz)
    cx = xs * 0.24
    cone = [(-0.1, 0.0), (0.1, 0.0), (0.016, -0.27), (-0.016, -0.27)]
    parts.append(slab(cone, 0.008, P(cx, 0.64, 0.003), WAFFLE, rot=rot, name="Cone"))
    for k in range(3):
        for sgn in (-1, 1):
            parts.append(ck.box(0.006, 0.2, 0.004, P(cx + sgn * (-0.045 + 0.045 * k) * 0.8, 0.54, 0.0085), WAFFLE_LINE,
                                rot=(0, rot[1], sgn * 0.5), name="WaffleLine"))
    parts.append(ck.sph(0.1, P(cx, 0.705, 0.004), STRAWB, scale=(1.0, 0.92, 0.14), segs=14, rings=7, name="Scoop"))
    parts.append(ck.sph(0.082, P(cx + xs * 0.01, 0.83, 0.004), CHOC, scale=(1.0, 0.95, 0.15), segs=14, rings=7, name="Scoop"))
    parts.append(ck.sph(0.026, P(cx + xs * 0.02, 0.925, 0.006), CHERRY, scale=(1, 1, 0.6), segs=10, rings=6, name="Cherry"))
    px = -cx
    parts.append(ck.box(0.15, 0.27, 0.014, P(px, 0.66, 0.004), MINT, name="Popsicle", bevel=0.06, bevel_segs=2))
    parts.append(ck.box(0.154, 0.1, 0.018, P(px, 0.765, 0.004), CHOC, name="PopsicleDip", bevel=0.05, bevel_segs=2))
    parts.append(ck.box(0.035, 0.12, 0.008, P(px, 0.47, 0.002), STICK, name="PopsicleStick", bevel=0.012, bevel_segs=2))


decorations(1)
decorations(-1)

# ---- little menu board clamped to the pole, facing the line (-x) and angled a bit toward the street
MB_Y, MB_ROT = 1.45, (0, -1.134, 0)
fx, fz = -math.cos(math.radians(25)), math.sin(math.radians(25))


def MB(u, v, w):
    """Board-local (u to the reader's right, v up, w out of the face) -> cart coords."""
    ux, uz = math.sin(math.radians(25)), math.cos(math.radians(25))   # reader's right
    return (fx * (0.07 + w) + ux * u, MB_Y + v, fz * (0.07 + w) + uz * u)


parts.append(ck.box(0.3, 0.24, 0.016, MB(0, 0, 0), FRAME, rot=MB_ROT, name="MenuFrame", bevel=0.008, bevel_segs=2))
parts.append(ck.box(0.26, 0.2, 0.01, MB(0, 0, 0.007), CHALK, rot=MB_ROT, name="MenuChalk", bevel=0.004, bevel_segs=1))
parts.append(ck.box(0.16, 0.016, 0.004, MB(0, 0.07, 0.013), PINK, rot=MB_ROT, name="MenuHeading", bevel=0.002, bevel_segs=1))
for row, (col, y) in enumerate(((STRAWB, 0.025), (CHOC, -0.022), (MINT, -0.069))):
    parts.append(ck.sph(0.017, MB(-0.09, y, 0.012), col, scale=(1, 1, 0.5), rot=MB_ROT, segs=10, rings=5, name="MenuIcon"))
    parts.append(ck.box(0.11 - 0.02 * (row % 2), 0.009, 0.003, MB(0.0, y + 0.006, 0.0125), CHALK_LINE, rot=MB_ROT, name="MenuLine"))
    parts.append(ck.box(0.035, 0.009, 0.003, MB(0.085, y + 0.006, 0.0125), CHALK_LINE, rot=MB_ROT, name="MenuPrice"))
for y in (MB_Y - 0.07, MB_Y + 0.07):
    parts.append(ck.tor(0.043, 0.007, (0, y, 0), CHROME, rot=(math.pi / 2, 0, 0), major_segs=12, minor_segs=4, name="MenuClamp"))
    parts.append(ck.box(0.02, 0.02, 0.06, MB(0, y - MB_Y, -0.035), CHROME, rot=MB_ROT, name="MenuBracket"))

cart = bake(ck.join(parts, "IceCreamCart"))
print("[ice_cream_cart] objects:", sorted(o.name for o in bpy.context.scene.objects))
ck.export("ice_cream_cart")

# ---- previews (sidewalk slab + a stand-in vendor where the game places him: local (+0.95, 0, 0) facing -x)
ck.box(4.0, 0.16, 3.0, (0, -0.08, 0), ck.clay("sidewalk", 0.95), name="_sidewalk")
ck.preview("ice_cream_cart", views=[
    {"eye": (-2.9, 2.3, 3.3), "look": (0, 1.15, 0), "lens": 32},
    {"eye": (2.9, 2.6, -3.0), "look": (0, 1.15, 0), "lens": 32},
    {"eye": (0.2, 1.5, 4.0), "look": (0, 1.15, 0), "lens": 32},
    {"eye": (-2.0, 1.35, 0.9), "look": (-0.3, 1.05, 0), "lens": 40},
])
H = 1.78
SK, TOP, PANTS = ck.clay("#c48e64"), ck.clay("#f4f0e6"), ck.clay("#3a3a40")


def V(px, py, pz):
    """Vendor-local -> cart coords (he faces -x)."""
    return (0.95 - pz, py, px)


for s in (-1, 1):
    ck.cyl(0.06 * H, 0.055 * H, 0.44 * H, V(s * 0.085 * H, 0.25 * H, 0), PANTS, name="_leg")
    sh = V(s * 0.185 * H, 0.78 * H, 0)
    hd = V(s * 0.185 * H, 0.78 * H - 0.3 * H * math.cos(1.1), 0.3 * H * math.sin(1.1))
    tube([sh, hd], 0.042 * H, TOP, name="_arm")
    ck.sph(0.045 * H, hd, SK, name="_hand")
ck.sph(0.135 * H, V(0, 0.48 * H, 0), PANTS, scale=(0.78, 0.55, 1.05), name="_pelvis")
ck.cyl(0.15 * H, 0.13 * H, 0.32 * H, V(0, 0.64 * H, 0), TOP, name="_torso").scale = (0.74, 1, 1)
ck.sph(0.15 * H, V(0, 0.8 * H, 0), TOP, scale=(0.74, 0.42, 1), name="_shoulders")
ck.sph(0.115 * H, V(0, 0.995 * H, 0), SK, name="_head")
ck.cyl(0.12, 0.12, 0.12, V(0, 0.995 * H + 0.95 * 0.115 * H, 0), TOP, name="_hat")
ck.preview("ice_cream_cart_vendor", views=[
    {"eye": (-2.9, 2.3, 3.3), "look": (0.2, 1.15, 0), "lens": 30},
    {"eye": (2.9, 2.6, -3.0), "look": (0.2, 1.15, 0), "lens": 30},
    {"eye": (0.4, 1.6, 4.0), "look": (0.4, 1.2, 0), "lens": 32},
    {"eye": (0.75, 2.6, 2.2), "look": (0.75, 1.6, 0), "lens": 35},
])
