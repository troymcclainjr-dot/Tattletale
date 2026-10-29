"""car_kit - shared builders for cop_car.py and sedan.py (lofted clay bodies, cabins, wheels, trim). Not an asset."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math
import bpy, bmesh
from mathutils import Vector, Matrix
import claykit as ck


class P:
    """Plain parameter bag."""
    def __init__(self, **kw):
        self.__dict__.update(kw)


# ------------------------------------------------------------------ mesh plumbing
def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def attach(obj, parent):
    """Parent keeping obj's transform as LOCAL to parent (like THREE.Group.add)."""
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    return obj


def place(obj, pos=(0, 0, 0), rot=None):
    if rot is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = ck.grot(*rot).to_quaternion()
    obj.location = ck.G(pos)
    return obj


def mesh(name, verts, faces, mats, fmat=None, smooth_deg=40, recalc=True):
    """Mesh object at the origin from GAME-coord verts and index faces; fmat = material slot per face."""
    bm = bmesh.new()
    bv = [bm.verts.new(ck.G(v)) for v in verts]
    for k, f in enumerate(faces):
        try:
            face = bm.faces.new([bv[i] for i in f])
        except ValueError:
            continue
        if fmat:
            face.material_index = fmat[k]
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    for m in mats:
        me.materials.append(m)
    ck.smooth(obj, smooth_deg)
    return obj


def set_origin(obj, pos):
    """Move the object origin to game point pos without moving the mesh."""
    bpy.context.view_layer.update()
    target = ck.G(pos)
    local = obj.matrix_world.inverted() @ target
    obj.data.transform(Matrix.Translation(-local))
    obj.location = obj.matrix_world @ local
    return obj


def push(obj, center, radius, vec):
    """Dent: move vertices within radius of game point center by game vector vec (smooth falloff)."""
    c = ck.G(center)
    v = ck.G(vec)
    for vt in obj.data.vertices:
        d = (vt.co - c).length
        if d < radius:
            vt.co += v * (1 - (d / radius) ** 2) ** 2
    obj.data.update()
    return obj


# ------------------------------------------------------------------ body: loft along x
def end_inset(B, x):
    """(side, top, bottom) insets that round the nose and tail (elliptical profile)."""
    for x0, (dx, rs, rtop, rbot), sgn in ((B.x_nose - B.front[0], B.front, 1), (B.x_tail + B.rear[0], B.rear, -1)):
        u = (x - x0) * sgn / dx
        if u > 0:
            f = 1 - math.sqrt(max(0.0, 1 - min(1.0, u) ** 2))
            return rs * f, rtop * f, rbot * f
    return 0.0, 0.0, 0.0


def arch_yb(B, x):
    y = B.yb_base
    for wx in B.wheel_x:
        dx = abs(x - wx)
        if dx <= B.arch_r:
            y = max(y, B.wheel_y + math.sqrt(B.arch_r ** 2 - dx * dx))
    return y


def body_ring(B, x):
    """Rounded cross-section at station x: list of (z, y, kind, side_idx, w_side, w_top)."""
    ds, dt, db = end_inset(B, x)
    hw = B.hw(x) - ds
    yb = arch_yb(B, x) + B.yb_extra(x) + db
    yt = B.yt(x) - dt
    rb = min(B.rb, (yt - yb) * 0.3)
    rt = min(B.rt, (yt - yb) * 0.6, hw * 0.5)
    y0, y1 = yb + rb, yt - rt
    tuck = lambda y: B.tuck_k * max(0.0, B.tuck_y - y) ** 2
    z0, z1 = hw - tuck(y0), hw - tuck(y1)
    crown = B.crown(x)
    half = [(0.0, yb, "bot", -1, 0, 0)]
    for k in range(4):
        a = math.radians(-90 + 30 * k)
        half.append((z0 - rb + rb * math.cos(a), y0 + rb * math.sin(a), "bc", -1, k / 3, 0))
    for i, f in enumerate(B.side_fracs):
        y = y0 + (y1 - y0) * f
        half.append((hw - tuck(y), y, "side", i, 1, 0))
    for k in range(5):
        a = math.radians(22.5 * k)
        half.append((z1 - rt + rt * math.cos(a), y1 + rt * math.sin(a), "tc", -1, 1 - k / 4, k / 4))
    zc = z1 - rt
    half.append((zc * 0.5, yt + crown * 0.75, "top", -1, 0, 1))
    half.append((0.0, yt + crown, "top", -1, 0, 1))
    return half + [(-z, y, k, i, ws, wt) for (z, y, k, i, ws, wt) in reversed(half[1:-1])]


def side_fracs(B, ys, yt_ref):
    y0, y1 = B.yb_base + B.rb, yt_ref - B.rt
    return [(y - y0) / (y1 - y0) for y in ys]


def body_stations(B, seams):
    xs = []
    for x0, dx, sgn in ((B.x_nose - B.front[0], B.front[0], 1), (B.x_tail + B.rear[0], B.rear[0], -1)):
        xs += [x0 + sgn * dx * math.sin(math.radians(t)) for t in (0, 28, 52, 70, 83, 90)]
    for wx in B.wheel_x:
        R = B.arch_r
        xs += [wx + R * math.cos(math.pi * k / 8) for k in range(9)]
        xs += [wx - R - 0.002, wx + R + 0.002]
    for sx, kind, d in seams:
        xs += [sx - 0.012, sx, sx + 0.012]
    xs += list(B.extra_x)
    xs = sorted(x for x in xs if B.x_tail - 1e-6 <= x <= B.x_nose + 1e-6)
    out = []
    for x in xs:
        if out and x - out[-1] < 0.0015:
            continue
        if out and x - out[-1] > B.step:
            n = int(math.ceil((x - out[-1]) / B.step))
            x0 = out[-1]
            out += [x0 + (x - x0) * k / n for k in range(1, n)]
        out.append(x)
    return out


def body_loft(name, B, mats, mat_fn, seams=()):
    """Closed car body lofted along x. seams: (x, 'side'|'top', depth) pressed grooves.
    mat_fn(x_mid, pt_a, pt_b) -> material slot for the quad between ring points a and b."""
    xs = body_stations(B, seams)
    rings, meta = [], None
    for x in xs:
        ring = body_ring(B, x)
        for sx, kind, depth in seams:
            if abs(x - sx) < 0.002:
                if kind == "side":
                    ring = [(z - math.copysign(depth * ws, z) if z else z, y, k, i, ws, wt) for (z, y, k, i, ws, wt) in ring]
                else:
                    ring = [(z, y - depth * wt, k, i, ws, wt) for (z, y, k, i, ws, wt) in ring]
        rings.append([(x, y, z) for (z, y, *_r) in ring])
        meta = ring
    n = len(rings[0])
    verts = [p for r in rings for p in r]
    faces, fm = [], []
    for i in range(len(rings) - 1):
        xm = 0.5 * (xs[i] + xs[i + 1])
        for j in range(n):
            j2 = (j + 1) % n
            faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j))
            fm.append(mat_fn(xm, meta[j], meta[j2]))
    last = (len(rings) - 1) * n
    faces += [tuple(range(n)), tuple(last + j for j in range(n))]
    fm += [0, 0]
    return mesh(name, verts, faces, mats, fm)


# ------------------------------------------------------------------ cabin: loft along y
def rrect(x0, x1, w, r, nc=5, ne=(3, 3)):
    """Rounded rectangle in plan view (x, z), x0..x1 by -w..w, corner radius r."""
    corners = [((x1 - r, w - r), 0), ((x0 + r, w - r), 90), ((x0 + r, -w + r), 180), ((x1 - r, -w + r), 270)]
    pts = []
    for ci, ((cx, cz), a0) in enumerate(corners):
        for k in range(nc):
            a = math.radians(a0 + 90 * k / (nc - 1))
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
        (nx, nz), na = corners[(ci + 1) % 4]
        ex, ez = pts[-1]
        sx, sz = nx + r * math.cos(math.radians(na)), nz + r * math.sin(math.radians(na))
        m = ne[ci % 2]
        for k in range(1, m + 1):
            t = k / (m + 1)
            pts.append((ex + (sx - ex) * t, ez + (sz - ez) * t))
    return pts


def cabin_loft(name, C, mats, fmat_fn=None):
    """Greenhouse stacked from rounded-rect slices: xf(y)/xb(y) front/back, hw(y) half width, rounded roof edge."""
    ys = list(C.ys) + [C.y_roof - C.r_roof + C.r_roof * math.sin(math.radians(t)) for t in (0, 30, 55, 75, 90)]
    rings = []
    for y in ys:
        u = (y - (C.y_roof - C.r_roof)) / C.r_roof
        d = C.r_roof * (1 - math.sqrt(max(0.0, 1 - min(1.0, u) ** 2))) if u > 0 else 0.0
        x0, x1, w = C.xb(y) + d, C.xf(y) - d, C.hw(y) - d
        r = min(C.rc, 0.45 * (x1 - x0), 0.9 * w)
        rings.append([(x, y, z) for (x, z) in rrect(x0, x1, w, r)])
    n = len(rings[0])
    verts = [p for r in rings for p in r]
    faces = []
    for i in range(len(rings) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j))
    faces.append(tuple(range(n)))
    top = rings[-1]
    cx = sum(p[0] for p in top) / n
    verts.append((cx, C.y_roof + C.crown, 0.0))
    c = len(verts) - 1
    last = (len(rings) - 1) * n
    for j in range(n):
        faces.append((last + j, last + (j + 1) % n, c))
    return mesh(name, verts, faces, mats, [0] * len(faces))


# ------------------------------------------------------------------ flat parts
def rounded_poly(pts, r, seg=4):
    """Round the corners of a convex 2D polygon (any winding) with radius r. Returns CCW points."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if area < 0:
        pts = pts[::-1]
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        d1, d2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((d1.y, -d1.x)), Vector((d2.y, -d2.x))
        cosphi = max(-0.999, min(1.0, n1.dot(n2)))
        k = r / math.cos(math.acos(cosphi) / 2)
        c = p1 - (n1 + n2).normalized() * k
        a1, a2 = math.atan2(n1.y, n1.x), math.atan2(n2.y, n2.x)
        if a2 < a1:
            a2 += 2 * math.pi
        for s in range(seg + 1):
            a = a1 + (a2 - a1) * s / seg
            out.append((c.x + r * math.cos(a), c.y + r * math.sin(a)))
    return out


def offset_poly(pts, d):
    """Grow a convex 2D polygon outward by d (any winding). Returns CCW points."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if area < 0:
        pts = pts[::-1]
    lines = []
    for i in range(n):
        p0, p1 = Vector(pts[i]), Vector(pts[(i + 1) % n])
        dv = (p1 - p0).normalized()
        lines.append((p0 + Vector((dv.y, -dv.x)) * d, dv))
    out = []
    for i in range(n):
        (a, da), (b, db) = lines[i - 1], lines[i]
        t = ((b.x - a.x) * db.y - (b.y - a.y) * db.x) / (da.x * db.y - da.y * db.x)
        q = a + da * t
        out.append((q.x, q.y))
    return out


def tilt(obj, pivot, rot):
    """Rotate an origin-placed object's mesh about a game pivot by a three.js Euler (knocked-askew parts)."""
    p = ck.G(pivot)
    obj.data.transform(Matrix.Translation(p) @ ck.grot(*rot).to_4x4() @ Matrix.Translation(-p))
    obj.data.update()
    return obj


def surface_slab(name, outline, to3d, normal, mat, front=0.004, back=-0.004, smooth_deg=30):
    """Thin plate whose outline (2D, mapped onto a surface by to3d(u, v)) sits front..back along normal."""
    nv = Vector(normal).normalized()
    n = len(outline)
    base = [Vector(to3d(u, v)) for (u, v) in outline]
    verts = [tuple(p + nv * front) for p in base] + [tuple(p + nv * back) for p in base]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return mesh(name, verts, faces, [mat], smooth_deg=smooth_deg)


def star_outline(r_out, r_in, rot=0.0):
    return [((r_out if k % 2 == 0 else r_in) * math.cos(rot + math.pi / 2 + k * math.pi / 5),
             (r_out if k % 2 == 0 else r_in) * math.sin(rot + math.pi / 2 + k * math.pi / 5)) for k in range(10)]


# ------------------------------------------------------------------ sweeps (bumpers, moldings)
def rr_profile(depth, height, r, seg=3, off=0.0, yoff=0.0):
    """Closed rounded-rect profile in the (out, up) plane, centered (plus offsets)."""
    a, b = depth / 2 - r, height / 2 - r
    pts = []
    for cx, cy, a0 in ((a, b, 0), (-a, b, 90), (-a, -b, 180), (a, -b, 270)):
        for k in range(seg + 1):
            t = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(t) + off, cy + r * math.sin(t) + yoff))
    return pts


def sweep(name, path, profile, mat, smooth_deg=50):
    """Sweep a closed 2D profile (out, up) along a GAME path; out = up x tangent. Capped and closed."""
    upv = Vector((0, 1, 0))
    N = len(path)
    rings = []
    for k in range(N):
        p = Vector(path[k])
        t = Vector(path[min(k + 1, N - 1)]) - Vector(path[max(k - 1, 0)])
        t.y = 0
        t.normalize()
        out = upv.cross(t).normalized()
        rings.append([tuple(p + out * a + upv * b) for (a, b) in profile])
    n = len(profile)
    verts = [q for r in rings for q in r]
    faces = []
    for i in range(N - 1):
        for j in range(n):
            j2 = (j + 1) % n
            faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j))
    faces += [tuple(range(n)), tuple((N - 1) * n + j for j in range(n))]
    return mesh(name, verts, faces, [mat], smooth_deg=smooth_deg)


def u_path(x_front, half_w, corner_r, x_end, y, seg=5, rear=False):
    """Plan-view U around the nose (or tail if rear): side, corner arc, across, corner arc, side."""
    cx = x_front - corner_r
    pts = [(x_end, y, -half_w)]
    for k in range(seg + 1):
        a = math.radians(-90 + 90 * k / seg)
        pts.append((cx + corner_r * math.cos(a), y, -half_w + corner_r + corner_r * math.sin(a)))
    for k in range(seg + 1):
        a = math.radians(90 * k / seg)
        pts.append((cx + corner_r * math.cos(a), y, half_w - corner_r + corner_r * math.sin(a)))
    pts.append((x_end, y, half_w))
    if rear:
        pts = [(-x, yy, z) for (x, yy, z) in pts][::-1]
    return pts


# ------------------------------------------------------------------ wheels
def lathe(name, prof, segs, mats_by_key, mirror=False, perturb=None, smooth_deg=55):
    """Closed solid of revolution about the local game z axis (the axle).
    prof: [(r, z, key)] from pole to pole (first and last r = 0); +z = outboard face.
    A segment takes the material of its END point's key. mirror flips z (left-side wheels)."""
    keys = list(dict.fromkeys(p[2] for p in prof))
    s = -1.0 if mirror else 1.0
    rows = prof[1:-1]
    verts = [(0.0, 0.0, s * prof[0][1])]
    for j, (r, z, key) in enumerate(rows):
        for k in range(segs):
            a = 2 * math.pi * k / segs
            rr, zz = perturb(k, j, r, z) if perturb else (r, z)
            verts.append((rr * math.cos(a), rr * math.sin(a), s * zz))
    verts.append((0.0, 0.0, s * prof[-1][1]))
    V = lambda j, k: 1 + j * segs + (k % segs)
    m = len(rows)
    faces, fm = [], []
    for k in range(segs):
        faces.append((0, V(0, k + 1), V(0, k)))
        fm.append(keys.index(rows[0][2]))
    for j in range(m - 1):
        for k in range(segs):
            faces.append((V(j, k), V(j, k + 1), V(j + 1, k + 1), V(j + 1, k)))
            fm.append(keys.index(rows[j + 1][2]))
    last = len(verts) - 1
    for k in range(segs):
        faces.append((last, V(m - 1, k), V(m - 1, k + 1)))
        fm.append(keys.index(prof[-1][2]))
    return mesh(name, verts, faces, [mats_by_key[k] for k in keys], fm, smooth_deg)


TIRE_PROFILE = [  # (r, z, key): inner face and tyre; each car appends its outboard face (z+ = outboard)
    (0.0, -0.10, "steel"), (0.2, -0.108, "steel"),
    (0.232, -0.132, "tire"), (0.30, -0.148, "tire"), (0.352, -0.128, "tire"),
    (0.361, -0.095, "tire"), (0.362, -0.03, "tire"), (0.349, -0.019, "tire"), (0.349, 0.019, "tire"),
    (0.362, 0.03, "tire"), (0.361, 0.095, "tire"), (0.352, 0.128, "tire"), (0.33, 0.145, "tire"),
]


def tread(k, j, r, z):
    """Chunky toy tread: notched shoulders and a zig-zag centre groove."""
    if j in (3, 10):                       # shoulders
        return (r - (0.009 if k % 2 else 0.0), z)
    if j in (6, 7):                        # groove
        return (r, z + (0.011 if k % 2 else -0.011))
    return (r, z)


# ------------------------------------------------------------------ lettering and fuzz
def text(s, size, depth, m, font="impact", res=3, bevel=0.0, name="text", cull_back=True):
    """Raised lettering centred on its glyph box, in the game XY plane facing +z (low curve resolution).
    cull_back drops the back cap (the letters are always pressed into a surface)."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size = size
    cu.extrude = depth / 2
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.resolution_u = res
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    tmp = link(bpy.data.objects.new(name, cu))
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    me.transform(Matrix.Translation((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0)))
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    if cull_back:
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.normal_update()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.y > 0.9], context="FACES")
        bm.to_mesh(me)
        bm.free()
    obj = link(bpy.data.objects.new(name, me))
    ck.assign(obj, m)
    return obj


def lumpy_world(objs, amount=0.003, freq=2.5, seed=0):
    """ck.lumpy, but the noise is looked up in WORLD space so neighbouring parts (decals on a panel)
    get the same squish and nothing floats off or sinks into what it sits on."""
    from mathutils import noise
    bpy.context.view_layer.update()
    off = Vector((seed * 13.17, seed * 7.31, seed * 3.77))
    for o in objs:
        mw = o.matrix_world
        inv = mw.inverted()
        nm = mw.to_3x3().inverted().transposed()
        me = o.data
        for v in me.vertices:
            pw = mw @ v.co
            nw = (nm @ v.normal).normalized()
            pw += nw * amount * noise.noise(pw * freq + off)
            v.co = inv @ pw
        me.update()


def fuzzy_ball(name, r, m, seed=0, subdiv=3, fuzz=0.16):
    """Icosphere roughed up into a fuzzy pom (random tufts + noise)."""
    import random as _r
    rng = _r.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    for v in bm.verts:
        n = v.co.normalized()
        v.co = n * r * (1 + fuzz * (rng.random() ** 1.5) - fuzz * 0.35)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    ck.assign(obj, m)
    ck.smooth(obj, 180)
    return obj


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def tri_report(objs, top=12):
    """Print the heaviest parts (by name) before they get joined."""
    agg = {}
    for o in objs:
        if o and o.type == "MESH":
            agg[o.name.split(".")[0]] = agg.get(o.name.split(".")[0], 0) + tris(o)
    for k, v in sorted(agg.items(), key=lambda kv: -kv[1])[:top]:
        print(f"[tris] {k}: {v}")
    print(f"[tris] parts total: {sum(agg.values())}")


def report(root_name):
    """Print the exported hierarchy (names, types, game positions) for the contract check."""
    bpy.context.view_layer.update()

    def walk(o, depth):
        w = o.matrix_world.translation
        print(f"[contract] {'  ' * depth}{o.name} ({o.type}) game=({w.x:.3f}, {w.z:.3f}, {-w.y:.3f})")
        for c in sorted(o.children, key=lambda c: c.name):
            walk(c, depth + 1)
    walk(bpy.data.objects[root_name], 0)
