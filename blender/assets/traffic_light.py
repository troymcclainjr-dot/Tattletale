"""Traffic light at the crosswalk: pole, mast arm over the far lane, signal head facing -x (LampRed/Yellow/Green)."""
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


def tube(pts, r, m=None, parent=None, name="tube", res=1, closed=False):
    """Round tube through game-coord points (local to parent)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.use_fill_caps = not closed
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


def visor(center, r_in, thick, length, m, a0=-24, a1=204, segs=16, name="Visor"):
    """Cap visor around a lamp facing -x: open underneath, longest on top, tapering to nothing at the ends."""
    cx, cy, cz = center
    s0 = -math.sin(math.radians(a0))
    bm = bmesh.new()
    cols = []
    for k in range(segs + 1):
        t = math.radians(a0 + (a1 - a0) * k / segs)
        dy, dz = math.sin(t), math.cos(t)
        L = max(0.012, length * ((math.sin(t) + s0) / (1 + s0)) ** 0.8)
        x0, x1 = cx + 0.02, cx + 0.02 - L
        cols.append([bm.verts.new(ck.G(x, cy + dy * rr, cz + dz * rr))
                     for x, rr in ((x0, r_in), (x0, r_in + thick), (x1, r_in + thick), (x1, r_in))])
    for a, b in zip(cols, cols[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(cols[0])
    bm.faces.new(list(reversed(cols[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, 50)
    return obj


def band(r, y, h, m, name="Band", segs=18):
    """Thin rounded strap around the pole (cheaper than a torus)."""
    return lathe([(0, y - h / 2), (r - 0.004, y - h / 2), (r, y - h / 4), (r, y + h / 4), (r - 0.004, y + h / 2), (0, y + h / 2)],
                 m=m, segs=segs, name=name, angle=70)


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


# ---------------------------------------------------------------- build
ck.reset()
random.seed(31)
POLE = ck.clay("pole", 0.8)          # #2a2a2e
HEAD = ck.clay("#1c1c20", 0.8)
YEL = ck.clay("lane_yellow", 0.7)
CHROME = ck.gloss("alu", 0.3)
BLK = ck.clay("black", 0.6)
WHITE = ck.clay("cream", 0.8)
SIDEWALK = 0.16                      # south sidewalk top; the game puts the origin at street level
parts = []

# pole: 4.6 tall, r .11 at the foot to .09 at the top, with a slight hand-made bow
pole = lathe([(0.11 - 0.02 * i / 15, 4.6 * i / 15) for i in range(16)], m=POLE, segs=16, name="Pole")
ck.wobble(pole, 0.012, 0.35, seed=3)
ck.lumpy(pole, 0.0025, 9, seed=4)
parts.append(pole)

# sturdy base: square plate with four anchor nuts, flared cast skirt with a ring
parts.append(ck.box(0.4, 0.05, 0.4, (0, SIDEWALK + 0.025, 0), POLE, name="BasePlate", bevel=0.018, bevel_segs=2))
for sx in (-1, 1):
    for sz in (-1, 1):
        parts.append(ck.cyl(0.028, 0.03, 0.026, (sx * 0.145, SIDEWALK + 0.063, sz * 0.145), POLE, segs=6, name="Nut"))
        parts.append(ck.cyl(0.011, 0.012, 0.03, (sx * 0.145, SIDEWALK + 0.085, sz * 0.145), CHROME, segs=6, name="Bolt"))
parts.append(lathe([(0.0, 0.2), (0.165, 0.2), (0.172, 0.21), (0.166, 0.224), (0.15, 0.24), (0.134, 0.275), (0.123, 0.33),
                    (0.116, 0.42), (0.114, 0.468), (0.126, 0.477), (0.13, 0.494), (0.126, 0.51), (0.11, 0.52), (0.0, 0.52)],
                   m=POLE, segs=20, name="Skirt"))

# collar + cap where the arm meets the pole, flange plate and bolts
parts.append(lathe([(0, 4.36), (0.104, 4.36), (0.12, 4.378), (0.122, 4.585), (0.112, 4.605), (0.1, 4.612), (0.086, 4.652),
                    (0.052, 4.684), (0, 4.694)], m=POLE, segs=18, name="Collar"))
parts.append(lathe([(0, -0.016), (0.085, -0.016), (0.095, -0.006), (0.095, 0.006), (0.085, 0.016), (0, 0.016)],
                   (0, 4.5, -0.13), POLE, rot=(math.pi / 2, 0, 0), segs=16, name="Flange"))
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    parts.append(ck.cyl(0.014, 0.014, 0.02, (0.064 * math.cos(a), 4.5 + 0.064 * math.sin(a), -0.15), POLE,
                        rot=(math.pi / 2, 0, 0), segs=6, name="FlangeBolt"))

# mast arm: 3.3 long along z at y 4.5, reaching out over the far lane (-z), slight taper
arm = lathe([(0, -1.668), (0.03, -1.665), (0.05, -1.657), (0.055, -1.645)] +
            [(0.055 + 0.011 * i / 10, -1.645 + 3.295 * i / 10) for i in range(1, 11)] + [(0, 1.65)],
            (0, 4.5, -1.6), POLE, rot=(math.pi / 2, 0, 0), segs=12, name="Arm")
ck.wobble(arm, 0.008, 0.5, seed=5)
parts.append(arm)
# diagonal brace under the arm with clamp bands
parts.append(tube([(0, 3.86, -0.085), (0, 4.445, -1.3)], 0.021, POLE, name="Brace"))
parts.append(band(0.1, 3.86, 0.03, POLE, name="BraceBand"))
parts.append(ck.tor(0.066, 0.013, (0, 4.5, -1.3), POLE, name="ArmBand", major_segs=16, minor_segs=5))

# signal head: three stacked sections between a top and bottom cap, hung from a saddle clamp on the arm
HZ = -3.1
for y in (4.3, 3.95, 3.6):
    parts.append(ck.box(0.4, 0.35, 0.42, (0, y, HZ), HEAD, name="HeadSection", bevel=0.03, bevel_segs=2))
for y in (4.5, 3.4):
    parts.append(ck.box(0.43, 0.05, 0.45, (0, y, HZ), HEAD, name="HeadCap", bevel=0.018, bevel_segs=2))
parts.append(ck.box(0.15, 0.13, 0.36, (0, 4.555, HZ), HEAD, name="Saddle", bevel=0.035, bevel_segs=2))
for z in (HZ - 0.12, HZ + 0.12):
    parts.append(ck.tor(0.074, 0.012, (0, 4.5, z), POLE, name="UBolt", major_segs=16, minor_segs=5))
# backplate just behind the lamp face, with a raised yellow border
BP_X = -0.18
bp_z0, bp_z1, bp_y0, bp_y1 = HZ - 0.33, HZ + 0.33, 3.375 - 0.12, 4.525 + 0.07
parts.append(ck.box(0.02, bp_y1 - bp_y0, bp_z1 - bp_z0, (BP_X, (bp_y0 + bp_y1) / 2, HZ), HEAD, name="Backplate",
                    bevel=0.008, bevel_segs=2))
ins, cr = 0.035, 0.05
loop = []
for (cy, cz, a0) in ((bp_y1 - ins - cr, bp_z1 - ins - cr, 0), (bp_y1 - ins - cr, bp_z0 + ins + cr, 90),
                     (bp_y0 + ins + cr, bp_z0 + ins + cr, 180), (bp_y0 + ins + cr, bp_z1 - ins - cr, 270)):
    for k in range(4):
        a = math.radians(a0 + 90 * k / 3)
        loop.append((BP_X - 0.012, cy + cr * math.sin(a), cz + cr * math.cos(a)))
parts.append(tube(loop, 0.012, YEL, name="BackplateBorder", closed=True))
# lamp bezels and cap visors (open underneath, so a lit lamp still reads from the side)
for y in (4.3, 3.95, 3.6):
    parts.append(ck.tor(0.148, 0.016, (-0.204, y, HZ), HEAD, rot=(0, math.pi / 2, 0), name="Bezel", major_segs=22, minor_segs=5))
    parts.append(visor((-0.22, y, HZ), 0.152, 0.014, 0.22, HEAD, name="Visor"))

# pedestrian push-button box on the crosswalk (+x) side of the pole, with an arrow plate above
PB_Y = SIDEWALK + 1.05
for y in (PB_Y - 0.06, PB_Y + 0.06):
    parts.append(band(0.106, y, 0.018, POLE, name="ButtonStrap"))
parts.append(ck.box(0.075, 0.18, 0.12, (0.142, PB_Y, 0), YEL, name="ButtonBox", bevel=0.022, bevel_segs=2))
parts.append(lathe([(0, 0), (0.034, 0), (0.036, 0.006), (0.033, 0.012), (0.024, 0.014), (0.0, 0.014)],
                   (0.178, PB_Y - 0.015, 0), BLK, rot=(0, 0, -math.pi / 2), segs=16, name="ButtonRing"))
parts.append(ck.sph(0.021, (0.193, PB_Y - 0.015, 0), CHROME, scale=(0.6, 1, 1), name="Button", segs=12, rings=8))
parts.append(ck.box(0.012, 0.13, 0.1, (0.118, PB_Y + 0.17, 0), WHITE, name="ArrowPlate", bevel=0.004, bevel_segs=1))
arrow = [(-0.034, 0.008), (0.006, 0.008), (0.006, 0.026), (0.04, 0.0), (0.006, -0.026), (0.006, -0.008), (-0.034, -0.008)]
# drawn facing +x, pointing -z: across the street, the way the crosswalk goes
parts.append(slab(arrow, 0.006, (0.126, PB_Y + 0.17, 0), BLK, rot=(0, math.pi / 2, 0), name="Arrow"))

body = bake(ck.join(parts, "TrafficLight"))

# lamps: separate objects, each with its own glow material (the game switches their emission).
# Only the part of each r .13 sphere in front of the face is modeled (a smooth dome, origin at the sphere center).
a_max = math.pi / 2 + math.asin(0.02 / 0.13)
dome = [(0.13 * math.sin(a_max * (1 - k / 8)), 0.13 * math.cos(a_max * (1 - k / 8))) for k in range(8)] + [(0, 0.13)]
for name, col, y in (("LampRed", "#ff2a2a", 4.3), ("LampYellow", "#ffc21a", 3.95), ("LampGreen", "#2aff6a", 3.6)):
    bake(lathe(dome, (-0.22, y, HZ), ck.glow(col, 3.0), rot=(0, 0, math.pi / 2), name=name, segs=24, angle=180), keep_loc=True)

print("[traffic_light] objects:", sorted(o.name for o in bpy.context.scene.objects))
ck.export("traffic_light")

# preview only: the south sidewalk slab the light stands on (top 0.16, curb edge at local z -0.6)
ck.box(4.0, 0.16, 3.6, (0, 0.08, 1.2), ck.clay("sidewalk", 0.95), name="_sidewalk")
ck.preview("traffic_light", views=[
    {"eye": (-3.2, 3.4, -0.8), "look": (0, 3.95, -2.9), "lens": 50},
    {"eye": (-5.5, 2.4, -9.0), "look": (0, 2.6, -1.4), "lens": 30},
    {"eye": (-2.6, 3.95, -3.1), "look": (0, 3.95, -3.1), "lens": 50},
    {"eye": (1.7, 1.2, 1.3), "look": (0.05, 0.75, 0), "lens": 40},
])
