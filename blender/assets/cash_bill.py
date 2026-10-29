"""Dropped dollar bill (local, origin at center, lying flat): dark green clay border, softly glowing faces, a pressed oval and "$"."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

ck.reset()
random.seed(5)

W, H, D = 0.24, 0.012, 0.11            # JS box(.24, .012, .11)
BORDER = ck.clay("#3c7a3e", 0.8)
FACE = ck.glow("#5ab05a", 0.5)         # JS: color 0x5ab05a with a soft emissive glow
PRINT = ck.clay("#2a5a2e", 0.8)


# ------------------------------------------------------------------ local helpers (game coords)
def rrect(w, d, rc, n=3):
    """Rounded rectangle outline in (x, z), CCW."""
    pts = []
    for cx, cz, a0 in ((w / 2 - rc, -(d / 2 - rc), 270), (w / 2 - rc, d / 2 - rc, 0), (-(w / 2 - rc), d / 2 - rc, 90), (-(w / 2 - rc), -(d / 2 - rc), 180)):
        for i in range(n):
            a = math.radians(a0 + 90 * i / (n - 1))
            pts.append((cx + rc * math.cos(a), cz + rc * math.sin(a)))
    return pts


def inset(pts, d):
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))
        nm = (n1 + n2).normalized()
        out.append(tuple(p1 + nm * (d / max(0.4, nm.dot(n1)))))
    return out


def slab(outline, y0, y1, m, e=0.0, name="slab"):
    """Extruded outline; e > 0 chamfers the top and bottom edges (smooth shaded, reads rounded)."""
    layers = [(outline, y0), (outline, y1)] if e <= 0 else \
        [(inset(outline, e), y0), (outline, y0 + e), (outline, y1 - e), (inset(outline, e), y1)]
    bm = bmesh.new()
    rings = [[bm.verts.new(ck.G(x, y, z)) for (x, z) in pts] for pts, y in layers]
    n = len(outline)
    for i in range(len(rings) - 1):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, 50)
    return obj


def cuts(obj, xs):
    """Slice along x so the bill can bend smoothly."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for x in xs:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(x, 0, 0), plane_no=(1, 0, 0))
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def loft(pts, rads, segs=5, m=None, name="loft", side=(0, 1, 0), closed=False):
    """Tube through game points; rads = (r_along_side, r_other). Pole caps unless closed."""
    P = [Vector(p) for p in pts]
    n = len(P)
    if closed:
        T = [(P[(i + 1) % n] - P[i - 1]).normalized() for i in range(n)]
    else:
        T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = Vector(side)
    bm = bmesh.new()
    rings = []
    for i in range(n):
        N = (ref - T[i] * ref.dot(T[i])).normalized()
        B = T[i].cross(N).normalized()
        ra, rb = rads[i]
        rings.append([bm.verts.new(ck.G(P[i] + N * (math.cos(2 * math.pi * j / segs) * ra)
                                        + B * (math.sin(2 * math.pi * j / segs) * rb))) for j in range(segs)])
    for i in range(n if closed else n - 1):
        i2 = (i + 1) % n
        for j in range(segs):
            k = (j + 1) % segs
            bm.faces.new((rings[i][j], rings[i][k], rings[i2][k], rings[i2][j]))
    if not closed:
        c0 = bm.verts.new(ck.G(P[0] - T[0] * rads[0][1] * 0.8))
        c1 = bm.verts.new(ck.G(P[-1] + T[-1] * rads[-1][1] * 0.8))
        for j in range(segs):
            k = (j + 1) % segs
            bm.faces.new((rings[0][k], rings[0][j], c0))
            bm.faces.new((rings[-1][j], rings[-1][k], c1))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = ck._mesh_obj(name, bm)
    ck.assign(obj, m)
    ck.smooth(obj, 180)
    return obj


# ------------------------------------------------------------------ the bill
TOP = 0.0062                            # face panels stand 2 mm proud of the 8 mm border slab
XS = (-0.078, -0.027, 0.027, 0.078)
base = cuts(slab(rrect(W, D, 0.008), -0.004, 0.004, BORDER, e=0.0016, name="CashBill"), XS)
parts = [base]
for sg in (1, -1):                      # glowing faces, top and bottom
    y0, y1 = (0.003, TOP) if sg > 0 else (-TOP, -0.003)
    parts.append(cuts(slab(rrect(0.222, 0.092, 0.006), y0, y1, FACE, name="Face"), XS))

# pressed oval in the middle of the top face (the underside never faces the camera)
segs, a, b, y = 16, 0.031, 0.0245, TOP + 0.0006
pts = [(a * math.cos(2 * math.pi * i / segs), y, b * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
parts.append(loft(pts, [(0.0019, 0.0028)] * segs, 4, PRINT, "Oval", closed=True))

# a rolled-clay "$" inside the oval, reading upright from the street side (top toward -z)
h, R = 0.032, 0.008
path = []
for i in range(7):                      # upper bowl: from the upper right, over the top, down to the middle
    a = math.radians(25 + (270 - 25) * i / 6)
    path.append((0.85 * R * math.cos(a), h / 4 + R * math.sin(a)))
for i in range(1, 7):                   # lower bowl: from the middle, round the right, to the lower left
    a = math.radians(90 - (90 + 155) * i / 6)
    path.append((0.85 * R * math.cos(a), -h / 4 + R * math.sin(a)))
y = TOP + 0.0007
parts.append(loft([(u, y, -v) for (u, v) in path], [(0.0016, 0.0024)] * len(path), 4, PRINT, "DollarS"))
parts.append(loft([(0.0, y, -0.0195), (0.0, y, 0.0), (0.0, y, 0.0195)], [(0.0014, 0.0017)] * 3, 4, PRINT, "DollarBar"))

# two corner rosettes (where a real bill has its numerals; no text added)
for (x, z) in ((-0.084, -0.025), (0.084, 0.025)):
    parts.append(ck.cyl(0.0072, 0.0072, 0.002, (x, TOP + 0.0004, z), PRINT, name="Rosette", segs=8))

bill = ck.join(parts, "CashBill")


# slight curl: ends lifted, a gentle twist, one dog-eared corner; centered so the bob height stays the JS one
def curl(x, y, z):
    u, v = x / (W / 2), z / (D / 2)
    c = min(1.0, max(0.0, (u - 0.62) / 0.38)) * min(1.0, max(0.0, (v + 0.1) / 1.1))
    return x, y + 0.009 * (u * u - 0.36) + 0.0025 * u * v + 0.005 * c * c, z


me = bill.data
for vt in me.vertices:
    x, yy, z = curl(vt.co.x, vt.co.z, -vt.co.y)
    vt.co = Vector((x, -z, yy))
me.update()
ck.lumpy(bill, 0.0006, 60, seed=3)

bpy.context.view_layer.update()
vs = [Vector((v.co.x, v.co.z, -v.co.y)) for v in bill.data.vertices]
lo = Vector([min(v[i] for v in vs) for i in range(3)])
hi = Vector([max(v[i] for v in vs) for i in range(3)])
print(f"[cash_bill] tris={sum(len(p.vertices) - 2 for p in bill.data.polygons)} bounds x {lo.x:.3f}..{hi.x:.3f} "
      f"y {lo.y:.4f}..{hi.y:.4f} z {lo.z:.3f}..{hi.z:.3f} mats={[m.name for m in bill.data.materials]}")
ck.export("cash_bill")

bill.location = ck.G(0, 0.19, 0)       # preview only: float it at the game's bob height
ck.preview("cash_bill")
ck.preview("cash_bill_close", views=[
    {"eye": (0.0, 0.62, 0.32), "look": (0, 0.19, 0.0), "lens": 50},
    {"eye": (0.38, 0.32, -0.25), "look": (0, 0.19, 0.0), "lens": 50},
    {"eye": (-0.42, 0.24, 0.12), "look": (0, 0.19, 0.0), "lens": 50},
    {"eye": (0.0, 2.6, 5.0), "look": (0, 0.19, 0.0), "lens": 50},
])
