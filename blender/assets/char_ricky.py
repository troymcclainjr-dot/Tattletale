"""Builds Ricky the bank robber (makeRicky): striped shirt, black domino mask, knit beanie and a lumpy money sack with a green $."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math
import numpy as np
import bpy, bmesh
import claykit as ck
from lib import person as P

H = 1.76
STRIPES = P.stripes(["#141414", "#f4f0e6"], 0.02 * H)      # JS stripesMat: 0.02H bands
SACK = "#c8b080"
ROPE = "#7a5a34"


# ------------------------------------------------------------------ helpers
def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def cull_hidden(obj, cover, margin):
    """Delete faces of obj (verts in its parent's local game coords) buried deeper than margin inside cover."""
    V = P._mesh_verts(obj)
    P._MARGIN[0] = 0.02
    inside = P._eval_points(cover, V) < -margin
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    dead = [f for f in bm.faces if all(inside[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(dead)


def glyph_loops(ch, size, font="black"):
    """Outline loops (2D, centered) of a character, from Blender's font fill."""
    t = ck.text(ch, size=size, depth=0.0, bevel=0.0, font=font, resolution=10, name="_glyph")
    bm = bmesh.new()
    bm.from_mesh(t.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bnd = [e for e in bm.edges if len(e.link_faces) == 1]
    nxt = {}
    for e in bnd:
        a, b = e.verts
        nxt.setdefault(a.index, []).append(b.index)
        nxt.setdefault(b.index, []).append(a.index)
    co = {v.index: (v.co.x, v.co.z) for v in bm.verts}     # mesh faces game +z: Blender (x, z) = game (x, y)
    seen, loops = set(), []
    for s in nxt:
        if s in seen:
            continue
        loop, prev, cur = [s], None, s
        seen.add(s)
        while True:
            cands = [n for n in nxt[cur] if n != prev and n not in seen]
            if not cands:
                break
            prev, cur = cur, cands[0]
            seen.add(cur)
            loop.append(cur)
        if len(loop) > 2:
            loops.append(np.array([co[i] for i in loop]))
    bm.free()
    bpy.data.objects.remove(t)
    allp = np.concatenate(loops)
    c = (allp.min(0) + allp.max(0)) / 2
    return [L - c for L in loops], (allp.max(0) - allp.min(0))


def poly_sdf2d(loops):
    """Signed 2D distance to a set of closed loops (even-odd fill), vectorized over points."""
    A = np.concatenate(loops)
    B = np.concatenate([np.roll(L, -1, 0) for L in loops])

    def f(u, v):
        d = np.full(len(u), np.inf)
        s = np.ones(len(u))
        for a, b in zip(A, B):
            e = b - a
            wx, wy = u - a[0], v - a[1]
            h = np.clip((wx * e[0] + wy * e[1]) / max(e @ e, 1e-12), 0, 1)
            d = np.minimum(d, (wx - e[0] * h) ** 2 + (wy - e[1] * h) ** 2)
            c1, c2, c3 = v >= a[1], v < b[1], e[0] * wy > e[1] * wx
            s = np.where((c1 & c2 & c3) | (~c1 & ~c2 & ~c3), -s, s)
        return s * np.sqrt(d)
    return f


def raised_letter(ch, surf, c, n, up, size, height=0.011, font="black", k=0.0025):
    """A clay letter standing `height` proud of surface `surf`, centered at c and facing n (follows the curve)."""
    loops, ext = glyph_loops(ch, size, font)
    f2 = poly_sdf2d(loops)
    n = unit(n)
    right = unit(np.cross(up, n))
    upv = np.cross(n, right)
    c = np.asarray(c, float)

    def f(p):
        q = p - c
        return f2(q @ right, q @ upv)
    R = float(np.linalg.norm(ext)) * 0.6 + 0.1
    prism = P.Sdf(f, c - R, c + R)
    skin = P.subtract(P.offset(surf, height), P.offset(surf, -0.012))
    front = P.halfspace(c - n * 0.08, -n)
    return P.intersect(P.intersect(skin, prism, k=k), front)


def part(name, s, m, parent, cell, target, lumps=0.0):
    ob = P.clay_mesh(name, s, m, parent, cell=cell, target=target, lumps=lumps)
    ob.data.name = name
    return ob


def torso_loop(r, angle, x0, y0, lift, n=44):
    """Points of a closed loop hugging the torso in the plane through (x0, y0) with normal (cos a, sin a, 0)."""
    d1 = np.array([-math.sin(angle), math.cos(angle), 0.0])
    d2 = np.array([0.0, 0.0, 1.0])
    o = np.array([x0, y0, 0.0])
    th = np.linspace(0, 2 * math.pi, n, endpoint=False)
    D = np.cos(th)[:, None] * d1 + np.sin(th)[:, None] * d2
    t = P.ray_hit(r.sdf["torso"], o + D * 0.9, -D, 0.9, steps=120)
    return o + D * (0.9 - t + lift)[:, None]


# trim the builder's budgets a little (stripes are cut into bands, which adds triangles back)
TRIM = {"Body_top": 0.62, "ArmL_sleeve": 0.75, "ArmR_sleeve": 0.75, "LegL_pants": 0.8, "LegR_pants": 0.8,
        "LegL_shoe": 0.85, "LegR_shoe": 0.85, "Hair": 0.7}
_sdf_mesh = P.sdf_mesh


def _trimmed(name, s, m, cell, target=None, *a, **k):
    if target and name in TRIM:
        target = int(target * TRIM[name])
    return _sdf_mesh(name, s, m, cell, target, *a, **k)


P.sdf_mesh = _trimmed

# ------------------------------------------------------------------ the puppet
ck.reset()
r = P.make_person(h=H, skin="#e8b48a", top_mat=STRIPES, sleeve_mat=STRIPES, pants="#1a1a1e", shoes="#0a0a0c",
                  hair="#141010", style="short",
                  # a shifty, square-jawed face (mostly behind the mask)
                  gaze=(0.34, -0.05), lid=0.3, lid_tilt=-0.08, lid_low=0.0, nose="round", nose_size=1.14,
                  chin=1.18, cheeks=0.95, smile=0.3, mouth_w=0.94, brow=dict(tilt=-0.7, thick=1.3, raise_=-0.004),
                  seed=1776)
hy, hs = r.hy, r.hs
EY = hy + 0.02 * H                       # JS mask line (eye centers)
RE = 0.026 * H
EYES = [np.array([s * 0.042 * H, EY, 0.093 * H]) for s in (-1, 1)]
HH = P.union(r.sdf["head"], r.sdf["hair"])

# ---- black domino mask (JS box hs*2.05 wide at (0, hy+.02H, hs*.82)): a smooth front piece bridging the eyes,
# eye holes, and a tie band that runs back under the beanie
base = P.union(HH, *[P.sphere(E, RE + 0.0048 * H) for E in EYES], k=0.017 * H)
grown = P.offset(base, 0.0034 * H)
lobes = P.union(*[P.xform(P.ellipse2d((0, 0), 0.048 * H, 0.0315 * H), pos=(E[0] * 1.05, E[1] + 0.002 * H, 0), rot=(0, 0, s * 0.17))
                  for s, E in zip((-1, 1), EYES)], k=0.014 * H)
front = P.intersect(lobes, P.halfspace((0, 0, 0.035 * H), (0, 0, -1)))
band = P.plane_slab((0, EY + 0.0005 * H, 0), (0, 1, 0), 0.0128 * H)
mask = P.intersect(grown, P.union(front, band, k=0.006 * H), k=0.0016 * H)
holes = P.union(*[P.xform(P.ellipse2d((0, 0), 0.0232 * H, 0.0185 * H), pos=(E[0] * 1.02, E[1] - 0.0015 * H, 0), rot=(0, 0, s * 0.12))
                  for s, E in zip((-1, 1), EYES)])
holes = P.intersect(holes, P.halfspace((0, 0, 0.04 * H), (0, 0, -1)))
mask = P.subtract(mask, holes, k=0.0016 * H)
MASK_SOLID = mask
part("Mask", mask, ck.clay("#0a0a0c", 0.5), r.head, 0.0009 * H, 1000)

# ---- knit watch cap pulled down to the mask (JS: black hemisphere over the head): smooth dome, ribbed rolled cuff
TILT = 0.2
YB = hy + 0.021 * H
nb = np.array([0.0, math.cos(TILT), -math.sin(TILT)])
DOME = P.ellipsoid((0, hy + 0.008 * H, -0.009 * H), (hs * 0.99 + 0.0165 * H, hs + 0.0235 * H, hs * 1.03 + 0.0175 * H))


def ribs(p, amp=0.0017 * H, n=40):
    a = np.arctan2(p[:, 0], p[:, 2] + 0.01 * H)
    return -amp * (0.5 - 0.5 * np.cos(n * a))


cap = P.intersect(DOME, P.halfspace((0, YB, 0), -nb), k=0.004 * H)
cuff_c = np.array([0, YB, 0]) + nb * 0.0175 * H
cuff = P.intersect(P.offset(DOME, 0.0075 * H), P.plane_slab(cuff_c, nb, 0.0175 * H), k=0.005 * H)
cuff = P.displace(cuff, ribs, 0.0018 * H)
beanie = P.union(cap, cuff, k=0.002 * H)
BEANIE_SOLID = P.union(cap, P.intersect(P.offset(DOME, 0.0075 * H), P.plane_slab(cuff_c, nb, 0.0175 * H)))
part("Beanie", beanie, ck.clay("#161616", 0.95), r.head, 0.0011 * H, 1800, lumps=0.00025 * H)

# hair, scalp and brows under the beanie and the mask never show
n_cut = cull_hidden(r.meshes["Head"], P.union(BEANIE_SOLID, MASK_SOLID), 0.0025 * H)
print(f"[ricky] culled {n_cut} hidden head faces")

# ---- five o'clock shadow on the jaw and upper lip: a thin darker layer
skin = r.sdf["head"]
MC = np.array([0, hy - 0.05 * H])                                  # mouth center (Head-local x, y)
area = P.union(P.ellipsoid((0, hy - 0.083 * H, 0.03 * H), (0.118 * H, 0.072 * H, 0.11 * H)),
               P.ellipsoid((0, hy - 0.034 * H, 0.095 * H), (0.038 * H, 0.013 * H, 0.04 * H)), k=0.012 * H)
area = P.intersect(area, P.halfspace((0, 0, -0.02 * H), (0, 0, -1)), k=0.01 * H)
area = P.subtract(area, P.ellipse2d(tuple(MC), 0.047 * H, 0.03 * H), k=0.004 * H)
area = P.subtract(area, P.ellipse2d((0, hy - 0.004 * H), 0.034 * H, 0.024 * H), k=0.004 * H)   # nose and nostrils
LU = 0.0005 * H                                                      # the head mesh's own lumps (person.py seed 51)
skin_l = P.displace(skin, lambda p: LU * P.vnoise(p, 1.0 / (140.0 * LU), 51), LU)
stub = P.intersect(P.subtract(P.offset(skin_l, 0.0012 * H), P.offset(skin, -0.003 * H)), area, k=0.0008 * H)
part("Stubble", stub, ck.clay(P.hexmix("#e8b48a", "#3a4050", 0.44), 0.9), r.head, 0.0009 * H, 800)

# ---- the money sack on his back (JS bag group at Body-local (.12H, .3H, -.2H), lumpy r .26 scaled (1, 1.1, .9))
B = np.array([0.12 * H, 0.3 * H, -0.2 * H])
low = P.ellipsoid(B + (0.0, -0.03, -0.01), (0.262, 0.255, 0.236))
up = P.ellipsoid(B + (0.0, 0.12, 0.0), (0.19, 0.15, 0.17))
neck = P.round_cone(B + (0, 0.2, 0), B + (0, 0.305, 0), 0.085, 0.046)
sack = P.union(low, up, neck, k=0.07)
sack = P.displace(sack, lambda p: 0.013 * P.vnoise(p, 8.0, 3) + 0.006 * P.vnoise(p, 19.0, 4), 0.019)
for k in range(7):                                                  # folds gathered up to the neck
    a = 2 * math.pi * k / 7 + 0.4
    sa, ca = math.sin(a), math.cos(a)
    pts = [B + (0.06 * sa, 0.27, 0.06 * ca), B + (0.15 * sa, 0.17, 0.14 * ca), B + (0.215 * sa, 0.04, 0.2 * ca)]
    sack = P.groove(sack, pts, P.radial(pts, B), 0.0085, 0.1)
SACK_SHAPE = sack
sack = P.subtract(sack, P.offset(r.sdf["torso"], 0.007 * H), k=0.035)   # squashed against his back


def ruffle(p):
    a = np.arctan2(p[:, 0] - B[0], p[:, 2] - B[2])
    return 0.011 * np.sin(7 * a + 0.6) * P.smoothstep(0.32, 0.375, p[:, 1] - B[1])


TIE = B + np.array([0, 0.305, 0])
tuft = P.union(P.round_cone(TIE + (0, 0.005, 0), TIE + (0, 0.055, 0), 0.042, 0.078), P.sphere(TIE + (0, 0.042, 0), 0.054), k=0.02)
tuft = P.subtract(P.displace(tuft, ruffle, 0.012), P.ellipsoid(TIE + (0, 0.085, 0), (0.055, 0.028, 0.055)), k=0.012)
sack_ob = part("Sack", P.union(sack, tuft, k=0.012), ck.clay(SACK, 0.95), r.body, 0.0045, 1700)

# rope: tied round the neck with a knot and two loose ends, and a strap over his left shoulder, across the chest
tie = P.torus(TIE, 0.05, 0.0155)
knot = P.ellipsoid(TIE + (0.045, -0.004, 0.035), (0.026, 0.022, 0.02))
ends = [P.tube([TIE + (0.05, -0.01, 0.04), TIE + (0.075, -0.06, 0.06), TIE + (0.07, -0.11, 0.075) + (dx, 0, 0)], [0.012, 0.011, 0.009])
        for dx in (-0.03, 0.025)]
loop = torso_loop(r, -0.62, -0.035 * H, 0.17 * H, 0.0085 * H)
strap = P.loop_tube(list(loop), 0.0085 * H, n=3)
top = loop[np.argmax(loop[:, 1] - 2.0 * loop[:, 2])]                 # the back of the shoulder
link = P.tube([top + (0, 0.0, -0.01), top + (0.0, 0.07, -0.09), TIE + (-0.015, -0.035, 0.035)], 0.011)
rope = P.union(tie, knot, *ends, strap, link, k=0.004)
rope = P.displace(rope, lambda p: -0.0016 * (0.5 - 0.5 * np.sin(170 * (p[:, 0] + p[:, 1] - p[:, 2]))), 0.0017)
rope_ob = part("Rope", rope, ck.clay(ROPE, 0.9), r.body, 0.0024, 1150)

# two bills poking out of the top
bills = []
for i, (ax, az, sx) in enumerate(((0.35, 0.2, 0.015), (-0.25, -0.4, -0.02))):
    b = P.rbox((0, 0.06, 0), (0.034, 0.06, 0.0022), 0.0018)
    b = P.warp(b, lambda p: p + np.stack([np.zeros(len(p)), np.zeros(len(p)), 0.9 * (p[:, 1] - 0.03) ** 2], 1), 0.01)
    bills.append(P.xform(b, pos=TIE + (sx, 0.04, 0.0), rot=(ax, 0.6 + i * 1.9, az)))
bill_ob = part("Bills", P.union(*bills), ck.clay("#7aa874", 0.85), r.body, 0.0016, 400)

# green $ on the OUTSIDE (the JS sign faced his back): on the back-left, reads from behind and from the left
dn = unit((math.sin(0.62), 0.08, -math.cos(0.62)))
dc = P.snap(SACK_SHAPE, [B + dn * 0.35], [dn], 0.25)[0]
dollar = raised_letter("$", SACK_SHAPE, dc, dn, (0, 1, 0), 0.27, height=0.012)
dollar_ob = part("SackDollar", dollar, ck.clay("#2a7a3a", 0.8), r.body, 0.0022, 520)
ck.join([sack_ob, rope_ob, bill_ob, dollar_ob], "MoneySack")

P.export_character("ricky")
for ob in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if ob.type == "MESH":
        print(f"[ricky] {ob.name:12s} parent={ob.parent.name:6s} {sum(len(p.vertices) - 2 for p in ob.data.polygons):6d} tris  {[m.name for m in ob.data.materials]}")
ck.preview("ricky")
hc = 0.47 * H + 0.36 * H + hy
P.pose_sheet(r, "ricky_pose", [
    dict(pose=dict(walk=0.45, armR=(-0.25, 0.1), armL=(0.2, 0.1)), eye=(2.3 * H, 0.62 * H, 0.5 * H), look=(0, 0.52 * H, 0), lens=50),
    dict(pose=dict(walk=0.45, phase=-math.pi / 2, armR=(-0.25, 0.1), armL=(0.2, 0.1)), eye=(-1.1 * H, 0.9 * H, -2.0 * H), look=(0, 0.6 * H, 0), lens=50),
    dict(pose=dict(armR=(-0.3, 0.1), armL=(0.0, 0.1), look=0.2), eye=(1.0 * H, 0.75 * H, 2.1 * H), look=(0, 0.55 * H, 0), lens=50),
    dict(pose=dict(armR=(-0.3, 0.1), armL=(0.0, 0.1), look=-0.2), eye=(0.25 * H, hc + 0.03 * H, 0.75 * H), look=(0, hc - 0.02 * H, 0), lens=55),
])
