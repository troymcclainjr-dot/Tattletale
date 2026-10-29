"""Builds Officer Dan of Precinct 9 (cop_dan); also holds the cop kit (cap, duty belt, badges, donut) used by char_cop_steve.py."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claykit as ck
from lib import person as P
from char_kit import (BIG, bounded, plate, star, shield_pts, prism_x, in_frame, hit, place, euler_facing,
                      ellipse_ring, fit_ellipse, part, join_into, swap_material, cull_hidden, cull_person, hat_hair,
                      long_sleeve, report)

NAVY, GOLD, BLACK = "#1a2a5a", "#f2c230", "#0a0a0c"     # characters.js makeCop

# The two cops (state.js 20-21): makeCop(name, o) = makePerson({h 1.8, top/pants navy, shoes black, short} + o)
COPS = {
    "cop_dan": dict(name="DAN", h=1.8, skin="#e8b48a", hair="#5a3a1a", mustache=True, belly=1.45,
                    look=dict(lid=0.4, lid_tilt=-0.1, lid_low=0.14, nose="round", nose_size=1.1, cheeks=1.22, chin=1.2,
                              smile=0.75, mustache_style="brush", ear_size=1.05,
                              brow=dict(raise_=-0.011, tilt=0.25, thick=1.25, arch=0.7)),
                    cap_tilt=0.13, belt=(-0.012, 0.022), seed=11),
    "cop_steve": dict(name="STEVE", h=1.88, skin="#c48e64", hair="#141010", glasses=True,
                      look=dict(lid=0.26, nose="long", nose_size=1.0, cheeks=0.88, chin=1.12, smile=0.12, mouth_w=0.9,
                                ear_size=1.04, brow=dict(raise_=-0.009, tilt=-0.15, thick=1.1, arch=0.6)),
                      cap_tilt=0.02, belt=(0.012, 0.045), seed=23),
}


# ====================================================================== the police cap (characters.js makeCop)
def police_cap(r, tilt=0.0):
    """Peaked cap: crown band hs*.98 at hy+hs*.72, wider top hs*1.12 at hy+hs*.95, black visor at
    (0, hy+hs*.55, hs*.85) tilted .25, gold cap badge in front. Fitted around this head and its hair;
    tilt > 0 pushes it back on the head. Returns (meshes, cap SDF in Head-local coords)."""
    H, hs, hy = r.H, r.hs, r.hy
    O = np.array([0.0, hy, 0.0])
    Rm = P.rotm((-tilt, 0.0, 0.0))
    hh = in_frame(P.union(r.sdf["head"], P._hair_cap(r, "short")), O, Rm)
    y0 = 0.56 * hs
    a, b, zc = fit_ellipse(hh, [y0 + 0.02 * hs, y0 + 0.1 * hs, y0 + 0.2 * hs], -0.05 * hs, 1.9 * hs)
    a, b = a + 0.03 * hs, b + 0.03 * hs
    # crown: band, flare, wide soft top (a loft through ellipses, then rounded)
    rnd = 0.05 * hs
    ys = [y0, y0 + 0.13 * hs, y0 + 0.26 * hs, y0 + 0.39 * hs, y0 + 0.49 * hs, y0 + 0.54 * hs]
    sc = [1.0, 1.0, 1.02, 1.1, 1.155, 1.14]
    ys[0] += rnd
    ys[-1] -= rnd
    crown = P.offset(P.loft(ys, [a * s - rnd for s in sc], [b * s - rnd for s in sc], [zc] * 6), rnd)
    rise = 0.07 * hs        # the stiffened front of the top stands higher than the back

    def shear(p):
        q = p.copy()
        q[:, 1] = p[:, 1] - rise * P.smoothstep(y0 + 0.2 * hs, y0 + 0.55 * hs, p[:, 1]) * (p[:, 2] - zc) / b
        return q
    crown = P.warp(crown, shear, pad=rise)
    crown = P.union(crown, P.ellipsoid((0, y0 + 0.5 * hs, zc - 0.06 * hs), (0.78 * a, 0.1 * hs, 0.72 * b)), k=0.05 * hs)
    # piping round the top edge, a pressed seam where the band meets the crown
    yp = y0 + 0.47 * hs
    pts, th = ellipse_ring(a, b, zc, yp, 32, 1.16)
    pts[:, 1] += rise * (pts[:, 2] - zc) / b * 0.93
    nrm = np.stack([np.sin(th), np.full(len(th), 0.25), np.cos(th)], 1)
    crown = P.union(crown, P.loop_tube(list(P.snap(crown, pts, nrm, 0.12 * hs, lift=-0.004 * hs)), 0.016 * hs), k=0.008 * hs)
    pts, th = ellipse_ring(a, b, zc, y0 + 0.27 * hs, 32, 1.03)
    seam = P.loop_tube(list(P.snap(crown, pts, np.stack([np.sin(th), np.zeros(len(th)), np.cos(th)], 1), 0.1 * hs, lift=0.004 * hs)), 0.012 * hs)
    crown = P.subtract(crown, seam, k=0.008 * hs)
    # visor: a stiff crescent round the front of the band, tilted down .25
    F = np.array([0.0, y0 + 0.035 * hs, zc + b])
    ao, bo, tv = a * 1.02, b + 0.3 * hs, 0.03 * hs
    Rv = P.rotm((0.25, 0.0, 0.0))

    def vis(p):
        q = (p - F) @ Rv
        x, y = q[:, 0], q[:, 1] + 0.07 * hs * (q[:, 0] / ao) ** 2
        z = q[:, 2] + (F[2] - zc)
        k0 = np.sqrt((x / ao) ** 2 + (z / bo) ** 2)
        k1 = np.sqrt((x / ao ** 2) ** 2 + (z / bo ** 2) ** 2)
        d2 = np.maximum(k0 * (k0 - 1.0) / np.maximum(k1, 1e-12), (zc + 0.3 * b) - z - zc)
        return np.stack([d2, np.abs(y) - tv], 1)
    vrr = 0.026 * hs

    def visor_f(p):
        d = vis(p) + vrr
        return np.sqrt((np.maximum(d, 0) ** 2).sum(1)) + np.minimum(d.max(1), 0) - vrr
    e = max(ao, bo) + 0.1 * hs
    visor = P.Sdf(visor_f, [-e, y0 - 0.4 * hs, zc - 0.2 * hs], [e, y0 + 0.4 * hs, zc + bo + 0.1 * hs])
    # chin strap across the front of the band, a gold button at each end
    zcut = zc + 0.36 * b
    strap = P.intersect(P.offset(crown, 0.014 * hs), P.slab(y0 + 0.055 * hs, y0 + 0.135 * hs), k=0.006 * hs)
    strap = P.intersect(strap, P.halfspace((0, 0, zcut), (0, 0, -1)), k=0.006 * hs)
    bx = a * math.sqrt(1 - 0.36 ** 2)
    btn = []
    for sx in (-1, 1):
        pt, n = hit(crown, (sx * 2 * a, y0 + 0.095 * hs, zcut), (-sx, 0, 0), 2 * a)
        btn.append(P.sphere(pt + n * 0.012 * hs, 0.042 * hs))
    # cap badge: a gold shield with a star, on the front of the crown (JS: gold ball at hy+hs*.8)
    pt, n = hit(crown, (0, y0 + 0.31 * hs, 3 * hs), (0, 0, -1), 4 * hs)
    bw, bh = 0.27 * hs, 0.31 * hs
    badge = P.union(plate(shield_pts(bw, bh), 0.022 * hs, 0.012 * hs),
                    plate(star(5, 0.085 * hs, 0.036 * hs, 0, 0.01 * hs), 0.022 * hs, 0.01 * hs, z0=0.018 * hs), k=0.006 * hs)
    badge = place(badge, pt, n, lift=0.004 * hs)
    to_head = lambda s: P.xform(s, pos=O, rot=Rm)
    cap_mat = ck.clay(NAVY, 0.6)
    gold = ck.gloss(GOLD, 0.2)
    shiny_black = ck.gloss(BLACK, 0.2)
    meshes = [part("Cap_crown", to_head(crown), cap_mat, r.head, 0.0013 * H, 950, lumps=0.0004 * H, seed=61),
              part("Cap_visor", to_head(visor), shiny_black, r.head, 0.0009 * H, 260),
              part("Cap_strap", to_head(strap), shiny_black, r.head, 0.0008 * H, 120),
              part("Cap_buttons", to_head(P.union(*btn)), gold, r.head, 0.0007 * H, 60),
              part("Cap_badge", to_head(badge), gold, r.head, 0.0006 * H, 160)]
    # hair cutter: the crown plus everything straight above the band
    column = P.loft([y0 + 0.15 * hs, y0 + 3.0 * hs], [a * 0.985] * 2, [b * 0.985] * 2, [zc] * 2)
    return meshes, to_head(crown), to_head(P.union(crown, column))


# ====================================================================== the uniform shirt and duty belt (Body-local)
def torso_without_belly(r):
    keep = r.opts["belly"]
    r.opts["belly"] = 0.0
    t = P._torso_body(r)
    r.opts["belly"] = keep
    return t


def chest_badge(r):
    """characters.js: gold ball r .03H at body-local (.07H, .27H, .11H), his left chest -> a gold shield badge."""
    H = r.H
    torso = r.sdf["torso"]
    pt, n = hit(torso, (0.07 * H, 0.27 * H, 0.5 * H), (0, 0, -1), 0.6 * H)
    w, h, th = 0.05 * H, 0.06 * H, 0.0026 * H
    inner = P.poly2d(shield_pts(w * 0.78, h * 0.78))
    rim = P.intersect(plate(shield_pts(w * 0.99, h * 0.99), th, 0.0012 * H, z0=0.0013 * H),
                      P.Sdf(lambda p: -inner.f(p), [-BIG] * 3, [BIG] * 3), k=0.0006 * H)
    s = P.union(plate(shield_pts(w, h), th, 0.0014 * H), rim,
                plate(star(5, 0.0135 * H, 0.0058 * H, 0, 0.002 * H), th, 0.0011 * H, z0=0.0022 * H), k=0.0006 * H)
    return part("Badge", place(s, pt, n, lift=0.0016 * H), ck.gloss(GOLD, 0.2), r.body, 0.00045 * H, 230)


def name_tag(r, name):
    """A small gold name bar over his right pocket with the name in raised dark letters."""
    H = r.H
    pt, n = hit(r.sdf["torso"], (-0.068 * H, 0.262 * H, 0.5 * H), (0, 0, -1), 0.6 * H)
    hw, hh, th = 0.027 * H, 0.0072 * H, 0.0016 * H
    rot = euler_facing(n)
    objs = [ck.box(2 * hw, 2 * hh, 2 * th, tuple(pt + n * 0.0012 * H), ck.gloss(GOLD, 0.2), rot=rot, parent=r.body,
                   name="NameTag", bevel=0.001 * H, bevel_segs=2)]
    lp = pt + n * (0.0012 * H + th + 0.0003 * H)
    t = ck.text(name, size=0.0105 * H, depth=0.0011 * H, pos=tuple(lp), m=ck.clay("#141a2e", 0.6), rot=rot,
                parent=r.body, name="NameTag_text", font="black", fit_width=2 * hw - 0.006 * H, bevel=0.0, resolution=2)
    objs.append(t)
    return objs


def pockets(r, sx_list=(-1, 1)):
    """Two chest pockets with pointed button-down flaps."""
    H = r.H
    torso = r.sdf["torso"]
    front = P.halfspace((0, 0, 0.0), (0, 0, -1))
    parts, flaps, btns = [], [], []
    for sx in sx_list:
        x = sx * 0.064 * H
        body = P.intersect(P.rbox((x, 0.197 * H, 0), (0.029 * H, 0.033 * H, BIG), 0.008 * H), front)
        parts.append(P.patch(torso, body, 0.0034 * H))
        fl = P.intersect(P.poly2d([(x - 0.032 * H, 0.233 * H), (x + 0.032 * H, 0.233 * H), (x + 0.032 * H, 0.214 * H),
                                   (x, 0.203 * H), (x - 0.032 * H, 0.214 * H)]), front, k=0.002 * H)
        flaps.append(P.patch(torso, fl, 0.0062 * H, k=0.0022 * H))
        bp, bn = hit(torso, (x, 0.21 * H, 0.5 * H), (0, 0, -1), 0.6 * H)
        btns.append(P.sphere(bp + bn * 0.0068 * H, 0.0052 * H))
    top = r.mats["top"]
    return [part("Pockets", P.union(*parts), top, r.body, 0.0011 * H, 260, lumps=0.0003 * H, seed=71),
            part("PocketFlaps", P.union(*flaps), top, r.body, 0.001 * H, 320, lumps=0.0003 * H, seed=72),
            part("PocketButtons", P.union(*btns), r.mats["button"], r.body, 0.0006 * H, 70)]


def epaulettes(r):
    """Shoulder straps from the collar to the shoulder seam, buttoned at the collar end."""
    H = r.H
    torso = r.sdf["torso"]
    straps, btns = [], []
    for sx in (-1, 1):
        reg = P.intersect(P.rbox((sx * 0.118 * H, 0.42 * H, 0.004 * H), (0.052 * H, 0.12 * H, 0.017 * H), 0.007 * H),
                          P.halfspace((0, 0.3 * H, 0), (0, -1, 0)))
        straps.append(P.patch(torso, reg, 0.0042 * H, k=0.0015 * H))
        bp, bn = hit(torso, (sx * 0.077 * H, 0.6 * H, 0.004 * H), (0, -1, 0), 0.4 * H)
        btns.append(P.sphere(bp + bn * 0.006 * H, 0.0058 * H))
    return [part("Epaulettes", P.union(*straps), r.mats["top"], r.body, 0.001 * H, 260, lumps=0.0003 * H, seed=73),
            part("EpauletteButtons", P.union(*btns), r.mats["button"], r.body, 0.0006 * H, 50)]


def duty_belt(r, y0, y1, belly):
    """Black glossy duty belt: buckle, holster (right hip), radio (back left) with its cord up to the
    shoulder mic, handcuffs (back right). A big belly hangs over it (Dan)."""
    H = r.H
    pel = P._pelvis_sdf(r)
    core = P.union(torso_without_belly(r) if belly else r.sdf["torso"], pel, k=0.01 * H)
    t = 0.0068 * H
    full = P.intersect(P.offset(core, t), P.slab(y0 * H, y1 * H), k=0.0022 * H)
    # hollow it into a ring (and drop what the belly hides)
    band = P.subtract(full, P.offset(P.union(core, r.sdf["torso"]), -0.004 * H), k=0.002 * H)
    ym = 0.5 * (y0 + y1) * H
    leather, black = ck.gloss("#141414", 0.35), ck.clay("#1a1a1e", 0.6)
    steel = ck.metal("#c8ccd4", 0.3)
    objs = [part("Belt", band, leather, r.body, 0.0013 * H, 500, seed=74)]
    # buckle (skipped when the belly covers it)
    bp, bn = hit(full, (0, ym, 0.5 * H), (0, 0, -1), 0.6 * H)
    if r.sdf["torso"](bp[None, :])[0] > -0.004 * H:
        bw, bh, bt = 0.021 * H, 0.0155 * H, 0.0024 * H
        frame = P.subtract(P.rbox((0, 0, 0), (bw, bh, bt), 0.003 * H), P.rbox((0, 0, 0.0016 * H), (bw * 0.62, bh * 0.5, bt), 0.0015 * H), k=0.0008 * H)
        objs.append(part("Buckle", place(bounded(frame, [-bw - 0.01, -bh - 0.01, -bt - 0.01], [bw + 0.01, bh + 0.01, bt + 0.01]), bp, bn, lift=0.0012 * H),
                         steel, r.body, 0.0005 * H, 110))
    # holster on the right hip, outside the thigh, a dark grip leaning back out of it
    hp, hn = hit(full, (-0.5 * H, ym, -0.028 * H), (1, 0, 0), 0.6 * H)
    hc = np.array([hp[0] - 0.019 * H, y1 * H - 0.045 * H, hp[2]])
    hol = P.union(P.rbox(hc, (0.0145 * H, 0.04 * H, 0.031 * H), 0.011 * H),
                  P.round_cone(hc + np.array([0, -0.01 * H, 0.008 * H]), hc + np.array([0, -0.075 * H, 0.012 * H]), 0.0155 * H, 0.0125 * H), k=0.01 * H)
    hol = P.union(hol, P.rbox(np.array([hc[0] + 0.004 * H, ym, hc[2]]), (0.012 * H, 0.021 * H, 0.022 * H), 0.004 * H), k=0.004 * H)
    grip = P.rbox(hc + np.array([0, 0.052 * H, -0.017 * H]), (0.0105 * H, 0.026 * H, 0.0145 * H), 0.006 * H, rot=(-0.38, 0, 0))
    snapb = P.sphere(hc + np.array([-0.016 * H, 0.034 * H, -0.004 * H]), 0.0042 * H)
    tab = P.rbox(hc + np.array([-0.002 * H, 0.036 * H, -0.004 * H]), (0.0145 * H, 0.006 * H, 0.012 * H), 0.003 * H)
    objs.append(part("Holster", P.union(hol, tab, k=0.003 * H), leather, r.body, 0.0011 * H, 320, seed=75))
    objs.append(part("HolsterGrip", grip, ck.gloss("#2a2a2e", 0.35), r.body, 0.0009 * H, 120))
    objs.append(part("HolsterSnap", snapb, steel, r.body, 0.0006 * H, 30))
    # radio on the back left, antenna up
    rp, rn = hit(full, (0.098 * H, ym, -0.5 * H), (0, 0, 1), 0.6 * H)
    rc = rp + rn * 0.011 * H + np.array([0, -0.012 * H, 0])
    radio = P.union(P.rbox(rc, (0.017 * H, 0.03 * H, 0.0095 * H), 0.005 * H, rot=(0, math.atan2(rn[0], rn[2]), 0)),
                    P.capsule(rc + np.array([0.009 * H, 0.03 * H, 0]), rc + np.array([0.01 * H, 0.066 * H, 0.001 * H]), 0.0034 * H),
                    P.cylinder(rc + np.array([-0.007 * H, 0.032 * H, 0]), 0.0045 * H, 0.004 * H, round_=0.0015 * H), k=0.0015 * H)
    objs.append(part("Radio", radio, black, r.body, 0.0008 * H, 190))
    # handcuffs hanging at the back right
    cp, cn = hit(full, (-0.075 * H, y0 * H + 0.004 * H, -0.5 * H), (0, 0, 1), 0.6 * H)
    cc = cp + cn * 0.006 * H
    ring_rot = P.frame_y(cn)
    cuffs = P.union(P.torus(cc + np.array([-0.002 * H, -0.024 * H, 0]), 0.0155 * H, 0.0029 * H, rot=ring_rot),
                    P.torus(cc + np.array([-0.033 * H, -0.03 * H, 0.002 * H]), 0.0155 * H, 0.0029 * H, rot=P.frame_y(cn + np.array([0.2, 0, 0]))),
                    P.capsule(cc + np.array([-0.012 * H, -0.026 * H, 0]), cc + np.array([-0.022 * H, -0.028 * H, 0]), 0.0032 * H))
    clip = P.rbox(cc + np.array([0.0, -0.004 * H, 0]), (0.006 * H, 0.012 * H, 0.002 * H), 0.0015 * H)
    objs.append(part("Cuffs", cuffs, steel, r.body, 0.0006 * H, 220))
    objs.append(part("CuffClip", clip, leather, r.body, 0.0006 * H, 30))
    # a ring of keys at his left hip
    kp, kn = hit(full, (0.5 * H, y0 * H + 0.006 * H, 0.03 * H), (-1, 0, 0), 0.6 * H)
    kc = kp + kn * 0.004 * H
    ring_c = kc + np.array([0, -0.012 * H, 0])
    keys = [P.torus(ring_c, 0.0085 * H, 0.0014 * H, rot=P.frame_y(kn)),
            P.rbox(kc + np.array([0, -0.001 * H, 0]), (0.0022 * H, 0.0055 * H, 0.0022 * H), 0.001 * H)]
    for k, (ang, ln) in enumerate(((-0.25, 0.026), (0.12, 0.022), (0.42, 0.024))):
        top = ring_c + np.array([math.sin(ang) * 0.006 * H, -0.0085 * H, 0.0])
        dirv = np.array([math.sin(ang) * 0.6, -1.0, 0.0])
        dirv /= np.linalg.norm(dirv)
        keys.append(P.sphere(top + dirv * 0.004 * H, 0.0052 * H))
        keys.append(P.capsule(top + dirv * 0.008 * H, top + dirv * ln * H, 0.0021 * H))
    objs.append(part("Keys", P.union(*keys), steel, r.body, 0.00045 * H, 150))
    return objs, rc


def shoulder_mic(r, radio_top):
    """Radio mic clipped at his left shoulder strap, cord over the shoulder down the back to the radio."""
    H = r.H
    torso = r.sdf["torso"]
    mp, mn = hit(torso, (0.118 * H, 0.33 * H, 0.5 * H), (0, -0.25, -1), 0.6 * H)
    mic = place(bounded(P.rbox((0, 0, 0), (0.0115 * H, 0.0165 * H, 0.0068 * H), 0.0042 * H), [-0.03] * 3, [0.03] * 3), mp, mn, lift=0.0078 * H)
    grille = [P.capsule(np.array([-0.006 * H, y * H, 0.0068 * H]), np.array([0.006 * H, y * H, 0.0068 * H]), 0.0014 * H) for y in (-0.006, 0.0, 0.006)]
    mic = P.subtract(mic, place(bounded(P.union(*grille), [-0.03] * 3, [0.03] * 3), mp, mn, lift=0.0078 * H), k=0.001 * H)
    # cord: out of the top of the mic, hugging the shoulder over the top and down the back to the radio
    rc = 0.0033 * H
    c = np.array([0.136 * H, 0.318 * H, 0.0])
    phis = np.radians([28, 52, 76, 100, 124, 148, 168])
    raw = [c + np.array([0, 0.06 * H * math.sin(f), 0.085 * H * math.cos(f)]) for f in phis]
    nrm = [(0.25, math.sin(f), math.cos(f)) for f in phis]
    raw += [(0.128 * H, 0.24 * H, -0.3 * H), (0.12 * H, 0.17 * H, -0.3 * H), (0.112 * H, 0.1 * H, -0.3 * H)]
    nrm += [(0.12, 0, -1)] * 3
    pts = [mp + mn * 0.0075 * H + np.array([0, 0.018 * H, 0])] + list(P.snap(torso, raw, nrm, 0.3 * H, lift=rc + 0.0006 * H))
    pts.append(radio_top + np.array([0, 0.03 * H, 0]))
    cord = P.tube(pts, rc, n=4)
    black = ck.clay("#1a1a1e", 0.6)
    return [part("Mic", mic, black, r.body, 0.0006 * H, 100), part("MicCord", cord, black, r.body, 0.0009 * H, 140)]


def belly_smear(r, seed):
    """A smear of pink icing on Dan's shirt, with two stray sprinkles."""
    H = r.H
    torso = r.sdf["torso"]
    reg = P.intersect(P.union(P.ellipse2d((0.03 * H, 0.136 * H), 0.016 * H, 0.01 * H), P.ellipse2d((0.043 * H, 0.128 * H), 0.01 * H, 0.007 * H),
                              P.ellipse2d((0.02 * H, 0.142 * H), 0.008 * H, 0.006 * H)), P.halfspace((0, 0, 0.05 * H), (0, 0, -1)))
    smear = P.patch(torso, reg, 0.0019 * H, k=0.0012 * H)
    sp = []
    for (x, y, a) in ((0.026 * H, 0.137 * H, 0.6), (0.041 * H, 0.129 * H, -0.9)):
        p, n = hit(torso, (x, y, 0.5 * H), (0, 0, -1), 0.6 * H)
        d = np.array([math.cos(a), math.sin(a), 0.0]) * 0.006
        sp.append((P.capsule(p + n * 0.0026 * H - d, p + n * 0.0026 * H + d, 0.0026), ("#f8f6f0", "#2ad0e8")[len(sp)]))
    out = [part("IcingSmear", smear, ck.gloss("#e84a9a", 0.3), r.body, 0.0006 * H, 120)]
    for i, (s, c) in enumerate(sp):
        out.append(part(f"SmearSprinkle{i}", s, ck.clay(c, 0.5), r.body, 0.0005, 40))
    return out


def sleeve_patches(r):
    """Shield patches on the outside of both upper sleeves (gold rim, star)."""
    H = r.H
    sleeve = long_sleeve(r)
    yc = -0.088 * H
    outer = P.halfspace((0.01 * H, 0, 0), (-1, 0, 0))
    reg = P.intersect(prism_x(shield_pts(0.042 * H, 0.05 * H, 0.0, yc)), outer)
    base = P.patch(sleeve, reg, 0.0026 * H, k=0.0008 * H)
    rim = P.intersect(P.offset(sleeve, 0.0036 * H), P.subtract(P.offset(reg, 0.0026 * H), P.offset(reg, -0.0016 * H)), k=0.0006 * H)
    st = P.patch(sleeve, P.intersect(prism_x(star(5, 0.0135 * H, 0.0056 * H, 0.0, yc + 0.0015 * H)), outer), 0.0038 * H, k=0.0006 * H)
    blue, gold = ck.clay("#4a6ab8", 0.8), ck.gloss(GOLD, 0.2)
    out = {}
    for side, key in ((1, "ArmL"), (-1, "ArmR")):
        f = (lambda s: s) if side > 0 else P.mirror_x
        piv = r.armL if side > 0 else r.armR
        out[key] = [part(f"{key}_patch", f(base), blue, piv, 0.0007 * H, 140),
                    part(f"{key}_patchrim", f(P.union(rim, st)), gold, piv, 0.0005 * H, 190)]
    return out


# ====================================================================== the donut
def donut(r, seed, name="Donut"):
    """characters.js: pink torus (R .08, r .035, roughness .3) in the right hand at arm-local (0, -.33H, .03),
    rotated y=PI/2. Sculpted: golden dough, glossy pink icing with drips, sprinkles, and a bite out of the far side.
    Built in the torus' own frame (ring in xy, axis z, icing on +z)."""
    rnd = random.Random(seed)
    R, rt, rz = 0.08, 0.037, 0.03
    e = R + rt + 0.02

    def ring(p, grow=0.0):
        u = np.sqrt(p[:, 0] ** 2 + p[:, 1] ** 2) - R
        v = p[:, 2]
        a, b = rt + grow, rz + grow
        k0 = np.sqrt((u / a) ** 2 + (v / b) ** 2)
        k1 = np.sqrt((u / a ** 2) ** 2 + (v / b ** 2) ** 2)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
    dough = P.Sdf(ring, [-e, -e, -0.05], [e, e, 0.05])
    ph = [rnd.uniform(0, 6.28) for _ in range(4)]

    def icing_f(p):
        u = np.sqrt(p[:, 0] ** 2 + p[:, 1] ** 2) - R
        th = np.arctan2(p[:, 1], p[:, 0])
        phi = np.arctan2(u, p[:, 2])                      # 0 on top, + outside, - in the hole
        out = 2.3 + 0.38 * np.maximum(0, np.sin(5 * th + ph[0])) ** 3 + 0.1 * np.sin(11 * th + ph[1])   # over the rim, dripping under
        inn = 1.7 + 0.12 * np.sin(7 * th + ph[2])
        ang = np.maximum(phi - out, -inn - phi) * rt
        shell = np.maximum(ring(p, 0.0036), -ring(p, -0.004))
        return P.smax(shell, ang, 0.002)
    icing = P.Sdf(icing_f, [-e, -e, -0.05], [e, e, 0.05])
    # the bite: four tooth scallops through the far side (local -y, away from the fingers)
    M = np.array([0.0, -(R + rt + 0.008), 0.0])
    bites = P.union(*[P.capsule(M + 0.034 * np.array([math.sin(a), math.cos(a), 0]) + (0, 0, -0.05),
                                M + 0.034 * np.array([math.sin(a), math.cos(a), 0]) + (0, 0, 0.05), 0.0205 + 0.002 * math.cos(3 * a))
                      for a in (-0.98, -0.33, 0.33, 0.98)])
    dough_c = P.subtract(dough, P.offset(bites, 0.003), k=0.0015)
    icing_c = P.subtract(icing, P.offset(bites, 0.0004), k=0.001)
    crumb = P.intersect(dough, P.subtract(P.offset(bites, 0.003), bites))
    objs = [P.sdf_mesh(name + "_dough", dough_c, ck.clay("#c98a48", 0.75), 0.0012, 360, lumps=0.0008, seed=seed),
            P.sdf_mesh(name + "_icing", icing_c, ck.gloss("#e84a9a", 0.3), 0.0011, 440, lumps=0.0004, seed=seed + 1),
            P.sdf_mesh(name + "_crumb", crumb, ck.clay("#f0d8a0", 0.9), 0.0008, 130, lumps=0.0006, seed=seed + 2)]
    # sprinkles on the icing (none in the bite or under the fingers at +y)
    cols = {"#f8f6f0": [], "#f2c21a": [], "#2ad0e8": []}
    keys = list(cols)
    k = 0
    tries = 0
    while k < 15 and tries < 400:
        tries += 1
        th = rnd.uniform(-math.pi, math.pi)
        if abs(th + math.pi / 2) < 0.62 or abs(th - math.pi / 2) < 0.5:
            continue
        phi = rnd.uniform(-0.95, 1.25)
        n = np.array([math.sin(phi) * math.cos(th), math.sin(phi) * math.sin(th), math.cos(phi)])
        base = np.array([(R + rt * math.sin(phi)) * math.cos(th), (R + rt * math.sin(phi)) * math.sin(th), rz * math.cos(phi)])
        pt = P.snap(icing_c, [base], [n], 0.02, lift=0.0012)[0]
        et = np.array([-math.sin(th), math.cos(th), 0.0])
        ep = np.array([math.cos(phi) * math.cos(th), math.cos(phi) * math.sin(th), -math.sin(phi)])
        al = rnd.uniform(0, math.pi)
        d = (math.cos(al) * et + math.sin(al) * ep) * 0.0062
        cols[keys[k % 3]].append(P.capsule(pt - d, pt + d, 0.0027))
        k += 1
    for c, caps in cols.items():
        objs.append(P.sdf_mesh(name + "_sprinkles", P.union(*caps), ck.clay(c, 0.5), 0.0008, 20 * len(caps)))
    d = ck.join([o for o in objs if o], name)
    cull_hidden(d, P.union(dough_c, icing_c), 0.0012)
    return P.in_hand(r, "R", d, pos=(0, -0.03 * r.H, 0.03), rot=(0, math.pi / 2, 0))


# ====================================================================== the cop
def make_cop(cid):
    c = COPS[cid]
    ck.reset()
    random.seed(c["seed"])
    opts = dict(h=c["h"], skin=c["skin"], top=NAVY, pants=NAVY, shoes=BLACK, hair=c["hair"], style="bald",
                mustache=c.get("mustache", False), belly=c.get("belly", 0.0), glasses=c.get("glasses", False),
                collar="button", tuck=True, button_color="#d8b440", sole="#141414", seed=c["seed"])
    opts.update(c["look"])
    r = P.make_person(**opts)
    H = r.H
    # head: cap, and the short hair (style "short" in the JS) showing under it
    cap_meshes, crown, cutter = police_cap(r, c["cap_tilt"])
    hair = hat_hair(r, cutter, target=950)
    join_into(r, "Head", cap_meshes + [hair])
    # body: badge, name tag, pockets, shoulder straps, duty belt, shoulder radio
    body = [chest_badge(r)] + name_tag(r, c["name"]) + pockets(r) + epaulettes(r)
    belt, radio_top = duty_belt(r, c["belt"][0], c["belt"][1], belly=c.get("belly", 0.0) > 0)
    body += belt + shoulder_mic(r, radio_top)
    if c.get("belly"):
        body += belly_smear(r, c["seed"])
    join_into(r, "Body", body)
    for key, objs in sleeve_patches(r).items():
        join_into(r, key, objs)
    # polished black shoes
    for key in ("LegR", "LegL"):
        swap_material(r.meshes[key], ck.clay(BLACK, 0.5).name, ck.gloss(BLACK, 0.2))
    # drop faces buried inside other parts of the same pivot (hair shell, skin under the cap, patch walls...)
    cull_person(r, head_solid=P.union(r.sdf["head"], crown))
    donut(r, c["seed"] + 5)
    return r


def cop_tiles(r):
    H = r.H
    hc = 0.47 * H + 0.36 * H + r.hy
    eat = dict(armR=(-1.2, 0.25), armL=(-0.15, 0.12))
    bite = dict(armR=(-2.4, 0.25), armL=(-0.15, 0.12), mouth=0.5)
    return {
        "_pose": [dict(pose=eat, eye=(0.9 * H, 0.85 * H, 1.75 * H), look=(0, 0.6 * H, 0), lens=45),
                  dict(pose=bite, eye=(-0.55 * H, 0.9 * H, 1.6 * H), look=(-0.05 * H, 0.68 * H, 0), lens=45),
                  dict(pose=dict(walk=0.55, armR=(-0.3, 0.1)), eye=(2.3 * H, 0.6 * H, 0.45 * H), look=(0, 0.5 * H, 0), lens=45),
                  dict(pose=dict(armR=(-0.4, 0.1), armL=(-0.15, 0.12), mouth=0.8), eye=(0.3 * H, hc + 0.02 * H, 0.8 * H), look=(0, hc - 0.04 * H, 0), lens=50)],
        "_pose2": [dict(pose=dict(armR=(-0.4, 0.1), armL=(-0.15, 0.12)), eye=(-1.1 * H, 0.75 * H, -1.5 * H), look=(0, 0.5 * H, 0), lens=45),
                   dict(pose=dict(walk=0.55, phase=-math.pi / 2, armR=(-0.3, 0.1)), eye=(-2.3 * H, 0.6 * H, 0.5 * H), look=(0, 0.5 * H, 0), lens=45),
                   dict(pose=eat, eye=(-0.05 * H, 0.78 * H, 0.75 * H), look=(-0.2 * H, 0.66 * H, 0.1 * H), lens=50),
                   dict(pose=dict(armR=(-0.2, 0.15), armL=(-0.2, 0.15)), eye=(0.55 * H, hc + 0.12 * H, 0.75 * H), look=(0, hc, 0), lens=55)],
    }


def build(cid):
    r = make_cop(cid)
    report(r, "cop")
    P.export_character(cid)
    ck.preview(cid)
    for suffix, tiles in cop_tiles(r).items():
        P.pose_sheet(r, cid + suffix, tiles)
    return r


if __name__ == "__main__":
    build("cop_dan")
