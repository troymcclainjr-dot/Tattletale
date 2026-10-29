"""The street and all ground (world space): asphalt, sidewalks, curbs, grass, road paint, end walls, chain-link fence, power line."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, bisect, math, random
from mathutils import Vector, noise

ck.reset()
R = random.Random(1907)
TAU = math.tau

# ------------------------------------------------------------------ layout (JS world.js buildBlock)
X0, X1 = -59.0, 71.0                       # every ground strip is 130 m long, centered on x=6
SW, CURB_H, GRASS_H = 0.16, 0.18, 0.12     # walkable tops (groundY); the street is 0
PAINT = 0.004                              # road paint stands 4 mm proud of the asphalt (scuffs 2.5 mm above that)
GD = 0.008                                 # pressed joint depth
GW = 0.018                                 # pressed joint half width
DRAIN = (0.04, 0.96, 0.14, 0.41)           # storm drain hole in the north gutter: x0, x1, z0, z1
WALLS = (-33.2, 46.6)                      # BOUNDS.x0-1.2, BOUNDS.x1+1.6
SHOES_ON_WIRE = True                       # the JS "insulators" (two white .15x.12x.3 boxes hung .4 m under the wire) read as sneakers

# ------------------------------------------------------------------ materials (JS colors; new ones only for new details)
ASPH = ck.clay("asphalt", 0.95)
PATCH_OLD, PATCH_NEW = ck.clay("#48484d", 0.95), ck.clay("#2c2c31", 0.95)
TAR = ck.gloss("#17171a", 0.45)
OIL = ck.clay("#36363b", 0.8)
IRON, IRON_D = ck.metal("#57534e", 0.55), ck.metal("#45423e", 0.6)   # cast iron: manholes, grate, meter lids
PIT = ck.clay("#121214", 0.95)
SIDE, SIDE_L, SIDE_D = ck.clay("sidewalk"), ck.clay("#b2aea4"), ck.clay("#9c988e")
JOINT_SW = ck.clay("#86827a")                  # dirt packed into the pressed joints
CRACK = ck.clay("crack")
CURB, CURB_D, JOINT_C = ck.clay("curb"), ck.clay("#bbb7ab"), ck.clay("#9e9a8f")
GUTTER, JOINT_G = ck.clay("#8f8c83"), ck.clay("#6e6b64")
RED = ck.clay("fire_red", 0.5)
GRASS, VERGE = ck.clay("grass", 0.95), ck.clay("#5f7d36", 0.95)
TUFT_D, TUFT_L = ck.clay("#56752e", 0.95), ck.clay("#7d9d46", 0.95)
DIRT = ck.clay("#6e5a3c", 0.95)
TUFT_DRY = ck.clay("#9c9a4e", 0.95)              # straw-colored weeds
YELLOW, YELLOW_F = ck.clay("lane_yellow"), ck.clay("#dcb43a")
XWALK, WHITE = ck.clay("crosswalk"), ck.clay("cream")
WORN = ck.clay("#a7a49b")                      # paint scuffed thin by tires
WALL_T = [ck.clay("wall"), ck.clay("#46464e"), ck.clay("#4f4f57")]
WALL_CAP, GRIME, STREAK = ck.clay("#5a5a62"), ck.clay("#35353b"), ck.clay("#3e3e45")
CONC = ck.clay("concrete")
FENCE, FENCE_MESH = ck.metal("fence", 0.4), ck.glass("fence", 0.38)
WIRE = ck.clay("wire")
WOOD = ck.clay("#6a5846")
CERAMIC = ck.clay("insulator", 0.4)
SHOE, SOLE, SHOE_IN = ck.clay("insulator"), ck.clay("#dcdad2"), ck.clay("#2a2624")
GUARD = ck.clay("lane_yellow", 0.5)
HARDWARE = ck.metal("iron", 0.5)


# ------------------------------------------------------------------ mesh helpers (game coords)
def n1(x, s=0.0):
    return noise.noise(Vector((x, s * 1.731 + 0.37, s * 0.917 + 0.11)))


class MB:
    """Collects game-space vertices and faces, then builds one object with several materials."""
    def __init__(s, name):
        s.name, s.V, s.F, s.M, s.S, s.mats = name, [], [], [], [], []

    def v(s, x, y, z):
        s.V.append((x, -z, y))
        return len(s.V) - 1

    def f(s, idx, m, smooth=True):
        if m not in s.mats:
            s.mats.append(m)
        s.F.append(tuple(idx))
        s.M.append(s.mats.index(m))
        s.S.append(smooth)

    def build(s, sharp=45):
        me = bpy.data.meshes.new(s.name)
        me.from_pydata(s.V, [], s.F)
        for m in s.mats:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", s.M)
        me.polygons.foreach_set("use_smooth", s.S)
        me.validate(clean_customdata=False)
        me.update()
        if sharp:
            me.set_sharp_from_angle(angle=math.radians(sharp))
        o = bpy.data.objects.new(s.name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


def sheet(mb, P, mfn, flip=False):
    """Quad sheet over a grid of game points P[i][k]; with i along x and k along +z the faces point up."""
    ids = [[mb.v(*p) for p in row] for row in P]
    for i in range(len(P) - 1):
        for k in range(len(P[0]) - 1):
            m = mfn(i, k)
            if m is None:
                continue
            q = [ids[i][k], ids[i][k + 1], ids[i + 1][k + 1], ids[i + 1][k]]
            mb.f(q[::-1] if flip else q, m)
    return ids


def poly(mb, pts, m, flip=False):
    ids = [mb.v(*p) for p in pts]
    mb.f(ids[::-1] if flip else ids, m, smooth=False)


def end_caps(mb, P, m, flip):
    """Close the two ends of a swept profile (stations along x) down to y=0."""
    for i, fl in ((0, not flip), (len(P) - 1, flip)):
        pts = list(P[i])
        if pts[-1][1] > 0.001:
            pts.append((pts[-1][0], 0.0, pts[-1][2]))
        if pts[0][1] > 0.001:
            pts.append((pts[0][0], 0.0, pts[0][2]))
        poly(mb, pts, m, flip=fl)


def polar(mb, cx, cz, rings, n, y0=0.0):
    """Round flat thing facing up. rings: [(r, y, m)] from the outside in; r=0 closes the center."""
    ids = []
    for (r, y, m) in rings:
        if r == 0:
            ids.append([mb.v(cx, y0 + y, cz)] * n)
        else:
            ids.append([mb.v(cx + r * math.cos(TAU * q / n), y0 + y, cz + r * math.sin(TAU * q / n)) for q in range(n)])
    for k in range(len(rings) - 1):
        for q in range(n):
            q1 = (q + 1) % n
            f = [ids[k + 1][q], ids[k + 1][q1], ids[k][q1], ids[k][q]]
            f = [v for j, v in enumerate(f) if v not in f[:j]]
            mb.f(f, rings[k][2])


def outline(cx, cz, a, b, rot=0.0, shape=2.0, jit=0.12, nseg=16, seed=0.0):
    """Irregular closed outline [(x, z)] (superellipse with two octaves of wobble), counter-clockwise in x/z."""
    cr, sr = math.cos(rot), math.sin(rot)
    pts = []
    for q in range(nseg):
        t = TAU * q / nseg
        ct, st = math.cos(t), math.sin(t)
        r = (abs(ct) ** shape + abs(st) ** shape) ** (-1.0 / shape)
        r *= 1 + jit * (n1(math.cos(t) * 1.3 + seed * 5.3, math.sin(t) * 1.3 + seed) + 0.5 * n1(math.cos(t) * 3.7 + seed, math.sin(t) * 3.7 - seed))
        lx, lz = a * r * ct, b * r * st
        pts.append((cx + lx * cr - lz * sr, cz + lx * sr + lz * cr))
    return pts


def clip(pts, x0, x1, z0, z1):
    """Sutherland-Hodgman clip of a polygon [(x, z)] to a rectangle."""
    for axis, lim, keep_lo in ((0, x0, True), (0, x1, False), (1, z0, True), (1, z1, False)):
        out = []
        for i, p in enumerate(pts):
            q = pts[i - 1]
            pin, qin = (p[axis] >= lim) == keep_lo, (q[axis] >= lim) == keep_lo
            if pin != qin:
                t = (lim - q[axis]) / (p[axis] - q[axis])
                out.append((q[0] + (p[0] - q[0]) * t, q[1] + (p[1] - q[1]) * t))
            if pin:
                out.append(p)
        pts = out
        if not pts:
            break
    return pts


def flat_poly(mb, pts, y, m):
    """Fan a star-shaped outline [(x, z)] (counter-clockwise in x/z) into an upward-facing patch."""
    cx, cz = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    c = mb.v(cx, y, cz)
    ring = [mb.v(x, y, z) for x, z in pts]
    for q in range(len(ring)):
        mb.f([c, ring[(q + 1) % len(ring)], ring[q]], m)


def blob(mb, cx, cz, a, b, y, m, rot=0.0, shape=2.0, jit=0.12, drop=0.002, nseg=16, seed=0.0):
    """Irregular flat patch facing up (superellipse outline), edge dropped a little so it reads as a layer."""
    cr, sr = math.cos(rot), math.sin(rot)
    c = mb.v(cx, y, cz)
    inner, outer = [], []
    for q in range(nseg):
        t = TAU * q / nseg
        ct, st = math.cos(t), math.sin(t)
        r = (abs(ct) ** shape + abs(st) ** shape) ** (-1.0 / shape)
        r *= 1 + jit * (n1(math.cos(t) * 1.3 + seed * 5.3, math.sin(t) * 1.3 + seed) + 0.5 * n1(math.cos(t) * 3.7 + seed, math.sin(t) * 3.7 - seed))
        lx, lz = a * r * ct, b * r * st
        x, z = lx * cr - lz * sr, lx * sr + lz * cr
        inner.append(mb.v(cx + 0.84 * x, y, cz + 0.84 * z))
        outer.append(mb.v(cx + x, y - drop, cz + z))
    for q in range(nseg):
        q1 = (q + 1) % nseg
        mb.f([c, inner[q1], inner[q]], m)
        mb.f([inner[q], inner[q1], outer[q1], outer[q]], m)


def ribbon(mb, pts, widths, yfn, m):
    """Flat strip along a centerline [(x, z)], facing up; yfn(x, z) gives its height."""
    L, Rt = [], []
    for i, (x, z) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dz) or 1.0
        px, pz = -dz / l * widths[i] / 2, dx / l * widths[i] / 2
        L.append(mb.v(x + px, yfn(x + px, z + pz), z + pz))
        Rt.append(mb.v(x - px, yfn(x - px, z - pz), z - pz))
    for i in range(len(pts) - 1):
        mb.f([L[i], L[i + 1], Rt[i + 1], Rt[i]], m)


def tube(mb, pts, r, n, m, smooth=True):
    """Tube along game-space Vectors (wires, rails, laces)."""
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
        u = t.cross(a).normalized()
        w = t.cross(u).normalized()
        rings.append([mb.v(*(p + (u * math.cos(TAU * q / n) + w * math.sin(TAU * q / n)) * r)) for q in range(n)])
    for i in range(len(pts) - 1):
        for q in range(n):
            q1 = (q + 1) % n
            mb.f([rings[i][q], rings[i][q1], rings[i + 1][q1], rings[i + 1][q]], m, smooth)


def lathe(mb, cx, cz, prof, n, lean=(0.0, 0.0), phase=0.0):
    """Surface of revolution around a vertical axis. prof: [(r, y, m)] bottom to top (m = band above); r=0 closes."""
    ids, y0 = [], prof[0][1]
    for (r, y, m) in prof:
        ox, oz = cx + lean[0] * (y - y0), cz + lean[1] * (y - y0)
        if r == 0:
            ids.append([mb.v(ox, y, oz)] * n)
        else:
            ids.append([mb.v(ox + r * math.cos(phase + TAU * q / n), y, oz + r * math.sin(phase + TAU * q / n)) for q in range(n)])
    for i in range(len(prof) - 1):
        for q in range(n):
            q1 = (q + 1) % n
            f = [ids[i][q], ids[i + 1][q], ids[i + 1][q1], ids[i][q1]]
            f = [v for j, v in enumerate(f) if v not in f[:j]]
            if len(f) >= 3:
                mb.f(f, prof[i][2])


def mound(mb, cx, cz, a, b, y0, h, m, rot=0.0, nseg=20, seed=0.0):
    """Low lumpy mound of clay (bare dirt), h high in the middle, its rim just above the ground."""
    out = outline(cx, cz, a, b, rot, 2.0, 0.3, nseg, seed)
    ids = []
    for f, hy in ((1.0, 0.0), (0.8, 0.55), (0.5, 0.9), (0.22, 1.0)):
        ring = []
        for x, z in out:
            px, pz = cx + (x - cx) * f, cz + (z - cz) * f
            ring.append(mb.v(px, y0 + 0.0015 + h * hy * (1 + 0.35 * n1(px * 9.1, pz * 9.1 + seed)), pz))
        ids.append(ring)
    c = mb.v(cx, y0 + 0.0015 + h * (1 + 0.2 * n1(cx * 3.3, cz * 3.3)), cz)
    for k in range(3):
        for q in range(nseg):
            q1 = (q + 1) % nseg
            mb.f([ids[k + 1][q], ids[k + 1][q1], ids[k][q1], ids[k][q]], m)
    for q in range(nseg):
        mb.f([c, ids[-1][(q + 1) % nseg], ids[-1][q]], m)


def tuft(mb, x, z, y0, s, mats, nb=None):
    """A pinched clump of clay grass blades."""
    m = R.choice(mats)
    for _ in range(nb or R.randint(4, 6)):
        a, r0 = R.uniform(0, TAU), R.uniform(0.0, 0.02) * s
        bx, bz = x + math.cos(a) * r0, z + math.sin(a) * r0
        h = R.uniform(0.026, 0.06) * s
        la, lean = a + R.uniform(-0.6, 0.6), R.uniform(0.2, 0.65) * h
        tip = mb.v(bx + math.cos(la) * lean, y0 + h, bz + math.sin(la) * lean)
        br, a0 = R.uniform(0.006, 0.01) * s, R.uniform(0, TAU)
        base = [mb.v(bx + math.cos(a0 + q * TAU / 3) * br, y0 - 0.004, bz + math.sin(a0 + q * TAU / 3) * br) for q in range(3)]
        for q in range(3):
            mb.f([base[(q + 1) % 3], base[q], tip], m)


def joint_centers(a, b, step, jit):
    out, x = [], a + step * R.uniform(0.3, 0.9)
    while x < b - 0.3:
        out.append(x)
        x += step + R.uniform(-jit, jit)
    return out


def stations(a, b, centers, gw, extra=()):
    """Stations along x: ends, extras, and a (rim, center, rim) triplet per pressed joint."""
    st = [(a, -1, False), (b, -1, False)] + [(e, -1, False) for e in extra]
    for k, c in enumerate(centers):
        st += [(c - gw, k, False), (c, k, True), (c + gw, k, False)]
    return sorted(st)


def free(x, z, regions):
    return not any(a <= x <= b and c <= z <= d for a, b, c, d in regions)


# ------------------------------------------------------------------ sidewalks: slabs with pressed joints
def sidewalk(name, rows, zjoints, ncracks, crack_z, crack_x):
    """rows: [(z, y, is_joint_center, joint_group)] with z increasing; y=None is the slab top.
    Transverse joints every ~1.55 m. Returns the MeshBuilder and a surface height function."""
    cx = joint_centers(X0, X1, 1.55, 0.07)
    st = stations(X0, X1, cx, GW)
    skew = [R.uniform(-0.006, 0.006) for _ in cx]
    zmid = (rows[0][0] + rows[-1][0]) / 2
    slabs = {}

    def slab(x, z):
        key = (bisect.bisect(cx, x), bisect.bisect(zjoints, z))
        if key not in slabs:
            r = R.random()
            slabs[key] = (SIDE_L if r < 0.07 else SIDE_D if r < 0.15 else SIDE, R.uniform(-0.0011, 0.0011), R.uniform(-0.0014, 0.0014))
        return slabs[key]

    def top(x, z):
        m, t0, tx = slab(x, z)
        ix = bisect.bisect(cx, x)
        xl, xr = (cx[ix - 1] if ix > 0 else X0), (cx[ix] if ix < len(cx) else X1)
        return SW + t0 + tx * ((x - xl) / max(xr - xl, 0.1) - 0.5)

    P = []
    for (sx, j, center) in st:
        row = []
        for (rz, ry, rcenter, grp) in rows:
            z = rz + (0.005 * n1(sx * 0.21 + grp * 3.3, 4) if grp >= 0 else 0.0)
            x = sx + (skew[j] * (z - zmid) if j >= 0 else 0.0)
            if center or rcenter:
                y = min(ry if ry is not None else SW, SW - GD)
            else:
                y = ry if ry is not None else top(x, z)
            row.append((x, y, z))
        P.append(row)
    mb = MB(name)
    def sm(i, k):
        if st[i][2] or st[i + 1][2] or rows[k][2] or rows[k + 1][2]:
            return JOINT_SW
        return slab((P[i][k][0] + P[i + 1][k + 1][0]) / 2, (P[i][k][2] + P[i + 1][k + 1][2]) / 2)[0]
    sheet(mb, P, sm)
    end_caps(mb, P, SIDE, False)

    def surf(x, z):
        ix = bisect.bisect(cx, x)
        d = min([abs(x - (cx[j] + skew[j] * (z - zmid))) for j in (ix - 1, ix) if 0 <= j < len(cx)] + [abs(z - zj) for zj in zjoints])
        base = top(x, z)
        return base + (SW - GD - base) * (1 - d / GW) if d < GW else base

    # hairline cracks (JS: 20 dark boxes on the north sidewalk, randomized; these are seeded polylines)
    for _ in range(ncracks):
        L, x, z, ang = R.uniform(0.4, 1.2), R.uniform(*crack_x), R.uniform(*crack_z), R.uniform(-1, 1)
        dx, dz = math.cos(ang), -math.sin(ang)
        n = max(5, int(L / 0.06))
        off, pts = 0.0, []
        for i in range(n + 1):
            t = i / n - 0.5
            off = max(-0.035, min(0.035, off + R.uniform(-0.012, 0.012)))
            pts.append((x + dx * t * L - dz * off, z + dz * t * L + dx * off))
        ws = [0.004 + 0.016 * max(0.0, math.sin(math.pi * i / n)) ** 0.7 for i in range(n + 1)]
        ribbon(mb, pts, ws, lambda a, b: surf(a, b) + 0.003, CRACK)
        if R.random() < 0.45:   # a short branch
            k0 = R.randint(n // 3, 2 * n // 3)
            bx, bz = pts[k0]
            ba = ang + R.choice((-1, 1)) * R.uniform(0.5, 1.1)
            bl = L * R.uniform(0.25, 0.45)
            bp = [(bx + math.cos(ba) * bl * t / 4 + R.uniform(-0.01, 0.01), bz - math.sin(ba) * bl * t / 4 + R.uniform(-0.01, 0.01)) for t in range(5)]
            ribbon(mb, bp, [0.012, 0.01, 0.008, 0.006, 0.003], lambda a, b: surf(a, b) + 0.003, CRACK)
    return mb, surf


NROWS = [(-3.2, 0.110, False, -1), (-3.2, 0.146, False, -1), (-3.195, 0.1555, False, -1), (-3.185, None, False, -1),
         (-1.66 - GW, None, False, 0), (-1.66, None, True, 0), (-1.66 + GW, None, False, 0), (-0.06, None, False, -1)]
SROWS = [(13.22, None, False, -1)]
for g, zj in enumerate((14.66, 16.11, 17.55)):
    SROWS += [(zj - GW, None, False, g), (zj, None, True, g), (zj + GW, None, False, g)]
SROWS += [(18.985, None, False, -1), (18.995, 0.1555, False, -1), (19.0, 0.146, False, -1), (19.0, 0.0, False, -1)]

side_n, surf_n = sidewalk("Sidewalk_North", NROWS, [-1.66], 20, (-2.8, -0.4), (-30, 44))
side_s, surf_s = sidewalk("Sidewalk_South", SROWS, [14.66, 16.11, 17.55], 10, (13.6, 18.4), (-30, 44))


# ------------------------------------------------------------------ curbs (rounded nose, pressed joints) and gutter pans
CURB_P = [(-0.125, 0.12), (-0.125, 0.168), (-0.121, 0.1765), (-0.111, 0.18), (0.072, 0.18), (0.097, 0.1775),
          (0.112, 0.1705), (0.1215, 0.159), (0.125, 0.144), (0.128, 0.0)]
GUT_P = [(0.118, 0.005), (0.14, 0.005), (0.41, 0.005), (0.42, 0.003), (0.426, 0.0)]


def prof_normals(P):
    out = []
    for k in range(len(P)):
        a, b = P[max(k - 1, 0)], P[min(k + 1, len(P) - 1)]
        tz, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tz, ty) or 1.0
        out.append((-ty / l, tz / l))
    return out


def wob_z(x, seed):
    """Hand-set curb line waviness (calm at the storm drain so the grate fits)."""
    k = min(1.0, max(0.0, (abs(x - 0.5) - 0.7) / 1.0))
    return 0.005 * n1(x * 0.3, seed) * k


def curb_and_gutter(name, side, seed):
    """side=+1: north curb straddling z=0, front to +z; -1: south curb, front face at z=13 facing -z."""
    mz = (lambda pz: pz) if side > 0 else (lambda pz: 13.125 - pz)
    extra = (7.1, 12.1) if side > 0 else ()
    cj = [c for c in joint_centers(X0, X1, 1.85, 0.12) if all(abs(c - e) > 0.06 for e in extra)]
    st = stations(X0, X1, cj, 0.011, extra)
    N = prof_normals(CURB_P)
    P = []
    for (x, j, center) in st:
        dz, dy = wob_z(x, seed), 0.0015 * n1(x * 0.55, seed + 9)
        row = []
        for (pz, py), (nz, ny) in zip(CURB_P, N):
            if center:
                pz, py = pz - nz * 0.006, py - ny * 0.006
            row.append((x, py + (dy if py > 0.1 else 0.0), mz(pz) + dz))
        P.append(row)
    tone = {}

    def cm(i, k):
        xm = (st[i][0] + st[i + 1][0]) / 2
        if side > 0 and 7.1 <= xm <= 12.1:
            return RED                                  # the fire lane
        if st[i][2] or st[i + 1][2]:
            return JOINT_C
        key = bisect.bisect(cj, xm)
        if key not in tone:
            tone[key] = CURB_D if R.random() < 0.18 else CURB
        return tone[key]
    mb = MB(name)
    sheet(mb, P, cm, flip=side < 0)
    end_caps(mb, P, CURB, side < 0)
    # gutter pan: joints at every other curb joint
    gx = (DRAIN[0], DRAIN[1]) if side > 0 else ()
    gj = [c for c in cj[::2] if all(abs(c - e) > 0.06 for e in gx)]
    gs = stations(X0, X1, gj, 0.009, gx)
    G = [[(x, py - (0.003 if center and py > 0.004 else 0.0), mz(pz) + wob_z(x, seed)) for (pz, py) in GUT_P] for (x, j, center) in gs]

    def gm(i, k):
        xm = (gs[i][0] + gs[i + 1][0]) / 2
        if side > 0 and k == 1 and DRAIN[0] < xm < DRAIN[1]:
            return None
        return JOINT_G if gs[i][2] or gs[i + 1][2] else GUTTER
    sheet(mb, G, gm, flip=side < 0)
    return mb


curb_n = curb_and_gutter("Curb_North", 1, 3)
curb_s = curb_and_gutter("Curb_South", -1, 8)


# ------------------------------------------------------------------ asphalt: patches, tar snakes, manholes, storm drain
asph = MB("Asphalt")
xs, zs = [X0, DRAIN[0], DRAIN[1], X1], [0.0, DRAIN[2], DRAIN[3], 14.0]
sheet(asph, [[(x, 0.0, z) for z in zs] for x in xs], lambda i, k: None if (i, k) == (1, 1) else ASPH)
for x, fl in ((X0, True), (X1, False)):
    poly(asph, [(x, 0.0, 0.0), (x, 0.0, 14.0), (x, -0.1, 14.0), (x, -0.1, 0.0)], ASPH, flip=fl)

# storm drain: a dark pit under the hole, an iron grate on top (the gutter runs past it)
a, b, c, d = DRAIN
top_y, bot = 0.0049, -0.14
poly(asph, [(a, top_y, c), (a, top_y, d), (a, bot, d), (a, bot, c)], PIT)
poly(asph, [(b, top_y, c), (b, top_y, d), (b, bot, d), (b, bot, c)], PIT, flip=True)
poly(asph, [(a, top_y, c), (a, bot, c), (b, bot, c), (b, top_y, c)], PIT)
poly(asph, [(a, top_y, d), (a, bot, d), (b, bot, d), (b, top_y, d)], PIT, flip=True)
poly(asph, [(a, bot, c), (a, bot, d), (b, bot, d), (b, bot, c)], PIT)
grate = []
for k in range(9):
    gx = a + 0.06 + k * (b - a - 0.12) / 8
    grate.append(ck.box(0.026, 0.045, d - c + 0.01, (gx, 0.0075 - 0.0225, (c + d) / 2), IRON, bevel=0.006, bevel_segs=1, name="grate"))
grate.append(ck.box(b - a, 0.03, 0.024, ((a + b) / 2, -0.009, (c + d) / 2), IRON, bevel=0.005, bevel_segs=1, name="grate"))
for z in (c - 0.006, d + 0.006):
    grate.append(ck.box(b - a + 0.05, 0.014, 0.034, ((a + b) / 2, 0.002, z), IRON, bevel=0.005, bevel_segs=1, name="grate"))
for x in (a - 0.006, b + 0.006):
    grate.append(ck.box(0.034, 0.014, d - c + 0.05, (x, 0.002, (c + d) / 2), IRON, bevel=0.005, bevel_segs=1, name="grate"))
# a dark inlet slot in the curb face above the grate, under a little concrete hood
grate.append(ck.box(b - a - 0.04, 0.055, 0.012, ((a + b) / 2, 0.07, 0.127), PIT, name="inlet"))
grate.append(ck.box(b - a + 0.02, 0.03, 0.03, ((a + b) / 2, 0.112, 0.133), CURB, bevel=0.008, bevel_segs=2, name="inlet_hood"))

AVOID_ROAD = [(0.85, 5.75, 0.3, 12.8), (-1.25, -0.55, 7.5, 12.8), (8.6, 10.6, 0.35, 0.85), (-7.8, -0.4, 0.0, 2.0),
              (-51.2, 71.0, 6.86, 7.14)]   # crosswalk, stop line, FIRE LANE, Gary's gutter, the lane dashes
PATCHES = [(-20.5, 4.4, 0.8, 0.55, 0.1, 2.5, PATCH_OLD), (-9.5, 10.6, 1.3, 0.7, -0.03, 6, PATCH_NEW),
           (13.6, 5.0, 0.5, 0.4, 0.6, 2, PATCH_OLD), (28.0, 11.3, 1.5, 0.5, 0.02, 6, PATCH_NEW),
           (34.4, 3.5, 0.65, 0.55, 0.4, 2.2, PATCH_OLD), (-27.2, 9.2, 0.55, 0.45, 1.0, 2, PATCH_OLD),
           (40.6, 8.6, 0.45, 0.35, 0.3, 2, PATCH_NEW), (7.0, 11.8, 0.8, 0.5, -0.1, 3, PATCH_OLD),
           (-3.5, 5.3, 0.6, 0.4, 0.2, 2, PATCH_NEW)]
for k, (px, pz, pa, pb, pr, sh, pm) in enumerate(PATCHES):
    blob(asph, px, pz, pa, pb, 0.003, pm, rot=pr, shape=sh, jit=0.07 if sh > 3 else 0.14, nseg=18, seed=k + 1)
    AVOID_ROAD.append((px - pa - 0.15, px + pa + 0.15, pz - pa - 0.15, pz + pa + 0.15))

# oil drips where cars stop: the cop car's spots, Mama's stop at the crosswalk, a few parking spots
for k, (ox, oz, oa) in enumerate([(42.6, 2.7, 0.5), (10.2, 2.65, 0.35), (-2.2, 10.5, 0.45), (-24.0, 2.8, 0.3),
                                  (31.0, 10.4, 0.3), (-16.5, 10.6, 0.25), (18.0, 2.75, 0.22)]):
    flat_poly(asph, outline(ox, oz, oa, oa * 0.55, R.uniform(-0.2, 0.2), 2.0, 0.38, 26, k + 60), 0.0028, OIL)
    for _ in range(R.randint(1, 3)):
        dr = R.uniform(0.03, 0.08)
        flat_poly(asph, outline(ox + R.uniform(-1.3, 1.3) * oa, oz + R.uniform(-0.9, 0.9) * oa * 0.55, dr, dr * 0.8, 0, 2.0, 0.3, 10, k + 9.1), 0.0028, OIL)
    AVOID_ROAD.append((ox - oa - 0.1, ox + oa + 0.1, oz - oa - 0.1, oz + oa + 0.1))

MANHOLES = [(-14.3, 2.8), (21.3, 10.9)]
for k, (mx, mz) in enumerate(MANHOLES):
    polar(asph, mx, mz, [(0.405, 0.0, IRON), (0.398, 0.0035, IRON), (0.388, 0.005, IRON), (0.345, 0.005, IRON),
                         (0.337, 0.0035, IRON), (0.33, 0.0015, IRON_D), (0.323, 0.0035, IRON_D), (0.316, 0.006, IRON_D),
                         (0.300, 0.006, IRON_D), (0.293, 0.004, IRON_D), (0.215, 0.004, IRON_D), (0.208, 0.0062, IRON_D),
                         (0.193, 0.0062, IRON_D), (0.186, 0.004, IRON_D), (0.09, 0.004, IRON_D), (0.083, 0.006, IRON_D),
                         (0.068, 0.006, IRON_D), (0.06, 0.004, IRON_D), (0.0, 0.004, IRON_D)], 32)
    for q in range(8):   # cast ribs between the rings
        ang = TAU * q / 8 + 0.2 * k
        grate.append(ck.box(0.1, 0.006, 0.018, (mx + math.cos(ang) * 0.14, 0.0035, mz + math.sin(ang) * 0.14), IRON_D,
                            rot=(0, -ang, 0), bevel=0.003, bevel_segs=1, name="rib"))
    AVOID_ROAD.append((mx - 0.6, mx + 0.6, mz - 0.6, mz + 0.6))

# tar-sealed cracks: start, heading, length, wiggle
TAR_LINES = [(-28, 6.72, 0.0, 6.0, 0.25), (12, 7.32, 0.0, 4.5, 0.25), (30, 6.74, math.pi, 5.0, 0.25),
             (14, 0.45, 0.0, 7.0, 0.06), (-26, 0.45, 0.0, 5.0, 0.06), (-18, 2.9, math.pi / 2, 3.0, 0.4),
             (24.5, 8.9, math.pi / 2, 3.5, 0.4), (-6.5, 9.6, -math.pi / 2, 2.4, 0.4), (38, 4.4, 0.6, 2.2, 0.5),
             (-12.5, 12.0, 0.2, 3.0, 0.35), (-20, 12.66, 0.0, 6.0, 0.06), (20, 12.66, 0.0, 5.0, 0.06),
             (7.4, 4.1, 1.2, 2.0, 0.45), (-36, 5.5, 0.1, 4.0, 0.35), (44, 10.0, 2.8, 3.0, 0.4)]
for (tx, tz, th, tl, wig) in TAR_LINES:
    seg, cur = [], []
    x, z, h = tx, tz, th
    for i in range(int(tl / 0.12) + 1):
        if free(x, z, AVOID_ROAD) and 0.42 < z < 12.7:
            cur.append((x, z))
        elif cur:
            seg.append(cur)
            cur = []
        h += R.uniform(-wig, wig) * 0.5 + (th - h) * 0.15
        x, z = x + math.cos(h) * 0.12, z + math.sin(h) * 0.12
    if cur:
        seg.append(cur)
    for s in seg:
        if len(s) >= 3:
            ws = [R.uniform(0.032, 0.05) * (0.45 if i in (0, len(s) - 1) else 1.0) for i in range(len(s))]
            ribbon(asph, s, ws, lambda a, b: 0.0032, TAR)


# ------------------------------------------------------------------ road paint (hand painted, a little worn)
paint = MB("RoadPaint")


def paint_rect(x0, x1, z0, z1, m, nx, nz, jit=0.006, rot=0.0, seed=0.0):
    """Hand-painted stripe: a grid with wavy edges, rotated a hair, edges a touch thinner."""
    xc, zc = (x0 + x1) / 2, (z0 + z1) / 2
    cr, sr = math.cos(rot), math.sin(rot)
    P = []
    for i in range(nx + 1):
        row = []
        for k in range(nz + 1):
            x, z = x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * k / nz
            ex, ez = i in (0, nx), k in (0, nz)
            x += jit * n1(z * 2.3 + seed * 7.7, i + seed) if ex else (x1 - x0) / nx * R.uniform(-0.2, 0.2)
            z += jit * 1.4 * n1(x * 7.1 + seed * 3.1, k + seed) if ez else (z1 - z0) / nz * R.uniform(-0.2, 0.2)
            dx, dz = x - xc, z - zc
            row.append((xc + dx * cr - dz * sr, PAINT - (0.0015 if ex or ez else 0.0), zc + dx * sr + dz * cr))
        P.append(row)
    sheet(paint, P, lambda i, k: m)


WHEELS = (1.9, 3.5, 9.7, 11.3)   # tire tracks: cop car lane z=2.7, Mama's lane z=10.5


def scuffs(x0, x1, z0, z1, seed, tracks=True, nchips=3, margin=0.02):
    """Worn spots in the tire tracks (asphalt showing, or paint scuffed thin) and a few chips."""
    spots = []
    if tracks:
        for zw in WHEELS:
            if z0 + 0.1 < zw < z1 - 0.1:
                for _ in range(R.choice((0, 1, 1, 1, 2))):
                    spots.append((R.uniform(x0 + 0.05, x1 - 0.05), zw + R.uniform(-0.14, 0.14), R.uniform(0.09, 0.24),
                                  R.uniform(0.05, 0.12), ASPH if R.random() < 0.55 else WORN))
    for _ in range(nchips):
        spots.append((R.uniform(x0, x1), R.uniform(z0, z1), R.uniform(0.015, 0.045), R.uniform(0.015, 0.04), ASPH))
    kept = []
    for k, (sx, sz, a, b, m) in enumerate(spots):
        r = max(a, b) * 1.5                            # outline wobble reaches ~1.45x
        if any(math.hypot(sx - kx, sz - kz) < r + kr for kx, kz, kr in kept):
            continue                                   # overlapping scuffs at one height would z-fight
        kept.append((sx, sz, r))
        pts = clip(outline(sx, sz, a, b, R.uniform(-0.3, 0.3), 2.0, 0.3, 14, seed + k * 1.7), x0 + margin, x1 - margin, z0 + margin, z1 - margin)
        if len(pts) >= 3:
            flat_poly(paint, pts, PAINT + 0.0025, m)


# 26 yellow lane dashes at x = -50 + 5k (the one inside the crosswalk and the one past the asphalt's end are left out)
for k in range(26):
    xc = -50 + 5 * k
    if (xc + 1 > 1.05 and xc - 1 < 5.6) or xc + 1 > X1:
        continue
    L = 2.0 + R.uniform(-0.04, 0.04)
    lo, hi = xc - L / 2, (min(xc + L / 2, 0.92) if xc < 1.05 else xc + L / 2)   # the x=0 dash stops short of the crosswalk
    paint_rect(lo, hi, 6.925, 7.075, YELLOW_F if R.random() < 0.3 else YELLOW, 8, 1, 0.005, R.uniform(-0.004, 0.004), k)
    scuffs(lo, hi, 6.925, 7.075, k * 3.1, tracks=False, nchips=R.choice((0, 1, 2)), margin=0.025)
# the crosswalk Grandma is NOT using
for k in range(5):
    xc = 1.3 + k + R.uniform(-0.02, 0.02)
    paint_rect(xc - 0.275, xc + 0.275, 0.45, 12.65, XWALK, 2, 41, 0.008, R.uniform(-0.0015, 0.0015), k + 40)
    scuffs(xc - 0.275, xc + 0.275, 0.45, 12.65, k * 7.3 + 40, nchips=4)
# stop line (buildStage2), far lane
paint_rect(-1.05, -0.75, 7.72, 12.65, WHITE, 2, 16, 0.006, 0.001, 77)
scuffs(-1.05, -0.75, 7.72, 12.65, 77, nchips=2)
paint_obj = paint.build()
fire_text = ck.text("FIRE LANE", 0.36, 0.005, (9.6, 0.002, 0.6), WHITE, rot=(-math.pi / 2, 0, R.uniform(-0.012, 0.012)),
                    font="impact", fit_width=1.3, bevel=0.0, name="FireLaneText")
ck.wobble(fire_text, 0.0015, 4.0, seed=3)
bm = bmesh.new()                                   # its underside sits below the asphalt: drop it
bm.from_mesh(fire_text.data)
rot3 = fire_text.rotation_quaternion.to_matrix()
bmesh.ops.delete(bm, geom=[f for f in bm.faces if (rot3 @ f.normal).z < -0.5], context="FACES")
bm.to_mesh(fire_text.data)
bm.free()
paint_obj = ck.join([paint_obj, fire_text], "RoadPaint")


# ------------------------------------------------------------------ grass strip (extends under the houses), verge past the fence
grass = MB("Grass")
sheet(grass, [[(x, GRASS_H, z) for z in (-18.0, -3.18)] for x in (X0, X1)], lambda i, k: GRASS)
for x, fl in ((X0, True), (X1, False)):
    poly(grass, [(x, GRASS_H, -18.0), (x, GRASS_H, -3.18), (x, 0.0, -3.18), (x, 0.0, -18.0)], GRASS, flip=fl)
DIRT_PATCHES = [(-17.5, -5.0, 1.15, 0.42, 0.0), (-10.5, -3.62, 0.55, 0.28, 0.1), (19.6, -3.6, 0.5, 0.26, -0.1),
                (-23.9, -5.6, 0.32, 0.55, 0.15), (17.1, -5.3, 0.3, 0.5, -0.1), (-28.6, -4.6, 0.4, 0.3, 0.7),
                (40.4, -4.9, 0.45, 0.32, 0.4), (2.8, -3.55, 0.45, 0.24, 0.0), (-4.3, -5.9, 0.35, 0.25, 0.9)]
for k, (bx, bz, ba, bb, br) in enumerate(DIRT_PATCHES):   # bare, trodden spots
    mound(grass, bx, bz, ba, bb, GRASS_H, 0.006, DIRT, rot=br, nseg=22, seed=k + 20)

verge = MB("Verge")
sheet(verge, [[(x, 0.0, z) for z in (18.99, 32.0)] for x in (X0, X1)], lambda i, k: VERGE)

GRASS_AVOID = [(8.6, 14.4, -6.9, -3.1), (33.3, 38.7, -5.8, -3.1), (-9.65, -8.35, -5.25, -4.15),
               (-19.2, -15.8, -5.6, -4.4), (15.6, 17.4, -3.5, -2.6)]
for sx_ in (22.5, 28.0, 43.5):
    GRASS_AVOID.append((sx_ - 0.85, sx_ + 0.85, -7.1, -6.0))
for hx in (-30, -24, -18, -12, -6, 6, 12, 17, -1.1):
    GRASS_AVOID.append((hx + 0.1 - 0.9, hx + 0.1 + 0.9, -7.1, -6.0))
TUFTS = [TUFT_D, TUFT_D, TUFT_D, TUFT_L, TUFT_DRY]
tufts = MB("GrassTufts")
x = X0 + 0.3
while x < X1 - 0.3:                       # along the sidewalk edge: the grass creeps over the concrete
    play = -33.7 < x < 47.1
    if R.random() < (0.82 if play else 0.35):
        z = -3.2 - R.uniform(0.0, 0.16)
        if free(x, z, GRASS_AVOID):
            for _ in range(1 if R.random() < 0.75 else 2):
                tuft(tufts, x + R.uniform(-0.05, 0.05), z - R.uniform(0.0, 0.05), GRASS_H, R.uniform(1.3, 2.2), TUFTS, nb=R.randint(4, 6))
    x += R.uniform(0.12, 0.42) * (1 if play else 2.6)
x = X0 + 0.3
while x < X1 - 0.3:                       # against the house fronts, where nobody mows
    play = -33.7 < x < 47.1
    if R.random() < (0.75 if play else 0.3):
        z = -7.0 + R.uniform(0.03, 0.22)
        if free(x, z, GRASS_AVOID):
            tuft(tufts, x, z, GRASS_H, R.uniform(2.0, 3.2), TUFTS, nb=R.randint(4, 6))
    x += R.uniform(0.2, 0.6) * (1 if play else 2.2)
for xw, s in ((WALLS[0], 1), (WALLS[1], -1)):   # at the end walls' feet
    for _ in range(14):
        tuft(tufts, xw + s * R.uniform(0.6, 0.78), R.uniform(-6.9, -3.3), GRASS_H, R.uniform(1.8, 2.8), TUFTS, nb=R.randint(5, 7))
for _ in range(36):                       # a few low clumps in the open
    x, z = R.uniform(-33, 46.5), R.uniform(-6.6, -3.5)
    if free(x, z, GRASS_AVOID):
        for _ in range(R.randint(1, 3)):
            tuft(tufts, x + R.uniform(-0.08, 0.08), z + R.uniform(-0.08, 0.08), GRASS_H, R.uniform(0.45, 0.75), TUFTS)
for tx in (-15.8, 4.8, 26.4):              # around the trash cans
    for _ in range(4):
        a = R.uniform(0, TAU)
        tuft(tufts, tx + math.cos(a) * R.uniform(0.33, 0.4), -3.5 + math.sin(a) * R.uniform(0.33, 0.4), GRASS_H, R.uniform(1.2, 1.7), TUFTS)
for px in (-18.9, -16.1):                  # hammock posts
    for _ in range(3):
        a = R.uniform(0, TAU)
        tuft(tufts, px + math.cos(a) * 0.17, -5.0 + math.sin(a) * 0.17, GRASS_H, R.uniform(1.2, 1.6), TUFTS)
for k, (bx, bz, ba, bb, br) in enumerate(DIRT_PATCHES):   # grass hanging on around the bare spots
    for q in range(int((ba + bb) * 7)):
        t = R.uniform(0, TAU)
        x, z = bx + math.cos(t) * ba * R.uniform(0.95, 1.15), bz + math.sin(t) * bb * R.uniform(0.95, 1.15)
        if free(x, z, GRASS_AVOID[:2] + GRASS_AVOID[5:]):
            tuft(tufts, x, z, GRASS_H, R.uniform(0.8, 1.4), TUFTS)
grass_obj = ck.join([grass.build(), tufts.build(sharp=None)], "Grass")

vt = MB("VergeTufts")
for _ in range(180):
    x = R.uniform(-50, 60)
    z = 19.05 + (R.uniform(0.0, 0.35) if R.random() < 0.4 else R.uniform(0.3, 8.0))
    tuft(vt, x, z, 0.0, R.uniform(1.2, 2.4), [TUFT_D, TUFT_L, TUFT_DRY, VERGE])
verge_obj = ck.join([verge.build(), vt.build(sharp=None)], "Verge")

# weeds along sidewalk edges: the fence line, the back of the north curb, the curb face, the wall feet
wn, ws_ = MB("WeedsN"), MB("WeedsS")
x = -44.0
while x < 56.0:
    if R.random() < 0.6:
        tuft(ws_, x, 18.87 + R.uniform(-0.08, 0.09), SW, R.uniform(0.6, 1.0), TUFTS)
    x += R.uniform(0.4, 1.6)
for _ in range(16):
    x = R.uniform(-32, 45)
    if all(abs(x - p) > 0.3 for p in (-24, -12, 4, 14, 30, 40, -8.5, 9.6, 25)):
        tuft(wn, x, -0.13 - R.uniform(0.0, 0.02), SW, R.uniform(0.5, 0.8), TUFTS, nb=3)
for _ in range(12):
    x = R.uniform(-32, 45)
    if free(x, 0.14, [(-7.8, -0.3, 0, 1), (0.8, 5.8, 0, 1), (7.0, 12.2, 0, 1)]):
        tuft(curb_n, x, 0.135, 0.005, R.uniform(0.45, 0.7), TUFTS, nb=3)
for xw, s in ((WALLS[0], 1), (WALLS[1], -1)):
    for _ in range(5):
        tuft(wn, xw + s * R.uniform(0.58, 0.66), R.uniform(-3.1, -0.3), SW, R.uniform(0.7, 1.1), TUFTS)
        tuft(ws_, xw + s * R.uniform(0.58, 0.66), R.uniform(13.4, 18.7), SW, R.uniform(0.7, 1.1), TUFTS)
lids = []
for lx, lz, lr in ((-20.6, -2.45, 0.05), (15.2, -1.25, -0.04), (-12.8, 15.4, 0.02)):   # water meter lids
    lids.append(ck.box(0.34, 0.008, 0.48, (lx, SW - 0.001, lz), IRON, rot=(0, lr, 0), bevel=0.0035, bevel_segs=1, name="meter_lid"))
    lids.append(ck.box(0.22, 0.003, 0.34, (lx, SW + 0.0035, lz), IRON_D, rot=(0, lr, 0), bevel=0.0012, bevel_segs=1, name="meter_panel"))
side_n_obj = ck.join([side_n.build(), wn.build(sharp=None)] + lids[:4], "Sidewalk_North")
side_s_obj = ck.join([side_s.build(), ws_.build(sharp=None)] + lids[4:], "Sidewalk_South")
curb_n_obj = curb_n.build()
curb_s_obj = curb_s.build()
asph_obj = ck.join([asph.build()] + grate, "Asphalt")


# ------------------------------------------------------------------ end walls: weathered precast panels with caps
def end_wall(xw, inner, name):
    parts = []
    sections = ((-10.1, -7.5, -4.9, -2.3, 0.3), (13.0, 15.35, 17.65, 20.0))
    for edges in sections:
        z0, z1 = edges[0], edges[-1]
        for a, b in zip(edges[:-1], edges[1:]):
            h = 5.0 + R.uniform(-0.02, 0.012)
            parts.append(ck.box(1.0, h, b - a - 0.016, (xw + R.uniform(-0.004, 0.004), h / 2, (a + b) / 2), R.choice(WALL_T),
                                rot=(0, R.uniform(-0.002, 0.002), 0), bevel=0.04, bevel_segs=2, name=name + "_panel"))
            parts.append(ck.box(1.16, 0.15, b - a - 0.01, (xw, 5.05, (a + b) / 2), WALL_CAP, bevel=0.035, bevel_segs=2, name=name + "_cap"))
        parts.append(ck.box(1.1, 0.34, z1 - z0 + 0.06, (xw, 0.17, (z0 + z1) / 2), GRIME, bevel=0.03, bevel_segs=2, name=name + "_footing"))
    mb = MB(name + "_weather")
    fx = xw + inner * 0.503                # 3 mm off the inner face

    def quad(a, b, c, d, m):
        mb.f([a, b, c, d] if inner > 0 else [d, c, b, a], m)
    for edges in sections:
        z0, z1 = edges[0], edges[-1]
        n = int((z1 - z0) / 0.2)
        zs_ = [z0 + 0.03 + (z1 - z0 - 0.06) * k / n for k in range(n + 1)]
        # drip band under the cap, ragged lower edge, with streaks running out of it
        low = [4.8 - 0.07 * (1 + n1(z * 1.7, 11)) - 0.04 * n1(z * 6.1, 3) for z in zs_]
        top = [mb.v(fx, 4.975, z) for z in zs_]
        bot = [mb.v(fx, y, z) for y, z in zip(low, zs_)]
        for k in range(n):
            quad(top[k], top[k + 1], bot[k + 1], bot[k], STREAK)
        for _ in range(int((z1 - z0) / 1.5)):
            k0 = R.randint(1, n - 3)
            w = R.uniform(0.16, 0.45)
            zc = zs_[k0] + 0.1
            ytop, L, end = low[k0] + 0.03, R.uniform(0.6, 2.8), R.uniform(0.4, 0.7)
            Lv, Rv = [], []
            for j in range(7):
                t = j / 6
                hw = w / 2 * (1 - (1 - end) * t ** 0.8) * (1 + 0.3 * n1(zc * 3 + t * 9, 2))
                zz = zc + 0.04 * n1(zc + t * 2.5, 5)
                Lv.append(mb.v(fx, ytop - L * t, zz - hw))
                Rv.append(mb.v(fx, ytop - L * t, zz + hw))
            for j in range(6):
                quad(Lv[j], Rv[j], Rv[j + 1], Lv[j + 1], STREAK)
        # splash grime above the footing
        top = [mb.v(fx, 0.62 + 0.22 * n1(z * 0.6, 2) + 0.06 * n1(z * 2.9, 7), z) for z in zs_]
        bot = [mb.v(fx, 0.335, z) for z in zs_]
        for k in range(n):
            quad(top[k], top[k + 1], bot[k + 1], bot[k], GRIME)
    return ck.join([mb.build()] + parts, name)


wall_w = end_wall(WALLS[0], 1, "EndWall_West")
wall_e = end_wall(WALLS[1], -1, "EndWall_East")


# ------------------------------------------------------------------ chain-link fence (JS: 100 x 2 see-through panel at z=18.9)
fz, wz = 18.9, 18.868              # posts, fabric plane (street side of the posts)
fence = MB("Fence")
for k in range(41):
    x = -44 + 2.5 * k
    r = 0.042 if k in (0, 40) else 0.03
    lathe(fence, x, fz, [(0.066, SW - 0.01, CONC), (0.058, SW + 0.03, CONC), (r, SW + 0.034, FENCE), (r, 1.955, FENCE),
                         (r + 0.008, 1.96, FENCE), (r + 0.006, 2.0, FENCE), (0, 2.013, FENCE)], 8,
          lean=(R.uniform(-0.004, 0.004), R.uniform(-0.004, 0.004)), phase=R.uniform(0, 1))
tube(fence, [Vector((-44 + 1.25 * i, 1.975 + R.uniform(-0.004, 0.004), fz + R.uniform(-0.003, 0.003))) for i in range(81)], 0.021, 6, FENCE)
H, Y0, D = 1.75, 0.2, 0.25         # fabric height, bottom, diamond pitch
for fam, zoff in ((1, -0.005), (-1, -0.012)):   # both wire families on the street side of the see-through panel
    k = 0
    while True:
        xs_ = -44 - H + k * D if fam > 0 else -44 + k * D
        k += 1
        if (fam > 0 and xs_ > 56) or (fam < 0 and xs_ - H > 56):
            break
        p0, p1 = Vector((xs_, Y0, wz + zoff)), Vector((xs_ + fam * H, Y0 + H, wz + zoff))
        for lo, hi in ((-44, 56),):     # clip the diagonal to the fence's ends
            for p, q in ((p0, p1), (p1, p0)):
                if p.x < lo:
                    t = (lo - p.x) / (q.x - p.x)
                    p[:] = p.lerp(q, t)
                if p.x > hi:
                    t = (p.x - hi) / (p.x - q.x)
                    p[:] = p.lerp(q, t)
        if (p1 - p0).length > 0.05:
            tube(fence, [p0, p1], 0.0055, 3, FENCE)
fence_obj = fence.build()
mesh = MB("FenceMesh")
poly(mesh, [(-44, 1.96, wz), (56, 1.96, wz), (56, Y0, wz), (-44, Y0, wz)], FENCE_MESH)
mesh_obj = mesh.build(sharp=None)


# ------------------------------------------------------------------ power line: two poles past the end walls, a sagging wire, the shoes
pl = MB("PowerLineWire")
PX, PZ, ARM = (-35.4, 48.6), -0.35, 7.05
WY = ARM + 0.055 + 0.13                    # wire rests on the insulator tops
xm, half = (PX[0] + PX[1]) / 2, (PX[1] - PX[0]) / 2


def wire_y(x):
    return 6.4 + (WY - 6.4) * ((x - xm) / half) ** 2


tube(pl, [Vector((PX[0] + (PX[1] - PX[0]) * i / 48, wire_y(PX[0] + (PX[1] - PX[0]) * i / 48), 0.3)) for i in range(49)], 0.03, 6, WIRE)
for px, s in ((PX[0], -1), (PX[1], 1)):
    lathe(pl, px, PZ, [(0.15, 0.0, WOOD), (0.145, 0.6, WOOD), (0.118, 7.45, WOOD), (0.1, 7.6, WOOD), (0, 7.63, WOOD)], 10,
          lean=(s * 0.004, 0.002))
    for iz in (0.3, -1.0):                 # pin insulators on the crossarm
        lathe(pl, px, iz, [(0.012, ARM + 0.04, HARDWARE), (0.012, ARM + 0.06, CERAMIC), (0.05, ARM + 0.075, CERAMIC), (0.062, ARM + 0.1, CERAMIC),
                           (0.036, ARM + 0.13, CERAMIC), (0.042, ARM + 0.155, CERAMIC), (0.024, ARM + 0.18, CERAMIC), (0, ARM + 0.185, CERAMIC)], 10)
    for bz in (PZ - 0.55, PZ + 0.55):       # crossarm braces
        tube(pl, [Vector((px, ARM - 0.62, PZ)), Vector((px, ARM - 0.04, bz))], 0.012, 4, HARDWARE)
    gx = px + s * 3.4                       # dead-end guy wire to a ground anchor, yellow guard sleeve
    tube(pl, [Vector((px + s * 0.12, 7.25, PZ)), Vector((gx, SW + 0.02, PZ - 0.2))], 0.008, 4, WIRE)
    tg = 2.0 / (Vector((px + s * 0.12, 7.25, PZ)) - Vector((gx, SW + 0.02, PZ - 0.2))).length
    tube(pl, [Vector((gx, SW + 0.02, PZ - 0.2)), Vector((gx, SW + 0.02, PZ - 0.2)).lerp(Vector((px + s * 0.12, 7.25, PZ)), tg)], 0.022, 8, GUARD)
pole_parts = [pl.build()]
for px in PX:
    pole_parts.append(ck.box(0.1, 0.11, 1.75, (px, ARM, PZ), WOOD, bevel=0.015, bevel_segs=2, name="crossarm"))


def sneaker(pos, rot):
    g = ck.empty("_shoe", pos, rot=rot)
    ps = [ck.box(0.15, 0.034, 0.30, (0, -0.043, 0), SOLE, parent=g, bevel=0.014, bevel_segs=2, name="sole"),
          ck.sph(1.0, (0, -0.008, -0.025), SHOE, scale=(0.071, 0.05, 0.125), parent=g, segs=12, rings=8, name="upper"),
          ck.sph(1.0, (0, -0.02, 0.085), SHOE, scale=(0.068, 0.036, 0.068), parent=g, segs=10, rings=6, name="toe"),
          ck.sph(1.0, (0, 0.036, -0.078), SHOE_IN, scale=(0.042, 0.012, 0.05), parent=g, segs=10, rings=4, name="collar")]
    for s in (-1, 1):
        ps.append(ck.box(0.008, 0.02, 0.12, (s * 0.068, -0.012, -0.03), RED, parent=g, bevel=0.003, bevel_segs=1, name="stripe"))
    for k in range(3):
        ps.append(ck.box(0.06, 0.008, 0.012, (0, 0.036 - k * 0.008, -0.025 + k * 0.03), SOLE, parent=g, bevel=0.003, bevel_segs=1, name="lace"))
    collar = Vector(ck.local_to(g, 0, 0.045, -0.085))
    for p in ps:
        ck.set_parent(p, None)
    bpy.data.objects.remove(g)
    return ps, collar


if SHOES_ON_WIRE:
    shoes, laces = [], MB("Laces")
    wy = wire_y(13.0)
    ca = None
    for sx, rot in ((12.85, (0.55, 0.25, 0.08)), (13.15, (0.62, -0.3, -0.1))):
        ps, col = sneaker((sx, 6.0, 0.3), rot)
        shoes += ps
        if ca is None:
            ca = col
        else:
            top_a, top_b = Vector((12.975, wy + 0.035, 0.28)), Vector((13.025, wy + 0.035, 0.32))
            mid = Vector((13.0, wy + 0.04, 0.3))
            tube(laces, [ca, ca.lerp(top_a, 0.5) + Vector((0.01, 0, 0)), top_a, mid, top_b, col.lerp(top_b, 0.5) + Vector((-0.01, 0, 0)), col], 0.006, 4, SHOE)
    sneakers = ck.join([laces.build()] + shoes, "Sneakers")
else:   # plain white insulators hung under the wire, as the README describes them
    ins = MB("Insulators")
    for sx in (12.85, 13.15):
        lathe(ins, sx, 0.3, [(0.0, 5.94, CERAMIC), (0.06, 5.95, CERAMIC), (0.075, 6.0, CERAMIC), (0.05, 6.05, CERAMIC), (0.02, 6.06, HARDWARE),
                             (0.012, wire_y(sx), HARDWARE), (0, wire_y(sx) + 0.01, HARDWARE)], 10)
    sneakers = ins.build()
power = ck.join(pole_parts, "PowerLine")


# ------------------------------------------------------------------ report, export, previews
bpy.context.view_layer.update()
for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if o.type == "MESH":
        print(f"[street] {o.name:16s} {sum(len(p.vertices) - 2 for p in o.data.polygons):6d} tris  mats={len(o.data.materials)}")


def walk_check(o, zr, want, tol):
    """Highest/lowest vertex of a walkable surface inside a z band (away from edges)."""
    ys = [v.co.z for v in o.data.vertices if zr[0] < -v.co.y < zr[1] and -30 < v.co.x < 44 and v.co.z > want - 0.02]
    print(f"[street] contract {o.name}: z {zr} top {min(ys):.4f}..{max(ys):.4f} (want {want}, tol {tol})")


walk_check(side_n_obj, (-3.0, -0.3), SW, 0.002)
walk_check(side_s_obj, (13.5, 18.6), SW, 0.002)
walk_check(curb_n_obj, (-0.115, 0.08), CURB_H, 0.002)

ck.export("street")


def shoot(pid, views):
    for m in bpy.data.materials:               # cull back faces like Godot does, so flipped faces show up
        m.use_backface_culling = not m.name.startswith("glass_")
    ck.preview(pid, views=views, ground=False)


shoot("street_a", [{"eye": (4, 1.7, 5), "look": (4, 0, -2), "lens": 35},
                   {"eye": (6, 3.6, 8.5), "look": (6, 1.0, 1.5), "lens": 28},
                   {"eye": (9.6, 2.2, 3.6), "look": (9.6, 0, 0.3), "lens": 35},
                   {"eye": (-1.2, 1.4, 2.6), "look": (0.4, 0, 0.25), "lens": 40}])
shoot("street_b", [{"eye": (3.3, 1.7, -1.5), "look": (3.3, 0, 7), "lens": 30},
                   {"eye": (6, 1.6, 14.5), "look": (6, 1.0, 19), "lens": 35},
                   {"eye": (-27, 2.5, 6), "look": (-33, 2, -2), "lens": 30},
                   {"eye": (10, 4.5, 5), "look": (13, 6.1, 0.3), "lens": 40}])
shoot("street_c", [{"eye": (-14.3, 1.6, 5.2), "look": (-14.3, 0, 2.8), "lens": 35},
                   {"eye": (-10, 4, 12), "look": (10, 0, 2), "lens": 24},
                   {"eye": (40, 3, 7), "look": (47, 3, 0), "lens": 28},
                   {"eye": (-24, 1.4, -1.5), "look": (-24, 0.1, -5), "lens": 35}])
shoot("street_d", [{"eye": (-30, 2.0, 6), "look": (-60, 0, 6), "lens": 30},
                   {"eye": (-3, 1.7, 16.5), "look": (2, 0, 11), "lens": 30},
                   {"eye": (-2.5, 3.0, 3.6), "look": (-2.5, 0, 0.4), "lens": 30},
                   {"eye": (10, 3.5, 9), "look": (10, 1, 17), "lens": 30}])
