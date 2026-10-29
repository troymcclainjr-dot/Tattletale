"""Builds Gary (makeGary), in the gutter since 2009: patched army jacket, slouchy beanie, scraggly beard, tired eyes, fingerless gloves and his glass pipe."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math
import numpy as np
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import claykit as ck
from lib import person as P

H = 1.72
SKIN, TOP, HAIR = "#c8a888", "#7a7258", "#6a5a3a"
LYING = dict(rig_rot=(-math.pi / 2, 0, math.pi / 2), rig_pos=(-1.95, 0.21, 0.73))   # = outer (yaw pi/2) * inner (x -pi/2)
# animate.js poses (and the game's hand-to-face tuning in animate.gd)
POSES = {
    "rest": dict(armR=(-0.5, 0.2), armL=(-0.3, 0.25)),
    "smoke_js": dict(armR=(-2.6, 0.35), armL=(-0.3, 0.25)),
    "smoke_game": dict(armR=(-2.35, -0.66), armL=(-0.3, 0.25)),
    "wave_hi": dict(armR=(-0.5, 0.2), armL=(-2.9, 0.4), look=0.4),
    "wave_lo": dict(armR=(-2.6, 0.35), armL=(-2.3, 0.4), look=0.4),
    "phone_js": dict(armR=(-2.9, 0.75), armL=(-0.3, 0.25), look=0.3),
    "phone_game": dict(armR=(-3.0, -0.1), armL=(-0.3, 0.25), look=0.3),
}


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def part(name, s, m, parent, cell, target, lumps=0.0, seed=0):
    ob = P.sdf_mesh(name, s, m, cell, target, lumps=lumps, seed=seed)
    ob.data.name = name
    P.attach(ob, parent)
    return ob


def cull_hidden(obj, cover, margin):
    """Delete faces of obj (verts in its parent's local game coords) buried deeper than margin inside cover."""
    V = P._mesh_verts(obj)
    P._MARGIN[0] = 0.02
    inside = P._eval_points(cover, V) < -margin
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    dead = [f for f in bm.faces if all(inside[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(dead)


# trim the builder's budgets: his legs never come out from under the quilt
TRIM = {"LegL_pants": 0.6, "LegR_pants": 0.6, "LegL_shoe": 0.6, "LegR_shoe": 0.6, "LegL_sole": 0.6, "LegR_sole": 0.6,
        "Body_pelvis": 0.6, "Body_top": 0.85, "Hair": 0.85, "Body_buttons": 0.7}
_sdf_mesh = P.sdf_mesh


def _trimmed(name, s, m, cell, target=None, *a, **k):
    if target and name in TRIM:
        target = int(target * TRIM[name])
    return _sdf_mesh(name, s, m, cell, target, *a, **k)


P.sdf_mesh = _trimmed

# his long hair as many thin, ragged, tapered locks (the builder's thick round-ended locks read as fingers when he lies down)
_hair_extras = P._hair_extras


def _ragged_long_hair(r, style):
    if style != "long":
        return _hair_extras(r, style)
    hy = r.hy
    rnd = np.random.RandomState(r.opts["seed"] + 9)
    locks = []
    n = 24
    for i in range(n):
        az = math.radians(-118 + 236 * i / (n - 1)) + rnd.uniform(-0.05, 0.05)
        sa, ca = math.sin(az), -math.cos(az)                               # az 0 = straight back
        w = rnd.uniform(-1, 1)
        rad = (0.0102 + 0.003 * rnd.rand()) * H
        y_end = (0.022 + 0.014 * abs(sa) + rnd.uniform(-0.012, 0.012)) * H
        pts = [(sa * 0.118 * H, hy - 0.005 * H, ca * 0.118 * H - 0.006 * H), (sa * 0.113 * H, hy - 0.07 * H, ca * 0.113 * H - 0.004 * H),
               ((sa * 0.106 + 0.006 * w) * H, 0.075 * H, ca * 0.106 * H), ((sa * 0.112 - 0.006 * w) * H, y_end + 0.016 * H, ca * 0.112 * H),
               ((sa * 0.12 + 0.012 * w) * H, y_end, (ca * 0.12 + 0.006 * rnd.uniform(-1, 1)) * H)]
        locks.append(P.tube(pts, [rad, rad, rad * 0.9, rad * 0.55, rad * 0.15], n=5))
    out = [("hair", P.union(*locks, k=0.008 * H))]
    for sx in (-1, 1):                                                    # thin locks framing the face
        side = []
        for j, (zo, rad) in enumerate(((0.032, 0.0088), (0.018, 0.0095), (0.004, 0.0095), (-0.01, 0.009))):
            yb = hy - (0.088 - 0.01 * j + rnd.uniform(-0.008, 0.008)) * H
            pts = [(sx * 0.1 * H, hy + 0.06 * H, zo * H), (sx * 0.114 * H, hy, (zo + 0.004) * H),
                   (sx * 0.109 * H, hy - 0.05 * H, (zo - 0.004) * H), (sx * (0.1 + 0.005 * j) * H, yb, (zo + 0.008) * H)]
            side.append(P.tube(pts, [rad * H, rad * H, rad * 0.8 * H, rad * 0.2 * H]))
        out.append(("hair", P.union(*side, k=0.004 * H)))
    return out


P._hair_extras = _ragged_long_hair

# ------------------------------------------------------------------ the puppet
ck.reset()
r = P.make_person(h=H, skin=SKIN, top=TOP, pants="#4a4436", shoes="#2a2a2a", hair=HAIR, style="long", belly=0.55,
                  collar="polo", pocket=True, button_color="#3a3628", tuck=True,
                  # friendly, sleepy, a big grin: "Heyyyy, 2-Pack!"
                  lid=0.47, lid_tilt=-0.22, lid_low=0.18, gaze=(0.06, 0.05), eye_size=1.02, pupil=0.92,
                  smile=1.0, mouth_w=1.12, nose="broad", nose_size=1.08, cheeks=1.08, chin=1.0, ear_size=1.06,
                  brow=dict(raise_=0.006, tilt=0.6, thick=1.15, arch=1.25), hair_volume=1.1, seed=2009)
hy, hs = r.hy, r.hs
SK = r.sdf["head"]
HH = P.union(SK, r.sdf["hair"])
EYES = [np.array([s * 0.042 * H, hy + 0.02 * H, 0.093 * H]) for s in (-1, 1)]

# ---- the lumpy army-green beanie (JS: sph(hs*.92) cap at hy + hs*.15, lumpy .01): slouchy, rolled cuff, sits above the brows
TILT = 0.28
YB = hy + 0.05 * H
nb = np.array([0.0, math.cos(TILT), -math.sin(TILT)])
DOME = P.ellipsoid((0, hy + 0.006 * H, -0.01 * H), (hs * 0.99 + 0.012 * H, hs + 0.02 * H, hs * 1.03 + 0.012 * H))
DOME = P.union(DOME, P.offset(HH, 0.0065 * H), k=0.022 * H)            # hugs the long hair without its strand grooves
DOME = P.union(DOME, P.ellipsoid((0.01 * H, hy + hs * 0.86, -0.05 * H), (0.08 * H, 0.06 * H, 0.072 * H)), k=0.045 * H)   # the slouch
DOME = P.displace(DOME, lambda p: 0.0034 * H * P.vnoise(p, 1.0 / (0.05 * H), 11) + 0.0014 * H * P.vnoise(p, 1.0 / (0.018 * H), 12), 0.005 * H)


def ribs(p, amp=0.0017 * H, n=36):
    a = np.arctan2(p[:, 0], p[:, 2] + 0.01 * H)
    return -amp * (0.5 - 0.5 * np.cos(n * a))


cap = P.intersect(DOME, P.halfspace((0, YB, 0), -nb), k=0.005 * H)
cuff_c = np.array([0, YB, 0]) + nb * 0.016 * H
cuff = P.intersect(P.offset(DOME, 0.0075 * H), P.plane_slab(cuff_c, nb, 0.016 * H), k=0.005 * H)
cuff = P.displace(cuff, ribs, 0.0018 * H)
BEANIE_SOLID = P.union(cap, P.intersect(P.offset(DOME, 0.0075 * H), P.plane_slab(cuff_c, nb, 0.016 * H)))
part("Beanie", P.union(cap, cuff, k=0.002 * H), ck.clay("#3a4a2a", 0.95), r.head, 0.0012 * H, 1900)

# ---- tired eye bags (JS #5a3a4a blobs under the eyes): puffy crescents
bags = []
for side, E in zip((-1, 1), EYES):
    xs = [E[0] - side * 0.017 * H, E[0] + side * 0.002 * H, E[0] + side * 0.021 * H]
    ys = [E[1] - 0.024 * H, E[1] - 0.031 * H, E[1] - 0.025 * H]
    pts = [(x, y, float(r.face(x, y)) + 0.001 * H) for x, y in zip(xs, ys)]
    bags.append(P.tube(pts, [0.0032 * H, 0.0058 * H, 0.0032 * H], n=6))
part("EyeBags", P.union(*bags), ck.clay("#5a3a4a", 0.85), r.head, 0.0007 * H, 300)

# ---- scraggly beard and droopy mustache (JS: sph(hs*.6) at (0, hy - hs*.7, hs*.35)): clear of the mouth
MC = np.array([0.0, hy - 0.05 * H])
BIGB = 1e9
mouth_hole = P.ellipse2d((0.0, MC[1] + 0.002 * H), 0.055 * H, 0.033 * H)
jaw = P.intersect(P.offset(SK, 0.0105 * H), P.ellipsoid((0, hy - 0.062 * H, 0.015 * H), (0.124 * H, 0.078 * H, 0.118 * H)), k=0.008 * H)
jaw = P.intersect(jaw, P.halfspace((0, 0, -0.035 * H), (0, 0, -1)), k=0.01 * H)
jaw = P.intersect(jaw, P.Sdf(lambda p: p[:, 1] - (hy - 0.027 * H + 0.03 * H * (p[:, 0] / (0.11 * H)) ** 2), [-BIGB] * 3, [BIGB] * 3), k=0.01 * H)
jaw = P.subtract(jaw, P.sphere((0, hy - 0.012 * H, 0.112 * H), 0.032 * H), k=0.008 * H)                 # keep the nose clean
mass = P.ellipsoid((0, hy - 0.093 * H, 0.05 * H), (0.066 * H, 0.046 * H, 0.05 * H))
rnd = np.random.RandomState(2009)
tufts = []
for i, a in enumerate(np.linspace(-1.0, 1.0, 19)):                    # a ragged lower edge
    x0 = 0.078 * H * math.sin(1.25 * a)
    y0 = hy - 0.112 * H + 0.05 * H * abs(a) ** 1.7
    z0 = 0.078 * H * math.cos(1.3 * a) - 0.014 * H
    ln = (0.016 + 0.02 * rnd.rand()) * H * (1.0 - 0.35 * abs(a))
    d = unit((0.25 * a + rnd.uniform(-0.2, 0.2), -1.0, 0.35 + rnd.uniform(-0.15, 0.25)))
    p0 = np.array([x0, y0 + 0.01 * H, z0])
    tufts.append(P.round_cone(p0, p0 + d * ln, 0.0105 * H, 0.0018 * H))
stache = []
for side in (-1, 1):
    for j, dy in enumerate((0.0, -0.006)):
        pts = [(side * 0.006 * H, hy - (0.024 - dy * 0.3) * H), (side * 0.03 * H, hy - (0.027 - dy) * H),
               (side * 0.05 * H, hy - (0.044 - dy) * H), (side * 0.058 * H, hy - (0.07 - dy) * H)]
        P3 = [(x, y, float(r.face(x, y)) + 0.007 * H) for x, y in pts]
        stache.append(P.tube(P3, [0.0085 * H, 0.0085 * H, 0.0068 * H, 0.0035 * H], n=5))
beard = P.subtract(P.union(jaw, mass, *tufts, k=0.011 * H), P.intersect(mouth_hole, P.halfspace((0, 0, 0.05 * H), (0, 0, -1))), k=0.006 * H)
beard = P.union(beard, *stache, k=0.006 * H)
STRANDS = np.array([1.0 / (0.007 * H), 1.0 / (0.05 * H), 1.0 / (0.007 * H)])          # streaks running down the beard
beard = P.displace(beard, lambda p: 0.0015 * H * P.vnoise(p * STRANDS, 1.0, 21) + 0.001 * H * P.vnoise(p, 1.0 / (0.02 * H), 22), 0.0026 * H)
part("Beard", beard, ck.clay(HAIR, 0.85), r.head, 0.0011 * H, 1900)

# long hair and scalp under the beanie never show
n_cut = cull_hidden(r.meshes["Head"], BEANIE_SOLID, 0.003 * H)
print(f"[gary] culled {n_cut} hidden head faces")

# ---- patched, worn sleeves (rebuild the builder's long sleeve, LEFT arm-local) and fingerless gloves
sleeve = P.union(P.sphere((0, 0, 0), 0.0455 * H), P.round_cone((0, -0.005 * H, 0), (0, -0.252 * H, 0.005 * H), 0.0455 * H, 0.0405 * H), k=0.02 * H)
PATCHES = {   # side: [(center (arm-local, that side), half size, prism axis, color)]
    -1: [((-0.012 * H, -0.085 * H, 0.04 * H), (0.026 * H, 0.03 * H), (0.25, 0, 1), "#5a6a7a"),
         ((-0.042 * H, -0.2 * H, 0.0), (0.02 * H, 0.024 * H), (-1, 0, 0.2), "#8a6a4a")],
    1: [((0.008 * H, -0.165 * H, 0.04 * H), (0.024 * H, 0.028 * H), (0.1, 0, 1), "#6a4a3a"),
        ((0.044 * H, -0.06 * H, -0.006 * H), (0.019 * H, 0.022 * H), (1, 0, 0.15), "#5a6a5a")],
}
hand = r.sdf["hand"]
glove = P.intersect(P.subtract(P.offset(hand, 0.0034 * H), P.offset(hand, -0.002 * H)), P.halfspace((0, -0.309 * H, 0), (0, -1, 0)), k=0.0015 * H)
glove = P.subtract(glove, P.sphere((-0.019 * H, -0.304 * H, 0.046 * H), 0.0145 * H), k=0.003 * H)        # thumb tip out
glove = P.union(glove, P.torus((0, -0.263 * H, 0.002 * H), 0.0272 * H, 0.0056 * H), k=0.003 * H)        # knit wrist band
for side, pv, nm in ((1, r.armL, "ArmL"), (-1, r.armR, "ArmR")):
    s_side = sleeve if side > 0 else P.mirror_x(sleeve)
    objs = []
    stitches = []
    for k, (c, (hw, hh), ax, col) in enumerate(PATCHES[side]):
        c = np.asarray(c, float)
        ax = unit(ax)
        up = np.array([0.0, 1.0, 0.0])
        rt = unit(np.cross(up, ax))
        f2 = (lambda c=c, rt=rt, hw=hw, hh=hh: (lambda p: np.maximum(np.abs((p - c) @ rt) - hw, np.abs(p[:, 1] - c[1]) - hh)))()
        region = P.intersect(P.Sdf(f2, c - 0.1 * H, c + 0.1 * H), P.halfspace(c - ax * 0.03 * H, -ax))
        objs.append(P.sdf_mesh(f"{nm}_patch{k}", P.patch(s_side, region, 0.0036 * H, k=0.0012 * H), ck.clay(col, 0.92), 0.0011 * H, 170, seed=40 + k))
        border = []
        for t in np.linspace(0, 1, 9)[:-1]:                                  # cross stitches round the border
            per = t * 4
            e = int(per)
            u = per - e
            lx, ly = [(-1 + 2 * u, -1), (1, -1 + 2 * u), (1 - 2 * u, 1), (-1, 1 - 2 * u)][e]
            border.append(c + rt * lx * hw * 0.82 + up * ly * hh * 0.82)
        bpts = P.snap(s_side, border, [ax], 0.06 * H, lift=0.0042 * H)
        for q in bpts:
            d = 0.0045 * H
            stitches.append(P.capsule(q - rt * d - up * d, q + rt * d + up * d, 0.0013 * H))
            stitches.append(P.capsule(q - rt * d + up * d, q + rt * d - up * d, 0.0013 * H))
    objs.append(P.sdf_mesh(f"{nm}_stitches", P.union(*stitches), ck.clay("#d8ccb0", 0.85), 0.0007 * H, 300, seed=50))
    objs.append(P.sdf_mesh(f"{nm}_glove", glove if side > 0 else P.mirror_x(glove), ck.clay("#5c5a4c", 0.95), 0.0009 * H, 520, seed=60 + side))
    for ob in objs:
        P.attach(ob, pv)
    ck.join([r.meshes[nm]] + objs, nm + "_Mesh")

# ---- the glass pipe (JS group at arm-local (0, -.32H, .04) = HandR-local (0, -.02H, .04)): stem forward, bulb at the bowl
pipe_s = P.union(P.round_cone((0, 0, -0.09), (0, 0, 0.07), 0.0135, 0.0165), P.sphere((0, 0.004, 0.1), 0.036), k=0.012)
pipe_s = P.subtract(pipe_s, P.cylinder((0, 0.035, 0.1), 0.012, 0.012, round_=0.003), k=0.004)          # the bowl opening
pipe = P.sdf_mesh("Pipe", pipe_s, ck.glass("#e8f0ff", 0.6), 0.0012, 500)
pipe.data.name = "Pipe"
P.in_hand(r, "R", pipe, (0, -0.02 * H, 0.04))
ember_s = P.displace(P.sphere((0, 0, 0), 0.03), lambda p: 0.004 * P.vnoise(p, 60.0, 9), 0.004)
ember = P.sdf_mesh("Ember", ember_s, ck.glow("#ff8a1a", 3.0), 0.0012, 300)
ember.data.name = "Ember"
P.attach(ember, pipe, (0, 0, 0.1))

P.export_character("gary")
for ob in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if ob.type == "MESH":
        print(f"[gary] {ob.name:12s} parent={ob.parent.name:6s} {sum(len(p.vertices) - 2 for p in ob.data.polygons):6d} tris  {[m.name for m in ob.data.materials]}")
ck.preview("gary")
hc = 0.47 * H + 0.36 * H + hy
P.pose_sheet(r, "gary_pose", [
    dict(pose=POSES["smoke_game"], eye=(0.9 * H, hc + 0.05 * H, 1.3 * H), look=(0, hc - 0.1 * H, 0), lens=45),
    dict(pose=POSES["wave_hi"], eye=(1.2 * H, 0.9 * H, 2.0 * H), look=(0, 0.75 * H, 0), lens=45),
    dict(pose=POSES["phone_js"], eye=(-0.8 * H, 1.0 * H, 1.6 * H), look=(0, 0.8 * H, 0), lens=45),
    dict(pose=POSES["rest"], eye=(0.25 * H, hc + 0.02 * H, 0.75 * H), look=(0, hc - 0.03 * H, 0), lens=55),
])

# ------------------------------------------------------------------ lying in his spot: quilt fit (preview only, after export)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ck.MODELS, "gary_spot.glb"))
spot = [o for o in bpy.data.objects if o not in before]
quilt = next(o for o in spot if o.name.startswith("GaryQuilt"))
pillow = next(o for o in spot if o.name.startswith("GaryPillow"))
bpy.context.view_layer.update()


def bvh(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(ob, dg)
    bm.transform(ob.matrix_world)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


QT = bvh(quilt)


def fit_report(label, pose):
    """Count Gary's body vertices that poke up through the quilt (rays cast up hit the quilt's top first, or nothing
    while the quilt lies below), and the highest toe and belly points (world y)."""
    P.reset_pose(r)
    P.set_pose(r, **pose)
    P._rot(r.rig, LYING["rig_rot"])
    r.rig.location = ck.G(LYING["rig_pos"])
    bpy.context.view_layer.update()
    out = {}
    for nm in ("LegL_Mesh", "LegR_Mesh", "Body_Mesh", "ArmL_Mesh", "ArmR_Mesh", "Head_Mesh", "Beard", "Beanie"):
        ob = bpy.data.objects[nm]
        mw = ob.matrix_world
        poke = inside = 0
        ymax = -9
        for v in ob.data.vertices:
            w = mw @ v.co
            g = (w.x, w.z, -w.y)
            if nm.startswith("Leg") and v.co.z < -0.37 * H:        # shoes: leg-local y below the cuff
                ymax = max(ymax, g[1])
            if nm == "Body_Mesh" and -0.02 * H < v.co.z < 0.25 * H:
                ymax = max(ymax, g[1])
            if not (-3.15 < g[0] < -1.7 and 0.33 < g[2] < 1.13):  # inside the quilt's footprint, clear of its edges
                continue
            up = QT.ray_cast(w, Vector((0, 0, 1)))
            dn = QT.ray_cast(w, Vector((0, 0, -1)))
            if up[0] is not None and up[1].z > 0:
                inside += 1
                if nm in ("Body_Mesh", "LegL_Mesh", "LegR_Mesh") and inside <= 3 and label == "rest":
                    print(f"[gary]   {nm} vert in quilt at x={g[0]:.3f} y={g[1]:.3f} z={g[2]:.3f} (local {v.co.x:.3f},{v.co.z:.3f},{-v.co.y:.3f}) quilt top {up[0].z:.3f}")
            elif up[0] is None and dn[0] is not None:
                poke += 1
        out[nm] = (poke, inside, ymax)
    P.reset_pose(r)
    _rot0(r)
    msg = "  ".join(f"{k.replace('_Mesh', '')}:{p}/{i}" + (f" ymax={y:.3f}" if y > -9 else "") for k, (p, i, y) in out.items())
    print(f"[gary] fit {label:10s} poke/inside  {msg}")
    return out


def _rot0(r):
    P._rot(r.rig, (0, 0, 0))
    r.rig.location = (0, 0, 0)
    bpy.context.view_layer.update()


for k, ps in POSES.items():
    fit_report(k, ps)

V_GAME = dict(eye=(-2.5, 2.6, 5.5), look=(-3.6, 0.6, 0.8), lens=36)       # game_shot "gary_spot"
V_NEAR = dict(eye=(-2.2, 1.35, 2.5), look=(-3.25, 0.35, 0.75), lens=40)
V_HEAD = dict(eye=(-4.5, 1.05, 1.9), look=(-3.45, 0.3, 0.7), lens=45)
V_SIDE = dict(eye=(-2.75, 0.62, 2.3), look=(-2.75, 0.3, 0.73), lens=32)
V_TOP = dict(eye=(-3.0, 3.2, 1.15), look=(-3.0, 0.2, 0.73), lens=30)
P.pose_sheet(r, "gary_lying", [dict(V_GAME, pose=POSES["rest"], **LYING), dict(V_NEAR, pose=POSES["smoke_game"], **LYING),
                               dict(V_HEAD, pose=POSES["wave_hi"], **LYING), dict(V_SIDE, pose=POSES["rest"], **LYING)])
P.pose_sheet(r, "gary_lying2", [dict(V_NEAR, pose=POSES["smoke_js"], **LYING), dict(V_NEAR, pose=POSES["wave_lo"], **LYING),
                                dict(V_NEAR, pose=POSES["phone_js"], **LYING), dict(V_NEAR, pose=POSES["phone_game"], **LYING)])
P.pose_sheet(r, "gary_lying3", [dict(V_TOP, pose=POSES["rest"], **LYING), dict(V_HEAD, pose=POSES["smoke_game"], **LYING),
                                dict(V_SIDE, pose=POSES["wave_hi"], **LYING),
                                dict(eye=(-3.45, 0.75, 1.6), look=(-3.62, 0.25, 0.73), lens=45, pose=POSES["rest"], **LYING)])
