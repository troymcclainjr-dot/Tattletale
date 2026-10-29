"""Payphone: post, blue steel housing with keypad, coin slot and return, armored cord, handset, steel hood, PHONE sign, taped OUT OF ORDER note."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

FONT_HAND = r"C:\Windows\Fonts\segoeprb.ttf"   # marker handwriting for the taped note


# ------------------------------------------------------------------ local helpers (claykit has no lathe/sweep/prism)
def _new_obj(name, bm, m, parent, smooth_deg=40):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    ck.smooth(o, smooth_deg)
    if parent is not None:
        o.parent = parent
        o.matrix_parent_inverse = Matrix.Identity(4)
    return o


def anchor(name, parent, m):
    """An empty mesh at the parent's origin to join parts into (keeps exported nodes un-rotated)."""
    o = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    o.parent = parent
    return o


def rrect(w, h, r, n=4):
    """Rounded-rectangle outline, CCW, centered. r = radius or (bl, br, tr, tl)."""
    if not hasattr(r, "__len__"):
        r = (r, r, r, r)
    pts = []
    for cx, cy, a0, rr in ((w / 2 - r[1], -h / 2 + r[1], -90, r[1]), (w / 2 - r[2], h / 2 - r[2], 0, r[2]),
                           (-w / 2 + r[3], h / 2 - r[3], 90, r[3]), (-w / 2 + r[0], -h / 2 + r[0], 180, r[0])):
        if rr <= 1e-5:
            pts.append((cx, cy))
            continue
        k = max(1, int(n * rr / max(r)) if max(r) > 0 else 1)
        for i in range(k + 1):
            a = math.radians(a0 + 90 * i / k)
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def star(R, r, n=5, a0=90):
    return [((R if i % 2 == 0 else r) * math.cos(math.radians(a0 + 180 * i / n)),
             (R if i % 2 == 0 else r) * math.sin(math.radians(a0 + 180 * i / n))) for i in range(2 * n)]


def blob(r, n, jit, rnd):
    return [(r * (1 + rnd.uniform(-jit, jit)) * math.cos(2 * math.pi * i / n),
             r * (1 + rnd.uniform(-jit, jit)) * math.sin(2 * math.pi * i / n)) for i in range(n)]


def prism(outline, t, pos, m, rot=None, parent=None, name="prism", plane="xy", bevel=0.0, segs=2):
    """Extrude a 2D outline by thickness t (centered). plane 'xy': faces game +z; 'zy': outline (z, y),
    extruded along x; 'xz': outline (x, z), extruded along y (a flat plate)."""
    def g(u, v, w):
        if plane == "xy":
            return ck.G(u, v, w)
        if plane == "zy":
            return ck.G(w, v, u)
        return ck.G(u, w, v)
    bm = bmesh.new()
    F = [bm.verts.new(g(u, v, t / 2)) for u, v in outline]
    B = [bm.verts.new(g(u, v, -t / 2)) for u, v in outline]
    bm.faces.new(F)
    bm.faces.new(list(reversed(B)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((F[i], B[i], B[j], F[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _new_obj(name, bm, m, None)
    if bevel > 0:
        ck.bevel_obj(o, bevel, segs)
    return ck._place(o, pos, rot, parent)


def lathe(profile, pos, m, rot=None, parent=None, name="lathe", segs=16, smooth_deg=50):
    """Revolve [(r, y), ...] around the game y axis (y=0 at pos). r=0 makes a pole.
    Walk the outside upward (and an inner wall downward) so normals face out."""
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new(ck.G(0, y, 0))])
        else:
            rings.append([bm.verts.new(ck.G(r * math.cos(2 * math.pi * i / segs), y, r * math.sin(2 * math.pi * i / segs)))
                          for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], b[0], a[j]))
            else:
                bm.faces.new((a[i], b[i], b[j], a[j]))
    o = _new_obj(name, bm, m, None, smooth_deg)
    return ck._place(o, pos, rot, parent)


def _catmull(pts, n_per):
    P = [Vector(p) for p in pts]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n_per):
            t = k / n_per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return out


def _resample(path, ds):
    L = [0.0]
    for a, b in zip(path, path[1:]):
        L.append(L[-1] + (b - a).length)
    n = max(2, int(round(L[-1] / ds)) + 1)
    out, j = [], 0
    for i in range(n):
        s = L[-1] * i / (n - 1)
        while j < len(L) - 2 and L[j + 1] < s:
            j += 1
        t = (s - L[j]) / max(1e-9, L[j + 1] - L[j])
        out.append(path[j].lerp(path[j + 1], min(1.0, max(0.0, t))))
    return out


def tube(pts, r, m, parent=None, name="tube", segs=8, n_per=6, rfun=None, caps=True, ds=None):
    """Sweep a circle along a Catmull-Rom curve through pts (parent-local game coords).
    rfun(s, L) -> radius at arc length s (for ribbed cords). ds resamples evenly by arc length."""
    path = _catmull(pts, n_per if not ds else 24)
    if ds:
        path = _resample(path, ds)
    L = [0.0]
    for a, b in zip(path, path[1:]):
        L.append(L[-1] + (b - a).length)
    T = []
    for i in range(len(path)):
        a = path[max(0, i - 1)]
        b = path[min(len(path) - 1, i + 1)]
        T.append((b - a).normalized())
    up = Vector((0, 1, 0)) if abs(T[0].y) < 0.9 else Vector((1, 0, 0))
    N = T[0].cross(up).normalized()
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        if i > 0:
            N = (N - T[i] * N.dot(T[i])).normalized()
        Bv = T[i].cross(N)
        rr = rfun(L[i], L[-1]) if rfun else r
        rings.append([bm.verts.new(ck.G(p + (N * math.cos(2 * math.pi * k / segs) + Bv * math.sin(2 * math.pi * k / segs)) * rr))
                      for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((a[k], a[j], b[j], b[k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_obj(name, bm, m, parent, 60)


def sheet(w, h, nx, ny, center, ang, zfun, m, parent=None, name="sheet", thick=0.002):
    """A thin flat sheet (paper, tape) in the game xy plane facing +z, rotated by ang around z.
    zfun(x, y) gives the front surface z at each grid point (drape, curl). Solidified backwards."""
    bm = bmesh.new()
    ca, sa = math.cos(ang), math.sin(ang)
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u = -w / 2 + w * i / nx
            v = -h / 2 + h * j / ny
            x = center[0] + u * ca - v * sa
            y = center[1] + u * sa + v * ca
            row.append(bm.verts.new(ck.G(x, y, zfun(x, y))))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    o = _new_obj(name, bm, m, parent, 60)
    md = o.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = -1.0
    ck._apply_modifiers(o)
    ck.smooth(o, 60)
    return o


def _islands(bm):
    bm.verts.ensure_lookup_table()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        seen.add(v.index)
        stack, comp = [v], []
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        out.append(comp)
    return out


def jtext(s, pos, m, parent=None, name="text", font="impact", size=0.2, depth=0.006, rot=None, fit=None,
          res=2, bevel=0.0015, jrot=0.0, jpos=0.0, jscale=0.0, wob=0.0, seed=1, line_spacing=1.0):
    """Low-poly raised lettering, centered on pos, facing game +z. Per-letter jitter (jrot rad,
    jpos x size, jscale) and outline wobble (m) give a hand-painted look. fit=(w, h) scales to fit."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size = size
    cu.resolution_u = res
    cu.extrude = depth / 2
    cu.bevel_depth = bevel
    cu.bevel_resolution = 0
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_line = line_spacing
    try:
        cu.fill_mode = "FRONT"
    except Exception:
        pass
    tmp = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=size * 1e-4)
    rnd = random.Random(seed)
    if jrot or jpos or jscale:
        isl = _islands(bm)
        # caps, walls and holes of one glyph can be separate islands: group by bbox containment
        boxes = [(min(v.co.x for v in c), max(v.co.x for v in c), min(v.co.y for v in c), max(v.co.y for v in c)) for c in isl]
        par = list(range(len(isl)))

        def find(i):
            while par[i] != i:
                par[i] = par[par[i]]
                i = par[i]
            return i
        for i, (x0, x1, y0, y1) in enumerate(boxes):
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            for j, (a0, a1, b0, b1) in enumerate(boxes):
                if j != i and a0 <= cx <= a1 and b0 <= cy <= b1 and (a1 - a0) * (b1 - b0) >= 0.6 * (x1 - x0) * (y1 - y0):
                    par[find(i)] = find(j)
        groups = {}
        for i, comp in enumerate(isl):
            groups.setdefault(find(i), []).extend(comp)
        isl = list(groups.values())
        isl.sort(key=lambda c: min(v.co.x for v in c) - 10 * max(v.co.y for v in c))
        for comp in isl:
            xs = [v.co.x for v in comp]
            ys = [v.co.y for v in comp]
            c = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, 0))
            R = Matrix.Rotation(rnd.uniform(-jrot, jrot), 3, "Z")
            sc = 1 + rnd.uniform(-jscale, jscale)
            off = Vector((rnd.uniform(-jpos, jpos) * size, rnd.uniform(-jpos, jpos) * size, 0))
            for v in comp:
                p = v.co - c
                v.co = c + R @ Vector((p.x * sc, p.y * sc, p.z)) + off
    if wob:
        o3 = Vector((seed * 3.1, seed * 1.7, 0))
        for v in bm.verts:
            q = Vector((v.co.x, v.co.y, 0)) * 28 + o3
            v.co.x += noise.noise(q) * wob
            v.co.y += noise.noise(q + Vector((17, 5, 0))) * wob
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = 1.0
    if fit:
        k = min(fit[0] / (max(xs) - min(xs)) if fit[0] else 1e9, fit[1] / (max(ys) - min(ys)) if fit[1] else 1e9)
    for v in bm.verts:
        v.co.x = (v.co.x - cx) * k
        v.co.y = (v.co.y - cy) * k
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    ck.smooth(o, 35)
    print(f"[text] {name} {s!r}: {sum(len(p.vertices) - 2 for p in me.polygons)} tris")
    return ck._place(o, pos, rot, parent)


def clear_preview():
    """ck.preview adds a sun, ground and camera each call; drop them before the next sheet."""
    for o in list(bpy.context.scene.objects):
        if o.name.startswith(("sun", "_ground", "cam")):
            bpy.data.objects.remove(o)


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o and o.type == "MESH")


# ------------------------------------------------------------------ materials
ck.reset()
random.seed(11)
STEEL = ck.clay("phone_post", 0.4)          # post (JS)
BLUE = ck.clay("phone_blue", 0.35)          # housing (JS)
PLATE = ck.clay("phone_plate", 0.3)         # faceplate (JS)
HOOD = ck.clay("fence", 0.45)               # steel hood
CHROME = ck.metal("alu", 0.3)               # coin slot, return, hook
CORD = ck.gloss("#b8bec6", 0.3)             # armored cord: polished steel that stays light in engine
DARK = ck.clay("pole", 0.5)                 # keypad bezel, cradle, slots, bolts
IRON = SLOT = DARK
HANDSET = ck.gloss("black", 0.35)
CREAM = ck.clay("cream", 0.6)                # keys, PHONE letters, instruction card, tape
NAVY = ck.clay("navy", 0.8)
CARD = CREAM
NOTE = ck.clay("#f2d24a", 0.85)             # OUT OF ORDER paper (JS bg)
MARKER = ck.clay("red", 0.6)                # OUT OF ORDER writing (JS fg)
TAPE = CREAM
PINK = ck.clay("pink", 0.5)
CYAN = ck.clay("cyan", 0.5)
CHIP = HOOD                                 # paint chips show bare steel

root = ck.empty("Payphone", (0, 0, 0))
P = dict(parent=root)

# ------------------------------------------------------------------ post (JS: r .06, 1.3 tall at (0, .65, -.05))
post = [anchor("Payphone_Body", root, BLUE), ck.cyl(0.06, 0.06, 1.3, (0, 0.65, -0.05), STEEL, name="Post", segs=16, **P)]
ck.wobble(post[1], 0.003, 1.2, seed=3)
post.append(ck.cyl(0.072, 0.085, 0.06, (0, 0.03, -0.05), STEEL, name="PostFoot", segs=16, **P))
post.append(ck.bevel_obj(ck.cyl(0.112, 0.116, 0.018, (0, 0.056, -0.05), STEEL, name="PostFlange", segs=16, **P), 0.005, 1))
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    post.append(ck.cyl(0.013, 0.014, 0.012, (0.088 * math.cos(a), 0.07, -0.05 + 0.088 * math.sin(a)), IRON,
                       rot=(0, a, 0), name="PostBolt", segs=6, **P))
post.append(ck.bevel_obj(ck.cyl(0.07, 0.074, 0.05, (0, 1.012, -0.05), STEEL, name="PostCollar", segs=14, **P), 0.006, 1))
post.append(ck.box(0.17, 0.014, 0.17, (0, 1.044, -0.05), STEEL, name="MountPlate", bevel=0.005, bevel_segs=1, **P))
gum = ck.sph(0.016, (0.047, 0.83, -0.012), PINK, scale=(1.15, 0.85, 0.7), name="Gum", segs=8, rings=6, **P)
ck.lumpy(gum, 0.004, 90, seed=2)
post.append(gum)

# ------------------------------------------------------------------ housing (JS: .55 x .8 x .3 at (0, 1.45, 0)), front face z = .15
FZ = 0.15
housing = [ck.box(0.55, 0.8, 0.3, (0, 1.45, 0), BLUE, name="Housing", bevel=0.03, bevel_segs=3, **P)]
ck.wobble(housing[0], 0.002, 2.0, seed=5)
for sx in (-1, 1):  # tamper screws
    housing.append(ck.cyl(0.009, 0.009, 0.006, (sx * 0.232, 1.812, FZ + 0.002), CHROME, rot=(math.pi / 2, 0, 0), name="Screw", segs=6, **P))
# faceplate (JS metal plate .38 x .24 at (0, 1.6, .16); nudged right/up to clear the handset and 12-key pad)
housing.append(prism(rrect(0.35, 0.2, 0.02), 0.016, (0.045, 1.635, FZ + 0.008), PLATE, name="Faceplate", bevel=0.004, segs=1, **P))
housing.append(prism(rrect(0.2, 0.13, 0.008), 0.004, (0.0, 1.635, FZ + 0.017), CARD, name="InstructionCard", **P))
housing.append(ck.box(0.17, 0.018, 0.003, (0.0, 1.681, FZ + 0.0195), MARKER, name="CardHeader", **P))
for i, (ln, dx) in enumerate(((0.15, 0.0), (0.12, -0.015), (0.15, 0.0), (0.09, -0.03))):
    housing.append(ck.box(ln, 0.007, 0.002, (dx, 1.652 - i * 0.017, FZ + 0.019), NAVY, name="CardLine", **P))
for sx in (-1, 1):
    for sy in (-1, 1):
        housing.append(ck.cyl(0.006, 0.006, 0.004, (0.045 + sx * 0.158, 1.635 + sy * 0.083, FZ + 0.017), CHROME,
                              rot=(math.pi / 2, 0, 0), name="PlateScrew", segs=6, **P))
# coin slot
housing.append(prism(rrect(0.06, 0.1, 0.014), 0.012, (0.17, 1.635, FZ + 0.02), CHROME, name="CoinSlotBoss", bevel=0.003, segs=1, **P))
housing.append(ck.box(0.009, 0.052, 0.004, (0.17, 1.645, FZ + 0.0265), SLOT, name="CoinSlot", **P))
# keypad: bezel + 3 x 4 keys (JS had 6 keys around (0, 1.32, .16))
housing.append(prism(rrect(0.215, 0.2, 0.016), 0.014, (0.035, 1.42, FZ + 0.007), DARK, name="KeypadBezel", bevel=0.003, segs=1, **P))
for r in range(4):
    for c in range(3):
        housing.append(ck.box(0.046, 0.034, 0.014, (0.035 + (c - 1) * 0.062, 1.486 - r * 0.044, FZ + 0.019), CREAM,
                              name="Key", bevel=0.005, bevel_segs=1, **P))
# coin return, right of the keypad
housing.append(prism(rrect(0.075, 0.085, 0.012), 0.03, (0.2, 1.40, FZ + 0.015), CHROME, name="CoinReturn", bevel=0.004, segs=1, **P))
housing.append(prism(rrect(0.05, 0.032, 0.006), 0.004, (0.2, 1.407, FZ + 0.0305), SLOT, name="CoinReturnHole", **P))
housing.append(ck.box(0.054, 0.026, 0.006, (0.2, 1.378, FZ + 0.034), CHROME, rot=(-0.4, 0, 0), name="CoinFlap", bevel=0.002, bevel_segs=1, **P))
# handset cradle and hook (handset hangs at x -.19, JS -.2); the cradle stops above the taped note
housing.append(prism(rrect(0.11, 0.39, 0.025), 0.014, (-0.19, 1.485, FZ + 0.007), DARK, name="Cradle", bevel=0.003, segs=1, **P))
housing.append(ck.box(0.08, 0.03, 0.07, (-0.19, 1.655, FZ + 0.045), CHROME, name="Hook", bevel=0.009, bevel_segs=2, **P))
housing.append(ck.cyl(0.021, 0.021, 0.016, (-0.281, 1.13, 0.03), CHROME, rot=(0, 0, math.pi / 2), name="Grommet", segs=10, **P))
# back: mounting bolts and a blank service plate
for sx in (-1, 1):
    for y in (1.14, 1.76):
        housing.append(ck.cyl(0.011, 0.011, 0.007, (sx * 0.2, y, -0.1515), IRON, rot=(math.pi / 2, 0, 0), name="BackBolt", segs=6, **P))
housing.append(prism(rrect(0.13, 0.07, 0.01, n=2), 0.004, (0.0, 1.62, -0.1505), PLATE, name="ServicePlate", **P))
# stickers on the housing's sides
housing.append(prism(star(0.034, 0.015), 0.002, (0.2758, 1.6, 0.04), PINK, name="StarSticker", plane="zy", **P))
housing.append(prism(blob(0.028, 10, 0.0, random.Random(1)), 0.002, (-0.2758, 1.42, -0.03), CYAN, name="DotSticker", plane="zy", **P))
housing.append(prism(blob(0.03, 9, 0.35, random.Random(9)), 0.002, (-0.2758, 1.66, 0.05), CARD, name="TornSticker", plane="zy", **P))
# paint chips showing the steel underneath
rnd = random.Random(4)
for (x, y, z, plane) in ((-0.2, 1.80, FZ + 0.0008, "xy"), (0.238, 1.775, FZ + 0.0008, "xy"),
                         (1.22, 0.06, 0.2758, "zy"), (1.55, -0.07, 0.2758, "zy"), (1.70, 0.09, -0.2758, "zy")):
    if plane == "xy":
        housing.append(prism(blob(0.011, 7, 0.45, rnd), 0.0015, (x, y, z), CHIP, rot=(0, 0, rnd.uniform(0, 3)), name="Chip", **P))
    else:
        housing.append(prism(blob(0.012, 7, 0.45, rnd), 0.0015, (z, x, y), CHIP, name="Chip", plane="zy", **P))

# ------------------------------------------------------------------ handset (JS: .1 x .42 x .1 at (-.2, 1.42, .18)) and armored cord
HX = -0.19
cup = [(0.0, 0.0), (0.040, 0.0), (0.047, 0.005), (0.048, 0.018), (0.042, 0.030), (0.026, 0.039), (0.0, 0.042)]
hs = [anchor("Payphone_Handset", root, HANDSET), lathe(cup, (HX, 1.588, 0.17), HANDSET, rot=(math.pi / 2, 0, 0), name="Earpiece", segs=12, **P),
      lathe(cup, (HX, 1.254, 0.17), HANDSET, rot=(math.pi / 2, 0, 0), name="Mouthpiece", segs=12, **P)]
hs.append(tube([(HX, 1.595, 0.2), (HX, 1.50, 0.224), (HX, 1.42, 0.231), (HX, 1.34, 0.224), (HX, 1.247, 0.2)], 0.021, HANDSET,
               name="HandsetGrip", segs=8, n_per=4, rfun=lambda s, L: 0.021 - 0.003 * math.sin(math.pi * s / L), **P))
hs.append(ck.cyl(0.011, 0.016, 0.032, (HX, 1.197, 0.205), HANDSET, name="StrainRelief", segs=8, **P))
cord_pts = [(HX, 1.184, 0.205), (HX - 0.001, 1.12, 0.212), (HX - 0.008, 1.035, 0.218), (HX - 0.032, 0.978, 0.205),
            (HX - 0.072, 0.962, 0.166), (HX - 0.106, 0.985, 0.112), (HX - 0.118, 1.045, 0.062), (HX - 0.108, 1.103, 0.034),
            (-0.276, 1.13, 0.03)]
rib = lambda s, L: 0.0105 * (1.0 + 0.2 * math.cos(2 * math.pi * s / 0.024))
hs.append(tube(cord_pts, 0.011, CORD, name="ArmoredCord", segs=6, rfun=rib, ds=0.008, **P))

# ------------------------------------------------------------------ little steel rain hood: roof on the housing, front lip, side cheeks
hood = [prism(rrect(0.66, 0.435, 0.03), 0.025, (0, 1.8625, 0.0525), HOOD, name="HoodRoof", plane="xz", bevel=0.008, segs=2, **P)]
hood.append(ck.box(0.66, 0.042, 0.018, (0, 1.846, 0.261), HOOD, name="HoodLip", bevel=0.007, bevel_segs=2, **P))
for sx in (-1, 1):
    # outline in (z, y): a cheek under each side of the roof, its front-bottom corner swept up
    hood.append(prism(rrect(0.42, 0.15, (0.0, 0.14, 0.0, 0.0), n=5), 0.018, (sx * 0.309, 1.776, 0.06), HOOD,
                      name="HoodCheek", plane="zy", bevel=0.006, segs=1, **P))
    hood.append(ck.cyl(0.012, 0.012, 0.032, (sx * 0.17, 1.889, 0.16), HOOD, name="SignLeg", segs=8, **P))

# ------------------------------------------------------------------ PHONE sign (JS: .5 x .13 at (0, 1.97, .16), cream on navy), on two legs
sign = [ck.box(0.5, 0.13, 0.06, (0, 1.97, 0.16), NAVY, name="SignBox", bevel=0.016, bevel_segs=3, **P)]
sign.append(jtext("PHONE", (0, 1.969, 0.1915), CREAM, name="SignText", font="impact", size=0.1, depth=0.005,
                  fit=(0.42, 0.086), res=2, bevel=0.0, **P))

# ------------------------------------------------------------------ OUT OF ORDER note, taped on (JS: .42 x .24 at (.03, 1.18, .155), tilted .12)
NC, NA, NW, NH = (0.03, 1.18), 0.12, 0.42, 0.24


def note_z(x, y):
    z = FZ + 0.0028 + 0.0006 * noise.noise(Vector((x * 30, y * 30, 0.5)))
    if y < 1.08:  # loose bottom corner curls off the housing's rounded bottom edge
        z += 16.0 * (1.08 - y) ** 2
    return z


def note_dist(x, y):
    """Signed distance from the note's edge (negative inside)."""
    ca, sa = math.cos(-NA), math.sin(-NA)
    u = (x - NC[0]) * ca - (y - NC[1]) * sa
    v = (x - NC[0]) * sa + (y - NC[1]) * ca
    return max(abs(u) - NW / 2, abs(v) - NH / 2)


def tape_z(x, y):
    d = note_dist(x, y)
    f = 1.0 if d <= 0 else max(0.0, 1.0 - d / 0.012)   # steps down just outside the paper edge
    f = f * f * (3 - 2 * f)
    return FZ + 0.0009 + f * (note_z(x, y) - FZ + 0.0003)


note = [anchor("Payphone_OutOfOrder", root, NOTE), sheet(NW, NH, 8, 6, NC, NA, note_z, NOTE, name="Note", thick=0.002, **P)]
note.append(jtext("OUT OF\nORDER", (0.03, 1.198, FZ + 0.0035), MARKER, name="NoteText", font=FONT_HAND, size=0.1,
                  depth=0.003, rot=(0, 0, NA), fit=(0.34, 0.175), res=1, bevel=0.0, jrot=0.07, jpos=0.04,
                  jscale=0.06, wob=0.0012, seed=4, line_spacing=0.86, **P))
for tu, ta in ((-0.115, 0.5), (NW / 2, -0.6)):  # the top-left corner hides behind the handset, so tape the top edge there
    ca, sa = math.cos(NA), math.sin(NA)
    u, v = tu, NH / 2 - 0.004
    c = (NC[0] + u * ca - v * sa, NC[1] + u * sa + v * ca)
    note.append(sheet(0.085, 0.027, 8, 1, c, NA + ta, tape_z, TAPE, name="Tape", thick=0.0008, **P))

# ------------------------------------------------------------------ join into a few meshes and export
parts = {"Payphone_Body": post + housing + hood + sign, "Payphone_Handset": hs, "Payphone_OutOfOrder": note}
for nm, objs in parts.items():
    print(f"[payphone] {nm}: {tris(objs)} tris")
    ck.join(objs, nm)
ck.export("payphone")
print("[payphone] objects:", sorted(o.name for o in bpy.context.scene.objects))
ck.preview("payphone")
clear_preview()
ck.preview("payphone_close", views=[
    {"eye": (0.35, 1.62, 1.25), "look": (0.0, 1.45, 0.1), "lens": 50},
    {"eye": (2.6, 3.2, 5.0), "look": (0.0, 1.25, 0.0), "lens": 35},
    {"eye": (0.06, 1.25, 0.75), "look": (0.03, 1.2, 0.15), "lens": 60},
    {"eye": (1.6, 1.5, -0.9), "look": (0.0, 1.2, 0.0), "lens": 40},
])
