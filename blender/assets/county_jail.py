"""The squirrel's tiny COUNTY JAIL: stone base, iron cage with a padlocked door, iron roof, sign, flag, tin cup."""
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


def label(s, size, depth, pos, m, font="impact", fit=None, max_h=None, res=3, name="Text"):
    """Raised lettering facing +z, centered exactly on pos (by its mesh bounds), low curve resolution."""
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
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    tobj = bpy.data.objects.new(name, me)
    ck._link(tobj)
    ck.assign(tobj, m)
    return ck._place(tobj, pos, None, None)


def solidify(obj, thick):
    md = obj.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = 0.0
    ck._apply_modifiers(obj)
    return obj


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


# ---------------------------------------------------------------- build (local to the jail origin, which sits on the grass)
ck.reset()
random.seed(9)
STONES = [ck.clay(c, 0.92) for c in ("#8a8a90", "#84848a", "#929298", "#7e7e86")]
MORTAR = ck.clay("#64646a", 0.95)
PLINTH = ck.clay("#7a7a80", 0.93)
CAPSTONE = ck.clay("#96969c", 0.9)
IRON = ck.clay("iron", 0.45)            # #3a3a3e, satin painted iron
BRASS = ck.metal("#c8a040", 0.3)
GOLD = ck.metal("gold", 0.35)           # #f2c230
CREAM = ck.clay("cream", 0.85)          # #f4f0e6
INK = ck.clay("black", 0.7)             # #141414
TIN = ck.gloss("#a8acb4", 0.35)
parts = []

# ---- stone base, 1 x 0.5 x 0.8: footing course, two courses of ashlar blocks over dark mortar, cap course = cell floor (y 0.5)
parts.append(ck.box(1.06, 0.09, 0.86, (0, 0.045, 0), PLINTH, name="Footing", bevel=0.02, bevel_segs=2))
parts.append(ck.box(0.9, 0.36, 0.7, (0, 0.27, 0), MORTAR, name="Mortar"))
GAP, DEPTH = 0.009, 0.07


def stone(w, h, d, pos, segs=2):
    s = ck.box(w - GAP, h - GAP, d, pos, random.choice(STONES), name="Stone", bevel=0.016, bevel_segs=segs,
               rot=(random.uniform(-0.012, 0.012), random.uniform(-0.012, 0.012), random.uniform(-0.015, 0.015)))
    ck.lumpy(s, 0.003, 11, seed=random.randint(0, 99))
    parts.append(s)


def course(y0, h, front, side):
    """front: block widths along x (sum 1.0) for the +z and -z faces; side: widths along z (sum 0.66) for the x faces."""
    yc = y0 + h / 2
    for sz, ws in ((1, front), (-1, list(reversed(front)))):
        x = -0.5
        for w in ws:
            stone(w, h, DEPTH, (x + w / 2, yc + random.uniform(-0.002, 0.002), sz * (0.4 - DEPTH / 2)), 2 if sz > 0 else 1)
            x += w
    for sx, ws in ((1, side), (-1, list(reversed(side)))):
        z = -0.33
        for w in ws:
            stone(DEPTH, h, w, (sx * (0.5 - DEPTH / 2), yc + random.uniform(-0.002, 0.002), z + w / 2), 1)
            z += w


course(0.09, 0.175, [0.36, 0.30, 0.34], [0.34, 0.32])
course(0.265, 0.175, [0.2, 0.34, 0.28, 0.18], [0.21, 0.25, 0.2])
parts.append(ck.box(1.05, 0.06, 0.85, (0, 0.47, 0), CAPSTONE, name="CapCourse", bevel=0.016, bevel_segs=2))

# sheriff's star on the front of the base (comically official)
star = []
for k in range(12):
    a = math.pi / 2 + k * math.pi / 6
    rr = 0.075 if k % 2 == 0 else 0.036
    star.append((rr * math.cos(a), rr * math.sin(a)))
parts.append(slab(star, 0.012, (0, 0.265, 0.405), GOLD, name="Star"))
for k in range(6):
    a = math.pi / 2 + k * math.pi / 3
    parts.append(ck.sph(0.011, (0.078 * math.cos(a), 0.265 + 0.078 * math.sin(a), 0.408), GOLD, segs=6, rings=4, name="StarTip"))
parts.append(ck.sph(0.02, (0, 0.265, 0.41), GOLD, scale=(1, 1, 0.5), segs=12, rings=6, name="StarBoss"))

# ---- iron cage: bars exactly where the JS has them (r .025, 0.7 tall, centered y .85)
bars = []
for k in range(8):
    x = -0.44 + k * 0.126
    bars += [(x, 0.4), (x, -0.4)]
for sx in (-0.5, 0.5):
    for k in range(6):
        bars.append((sx, -0.34 + k * 0.136))
for i, (x, z) in enumerate(bars):
    b = ck.cyl(0.025, 0.025, 0.7, (x, 0.85, z), IRON, segs=8, name="Bar")
    ck.wobble(b, 0.003, 3.0, seed=i)
    parts.append(b)
# rails top and bottom, corner posts
for y in (0.535, 1.155):
    for sz in (-1, 1):
        parts.append(ck.box(1.0, 0.032, 0.03, (0, y, sz * 0.4), IRON, name="Rail", bevel=0.008, bevel_segs=1))
    for sx in (-1, 1):
        parts.append(ck.box(0.03, 0.032, 0.8, (sx * 0.5, y, 0), IRON, name="Rail", bevel=0.008, bevel_segs=1))
for sx in (-1, 1):
    for sz in (-1, 1):
        parts.append(ck.box(0.052, 0.68, 0.052, (sx * 0.5, 0.84, sz * 0.4), IRON, name="CornerPost", bevel=0.012, bevel_segs=2))

# ---- the barred door in the front: stiles, a cross rail, hinges on the left, a hasp and a big brass padlock on the right
DZ = 0.43
for x in (-0.251, 0.253):
    parts.append(ck.box(0.032, 0.6, 0.016, (x, 0.845, DZ), IRON, name="DoorStile", bevel=0.006, bevel_segs=1))
parts.append(ck.box(0.536, 0.03, 0.016, (0.001, 0.70, DZ), IRON, name="DoorRail", bevel=0.006, bevel_segs=1))
for y in (0.64, 1.05):
    parts.append(ck.cyl(0.014, 0.014, 0.07, (-0.272, y, DZ), IRON, segs=8, name="Hinge"))
    parts.append(ck.box(0.05, 0.026, 0.01, (-0.248, y, DZ + 0.006), IRON, name="HingeStrap", bevel=0.004, bevel_segs=1))
parts.append(ck.box(0.05, 0.05, 0.012, (0.268, 0.86, DZ + 0.006), IRON, name="Hasp", bevel=0.005, bevel_segs=1))
parts.append(ck.tor(0.022, 0.0055, (0.282, 0.835, DZ + 0.022), BRASS, rot=(0, 0.25, 0), major_segs=14, minor_segs=5, name="Shackle"))
parts.append(ck.box(0.072, 0.064, 0.03, (0.282, 0.79, DZ + 0.024), BRASS, name="Padlock", bevel=0.014, bevel_segs=2))
parts.append(slab([(-0.004, 0.006), (0.004, 0.006), (0.004, -0.002), (0.002, -0.012), (-0.002, -0.012), (-0.004, -0.002)],
                  0.004, (0.282, 0.792, DZ + 0.04), INK, name="Keyhole"))

# ---- iron roof (y 1.17..1.23 as in the JS, a little overhang), rivets, corner finials
parts.append(ck.box(1.04, 0.035, 0.84, (0, 1.185, 0), IRON, name="RoofBand", bevel=0.01, bevel_segs=2))
parts.append(ck.box(1.1, 0.04, 0.9, (0, 1.212, 0), IRON, name="Roof", bevel=0.016, bevel_segs=2))
for k in range(6):
    for sz in (-1, 1):
        parts.append(ck.sph(0.012, (-0.4 + k * 0.16, 1.232, sz * 0.41), IRON, scale=(1, 0.6, 1), segs=6, rings=3, name="Rivet"))
for k in range(3):
    for sx in (-1, 1):
        parts.append(ck.sph(0.012, (sx * 0.51, 1.232, -0.22 + k * 0.22), IRON, scale=(1, 0.6, 1), segs=6, rings=3, name="Rivet"))
for sx in (-1, 1):
    for sz in (-1, 1):
        parts.append(lathe([(0, 1.23), (0.016, 1.23), (0.01, 1.245), (0.022, 1.262), (0.024, 1.275), (0.015, 1.292), (0, 1.297)],
                           (sx * 0.5, 0, sz * 0.4), IRON, segs=8, name="Finial"))

# ---- the sign: cream board in an iron frame on two little uprights, raised dark letters
SIGN_Y, SIGN_Z = 1.38, 0.4
for x in (-0.3, 0.3):
    parts.append(ck.box(0.026, 0.09, 0.012, (x, 1.27, SIGN_Z - 0.016), IRON, name="SignPost", bevel=0.004, bevel_segs=1))
parts.append(ck.box(0.83, 0.19, 0.016, (0, SIGN_Y, SIGN_Z - 0.016), IRON, name="SignFrame", bevel=0.006, bevel_segs=2))
parts.append(ck.box(0.8, 0.16, 0.022, (0, SIGN_Y, SIGN_Z - 0.004), CREAM, name="SignBoard", bevel=0.006, bevel_segs=2))
parts.append(label("COUNTY JAIL", 0.12, 0.01, (0, SIGN_Y, SIGN_Z + 0.007 + 0.004), INK, font="impact", fit=0.74, max_h=0.112,
                   name="SignText"))

# ---- a little flag on the back corner of the roof
FX, FZ = -0.47, -0.38
parts.append(ck.cyl(0.008, 0.009, 0.56, (FX, 1.51, FZ), IRON, segs=8, name="FlagPole"))
parts.append(ck.sph(0.016, (FX, 1.8, FZ), GOLD, segs=10, rings=6, name="FlagBall"))
FW, FH, NX, NY = 0.22, 0.14, 12, 7
bm = bmesh.new()
grid = []
for i in range(NX + 1):
    u = i / NX
    col = []
    for j in range(NY + 1):
        v = j / NY
        x = FX + 0.01 + u * FW
        y = 1.77 - (1 - v) * FH - 0.012 * u * u
        z = FZ + 0.018 * math.sin(u * 7.0) * u
        col.append(bm.verts.new(ck.G(x, y, z)))
    grid.append(col)
RED, WHT, BLU = ck.clay("red", 0.9), ck.clay("cream", 0.9), ck.clay("watch_blue", 0.9)
for i in range(NX):
    for j in range(NY):
        f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
        canton = i < 5 and j >= 3
        f.material_index = 2 if canton else (0 if j % 2 == 0 else 1)
flag = ck._mesh_obj("Flag", bm)
for mm in (RED, WHT, BLU):
    flag.data.materials.append(mm)
solidify(flag, 0.005)
ck.smooth(flag, 180)
parts.append(flag)

# ---- inside: a tiny dented tin cup in the front-right corner, clear of the squirrel (he sits in the middle at y 0.5)
cup = lathe([(r * 1.2, y * 1.2) for r, y in ((0, 0), (0.026, 0), (0.029, 0.005), (0.031, 0.05), (0.034, 0.054), (0.031, 0.058),
                                             (0.027, 0.054), (0.025, 0.012), (0, 0.012))],
            (0.379, 0.5, 0.27), TIN, rot=(0.05, 2.6, -0.04), segs=14, name="TinCup")
ck.lumpy(cup, 0.0015, 40, seed=3)
parts.append(cup)
parts.append(ck.tor(0.019, 0.0055, (0.0, 0.036, -0.041), TIN, rot=(0, math.pi / 2, 0), parent=cup, major_segs=12, minor_segs=4, name="CupHandle"))

jail = bake(ck.join(parts, "CountyJail"))
print("[county_jail] objects:", sorted(o.name for o in bpy.context.scene.objects))
ck.export("county_jail")

# ---- previews: with a stand-in squirrel (preview only) where the game jails him (local y 0.5)
ck.box(3.0, 0.12, 3.0, (0, -0.06, 0), ck.clay("grass", 0.95), name="_grass")
fur = ck.clay("#8a5a34", 0.85)
ck.sph(0.2, (0, 0.7, 0), fur, scale=(0.8, 0.85, 1.25), name="_sq_body")
ck.sph(0.15, (0, 0.86, 0.2), fur, name="_sq_head")
ck.sph(0.2, (0, 0.92, -0.28), fur, scale=(0.7, 1.5, 0.7), name="_sq_tail")
ck.preview("county_jail", views=[
    {"eye": (1.5, 1.7, 2.5), "look": (0, 0.8, 0), "lens": 40},
    {"eye": (-1.8, 1.9, -2.2), "look": (0, 0.8, 0), "lens": 40},
    {"eye": (0, 1.3, 2.6), "look": (0, 0.85, 0), "lens": 45},
    {"eye": (0.55, 0.95, 1.1), "look": (0.15, 0.8, 0.2), "lens": 35},
])
