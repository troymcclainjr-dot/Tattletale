"""Lemonade stand: kid-built plank stand, painted LEMONADE 25 CENTS, striped awning, pitcher, cups, coin jar, lemons, toggled SignOpen / SignClosed."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

FONT_KID = r"C:\Windows\Fonts\comicbd.ttf"   # chunky kid lettering, wobbled per letter below


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


def ellipse(rx, ry, n=12, nub=0.0):
    """Ellipse outline; nub > 0 pinches the x ends into lemon tips."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c = math.cos(a)
        out.append((rx * c * (1 + nub * abs(c) ** 8), ry * math.sin(a)))
    return out


def jitter(outline, amt, rnd):
    return [(u + rnd.uniform(-amt, amt), v + rnd.uniform(-amt, amt)) for u, v in outline]


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


def lathe(profile, pos, m, rot=None, parent=None, name="lathe", segs=16, smooth_deg=50, deform=None):
    """Revolve [(r, y), ...] around the game y axis (y=0 at pos). r=0 makes a pole.
    Walk the outside upward (and an inner wall downward) so normals face out.
    deform(x, y, z) -> (x, y, z) reshapes the result in local game coords (spouts, ovals)."""
    bm = bmesh.new()
    rings = []

    def vert(x, y, z):
        if deform:
            x, y, z = deform(x, y, z)
        return bm.verts.new(ck.G(x, y, z))
    for r, y in profile:
        if r <= 1e-6:
            rings.append([vert(0, y, 0)])
        else:
            rings.append([vert(r * math.cos(2 * math.pi * i / segs), y, r * math.sin(2 * math.pi * i / segs)) for i in range(segs)])
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


def tube(pts, r, m, parent=None, name="tube", segs=8, n_per=6, caps=True):
    """Sweep a circle along a Catmull-Rom curve through pts (parent-local game coords)."""
    path = _catmull(pts, n_per)
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
        rings.append([bm.verts.new(ck.G(p + (N * math.cos(2 * math.pi * k / segs) + Bv * math.sin(2 * math.pi * k / segs)) * r))
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


def grid_sheet(rows, m, parent=None, name="sheet", thick=0.006):
    """A cloth-like sheet through a grid of game points rows[j][i]; solidified (two-sided)."""
    bm = bmesh.new()
    V = [[bm.verts.new(ck.G(p)) for p in row] for row in rows]
    for j in range(len(V) - 1):
        for i in range(len(V[j]) - 1):
            bm.faces.new((V[j][i], V[j + 1][i], V[j + 1][i + 1], V[j][i + 1]))
    o = _new_obj(name, bm, m, parent, 50)
    md = o.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = -1.0
    ck._apply_modifiers(o)
    ck.smooth(o, 50)
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


LETTERS = []   # (cx, ymin, w) of each glyph of the last jtext, in its local frame (for paint drips)


def jtext(s, pos, m, parent=None, name="text", font="impact", size=0.2, depth=0.006, rot=None, fit=None,
          res=2, bevel=0.0, jrot=0.0, jpos=0.0, jscale=0.0, wob=0.0, seed=1, line_spacing=1.0):
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
    isl = sorted(groups.values(), key=lambda c: min(v.co.x for v in c) - 10 * max(v.co.y for v in c))
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
    LETTERS[:] = [((min(v.co.x for v in c) + max(v.co.x for v in c)) / 2, min(v.co.y for v in c),
                   max(v.co.x for v in c) - min(v.co.x for v in c)) for c in isl]
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    ck.assign(o, m)
    ck.smooth(o, 35)
    print(f"[text] {name} {s!r}: {sum(len(p.vertices) - 2 for p in me.polygons)} tris")
    return ck._place(o, pos, rot, parent)


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o and o.type == "MESH")


def clear_preview():
    """ck.preview adds a sun, ground and camera each call; drop them before the next sheet."""
    for o in list(bpy.context.scene.objects):
        if o.name.startswith(("sun", "_ground", "cam")):
            bpy.data.objects.remove(o)


def placed(objs, pos, rot, parent, name):
    """Join parts built around the origin and place the result (pos/rot local to parent)."""
    o = ck.join(objs, name)
    return ck._place(o, pos, rot, parent)


# ------------------------------------------------------------------ materials
ck.reset()
random.seed(17)
WOOD = ck.clay("wood", 0.7)                 # JS wood
WOOD_D = ck.clay("#bf9656", 0.72)           # board-to-board variation
WOOD_L = ck.clay("#d1ab6b", 0.7)
KNOT = ck.clay("#9a7448", 0.8)
NAIL = ck.clay("iron", 0.6)
PAINT = ck.clay("red", 0.85)                # LEMONADE 25 CENTS (JS fg) and the awning's red stripes
PAINT_Y = ck.clay("#f2d24a", 0.75)
LEAF = ck.clay("grass", 0.7)
STRIPE_C = ck.clay("cream", 0.88)
LEMONADE = ck.gloss("lane_yellow", 0.2)     # deeper than the JS #f8e04a so it survives the glass and tonemapping
GLASS = ck.glass("#eaf6f4", 0.14)
GLASS_H = ck.glass("#eaf6f4", 0.35)
LEMON = ck.clay("lemon", 0.6)
LEMON_IN = ck.clay("#f8eca0", 0.45)
PITH = ck.clay("cream", 0.6)
CUP = PITH                                  # JS cups are cream r.3; rougher here because r.3 mirrored the sky blue
SILVER = ck.metal("alu", 0.3)
COOLER = ck.clay("maildrop_blue", 0.5)
COOLER_LID = PITH
COPPER = ck.metal("#b8743a", 0.35)
# toggled signs: each has materials nothing else uses
OPEN_BG = ck.clay("#f2d24a", 0.8)
OPEN_FG = ck.clay("navy", 0.8)
CLOSED_BG = ck.clay("red", 0.8)
CLOSED_FG = ck.clay("cream", 0.8)
CLOSED_NAIL = ck.clay("iron", 0.61)

root = ck.empty("LemonadeStand", (0, 0, 0))
P = dict(parent=root)

# ------------------------------------------------------------------ frame (JS: tabletop 1.4x.06x.6 at y .8, front 1.4x.75 at z .3, posts at x +-.67 z -.25, board 1.5x.3 at y 1.6)
frame = [anchor("LemonadeStand_Body", root, WOOD)]
for sx in (-1, 1):  # front legs behind the planks
    frame.append(ck.box(0.05, 0.785, 0.05, (sx * 0.645, 0.3925, 0.255), WOOD_D, name="FrontLeg", bevel=0.008, bevel_segs=1, **P))
# front panel: three planks, a bit crooked, with gaps (bottom plank clears the sidewalk)
PLANKS = [(0.185, 0.232, 1.42, -0.008, 0.005, WOOD), (0.429, 0.232, 1.40, 0.010, -0.006, WOOD_L), (0.670, 0.226, 1.43, -0.004, 0.004, WOOD_D)]
for i, (y, h, ln, dx, rz, mt) in enumerate(PLANKS):
    p = ck.box(ln, h, 0.035, (dx, y, 0.2975), mt, rot=(0, 0, rz), name="FrontPlank", bevel=0.008, bevel_segs=2, **P)
    ck.wobble(p, 0.0015, 1.3, seed=i + 1)
    frame.append(p)
# tabletop: two boards butting against the back posts
frame.append(ck.box(1.46, 0.045, 0.33, (0.006, 0.8075, 0.17), WOOD_L, rot=(0, 0.006, 0), name="TopBoardFront", bevel=0.008, bevel_segs=2, **P))
frame.append(ck.box(1.44, 0.045, 0.205, (-0.01, 0.8075, -0.11), WOOD, rot=(0, -0.008, 0), name="TopBoardBack", bevel=0.008, bevel_segs=2, **P))
for sx in (-1, 1):  # back posts run up to carry the awning
    post = ck.box(0.06, 1.99, 0.06, (sx * 0.67, 0.995, -0.25), WOOD_D, rot=(0, 0, -sx * 0.006), name="BackPost", bevel=0.008, bevel_segs=1, **P)
    ck.wobble(post, 0.004, 0.8, seed=7 + sx)
    frame.append(post)
    frame.append(ck.box(0.03, 0.05, 0.45, (sx * 0.655, 0.76, 0.005), WOOD, name="SideApron", bevel=0.006, bevel_segs=1, **P))
    frame.append(ck.box(0.03, 0.05, 0.45, (sx * 0.655, 0.2, 0.005), WOOD_L, rot=(sx * 0.04, 0, 0), name="SideStretcher", bevel=0.006, bevel_segs=1, **P))
frame.append(ck.box(1.36, 0.04, 0.03, (0, 0.765, -0.205), WOOD_D, name="BackRail", bevel=0.006, bevel_segs=1, **P))
BOARD_RZ = 0.012
frame.append(ck.box(1.5, 0.3, 0.035, (0.005, 1.6, -0.2025), WOOD_L, rot=(0, 0, BOARD_RZ), name="SignBoard", bevel=0.009, bevel_segs=2, **P))
# nails
NAILS = []
for y, h, ln, dx, rz, mt in PLANKS:
    for sx in (-1, 1):
        for dy in (-0.06, 0.06):
            NAILS.append(((sx * 0.645, y + dy + sx * 0.645 * rz, 0.3155), "z"))
for sx in (-1, 1):
    for dy in (-0.08, 0.08):
        NAILS.append(((sx * 0.67, 1.6 + dy + sx * 0.67 * BOARD_RZ, -0.1845), "z"))
    for z in (0.23, 0.28):
        NAILS.append(((sx * 0.645, 0.8305, z - 0.02), "y"))
    NAILS.append(((sx * 0.6, 0.8305, -0.205), "y"))
for (x, y, z), ax in NAILS:
    rot = (math.pi / 2 + random.uniform(-0.15, 0.15), 0, 0) if ax == "z" else (random.uniform(-0.1, 0.1), 0, random.uniform(-0.1, 0.1))
    frame.append(ck.cyl(0.0065, 0.0065, 0.005, (x, y, z), NAIL, rot=rot, name="Nail", segs=6, **P))
# knots in the wood
rk = random.Random(3)
for (x, y, z, plane, a) in ((-0.25, 0.14, 0.3155, "xy", 0.2), (0.6, 0.735, 0.3155, "xy", -0.3), (-0.5, 1.55, -0.1845, "xy", 0.1)):
    frame.append(prism(jitter(ellipse(0.02, 0.009, 9), 0.002, rk), 0.004, (x, y, z), KNOT, rot=(0, 0, a), name="Knot", **P))
frame.append(prism(jitter(ellipse(0.022, 0.01, 9), 0.002, rk), 0.002, (0.18, 0.8301, 0.27), KNOT, name="Knot", plane="xz", **P))

# ------------------------------------------------------------------ painted lettering on the front planks (JS: "LEMONADE\n25 CENTS" red, ~1.25 x .55 at z .33)
FRONT = 0.315
letters = []
drips = []
# drips run from the foot of a leg (M, N), never from the middle of a bar, so no letter grows an accent
for text, (y, h, ln, dx, rz, mt), fit, seed, drip_at in (("LEMONADE", PLANKS[2], (1.2, 0.175), 5, ((2, -1, 0.05), (4, 1, 0.038))),
                                                        ("25 CENTS", PLANKS[1], (0.9, 0.165), 9, ((4, -1, 0.045),))):
    cx = dx * 0.5
    letters.append(jtext(text, (cx, y + 0.002, FRONT + 0.002), PAINT, name="Paint", font=FONT_KID, size=0.2, depth=0.008,
                         rot=(0, 0, rz), fit=fit, res=2, jrot=0.07, jpos=0.035, jscale=0.06, wob=0.0025, seed=seed, **P))
    for li, side, L in drip_at:
        lx, ly, lw = LETTERS[li]
        px = cx + lx + side * (lw / 2 - 0.016)
        top = y + 0.002 + ly + 0.008
        drips.append(prism(rrect(0.011, L, 0.0055, n=2), 0.006, (px, top - L / 2, FRONT + 0.0008), PAINT, name="Drip", **P))
        drips.append(prism(ellipse(0.0085, 0.0095, 8), 0.0065, (px, top - L, FRONT + 0.001), PAINT, name="DripBulb", **P))
letters += drips
for sx, a in ((-1, 0.35), (1, -0.25)):  # painted lemons either side of 25 CENTS
    lx, ly = sx * 0.565, 0.43
    letters.append(prism(ellipse(0.068, 0.044, 16, nub=0.16), 0.006, (lx, ly, FRONT + 0.001), PAINT_Y, rot=(0, 0, a), name="PaintLemon", **P))
    ca, sa = math.cos(a), math.sin(a)
    tip = (lx - sx * 0.07 * ca, ly - sx * 0.07 * sa)
    letters.append(prism(ellipse(0.026, 0.011, 8), 0.0065, (tip[0] + 0.006, tip[1] + 0.03, FRONT + 0.0015), LEAF,
                         rot=(0, 0, 0.6 * sx), name="PaintLeaf", **P))
    letters.append(prism(ellipse(0.016, 0.008, 8), 0.0065, (lx - 0.02, ly + 0.014, FRONT + 0.002), STRIPE_C, rot=(0, 0, a), name="PaintShine", **P))

# ------------------------------------------------------------------ striped awning over the sign board (kept high so the sign reads from the street)
awn = []
awn.append(ck.cyl(0.014, 0.014, 1.48, (0, 2.004, -0.25), WOOD, rot=(0, 0, math.pi / 2), name="AwningBackRod", segs=8, **P))
awn.append(ck.cyl(0.011, 0.011, 1.58, (0, 1.952, -0.062), WOOD, rot=(0, 0, math.pi / 2), name="AwningFrontRod", segs=8, **P))
for sx in (-1, 1):
    awn.append(tube([(sx * 0.672, 1.99, -0.25), (sx * 0.765, 1.952, -0.062)], 0.009, WOOD, name="AwningArm", segs=6, n_per=1, **P))
N_STRIPES, AW = 10, 0.78
for i in range(N_STRIPES):
    x0 = -AW + 2 * AW * i / N_STRIPES
    x1 = x0 + 2 * AW / N_STRIPES
    cols = [x0 + (x1 - x0) * k / 3 for k in range(4)]
    prof = [(-0.268, 2.004), (-0.25, 2.025), (-0.155, 1.989), (-0.062, 1.969), (-0.05, 1.952)]
    rows = [[(x, y + 0.002 * math.sin(7 * x + i), z) for x in cols] for z, y in prof]
    rows.append([(x, 1.915 - 0.028 * math.sin(math.pi * k / 3) + 0.003 * math.sin(5 * x), -0.047) for k, x in enumerate(cols)])
    awn.append(grid_sheet(rows, PAINT if i % 2 == 0 else STRIPE_C, name="AwningStripe", thick=0.006, **P))

# ------------------------------------------------------------------ toggled signs on the board's front face (JS: 1.3 x .26 at (0, 1.6, -.22))
BOARD_FRONT = -0.185
op = [anchor("SignOpen", root, OPEN_BG)]
op.append(prism(rrect(1.3, 0.26, 0.03, n=3), 0.008, (0.005, 1.6, BOARD_FRONT + 0.005), OPEN_BG, rot=(0, 0, BOARD_RZ + 0.004),
                name="OpenPlate", bevel=0.003, segs=1, **P))
op.append(jtext("OPEN", (0.005, 1.597, BOARD_FRONT + 0.0115), OPEN_FG, name="OpenText", font=FONT_KID, size=0.2, depth=0.005,
                rot=(0, 0, BOARD_RZ + 0.004), fit=(0.62, 0.17), res=2, jrot=0.06, jpos=0.03, jscale=0.05, wob=0.0025, seed=21, **P))
cl = [anchor("SignClosed", root, CLOSED_BG)]
# CLOSED is a cardboard placard hung on two nails over the board, so it never touches OPEN
cl.append(prism(jitter(rrect(1.28, 0.25, 0.02, n=2), 0.004, random.Random(5)), 0.006, (0.0, 1.598, BOARD_FRONT + 0.018), CLOSED_BG,
                rot=(0, 0, BOARD_RZ - 0.006), name="ClosedPlate", bevel=0.002, segs=1, **P))
cl.append(jtext("CLOSED", (0.0, 1.595, BOARD_FRONT + 0.0225), CLOSED_FG, name="ClosedText", font=FONT_KID, size=0.2, depth=0.005,
                rot=(0, 0, BOARD_RZ - 0.006), fit=(0.92, 0.17), res=2, jrot=0.06, jpos=0.03, jscale=0.05, wob=0.0025, seed=33, **P))
for sx in (-1, 1):
    x = sx * 0.58
    y = 1.598 + 0.1 + x * (BOARD_RZ - 0.006)
    cl.append(ck.cyl(0.0035, 0.0035, 0.024, (x, y, BOARD_FRONT + 0.009), CLOSED_NAIL, rot=(math.pi / 2, 0, 0), name="ClosedNail", segs=6, **P))
    cl.append(ck.cyl(0.008, 0.008, 0.003, (x, y, BOARD_FRONT + 0.0225), CLOSED_NAIL, rot=(math.pi / 2, 0, 0), name="ClosedNailHead", segs=8, **P))

# ------------------------------------------------------------------ on the table (top at y .83)
TOP = 0.83
goods = [anchor("LemonadeStand_Goods", root, LEMONADE)]


def lemon_slice(r=0.032, spokes=3):
    parts = [ck.cyl(r, r, 0.007, (0, 0, 0), LEMON, name="SliceRind", segs=12),
             ck.cyl(r - 0.004, r - 0.004, 0.002, (0, 0.0035, 0), LEMON_IN, name="SliceFlesh", segs=12)]
    for k in range(spokes):
        parts.append(ck.box(2 * r - 0.012, 0.0015, 0.002, (0, 0.0048, 0), PITH, rot=(0, k * math.pi / spokes, 0), name="SlicePith"))
    return parts


# pitcher (JS: r .12, .28 tall at (-.35, .97, 0)): glass with lemonade inside, a spout and a handle
PX, PZ = -0.35, 0.0


def spout(x, y, z):
    f = max(0.0, x / max(1e-6, math.hypot(x, z))) ** 6 * max(0.0, (y - 0.2) / 0.078) ** 2
    s = 1 + 0.028 * f / max(1e-6, math.hypot(x, z))
    return x * s, y + 0.006 * f, z * s


# the lemonade itself is the glossy lower body (two glass layers in front of it washed the yellow out in engine);
# glass only shows above the waterline and as a thick base
goods.append(lathe([(0.1118, 0.19), (0.107, 0.262), (0.109, 0.272), (0.105, 0.278), (0.101, 0.272), (0.103, 0.262), (0.1036, 0.19)],
                   (PX, TOP, PZ), GLASS, name="PitcherGlass", segs=14, deform=spout, **P))
goods.append(lathe([(0.0, 0.0), (0.105, 0.0), (0.112, 0.005), (0.1135, 0.012), (0.0, 0.012)], (PX, TOP, PZ), GLASS_H, name="PitcherBase", segs=14, **P))
goods.append(lathe([(0.0, 0.012), (0.1135, 0.012), (0.1158, 0.04), (0.113, 0.17), (0.1118, 0.2), (0.0, 0.2)], (PX, TOP, PZ), LEMONADE,
                   name="PitcherLemonade", segs=14, **P))
goods.append(tube([(PX - 0.104, TOP + 0.24, PZ), (PX - 0.15, TOP + 0.236, PZ), (PX - 0.174, TOP + 0.18, PZ), (PX - 0.166, TOP + 0.1, PZ),
                   (PX - 0.122, TOP + 0.06, PZ), (PX - 0.106, TOP + 0.056, PZ)], 0.012, GLASS_H, name="PitcherHandle", segs=6, n_per=3, **P))
goods.append(placed(lemon_slice(), (PX + 0.03, TOP + 0.201, PZ + 0.03), (0.15, 0.4, 0.1), root, "FloatSlice"))
goods.append(placed(lemon_slice(0.029), (PX - 0.042, TOP + 0.2, PZ - 0.035), (-0.12, 1.3, -0.08), root, "FloatSlice"))
goods.append(placed(lemon_slice(0.034), (PX, TOP + 0.262, PZ - 0.106), (0, 0, math.pi / 2), root, "RimSlice"))
# three cups (JS: r .05/.04, .12 tall at x .1 + .15k, z .05); two are poured
cup_prof = [(0.0, 0.0), (0.038, 0.0), (0.04, 0.004), (0.0495, 0.116), (0.052, 0.119), (0.0505, 0.1225), (0.0475, 0.119), (0.039, 0.011), (0.0, 0.011)]
for k, (dx, dz) in enumerate(((0.0, 0.0), (0.004, 0.012), (-0.003, -0.008))):
    x, z = 0.1 + 0.15 * k + dx, 0.05 + dz
    goods.append(lathe(cup_prof, (x, TOP, z), CUP, name="Cup", segs=10, **P))
    if k < 2:
        goods.append(ck.cyl(0.0452, 0.0452, 0.004, (x, TOP + 0.093, z), LEMONADE, name="CupLemonade", segs=10, **P))
# a stack of spare cups, upside down
stack = [(0.0, 0.0), (0.0505, 0.0)]
for k in range(4):
    y = 0.018 * k
    stack += [(0.0505 - 0.0003 * k, y + 0.001), (0.0527 - 0.0003 * k, y + 0.0035), (0.0505 - 0.0003 * k, y + 0.0065)]
stack += [(0.0405, 0.178), (0.038, 0.181), (0.0, 0.181)]
goods.append(lathe(stack, (0.575, TOP, -0.105), CUP, rot=(0, 0, 0.02), name="CupStack", segs=10, **P))
# coin jar with the takings
JX, JZ = 0.6, 0.17
jar = [(0.0, 0.0), (0.044, 0.0), (0.05, 0.007), (0.05, 0.088), (0.043, 0.103), (0.042, 0.112), (0.045, 0.116), (0.043, 0.12),
       (0.038, 0.117), (0.038, 0.104), (0.045, 0.088), (0.045, 0.012), (0.0, 0.01)]
goods.append(lathe(jar, (JX, TOP, JZ), GLASS, name="CoinJar", segs=10, **P))
rc = random.Random(8)
for k in range(6):
    a, rr = rc.uniform(0, 6.28), rc.uniform(0.0, 0.026)
    goods.append(ck.cyl(0.0115, 0.0115, 0.0028, (JX + rr * math.cos(a), TOP + 0.013 + 0.0035 * k, JZ + rr * math.sin(a)),
                        SILVER if k % 3 else COPPER, rot=(rc.uniform(-0.4, 0.4), 0, rc.uniform(-0.4, 0.4)), name="Coin", segs=6, **P))
for (x, z, m) in ((0.505, 0.262, SILVER), (0.538, 0.292, COPPER)):
    goods.append(ck.cyl(0.0115, 0.0115, 0.0028, (x, TOP + 0.0015, z), m, name="Coin", segs=8, **P))
# the cooler with the ice, under the table; it stands on the sidewalk top (local y .04, the stand straddles its edge)
goods.append(ck.box(0.42, 0.24, 0.3, (0.24, 0.16, -0.005), COOLER, rot=(0, 0.12, 0), name="Cooler", bevel=0.03, bevel_segs=1, **P))
goods.append(ck.box(0.44, 0.05, 0.32, (0.24, 0.302, -0.005), COOLER_LID, rot=(0, 0.12, 0), name="CoolerLid", bevel=0.02, bevel_segs=1, **P))
goods.append(ck.box(0.2, 0.025, 0.04, (0.24, 0.34, -0.005), COOLER_LID, rot=(0, 0.12, 0), name="CoolerHandle", bevel=0.01, bevel_segs=1, **P))
# lemons: two whole ones and a cut half
for k, (x, z, ry) in enumerate(((-0.6, 0.19, 0.5), (-0.63, 0.065, -0.35))):
    body = ck.sph(0.036, (0, 0, 0), LEMON, scale=(1.3, 0.94, 0.94), name="Lemon", segs=10, rings=7)
    ck.lumpy(body, 0.0018, 55, seed=k + 2)
    nubs = [ck.cyl(0.004, 0.012, 0.016, (s * 0.049, 0, 0), LEMON, rot=(0, 0, -s * math.pi / 2), name="LemonTip", segs=6) for s in (-1, 1)]
    goods.append(placed([body] + nubs, (x, TOP + 0.033, z), (0, ry, 0.03), root, "Lemon"))
oval = lambda x, y, z: (x * 1.22, y, z)
half = [lathe([(0.0, 0.0), (0.02, 0.003), (0.031, 0.012), (0.035, 0.026), (0.034, 0.03), (0.0, 0.03)], (0, 0, 0), LEMON,
              name="HalfLemonRind", segs=12, deform=oval),
        lathe([(0.0, 0.029), (0.031, 0.029), (0.0305, 0.0312), (0.0, 0.0312)], (0, 0, 0), LEMON_IN, name="HalfLemonFlesh", segs=12, deform=oval)]
for k in range(3):
    half.append(ck.box(0.064, 0.0015, 0.002, (0, 0.0318, 0), PITH, rot=(0, k * math.pi / 3, 0), name="HalfLemonPith"))
goods.append(placed(half, (-0.13, TOP + 0.004, 0.215), (0.32, 0.4, 0), root, "HalfLemon"))

# ------------------------------------------------------------------ join and export
parts = {"LemonadeStand_Body": frame + letters + awn, "SignOpen": op, "SignClosed": cl, "LemonadeStand_Goods": goods}
for nm, objs in parts.items():
    print(f"[stand] {nm}: {tris(objs)} tris")
    ck.join(objs, nm)
ck.export("lemonade_stand")
print("[stand] objects:", sorted(o.name for o in bpy.context.scene.objects))
for o in bpy.context.scene.objects:
    if o.type == "MESH":
        print(f"[stand]   {o.name}: materials {[m.name for m in o.data.materials]}")
bpy.data.objects["SignClosed"].hide_render = True
ck.preview("lemonade_stand")
clear_preview()
ck.preview("lemonade_stand_close", views=[
    {"eye": (2.4, 3.3, 5.8), "look": (0.0, 1.05, 0.0), "lens": 35},
    {"eye": (0.0, 1.25, 2.6), "look": (0.0, 1.15, 0.0), "lens": 40},
    {"eye": (0.45, 1.45, 1.15), "look": (0.0, 0.9, 0.05), "lens": 40},
    {"eye": (-2.0, 1.7, -2.2), "look": (0.0, 0.95, 0.0), "lens": 35},
])
clear_preview()
bpy.data.objects["SignClosed"].hide_render = False
bpy.data.objects["SignOpen"].hide_render = True
ck.preview("lemonade_stand_closed", views=[{"eye": (1.2, 2.2, 4.2), "look": (0.0, 1.2, 0.0), "lens": 40},
                                          {"eye": (2.3, 1.7, 0.3), "look": (0.0, 1.6, -0.2), "lens": 50}])
