"""Mrs. Johnson's lawn (local, origin = patch bottom centre at world (11.5, 0.12, -5.0)): Brown and Green versions plus her Hose."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, noise

TAU = 2 * math.pi
CTX = "--ctx" in sys.argv          # also write _ctx_lawn_brown/_green.glb (stand-in ground) for Godot previews
NOSHOT = "--noshot" in sys.argv

ck.reset()
random.seed(97)

W, D, TOP = 5.4, 3.4, 0.03          # world.js line 97: box(5.4, .03, 3.4), top 0.03 above the grass

# ------------------------------------------------------------------ materials
BROWN = ck.clay("lawn_brown", 0.95)     # #8a6a3a, the JS colour (dried out)
DIRT = ck.clay("#6e5232", 0.95)          # bare patches
CRACK = ck.clay("#4a3620", 0.95)         # cracks in the bare dirt
STRAW = ck.clay("#a2844c", 0.95)         # sun-bleached grass
DEAD = ck.clay("#7a5c30", 0.95)          # dead grass
OLIVE = ck.clay("#7a7e3a", 0.95)         # the last few struggling blades
GREEN = ck.clay("grass", 0.85)           # #6a8a3a, the JS colour (watered: a touch of sheen)
DEEP = ck.clay("#587a32", 0.95)          # lush tufts and clumps, shade side
FRESH = ck.clay("#7c9c46", 0.95)         # lush tufts, sun side
HOSE = ck.clay("#d89a30", 0.6)           # mustard garden hose
BRASS = ck.metal("#b08a3a", 0.35)


# ------------------------------------------------------------------ mesh helpers (game coords)
def build(name, verts, faces, m, sm=40, mode="closed"):
    """mode 'closed': outward normals by signed volume; 'up': faces turned to +y;
    'slab': height field up, skirt outward; 'none': keep the winding as built."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(ck.G(v)) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    flip = []
    if mode == "closed":
        vol = sum(f.verts[0].co.dot(f.verts[k].co.cross(f.verts[k + 1].co))
                  for f in bm.faces for k in range(1, len(f.verts) - 1))
        flip = list(bm.faces) if vol < 0 else []
    elif mode == "up":
        flip = [f for f in bm.faces if f.normal.z < 0]
    elif mode == "slab":
        for f in bm.faces:
            c = f.calc_center_median()
            if f.normal.z < -0.05 or (abs(f.normal.z) <= 0.05 and c.x * f.normal.x + c.y * f.normal.y < 0):
                flip.append(f)
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)
    bm.to_mesh(me)
    bm.free()
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    ck.smooth(o, sm)
    return o


def rev(rows, n, phase=0.0):
    """Surface of revolution around local +y (rows bottom -> top; a number is an apex)."""
    verts, faces, idx = [], [], []
    for row in rows:
        if isinstance(row, (int, float)):
            idx.append(len(verts))
            verts.append(Vector((0.0, row, 0.0)))
        else:
            ring = []
            for j in range(n):
                th = phase + TAU * j / n
                ring.append(len(verts))
                verts.append(Vector((row[0] * math.cos(th), row[1], row[0] * math.sin(th))))
            idx.append(ring)
    for a, b in zip(idx[:-1], idx[1:]):
        la, lb = isinstance(a, list), isinstance(b, list)
        for j in range(n):
            k = (j + 1) % n
            if la and lb:
                faces.append((a[j], b[j], b[k], a[k]))
            elif la:
                faces.append((a[j], b, a[k]))
            elif lb:
                faces.append((a, b[j], b[k]))
    return verts, faces


def xf(verts, R=None, t=(0, 0, 0), s=None):
    t = Vector(t)
    out = []
    for v in verts:
        w = Vector((v.x * s[0], v.y * s[1], v.z * s[2])) if s else v.copy()
        out.append((R @ w if R is not None else w) + t)
    return out


def align_y(d):
    return Vector((0, 1, 0)).rotation_difference(Vector(d).normalized()).to_matrix()


def tube(path, radius, segs=8, caps=True):
    P = [Vector(p) for p in path]
    n = len(P)
    T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = Vector((0, 1, 0)) if abs(T[0].y) < 0.9 else Vector((1, 0, 0))
    N = T[0].cross(ref).normalized()
    verts, faces = [], []
    for i in range(n):
        if i:
            N = T[i - 1].rotation_difference(T[i]) @ N
            N = (N - T[i] * N.dot(T[i])).normalized()
        B = T[i].cross(N)
        for j in range(segs):
            a = TAU * j / segs
            verts.append(P[i] + (N * math.cos(a) + B * math.sin(a)) * radius)
    for i in range(n - 1):
        for j in range(segs):
            k = (j + 1) % segs
            faces.append((i * segs + j, i * segs + k, (i + 1) * segs + k, (i + 1) * segs + j))
    if caps:
        faces.append(tuple(range(segs))[::-1])
        faces.append(tuple(range((n - 1) * segs, n * segs)))
    return verts, faces


def smooth_path(pts, steps=6):
    """Catmull-Rom through control points."""
    P = [Vector(p) for p in pts]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for s in range(steps):
            t = s / steps
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return out


# ------------------------------------------------------------------ the patch surface
def edge_dist(x, z):
    return min(W / 2 - abs(x), D / 2 - abs(z))


# houses.py puts a concrete splash block (top 0.035 above the grass) under house 12's downspout,
# straddling the back of the lawn: the turf dips around it so it sits on top instead of sinking in.
SPLASH = (-2.27, -2.01, -1.805, -1.385)


def splash_dist(x, z):
    dx = max(SPLASH[0] - x, 0.0, x - SPLASH[1])
    dz = max(SPLASH[2] - z, 0.0, z - SPLASH[3])
    return math.hypot(dx, dz)


def make_height(seed, puff):
    off = Vector((seed * 3.1, seed * 1.7, seed * 0.9))

    def h(x, z):
        p = Vector((x, z, 0.0))
        n = 0.005 * noise.noise(p * 1.2 + off) + 0.0025 * noise.noise(p * 4.0 + off * 2)
        k = max(0.0, min(1.0, edge_dist(x, z) / 0.07))
        k = math.sin(k * math.pi / 2) ** 0.8          # rounded lip
        q = max(0.0, min(1.0, (splash_dist(x, z) - 0.03) / 0.09))
        return (TOP + puff + n) * (0.22 + 0.78 * k) * (0.15 + 0.85 * q * q * (3 - 2 * q))
    return h


H_BROWN, H_GREEN = make_height(1, 0.0), make_height(2, 0.003)


def wobble_xz(x, z, seed):
    """Hand-cut outline: points near the edge pushed in and out a little."""
    w = max(0.0, 1.0 - edge_dist(x, z) / 0.25)
    p = Vector((x * 1.7 + seed, z * 1.7, 4.2))
    return x + 0.014 * w * noise.noise(p), z + 0.014 * w * noise.noise(p + Vector((9.1, 0, 0)))


def slab(name, h, m, seed):
    """The turf: a lumpy height field with a rounded lip and a skirt tucked under the grass."""
    def axis(L, step):
        n = int(round((L - 0.2) / step))
        inner = [-L / 2 + 0.1 + (L - 0.2) * k / n for k in range(n + 1)]
        return [-L / 2, -L / 2 + 0.02, -L / 2 + 0.05] + inner + [L / 2 - 0.05, L / 2 - 0.02, L / 2]
    xs, zs = axis(W, 0.15), axis(D, 0.15)
    nx, nz = len(xs), len(zs)
    verts, faces = [], []
    for z in zs:
        for x in xs:
            wx, wz = wobble_xz(x, z, seed)
            verts.append(Vector((wx, h(x, z), wz)))
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
    ring = list(range(nx)) + [j * nx + nx - 1 for j in range(1, nz)] + \
        [(nz - 1) * nx + i for i in range(nx - 2, -1, -1)] + [j * nx for j in range(nz - 2, 0, -1)]
    base = len(verts)
    for idx in ring:
        p = verts[idx]
        out = Vector((math.copysign(1, p.x) if abs(abs(p.x) - W / 2) < 0.03 else 0, 0,
                      math.copysign(1, p.z) if abs(abs(p.z) - D / 2) < 0.03 else 0))
        verts.append(Vector((p.x, -0.012, p.z)) + out * 0.01)
    for k in range(len(ring)):
        k2 = (k + 1) % len(ring)
        faces.append((ring[k], base + k, base + k2, ring[k2]))
    return build(name, verts, faces, m, sm=50, mode="slab")


def outline(cx, cz, r0, seed, n):
    pts = []
    for j in range(n):
        a = TAU * j / n
        c, s = math.cos(a), math.sin(a)
        k = 1 + 0.32 * noise.noise(Vector((c * 1.2 + seed, s * 1.2, seed * 0.37))) \
            + 0.12 * noise.noise(Vector((c * 3.5 + seed, s * 3.5, seed * 0.71)))
        pts.append((cx + r0 * k * c, cz + r0 * k * s))
    return pts


def blob_patch(name, cx, cz, r0, h, m, lift, seed, n=20):
    """Irregular flat patch lying on the lawn surface (centre, an inner ring, the ragged edge)."""
    edge = outline(cx, cz, r0, seed, n)
    verts = [Vector((cx, h(cx, cz) + lift, cz))]
    for f, l in ((0.55, lift), (1.0, lift * 0.6)):
        for (x, z) in edge:
            x, z = cx + (x - cx) * f, cz + (z - cz) * f
            verts.append(Vector((x, h(x, z) + l, z)))
    faces = [(0, 1 + j, 1 + (j + 1) % n) for j in range(n)]
    faces += [(1 + j, 1 + n + j, 1 + n + (j + 1) % n, 1 + (j + 1) % n) for j in range(n)]
    return build(name, verts, faces, m, sm=60, mode="up")


def cracks(cx, cz, r0, h, lift, rng, verts, faces):
    """A few dry cracks wandering across a bare patch (thin strips)."""
    for _ in range(rng.randint(2, 4)):
        a = rng.uniform(0, TAU)
        p = Vector((cx + r0 * 0.6 * math.cos(a), 0, cz + r0 * 0.6 * math.sin(a)))
        d = Vector((-math.cos(a), 0, -math.sin(a)))
        pts = [p.copy()]
        for _ in range(rng.randint(4, 6)):
            d = (d + Vector((rng.uniform(-0.6, 0.6), 0, rng.uniform(-0.6, 0.6)))).normalized()
            p = p + d * r0 * rng.uniform(0.16, 0.26)
            pts.append(p.copy())
        for k in range(len(pts) - 1):
            a0, a1 = pts[k], pts[k + 1]
            side = (a1 - a0).cross(Vector((0, 1, 0))).normalized()
            w0, w1 = 0.006 * (1 - k / len(pts)) + 0.002, 0.006 * (1 - (k + 1) / len(pts)) + 0.002
            i = len(verts)
            for q, w in ((a0, w0), (a1, w1)):
                for sgn in (1, -1):
                    x, z = q.x + side.x * w * sgn, q.z + side.z * w * sgn
                    verts.append(Vector((x, h(x, z) + lift, z)))
            faces.append((i, i + 1, i + 3, i + 2))


def blade(b, az, lean, hb, wb, bend, verts, faces):
    """One chunky grass blade: a three-sided wedge (its base hides under the turf).
    Faces are wound to point outward: front (L, R, T), right-back (R, K, T), back-left (K, L, T)."""
    d = Vector((math.cos(az), 0, math.sin(az)))
    s = Vector((-math.sin(az), 0, math.cos(az)))
    tip = b + (d * (math.sin(lean) + bend) + Vector((0, math.cos(lean), 0))) * hb
    i = len(verts)
    verts += [b + s * wb * 0.5, b - s * wb * 0.5, b - d * wb * 0.4, tip]
    faces += [(i, i + 1, i + 3), (i + 1, i + 2, i + 3), (i + 2, i, i + 3)]


# ------------------------------------------------------------------ the hose (shared by both versions)
SPIGOT = Vector((-1.8, 0.52, -2.0))      # house 12's front wall (world z = -7) is local z = -2, above its 0.5 m base course
COIL_C, COIL_R0, COIL_R1, TURNS, HR = Vector((-1.47, 0.0, -1.43)), 0.27, 0.135, 2.5, 0.014
NOZZLE = Vector((-0.95, 0.0, -1.2))


def ground_y(x, z):
    """What the hose lies on: the higher of the two lawns, or the grass outside them (0)."""
    if edge_dist(x, z) < 0:
        return 0.0
    return max(H_BROWN(x, z), H_GREEN(x, z))


def hose_path():
    lead = [(SPIGOT.x, SPIGOT.y - 0.05, -1.935), (SPIGOT.x + 0.01, SPIGOT.y - 0.24, -1.925),
            (SPIGOT.x + 0.02, 0.07, -1.9), (SPIGOT.x + 0.04, HR, -1.84)]
    th0 = math.atan2(-1.80 - COIL_C.z, SPIGOT.x + 0.06 - COIL_C.x)
    nsp = int(TURNS * 26)
    spiral = []
    for k in range(nsp + 1):
        u = k / nsp
        th = th0 - TURNS * TAU * u
        r = COIL_R0 - (COIL_R0 - COIL_R1) * u
        x, z = COIL_C.x + r * math.cos(th), COIL_C.z + r * math.sin(th)
        spiral.append(Vector((x, ground_y(x, z) + HR + 0.002 * math.sin(k * 0.9), z)))
    pts = [Vector(p) for p in lead[:3]]
    pts += smooth_path([lead[2], lead[3], spiral[0], spiral[3]], 5)[1:-2]
    pts += spiral
    # the free end climbs radially over the loops, then wanders out to the nozzle
    end = spiral[-1]
    d = Vector((end.x - COIL_C.x, 0, end.z - COIL_C.z)).normalized()
    over = [end + d * 0.035 + Vector((0, 0.04, 0)), end + d * 0.085 + Vector((0, 0.05, 0)),
            end + d * 0.135 + Vector((0, 0.045, 0)), end + d * 0.21]
    far = Vector((NOZZLE.x, 0, NOZZLE.z))
    mid = (over[-1] + far) / 2 + Vector((0.04, 0, 0.05))
    for q in (over[-1], mid, far):
        q.y = ground_y(q.x, q.z) + HR
    pts += smooth_path([end] + over + [mid, far], 5)[1:]
    return pts


HOSE_PTS = hose_path()


def make_hose():
    P = []
    v, f = tube(HOSE_PTS, HR, 10)
    P.append(build("hose_tube", v, f, HOSE, sm=60))
    tdir = (HOSE_PTS[-1] - HOSE_PTS[-2]).normalized()
    v, f = rev([0.0, (0.019, 0.0), (0.02, 0.006), (0.02, 0.026), (0.016, 0.03), (0.015, 0.075), (0.013, 0.08),
                (0.014, 0.085), (0.014, 0.096), (0.008, 0.1), 0.1], 12)
    P.append(build("hose_nozzle", xf(v, align_y(tdir), HOSE_PTS[-1] - tdir * 0.012), f, BRASS))
    # spigot: pipe out of the wall, a handle wheel on top, the coupling the hose screws onto
    v, f = rev([0.0, (0.017, 0.0), (0.017, 0.1), (0.02, 0.1), (0.02, 0.125), 0.125], 10)
    P.append(build("spigot_pipe", xf(v, align_y((0, 0, 1)), SPIGOT + Vector((0, 0, -0.06))), f, BRASS))
    v, f = rev([0.0, (0.022, 0.0), (0.022, 0.045), (0.019, 0.05), 0.05], 10)
    P.append(build("spigot_body", xf(v, align_y((0, -1, 0)), SPIGOT + Vector((0, 0.012, 0.065))), f, BRASS))
    v, f = rev([0.0, (0.007, 0.0), (0.007, 0.03), (0.034, 0.03), (0.036, 0.036), (0.034, 0.042), (0.008, 0.042), 0.046], 12)
    P.append(build("spigot_wheel", xf(v, t=SPIGOT + Vector((0, 0.03, 0.065))), f, BRASS))
    v, f = rev([0.0, (0.021, 0.0), (0.021, 0.03), (0.016, 0.034), 0.034], 10)
    P.append(build("hose_coupling", xf(v, align_y((0, -1, 0.06)), Vector((SPIGOT.x, SPIGOT.y - 0.03, -1.935))), f, BRASS))
    o = ck.join(P, "Hose")
    ck.lumpy(o, 0.0012, 30, seed=5)
    return o


# ------------------------------------------------------------------ scattering
AVOID_C = [(-2.0, 1.5, 0.09)]           # THE JOHNSONS post (world 9.5, -3.5)


def blocked(x, z, pad=0.0):
    if edge_dist(x, z) < 0.035 + pad:
        return True
    if -0.25 < x < 1.45 and z < -1.05:   # house 12's front stoop
        return True
    if splash_dist(x, z) < 0.05 + pad:   # the downspout's splash block
        return True
    for (cx, cz, r) in AVOID_C:
        if (x - cx) ** 2 + (z - cz) ** 2 < (r + pad) ** 2:
            return True
    if (x - COIL_C.x) ** 2 + (z - COIL_C.z) ** 2 < (COIL_R0 + 0.05 + pad) ** 2:
        return True
    for p in HOSE_PTS[::2]:
        if (x - p.x) ** 2 + (z - p.z) ** 2 < (0.045 + pad) ** 2:
            return True
    return False


def tufts(name, h, specs, rng, count, density, patches=(), patch_avoid=1.0):
    """specs: (material, weight, (hmin, hmax), (lean_min, lean_max), (blades_min, blades_max), spread)."""
    groups = [([], []) for _ in specs]
    tot = sum(s[1] for s in specs)
    placed = tries = 0
    while placed < count and tries < count * 30:
        tries += 1
        x, z = rng.uniform(-W / 2, W / 2), rng.uniform(-D / 2, D / 2)
        if blocked(x, z) or rng.random() > density(x, z):
            continue
        if any((x - px) ** 2 + (z - pz) ** 2 < (pr * patch_avoid) ** 2 for (px, pz, pr) in patches):
            continue
        pick = rng.uniform(0, tot)
        gi = 0
        for gi, s in enumerate(specs):
            pick -= s[1]
            if pick <= 0:
                break
        m, _, (h0, h1), (l0, l1), (n0, n1), spread = specs[gi]
        verts, faces = groups[gi]
        a0 = rng.uniform(0, TAU)
        nb = rng.randint(n0, n1)
        for k in range(nb):
            az = a0 + TAU * k / nb + rng.uniform(-0.35, 0.35)
            rr = rng.uniform(0.15, 1.0) * spread
            bx, bz = x + rr * math.cos(az), z + rr * math.sin(az)
            blade(Vector((bx, h(bx, bz) - 0.004, bz)), az, rng.uniform(l0, l1), rng.uniform(h0, h1),
                  rng.uniform(0.011, 0.017), rng.uniform(0.0, 0.3), verts, faces)
        placed += 1
    return [build(f"{name}_{gi}", v, f, specs[gi][0], sm=180, mode="none") for gi, (v, f) in enumerate(groups) if v]


def brown_version():
    rng = random.Random(11)
    h = H_BROWN
    P = [slab("brown_slab", h, BROWN, 1)]
    # bare dirt where it died right off (some cracked), sun-bleached grass round the edges of it
    patches, cv, cf = [], [], []
    for k in range(11):
        for _ in range(60):
            x, z, r = rng.uniform(-2.4, 2.4), rng.uniform(-1.4, 1.4), rng.uniform(0.12, 0.38)
            if not blocked(x, z, r * 0.5) and edge_dist(x, z) > r * 0.9:
                break
        patches.append((x, z, r))
        lift = 0.0048 + 0.0004 * k
        P.append(blob_patch("brown_dirt", x, z, r, h, DIRT, lift, k))
        if r > 0.2:
            cracks(x, z, r, h, lift + 0.0009, rng, cv, cf)
        if k < 7:   # a bleached halo next to most bare spots
            a = rng.uniform(0, TAU)
            P.append(blob_patch("brown_straw", x + r * 0.5 * math.cos(a), z + r * 0.5 * math.sin(a), r * 1.35, h,
                                STRAW, 0.0024 + 0.0001 * k, 40 + k))
    P.append(build("brown_cracks", cv, cf, CRACK, sm=60, mode="up"))
    # the one spot that still gets water: under the downspout
    sv, sf = [], []
    for k in range(9):
        a = rng.uniform(0, TAU)
        x = (SPLASH[0] + SPLASH[1]) / 2 + math.cos(a) * rng.uniform(0.2, 0.3)
        z = (SPLASH[2] + SPLASH[3]) / 2 + math.sin(a) * rng.uniform(0.25, 0.36)
        if edge_dist(x, z) < 0.04 or splash_dist(x, z) < 0.06:
            continue
        for b in range(5):
            az = TAU * b / 5 + rng.uniform(-0.3, 0.3)
            blade(Vector((x, h(x, z) - 0.004, z)), az, rng.uniform(0.2, 0.5), rng.uniform(0.024, 0.036),
                  rng.uniform(0.011, 0.016), 0.1, sv, sf)
    if sv:
        P.append(build("brown_splash", sv, sf, OLIVE, sm=180, mode="none"))
    dens = lambda x, z: 0.3 + 0.7 * min(1.0, max(0.0, noise.noise(Vector((x * 0.9, z * 0.9, 7.7))) + 0.45))
    # dead grass lies matted and splayed; a few olive survivors still stand up
    P += tufts("brown_tuft", h, [(STRAW, 5, (0.03, 0.05), (0.95, 1.3), (6, 8), 0.04),
                                 (DEAD, 4, (0.028, 0.045), (1.0, 1.35), (6, 8), 0.04),
                                 (OLIVE, 1, (0.02, 0.034), (0.3, 0.7), (4, 6), 0.022)],
               rng, 300, dens, patches, 0.8)
    return ck.join(P, "Brown")


def stripe(name, h, z0, z1, m, lift, seed):
    """A mowing stripe lying on the turf, ragged a little at its ends."""
    nx, nz = 40, 4
    verts, faces = [], []
    for i in range(nx + 1):
        x = -W / 2 + 0.05 + (W - 0.1) * i / nx
        ra = 0.012 * noise.noise(Vector((x * 2.0, z0 * 3.0, seed)))
        rb = 0.012 * noise.noise(Vector((x * 2.0, z1 * 3.0, seed)))
        for j in range(nz + 1):
            zz = z0 + ra + (z1 + rb - z0 - ra) * j / nz
            verts.append(Vector((x, h(x, zz) + lift, zz)))
    for i in range(nx):
        for j in range(nz):
            a = i * (nz + 1) + j
            faces.append((a, a + nz + 1, a + nz + 2, a + 1))
    return build(name, verts, faces, m, sm=60, mode="up")


def green_version():
    rng = random.Random(23)
    h = H_GREEN
    P = [slab("green_slab", h, GREEN, 2)]
    # freshly mown stripes along the street, the way a proud lawn looks
    n = 7
    for k in range(1, n, 2):
        z0 = -D / 2 + 0.05 + (D - 0.1) * k / n
        z1 = -D / 2 + 0.05 + (D - 0.1) * (k + 1) / n
        P.append(stripe("green_stripe", h, z0, z1, DEEP, 0.003, k))
    dens = lambda x, z: 0.55 + 0.45 * min(1.0, max(0.0, noise.noise(Vector((x * 1.1, z * 1.1, 3.3))) + 0.5))
    P += tufts("green_tuft", h, [(DEEP, 3, (0.024, 0.04), (0.12, 0.45), (5, 7), 0.03),
                                 (GREEN, 3, (0.022, 0.038), (0.15, 0.5), (5, 7), 0.03),
                                 (FRESH, 3, (0.026, 0.04), (0.1, 0.4), (4, 6), 0.026)],
               rng, 400, dens)
    return ck.join(P, "Green")


brown = brown_version()
green = green_version()
hose = make_hose()

for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if o.type == "MESH":
        print(f"[lawn] {o.name:8s} {sum(len(p.vertices) - 2 for p in o.data.polygons):6d} tris  mats={[m.name for m in o.data.materials]}")

ck.export("lawn")


# ------------------------------------------------------------------ previews (stand-ins, not exported)
def standins():
    return [ck.box(16, 0.12, 4.0, (0, -0.06, 0.0), ck.clay("grass", 0.95), name="_grass"),
            ck.box(16, 0.16, 3.2, (0, -0.04, 3.4), ck.clay("sidewalk"), name="_side"),
            ck.box(16, 3.0, 0.3, (0, 1.38, -2.15), ck.clay("#7a6a5a"), name="_wall"),
            ck.box(1.6, 0.4, 0.9, (0.6, 0.08, -1.55), ck.clay("curb"), name="_stoop"),
            ck.cyl(0.03, 0.03, 0.7, (-2.0, 0.28, 1.5), ck.clay("post_brown"), name="_signpost"),
            ck.box(0.9, 0.16, 0.02, (-2.0, 0.68, 1.53), ck.clay("cream"), name="_signboard"),
            ck.cyl(0.19, 0.19, 1.3, (0.6, 0.62, 0.9), ck.clay("#9a9a9a"), name="_dude"),
            ck.sph(0.17, (0.6, 1.44, 0.9), ck.clay("#9a9a9a"), name="_dude_head")]


stand = standins()
VIEWS = [{"eye": (0.0, 3.3, 7.9), "look": (0.0, 1.54, 2.6), "lens": 27},
         {"eye": (2.3, 1.25, 2.7), "look": (0.4, 0.0, 0.2), "lens": 35},
         {"eye": (-0.65, 0.95, -0.45), "look": (-1.5, 0.05, -1.45), "lens": 35},
         {"eye": (-0.9, 0.35, 1.9), "look": (-0.3, 0.03, 0.7), "lens": 40}]
if CTX:
    for keep, drop in ((brown, green), (green, brown)):
        col = drop.users_collection[0]
        col.objects.unlink(drop)
        ck.export(f"_ctx_lawn_{keep.name.lower()}", save_blend=False)
        col.objects.link(drop)
if not NOSHOT:
    green.hide_render = True
    ck.preview("lawn_brown", views=VIEWS)
    green.hide_render, brown.hide_render = False, True
    ck.preview("lawn_green", views=VIEWS)
    brown.hide_render = False
