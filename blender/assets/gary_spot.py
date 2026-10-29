"""Gary's spot in the gutter: welcome mat, shopping cart, WELCOME HOME sign, GARY mailbox, kettle grill, quilt, pillow and clutter."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector, Matrix, Quaternion, noise

ck.reset()
random.seed(2009)
R = random.Random(2009)
HAND = r"C:\Windows\Fonts\segoeprb.ttf"   # hand-painted lettering (Segoe Print Bold)

ALU = ck.metal("#c8ccd4", 0.35)
WOOD = ck.clay("#7a4a24", 0.85)
RED = ck.clay("#c4162a", 0.5)
ENAMEL = ck.gloss("#141414", 0.4)
RUBBER = ck.clay("#141414", 0.9)
DARK = ck.clay("#2a2624", 0.8)
SIGN_WHITE = ck.clay("#f4f0e6", 0.85)
PAINT = ck.clay("#c4162a", 0.6)          # the red house paint of the sign (and the bucket it came from)


# ------------------------------------------------------------------ helpers
def sgnpow(a, e):
    return math.copysign(abs(a) ** e, a)


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def nz(x, y=0.0, z=0.0):
    return noise.noise(Vector((x, y, z)))


class MB:
    """Collects geometry (Blender coords) with per-face materials, then builds one mesh object."""
    def __init__(self):
        self.v, self.f, self.fm, self.mats = [], [], [], []

    def mi(self, m):
        m = ck._material(m)
        if m in self.mats:
            return self.mats.index(m)
        self.mats.append(m)
        return len(self.mats) - 1

    def verts(self, vs):
        o = len(self.v)
        self.v.extend(Vector(p) for p in vs)
        return o

    def faces(self, fs, m, o=0):
        k = self.mi(m)
        for f in fs:
            self.f.append(tuple(o + i for i in f))
            self.fm.append(k)

    def add(self, vs, fs, m):
        self.faces(fs, m, self.verts(vs))

    def build(self, name, parent=None, smooth=180, recalc=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in self.v], [], self.f)
        for m in self.mats:
            me.materials.append(m)
        for p, k in zip(me.polygons, self.fm):
            p.material_index = k
        if recalc:
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        ck.smooth(ob, smooth)
        ck._place(ob, (0, 0, 0), None, parent)
        return ob


def tube(mb, pts, r, m, segs=6, closed=False, cap=True):
    """Round tube through game-space points (parallel-transport frames). r: radius or list per point."""
    P = [ck.G(p) for p in pts]
    n = len(P)
    rs = list(r) if isinstance(r, (list, tuple)) else [r] * n
    T = []
    for i in range(n):
        t = (P[(i + 1) % n] - P[i - 1]) if closed else (P[min(i + 1, n - 1)] - P[max(i - 1, 0)])
        T.append(t.normalized())
    a = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = [(a - T[0] * a.dot(T[0])).normalized()]
    for i in range(1, n):
        v = N[-1] - T[i] * N[-1].dot(T[i])
        N.append(v.normalized() if v.length > 1e-8 else N[-1])
    if closed:
        ne = (N[-1] - T[0] * N[-1].dot(T[0])).normalized()
        ang = math.atan2(T[0].dot(ne.cross(N[0])), ne.dot(N[0]))
        N = [Quaternion(T[i], ang * i / n) @ N[i] for i in range(n)]
    vs, fs = [], []
    for i in range(n):
        B = T[i].cross(N[i])
        for k in range(segs):
            th = 2 * math.pi * k / segs
            vs.append(P[i] + rs[i] * (math.cos(th) * N[i] + math.sin(th) * B))
    for i in range(n if closed else n - 1):
        i2 = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            fs.append((i * segs + k, i * segs + k2, i2 * segs + k2, i2 * segs + k))
    if cap and not closed:
        fs.append(tuple(range(segs))[::-1])
        fs.append(tuple((n - 1) * segs + k for k in range(segs)))
    mb.add(vs, fs, m)


def rounded(pts, rad, n=3, closed=False):
    """Replace a polyline's corners with small arcs (game coords)."""
    P = [Vector(p) for p in pts]
    out, m = [], len(P)
    for i in range(m):
        if not closed and i in (0, m - 1):
            out.append(P[i])
            continue
        a, b, c = P[i - 1], P[i], P[(i + 1) % m]
        da, db = a - b, c - b
        p0 = b + da.normalized() * min(rad, da.length * 0.45)
        p2 = b + db.normalized() * min(rad, db.length * 0.45)
        for k in range(n + 1):
            t = k / n
            out.append((1 - t) ** 2 * p0 + 2 * (1 - t) * t * b + t * t * p2)
    return [tuple(p) for p in out]


def uvs(segs, rings):
    """Unit UV sphere in GAME axes (poles on y): verts, faces (outward)."""
    vs = [(0.0, 1.0, 0.0)]
    for i in range(1, rings):
        th = math.pi * i / rings
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            vs.append((math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)))
    vs.append((0.0, -1.0, 0.0))
    fs = [(0, 1 + (j + 1) % segs, 1 + j) for j in range(segs)]
    for i in range(rings - 2):
        for j in range(segs):
            a, b = 1 + i * segs + j, 1 + i * segs + (j + 1) % segs
            fs.append((a, b, b + segs, a + segs))
    s, base = len(vs) - 1, 1 + (rings - 2) * segs
    fs += [(s, base + j, base + (j + 1) % segs) for j in range(segs)]
    return vs, fs


def blob(name, c, rad, m, segs=16, rings=10, ex=1.0, ey=1.0, fn=None, parent=None, lump=None):
    """Squashed (super)ellipsoid; fn(p, unit_dir) can reshape each vertex (game coords)."""
    V0, F = uvs(segs, rings)
    vs = []
    for u in V0:
        p = [c[0] + rad[0] * sgnpow(u[0], ex), c[1] + rad[1] * sgnpow(u[1], ey), c[2] + rad[2] * sgnpow(u[2], ex)]
        if fn:
            p = fn(p, u)
        vs.append(ck.G(p))
    mb = MB()
    mb.add(vs, F, m)
    ob = mb.build(name, parent)
    if lump:
        ck.lumpy(ob, *lump)
    return ob


def crumple(obj, amount=0.01, freq=8.0, seed=0):
    """Ridged noise along the normals: sharp fold lines like crumpled plastic."""
    off = Vector((seed * 3.3, seed * 1.7, seed * 5.1))
    for v in obj.data.vertices:
        v.co += v.normal * amount * ((1 - abs(noise.noise(v.co * freq + off))) ** 3 - 0.3)
    obj.data.update()
    return obj


def grid_slab(mb, X, Z, YB, YT, top_mat, bot_mat, wall_mat, bulge=0.004):
    """Closed slab from (n+1)x(m+1) game-space grids (rows i along X, columns j along Z).
    top_mat(i, j) / wall_mat(side, k) may be materials or callables. Build with recalc=True."""
    n, m = len(X) - 1, len(X[0]) - 1
    vs = [ck.G((X[i][j], YT[i][j], Z[i][j])) for i in range(n + 1) for j in range(m + 1)]
    vs += [ck.G((X[i][j], YB[i][j], Z[i][j])) for i in range(n + 1) for j in range(m + 1)]
    nT = (n + 1) * (m + 1)
    T = lambda i, j: i * (m + 1) + j
    B = lambda i, j: nT + i * (m + 1) + j
    loop = [(i, 0) for i in range(n)] + [(n, j) for j in range(m)] + [(i, m) for i in range(n, 0, -1)] + [(0, j) for j in range(m, 0, -1)]
    side = ["z0"] * n + ["x1"] * m + ["z1"] * n + ["x0"] * m
    for (i, j) in loop:
        ii, jj = min(max(i, 1), n - 1), min(max(j, 1), m - 1)
        dx, dz = X[i][j] - X[ii][jj], Z[i][j] - Z[ii][jj]
        L = math.hypot(dx, dz) or 1.0
        vs.append(ck.G((X[i][j] + dx / L * bulge, 0.5 * (YT[i][j] + YB[i][j]), Z[i][j] + dz / L * bulge)))
    o = mb.verts(vs)
    Mi = lambda k: 2 * nT + k
    groups = {}

    def put(mt, f):
        mt = ck._material(mt)
        groups.setdefault(mt.name, [mt, []])[1].append(f)
    for i in range(n):
        for j in range(m):
            put(top_mat(i, j) if callable(top_mat) else top_mat, (T(i, j), T(i, j + 1), T(i + 1, j + 1), T(i + 1, j)))
            put(bot_mat, (B(i, j), B(i + 1, j), B(i + 1, j + 1), B(i, j + 1)))
    Lp = len(loop)
    for k in range(Lp):
        a, b = loop[k], loop[(k + 1) % Lp]
        wm = wall_mat(side[k], k) if callable(wall_mat) else wall_mat
        put(wm, (T(*a), T(*b), Mi((k + 1) % Lp), Mi(k)))
        put(wm, (Mi(k), Mi((k + 1) % Lp), B(*b), B(*a)))
    for mt, fs in groups.values():
        mb.faces(fs, mt, o)


def ctext(s, size, depth, m, name="text", font="impact", fit_width=None, bevel=0.0, res=2, back=False):
    """ck.text with a low curve resolution (claykit's default makes ~5k triangles per word). Faces game +z.
    back=False drops the back faces, which are buried in whatever the letters sit on."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size, cu.extrude, cu.bevel_depth = size, depth / 2, bevel
    cu.bevel_resolution, cu.resolution_u = 0, res
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    obj = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    if fit_width and obj.dimensions.x > fit_width:
        cu.size = size * fit_width / obj.dimensions.x
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    if not back:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.y > 0.9], context="FACES")
        bm.to_mesh(me)
        bm.free()
    ck.assign(ob, m)
    ck.smooth(ob, 40)
    return ob


def hand_text(s, size, depth, pos, m, rot=None, parent=None, name="text", font=HAND, jit=0.07, seed=1,
              fit_width=None, bevel=0.0, drips=(), res=2):
    """Hand-painted lettering: each letter gets a little wobble, tilt and size change, plus paint drips
    running down from the bottoms of the letters listed in drips (indices)."""
    ob = ctext(s, size, depth, m, name, font, fit_width, bevel, res)
    rnd = random.Random(seed)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen, comps = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            w = stack.pop()
            comp.append(w)
            for e in w.link_edges:
                o = e.other_vert(w)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        comps.append(comp)
    # merge pieces of the same letter (overlapping x ranges)
    boxes = [[min(w.co.x for w in c), max(w.co.x for w in c), c] for c in comps]
    boxes.sort(key=lambda b: b[0])
    letters = []
    for b in boxes:
        if letters and b[0] < letters[-1][1] - 0.3 * (b[1] - b[0]):
            letters[-1][1] = max(letters[-1][1], b[1])
            letters[-1][2] = letters[-1][2] + b[2]
        else:
            letters.append(b)
    drip_pts = []
    for li, (x0, x1, verts) in enumerate(letters):
        c = sum((w.co for w in verts), Vector()) / len(verts)
        rot_m = Matrix.Rotation(rnd.uniform(-jit, jit), 3, "Y")
        sc = 1 + rnd.uniform(-0.06, 0.06)
        off = Vector((rnd.uniform(-0.02, 0.02) * size, 0, rnd.uniform(-0.05, 0.05) * size))
        for w in verts:
            w.co = c + rot_m @ ((w.co - c) * sc) + off
        zmin = min(w.co.z for w in verts)
        low = sorted(w.co.x for w in verts if w.co.z < zmin + 0.004)
        drip_pts.append((low[len(low) // 2] + rnd.uniform(-0.3, 0.3) * (low[-1] - low[0]), zmin))
    bm.to_mesh(me)
    bm.free()
    if drips:
        mb = MB()
        for (x, zb) in [drip_pts[i] for i in drips if i < len(drip_pts)]:
            L = rnd.uniform(0.012, 0.04)
            # local text frame: blender (x, y, z) == game (x, z, -y)
            tube(mb, [(x, zb + 0.004, 0), (x, zb - L * 0.6, 0), (x, zb - L, 0)], [0.0035, 0.003, 0.0045], m, segs=6)
            V0, F = uvs(8, 5)
            mb.add([ck.G((x + 0.0055 * u[0], zb - L - 0.002 + 0.0065 * u[1], 0.0045 * u[2])) for u in V0], F, m)
        d = mb.build(name + "_drips")
        ob = ck.join([ob, d], name)
    return ck._place(ob, pos, rot, parent)


def can(mb, base, h, r, col, tilt=(0, 0, 0), crush=0.0):
    """Soda can: body + silver top and bottom (game coords, base = bottom center)."""
    rm = ck.grot(*tilt)
    def P(x, y, z):
        q = rm @ Vector(ck.G((x, y, z)))
        b = ck.G(base)
        return (b + q)
    segs = 12
    def ring(y, rr):
        return [P(rr * math.cos(2 * math.pi * k / segs) * (1 - crush * (0.5 + 0.5 * math.cos(4 * math.pi * k / segs))), y,
                  rr * math.sin(2 * math.pi * k / segs)) for k in range(segs)]
    body = ring(0.008, r) + ring(h * 0.5, r * (1 - crush * 0.6)) + ring(h - 0.012, r)
    fs = []
    for i in range(2):
        for k in range(segs):
            k2 = (k + 1) % segs
            fs.append((i * segs + k2, i * segs + k, (i + 1) * segs + k, (i + 1) * segs + k2))
    o = mb.verts(body)
    mb.faces(fs, col, o)
    top = ring(h - 0.012, r) + ring(h, r * 0.86) + [P(0, h - 0.002, 0)]
    fs = []
    for k in range(segs):
        k2 = (k + 1) % segs
        fs.append((k2, k, segs + k, segs + k2))
        fs.append((segs + k2, segs + k, 2 * segs))
    o = mb.verts(top)
    mb.faces(fs, ALU, o)
    bot = ring(0.008, r) + ring(0.0, r * 0.85) + [P(0, 0.003, 0)]
    fs = []
    for k in range(segs):
        k2 = (k + 1) % segs
        fs.append((k, k2, segs + k2, segs + k))
        fs.append((segs + k, segs + k2, 2 * segs))
    o = mb.verts(bot)
    mb.faces(fs, ALU, o)


# ------------------------------------------------------------------ Gary's body (makePerson, H=1.72), to drape the quilt
GH = 1.72
HEAD = (-3.661, 0.21, 0.73)           # head sphere center when lying (feet x=-1.95, head toward -x)
HEAD_R = 0.115 * GH


def gary_top(X, Z, grow=1.06):
    """Top surface height of Gary's lying body (legs, shoes, pelvis, torso, belly; no arms) over grids X, Z."""
    e = np.zeros_like(X)

    def ell(c, r, g=grow):
        rx, ry, rz = r[0] * g, r[1] * g, r[2] * g
        q = 1 - ((X - c[0]) / rx) ** 2 - ((Z - c[2]) / rz) ** 2
        return np.where(q > 0, c[1] + ry * np.sqrt(np.clip(q, 0, None)), 0.0)

    def xcyl(xa, xb, ra, rb, cy, cz, ys=1.0, g=grow):
        t = np.clip((X - xa) / (xb - xa), 0, 1)
        r = (ra + (rb - ra) * t) * g
        q = 1 - ((Z - cz) / r) ** 2
        ins = (X <= max(xa, xb)) & (X >= min(xa, xb)) & (q > 0)
        return np.where(ins, cy + r * ys * np.sqrt(np.clip(q, 0, None)), 0.0)
    for s in (-1, 1):
        zc = 0.73 - s * 0.085 * GH
        e = np.maximum(e, xcyl(-2.0016, -2.7584, 0.055 * GH, 0.062 * GH, 0.21, zc, g=1.04))
        e = np.maximum(e, np.where((X > -2.07) & (X < -1.935) & (np.abs(Z - zc) < 0.095), 0.432, 0.0))
    e = np.maximum(e, ell((-2.7756, 0.21, 0.73), (0.1277, 0.1811, 0.2438)))           # pelvis
    e = np.maximum(e, xcyl(-2.7756, -3.326, 0.13 * GH, 0.15 * GH, 0.21, 0.73, 0.74))    # torso
    e = np.maximum(e, ell((-3.326, 0.21, 0.73), (0.1084, 0.1909, 0.258)))              # chest
    e = np.maximum(e, ell((-2.9648, 0.2874, 0.73), (0.2064, 0.1135, 0.2167)))          # belly
    return e


def blur(A, s):
    r = int(3 * s) + 1
    g = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    g /= g.sum()
    P = np.pad(A, ((r, r), (0, 0)), mode="edge")
    A = sum(g[k] * P[k:k + A.shape[0], :] for k in range(2 * r + 1))
    P = np.pad(A, ((0, 0), (r, r)), mode="edge")
    return sum(g[k] * P[:, k:k + A.shape[1]] for k in range(2 * r + 1))


class Drape:
    """Height field of a cloth thrown over Gary: cone-dilated body envelope, blurred, plus folds."""
    def __init__(self, slope=1.2, clear=0.015):
        st = self.st = 0.015
        self.xs = np.arange(-3.50, -1.45, st)
        self.zs = np.arange(0.10, 1.36, st)
        X, Z = np.meshgrid(self.xs, self.zs, indexing="ij")
        E = gary_top(X, Z)
        sel = E > 0
        qx, qz, qe = X[sel].astype(np.float32), Z[sel].astype(np.float32), E[sel].astype(np.float32)
        fx, fz = X.ravel().astype(np.float32), Z.ravel().astype(np.float32)
        out = np.empty(fx.size, np.float32)
        for a in range(0, fx.size, 400):
            dx = fx[a:a + 400, None] - qx[None, :]
            dz = fz[a:a + 400, None] - qz[None, :]
            out[a:a + 400] = np.max(qe[None, :] - slope * np.sqrt(dx * dx + dz * dz), axis=1)
        D = blur(np.maximum(out.reshape(X.shape), 0.0), 1.6)
        self.D = np.where(sel, np.maximum(D, E + clear), D)
        self.E = E
        self.GX, self.GZ = np.gradient(self.D, st)

    def samp(self, A, x, z):
        fi, fj = (x - self.xs[0]) / self.st, (z - self.zs[0]) / self.st
        i = min(max(int(math.floor(fi)), 0), A.shape[0] - 2)
        j = min(max(int(math.floor(fj)), 0), A.shape[1] - 2)
        ti, tj = min(max(fi - i, 0.0), 1.0), min(max(fj - j, 0.0), 1.0)
        return float(A[i, j] * (1 - ti) * (1 - tj) + A[i + 1, j] * ti * (1 - tj) + A[i, j + 1] * (1 - ti) * tj + A[i + 1, j + 1] * ti * tj)

    def folds(self, x, z):
        gx, gz = self.samp(self.GX, x, z), self.samp(self.GZ, x, z)
        m = smoothstep(0.12, 0.55, math.hypot(gx, gz))
        side = abs(gz) / (abs(gx) + abs(gz) + 1e-6)
        n1 = nz(x * 3.1, z * 1.7, 0.3)
        rs = 0.5 + 0.5 * math.sin(2 * math.pi * (x + 0.06 * n1) / 0.17)
        rf = 0.5 + 0.5 * math.sin(2 * math.pi * (z + 0.05 * n1) / 0.12)
        d = self.samp(self.D, x, z)
        gm = 1.0 - smoothstep(0.0, 0.05, d)
        return 0.015 * m * (side * rs ** 2 + (1 - side) * rf ** 2) + 0.007 * gm * (0.5 + 0.5 * nz(x * 6, z * 6, 1.7))

    def under(self, x, z):
        """Height of the quilt's underside."""
        return self.samp(self.D, x, z) + 0.003 + self.folds(x, z)


QUILT_T = 0.026     # quilt thickness
QUILT_PUFF = 0.007


# ================================================================== welcome mat
def build_mat():
    cx, cz, W, D = -1.1, 1.4, 0.9, 0.6
    n, m = 16, 11
    X = [[0.0] * (m + 1) for _ in range(n + 1)]
    Z = [[0.0] * (m + 1) for _ in range(n + 1)]
    YB = [[0.0] * (m + 1) for _ in range(n + 1)]
    YT = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for j in range(m + 1):
            u, v = i / n, j / m
            x, z = cx + (u - 0.5) * W, cz + (v - 0.5) * D
            if i in (0, n) or j in (0, m):                     # frayed outline
                f = nz(x * 23.0, z * 23.0, 0.5)
                x += (1 if i == n else -1 if i == 0 else 0) * 0.009 * f
                z += (1 if j == m else -1 if j == 0 else 0) * 0.009 * f
            curl = smoothstep(0.72, 1.0, u) * smoothstep(0.62, 1.0, v)   # the +x/+z corner curls up
            lift = 0.04 * curl ** 2
            de = min(u * W, (1 - u) * W, v * D, (1 - v) * D)
            X[i][j], Z[i][j] = x, z
            YB[i][j] = 0.0015 + lift
            YT[i][j] = 0.024 - 0.007 * (1 - smoothstep(0.0, 0.035, de)) + 0.0025 * nz(x * 31, z * 31, 2.0) + lift
    base, border = ck.clay("#8a6a3a", 0.95), ck.clay("#6e5230", 0.95)
    mb = MB()
    grid_slab(mb, X, Z, YB, YT, lambda i, j: border if (i < 2 or i >= n - 2 or j < 2 or j >= m - 2) else base, border, border, bulge=0.003)
    ob = mb.build("Mat_Base", recalc=True)
    ck.lumpy(ob, 0.0015, 40.0, 3)
    fr = MB()
    fringe = ck.clay("#9a7a4a", 0.95)
    for sx in (-1, 1):                                   # frayed fringe on the short ends
        for k in range(14):
            z = cz - D / 2 + 0.025 + (D - 0.05) * k / 13 + R.uniform(-0.008, 0.008)
            x0 = cx + sx * (W / 2 - 0.012)
            L, a = R.uniform(0.02, 0.05), R.uniform(-0.6, 0.6)
            x1, z1 = x0 + sx * L * math.cos(a), z + L * math.sin(a)
            tube(fr, [(x0, 0.012, z), ((x0 + x1) / 2, 0.008, (z + z1) / 2 + R.uniform(-0.006, 0.006)), (x1, 0.0045, z1)], 0.0045, fringe, segs=4)
    f = fr.build("Mat_Fringe")
    txt = ctext("WELCOME", 0.14, 0.012, ck.clay("#2a1a10", 0.9), "Mat_Text", "impact", 0.6, 0.0, res=2)
    ck._place(txt, (cx, 0.026, cz), (-math.pi / 2, 0, 0), None)
    return ck.join([ob, f, txt], "WelcomeMat")


# ================================================================== shopping cart
TOP = [(-0.34, 0.99, -0.46), (0.34, 0.99, -0.46), (0.41, 1.0, 0.43), (-0.41, 1.0, 0.43)]    # basket rim FL FR BR BL (local)
BOT = [(-0.30, 0.56, -0.36), (0.30, 0.56, -0.36), (0.38, 0.53, 0.40), (-0.38, 0.53, 0.40)]


def lerp3(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def quad(c00, c10, c11, c01, s, h):
    return lerp3(lerp3(c00, c10, s), lerp3(c01, c11, s), h)


def basket_clamp(p):
    """Keep bag vertices below the rim inside the wire basket, and out of the kid seat (the can sack sits there)."""
    x, y, z = p
    if y < 1.15:
        z = min(z, 0.19)
    if y < 0.99:
        h = min(max((y - 0.53) / 0.46, 0.0), 1.0)
        zf, zb = -0.36 - 0.10 * h + 0.022, 0.40 + 0.03 * h - 0.022
        z = min(max(z, zf), zb)
        t = (z + 0.4) / 0.83
        hw = 0.30 + 0.08 * t + 0.035 * h - 0.022
        x = min(max(x, -hw), hw)
        y = max(y, 0.552)
    return [x, y, z]


def ellip(mb, c, ax, ay, az, m, segs=10, rings=6):
    """Ellipsoid with arbitrary half-axis vectors (game coords)."""
    if ax.cross(ay).dot(az) < 0:                             # keep the winding outward
        az = -az
    V0, F = uvs(segs, rings)
    mb.add([ck.G(Vector(c) + ax * u[0] + ay * u[1] + az * u[2]) for u in V0], F, m)


def trash_bag(name, c, size, col, knot, seed, parent=None, tie=None, tied=True, segs=16, rings=10):
    """A stuffed garbage bag: slouchy boxy sack, deep creases gathered into a twisted neck, two flat tied flaps.
    size = (side, along the knot axis, side); vertices below the rim stay inside the basket.
    tied=False: no neck or knot (for bags whose tops are buried under the others)."""
    d = Vector(knot).normalized()
    a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    e1 = d.cross(a).normalized()
    e2 = e1.cross(d)                                         # right-handed (e1, d, e2), or the sphere turns inside out
    rs = random.Random(seed)
    nf, ph = rs.choice((10, 11, 12)), rs.uniform(0, 6.28)
    V0, F = uvs(segs, rings)
    vs = []
    pokes = []                                               # corners of whatever is inside pushing the plastic out
    for _ in range(3):
        a_, b_ = rs.uniform(0, 6.28), rs.uniform(-0.9, 0.2)
        pokes.append((Vector((math.cos(a_) * math.cos(b_), math.sin(b_), math.sin(a_) * math.cos(b_))), rs.uniform(0.035, 0.06)))
    for (ux, uy, uz) in V0:
        pinch = smoothstep(0.25, 1.0, uy) if tied else 0.0
        rr = (1.0 + 0.2 * (1 - uy) * 0.5) * (1 - 0.86 * pinch ** 1.4)
        az = math.atan2(uz, ux)
        cr = 1 + (0.03 + 0.22 * pinch) * (2 * abs(math.sin(0.5 * (nf * az + ph + 2.2 * uy))) - 1)
        uu = Vector((ux, uy, uz))
        push = sum(amt * smoothstep(0.7, 1.0, uu.dot(pd)) ** 2 for pd, amt in pokes)
        q = (Vector(c) + e1 * (size[0] * sgnpow(ux, 0.65) * rr * cr + ux * push) + d * (size[1] * sgnpow(uy, 0.8) + 0.07 * pinch + uy * push)
             + e2 * (size[2] * sgnpow(uz, 0.65) * rr * cr + uz * push))
        vs.append(ck.G(basket_clamp(list(q))))
    mb = MB()
    mb.add(vs, F, col)
    ob = mb.build(name, parent)
    ck.lumpy(ob, 0.03, 3.5, seed)
    crumple(ob, 0.014, 7.0, seed + 3)
    if not tied:
        return ob
    top = Vector(c) + d * (size[1] + 0.07)
    km = MB()
    tube(km, [tuple(top - d * 0.06), tuple(top - d * 0.01), tuple(top + d * 0.03)], [0.036, 0.022, 0.02], col, segs=8)
    ellip(km, top + d * 0.03, e1 * 0.026, d * 0.022, e2 * 0.024, tie or col, 7, 4)
    for sgn, up, ln in ((-1, 0.75, 0.05), (1, -0.25, 0.044)):   # the two flaps it was tied with: one perky, one flopped
        along = (d * up + e1 * sgn).normalized()
        wid = (e2 + d * 0.25 * sgn).normalized()
        nrm = along.cross(wid).normalized()
        ellip(km, top + d * 0.035 + along * (ln - 0.008), along * ln, nrm * 0.007, wid * 0.03, tie or col, 8, 4)
    k = km.build(name + "_knot", parent)
    ck.lumpy(k, 0.004, 40.0, seed)
    return ck.join([ob, k], name)


def caster(par, x, z, turn, parts):
    g = ck.empty("_caster", (x, 0, z), rot=(0, turn, 0), parent=par)
    parts.append(ck.cyl(0.06, 0.06, 0.032, (0, 0.06, 0), RUBBER, rot=(0, 0, math.pi / 2), parent=g, segs=12, name="wheel"))
    for s in (-1, 1):
        parts.append(ck.cyl(0.026, 0.026, 0.006, (s * 0.018, 0.06, 0), ALU, rot=(0, 0, math.pi / 2), parent=g, segs=8, name="hub"))
        parts.append(ck.box(0.006, 0.085, 0.034, (s * 0.024, 0.1, -0.008), ALU, parent=g, name="fork"))
    parts.append(ck.box(0.056, 0.008, 0.05, (0, 0.142, -0.006), ALU, parent=g, name="plate", bevel=0.002, bevel_segs=1))
    parts.append(ck.cyl(0.011, 0.011, 0.02, (0, 0.152, -0.006), ALU, parent=g, segs=8, name="stem"))


def build_cart():
    cart = ck.empty("ShoppingCart", (-5.9, 0, 1.15), rot=(0, 0.3, 0))
    fr = MB()

    def panel(c00, c10, c11, c01, ns, hs, r=0.0065, bend=None):
        for k in range(1, ns):
            s = k / ns
            mid = list(quad(c00, c10, c11, c01, s, 0.5))
            mid[0] += R.uniform(-0.006, 0.006)
            mid[2] += R.uniform(-0.006, 0.006)
            if bend:
                mid = bend(mid, s)
            tube(fr, [quad(c00, c10, c11, c01, s, 0), tuple(mid), quad(c00, c10, c11, c01, s, 1)], r, ALU, segs=4, cap=False)
        for h in hs:
            tube(fr, [quad(c00, c10, c11, c01, s, h) for s in (0, 0.5, 1)], r, ALU, segs=4, cap=False)

    def dent(p, s):                                       # the right side got kicked in a bit
        k = math.exp(-((s - 0.45) / 0.18) ** 2)
        return [p[0] - 0.035 * k, p[1], p[2]]
    panel(BOT[1], BOT[2], TOP[2], TOP[1], 14, (0.35, 0.68), bend=dent)   # right side
    panel(BOT[0], BOT[3], TOP[3], TOP[0], 14, (0.35, 0.68))              # left side
    panel(BOT[0], BOT[1], TOP[1], TOP[0], 10, (0.5,))                     # front
    panel(BOT[3], BOT[2], TOP[2], TOP[3], 10, (0.42, 0.78))              # back gate
    panel(BOT[0], BOT[1], BOT[2], BOT[3], 9, (0.3, 0.7))                  # floor
    tube(fr, rounded(TOP, 0.04, 3, closed=True), 0.013, ALU, segs=6, closed=True)
    tube(fr, rounded(BOT, 0.03, 3, closed=True), 0.01, ALU, segs=5, closed=True)
    # rear legs and handle in one bent tube, chassis U, front legs
    tube(fr, rounded([(0.36, 0.15, 0.40), (0.375, 0.53, 0.42), (0.395, 0.96, 0.462), (0.36, 1.07, 0.51),
                      (-0.36, 1.07, 0.51), (-0.395, 0.96, 0.462), (-0.375, 0.53, 0.42), (-0.36, 0.15, 0.40)], 0.05, 4), 0.015, ALU, segs=8)
    tube(fr, rounded([(0.36, 0.15, 0.40), (0.30, 0.15, -0.40), (-0.30, 0.15, -0.40), (-0.36, 0.15, 0.40)], 0.05, 3), 0.014, ALU, segs=7)
    for s in (-1, 1):
        tube(fr, [(s * 0.30, 0.15, -0.40), (s * 0.302, 0.36, -0.385), (s * 0.30, 0.56, -0.36)], 0.013, ALU, segs=7)
    for k in range(6):                                     # bottom tray
        x = -0.24 + 0.096 * k
        tube(fr, [(x, 0.165, -0.385), (x, 0.165, 0.385)], 0.006, ALU, segs=5)
    for z in (-0.33, 0.0, 0.33):
        rx = 0.30 + 0.06 * (z + 0.40) / 0.8
        tube(fr, [(-rx, 0.16, z), (rx, 0.16, z)], 0.006, ALU, segs=5)
    frame = fr.build("Cart_Frame", cart)
    parts = [frame]
    parts.append(ck.cyl(0.022, 0.022, 0.6, (0, 1.07, 0.51), RED, rot=(0, 0, math.pi / 2), parent=cart, segs=12, name="grip"))
    parts.append(ck.box(0.5, 0.016, 0.15, (0, 0.866, 0.333), RED, parent=cart, name="seat_flap", bevel=0.006, bevel_segs=2))
    for (x, z, t) in [(0.36, 0.40, 0.1), (-0.36, 0.40, -0.06), (0.30, -0.40, 1.25), (-0.30, -0.40, 0.05)]:
        caster(cart, x, z, t, parts)
    ck.join(parts, "Cart_Frame")
    # the load: four trash bags (the JS colors), a bag of cans in the kid seat, a bedroll strapped to the front
    bags = [trash_bag("bag_brown", (-0.13, 0.77, -0.17), (0.21, 0.22, 0.22), ck.clay("#6a5a3a", 0.55), (-0.15, 1, -0.3), 1, cart, tied=False),
            trash_bag("bag_blue", (0.14, 0.78, -0.08), (0.22, 0.23, 0.23), ck.clay("#3a5a6a", 0.55), (0.35, 1, 0.05), 2, cart, tied=False),
            trash_bag("bag_red", (-0.12, 1.08, -0.15), (0.21, 0.27, 0.22), ck.clay("#8a3a3a", 0.55), (-0.8, 0.4, -0.5), 3, cart),
            trash_bag("bag_cream", (0.14, 1.08, 0.04), (0.24, 0.22, 0.23), ck.clay("#c8c0a8", 0.55), (0.3, 1, 0.35), 4, cart,
                      tie=RED)]
    cans = MB()
    cols = ["#c4162a", "#c8ccd4", "#3a5a8a", "#4a7a4a", "#f2c230", "#c4162a", "#c8ccd4", "#e84a9a", "#3a5a8a"]
    rc = random.Random(44)
    for k, col in enumerate(cols):
        a = k * 2.4
        rad_k = 0.035 + 0.06 * (k % 3) / 2
        base = (rad_k * math.cos(a) * 1.5, 0.89 + 0.06 * (k // 3), 0.335 + rad_k * math.sin(a) * 0.7)
        up = k >= 6
        can(cans, base, 0.115, 0.03, ALU if col == "#c8ccd4" else ck.clay(col, 0.5),
            tilt=((rc.uniform(-0.35, 0.35), rc.uniform(0, 6.28), rc.uniform(-0.35, 0.35)) if up else
                  (rc.uniform(-1.3, 1.3), rc.uniform(0, 6.28), rc.uniform(-1.3, 1.3))), crush=0.3)
    cobj = cans.build("cans", cart)
    V0, F = uvs(16, 10)
    keep = [f for f in F if min(f) >= 1 + 16]               # drop the top cap: an open bag
    sk = MB()
    sk.add([ck.G((0.2 * u[0], max(0.99 + 0.14 * u[1], 0.876), 0.335 + 0.11 * u[2])) for u in V0], keep, ck.glass("#dde6ee", 0.3))
    sack = sk.build("can_sack", cart)
    ck.lumpy(sack, 0.012, 9.0, 5)
    roll = MB()
    olive, olive_l = ck.clay("#6a7a4a", 0.9), ck.clay("#8a9a64", 0.9)
    rr = ck.cyl(0.085, 0.085, 0.56, (0, 0.80, -0.56), olive, rot=(0, 0, math.pi / 2), parent=cart, segs=16, name="bedroll")
    ck.lumpy(rr, 0.006, 9.0, 8)
    for s in (-1, 1):
        sp = [(s * 0.283, 0.80 + (0.012 + 0.068 * t) * math.sin(5 * math.pi * t), -0.56 + (0.012 + 0.068 * t) * math.cos(5 * math.pi * t)) for t in [k / 14 for k in range(15)]]
        tube(roll, sp, 0.0045, olive_l, segs=4)
        # strap around the roll and over the rim
        st = [(s * 0.17, 0.80 + 0.092 * math.sin(a), -0.56 + 0.092 * math.cos(a)) for a in [math.pi * 2 * k / 14 for k in range(14)]]
        tube(roll, st, 0.009, DARK, segs=4, closed=True)
        tube(roll, [(s * 0.17, 0.89, -0.545), (s * 0.18, 0.96, -0.50), (s * 0.18, 0.99, -0.46)], 0.008, DARK, segs=4)
    rob = roll.build("bedroll_bits", cart)
    ck.join(bags + [cobj, sack, rr, rob], "Cart_Load")
    return cart


# ================================================================== WELCOME HOME sign
def build_sign():
    sx, sz = -4.55, 0.6
    bucket_c = ck.clay("#e4e0d4", 0.7)
    parts = [ck.cyl(0.112, 0.095, 0.19, (sx, 0.095, sz), bucket_c, segs=22, name="bucket")]
    mb = MB()
    tube(mb, [(sx + 0.112 * math.cos(a), 0.192, sz + 0.112 * math.sin(a)) for a in [2 * math.pi * k / 20 for k in range(20)]], 0.008, bucket_c, segs=5, closed=True)
    for k, (a, L) in enumerate([(1.2, 0.09), (1.75, 0.05), (2.3, 0.12), (0.7, 0.04), (2.8, 0.07)]):   # red paint drips (he painted the sign with it)
        pts = []
        for t in (0.0, 0.5, 1.0):
            y = 0.196 - L * t
            rr = 0.095 + 0.017 * (y / 0.19) + 0.0035
            pts.append((sx + rr * math.cos(a), y, sz + rr * math.sin(a)))
        tube(mb, pts, [0.006, 0.005, 0.007], PAINT, segs=6)
    tube(mb, [(sx + 0.117 * math.cos(a), 0.199, sz + 0.117 * math.sin(a)) for a in [0.4 + 2.6 * k / 9 for k in range(10)]], 0.0055, PAINT, segs=5)
    tube(mb, [(sx + 0.112 * math.cos(a), 0.17 - 0.05 * math.sin(a - 1.0), sz + 0.112 * math.sin(a) + 0.06 * math.sin(a - 1.0) ** 2)
              for a in [1.0 + math.pi * k / 12 for k in range(13)]], 0.0035, ALU, segs=5)   # wire handle, flopped down
    parts.append(mb.build("bucket_bits"))
    parts.append(blob("gravel", (sx, 0.197, sz), (0.1, 0.018, 0.1), ck.clay("#8a8a90", 0.95), 14, 6,
                      fn=lambda p, u: [p[0], max(p[1], 0.188), p[2]], lump=(0.008, 40.0, 2)))
    g = ck.empty("_sign", (sx, 0.19, 0.535), rot=(-0.02, 0.07, 0.035))
    post = ck.box(0.062, 1.0, 0.058, (0, 0.40, 0), WOOD, parent=g, name="post", bevel=0.008)
    ck.wobble(post, 0.004, 1.5, 5)
    parts.append(post)
    p1 = ck.box(0.82, 0.2, 0.03, (0.0, 0.865, 0.045), SIGN_WHITE, rot=(0, 0, 0.012), parent=g, name="plank_top", bevel=0.009, bevel_segs=2)
    p2 = ck.box(0.80, 0.195, 0.03, (0.012, 0.66, 0.047), SIGN_WHITE, rot=(0, 0, -0.01), parent=g, name="plank_bot", bevel=0.009, bevel_segs=2)
    for p, s in ((p1, 11), (p2, 12)):
        ck.lumpy(p, 0.0025, 9.0, s, subdiv=0)
        parts.append(p)
    for y in (0.83, 0.90, 0.63, 0.70):
        parts.append(ck.cyl(0.009, 0.009, 0.006, (R.uniform(-0.006, 0.006), y, 0.0625), ck.clay("#3a3a3e", 0.5), rot=(math.pi / 2, 0, 0), parent=g, segs=8, name="nail"))
    parts.append(hand_text("WELCOME", 0.2, 0.008, (0.0, 0.862, 0.0625), PAINT, parent=g, name="txt_welcome", fit_width=0.70, seed=3, drips=(1, 5, 6)))
    parts.append(hand_text("HOME", 0.22, 0.008, (0.02, 0.655, 0.0645), PAINT, parent=g, name="txt_home", fit_width=0.46, seed=9, drips=(0, 2)))
    return ck.join(parts, "WelcomeHomeSign")


# ================================================================== Gary's mailbox + front yard
def mailbox_profile(n_arch=14, scale=1.0, cy=1.1):
    """Rural mailbox cross-section (x, y): flat sides, rounded bottom corners, arched top."""
    pts, rc, hw = [], 0.02 * scale, 0.15 * scale
    y0 = cy - 0.15 * scale
    for k in range(4):
        a = -math.pi / 2 + (math.pi / 2) * k / 3
        pts.append((hw - rc + rc * math.cos(a), y0 + rc + rc * math.sin(a)))
    for k in range(1, 4):
        pts.append((hw, y0 + rc + (cy - y0 - rc) * k / 3))
    for k in range(1, n_arch):
        a = math.pi * k / n_arch
        pts.append((hw * math.cos(a), cy + hw * math.sin(a)))
    for k in range(0, 3):
        pts.append((-hw, cy - (cy - y0 - rc) * k / 3))
    for k in range(4):
        a = math.pi + (math.pi / 2) * k / 3
        pts.append((-hw + rc + rc * math.cos(a), y0 + rc + rc * math.sin(a)))
    for k in range(1, 4):
        pts.append((-hw + rc + (2 * hw - 2 * rc) * k / 4, y0))
    return pts


def extrude(mb, prof, zs, m, cx=0.0, dentf=None, cap0=True, cap1=True):
    n = len(prof)
    vs = []
    for z in zs:
        for (x, y) in prof:
            p = [cx + x, y, z]
            if dentf:
                p = dentf(p)
            vs.append(ck.G(p))
    cyc = sum(y for _, y in prof) / n
    c0 = len(vs)
    vs.append(ck.G((cx, cyc, zs[0])))
    vs.append(ck.G((cx, cyc, zs[-1])))
    fs = []
    for i in range(len(zs) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            fs.append((i * n + k, i * n + k2, (i + 1) * n + k2, (i + 1) * n + k))
    if cap0:
        fs += [(c0, (k + 1) % n, k) for k in range(n)]
    if cap1:
        b = (len(zs) - 1) * n
        fs += [(c0 + 1, b + k, b + (k + 1) % n) for k in range(n)]
    mb.add(vs, fs, m)


def build_mailbox():
    mx, mz = -1.25, 0.35
    blue = ck.clay("#2a3a6a", 0.45)
    parts = []
    post = ck.box(0.1, 0.94, 0.1, (mx, 0.455, mz), WOOD, rot=(0.02, 0.05, -0.025), name="post", bevel=0.012, bevel_segs=2)
    ck.wobble(post, 0.004, 1.3, 7)
    parts.append(post)
    parts.append(ck.box(0.18, 0.026, 0.44, (mx, 0.937, mz), WOOD, name="shelf", bevel=0.006))

    def dentf(p):                                         # a couple of dents: side and top
        x, y, z = p
        d1 = math.exp(-(((y - 1.04) / 0.07) ** 2 + ((z - 0.27) / 0.09) ** 2))
        d2 = math.exp(-(((x - mx - 0.05) / 0.07) ** 2 + ((z - 0.5) / 0.06) ** 2)) * smoothstep(1.15, 1.22, y)
        cxy = Vector((mx, 1.08))
        q = Vector((x, y))
        inward = (cxy - q).normalized()
        q = q + inward * (0.022 * d1 * smoothstep(0.0, 0.05, mx - x) + 0.014 * d2)
        return [q.x, q.y, z]
    body = MB()
    zs = [0.10, 0.106] + [0.12 + 0.48 * k / 8 for k in range(9)]
    prof = mailbox_profile()
    extrude(body, [(x * 0.97, 1.1 + (y - 1.1) * 0.97) for (x, y) in prof], [zs[0]], blue, cx=mx, cap1=False)
    extrude(body, prof, zs[1:], blue, cx=mx, dentf=dentf)
    parts.append(body.build("box", recalc=False))
    door = MB()
    extrude(door, [(x * 1.035, 1.1 + (y - 1.1) * 1.035) for (x, y) in mailbox_profile()], [0.598, 0.606, 0.614], blue, cx=mx)
    parts.append(door.build("door"))
    parts.append(ck.box(0.045, 0.028, 0.014, (mx, 1.246, 0.619), blue, name="latch", bevel=0.005))
    fx = mx - 0.158                                        # flag on the -x side, UP (outgoing mail!)
    parts.append(ck.box(0.012, 0.27, 0.028, (fx, 1.165, 0.42), RED, name="flag_arm", bevel=0.004))
    parts.append(ck.box(0.012, 0.075, 0.1, (fx, 1.265, 0.484), RED, name="flag", bevel=0.004))
    parts.append(ck.cyl(0.012, 0.012, 0.012, (fx - 0.004, 1.06, 0.42), ck.clay("#3a3a3e", 0.5), rot=(0, 0, math.pi / 2), segs=8, name="rivet"))
    rust = ck.clay("#8a5a3a", 0.9)
    for (x, y, z) in [(mx - 0.06, 1.24, 0.2), (mx + 0.03, 1.248, 0.42)]:
        parts.append(blob("rust", (x, y, z), (0.022, 0.006, 0.03), rust, 8, 5, lump=(0.003, 60, 1)))
    parts.append(hand_text("GARY", 0.09, 0.008, (mx, 1.075, 0.6175), SIGN_WHITE, name="txt_gary", fit_width=0.21, seed=21, jit=0.09))
    return ck.join(parts, "GaryMailbox")


def build_yard():
    """Gary's front lawn: a scrap of fake turf under the mailbox, three stones, and a plastic flamingo."""
    cx, cz, W, D = -1.12, 0.35, 0.62, 0.42
    n, m = 12, 8
    X = [[0.0] * (m + 1) for _ in range(n + 1)]
    Z = [[0.0] * (m + 1) for _ in range(n + 1)]
    YB = [[0.0] * (m + 1) for _ in range(n + 1)]
    YT = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for j in range(m + 1):
            u, v = i / n, j / m
            x, z = cx + (u - 0.5) * W, cz + (v - 0.5) * D
            if i in (0, n) or j in (0, m):
                f = nz(x * 17, z * 17, 4.0)
                x += (1 if i == n else -1 if i == 0 else 0) * 0.012 * f
                z += (1 if j == m else -1 if j == 0 else 0) * 0.012 * f
            curl = smoothstep(0.7, 1.0, u) * smoothstep(0.55, 1.0, v)
            X[i][j], Z[i][j] = x, z
            YB[i][j] = 0.0015 + 0.03 * curl ** 2
            YT[i][j] = YB[i][j] + 0.016 + 0.006 * (0.5 + 0.5 * nz(x * 45, z * 45, 6.0))
    grass, grass_d = ck.clay("#6a8a3a", 0.95), ck.clay("#5c7c34", 0.95)
    mb = MB()
    grid_slab(mb, X, Z, YB, YT, lambda i, j: grass_d if (i * 7 + j * 3) % 5 == 0 else grass, grass_d, grass_d, bulge=0.004)
    turf = mb.build("turf", recalc=True)
    tufts = MB()
    rt = random.Random(77)
    for k in range(30):
        x, z = cx + rt.uniform(-0.28, 0.28), cz + rt.uniform(-0.18, 0.18)
        if abs(x + 1.25) < 0.07 and abs(z - 0.35) < 0.07:
            continue
        h, a, b = rt.uniform(0.02, 0.04), rt.uniform(0, 6.28), rt.uniform(0.1, 0.5)
        tube(tufts, [(x, 0.016, z), (x + math.cos(a) * h * b, 0.016 + h, z + math.sin(a) * h * b)], [0.006, 0.001], grass if k % 3 else grass_d, segs=4)
    parts = [turf, tufts.build("tufts")]
    for (x, z, r) in [(-1.33, 0.27, 0.045), (-1.17, 0.45, 0.035), (-1.2, 0.24, 0.03)]:
        parts.append(blob("stone", (x, 0.016 + r * 0.45, z), (r, r * 0.65, r * 0.85), ck.clay("#8a8a90", 0.95), 8, 5, lump=(0.005, 30, int(x * 100))))
    # the flamingo, facing Gary (-x), legs stuck in the turf beside the post
    pink, pink_d, beak_k = ck.clay("#e84a9a", 0.5), ck.clay("#c83a82", 0.5), ENAMEL
    fx, fz = -1.37, 0.47
    parts.append(blob("fl_body", (fx + 0.01, 0.42, fz), (0.125, 0.07, 0.056), pink, 12, 8,
                      fn=lambda p, u: [p[0], p[1] + 0.22 * (p[0] - fx) + 0.03 * max(u[0], 0) ** 2, p[2]]))
    for s in (-1, 1):
        parts.append(blob("fl_wing", (fx + 0.025, 0.433, fz + s * 0.045), (0.085, 0.04, 0.018), pink_d, 8, 5,
                          fn=lambda p, u: [p[0], p[1] + 0.25 * (p[0] - fx - 0.025), p[2]]))
    fl = MB()
    tube(fl, [(fx - 0.09, 0.43, fz), (fx - 0.125, 0.5, fz), (fx - 0.1, 0.565, fz), (fx - 0.06, 0.61, fz), (fx - 0.07, 0.655, fz)],
         [0.02, 0.016, 0.014, 0.013, 0.014], pink, segs=8)
    tube(fl, [(fx - 0.1, 0.665, fz), (fx - 0.13, 0.655, fz), (fx - 0.145, 0.635, fz)], [0.011, 0.009, 0.007], pink, segs=7)
    tube(fl, [(fx - 0.145, 0.635, fz), (fx - 0.152, 0.62, fz), (fx - 0.15, 0.608, fz)], [0.0068, 0.005, 0.002], beak_k, segs=7)
    tube(fl, [(fx + 0.0, 0.36, fz - 0.012), (fx + 0.004, 0.18, fz - 0.016), (fx + 0.006, 0.005, fz - 0.02)], 0.0045, ALU, segs=5)
    tube(fl, [(fx + 0.02, 0.36, fz + 0.012), (fx + 0.035, 0.18, fz + 0.02), (fx + 0.045, 0.005, fz + 0.026)], 0.0045, ALU, segs=5)
    parts.append(fl.build("fl_neck"))
    parts.append(ck.sph(0.032, (fx - 0.078, 0.668, fz), pink, scale=(1.15, 0.95, 0.9), name="fl_head", segs=10, rings=6))
    for s in (-1, 1):
        parts.append(ck.sph(0.0055, (fx - 0.088, 0.678, fz + s * 0.027), beak_k, name="fl_eye", segs=6, rings=4))
    parts.append(blob("fl_tail", (fx + 0.125, 0.46, fz), (0.03, 0.02, 0.035), pink_d, 8, 5))
    return ck.join(parts, "GaryFrontYard")


# ================================================================== kettle grill
def build_grill():
    gx, gz = -7.2, 0.4
    parts = []
    parts.append(blob("bowl", (gx, 0.62, gz), (0.38, 0.228, 0.38), ENAMEL, 24, 10, fn=lambda p, u: [p[0], min(p[1], 0.62), p[2]], lump=(0.002, 6, 1)))
    parts.append(blob("lid", (gx, 0.616, gz), (0.388, 0.234, 0.388), ENAMEL, 24, 10, fn=lambda p, u: [p[0], max(p[1], 0.616), p[2]], lump=(0.002, 6, 2)))
    parts.append(ck.tor(0.387, 0.008, (gx, 0.617, gz), ENAMEL, rot=(math.pi / 2, 0, 0), name="rim", major_segs=28, minor_segs=4))
    # lid handle: wood bar on two alu brackets
    for s in (-1, 1):
        parts.append(ck.box(0.012, 0.05, 0.03, (gx + s * 0.07, 0.866, gz), ALU, name="bracket", bevel=0.003, bevel_segs=1))
    parts.append(ck.box(0.2, 0.032, 0.042, (gx, 0.894, gz), ck.clay("#6a3e1e", 0.6), name="handle", bevel=0.013, bevel_segs=2))
    parts.append(ck.box(0.17, 0.005, 0.06, (gx, 0.853, gz), ALU, name="shield", bevel=0.002, bevel_segs=1))
    # lid damper vent near the top, facing the street: a disc with three radial slots and a tab
    lat = math.radians(60)
    vp = Vector((gx, 0.616 + 0.234 * math.sin(lat), gz + 0.388 * math.cos(lat)))
    n = Vector((0, math.sin(lat) / 0.234, math.cos(lat) / 0.388)).normalized()
    tilt = math.atan2(n.z, n.y)
    vc = vp + n * 0.003
    parts.append(ck.cyl(0.042, 0.042, 0.005, tuple(vc), ALU, rot=(tilt, 0, 0), segs=14, name="vent"))
    t1 = Vector((1, 0, 0))
    t2 = n.cross(t1)
    vm = MB()
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        rd = t1 * math.cos(a) + t2 * math.sin(a)
        tube(vm, [tuple(vc + n * 0.003 + rd * 0.012), tuple(vc + n * 0.003 + rd * 0.031)], 0.0045, RUBBER, segs=5)
    tube(vm, [tuple(vc + n * 0.004 + t1 * 0.03), tuple(vc + n * 0.006 + t1 * 0.058)], 0.005, ALU, segs=5)
    parts.append(vm.build("vent_slots"))
    # side handle (+x) with a spatula hanging off it
    mb = MB()
    for dz in (-0.045, 0.045):
        tube(mb, [(gx + 0.36, 0.585, gz + dz), (gx + 0.42, 0.585, gz + dz)], 0.006, ALU, segs=5)
    tube(mb, [(gx + 0.425, 0.585, gz - 0.065), (gx + 0.425, 0.585, gz + 0.065)], 0.014, ENAMEL, segs=8)
    tube(mb, [(gx + 0.425, 0.6, gz + 0.02), (gx + 0.435, 0.57, gz + 0.02), (gx + 0.44, 0.545, gz + 0.02)], 0.004, ALU, segs=5)
    # legs: two with wheels (curb side), one with a foot; triangle shelf with the ash pan
    feet = []
    for a in (90, 210, 330):
        ar = math.radians(a)
        top = (gx + 0.22 * math.cos(ar), 0.44, gz + 0.22 * math.sin(ar))
        bot = (gx + 0.33 * math.cos(ar), 0.055 if a != 90 else 0.012, gz + 0.33 * math.sin(ar))
        tube(mb, [top, lerp3(top, bot, 0.5), bot], 0.014, ALU, segs=7)
        feet.append((top, bot))
    tri = [lerp3(t, b, (0.44 - 0.18) / (0.44 - b[1])) for (t, b) in feet]
    tube(mb, rounded(tri, 0.03, 2, closed=True), 0.006, ALU, segs=5, closed=True)
    tube(mb, [feet[1][1], feet[2][1]], 0.006, ALU, segs=5)
    parts.append(mb.build("grill_bits"))
    parts.append(ck.sph(0.02, (feet[0][1][0], 0.012, feet[0][1][2]), RUBBER, scale=(1, 0.6, 1), name="foot", segs=10, rings=6))
    for t, b in feet[1:]:
        parts.append(ck.cyl(0.055, 0.055, 0.026, (b[0] + (0.02 if b[0] > gx else -0.02), 0.055, b[2]), RUBBER, rot=(0, 0, math.pi / 2), segs=14, name="wheel"))
    parts.append(ck.cyl(0.15, 0.12, 0.04, (gx, 0.16, gz), ALU, segs=20, name="ash_pan"))
    sp = ck.empty("_spatula", (gx + 0.44, 0.545, gz + 0.02), rot=(0.05, 0.3, 0.06))
    parts.append(ck.box(0.016, 0.16, 0.011, (0, -0.08, 0), WOOD, parent=sp, name="sp_handle", bevel=0.004, bevel_segs=1))
    parts.append(ck.box(0.07, 0.085, 0.004, (0, -0.2, 0), ALU, parent=sp, name="sp_blade"))
    return ck.join(parts, "KettleGrill")


# ================================================================== Gary's bed: quilt, pillow, clutter
QUILT_PURPLES = ["#6a4a6a", "#7a5a7a", "#5a3a5a", "#6a4a5a", "#7a4a6a", "#5a4a6a"]
QUILT_ACCENTS = ["#8a6a3a", "#8a3a3a", "#4a5a6a", "#a8987a"]


def build_bed(dr):
    def x_top(z):
        return -3.18 + 0.14 * ((z - 0.73) / 0.45) ** 2

    def x_end(z):
        return -1.645 + 0.022 * math.sin(z * 9.0) + 0.012 * nz(z * 5, 0.3, 0.7)

    def z_lo(x):
        return 0.30 + 0.022 * math.sin(x * 6.0 + 1.0) + 0.01 * nz(x * 4, 1.1, 0.2)

    def z_hi(x):
        return 1.165 + 0.026 * math.sin(x * 5.0 + 2.0) + 0.01 * nz(x * 4, 2.3, 0.9)
    Ltot = 1.53
    band = [0.0, 0.012, 0.035, 0.062, 0.085, 0.100]
    s0, NPX, CPX, NPZ, CPZ = 0.108, 8, 4, 5, 4
    srows = band + [s0 + (Ltot - s0) * k / (NPX * CPX) for k in range(NPX * CPX + 1)]
    vrows = [k / (NPZ * CPZ) for k in range(NPZ * CPZ + 1)]
    nb, nI, nJ = len(band), len(srows), len(vrows)
    X = [[0.0] * nJ for _ in range(nI)]
    Z = [[0.0] * nJ for _ in range(nI)]
    YB = [[0.0] * nJ for _ in range(nI)]
    YT = [[0.0] * nJ for _ in range(nI)]
    for i, s in enumerate(srows):
        for j, v in enumerate(vrows):
            xn = -3.18 + s
            z = z_lo(xn) + v * (z_hi(xn) - z_lo(xn))
            x = x_top(z) + s / Ltot * (x_end(z) - x_top(z))
            dl = min(min(v, 1 - v) * (z_hi(xn) - z_lo(xn)), (Ltot - s) / Ltot * (x_end(z) - x_top(z)))
            body = dr.samp(dr.E, x, z)
            yb = min(dr.under(x, z), 0.003 + 2.3 * dl + 0.004 * (0.5 + 0.5 * nz(x * 9, z * 9, 3.0)))   # edges reach the asphalt
            yb = max(yb, body + 0.015) if body > 0 else yb
            if i < nb:                                      # folded-back band shows the lining
                yt = yb + QUILT_T + 0.02 * smoothstep(-0.004, 0.012, s)
            else:
                a, b = ((i - nb) % CPX) / CPX, (j % CPZ) / CPZ
                yt = yb + QUILT_T + QUILT_PUFF * math.sin(math.pi * a) * math.sin(math.pi * b)
            X[i][j], Z[i][j], YB[i][j], YT[i][j] = x, z, yb, yt
    # patch colors: mostly purples, a few accents, no two neighbors alike
    rq = random.Random(9)
    cols = [[None] * NPZ for _ in range(NPX)]
    for pi in range(NPX):
        for pj in range(NPZ):
            while True:
                c = rq.choice(QUILT_ACCENTS) if rq.random() < 0.2 else rq.choice(QUILT_PURPLES + ["#6a4a6a"] * 3)
                if (pi == 0 or cols[pi - 1][pj] != c) and (pj == 0 or cols[pi][pj - 1] != c):
                    break
            cols[pi][pj] = c
    lining, binding = ck.clay("#d8ccb4", 0.95), ck.clay("#4a2a44", 0.95)

    def top_mat(i, j):
        if i < nb:
            return binding if i == nb - 1 else lining
        return ck.clay(cols[min((i - nb) // CPX, NPX - 1)][min(j // CPZ, NPZ - 1)], 0.97)
    mb = MB()
    grid_slab(mb, X, Z, YB, YT, top_mat, lining, lambda side, k: lining if side == "x0" else binding, bulge=0.007)
    quilt = mb.build("GaryQuilt", recalc=True)
    ck.lumpy(quilt, 0.003, 11.0, 4)

    def top_bound(x, z):
        return dr.under(x, z) + QUILT_T + QUILT_PUFF

    # two sewn-on repair patches with white stitches
    extras = []
    stitch = ck.clay("#ece4d2", 0.9)
    for (cx, cz, w, d, ang, col) in [(-2.28, 0.5, 0.13, 0.11, 0.35, "#4a5a7a"), (-2.62, 0.93, 0.12, 0.1, -0.25, "#a88a4a")]:
        n, m = 4, 4
        PX = [[0.0] * (m + 1) for _ in range(n + 1)]
        PZ = [[0.0] * (m + 1) for _ in range(n + 1)]
        PB = [[0.0] * (m + 1) for _ in range(n + 1)]
        PT = [[0.0] * (m + 1) for _ in range(n + 1)]
        ca, sa = math.cos(ang), math.sin(ang)
        for i in range(n + 1):
            for j in range(m + 1):
                lx, lz = (i / n - 0.5) * w, (j / m - 0.5) * d
                x, z = cx + lx * ca - lz * sa, cz + lx * sa + lz * ca
                PX[i][j], PZ[i][j] = x, z
                PB[i][j] = top_bound(x, z) - 0.003
                PT[i][j] = PB[i][j] + 0.007
        pm = MB()
        grid_slab(pm, PX, PZ, PB, PT, ck.clay(col, 0.95), ck.clay(col, 0.95), ck.clay(col, 0.95), bulge=0.002)
        extras.append(pm.build("repair_patch", recalc=True))
        st = MB()
        for e in range(4):
            for k in range(4):
                t = (k + 0.5) / 4 - 0.5
                lx, lz = [(t * w * 0.85, -d * 0.42), (w * 0.42, t * d * 0.85), (t * w * 0.85, d * 0.42), (-w * 0.42, t * d * 0.85)][e]
                dx, dz = ((0.006, 0) if e % 2 == 0 else (0, 0.006))
                p0 = (cx + (lx - dx) * ca - (lz - dz) * sa, 0, cz + (lx - dx) * sa + (lz - dz) * ca)
                p1 = (cx + (lx + dx) * ca - (lz + dz) * sa, 0, cz + (lx + dx) * sa + (lz + dz) * ca)
                y0, y1 = top_bound(p0[0], p0[2]) + 0.0045, top_bound(p1[0], p1[2]) + 0.0045
                tube(st, [(p0[0], y0, p0[2]), (p1[0], y1, p1[2])], 0.0028, stitch, segs=4)
        extras.append(st.build("stitches"))
    ck.join([quilt] + extras, "GaryQuilt")
    build_pillow()
    build_clutter(dr, top_bound)


def build_pillow():
    c, rad = (-3.80, 0.075, 0.73), (0.27, 0.075, 0.265)
    hx = -3.691                                           # beanie

    def cap(x, z):
        cp = 9.0
        for (cx0, r0) in ((HEAD[0], HEAD_R * 1.04), (hx, 0.19)):
            d = math.hypot(x - cx0, z - HEAD[2])
            if d < r0:
                cp = min(cp, HEAD[1] - math.sqrt(r0 * r0 - d * d) + 0.03)
        ox = max(0.0, abs(x + 3.555) - 0.18)              # long hair under the back of the head
        oz = max(0.0, abs(z - 0.73) - 0.2)
        cp = min(cp, 0.052 + 1.3 * math.hypot(ox, oz))
        return cp

    def fn(p, u):
        x, y, z = p
        y = c[1] + rad[1] * sgnpow(u[1], 0.85) * (1 - 0.5 * abs(sgnpow(u[0], 0.45) * sgnpow(u[2], 0.45)) ** 1.5)
        y = max(y, 0.003)
        s = min(1.0, max(0.12, (cap(x, z) - 0.003) / (0.152 - 0.003)))
        return [x, 0.003 + (y - 0.003) * s, z]
    ob = blob("GaryPillow", c, rad, ck.clay("#e4dccb", 0.95), 28, 14, ex=0.45, fn=fn, lump=(0.004, 9.0, 6))
    # an old stain
    stain = ck.clay("#cdbf94", 0.95)
    sm = ob.data
    ob.data.materials.append(stain)
    for p in sm.polygons:
        cc = p.center
        gx, gz = cc.x, -cc.y
        if math.hypot(gx + 3.98, gz - 0.86) < 0.07 + 0.02 * nz(gx * 20, gz * 20, 1) and cc.z > 0.08:
            p.material_index = 1
    return ob


def build_clutter(dr, top_bound):
    parts = []
    # --- folded newspaper lying across his shins
    cx, cz, ang, w, d = -2.33, 0.70, 0.42, 0.29, 0.2
    n, m = 6, 4
    X = [[0.0] * (m + 1) for _ in range(n + 1)]
    Z = [[0.0] * (m + 1) for _ in range(n + 1)]
    YB = [[0.0] * (m + 1) for _ in range(n + 1)]
    YT = [[0.0] * (m + 1) for _ in range(n + 1)]
    ca, sa = math.cos(ang), math.sin(ang)
    raw = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for j in range(m + 1):
            lx, lz = (i / n - 0.5) * w, (j / m - 0.5) * d
            x, z = cx + lx * ca - lz * sa, cz + lx * sa + lz * ca
            X[i][j], Z[i][j] = x, z
            raw[i][j] = top_bound(x, z)
    for i in range(n + 1):                               # paper is stiff: smooth it, but never dip into the quilt
        for j in range(m + 1):
            nb_ = [raw[a][b] for a in range(max(0, i - 1), min(n, i + 1) + 1) for b in range(max(0, j - 1), min(m, j + 1) + 1)]
            YB[i][j] = max(raw[i][j] - 0.004, sum(nb_) / len(nb_) - 0.002)
            YT[i][j] = YB[i][j] + 0.011 + (0.004 if i == 0 else 0.0)
    paper, ink, head = ck.clay("#d8d4c4", 0.9), ck.clay("#8e8c84", 0.9), ck.clay("#2a2a2a", 0.9)

    def nm(i, j):
        if j == m - 1 and 1 <= i <= 4:
            return head
        if j in (1, 2) and i in (1, 2, 4):
            return ink
        return paper
    mb = MB()
    grid_slab(mb, X, Z, YB, YT, nm, paper, paper, bulge=0.003)
    parts.append(mb.build("newspaper", recalc=True))

    # --- pizza box balanced on his toes, lid propped open, two slices left
    pcx, pcz, pang = -2.0, 0.73, 0.12
    hw = 0.17
    ca, sa = math.cos(pang), math.sin(pang)
    yb = max(top_bound(pcx + lx * ca - lz * sa, pcz + lx * sa + lz * ca) for lx in (-hw, -hw / 2, 0, hw / 2, hw) for lz in (-hw, -hw / 2, 0, hw / 2, hw)) - 0.001
    g = ck.empty("_pizza", (pcx, yb, pcz), rot=(0, pang, 0))
    card, card_in, card_d = ck.clay("#b8925a", 0.9), ck.clay("#cdb07a", 0.9), ck.clay("#9a7444", 0.9)
    parts.append(ck.box(0.34, 0.006, 0.34, (0, 0.003, 0), card, parent=g, name="pz_floor"))
    for (w_, d_, x_, z_) in [(0.34, 0.008, 0, 0.166), (0.34, 0.008, 0, -0.166), (0.008, 0.34, 0.166, 0), (0.008, 0.34, -0.166, 0)]:
        parts.append(ck.box(w_, 0.032, d_, (x_, 0.016, z_), card, parent=g, name="pz_wall", bevel=0.002, bevel_segs=1))
    parts.append(ck.box(0.328, 0.002, 0.328, (0, 0.0065, 0), card_in, parent=g, name="pz_in", bevel=0.0))
    lid = ck.empty("_lid", (0, 0.032, -0.17), rot=(-0.62, 0, 0), parent=g)
    parts.append(ck.box(0.345, 0.007, 0.345, (0, 0.0035, 0.1725), card, parent=lid, name="pz_lid", bevel=0.003, bevel_segs=1))
    parts.append(ck.cyl(0.08, 0.08, 0.003, (0.03, 0.009, 0.2), PAINT, parent=lid, segs=20, name="pz_logo"))
    parts.append(ck.cyl(0.055, 0.055, 0.003, (0.03, 0.011, 0.2), SIGN_WHITE, parent=lid, segs=20, name="pz_logo2"))
    parts.append(blob("pz_grease", (-0.07, 0.008, 0.1), (0.035, 0.002, 0.03), card_d, 8, 4, parent=lid))
    sl = MB()
    cheese, crust, pep = ck.clay("#e8b84a", 0.7), ck.clay("#c8904a", 0.85), ck.clay("#a83a2a", 0.7)
    for (a0, x0, z0) in [(0.15, -0.03, -0.025), (1.15, -0.03, -0.025)]:
        R0, n_ = 0.14, 6
        arc = [(x0 + R0 * math.cos(a0 + 0.78 * k / n_), z0 + R0 * math.sin(a0 + 0.78 * k / n_)) for k in range(n_ + 1)]
        vs = [ck.G((x0, 0.0075, z0)), ck.G((x0, 0.019, z0))]
        for (ax, az) in arc:
            vs += [ck.G((ax, 0.0075, az)), ck.G((ax, 0.019, az))]
        fs = []
        for k in range(n_):
            a, b = 2 + 2 * k, 4 + 2 * k
            fs += [(1, b + 1, a + 1), (0, a, b), (a, a + 1, b + 1, b)]
        fs += [(0, 1, 3, 2), (0, 2 + 2 * n_, 3 + 2 * n_, 1)]
        sl.add(vs, fs, cheese)
        tube(sl, [(ax, 0.02, az) for (ax, az) in arc], 0.011, crust, segs=7)
        for k in range(2):
            t = 0.35 + 0.35 * k
            aa = a0 + 0.78 * (0.3 + 0.4 * k)
            px, pz = x0 + R0 * t * math.cos(aa), z0 + R0 * t * math.sin(aa)
            V0, F = uvs(10, 4)
            sl.add([ck.G((px + 0.018 * u[0], 0.0205 + 0.002 * u[1], pz + 0.018 * u[2])) for u in V0], F, pep)
    parts.append(sl.build("pz_slices", g, recalc=True))

    # --- by his head, on the curb side: a little transistor radio and a soda can
    rg = ck.empty("_radio", (-3.53, 0.0, 0.405), rot=(0, -0.12, 0))
    brown = ck.clay("#4a3a2a", 0.7)
    parts.append(ck.box(0.2, 0.12, 0.068, (0, 0.06, 0), brown, parent=rg, name="radio", bevel=0.014, bevel_segs=2))
    parts.append(ck.cyl(0.036, 0.036, 0.006, (-0.045, 0.058, 0.035), ck.clay("#c8c0a8", 0.55), rot=(math.pi / 2, 0, 0), parent=rg, segs=16, name="grille"))
    for k in range(4):
        parts.append(ck.box(0.05, 0.0035, 0.004, (-0.045, 0.037 + 0.014 * k, 0.0385), DARK, parent=rg, name="slot"))
    parts.append(ck.box(0.062, 0.032, 0.005, (0.052, 0.074, 0.0345), ck.clay("#e8d8a8", 0.6), parent=rg, name="dial"))
    parts.append(ck.box(0.003, 0.026, 0.003, (0.06, 0.074, 0.0375), RED, parent=rg, name="needle"))
    for x in (0.035, 0.07):
        parts.append(ck.cyl(0.011, 0.011, 0.012, (x, 0.032, 0.038), ALU, rot=(math.pi / 2, 0, 0), parent=rg, segs=10, name="knob"))
    rb = MB()
    tube(rb, [(-0.07, 0.115, 0), (-0.05, 0.155, 0), (0.05, 0.155, 0), (0.07, 0.115, 0)], 0.006, DARK, segs=6)
    tube(rb, [(-0.085, 0.11, -0.02), (-0.2, 0.31, -0.03), (-0.3, 0.48, -0.035)], [0.0045, 0.0035, 0.0028], ALU, segs=5)
    parts.append(rb.build("radio_bits", rg))
    parts.append(ck.sph(0.007, (-0.3, 0.48, -0.035), ALU, parent=rg, name="antenna_tip", segs=8, rings=5))
    cm = MB()
    can(cm, (-3.76, 0.0, 0.42), 0.115, 0.032, RED, tilt=(0, 0.6, 0.04))
    parts.append(cm.build("soda"))
    return ck.join(parts, "GaryClutter")


# ================================================================== build
dr = Drape(slope=1.5)
build_mat()
build_cart()
build_sign()
build_mailbox()
build_yard()
build_grill()
build_bed(dr)
while True:                                               # drop helper empties left with no children
    dead = [o for o in bpy.context.scene.objects if o.type == "EMPTY" and o.name.startswith("_") and not o.children]
    if not dead:
        break
    for o in dead:
        bpy.data.objects.remove(o)
ck.export("gary_spot")
for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
    tri = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
    print("[gary_spot] node", o.name, o.type, "parent=" + (o.parent.name if o.parent else "-"), tri, "tris",
          len(o.data.materials) if o.type == "MESH" else "", "mats")


def verify():
    """Contract checks: quilt height, the space above Gary's chest, his body volume, nothing below the street."""
    bpy.context.view_layer.update()
    pts = {}
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            mw = o.matrix_world
            pts[o.name] = [(w.x, w.z, -w.y) for w in (mw @ v.co for v in o.data.vertices)]
    for o in bpy.context.scene.objects:                   # every closed island must have positive volume (normals out)
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        seen, bad, closed = set(), 0, 0
        for f0 in bm.faces:
            if f0.index in seen:
                continue
            stack, vol, shut = [f0], 0.0, True
            seen.add(f0.index)
            while stack:
                f = stack.pop()
                vs = [v.co for v in f.verts]
                for i in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
                for e in f.edges:
                    shut = shut and len(e.link_faces) == 2
                    for g in e.link_faces:
                        if g.index not in seen:
                            seen.add(g.index)
                            stack.append(g)
            if shut:                                      # open pieces (letters, cans, the sack) have no inside
                closed += 1
                bad += vol < -1e-9
        bm.free()
        print("[gary_spot] check %-16s closed islands %d, inside-out %d" % (o.name, closed, bad))
    q = pts["GaryQuilt"]
    print("[gary_spot] check quilt top max y = %.3f (must stay under 0.55)" % max(p[1] for p in q))
    for name, ps in sorted(pts.items()):
        chest = sum(1 for (x, y, z) in ps if -3.0 < x < -2.2 and 0.4 < y < 1.2 and 0.3 < z < 1.2)
        body = sum(1 for (x, y, z) in ps if -3.85 < x < -1.6 and 0.1 < y < 0.5 and 0.5 < z < 0.95)
        print("[gary_spot] check %-16s minY %.3f  above-chest verts %d  in-body-box verts %d" % (name, min(p[1] for p in ps), chest, body))


verify()


# ------------------------------------------------------------------ previews (not exported): street context and a stand-in Gary
def context():
    ck.box(16, 0.1, 6, (-3.5, -0.05, 3.0), ck.clay("#3a3a40", 0.95), name="_asphalt")
    ck.box(16, 0.18, 0.25, (-3.5, 0.09, 0), ck.clay("#c8c4b8"), name="_curb")
    ck.box(16, 0.16, 3.2, (-3.5, 0.08, -1.725), ck.clay("#a8a49a"), name="_side")
    ck.box(16, 0.12, 4, (-3.5, 0.06, -5.3), ck.clay("#6a8a3a", 0.95), name="_grass")


def gary_proxy(armR=(-0.5, 0.2), armL=(-0.3, 0.25)):
    H = GH
    sk, tp, pa, sh, hr = ck.clay("#c8a888"), ck.clay("#7a7258"), ck.clay("#4a4436"), ck.clay("#2a2a2a", 0.5), ck.clay("#6a5a3a")
    outer = ck.empty("_gp_outer", (-1.95, 0.21, 0.73), rot=(0, math.pi / 2, 0))
    inner = ck.empty("_gp_inner", (0, 0, 0), rot=(-math.pi / 2, 0, 0), parent=outer)
    for s in (-1, 1):
        lp = ck.empty("_gp_leg", (s * 0.085 * H, 0.47 * H, 0), parent=inner)
        ck.cyl(0.062 * H, 0.055 * H, 0.44 * H, (0, -0.22 * H, 0), pa, parent=lp, segs=12, name="_gp")
        ck.box(0.1 * H, 0.065 * H, 0.18 * H, (0, -0.44 * H, 0.035 * H), sh, parent=lp, bevel=0.02, name="_gp")
    body = ck.empty("_gp_body", (0, 0.47 * H, 0), parent=inner)
    ck.sph(0.135 * H, (0, 0.01 * H, 0), pa, scale=(1.05, 0.55, 0.78), parent=body, name="_gp")
    t = ck.cyl(0.15 * H, 0.13 * H, 0.32 * H, (0, 0.17 * H, 0), tp, parent=body, segs=16, name="_gp")
    t.data.transform(Matrix.Diagonal((1, 0.74, 1, 1)))
    ck.sph(0.15 * H, (0, 0.33 * H, 0), tp, scale=(1, 0.42, 0.74), parent=body, name="_gp")
    ck.sph(0.12 * H, (0, 0.12 * H, 0.045 * H), tp, scale=(1.05, 1, 0.55), parent=body, name="_gp")
    for s, a in ((-1, (armR[0], 0, -armR[1])), (1, (armL[0], 0, armL[1]))):
        ap = ck.empty("_gp_arm", (s * 0.185 * H, 0.31 * H, 0), rot=a, parent=body)
        ck.cyl(0.045 * H, 0.04 * H, 0.29 * H, (0, -0.145 * H, 0), tp, parent=ap, segs=10, name="_gp")
        ck.sph(0.045 * H, (0, -0.30 * H, 0), sk, parent=ap, name="_gp")
    head = ck.empty("_gp_head", (0, 0.36 * H, 0), parent=body)
    hs, hy = 0.115 * H, 0.05 * H + 0.115 * H
    ck.cyl(0.04 * H, 0.045 * H, 0.07 * H, (0, 0.02 * H, 0), sk, parent=head, segs=10, name="_gp")
    ck.sph(hs, (0, hy, 0), sk, parent=head, name="_gp")
    ck.sph(hs * 0.6, (0, hy - hs * 0.7, hs * 0.35), hr, scale=(1, 1.1, 0.7), parent=head, name="_gp")
    ck.sph(hs * 0.92, (0, hy + hs * 0.15, 0), ck.clay("#3a4a2a"), parent=head, name="_gp")
    ck.box(hs * 1.9, hs * 1.7, hs * 0.45, (0, hy - hs * 0.55, -hs * 0.72), hr, parent=head, name="_gp")
    ck.sph(0.022 * H, (0, hy - 0.005 * H, 0.114 * H), sk, parent=head, name="_gp")
    for s in (-1, 1):
        ck.sph(0.026 * H, (s * 0.042 * H, hy + 0.02 * H, 0.093 * H), ck.clay("#f8f6f0"), parent=head, name="_gp")


if "--no-preview" not in sys.argv:
    context()
    gary_proxy()
    ck.preview("gary_spot", views=[
        {"eye": (-2.5, 2.6, 5.5), "look": (-3.6, 0.6, 0.8), "lens": 30},
        {"eye": (-1.4, 1.5, 4.2), "look": (-3.3, 0.5, 0.75), "lens": 43},
        {"eye": (-3.0, 0.75, 2.6), "look": (-3.2, 0.35, 0.7), "lens": 28},
        {"eye": (-5.0, 1.9, 3.6), "look": (-6.4, 0.7, 0.9), "lens": 32}])
    ck.preview("gary_spot_b", views=[
        {"eye": (0.6, 1.5, 3.3), "look": (-1.3, 0.55, 0.8), "lens": 32},
        {"eye": (-5.1, 1.75, 3.0), "look": (-5.95, 0.85, 1.1), "lens": 45},
        {"eye": (-3.0, 2.2, -2.6), "look": (-3.2, 0.4, 0.7), "lens": 28},
        {"eye": (-3.3, 1.0, -0.9), "look": (-3.8, 0.2, 0.55), "lens": 35}])
    # arms up: smoking and waving
    for o in list(bpy.context.scene.objects):
        if o.name.startswith("_gp"):
            bpy.data.objects.remove(o)
    gary_proxy(armR=(-2.6, 0.35), armL=(-2.5, 0.4))
    ck.preview("gary_spot_c", views=[
        {"eye": (-2.5, 2.6, 5.5), "look": (-3.3, 0.5, 0.8), "lens": 40},
        {"eye": (-1.4, 1.5, 4.2), "look": (-3.3, 0.5, 0.75), "lens": 43},
        {"eye": (-5.2, 1.2, 0.75), "look": (-3.2, 0.45, 0.75), "lens": 35},
        {"eye": (-3.2, 3.4, 0.76), "look": (-3.2, 0.3, 0.75), "lens": 30}])
