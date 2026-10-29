"""person - the shared clay-puppet builder for every Tattletale character (makePerson in js/characters.js).

USE (one character per scene; build, export, then preview)
    import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import claykit as ck
    from lib import person as P
    ck.reset()
    r = P.make_person(h=1.76, skin="#e8b48a", pants="#1a1a1e", shoes="#0a0a0c", hair="#141010", style="short",
                      top_mat=P.stripes(["#141414", "#f4f0e6"], 0.02 * 1.76))
    P.in_hand(r, "R", my_prop, pos=(0, -0.02, 0.03))       # accessories (see below)
    P.export_character("ricky")     # godot/assets/models/characters/ricky.glb (+ blend), prints the rig check
    ck.preview("ricky")             # rest pose sheet
    P.pose_sheet(r, "ricky_pose")   # binoculars / walk / nod+look+mouth shut, posed like the game (not exported)

make_person(**o): the JS options, same names and defaults (H = h):
    h=1.8 skin top(=skin) pants="#33343a" shoes="#1c1c1e" hair(None = no hair) style=short|bob|bun|long|bald
    glasses mustache (colored like hair) belly (JS z-scale, e.g. 1.4) shirtless topMat/top_mat sleeveMat/sleeve_mat
    top_mat / sleeve_mat: a hex color, a bpy material, or P.stripes(colors, width) (striped clay, cut into bands)
  extras (all optional; defaults give a plain crew-neck tee, sneakers for bright shoes, shoes for dark ones):
    style also tuft (a baby curl) and curls (short tight curls); hair_flow=crown|back|side|center
    (part=+1/-1 picks the side for "side"), hair_volume, hair_line (raise/lower the hairline, degrees), cowlick
    collar=crew|v|scoop|polo|button|tank|none  sleeves=long|short|none  bust=0..1  tuck  belt=hex  pocket  rib
    diaper  button_color  shoe_style=sneaker|shoe|bare  sole=hex  laces  lace_color
    face: lid (upper lid cover 0..0.6) lid_low lid_tilt (+ = outer corners up) lashes eye_size pupil gaze=(x, y)
          brow={"raise": 0, "tilt": .3, "arch": 1, "thick": 1, "length": 1} (tilt + = inner ends up)
          brows=hex brow_ridge nose=round|button|long|broad
          nose_size ear_size cheeks chin lips=hex tongue=hex smile mouth_w mouth_shape=smile|o|flat
          mustache_style=walrus|brush|handlebar glasses_color  seed
    soft=True: skin/clothes use gloss_ at roughness .85 (finer thumbprints; for very small characters)

RETURNS a Person (dict with attribute access):
    rig legR legL body armR armL handR handL head    pivot empties, exactly as the README contract
    mouth                                           the "Mouth" mesh (child of Head, scale 1, modeled open)
    legs=[legR, legL] arms=[armR, armL]             like the JS rig arrays
    H hy hs                                         JS numbers: head sphere center (0, hy, 0) in Head, radius hs
    mats    skin top sleeve pants shoe sole hair brow mustache white black mouth lips tongue ... (bpy materials)
    meshes  "LegR" "LegL" "Body" "ArmR" "ArmL" "Head" -> the joined clay mesh under that pivot ("<pivot>_Mesh")
    sdf     "head" (Head-local skin) "hair" "torso" (Body-local) "hand" (ArmL-local) "leg": shapes to fit things to
    face    FaceMap: face(x, y) -> z of the face surface (Head-local), for things that sit on the face

ACCESSORIES (positions LOCAL to the pivot in game coords, like adding to a THREE.Group):
    attach(obj, pivot, pos, rot)     parent any object to r.head / r.body / r.handR / ... (rot = three.js Euler XYZ)
    in_hand(r, "R"|"L", obj, pos, rot)   held props; HandR/HandL sit at the hand's center (JS arms[i] (0,-.3H,0))
    on_head(r, el_deg, az_deg, out)  Head-local point on the head/hair surface (az 0 = front, 90 = +x, el 90 = top)
    head_top(r)                      Head-local y of the top of the head (hair included)
    clay_mesh(name, sdf, mat, parent, cell, target)   sculpt any SDF (below) into a clay part under a pivot
    head_band(r, y, height, thickness, color, tilt)   bandana / headband / mask hugging head+hair (tilt>0: front up)
    skull_cap(r, y, thickness, color, tilt, rim)      beanie / cap dome over the head above height y
    torso_band(r, width, thickness, color, angle, x, y)   sash / strap wrapped around the torso
    paper_hat(r)  earrings(r)  bow_tie(r)              ready-made pieces
    set_pose(r, walk, phase, armR, armL, lean, tilt, nod, look, bob, mouth)   the JS pose() for previews
    pose_sheet(r, id, tiles)  posed 2x2 render (default: binoculars x2, walk, nod/look with the mouth shut)
    check_rig()  binocular_check(r)   print the pivot contract check / where the hands land for binoculars
SDF SCULPTING (game coords, meters; negative inside):
    sphere ellipsoid capsule round_cone rbox torus cylinder tube(points, radii) loop_tube halfspace slab poly2d
    union(*s, k=blend) subtract(a, b, k) intersect(a, b, k) offset shell displace warp xform symmetric_x
    groove(s, pts, normals, r, reach) / seam(...) press creases / raise seams along a surface; patch(s, region, h)
    snap(s, pts, normals, reach) projects points onto a surface; ray_hit casts rays.
"""
import math, os, random
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix

import claykit as ck

BIG = 1e9


# ====================================================================== SDF clay sculpting
# A shape is an Sdf: f(P) -> signed distance for an (N, 3) array of GAME-coordinate points
# (negative inside), plus a bounding box. Combine primitives with union / smooth unions /
# subtraction, then sdf_mesh() turns it into a clay mesh (surface nets + decimate).

def _a(v):
    return np.asarray(v, dtype=np.float64)


def rotm(rot):
    """three.js Euler XYZ (game axes) -> 3x3 numpy matrix (local -> parent). None passes through."""
    if rot is None:
        return None
    if isinstance(rot, np.ndarray) and rot.shape == (3, 3):
        return rot
    rx, ry, rz = rot
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    X = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return X @ Y @ Z


class Sdf:
    __slots__ = ("f", "lo", "hi")

    def __init__(self, f, lo, hi):
        self.f, self.lo, self.hi = f, _a(lo), _a(hi)

    def __call__(self, p):
        return self.f(np.atleast_2d(_a(p)))

    def __or__(self, o):
        return union(self, o)

    def __sub__(self, o):
        return subtract(self, o)

    def __and__(self, o):
        return intersect(self, o)


_MARGIN = [0.02]   # set by the polygonizer: children farther than this from a point are skipped


def _inbox(p, lo, hi):
    return ((p[:, 0] >= lo[0]) & (p[:, 0] <= hi[0]) & (p[:, 1] >= lo[1]) & (p[:, 1] <= hi[1])
            & (p[:, 2] >= lo[2]) & (p[:, 2] <= hi[2]))


def _eval(s, p, extra=0.0):
    """Evaluate s only where p is inside its (padded) box; BIG elsewhere."""
    m = _inbox(p, s.lo - _MARGIN[0] - extra, s.hi + _MARGIN[0] + extra)
    out = np.full(len(p), BIG)
    if m.all():
        return s.f(p)
    if m.any():
        idx = np.nonzero(m)[0]
        out[idx] = s.f(p[idx])
    return out


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


# ---- primitives (all positions in the part's local game coords)
def sphere(c, r):
    c = _a(c)
    return Sdf(lambda p: np.sqrt(((p - c) ** 2).sum(1)) - r, c - r, c + r)


def ellipsoid(c, rad, rot=None):
    c, rad = _a(c), _a(rad)
    R = rotm(rot)

    def f(p):
        q = p - c
        if R is not None:
            q = q @ R
        k0 = np.sqrt(((q / rad) ** 2).sum(1))
        k1 = np.sqrt(((q / (rad * rad)) ** 2).sum(1))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
    e = rad.max() if R is not None else rad
    return Sdf(f, c - e, c + e)


def round_cone(a, b, ra, rb):
    """Tapered capsule from a (radius ra) to b (radius rb). Exact (Inigo Quilez)."""
    a, b = _a(a), _a(b)
    ba = b - a
    l2 = float(ba @ ba)
    if l2 < 1e-14:
        return sphere(a, max(ra, rb))
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    def f(p):
        pa = p - a
        y = pa @ ba
        z = y - l2
        x2 = ((pa * l2 - np.outer(y, ba)) ** 2).sum(1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d1 = np.sqrt(x2 + z2) * il2 - rb
        d2 = np.sqrt(x2 + y2) * il2 - ra
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - ra
        return np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))
    lo = np.minimum(a - ra, b - rb)
    hi = np.maximum(a + ra, b + rb)
    return Sdf(f, lo, hi)


def capsule(a, b, r):
    return round_cone(a, b, r, r)


def rbox(c, half, r=0.0, rot=None):
    """Rounded box: half extents (game x, y, z), corner radius r."""
    c, half = _a(c), _a(half)
    R = rotm(rot)

    def f(p):
        q = p - c
        if R is not None:
            q = q @ R
        q = np.abs(q) - (half - r)
        return np.sqrt((np.maximum(q, 0) ** 2).sum(1)) + np.minimum(q.max(1), 0) - r
    e = np.linalg.norm(half) if R is not None else half
    return Sdf(f, c - e, c + e)


def torus(c, R_, r, rot=None):
    """Ring of radius R_ in the local XZ plane (axis = local y), tube radius r."""
    c = _a(c)
    M = rotm(rot)

    def f(p):
        q = p - c
        if M is not None:
            q = q @ M
        qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - R_
        return np.sqrt(qx ** 2 + q[:, 1] ** 2) - r
    e = R_ + r
    return Sdf(f, c - e, c + e)


def cylinder(c, r, h, round_=0.0, rot=None):
    """Capped cylinder along local y, radius r, half height h, edge rounding round_."""
    c = _a(c)
    M = rotm(rot)

    def f(p):
        q = p - c
        if M is not None:
            q = q @ M
        dx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - r + round_
        dy = np.abs(q[:, 1]) - h + round_
        return (np.minimum(np.maximum(dx, dy), 0) + np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2) - round_)
    e = math.hypot(r, h) if M is not None else np.array([r, h, r])
    return Sdf(f, c - e, c + e)


def halfspace(point, normal):
    """Everything on the -normal side of the plane is inside."""
    point, n = _a(point), _a(normal)
    n = n / np.linalg.norm(n)
    return Sdf(lambda p: (p - point) @ n, [-BIG] * 3, [BIG] * 3)


def catmull(pts, n=6):
    """Catmull-Rom through pts (list of 3-vectors) -> denser polyline."""
    P = [_a(p) for p in pts]
    if len(P) < 3:
        return P
    P = [2 * P[0] - P[1]] + P + [2 * P[-1] - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return out


def tube(pts, radii, n=5, k=0.0):
    """Smooth tapered tube through control points (a clay 'sausage'): hair locks, brows, rims.
    radii: one value or one per control point."""
    if np.isscalar(radii):
        radii = [radii] * len(pts)
    P = catmull(pts, n)
    R = np.interp(np.linspace(0, 1, len(P)), np.linspace(0, 1, len(radii)), radii)
    segs = [round_cone(P[i], P[i + 1], R[i], R[i + 1]) for i in range(len(P) - 1)]
    return union(*segs, k=k)


# ---- operations
def union(*ss, k=0.0):
    ss = [s for s in ss if s is not None]
    if len(ss) == 1:
        return ss[0]
    lo = np.min([s.lo for s in ss], 0) - k
    hi = np.max([s.hi for s in ss], 0) + k

    def f(p):
        d = np.full(len(p), BIG)
        for s in ss:
            m = _inbox(p, s.lo - _MARGIN[0] - k, s.hi + _MARGIN[0] + k)
            if not m.any():
                continue
            if m.all():
                ds = s.f(p)
                d = smin(d, ds, k) if k > 0 else np.minimum(d, ds)
            else:
                idx = np.nonzero(m)[0]
                ds = s.f(p[idx])
                d[idx] = smin(d[idx], ds, k) if k > 0 else np.minimum(d[idx], ds)
        return d
    return Sdf(f, lo, hi)


def subtract(a, b, k=0.0):
    """a minus b (smooth when k > 0)."""
    def f(p):
        da = a.f(p)
        db = _eval(b, p, k)
        return smax(da, -db, k) if k > 0 else np.maximum(da, -db)
    return Sdf(f, a.lo, a.hi)


def intersect(a, b, k=0.0):
    def f(p):
        da = a.f(p)
        db = _eval(b, p, k)
        return smax(da, db, k) if k > 0 else np.maximum(da, db)
    return Sdf(f, np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def shell(s, t):
    """Hollow skin of thickness 2t around s's surface."""
    return Sdf(lambda p: np.abs(s.f(p)) - t, s.lo - t, s.hi + t)


def offset(s, d):
    """Grow (d > 0) or shrink the shape."""
    return Sdf(lambda p: s.f(p) - d, s.lo - max(d, 0), s.hi + max(d, 0))


def displace(s, fn, amp):
    """Add fn(p) (meters, + = outward) to the surface; amp = max |fn| for the bounds."""
    return Sdf(lambda p: s.f(p) - fn(p), s.lo - amp, s.hi + amp)


def warp(s, fn, pad=0.0):
    """Evaluate s at fn(p) (a gentle domain warp: bends, curls)."""
    return Sdf(lambda p: s.f(fn(p)), s.lo - pad, s.hi + pad)


def xform(s, pos=(0, 0, 0), rot=None, scale=1.0):
    """Place a shape built around the origin: rotate (three.js Euler XYZ), uniform scale, move."""
    pos = _a(pos)
    R = rotm(rot)
    if R is None:
        R = np.eye(3)

    def f(p):
        return s.f(((p - pos) @ R) / scale) * scale
    corners = np.array([[x, y, z] for x in (s.lo[0], s.hi[0]) for y in (s.lo[1], s.hi[1]) for z in (s.lo[2], s.hi[2])])
    w = (corners * scale) @ R.T + pos
    return Sdf(f, w.min(0), w.max(0))


def mirror_x(s):
    return Sdf(lambda p: s.f(p * np.array([-1.0, 1.0, 1.0])), [-s.hi[0], s.lo[1], s.lo[2]], [-s.lo[0], s.hi[1], s.hi[2]])


def symmetric_x(s):
    """Shape built for x > 0 duplicated onto x < 0 (evaluated at |x|)."""
    def f(p):
        q = p.copy()
        q[:, 0] = np.abs(q[:, 0])
        return s.f(q)
    e = max(abs(s.lo[0]), abs(s.hi[0]))
    return Sdf(f, [-e, s.lo[1], s.lo[2]], [e, s.hi[1], s.hi[2]])


# ---- noise (vectorized, seeded) for lumps and textures
def _hash3(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(p, freq=1.0, seed=0):
    """Smooth value noise in [-1, 1]."""
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    u = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = ((u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2]))
                out = out + w * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out * 2 - 1


def worley(p, cell, seed=0):
    """Distance to the nearest jittered feature point (F1), in units of cell."""
    q = p / cell
    i = np.floor(q).astype(np.int64)
    best = np.full(len(p), 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz
                fx = cx + _hash3(cx, cy, cz, seed)
                fy = cy + _hash3(cx, cy, cz, seed + 1)
                fz = cz + _hash3(cx, cy, cz, seed + 2)
                d = (q[:, 0] - fx) ** 2 + (q[:, 1] - fy) ** 2 + (q[:, 2] - fz) ** 2
                best = np.minimum(best, d)
    return np.sqrt(best)


# ---- meshing
def _grid_eval(s, lo, cell, shape, P=None):
    nx, ny, nz = shape
    xs = lo[0] + np.arange(nx) * cell
    ys = lo[1] + np.arange(ny) * cell
    zs = lo[2] + np.arange(nz) * cell
    F = np.empty(shape, np.float32)
    step = max(1, 400000 // (ny * nz))
    for i0 in range(0, nx, step):
        i1 = min(nx, i0 + step)
        X, Y, Z = np.meshgrid(xs[i0:i1], ys, zs, indexing="ij")
        F[i0:i1] = s.f(np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)).reshape(i1 - i0, ny, nz)
    return F


def _eval_points(s, pts):
    out = np.empty(len(pts))
    for i0 in range(0, len(pts), 300000):
        out[i0:i0 + 300000] = s.f(pts[i0:i0 + 300000])
    return out


def sample_grid(s, cell, coarse=4):
    """Narrow-band sampling: coarse grid first, exact values only near the surface."""
    lo = s.lo - 3 * cell
    hi = s.hi + 3 * cell
    cc = cell * coarse
    nc = np.ceil((hi - lo) / cc).astype(int) + 2
    _MARGIN[0] = cc * 2.0
    Fc = _grid_eval(s, lo, cc, tuple(nc))
    A = np.abs(Fc) < cc * 1.25
    S = Fc < 0
    M = np.zeros(tuple(nc - 1), bool)
    mn = np.zeros(tuple(nc - 1), bool)
    mx = np.zeros(tuple(nc - 1), bool)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                sl = (slice(dx, dx + nc[0] - 1), slice(dy, dy + nc[1] - 1), slice(dz, dz + nc[2] - 1))
                M |= A[sl]
                mn |= S[sl]
                mx |= ~S[sl]
    M |= mn & mx
    nf = (nc - 1) * coarse + 1
    Mf = np.repeat(np.repeat(np.repeat(M, coarse, 0), coarse, 1), coarse, 2)
    Pm = np.zeros(tuple(nf), bool)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                Pm[dx:dx + nf[0] - 1, dy:dy + nf[1] - 1, dz:dz + nf[2] - 1] |= Mf
    ix = [np.minimum(np.rint(np.arange(nf[a]) / coarse).astype(int), nc[a] - 1) for a in range(3)]
    F = Fc[np.ix_(ix[0], ix[1], ix[2])].astype(np.float32)
    idx = np.nonzero(Pm)
    pts = lo + np.stack(idx, 1) * cell
    _MARGIN[0] = cell * 3.0
    F[idx] = _eval_points(s, pts)
    return F, lo


def surface_nets(F, lo, cell):
    """Quad mesh of the zero level set (one vertex per sign-changing cell)."""
    inside = F < 0
    nx, ny, nz = F.shape
    cid = lambda i, j, k: (i * (ny - 1) + j) * (nz - 1) + k
    all_ids, all_pts, quads = [], [], []
    for ax in range(3):
        if ax == 0:
            e = inside[:-1] != inside[1:]
        elif ax == 1:
            e = inside[:, :-1] != inside[:, 1:]
        else:
            e = inside[:, :, :-1] != inside[:, :, 1:]
        i, j, k = np.nonzero(e)
        if len(i) == 0:
            continue
        f0 = F[i, j, k].astype(np.float64)
        f1 = F[i + (ax == 0), j + (ax == 1), k + (ax == 2)].astype(np.float64)
        t = f0 / (f0 - f1)
        p = np.stack([i, j, k], 1).astype(np.float64)
        p[:, ax] += t
        if ax == 0:
            cs = [(i, j - 1, k - 1), (i, j, k - 1), (i, j, k), (i, j - 1, k)]
        elif ax == 1:
            cs = [(i - 1, j, k - 1), (i - 1, j, k), (i, j, k), (i, j, k - 1)]
        else:
            cs = [(i - 1, j - 1, k), (i, j - 1, k), (i, j, k), (i - 1, j, k)]
        ids = np.stack([cid(*c) for c in cs], 1)
        for c in range(4):
            all_ids.append(ids[:, c])
            all_pts.append(p)
        quads.append((ids, f0 < 0))
    if not quads:
        return np.zeros((0, 3)), np.zeros((0, 4), int)
    all_ids = np.concatenate(all_ids)
    all_pts = np.concatenate(all_pts)
    uniq, inv = np.unique(all_ids, return_inverse=True)
    cnt = np.bincount(inv)
    V = np.stack([np.bincount(inv, weights=all_pts[:, a]) for a in range(3)], 1) / cnt[:, None]
    V = lo + V * cell
    faces = []
    for ids, ins in quads:
        vi = np.searchsorted(uniq, ids)
        vi[~ins] = vi[~ins][:, ::-1]
        faces.append(vi)
    return V, np.concatenate(faces)


def project(s, V, cell, iters=2):
    """Newton steps that pull vertices onto the true surface (sharper, more accurate)."""
    _MARGIN[0] = cell * 3.0
    h = cell * 0.25
    for _ in range(iters):
        d = _eval_points(s, V)
        g = np.zeros_like(V)
        for a in range(3):
            e = np.zeros(3)
            e[a] = h
            g[:, a] = (_eval_points(s, V + e) - _eval_points(s, V - e)) / (2 * h)
        g2 = np.maximum((g * g).sum(1), 1e-12)
        step = (d / g2)[:, None] * g
        n = np.linalg.norm(step, axis=1)
        lim = np.minimum(1.0, cell * 0.75 / np.maximum(n, 1e-12))
        V = V - step * lim[:, None]
    return V


def mesh_from_arrays(name, V, Q):
    """Game-coordinate verts/quads -> Blender mesh object (not linked to a parent)."""
    Vb = np.stack([V[:, 0], -V[:, 2], V[:, 1]], 1)
    me = bpy.data.meshes.new(name)
    me.from_pydata(Vb.tolist(), [], Q.tolist())
    me.validate(clean_customdata=False)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def decimate(obj, target_tris, sym=False):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if target_tris and tris > target_tris:
        md = obj.modifiers.new("dec", "DECIMATE")
        md.decimate_type = "COLLAPSE"
        md.ratio = max(0.001, target_tris / tris)
        md.use_collapse_triangulate = True
        if sym:
            md.use_symmetry = True
            md.symmetry_axis = "X"
        ck._apply_modifiers(obj)
    return obj


def _mesh_verts(obj):
    me = obj.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)


def _sdf_grad(s, P, h):
    g = np.zeros_like(P)
    for a in range(3):
        e = np.zeros(3)
        e[a] = h
        g[:, a] = _eval_points(s, P + e) - _eval_points(s, P - e)
    return g / (2 * h)


def reproject(obj, s, cell):
    """Pull a decimated mesh's vertices back onto the true surface (one Newton step)."""
    _MARGIN[0] = cell * 3.0
    P = _mesh_verts(obj)
    d = _eval_points(s, P)
    g = _sdf_grad(s, P, cell * 0.25)
    step = (d / np.maximum((g * g).sum(1), 1e-12))[:, None] * g
    n = np.linalg.norm(step, axis=1)
    step *= np.minimum(1.0, cell * 0.75 / np.maximum(n, 1e-12))[:, None]
    P = P - step
    obj.data.vertices.foreach_set("co", np.stack([P[:, 0], -P[:, 2], P[:, 1]], 1).ravel())
    obj.data.update()


def sdf_normals(obj, s, cell):
    """Smooth shading straight from the shape: custom normals = the SDF gradient at each vertex,
    so long decimated triangles never streak."""
    _MARGIN[0] = cell * 3.0
    P = _mesh_verts(obj)
    g = _sdf_grad(s, P, cell)
    ln = np.linalg.norm(g, axis=1)
    vn = np.empty(len(P) * 3)
    obj.data.vertices.foreach_get("normal", vn)
    vn = vn.reshape(-1, 3)
    vn = np.stack([vn[:, 0], vn[:, 2], -vn[:, 1]], 1)
    ok = ln > 1e-9
    g[ok] /= ln[ok][:, None]
    ok &= (g * vn).sum(1) > 0.2     # the field disagrees with the mesh (thin spots): trust the mesh
    g[~ok] = vn[~ok]
    nb = np.stack([g[:, 0], -g[:, 2], g[:, 1]], 1)
    try:
        obj.data.normals_split_custom_set_from_vertices([tuple(v) for v in nb])
    except Exception as e:
        print(f"[person] custom normals failed on {obj.name}: {e}")


def sdf_mesh(name, s, m, cell, target=None, parent=None, sym=False, lumps=0.0, lump_freq=None, seed=0, project_iters=2):
    """Mesh an Sdf (built in the parent's local game coords) into a clay part.
    cell = sampling size in meters (small features need ~1/4 of their thickness);
    target = triangle budget (decimated down to it); lumps = hand-made wobble in meters (pressed
    into the shape before meshing); m = material, hex color or a Stripes painter."""
    if lumps > 0:
        freq = lump_freq or 1.0 / (140.0 * lumps)
        base = s
        s = displace(base, lambda p: lumps * vnoise(p, freq, seed), lumps)
    F, lo = sample_grid(s, cell)
    V, Q = surface_nets(F, lo, cell)
    if len(V) == 0:
        print(f"[person] WARNING: {name} produced no surface")
        return None
    if project_iters:
        V = project(s, V, cell, project_iters)
    obj = mesh_from_arrays(name, V, Q)
    decimate(obj, int(target * 0.5) if (target and isinstance(m, Stripes)) else target, sym)
    obj.data.validate()
    reproject(obj, s, cell)
    _finish(obj, (ck.clay(m) if isinstance(m, str) else m) if m is not None else ck.clay("#808080"))
    ck.smooth(obj, 180)
    sdf_normals(obj, s, cell)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
    return obj


# ====================================================================== helpers
def _rgb01(h):
    h = ck.PAL.get(h, h).lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def hexmix(a, b, t):
    """Blend two hex colors (t = 0 -> a, 1 -> b)."""
    c = _rgb01(a) * (1 - t) + _rgb01(b) * t
    return "#%02x%02x%02x" % tuple(int(round(v * 255)) for v in np.clip(c, 0, 1))


def shade(h, f):
    """f < 1 darker, f > 1 lighter (toward white)."""
    return hexmix(h, "#000000", 1 - f) if f <= 1 else hexmix(h, "#ffffff", min(1.0, f - 1))


def luma(h):
    c = _rgb01(h)
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def chroma(h):
    c = _rgb01(h)
    return float(c.max() - c.min())


def _unit(v):
    v = _a(v)
    return v / np.linalg.norm(v)


def _basis(axis):
    """Two unit vectors perpendicular to axis (and each other)."""
    a = _unit(axis)
    t = np.array([1.0, 0, 0]) if abs(a[0]) < 0.9 else np.array([0, 0, 1.0])
    u = _unit(np.cross(a, t))
    return u, np.cross(a, u)


def frame_y(axis):
    """3x3 matrix whose local y is `axis` (orients torus / cylinder SDFs)."""
    a = _unit(axis)
    u, v = _basis(a)
    return np.stack([u, a, v], 1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def slab(y0, y1):
    """Everything between heights y0 and y1."""
    return intersect(halfspace((0, y1, 0), (0, 1, 0)), halfspace((0, y0, 0), (0, -1, 0)))


def poly2d(pts):
    """Prism along z from a 2D polygon in the (x, y) plane (exact 2D distance, IQ's sdPolygon)."""
    P = np.array(pts, float)
    m = len(P)

    def f(p):
        x, y = p[:, 0], p[:, 1]
        d = np.full(len(p), np.inf)
        s = np.ones(len(p))
        for i in range(m):
            a, b = P[i], P[(i + 1) % m]
            e = b - a
            wx, wy = x - a[0], y - a[1]
            h = np.clip((wx * e[0] + wy * e[1]) / (e @ e), 0, 1)
            d = np.minimum(d, (wx - e[0] * h) ** 2 + (wy - e[1] * h) ** 2)
            c1, c2, c3 = y >= a[1], y < b[1], e[0] * wy > e[1] * wx
            s = np.where((c1 & c2 & c3) | (~c1 & ~c2 & ~c3), -s, s)
        return s * np.sqrt(d)
    return Sdf(f, [P[:, 0].min(), P[:, 1].min(), -BIG], [P[:, 0].max(), P[:, 1].max(), BIG])


def ellipse2d(c, rx, ry):
    """Elliptic prism along z (approximate distance)."""
    cx, cy = c

    def f(p):
        x, y = (p[:, 0] - cx) / rx, (p[:, 1] - cy) / ry
        k0 = np.sqrt(x * x + y * y)
        k1 = np.sqrt((x / rx) ** 2 + (y / ry) ** 2)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
    return Sdf(f, [cx - rx, cy - ry, -BIG], [cx + rx, cy + ry, BIG])


def loft(ys, rx, rz, zc=None):
    """Elliptic body through cross-sections (height, x radius, z radius[, z center]), smoothly
    interpolated, flat caps at both ends. The workhorse for torsos."""
    n = len(ys)
    zc = zc or [0.0] * n
    T = np.array(catmull([(ys[i], rx[i], rz[i], zc[i]) for i in range(n)], 12))
    T = T[np.argsort(T[:, 0])]
    Y, RX, RZ, ZC = T[:, 0], T[:, 1], T[:, 2], T[:, 3]
    y0, y1 = ys[0], ys[-1]

    def f(p):
        y = p[:, 1]
        yc = np.clip(y, y0, y1)
        a, b, zo = np.interp(yc, Y, RX), np.interp(yc, Y, RZ), np.interp(yc, Y, ZC)
        x, z = p[:, 0] / a, (p[:, 2] - zo) / b
        k0 = np.sqrt(x * x + z * z)
        k1 = np.sqrt((x / a) ** 2 + (z / b) ** 2)
        dr = k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
        dc = np.maximum(y0 - y, y - y1)
        return np.where((dr > 0) & (dc > 0), np.sqrt(dr * dr + dc * dc), np.maximum(dr, dc))
    m = max(RX.max(), RZ.max() + np.abs(ZC).max())
    return Sdf(f, [-m, y0, -m], [m, y1, m])


def loop_tube(pts, radii, n=4, k=0.0):
    """Closed smooth tube through a ring of points (collars, lips, rims)."""
    P = [_a(p) for p in pts]
    m = len(P)
    if np.isscalar(radii):
        radii = [radii] * m
    out, rad = [], []
    for i in range(m):
        p0, p1, p2, p3 = P[(i - 1) % m], P[i], P[(i + 1) % m], P[(i + 2) % m]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            rad.append(radii[i] * (1 - t) + radii[(i + 1) % m] * t)
    out.append(out[0])
    rad.append(rad[0])
    return union(*[round_cone(out[i], out[i + 1], rad[i], rad[i + 1]) for i in range(len(out) - 1)], k=k)


def ray_hit(s, origins, dirs, tmax, steps=80):
    """Distance along each ray to the first outside->inside crossing (nan if none)."""
    _MARGIN[0] = max(_MARGIN[0], 0.02)
    O = np.atleast_2d(_a(origins))
    D = np.atleast_2d(_a(dirs))
    if len(D) == 1 and len(O) > 1:
        D = np.repeat(D, len(O), 0)
    D = D / np.linalg.norm(D, axis=1)[:, None]
    ts = np.linspace(0, tmax, steps)
    F = _eval_points(s, (O[:, None, :] + D[:, None, :] * ts[None, :, None]).reshape(-1, 3)).reshape(len(O), steps)
    ins = F < 0
    first = np.argmax(ins, 1)
    ok = ins.any(1) & (first > 0)
    lo, hi = ts[np.maximum(first - 1, 0)].copy(), ts[first].copy()
    for _ in range(24):
        mid = 0.5 * (lo + hi)
        out = _eval_points(s, O + D * mid[:, None]) >= 0
        lo, hi = np.where(out, mid, lo), np.where(out, hi, mid)
    t = 0.5 * (lo + hi)
    t[~ok] = np.nan
    return t


def snap(s, pts, normals, reach, lift=0.0):
    """Project rough points onto the surface of s (casting inward along -normals), then lift along them."""
    pts = np.atleast_2d(_a(pts))
    N = np.atleast_2d(_a(normals))
    if len(N) == 1:
        N = np.repeat(N, len(pts), 0)
    N = N / np.linalg.norm(N, axis=1)[:, None]
    O = pts + N * reach
    t = ray_hit(s, O, -N, 2 * reach)
    t = np.where(np.isnan(t), reach, t)
    return O - N * (t - lift)[:, None]


def radial(pts, center=(0, 0, 0), axis_y=True):
    """Outward normals from a vertical axis through center (axis_y) or from the center point."""
    P = np.atleast_2d(_a(pts)) - _a(center)
    if axis_y:
        P[:, 1] = 0
    return P / np.maximum(np.linalg.norm(P, axis=1)[:, None], 1e-9)


def groove(s, pts, normals, r, reach, k=None, lift=0.25):
    """Press a crease into s along a curve of rough surface points (smooth tube subtraction)."""
    P = snap(s, pts, normals, reach, lift=r * lift)
    return subtract(s, tube(list(P), r, n=5), k=k if k is not None else r * 0.8)


def seam(s, pts, normals, r, reach, k=None, lift=-0.3):
    """Raised clay seam/rim along a curve on the surface."""
    P = snap(s, pts, normals, reach, lift=r * lift)
    return union(s, tube(list(P), r, n=5), k=k if k is not None else r * 0.5)


def patch(s, region, height, k=None):
    """A flat clay patch (pocket, placket, collar flap) lying on s inside `region`, `height` proud."""
    return intersect(offset(s, height), region, k=k if k is not None else height * 0.6)


def edge_band(s, region, height, width):
    """A raised binding along the border of a cut-out region (necklines, armholes)."""
    return intersect(offset(s, height), subtract(offset(region, width), region))


class FaceMap:
    """Height field z(x, y) of a surface seen from +z (the face): place brows, lips, mustaches on it."""

    def __init__(self, s, x0, x1, y0, y1, zfront, zback, n=56):
        self.xs, self.ys = np.linspace(x0, x1, n), np.linspace(y0, y1, n)
        X, Y = np.meshgrid(self.xs, self.ys, indexing="ij")
        O = np.stack([X.ravel(), Y.ravel(), np.full(X.size, zfront)], 1)
        t = ray_hit(s, O, [(0, 0, -1)], zfront - zback, steps=140)
        self.Z = np.where(np.isnan(t), zback, zfront - t).reshape(n, n)

    def __call__(self, x, y):
        x, y = np.asarray(x, float), np.asarray(y, float)
        fx = np.clip((x - self.xs[0]) / (self.xs[1] - self.xs[0]), 0, len(self.xs) - 1.001)
        fy = np.clip((y - self.ys[0]) / (self.ys[1] - self.ys[0]), 0, len(self.ys) - 1.001)
        i, j = np.floor(fx).astype(int), np.floor(fy).astype(int)
        u, v = fx - i, fy - j
        Z = self.Z
        return Z[i, j] * (1 - u) * (1 - v) + Z[i + 1, j] * u * (1 - v) + Z[i, j + 1] * (1 - u) * v + Z[i + 1, j + 1] * u * v


def _periodic(pts_deg, smooth_deg=5, mirror=True):
    """[(az_deg, value_deg), ...] for az >= 0 (mirrored to az < 0) -> f(az_rad) -> value_rad."""
    pts = list(pts_deg)
    if mirror:
        pts = pts + [(-a, v) for a, v in pts if 0 < a < 180]
    pts.sort()
    a = np.array([p[0] for p in pts], float)
    v = np.array([p[1] for p in pts], float)
    grid = np.arange(-180, 180, 1.0)
    tab = np.interp(grid, np.concatenate([a - 360, a, a + 360]), np.concatenate([v, v, v]))
    if smooth_deg:
        k = int(smooth_deg)
        tab = np.convolve(np.concatenate([tab[-k:], tab, tab[:k]]), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    tab = np.radians(tab)
    return lambda az: np.interp(np.degrees(az), grid, tab, period=360)


def _stable_seed(*parts):
    import zlib
    return zlib.crc32("|".join(str(p) for p in parts).encode()) % 100000


def _rot(obj, euler):
    """Set a pivot's rotation from a three.js Euler XYZ (game axes), like obj.rotation.set(x, y, z)."""
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = ck.grot(*euler).to_quaternion()


def attach(obj, pivot, pos=(0, 0, 0), rot=None):
    """Parent obj to a pivot (e.g. r.head, r.handR) at a LOCAL game-coord transform."""
    obj.parent = pivot
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = ck.G(pos)
    if rot is not None:
        _rot(obj, rot)
    return obj


def in_hand(r, side, obj, pos=(0, 0, 0), rot=None):
    """Put a prop in the right ("R") or left ("L") hand; pos is relative to the hand's center."""
    return attach(obj, r.handR if side.upper().startswith("R") else r.handL, pos, rot)


# ====================================================================== materials and stripes
class Stripes:
    """Striped clay for top_mat / sleeve_mat (Ricky's shirt): bands `width` meters tall along
    the part's local y, cycling through `colors`. The mesh is cut along each band edge."""

    def __init__(self, colors, width, phase=0.0, rough=0.9):
        self.colors, self.width, self.phase, self.rough = list(colors), width, phase, rough

    def materials(self):
        return [ck.clay(c, self.rough) for c in self.colors]

    def apply(self, obj):
        me = obj.data
        bm = bmesh.new()
        bm.from_mesh(me)
        zs = [v.co.z for v in bm.verts]
        for k in range(math.floor((min(zs) - self.phase) / self.width), math.ceil((max(zs) - self.phase) / self.width) + 1):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, self.phase + k * self.width), plane_no=(0, 0, 1))
        me.materials.clear()
        for m in self.materials():
            me.materials.append(m)
        for f in bm.faces:
            f.material_index = int(math.floor((f.calc_center_median().z - self.phase) / self.width)) % len(self.colors)
        bm.to_mesh(me)
        bm.free()
        return obj


def stripes(colors, width, phase=0.0, rough=0.9):
    return Stripes(colors, width, phase, rough)


def _finish(obj, m):
    """Assign a material, or let a Stripes painter color the part."""
    if obj is None:
        return None
    if isinstance(m, Stripes):
        m.apply(obj)
    else:
        ck.assign(obj, m)
    return obj


class Person(dict):
    """The rig: pivots, sizes, materials, meshes and SDFs (a dict with attribute access)."""
    __getattr__ = dict.__getitem__

    def __setattr__(self, k, v):
        self[k] = v


# ====================================================================== options
def _opts(o):
    o = dict(o)
    for js, py in (("topMat", "top_mat"), ("sleeveMat", "sleeve_mat")):
        if js in o:
            o[py] = o.pop(js)
    d = dict(h=1.8, skin="#c8a888", top=None, pants="#33343a", shoes="#1c1c1e", hair=None, style="short",
             glasses=False, mustache=False, belly=0.0, shirtless=False, top_mat=None, sleeve_mat=None,
             collar=None, sleeves=None, bust=0.0, tuck=False, belt=None, pocket=False, rib=False, diaper=False,
             button_color=None, shoe_style=None, sole=None, laces=None, lace_color="#f4f0e6",
             lips=None, tongue="#a8464e", smile=0.5, mouth_w=1.0, mouth_shape="smile",
             brows=None, brow=None, brow_ridge=1.0, lid=0.2, lid_low=0.1, lid_tilt=0.0, lashes=False,
             eye_size=1.0, pupil=1.0, gaze=(0.0, 0.0), nose="round", nose_size=1.0, ear_size=1.0,
             cheeks=1.0, chin=1.0, hair_flow=None, part=1, hair_volume=1.0, hair_line=0.0, cowlick=False,
             mustache_style="walrus", glasses_color="#0a0a0c", bun_tie=None, soft=False, seed=None)
    d.update(o)
    o = d
    if o["top"] is None:
        o["top"] = o["skin"]                                     # JS: clay(o.top || o.skin)
    if o["collar"] is None:
        o["collar"] = "none" if o["shirtless"] else "crew"
    if o["sleeves"] is None:
        o["sleeves"] = "none" if (o["shirtless"] or o["collar"] == "tank") else "long"
    if o["shoe_style"] is None:
        sh = o["shoes"].lower()
        o["shoe_style"] = "bare" if sh == o["skin"].lower() else ("sneaker" if (chroma(sh) > 0.35 or luma(sh) > 0.55) else "shoe")
    if o["sole"] is None:
        if o["shoe_style"] == "sneaker":
            o["sole"] = shade(o["shoes"], 0.84) if luma(o["shoes"]) > 0.7 else "#f2eee4"
        else:
            o["sole"] = "#3b302a" if luma(o["shoes"]) < 0.08 else shade(o["shoes"], 0.55)
    if o["laces"] is None:
        o["laces"] = o["shoe_style"] == "sneaker"
    if o["lips"] is None:
        o["lips"] = shade(hexmix(o["skin"], "#a8484a", 0.3), 0.86)
    if o["brows"] is None:
        o["brows"] = o["hair"] if o["hair"] else shade(o["skin"], 0.45)
    if o["seed"] is None:
        o["seed"] = _stable_seed(o["h"], o["skin"], o["top"], o["pants"], o["hair"], o["style"])
    if o["button_color"] is None:
        o["button_color"] = "#f4f0e6" if luma(o["top"]) < 0.7 else "#c8c0b0"
    return o


# ====================================================================== legs and shoes
def _leg_sdf(r):
    """Pants leg for the LEFT leg (leg-local): hip ball, tapered tube, knee, rolled cuff, creases."""
    H = r.H
    yc = -0.386 * H
    leg = union(sphere((0, 0, 0), 0.059 * H), round_cone((0, 0, 0), (0, yc, 0.004 * H), 0.059 * H, 0.0545 * H), k=0.02 * H)
    leg = union(leg, ellipsoid((0, -0.215 * H, 0.013 * H), (0.05 * H, 0.05 * H, 0.044 * H)), k=0.035 * H)
    leg = union(leg, torus((0, yc - 0.003 * H, 0.004 * H), 0.0535 * H, 0.0082 * H), k=0.004 * H)
    leg = intersect(leg, halfspace((0, yc - 0.0095 * H, 0), (0, -1, 0)), k=0.004 * H)
    base = leg
    # creases: front of the knee, back of the knee, a little stacking above the cuff
    cr = 0.0034 * H
    for y, front, wob in ((-0.19, 1, 0.012), (-0.232, 1, -0.01), (-0.205, -1, -0.012), (-0.248, -1, 0.012),
                          (-0.338, 1, 0.01), (-0.352, -1, -0.008)):
        a = np.linspace(-1.0, 1.0, 5)
        pts = [(0.06 * H * math.sin(t), (y + wob * t) * H, front * 0.06 * H * math.cos(t)) for t in a]
        leg = groove(leg, pts, radial(pts), cr, 0.05 * H)
    r.sdf["leg"] = base
    return leg


def _shoe_sdfs(r):
    """(upper, sole, extras: list of (sdf, material key)) for the LEFT foot, leg-local."""
    H, o = r.H, r.opts
    yg = -0.47 * H
    style = o["shoe_style"]
    if style == "bare":
        foot = union(ellipsoid((0.002 * H, yg + 0.024 * H, 0.03 * H), (0.041 * H, 0.025 * H, 0.068 * H)),
                     sphere((0, yg + 0.029 * H, -0.02 * H), 0.031 * H),
                     cylinder((0, yg + 0.066 * H, -0.006 * H), 0.035 * H, 0.03 * H, round_=0.01 * H), k=0.024 * H)
        toes = []
        for i, (x, rad) in enumerate(((-0.023, 0.0118), (-0.0095, 0.0098), (0.003, 0.0092), (0.0145, 0.0086), (0.0245, 0.0078))):
            z = 0.088 - 0.0035 * abs(i - 0.6) ** 1.6
            toes.append(sphere((x * H, yg + 0.0125 * H + rad * H * 0.6, z * H), rad * H))
        foot = union(foot, *toes, k=0.005 * H)
        foot = intersect(foot, halfspace((0, yg, 0), (0, -1, 0)), k=0.003 * H)
        return foot, None, []
    st = (0.014 if style == "sneaker" else 0.012) * H
    sole = union(cylinder((0, yg + st * 0.5, -0.012 * H), 0.046 * H, st * 0.5, round_=0.0055 * H),
                 cylinder((-0.003 * H, yg + st * 0.5, 0.074 * H), 0.0515 * H, st * 0.5, round_=0.0055 * H), k=0.05 * H)
    if style == "shoe":   # a heel block under the back
        sole = union(sole, cylinder((0, yg + 0.011 * H, -0.017 * H), 0.041 * H, 0.011 * H, round_=0.004 * H), k=0.004 * H)
    sole = intersect(sole, halfspace((0, yg, 0), (0, -1, 0)), k=0.003 * H)
    upper = union(ellipsoid((0, yg + 0.032 * H, -0.012 * H), (0.0435 * H, 0.036 * H, 0.046 * H)),
                  ellipsoid((-0.003 * H, yg + 0.024 * H, 0.07 * H), (0.046 * H, 0.0265 * H, 0.057 * H)),
                  cylinder((0, yg + 0.066 * H, -0.006 * H), 0.04 * H, 0.014 * H, round_=0.007 * H),
                  ellipsoid((0, yg + 0.054 * H, 0.03 * H), (0.026 * H, 0.016 * H, 0.024 * H), rot=(0.5, 0, 0)), k=0.024 * H)
    upper = intersect(upper, halfspace((0, yg + st * 0.55, 0), (0, -1, 0)))
    extras = []
    if style == "sneaker":
        cap = intersect(offset(upper, 0.0024 * H), halfspace((0, 0, 0.079 * H), (0, 0, -1)), k=0.004 * H)
        cap = intersect(cap, halfspace((0, yg + 0.042 * H, 0), (0, 1, 0)), k=0.004 * H)
        fox = intersect(offset(upper, 0.0016 * H), slab(yg + st * 0.4, yg + st + 0.0075 * H), k=0.002 * H)
        extras += [(cap, "sole"), (fox, "sole")]
    else:   # a stitched toe seam
        a = np.linspace(-1.0, 1.0, 7)
        pts = [(0.045 * H * math.sin(t * 1.2), yg + 0.03 * H + 0.012 * H * math.cos(t), 0.058 * H + 0.012 * H * abs(t)) for t in a]
        upper = groove(upper, pts, [(math.sin(t * 1.2), 0.9, 0.3) for t in a], 0.0026 * H, 0.04 * H)
    if o["laces"]:
        zs = (0.012, 0.027, 0.042)
        tops = snap(upper, [(0, yg + 0.09 * H, z * H) for z in zs], [(0, 1, 0)], 0.06 * H)
        lc = []
        for i, (z, p) in enumerate(zip(zs, tops)):
            dz = 0.004 * H * (1 if i % 2 else -1)
            y = p[1] + 0.0018 * H
            lc.append(capsule((-0.017 * H, y - 0.002 * H, z * H - dz), (0.017 * H, y - 0.002 * H, z * H + dz), 0.0042 * H))
        bow = tops[0] + np.array([0, 0.003 * H, -0.006 * H])
        lc.append(tube([bow + np.array([-0.014 * H, -0.002 * H, 0.004 * H]), bow, bow + np.array([0.012 * H, -0.003 * H, 0.006 * H])], 0.0038 * H))
        extras.append((union(*lc), "lace"))
    return upper, sole, extras


def _sided(prefix, specs, side):
    """Mesh a list of (name, sdf built for the LEFT side, material, cell, target, lumps, seed) for one
    side (+1 left, -1 right = mirrored), so each side gets its own lumps."""
    objs = []
    for nm, sd, m, cell, target, lumps, seed in specs:
        objs.append(sdf_mesh(f"{prefix}_{nm}", sd if side > 0 else mirror_x(sd), m, cell, target, lumps=lumps, seed=seed + (0 if side > 0 else 101)))
    return [x for x in objs if x]


def _build_legs(r):
    H, o, M = r.H, r.opts, r.mats
    leg = _leg_sdf(r)
    upper, sole, extras = _shoe_sdfs(r)
    shoe_mat = M["skin"] if o["shoe_style"] == "bare" else M["shoe"]
    specs = [("pants", leg, M["pants"], 0.0024 * H, 800, 0.0007 * H, 3),
             ("shoe", upper, shoe_mat, 0.0016 * H, 700 if o["shoe_style"] != "bare" else 1000, 0.0005 * H, 4)]
    if sole is not None:
        specs.append(("sole", sole, M["sole"], 0.0016 * H, 300, 0.0, 5))
    for i, (sd, key) in enumerate(extras):
        specs.append((key + str(i), sd, M[key], 0.0011 * H, 240 if key != "lace" else 200, 0.0, 6 + i))
    for side, pv, nm in ((1, r.legL, "LegL"), (-1, r.legR, "LegR")):
        ob = ck.join(_sided(nm, specs, side), nm + "_Mesh")
        attach(ob, pv)
        r.meshes[nm] = ob


# ====================================================================== body: pelvis and torso
def _pelvis_sdf(r):
    H, o = r.H, r.opts
    if o["diaper"]:
        pel = union(ellipsoid((0, 0.0, -0.006 * H), (0.163 * H, 0.098 * H, 0.128 * H)),
                    ellipsoid((0, -0.035 * H, -0.03 * H), (0.14 * H, 0.08 * H, 0.11 * H)), k=0.04 * H)
        for sx in (-1, 1):   # soft leg-hole puffs
            pel = union(pel, ellipsoid((sx * 0.085 * H, -0.045 * H, 0.0), (0.07 * H, 0.04 * H, 0.08 * H)), k=0.03 * H)
        return pel
    pel = union(ellipsoid((0, 0.012 * H, -0.004 * H), (0.142 * H, 0.08 * H, 0.1 * H)),
                ellipsoid((0, -0.006 * H, -0.024 * H), (0.12 * H, 0.066 * H, 0.072 * H)),
                ellipsoid((0, -0.042 * H, 0.004 * H), (0.06 * H, 0.045 * H, 0.07 * H)), k=0.018 * H)
    # fly seam (a J-shaped crease) and side seams
    pts = [(0.0, 0.05 * H, 0.11 * H), (0.004 * H, 0.0, 0.11 * H), (0.016 * H, -0.03 * H, 0.1 * H)]
    pel = groove(pel, pts, [(0, 0.2, 1)], 0.0026 * H, 0.06 * H)
    if o["shirtless"] or o["tuck"] or o["belt"]:
        pel = union(pel, intersect(offset(pel, 0.0032 * H), slab(0.02 * H, 0.046 * H)), k=0.002 * H)
    return pel


def _torso_body(r):
    """The torso shape under any garment (Body-local)."""
    H, o = r.H, r.opts
    ys = [-0.005, 0.02, 0.06, 0.12, 0.18, 0.24, 0.3]
    if o["shirtless"] or o["tuck"]:
        rx = [0.128, 0.129, 0.131, 0.134, 0.139, 0.146, 0.150]
        rz = [0.093, 0.094, 0.096, 0.099, 0.103, 0.108, 0.111]
    else:
        rx = [0.150, 0.148, 0.139, 0.134, 0.139, 0.146, 0.150]
        rz = [0.115, 0.113, 0.103, 0.099, 0.103, 0.108, 0.111]
    t = loft([y * H for y in ys], [v * H for v in rx], [v * H for v in rz])
    t = union(t, ellipsoid((0, 0.318 * H, 0), (0.193 * H, 0.077 * H, 0.111 * H)), k=0.03 * H)
    t = union(t, ellipsoid((0, 0.255 * H, 0.016 * H), (0.12 * H, 0.07 * H, 0.095 * H)), k=0.03 * H)
    if o["belly"]:
        t = union(t, ellipsoid((0, 0.12 * H, 0.045 * H), (0.126 * H, 0.12 * H, 0.12 * H * o["belly"])), k=0.04 * H)
    if o["bust"] > 0:
        b = o["bust"]
        for sx in (-1, 1):
            t = union(t, ellipsoid((sx * 0.05 * H, 0.243 * H, 0.074 * H + 0.012 * H * b), (0.05 * H, 0.046 * H, 0.04 * H * (0.6 + 0.4 * b))), k=0.03 * H)
    return t


def _neck_ring(r, t, n=20, rx=0.05, rz=0.047, zc=0.004, drop=0.002):
    """Points around the neck on top of the torso (theta 0 = front)."""
    H = r.H
    th = np.linspace(0, 2 * np.pi, n, endpoint=False)
    X, Z = rx * H * np.sin(th), zc * H + rz * H * np.cos(th)
    tt = ray_hit(t, np.stack([X, np.full(n, 0.7 * H), Z], 1), [(0, -1, 0)], 0.5 * H)
    return np.stack([X, 0.7 * H - tt - drop * H, Z], 1), th


def _front(z=0.02):
    return halfspace((0, 0, z), (0, 0, -1))


def _back(z=-0.02):
    return halfspace((0, 0, z), (0, 0, 1))


def _build_body(r):
    H, o, M = r.H, r.opts, r.mats
    body = _torso_body(r)
    shirtless = o["shirtless"]
    collar = o["collar"]
    parts = []
    shirt = body
    skin_region = None
    ring, th = _neck_ring(r, body)
    ytop = float(np.mean(ring[:, 1]))
    yfront = float(ring[0, 1])
    if shirtless:
        nav = snap(body, [(0, 0.085 * H, 0.1 * H)], [(0, 0, 1)], 0.2 * H)[0]
        shirt = subtract(shirt, sphere(nav + np.array([0, 0, 0.004 * H]), 0.0085 * H), k=0.004 * H)
    else:
        # cut-outs that show skin (v, scoop, tank)
        if collar == "v":
            skin_region = intersect(poly2d([(-0.052 * H, ytop + 0.03 * H), (0.052 * H, ytop + 0.03 * H), (0, yfront - 0.078 * H)]), _front(0.03 * H), k=0.006 * H)
        elif collar == "scoop":
            skin_region = intersect(ellipse2d((0, yfront + 0.012 * H), 0.072 * H, 0.068 * H), _front(0.03 * H))
        elif collar == "tank":
            fr = intersect(ellipse2d((0, yfront + 0.02 * H), 0.064 * H, 0.09 * H), _front(0.02 * H))
            bk = intersect(ellipse2d((0, ytop + 0.03 * H), 0.06 * H, 0.06 * H), _back(-0.02 * H))
            arm = symmetric_x(ellipse2d((0.172 * H, 0.335 * H), 0.072 * H, 0.098 * H))
            skin_region = union(fr, bk, arm)
        if skin_region is not None:
            shirt = subtract(shirt, skin_region, k=0.004 * H)
            shirt = union(shirt, edge_band(body, skin_region, 0.0028 * H, 0.0075 * H), k=0.002 * H)
            parts.append(sdf_mesh("Body_skin", intersect(offset(body, -0.0055 * H), offset(skin_region, 0.01 * H)), M["skin"], 0.003 * H, 900, lumps=0.0006 * H, seed=21))
        if o["rib"]:
            shirt = displace(shirt, lambda p: -0.0016 * H * (0.5 - 0.5 * np.cos(64 * np.arctan2(p[:, 0], p[:, 2]))), 0.002 * H)
        # hem
        if not o["tuck"]:
            shirt = union(shirt, intersect(offset(body, 0.003 * H), slab(-0.012 * H, 0.016 * H)), k=0.002 * H)
            shirt = intersect(shirt, halfspace((0, -0.007 * H, 0), (0, -1, 0)), k=0.002 * H)
        # collars
        if collar in ("crew", "polo", "button"):
            lift = 0.004 if collar == "crew" else 0.008
            rad = 0.0105 if collar == "crew" else 0.0095
            pts = ring + np.array([0, lift * H, 0])
            shirt = union(shirt, loop_tube(list(pts), rad * H), k=0.003 * H)
            shirt = subtract(shirt, cylinder((0, ytop + 0.006 * H, 0.004 * H), 0.041 * H, 0.012 * H, round_=0.004 * H), k=0.004 * H)
        if collar in ("polo", "button"):
            for sx in (-1, 1):
                tri = poly2d([(sx * 0.008 * H, yfront + 0.012 * H), (sx * 0.062 * H, ytop + 0.004 * H), (sx * 0.034 * H, yfront - 0.05 * H)])
                shirt = union(shirt, patch(body, intersect(tri, _front(0.0)), 0.0068 * H))
            y_end = yfront - 0.085 * H if collar == "polo" else -0.004 * H
            plk = intersect(poly2d([(-0.014 * H, yfront - 0.01 * H), (0.014 * H, yfront - 0.01 * H), (0.014 * H, y_end), (-0.014 * H, y_end)]), _front(0.0))
            shirt = union(shirt, patch(body, plk, 0.0026 * H))
            nb = 2 if collar == "polo" else 5
            ys_b = np.linspace(yfront - 0.03 * H, y_end + (0.02 * H if collar == "polo" else 0.035 * H), nb)
            bp = snap(body, [(0, y, 0.2 * H) for y in ys_b], [(0, 0, 1)], 0.3 * H, lift=0.0042 * H)
            parts.append(sdf_mesh("Body_buttons", union(*[sphere(p, 0.0058 * H) for p in bp]), M["button"], 0.0009 * H, 70 * nb))
        if o["pocket"]:
            reg = intersect(rbox((0.062 * H, 0.232 * H, 0.0), (0.028 * H, 0.032 * H, BIG), 0.008 * H), _front(0.0))
            shirt = union(shirt, patch(body, reg, 0.0038 * H, k=0.0016 * H))
            shirt = seam(shirt, [(0.036 * H, 0.258 * H, 0.15 * H), (0.062 * H, 0.258 * H, 0.15 * H), (0.088 * H, 0.258 * H, 0.15 * H)], [(0, 0, 1)], 0.0026 * H, 0.2 * H, lift=0.6)
        # fabric creases: armpit folds, waist folds, back folds
        cr = 0.0034 * H
        for sx in (-1, 1):
            for (a, b) in (((0.118, 0.272), (0.062, 0.15)), ((0.13, 0.215), (0.09, 0.118))):
                pts = [(sx * a[0] * H, a[1] * H, 0.0), (sx * (a[0] + b[0]) * 0.5 * H, (a[1] + b[1]) * 0.5 * H, 0.0), (sx * b[0] * H, b[1] * H, 0.0)]
                pts = [(x, y, 0.2 * H) for x, y, _ in pts]
                shirt = groove(shirt, pts, [(sx * 0.35, 0, 1)], cr, 0.3 * H)
            for y in (0.07, 0.095):
                pts = [(sx * 0.14 * H, y * H, z * H) for z in (0.05, 0.0, -0.05)]
                shirt = groove(shirt, pts, [(sx, 0, 0)], cr * 0.9, 0.2 * H)
            pts = [(sx * 0.07 * H, 0.27 * H, -0.2 * H), (sx * 0.06 * H, 0.2 * H, -0.2 * H), (sx * 0.075 * H, 0.13 * H, -0.2 * H)]
            shirt = groove(shirt, pts, [(sx * 0.2, 0, -1)], cr, 0.3 * H)
    r.sdf["torso"] = body
    tm = M["skin"] if shirtless else M["top"]
    parts.append(sdf_mesh("Body_top", shirt, tm, 0.0028 * H, 2700, lumps=0.0008 * H, seed=22))
    pel = _pelvis_sdf(r)
    parts.append(sdf_mesh("Body_pelvis", pel, M["pants"], 0.003 * H, 900, lumps=0.0007 * H, seed=23))
    if o["belt"]:
        belt = intersect(offset(pel, 0.0055 * H), slab(0.019 * H, 0.045 * H), k=0.002 * H)
        parts.append(sdf_mesh("Body_belt", belt, ck.clay(o["belt"], 0.6), 0.0018 * H, 700))
        bk = snap(pel, [(0, 0.032 * H, 0.2 * H)], [(0, 0, 1)], 0.3 * H)[0]
        parts.append(sdf_mesh("Body_buckle", rbox(bk + np.array([0, 0, 0.004 * H]), (0.016 * H, 0.013 * H, 0.004 * H), 0.003 * H), ck.metal("#c8b070", 0.35), 0.0008 * H, 160))
    r.meshes["Body"] = ck.join([p for p in parts if p], "Body_Mesh")
    attach(r.meshes["Body"], r.body)


# ====================================================================== arms and hands
def _hand_sdf(r):
    """Mitten hand for the LEFT arm (arm-local): palm faces -x (the body), thumb forward."""
    H = r.H
    yc = -0.298 * H
    palm = ellipsoid((0, yc, 0), (0.0255 * H, 0.043 * H, 0.036 * H))

    def curl(p):
        q = p.copy()
        t = np.clip((-0.282 * H - p[:, 1]) / (0.058 * H), 0, 1)
        q[:, 0] = q[:, 0] + 0.012 * H * t * t
        return q
    palm = warp(palm, curl, pad=0.013 * H)
    palm = union(palm, capsule((0.012 * H, -0.31 * H, -0.02 * H), (0.012 * H, -0.308 * H, 0.022 * H), 0.012 * H), k=0.012 * H)
    thumb = round_cone((-0.011 * H, -0.276 * H, 0.021 * H), (-0.018 * H, -0.302 * H, 0.043 * H), 0.0145 * H, 0.0122 * H)
    hand = union(palm, thumb, k=0.008 * H)
    hand = union(hand, capsule((0, -0.236 * H, 0.002 * H), (0, -0.268 * H, 0.002 * H), 0.0262 * H), k=0.012 * H)
    # the thumb crease
    hand = groove(hand, [(-0.02 * H, -0.272 * H, 0.012 * H), (-0.024 * H, -0.29 * H, 0.02 * H), (-0.022 * H, -0.304 * H, 0.03 * H)], [(-1, 0, 0.3)], 0.0022 * H, 0.04 * H)
    return hand


def _build_arms(r):
    H, o, M = r.H, r.opts, r.mats
    sl = o["sleeves"]
    parts = []
    hand = _hand_sdf(r)
    r.sdf["hand"] = hand
    ball = sphere((0, 0, 0), 0.0455 * H)
    specs = []
    if sl == "long":
        s = union(ball, round_cone((0, -0.005 * H, 0), (0, -0.252 * H, 0.005 * H), 0.0455 * H, 0.0405 * H), k=0.02 * H)
        s = union(s, torus((0, -0.252 * H, 0.005 * H), 0.0405 * H, 0.0062 * H), k=0.003 * H)
        s = intersect(s, halfspace((0, -0.259 * H, 0), (0, -1, 0)), k=0.003 * H)
        for y, wob in ((-0.13, 0.01), (-0.148, -0.008)):
            a = np.linspace(-1.1, 1.1, 5)
            pts = [(-0.046 * H * math.sin(t + 0.6), (y + wob * t) * H, 0.046 * H * math.cos(t + 0.6)) for t in a]
            s = groove(s, pts, radial(pts), 0.003 * H, 0.04 * H)
        specs += [("sleeve", s, M["sleeve"], 0.0022 * H, 800, 0.0006 * H, 31),
                  ("hand", hand, M["skin"], 0.0013 * H, 800, 0.0004 * H, 32)]
    elif sl == "short":
        s = union(ball, round_cone((0, -0.005 * H, 0), (0, -0.112 * H, 0.002 * H), 0.049 * H, 0.0465 * H), k=0.02 * H)
        s = union(s, intersect(offset(s, 0.0025 * H), slab(-0.118 * H, -0.103 * H)), k=0.002 * H)
        s = intersect(s, halfspace((0, -0.118 * H, 0), (0, -1, 0)), k=0.003 * H)
        fore = union(round_cone((0, -0.08 * H, 0.0), (0, -0.25 * H, 0.004 * H), 0.037 * H, 0.0285 * H), hand, k=0.014 * H)
        specs += [("sleeve", s, M["sleeve"], 0.0022 * H, 700, 0.0006 * H, 31),
                  ("arm", fore, M["skin"], 0.0014 * H, 1300, 0.0005 * H, 32)]
    else:   # bare arm (shirtless, tank top)
        a = union(sphere((0, 0, 0), 0.0455 * H), round_cone((0, -0.01 * H, 0), (0, -0.25 * H, 0.004 * H), 0.044 * H, 0.0295 * H), k=0.02 * H)
        a = union(a, ellipsoid((0.004 * H, -0.06 * H, 0.0), (0.046 * H, 0.06 * H, 0.046 * H)), k=0.02 * H)
        a = union(a, hand, k=0.014 * H)
        specs.append(("arm", a, M["sleeve"], 0.0015 * H, 1600, 0.0005 * H, 32))
    for side, pv, nm in ((1, r.armL, "ArmL"), (-1, r.armR, "ArmR")):
        ob = ck.join(_sided(nm, specs, side), nm + "_Mesh")
        attach(ob, pv)
        r.meshes[nm] = ob


# ====================================================================== head
def _ear_sdf(H, s=1.0):
    """One ear in ear-local coords: x out of the head, y up, z forward. Rim, bowl, inner fold, lobe."""
    u = H * s
    e = union(ellipsoid((0, 0, 0), (0.0105 * u, 0.028 * u, 0.0195 * u)), sphere((-0.001 * u, -0.022 * u, 0.003 * u), 0.0085 * u), k=0.006 * u)
    e = subtract(e, ellipsoid((0.0088 * u, -0.001 * u, 0.0015 * u), (0.0075 * u, 0.0195 * u, 0.0125 * u)), k=0.0028 * u)
    fold = tube([(0.0052 * u, 0.0165 * u, -0.004 * u), (0.0058 * u, 0.006 * u, -0.0088 * u), (0.0058 * u, -0.007 * u, -0.0062 * u), (0.0052 * u, -0.0125 * u, 0.001 * u)], 0.0029 * u)
    e = union(e, fold, k=0.002 * u)
    return union(e, sphere((0.0035 * u, -0.004 * u, 0.0135 * u), 0.0042 * u), k=0.002 * u)


def _nose_sdf(r):
    H, hy, o = r.H, r.hy, r.opts
    kind, s = o["nose"], o["nose_size"] * 1.12
    base = np.array([0, hy - 0.006 * H, 0.112 * H])

    def P(x, y, z):
        return base + s * np.array([x, y, z]) * H
    if kind == "button":
        n = union(sphere(P(0, -0.003, 0.006), 0.0165 * H * s), round_cone(P(0, 0.03, -0.008), P(0, 0.004, 0.004), 0.008 * H * s, 0.011 * H * s),
                  *[sphere(P(sx * 0.0135, -0.009, -0.002), 0.0095 * H * s) for sx in (-1, 1)], k=0.007 * H * s)
        nos = [sphere(P(sx * 0.0078, -0.0155, 0.004), 0.0042 * H * s) for sx in (-1, 1)]
    elif kind == "long":
        n = union(sphere(P(0, -0.007, 0.014), 0.0175 * H * s), round_cone(P(0, 0.034, -0.008), P(0, -0.002, 0.012), 0.0095 * H * s, 0.0135 * H * s),
                  *[sphere(P(sx * 0.015, -0.011, -0.001), 0.0105 * H * s) for sx in (-1, 1)], k=0.008 * H * s)
        nos = [sphere(P(sx * 0.0085, -0.0195, 0.008), 0.0048 * H * s) for sx in (-1, 1)]
    elif kind == "broad":
        n = union(sphere(P(0, -0.003, 0.006), 0.021 * H * s), round_cone(P(0, 0.032, -0.008), P(0, 0.004, 0.006), 0.0105 * H * s, 0.015 * H * s),
                  *[sphere(P(sx * 0.0195, -0.01, -0.003), 0.0135 * H * s) for sx in (-1, 1)], k=0.009 * H * s)
        nos = [sphere(P(sx * 0.0105, -0.0195, 0.005), 0.0058 * H * s) for sx in (-1, 1)]
    else:   # round (the JS ball nose, sculpted)
        n = union(sphere(P(0, -0.002, 0.006), 0.0195 * H * s), round_cone(P(0, 0.034, -0.008), P(0, 0.004, 0.006), 0.0095 * H * s, 0.0135 * H * s),
                  *[sphere(P(sx * 0.016, -0.01, -0.004), 0.0115 * H * s) for sx in (-1, 1)], k=0.008 * H * s)
        nos = [sphere(P(sx * 0.0092, -0.0185, 0.0045), 0.0052 * H * s) for sx in (-1, 1)]
    return n, union(*nos)


def _eye_centers(r):
    H, hy = r.H, r.hy
    return [np.array([s * 0.042 * H, hy + 0.02 * H, 0.093 * H]) for s in (-1, 1)]


def _head_skin(r):
    """Skull, jaw, cheeks, chin, brow ridge, neck, nose, ears, eye sockets: one fused clay head."""
    H, hy, hs, o = r.H, r.hy, r.hs, r.opts
    C = np.array([0, hy, 0])
    cran = ellipsoid(C + (0, 0.004 * H, -0.006 * H), (hs * 0.99, hs, hs * 1.03))
    s = union(cran, ellipsoid(C + (0, -0.04 * H, 0.026 * H), (0.087 * H, 0.072 * H, 0.084 * H)), k=0.03 * H)
    ch = o["cheeks"]
    for sx in (-1, 1):
        s = union(s, ellipsoid(C + (sx * 0.052 * H, -0.03 * H, 0.07 * H), (0.038 * H * ch, 0.032 * H * ch, 0.034 * H * ch)), k=0.02 * H)
    c = o["chin"]
    s = union(s, ellipsoid(C + (0, -0.086 * H, 0.072 * H), (0.034 * H * c, 0.025 * H * c, 0.03 * H * c)), k=0.02 * H)
    if o["brow_ridge"] > 0:
        xs = np.array([-0.068, -0.034, 0.0, 0.034, 0.068]) * H
        yb = hy + 0.052 * H
        zs = -0.006 * H + hs * 1.03 * np.sqrt(np.maximum(1 - (xs / (hs * 0.99)) ** 2 - ((yb - hy - 0.004 * H) / hs) ** 2, 0.05)) - 0.006 * H
        s = union(s, tube([(x, yb, z) for x, z in zip(xs, zs)], 0.0105 * H * o["brow_ridge"]), k=0.02 * H)
    s = union(s, capsule((0, -0.05 * H, -0.002 * H), (0, 0.085 * H, -0.008 * H), 0.041 * H), k=0.025 * H)
    nose, nostrils = _nose_sdf(r)
    s = union(s, nose, k=0.009 * H)
    ear = xform(_ear_sdf(H, o["ear_size"]), pos=(0.1115 * H, hy + 0.003 * H, -0.008 * H), rot=(-0.12, -0.32, 0))
    s = union(s, symmetric_x(ear), k=0.005 * H)
    re = 0.026 * H * o["eye_size"]
    for E in _eye_centers(r):
        s = subtract(s, sphere(E, re + 0.0026 * H), k=0.011 * H)
    s = subtract(s, nostrils, k=0.003 * H)
    return s


def _lid_sdf(r, E, side, cover, tilt, lower=False):
    """An eyelid: a clay shell over the eyeball, cut by a tilted plane (cover 0 = open, 0.5 = half shut)."""
    H = r.H
    re = 0.026 * H * r.opts["eye_size"]
    rin, rout = re + 0.0009 * H, re + 0.0047 * H

    def sh(p):
        d = np.sqrt(((p - E) ** 2).sum(1))
        return np.maximum(d - rout, rin - d)
    beta = 0.55 if not lower else 0.35
    ye = re * (1 - 2 * cover) * (-1 if lower else 1)
    ze = math.sqrt(max(re * re - ye * ye, 1e-12))
    n = np.array([0.0, math.cos(beta), -math.sin(beta)]) * np.array([1, -1 if lower else 1, 1])
    g = tilt * side
    n = np.array([-math.sin(g) * n[1], math.cos(g) * n[1], n[2]])
    q0 = np.array([0.0, ye, ze])
    d0 = float(n @ q0)

    def f(p):
        return smax(sh(p), d0 - (p - E) @ n, 0.0014 * H)
    return Sdf(f, E - rout, E + rout)


def _build_eyes(r, parts):
    H, o, M = r.H, r.opts, r.mats
    re = 0.026 * H * o["eye_size"]
    gx, gy = o["gaze"]
    g = _unit((math.sin(gx), math.sin(gy), 1.0))
    gh = _unit(g + np.array([0.3, 0.36, 0.0]))
    for side, E in zip((-1, 1), _eye_centers(r)):
        nm = "R" if side < 0 else "L"
        ball = ck.sph(re, tuple(E), M["white"], segs=18, rings=12, name=f"Eye{nm}_ball")
        parts.append(ball)
        R1 = re + 0.0016 * H
        rp = 0.0135 * H * o["pupil"]
        pupil = intersect(sphere(E, R1), sphere(E + g * R1, rp), k=0.0007 * H)
        parts.append(sdf_mesh(f"Eye{nm}_pupil", pupil, M["black"], 0.00045 * H, 170, project_iters=3))
        R2 = R1 + 0.0009 * H
        hl = intersect(sphere(E, R2), sphere(E + gh * R2, 0.0043 * H), k=0.0004 * H)
        parts.append(sdf_mesh(f"Eye{nm}_shine", hl, M["shine"], 0.0003 * H, 60, project_iters=3))
        lid = _lid_sdf(r, E, side, o["lid"], o["lid_tilt"])
        if o["lid_low"] > 0:
            lid = union(lid, _lid_sdf(r, E, side, o["lid_low"], -0.5 * o["lid_tilt"], lower=True))
        parts.append(sdf_mesh(f"Eye{nm}_lids", lid, M["skin"], 0.0006 * H, 420, project_iters=3))
        if o["lashes"]:
            # two little flicks at the outer corner of the upper lid
            ye = re * (1 - 2 * o["lid"])
            base = E + np.array([side * re * 0.82, ye * 0.55 + 0.004 * H, re * 0.45])
            fl = [tube([base + np.array([0, dy * H, 0]), base + np.array([side * 0.008 * H, (0.006 + dy) * H, 0.002 * H]),
                        base + np.array([side * 0.013 * H, (0.011 + dy * 1.4) * H, 0.001 * H])], [0.0022 * H, 0.0016 * H, 0.0008 * H]) for dy in (0.0, -0.005)]
            parts.append(sdf_mesh(f"Eye{nm}_lashes", union(*fl), M["lash"], 0.0005 * H, 200))


def _build_brows(r, fmap, parts):
    H, o = r.H, r.opts
    b = dict(raise_=0.0, tilt=0.3, arch=1.0, thick=1.0, length=1.0)
    b.update(o["brow"] or {})
    if "raise" in b:
        b["raise_"] = b.pop("raise")
    segs = []
    for side, E in zip((-1, 1), _eye_centers(r)):
        L = b["length"]
        xs = [E[0] - side * 0.021 * H * L, E[0] + side * 0.006 * H, E[0] + side * 0.026 * H * L]
        ys = [E[1] + (0.040 + b["raise_"] + 0.006 * b["tilt"]) * H, E[1] + (0.045 + b["raise_"] + 0.003 * (b["arch"] - 1)) * H,
              E[1] + (0.036 + b["raise_"] - 0.004 * b["tilt"]) * H]
        rads = np.array([0.0064, 0.0066, 0.0042]) * H * b["thick"]
        pts = [(x, y, float(fmap(x, y)) + rr * 0.15) for x, y, rr in zip(xs, ys, rads)]
        segs.append(tube(pts, list(rads), n=6))
    parts.append(sdf_mesh("Brows", union(*segs), r.mats["brow"], 0.0008 * H, 320))


def _mouth_meshes(r, fmap):
    """The Mouth: lips, dark inside, tongue, modeled OPEN around its own origin (Mouth-local)."""
    H, o, M = r.H, r.opts, r.mats
    M0 = np.array([0, 0.115 * H, 0.1 * H])
    shape = o["mouth_shape"]
    w = 0.036 * H * o["mouth_w"]
    h = 0.021 * H
    sm = 0.007 * H * o["smile"]
    if shape == "o":
        w, h, sm = 0.021 * H * o["mouth_w"], 0.02 * H, 0.0
    elif shape == "flat":
        sm = 0.0

    def fz(x, y):   # face surface height, Mouth-local
        return fmap(x, y + M0[1]) - M0[2]
    th = np.linspace(0, 2 * np.pi, 28, endpoint=False)
    X = w * np.cos(th)
    Y = h * np.sin(th) + sm * np.cos(th) ** 2
    rl = 0.004 * H + np.where(np.sin(th) > 0, 0.0009 * H, 0.0023 * H) * np.abs(np.sin(th))
    Z = fz(X, Y) + 0.0032 * H
    lips = loop_tube([(x, y, z) for x, y, z in zip(X, Y, Z)], list(rl))

    def rho(p):
        x = p[:, 0] / w
        return np.sqrt(x * x + ((p[:, 1] - sm * x * x) / h) ** 2)

    kd = 0.0016 * H

    def dish(p):
        rh = rho(p)
        zf = fz(p[:, 0], p[:, 1])
        front = zf + 0.0012 * H + 0.0045 * H * np.minimum(rh, 1.2) ** 2
        return smax(smax((rh - 1.0) * min(w, h), p[:, 2] - front, kd), (zf - 0.006 * H) - p[:, 2], kd)
    inside = Sdf(dish, [-w * 1.1, -h * 1.2 - abs(sm), -0.06 * H], [w * 1.1, h * 1.2 + abs(sm), 0.06 * H])
    tz = float(fz(0.0, -h * 0.45))
    tongue = intersect(ellipsoid((0, -h * 0.45, tz - 0.001 * H), (w * 0.52, h * 0.45, 0.0062 * H)),
                       Sdf(lambda p: (rho(p) - 0.94) * min(w, h), [-w, -h * 2, -BIG], [w, h * 2, BIG]))
    objs = [sdf_mesh("Mouth_lips", lips, M["lips"], 0.0007 * H, 520),
            sdf_mesh("Mouth_inside", inside, M["mouth"], 0.0007 * H, 320),
            sdf_mesh("Mouth_tongue", tongue, M["tongue"], 0.0007 * H, 160)]
    mouth = ck.join([x for x in objs if x], "Mouth")
    attach(mouth, r.head, tuple(M0))
    return mouth


# ---------------------------------------------------------------------- hair
HAIRLINES = {   # (azimuth deg from the front, elevation deg of the hairline); mirrored left/right
    "short": [(0, 42), (34, 40), (56, 34), (70, 27), (77, 4), (83, 4), (89, 22), (104, 23), (118, 9), (140, -15), (180, -32)],
    "curls": [(0, 45), (30, 44), (52, 38), (64, 30), (72, 30), (77, 4), (83, 4), (89, 22), (104, 23), (118, 9), (140, -14), (180, -28)],
    "bob": [(0, 33), (28, 32), (52, 24), (66, 4), (78, -24), (100, -34), (140, -40), (180, -43)],
    "bun": [(0, 45), (36, 42), (60, 31), (74, 17), (86, 21), (104, 22), (120, 6), (145, -14), (180, -27)],
    "long": [(0, 42), (36, 40), (60, 31), (72, 12), (86, -10), (110, -16), (140, -20), (180, -24)],
}


def _hair_cap(r, style):
    H, hy, hs, o = r.H, r.hy, r.hs, r.opts
    seed = o["seed"]
    rnd = random.Random(seed)
    C = np.array([0, hy + 0.004 * H, -0.006 * H])
    ax, ay, az_ = hs * 0.99, hs, hs * 1.03
    vol = o["hair_volume"]
    spec = dict(top=0.021, side=0.012, back=0.013, taper=0.22, tip=0.075, groove=0.0062, clumps=16, flow="crown", pole=(0, 0.8, -0.6), sharp=0.6, flare=0.0)
    if style == "bob":
        spec.update(top=0.026, side=0.03, back=0.03, taper=0.1, tip=0.035, groove=0.0065, clumps=20, pole=(0, 0.92, -0.38), flare=0.012)
    elif style == "bun":
        bd = _unit((0, 0.78, -0.55))
        spec.update(top=0.011, side=0.0095, back=0.011, taper=0.3, tip=0.03, groove=0.0045, clumps=22, pole=tuple(bd))
    elif style == "long":
        spec.update(top=0.02, side=0.016, back=0.018, taper=0.18, tip=0.05, groove=0.0058, clumps=18, flow="center")
    elif style == "curls":
        spec.update(top=0.022, side=0.016, back=0.016, taper=0.12, tip=0.0, groove=0.0, clumps=1)
    if o["hair_flow"]:
        fl = o["hair_flow"]
        spec["flow"] = "center" if fl == "center" else "crown"
        if fl == "back":
            spec["pole"] = (0, 0.3, 1.0)
        elif fl == "side":
            spec["pole"] = (-0.8 * (1 if o.get("part", 1) > 0 else -1), 0.55, 0.2)
        elif fl == "crown" and style not in ("bun",):
            spec["pole"] = (0, 0.8, -0.6)
    line_pts = [(a, v + o["hair_line"]) for a, v in HAIRLINES.get(style, HAIRLINES["short"])]
    line = _periodic(line_pts)
    pole = _unit(spec["pole"])
    pu, pv = _basis(pole)
    ph = [rnd.uniform(0, 6.28) for _ in range(4)]
    N = spec["clumps"]

    def f(p):
        q = p - C
        rr = np.sqrt((q * q).sum(1)) + 1e-12
        d = q / rr[:, None]
        el = np.arcsin(np.clip(d[:, 1], -1, 1))
        az = np.arctan2(d[:, 0], d[:, 2])
        Rb = 1.0 / np.sqrt((d[:, 0] / ax) ** 2 + (d[:, 1] / ay) ** 2 + (d[:, 2] / az_) ** 2)
        if spec["flow"] == "center":
            lat = np.arcsin(np.clip(d[:, 2], -1, 1))
            c = lat / np.pi * N + 0.22 * np.sin(lat * 7 + ph[0]) + 0.5 * (d[:, 0] > 0)
            fade = np.ones_like(c)
        else:
            psi = np.arctan2(d @ pv, d @ pu)
            ang = np.arccos(np.clip(d @ pole, -1, 1))
            c = psi / (2 * np.pi) * N + 0.3 * np.sin(3 * psi + ph[0]) + 0.18 * np.sin(5 * psi + ph[1])
            fade = smoothstep(0.12, 0.45, ang) * smoothstep(0.12, 0.6, np.pi - ang)
        cid = np.floor(c).astype(np.int64)
        if spec["flow"] != "center":
            cid = cid % max(N, 1)
        fr = c - np.floor(c)
        prof = (0.5 - 0.5 * np.cos(2 * np.pi * fr)) ** spec["sharp"]
        hv = _hash3(cid, cid * 0 + 3, cid * 0 + 5, seed)
        lim = line(az) - spec["tip"] * prof * (0.55 + 0.45 * hv) * fade
        u = smoothstep(0.0, spec["taper"], el - lim)
        up = np.maximum(d[:, 1], 0.0)
        th = spec["side"] + (spec["top"] - spec["side"]) * up
        th = th + (spec["back"] - spec["side"]) * np.maximum(0, -d[:, 2]) * (1 - up)
        th = th * H * vol
        if spec["flare"]:
            th = th + spec["flare"] * H * smoothstep(0.45, 0.0, el - lim)
        th = th * (0.42 + 0.58 * u)
        if style == "long":
            part = np.exp(-(d[:, 0] / 0.06) ** 2) * smoothstep(0.55, 0.85, d[:, 1]) * smoothstep(-0.2, 0.3, d[:, 2])
            th = th * (1 - 0.55 * part)
        g = spec["groove"] * H * fade * (0.65 + 0.6 * _hash3(cid, cid * 0 + 9, cid * 0 + 1, seed))
        Rout = Rb + th - g * (1 - prof)
        if style == "curls":
            w = worley(p, 0.017 * H, seed)
            Rout = Rout + 0.0062 * H * np.sqrt(np.clip(1 - (w / 0.62) ** 2, 0, 1)) - 0.003 * H
        d_out = rr - Rout
        d_edge = (lim - el) * rr
        out = smax(d_out, d_edge, 0.0055 * H)
        return np.maximum(out, (Rb - 0.018 * H) - rr)
    e = hs * 1.03 + 0.06 * H
    return Sdf(f, C - e, C + e)


def _hair_extras(r, style):
    """Locks and knots added to a cap: cowlick, bun coil, long curtain and side locks, baby tuft."""
    H, hy, hs, o = r.H, r.hy, r.hs, r.opts
    C = np.array([0, hy + 0.004 * H, -0.006 * H])
    out = []
    if style == "bun":
        bd = _unit((0, 0.78, -0.55))
        B = C + bd * (hs + 0.03 * H)          # the JS bun (r .42hs) sits on the back of the crown
        u, v = _basis(bd)
        pts = []
        turns, n = 2.8, 56
        for i in range(n + 1):
            t = i / n
            a = 2 * np.pi * turns * t
            th = 1.45 * (1 - t) ** 0.8
            rad = 0.04 * H * (0.8 + 0.2 * (1 - t))
            pts.append(B + rad * (math.sin(th) * (math.cos(a) * u + math.sin(a) * v) + math.cos(th) * bd))
        coil = union(*[round_cone(pts[i], pts[i + 1], 0.0145 * H, 0.0145 * H) for i in range(n)])
        out.append(("hair", union(coil, sphere(B, 0.036 * H), round_cone(B - bd * 0.045 * H, B - bd * 0.01 * H, 0.03 * H, 0.033 * H), k=0.004 * H)))
        tie = torus(B - bd * 0.02 * H, 0.037 * H, 0.0098 * H, rot=frame_y(bd))
        out.append(("tie", tie))
    elif style == "long":
        rnd = random.Random(o["seed"] + 9)
        locks = []
        n = 13
        for i in range(n):
            az = math.radians(-112 + 224 * i / (n - 1)) + rnd.uniform(-0.04, 0.04)
            sa, ca = math.sin(az), -math.cos(az)          # az 0 = straight back
            w = rnd.uniform(-1, 1)
            rad = (0.0175 + 0.003 * rnd.random()) * H
            y_end = (0.012 + 0.012 * abs(sa) + rnd.uniform(-0.006, 0.006)) * H
            pts = [(sa * 0.118 * H, hy - 0.005 * H, ca * 0.118 * H - 0.006 * H),
                   (sa * 0.112 * H, hy - 0.07 * H, ca * 0.112 * H - 0.004 * H),
                   ((sa * 0.104 + 0.004 * w) * H, 0.07 * H, ca * 0.104 * H),
                   ((sa * 0.112 - 0.004 * w) * H, y_end + 0.012 * H, ca * 0.11 * H),
                   ((sa * 0.12 + 0.006 * w) * H, y_end, ca * 0.118 * H)]
            locks.append(tube(pts, [rad, rad, rad * 0.95, rad * 0.75, rad * 0.4], n=5))
        out.append(("hair", union(*locks, k=0.0065 * H)))
        for sx in (-1, 1):   # side locks framing the face
            locks = []
            for j, (zo, rad) in enumerate(((0.03, 0.0125), (0.012, 0.014), (-0.008, 0.0135))):
                pts = [(sx * 0.1 * H, hy + 0.06 * H, zo * H), (sx * 0.114 * H, hy + 0.0 * H, (zo + 0.004) * H),
                       (sx * 0.108 * H, hy - 0.05 * H, (zo - 0.004) * H), (sx * (0.1 + 0.006 * j) * H, hy - 0.092 * H + 0.008 * j * H, (zo + 0.006) * H)]
                locks.append(tube(pts, [rad * H, rad * H, rad * 0.9 * H, rad * 0.55 * H]))
            out.append(("hair", union(*locks, k=0.004 * H)))
    elif style == "tuft":
        top = np.array([0, hy + hs * 0.985, -0.006 * H])
        curl = tube([top - np.array([0, 0.01 * H, 0.004 * H]), top + np.array([0, 0.018 * H, 0.004 * H]), top + np.array([0, 0.034 * H, 0.02 * H]),
                     top + np.array([0, 0.03 * H, 0.038 * H]), top + np.array([0, 0.016 * H, 0.04 * H]), top + np.array([0, 0.012 * H, 0.026 * H]),
                     top + np.array([0, 0.019 * H, 0.019 * H])], [0.012 * H, 0.011 * H, 0.0095 * H, 0.008 * H, 0.0065 * H, 0.005 * H, 0.0035 * H], n=6)
        wisps = [tube([top + np.array([sx * 0.02 * H, -0.006 * H, -0.01 * H]), top + np.array([sx * 0.032 * H, 0.004 * H, 0.002 * H]),
                       top + np.array([sx * 0.04 * H, 0.002 * H, 0.016 * H])], [0.0065 * H, 0.005 * H, 0.0025 * H]) for sx in (-1, 1)]
        out.append(("hair", union(curl, *wisps, k=0.004 * H)))
    if o["cowlick"] and style in ("short", "curls"):
        pole = _unit((0, 0.8, -0.6))
        P0 = C + pole * (hs * 1.0 + 0.012 * H)
        out.append(("hair", union(tube([P0, P0 + np.array([0.002 * H, 0.022 * H, 0.004 * H]), P0 + np.array([0.006 * H, 0.034 * H, 0.02 * H])],
                                       [0.009 * H, 0.0065 * H, 0.0025 * H]),
                                  tube([P0 + np.array([-0.004 * H, 0, 0]), P0 + np.array([-0.01 * H, 0.018 * H, 0.0]), P0 + np.array([-0.016 * H, 0.026 * H, 0.012 * H])],
                                       [0.008 * H, 0.0055 * H, 0.002 * H]))))
    return out


def _build_hair(r, parts):
    H, o, M = r.H, r.opts, r.mats
    style = o["style"]
    if not o["hair"] or style == "bald":
        return None
    shapes = []
    if style != "tuft":
        shapes.append(_hair_cap(r, style))
    tie = None
    for key, s in _hair_extras(r, style):
        if key == "tie":
            tie = s
        else:
            shapes.append(s)
    hair = union(*shapes, k=0.006 * H) if len(shapes) > 1 else shapes[0]
    r.sdf["hair"] = hair
    cell = 0.0017 * H if style not in ("curls", "tuft") else 0.0013 * H
    parts.append(sdf_mesh("Hair", hair, M["hair"], cell, 3800 if style in ("long", "bob", "curls") else 3000, lumps=0.0006 * H, seed=41))
    if tie is not None:
        parts.append(sdf_mesh("Hair_tie", tie, ck.clay(o["bun_tie"] or o["top"], 0.8), 0.0012 * H, 500))
    return hair


def _build_mustache(r, fmap, parts):
    H, hy, o = r.H, r.hy, r.opts
    style = o["mustache_style"]
    strands = []
    rnd = random.Random(o["seed"] + 5)
    for side in (-1, 1):
        n = 5 if style == "walrus" else 3
        for j in range(n):
            t = j / max(n - 1, 1)
            if style == "walrus":
                pts = [(side * 0.004 * H, hy - (0.028 + 0.004 * t) * H), (side * 0.026 * H, hy - (0.03 + 0.006 * t) * H),
                       (side * (0.044 + 0.004 * t) * H, hy - (0.045 + 0.012 * t) * H), (side * (0.05 + 0.002 * t) * H, hy - (0.062 + 0.008 * t) * H)]
                rads = [0.0085 * H, 0.0085 * H, 0.0065 * H, 0.003 * H]
            elif style == "handlebar":
                pts = [(side * 0.004 * H, hy - 0.03 * H), (side * 0.026 * H, hy - (0.033 + 0.003 * t) * H), (side * 0.046 * H, hy - 0.03 * H), (side * 0.054 * H, hy - 0.016 * H)]
                rads = [0.0075 * H, 0.0068 * H, 0.0042 * H, 0.0022 * H]
            else:   # brush, like the JS block
                pts = [(side * 0.004 * H, hy - (0.026 + 0.004 * t) * H), (side * 0.022 * H, hy - (0.028 + 0.005 * t) * H), (side * 0.04 * H, hy - (0.032 + 0.004 * t) * H)]
                rads = [0.0085 * H, 0.008 * H, 0.0055 * H]
            jit = rnd.uniform(-0.0015, 0.0015) * H
            P = [(x, y + jit, float(fmap(x, y)) + 0.0085 * H) for x, y in pts]
            strands.append(tube(P, rads, n=5))
    parts.append(sdf_mesh("Mustache", union(*strands, k=0.0015 * H), r.mats["mustache"], 0.0009 * H, 900))


def _build_glasses(r, parts):
    H, hy = r.H, r.hy
    g = []
    for side, E in zip((-1, 1), _eye_centers(r)):
        c = np.array([E[0], E[1], 0.118 * H])
        g.append(torus(c, 0.03 * H, 0.0048 * H, rot=(math.pi / 2, 0, 0)))
        g.append(tube([(side * 0.071 * H, hy + 0.025 * H, 0.112 * H), (side * 0.1 * H, hy + 0.026 * H, 0.08 * H),
                       (side * 0.116 * H, hy + 0.022 * H, 0.02 * H), (side * 0.117 * H, hy + 0.008 * H, -0.012 * H)], 0.0036 * H))
    g.append(tube([(-0.013 * H, hy + 0.026 * H, 0.122 * H), (0, hy + 0.031 * H, 0.125 * H), (0.013 * H, hy + 0.026 * H, 0.122 * H)], 0.0042 * H))
    parts.append(sdf_mesh("Glasses", union(*g), ck.gloss(r.opts["glasses_color"], 0.3), 0.0009 * H, 1600))


def _build_head(r):
    H, o, M = r.H, r.opts, r.mats
    hy = r.hy
    skin = _head_skin(r)
    r.sdf["head"] = skin
    parts = [sdf_mesh("Head_skin", skin, M["skin"], 0.0013 * H, 4000, sym=True, lumps=0.0005 * H, seed=51)]
    fmap = FaceMap(skin, -0.11 * H, 0.11 * H, hy - 0.13 * H, hy + 0.11 * H, 0.3 * H, -0.05 * H)
    r.face = fmap
    _build_eyes(r, parts)
    _build_brows(r, fmap, parts)
    _build_hair(r, parts)
    if o["mustache"]:
        _build_mustache(r, fmap, parts)
    if o["glasses"]:
        _build_glasses(r, parts)
    r.meshes["Head"] = ck.join([p for p in parts if p], "Head_Mesh")
    attach(r.meshes["Head"], r.head)
    r.mouth = _mouth_meshes(r, fmap)


# ====================================================================== the builder
def make_person(**o):
    """Build a clay puppet with the exact pivot rig of makePerson() (see the module docstring)."""
    o = _opts(o)
    H = float(o["h"])
    hs = 0.115 * H
    hy = 0.05 * H + hs
    rig = ck.empty("Rig")
    legR = ck.empty("LegR", (-0.085 * H, 0.47 * H, 0), parent=rig)
    legL = ck.empty("LegL", (0.085 * H, 0.47 * H, 0), parent=rig)
    body = ck.empty("Body", (0, 0.47 * H, 0), parent=rig)
    armR = ck.empty("ArmR", (-0.185 * H, 0.31 * H, 0), parent=body)
    handR = ck.empty("HandR", (0, -0.30 * H, 0), parent=armR, size=0.05)
    armL = ck.empty("ArmL", (0.185 * H, 0.31 * H, 0), parent=body)
    handL = ck.empty("HandL", (0, -0.30 * H, 0), parent=armL, size=0.05)
    head = ck.empty("Head", (0, 0.36 * H, 0), parent=body)
    base = (lambda h, r=0.86: ck.mat("gloss", h, 0.85)) if o["soft"] else ck.clay
    skin = base(o["skin"])
    top = o["top_mat"] if o["top_mat"] is not None else base(o["top"])
    if isinstance(top, str):
        top = base(top)
    sleeve = o["sleeve_mat"]
    if isinstance(sleeve, str):
        sleeve = base(sleeve)
    if sleeve is None:
        sleeve = skin if (o["shirtless"] or o["sleeves"] == "none") else top
    mats = dict(skin=skin, top=top, sleeve=sleeve, pants=base(o["pants"]), shoe=ck.clay(o["shoes"], 0.5),
                sole=ck.clay(o["sole"], 0.7), lace=ck.clay(o["lace_color"], 0.85), hair=ck.clay(o["hair"], 0.8) if o["hair"] else None,
                brow=ck.clay(o["brows"], 0.8), mustache=ck.clay(o["hair"] or "#3a2a1a", 0.8), button=ck.clay(o["button_color"], 0.5),
                white=ck.gloss("#f8f6f0", 0.4), black=ck.gloss("#0a0a0c", 0.3), shine=ck.gloss("#ffffff", 0.2),
                mouth=ck.clay("#3a1414", 0.6), lips=ck.clay(o["lips"], 0.7), tongue=ck.clay(o["tongue"], 0.6), lash=ck.clay("#1a1414", 0.7))
    r = Person(rig=rig, legR=legR, legL=legL, body=body, armR=armR, armL=armL, handR=handR, handL=handL, head=head, mouth=None,
               legs=[legR, legL], arms=[armR, armL], H=H, hy=hy, hs=hs, opts=o, mats=mats, meshes={}, sdf={}, face=None)
    _build_legs(r)
    _build_body(r)
    _build_arms(r)
    _build_head(r)
    for p in (rig, legR, legL, body, armR, armL, handR, handL, head):
        p.rotation_mode = "QUATERNION"
    tris = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            tris += t
            print(f"[person]   {ob.name:10s} {t:6d} tris  {len(ob.data.materials)} materials")
    print(f"[person] built h={H} style={o['style']}  {tris} tris")
    return r


# ====================================================================== accessories
def on_head(r, el_deg, az_deg, out=0.0, hair=True):
    """Head-local point on the head surface (hair included when hair=True) seen from the head center
    at elevation el_deg (90 = top) and azimuth az_deg (0 = front/+z, 90 = +x), pushed `out` meters."""
    C = np.array([0, r.hy, 0])
    el, az = math.radians(el_deg), math.radians(az_deg)
    d = np.array([math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)])
    s = r.sdf["head"]
    if hair and r.sdf.get("hair") is not None:
        s = union(s, r.sdf["hair"])
    reach = r.hs * 2.5
    t = ray_hit(s, [C + d * reach], [-d], reach)[0]
    return tuple(C + d * (reach - t + out))


def head_top(r, hair=True):
    """Head-local y of the top of the head (hair included)."""
    return on_head(r, 90, 0, 0, hair)[1]


def clay_mesh(name, s, m, parent=None, cell=0.002, target=1500, pos=(0, 0, 0), sym=False, lumps=0.0):
    """Mesh an SDF built in the parent's local game coords into a clay part, parented to `parent`."""
    obj = sdf_mesh(name, s, m, cell, target, sym=sym, lumps=lumps)
    if parent is not None:
        attach(obj, parent, pos)
    return obj


def paper_hat(r, color="#f4f0e6", radius=0.12, height=0.12, y=None, name="PaperHat"):
    """The ice-cream vendor's paper cap (world.js: cyl(.12,.12,.12) at hy + hs*.95 on the head),
    sculpted: slight flare, a folded band, a pressed side seam and a soft dented crown."""
    H = r.H
    yc = r.hy + r.hs * 0.95 if y is None else y
    h2 = height / 2
    body = cylinder((0, yc + 0.004, 0), radius * 0.985, h2 - 0.004, round_=0.012)
    flare = cylinder((0, yc - h2 + 0.02, 0), radius * 1.02, 0.02, round_=0.008)
    hat = union(body, flare, k=0.01)
    band = intersect(offset(hat, 0.004), slab(yc - h2 + 0.006, yc - h2 + 0.034), k=0.002)
    hat = union(hat, band, k=0.002)
    hat = subtract(hat, ellipsoid((0.02, yc + h2 + 0.012, -0.01), (radius * 0.55, 0.018, radius * 0.5)), k=0.012)
    hat = groove(hat, [(radius, yc - h2 + 0.04, -0.03), (radius, yc + 0.0, -0.032), (radius, yc + h2 - 0.01, -0.03)], [(1, 0, 0)], 0.0028, 0.06)
    return clay_mesh(name, hat, ck.clay(color, 0.9), r.head, cell=0.0018, target=1600)


def earrings(r, color="#f2c230", size=1.0, name="Earrings"):
    """Little hoop earrings hanging from both ear lobes."""
    H, hy = r.H, r.hy
    rings = []
    for sx in (-1, 1):
        c = np.array([sx * 0.116 * H, hy - 0.035 * H, 0.0])
        rings.append(torus(c, 0.011 * H * size, 0.0024 * H * size, rot=(math.pi / 2, sx * 1.2, 0)))
    return clay_mesh(name, union(*rings), ck.gloss(color, 0.25), r.head, cell=0.0006 * H, target=600)


def plane_slab(point, normal, half):
    """Everything within `half` of the plane through point with this normal."""
    n = _unit(normal)
    point = _a(point)
    return intersect(halfspace(point + n * half, n), halfspace(point - n * half, -n))


def _head_and_hair(r, hair=True):
    s = r.sdf["head"]
    if hair and r.sdf.get("hair") is not None:
        s = union(s, r.sdf["hair"])
    return s


def head_band(r, y, height, thickness, color, tilt=0.0, hair=True, name="HeadBand", k=None):
    """A band hugging the head (and hair) around Head-local height y: bandanas, headbands, hat bands,
    a robber's mask. tilt (rad) > 0 raises the front (leans back); a JS torus with
    rotation.x = PI/2 + a is tilt = -a."""
    n = (0.0, math.cos(tilt), -math.sin(tilt))
    band = intersect(offset(_head_and_hair(r, hair), thickness), plane_slab((0, y, 0), n, height / 2), k=k if k is not None else thickness * 0.6)
    return clay_mesh(name, band, color if not isinstance(color, str) else ck.clay(color, 0.85), r.head, cell=0.0011 * r.H, target=1400)


def skull_cap(r, y, thickness, color, tilt=0.0, hair=True, rim=0.0, name="Cap"):
    """A dome hugging the top of the head above Head-local height y (beanies, caps, helmets).
    tilt > 0 raises the front edge; rim > 0 adds a rolled brim of that radius at the bottom edge."""
    n = np.array([0.0, math.cos(tilt), -math.sin(tilt)])
    hh = _head_and_hair(r, hair)
    cap = intersect(offset(hh, thickness), halfspace((0, y, 0), -n), k=thickness * 0.5)
    if rim > 0:
        cap = union(cap, intersect(offset(hh, thickness + rim * 0.9), plane_slab(np.array([0, y, 0]) + n * rim, n, rim)), k=rim * 0.4)
    return clay_mesh(name, cap, color if not isinstance(color, str) else ck.clay(color, 0.9), r.head, cell=0.0014 * r.H, target=2200)


def torso_band(r, width, thickness, color, angle=0.0, x=0.0, y=None, name="Sash"):
    """A strap/sash wrapped around the torso: a band `width` wide whose center line crosses the body at
    (x, y) (Body-local), tilted `angle` rad about z like a box's rotation.z (0 = vertical strap;
    0.62 = 2-Pack's front sash, left hip to right shoulder). One plane, so front and back connect."""
    H = r.H
    y = 0.17 * H if y is None else y
    n = (math.cos(angle), math.sin(angle), 0.0)
    band = intersect(offset(r.sdf["torso"], thickness), plane_slab((x, y, 0), n, width / 2), k=thickness * 0.5)
    return clay_mesh(name, band, color if not isinstance(color, str) else ck.clay(color, 0.8), r.body, cell=0.0016 * H, target=1600)


def bow_tie(r, color="#c4162a", name="BowTie"):
    """A clay bow tie at the front of the collar (Body-local)."""
    H = r.H
    ring, th = _neck_ring(r, r.sdf["torso"])
    c = ring[0] + np.array([0, -0.008 * H, 0.012 * H])
    s = union(sphere(c, 0.0095 * H),
              *[round_cone(c, c + np.array([sx * 0.036 * H, 0.006 * H, -0.004 * H]), 0.008 * H, 0.0165 * H) for sx in (-1, 1)],
              *[round_cone(c, c + np.array([sx * 0.034 * H, -0.009 * H, -0.004 * H]), 0.007 * H, 0.013 * H) for sx in (-1, 1)], k=0.004 * H)
    return clay_mesh(name, s, ck.clay(color, 0.8), r.body, cell=0.0009 * H, target=700)


# ====================================================================== export
def export_character(asset_id):
    """godot/assets/models/characters/<id>.glb (+ blender/blend/<id>.blend). Call before any preview."""
    path = ck.export(asset_id, subdir="characters")
    check_rig()
    return path


CONTRACT = {   # pivot: (parent, local position in H)
    "Rig": (None, (0, 0, 0)), "LegR": ("Rig", (-0.085, 0.47, 0)), "LegL": ("Rig", (0.085, 0.47, 0)),
    "Body": ("Rig", (0, 0.47, 0)), "ArmR": ("Body", (-0.185, 0.31, 0)), "ArmL": ("Body", (0.185, 0.31, 0)),
    "HandR": ("ArmR", (0, -0.30, 0)), "HandL": ("ArmL", (0, -0.30, 0)), "Head": ("Body", (0, 0.36, 0)),
    "Mouth": ("Head", (0, 0.115, 0.1)),
}


def check_rig(H=None):
    """Print the pivot hierarchy and compare it with the README contract."""
    obs = bpy.context.scene.objects
    if H is None:
        H = obs["Body"].location.z / 0.47
    ok = True
    for name, (par, pos) in CONTRACT.items():
        ob = obs.get(name)
        if ob is None:
            print(f"[person] MISSING {name}")
            ok = False
            continue
        loc = ob.location
        g = (loc.x, loc.z, -loc.y)
        want = tuple(v * H for v in pos)
        err = max(abs(a - b) for a, b in zip(g, want))
        pn = ob.parent.name if ob.parent else None
        sc = tuple(round(v, 4) for v in ob.scale)
        bad = err > 1e-5 or pn != par or sc != (1.0, 1.0, 1.0)
        ok &= not bad
        print(f"[person] {'BAD ' if bad else ''}{name:6s} parent={pn!s:5s} pos=({g[0]:+.4f},{g[1]:+.4f},{g[2]:+.4f}) scale={sc}")
    print(f"[person] rig contract {'OK' if ok else 'FAILED'} (H={H:.3f})")
    return ok


# ====================================================================== posing and pose previews
def set_pose(r, walk=0.0, phase=math.pi / 2, armR=None, armL=None, lean=0.0, tilt=0.0, nod=0.0, look=0.0, bob=0.0, mouth=0.0, legs=None):
    """The JS pose(): arms [forward-raise, outward], three.js Euler XYZ, mouth scale y = .3 + open*.9.
    legs=(right, left) overrides the walk swing (the baby's crawl)."""
    sw = math.sin(phase) * walk if walk else 0.0
    lr, ll = legs if legs else (sw, -sw)
    _rot(r.legR, (lr, 0, 0))
    _rot(r.legL, (ll, 0, 0))
    aR = armR or (-sw * 0.8, 0.08)
    aL = armL or (sw * 0.8, 0.08)
    _rot(r.armR, (aR[0], 0, -aR[1]))
    _rot(r.armL, (aL[0], 0, aL[1]))
    _rot(r.body, (lean, 0, tilt))
    _rot(r.head, (nod, look, 0))
    r.body.location = ck.G(0, 0.47 * r.H + bob, 0)
    r.mouth.scale = ck.gscale(1, 0.3 + mouth * 0.9, 1)
    bpy.context.view_layer.update()


def binocular_check(r):
    """Where the hands land for the binoculars pose (three.js XYZ), as the game passes it and with the
    outward sign flipped; prints the distance from each hand center to the binocular barrel in front of
    each eye (2-Pack's binoculars: Head-local (+-0.042H, hy+0.02H, 0.17H))."""
    H = r.H
    out = {}
    for label, aR, aL in (("as given (-2.45, 0, -/+0.42)", (-2.45, 0.42), (-2.45, 0.42)),
                          ("outward flipped (-2.45, 0, +/-0.42)", (-2.45, -0.42), (-2.45, -0.42))):
        reset_pose(r)
        set_pose(r, armR=aR, armL=aL)
        res = []
        for hand, sx in ((r.handR, -1), (r.handL, 1)):
            hw = hand.matrix_world.translation
            bw = r.head.matrix_world @ ck.G(sx * 0.042 * H, r.hy + 0.02 * H, 0.17 * H)
            res.append((hw - bw).length / H)
        out[label] = res
        print(f"[person] binoculars {label}: hand-to-barrel R {res[0]:.3f}H  L {res[1]:.3f}H  ({res[0] * H:.2f} m)")
    reset_pose(r)
    return out


def reset_pose(r):
    for p in (r.legR, r.legL, r.armR, r.armL, r.body, r.head):
        _rot(p, (0, 0, 0))
    r.body.location = ck.G(0, 0.47 * r.H, 0)
    r.mouth.scale = (1, 1, 1)
    bpy.context.view_layer.update()


POSES = {
    "binoculars": dict(armR=(-2.45, 0.42), armL=(-2.45, 0.42)),
    "walk": dict(walk=0.5, phase=math.pi / 2),
    "run": dict(walk=0.95, phase=math.pi / 2, lean=0.3, armR=(-1.3, 0.1), armL=(1.3, 0.1)),
    "nod_look": dict(nod=0.25, look=0.6, mouth=0.0, armR=(-0.15, 0.1), armL=(-0.15, 0.1)),
    "talk": dict(mouth=1.0, armR=(-0.9, 0.45), armL=(-0.9, 0.45), nod=-0.1),
    "idle": dict(armR=(-0.15, 0.1), armL=(-0.15, 0.1)),
}


def _scene_preview_setup():
    sc = bpy.context.scene
    ck._preview_materials()
    ck._engine(sc)
    try:
        sc.eevee.taa_render_samples = 24
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "AgX"
    except Exception:
        pass
    if sc.world is None or sc.world.name != "sky":
        w = bpy.data.worlds.new("sky")
        try:
            w.use_nodes = True
        except Exception:
            pass
        bg = next((n for n in w.node_tree.nodes if n.type == "BACKGROUND"), None)
        bg.inputs["Color"].default_value = (*ck._rgb(ck.SKY), 1)
        bg.inputs["Strength"].default_value = 0.9
        sc.world = w
    if not any(o.type == "LIGHT" for o in sc.objects):
        sd = bpy.data.lights.new("_pv_sun", "SUN")
        sd.energy, sd.color, sd.angle = 3.2, (1.0, 0.94, 0.85), math.radians(4)
        sun = bpy.data.objects.new("_pv_sun", sd)
        ck._link(sun)
        sun.rotation_mode = "QUATERNION"
        sun.rotation_quaternion = ck.G(14, 26, 12).normalized().to_track_quat("Z", "Y")
    if "_ground" not in sc.objects:
        ck.plane(20, 20, (0, -0.002, 0), ck.clay("#7d7a70", 0.95), name="_ground")
    cam = sc.objects.get("_pv_cam") or sc.objects.get("cam")
    if cam is None:
        cam = bpy.data.objects.new("_pv_cam", bpy.data.cameras.new("_pv_cam"))
        ck._link(cam)
    sc.camera = cam
    return sc, cam


def pose_sheet(r, sheet_id, tiles=None, size=(900, 700)):
    """Render up to 4 posed tiles into .work/previews/<sheet_id>.png (NOT exported; call after export).
    tiles: [{"pose": dict for set_pose, "eye": (x,y,z), "look": (x,y,z), "lens": 50}, ...] in game coords."""
    import numpy as _np
    H = r.H
    if tiles is None:
        tiles = default_tiles(r)
    sc, cam = _scene_preview_setup()
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    imgs = []
    for i, t in enumerate(tiles[:4]):
        reset_pose(r)
        set_pose(r, **t.get("pose", {}))
        if "rig_rot" in t:
            _rot(r.rig, t["rig_rot"])
        else:
            _rot(r.rig, (0, 0, 0))
        r.rig.location = ck.G(t.get("rig_pos", (0, 0, 0)))
        cam.data.lens = t.get("lens", 50)
        cam.data.clip_start = 0.01
        ck._look_at(cam, ck.G(t["eye"]), ck.G(t["look"]))
        tmp = os.path.join(ck.PREVIEWS, f"_{sheet_id}_{i}.png")
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = _np.empty(size[0] * size[1] * 4, dtype=_np.float32)
        img.pixels.foreach_get(px)
        imgs.append(px.reshape(size[1], size[0], 4))
        bpy.data.images.remove(img)
        os.remove(tmp)
    while len(imgs) < 4:
        imgs.append(_np.ones_like(imgs[0]))
    sheet = _np.concatenate([_np.concatenate([imgs[2], imgs[3]], 1), _np.concatenate([imgs[0], imgs[1]], 1)], 0)
    out = bpy.data.images.new(f"sheet_{sheet_id}", size[0] * 2, size[1] * 2, alpha=True)
    out.pixels.foreach_set(_np.ascontiguousarray(sheet, dtype=_np.float32).ravel())
    path = os.path.join(ck.PREVIEWS, sheet_id + ".png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    reset_pose(r)
    _rot(r.rig, (0, 0, 0))
    r.rig.location = (0, 0, 0)
    print(f"[person] pose sheet {path}")
    return path


def default_tiles(r):
    """Binoculars (front 3/4 and from behind), a walk from the side, a nod/look with the mouth shut."""
    H = r.H
    hc = 0.47 * H + 0.36 * H + r.hy
    return [
        dict(pose=POSES["binoculars"], eye=(0.75 * H, hc + 0.05 * H, 1.15 * H), look=(0, hc - 0.12 * H, 0.05 * H), lens=50),
        dict(pose=POSES["binoculars"], eye=(-0.7 * H, hc + 0.25 * H, -1.0 * H), look=(0, hc - 0.15 * H, 0), lens=50),
        dict(pose=POSES["walk"], eye=(2.2 * H, 0.55 * H, 0.35 * H), look=(0, 0.48 * H, 0), lens=50),
        dict(pose=POSES["nod_look"], eye=(0.25 * H, hc + 0.02 * H, 0.75 * H), look=(0, hc - 0.03 * H, 0), lens=55),
    ]
