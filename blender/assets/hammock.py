"""Daddy's hammock on the grass: two rough wooden posts, rope rigging, spreader bars, striped canvas bed, pillow."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math, random
import bpy, bmesh
from mathutils import Vector, noise, Matrix
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


def tube(pts, r, m=None, parent=None, name="tube", res=1, curved=False, path_res=6):
    """Round tube through game-coord points (local to parent); curved=True runs a smooth curve through them."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.use_fill_caps = True
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


def solidify(obj, thick):
    md = obj.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = 0.0
    md.use_even_offset = True
    ck._apply_modifiers(obj)
    return obj


def wood_grain(obj, amount=0.012, seed=0):
    """Rough post surface: vertical grain streaks plus lumps, pushed out from the local y axis."""
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in obj.data.vertices:
        x, y, h = v.co                       # Blender local: z is up the post
        rr = math.hypot(x, y)
        if rr < 1e-5:
            continue
        a = math.atan2(y, x)
        streak = noise.noise(Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, h * 0.6)) + off)
        lump = noise.noise(Vector((x, y, h)) * 7.0 + off)
        d = amount * (0.8 * streak + 0.45 * lump)
        v.co.x += x / rr * d
        v.co.y += y / rr * d
    obj.data.update()
    return obj


def pillow(size, cx, m, name="Pillow", seed=0):
    """Puffy rectangular pillow draped over the curved bed (its underside follows the canvas)."""
    o = ck.sph(1.0, (0, 0, 0), m, name=name, segs=18, rings=10)
    sx, sy, sz = size
    for v in o.data.vertices:
        x, y, z = v.co                                   # Blender local: z up
        px = cx + math.copysign(abs(x) ** 0.55, x) * sx / 2
        pz = -math.copysign(abs(y) ** 0.55, y) * sz / 2
        py = bed_height(px, pz) + sy / 2 + math.copysign(abs(z) ** 1.15, z) * sy / 2
        v.co = ck.G(px, py, pz)
    o.data.update()
    ck.lumpy(o, 0.005, 9, seed=seed)
    return o


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


# ---------------------------------------------------------------- layout (local to the hammock origin)
POST_X = 1.4          # posts at x +-1.4
GRASS = 0.12          # grass top; the game puts the origin at y 0
BAR_X, BAR_Y = 1.2, 0.975
HALF_W = 0.43


def bed_center(u):
    """Height of the bed's center line along x: nearly flat under Daddy (his back is at y ~0.82), rising to the bars."""
    a = min(1.0, abs(u) / BAR_X)
    r = ((a - 0.75) / 0.25) ** 2 if a > 0.75 else 0.0
    return 0.787 + 0.02 * a * a + (BAR_Y - 0.807) * r, a, r


def bed_point(u, v):
    """Bed surface: u in [-1.2, 1.2] along x, v in [-1, 1] across. The long edges sag in a catenary
    between the bars and ride up around him, so the cross-section is a cradle."""
    c, a, r = bed_center(u)
    edge = BAR_Y - 0.09 * (1 - a * a)
    hw = HALF_W - 0.04 * (1 - a * a)
    pleat = 0.006 * math.sin(v * math.pi * 4.5) * r          # gathers near the bars
    y = c + (edge - c) * (0.65 * v * v + 0.35 * v ** 4) + pleat
    return (u, y, v * hw)


def bed_height(x, z):
    """Top of the canvas at (x, z)."""
    a = min(1.0, abs(x) / BAR_X)
    hw = HALF_W - 0.04 * (1 - a * a)
    return bed_point(x, max(-1.0, min(1.0, z / hw)))[1] + 0.009


ck.reset()
random.seed(12)
WOOD = ck.clay("post_brown", 0.92)     # #7a4a24
KNOT = ck.clay("bark", 0.95)           # #5a3a24
ENDGRAIN = ck.clay("#a87a4a", 0.95)
BARWOOD = ck.clay("#b08a56", 0.75)
ROPE = ck.clay("#c2ad80", 0.95)
IRON = ck.clay("iron", 0.45)
CANVAS = ck.clay("#d8c8a0", 0.95)
STRIPE_A = ck.clay("#a84a3a", 0.95)    # brick red
STRIPE_B = ck.clay("#c89a3a", 0.95)    # mustard
PILLOW = ck.clay("cream", 0.95)
SOIL = ck.clay("#6a5236", 0.95)
TUFT = ck.clay("#5a7a32", 0.95)
parts = []

# posts: rough, slightly leaning outward under the hammock's pull, sawn tops with lighter end grain
for sx in (-1, 1):
    prof = [(0.12 - 0.02 * i / 14, 1.74 * i / 14) for i in range(15)] + [(0.098, 1.775), (0.085, 1.795), (0.0, 1.805)]
    post = lathe(prof, m=WOOD, segs=14, name="Post", angle=70)
    wood_grain(post, 0.011, seed=sx + 3)
    ck.wobble(post, 0.01, 0.8, seed=sx + 7)
    ck._place(post, (sx * POST_X, 0, 0), (0, 0, -sx * 0.025), None)
    parts.append(post)
    parts.append(ck.cyl(0.074, 0.08, 0.012, (0, 1.80, 0), ENDGRAIN, rot=(0.06 * sx, 0, 0.04), parent=post, segs=14, name="EndGrain"))
    for k, (ky, ka) in enumerate(((0.62, 0.9 + sx), (1.12, 3.0 - sx))):
        kr = 0.114 - 0.02 * ky / 1.74
        parts.append(ck.sph(0.026, (kr * math.cos(ka), ky, kr * math.sin(ka)), KNOT, scale=(0.7, 1.0, 0.7), parent=post,
                            segs=8, rings=5, name="Knot"))
    # rope lashing near the top and an iron ring on the inner face
    for k, yy in enumerate((1.37, 1.40, 1.43)):
        rr = 0.12 - 0.02 * yy / 1.74 + 0.004
        parts.append(ck.tor(rr, 0.011, (0, yy, 0), ROPE, rot=(math.pi / 2 + 0.08 * (k - 1), 0, 0.05 * sx), parent=post,
                            major_segs=14, minor_segs=4, name="Lashing"))
    # the rope end is knotted under the lashing and holds the iron ring the strings gather on
    knot = ck.sph(0.022, (-sx * 0.118, 1.357, 0), ROPE, scale=(1.0, 0.8, 1.1), parent=post, segs=10, rings=6, name="Knot")
    ck.lumpy(knot, 0.004, 60, seed=sx + 2)
    parts.append(knot)
    parts.append(ck.tor(0.03, 0.007, (-sx * 0.126, 1.322, 0), IRON, parent=post, major_segs=14, minor_segs=5, name="Ring"))
    # soil mound and grass tufts at the foot
    parts.append(lathe([(0.11, GRASS - 0.02), (0.24, GRASS - 0.005), (0.2, GRASS + 0.018), (0.15, GRASS + 0.032),
                        (0.115, GRASS + 0.036)], (sx * POST_X, 0, 0), SOIL, segs=14, name="Mound"))
    for t in range(4):
        a = random.uniform(0, 2 * math.pi)
        rr = random.uniform(0.2, 0.3)
        cx, cz = sx * POST_X + rr * math.cos(a), rr * math.sin(a)
        for b in range(3):
            h = random.uniform(0.06, 0.11)
            parts.append(ck.cone(0.012, h, (cx + random.uniform(-0.02, 0.02), GRASS + h / 2 - 0.005, cz + random.uniform(-0.02, 0.02)),
                                 TUFT, rot=(random.uniform(-0.35, 0.35), 0, random.uniform(-0.35, 0.35)), segs=5, name="Tuft"))

bpy.context.view_layer.update()

# spreader bars with the canvas wrapped over them, and the string fans up to the rings
for sx in (-1, 1):
    bar = ck.cyl(0.021, 0.021, 2 * HALF_W + 0.08, (sx * BAR_X, BAR_Y, 0), BARWOOD, rot=(math.pi / 2, 0, 0), segs=10, name="SpreaderBar")
    ck.wobble(bar, 0.004, 2.0, seed=sx + 11)
    parts.append(bar)
    for sz in (-1, 1):
        parts.append(ck.sph(0.03, (sx * BAR_X, BAR_Y, sz * (HALF_W + 0.045)), BARWOOD, segs=10, rings=6, name="BarKnob"))
    sleeve = ck.cyl(0.034, 0.034, 2 * HALF_W - 0.01, (sx * BAR_X, BAR_Y, 0), CANVAS, rot=(math.pi / 2, 0, 0), segs=10, name="Sleeve")
    ck.lumpy(sleeve, 0.004, 14, seed=sx + 5)
    parts.append(sleeve)
    # bottom of the ring on the leaning post, in hammock coords
    lean = -sx * 0.025
    ry = 1.30
    rx = sx * POST_X + (-sx * 0.13) * math.cos(lean) - ry * math.sin(lean)
    ryw = (-sx * 0.13) * math.sin(lean) + ry * math.cos(lean)
    for k in range(5):
        z = -0.4 + 0.2 * k
        parts.append(tube([(rx, ryw, 0.0), (sx * BAR_X, BAR_Y + 0.02, z)], 0.006, ROPE, name="String", res=0))

# the bed: one canvas sheet with woven stripes near each edge, solidified
NU, BANDS = 28, [(-1.0, -0.8, 0), (-0.8, -0.68, 1), (-0.68, -0.62, 0), (-0.62, -0.56, 2), (-0.56, 0.56, 0),
                  (0.56, 0.62, 2), (0.62, 0.68, 0), (0.68, 0.8, 1), (0.8, 1.0, 0)]
vs = [-1.0]
for v0, v1, _ in BANDS:
    n = max(1, round((v1 - v0) / 0.11))
    vs += [v0 + (v1 - v0) * (k + 1) / n for k in range(n)]
bm = bmesh.new()
grid = [[bm.verts.new(ck.G(bed_point(-BAR_X + 2 * BAR_X * i / NU, v))) for v in vs] for i in range(NU + 1)]
for i in range(NU):
    for j in range(len(vs) - 1):
        f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
        vm = (vs[j] + vs[j + 1]) / 2
        f.material_index = next(b[2] for b in BANDS if b[0] <= vm <= b[1])
bed = ck._mesh_obj("Bed", bm)
for mm in (CANVAS, STRIPE_A, STRIPE_B):
    bed.data.materials.append(mm)
ck.lumpy(bed, 0.004, 6, seed=2)
solidify(bed, 0.018)
ck.smooth(bed, 180)
parts.append(bed)
# rolled hems along both long edges
for v in (-1.0, 1.0):
    pts = []
    for i in range(0, NU + 1, 2):
        x, y, z = bed_point(-BAR_X + 2 * BAR_X * i / NU, v)
        pts.append((x, y + 0.004, z + 0.008 * v))
    parts.append(tube(pts, 0.016, CANVAS, name="Hem", res=1, curved=True, path_res=2))

# pillow under Daddy's head (his head is at x ~ -0.89)
parts.append(pillow((0.32, 0.08, 0.48), -0.99, PILLOW, seed=4))

# a tipped-over soda can on the grass by the foot post
can = lathe([(0, -0.06), (0.026, -0.06), (0.032, -0.052), (0.033, 0.048), (0.027, 0.058), (0.024, 0.061), (0, 0.061)],
            (0.95, GRASS + 0.032, 0.42), ck.clay("red", 0.5), rot=(0, 0.5, math.pi / 2), segs=12, name="Can")
parts.append(can)
parts.append(ck.cyl(0.025, 0.025, 0.006, (0.0, 0.06, 0), ck.gloss("alu", 0.3), parent=can, segs=12, name="CanLid"))

hammock = bake(ck.join(parts, "Hammock"))
print("[hammock] objects:", sorted(o.name for o in bpy.context.scene.objects))
ck.export("hammock")

# ---- previews (Daddy proxy is preview-only, built from the JS person proportions lying where resetDad puts him)
ck.box(5.0, GRASS, 3.0, (0, GRASS / 2, 0), ck.clay("grass", 0.95), name="_grass")
ck.preview("hammock", views=[
    {"eye": (2.8, 2.5, 4.4), "look": (0, 0.85, 0), "lens": 35},
    {"eye": (-2.6, 1.9, -3.2), "look": (0, 0.9, 0), "lens": 35},
    {"eye": (0, 2.8, 5.6), "look": (0, 0.9, 0), "lens": 35},
    {"eye": (3.4, 1.35, 0.5), "look": (0, 1.0, 0), "lens": 40},
])

ck.preview("hammock_close", views=[
    {"eye": (2.0, 1.55, 0.9), "look": (1.3, 1.2, 0), "lens": 45},
    {"eye": (-0.9, 2.1, 1.3), "look": (-0.95, 0.85, 0), "lens": 40},
    {"eye": (1.2, 0.5, 1.6), "look": (1.25, 0.25, 0.2), "lens": 40},
    {"eye": (-2.1, 1.3, -1.2), "look": (-1.25, 1.05, 0), "lens": 45},
])
H = 1.8
TOP = ck.clay("#f4f0e6")
SK = ck.clay("#8a5a3c")
PANTS = ck.clay("#4a4a5a")


def dad(px, py, pz):
    """Person-local (x, y, z) -> hammock coords for Daddy lying face up, feet at x 0.9, head toward -x."""
    return (0.9 - py, 1.02 + pz, -px)


for s in (-1, 1):
    ck.cyl(0.058 * H, 0.058 * H, 0.44 * H, dad(s * 0.085 * H, 0.25 * H, 0), PANTS, rot=(0, 0, math.pi / 2), name="_leg")
    ck.box(0.1 * H, 0.18 * H, 0.065 * H, dad(s * 0.085 * H, 0.03 * H, 0.035 * H), ck.clay("#2a2a2a"), name="_shoe")
    ck.cyl(0.042 * H, 0.042 * H, 0.29 * H, dad(s * 0.185 * H, 0.635 * H, 0), TOP, rot=(0, 0, math.pi / 2), name="_arm")
ck.sph(0.135 * H, dad(0, 0.48 * H, 0), PANTS, scale=(0.55, 0.78, 1.05), name="_pelvis")
ck.cyl(0.14 * H, 0.14 * H, 0.32 * H, dad(0, 0.64 * H, 0), TOP, rot=(0, 0, math.pi / 2), name="_torso").scale = (1, 0.74, 1)
ck.sph(0.12 * H, dad(0, 0.59 * H, 0.045 * H), TOP, scale=(1.0, 1.4, 1.05), name="_belly")
ck.sph(0.115 * H, dad(0, 0.995 * H, 0), SK, name="_head")
ck.preview("hammock_dad", views=[
    {"eye": (2.8, 2.5, 4.4), "look": (0, 0.9, 0), "lens": 35},
    {"eye": (-2.4, 1.6, 1.8), "look": (-0.8, 0.95, 0), "lens": 40},
    {"eye": (0, 2.8, 5.6), "look": (0, 0.9, 0), "lens": 35},
    {"eye": (3.4, 1.35, 0.5), "look": (0, 1.0, 0), "lens": 40},
])
