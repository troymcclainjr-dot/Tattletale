"""Corner store, bank, liquor store and Precinct 9 (sign, doors, blue globes, steps, donut box), world space."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ck.reset()
random.seed(909)
PI = math.pi
FZ = -7.0                     # every front wall
BAG = []                      # parts of the object being built
C, GL = ck.clay, ck.gloss
DARK_GLASS = GL("window", 0.15)
PAINT = C("pole", 0.6)                                   # painted shopfront frames
IRON = ck.metal("pole", 0.45)                            # bars, railings, brackets
BRASS, BRONZE = ck.metal("#c8a050", 0.35), ck.metal("#5a4630", 0.45)
GALV, PIPE = ck.metal("#8a8a90", 0.5), ck.metal("#6a7078", 0.5)
TAR = C("#3e3a36", 0.95)     # same tar roof as the houses
HAND = r"C:\Windows\Fonts\segoeprb.ttf"


def R(a, b):
    return random.uniform(a, b)


def shade(h, k):
    """Hex colour scaled by k (grime, weathering)."""
    h = ck.PAL.get(h, h).lstrip("#")
    return "#" + "".join(f"{max(0, min(255, round(int(h[i:i + 2], 16) * k))):02x}" for i in (0, 2, 4))


def keep(o):
    BAG.append(o)
    return o


# ------------------------------------------------------------------ primitives (kept in BAG)
def bx(w, h, d, x, y, z, m, bev=0.015, segs=2, rot=None, name="part"):
    return keep(ck.box(w, h, d, (x, y, z), m, rot=rot, name=name, bevel=bev, bevel_segs=segs))


def cy(rt, rb, h, x, y, z, m, rot=None, segs=12, cap=True, name="cyl"):
    return keep(ck.cyl(rt, rb, h, (x, y, z), m, rot=rot, segs=segs, cap=cap, name=name))


def sp(r, x, y, z, m, scale=(1, 1, 1), rot=None, segs=12, rings=8, name="sph"):
    return keep(ck.sph(r, (x, y, z), m, scale=scale, rot=rot, segs=segs, rings=rings, name=name))


def to(rr, r, x, y, z, m, rot=None, segs=(20, 8), name="torus"):
    return keep(ck.tor(rr, r, (x, y, z), m, rot=rot, major_segs=segs[0], minor_segs=segs[1], name=name))


def _curve_mesh(cu, name):
    tmp = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    return me


def _mesh_ob(me, m, name, smooth_deg=40):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ck.assign(ob, m)
    ck.smooth(ob, smooth_deg)
    return ob


def _place(ob, pos, rot=None):
    if rot is not None:
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = ck.grot(*rot).to_quaternion()
    ob.location = ck.G(pos)
    return ob


_CAP = {}


def _font(f):
    return bpy.data.fonts.load(ck.FONTS.get(f, f), check_existing=True)


def _cap(font):
    if font not in _CAP:
        cu = bpy.data.curves.new("cap", "FONT")
        cu.body, cu.font, cu.size = "H", _font(font), 1.0
        me = _curve_mesh(cu, "cap")
        ys = [v.co.y for v in me.vertices]
        _CAP[font] = max(ys) - min(ys)
        bpy.data.meshes.remove(me)
    return _CAP[font]


def letters(s, cap, pos, m, fit=None, depth=0.025, font="impact", res=3, bevel=0.004, rot=None, name="letters"):
    """Raised lettering, cap height `cap` (shrunk to `fit` wide), centred on pos, facing +z, open back."""
    k = cap / _cap(font)
    cu = bpy.data.curves.new(name, "FONT")
    cu.body, cu.font, cu.size = s, _font(font), 1.0
    cu.align_x, cu.align_y = "CENTER", "BOTTOM_BASELINE"
    me = _curve_mesh(cu, name)
    xs = [v.co.x for v in me.vertices]
    bpy.data.meshes.remove(me)
    if fit and (max(xs) - min(xs)) * k > fit:
        k = fit / (max(xs) - min(xs))
    cu.size, cu.resolution_u = k, res
    cu.extrude, cu.bevel_depth, cu.bevel_resolution = depth / 2, bevel, 1
    me = _curve_mesh(cu, name)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.6], context="FACES")
    xs = [v.co.x for v in bm.verts]
    sh = Vector(((max(xs) + min(xs)) / -2, -k * _cap(font) / 2, 0.0))
    for v in bm.verts:
        v.co += sh
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Rotation(PI / 2, 4, "X"))
    return keep(_place(_mesh_ob(me, m, name, 35), pos, rot))


def plate(pts, depth, pos, m, bevel=0.0, rot=None, name="plate", smooth_deg=35):
    """Extruded 2D outline (x right, y up) facing +z, centred in depth on pos."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions, cu.fill_mode = "2D", "BOTH"
    cu.extrude, cu.bevel_depth, cu.bevel_resolution = depth / 2, bevel, 1 if bevel else 0
    s = cu.splines.new("POLY")
    s.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        s.points[i].co = (x, y, 0.0, 1.0)
    s.use_cyclic_u = True
    me = _curve_mesh(cu, name)
    me.transform(Matrix.Rotation(PI / 2, 4, "X"))
    return keep(_place(_mesh_ob(me, m, name, smooth_deg), pos, rot))


def tube(pts, r, m, smooth=False, closed=False, res=6, bres=1, name="tube"):
    """Round rod through game-space points."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth, cu.bevel_resolution, cu.use_fill_caps, cu.resolution_u = r, bres, not closed, res
    if smooth:
        s = cu.splines.new("BEZIER")
        s.bezier_points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            b = s.bezier_points[i]
            b.co = ck.G(p)
            b.handle_left_type = b.handle_right_type = "AUTO"
    else:
        s = cu.splines.new("POLY")
        s.points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            s.points[i].co = (*ck.G(p), 1.0)
    s.use_cyclic_u = closed
    return keep(_mesh_ob(_curve_mesh(cu, name), m, name, 50))


def lathe(prof, pos, m, segs=12, name="lathe", smooth_deg=50, rot=None):
    """Revolve (r, y) pairs, bottom to top, around game Y."""
    bm = bmesh.new()
    rings = [[bm.verts.new((max(r, 0.0015) * math.cos(2 * PI * i / segs), max(r, 0.0015) * math.sin(2 * PI * i / segs), y))
              for i in range(segs)] for r, y in prof]
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return keep(_place(_mesh_ob(me, m, name, smooth_deg), pos, rot))


def sheet(fn, nu, nv, th, m, off=(0.0, -1.0, 0.0), name="sheet", smooth_deg=50):
    """Thick surface: fn(u, v) -> game point, thickness th along the game direction `off`."""
    bm = bmesh.new()
    O = ck.G(off) * th
    top = [[bm.verts.new(ck.G(fn(i / nu, j / nv))) for j in range(nv + 1)] for i in range(nu + 1)]
    bot = [[bm.verts.new(top[i][j].co + O) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]))
    for i in range(nu):
        bm.faces.new((top[i][0], bot[i][0], bot[i + 1][0], top[i + 1][0]))
        bm.faces.new((top[i + 1][nv], bot[i + 1][nv], bot[i][nv], top[i][nv]))
    for j in range(nv):
        bm.faces.new((top[0][j + 1], bot[0][j + 1], bot[0][j], top[0][j]))
        bm.faces.new((top[nu][j], bot[nu][j], bot[nu][j + 1], top[nu][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return keep(_mesh_ob(me, m, name, smooth_deg))


# ------------------------------------------------------------------ outlines
def rrect(w, h, r, n=4):
    pts = []
    for cx, cz, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, PI / 2), (-w / 2 + r, -h / 2 + r, PI), (w / 2 - r, -h / 2 + r, 1.5 * PI)):
        pts += [(cx + r * math.cos(a0 + PI / 2 * k / n), cz + r * math.sin(a0 + PI / 2 * k / n)) for k in range(n + 1)]
    return pts


def star(ro, ri, n=5):
    return [((ro if i % 2 == 0 else ri) * math.cos(PI / 2 + PI * i / n), (ro if i % 2 == 0 else ri) * math.sin(PI / 2 + PI * i / n))
            for i in range(2 * n)]


def ragged(w, h, n=14, j=0.22):
    return [(math.cos(2 * PI * i / n) * w / 2 * (1 + R(-j, j)), math.sin(2 * PI * i / n) * h / 2 * (1 + R(-j, j))) for i in range(n)]


# ------------------------------------------------------------------ walls
def gridbox(w, h, d, c, m, step=0.42, bev=0.07, name="block"):
    """Box with a vertex grid (so it can be lumped), mesh in world coords, edges rounded."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, v.co.z * h))
    for axis, size in ((0, w), (1, d), (2, h)):
        n = max(1, round(size / step))
        for i in range(1, n):
            co, no = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
            co[axis], no[axis] = -size / 2 + size * i / n, 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Translation(ck.G(c)))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ck.assign(ob, m)
    if bev:
        ck.bevel_obj(ob, bev, 3, 40)
    return ob


def block(w, h, d, c, m, holes, seed):
    """The JS block with recessed openings cut into its front wall: holes = (x0, x1, y0, y1, depth)."""
    ob = gridbox(w, h, d, c, m)
    for (a, b, y0, y1, dep) in holes:
        cut = ck.box(b - a, y1 - y0, dep + 0.4, ((a + b) / 2, (y0 + y1) / 2, FZ + 0.2 - dep / 2), m, name="cutter")
        md = ob.modifiers.new("cut", "BOOLEAN")
        md.operation, md.solver, md.object = "DIFFERENCE", "EXACT", cut
        ck._apply_modifiers(ob)
        bpy.data.objects.remove(cut)
    ck.smooth(ob, 40)
    ck.lumpy(ob, 0.006, 1.3, seed=seed)
    ck.wobble(ob, 0.008, 0.3, seed=seed)
    return keep(ob)


def bvh(ob):
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    return BVHTree.FromPolygons([mw @ v.co for v in ob.data.vertices], [tuple(p.vertices) for p in ob.data.polygons])


def conform(ob, tree, d=(0.0, 0.0, -1.0), off=0.004):
    """Press a thin decal onto the (lumpy) wall: its back ends up `off` in front of the surface."""
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    mi = mw.inverted()
    D = ck.G(d).normalized()
    ws = [mw @ v.co for v in ob.data.vertices]
    back = max(w.dot(D) for w in ws)
    for v, w in zip(ob.data.vertices, ws):
        hit = tree.ray_cast(w - D * 0.6, D, 2.0)[0]
        if hit is not None:
            v.co = mi @ (w + D * ((hit - w).dot(D) - off - (back - w.dot(D))))
    ob.data.update()
    return ob


def streak(x, ytop, length, width, col, tree, name="streak"):
    """A rain / rust stain running down the wall from ytop."""
    w2 = width / 2
    pts = [(-w2, 0.0), (w2, 0.0), (w2 * R(0.7, 0.95), -length * 0.5), (w2 * R(0.35, 0.6), -length * 0.85), (R(-0.01, 0.01), -length),
           (-w2 * R(0.35, 0.6), -length * R(0.75, 0.9)), (-w2 * R(0.7, 0.95), -length * 0.45)]
    return conform(plate(pts, 0.003, (x, ytop, FZ + 0.03), C(col), name=name), tree)


def smudge(x, y, w, h, col, tree, name="smudge"):
    return conform(plate(ragged(w, h, 12, 0.18), 0.003, (x, y, FZ + 0.03), C(col), name=name), tree)


def frame(a, b, y0, y1, t, m, z0=FZ - 0.05, z1=FZ + 0.05, sill=True, ov=0.012):
    """Four bars around an opening, overlapping its cut edge by ov."""
    d, zc = z1 - z0, (z0 + z1) / 2
    bev = min(0.02, t / 3)
    bx(b - a + 2 * t - 2 * ov, t, d, (a + b) / 2, y1 + t / 2 - ov, zc, m, bev=bev)
    if sill:
        bx(b - a + 2 * t - 2 * ov, t, d, (a + b) / 2, y0 - t / 2 + ov, zc, m, bev=bev)
    ylo = y0 - (t - ov if sill else 0.0)
    for x in (a - t / 2 + ov, b + t / 2 - ov):
        bx(t, y1 + t - ov - ylo, d - 0.004, x, (y1 + t - ov + ylo) / 2, zc - 0.002, m, bev=bev)


def bricks(x, y, cols, rows, tree, seed=0):
    """A patch of bare brick where the render has fallen off."""
    smudge(x, y, cols * 0.2 + 0.12, rows * 0.085 + 0.1, "#6e6052", tree)
    for r in range(rows):
        for c in range(cols - (r % 2)):
            bxx = x - (cols - 1) * 0.1 + c * 0.2 + (0.1 if r % 2 else 0.0) + R(-0.008, 0.008)
            b = bx(0.17, 0.064, 0.03, bxx, y - (rows - 1) * 0.0425 + r * 0.085, FZ + 0.03,
                   C(random.choice(["#8a4a3a", "#7a4232"])), bev=0.012, segs=1)
            conform(b, tree, off=-0.012)


# ------------------------------------------------------------------ shared props
def roof_ac(x, y, z):
    bx(1.0, 0.62, 0.8, x, y + 0.31, z, C("#b8b6aa"), bev=0.04)
    for k in range(5):
        bx(0.86, 0.022, 0.01, x, y + 0.1 + k * 0.1, z + 0.4, C("#8a8a84"), bev=0)
    cy(0.27, 0.27, 0.03, x, y + 0.625, z, IRON, segs=16)
    to(0.27, 0.022, x, y + 0.64, z, C("#7a7a74"), rot=(PI / 2, 0, 0), segs=(20, 6))
    bx(0.5, 0.012, 0.025, x, y + 0.65, z, C("#7a7a74"), bev=0)
    bx(0.025, 0.012, 0.5, x, y + 0.65, z, C("#7a7a74"), bev=0)


def vent(x, y, z, h=0.6):
    cy(0.06, 0.06, h, x, y + h / 2, z, PIPE, segs=10)
    cy(0.11, 0.1, 0.07, x, y + h + 0.03, z, PIPE, segs=10)


def downspout(x, z, ytop, m, wx):
    """Rain head, pipe and shoe on a side wall at x = wx; (x, z) is the pipe centre."""
    bx(0.2, 0.22, 0.16, x, ytop, z, m, bev=0.02)
    tube([(x, ytop - 0.1, z), (x, 0.32, z), (x, 0.2, z + 0.08), (x, 0.15, z + 0.2)], 0.045, m, smooth=True, bres=2)
    for yy in (ytop - 0.6, ytop / 2, 1.2):
        bx(abs(x - wx) + 0.05, 0.04, 0.11, (x + wx) / 2, yy, z, m, bev=0.008, segs=1)


def neon(pts2d, ox, oy, z, r, m, closed=False, smooth=True):
    return tube([(ox + px, oy + py, z) for px, py in pts2d], r, m, smooth=smooth, closed=closed, res=4, bres=1, name="neon")


# ------------------------------------------------------------------ corner store goods
def store_goods(a, b, yf, zb):
    """Chips on the display floor, cans on the first shelf, soda and cereal on the second."""
    span = b - a
    bags = [GL("gold", 0.3), GL("red", 0.3), GL("phone_blue", 0.3), GL("orange", 0.3)]
    cans = [GL("red", 0.3), GL("#e8e4d6", 0.3), GL("phone_blue", 0.3), GL("#3a8a4a", 0.3)]
    boxes = [C("gold"), C("red"), C("phone_blue"), C("#e8e4d6")]
    n = 6
    for i in range(n):
        x = a + span * (i + 0.5) / n + R(-0.015, 0.015)
        t, z0, col = 0.2 + R(-0.06, 0.06), zb + 0.1, bags[(i + 1) % 4]
        for h, w, hh, d in ((0.15, 0.2, 0.26, 0.075), (0.285, 0.21, 0.03, 0.03), (0.018, 0.2, 0.03, 0.04)):
            bx(w, hh, d, x, yf + h * math.cos(t), z0 - h * math.sin(t), col, bev=0.03 if hh > 0.1 else 0.008, segs=2 if hh > 0.1 else 1, rot=(-t, 0, 0))
        cy(0.06, 0.06, 0.01, x, yf + 0.16 * math.cos(t) + 0.038 * math.sin(t), z0 - 0.16 * math.sin(t) + 0.038 * math.cos(t),
           C("cream") if i % 4 != 3 else C("red"), rot=(PI / 2 - t, 0, 0), segs=12)
    for i, x in enumerate((a + 0.22, b - 0.25)):
        bx(0.26, 0.07, 0.19, x, yf + 0.035, zb + 0.24, boxes[i], bev=0.01, segs=1, rot=(0, R(-0.2, 0.2), 0))
    # shelf 1: two rows of cans, grouped by brand, a short pyramid on top
    ys = 1.325
    n = int((span - 0.1) / 0.125)
    xs = [a + 0.07 + i * (span - 0.14) / (n - 1) for i in range(n)]
    for row, zz in ((0, zb + 0.08), (1, zb + 0.19)):
        for i, x in enumerate(xs):
            cy(0.05, 0.05, 0.13, x + R(-0.006, 0.006), ys + 0.065, zz, cans[(i // 3 + row) % 4], segs=10)
    for i, x in enumerate(xs[1:4]):
        cy(0.05, 0.05, 0.13, x + 0.06, ys + 0.195, zb + 0.19, cans[2], segs=10)
    # shelf 2: two-litre bottles and cereal boxes
    ys = 1.825
    pop = [GL("#3a1a14", 0.3), GL("#5a9a3a", 0.3), GL("orange", 0.3)]
    prof = [(0.048, 0.0), (0.054, 0.015), (0.054, 0.19), (0.046, 0.235), (0.024, 0.28), (0.018, 0.29), (0.018, 0.305)]
    for i in range(6):
        x = a + 0.12 + i * 0.16 + R(-0.01, 0.01)
        lathe(prof, (x, ys, zb + 0.15), pop[i % 3], segs=10)
        cy(0.056, 0.056, 0.08, x, ys + 0.11, zb + 0.15, C("cream") if i % 3 else C("red"), segs=10)
        cy(0.022, 0.022, 0.03, x, ys + 0.315, zb + 0.15, C("red") if i % 3 != 1 else C("#3a8a4a"), segs=8)
    for i, x in enumerate((b - 0.36, b - 0.14)):
        bx(0.19, 0.3, 0.075, x, ys + 0.15, zb + 0.14, boxes[i % 2], bev=0.01, segs=1, rot=(0, R(-0.08, 0.08), 0))
        bx(0.13, 0.12, 0.006, x, ys + 0.17, zb + 0.18, boxes[(i + 3) % 4], bev=0)


# ================================================================== CORNER STORE
def corner_store():
    X = 22.5
    wall, trim, dark = C("store"), C("#d8d0bc"), PAINT
    tile, wood = C("#2f3a34", 0.7), C("#7a5a3a")
    door = (21.8, 23.2, -0.1, 2.42, 0.22)
    wins = [(19.92, 21.58, 0.80, 2.45, 0.32), (23.42, 25.08, 0.80, 2.45, 0.32)]
    ups = [(20.55, 21.45, 5.30, 6.22, 0.16), (23.55, 24.45, 5.30, 6.22, 0.16)]
    blk = block(6.0, 7.0, 7.0, (X, 3.5, -10.5), wall, [door] + wins + ups, seed=3)
    tree = bvh(blk)

    # storefront: end piers, fascia, bulkheads, display windows
    for px in (19.68, 25.32):
        bx(0.26, 2.62, 0.1, px, 1.31, FZ + 0.03, dark, bev=0.025)
        bx(0.32, 0.24, 0.14, px, 0.12, FZ + 0.05, tile, bev=0.025)
    bx(5.96, 0.2, 0.12, X, 2.6, FZ + 0.04, dark, bev=0.03)
    for (a, b, y0, y1, dep) in wins:
        cx, wi, zb = (a + b) / 2, b - a, FZ - dep
        bx(wi + 0.1, y0 - 0.06, 0.05, cx, (y0 - 0.06) / 2, FZ + 0.01, tile, bev=0.02)
        bx(wi - 0.24, 0.38, 0.03, cx, (y0 - 0.06) / 2 + 0.03, FZ + 0.045, tile, bev=0.012)
        bx(wi - 0.01, 0.04, dep - 0.03, cx, y0 + 0.02, FZ - dep / 2 - 0.015, wood, bev=0.01)
        bx(wi - 0.01, y1 - y0, 0.02, cx, (y0 + y1) / 2, zb + 0.012, C("#3a2a20"), bev=0.005)
        for sy in (1.31, 1.81):
            bx(wi - 0.04, 0.03, 0.22, cx, sy, zb + 0.135, wood, bev=0.008)
            for kx in (a + 0.15, b - 0.15):
                bx(0.02, 0.1, 0.16, kx, sy - 0.065, zb + 0.11, dark, bev=0.004, segs=1)
        store_goods(a + 0.04, b - 0.04, y0 + 0.04, zb + 0.02)
        bx(wi, y1 - y0, 0.01, cx, (y0 + y1) / 2, FZ - 0.045, ck.glass("#3a4a58", 0.2), bev=0)
        frame(a, b, y0, y1, 0.07, dark)
    # hand-lettered price cards taped inside the glass
    plate(star(0.17, 0.115, 9), 0.004, (21.22, 2.2, FZ - 0.062), C("gold"))
    letters("$1", 0.085, (21.22, 2.2, FZ - 0.059), C("red"), font=HAND, depth=0.004, res=2, bevel=0.0)
    plate(rrect(0.3, 0.2, 0.02), 0.004, (23.8, 2.22, FZ - 0.062), C("cream"), rot=(0, 0, 0.06))
    letters("99\u00a2", 0.075, (23.8, 2.22, FZ - 0.059), C("red"), font=HAND, depth=0.004, res=2, bevel=0.0, rot=(0, 0, 0.06))

    # door: threshold, jambs, glazed leaf, push bar
    zr = FZ - 0.22
    bx(1.46, 0.3, 0.34, X, 0.03, FZ - 0.1, C("curb"), bev=0.025)
    for sx in (-1, 1):
        bx(0.1, 2.3, 0.08, X + sx * 0.65, 1.27, zr + 0.04, dark, bev=0.01)
        bx(0.09, 2.16, 0.05, X + sx * 0.555, 1.27, zr + 0.05, dark, bev=0.012)
    bx(1.4, 0.1, 0.08, X, 2.37, zr + 0.04, dark, bev=0.01)
    bx(1.2, 0.09, 0.05, X, 2.28, zr + 0.05, dark, bev=0.012)
    bx(1.2, 0.3, 0.05, X, 0.33, zr + 0.05, dark, bev=0.012)
    bx(1.04, 1.86, 0.012, X, 1.39, zr + 0.035, DARK_GLASS, bev=0)
    alu = ck.metal("alu", 0.35)
    tube([(X - 0.44, 1.05, zr + 0.13), (X + 0.44, 1.05, zr + 0.13)], 0.018, alu, bres=2)
    for sx in (-0.38, 0.38):
        cy(0.012, 0.012, 0.06, X + sx, 1.05, zr + 0.1, alu, rot=(PI / 2, 0, 0), segs=6)
    bx(1.0, 0.2, 0.008, X, 0.34, zr + 0.079, alu, bev=0)
    frame(21.8, 23.2, 0.18, 2.42, 0.07, dark, sill=False)

    # striped awning on an iron frame
    xa, xb, yt, yf, zf, n = 19.72, 25.28, 3.42, 2.86, -6.02, 10
    red, cream = C("red"), C("cream")
    ws = (xb - xa) / n
    for k in range(n):
        x0 = xa + k * ws
        col = red if k % 2 == 0 else cream
        j = R(-0.006, 0.006)
        sheet(lambda u, v, x0=x0, j=j: (x0 + ws * u, yt - (yt - yf) * v - 0.035 * math.sin(PI * v) + j * v, FZ + (zf - FZ) * v), 1, 6, 0.025, col)
        sheet(lambda u, v, x0=x0, j=j: (x0 + ws * u, yf + j + 0.012 - (0.2 + 0.07 * math.sin(PI * u)) * v, zf + 0.012), 6, 1, 0.022, col, off=(0, 0, -1))
    for xs_, s in ((xa, 1), (xb, -1)):
        sheet(lambda u, v, xs_=xs_: (xs_, (yt - (yt - yf) * u - 0.035 * math.sin(PI * u) + 0.004) * (1 - v) + (yt - 0.55 - (yt - 0.55 - yf + 0.19) * u) * v,
                                     FZ + (zf - FZ) * u), 6, 1, 0.022, red, off=(s, 0, 0))
    iron = IRON
    tube([(xa + 0.03, yf - 0.03, zf - 0.025), (xb - 0.03, yf - 0.03, zf - 0.025)], 0.018, iron)
    tube([(xa, yt + 0.03, FZ + 0.03), (xb, yt + 0.03, FZ + 0.03)], 0.02, iron)
    for ax in (xa + 0.08, X, xb - 0.08):
        tube([(ax, 2.74, FZ + 0.02), (ax, yf - 0.05, zf - 0.04)], 0.014, iron)
        bx(0.07, 0.12, 0.03, ax, 2.74, FZ + 0.012, iron, bev=0.008, segs=1)

    # sign board, frame, lettering, gooseneck lamps
    bx(4.8, 0.7, 0.1, X, 4.2, -6.95, C("sign_white"), bev=0.025)
    frame(X - 2.4, X + 2.4, 3.85, 4.55, 0.055, dark, z0=-6.99, z1=-6.885, ov=0.02)
    letters("CORNER STORE", 0.36, (X, 4.2, -6.9 + 0.0095), C("black"), fit=4.3)
    lamp = C("#2f4a3a", 0.6)
    dy, dz = -math.cos(0.7), -math.sin(0.7)
    for lx in (21.0, X, 24.0):
        cy(0.05, 0.05, 0.03, lx, 4.8, FZ + 0.012, lamp, rot=(PI / 2, 0, 0), segs=10)
        tube([(lx, 4.8, FZ + 0.02), (lx, 4.92, -6.8), (lx, 4.93, -6.55), (lx, 4.86, -6.42)], 0.016, lamp, smooth=True)
        cy(0.04, 0.15, 0.14, lx, 4.86 + 0.07 * dy, -6.42 + 0.07 * dz, lamp, rot=(0.7, 0, 0), segs=14)
        cy(0.125, 0.125, 0.01, lx, 4.86 + 0.137 * dy, -6.42 + 0.137 * dz, C("sign_white"), rot=(0.7, 0, 0), segs=14)

    # upper windows: sash, sill, lintel; a blind in one, a flower box on the other
    sash = C("#efe9da")
    for i, (a, b, y0, y1, dep) in enumerate(ups):
        cx = (a + b) / 2
        bx(b - a, y1 - y0, 0.02, cx, (y0 + y1) / 2, FZ - dep + 0.02, DARK_GLASS, bev=0)
        zs = FZ - dep + 0.055
        for (w_, h_, x_, y_) in ((b - a, 0.05, cx, y1 - 0.025), (b - a, 0.05, cx, y0 + 0.025), (0.05, y1 - y0, a + 0.025, (y0 + y1) / 2),
                                 (0.05, y1 - y0, b - 0.025, (y0 + y1) / 2), (b - a, 0.045, cx, (y0 + y1) / 2)):
            bx(w_, h_, 0.04, x_, y_, zs, sash, bev=0.008, segs=1)
        bx(b - a + 0.2, 0.07, 0.17, cx, y0 - 0.035, FZ + 0.06, trim, bev=0.02)
        bx(b - a + 0.16, 0.13, 0.07, cx, y1 + 0.065, FZ + 0.02, trim, bev=0.02)
        frame(a, b, y0, y1, 0.06, trim, z0=FZ - 0.03, z1=FZ + 0.035, sill=False)
        if i == 0:
            bx(b - a - 0.1, 0.36, 0.01, cx, y1 - 0.24, zs + 0.03, trim, bev=0.004)
            to(0.02, 0.005, cx, y1 - 0.45, zs + 0.035, C("gold"), segs=(10, 4))
        else:
            bx(0.96, 0.16, 0.2, cx, y0 + 0.08, FZ + 0.11, C("#a85a3a"), bev=0.02)
            for k in range(8):
                fx = a + 0.06 + k * 0.11
                sp(0.06, fx, y0 + 0.2, FZ + 0.1 + R(-0.04, 0.04), C("#3a8a4a"), scale=(1.2, 0.8, 1.0), segs=8, rings=6)
                if k % 2 == 0:
                    sp(0.042, fx + R(-0.02, 0.02), y0 + 0.27, FZ + 0.13, C("red") if k % 4 == 0 else C("gold"), segs=8, rings=6)

    # cornice on corbels, a false-front parapet with a raised centre, low side parapets
    for k in range(9):
        bx(0.12, 0.2, 0.2, 19.78 + k * 0.68, 6.52, FZ + 0.09, trim, bev=0.03)
    bx(6.0, 0.14, 0.32, X, 6.69, FZ + 0.15, trim, bev=0.035)
    bx(6.0, 0.1, 0.36, X, 6.81, FZ + 0.165, trim, bev=0.03)
    bx(6.0, 0.44, 0.28, X, 7.08, FZ - 0.11, wall, bev=0.04)
    bx(2.2, 0.34, 0.28, X, 7.47, FZ - 0.11, wall, bev=0.04)
    bx(6.04, 0.07, 0.36, X - 0.02, 7.335, FZ - 0.11, trim, bev=0.025)
    bx(2.28, 0.07, 0.36, X, 7.675, FZ - 0.11, trim, bev=0.025)
    for sx in (-1, 1):
        bx(0.2, 0.22, 6.72, X + sx * 2.9, 7.1, -10.62, wall, bev=0.04)
    bx(5.6, 0.22, 0.2, X, 7.1, -13.9, wall, bev=0.04)
    bx(5.62, 0.04, 6.56, X, 7.01, -10.52, TAR, bev=0.015, segs=1)
    roof_ac(21.0, 7.0, -11.6)
    vent(24.1, 7.0, -12.4)
    bx(0.8, 0.22, 0.8, 23.6, 7.11, -10.2, C("#7a7a74"), bev=0.03)

    # grime and age
    g = shade("store", 0.78)
    for (a, b, y0, y1, dep) in ups:
        for sx in (a + 0.1, b - 0.14):
            streak(sx + R(-0.03, 0.03), y0 - 0.07, R(0.4, 0.75), R(0.05, 0.09), g, tree)
    streak(20.35, 3.84, 0.38, 0.07, g, tree)
    streak(24.7, 3.84, 0.3, 0.06, g, tree)
    streak(19.62, 6.4, 1.2, 0.12, g, tree)
    streak(25.3, 6.4, 0.9, 0.1, g, tree)
    bricks(22.95, 5.75, 3, 3, tree)
    smudge(20.0, 3.65, 0.3, 0.18, g, tree)
    return finish("CornerStore", (X, 0.0, -10.5))


# ================================================================== BANK
BALUSTER = [(0.055, 0.0), (0.055, 0.03), (0.032, 0.055), (0.042, 0.1), (0.072, 0.18), (0.068, 0.22), (0.034, 0.31), (0.028, 0.345),
            (0.048, 0.37), (0.052, 0.42)]


def fluted(x, y0, y1, zc, r0, r1, m, flutes=16, rings=5):
    bm = bmesh.new()
    n = flutes * 2
    rows = []
    for k in range(rings + 1):
        t = k / rings
        r = r0 + (r1 - r0) * t + 0.006 * math.sin(PI * t)
        rows.append([bm.verts.new((x + r * (0.93 if i % 2 else 1.0) * math.cos(2 * PI * i / n), -zc + r * (0.93 if i % 2 else 1.0) * math.sin(2 * PI * i / n),
                                   y0 + (y1 - y0) * t)) for i in range(n)])
    for a, b in zip(rows, rows[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("shaft")
    bm.to_mesh(me)
    bm.free()
    return keep(_mesh_ob(me, m, "shaft", 50))


def column(x, yb, yt, zc, m):
    bx(0.4, 0.1, 0.4, x, yb + 0.05, zc, m, bev=0.02)
    to(0.155, 0.04, x, yb + 0.14, zc, m, rot=(PI / 2, 0, 0), segs=(20, 6))
    fluted(x, yb + 0.15, yt - 0.17, zc, 0.15, 0.13, m)
    to(0.135, 0.02, x, yt - 0.19, zc, m, rot=(PI / 2, 0, 0), segs=(16, 5))
    cy(0.19, 0.135, 0.09, x, yt - 0.125, zc, m, segs=16)
    bx(0.42, 0.08, 0.42, x, yt - 0.04, zc, m, bev=0.015)


def bank():
    X = 28.0
    wall, stone, stone_d = C("bank"), C("#ddd6c4"), C("#a89f8a")
    bronze, brass = GL("#5a4630", 0.45), BRASS
    door = (27.3, 28.7, 0.24, 3.2, 0.3)
    wins = [(26.22, 26.68, 1.62, 3.08, 0.16), (29.32, 29.78, 1.62, 3.08, 0.16)]
    blk = block(5.0, 7.0, 7.0, (X, 3.5, -10.5), wall, [door] + wins, seed=5)
    tree = bvh(blk)

    # stylobate step and four engaged Doric columns
    bx(4.92, 0.3, 0.66, X, 0.15, FZ + 0.31, stone_d, bev=0.035)
    for cxk in (25.95, 26.95, 29.05, 30.05):
        column(cxk, 0.3, 3.51, -6.8, stone)
    # entablature: architrave, frieze with the BANK tablet, dentil cornice, pediment with a clock
    bx(4.72, 0.28, 0.46, X, 3.65, FZ + 0.21, stone, bev=0.02)
    bx(4.72, 0.89, 0.36, X, 4.235, FZ + 0.16, wall, bev=0.02)
    bx(4.0, 0.7, 0.06, X, 4.2, -6.635, C("sign_white"), bev=0.018)
    frame(X - 2.0, X + 2.0, 3.85, 4.55, 0.04, BRONZE, z0=-6.66, z1=-6.59, ov=0.015)
    letters("BANK", 0.36, (X, 4.2, -6.605 + 0.0095), C("black"), fit=3.6)
    for k in range(27):
        bx(0.08, 0.1, 0.16, 25.66 + k * 0.18, 4.63, -6.59, stone, bev=0.012, segs=1)
    bx(5.0, 0.24, 0.62, X, 4.8, FZ + 0.29, stone, bev=0.035)
    by, apex = 4.92, 5.8
    plate([(-2.4, 0.0), (2.4, 0.0), (0.0, apex - by)], 0.32, (X, by, -6.85), wall)
    a = math.atan2(apex - by, 2.4)
    for s in (-1, 1):
        mx, my = X + s * 1.2, by + (apex - by) / 2
        bx(2.82, 0.2, 0.56, mx, my + 0.1 / math.cos(a), FZ + 0.26, stone, bev=0.03, rot=(0, 0, -s * a))
    cz = -6.66
    cy(0.2, 0.2, 0.03, X, 5.2, cz, C("sign_white"), rot=(PI / 2, 0, 0), segs=24)
    to(0.205, 0.026, X, 5.2, cz + 0.012, BRONZE, segs=(24, 6))
    for k in range(12):
        t = 2 * PI * k / 12
        bx(0.018, 0.06 if k % 3 == 0 else 0.04, 0.008, X + 0.16 * math.sin(t), 5.2 + 0.16 * math.cos(t), cz + 0.02, C("black"), bev=0, rot=(0, 0, -t))
    for t, L, wd in ((-PI / 3, 0.1, 0.024), (PI / 3, 0.15, 0.016)):
        bx(wd, L, 0.008, X + math.sin(t) * L / 2, 5.2 + math.cos(t) * L / 2, cz + 0.03, C("black"), bev=0, rot=(0, 0, -t))
    cy(0.018, 0.018, 0.02, X, 5.2, cz + 0.03, brass, rot=(PI / 2, 0, 0), segs=10)
    # top: frieze band, modillions, heavy cornice, balustrade
    bx(5.0, 0.3, 0.06, X, 6.28, FZ + 0.02, stone, bev=0.015)
    for k in range(12):
        bx(0.12, 0.12, 0.3, 25.75 + k * 0.405, 6.49, FZ + 0.16, stone, bev=0.02)
    bx(5.12, 0.18, 0.62, X + 0.06, 6.64, FZ + 0.29, stone, bev=0.035)
    bx(5.18, 0.12, 0.68, X + 0.09, 6.79, FZ + 0.31, stone, bev=0.03)
    zb_ = FZ - 0.12
    bx(5.0, 0.1, 0.34, X, 7.05, zb_, stone, bev=0.02)
    dies = (25.66, X, 30.34)
    for xd in dies:
        bx(0.3, 0.42, 0.38, xd, 7.31, zb_, stone, bev=0.03)
    for k in range(1, 20):
        x = 25.66 + 0.2335 * k
        if min(abs(x - xd) for xd in dies) > 0.2:
            lathe(BALUSTER, (x, 7.1, zb_), stone, segs=8)
    bx(5.04, 0.08, 0.38, X, 7.56, zb_, stone, bev=0.02)
    for sx in (-1, 1):
        bx(0.2, 0.2, 6.7, X + sx * 2.4, 7.09, -10.64, wall, bev=0.04)
    bx(4.6, 0.2, 0.2, X, 7.09, -13.9, wall, bev=0.04)
    bx(4.62, 0.04, 6.5, X, 7.01, -10.55, TAR, bev=0.015, segs=1)
    roof_ac(29.2, 7.0, -11.8)
    vent(26.5, 7.0, -12.6, 0.5)

    # heavy bronze double door with a transom, stone surround and keystone
    zr = FZ - 0.3
    bx(1.46, 0.36, 0.38, X, 0.12, FZ - 0.14, stone_d, bev=0.02)
    for sx in (-1, 1):
        lx = X + sx * 0.345
        bx(0.68, 2.34, 0.07, lx, 1.47, zr + 0.045, bronze, bev=0.012)
        bx(0.5, 0.84, 0.03, lx, 2.06, zr + 0.09, bronze, bev=0.015)
        bx(0.5, 0.8, 0.03, lx, 0.84, zr + 0.09, bronze, bev=0.015)
        bx(0.28, 0.48, 0.012, lx, 2.06, zr + 0.11, DARK_GLASS, bev=0)
        tube([(X + sx * 0.08, 1.0, zr + 0.16), (X + sx * 0.08, 1.5, zr + 0.16)], 0.02, brass, bres=2)
        for yy in (1.04, 1.46):
            cy(0.01, 0.01, 0.06, X + sx * 0.08, yy, zr + 0.125, brass, rot=(PI / 2, 0, 0), segs=6)
    bx(1.4, 0.06, 0.08, X, 2.67, zr + 0.04, bronze, bev=0.01)
    bx(1.38, 0.5, 0.012, X, 2.94, zr + 0.03, DARK_GLASS, bev=0)
    for k in range(5):
        cy(0.01, 0.01, 0.48, X - 0.56 + k * 0.28, 2.94, zr + 0.055, BRONZE, segs=6, cap=False)
    frame(27.3, 28.7, 0.3, 3.2, 0.14, stone, sill=False)
    plate([(-0.13, 0.15), (0.13, 0.15), (0.09, -0.15), (-0.09, -0.15)], 0.16, (X, 3.27, FZ + 0.07), stone, bevel=0.01)

    # tall narrow side windows with bronze grilles
    for (a_, b_, y0, y1, dep) in wins:
        cx = (a_ + b_) / 2
        bx(b_ - a_, y1 - y0, 0.015, cx, (y0 + y1) / 2, FZ - dep + 0.02, DARK_GLASS, bev=0)
        for k in range(3):
            cy(0.011, 0.011, y1 - y0, a_ + (k + 1) * (b_ - a_) / 4, (y0 + y1) / 2, FZ - 0.04, BRONZE, segs=6, cap=False)
        for yy in (y0 + 0.5, y0 + 1.0):
            bx(b_ - a_, 0.03, 0.014, cx, yy, FZ - 0.04, BRONZE, bev=0)
        bx(b_ - a_ + 0.18, 0.07, 0.16, cx, y0 - 0.035, FZ + 0.05, stone, bev=0.02)
        frame(a_, b_, y0, y1, 0.05, stone, z0=FZ - 0.03, z1=FZ + 0.03, sill=False)
        bx(b_ - a_ + 0.14, 0.14, 0.08, cx, y1 + 0.07, FZ + 0.02, stone, bev=0.02)
        bx(0.1, 0.18, 0.1, cx, y1 + 0.08, FZ + 0.035, stone, bev=0.015)

    # night-deposit slot under the right window
    alu = ck.metal("alu", 0.35)
    nx = 29.55
    bx(0.36, 0.36, 0.05, nx, 1.18, FZ + 0.015, alu, bev=0.012)
    bx(0.27, 0.12, 0.03, nx, 1.22, FZ + 0.05, alu, bev=0.01)
    bx(0.2, 0.022, 0.01, nx, 1.25, FZ + 0.066, C("black"), bev=0)
    tube([(nx - 0.08, 1.185, FZ + 0.085), (nx + 0.08, 1.185, FZ + 0.085)], 0.011, alu)
    bx(0.42, 0.035, 0.1, nx, 1.385, FZ + 0.04, alu, bev=0.012)
    for sx in (-0.14, 0.14):
        for yy in (1.04, 1.32):
            sp(0.012, nx + sx, yy, FZ + 0.042, alu, segs=6, rings=4)
    # security camera on a bracket
    cam = alu
    tube([(30.36, 3.3, FZ + 0.01), (30.36, 3.3, FZ + 0.2)], 0.015, cam)
    bx(0.11, 0.1, 0.24, 30.36, 3.24, FZ + 0.26, cam, bev=0.025, rot=(-0.35, 0, 0))
    cy(0.03, 0.03, 0.03, 30.36, 3.2, FZ + 0.385, C("black"), rot=(PI / 2 - 0.35, 0, 0), segs=10)

    # east side (seen in the gap to the precinct): plinth, downspout
    bx(0.1, 0.55, 7.0, 30.53, 0.275, -10.5, stone_d, bev=0.03)
    downspout(30.6, -7.4, 6.4, GL("#6a9a8a", 0.5), 30.5)

    # grime and age
    g = shade("bank", 0.82)
    for (a_, b_, y0, y1, dep) in wins:
        streak((a_ + b_) / 2 + R(-0.06, 0.06), y0 - 0.075, R(0.35, 0.55), 0.08, g, tree)
    for x in (25.7, 27.4, 28.7, 30.3):
        streak(x + R(-0.05, 0.05), 6.12, R(0.35, 0.8), R(0.06, 0.1), g, tree)
    streak(30.35, 3.18, 0.5, 0.05, g, tree)
    smudge(26.45, 1.1, 0.35, 0.22, g, tree)
    plate([(-2.46, 0.0), (2.46, 0.0)] + [(2.46 - 4.92 * k / 16, 0.07 + R(0.0, 0.06)) for k in range(17)], 0.004, (X, 0.1, -6.358),
          C(shade("#a89f8a", 0.82)))
    return finish("Bank", (X, 0.0, -10.5))


# ================================================================== LIQUOR
def liquor_goods(a, b, yf, zb):
    """Bottles on three levels: wine, whiskey, vodka, gin."""
    kinds = [  # (body colour, profile)
        (GL("#24402a", 0.2), [(0.036, 0.0), (0.038, 0.01), (0.038, 0.19), (0.03, 0.235), (0.013, 0.26), (0.013, 0.33)]),
        (GL("#4a1820", 0.2), [(0.036, 0.0), (0.038, 0.01), (0.038, 0.19), (0.03, 0.235), (0.013, 0.26), (0.013, 0.33)]),
        (GL("#a8601e", 0.2), [(0.05, 0.0), (0.052, 0.01), (0.052, 0.17), (0.04, 0.2), (0.016, 0.22), (0.016, 0.27)]),
        (GL("#c8d4d4", 0.2), [(0.042, 0.0), (0.044, 0.01), (0.044, 0.2), (0.022, 0.25), (0.014, 0.27), (0.014, 0.31)]),
        (GL("#2a4a8a", 0.2), [(0.046, 0.0), (0.048, 0.01), (0.048, 0.18), (0.03, 0.22), (0.015, 0.24), (0.015, 0.29)]),
    ]
    label, gold = C("cream"), BRASS
    for lvl, y in enumerate((yf, 1.385, 1.885)):
        n = int((b - a) / 0.12)
        for i in range(n):
            body, prof = kinds[(i // 2 + lvl * 2) % len(kinds)]
            x = a + 0.06 + i * (b - a - 0.12) / (n - 1) + R(-0.005, 0.005)
            z = zb + (0.1 if (i + lvl) % 2 else 0.16)
            lathe(prof, (x, y, z), body, segs=8)
            top = prof[-1][1]
            cy(prof[2][0] + 0.003, prof[2][0] + 0.003, 0.07, x, y + top * 0.35, z, label, segs=8)
            cy(prof[-1][0] + 0.003, prof[-1][0] + 0.003, 0.025, x, y + top + 0.008, z, gold if i % 2 else C("black"), segs=8)


def liquor():
    X = 43.5
    wall, trim, iron, paint, tile = C("liquor"), C("#4a3456"), IRON, PAINT, C("#3e3446", 0.7)
    door = (42.8, 44.2, -0.1, 2.42, 0.22)
    wins = [(41.0, 42.5, 0.86, 2.4, 0.3), (44.5, 46.0, 0.86, 2.4, 0.3)]
    ups = [(41.3, 42.2, 5.25, 6.15, 0.15), (44.8, 45.7, 5.25, 6.15, 0.15)]
    blk = block(6.0, 7.0, 7.0, (X, 3.5, -10.5), wall, [door] + wins + ups, seed=8)
    tree = bvh(blk)

    # storefront: fascia, bulkheads, bottle displays, neon, glass, heavy bars
    bx(5.5, 0.2, 0.12, 43.32, 2.6, FZ + 0.04, paint, bev=0.03)
    pink, cyan = ck.glow("pink", 2.5), ck.glow("cyan", 2.5)
    for i, (a, b, y0, y1, dep) in enumerate(wins):
        cx, wi, zb = (a + b) / 2, b - a, FZ - dep
        bx(wi + 0.1, y0 - 0.06, 0.05, cx, (y0 - 0.06) / 2, FZ + 0.01, tile, bev=0.02)
        bx(wi - 0.01, 0.04, dep - 0.03, cx, y0 + 0.02, FZ - dep / 2 - 0.015, C("#3a3040"), bev=0.01)
        bx(wi - 0.01, y1 - y0, 0.02, cx, (y0 + y1) / 2, zb + 0.012, C("#2a2228"), bev=0.005)
        for sy in (1.37, 1.87):
            bx(wi - 0.04, 0.03, 0.22, cx, sy, zb + 0.135, C("#5a4a3a"), bev=0.008)
        liquor_goods(a + 0.04, b - 0.04, y0 + 0.04, zb + 0.02)
        if i == 0:   # a neon bottle
            pts = [(-0.11, -0.3), (0.11, -0.3), (0.12, 0.05), (0.06, 0.15), (0.04, 0.24), (0.04, 0.33), (-0.04, 0.33), (-0.04, 0.24),
                   (-0.06, 0.15), (-0.12, 0.05)]
            neon(pts, cx, 1.62, FZ - 0.075, 0.013, pink, closed=True)
            neon([(-0.07, -0.08), (0.07, -0.08)], cx, 1.62, FZ - 0.075, 0.011, pink, smooth=False)
        else:        # a neon martini glass
            neon([(-0.2, 0.22), (0.0, -0.04), (0.2, 0.22)], cx, 1.66, FZ - 0.075, 0.013, cyan, closed=True, smooth=False)
            neon([(0.0, -0.04), (0.0, -0.3)], cx, 1.66, FZ - 0.075, 0.012, cyan, smooth=False)
            neon([(-0.12, -0.31), (0.12, -0.31)], cx, 1.66, FZ - 0.075, 0.012, cyan, smooth=False)
            sp(0.035, cx + 0.05, 1.79, FZ - 0.075, ck.glow("#7ad04a", 2.0), segs=10, rings=6)
        bx(wi, y1 - y0, 0.01, cx, (y0 + y1) / 2, FZ - 0.045, ck.glass("#3a3448", 0.22), bev=0)
        frame(a, b, y0, y1, 0.07, paint)
        nb = int(wi / 0.125)
        for k in range(nb):
            cy(0.016, 0.016, y1 - y0 + 0.06, a + 0.06 + k * (wi - 0.12) / (nb - 1), (y0 + y1) / 2, FZ + 0.085, iron, segs=6, cap=False)
        for yy in (y0 + 0.06, (y0 + y1) / 2, y1 - 0.06):
            bx(wi + 0.12, 0.05, 0.016, cx, yy, FZ + 0.085, iron, bev=0.005, segs=1)
        for sx in (a - 0.03, b + 0.03):
            for yy in (y0 + 0.06, y1 - 0.06):
                cy(0.022, 0.022, 0.03, sx, yy, FZ + 0.09, iron, rot=(PI / 2, 0, 0), segs=6)

    # door: threshold, jambs, glazed leaf with a grille, folded scissor gate
    zr = FZ - 0.22
    bx(1.46, 0.3, 0.34, X, 0.03, FZ - 0.1, C("curb"), bev=0.025)
    for sx in (-1, 1):
        bx(0.1, 2.3, 0.08, X + sx * 0.65, 1.27, zr + 0.04, paint, bev=0.01)
        bx(0.09, 2.16, 0.05, X + sx * 0.555, 1.27, zr + 0.05, paint, bev=0.012)
    bx(1.4, 0.1, 0.08, X, 2.37, zr + 0.04, paint, bev=0.01)
    bx(1.2, 0.09, 0.05, X, 2.28, zr + 0.05, paint, bev=0.012)
    bx(1.2, 0.3, 0.05, X, 0.33, zr + 0.05, paint, bev=0.012)
    bx(1.04, 1.86, 0.012, X, 1.39, zr + 0.035, DARK_GLASS, bev=0)
    for k in range(7):
        cy(0.011, 0.011, 1.84, X - 0.45 + k * 0.15, 1.39, zr + 0.085, iron, segs=6, cap=False)
    for yy in (0.62, 1.39, 2.16):
        bx(1.06, 0.035, 0.012, X, yy, zr + 0.085, iron, bev=0)
    for k in range(9):
        bx(0.025, 2.2, 0.03, 42.9 + k * 0.022 + R(-0.003, 0.003), 1.3, FZ - 0.06 + (k % 2) * 0.03, iron, bev=0.006, segs=1)
    bx(0.3, 0.05, 0.1, 42.99, 2.42, FZ - 0.04, iron, bev=0.01)
    frame(42.8, 44.2, 0.18, 2.42, 0.07, paint, sill=False)
    bx(0.12, 0.16, 0.05, X, 3.0, FZ + 0.02, iron, bev=0.01)
    cy(0.07, 0.07, 0.14, X, 2.92, FZ + 0.1, C("cream"), rot=(PI / 2 - 0.5, 0, 0), segs=10)
    for k in range(4):
        to(0.075, 0.006, X, 2.92 - 0.03 * k * math.sin(0.5), FZ + 0.06 + 0.03 * k * math.cos(0.5), iron, rot=(-0.5, 0, 0), segs=(12, 3))
    tube([(X + 0.03, 3.08, FZ + 0.02), (X + 0.03, 3.6, FZ + 0.02), (X + 0.9, 3.6, FZ + 0.02)], 0.012, iron)

    # the sign: red neon letters on the white board, a cyan tube around it
    bx(4.8, 0.7, 0.1, X, 4.2, -6.95, C("sign_white"), bev=0.025)
    letters("LIQUOR", 0.36, (X, 4.2, -6.9 + 0.0095), ck.glow("#b8102a", 1.2), fit=4.3)
    path = rrect(4.6, 0.52, 0.07, 3)
    neon(path, X, 4.2, -6.86, 0.02, cyan, closed=True, smooth=False)
    for px, py in path[::3]:
        cy(0.009, 0.009, 0.04, X + px, 4.2 + py, -6.885, C("curb"), rot=(PI / 2, 0, 0), segs=6)
    for sx in (-2.2, 2.2):
        bx(0.05, 0.05, 0.06, X + sx, 4.6, -6.95, iron, bev=0.01, segs=1)

    # upper floor: one window boarded up, one with a tired blind
    for i, (a, b, y0, y1, dep) in enumerate(ups):
        cx = (a + b) / 2
        bx(b - a + 0.16, 0.07, 0.16, cx, y0 - 0.035, FZ + 0.05, trim, bev=0.02)
        bx(b - a + 0.12, 0.12, 0.07, cx, y1 + 0.06, FZ + 0.02, trim, bev=0.02)
        frame(a, b, y0, y1, 0.05, trim, z0=FZ - 0.03, z1=FZ + 0.03, sill=False)
        if i == 0:
            bx(b - a + 0.06, y1 - y0 + 0.06, 0.04, cx, (y0 + y1) / 2, FZ + 0.025, C("board"), bev=0.012)
            for s in (-1, 1):
                bx(1.16, 0.17, 0.035, cx, (y0 + y1) / 2 + s * 0.18, FZ + 0.065, C("board_light"), bev=0.01, rot=(0, 0, s * 0.3))
            for s in (-1, 1):
                for t in (-0.42, 0.42):
                    sp(0.012, cx + t * math.cos(0.3), (y0 + y1) / 2 + s * 0.18 + s * t * math.sin(0.3), FZ + 0.085, iron, segs=6, rings=4)
        else:
            bx(b - a, y1 - y0, 0.02, cx, (y0 + y1) / 2, FZ - dep + 0.02, DARK_GLASS, bev=0)
            frame(a + 0.05, b - 0.05, y0 + 0.05, y1 - 0.05, 0.05, trim, z0=FZ - dep + 0.03, z1=FZ - dep + 0.08, ov=0.0)
            bx(b - a - 0.14, 0.5, 0.01, cx, y1 - 0.3, FZ - dep + 0.09, C("#d8cca8"), bev=0.004, rot=(0, 0, 0.04))

    dish = C("cream")
    tube([(46.0, 5.7, FZ + 0.02), (46.0, 5.7, -6.75)], 0.02, iron)
    bx(0.08, 0.2, 0.03, 46.0, 5.7, FZ + 0.012, iron, bev=0.008, segs=1)
    sp(0.26, 46.0, 5.78, -6.6, dish, scale=(1.0, 1.0, 0.32), rot=(-0.5, -0.5, 0), segs=16, rings=8)
    tube([(46.0, 5.62, -6.58), (45.86, 5.9, -6.37)], 0.01, iron)
    sp(0.035, 45.86, 5.91, -6.36, C("#7a7a74"), segs=8, rings=6)

    # cornice: corbel band, cap, parapet with a metal coping
    for k in range(14):
        bx(0.18, 0.1, 0.09, 40.85 + k * 0.405, 6.55, FZ + 0.035, trim, bev=0.015, segs=1)
    bx(6.0, 0.14, 0.18, X, 6.72, FZ + 0.07, trim, bev=0.03)
    bx(6.0, 0.36, 0.26, X, 7.0, FZ - 0.1, wall, bev=0.04)
    bx(6.06, 0.05, 0.32, X, 7.205, FZ - 0.1, GALV, bev=0.015)
    for sx in (-1, 1):
        bx(0.2, 0.2, 6.72, X + sx * 2.9, 7.1, -10.62, wall, bev=0.04)
    bx(5.6, 0.2, 0.2, X, 7.1, -13.9, wall, bev=0.04)
    bx(5.62, 0.04, 6.56, X, 7.01, -10.54, TAR, bev=0.015, segs=1)
    roof_ac(44.6, 7.0, -12.0)
    vent(42.0, 7.0, -11.0)

    # grime, rust, old posters
    g, rust = shade("liquor", 0.75), "#5a3a2a"
    for (a, b, y0, y1, dep) in wins:
        for k in range(3):
            streak(a + 0.2 + k * 0.55 + R(-0.05, 0.05), y1 + 0.17, R(0.12, 0.2), R(0.03, 0.05), rust, tree)
    for (a, b, y0, y1, dep) in ups:
        streak((a + b) / 2 + R(-0.2, 0.2), y0 - 0.075, R(0.5, 0.9), 0.09, g, tree)
    streak(41.2, 3.84, 0.5, 0.08, g, tree)
    streak(45.6, 3.84, 0.42, 0.07, g, tree)
    for i, (px, py, w_, h_, col, rz) in enumerate(((40.7, 1.45, 0.3, 0.42, "#e8dca0", 0.05), (40.72, 1.05, 0.26, 0.3, "#f4f0e6", -0.08),
                                                    (40.68, 1.8, 0.24, 0.2, "#d8a8b8", 0.12))):
        pts = [(-w_ / 2, h_ / 2), (w_ / 2, h_ / 2)] + [(w_ / 2 - w_ * k / 5, -h_ / 2 + R(0.0, 0.07)) for k in range(6)]
        conform(plate(pts, 0.003, (px, py, FZ + 0.03), C(col), rot=(0, 0, rz)), tree, off=0.004 + 0.003 * i)
    smudge(43.5, 0.3, 1.2, 0.3, g, tree)
    return finish("Liquor", (X, 0.0, -10.5))


# ================================================================== PRECINCT 9
SHIELD = [(0.0, 0.5), (0.1, 0.43), (0.22, 0.47), (0.35, 0.42), (0.5, 0.47), (0.49, 0.3), (0.47, 0.1), (0.43, -0.1), (0.36, -0.27),
          (0.25, -0.41), (0.12, -0.5), (0.0, -0.56)]


def shield_pts(s):
    return [(x * s, y * s) for x, y in SHIELD + [(-x, y) for x, y in reversed(SHIELD[1:-1])]]


def bench(cx, cz, wood, iron):
    y0 = 0.12
    for dz in (-0.14, 0.0, 0.14):
        bx(1.4, 0.035, 0.11, cx, y0 + 0.43, cz + dz, wood, bev=0.012)
    for yy in (0.66, 0.82):
        bx(1.4, 0.1, 0.03, cx, y0 + yy, cz - 0.25 - (yy - 0.66) * 0.12, wood, bev=0.012, rot=(-0.12, 0, 0))
    for sx in (-0.57, 0.57):
        x = cx + sx
        tube([(x, y0, cz + 0.2), (x, y0 + 0.41, cz + 0.2), (x, y0 + 0.6, cz + 0.22), (x, y0 + 0.63, cz + 0.02)], 0.02, iron, smooth=True)
        tube([(x, y0, cz - 0.17), (x, y0 + 0.41, cz - 0.2), (x, y0 + 0.97, cz - 0.3)], 0.02, iron, smooth=True)
        tube([(x, y0 + 0.41, cz + 0.22), (x, y0 + 0.41, cz - 0.22)], 0.018, iron)


def precinct():
    X = 36.0
    wall, base, stone, navy = C("precinct"), C("#46526a"), C("#b8b8ae"), C("precinct_sign")
    stone2, iron = C("#a8a8a0"), IRON
    door = (34.9, 37.1, 0.6, 3.42, 0.35)
    gwin = [(32.1, 33.4, 1.3, 2.8, 0.2), (38.6, 39.9, 1.3, 2.8, 0.2)]
    uwin = [(32.2, 33.3, 3.85, 4.7, 0.18), (38.7, 39.8, 3.85, 4.7, 0.18)]
    blk = block(9.0, 8.0, 8.0, (X, 4.0, -11.0), wall, [door] + gwin + uwin, seed=13)
    tree = bvh(blk)

    # base course, quoins, string course
    for (a, b) in ((31.5, 34.6), (37.4, 40.5)):
        bx(b - a, 0.9, 0.1, (a + b) / 2, 0.45, FZ + 0.03, base, bev=0.035)
    bx(0.1, 0.9, 8.08, 31.47, 0.45, -10.96, base, bev=0.035)
    for k in range(15):
        y = 0.95 + k * 0.405 + 0.18
        wq, dq = (0.45, 0.28) if k % 2 == 0 else (0.28, 0.45)
        m = stone if k % 3 else stone2
        bx(wq + 0.04, 0.36, dq + 0.05, 31.46 + (wq + 0.04) / 2, y, FZ - dq / 2 + 0.025, m, bev=0.03)
        bx(wq, 0.36, 0.1, 40.5 - wq / 2, y, FZ + 0.0, stone2 if k % 3 else stone, bev=0.03)
    bx(9.0, 0.12, 0.08, X, 3.56, FZ + 0.0, stone, bev=0.02)

    # entrance: stone surround, double doors, transom
    for px in (34.73, 37.27):
        bx(0.26, 2.72, 0.16, px, 2.08, FZ + 0.06, stone, bev=0.03)
    bx(3.3, 0.42, 0.22, X, 3.63, FZ + 0.1, stone, bev=0.03)
    bx(3.44, 0.08, 0.3, X, 3.88, FZ + 0.13, stone, bev=0.025)
    zr = FZ - 0.35
    bx(2.24, 0.15, 0.42, X, 0.66, FZ - 0.16, C("curb"), bev=0.02)
    brass = BRASS
    for sx in (-1, 1):
        lx = X + sx * 0.53
        bx(0.1, 2.22, 0.06, X + sx * 0.98, 1.85, zr + 0.05, navy, bev=0.012)
        bx(0.1, 2.22, 0.06, X + sx * 0.08, 1.85, zr + 0.05, navy, bev=0.012)
        bx(1.0, 0.1, 0.06, lx, 2.91, zr + 0.05, navy, bev=0.012)
        bx(1.0, 0.32, 0.06, lx, 0.9, zr + 0.05, navy, bev=0.012)
        bx(0.86, 1.86, 0.012, lx, 1.92, zr + 0.035, DARK_GLASS, bev=0)
        bx(0.86, 0.06, 0.05, lx, 1.42, zr + 0.06, navy, bev=0.01)
        bx(0.07, 0.34, 0.008, X + sx * 0.08, 1.6, zr + 0.085, brass, bev=0)
        bx(0.8, 0.2, 0.008, lx, 0.88, zr + 0.083, brass, bev=0)
    for sx in (-1, 1):
        bx(0.08, 2.84, 0.36, X + sx * 1.06, 2.0, FZ - 0.17, navy, bev=0.01)
    bx(2.2, 0.08, 0.36, X, 3.38, FZ - 0.17, navy, bev=0.01)
    bx(0.07, 2.22, 0.07, X, 1.85, zr + 0.06, navy, bev=0.01)
    bx(2.2, 0.08, 0.07, X, 3.0, zr + 0.05, navy, bev=0.012)
    bx(2.2, 0.38, 0.012, X, 3.21, zr + 0.035, DARK_GLASS, bev=0)
    for k in range(3):
        bx(0.05, 0.38, 0.05, X - 0.55 + k * 0.55, 3.21, zr + 0.05, navy, bev=0.01, segs=1)
    bx(1.6, 0.025, 0.8, X, 0.735, -6.55, C("#3a3a3e"), bev=0.008)

    # blue globe lamps: wall plates and wrought arms (the globes are their own object)
    for gx in (34.2, 37.8):
        bx(0.13, 0.62, 0.03, gx, 2.42, FZ + 0.012, iron, bev=0.01)
        tube([(gx, 2.62, FZ + 0.02), (gx, 2.62, -6.45)], 0.022, iron, bres=2)
        tube([(gx, 2.15, FZ + 0.02), (gx, 2.2, -6.82), (gx, 2.42, -6.6), (gx, 2.6, -6.55)], 0.016, iron, smooth=True)
        to(0.05, 0.012, gx, 2.27, -6.86, iron, rot=(0, PI / 2, 0), segs=(12, 4))
        cy(0.1, 0.055, 0.1, gx, 2.71, -6.45, iron, segs=14)
        cy(0.06, 0.06, 0.04, gx, 3.3, -6.45, iron, segs=10)
        cy(0.0, 0.025, 0.09, gx, 3.36, -6.45, iron, segs=8)

    # ground-floor windows: stone sill and lintel, bars; blinds in one
    for i, (a, b, y0, y1, dep) in enumerate(gwin):
        cx = (a + b) / 2
        bx(b - a, y1 - y0, 0.015, cx, (y0 + y1) / 2, FZ - dep + 0.02, DARK_GLASS, bev=0)
        frame(a, b, y0, y1, 0.06, navy, z0=FZ - 0.06, z1=FZ + 0.03)
        bx(b - a + 0.22, 0.08, 0.2, cx, y0 - 0.04, FZ + 0.07, stone, bev=0.025)
        bx(b - a + 0.2, 0.16, 0.09, cx, y1 + 0.08, FZ + 0.02, stone, bev=0.02)
        if i == 0:
            for k in range(11):
                bx(b - a - 0.04, 0.03, 0.01, cx, y1 - 0.06 - k * 0.065, FZ - dep + 0.045, C("cream"), bev=0.004, segs=1, rot=(0.35, 0, 0))
        nb = 9
        for k in range(nb):
            cy(0.017, 0.017, y1 - y0 + 0.04, a + 0.08 + k * (b - a - 0.16) / (nb - 1), (y0 + y1) / 2, FZ + 0.1, iron, segs=6, cap=False)
        for yy in (y0 + 0.12, y1 - 0.12):
            bx(b - a + 0.06, 0.045, 0.016, cx, yy, FZ + 0.1, iron, bev=0.005, segs=1)
            for sx in (a - 0.02, b + 0.02):
                cy(0.022, 0.022, 0.1, sx, yy, FZ + 0.05, iron, rot=(PI / 2, 0, 0), segs=6)

    # upper windows: sill, keystone lintel; blinds left, a window AC unit right
    for i, (a, b, y0, y1, dep) in enumerate(uwin):
        cx = (a + b) / 2
        bx(b - a, y1 - y0, 0.015, cx, (y0 + y1) / 2, FZ - dep + 0.02, DARK_GLASS, bev=0)
        frame(a + 0.04, b - 0.04, y0 + 0.04, y1 - 0.04, 0.05, navy, z0=FZ - dep + 0.03, z1=FZ - dep + 0.08, ov=0.0)
        bx(b - a + 0.2, 0.07, 0.18, cx, y0 - 0.035, FZ + 0.06, stone, bev=0.02)
        bx(b - a + 0.18, 0.14, 0.08, cx, y1 + 0.07, FZ + 0.02, stone, bev=0.02)
        frame(a, b, y0, y1, 0.07, stone, z0=FZ - 0.03, z1=FZ + 0.035, sill=False)
        bx(0.12, 0.2, 0.1, cx, y1 + 0.08, FZ + 0.04, stone, bev=0.015)
        if i == 0:
            for k in range(8):
                bx(b - a - 0.1, 0.028, 0.01, cx, y1 - 0.1 - k * 0.062, FZ - dep + 0.09, C("cream"), bev=0.004, segs=1, rot=(0.35, 0, 0))
            bx(b - a - 0.08, 0.03, 0.02, cx, y1 - 0.1 - 8 * 0.062, FZ - dep + 0.09, stone, bev=0.006, segs=1)
        else:
            ac = C("#d8d4c4")
            bx(0.72, 0.44, 0.6, cx, y0 + 0.22, FZ + 0.08, ac, bev=0.035)
            for k in range(5):
                bx(0.6, 0.026, 0.012, cx, y0 + 0.08 + k * 0.07, FZ + 0.386, C("#8a8a84"), bev=0)
            for sx in (-0.24, 0.24):
                tube([(cx + sx, y0 + 0.01, -6.7), (cx + sx, y0 - 0.38, FZ + 0.01)], 0.014, iron)
                bx(0.03, 0.42, 0.012, cx + sx * 1.48, y0 + 0.3, FZ - dep + 0.06, ac, bev=0)
            streak(cx + 0.12, y0 - 0.08, 0.85, 0.1, shade("precinct", 0.8), tree)

    # sign board in a stone frame, the lettering, a police shield above
    bx(6.5, 0.9, 0.12, X, 5.6, -6.94, navy, bev=0.03)
    frame(X - 3.25, X + 3.25, 5.15, 6.05, 0.12, stone, z0=-7.02, z1=-6.85, ov=0.02)
    letters("POLICE  \u00b7  PRECINCT 9", 0.4, (X, 5.6, -6.88 + 0.0095), C("sign_white"), fit=6.0)
    gold = ck.metal("gold", 0.3)
    sy = 6.68
    plate(shield_pts(0.78), 0.06, (X, sy, FZ + 0.025), gold, bevel=0.012)
    plate([(x, y - 0.015) for x, y in shield_pts(0.64)], 0.02, (X, sy, FZ + 0.06), navy, bevel=0.005)
    plate(star(0.17, 0.072), 0.02, (X, sy - 0.03, FZ + 0.078), gold, bevel=0.005)
    for s in (-1, 1):
        sp(0.02, X + s * 0.25, sy + 0.22, FZ + 0.072, gold, segs=8, rings=6)
    sp(0.02, X, sy - 0.33, FZ + 0.072, gold, segs=8, rings=6)

    # cornice on modillions, parapet with a raised centre
    for k in range(15):
        bx(0.12, 0.16, 0.3, 31.8 + k * 0.6, 7.26, FZ + 0.15, stone, bev=0.025)
    bx(9.3, 0.22, 0.48, X, 7.45, FZ + 0.22, stone, bev=0.035)
    bx(9.36, 0.14, 0.54, X, 7.63, FZ + 0.24, stone, bev=0.03)
    for (a, b, top) in ((31.5, 34.5, 8.2), (34.5, 37.5, 8.55), (37.5, 40.5, 8.2)):
        bx(b - a, top - 7.7, 0.3, (a + b) / 2, (top + 7.7) / 2, FZ - 0.12, wall, bev=0.04)
        bx(b - a + 0.06, 0.08, 0.38, (a + b) / 2, top + 0.04, FZ - 0.12, stone, bev=0.025)
    for sx in (-1, 1):
        bx(0.22, 0.3, 7.7, X + sx * 4.39, 8.15, -11.15, wall, bev=0.04)
    bx(8.56, 0.3, 0.22, X, 8.15, -14.89, wall, bev=0.04)
    bx(8.58, 0.04, 7.52, X, 8.01, -11.03, TAR, bev=0.015, segs=1)
    roof_ac(33.8, 8.0, -11.5)
    roof_ac(35.4, 8.0, -12.6)
    vent(37.6, 8.0, -10.4)
    m_ = GALV
    cy(0.035, 0.05, 3.2, 39.0, 9.6, -13.2, m_, segs=8)
    for yy, L in ((10.35, 0.9), (10.85, 0.6)):
        cy(0.012, 0.012, L, 39.0, yy, -13.2, m_, rot=(0, 0, PI / 2), segs=6)
    sp(0.05, 39.0, 11.24, -13.2, ck.glow("red", 1.5), segs=10, rings=6)
    for gx, gz in ((38.0, -12.6), (39.9, -12.5), (39.0, -14.3)):
        tube([(39.0, 10.0, -13.2), (gx, 8.0, gz)], 0.006, C("black"), bres=0)

    # flagpole stub, bench, AC condenser, downspout
    bx(0.12, 0.2, 0.04, 32.3, 6.42, FZ + 0.015, iron, bev=0.01)
    cy(0.045, 0.045, 0.14, 32.3, 6.5, -6.93, iron, rot=(PI / 4, 0, 0), segs=10)
    cy(0.022, 0.026, 1.0, 32.3, 6.8, -6.62, ck.metal("alu", 0.35), rot=(PI / 4, 0, 0), segs=8)
    sp(0.055, 32.3, 7.16, -6.26, gold, segs=12, rings=8)
    bench(32.6, -6.6, C("board_light"), iron)
    body = C("#b8b6aa")
    bx(0.96, 0.08, 0.76, 39.6, 0.16, -6.6, C("concrete"), bev=0.02)
    bx(0.82, 0.66, 0.62, 39.6, 0.53, -6.6, body, bev=0.035)
    for k in range(6):
        bx(0.7, 0.02, 0.006, 39.6, 0.3 + k * 0.085, -6.287, C("#8a8a84"), bev=0)
    cy(0.21, 0.21, 0.012, 39.6, 0.865, -6.6, IRON, segs=16)
    to(0.21, 0.018, 39.6, 0.872, -6.6, C("#7a7a74"), rot=(PI / 2, 0, 0), segs=(20, 6))
    bx(0.42, 0.012, 0.02, 39.6, 0.875, -6.6, C("#7a7a74"), bev=0)
    bx(0.02, 0.012, 0.42, 39.6, 0.875, -6.6, C("#7a7a74"), bev=0)
    tube([(39.3, 0.62, -6.9), (39.3, 0.62, FZ + 0.04), (39.3, 1.15, FZ + 0.04)], 0.022, C("black"))
    downspout(31.4, -7.42, 7.05, PIPE, 31.5)

    # grime, patching, age
    g = shade("precinct", 0.8)
    for (a, b, y0, y1, dep) in gwin:
        for sx in (a + 0.2, b - 0.25):
            streak(sx + R(-0.05, 0.05), y0 - 0.085, R(0.15, 0.3), R(0.06, 0.09), g, tree)
    streak(32.75 + 0.2, 3.775, 0.55, 0.08, g, tree)
    for gx in (34.2, 37.8):
        streak(gx + 0.02, 2.1, 0.32, 0.1, g, tree)
    for x in (32.9, 35.0, 37.1, 39.2):
        streak(x + R(-0.1, 0.1), 7.15, R(0.25, 0.5), R(0.06, 0.1), g, tree)
    smudge(37.4, 4.55, 0.8, 0.32, shade("precinct", 1.06), tree)
    smudge(33.9, 4.2, 0.5, 0.3, shade("precinct", 1.06), tree)
    return finish("Precinct9", (X, 0.0, -11.0))


def precinct_steps():
    curb, curb2, iron = C("curb"), C("#c0bcae"), IRON
    for k in range(3):
        st = bx(5.0, 0.18 * (k + 1), 0.62, 36.0, 0.09 * (k + 1), -(3.6 + 0.6 * k), curb if k % 2 == 0 else curb2, bev=0.035)
        ck.lumpy(st, 0.003, 3.0, seed=k)
    st = bx(5.0, 0.72, 1.95, 36.0, 0.36, -6.065, curb2, bev=0.035)
    ck.lumpy(st, 0.003, 3.0, seed=4)
    tube([(34.5, 0.36, -4.25), (34.66, 0.36, -4.21), (34.8, 0.36, -4.27), (35.0, 0.36, -4.22), (35.12, 0.36, -4.26)], 0.006, C("crack"), bres=0)

    def tread(z):
        return 0.18 if z > -3.89 else 0.36 if z > -4.49 else 0.54 if z > -5.09 else 0.72

    def rail(z):
        return 1.09 + (min(-3.42 - z, 1.73) / 1.73) * 0.51
    for x in (33.62, 38.38):
        tube([(x, rail(-3.42), -3.42), (x, rail(-5.15), -5.15), (x, rail(-5.15), -6.97)], 0.025, iron, bres=2)
        for z, r in ((-3.42, 0.03), (-4.3, 0.02), (-5.15, 0.022), (-6.95, 0.022)):
            cy(r, r, rail(z) - tread(z), x, (rail(z) + tread(z)) / 2, z, iron, segs=8)
        sp(0.045, x, rail(-3.42) + 0.04, -3.42, iron, segs=10, rings=6)
        z = -3.55
        while z > -6.85:
            if abs(z + 4.3) > 0.07 and abs(z + 5.15) > 0.07:
                cy(0.011, 0.011, rail(z) - tread(z), x, (rail(z) + tread(z)) / 2, z, iron, segs=6, cap=False)
            z -= 0.14
    return finish("Precinct9_Steps", (36.0, 0.0, -5.17))


def precinct_globes():
    for gx in (34.2, 37.8):
        sp(0.3, gx, 3.0, -6.45, ck.glow("police_blue_glow", 2.0), segs=24, rings=16)
    return finish("Precinct9_Globes", (36.0, 3.0, -6.45))


def donut_box():
    box = C("#f4e2d4")
    bx(0.6, 0.12, 0.6, 37.6, 0.785, -5.3, box, bev=0.012)
    bx(0.608, 0.03, 0.608, 37.6, 0.83, -5.3, box, bev=0.008, segs=1)
    bx(0.61, 0.022, 0.61, 37.6, 0.765, -5.3, C("pink"), bev=0.005, segs=1)
    bx(0.2, 0.05, 0.004, 37.6, 0.79, -4.998, box, bev=0)
    dough, icing = C("#d89a5a"), GL("pink", 0.3)
    for (x, y, z, rx, rz) in ((37.45, 0.895, -5.22, 0.0, 0.0), (37.75, 0.895, -5.38, 0.0, 0.0), (37.6, 0.995, -5.3, 0.06, -0.05)):
        to(0.12, 0.05, x, y, z, dough, rot=(PI / 2 + rx, 0, rz), segs=(24, 10))
        fr = to(0.12, 0.053, x, y, z, icing, rot=(PI / 2 + rx, 0, rz), segs=(24, 10))
        for v in fr.data.vertices:
            cut = -0.006 + 0.008 * math.sin(5 * math.atan2(v.co.z, v.co.x) + x * 40)
            if v.co.y < cut:
                v.co.y = cut + (v.co.y - cut) * 0.1
        fr.data.update()
    return finish("Precinct9_DonutBox", (37.6, 0.725, -5.3))


# ------------------------------------------------------------------ assemble
def finish(name, origin):
    ob = ck.join(BAG[:], name)
    BAG.clear()
    bpy.context.view_layer.update()
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    t = ck.G(origin)
    ob.data.transform(Matrix.Translation(-t))
    ob.location = t
    return ob


built = [corner_store(), bank(), liquor(), precinct(), precinct_steps(), precinct_globes(), donut_box()]
dg = bpy.context.evaluated_depsgraph_get()
for o in built:
    print(f"[shops] {o.name}: {sum(len(p.vertices) - 2 for p in o.evaluated_get(dg).data.polygons)} tris, "
          f"{len(o.data.materials)} materials, origin {tuple(round(v, 2) for v in (o.location.x, o.location.z, -o.location.y))}")
    print("        " + " ".join(sorted(m.name for m in o.data.materials)))
ck.export("shops")


# ------------------------------------------------------------------ previews (stand-ins for the neighbours, not exported)
def stand_ins():
    ck.box(40, 0.12, 4.0, (33, 0.06, -5.0), C("grass", 0.95), name="_grass")
    ck.box(40, 0.16, 3.2, (33, 0.08, -1.6), C("sidewalk"), name="_walk")
    ck.box(40, 0.18, 0.25, (33, 0.09, 0.0), C("curb"), name="_curb")
    ck.box(40, 0.1, 14, (33, -0.045, 7.0), C("asphalt", 0.95), name="_street")
    for (x, z) in ((35.2, -2.75), (37.3, -2.7)):
        ck.cyl(0.2, 0.2, 1.3, (x, 0.81, z), C("navy"), name="_cop")
        ck.sph(0.2, (x, 1.71, z), C("#c8946a"), name="_head")
    ck.box(5, 6.5, 7, (17, 3.25, -10.5), C("#4a4a5a"), name="_house17")
    ck.box(5.2, 0.32, 7.2, (17, 6.64, -10.5), C("roof_trim"), name="_trim17")
    ck.box(1, 5, 10.4, (46.6, 2.5, -4.9), C("wall"), name="_endwall")
    for x in (30, 40):
        ck.cyl(0.07, 0.07, 5, (x, 2.5, -0.2), C("pole"), name="_lamp")
    ck.cyl(0.3, 0.27, 0.9, (26.4, 0.57, -3.5), C("trash"), name="_can")
    ck.cone(1.0, 0.35, (24.6, 2.3, -2.2), C("pink"), name="_umbrella")


if os.environ.get("SHOPS_PREVIEW", "1") == "1":
    stand_ins()
    ck.preview("shops", views=[{"eye": (17, 3.2, 6), "look": (31, 3.4, -8), "lens": 28}, {"eye": (46, 3.2, 5), "look": (33, 3.6, -8), "lens": 28},
                   {"eye": (36, 1.7, -1), "look": (36, 3.2, -7), "lens": 22}, {"eye": (39.4, 2.3, 5.4), "look": (35.4, 1.1, -1.3), "lens": 35}])
    ck.preview("shops_cs", views=[{"eye": (22.5, 1.6, -3.0), "look": (22.5, 1.8, -7), "lens": 24}, {"eye": (21.0, 1.5, -5.0), "look": (20.8, 1.55, -7.2), "lens": 30},
                      {"eye": (24.6, 2.2, -3.5), "look": (22.5, 3.7, -7), "lens": 26}, {"eye": (22.5, 4.0, -2.0), "look": (22.5, 5.9, -7), "lens": 28}])
    ck.preview("shops_bank", views=[{"eye": (28, 1.7, -1.5), "look": (28, 3.4, -7), "lens": 22}, {"eye": (29.3, 1.3, -4.2), "look": (28.6, 1.4, -7), "lens": 26},
                        {"eye": (28, 3.6, -3.0), "look": (28, 5.8, -7), "lens": 28}, {"eye": (32.6, 2.0, -3.0), "look": (30.8, 3.0, -9), "lens": 24}])
    ck.preview("shops_liquor", views=[{"eye": (43.5, 1.7, -1.5), "look": (43.5, 3.0, -7), "lens": 22}, {"eye": (41.6, 1.5, -4.5), "look": (41.8, 1.6, -7), "lens": 28},
                          {"eye": (43.5, 3.2, -4.0), "look": (43.5, 4.2, -7), "lens": 30}, {"eye": (39, 2.2, -2), "look": (44, 3, -7), "lens": 26}])
    ck.preview("shops_p9", views=[{"eye": (36, 1.6, -2.5), "look": (36, 2.4, -7), "lens": 22}, {"eye": (38.6, 1.4, -2.6), "look": (37.4, 0.8, -5.2), "lens": 30},
                      {"eye": (36, 4.0, -2.0), "look": (36, 6.4, -7), "lens": 26}, {"eye": (31.0, 1.6, -3.0), "look": (33.2, 2.6, -7), "lens": 24}])
    ck.preview("shops_roof", views=[{"eye": (33, 14, 22), "look": (33, 3, -9), "lens": 30}, {"eye": (24, 16, 2), "look": (33, 7, -11), "lens": 26},
                        {"eye": (31.0, 2.5, -4.5), "look": (31.0, 3.5, -11), "lens": 22}, {"eye": (12, 9, -2), "look": (21, 6.8, -9), "lens": 30}])
