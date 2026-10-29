"""Squirrel with Gary's sandwich (local, faces +z): clay body, tufted tail on the Tail pivot, Sandwich object."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc
from mathutils.kdtree import KDTree

ck.reset()
random.seed(31)

FUR = ck.clay("#8a5a34", 0.85)
FUR_D = ck.clay("#744828", 0.85)      # paws, feet, toes, ear tufts
TAIL_L = ck.clay("#9a663c", 0.85)     # tail strand shades
TAIL_D = ck.clay("#7c4e2e", 0.85)
CREAM = ck.clay("#e0bc8c", 0.88)      # belly, muzzle, chin
EAR_IN = ck.clay("#c48a74", 0.85)
NOSE = ck.gloss("#2a1a16", 0.35)
EYE = ck.gloss("eye_black", 0.15)
SHINE = ck.gloss("#ffffff", 0.1)
TOOTH = ck.gloss("white_clay", 0.3)
BREAD = ck.clay("#e8c890", 0.9)
CRUST = ck.clay("#b8844a", 0.88)
LETTUCE = ck.clay("#7aae46", 0.8)
TOMATO = ck.gloss("#c8402a", 0.45)
CHEESE = ck.clay("#f2c230", 0.7)


# ------------------------------------------------------------------ local helpers (game coords)
def gdef(obj, fn):
    """Deform mesh-local vertices with fn(x, y, z) -> (x, y, z) in game axes."""
    me = obj.data
    for v in me.vertices:
        x, y, z = fn(v.co.x, v.co.z, -v.co.y)
        v.co = Vector((x, -z, y))
    me.update()
    return obj


def orient(obj, fwd, up=(0, 1, 0)):
    """Rotate obj so its local +z points along fwd and +y toward up (game axes, parent frame)."""
    f = Vector(fwd).normalized()
    r = Vector(up).cross(f).normalized()
    u = f.cross(r).normalized()
    m = Matrix((ck.G(r), ck.G(-f), ck.G(u))).transposed()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = m.to_quaternion()
    return obj


def loft(pts, rads, segs=8, m=None, name="loft", side=(1, 0, 0)):
    """Closed tube through game points; rads = r or (r_side, r_other) per point. Pole caps at both ends."""
    P = [Vector(p) for p in pts]
    n = len(P)
    T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = Vector(side)
    bm = bmesh.new()
    rings, prevN = [], None
    for i in range(n):
        N = ref - T[i] * ref.dot(T[i])
        N = N.normalized() if N.length > 1e-6 else prevN
        prevN = N
        B = T[i].cross(N).normalized()
        r = rads[i]
        rx, ry = (r, r) if not hasattr(r, "__len__") else r
        rings.append([bm.verts.new(ck.G(P[i] + N * (math.cos(2 * math.pi * j / segs) * rx)
                                        + B * (math.sin(2 * math.pi * j / segs) * ry))) for j in range(segs)])
    for i in range(n - 1):
        for j in range(segs):
            k = (j + 1) % segs
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    rmin = lambda r: r if not hasattr(r, "__len__") else min(r)
    c0 = bm.verts.new(ck.G(P[0] - T[0] * rmin(rads[0]) * 0.7))
    c1 = bm.verts.new(ck.G(P[-1] + T[-1] * rmin(rads[-1]) * 0.7))
    for j in range(segs):
        k = (j + 1) % segs
        bm.faces.new((rings[0][k], rings[0][j], c0))
        bm.faces.new((rings[-1][j], rings[-1][k], c1))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, 180)
    return obj


TUFT_PROFILE = (0.6, 1.0, 0.86, 0.55, 0.24)


def tuft(root, direction, length, width, bend=(0, 0, 0), m=FUR, segs=6, flat=1.0, name="tuft", side=None, profile=TUFT_PROFILE):
    """A pulled clay tuft: teardrop from root along direction, tip flicked by bend."""
    d = Vector(direction).normalized()
    if side is None:
        side = (0, 1, 0) if abs(d.y) < 0.9 else (1, 0, 0)
    pts, rads = [], []
    for i, pr in enumerate(profile):
        s = i / (len(profile) - 1)
        pts.append(Vector(root) + d * (length * s) + Vector(bend) * (s * s))
        rads.append((width * pr, width * pr * flat))
    return loft(pts, rads, segs, m, name, side=side)


def catmull(pts, n_per=3):
    P = [Vector(p) for p in pts]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(n_per):
            t = k / n_per
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t))
    out.append(P[-1])
    return out


def lerp_list(vals, n_per=3):
    out = []
    for i in range(len(vals) - 1):
        for k in range(n_per):
            out.append(vals[i] + (vals[i + 1] - vals[i]) * k / n_per)
    out.append(vals[-1])
    return out


def sample(sp, rr, s):
    """Point, tangent and radius at arc-length fraction s along a polyline."""
    L = [0.0]
    for i in range(1, len(sp)):
        L.append(L[-1] + (sp[i] - sp[i - 1]).length)
    tgt = s * L[-1]
    for i in range(1, len(sp)):
        if L[i] >= tgt - 1e-9:
            f = (tgt - L[i - 1]) / max(L[i] - L[i - 1], 1e-9)
            return sp[i - 1].lerp(sp[i], f), (sp[i] - sp[i - 1]).normalized(), rr[i - 1] + (rr[i] - rr[i - 1]) * f
    return sp[-1], (sp[-1] - sp[-2]).normalized(), rr[-1]


def hpos(x, y, z):
    """Head-local point -> world game coords."""
    return Vector(ck.local_to(head_piv, x, y, z))


def hdir(x, y, z):
    return hpos(x, y, z) - hpos(0, 0, 0)


# ------------------------------------------------------------------ body (JS: lumpy sphere .2 scaled .8,.85,1.25 at y .2)
def body_shape(segs, rings, name):
    b = ck.sph(0.2, (0, 0.2, 0), FUR, scale=(0.8, 0.85, 1.25), rot=(-0.15, 0, 0), name=name, segs=segs, rings=rings)
    gdef(b, lambda x, y, z: (x * (1.0 - 0.1 * z / 0.25), y, z))          # fuller haunches, narrower chest
    return ck.lumpy(b, 0.006, 7, seed=1)


parts = []
body = body_shape(22, 14, "SquirrelBody")

# cream belly: a decal mesh ray-cast onto the body itself, so it hugs every facet; scalloped fur edge
def decal(target, cx, cy, rx_fn, ry, m, name, n_ang=30, rings=(0.2, 0.45, 0.75, 0.93, 1.0, 1.07),
          offs=(0.0055, 0.0054, 0.0052, 0.0048, 0.0042, 0.003, -0.0035), scallop=0.05, lobes=9):
    """Patch over target's front (its local +z), projected along local -z. Offsets ride the smooth normals."""
    bpy.context.view_layer.update()
    me = target.data
    bvh = BVHTree.FromObject(target, bpy.context.evaluated_depsgraph_get())

    def hit(x, y):
        loc, nrm, idx, _ = bvh.ray_cast(Vector((x, -0.6, y)), Vector((0, 1, 0)))
        if loc is None:
            loc, nrm, idx, _ = bvh.find_nearest(Vector((x, -0.3, y)))
        poly = me.polygons[idx]
        vs = [me.vertices[i] for i in poly.vertices]
        w = poly_3d_calc([v.co for v in vs], loc)
        n = sum((v.normal * wi for v, wi in zip(vs, w)), Vector()).normalized()
        return loc, n

    bm = bmesh.new()
    c_loc, c_n = hit(cx, cy)
    center = bm.verts.new(c_loc + c_n * offs[0])
    loops = []
    for ri, f in enumerate(rings):
        loop = []
        for j in range(n_ang):
            a = 2 * math.pi * j / n_ang
            k = f * (1 + scallop * math.sin(lobes * a) * min(1.0, f))
            loc, n = hit(cx + rx_fn(a) * k * math.cos(a), cy + ry * k * math.sin(a))
            loop.append(bm.verts.new(loc + n * offs[ri + 1]))
        loops.append(loop)
    for j in range(n_ang):
        k = (j + 1) % n_ang
        bm.faces.new((center, loops[0][j], loops[0][k]))
        for ri in range(len(loops) - 1):
            bm.faces.new((loops[ri][j], loops[ri + 1][j], loops[ri + 1][k], loops[ri][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    if bm.faces[0].normal.dot(c_n) < 0:                       # an open patch: make it face away from the target
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, 180)
    obj.matrix_world = target.matrix_world.copy()
    return obj


belly = decal(body, 0.0, -0.035, lambda a: 0.086 - 0.02 * math.sin(a), 0.125, CREAM, "Belly")
parts.append(belly)

for s in (-1, 1):
    h = ck.sph(0.1, (s * 0.112, 0.13, -0.085), FUR, scale=(0.68, 0.98, 1.15), rot=(-0.35, s * 0.12, 0), name="Haunch", segs=14, rings=9)
    ck.lumpy(h, 0.005, 9, seed=2 + s)
    foot = ck.sph(0.1, (s * 0.1, 0.022, 0.035), FUR_D, scale=(0.36, 0.25, 0.85), rot=(0, s * 0.14, 0), name="Foot", segs=14, rings=9)
    gdef(foot, lambda x, y, z: (x, max(y, -0.022), z))                  # flat sole on the ground
    ck.lumpy(foot, 0.003, 14, seed=5 + s)
    parts += [h, foot]
    for k, dx in enumerate((-0.019, 0.0, 0.019)):
        parts.append(ck.sph(0.012, (dx, -0.009, 0.077 - abs(dx) * 0.3), FUR_D, scale=(1, 0.8, 1.1), parent=foot, name="Toe", segs=6, rings=4))

# ------------------------------------------------------------------ head (JS: sphere .15 at (0,.36,.2)), tilted a touch
head_piv = ck.empty("HeadTmp", (0, 0.36, 0.2), rot=(0.04, 0, 0.07))
head = ck.sph(0.15, (0, 0, 0), FUR, scale=(1.03, 0.96, 1.0), parent=head_piv, name="Head", segs=22, rings=15)
gdef(head, lambda x, y, z: (x * (1.0 + 0.06 * max(0.0, -y / 0.15)), y, z))   # cheeks fuller low down
ck.lumpy(head, 0.004, 8, seed=4)
parts.append(head)

# muzzle: two whisker pads resting on the sandwich, a nose, buck teeth, a chin under the sandwich
for s in (-1, 1):
    parts.append(ck.sph(0.03, (s * 0.024, -0.015, 0.135), CREAM, scale=(1.0, 0.85, 0.9), parent=head_piv, name="Pad", segs=10, rings=7))
parts.append(ck.sph(0.016, (0, 0.012, 0.162), NOSE, scale=(1.3, 0.85, 0.9), parent=head_piv, name="Nose", segs=10, rings=7))
for s in (-1, 1):
    parts.append(ck.box(0.0105, 0.017, 0.006, (s * 0.0062, -0.031, 0.154), TOOTH, parent=head_piv, name="Tooth", bevel=0.002, bevel_segs=1))
chin = ck.sph(0.032, (0, -0.105, 0.115), CREAM, scale=(1.15, 0.75, 1.0), parent=head_piv, name="Chin", segs=10, rings=7)
parts.append(chin)

# eyes: big glossy domes, two highlights each (both on the same side)
for s in (-1, 1):
    n = Vector((s * 0.07, 0.04, 0.13)).normalized()
    eye = ck.sph(0.034, tuple(n * 0.141), EYE, scale=(0.9, 1.12, 0.65), parent=head_piv, name="Eye", segs=14, rings=9)
    orient(eye, n)
    up = (Vector((0, 1, 0)) - n * n.y).normalized()
    for (a, b, r, sg) in ((0.012, 0.009, 0.0085, 8), (-0.013, 0.001, 0.0042, 6)):
        hl = ck.sph(r, tuple(n * 0.161 + up * a + Vector((1, 0, 0)) * b), SHINE, scale=(1, 1, 0.6), parent=head_piv, name="Shine", segs=sg, rings=sg - 3)
        orient(hl, n)
        parts.append(hl)
    parts.append(eye)

# ears: flattened cones (JS r .04 h .09 at (+-.07,.52,.17)) with a pink inside and a little tuft
for s in (-1, 1):
    base = Vector((s * 0.07, 0.118, -0.03))
    axis = Vector((s * 0.32, 1.0, -0.06)).normalized()
    beta = s * 0.35
    sv = Vector((math.cos(beta), 0, -math.sin(beta)))
    L = 0.098
    prof = [(0.036, 0.017), (0.039, 0.017), (0.034, 0.015), (0.024, 0.012), (0.013, 0.008), (0.005, 0.004)]
    fr = [0.0, 0.2, 0.45, 0.7, 0.88, 1.0]
    pts = [hpos(*(base + axis * (L * f))) for f in fr]
    wsv = hdir(*sv)
    ear = loft(pts, prof, 10, FUR, "Ear", side=tuple(wsv))
    ck.lumpy(ear, 0.002, 18, seed=10 + s)
    parts.append(ear)
    fn = axis.cross(sv).normalized()          # face normal, should point forward
    if fn.z < 0:
        fn = -fn
    inner = ck.sph(0.03, tuple(base + axis * (L * 0.42) + fn * 0.0125), EAR_IN, scale=(0.7, 1.15, 0.2), parent=head_piv, name="EarIn", segs=8, rings=5)
    orient(inner, fn, axis)
    parts.append(inner)
    tip = base + axis * (L * 0.93)
    for k, sp in enumerate((-0.35, 0.3)):
        d = axis + sv * sp + Vector((0, 0, -0.15))
        parts.append(tuft(hpos(*tip), hdir(*d), 0.036 - k * 0.007, 0.008, m=FUR_D, name="EarTuft", segs=4))

# cowlick and cheek ruff
for (r, d, L, w) in (((0.0, 0.135, 0.03), (0.05, 1.0, -0.45), 0.052, 0.018),
                     ((0.02, 0.13, 0.005), (0.45, 1.0, -0.6), 0.04, 0.014)):
    parts.append(tuft(hpos(*r), hdir(*d), L, w, bend=hdir(0, -0.006, -0.016), flat=0.7, name="Cowlick", segs=6))
for s in (-1, 1):
    for (r, d, L, w) in (((s * 0.1, -0.035, 0.06), (s * 0.7, -0.6, -0.55), 0.046, 0.028),
                         ((s * 0.092, -0.07, 0.05), (s * 0.6, -0.95, -0.35), 0.042, 0.025)):
        parts.append(tuft(hpos(*r), hdir(*d), L, w, bend=hdir(s * 0.008, 0.002, 0), flat=0.5, name="Cheek", segs=6,
                          side=tuple(hdir(0, 0, 1)), profile=(0.66, 1.0, 0.92, 0.66, 0.38)))

# ------------------------------------------------------------------ arms and paws clutching the sandwich
for s in (-1, 1):
    arm = loft([(s * 0.066, 0.222, 0.19), (s * 0.09, 0.228, 0.258), (s * 0.1, 0.25, 0.3), (s * 0.094, 0.285, 0.33)],
               [0.034, 0.03, 0.025, 0.021], 8, FUR, "Arm")
    ck.lumpy(arm, 0.002, 16, seed=20 + s)
    paw = ck.sph(0.022, (s * 0.091, 0.3, 0.348), FUR_D, scale=(0.75, 1.05, 1.15), rot=(0, 0, s * 0.25), name="Paw", segs=8, rings=6)
    parts += [arm, paw]
    for k, z in enumerate((0.333, 0.348, 0.363)):
        parts.append(ck.sph(0.0085, (s * 0.075, 0.327, z), FUR_D, scale=(1.25, 0.85, 1.0), name="Finger", segs=6, rings=5))

# ------------------------------------------------------------------ tail: pulled clay tufts on an S-curve core, fused by a voxel remesh
def fuse(obj, voxel=0.004, target_tris=2500, smooth_iter=4):
    """Voxel-remesh overlapping pieces into one soft clay surface, then decimate to the budget."""
    md = obj.modifiers.new("vox", "REMESH")
    md.mode = "VOXEL"
    md.voxel_size = voxel
    md.adaptivity = 0.0
    md.use_smooth_shade = True
    ck._apply_modifiers(obj)
    if smooth_iter:
        md = obj.modifiers.new("soft", "SMOOTH")
        md.factor = 0.5
        md.iterations = smooth_iter
        ck._apply_modifiers(obj)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > target_tris:
        md = obj.modifiers.new("dec", "DECIMATE")
        md.decimate_type = "COLLAPSE"
        md.ratio = target_tris / tris
        ck._apply_modifiers(obj)
    ck.smooth(obj, 180)
    return obj


TAIL_PIVOT = (0, 0.19, -0.22)
ctrl = [(0, 0.15, -0.14), (0, 0.19, -0.24), (0, 0.255, -0.305), (0, 0.345, -0.325), (0, 0.435, -0.315), (0, 0.507, -0.272),
        (0, 0.545, -0.21), (0, 0.55, -0.145), (0, 0.527, -0.094), (0, 0.488, -0.075), (0, 0.45, -0.08)]
crad = [0.05, 0.075, 0.094, 0.104, 0.108, 0.103, 0.094, 0.082, 0.068, 0.054, 0.04]
sp = catmull(ctrl, 3)
sp.append(sp[-1] + (sp[-1] - sp[-2]).normalized() * 0.06)   # run the spine on past the tip for the end strands
rr = lerp_list(crad, 3) + [0.02]
S_END = 1.0 - 0.06 / sum((sp[i] - sp[i - 1]).length for i in range(1, len(sp)))


STRANDS = []   # (centerline, material slot) so the fused surface can take each strand's shade


def strand(s0, ds, th0, width, lift, twist, mi=0):
    """A pulled clay strand lying along the tail: hugs the spine at ~0.65R, lifts off at its tip."""
    pts, rads, sides = [], [], []
    n = 9
    for i in range(n):
        u = i / (n - 1)
        s_ = min(1.0, s0 + ds * u)
        p_, t_, r_ = sample(sp, rr, s_)
        N_ = (Vector((1, 0, 0)) - t_ * t_.x).normalized()
        B_ = t_.cross(N_).normalized()
        th = th0 + twist * u
        dirn = N_ * math.cos(th) + B_ * math.sin(th)
        rho = r_ * (0.62 + 0.22 * u + lift * u ** 3)
        pts.append(p_ + dirn * rho)
        prof = math.sin(0.5 * math.pi * min(1.0, u / 0.28)) * (1.0 - u) ** 0.55 + 0.13
        rads.append((width * prof, width * prof * 0.72))
        sides.append(t_.cross(dirn))
    STRANDS.append((pts, mi))
    return loft(pts, rads, 8, FUR, "TailStrand", side=tuple(sum(sides, Vector()).normalized()))


tail_parts = [loft(sp[:-1], [r * 0.78 for r in rr[:-1]], 14, FUR, "TailFur")]
rows, per = 11, 7
for k in range(rows):
    for j in range(per):
        s0 = 0.06 + 0.083 * k + random.uniform(-0.02, 0.02)
        th0 = 2 * math.pi * j / per + 0.45 * k + random.uniform(-0.2, 0.2)
        p0, t0, r0 = sample(sp, rr, min(1.0, s0 + 0.1))
        outer = (p0 - Vector((0, 0.38, -0.2))).normalized().dot((Vector((1, 0, 0)) - t0 * t0.x).normalized() * math.cos(th0)
                                                                 + t0.cross((Vector((1, 0, 0)) - t0 * t0.x).normalized()) * math.sin(th0))
        ds = min(1.0 - s0, random.uniform(0.17, 0.24) * (1.15 if outer > 0.3 else 1.0))
        mi = 1 if random.random() < (0.45 if outer > 0.2 else 0.15) else (2 if random.random() < 0.15 else 0)
        tail_parts.append(strand(s0, ds, th0, r0 * random.uniform(0.34, 0.42), 0.25 + 0.16 * max(0.0, outer),
                                 random.uniform(-0.3, 0.3), mi))
for j in range(5):                                                 # the tip: strands gathering into a soft flame
    th0 = 2 * math.pi * j / 5 + 0.3
    tail_parts.append(strand(S_END - 0.14, 0.14 + (1.0 - S_END) * 0.9, th0, 0.03, 0.15, 0.4, 1 if j % 2 else 0))
tail_core = fuse(ck.join(tail_parts, "TailFur"), smooth_iter=2, target_tris=2500)
tail_core.data.materials.clear()
for m_ in (FUR, TAIL_L, TAIL_D):
    tail_core.data.materials.append(m_)
kd = KDTree(sum(len(c) for c, _ in STRANDS))
slot = []
for c, mi in STRANDS:
    for q in c:
        kd.insert(ck.G(q), len(slot))
        slot.append(mi)
kd.balance()
for poly in tail_core.data.polygons:                               # each face takes the shade of the strand it sits on
    poly.material_index = slot[kd.find(poly.center)[1]]
ck.lumpy(tail_core, 0.0015, 30, seed=12)
tail_parts = [tail_core]

# ------------------------------------------------------------------ Gary's sandwich (JS box .16x.05x.12 at (0,.3,.36)), one bite out of it
def offset_outline(pts, d):
    """Offset a closed 2D outline inward by d (miter)."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sg = 1 if area > 0 else -1
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((-e1.y, e1.x)) * sg, Vector((-e2.y, e2.x)) * sg
        nm = n1 + n2
        nm = nm.normalized() if nm.length > 1e-6 else n1
        out.append(tuple(p1 + nm * (d / max(0.4, nm.dot(n1)))))
    return out


SA, SB, RC, BR, BC = 0.08, 0.06, 0.018, 0.036, 0.0045   # half sizes, corner radius, bite radius, tooth scallop


def bread_outline():
    pts = []
    D = math.radians

    def arc(cx, cz, a0, a1, n=3):
        for i in range(n):
            a = D(a0 + (a1 - a0) * i / (n - 1))
            pts.append((cx + RC * math.cos(a), cz + RC * math.sin(a)))
    arc(SA - RC, -(SB - RC), 270, 360)
    pts.append((SA, -0.004))
    for i in range(9):                                   # the bite: two incisor scoops at the front +x corner
        u = i / 8
        a = D(270 - 90 * u)
        r = BR + BC * abs(math.sin(2 * math.pi * u))
        pts.append((SA + r * math.cos(a), SB + r * math.sin(a)))
    pts.append((-0.012, SB))
    arc(-(SA - RC), SB - RC, 90, 180)
    pts.append((-SA, 0.002))
    arc(-(SA - RC), -(SB - RC), 180, 270)
    pts.append((0.004, -SB))
    return pts


def slab(outline, y0, y1, e, side_m, cap_m, dome_top=0.0, dome_bot=0.0, name="slab"):
    """Extruded outline with chamfered (smooth-shaded) edges; sides side_m, caps cap_m."""
    oin = offset_outline(outline, e)
    bm = bmesh.new()
    rings = [[bm.verts.new(ck.G(x, y, z)) for (x, z) in pts] for pts, y in
             ((oin, y0), (outline, y0 + e), (outline, y1 - e), (oin, y1))]
    n = len(outline)
    for i in range(3):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j])).material_index = 0
    fb = bm.faces.new(list(reversed(rings[0])))
    ft = bm.faces.new(rings[3])
    fb.material_index = ft.material_index = 1
    for f, dz in ((ft, dome_top), (fb, -dome_bot)):
        if dz:
            res = bmesh.ops.poke(bm, faces=[f])
            for v in res["verts"]:
                v.co.z += dz
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    obj.data.materials.append(side_m)
    obj.data.materials.append(cap_m)
    ck.smooth(obj, 50)
    return obj


def resample(outline, n):
    P = [Vector(p) for p in outline] + [Vector(outline[0])]
    L = [0.0]
    for i in range(1, len(P)):
        L.append(L[-1] + (P[i] - P[i - 1]).length)
    out = []
    for k in range(n):
        tgt = L[-1] * k / n
        for i in range(1, len(P)):
            if L[i] >= tgt:
                f = (tgt - L[i - 1]) / max(L[i] - L[i - 1], 1e-9)
                out.append(P[i - 1].lerp(P[i], f))
                break
    return out


def lettuce(outline, y, thick, out=0.008, ruffle=0.0035, n=34, name="Lettuce"):
    pts = resample(outline, n)
    bite_c = Vector((SA, SB))
    top, bot = [], []
    area = sum(pts[i].x * pts[(i + 1) % n].y - pts[(i + 1) % n].x * pts[i].y for i in range(n))
    sg = 1 if area > 0 else -1
    for i, p in enumerate(pts):
        e = (pts[(i + 1) % n] - pts[i - 1]).normalized()
        nout = Vector((e.y, -e.x)) * sg                   # outward normal
        dist = (p - bite_c).length
        k = min(1.0, max(0.0, (dist - BR - 0.004) / 0.012))
        k = k * k * (3 - 2 * k)
        t = i / n
        off = (out + 0.0022 * math.sin(t * 2 * math.pi * 13)) * k - 0.0015 * (1 - k)
        q = p + nout * off
        yy = y + ruffle * math.sin(t * 2 * math.pi * 9 + 0.6) * k
        top.append((q.x, yy + thick / 2, q.y))
        bot.append((q.x, yy - thick / 2, q.y))
    bm = bmesh.new()
    vt = [bm.verts.new(ck.G(*c)) for c in top]
    vb = [bm.verts.new(ck.G(*c)) for c in bot]
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new((vb[j], vb[k], vt[k], vt[j]))
    bm.faces.new(vt)
    bm.faces.new(list(reversed(vb)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, LETTUCE)
    ck.smooth(obj, 60)
    return obj


outline = bread_outline()
sw = [slab(outline, -0.025, -0.007, 0.0045, CRUST, BREAD, dome_bot=0.002, name="Sandwich"),
      lettuce(outline, -0.0058, 0.0026),
      slab(outline, 0.007, 0.025, 0.0045, CRUST, BREAD, dome_top=0.0035, name="BreadTop")]
for (x, z) in ((-0.064, 0.041), (0.068, -0.03)):                    # tomato slices peeking out
    tm = ck.cyl(0.026, 0.026, 0.0062, (x, -0.0015, z), TOMATO, name="Tomato", segs=12)
    ck.lumpy(tm, 0.0012, 60, seed=int(x * 1000))
    sw.append(tm)
cheese = ck.box(0.098, 0.0042, 0.098, (0.004, 0.0035, -0.004), CHEESE, rot=(0, 0.785 + 0.06, 0), name="Cheese", bevel=0.0015, bevel_segs=1)
sw.append(cheese)
sandwich = ck.join(sw, "Sandwich")
sandwich.location = ck.G(0, 0.3, 0.36)
sandwich.rotation_mode = "QUATERNION"
sandwich.rotation_quaternion = ck.grot(0.05, 0.04, -0.03).to_quaternion()

# ------------------------------------------------------------------ assemble: SquirrelBody, Tail > TailFur, Sandwich
body = ck.join([body] + parts, "SquirrelBody")
body.data.transform(body.matrix_basis)                 # bake the sphere's offset and tilt: node at the origin
body.matrix_basis = Matrix.Identity(4)
bpy.data.objects.remove(head_piv)
tail_piv = ck.empty("Tail", TAIL_PIVOT)
tail = ck.join(tail_parts, "TailFur")
tail.data.transform(Matrix.Translation(-ck.G(TAIL_PIVOT)))
tail.parent = tail_piv
tail.matrix_parent_inverse = Matrix.Identity(4)
tail.location = (0, 0, 0)

bpy.context.view_layer.update()
lo, hi = Vector((9, 9, 9)), Vector((-9, -9, -9))
for o in bpy.context.scene.objects:
    tri = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
    print(f"[squirrel] {o.name:14s} parent={o.parent.name if o.parent else '-':6s} tris={tri}")
    if o.type == "MESH":
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            g = Vector((w.x, w.z, -w.y))
            lo = Vector(map(min, lo, g))
            hi = Vector(map(max, hi, g))
print(f"[squirrel] bounds game x {lo.x:.3f}..{hi.x:.3f}  y {lo.y:.3f}..{hi.y:.3f}  z {lo.z:.3f}..{hi.z:.3f}")
ck.export("squirrel")
ck.preview("squirrel")
ck.preview("squirrel_close", views=[
    {"eye": (0.55, 0.62, 0.85), "look": (0, 0.33, 0.05), "lens": 45},
    {"eye": (-0.62, 0.66, -0.78), "look": (0, 0.36, -0.1), "lens": 45},
    {"eye": (0.12, 0.44, 0.78), "look": (0, 0.35, 0.25), "lens": 75},
    {"eye": (1.05, 0.42, 0.02), "look": (0, 0.33, 0.0), "lens": 38},
])
ck.preview("squirrel_detail", views=[
    {"eye": (-0.95, 0.5, -0.45), "look": (0, 0.4, -0.22), "lens": 45},
    {"eye": (0.0, 0.75, -1.0), "look": (0, 0.4, -0.25), "lens": 45},
    {"eye": (0.08, 0.2, 0.8), "look": (0, 0.17, 0.2), "lens": 70},
    {"eye": (0.35, 0.45, 0.7), "look": (0, 0.3, 0.36), "lens": 90},
])
