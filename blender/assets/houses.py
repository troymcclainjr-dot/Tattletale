"""Builds the 8 row houses and 2-Pack's house in world space (houses.glb), one object per house."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

WALL, EMB = -7.0, -7.012   # front wall plane; back face of anything stuck on it (hides the wall's lumps)
CAP = 0.53                 # cap height / font size for Impact and Arial Black

ck.reset()
random.seed(911)

# ---------------------------------------------------------------- materials
M_ROOF = ck.clay("roof_trim")
M_TAR = ck.clay("#3e3a36", 0.95)
M_GLASS = ck.gloss("window", 0.15)
M_PLY = ck.clay("board")
M_PLANK = ck.clay("board_light")
M_DOOR = ck.clay("door")
M_STOOP = ck.clay("curb")
M_CREAM = ck.clay("#e4dcc8")
M_WHITE = ck.clay("#f2eee2")
M_STONE = ck.clay("#b6ae9e")
M_CONC = ck.clay("#9a968c", 0.92)
M_MORTAR = ck.clay("#6e665c", 0.95)
M_BRASS = ck.metal("#c8a040", 0.35)
M_IRON = ck.metal("#2a2a2e", 0.55)
M_NAIL = ck.metal("#4e4e52", 0.45)
M_GALV = ck.metal("#8e9296", 0.5)
M_RUST = ck.clay("#7a4a2e", 0.9)
M_TERRA = ck.clay("#a8583a")
M_SOIL = ck.clay("#3a2a1e", 0.95)
M_DARK = ck.clay("#141414")
M_AC = ck.clay("#d4cebe")
M_ACG = ck.clay("#8a8882")
M_GLOBE = ck.gloss("#efe6cf", 0.3)
M_LAMP = ck.glow("#ffd890", 1.0)
M_DISH = ck.clay("#d8d6d0")
M_GLINT = ck.glass("#ffffff", 0.14)
BRICKS = [ck.clay(c) for c in ("#7a3e2e", "#8a4632", "#6c3628", "#82402c")]
LEAVES = [ck.clay(c) for c in ("#4a7a3a", "#5a8a3e", "#3e6a34")]
DEAD = [ck.clay(c) for c in ("#7a6a4a", "#6a5a3c")]


# ---------------------------------------------------------------- helpers
class House:
    def __init__(s, k, name, x, w, h, col, wins, **st):
        s.k, s.name, s.x, s.w, s.h, s.col, s.wins, s.st = k, name, x, w, h, col, wins, st
        s.wall = ck.clay(col)
        s.trim = ck.clay(st.get("trim", "#e4dcc8"))
        s.sash_m = ck.clay(st.get("sash", st.get("trim", "#e4dcc8")))
        s.sill = st.get("sill", M_STONE)
        s.ct, s.cd = st.get("ct", 0.09), st.get("cd", 0.075)   # casing width, casing protrusion
        s.door_x = x + 0.1
        s.face = WALL + (0.048 if st.get("surface") == "siding" else 0.0)   # outer face of the wall cladding
        s.parts, s.empties = [], []

    def add(s, o):
        s.parts.append(o)
        return o


def wallbox(H, w, h, front, x, y, m, bevel=0.012, segs=2, rot=None, back=EMB, name="part"):
    """Box stuck on the front wall: back face at `back`, front face `front` m in front of the wall."""
    zf = WALL + front
    return H.add(ck.box(w, h, zf - back, (x, y, (zf + back) / 2), m, rot=rot, bevel=bevel, bevel_segs=segs, name=name))


def bm_obj(bm, name, m, pos=(0, 0, 0), rot=None, smooth=40):
    """bmesh built in game-local coords (x, y up, z toward the street) -> placed object."""
    for v in bm.verts:
        v.co = Vector((v.co.x, -v.co.z, v.co.y))
    o = ck._mesh_obj(name, bm)
    ck.assign(o, m)
    ck.smooth(o, smooth)
    return ck._place(o, pos, rot, None)


def prism(pts, depth, pos, m, rot=None, axis="z", bevel=0.0, segs=2, name="prism", parent=None):
    """Extrude a 2D outline by depth (centered). axis z: pts are (x, y); axis x: pts are (z, y)."""
    bm = bmesh.new()

    def g(a, b, c):
        return (a, b, c) if axis == "z" else (c, b, a)
    f = bm.faces.new([bm.verts.new(g(a, b, -depth / 2)) for a, b in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)], vec=Vector(g(0, 0, depth)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co = Vector((v.co.x, -v.co.z, v.co.y))
    o = ck._mesh_obj(name, bm)
    ck.assign(o, m)
    if bevel > 0:
        ck.bevel_obj(o, bevel, segs)
    else:
        ck.smooth(o)
    return ck._place(o, pos, rot, parent)


def rod(p0, p1, r, m, segs=8, r0=None, name="rod", parent=None):
    """Cylinder from p0 to p1 (r0 = radius at p0)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = ck.cyl(r, r if r0 is None else r0, d.length, (0, 0, 0), m, segs=segs, name=name)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(ck.G(d).normalized())
    o.location = ck.G((p0 + p1) / 2)
    if parent is not None:
        o.parent = parent
        o.matrix_parent_inverse = Matrix.Identity(4)
    return o


def text_bm(s, size, depth, font="impact", bevel=0.0, offset=0.0, res=3, spacing=1.0):
    """Lettering as a bmesh in game-local coords (faces +z, depth centered). Low curve resolution."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size = size
    cu.extrude = max(depth / 2 - bevel, 0.0005)
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.offset = offset
    cu.resolution_u = res
    cu.space_character = spacing
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    o = bpy.data.objects.new("txt", cu)
    ck._link(o)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(o)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm


def label(H, s, cap, pos, m, depth=0.012, font="impact", fit=None, bevel=0.002, spacing=1.0, name="Text"):
    """Raised lettering centered on its ink box at pos (pos z = middle of its thickness)."""
    bm = text_bm(s, cap / CAP, depth, font, bevel=bevel, spacing=spacing)
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    w = max(xs) - min(xs)
    ox, oy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    k = fit / w if fit and w > fit else 1.0
    for v in bm.verts:
        v.co.x, v.co.y = (v.co.x - ox) * k, (v.co.y - oy) * k
    return H.add(bm_obj(bm, f"{H.name}_{name}", m, pos))


def islands(bm):
    """Connected vertex groups, sorted left to right."""
    bm.verts.index_update()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, stack = [], [v]
        seen.add(v.index)
        while stack:
            a = stack.pop()
            comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        out.append(comp)
    out.sort(key=lambda c: sum(v.co.x for v in c) / len(c))
    return out


def jaggy(w, h, rng, chip=0.02, n=3):
    """Rectangle outline with rough, splintered ends (centered)."""
    pts = [(-w / 2 + rng.uniform(0, chip), -h / 2), (w / 2 - rng.uniform(0, chip), -h / 2)]
    for i in range(1, n):
        pts.append((w / 2 + rng.uniform(-chip * 1.8, chip * 0.6), -h / 2 + h * i / n))
    pts += [(w / 2 - rng.uniform(0, chip), h / 2), (-w / 2 + rng.uniform(0, chip), h / 2)]
    for i in range(n - 1, 0, -1):
        pts.append((-w / 2 + rng.uniform(-chip * 0.6, chip * 1.8), -h / 2 + h * i / n))
    return pts


def inside(px, py, poly):
    c = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[i - 1]
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            c = not c
    return c


def jit(a):
    return random.uniform(-a, a)


# ---------------------------------------------------------------- the shell
def block(H):
    """Main block w x h x 7 (the camera/binocular occluder): soft edges, hand-smoothed walls."""
    w, h, d = H.w, H.h, 7.0
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, v.co.z * h))
    for axis, L in ((0, w), (1, d), (2, h)):
        n = max(1, round(L / 0.4))
        for i in range(1, n):
            co, no = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
            co[axis], no[axis] = -L / 2 + L * i / n, 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=co, plane_no=no)
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.9], context="FACES")
    o = ck._mesh_obj(H.name, bm)
    ck.assign(o, H.wall)
    ck.bevel_obj(o, 0.07, 3)
    ck.lumpy(o, H.st.get("lump", 0.006), 0.7, seed=H.k + 1)
    ck.smooth(o)
    return ck._place(o, (H.x, h / 2, -10.5), None, None)


def parapet(H, height=0.32, inset=0.24, depth=0.2):
    """The JS roof trim as a parapet ring around a recessed tar roof (same outside size)."""
    W, D = H.w + 0.2, 7.2
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * W, v.co.y * D, v.co.z * height))
    bm.normal_update()
    top = next(f for f in bm.faces if f.normal.z > 0.9)
    bmesh.ops.inset_region(bm, faces=[top], thickness=inset, depth=0.0)
    ext = bmesh.ops.extrude_face_region(bm, geom=[top])
    nf = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMFace)]
    bmesh.ops.translate(bm, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)], vec=Vector((0, 0, -depth)))
    if top.is_valid:
        bmesh.ops.delete(bm, geom=[top], context="FACES")
    for f in nf:
        f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = ck._mesh_obj(H.name + "_Parapet", bm)
    ck.assign(o, M_ROOF)
    o.data.materials.append(M_TAR)
    ck.bevel_obj(o, 0.03, 2)
    H.add(ck._place(o, (H.x, H.h - 0.02 + height / 2, -10.5), None, None))
    # coping on the side walls
    for s in (-1, 1):
        H.add(ck.box(0.3, 0.05, 7.1, (H.x + s * (W / 2 - 0.12), H.h + 0.32, -10.5), M_ROOF, bevel=0.02, bevel_segs=1))


def cornice(H, kind):
    x, w, h = H.x, H.w, H.h
    deep = kind == "bracket"
    # cap slab over the front parapet (the top edge projects the most)
    H.add(ck.box(w + (0.36 if deep else 0.32), 0.07, 0.475 if deep else 0.36, (x, h + 0.33, -6.9625 if deep else -7.03),
                 M_ROOF, bevel=0.025, bevel_segs=2))
    # bed molding tucked under the parapet overhang
    H.add(ck.box(w + 0.1, 0.11, 0.12, (x, h - 0.05, -6.962), M_ROOF, bevel=0.045, bevel_segs=3))
    if kind == "dentil":
        wallbox(H, w + 0.02, 0.24, 0.045, x, h - 0.2, M_ROOF, bevel=0.012)
        n = int((w - 0.1) / 0.16)
        for i in range(n):
            wallbox(H, 0.075, 0.09, 0.085, x - (n - 1) * 0.08 + i * 0.16, h - 0.16, M_ROOF, bevel=0.012, segs=1)
    elif kind == "bracket":
        # corona under the cap, frieze band with panels, scroll brackets holding it up
        H.add(ck.box(w + 0.3, 0.2, 0.27, (x, h + 0.2, -6.875), M_ROOF, bevel=0.03, bevel_segs=2))
        fr = ck.clay(H.st.get("frieze", "#2a2624"))
        wallbox(H, w + 0.02, 0.5, 0.04, x, h - 0.27, fr, bevel=0.012)
        n = H.st.get("brackets", 5)
        bm_ = ck.clay(H.st.get("bracket_col", "#2a2624"))
        xs = [x - w / 2 + 0.3 + (w - 0.6) * i / (n - 1) for i in range(n)]
        prof = [(0, 0), (0.262, 0), (0.262, -0.07), (0.2, -0.11), (0.15, -0.19), (0.125, -0.3), (0.12, -0.4),
                (0.1, -0.48), (0.06, -0.54), (0, -0.56)]
        for bx in xs:
            H.add(prism(prof, 0.13, (bx, h + 0.1, EMB), bm_, axis="x", bevel=0.016))
            H.add(ck.sph(0.042, (bx, h - 0.48, -6.976), bm_, segs=10, rings=6))    # pendant drop
        for a, b in zip(xs, xs[1:]):
            wallbox(H, b - a - 0.34, 0.24, 0.058, (a + b) / 2, h - 0.25, bm_, bevel=0.014)
    elif kind == "plain":
        wallbox(H, w + 0.02, 0.16, 0.035, x, h - 0.16, M_ROOF, bevel=0.01)


def courses(H, base=True, belt=3.12):
    """Base course (water table) and belt course between the floors."""
    x0 = H.x - H.w / 2 - 0.015
    x1 = H.x + H.w / 2 + 0.015 - H.st.get("trim_right", 0.0)
    if base:
        wallbox(H, x1 - x0, 0.5, 0.045, (x0 + x1) / 2, 0.25, H.st.get("base_m", M_CONC), bevel=0.014)
    if belt:
        wallbox(H, x1 - x0 + 0.03, 0.14, 0.07, (x0 + x1) / 2, belt, ck.clay(H.st.get("belt", "#b6ae9e")), bevel=0.02)


def siding(H, y0, y1, bh=0.205, tilt=0.11, th=0.026):
    """Lap siding boards across the facade, bottom edges kicked out (deep shadow lines), slightly irregular."""
    cb = 0.13
    x0, x1 = H.x - H.w / 2 + cb - 0.02, H.x + H.w / 2 - cb + 0.02
    if H.st.get("wide_left"):
        x0 = H.x - H.w / 2 + 0.4
    zc = -7.004 + (bh / 2) * math.sin(tilt) + th / 2     # top back edge just inside the wall
    n = int((y1 - y0) / bh)
    for i in range(n):
        yc = y0 + (i + 0.5) * bh
        b = ck.box(x1 - x0, bh + 0.014, th, ((x0 + x1) / 2 + jit(0.004), yc, zc + jit(0.0015)), H.wall,
                   rot=(-tilt, 0, jit(0.0025)), bevel=0.008, bevel_segs=1, name="board")
        H.add(b)


def corner_boards(H, y0, y1, m):
    for s in (-1, 1):
        if s < 0 and H.st.get("wide_left"):
            # wide board also hides the seam where this house overlaps its neighbour
            wallbox(H, 0.52, y1 - y0, 0.058, H.x - H.w / 2 + 0.17 - 0.06, (y0 + y1) / 2, m, bevel=0.016)
        else:
            wallbox(H, 0.15, y1 - y0, 0.055, H.x + s * (H.w / 2 - 0.07), (y0 + y1) / 2, m, bevel=0.016)


def rustication(H, y0, y1, m, bh=0.3):
    """Rusticated ground floor: courses of big stone blocks with deep joints, staggered."""
    n = max(1, round((y1 - y0) / bh))
    bh = (y1 - y0) / n
    x0, x1 = H.x - H.w / 2 - 0.006, H.x + H.w / 2 + 0.006
    rng = random.Random(H.k * 31)
    for i in range(n):
        yc = y0 + (i + 0.5) * bh
        x = x0 - (rng.uniform(0.3, 0.6) if i % 2 else 0.0)
        while x < x1:
            bw = rng.uniform(0.75, 1.15)
            a, b = max(x, x0), min(x + bw, x1)
            if b - a > 0.12:
                wallbox(H, b - a - 0.04, bh - 0.04, 0.032 + rng.uniform(-0.004, 0.004), (a + b) / 2, yc, m,
                        bevel=0.012, segs=2, rot=(0, 0, rng.uniform(-0.004, 0.004)))
            x += bw


def quoins(H, y0, y1, m):
    for s in (-1, 1):
        y, i = y0, 0
        while y + 0.32 <= y1:
            wq = 0.48 if i % 2 == 0 else 0.32
            xq = H.x + s * (H.w / 2 - wq / 2 + 0.006)
            wallbox(H, wq, 0.28, 0.042, xq, y + 0.16, m, bevel=0.014)
            H.add(ck.box(0.042, 0.28, wq * 0.75, (H.x + s * (H.w / 2 + 0.008), y + 0.16, -7.0 - wq * 0.375 + 0.03), m,
                         bevel=0.014, bevel_segs=2))
            y += 0.33
            i += 1


def pilasters(H, y0, y1, m):
    for s in (-1, 1):
        wallbox(H, 0.32, y1 - y0, 0.05, H.x + s * (H.w / 2 - 0.16), (y0 + y1) / 2, m, bevel=0.016)
        wallbox(H, 0.4, 0.12, 0.08, H.x + s * (H.w / 2 - 0.16), y1 - 0.06, m, bevel=0.02)   # capital


def brick_patch(H, dx, cy, rx, ry, seed):
    """Plaster fallen off: a mortar bed with bricks, ragged outline."""
    rng = random.Random(seed)
    poly = []
    for i in range(14):
        a = 2 * math.pi * i / 14
        r = 1 + rng.uniform(-0.28, 0.18)
        poly.append((rx * r * math.cos(a), ry * r * math.sin(a)))
    cx = H.x + dx
    H.add(prism(poly, 0.022, (cx, cy, EMB + 0.011), M_MORTAR, bevel=0.006, segs=1))
    # crumbled plaster lumps along the edge
    for i in range(0, 14, 2):
        px, py = poly[i]
        H.add(ck.sph(rng.uniform(0.03, 0.05), (cx + px * 1.02, cy + py * 1.02, -6.996), H.wall, scale=(1.4, 0.8, 0.35),
                     segs=8, rings=5))
    inner = [(px * 0.86, py * 0.86) for px, py in poly]
    row = 0
    y = -ry * 1.2
    while y < ry * 1.2:
        off = 0.125 if row % 2 else 0.0
        x = -rx * 1.3 + off
        while x < rx * 1.3:
            if inside(x, y, inner) and rng.random() > 0.07:
                H.add(ck.box(0.22 + rng.uniform(-0.01, 0.01), 0.066, 0.026,
                             (cx + x + rng.uniform(-0.006, 0.006), cy + y, -6.995 + 0.013 + rng.uniform(-0.003, 0.003)),
                             rng.choice(BRICKS), rot=(0, 0, rng.uniform(-0.03, 0.03)), bevel=0.009, bevel_segs=1, name="brick"))
            x += 0.25
        y += 0.085
        row += 1


# ---------------------------------------------------------------- openings
def window(H, cx, cy, boarded, deco=None, ww=1.1, wh=1.2, cd=None, seed=0, sill=True):
    t, cd = H.ct, (cd or H.cd)
    rng = random.Random(seed)
    if boarded:
        boarded_fill(H, cx, cy, ww, wh, rng)
    else:
        H.add(ck.box(ww + 0.02, wh + 0.02, 0.06, (cx, cy, -6.98), M_GLASS, bevel=0.008, bevel_segs=1, name="glass"))
        if deco == "ac":
            window_ac(H, cx, cy, ww, wh)
        sash(H, cx, cy, ww, wh, deco)
        if deco in ("shade", "torn", "curtains", "lace", "plant", "shade_plant"):
            interior(H, cx, cy, ww, wh, deco, rng)
        if deco == "bars":
            bars(H, cx, cy, ww, wh)
        # two soft glints so the dark glass reads as glass (on the pane a shade doesn't cover)
        yc = cy + (-0.3 if deco in ("shade", "shade_plant", "torn") else 0.3)
        for dx, L, gw in ((-0.22, 0.34, 0.055), (-0.09, 0.2, 0.03)):
            H.add(ck.box(gw, L, 0.003, (cx + dx, yc + rng.uniform(-0.02, 0.02), -6.9405), M_GLINT, rot=(0, 0, -0.65)))
    lean = 0.0 if H.st.get("tidy") else rng.uniform(-0.006, 0.006)
    for s in (-1, 1):
        wallbox(H, t, wh + 2 * t, cd, cx + s * (ww + t) / 2, cy, H.trim, bevel=0.016, rot=(0, 0, lean))
    for s in (-1, 1):
        wallbox(H, ww + 0.004, t, cd - 0.006, cx, cy + s * (wh + t) / 2, H.trim, bevel=0.016, rot=(0, 0, lean))
    if sill:
        sw = ww + 2 * t + 0.16
        H.add(ck.box(sw, 0.075, 0.19, (cx, cy - wh / 2 - t - 0.03, EMB + 0.095), H.sill, rot=(0.07, 0, lean * 2),
                     bevel=0.022, bevel_segs=2, name="sill"))
    lintel(H, cx, cy + wh / 2 + t, ww + 2 * t, rng)


def lintel(H, cx, y0, w, rng):
    kind = H.st.get("lintel", "stone")
    if kind == "stone":
        wallbox(H, w + 0.1, 0.17, 0.075, cx, y0 + 0.08, H.sill, bevel=0.02)
    elif kind == "keystone":
        wallbox(H, w + 0.1, 0.17, 0.07, cx, y0 + 0.08, H.sill, bevel=0.02)
        H.add(prism([(-0.075, -0.05), (0.075, -0.05), (0.105, 0.22), (-0.105, 0.22)], 0.1, (cx, y0, EMB + 0.05),
                    H.sill, bevel=0.015))
    elif kind == "cap":
        wallbox(H, w, 0.1, H.cd - 0.012, cx, y0 + 0.045, H.trim, bevel=0.014)
        wallbox(H, w + 0.09, 0.045, H.cd + 0.03, cx, y0 + 0.115, H.trim, bevel=0.014)
    elif kind == "soldier":
        n = max(3, round((w + 0.08) / 0.09))
        bw = (w + 0.08) / n
        for i in range(n):
            wallbox(H, bw - 0.014, 0.21 + rng.uniform(-0.012, 0.012), 0.036 + rng.uniform(-0.005, 0.005),
                    cx - (w + 0.08) / 2 + bw * (i + 0.5), y0 + 0.11, rng.choice(BRICKS), bevel=0.008, segs=1)


def sash(H, cx, cy, ww, wh, deco):
    zb, zf = -6.956, -6.934
    d, zc = zf - zb, (zb + zf) / 2
    m = H.sash_m
    for s in (-1, 1):
        H.add(ck.box(0.045, wh, d, (cx + s * (ww / 2 - 0.0225), cy, zc), m, bevel=0.006, bevel_segs=1))
    H.add(ck.box(ww, 0.05, d, (cx, cy + wh / 2 - 0.025, zc), m, bevel=0.006, bevel_segs=1))
    H.add(ck.box(ww, 0.06, d, (cx, cy - wh / 2 + 0.03, zc), m, bevel=0.006, bevel_segs=1))
    rail_y = cy - wh / 2 + 0.47 if deco == "ac" else cy
    H.add(ck.box(ww, 0.06, d + 0.008, (cx, rail_y, zc + 0.004), m, bevel=0.006, bevel_segs=1))
    if H.st.get("muntins"):
        for yy, hh in ((cy + wh / 4, wh / 2), (cy - wh / 4, wh / 2)):
            if deco == "ac" and yy < cy:
                continue
            H.add(ck.box(0.03, hh, d - 0.004, (cx, yy, zc), m, bevel=0.005, bevel_segs=1))


def interior(H, cx, cy, ww, wh, deco, rng):
    """What you see behind the glass: shades, curtains, a plant."""
    zc, d = -6.947, 0.009
    if deco in ("shade", "shade_plant", "torn"):
        f = rng.uniform(0.3, 0.55)
        sh = (wh - 0.08) * f
        top = cy + wh / 2 - 0.05
        mcol = ck.clay(H.st.get("shade_col", "#e8dcc0"))
        if deco == "torn":
            # crooked roller shade, one side sagging, ripped up from the hem
            a = (ww - 0.1) / 2
            dl, dr = sh * rng.uniform(1.3, 1.6), sh * rng.uniform(0.6, 0.8)
            if rng.random() < 0.5:
                dl, dr = dr, dl

            def hem(x):
                return -(dr + (dl - dr) * (a - x) / (2 * a))
            tx = rng.uniform(-0.2, 0.2)
            pts = [(-a, 0), (a, 0), (a, hem(a)), (tx + 0.08, hem(tx + 0.08)), (tx + 0.02, hem(tx) + 0.24),
                   (tx - 0.01, hem(tx) + 0.05), (tx - 0.06, hem(tx - 0.06) - 0.03), (-a, hem(-a))]
            H.add(prism(pts, d, (cx, top, zc), mcol, bevel=0.002, segs=1))
            H.add(ck.box(ww - 0.06, 0.04, d + 0.012, (cx, top + 0.005, zc + 0.003), M_CREAM, bevel=0.006, bevel_segs=1))
        else:
            H.add(ck.box(ww - 0.09, sh, d, (cx, top - sh / 2, zc), mcol, bevel=0.003, bevel_segs=1))
            H.add(ck.box(ww - 0.08, 0.025, d + 0.006, (cx, top - sh, zc), mcol, bevel=0.005, bevel_segs=1))
            H.add(ck.tor(0.022, 0.005, (cx, top - sh - 0.035, zc + 0.004), M_CREAM, major_segs=10, minor_segs=4))
    if deco in ("curtains", "lace"):
        mcol = ck.clay(H.st.get("curtain", "#a84a3a")) if deco == "curtains" else ck.glass("#f0ebe0", 0.55)
        top = cy + wh / 2 - 0.05
        for s in (-1, 1):
            # tied-back drape: full at the top, pinched at the tie, flaring at the bottom
            pw = 0.3
            pts = [(0, 0), (pw, 0), (pw * 0.95, -0.15), (0.13, -wh * 0.45), (0.2, -wh * 0.75), (0.24, -wh + 0.12), (0, -wh + 0.12)]
            if s > 0:
                pts = [(-px, py) for px, py in reversed(pts)]
            H.add(prism(pts, d, (cx - s * (ww / 2 - 0.045), top, zc), mcol, bevel=0.003, segs=1))
        H.add(rod((cx - ww / 2, top + 0.01, zc + 0.006), (cx + ww / 2, top + 0.01, zc + 0.006), 0.012, M_BRASS, segs=6))
    if deco in ("plant", "shade_plant"):
        bx = cx + rng.uniform(-0.25, 0.25)
        yb = cy - wh / 2 + 0.06
        H.add(ck.cyl(0.075, 0.055, 0.14, (bx, yb + 0.07, zc), M_TERRA, segs=10))
        for i in range(5):
            p = ck.sph(rng.uniform(0.06, 0.09), (bx + rng.uniform(-0.1, 0.1), yb + 0.2 + rng.uniform(0, 0.14), zc),
                       rng.choice(LEAVES), scale=(1, 1, 0.25), segs=8, rings=6)
            H.add(p)


def bars(H, cx, cy, ww, wh):
    z = WALL + H.cd + 0.022
    n = 7
    for i in range(n):
        bx = cx - (ww + 0.06) / 2 + (ww + 0.06) * (i + 0.5) / n
        H.add(rod((bx, cy - wh / 2 - 0.1, z), (bx, cy + wh / 2 + 0.1, z), 0.014, M_IRON, segs=6))
    for yy in (cy - wh / 2 - 0.06, cy + wh / 2 + 0.06, cy - 0.05):
        H.add(ck.box(ww + 0.22, 0.04, 0.016, (cx, yy, z), M_IRON, bevel=0.005, bevel_segs=1))
    for sx in (-1, 1):
        for yy in (cy - wh / 2 - 0.06, cy + wh / 2 + 0.06):
            wallbox(H, 0.05, 0.05, H.cd + 0.022, cx + sx * (ww / 2 + 0.1), yy, M_IRON, bevel=0.008, segs=1)


def boarded_fill(H, cx, cy, ww, wh, rng):
    """Plywood sheet with chipped edges, two splintered planks (the JS '>' cross), nail heads."""
    H.add(prism(jaggy(ww + 0.02, wh + 0.02, rng, 0.03, 4), 0.03, (cx, cy, -6.963), M_PLY, bevel=0.006, segs=1, name="plywood"))
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        H.add(ck.cyl(0.011, 0.011, 0.01, (cx + sx * (ww / 2 - 0.06), cy + sy * (wh / 2 - 0.06), -6.946), M_NAIL, rot=(math.pi / 2, 0, 0), segs=6))
    for b in range(2):
        ang = 0.3 if b else -0.3
        yb = cy + 0.25 - 0.5 * b
        zb = -6.904 + 0.018 * b
        H.add(prism(jaggy(1.3, 0.18, rng, 0.035, 3), 0.036, (cx, yb, zb), M_PLANK, rot=(0, 0, ang), bevel=0.006, segs=1, name="plank"))
        ca, sa = math.cos(ang), math.sin(ang)
        for ex in (-0.56, 0.56):
            for ey in (-0.045, 0.045):
                nx, ny = ex * ca - ey * sa, ex * sa + ey * ca
                H.add(ck.cyl(0.012, 0.012, 0.012, (cx + nx, yb + ny, zb + 0.02), M_NAIL, rot=(math.pi / 2, 0, 0), segs=6))


def window_ac(H, cx, cy, ww, wh):
    yb = cy - wh / 2 + 0.02
    bh = 0.42
    H.add(ck.box(0.64, bh, 0.5, (cx, yb + bh / 2, -6.95), M_AC, bevel=0.03, bevel_segs=2, name="ac"))
    for i in range(6):
        H.add(ck.box(0.54, 0.022, 0.03, (cx, yb + 0.08 + i * 0.052, -6.693), M_ACG, rot=(0.45, 0, 0), bevel=0.005, bevel_segs=1))
    H.add(ck.box(0.56, 0.035, 0.24, (cx, yb + bh + 0.005, -6.85), M_ACG, bevel=0.01, bevel_segs=1))
    side = (ww - 0.64) / 2
    for s in (-1, 1):
        H.add(ck.box(side - 0.01, bh - 0.03, 0.02, (cx + s * (0.32 + side / 2), yb + bh / 2, -6.94), M_CREAM, bevel=0.005, bevel_segs=1))
    for s in (-1, 1):
        H.add(rod((cx + s * 0.22, yb - 0.3, -6.995), (cx + s * 0.22, yb - 0.005, -6.74), 0.013, M_GALV, segs=6))


def door(H, cx, style="4panel", m=M_DOOR, transom=True, number=None, trim=None, hw=M_BRASS, knocker=False, kick=False):
    trim = trim or H.trim
    H.add(ck.box(1.0, 2.1, 0.08, (cx, 1.05, -6.97), m, bevel=0.012, bevel_segs=2, name="door"))

    def panel(px, py, pw, ph):
        H.add(ck.box(pw, ph, 0.024, (cx + px, py, -6.923), m, bevel=0.01, bevel_segs=2))
    if style == "4panel":
        for sx in (-0.22, 0.22):
            panel(sx, 1.68, 0.32, 0.56)
            panel(sx, 0.86, 0.32, 0.6)
    elif style == "6panel":
        for sx in (-0.22, 0.22):
            panel(sx, 1.88, 0.32, 0.24)
            panel(sx, 1.54, 0.32, 0.32)
            panel(sx, 0.86, 0.32, 0.6)
    elif style == "glass":
        H.add(ck.box(0.66, 0.6, 0.03, (cx, 1.66, -6.928), M_GLASS, bevel=0.008, bevel_segs=1))
        for yy, ww_, hh in ((1.98, 0.74, 0.05), (1.34, 0.74, 0.05)):
            H.add(ck.box(ww_, hh, 0.03, (cx, yy, -6.918), m, bevel=0.008, bevel_segs=1))
        for sx in (-0.355, 0.355):
            H.add(ck.box(0.05, 0.69, 0.03, (cx + sx, 1.66, -6.918), m, bevel=0.008, bevel_segs=1))
        H.add(ck.box(0.025, 0.6, 0.02, (cx, 1.66, -6.92), m))
        H.add(ck.box(0.66, 0.025, 0.02, (cx, 1.66, -6.92), m))
        panel(0, 0.86, 0.7, 0.6)
    elif style == "security":
        H.add(ck.box(0.2, 0.2, 0.02, (cx, 1.78, -6.925), M_GLASS, rot=(0, 0, math.pi / 4), bevel=0.005, bevel_segs=1))
        z = -6.885
        for yy in (0.46, 2.04, 0.95, 1.6):
            H.add(ck.box(0.98, 0.045, 0.02, (cx, yy, z), M_IRON, bevel=0.006, bevel_segs=1))
        for sx in (-0.47, 0.47):
            H.add(ck.box(0.05, 1.64, 0.02, (cx + sx, 1.25, z), M_IRON, bevel=0.006, bevel_segs=1))
        for i in range(7):
            bx = cx - 0.36 + 0.12 * i
            H.add(rod((bx, 0.46, z), (bx, 2.04, z), 0.012, M_IRON, segs=6))
        H.add(ck.tor(0.16, 0.014, (cx, 1.27, z), M_IRON, major_segs=16, minor_segs=5))
        H.add(ck.box(0.1, 0.18, 0.05, (cx + 0.38, 1.27, -6.875), M_IRON, bevel=0.01, bevel_segs=1))
    # casing, transom, hood
    t, cdp = 0.1, 0.085
    ytop = 2.62 if transom else 2.22
    for s in (-1, 1):
        wallbox(H, t, ytop - 0.38, cdp, cx + s * 0.55, (ytop + 0.38) / 2, trim, bevel=0.016)
    if transom:
        wallbox(H, 1.0, 0.1, cdp - 0.015, cx, 2.15, trim, bevel=0.012)
        H.add(ck.box(1.0, 0.33, 0.06, (cx, 2.36, -6.98), M_GLASS, bevel=0.008, bevel_segs=1, name="transom"))
        wallbox(H, 1.32, 0.12, cdp + 0.01, cx, 2.58, trim, bevel=0.016)
        wallbox(H, 1.44, 0.06, cdp + 0.06, cx, 2.67, trim, bevel=0.016)
        if number:
            label(H, number, 0.12, (cx, 2.36, -6.946), M_BRASS, depth=0.008, font="black", bevel=0.0015, name="Number")
    else:
        wallbox(H, 1.32, 0.12, cdp + 0.01, cx, 2.16, trim, bevel=0.016)
        wallbox(H, 1.44, 0.06, cdp + 0.06, cx, 2.25, trim, bevel=0.016)
    # threshold
    H.add(ck.box(1.06, 0.03, 0.12, (cx, 0.41, -6.95), M_STONE, bevel=0.01, bevel_segs=1))
    if style == "security":
        return
    # hardware: knob, deadbolt, mail slot (on the lock rail)
    kx = cx + 0.37
    H.add(ck.cyl(0.04, 0.04, 0.012, (kx, 1.27, -6.925), hw, rot=(math.pi / 2, 0, 0), segs=12))
    H.add(ck.sph(0.036, (kx, 1.27, -6.893), hw, segs=12, rings=8))
    H.add(ck.cyl(0.026, 0.026, 0.014, (kx, 1.42, -6.924), hw, rot=(math.pi / 2, 0, 0), segs=10))
    if style != "glass":
        H.add(ck.box(0.27, 0.075, 0.012, (cx, 1.27, -6.925), hw, bevel=0.004, bevel_segs=1))
        H.add(ck.box(0.21, 0.018, 0.006, (cx, 1.27, -6.918), M_DARK))
    if knocker:
        H.add(ck.box(0.07, 0.11, 0.014, (cx, 1.75, -6.925), hw, bevel=0.006, bevel_segs=1))
        H.add(ck.tor(0.065, 0.013, (cx, 1.66, -6.905), hw, major_segs=18, minor_segs=6))
        H.add(ck.cyl(0.018, 0.018, 0.02, (cx, 1.9, -6.92), hw, rot=(math.pi / 2, 0, 0), segs=10))   # peephole
    if kick:
        H.add(ck.box(0.92, 0.17, 0.008, (cx, 0.5, -6.927), hw, bevel=0.004, bevel_segs=1))


def stoop(H, cx, rail=0):
    """Landing at the JS height (top 0.4) with a step cut into the same footprint."""
    a = H.add(ck.box(1.6, 0.4, 0.6, (cx, 0.2, -6.73), M_STOOP, bevel=0.03, bevel_segs=2, name="stoop"))
    b = H.add(ck.box(1.56, 0.26, 0.36, (cx, 0.13, -6.28), M_STOOP, bevel=0.03, bevel_segs=2, name="step"))
    ck.wobble(a, 0.003, 1.3, seed=H.k)
    ck.wobble(b, 0.003, 1.3, seed=H.k + 9)
    if rail:
        xr = cx + rail * 0.73
        p = [(xr, 0.4, -6.93), (xr, 0.26, -6.16)]
        for (px, py, pz) in p:
            H.add(rod((px, py - 0.02, pz), (px, py + 0.84, pz), 0.02, M_IRON, segs=8))
            H.add(ck.sph(0.03, (px, py + 0.87, pz), M_IRON, segs=8, rings=6))
        H.add(rod((xr, 1.2, -7.0), (xr, 1.06, -6.1), 0.022, M_IRON, segs=8))
        H.add(rod((xr, 0.68, -6.93), (xr, 0.55, -6.16), 0.013, M_IRON, segs=6))
        for f in (0.33, 0.66):
            pz = -6.93 + 0.77 * f
            H.add(rod((xr, 0.4 - 0.14 * f, pz), (xr, 1.2 - 0.14 * f - 0.02, pz), 0.011, M_IRON, segs=6))


def porch_light(H, x, y, kind):
    f = H.face - WALL     # siding houses: mount on the boards, not the wall behind them

    def Z(z):
        return z + f
    if kind == "jelly":
        H.add(ck.cyl(0.065, 0.065, 0.03, (x, y, Z(EMB + 0.015)), M_IRON, rot=(math.pi / 2, 0, 0), segs=12))
        H.add(ck.box(0.035, 0.035, 0.1, (x, y, Z(-6.94)), M_IRON, bevel=0.008, bevel_segs=1))
        H.add(ck.cyl(0.062, 0.062, 0.03, (x, y + 0.01, Z(-6.86)), M_IRON, segs=12))
        H.add(ck.cyl(0.05, 0.058, 0.15, (x, y - 0.08, Z(-6.86)), M_GLOBE, segs=12))
        H.add(ck.tor(0.059, 0.007, (x, y - 0.08, Z(-6.86)), M_IRON, rot=(math.pi / 2, 0, 0), major_segs=12, minor_segs=4))
    elif kind == "globe":
        H.add(ck.cyl(0.07, 0.07, 0.03, (x, y, Z(EMB + 0.015)), M_BRASS, rot=(math.pi / 2, 0, 0), segs=12))
        H.add(rod((x, y, Z(-6.99)), (x, y - 0.02, Z(-6.88)), 0.016, M_BRASS, segs=6))
        H.add(ck.sph(0.085, (x, y - 0.06, Z(-6.85)), M_GLOBE, segs=14, rings=10))
    elif kind == "bare":
        H.add(ck.cyl(0.06, 0.06, 0.025, (x, y, Z(EMB + 0.012)), M_RUST, rot=(math.pi / 2, 0, 0), segs=10))
        H.add(ck.cyl(0.025, 0.03, 0.06, (x, y - 0.04, Z(-6.95)), M_DARK, segs=8))
        H.add(ck.sph(0.035, (x, y - 0.1, Z(-6.95)), M_GLOBE, scale=(1, 1.25, 1), segs=10, rings=8))
    elif kind == "broken":
        H.add(ck.cyl(0.06, 0.06, 0.025, (x, y, Z(EMB + 0.012)), M_RUST, rot=(math.pi / 2, 0, 0), segs=10))
        H.add(ck.cyl(0.025, 0.03, 0.06, (x, y - 0.04, Z(-6.95)), M_DARK, segs=8))
        H.add(rod((x, y - 0.06, Z(-6.95)), (x + 0.03, y - 0.3, Z(-6.93)), 0.006, M_DARK, segs=4))   # dangling wire
    elif kind == "lantern":
        H.add(ck.box(0.11, 0.26, 0.022, (x, y + 0.02, Z(EMB + 0.011)), M_IRON, bevel=0.008, bevel_segs=1))
        H.add(ck.box(0.035, 0.035, 0.14, (x, y + 0.1, Z(-6.93)), M_IRON, bevel=0.008, bevel_segs=1))
        zc = Z(-6.85)
        H.add(ck.box(0.13, 0.19, 0.13, (x, y - 0.03, zc), M_LAMP, bevel=0.01, bevel_segs=1))
        for sx in (-1, 1):
            for sz in (-1, 1):
                H.add(ck.box(0.022, 0.21, 0.022, (x + sx * 0.068, y - 0.03, zc + sz * 0.068), M_IRON, bevel=0.005, bevel_segs=1))
        H.add(ck.box(0.17, 0.03, 0.17, (x, y - 0.135, zc), M_IRON, bevel=0.008, bevel_segs=1))
        H.add(ck.cone(0.13, 0.1, (x, y + 0.12, zc), M_IRON, rot=(0, math.pi / 4, 0), segs=4))
        H.add(ck.sph(0.022, (x, y + 0.18, zc), M_IRON, segs=8, rings=6))


def downspout(H, side, m, broken=False):
    xs = H.x + side * (H.w / 2 - 0.16)
    zo = H.st.get("spout_z", 0.085)
    zc = WALL + zo
    top = H.h - (0.32 if H.st.get("cornice") == "plain" else 0.62)
    bot = 1.05 if broken else 0.3
    H.add(ck.cyl(0.046, 0.046, top - bot, (xs, (top + bot) / 2, zc), m, segs=10, name="downspout"))
    H.add(prism([(-0.13, 0.13), (0.13, 0.13), (0.07, -0.1), (-0.07, -0.1)], 0.18 + zo - 0.085, (xs, top + 0.1, WALL + (0.18 + zo - 0.085) / 2 - 0.005),
                m, bevel=0.012))
    yy = bot + 0.45
    while yy < top - 0.3:
        H.add(ck.box(0.13, 0.035, zo + 0.033, (xs, yy, WALL + (zo + 0.033) / 2), m, bevel=0.006, bevel_segs=1))
        yy += 1.45
    if broken:
        H.add(ck.tor(0.046, 0.009, (xs, bot, zc), m, rot=(math.pi / 2, 0, 0.3), major_segs=10, minor_segs=4))
    else:
        H.add(rod((xs, bot + 0.04, zc), (xs, 0.17, zc + 0.24), 0.046, m, segs=10))
        H.add(ck.box(0.26, 0.05, 0.42, (xs, 0.13, zc + 0.32), M_CONC, bevel=0.015, bevel_segs=1))


def flower_box(H, cx, ytop, width, kind, seed, m_box=None):
    """Window box hung right under the window casing (it replaces the sill); plants spill up in front of the window."""
    rng = random.Random(seed)
    mb = m_box or ck.clay("#6a4a2e")
    zf = -6.755
    H.add(ck.box(width, 0.2, zf - EMB, (cx, ytop - 0.1, (zf + EMB) / 2), mb, bevel=0.02, bevel_segs=2, name="flowerbox"))
    H.add(ck.box(width + 0.03, 0.045, 0.04, (cx, ytop - 0.02, zf - 0.012), mb, bevel=0.012, bevel_segs=2))
    H.add(ck.box(width - 0.07, 0.03, 0.17, (cx, ytop - 0.012, -6.86), M_SOIL, bevel=0.01, bevel_segs=1))
    for sx in (-1, 1):
        H.add(rod((cx + sx * width * 0.33, ytop - 0.34, -6.995), (cx + sx * width * 0.33, ytop - 0.2, -6.79), 0.012, M_IRON, segs=5))
    if kind == "dead":
        n = int(width / 0.11)
        for i in range(n):
            px = cx - width / 2 + 0.08 + (width - 0.16) * i / max(1, n - 1)
            for j in range(2):
                H.add(rod((px, ytop, -6.86), (px + rng.uniform(-0.08, 0.08), ytop + rng.uniform(0.12, 0.26), -6.86 + rng.uniform(-0.03, 0.07)),
                          0.008, rng.choice(DEAD), segs=4))
            if rng.random() < 0.5:
                H.add(ck.sph(0.035, (px, ytop + 0.02, -6.84), rng.choice(DEAD), scale=(1.3, 0.5, 1), segs=8, rings=5))
        return
    # lush: big lumpy foliage masses overhanging the front, flowers dotted over their tops and fronts
    n = max(3, int(width / 0.24))
    for i in range(n):
        px = cx - width / 2 + 0.12 + (width - 0.24) * i / (n - 1) + rng.uniform(-0.03, 0.03)
        r = rng.uniform(0.11, 0.135)
        rx, ry, rz = r * 1.3, r * 0.85, r * 0.9
        c = (px, ytop + 0.05 + rng.uniform(0, 0.035), -6.83 + rng.uniform(-0.015, 0.015))
        leaf = ck.sph(r, c, rng.choice(LEAVES), scale=(1.3, 0.85, 0.9), segs=12, rings=8)
        ck.lumpy(leaf, 0.018, 16, seed=seed + i)
        H.add(leaf)
        for j in range(5):
            th, ph = rng.uniform(-1.1, 1.1), rng.uniform(0.15, 1.15)
            fp = (c[0] + rx * math.cos(ph) * math.sin(th), c[1] + ry * math.sin(ph), c[2] + rz * math.cos(ph) * math.cos(th))
            H.add(ck.sph(rng.uniform(0.03, 0.042), fp, ck.clay(rng.choice(kind)), scale=(1, 0.8, 1), segs=7, rings=5))


# ---------------------------------------------------------------- roof clutter
def chimney(H, cx, cz, base, hh, w=0.62, d=0.52):
    m = random.choice(BRICKS[:2])
    n = max(3, int(hh / 0.22))
    bh = hh / n
    for i in range(n):
        H.add(ck.box(w + jit(0.012), bh + 0.004, d + jit(0.012), (cx + jit(0.008), base + bh * (i + 0.5), cz + jit(0.008)), m,
                     bevel=0.02, bevel_segs=1, name="chimney"))
    H.add(ck.box(w + 0.1, 0.09, d + 0.1, (cx, base + hh - 0.16, cz), m, bevel=0.02, bevel_segs=1))
    H.add(ck.box(w + 0.14, 0.07, d + 0.14, (cx, base + hh + 0.035, cz), M_CONC, bevel=0.02, bevel_segs=2))
    for fx in ((-0.13, 0.13) if w > 0.55 else (0,)):
        H.add(ck.cyl(0.085, 0.085, 0.26, (cx + fx, base + hh + 0.17, cz), M_TERRA, segs=10))


def antenna(H, cx, cz, base, ang=0.0, bent=False):
    e = ck.empty("ant", (cx, base, cz), rot=(0, ang, 0))
    H.empties.append(e)
    H.add(rod((0, 0, 0), (0, 1.9, 0), 0.022, M_GALV, segs=6, parent=e))
    for i, (yy, L) in enumerate(((1.3, 1.0), (1.55, 0.8), (1.8, 0.56))):
        tl = 0.14 if (bent and i == 2) else 0.0
        H.add(rod((-L / 2, yy - tl, 0), (L / 2, yy + tl, 0), 0.013, M_GALV, segs=5, parent=e))
    H.add(rod((0, 1.42, -0.5), (0, 1.42, 0.5), 0.013, M_GALV, segs=5, parent=e))
    H.add(ck.box(0.3, 0.04, 0.3, (0, 0.02, 0), M_GALV, parent=e))
    for s in (-1, 1):
        H.add(rod((s * 0.6, 0.0, 0.4 * s), (0, 1.1, 0), 0.006, M_DARK, segs=4, parent=e))


def dish(H, pos, ang=0.0):
    e = ck.empty("dish", pos, rot=(0, ang, 0))
    H.empties.append(e)
    H.add(rod((0, 0, -0.06), (0, 0.45, -0.06), 0.028, M_GALV, segs=8, parent=e))
    d = ck.sph(0.3, (0, 0.52, 0.0), M_DISH, scale=(1, 1, 0.2), rot=(-0.45, 0, 0), parent=e, segs=20, rings=10)
    H.add(d)
    H.add(rod((0, 0.33, 0.06), (0, 0.6, 0.4), 0.012, M_GALV, segs=6, parent=e))
    H.add(ck.box(0.06, 0.06, 0.1, (0, 0.61, 0.43), M_DARK, parent=e, bevel=0.01, bevel_segs=1))
    H.add(ck.box(0.3, 0.04, 0.3, (0, 0.02, -0.06), M_GALV, parent=e))


def roof(H, items):
    base = H.h + 0.1
    for it in items:
        k, a = it[0], it[1:]
        if k == "chimney":
            chimney(H, H.x + a[0], a[1], base, a[2], *(a[3:]))
        elif k == "antenna":
            antenna(H, H.x + a[0], a[1], base, a[2] if len(a) > 2 else 0.0, bent=len(a) > 3)
        elif k == "dish":
            dish(H, (H.x + a[0], base, a[1]), a[2])
        elif k == "vent":
            H.add(ck.cyl(0.07, 0.07, 0.36, (H.x + a[0], base + 0.18, a[1]), M_GALV, segs=10))
            H.add(ck.sph(0.15, (H.x + a[0], base + 0.38, a[1]), M_GALV, scale=(1, 0.45, 1), segs=14, rings=8))
        elif k == "stack":
            H.add(ck.cyl(0.05, 0.05, 0.6, (H.x + a[0], base + 0.3, a[1]), M_DARK, segs=8))
        elif k == "hatch":
            H.add(ck.box(0.8, 0.24, 0.8, (H.x + a[0], base + 0.12, a[1]), M_ROOF, bevel=0.03, bevel_segs=2))
            H.add(ck.box(0.88, 0.06, 0.88, (H.x + a[0], base + 0.26, a[1]), M_GALV, bevel=0.02, bevel_segs=1))
        elif k == "condenser":
            H.add(ck.box(0.75, 0.6, 0.7, (H.x + a[0], base + 0.3, a[1]), M_AC, bevel=0.03, bevel_segs=2))
            H.add(ck.cyl(0.26, 0.26, 0.03, (H.x + a[0], base + 0.61, a[1]), M_ACG, segs=16))


def wall_ac(H, x, y):
    """Through-the-wall AC sleeve high on a blank wall."""
    wallbox(H, 0.78, 0.48, 0.05, x, y, M_ACG, bevel=0.015)
    H.add(ck.box(0.7, 0.42, 0.3, (x, y, -6.85), M_AC, bevel=0.03, bevel_segs=2))
    for i in range(6):
        H.add(ck.box(0.6, 0.02, 0.03, (x, y - 0.15 + i * 0.06, -6.695), M_ACG, rot=(0.45, 0, 0), bevel=0.005, bevel_segs=1))
    H.add(rod((x + 0.3, y - 0.22, -6.8), (x + 0.32, y - 0.6, -6.95), 0.008, M_DARK, segs=4))   # drip line


def meter(H, x, y):
    """Electric meter box with a glass dome, its conduit and a sagging service cable up to the roof."""
    zb = H.face - 0.012
    H.add(ck.box(0.26, 0.34, 0.11, (x, y, zb + 0.055), M_GALV, bevel=0.02, bevel_segs=2, name="meter"))
    H.add(ck.cyl(0.075, 0.075, 0.07, (x, y + 0.03, zb + 0.14), ck.gloss("#c8d4d8", 0.2), rot=(math.pi / 2, 0, 0), segs=14))
    H.add(ck.cyl(0.08, 0.08, 0.015, (x, y + 0.03, zb + 0.11), M_GALV, rot=(math.pi / 2, 0, 0), segs=14))
    top = H.h - 0.7
    H.add(rod((x, y + 0.17, zb + 0.05), (x, top, zb + 0.05), 0.02, M_GALV, segs=6))
    H.add(ck.sph(0.04, (x, top + 0.02, zb + 0.05), M_GALV, segs=8, rings=6))
    pts = [(x, top + 0.03, zb + 0.06), (x - 0.12, top + 0.25, zb + 0.07), (x - 0.18, H.h - 0.1, zb + 0.09)]
    for a, b in zip(pts, pts[1:]):
        H.add(rod(a, b, 0.009, M_DARK, segs=4))


def round_vent(H, x, y, r, m):
    z0 = H.face - 0.012
    H.add(ck.cyl(r, r, 0.03, (x, y, z0 + 0.015), M_DARK, rot=(math.pi / 2, 0, 0), segs=20))
    H.add(ck.tor(r, 0.045, (x, y, z0 + 0.042), m, major_segs=28, minor_segs=8))
    for i in range(5):
        yy = y - r * 0.7 + i * r * 0.35
        ww = 2 * math.sqrt(max(r * r - (yy - y) ** 2, 0.0)) - 0.03
        H.add(ck.box(ww, 0.035, 0.03, (x, yy, z0 + 0.037), m, rot=(0.6, 0, 0), bevel=0.006, bevel_segs=1))


# ---------------------------------------------------------------- graffiti
def make_xf(gx, gy, a=0.0, sx=1.0, sy=1.0, sh=0.0, dy=0.0):
    """Per-letter hand-drawn transform about the letter center: stretch, shear, tilt, hop."""
    ca, sa = math.cos(a), math.sin(a)

    def f(x, y):
        x, y = (x - gx) * sx, (y - gy) * sy
        x += sh * y
        return gx + x * ca - y * sa, gy + dy + x * sa + y * ca
    return f


def in_tris(px, py, tris):
    for (ax, ay), (bx, by), (cx_, cy_) in tris:
        d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
        d2 = (px - cx_) * (by - cy_) - (bx - cx_) * (py - cy_)
        d3 = (px - ax) * (cy_ - ay) - (cx_ - ax) * (py - ay)
        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
            return True
    return False


def shine_spot(comp, rng):
    """A spot inside a letter near its top-left (for a white spray highlight), or None."""
    faces = {f for v in comp for f in v.link_faces}
    tris = []
    for f in faces:
        vs = f.verts
        if all(v.co.z > 0.0255 for v in vs):
            for i in range(1, len(vs) - 1):
                tris.append(((vs[0].co.x, vs[0].co.y), (vs[i].co.x, vs[i].co.y), (vs[i + 1].co.x, vs[i + 1].co.y)))
    front = [v for v in comp if v.co.z > 0.0255]
    if not tris or not front:
        return None
    cxm = sum(v.co.x for v in front) / len(front)
    cym = sum(v.co.y for v in front) / len(front)
    p0 = max(front, key=lambda v: (v.co.y - cym) - 0.6 * (v.co.x - cxm))
    for fr in (0.16, 0.22, 0.3, 0.38):
        px, py = p0.co.x + fr * (cxm - p0.co.x), p0.co.y + fr * (cym - p0.co.y)
        L = rng.uniform(0.035, 0.05)
        if all(in_tris(px + s * L, py + s * L, tris) for s in (-2.2, -1.3, 0, 1.3)):
            return px, py, L
    return None


def graffiti(H, lines, col, out_col, font, cy=4.8, outline=0.04, jitter=0.07, slant=0.025, drips=7, spacing=1.06, gap=0.17,
             seed=0, shine=0.45):
    """Spray-painted raised lettering: hand-drawn letters over a dark outline, drips, white shine marks.
    lines = [(text, cap height)]; the words are exactly the JS ones."""
    rng = random.Random(seed)
    fill_m, line_m, shine_m = ck.clay(col), ck.clay(out_col), ck.clay("#f4f0e6")
    total = sum(c for _, c in lines) + gap * (len(lines) - 1)
    ytop = total / 2
    pool, spots = [], []
    for li, (s, cap) in enumerate(lines):
        yc = ytop - cap / 2
        ytop -= cap + gap
        size = cap / CAP
        fill = text_bm(s, size, 0.03, font, bevel=0.004, spacing=spacing)
        xs = [v.co.x for v in fill.verts]
        ys = [v.co.y for v in fill.verts]
        ox, oy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        for v in fill.verts:
            v.co.x -= ox
            v.co.y -= oy
            v.co.z += 0.011
        isl = islands(fill)
        chars = [c for c in s if not c.isspace()]
        per = len(isl) == len(chars)
        if not per:
            print(f"[houses] graffiti '{s}': {len(isl)} islands for {len(chars)} letters, no per-letter jitter")
        groups = isl if per else [list(fill.verts)]
        outs = []
        for gi, comp in enumerate(groups):
            gxs = [v.co.x for v in comp]
            gys = [v.co.y for v in comp]
            gx, gy = (min(gxs) + max(gxs)) / 2, (min(gys) + max(gys)) / 2
            if per:
                sc = rng.uniform(0.94, 1.07)
                xf = make_xf(gx, gy, rng.uniform(-jitter, jitter), sc * rng.uniform(0.93, 1.07), sc * rng.uniform(0.94, 1.1),
                             rng.uniform(-0.09, 0.09), rng.uniform(-0.045, 0.045) * cap)
            else:
                xf = make_xf(gx, gy)
            for v in comp:
                v.co.x, v.co.y = xf(v.co.x, v.co.y)
            ob = text_bm(chars[gi] if per else s, size, 0.024, font, offset=outline, spacing=spacing)
            oxs = [v.co.x for v in ob.verts]
            oys = [v.co.y for v in ob.verts]
            ocx, ocy = (min(oxs) + max(oxs)) / 2, (min(oys) + max(oys)) / 2
            for v in ob.verts:
                v.co.x, v.co.y = xf(v.co.x - ocx + gx, v.co.y - ocy + gy)
                v.co.z -= 0.002
            outs.append(ob)
        sl = slant + rng.uniform(-0.012, 0.012)
        ph = rng.uniform(0, 6.28)
        cs, sn = math.cos(sl), math.sin(sl)
        for bmx in [fill] + outs:
            for v in bmx.verts:
                x, y = v.co.x, v.co.y
                x2 = x * cs - y * sn
                y2 = x * sn + y * cs + yc + 0.022 * math.sin(x * 1.25 + ph)
                p = Vector((x2 * 2.2, y2 * 2.2, seed * 3.1 + li))
                v.co.x = x2 + 0.011 * noise.noise(p)
                v.co.y = y2 + 0.011 * noise.noise(p + Vector((17.3, 4.1, 0.0)))
        if per:
            max_len = gap * 0.8 if li < len(lines) - 1 else 0.6     # upper lines may not run into the next one
            for comp in isl:
                ymin = min(v.co.y for v in comp)
                cand = [v.co.x for v in comp if v.co.y < ymin + 0.012 and v.co.z > 0.012]
                if cand:
                    pool.append((rng.choice(cand), ymin, max_len))
                if rng.random() < shine:
                    sp = shine_spot(comp, rng)
                    if sp:
                        spots.append(sp)
        H.add(bm_obj(fill, H.name + "_Graffiti", fill_m, (H.x, cy, WALL)))
        for ob in outs:
            H.add(bm_obj(ob, H.name + "_GraffitiLine", line_m, (H.x, cy, WALL)))
    rng.shuffle(pool)
    for i, (dx, ymin, max_len) in enumerate(pool[:drips]):
        L = min(max_len, rng.uniform(0.06, 0.5) if i % 3 else rng.uniform(0.35, 0.6))
        r = rng.uniform(0.011, 0.017)
        y0 = cy + ymin + 0.025
        x1 = H.x + dx + rng.uniform(-0.012, 0.012)     # drips wander a little
        H.add(rod((H.x + dx, y0, WALL + 0.004), (x1, y0 - L, WALL + 0.004), r * 0.85, fill_m, segs=8, r0=r * 1.2, name="drip"))
        H.add(ck.sph(r * 1.45, (x1, y0 - L, WALL + 0.004), fill_m, scale=(1, 1.15, 1), segs=8, rings=6))
    for px, py, L in spots:
        H.add(rod((H.x + px - L, cy + py - L, WALL + 0.025), (H.x + px + L, cy + py + L, WALL + 0.025), 0.011, shine_m, segs=6))
        H.add(ck.sph(0.017, (H.x + px - L * 1.9, cy + py - L * 1.9, WALL + 0.025), shine_m, segs=8, rings=5))


# ---------------------------------------------------------------- 2-Pack's specials
def slat(H, cx, y, z, L, wd, th, tilt, bend=None):
    """One venetian blind slat, optionally bent where a finger parts the blinds."""
    N = 30 if bend else 1
    bm = bmesh.new()
    rings = []
    for i in range(N + 1):
        x = -L / 2 + L * i / N
        dy, dz, dt = bend(x) if bend else (0.0, 0.0, 0.0)
        a = tilt + dt
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for u, v in ((-wd / 2, -th / 2), (wd / 2, -th / 2), (wd / 2, th / 2), (-wd / 2, th / 2)):
            ring.append(bm.verts.new((x, v * ca + u * sa + dy, -v * sa + u * ca + dz)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(4):
            bm.faces.new((r0[j], r0[(j + 1) % 4], r1[(j + 1) % 4], r1[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.add(bm_obj(bm, H.name + "_Blind", M_WHITE, (cx, y, z), smooth=60))


def blinds(H, cx):
    H.add(ck.box(1.44, 0.065, 0.075, (cx, 2.335, -6.905), M_WHITE, bevel=0.014, bevel_segs=2))
    px = 0.16    # where the peeking finger is (from the window center)

    def bump(amp, sig=0.14, push=-0.012, turn=-0.35):
        def f(x):
            g = math.exp(-((x - px) / sig) ** 2)
            return amp * g, push * g, turn * g * (1 if amp > 0 else -1)
        return f
    bends = {3: bump(0.014), 4: bump(0.05), 5: bump(-0.045), 6: bump(-0.013)}
    for k in range(9):
        slat(H, cx, 2.25 - k * 0.11, -6.905, 1.37, 0.078, 0.011, 0.85, bends.get(k))
    H.add(ck.box(1.38, 0.03, 0.06, (cx, 1.3, -6.905), M_WHITE, bevel=0.01, bevel_segs=1))
    for sx in (-0.45, 0.45):
        H.add(ck.box(0.008, 1.04, 0.004, (cx + sx, 1.82, -6.874), M_CREAM))
    H.add(rod((cx + 0.62, 2.3, -6.87), (cx + 0.62, 1.52, -6.87), 0.005, M_CREAM, segs=4))
    H.add(ck.cone(0.018, 0.05, (cx + 0.62, 1.5, -6.87), M_CREAM, rot=(math.pi, 0, 0), segs=8))


def watch_sign(H):
    """The blue NEIGHBORHOOD WATCH board (JS size), white rim, big yellow letters, bolted proud of the wall."""
    blue, yellow = ck.clay("watch_blue"), ck.clay("#f2c21a")
    H.add(ck.box(1.96, 0.36, 0.03, (-1, 2.6, -6.95), M_WHITE, bevel=0.012, bevel_segs=2, name="watch_rim"))
    H.add(ck.box(1.9, 0.3, 0.05, (-1, 2.6, -6.93), blue, bevel=0.012, bevel_segs=2, name="watch_board"))
    label(H, "NEIGHBORHOOD WATCH", 0.2, (-1, 2.6, -6.899), yellow, depth=0.014, fit=1.74, bevel=0.002, name="WatchText")
    for sx in (-0.915, 0.915):
        for sy in (-0.12, 0.12):
            H.add(ck.cyl(0.013, 0.013, 0.01, (-1 + sx, 2.6 + sy, -6.903), M_GALV, rot=(math.pi / 2, 0, 0), segs=8))
    for sx in (-0.8, 0.8):
        H.add(ck.cyl(0.02, 0.02, 0.03, (-1 + sx, 2.6, -6.975), M_GALV, rot=(math.pi / 2, 0, 0), segs=8))


def camera(H, x, y):
    """A little security camera aimed at the street (2-Pack is the neighborhood watch)."""
    wallbox(H, 0.1, 0.14, H.face - WALL + 0.02, x, y, M_WHITE, bevel=0.008, segs=1)
    H.add(rod((x, y, -6.99), (x, y - 0.03, -6.86), 0.014, M_WHITE, segs=6))
    e = ck.empty("cam", (x, y - 0.05, -6.83), rot=(0.42, 0.35, 0))
    H.empties.append(e)
    H.add(ck.box(0.09, 0.08, 0.21, (0, 0, 0.03), M_WHITE, parent=e, bevel=0.02, bevel_segs=2))
    H.add(ck.box(0.12, 0.012, 0.2, (0, 0.05, 0.05), M_WHITE, parent=e, bevel=0.004, bevel_segs=1))
    H.add(ck.cyl(0.026, 0.026, 0.02, (0, 0, 0.14), M_DARK, rot=(math.pi / 2, 0, 0), parent=e, segs=10))
    H.add(ck.sph(0.008, (0.03, -0.025, 0.14), ck.glow("#ff2a2a", 2.0), parent=e, segs=6, rings=4))


# ---------------------------------------------------------------- the houses
COLS = ["#8a4a3a", "#6a5a7a", "#4a6a7a", "#8a7a4a", "#7a3a3a", "#5a6a4a", "#7a6a5a", "#4a4a5a"]
XS = [-30, -24, -18, -12, -6, 6, 12, 17]
NAMES = ["House_m30", "House_m24", "House_m18", "House_m12", "House_m6", "House_p6", "House_p12", "House_p17"]
FLOWERS = ["#e84a5a", "#f2c21a", "#f4f0e6", "#e88ab8"]

STYLE = {
    "House_m30": dict(surface="stucco", lump=0.007, trim="#5a4436", sash="#4a3a2e", lintel="soldier", cornice="plain",
                      door="4panel", number="901", light=("bare", "above"), spout=(-1, "galv", False),
                      patches=[(0.0, 4.3, 0.42, 0.34), (-1.55, 0.85, 0.5, 0.24)], meter=(2.38, 1.45),
                      deco={(-1.5, 2.0): "shade", (1.4, 4.3): "ac"},
                      roof=[("chimney", -2.15, -9.2, 1.5), ("antenna", 1.0, -8.7, 0.3), ("vent", -0.6, -11.5)]),
    "House_m24": dict(surface="siding", lump=0.003, trim="#e4dcc8", lintel="cap", cornice="dentil", door="6panel",
                      number="903", light=("jelly", "left"), spout=(1, "brown", False), muntins=True,
                      deco={(-1.5, 2.0): "curtains", (1.4, 2.0): "shade_plant"}, curtain="#c8a44a",
                      fbox=((1.4, 2.0), "dead"), meter=(2.3, 1.45),
                      roof=[("dish", 1.6, -7.6, 0.25), ("vent", -1.2, -10.0), ("stack", 0.6, -12.0)]),
    "House_m18": dict(surface="stucco", lump=0.005, trim="#e0d8c4", sash="#2e3a3e", lintel="keystone", cornice="bracket",
                      frieze="#3e5a68", bracket_col="#e0d8c4", brackets=6, door="glass", number="905", light=("lantern", "left"), spout=(-1, "galv", False),
                      quoins="#c8c0ac", belt="#c8c0ac", rail=1, muntins=True, round_vent=6.25,
                      deco={(-1.5, 2.0): "lace", (1.4, 2.0): "shade", (-1.5, 4.3): "curtains", (1.4, 4.3): "shade_plant"},
                      curtain="#a84a3a",
                      roof=[("chimney", -2.15, -8.8, 1.6), ("chimney", 2.15, -8.8, 1.6), ("vent", 0.4, -11.0)]),
    "House_m12": dict(surface="rustic", lump=0.006, trim="#6a5a3a", sash="#e4dcc8", lintel="stone", cornice="plain",
                      door="security", number=None, light=("broken", "left"), spout=(1, "rust", True),
                      rustic_col="#a08f5e", meter=(2.32, 1.5),
                      deco={(-1.5, 4.3): "ac", (1.4, 4.3): "torn"},
                      roof=[("stack", -1.0, -9.0), ("vent", 1.3, -10.5), ("antenna", -1.9, -9.6, -0.5, True)]),
    "House_m6": dict(surface="stucco", lump=0.007, trim="#d8cfba", lintel="stone", cornice="dentil", door="4panel",
                     number="909", light=("jelly", "above"), spout=(-1, "galv", False), belt="#5e2c2c",
                     patches=[(-1.9, 6.6, 0.45, 0.3), (2.2, 0.9, 0.36, 0.26)],
                     deco={(-1.5, 2.0): "bars", (1.4, 2.0): "torn"},
                     graffiti=([("2-PACK IS A", 0.5), ("SNITCH", 0.78)], "#e84a9a", "#3a0e22", "impact", 0.042, 11),
                     roof=[("antenna", 1.2, -8.6, 0.2, True), ("vent", -1.0, -10.0)]),
    "House_p6": dict(surface="stucco", lump=0.006, trim="#2e3a2a", sash="#e4dcc8", lintel="keystone", cornice="bracket",
                     frieze="#4a5a3c", bracket_col="#6a7a5a", brackets=4, door="6panel", number="913", light=("lantern", "left"),
                     spout=(1, "galv", False), spout_z=0.115, pilasters="#6a7a5a", belt="#4a5a3c",
                     deco={(-1.5, 2.0): "curtains", (1.4, 2.0): "shade_plant"}, curtain="#8a3a3a",
                     fbox=((-1.5, 2.0), ["#f4f0e6", "#e84a5a"]),
                     graffiti=([("SNITCHES GET", 0.36), ("STITCHES", 0.52)], "#2ad0e8", "#0c2c36", "black", 0.04, 23),
                     roof=[("dish", -1.7, -7.6, -0.3), ("chimney", 2.15, -9.4, 1.4)]),
    "House_p12": dict(surface="stucco", lump=0.007, trim="#d0c8b4", lintel="stone", cornice="plain", door="4panel",
                      transom=False, number="915", light=("broken", "left"), spout=(-1, "galv", False), trim_right=0.42,
                      patches=[(1.7, 6.4, 0.4, 0.28)], wall_ac=(-1.7, 6.5),
                      graffiti=([("STILL THERE", 0.62)], "#f2c21a", "#3a2a08", "impact", 0.036, 37),
                      roof=[("vent", -0.8, -9.5), ("stack", 1.6, -10.5)]),
    "House_p17": dict(surface="siding", lump=0.003, trim="#eeeae0", lintel="cap", cornice="dentil", door="6panel",
                      number="917", light=("jelly", "left"), spout=(1, "white", False), wide_left=True, rail=1,
                      deco={(-1.5, 2.0): "curtains", (1.4, 2.0): "lace"}, curtain="#e84a9a",
                      fbox=((-1.5, 2.0), ["#e84a9a", "#e84a5a", "#f4f0e6"]),
                      roof=[("vent", -1.0, -9.0), ("chimney", 1.9, -9.6, 1.3, 0.5, 0.45)]),
}


def build_row_house(k):
    name, x, col = NAMES[k], XS[k], COLS[k]
    w = 5.0 if x == 17 else 5.6
    graf = x in (-6, 6, 12)
    h = 7.6 if graf else 5.6 + ((k * 37) % 25) / 10
    wins = []
    for wx in (-1.5, 1.4):
        for wz in ((2.0,) if graf else (2.0, 4.3)):
            wins.append((wx, wz, int(k * 7 + wx * 3 + wz) % 3 == 0))   # JS: ((k*7+wx*3+wz)|0)%3===0
    st = STYLE[name]
    random.seed(100 + k)
    H = House(k, name, x, w, h, col, wins, **st)
    H.add(block(H))
    parapet(H)
    cornice(H, st["cornice"])
    surf = st["surface"]
    if surf == "siding":
        wallbox(H, w + 0.02, 0.45, 0.05, x, 0.225, M_CONC, bevel=0.014)
        siding(H, 0.43, h - 0.38)
        corner_boards(H, 0.43, h - 0.36, H.trim)
    elif surf == "rustic":
        courses(H, base=True, belt=3.1)
        rustication(H, 0.5, 3.03, ck.clay(st.get("rustic_col", col)))
    else:
        courses(H, base=True, belt=3.12)
    if st.get("quoins"):
        quoins(H, 0.5, h - 0.5, ck.clay(st["quoins"]))
    if st.get("pilasters"):
        pilasters(H, 0.5, h - 0.55, ck.clay(st["pilasters"]))
    for i, (dx, cy, rx, ry) in enumerate(st.get("patches", [])):
        brick_patch(H, dx, cy, rx, ry, seed=k * 10 + i)
    fkey = st["fbox"][0] if st.get("fbox") else None
    for wx, wz, boarded in wins:
        window(H, x + wx, wz, boarded, st.get("deco", {}).get((wx, wz)), seed=k * 100 + int(wx * 10) + int(wz * 10),
               sill=(wx, wz) != fkey)
    if fkey:
        (fx, fz), kind = st["fbox"]
        flower_box(H, x + fx, fz - 0.6 - H.ct + 0.004, 1.3, kind, seed=k * 7)
    door(H, H.door_x, st["door"], transom=st.get("transom", True), number=st.get("number"))
    stoop(H, H.door_x, st.get("rail", 0))
    kind, where = st["light"]
    if where == "above":
        porch_light(H, H.door_x, 2.9 if st.get("transom", True) else 2.5, kind)
    else:
        porch_light(H, H.door_x - 0.78, 2.18, kind)
    side, sm, broken = st["spout"]
    downspout(H, side, {"galv": M_GALV, "brown": ck.clay("#4a3424"), "white": M_WHITE, "rust": M_RUST}[sm], broken)
    if st.get("round_vent"):
        round_vent(H, x + 0.05, st["round_vent"], 0.34, H.trim)
    if st.get("wall_ac"):
        wall_ac(H, x + st["wall_ac"][0], st["wall_ac"][1])
    if st.get("meter"):
        meter(H, x + st["meter"][0], st["meter"][1])
    if st.get("graffiti"):
        lines, gc, oc, font, ow, seed = st["graffiti"]
        graffiti(H, lines, gc, oc, font, outline=ow, seed=seed, spacing=1.08 if font == "impact" else 1.0)
    roof(H, st.get("roof", []))
    return H


def build_2pack():
    random.seed(911)
    H = House(8, "House_2Pack", 0.0, 5.6, 7.0, "#b8a070", [], trim="#f2eee2", lintel="cap", tidy=True, lump=0.003,
              surface="siding", cornice="dentil")
    H.door_x = -1.0
    H.add(block(H))
    parapet(H)
    cornice(H, "dentil")
    wallbox(H, 5.62, 0.45, 0.05, 0, 0.225, M_CONC, bevel=0.014)
    siding(H, 0.43, 6.62)
    corner_boards(H, 0.43, 6.64, M_WHITE)
    wallbox(H, 5.64, 0.13, 0.07, 0, 3.12, M_WHITE, bevel=0.02)   # belt course
    # the window with the blinds
    H.add(ck.box(1.4, 1.2, 0.06, (1.8, 1.75, -6.98), M_GLASS, bevel=0.008, bevel_segs=1, name="glass"))
    blinds(H, 1.8)
    t, cd = 0.11, 0.165
    for s in (-1, 1):
        wallbox(H, t, 1.2 + 2 * t, cd, 1.8 + s * (1.4 + t) / 2, 1.75, M_WHITE, bevel=0.02)
    for s in (-1, 1):
        wallbox(H, 1.404, t, cd - 0.005, 1.8, 1.75 + s * (1.2 + t) / 2, M_WHITE, bevel=0.02)
    wallbox(H, 1.4 + 2 * t, 0.1, cd - 0.01, 1.8, 2.35 + t + 0.05, M_WHITE, bevel=0.016)
    wallbox(H, 1.4 + 2 * t + 0.1, 0.05, cd + 0.03, 1.8, 2.35 + t + 0.125, M_WHITE, bevel=0.016)
    flower_box(H, 1.8, 1.75 - 0.6 - t + 0.004, 1.62, ["#e84a5a", "#f2c21a", "#f4f0e6", "#c4162a"], seed=911,
               m_box=ck.clay("#2a4a3a"))
    # red door, sign, light, number
    door(H, -1.0, "6panel", m=ck.clay("#c4162a", 0.5), transom=False, trim=M_WHITE, knocker=True, kick=True)
    watch_sign(H)
    porch_light(H, -1.95, 1.95, "lantern")
    H.add(ck.box(0.46, 0.22, 0.026, (0.22, 1.72, H.face + 0.006), M_WHITE, bevel=0.01, bevel_segs=2, name="number_plate"))
    label(H, "911", 0.13, (0.22, 1.72, H.face + 0.024), M_DARK, depth=0.012, font="black", bevel=0.002, name="Number")
    stoop(H, -1.0, rail=-1)
    H.add(ck.box(0.72, 0.022, 0.4, (-1.0, 0.405, -6.76), ck.clay("#7a5a36", 0.95), bevel=0.008, bevel_segs=1, name="mat"))
    H.add(ck.cyl(0.12, 0.09, 0.22, (-0.38, 0.51, -6.8), M_TERRA, segs=12))
    for i in range(4):
        H.add(ck.sph(random.uniform(0.08, 0.11), (-0.38 + jit(0.06), 0.68 + random.uniform(0, 0.08), -6.8 + jit(0.05)),
                     random.choice(LEAVES), segs=10, rings=7))
    downspout(H, -1, M_WHITE)
    round_vent(H, 0.0, 5.2, 0.36, M_WHITE)
    camera(H, -2.45, 3.55)
    roof(H, [("hatch", 1.2, -10.5), ("vent", -1.5, -9.5)])
    return H


def gbounds(o):
    """World bounds of an object in game coords: ((x0, y0, z0), (x1, y1, z1))."""
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    g = [(p.x, p.z, -p.y) for p in pts]
    return tuple(round(min(c[i] for c in g), 3) for i in range(3)), tuple(round(max(c[i] for c in g), 3) for i in range(3))


def finish(H):
    bpy.context.view_layer.update()
    stoop_o = next(o for o in H.parts if o.name.startswith("stoop"))
    print(f"[houses] {H.name} block {gbounds(H.parts[0])}  stoop top {gbounds(stoop_o)[1][1]}")
    obj = ck.join(H.parts, H.name)
    for e in H.empties:
        bpy.data.objects.remove(e)
    bpy.context.view_layer.update()
    tgt = ck.G((H.x, 0.0, -10.5))      # origin: bottom center of the main block
    obj.data.transform(Matrix.Translation(obj.matrix_world.inverted() @ tgt).inverted())
    obj.location = tgt
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[houses] {H.name}: {tris} tris, {len(obj.data.materials)} materials")
    return obj


houses = [finish(build_row_house(k)) for k in range(8)]
houses.append(finish(build_2pack()))
print("[houses] objects:", sorted(o.name for o in bpy.context.scene.objects))

ck.export("houses")



V = lambda e, l, lens=35: {"eye": e, "look": l, "lens": lens}
ck.preview("houses", views=[
    V((0, 1.7, -1.0), (0, 2.6, -7), 20),
    V((9, 2.0, 5.5), (-3, 3.6, -8), 26),
    V((-9, 2.0, 5.5), (-21, 3.6, -8), 26),
    V((2, 16, 24), (-6, 3, -9), 28),
])
ck.preview("houses_close1", views=[
    V((1.7, 1.6, -4.3), (1.8, 1.55, -7), 30),        # blinds and flower box
    V((-6, 3.6, -1.5), (-6, 4.8, -7), 30),            # pink graffiti
    V((-11.0, 2.0, -3.0), (-12.3, 1.8, -7), 28),       # m12: boarded windows, rusticated stone, security door
    V((-18, 4.0, -2.2), (-18, 7.4, -7), 30),           # bracket cornice
])
ck.preview("houses_close2", views=[
    V((6, 3.6, -1.5), (6, 4.8, -7), 30),              # cyan graffiti
    V((12, 3.4, -1.5), (12, 4.8, -7), 30),            # yellow graffiti
    V((17.1, 1.7, -3.2), (17.1, 1.6, -7), 36),         # Timmy's door
    V((-1.0, 1.9, -3.4), (-0.6, 2.1, -7), 32),         # 2-Pack's door, sign, number
])
