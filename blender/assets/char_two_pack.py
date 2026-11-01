"""Builds two_pack: Tattletale 2-Pack himself, the player character (make2Pack, js/characters.js 51-74)."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math, random, time
import numpy as np
import bpy, bmesh
import claykit as ck
from lib import person as P
from lib.person import (Sdf, sphere, ellipsoid, capsule, round_cone, rbox, torus, cylinder, halfspace, union, subtract,
                        intersect, offset, displace, xform, symmetric_x, tube, groove, seam, snap, slab, poly2d,
                        ellipse2d, plane_slab, vnoise, smoothstep)

H = 1.8
HS = 0.115 * H
HY = 0.05 * H + HS
SKIN, INK, RED, CREAM, GOLD = "#6e4228", "#1a2030", "#c4162a", "#f4f0e6", "#f2c230"
ORANGE, JEANS, KICKS, DARK = "#ff8a1a", "#2a4a7a", "#f4f4f4", "#1a1a1e"
T0 = time.time()

# sash: JS box .07H wide at (0, .17H, +-.112H), rotation z .62; one plane, so front and back are one band
SASH_A, SASH_W, SASH_T = 0.76, 0.07 * H, 0.0068 * H   # JS .62: a bit flatter so SNITCH 4 LIFE clears it
SASH_C = (0.0598 * H, 0.17 * H, 0.0)        # crosses the shoulder midway between neck and arm
SASH_NECK = 0.045 * H                        # over the shoulder top it settles this much toward the neck
# bandana: front edge just above the brows, knot low on the back of the skull
BAND_Y, BAND_H, BAND_TILT, BAND_T = HY + 0.066 * H, 0.038 * H, 0.2, 0.0092 * H
BAND_ROLL = 0.08                            # higher over his cocked left brow


def log(msg):
    print(f"[two_pack] {time.time() - T0:6.1f}s  {msg}")


# ------------------------------------------------------------------ small sdf helpers
def lumped(s, amount, seed):
    """Compatibility helper: keep intentional anatomy and remove blanket wobble."""
    return s


def grad(s, pts, h=0.001):
    pts = np.atleast_2d(np.asarray(pts, float))
    g = np.zeros_like(pts)
    for a in range(3):
        e = np.zeros(3)
        e[a] = h
        g[:, a] = s(pts + e) - s(pts - e)
    return g / np.maximum(np.linalg.norm(g, axis=1)[:, None], 1e-12)


def on(s, pts, normals, reach=0.3 * H, lift=0.0):
    """Points snapped onto s along -normals, then lifted along the true surface normal."""
    S = snap(s, pts, normals, reach)
    return S + grad(s, S) * lift if lift else S


def shell(s, out, inn):
    """A skin from `inn` under the surface of s to `out` above it (cheaper than a solid slice)."""
    return subtract(offset(s, out), offset(s, -inn))


def frame(y_axis, z_hint):
    """3x3 matrix (columns = local axes in the parent) with local y along y_axis, local z near z_hint."""
    y = np.asarray(y_axis, float)
    y = y / np.linalg.norm(y)
    z = np.asarray(z_hint, float)
    z = z - y * (z @ y)
    z = z / np.linalg.norm(z)
    return np.stack([np.cross(y, z), y, z], 1)


def sash_slab(off, half):
    """The sash band: points within `half` of the sash plane (JS angle, through SASH_C) shifted `off` along
    its normal. Near the top of the shoulder the band eases toward the neck, out of the arm's swing."""
    ca, sa = math.cos(SASH_A), math.sin(SASH_A)

    def f(p):
        sh = SASH_NECK * smoothstep(0.325 * H, 0.38 * H, p[:, 1])
        return np.abs(ca * (p[:, 0] - SASH_C[0] - sh) + sa * (p[:, 1] - SASH_C[1]) - off) - half
    return Sdf(f, [-P.BIG] * 3, [P.BIG] * 3)


def frustum(c, rb, rt, h2):
    """Tapered cylinder along y (radius rb at the bottom, rt at the top), half height h2."""
    c = np.asarray(c, float)

    def f(p):
        q = p - c
        y = q[:, 1]
        rr = rb + (rt - rb) * (np.clip(y, -h2, h2) + h2) / (2 * h2)
        dr = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - rr
        dy = np.abs(y) - h2
        return np.minimum(np.maximum(dr, dy), 0) + np.sqrt(np.maximum(dr, 0) ** 2 + np.maximum(dy, 0) ** 2)
    e = max(rb, rt)
    return Sdf(f, c - [e, h2, e], c + [e, h2, e])


# ------------------------------------------------------------------ sculpted lettering (tattoos)
def text_field(s, size, font="impact", px=0.0007, line_spacing=1.0, resolution=6):
    """2D signed distance (meters, < 0 inside) of a centered text layout: (sampler f(u, v), lo, hi)."""
    cu = bpy.data.curves.new("_ink", "FONT")
    cu.body = s
    cu.font = bpy.data.fonts.load(ck.FONTS.get(font, font), check_existing=True)
    cu.size = size
    cu.resolution_u = resolution
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_line = line_spacing
    ob = bpy.data.objects.new("_ink", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    seg = np.array([[e.verts[0].co.x, e.verts[0].co.y, e.verts[1].co.x, e.verts[1].co.y] for e in bm.edges if e.is_boundary])
    bm.free()
    bpy.data.meshes.remove(me)
    a, b = seg[:, :2], seg[:, 2:]
    pad = 0.006
    lo = np.minimum(a.min(0), b.min(0)) - pad
    hi = np.maximum(a.max(0), b.max(0)) + pad
    nu, nv = int(np.ceil((hi[0] - lo[0]) / px)) + 1, int(np.ceil((hi[1] - lo[1]) / px)) + 1
    U, V = np.meshgrid(lo[0] + np.arange(nu) * px, lo[1] + np.arange(nv) * px, indexing="ij")
    Q = np.stack([U.ravel(), V.ravel()], 1)
    ab = b - a
    L2 = np.maximum((ab ** 2).sum(1), 1e-18)
    aby = np.where(np.abs(ab[:, 1]) < 1e-15, 1e-15, ab[:, 1])
    D = np.empty(len(Q))
    ins = np.zeros(len(Q), bool)
    for i0 in range(0, len(Q), 1500):
        q = Q[i0:i0 + 1500]
        wx = q[:, None, 0] - a[None, :, 0]
        wy = q[:, None, 1] - a[None, :, 1]
        t = np.clip((wx * ab[None, :, 0] + wy * ab[None, :, 1]) / L2[None], 0, 1)
        D[i0:i0 + 1500] = np.sqrt(((wx - t * ab[None, :, 0]) ** 2 + (wy - t * ab[None, :, 1]) ** 2).min(1))
        cond = (a[None, :, 1] > q[:, None, 1]) != (b[None, :, 1] > q[:, None, 1])
        xi = a[None, :, 0] + (q[:, None, 1] - a[None, :, 1]) * ab[None, :, 0] / aby[None]
        ins[i0:i0 + 1500] = ((cond & (q[:, None, 0] < xi)).sum(1) % 2) == 1
    F = np.where(ins, -D, D).reshape(nu, nv)

    def f(u, v):
        fu = (u - lo[0]) / px
        fv = (v - lo[1]) / px
        out = np.full(len(u), pad)
        m = (fu >= 0) & (fu < nu - 1.001) & (fv >= 0) & (fv < nv - 1.001)
        if m.any():
            i, j = np.floor(fu[m]).astype(int), np.floor(fv[m]).astype(int)
            x, y = fu[m] - i, fv[m] - j
            out[m] = (F[i, j] * (1 - x) * (1 - y) + F[i + 1, j] * x * (1 - y) + F[i, j + 1] * (1 - x) * y + F[i + 1, j + 1] * x * y)
        return out
    return f, lo, hi


def ink_sdf(base, field, cx, cy, side, arch=0.0, lift=0.0013 * H, depth=0.0024 * H, zcut=0.0):
    """Tattoo lettering: a text layout projected along z onto `base` (side +1 = front, -1 = back, reads
    from that side), arched on a circle of radius `arch` (0 = straight), raised `lift` above the skin."""
    f2, lo, hi = field

    def f(p):
        d = base.f(p)
        sh = np.maximum(d - lift, -(d + depth))
        X = (p[:, 0] - cx) * side
        Y = p[:, 1] - cy
        if arch:
            u = arch * np.arctan2(X, Y + arch)
            v = np.sqrt(X * X + (Y + arch) ** 2) - arch
        else:
            u, v = X, Y
        return np.maximum(np.maximum(sh, f2(u, v)), (zcut - p[:, 2]) * side)
    w = max(abs(lo[0]), abs(hi[0])) + 0.01 * H
    sag = (w * w / (2 * arch)) if arch else 0.0
    z0, z1 = (zcut, 0.22 * H) if side > 0 else (-0.22 * H, zcut)
    return Sdf(f, [cx - w, cy + lo[1] - sag - 0.01 * H, z0], [cx + w, cy + hi[1] + 0.01 * H, z1])


# ------------------------------------------------------------------ gold rope chain
def rope_sdf(pts, R, amp, pitch, ply=3, n=8):
    """A twisted rope through a closed ring of points: a tube with `ply` helical ridges."""
    P_ = np.array(P.catmull(list(pts) + list(pts[:3]), n))
    P_ = P_[n:n + n * len(pts) + 1]                   # one closed lap
    A, B = P_[:-1], P_[1:]
    AB = B - A
    L = np.linalg.norm(AB, axis=1)
    S0 = np.concatenate([[0], np.cumsum(L)[:-1]])
    T = AB / L[:, None]
    ctr = A.mean(0)
    Nn = A - ctr
    Nn = Nn - T * (Nn * T).sum(1)[:, None]
    Nn /= np.linalg.norm(Nn, axis=1)[:, None]
    Bn = np.cross(T, Nn)
    L2 = L * L

    def f(p):
        out = np.empty(len(p))
        for i0 in range(0, len(p), 4000):
            q = p[i0:i0 + 4000]
            w = q[:, None, :] - A[None]
            t = np.clip((w * AB[None]).sum(2) / L2[None], 0, 1)
            d = w - t[..., None] * AB[None]
            d2 = (d * d).sum(2)
            k = d2.argmin(1)
            ii = np.arange(len(q))
            dv = d[ii, k]
            dist = np.sqrt(d2[ii, k])
            th = np.arctan2((dv * Bn[k]).sum(1), (dv * Nn[k]).sum(1))
            s = S0[k] + t[ii, k] * L[k]
            out[i0:i0 + 4000] = dist - R - amp * np.cos(ply * th - 2 * np.pi * s / pitch)
        return out
    e = R + amp
    return Sdf(f, P_.min(0) - e, P_.max(0) + e)


# ====================================================================== body (replaces person._build_body)
def torso_base(r):
    """Bare torso before the muscle detail: the shirtless loft, a little lat flare, pecs (Body-local)."""
    t = P._torso_body(r)
    t = union(t, symmetric_x(ellipsoid((0.1 * H, 0.235 * H, -0.03 * H), (0.05 * H, 0.085 * H, 0.064 * H), rot=(0, 0, -0.12))), k=0.03 * H)
    # pecs (JS: sph .08H scaled 1, .7, .4 at +-.07H, .27H, .085H), a fan from the sternum up toward the armpit
    t = union(t, symmetric_x(ellipsoid((0.066 * H, 0.27 * H, 0.079 * H), (0.073 * H, 0.05 * H, 0.03 * H), rot=(0, 0, 0.26))), k=0.017 * H)
    return t


ABS_Y = (0.2, 0.164, 0.128)                     # JS rows .17/.125/.08H, lifted clear of the boxers' waistband


def torso_bumps(r, base):
    """Lean and tough, not a bodybuilder: six soft abs, collarbones, shoulder blades, lower-back muscles."""
    t = base
    blocks = []
    for k, y in enumerate(ABS_Y):
        for sx in (-1, 1):
            x = sx * (0.03 + 0.0012 * k) * H + 0.0012 * H * math.sin(7 * k + sx)
            S = on(base, [(x, y * H, 0)], [(0, 0, 1)])[0]
            n = grad(base, [S])[0]
            blocks.append(ellipsoid(S - n * 0.0032 * H, (0.0245 * H, (0.0165 - 0.001 * k) * H, 0.0098 * H)))
    t = union(t, *blocks, k=0.008 * H)
    for sx in (-1, 1):
        t = seam(t, [(sx * x * H, y * H, 0) for x, y in ((0.022, 0.371), (0.07, 0.38), (0.13, 0.387))], [(0, 0.75, 0.7)],
                 0.0052 * H, 0.3 * H)                                                                         # collarbones
    blades = []
    for sx in (-1, 1):
        S = on(base, [(sx * 0.068 * H, 0.288 * H, 0)], [(0, 0, -1)])[0]
        n = grad(base, [S])[0]
        blades.append(ellipsoid(S - n * 0.004 * H, (0.042 * H, 0.05 * H, 0.011 * H), rot=(0, 0, sx * 0.25)))
        S = on(base, [(sx * 0.03 * H, 0.15 * H, 0)], [(0, 0, -1)])[0]
        blades.append(ellipsoid(S - grad(base, [S])[0] * 0.004 * H, (0.022 * H, 0.07 * H, 0.0095 * H)))
    return union(t, *blades, k=0.014 * H)


def torso_grooves(r, t):
    """The pressed lines that define the muscles: linea alba, tendon lines, six-pack edges, pec lines, spine."""
    base = t
    cr = 0.0029 * H
    t = groove(t, [(0, y * H, 0) for y in (0.226, 0.19, 0.155, 0.118)], [(0, 0, 1)], 0.0031 * H, 0.3 * H)       # linea alba
    for y in (0.182, 0.146):                                                                                   # tendon lines
        t = groove(t, [(x * H, (y + 0.004 * abs(x) / 0.055) * H, 0) for x in (-0.057, -0.028, 0, 0.028, 0.057)], [(0, 0, 1)], cr, 0.3 * H)
    for sx in (-1, 1):
        t = groove(t, [(sx * x * H, y * H, 0) for x, y in ((0.06, 0.222), (0.063, 0.175), (0.057, 0.132), (0.04, 0.112))],
                   [(sx * 0.35, 0, 1)], 0.0031 * H, 0.3 * H)                                                  # outer edge of the six-pack
        t = groove(t, [(sx * x * H, y * H, 0) for x, y in ((0.012, 0.229), (0.05, 0.222), (0.095, 0.229), (0.128, 0.252), (0.143, 0.282))],
                   [(sx * 0.3, -0.25, 1)], 0.0034 * H, 0.3 * H)                                               # under the pecs
    t = groove(t, [(0, y * H, 0) for y in (0.31, 0.27, 0.235)], [(0, 0, 1)], 0.0028 * H, 0.3 * H)              # sternum
    notch = on(base, [(0, 0.372 * H, 0)], [(0, 0.5, 1)])[0]
    t = subtract(t, sphere(notch + np.array([0, 0, 0.004 * H]), 0.009 * H), k=0.006 * H)
    t = groove(t, [(0, y * H, 0) for y in (0.345, 0.29, 0.23, 0.17, 0.115)], [(0, 0, -1)], 0.0042 * H, 0.3 * H)     # spine
    return t


def jeans_sdf(r, base):
    """The pelvis in jeans: the builder's pelvis, a waistband all the way round, belt loops, back pockets."""
    pel = P._pelvis_sdf(r)
    pel = union(pel, intersect(offset(union(pel, base), 0.0042 * H), slab(0.018 * H, 0.054 * H), k=0.002 * H), k=0.002 * H)
    plain = pel
    loops = []
    for ang in (-150, -112, -62, 62, 112, 150, 180):
        a = math.radians(ang)
        d = (math.sin(a), 0, math.cos(a))
        S = on(pel, [(d[0] * 0.2 * H, 0.032 * H, d[2] * 0.2 * H)], [d], 0.3 * H)[0]
        n = grad(pel, [S])[0]
        n[1] = 0
        n /= np.linalg.norm(n)
        loops.append(rbox(S + n * 0.0034 * H, (0.0058 * H, 0.0175 * H, 0.0028 * H), 0.0022 * H, rot=frame((0, 1, 0), n)))
    pel = union(pel, *loops, k=0.0015 * H)
    pockets = []
    for sx in (-1, 1):   # back pockets: pentagons on the seat with a stitched top hem
        pts = [(sx * x * H, y * H) for x, y in ((0.026, 0.012), (0.094, 0.01), (0.09, -0.034), (0.06, -0.05), (0.03, -0.036))]
        reg = intersect(poly2d(pts), halfspace((0, 0, -0.03 * H), (0, 0, 1)))
        pk = intersect(shell(plain, 0.0042 * H, 0.003 * H), reg, k=0.0012 * H)
        pk = groove(pk, [(sx * x * H, 0.004 * H, 0) for x in (0.03, 0.06, 0.09)], [(0, 0, -1)], 0.0013 * H, 0.3 * H)
        pockets.append(pk)
    fly = on(pel, [(0.0, 0.034 * H, 0)], [(0, 0, 1)], 0.3 * H)[0]
    return pel, plain, fly, union(*pockets)


def build_body(r):
    H_, M = r.H, r.mats
    log("body: torso")
    base = torso_base(r)
    bumps = torso_bumps(r, base)
    torso = lumped(torso_grooves(r, bumps), 0.0007 * H, 22)
    torso = intersect(torso, halfspace((0, 0.014 * H, 0), (0, -1, 0)), k=0.004 * H)    # nothing under the jeans
    skin = offset(bumps, 0.0008 * H)              # the skin's outer envelope (no grooves): parts fitted over it
    r.sdf["torso"] = base
    r.sdf["torso_skin"] = torso
    parts = [P.sdf_mesh("Body_top", torso, M["skin"], 0.002 * H, 2400)]
    log("body: jeans")
    pel, plain, fly, pockets = jeans_sdf(r, base)
    parts.append(P.sdf_mesh("Body_pelvis", pel, M["pants"], 0.0022 * H, 1000, lumps=0.0006 * H, seed=23))
    parts.append(P.sdf_mesh("Body_pockets", pockets, ck.clay("#36568a", 0.86), 0.0012 * H, 260))
    parts.append(P.sdf_mesh("Body_button", sphere(fly + np.array([0, 0, 0.002 * H]), 0.0062 * H), ck.metal("#c8b070", 0.35), 0.0008 * H, 90))
    # boxers' waistband above the jeans: three rolled ribs, red / white / red (JS: rings R .135H at .06/.08/.10H)
    log("body: waistband")
    ribs = [intersect(shell(skin, 0.0086 * H, 0.008 * H), slab((0.062 + 0.02 * k - 0.0098) * H, (0.062 + 0.02 * k + 0.0098) * H), k=0.0056 * H)
            for k in range(3)]
    band = union(*ribs, k=0.0012 * H)
    parts.append(P.sdf_mesh("Body_boxers", band, P.stripes([RED, CREAM, RED], 0.02 * H, phase=0.052 * H, rough=0.8), 0.0016 * H, 850))
    # the hall-monitor sash rides over skin, waistband and jeans
    log("body: sash")
    # it must clear the shoulder caps wherever the arms usually swing (rest, walk and run, the idle raise, cuffed)
    cap = intersect(union(sphere((0, 0, 0), 0.0466 * H), ellipsoid((0.004 * H, -0.03 * H, 0.0), (0.048 * H, 0.051 * H, 0.048 * H)), k=0.02 * H),
                    halfspace((0, -0.07 * H, 0), (0, -1, 0)))
    caps = []
    for rx, out in ((0.0, 0.08), (-0.6, 0.25), (-1.2, 0.3), (0.6, 0.2), (1.3, 0.1)):
        caps += [xform(cap, pos=(0.185 * H, 0.31 * H, 0), rot=(rx, 0, out)), xform(P.mirror_x(cap), pos=(-0.185 * H, 0.31 * H, 0), rot=(rx, 0, -out))]
    ribs_env = intersect(offset(skin, 0.009 * H), slab(0.044 * H, 0.122 * H), k=0.014 * H)     # soft rims: no dips over the ribs
    support = union(skin, ribs_env, offset(plain, 0.0034 * H), union(*caps), k=0.006 * H)
    sash = intersect(shell(support, SASH_T, 0.009 * H), sash_slab(0.0, SASH_W / 2), k=0.0018 * H)
    lines = shell(support, SASH_T + 0.004 * H, 0.0016 * H - SASH_T)
    for e in (-1, 1):
        sash = subtract(sash, intersect(lines, sash_slab(e * (SASH_W / 2 - 0.0058 * H), 0.0008 * H)), k=0.001 * H)
    r.sdf["sash"] = sash
    parts.append(P.sdf_mesh("Body_sash", sash, ck.clay(ORANGE, 0.8), 0.0015 * H, 1100))
    # gold rope chain around the neck, draped down to the whistle
    log("body: chain")
    over = union(skin, sash, k=0.002 * H)
    R = 0.0064 * H
    path = [((0.0, 0.378, -0.07), (0, 0.45, -1)), ((0.045, 0.383, -0.06), (0.4, 0.7, -0.7)), ((0.078, 0.39, -0.02), (0.3, 1, -0.1)),
            ((0.088, 0.383, 0.03), (0.3, 1, 0.45)), ((0.082, 0.355, 0.08), (0.25, 0.6, 1)), ((0.072, 0.318, 0.1), (0.1, 0.15, 1)),
            ((0.055, 0.29, 0.11), (0, 0, 1)), ((0.019, 0.278, 0.115), (0, 0, 1)), ((-0.018, 0.29, 0.11), (0, 0, 1)),
            ((-0.036, 0.318, 0.1), (-0.1, 0.15, 1)), ((-0.06, 0.356, 0.08), (-0.25, 0.6, 1)), ((-0.08, 0.383, 0.03), (-0.3, 1, 0.45)),
            ((-0.078, 0.39, -0.02), (-0.3, 1, -0.1)), ((-0.045, 0.383, -0.06), (-0.4, 0.7, -0.7))]
    ctrl = [np.array(q) * H for q, nn in path]
    nrm = [np.array(nn, float) / np.linalg.norm(nn) for q, nn in path]
    m = len(ctrl)
    dense, dn = [], []
    for i in range(m):
        p0, p1, p2, p3 = ctrl[(i - 1) % m], ctrl[i], ctrl[(i + 1) % m], ctrl[(i + 2) % m]
        for j in range(5):
            t = j / 5
            dense.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
            nv = nrm[i] * (1 - t) + nrm[(i + 1) % m] * t
            dn.append(nv / np.linalg.norm(nv))
    cp = on(over, np.array(dense), np.array(dn), 0.06 * H, lift=R * 0.85)
    cp = (np.roll(cp, 1, 0) + 2 * cp + np.roll(cp, -1, 0)) / 4
    gold = ck.metal(GOLD, 0.32)
    parts.append(P.sdf_mesh("Body_chain", rope_sdf(cp, R, 0.0016 * H, 0.021 * H, n=2), gold, 0.0011 * H, 600))
    # the whistle he blows at Grandma (JS: gold cyl r .025H, .07H long at (0, .25H, .12H)), hanging off the chain
    log("body: whistle")
    front = cp[:, 2] > 0.05 * H
    bottom = cp[front][np.argmin(cp[front][:, 1])]
    S = on(over, [(bottom[0] + 0.004 * H, 0.252 * H, 0)], [(0, 0, 1)])[0]
    nrm = grad(over, [S])[0]
    c = S + nrm * 0.0125 * H
    c[1] = 0.252 * H
    wh = union(cylinder((0, 0, 0), 0.021 * H, 0.0115 * H, round_=0.0045 * H, rot=(math.pi / 2, 0, 0)),
               rbox((-0.033 * H, 0.0075 * H, 0), (0.02 * H, 0.0068 * H, 0.0088 * H), 0.0034 * H), k=0.004 * H)
    wh = subtract(wh, rbox((-0.007 * H, 0.021 * H, 0), (0.0062 * H, 0.0065 * H, 0.013 * H), 0.0012 * H), k=0.0015 * H)   # sound window
    wh = subtract(wh, rbox((-0.054 * H, 0.0075 * H, 0), (0.004 * H, 0.0026 * H, 0.0052 * H), 0.001 * H))               # blow hole
    wh = union(wh, torus((-0.004 * H, 0.0285 * H, 0), 0.0092 * H, 0.0021 * H, rot=(0, 0, -math.pi / 2)), k=0.0015 * H)   # bail
    wh = xform(wh, pos=c, rot=(0, 0, 0.12))
    parts.append(P.sdf_mesh("Body_whistle", wh, gold, 0.0008 * H, 360))
    # tattoos, dark ink pressed onto the skin (exact JS wording)
    ink = ck.clay(INK, 0.45)          # a little sheen so the letters still read on his shaded back
    log("body: tattoos")
    for nm, txt, em, cx, cy, side, arch, tgt in TATTOOS:
        fld = text_field(txt, em)
        print(f"[two_pack] tattoo {nm}: {txt!r} em {em / H:.4f}H  width {(fld[2][0] - fld[1][0] - 0.012) / H:.3f}H  height {(fld[2][1] - fld[1][1] - 0.012) / H:.3f}H")
        parts.append(P.sdf_mesh("Tattoo_" + nm, ink_sdf(torso, fld, cx, cy, side, arch=arch), ink, 0.0009 * H, tgt))
    r.meshes["Body"] = ck.join([p for p in parts if p], "Body_Mesh")
    P.attach(r.meshes["Body"], r.body)
    log("body: done")


# (name, text, em size, Body-local center x, y, side +1 front / -1 back (reads from behind), arch radius, tris)
# 911 and the back lines sit where the sash strap leaves them readable (JS: 911 at x 0, the back block centered)
TATTOOS = [("911", "911", 0.042 * H, 0.02 * H, 0.305 * H, 1, 0.0, 200),
           ("snitch", "SNITCH 4 LIFE", 0.044 * H, -0.038 * H, 0.135 * H, 1, 0.42 * H, 620),
           ("neighborhood", "NEIGHBORHOOD", 0.046 * H, 0.056 * H, 0.345 * H, -1, 1.2 * H, 620),
           ("watch", "WATCH", 0.046 * H, -0.056 * H, 0.177 * H, -1, 0.0, 280)]


# ====================================================================== arms (replaces person._build_arms)
def build_arms(r):
    """Bare arms, lean and tough: deltoid cap, biceps, triceps, elbow, forearm, the builder's mitten hand."""
    M = r.mats
    hand = P._hand_sdf(r)
    r.sdf["hand"] = hand
    a = union(sphere((0, 0, 0), 0.0455 * H), ellipsoid((0.004 * H, -0.03 * H, 0.0), (0.047 * H, 0.05 * H, 0.047 * H)), k=0.02 * H)
    a = union(a, round_cone((0, -0.03 * H, 0), (0, -0.152 * H, 0.002 * H), 0.041 * H, 0.034 * H), k=0.02 * H)
    a = union(a, ellipsoid((0.0, -0.097 * H, 0.012 * H), (0.03 * H, 0.047 * H, 0.029 * H)), k=0.014 * H)
    a = union(a, ellipsoid((0.003 * H, -0.085 * H, -0.011 * H), (0.033 * H, 0.054 * H, 0.029 * H)), k=0.014 * H)
    a = union(a, sphere((0.0, -0.158 * H, -0.005 * H), 0.03 * H), k=0.016 * H)
    a = union(a, round_cone((0, -0.162 * H, 0.002 * H), (0, -0.252 * H, 0.004 * H), 0.034 * H, 0.027 * H), k=0.016 * H)
    a = union(a, ellipsoid((0.004 * H, -0.186 * H, 0.004 * H), (0.035 * H, 0.04 * H, 0.032 * H)), k=0.014 * H)
    a = union(a, hand, k=0.012 * H)
    specs = [("arm", a, M["sleeve"], 0.0015 * H, 1220, 0.0005 * H, 32)]
    for side, pv, nm in ((1, r.armL, "ArmL"), (-1, r.armR, "ArmR")):
        ob = ck.join(P._sided(nm, specs, side), nm + "_Mesh")
        P.attach(ob, pv)
        r.meshes[nm] = ob


# ====================================================================== sneakers (wraps person._shoe_sdfs)
_shoe_sdfs0 = P._shoe_sdfs


def shoe_sdfs(r):
    upper, sole, extras = _shoe_sdfs0(r)
    yg = -0.47 * H
    # red heel counter: reads from the camera behind him
    heel = intersect(offset(upper, 0.0017 * H), halfspace((0, 0, -0.024 * H), (0, 0, 1)), k=0.003 * H)
    heel = intersect(heel, halfspace((0, yg + 0.058 * H, -0.04 * H), (0, 1, 0.55)), k=0.003 * H)
    heel = intersect(heel, halfspace((0, yg + 0.011 * H, 0), (0, -1, 0)))
    # a red side stripe sweeping from the collar down to the ball of the foot (both sides)
    pts = [(-z * H, yg + y * H) for z, y in ((-0.034, 0.058), (0.0, 0.049), (0.034, 0.037), (0.074, 0.023), (0.08, 0.011),
                                             (0.036, 0.018), (0.0, 0.028), (-0.036, 0.037))]
    stripe = xform(poly2d(pts[::-1]), rot=(0, math.pi / 2, 0))
    stripe = intersect(intersect(offset(upper, 0.0016 * H), stripe, k=0.0008 * H), symmetric_x(halfspace((0.024 * H, 0, 0), (-1, 0, 0))))
    extras += [(heel, "accent"), (stripe, "accent")]
    # tread: pressed bars under the sole (the camera sees them when a foot swings back)
    bars = [rbox((0, yg, z * H), (0.06 * H, 0.0024 * H, 0.0032 * H), 0.0012 * H) for z in np.linspace(-0.045, 0.112, 9)]
    sole = subtract(sole, union(*bars), k=0.001 * H)
    return upper, sole, extras


def build_legs(r):
    """person._build_legs with the red accents and a tighter triangle budget."""
    M = r.mats
    M["accent"] = ck.clay(RED, 0.6)
    leg = P._leg_sdf(r)
    upper, sole, extras = P._shoe_sdfs(r)
    specs = [("pants", leg, M["pants"], 0.0024 * H, 560, 0.0007 * H, 3),
             ("shoe", upper, M["shoe"], 0.0016 * H, 480, 0.0005 * H, 4),
             ("sole", sole, M["sole"], 0.0016 * H, 220, 0.0, 5)]
    for i, (sd, key) in enumerate(extras):
        specs.append((key + str(i), sd, M[key], 0.0011 * H, 150 if key == "lace" else 170, 0.0, 6 + i))
    for side, pv, nm in ((1, r.legL, "LegL"), (-1, r.legR, "LegR")):
        ob = ck.join(P._sided(nm, specs, side), nm + "_Mesh")
        P.attach(ob, pv)
        r.meshes[nm] = ob


# ====================================================================== face (wraps / replaces person head parts)
_head_skin0 = P._head_skin


def head_skin(r):
    s = _head_skin0(r)
    hy = r.hy
    # the half smile: his left cheek bunched up, a dimple at that corner of the mouth
    s = union(s, ellipsoid((0.054 * H, hy - 0.031 * H, 0.074 * H), (0.025 * H, 0.019 * H, 0.021 * H)), k=0.013 * H)
    s = groove(s, [(0.045 * H, hy - 0.026 * H, 0), (0.051 * H, hy - 0.04 * H, 0), (0.049 * H, hy - 0.056 * H, 0)], [(0.35, 0, 1)], 0.0021 * H, 0.3 * H)
    for y, w in ((0.042, 0.034), (0.06, 0.028)):     # folds where the skull meets the neck at the back
        s = groove(s, [(x * w * H, y * H, 0) for x in (-1, -0.5, 0, 0.5, 1)], [(0, 0, -1)], 0.0021 * H, 0.3 * H)
    return s


LID_SKEW = 0.06      # his right lid heavier than the left: a lazy, sure-of-himself squint


def build_eyes(r, parts):
    """person._build_eyes with uneven lids and a smaller budget."""
    o, M = r.opts, r.mats
    re = 0.026 * H * o["eye_size"]
    gx, gy = o["gaze"]
    g = P._unit((math.sin(gx), math.sin(gy), 1.0))
    gh = P._unit(g + np.array([0.3, 0.36, 0.0]))
    for side, E in zip((-1, 1), P._eye_centers(r)):
        nm = "R" if side < 0 else "L"
        parts.append(ck.sph(re, tuple(E), M["white"], segs=16, rings=10, name=f"Eye{nm}_ball"))
        R1 = re + 0.0016 * H
        pupil = intersect(sphere(E, R1), sphere(E + g * R1, 0.0135 * H * o["pupil"]), k=0.0007 * H)
        parts.append(P.sdf_mesh(f"Eye{nm}_pupil", pupil, M["black"], 0.00045 * H, 130, project_iters=3))
        R2 = R1 + 0.0009 * H
        hl = intersect(sphere(E, R2), sphere(E + gh * R2, 0.0043 * H), k=0.0004 * H)
        parts.append(P.sdf_mesh(f"Eye{nm}_shine", hl, M["shine"], 0.0003 * H, 50, project_iters=3))
        lid = P._lid_sdf(r, E, side, o["lid"] - LID_SKEW * side, o["lid_tilt"])
        if o["lid_low"] > 0:
            lid = union(lid, P._lid_sdf(r, E, side, o["lid_low"], -0.5 * o["lid_tilt"], lower=True))
        parts.append(P.sdf_mesh(f"Eye{nm}_lids", lid, M["skin"], 0.0006 * H, 280, project_iters=3))


def build_head(r):
    """person._build_head for a bald head; the skin decimated without symmetry (the smirk) to a smaller budget."""
    M = r.mats
    hy = r.hy
    skin = P._head_skin(r)
    r.sdf["head"] = skin
    parts = [P.sdf_mesh("Head_skin", skin, M["skin"], 0.0013 * H, 2500, lumps=0.0005 * H, seed=51)]
    fmap = P.FaceMap(skin, -0.11 * H, 0.11 * H, hy - 0.13 * H, hy + 0.11 * H, 0.3 * H, -0.05 * H)
    r.face = fmap
    build_eyes(r, parts)
    build_brows(r, fmap, parts)
    r.meshes["Head"] = ck.join([p for p in parts if p], "Head_Mesh")
    P.attach(r.meshes["Head"], r.head)
    r.mouth = P._mouth_meshes(r, fmap)


BROWS = {-1: dict(raise_=-0.007, tilt=-0.32, arch=0.6, thick=1.08, length=1.06),   # his right: low and flat, unimpressed
         1: dict(raise_=0.0015, tilt=0.16, arch=2.2, thick=1.05, length=1.05)}    # his left: cocked


def build_brows(r, fmap, parts):
    segs = []
    for side, E in zip((-1, 1), P._eye_centers(r)):
        b = BROWS[side]
        L = b["length"]
        xs = [E[0] - side * 0.021 * H * L, E[0] + side * 0.006 * H, E[0] + side * 0.026 * H * L]
        ys = [E[1] + (0.040 + b["raise_"] + 0.006 * b["tilt"]) * H, E[1] + (0.045 + b["raise_"] + 0.003 * (b["arch"] - 1)) * H,
              E[1] + (0.036 + b["raise_"] - 0.004 * b["tilt"]) * H]
        rads = np.array([0.0064, 0.0066, 0.0042]) * H * b["thick"]
        pts = [(x, y, float(fmap(x, y)) + rr * 0.15) for x, y, rr in zip(xs, ys, rads)]
        segs.append(tube(pts, list(rads), n=6))
    parts.append(P.sdf_mesh("Brows", union(*segs), r.mats["brow"], 0.0008 * H, 360))


SMIRK = 0.011     # one-sided corner lift (H): his left corner curls up, still readable squashed to 0.3


def mouth_meshes(r, fmap):
    """person._mouth_meshes with a lopsided smile: modeled open, the game squashes it to 0.3 when shut."""
    o, M = r.opts, r.mats
    M0 = np.array([0, 0.115 * H, 0.1 * H])
    w = 0.036 * H * o["mouth_w"]
    h = 0.021 * H
    sm = 0.007 * H * o["smile"]
    sk = SMIRK * H

    def c(xn):
        return sm * xn * xn + sk * 0.5 * (xn + xn * xn)

    def fz(x, y):
        return fmap(x, y + M0[1]) - M0[2]
    th = np.linspace(0, 2 * np.pi, 28, endpoint=False)
    X = w * np.cos(th)
    Y = h * np.sin(th) + c(np.cos(th))
    rl = 0.004 * H + np.where(np.sin(th) > 0, 0.0009 * H, 0.0023 * H) * np.abs(np.sin(th))
    Z = fz(X, Y) + 0.0032 * H
    lips = P.loop_tube([(x, y, z) for x, y, z in zip(X, Y, Z)], list(rl))

    def rho(p):
        x = np.clip(p[:, 0] / w, -1.5, 1.5)
        return np.sqrt(x * x + ((p[:, 1] - c(x)) / h) ** 2)
    kd = 0.0016 * H

    def dish(p):
        rh = rho(p)
        zf = fz(p[:, 0], p[:, 1])
        front = zf + 0.0012 * H + 0.0045 * H * np.minimum(rh, 1.2) ** 2
        return P.smax(P.smax((rh - 1.0) * min(w, h), p[:, 2] - front, kd), (zf - 0.006 * H) - p[:, 2], kd)
    up = abs(sm) + abs(sk)
    inside = Sdf(dish, [-w * 1.1, -h * 1.2 - up, -0.06 * H], [w * 1.1, h * 1.2 + up, 0.06 * H])
    tz = float(fz(0.0, -h * 0.62))
    tongue = intersect(ellipsoid((0, -h * 0.62, tz - 0.0012 * H), (w * 0.5, h * 0.36, 0.0062 * H)),
                       Sdf(lambda p: (rho(p) - 0.94) * min(w, h), [-w, -h * 2 - up, -P.BIG], [w, h * 2 + up, P.BIG]))
    # upper teeth just inside the top lip: squashed shut they leave a white grin line, with one gold tooth
    def teeth_f(p):
        x = np.clip(p[:, 0] / w, -1.5, 1.5)
        zf = fz(p[:, 0], p[:, 1])
        d_in = (rho(p) - 0.9) * min(w, h)
        d_low = (c(x) + 0.12 * h) - p[:, 1]
        d_z = np.maximum(p[:, 2] - (zf + 0.0029 * H), (zf - 0.003 * H) - p[:, 2])
        return np.maximum(np.maximum(d_in, d_low), d_z)
    teeth = Sdf(teeth_f, [-w, -h - up, -0.06 * H], [w, h + up, 0.06 * H])
    for xn in (-0.62, -0.36, -0.12, 0.12, 0.36, 0.62):
        x0 = xn * w
        y0 = float(c(np.array([xn]))[0]) + 0.7 * h
        z0 = float(fz(x0, y0)) + 0.003 * H
        teeth = subtract(teeth, capsule((x0, y0 - 0.55 * h, z0), (x0, y0 + 0.4 * h, z0), 0.0011 * H), k=0.0006 * H)
    gx0 = 0.5 * w
    gold = intersect(teeth, rbox((gx0, 0.0, 0.0), (0.12 * w, h * 1.5, 0.05 * H), 0.001 * H))
    teeth = subtract(teeth, rbox((gx0, 0.0, 0.0), (0.12 * w, h * 1.5, 0.05 * H), 0.001 * H))
    objs = [P.sdf_mesh("Mouth_lips", lips, M["lips"], 0.0007 * H, 340),
            P.sdf_mesh("Mouth_inside", inside, M["mouth"], 0.0007 * H, 200),
            P.sdf_mesh("Mouth_tongue", tongue, M["tongue"], 0.0007 * H, 110),
            P.sdf_mesh("Mouth_teeth", teeth, ck.gloss("#f2eee4", 0.35), 0.0005 * H, 150),
            P.sdf_mesh("Mouth_goldtooth", gold, ck.metal(GOLD, 0.32), 0.0005 * H, 50)]
    mouth = ck.join([x for x in objs if x], "Mouth")
    P.attach(mouth, r.head, tuple(M0))
    return mouth


P._build_body = build_body
P._build_arms = build_arms
P._shoe_sdfs = shoe_sdfs
P._build_legs = build_legs
P._head_skin = head_skin
P._build_head = build_head
P._build_brows = build_brows
P._mouth_meshes = mouth_meshes


# ====================================================================== head pieces
def ribbon(path, widths, thick, twist=0.0, k=0.004 * H):
    """A cloth strip along a path (bandana tails): chained rounded slabs; widths and thicknesses per point."""
    path = [np.asarray(p, float) for p in P.catmull(path, 2)]
    m = len(path)
    wid = np.interp(np.linspace(0, 1, m), np.linspace(0, 1, len(widths)), widths)
    th = np.interp(np.linspace(0, 1, m), np.linspace(0, 1, len(thick)), thick) if not np.isscalar(thick) else np.full(m, thick)
    segs = []
    for i in range(m - 1):
        a, b = path[i], path[i + 1]
        d = b - a
        ln = np.linalg.norm(d)
        tw = twist * (i + 0.5) / (m - 1)
        R = frame(d, np.array([math.sin(tw), 0.0, -math.cos(tw)]))
        w, t = 0.5 * (wid[i] + wid[i + 1]), 0.5 * (th[i] + th[i + 1])
        segs.append(rbox((a + b) / 2, (w / 2, ln / 2 + t * 0.6, t / 2), t * 0.49, rot=R))
    return union(*segs, k=k)


def bandana(r):
    """Red bandana (JS: torus hs*.98 at hy+hs*.42, knot at the back, two cone tails): a folded band hugging
    the skull, worn a little rakish, a lumpy square knot low on the back of the head and two cloth tails."""
    head = r.sdf["head"]
    t, rl = BAND_TILT, BAND_ROLL
    n = np.array([-math.cos(t) * math.sin(rl), math.cos(t) * math.cos(rl), -math.sin(t)])
    c = np.array([0.0, BAND_Y, 0.0])
    band = intersect(shell(head, BAND_T, 0.006 * H), plane_slab(c, n, BAND_H / 2), k=BAND_T * 0.75)
    # a soft roll along the middle of the folded band
    band = union(band, intersect(shell(head, BAND_T + 0.0024 * H, 0.004 * H), plane_slab(c + n * 0.002 * H, n, BAND_H * 0.22), k=0.0045 * H), k=0.004 * H)
    # the knot at the back center of the band: a fat wrap with two lobes, in the skull's local frame
    back = np.array([0.0, -math.sin(t), -math.cos(t)])
    K0 = c + back * (0.3 * H - P.ray_hit(head, [c + back * 0.3 * H], [-back], 0.3 * H)[0])
    w_ = grad(head, [K0])[0]                                   # out of the skull
    v_ = np.array([0.0, 1.0, 0.0]) - w_ * w_[1]
    v_ /= np.linalg.norm(v_)                                   # up along the skull
    u_ = np.cross(v_, w_)
    R = np.stack([u_, v_, w_], 1)
    K = K0 + w_ * (BAND_T + 0.0095 * H)

    def at(x, y, z):
        return K + (u_ * x + v_ * y + w_ * z) * H
    knot = union(ellipsoid(K, (0.023 * H, 0.019 * H, 0.0155 * H), rot=R),
                 *[ellipsoid(at(e * 0.018, 0.004, -0.003), (0.0155 * H, 0.0125 * H, 0.012 * H), rot=R @ P.rotm((0, 0, -e * 0.5))) for e in (-1, 1)],
                 k=0.006 * H)
    for e in (-1, 1):   # creases where the cloth wraps into the knot
        knot = groove(knot, [at(e * 0.009, y, 0.03) for y in (0.013, 0.0, -0.013)], [w_], 0.0017 * H, 0.05 * H)
    knot = groove(knot, [at(x, 0.0, 0.03) for x in (-0.007, 0.0, 0.007)], [w_], 0.0013 * H, 0.05 * H)
    tails = []
    for e, tw in ((-1, 0.45), (1, -0.35)):
        side = e * math.copysign(1.0, u_[0])     # tails hang straight down (world axes), not along the tilted skull frame
        rel = [(0.007, -0.012, 0.004), (0.013, -0.033, 0.006), (0.021, -0.058, 0.004), (0.03, -0.081, -0.001), (0.036, -0.097, -0.006)]
        path = [K + np.array([side * x, y, z]) * H for x, y, z in rel]
        tl = ribbon(path, [0.019 * H, 0.025 * H, 0.03 * H, 0.033 * H, 0.032 * H], [0.0075 * H, 0.0068 * H, 0.006 * H, 0.0052 * H, 0.0048 * H], twist=tw)
        tip = path[-1]
        tl = intersect(tl, halfspace(tip + np.array([0, 0.004 * H, 0]), (side * 0.55, -1.0, 0.0)), k=0.002 * H)   # cut on the bias
        tl = groove(tl, [path[1], path[2], path[3] + np.array([0, 0.004 * H, 0])], [(0, 0, -1)], 0.0016 * H, 0.03 * H)
        tails.append(tl)
    red = ck.clay(RED, 0.85)
    parts = [P.sdf_mesh("Bandana_band", lumped(band, 0.0004 * H, 61), red, 0.0011 * H, 1000),
             P.sdf_mesh("Bandana_knot", lumped(union(knot, *tails, k=0.004 * H), 0.0003 * H, 62), red, 0.0008 * H, 600)]
    return ck.join(parts, "Bandana")


def teardrop(r):
    """Teardrop tattoo under his right eye (JS: sph .01H scaled .8, 1.6, .6 at (-.042H, hy-.035H, .11H))."""
    hy = r.hy
    cx, cy = -0.042 * H, hy - 0.035 * H
    drop = union(ellipse2d((cx, cy - 0.004 * H), 0.0068 * H, 0.0075 * H),
                 poly2d([(cx - 0.0056 * H, cy - 0.003 * H), (cx + 0.0056 * H, cy - 0.003 * H), (cx + 0.0012 * H, cy + 0.0128 * H)]), k=0.003 * H)
    region = intersect(drop, halfspace((0, 0, 0.05 * H), (0, 0, -1)))
    d = intersect(shell(r.sdf["head"], 0.0012 * H, 0.002 * H), region, k=0.0006 * H)
    return P.sdf_mesh("Teardrop", d, ck.clay(INK, 0.45), 0.0005 * H, 140)


# ====================================================================== toggled accessories
def binoculars(r):
    """Binoculars (JS: two #1a1a1e barrels r .025-.03H, .1H long at x +-.042H, Head-local (0, hy+.02H, .17H)):
    straight barrels with objective bells, rubber eyecups, a hinge and bridges, a focus wheel, lenses."""
    body = []
    zx = (math.pi / 2, 0, 0)
    for sx in (-1, 1):
        x = sx * 0.042 * H
        body += [cylinder((x, 0, 0.002 * H), 0.0258 * H, 0.036 * H, round_=0.006 * H, rot=zx),
                 cylinder((x, 0, 0.039 * H), 0.03 * H, 0.011 * H, round_=0.0045 * H, rot=zx),
                 cylinder((x, 0, -0.039 * H), 0.0198 * H, 0.009 * H, round_=0.003 * H, rot=zx)]
    sh = union(*body, cylinder((0, 0.007 * H, 0.004 * H), 0.0105 * H, 0.028 * H, round_=0.004 * H, rot=zx),
               *[rbox((0, 0.009 * H, z * H), (0.04 * H, 0.0058 * H, 0.0068 * H), 0.0028 * H) for z in (-0.021, 0.026)], k=0.004 * H)
    for sx in (-1, 1):
        x = sx * 0.042 * H
        sh = subtract(sh, cylinder((x, 0, 0.052 * H), 0.0236 * H, 0.004 * H, round_=0.0012 * H, rot=zx), k=0.0012 * H)
        sh = subtract(sh, cylinder((x, 0, -0.05 * H), 0.0125 * H, 0.004 * H, round_=0.001 * H, rot=zx), k=0.001 * H)
        for z in (-0.016, -0.004, 0.008, 0.02):           # rubber armour grip rings
            sh = subtract(sh, torus((x, 0, z * H), 0.0264 * H, 0.0013 * H, rot=zx), k=0.0008 * H)
        sh = union(sh, torus((x, 0, -0.048 * H), 0.0168 * H, 0.0047 * H, rot=zx), k=0.002 * H)     # eyecup
    wheel = cylinder((0, 0.02 * H, -0.013 * H), 0.0085 * H, 0.0062 * H, round_=0.0018 * H, rot=(0, 0, math.pi / 2))
    for k in range(10):
        a = 2 * math.pi * k / 10
        wheel = subtract(wheel, capsule((-0.008 * H, 0.02 * H + 0.0088 * H * math.cos(a), -0.013 * H + 0.0088 * H * math.sin(a)),
                                        (0.008 * H, 0.02 * H + 0.0088 * H * math.cos(a), -0.013 * H + 0.0088 * H * math.sin(a)), 0.0012 * H))
    sh = union(sh, wheel, k=0.002 * H)
    parts = [P.sdf_mesh("Bino_body", sh, ck.clay(DARK, 0.45), 0.0009 * H, 420)]
    lens = union(*[cylinder((sx * 0.042 * H, 0, 0.0492 * H), 0.0238 * H, 0.0012 * H, round_=0.0006 * H, rot=zx) for sx in (-1, 1)])
    parts.append(P.sdf_mesh("Bino_lens", lens, ck.gloss("#2a3a5a", 0.12), 0.0008 * H, 90))
    rims = union(*[torus((sx * 0.042 * H, 0, 0.0508 * H), 0.0258 * H, 0.0021 * H, rot=zx) for sx in (-1, 1)])
    parts.append(P.sdf_mesh("Bino_rims", rims, ck.metal("#9aa0a8", 0.35), 0.0007 * H, 130))
    b = ck.join(parts, "Binoculars")
    return P.attach(b, r.head, (0, r.hy + 0.02 * H, 0.17 * H))


def cup(r):
    """Timmy's lemonade (state.js: cyl r .05/.04, .13 tall, yellow #f8e04a at arm-local (0, -.33H, .04)):
    a tapered cup with a rolled rim, lemonade inside and a bendy straw. The node sits on the JS spot;
    the cup is nudged up and forward inside it so the mitten wraps its back instead of sinking in."""
    off = np.array([-0.008, 0.024, 0.046])
    cp = union(frustum(off, 0.04, 0.05, 0.065), torus(off + [0, 0.063, 0], 0.0492, 0.0034), k=0.002)
    cp = subtract(cp, frustum(off + [0, 0.07, 0], 0.0444, 0.0468, 0.034), k=0.002)
    for y in (-0.05, -0.044):
        cp = subtract(cp, torus(off + [0, y, 0], 0.0406 + (y + 0.065) * 0.0769, 0.0011), k=0.0007)
    parts = [P.sdf_mesh("Cup_cup", cp, ck.clay("#f8e04a", 0.45), 0.0012, 240)]
    parts.append(P.sdf_mesh("Cup_lemonade", cylinder(off + [0, 0.036, 0], 0.0452, 0.0022, round_=0.0008), ck.gloss("lane_yellow", 0.2), 0.0012, 90))
    straw = tube([off + [0.012, 0.03, -0.006], off + [0.017, 0.1, -0.012], off + [0.021, 0.117, -0.016], off + [0.04, 0.127, -0.022]], 0.0042, n=6)
    parts.append(P.sdf_mesh("Cup_straw", straw, ck.clay(CREAM, 0.6), 0.0009, 120))
    c = ck.join(parts, "Cup")
    return P.in_hand(r, "L", c, (0, -0.03 * H, 0.04))


# ====================================================================== pose previews
POSES = {
    "rest": dict(),
    "walk": dict(walk=0.55, phase=math.pi / 2),
    "walk2": dict(walk=0.55, phase=-math.pi / 2),
    "run": dict(walk=0.95, phase=math.pi / 2, lean=0.3, armR=(-1.3, 0.1), armL=(1.3, 0.1), bob=0.04),
    "run2": dict(walk=0.95, phase=-math.pi / 2, lean=0.3, armR=(1.3, 0.1), armL=(-1.3, 0.1), bob=0.04),
    "idle": dict(nod=0.13, armR=(-1.2, 0.3), armL=(-0.45, 0.28), bob=-0.02, mouth=0.15),
    "whistle": dict(armR=(-2.6, 0.5), armL=(-2.9, 0.3), lean=-0.05, mouth=0.9),
    "measure": dict(armR=(-0.9, 0.15), armL=(-0.9, 0.15), lean=0.45, nod=0.4),
    "cuffed": dict(armR=(0.6, 0.2), armL=(0.6, 0.2), nod=0.15, mouth=0.2),
    "squirrel": dict(armL=(-1.5, 0.15), armR=(-0.4, 0.2)),
    "bino": dict(armR=(-2.45, 0.42), armL=(-2.45, 0.42)),
    "puzzle": dict(armR=(-2.75, 0.55), armL=(-0.6, 0.15), nod=0.05),
    "shut": dict(armR=(-0.2, 0.15), armL=(-0.2, 0.15)),
    "talk": dict(mouth=1.0, armR=(-0.9, 0.45), armL=(-0.9, 0.45), nod=-0.1),
}
HC = 0.47 * H + 0.36 * H + HY      # head center height at rest


def sash_check(r):
    """For every game pose: how many arm vertices end up inside the sash (they would poke through it)."""
    sash = r.sdf["sash"]
    for name, ps in POSES.items():
        P.reset_pose(r)
        P.set_pose(r, **ps)
        binv = r.body.matrix_world.inverted()
        hits = []
        for arm in (r.meshes["ArmR"], r.meshes["ArmL"]):
            M = binv @ arm.matrix_world
            co = np.array([tuple(M @ v.co) for v in arm.data.vertices])
            hits.append(int((sash(np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)) < -0.0012 * H).sum()))
        print(f"[two_pack] sash vs arms  {name:9s} R {hits[0]:4d}  L {hits[1]:4d}")
    P.reset_pose(r)


def sheet(r, sid, tiles, size=(900, 700)):
    """P.pose_sheet with per-tile accessory visibility ('show': names of Binoculars / Cup to render)."""
    toggles = [bpy.context.scene.objects.get(n) for n in ("Binoculars", "Cup")]
    out = []
    for t in tiles:
        tt = dict(t)
        tt["pose"] = POSES[t["pose"]] if isinstance(t.get("pose"), str) else t.get("pose", {})
        out.append(tt)
    # render tiles one at a time so visibility can change between them
    sc, cam = P._scene_preview_setup()
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    imgs = []
    for i, t in enumerate(out[:4]):
        for ob in toggles:
            if ob:
                ob.hide_render = ob.name not in t.get("show", ())
        P.reset_pose(r)
        P.set_pose(r, **t["pose"])
        P._rot(r.rig, t.get("rig_rot", (0, 0, 0)))
        r.rig.location = ck.G(t.get("rig_pos", (0, 0, 0)))
        cam.data.lens = t.get("lens", 50)
        cam.data.clip_start = 0.01
        ck._look_at(cam, ck.G(t["eye"]), ck.G(t["look"]))
        tmp = os.path.join(ck.PREVIEWS, f"_{sid}_{i}.png")
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.empty(size[0] * size[1] * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        imgs.append(px.reshape(size[1], size[0], 4))
        bpy.data.images.remove(img)
        os.remove(tmp)
    while len(imgs) < 4:
        imgs.append(np.ones_like(imgs[0]))
    sh = np.concatenate([np.concatenate([imgs[2], imgs[3]], 1), np.concatenate([imgs[0], imgs[1]], 1)], 0)
    im = bpy.data.images.new(f"sheet_{sid}", size[0] * 2, size[1] * 2, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(sh, dtype=np.float32).ravel())
    path = os.path.join(ck.PREVIEWS, sid + ".png")
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    P.reset_pose(r)
    P._rot(r.rig, (0, 0, 0))
    r.rig.location = (0, 0, 0)
    for ob in toggles:
        if ob:
            ob.hide_render = False
    print(f"[two_pack] sheet {path}")


def play_cam(pitch=0.22, dist=5.6, yaw=0.0):
    """The game's third-person camera behind him (player.gd update_camera), Blender lens for fov 55."""
    eye = (-math.sin(yaw) * math.cos(pitch) * dist, 1.5 + math.sin(pitch) * dist, -math.cos(yaw) * math.cos(pitch) * dist)
    return dict(eye=eye, look=(0, 1.5, 0), lens=27)


SHEETS = {
    "two_pack_back": [
        dict(pose="walk", **play_cam()),
        dict(pose="rest", eye=(0.25, 1.35, -1.55), look=(0, 1.22, 0), lens=50),
        dict(pose="rest", eye=(-0.25, 2.15, -0.85), look=(0, 1.83, -0.1), lens=55),
        dict(pose="walk2", eye=(0.5, 0.45, -1.6), look=(0, 0.22, 0), lens=45),
    ],
    "two_pack_front": [
        dict(pose="shut", eye=(0.12, HC + 0.02, 0.85), look=(0, HC - 0.03, 0), lens=60),
        dict(pose="shut", eye=(0.55, HC + 0.04, 0.7), look=(0, HC - 0.03, 0), lens=55),
        dict(pose="shut", eye=(0.25, 1.25, 1.5), look=(0, 1.2, 0), lens=50),
        dict(pose="shut", eye=(0, 1.6, 3.2), look=(0, 1.25, 0.0), lens=42),
    ],
    "two_pack_detail": [
        dict(pose="rest", eye=(0.35, 0.95, -1.0), look=(0, 0.78, 0), lens=50),
        dict(pose="rest", eye=(0.75, 0.25, 0.55), look=(0.15, 0.06, 0.05), lens=50),
        dict(pose="walk", eye=(0.9, 1.0, 0.75), look=(0.35, 0.82, 0.1), lens=55, show=("Cup",)),
        dict(pose="rest", eye=(0.55, 1.95, 0.75), look=(0, 1.83, 0.25), lens=55, show=("Binoculars",)),
    ],
    "two_pack_pose": [
        dict(pose="walk", eye=(3.2, 1.0, 0.4), look=(0, 0.9, 0), lens=50),
        dict(pose="run", eye=(3.2, 1.0, 0.4), look=(0, 0.9, 0), lens=50),
        dict(pose="run2", **play_cam()),
        dict(pose="idle", eye=(1.4, 1.5, 2.6), look=(0, 0.95, 0), lens=45),
    ],
    "two_pack_pose2": [
        dict(pose="whistle", eye=(1.5, 1.6, 2.4), look=(0, 1.1, 0), lens=45),
        dict(pose="whistle", eye=(-1.2, 1.9, -2.4), look=(0, 1.2, 0), lens=45),
        dict(pose="measure", eye=(2.8, 1.1, 0.6), look=(0, 0.85, 0.2), lens=45),
        dict(pose="cuffed", eye=(-1.3, 1.6, -2.4), look=(0, 1.0, 0), lens=45),
    ],
    "two_pack_pose3": [
        dict(pose="squirrel", eye=(1.6, 1.5, 2.3), look=(0, 1.0, 0), lens=45, show=("Cup",)),
        dict(pose="bino", eye=(0.9, 1.75, 1.6), look=(0, 1.55, 0.1), lens=50, show=("Binoculars",)),
        dict(pose="puzzle", eye=(1.6, 1.5, 2.4), look=(0, 1.05, 0), lens=45),
        dict(pose="walk", eye=(1.4, 1.2, 1.2), look=(0, 0.95, 0), lens=50, show=("Cup",)),
    ],
}


def build(sheets=None):
    ck.reset()
    random.seed(11)
    log("make_person")
    r = P.make_person(h=1.8, skin=SKIN, shirtless=True, pants=JEANS, shoes=KICKS, style="bald",
                      brows="#1c1410", brow_ridge=1.15, lid=0.48, lid_low=0.2, lid_tilt=0.04, pupil=0.92, gaze=(0.08, -0.04),
                      nose="broad", nose_size=0.96, cheeks=1.04, chin=1.12, smile=0.55, ear_size=1.02)
    log("head pieces")
    extra = [bandana(r), teardrop(r)]
    head = r.meshes["Head"]
    for e in extra:
        P.attach(e, r.head)
    bpy.context.view_layer.update()
    r.meshes["Head"] = ck.join([head] + extra, "Head_Mesh")
    log("accessories")
    binoculars(r)
    cup(r)
    tris = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            tris += t
            print(f"[two_pack]   {ob.name:12s} {t:6d} tris  {len(ob.data.materials)} materials")
    print(f"[two_pack] total {tris} tris")
    P.export_character("two_pack")
    print("[two_pack] objects:", sorted(o.name for o in bpy.context.scene.objects))
    for nm in ("Binoculars", "Cup"):
        ob = bpy.context.scene.objects[nm]
        L = ob.location
        print(f"[two_pack] {nm}: parent={ob.parent.name} local=({L.x:+.4f},{L.z:+.4f},{-L.y:+.4f}) visible={not ob.hide_viewport}")
    P.binocular_check(r)
    sash_check(r)
    log("previews")
    for nm in ("Binoculars", "Cup"):
        bpy.context.scene.objects[nm].hide_render = True
    ck.preview("two_pack")
    for nm in ("Binoculars", "Cup"):
        bpy.context.scene.objects[nm].hide_render = False
    for sid, tiles in SHEETS.items():
        if sheets is None or sid in sheets:
            sheet(r, sid, tiles)
    log("done")
    return r


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(set(args) if args else None)
