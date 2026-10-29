"""Street furniture (world space): lamps, hydrants, trash cans, house mailboxes, the blue mail drop, THE JOHNSONS sign, the pines."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

TAU = 2 * math.pi
CTX = "--ctx" in sys.argv          # also write _ctx_furniture.glb (stand-in ground) for Godot previews
NOSHOT = "--noshot" in sys.argv    # skip the Blender preview sheets

ck.reset()
random.seed(66)

# ------------------------------------------------------------------ materials (JS colors)
POLE = ck.metal("pole", 0.5)          # painted steel pole and cast head
IRON = ck.metal("iron", 0.45)         # bolts, nuts, chains, collars
BULB = ck.glow("#ffe6b0", 1.0)
RED = ck.clay("hydrant", 0.3)
CAN = ck.metal("trash", 0.4)          # the cans and their lids are metal
BAG = ck.gloss("#232327", 0.45)
WOOD = ck.clay("post_brown")
MBOX = ck.clay("mailbox_blue", 0.4)
DROP = ck.clay("maildrop_blue", 0.4)
DARK = ck.metal("#1a1a1e", 0.5)       # mail drop angle-iron legs
SLOT = ck.clay("#141414")
CREAM = ck.clay("cream", 0.8)
INK = ck.clay("#2a1a10", 0.8)
BARK = ck.clay("bark")
PINE = ck.clay("pine")


# ------------------------------------------------------------------ mesh helpers (game coords)
def build(name, verts, faces, m, sm=40, closed=True):
    """Mesh object from game-space verts; closed meshes get outward normals by signed volume."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(ck.G(v)) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    if closed:
        vol = 0.0
        for p in me.polygons:
            vs = [me.vertices[i].co for i in p.vertices]
            for k in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[k].cross(vs[k + 1]))
        if vol < 0:
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    ck.smooth(o, sm)
    return o


def rev(rows, n, phase=0.0):
    """Surface of revolution around local +y. rows run bottom -> top around the cross-section:
    a number is an apex on the axis, (r, y) a ring, a callable f(theta) -> (r, y) a shaped ring."""
    verts, faces, idx = [], [], []
    for row in rows:
        if isinstance(row, (int, float)):
            idx.append(len(verts))
            verts.append(Vector((0.0, row, 0.0)))
        else:
            ring = []
            for j in range(n):
                th = phase + TAU * j / n
                r, y = row(th) if callable(row) else row
                ring.append(len(verts))
                verts.append(Vector((r * math.cos(th), y, r * math.sin(th))))
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
        if R is not None:
            w = R @ w
        out.append(w + t)
    return out


def rot3(rx=0.0, ry=0.0, rz=0.0):
    """three.js Euler XYZ in game space."""
    return Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z")


def align_y(d):
    """Rotation taking local +y onto direction d."""
    return Vector((0, 1, 0)).rotation_difference(Vector(d).normalized()).to_matrix()


def tube(path, radius, segs=8, caps=True):
    """Circle swept along a game-space polyline (parallel-transport frames). radius: float or per point."""
    P = [Vector(p) for p in path]
    n = len(P)
    rad = list(radius) if isinstance(radius, (list, tuple)) else [radius] * n
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
            verts.append(P[i] + (N * math.cos(a) + B * math.sin(a)) * rad[i])
    for i in range(n - 1):
        for j in range(segs):
            k = (j + 1) % segs
            faces.append((i * segs + j, i * segs + k, (i + 1) * segs + k, (i + 1) * segs + j))
    if caps:
        faces.append(tuple(range(segs))[::-1])
        faces.append(tuple(range((n - 1) * segs, n * segs)))
    return verts, faces


def extrude(prof, a0, a1, axis="z"):
    """2D profile (u, v) extruded along an axis. axis z: (u, v) = (x, y); axis x: (u, v) = (z, y)."""
    def P(u, v, w):
        return Vector((u, v, w)) if axis == "z" else Vector((w, v, u))
    m = len(prof)
    verts = [P(u, v, a0) for u, v in prof] + [P(u, v, a1) for u, v in prof]
    faces = [(i, (i + 1) % m, m + (i + 1) % m, m + i) for i in range(m)]
    faces += [tuple(range(m))[::-1], tuple(range(m, 2 * m))]
    return verts, faces


def link(c, t, nv, L, W, r, segs=6, minor=4):
    """One oval chain link centred at c, long axis t, short axis nv."""
    t, nv = t.normalized(), nv.normalized()
    b = t.cross(nv).normalized()
    pts = [c + t * (L / 2 * math.cos(TAU * i / segs)) + nv * (W / 2 * math.sin(TAU * i / segs)) for i in range(segs)]
    verts, faces = [], []
    for i in range(segs):
        tan = (pts[(i + 1) % segs] - pts[i - 1]).normalized()
        out = tan.cross(b).normalized()
        for j in range(minor):
            a = TAU * j / minor
            verts.append(pts[i] + (out * math.cos(a) + b * math.sin(a)) * r)
    for i in range(segs):
        i2 = (i + 1) % segs
        for j in range(minor):
            k = (j + 1) % minor
            faces.append((i * minor + j, i * minor + k, i2 * minor + k, i2 * minor + j))
    return verts, faces


def sphere_rows(rings):
    rows = [-1.0]
    for k in range(1, rings):
        ph = math.pi * k / rings
        rows.append((math.sin(ph), -math.cos(ph)))
    return rows + [1.0]


def blob(name, c, axes, m, R=None, segs=14, rings=8, deform=None, sm=180):
    """Ellipsoid with semi-axes (game x, y, z), optional deform(v) in its local frame, then rotated and placed."""
    v, f = rev(sphere_rows(rings), segs)
    v = xf(v, s=axes)
    if deform:
        v = [deform(p) for p in v]
    return build(name, xf(v, R, c), f, m, sm)


def nut(pos, r, h, m, sides=6, stud=0.0, R=None, name="nut"):
    rows = [0.0, (r, 0.0), (r, h)]
    rows += [(r * 0.42, h), (r * 0.42, h + stud), h + stud] if stud else [h]
    v, f = rev(rows, sides, phase=random.uniform(0, 1))
    return build(name, xf(v, R, pos), f, m, sm=30)


def finish(parts, name, base=(0, 0, 0)):
    """Join parts into one object whose origin sits at base (game coords)."""
    o = ck.join([p for p in parts if p], name)
    o.data.transform(o.matrix_basis)
    o.matrix_basis = Matrix.Identity(4)
    off = ck.G(base)
    o.data.transform(Matrix.Translation(-off))
    o.location = off
    return o


# ------------------------------------------------------------------ street lamps (world.js line 66)
LAMP_X = [-24, -12, 4, 14, 30, 40]


def street_lamp(x, i):
    rng = random.Random(10 + i)
    z0, g = -0.2, 0.16
    P = []
    # cast base: bolted flange, a bell flaring into the pole, two bead rings
    base = [g - 0.03, (0.13, g - 0.03), (0.135, g + 0.004), (0.13, g + 0.024), (0.113, g + 0.029),
            (0.107, g + 0.045), (0.1, g + 0.072), (0.092, g + 0.115), (0.086, g + 0.18), (0.082, g + 0.27),
            (0.08, g + 0.36), (0.088, g + 0.375), (0.092, g + 0.4), (0.088, g + 0.425), (0.08, g + 0.44),
            (0.078, g + 0.6), (0.084, g + 0.612), (0.084, g + 0.632), (0.077, g + 0.645), g + 0.68]
    v, f = rev(base, 12)
    P.append(build("lamp_base", xf(v, t=(x, 0, z0)), f, POLE))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2 + rng.uniform(-0.12, 0.12)
        P.append(nut((x + 0.121 * math.cos(a), g + 0.024, z0 + 0.121 * math.sin(a)), 0.012, 0.013, IRON, stud=0.01))
    # pole and gooseneck arm, one swept piece leaning out over the curb
    yb, Ra, phi = 4.68, 0.25, math.radians(65)
    path, rad = [], []
    shaft = [g + 0.3, 1.1, 1.9, 2.7, 3.5, 4.2, yb]
    for k, y in enumerate(shaft):
        w = math.sin(math.pi * k / (len(shaft) - 1))
        path.append((x + w * rng.uniform(-0.008, 0.008), y, z0 + w * rng.uniform(-0.008, 0.008)))
        rad.append(0.074 - 0.012 * (y - g) / (yb - g))
    for k in range(1, 11):
        p = phi * k / 10
        path.append((x, yb + Ra * math.sin(p), z0 + Ra * (1 - math.cos(p))))
        rad.append(0.062 - 0.013 * k / 10)
    tdir = Vector((0, math.cos(phi), math.sin(phi)))
    tip = Vector(path[-1]) + tdir * 0.06
    path.append(tuple(tip))
    rad.append(0.048)
    v, f = tube(path, rad, 10)
    P.append(build("lamp_pole", v, f, POLE, sm=60))
    # hand-hole cover on the sidewalk side
    P.append(ck.box(0.058, 0.15, 0.014, (x, g + 0.95, z0 - 0.068), POLE, name="lamp_hatch", bevel=0.005, bevel_segs=1))
    # cobra head, tilted a little up toward the street: domed shell, an iron pan, the glowing refractor
    Rh = Matrix.Rotation(math.radians(-8), 3, "X")
    fwd = Rh @ Vector((0, 0, 1))
    c = tip + fwd * 0.27
    AZ = 0.34

    def taper(flat):
        def f(p):
            s = 0.68 + 0.32 * min(1.0, max(0.0, (p.z / AZ + 1.0) / 1.25))
            y = p.y * (flat if p.y < 0 else 1.0)
            return Vector((p.x * s, y * s, p.z))
        return f
    P.append(blob("lamp_head", c, (0.17, 0.105, AZ), POLE, Rh, segs=14, rings=9, deform=taper(0.35), sm=60))
    P.append(blob("lamp_pan", c + Rh @ Vector((0, -0.034, 0.004)), (0.152, 0.03, 0.31), IRON, Rh, segs=12, rings=5,
                  deform=taper(1.0)))
    P.append(blob("lamp_lens", c + Rh @ Vector((0, -0.058, 0.045)), (0.104, 0.034, 0.2), BULB, Rh, segs=10, rings=5))
    # collar where the arm enters, photocell on top
    v, f = rev([0.0, (0.058, 0.0), (0.064, 0.008), (0.064, 0.042), (0.058, 0.05), 0.05], 10)
    P.append(build("lamp_collar", xf(v, align_y(tdir), tip - tdir * 0.075), f, IRON))
    v, f = rev([0.0, (0.027, 0.0), (0.028, 0.026), (0.024, 0.034), (0.012, 0.041), 0.043], 8)
    P.append(build("lamp_eye", xf(v, Rh, c + Rh @ Vector((0, 0.078, -0.11))), f, IRON))
    o = finish(P, f"Lamp_{i}", (x, g, z0))
    ck.lumpy(o, 0.0015, 9, seed=i)
    return o


# ------------------------------------------------------------------ fire hydrants (line 67)
HYD_X = [-8.5, 9.6, 25]


def chain(p0, p1, sag, L=0.03, W=0.018, r=0.0045):
    """Sagging chain of links from p0 to p1 (quadratic curve)."""
    p0, p1 = Vector(p0), Vector(p1)
    mid = (p0 + p1) / 2 + Vector((0, -sag, 0))
    pts = [(1 - t) ** 2 * p0 + 2 * (1 - t) * t * mid + t * t * p1 for t in [k / 40 for k in range(41)]]
    length = sum((pts[k + 1] - pts[k]).length for k in range(40))
    n = max(2, int(length / (L * 0.72)))
    out = []
    for k in range(n):
        u = (k + 0.5) / n * length
        acc = 0.0
        for j in range(40):
            seg = (pts[j + 1] - pts[j]).length
            if acc + seg >= u:
                q = pts[j] + (pts[j + 1] - pts[j]) * ((u - acc) / seg)
                t = (pts[j + 1] - pts[j]).normalized()
                break
            acc += seg
        side = t.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        nv = side if k % 2 == 0 else t.cross(side)
        v, f = link(q, t, nv, L, W, r)
        out.append(build("chain", v, f, IRON, sm=180))
    return out


def hydrant(x, i):
    rng = random.Random(20 + i)
    z0, g = -0.32, 0.16
    spin = rng.uniform(-0.12, 0.12)
    P = []
    prof = [0.14, (0.2, 0.14), (0.207, 0.15), (0.209, 0.168), (0.2, 0.183), (0.182, 0.19), (0.177, 0.203),
            (0.171, 0.214), (0.17, 0.25), (0.165, 0.47), (0.157, 0.7), (0.153, 0.758),
            (0.16, 0.77), (0.174, 0.78), (0.178, 0.797), (0.174, 0.814), (0.16, 0.823), (0.152, 0.83)]
    for a in (14, 32, 50, 66, 77):
        r = math.radians(a)
        prof.append((0.152 * math.cos(r), 0.83 + 0.14 * math.sin(r)))
    prof += [(0.03, 0.972), 0.974]
    v, f = rev(prof, 18, phase=spin)
    body = build("hyd_body", xf(v, t=(x, 0, z0)), f, RED)
    ck.lumpy(body, 0.0025, 8, seed=30 + i)
    P.append(body)
    # pentagon operating nut on a washer: the bolt on top
    v, f = rev([0.96, (0.05, 0.96), (0.052, 0.967), (0.047, 0.976), 0.977], 16)
    P.append(build("hyd_washer", xf(v, t=(x, 0, z0)), f, RED))
    P.append(nut((x, 0.975, z0), 0.034, 0.042, IRON, sides=5, name="hyd_nut"))
    for k in range(5):
        a = spin + k * TAU / 5 + 0.3
        P.append(nut((x + 0.19 * math.cos(a), 0.181, z0 + 0.19 * math.sin(a)), 0.011, 0.012, RED))
        P.append(nut((x + 0.166 * math.cos(a + 0.5), 0.82, z0 + 0.166 * math.sin(a + 0.5)), 0.009, 0.01, RED))
    # two hose nozzles (+-x) and the big pumper nozzle facing the street (+z), capped and chained
    for d, y, rb, rc, nr in (((1, 0, 0), 0.62, 0.042, 0.054, 0.022), ((-1, 0, 0), 0.62, 0.042, 0.054, 0.022),
                              ((0, 0, 1), 0.56, 0.055, 0.067, 0.027)):
        dv = (rot3(ry=-spin) @ Vector(d)).normalized()
        R = align_y(dv)
        org = Vector((x, y, z0))
        rows = [0.1, (rb, 0.1), (rb, 0.168), (rb + 0.009, 0.172), (rb + 0.009, 0.184), (rc, 0.186),
                (rc + 0.003, 0.192), (rc + 0.003, 0.214), (rc - 0.005, 0.222), 0.222]
        v, f = rev(rows, 14)
        P.append(build("hyd_nozzle", xf(v, R, org), f, RED))
        P.append(nut(org + dv * 0.221, nr, 0.017, RED, sides=5, R=R, name="hyd_capnut"))
        lug = org + dv * 0.2 + Vector((0, -(rc + 0.002), 0))
        anchor = org + dv * 0.163 + Vector((0, -0.095, 0))
        P += chain(lug, anchor, 0.03)
    return finish(P, f"Hydrant_{i}", (x, g, z0))


# ------------------------------------------------------------------ trash cans (line 68)
CAN_X = [-15.8, 4.8, 26.4]


def trash_can(x, i, lift, bag, dents):
    rng = random.Random(30 + i)
    z0 = -3.5
    spin = rng.uniform(0, TAU)

    def rb(y):
        return 0.27 + 0.03 * (y - 0.12) / 0.9
    rows = [0.11, (0.25, 0.11), (0.263, 0.116), (0.27, 0.132)]
    ys = [0.16, 0.22]
    for yc in (0.34, 0.6, 0.86):
        ys += [yc - 0.06, yc - 0.03, yc - 0.013, yc, yc + 0.013, yc + 0.03]
    ys += [0.93]
    for y in ys:
        bump = sum(0.012 * math.exp(-((y - yc) / 0.016) ** 2) for yc in (0.34, 0.6, 0.86))
        rows.append((rb(y) + bump, y))
    rows += [(0.297, 0.965), (0.302, 0.982), (0.31, 0.992), (0.314, 1.004), (0.311, 1.016), (0.302, 1.021),
             (0.293, 1.014), (0.289, 0.995), (0.286, 0.965), 0.96]
    v, f = rev(rows, 18, phase=spin)
    # dents
    for (da, dy, dd, dr) in dents:
        th0 = spin + da
        for p in v:
            r = math.hypot(p.x, p.z)
            if r < 0.2 or p.y < 0.13 or p.y > 0.99:
                continue
            dth = (math.atan2(p.z, p.x) - th0 + math.pi) % TAU - math.pi
            w = math.exp(-((r * dth) ** 2 + (p.y - dy) ** 2) / dr ** 2)
            p.x -= p.x / r * dd * w
            p.z -= p.z / r * dd * w
    body = build("can_body", xf(v, t=(x, 0, z0)), f, CAN)
    ck.lumpy(body, 0.002, 7, seed=40 + i)
    P = [body]
    # side handles
    for s in (0, math.pi):
        a = spin + s + 0.4
        R = rot3(ry=-a)
        hp = [(0.297, 0.885, -0.072), (0.326, 0.885, -0.058), (0.336, 0.885, 0.0), (0.326, 0.885, 0.058), (0.297, 0.885, 0.072)]
        v, f = tube(xf([Vector(p) for p in hp], R, (x, 0, z0)), 0.013, 8)
        P.append(build("can_handle", v, f, CAN))
    # black bag folded over the rim all the way round, its edge hanging in waves
    thb = spin + 1.2
    wa, wb = rng.uniform(0, TAU), rng.uniform(0, TAU)

    def yb(th):
        sag = bag * max(0.0, math.cos(th - thb)) ** 4
        return 0.968 + 0.014 * math.sin(5 * th + wa) + 0.008 * math.sin(9 * th + wb) - sag

    def wr(th):   # bunched-up plastic
        return 0.004 * math.sin(11 * th + wb) + 0.003 * math.sin(17 * th + wa)
    drape = [lambda th: (0.326 + wr(th), yb(th)), lambda th: (0.329 + wr(th), yb(th) + 0.012),
             lambda th: (0.327 + wr(th) * 0.6, 1.006), (0.316, 1.03), (0.3, 1.034), (0.282, 1.02),
             (0.276, 0.972), (0.282, 0.972), (0.298, 1.027), (0.312, 1.024), (0.319, 1.006),
             lambda th: (0.32 + wr(th) * 0.5, yb(th) + 0.006)]
    v, f = rev(drape + [drape[0]], 24, phase=spin)
    o = build("can_bag", xf(v, t=(x, 0, z0)), f, BAG, sm=70)
    ck.lumpy(o, 0.003, 14, seed=60 + i)
    P.append(o)
    # the lid sits up on the bag, lifted on one side where more bag bulges out
    lid = [1.047, (0.3, 1.047), (0.331, 1.043), (0.338, 1.034), (0.342, 1.042), (0.341, 1.058), (0.332, 1.068),
           (0.3, 1.076), (0.24, 1.087), (0.2, 1.108), (0.12, 1.128), (0.05, 1.136), 1.138]
    lv, lf = rev(lid, 18, phase=spin)
    hv, hf = tube([(-0.075, 1.128, 0), (-0.068, 1.158, 0), (-0.035, 1.174, 0), (0, 1.177, 0), (0.035, 1.174, 0),
                   (0.068, 1.158, 0), (0.075, 1.128, 0)], 0.012, 8)
    hv = xf(hv, rot3(ry=-spin - 0.9))
    hinge = Vector((0.33 * math.cos(thb + math.pi), 1.043, 0.33 * math.sin(thb + math.pi)))
    axis = Vector((-math.sin(thb + math.pi), 0, math.cos(thb + math.pi)))
    Rl = Matrix.Rotation(lift, 3, axis)
    probe = Rl @ (Vector((0.33 * math.cos(thb), 1.043, 0.33 * math.sin(thb))) - hinge) + hinge
    if probe.y < 1.043:
        Rl = Matrix.Rotation(-lift, 3, axis)
    lv = [Rl @ (p - hinge) + hinge for p in lv]
    hv = [Rl @ (p - hinge) + hinge for p in hv]
    P.append(build("can_lid", xf(lv, t=(x, 0, z0)), lf, CAN))
    P.append(build("can_lidhandle", xf(hv, t=(x, 0, z0)), hf, CAN))
    if lift > 0.05:
        gap = 0.66 * lift * 0.33
        c = Vector((x + 0.27 * math.cos(thb), 1.03 + gap * 0.5, z0 + 0.27 * math.sin(thb)))
        o = blob("bag_bulge", c, (0.075, 0.018 + gap * 0.45, 0.15), BAG, rot3(ry=-thb), segs=10, rings=6)
        ck.lumpy(o, 0.006, 22, seed=70 + i)
        P.append(o)
    if bag >= 0.03:
        a = thb + rng.uniform(-0.25, 0.25)
        c = Vector((x + 0.333 * math.cos(a), 0.94, z0 + 0.333 * math.sin(a)))
        o = blob("bag_fold", c, (0.014, 0.06, 0.045), BAG, rot3(ry=-a), segs=8, rings=5)
        ck.lumpy(o, 0.004, 25, seed=80 + i)
        P.append(o)
    return finish(P, f"TrashCan_{i}", (x, 0.12, z0))


# ------------------------------------------------------------------ house mailboxes (line 101)
MBOX_X = [-27, -21.2, -14.2]


def tunnel_profile(cx, y0, w, hs, n=10):
    """Rural mailbox cross-section: flat bottom, straight sides, round top (counter-clockwise)."""
    r = w / 2
    pts = [(cx + r, y0), (cx + r, y0 + hs)]
    for k in range(1, n):
        a = math.pi * k / n
        pts.append((cx + r * math.cos(a), y0 + hs + r * math.sin(a)))
    pts += [(cx - r, y0 + hs), (cx - r, y0)]
    return pts


def house_mailbox(x, i, flag_up, door_open):
    rng = random.Random(50 + i)
    z0 = -3.0
    P = []
    post = ck.box(0.085, 0.92, 0.085, (x, 0.54, z0), WOOD, name="mb_post", bevel=0.014)
    ck.wobble(post, 0.004, 2.0, seed=i)
    P.append(post)
    P.append(ck.box(0.1, 0.03, 0.4, (x, 0.985, z0 + 0.02), WOOD, name="mb_arm", bevel=0.008))
    P.append(ck.box(0.04, 0.23, 0.03, (x, 0.885, z0 + 0.11), WOOD, rot=(0.66, 0, 0), name="mb_brace", bevel=0.008))
    # tunnel box, the door at the street end (+z)
    prof = tunnel_profile(x, 1.0, 0.3, 0.15)
    v, f = extrude(prof, z0 - 0.25, z0 + 0.235, "z")
    bx = build("mb_box", v, f, MBOX, sm=35)
    ck.bevel_obj(bx, 0.012, 2, 40)
    P.append(bx)
    # rear seam ring
    seam = tunnel_profile(x, 0.995, 0.31, 0.155)
    v, f = extrude(seam, z0 - 0.235, z0 - 0.215, "z")
    o = build("mb_seam", v, f, MBOX, sm=35)
    ck.bevel_obj(o, 0.004, 1, 40)
    P.append(o)
    # door, hinged at the bottom front edge
    dprof = tunnel_profile(0.0, -0.005, 0.312, 0.157)
    dv, df = extrude(dprof, 0.0, 0.016, "z")
    Rd = rot3(rx=door_open)
    door = build("mb_door", xf(dv, Rd, (x, 1.0, z0 + 0.235)), df, MBOX, sm=35)
    ck.bevel_obj(door, 0.005, 1, 40)
    P.append(door)
    lv, lf = extrude([(-0.025, 0.28), (0.025, 0.28), (0.02, 0.3), (-0.02, 0.3)], 0.014, 0.034, "z")
    P.append(build("mb_latch", xf(lv, Rd, (x, 1.0, z0 + 0.235)), lf, MBOX))
    if door_open > 0.05:   # dark inside, and a bent letter sticking out
        iv, if_ = extrude(tunnel_profile(x, 1.012, 0.276, 0.14), z0 + 0.2355, z0 + 0.239, "z")
        P.append(build("mb_inside", iv, if_, SLOT))
        P.append(ck.box(0.17, 0.004, 0.12, (x - 0.01, 1.12, z0 + 0.22), CREAM, rot=(-0.18, 0.12, 0.06), name="mb_letter"))
    # flag on the +x side (the mailman's side)
    piv = Vector((x + 0.158, 1.1, z0 - 0.15))
    Rf = rot3(rx=0.0 if flag_up else math.pi / 2 - 0.05)
    av, af = extrude([(-0.0, 0.0), (0.012, 0.0), (0.012, 0.21), (0.0, 0.21)], -0.009, 0.009, "x")
    pv, pf = extrude([(0.012, 0.15), (0.085, 0.15), (0.085, 0.215), (0.012, 0.215)], -0.005, 0.005, "x")
    arm = build("mb_flagarm", xf(av, Rf, piv), af, RED)
    plate = build("mb_flag", xf(pv, Rf, piv), pf, RED)
    ck.bevel_obj(plate, 0.003, 1, 40)
    P += [arm, plate]
    P.append(nut(piv + Vector((0.004, 0, 0)), 0.012, 0.01, IRON, sides=8, R=rot3(rz=-math.pi / 2), name="mb_pivot"))
    return finish(P, f"Mailbox_{i}", (x, 0.16, z0))


# ------------------------------------------------------------------ the blue mail drop (lines 103-106)
def mail_drop():
    ox, oy, oz = 5.9, 0.16, -3.0
    P = []

    def W(px, py, pz):
        return (ox + px, oy + py, oz + pz)
    # body and dome: one profile (box 0.62 x 0.85 x 0.56, half-cylinder r 0.28 on top) extruded along x
    prof = [(0.28, 0.295), (0.28, 1.145)]
    for k in range(1, 16):
        a = math.pi * k / 16
        prof.append((0.28 * math.cos(a), 1.145 + 0.28 * math.sin(a)))
    prof += [(-0.28, 1.145), (-0.28, 0.295)]
    v, f = extrude([(oz + u, oy + w) for u, w in prof], ox - 0.31, ox + 0.31, "x")
    body = build("drop_body", v, f, DROP, sm=30)
    ck.bevel_obj(body, 0.03, 3, 30)
    ck.lumpy(body, 0.002, 6, seed=3)
    P.append(body)
    # seam band where the dome meets the box
    for sz in (-1, 1):
        P.append(ck.box(0.6, 0.022, 0.012, W(0, 1.14, sz * 0.284), DROP, name="drop_band", bevel=0.004, bevel_segs=1))
    # pull-down chute: dark slot, blue flap tilted out, a handle lip along its top
    P.append(ck.box(0.4, 0.045, 0.02, W(0, 1.062, 0.279), SLOT, name="drop_slot"))
    hinge = Vector(W(0, 0.925, 0.283))
    Rc = rot3(rx=0.2)
    fv, ff = extrude([(-0.215, 0.0), (0.215, 0.0), (0.215, 0.11), (-0.215, 0.11)], 0.0, 0.022, "z")
    flap = build("drop_flap", xf(fv, Rc, hinge), ff, DROP)
    ck.bevel_obj(flap, 0.006, 2, 40)
    P.append(flap)
    hv, hf = tube([(-0.11, 0.1, 0.018), (-0.1, 0.108, 0.045), (0.1, 0.108, 0.045), (0.11, 0.1, 0.018)], 0.011, 8)
    P.append(build("drop_handle", xf(hv, Rc, hinge), hf, DROP))
    for sx in (-1, 1):
        v, f = rev([0.0, (0.012, 0.0), (0.012, 0.03), 0.03], 8)
        P.append(build("drop_hinge", xf(v, rot3(rz=math.pi / 2), Vector(W(sx * 0.2, 0.928, 0.29))), f, DARK))
    # MAIL, sculpted
    P.append(ck.text("MAIL", 0.146, 0.012, W(0, 0.75, 0.282 + 0.004), CREAM, name="drop_mail", fit_width=0.38,
                     bevel=0.003, resolution=3))
    # collection door outline and its lock
    for (w, h, px, py) in ((0.46, 0.014, 0, 0.62), (0.46, 0.014, 0, 0.345), (0.014, 0.29, -0.223, 0.4825), (0.014, 0.29, 0.223, 0.4825)):
        P.append(ck.box(w, h, 0.008, W(px, py, 0.282), DROP, name="drop_door", bevel=0.003, bevel_segs=1))
    v, f = rev([0.0, (0.019, 0.0), (0.019, 0.008), (0.014, 0.012), 0.012], 12)
    P.append(build("drop_lock", xf(v, rot3(rx=math.pi / 2), Vector(W(0, 0.585, 0.279))), f, IRON))
    P.append(ck.box(0.006, 0.016, 0.004, W(0, 0.585, 0.293), SLOT, name="drop_keyhole"))
    # four angle-iron legs with foot pads and bolts
    for sx in (-1, 1):
        for sz in (-1, 1):
            lx, lz = sx * 0.26, sz * 0.22
            P.append(ck.box(0.06, 0.32, 0.012, W(lx, 0.155, lz + sz * 0.024), DARK, name="drop_leg", bevel=0.004, bevel_segs=1))
            P.append(ck.box(0.012, 0.32, 0.06, W(lx + sx * 0.024, 0.155, lz), DARK, name="drop_leg", bevel=0.004, bevel_segs=1))
            P.append(ck.box(0.1, 0.014, 0.1, W(lx + sx * 0.01, 0.007, lz + sz * 0.01), DARK, name="drop_foot", bevel=0.004, bevel_segs=2))
            P.append(nut(W(lx + sx * 0.035, 0.014, lz + sz * 0.035), 0.01, 0.01, IRON, stud=0.008))
    return finish(P, "MailDrop", (ox, oy, oz))


# ------------------------------------------------------------------ THE JOHNSONS (lines 98-99)
def johnsons_sign():
    x, z = 9.5, -3.5
    P = []
    post = ck.box(0.064, 0.86, 0.064, (x, 0.47, z), WOOD, name="js_post", bevel=0.012)
    ck.wobble(post, 0.003, 2.0, seed=5)
    P.append(post)
    v, f = rev([0.0, (0.046, 0.0), (0.046, 0.012), 0.05], 4, phase=math.pi / 4)
    P.append(build("js_cap", xf(v, t=(x, 0.9, z)), f, WOOD, sm=20))
    zb = z + 0.032 + 0.015
    board = ck.box(0.9, 0.16, 0.03, (x, 0.8, zb), CREAM, name="js_board", bevel=0.01)
    ck.lumpy(board, 0.0015, 9, seed=6)
    P.append(board)
    for (w, h, px, py) in ((0.93, 0.024, 0, 0.892), (0.93, 0.024, 0, 0.708), (0.024, 0.208, -0.453, 0.8), (0.024, 0.208, 0.453, 0.8)):
        P.append(ck.box(w, h, 0.04, (x + px, py, zb + 0.003), WOOD, name="js_frame", bevel=0.007, bevel_segs=2))
    P.append(ck.text("THE JOHNSONS", 0.165, 0.01, (x, 0.798, zb + 0.015 + 0.003), INK, name="js_text", fit_width=0.82,
                     bevel=0.0, resolution=3))
    for sx in (-1, 1):
        P.append(nut((x + sx * 0.453, 0.8, zb + 0.023), 0.007, 0.004, IRON, sides=10, R=rot3(rx=math.pi / 2)))
    return finish(P, "JohnsonsSign", (x, 0.12, z))


# ------------------------------------------------------------------ pines south of the fence (line 124)
def pine_layout():
    rng = random.Random(124)
    out = []
    for k in range(12):
        x = -34 + k * 7 + rng.uniform(-1.5, 1.5)
        z = 21 + rng.uniform(0, 3)
        s = rng.uniform(1, 1.6)
        out.append((x, z, s))
    return out


PINES = pine_layout()


def pine(x, z, s, k):
    rng = random.Random(200 + k)
    P = []
    # trunk with a little root flare
    roots = rng.uniform(0, TAU)

    rows = [-0.25, (0.17 * s, -0.25),
            lambda th: (0.2 * s * (1 + 0.45 * max(0.0, math.cos(3 * (th - roots))) ** 3), 0.0),
            lambda th: (0.155 * s * (1 + 0.2 * max(0.0, math.cos(3 * (th - roots))) ** 3), 0.12 * s),
            (0.135 * s, 0.45 * s), (0.12 * s, 0.8 * s), (0.08 * s, 1.1 * s), 1.2 * s]
    v, f = rev(rows, 7)
    tr = build("pine_trunk", xf(v, t=(x, 0, z)), f, BARK, sm=70)
    ck.lumpy(tr, 0.012 * s, 5, seed=k)
    P.append(tr)
    # three stacked bough tiers like the JS: thick scalloped clay slabs, rounded rims drooping at the tips
    lean = (rng.uniform(-0.035, 0.035), rng.uniform(-0.035, 0.035))
    for j in range(3):
        R, H, yr = (1 - 0.25 * j) * s * rng.uniform(0.92, 1.08), 1.3 * s, (0.45 + 0.75 * j) * s
        lobes = rng.choice((6, 6, 7)) if j < 2 else 5
        ph = rng.uniform(0, TAU)
        droop = rng.uniform(0.11, 0.19) * H
        ox, oz = rng.uniform(-0.04, 0.04) * s, rng.uniform(-0.04, 0.04) * s

        def lob(th, lobes=lobes, ph=ph):
            return (0.5 + 0.5 * math.cos(lobes * (th - ph))) ** 0.8

        def ring(rf, dy, dr=1.0, R=R, yr=yr, droop=droop, lob=lob):
            return lambda th: (R * rf * (0.76 + 0.3 * lob(th)), yr + dy - droop * dr * lob(th))
        rows = [yr + 0.3 * H, (0.3 * R, yr + 0.1 * H),
                ring(0.95, -0.085 * H), ring(1.0, -0.025 * H), ring(0.9, 0.055 * H, 0.9),
                lambda th, R=R, H=H, yr=yr, lob=lob: (R * 0.5 * (0.82 + 0.2 * lob(th)), yr + 0.6 * H - 0.03 * H * lob(th)),
                yr + H]
        v, f = rev(rows, lobes * 4, phase=ph)
        v = [Vector((p.x + ox + lean[0] * p.y, p.y, p.z + oz + lean[1] * p.y)) for p in v]
        tier = build("pine_tier", xf(v, t=(x, 0, z)), f, PINE, sm=180)
        ck.lumpy(tier, 0.035 * s, 2.0, seed=k * 7 + j)
        ck.lumpy(tier, 0.012 * s, 5.5, seed=k * 11 + j + 3)
        P.append(tier)
    return P


# ------------------------------------------------------------------ build
lamps = finish([street_lamp(x, i) for i, x in enumerate(LAMP_X)], "Lamps")
hyds = finish([hydrant(x, i) for i, x in enumerate(HYD_X)], "Hydrants")
cans = finish([trash_can(CAN_X[0], 0, 0.16, 0.04, [(2.0, 0.5, 0.016, 0.07)]),
               trash_can(CAN_X[1], 1, 0.03, 0.0, [(0.6, 0.7, 0.014, 0.06), (3.6, 0.3, 0.01, 0.05)]),
               trash_can(CAN_X[2], 2, 0.1, 0.03, [(4.4, 0.45, 0.02, 0.08)])], "TrashCans")
boxes = finish([house_mailbox(MBOX_X[0], 0, False, 0.0), house_mailbox(MBOX_X[1], 1, True, 0.0),
                house_mailbox(MBOX_X[2], 2, False, 0.55)], "Mailboxes")
drop = mail_drop()
sign = johnsons_sign()
pines = finish(sum([pine(x, z, s, k) for k, (x, z, s) in enumerate(PINES)], []), "Pines")

dg = bpy.context.evaluated_depsgraph_get()
for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    if o.type == "MESH":
        print(f"[furniture] {o.name:14s} {sum(len(p.vertices) - 2 for p in o.data.polygons):6d} tris  mats={[m.name for m in o.data.materials]}")

ck.export("furniture")


# ------------------------------------------------------------------ previews (stand-in ground, not exported)
def standins():
    S = []
    S.append(ck.box(130, 0.1, 14, (6, -0.05, 7), ck.clay("asphalt", 0.95), name="_asphalt"))
    S.append(ck.box(130, 0.16, 3.2, (6, 0.08, -1.6), ck.clay("sidewalk"), name="_side"))
    S.append(ck.box(130, 0.18, 0.25, (6, 0.09, 0), ck.clay("curb"), name="_curb"))
    S.append(ck.box(130, 0.12, 4, (6, 0.06, -5), ck.clay("grass", 0.95), name="_grass"))
    S.append(ck.box(130, 0.16, 6, (6, 0.08, 16), ck.clay("sidewalk"), name="_side_s"))
    S.append(ck.box(130, 4.0, 0.3, (6, 2.0, -7.15), ck.clay("#7a6a5a"), name="_wall"))
    S.append(ck.box(5.4, 0.03, 3.4, (11.5, 0.135, -5.0), ck.clay("lawn_brown", 0.95), name="_lawn"))
    for (px, pz) in ((-26.25, -2.3), (6.9, -2.2), (2.6, -1.3)):
        S.append(ck.cyl(0.19, 0.19, 1.3, (px, 0.16 + 0.65, pz), ck.clay("#9a9a9a"), name="_dude"))
        S.append(ck.sph(0.17, (px, 0.16 + 1.47, pz), ck.clay("#9a9a9a"), name="_dude_head"))
    return S


stand = standins()
if CTX:
    ck.export("_ctx_furniture", save_blend=False)
if not NOSHOT:
    px, pz, ps = PINES[5]
    ck.preview("furniture_lamp", views=[
        {"eye": (8.6, 3.2, -1.2), "look": (4, 3.0, -0.1), "lens": 26},
        {"eye": (5.2, 4.3, -1.1), "look": (4, 5.0, 0.25), "lens": 50},
        {"eye": (4.9, 0.9, -1.25), "look": (4, 0.38, -0.2), "lens": 40},
        {"eye": (-1.8, 3.42, -1.6), "look": (3.5, 1.66, -1.6), "lens": 27}])
    ck.preview("furniture_hyd", views=[
        {"eye": (10.6, 1.0, 0.85), "look": (9.6, 0.58, -0.32), "lens": 35},
        {"eye": (8.55, 1.15, -1.45), "look": (9.6, 0.58, -0.32), "lens": 35},
        {"eye": (10.1, 1.55, 0.3), "look": (9.6, 0.72, -0.32), "lens": 40},
        {"eye": (2.7, 3.42, -1.6), "look": (8.0, 1.66, -1.6), "lens": 27}])
    ck.preview("furniture_cans", views=[
        {"eye": (5.7, 1.5, -2.0), "look": (4.8, 0.65, -3.5), "lens": 40},
        {"eye": (25.1, 1.6, -2.3), "look": (26.4, 0.7, -3.5), "lens": 40},
        {"eye": (27.0, 2.1, -2.7), "look": (26.4, 0.95, -3.5), "lens": 40},
        {"eye": (-14.6, 1.6, -2.3), "look": (-15.8, 0.75, -3.5), "lens": 40}])
    ck.preview("furniture_mail", views=[
        {"eye": (-28.3, 1.65, -1.75), "look": (-27, 1.05, -3.0), "lens": 40},
        {"eye": (-13.0, 1.5, -1.9), "look": (-14.2, 1.05, -3.0), "lens": 40},
        {"eye": (5.6, 1.75, -1.15), "look": (5.9, 0.85, -3.0), "lens": 35},
        {"eye": (4.4, 1.35, -2.0), "look": (5.9, 0.85, -3.0), "lens": 35}])
    ck.preview("furniture_sign", views=[
        {"eye": (9.62, 1.0, -2.25), "look": (9.5, 0.78, -3.5), "lens": 45},
        {"eye": (10.4, 1.25, -2.4), "look": (9.5, 0.7, -3.5), "lens": 45},
        {"eye": (11.5, 3.42, 3.12), "look": (11.5, 1.66, -2.2), "lens": 27},
        {"eye": (-21.2 + 4.0, 3.42, -1.6), "look": (-21.2 - 1.3, 1.66, -1.6), "lens": 27}])
    ck.preview("furniture_pines", views=[
        {"eye": (4, 3.26, 0.68), "look": (4, 1.5, 6), "lens": 27},
        {"eye": (6, 3.4, -2), "look": (6, 2.5, 20), "lens": 26},
        {"eye": (PINES[2][0] + 3.5, 1.8, PINES[2][1] - 6.0), "look": (PINES[2][0], 2.2, PINES[2][1]), "lens": 35},
        {"eye": (PINES[8][0] - 3.0, 3.0, PINES[8][1] - 7.0), "look": (PINES[8][0], 2.4, PINES[8][1]), "lens": 35}])
