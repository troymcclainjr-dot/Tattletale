"""Builds Grandma (makeGranny): lavender cardigan over a blouse, pearls, glasses, white bun, sensible shoes and her aluminium walker."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math
import numpy as np
import bpy, bmesh
from mathutils import Vector
import claykit as ck
from lib import person as P

H = 1.5
WALK_POSE = dict(walk=0.22, lean=0.3, armR=(-1.05, 0.02), armL=(-1.05, 0.02))   # animate.js: her only pose
WALKER_AT = np.array([0.0, 0.0, 0.48])                                          # JS wk.position (Rig-local)
CARDI = "#b88ac8"


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def part(name, s, m, parent, cell, target, lumps=0.0):
    ob = P.clay_mesh(name, s, m, parent, cell=cell, target=target, lumps=lumps)
    ob.data.name = name
    return ob


# ------------------------------------------------------------------ aluminium tubing (swept circles, rounded bends)
def fillet(pts, R, k=6):
    """Polyline with every inner corner replaced by an arc of radius R."""
    P_ = [np.asarray(p, float) for p in pts]
    out = [P_[0]]
    for i in range(1, len(P_) - 1):
        A, B, C = P_[i - 1], P_[i], P_[i + 1]
        d1, d2 = unit(A - B), unit(C - B)
        th = math.acos(max(-1.0, min(1.0, float(d1 @ d2))))
        if th > math.pi - 1e-3:
            out.append(B)
            continue
        t = min(R / math.tan(th / 2), 0.45 * np.linalg.norm(A - B), 0.45 * np.linalg.norm(C - B))
        rr = t * math.tan(th / 2)
        S, E = B + d1 * t, B + d2 * t
        cen = B + unit(d1 + d2) * (rr / math.sin(th / 2))
        u, w = S - cen, E - cen
        ang = math.acos(max(-1.0, min(1.0, float(unit(u) @ unit(w)))))
        for j in range(k + 1):
            s = j / k
            v = (math.sin((1 - s) * ang) * u + math.sin(s * ang) * w) / math.sin(ang)
            out.append(cen + v)
    out.append(P_[-1])
    return out


def sweep(bm, path, r, segs=10, mat_index=0, caps=True):
    """Add a tube of radius r (scalar or per point) along path (game coords) to bmesh bm."""
    Pp = [np.asarray(p, float) for p in path]
    rs = [r] * len(Pp) if np.isscalar(r) else list(r)
    T = []
    for i in range(len(Pp)):
        t = Pp[min(i + 1, len(Pp) - 1)] - Pp[max(i - 1, 0)]
        T.append(unit(t))
    n = np.cross(T[0], [0.0, 1.0, 0.0])
    if np.linalg.norm(n) < 1e-6:
        n = np.cross(T[0], [1.0, 0.0, 0.0])
    n = unit(n)
    rings = []
    for i in range(len(Pp)):
        n = unit(n - (n @ T[i]) * T[i])
        b = np.cross(T[i], n)
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            q = Pp[i] + rs[i] * (math.cos(a) * n + math.sin(a) * b)
            ring.append(bm.verts.new((q[0], -q[2], q[1])))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(segs):
            f = bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
            f.material_index = mat_index
            f.smooth = True
    if caps:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(ring[::-1] if rev else ring)
            f.material_index = mat_index


# trim the builder's budgets a little so the walker and the trimmings fit in 25k
TRIM = {"Body_top": 0.72, "ArmL_sleeve": 0.85, "ArmR_sleeve": 0.85, "LegL_pants": 0.75, "LegR_pants": 0.75,
        "LegL_shoe": 0.85, "LegR_shoe": 0.85, "ArmL_hand": 0.85, "ArmR_hand": 0.85, "Hair": 0.75, "Hair_tie": 0.6,
        "Glasses": 0.55, "Head_skin": 0.82, "EyeR_lids": 0.7, "EyeL_lids": 0.7, "Mouth_lips": 0.8, "Mouth_inside": 0.8}
_sdf_mesh = P.sdf_mesh


def _trimmed(name, s, m, cell, target=None, *a, **k):
    if target and name in TRIM:
        target = int(target * TRIM[name])
    return _sdf_mesh(name, s, m, cell, target, *a, **k)


P.sdf_mesh = _trimmed

# a ninety-one-year-old face: crow's feet, forehead lines, smile folds (pressed into the builder's head)
_head_skin = P._head_skin


def _aged_head(r):
    s = _head_skin(r)
    hy = r.hy
    C = np.array([0.0, hy, 0.0])
    cr = 0.0029 * H
    lines = []
    for sx in (-1, 1):
        for dy in (-0.011, 0.0, 0.011):                                   # crow's feet
            lines.append([(sx * 0.071 * H, hy + (0.02 + dy * 0.4) * H, 0.075 * H), (sx * 0.086 * H, hy + (0.02 + dy * 1.25) * H, 0.058 * H)])
        lines.append([(sx * 0.024 * H, hy - 0.012 * H, 0.11 * H), (sx * 0.04 * H, hy - 0.036 * H, 0.104 * H),
                      (sx * 0.047 * H, hy - 0.062 * H, 0.096 * H)])           # nose-to-mouth folds
        lines.append([(sx * 0.026 * H, hy - 0.006 * H, 0.104 * H), (sx * 0.043 * H, hy - 0.011 * H, 0.1 * H),
                      (sx * 0.06 * H, hy - 0.006 * H, 0.09 * H)])             # under-eye lines
    for y, w in ((0.072, 0.05), (0.083, 0.042)):                           # forehead
        lines.append([(-w * H, hy + (y - 0.003) * H, 0.09 * H), (0.0, hy + y * H, 0.11 * H), (w * H, hy + (y - 0.003) * H, 0.09 * H)])
    for pts in lines:
        nrm = [unit(np.asarray(p) - C) for p in pts]
        s = P.groove(s, pts, nrm, cr, 0.05 * H)
    return s


P._head_skin = _aged_head

# a soft, rounded upper back
_torso_body = P._torso_body


def _stooped_torso(r):
    t = _torso_body(r)
    return P.union(t, P.ellipsoid((0, 0.275 * H, -0.045 * H), (0.12 * H, 0.085 * H, 0.08 * H)), k=0.045 * H)


P._torso_body = _stooped_torso

# ------------------------------------------------------------------ the puppet
ck.reset()
r = P.make_person(h=H, skin="#ecc0a0", top=CARDI, pants="#6a5a7a", shoes="#4a3a3a", hair="#d8d8d8", style="bun", glasses=True,
                  collar="v", bust=0.4, hair_line=6, bun_tie="#7a5a8a", sole="#cbbd9e", laces=False, shoe_style="shoe",
                  lid=0.34, lid_tilt=-0.12, lid_low=0.14, eye_size=0.94, nose="round", nose_size=1.06, ear_size=1.12,
                  cheeks=1.16, chin=0.94, smile=0.7, mouth_w=0.84, lips="#b07272",
                  brow=dict(arch=1.6, thick=0.68, raise_=0.004, tilt=0.4), seed=91)
hy, hs = r.hy, r.hs
torso = r.sdf["torso"]
ring, th = P._neck_ring(r, torso)
ytop, yfront = float(np.mean(ring[:, 1])), float(ring[0, 1])

# ---- the blouse in the cardigan's V, a rounded collar, pearl buttons down the cardigan, two pockets, pearls
vreg = P.intersect(P.poly2d([(-0.052 * H, ytop + 0.03 * H), (0.052 * H, ytop + 0.03 * H), (0, yfront - 0.078 * H)]),
                   P.halfspace((0, 0, 0.03 * H), (0, 0, -1)), k=0.006 * H)
blouse = P.intersect(P.subtract(P.offset(torso, -0.0018 * H), P.offset(torso, -0.008 * H)), P.offset(vreg, 0.005 * H))
collar = P.union(*[P.intersect(P.offset(torso, 0.0004 * H), P.intersect(P.ellipse2d((sx * 0.026 * H, yfront - 0.008 * H), 0.03 * H, 0.019 * H),
                                                                         P.halfspace((0, 0, 0.03 * H), (0, 0, -1)))) for sx in (-1, 1)])
collar = P.union(collar, P.loop_tube(list(ring + np.array([0, 0.004 * H, 0])), 0.0072 * H), k=0.004 * H)
BLOUSE = "#f2ece0"
part("Blouse", P.union(blouse, collar, k=0.002 * H), ck.clay(BLOUSE, 0.85), r.body, 0.0011 * H, 700)
plk = P.intersect(P.poly2d([(-0.0125 * H, yfront - 0.07 * H), (0.0125 * H, yfront - 0.07 * H), (0.0125 * H, -0.01 * H), (-0.0125 * H, -0.01 * H)]),
                  P.halfspace((0, 0, 0.0), (0, 0, -1)))
pockets = [P.intersect(P.rbox((sx * 0.072 * H, 0.062 * H, 0.0), (0.03 * H, 0.027 * H, 1.0), 0.008 * H), P.halfspace((0, 0, 0.0), (0, 0, -1)))
           for sx in (-1, 1)]
trims = P.union(P.patch(torso, plk, 0.0042 * H), *[P.patch(torso, pk, 0.0045 * H) for pk in pockets])
for sx in (-1, 1):                                                         # pocket openings
    trims = P.groove(trims, [(sx * 0.049 * H, 0.084 * H, 0.2 * H), (sx * 0.072 * H, 0.085 * H, 0.2 * H), (sx * 0.095 * H, 0.084 * H, 0.2 * H)],
                     [(0, 0, 1)], 0.0022 * H, 0.2 * H)
part("CardiganTrim", trims, ck.clay(P.shade(CARDI, 0.93), 0.9), r.body, 0.0012 * H, 650)
ys = np.linspace(yfront - 0.085 * H, 0.012 * H, 4)
bp = P.snap(torso, [(0, y, 0.2 * H) for y in ys], [(0, 0, 1)], 0.3 * H, lift=0.0075 * H)
buttons = P.union(*[P.subtract(P.sphere(p, 0.0068 * H), P.union(*[P.sphere(p + (dx, 0.0016 * H * sy, 0.0072 * H), 0.0014 * H)
                                                                    for dx, sy in ((-0.0018 * H, 1), (0.0018 * H, 1), (-0.0018 * H, -1), (0.0018 * H, -1))]))
                    for p in bp])
part("Buttons", buttons, ck.gloss("#f0e8d8", 0.35), r.body, 0.0006 * H, 400)
t = np.linspace(-1.0, 1.0, 21)
pearl_pts = P.snap(torso, [(0.06 * H * math.sin(1.25 * a), yfront - 0.006 * H - 0.035 * H * math.cos(a * math.pi / 2) ** 1.6, 0.2 * H) for a in t],
                   [(0, 0.15, 1)], 0.3 * H, lift=0.0075 * H)
part("Pearls", P.union(*[P.sphere(p, 0.0058 * H) for p in pearl_pts]), ck.gloss("#f4eee4", 0.25), r.body, 0.0007 * H, 520)

# ---- velcro straps on the sensible shoes
upper, sole, _ = P._shoe_sdfs(r)
yg = -0.47 * H
straps = []
for z in (0.018, 0.046):
    nrm = unit((0, 0.62, 1.0))
    sl = P.plane_slab((0, yg + 0.06 * H, z * H), nrm, 0.0072 * H)
    straps.append(P.intersect(P.intersect(P.offset(upper, 0.0026 * H), sl, k=0.0012 * H), P.halfspace((0, yg + 0.026 * H, 0), (0, -1, 0)), k=0.0015 * H))
strap = P.union(*straps)
for side, pv, nm in ((1, r.legL, "LegL"), (-1, r.legR, "LegR")):
    ob = P.sdf_mesh(nm + "_strap", strap if side > 0 else P.mirror_x(strap), ck.clay(P.shade("#4a3a3a", 1.12), 0.55), 0.0011 * H, 300, seed=7 + side)
    P.attach(ob, pv)
    ck.join([r.meshes[nm], ob], nm + "_Mesh")

# ------------------------------------------------------------------ the walker, fitted to her hands in the walking pose
P.set_pose(r, **WALK_POSE)
hands = []
for arm in (r.armR, r.armL):
    me = r.meshes["ArmR" if arm is r.armR else "ArmL"]
    loc = P._mesh_verts(me)
    sel = loc[:, 1] < -0.232 * H                                       # the mitten (below the cuff)
    mw = me.matrix_world
    W = np.array([tuple(mw @ Vector((p[0], -p[2], p[1]))) for p in loc[sel]])
    hands.append(np.stack([W[:, 0], W[:, 2], -W[:, 1]], 1) - WALKER_AT)    # walker-local game coords
P.reset_pose(r)
hc = [h.mean(0) for h in hands]
print("[granny] hand centers (walker-local):", [tuple(np.round(c, 3)) for c in hc])
GX = float(np.mean([abs(c[0]) for c in hc])) - 0.016                 # grip runs just inside each mitten's palm
GY = float(np.mean([c[1] for c in hc])) - 0.026                      # through its lower half
GZ = float(np.mean([c[2] for c in hc]))
RG = 0.0125
FX, BX, FZ, BZ = GX + 0.012, GX + 0.022, 0.15, -0.15                   # feet splay a little wider than the grips
print(f"[granny] grips at x=+-{GX:.3f} y={GY:.3f} z={GZ:.3f}")

bm = bmesh.new()
for sx in (-1, 1):
    side = [(sx * FX, 0.035, FZ), (sx * GX, GY, FZ - 0.01), (sx * GX, GY, BZ + 0.01), (sx * BX, 0.05, BZ)]
    sweep(bm, fillet(side, 0.05, 6), RG, 10, 0)
    sweep(bm, [(sx * (FX - 0.004), 0.30, FZ * 0.985), (sx * (BX - 0.006), 0.30, BZ * 0.985)], 0.0095, 8, 0)     # side brace
    for z0, x0, xg in ((FZ, FX, GX), (BZ, BX, GX)):                     # telescoping collars
        f = 0.36 / max(GY, 1e-3)
        x = x0 + (xg - x0) * f
        sweep(bm, [(sx * x, 0.355, z0 + (FZ - 0.01 - z0) * f * (1 if z0 > 0 else 0)), (sx * x, 0.385, z0)], 0.0165, 10, 0)
    g0, g1 = GZ - 0.075, GZ + 0.065                                    # foam grip
    sweep(bm, [(sx * GX, GY, g0), (sx * GX, GY, g0 + 0.008), (sx * GX, GY, g1 - 0.008), (sx * GX, GY, g1)],
          [0.016, 0.0195, 0.0195, 0.016], 14, 1)
    sweep(bm, [(sx * FX, 0.0, FZ), (sx * FX, 0.004, FZ), (sx * FX, 0.034, FZ), (sx * FX, 0.042, FZ)], [0.012, 0.0175, 0.016, 0.0125], 12, 2)   # rubber tips
cb = [(-GX - 0.002, 0.63, FZ - 0.006), (GX + 0.002, 0.63, FZ - 0.006)]                                       # front crossbar
sweep(bm, cb, 0.0115, 10, 0)
me = bpy.data.meshes.new("Walker")
bm.to_mesh(me)
bm.free()
wk = bpy.data.objects.new("Walker", me)
bpy.context.scene.collection.objects.link(wk)
for m in (ck.metal("#c8ccd4", 0.3), ck.clay("#55565c", 0.8), ck.clay("#2a2a2c", 0.7)):
    me.materials.append(m)
ck.smooth(wk, 50)

# tennis balls on the back feet (yellow felt with the white seam), sliced for the leg
balls = []
seams = []
RB = 0.034
for sx in (-1, 1):
    c = np.array([sx * BX, RB - 0.002, BZ])
    ball = P.sphere(c, RB)
    ball = P.displace(ball, lambda p: 0.0012 * P.vnoise(p, 120.0, 3), 0.0012)
    tt = np.linspace(0, 2 * math.pi, 25)[:-1]
    a_, b_ = 0.72, 0.28
    pts = [c + RB * 1.01 * unit((a_ * math.cos(u) + b_ * math.cos(3 * u), 0.6 * math.sin(2 * u), a_ * math.sin(u) - b_ * math.sin(3 * u))) for u in tt]
    seams.append(P.loop_tube(pts, 0.0028, n=3))
    balls.append(ball)
ball_ob = P.sdf_mesh("WalkerBalls", P.union(*balls), ck.clay("#e8f040", 0.95), 0.0016, 500)
seam_ob = P.sdf_mesh("WalkerSeams", P.union(*seams), ck.clay("#f4f2e8", 0.85), 0.0011, 300)
# her plum handbag, hooked over the front crossbar by its handle (it hangs side-on, under the bar)
BAR = np.array([0.07, 0.63, FZ - 0.006])
BAG = BAR + (0.0, -0.15, 0.0)
bag = P.rbox(BAG, (0.027, 0.058, 0.07), 0.02)
bag = P.union(bag, P.intersect(P.offset(bag, 0.0035), P.intersect(P.halfspace(BAG + (0, 0.012, 0), (0, -1, 0)), P.halfspace(BAG + (0.004, 0, 0), (-1, 0, 0)))), k=0.002)
bag = P.displace(bag, lambda p: 0.0015 * P.vnoise(p, 70.0, 5), 0.0016)
handle = P.tube([BAG + (0.0, 0.05, 0.042), BAR + (0.0, -0.045, 0.028), BAR + (0.0, 0.006, 0.0175), BAR + (0.0, 0.0185, 0.0),
                 BAR + (0.0, 0.006, -0.0175), BAR + (0.0, -0.045, -0.028), BAG + (0.0, 0.05, -0.042)], 0.0062, n=6)
bag_ob = P.sdf_mesh("WalkerBag", P.union(bag, handle, k=0.006), ck.clay("#5e3040", 0.75), 0.0016, 520)
clasp_ob = P.sdf_mesh("WalkerClasp", P.capsule(BAG + (0.031, 0.046, -0.012), BAG + (0.031, 0.046, 0.012), 0.0055), ck.metal("#c8b070", 0.35), 0.0011, 80)
for ob in (ball_ob, seam_ob, bag_ob, clasp_ob):
    ob.parent = None
ck.join([wk, ball_ob, seam_ob, bag_ob, clasp_ob], "Walker")
P.attach(wk, r.rig, tuple(WALKER_AT))

P.export_character("granny")
for ob in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if ob.type == "MESH":
        print(f"[granny] {ob.name:14s} parent={ob.parent.name:6s} {sum(len(p.vertices) - 2 for p in ob.data.polygons):6d} tris  {[m.name for m in ob.data.materials]}")
ck.preview("granny")
hc_ = 0.47 * H + 0.36 * H + hy
P.pose_sheet(r, "granny_pose", [
    dict(pose=WALK_POSE, eye=(2.2 * H, 0.62 * H, 0.9 * H), look=(0, 0.48 * H, 0.18), lens=45),
    dict(pose=dict(WALK_POSE, phase=-math.pi / 2), eye=(1.3 * H, 1.0 * H, 1.9 * H), look=(0, 0.45 * H, 0.2), lens=45),
    dict(pose=WALK_POSE, eye=(0.75, 1.05, 0.95), look=(0.18, 0.78, 0.46), lens=50),
    dict(pose=WALK_POSE, eye=(0.3 * H, hc_ + 0.05 * H, 1.1 * H), look=(0, hc_ - 0.08 * H, 0.15), lens=55),
])
