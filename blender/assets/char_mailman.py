"""Builds the mailman (mailman): blue uniform shirt, navy trousers, pith helmet, leather mail satchel, and the Letter he bends."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math, random
import numpy as np
import claykit as ck
from lib import person as P
from char_kit import (BIG, bounded, prism_x, in_frame, hit, place, fit_ellipse,
                      part, join_into, cull_hidden, cull_person, hat_hair, long_sleeve, report, hand_report)

LEATHER, CREAM = "#5a3a24", "#f4f0e6"          # state.js: strap and satchel, the letter
NAVY = "#2a3a6a"                                # his trousers
KHAKI, BRASS, INK = "#cdb98c", "#c8a048", "#2a2a3a"   # new details: helmet, buckles and rings, address ink
H_MAIL = 1.75


# ====================================================================== pith helmet
def pith_helmet(r, tilt=0.2):
    """Khaki pith helmet perched on the head (pushed back so the face reads from above): tall dome with six
    pressed panel seams, a navy band, a top vent button, a sloping brim, longer front and back."""
    H, hs, hy = r.H, r.hs, r.hy
    O = np.array([0.0, hy, 0.0])
    Rm = P.rotm((-tilt, 0.0, 0.0))
    hh = in_frame(P.union(r.sdf["head"], P._hair_cap(r, "short")), O, Rm)
    yb = 0.5 * hs
    a, b, zc = fit_ellipse(hh, [yb + 0.02 * hs, yb + 0.12 * hs, yb + 0.24 * hs], -0.05 * hs, 1.9 * hs)
    a, b = a + 0.04 * hs, b + 0.04 * hs
    ry = 0.97 * hs
    yd = yb + 0.2 * hs
    f = 1.0 / math.sqrt(1 - (0.2 * hs / ry) ** 2)
    dome = P.intersect(P.ellipsoid((0, yd, zc), (a * f, ry, b * f)), P.halfspace((0, yb, 0), (0, -1, 0)), k=0.02 * hs)
    # six panel seams from the vent down to the band
    for k in range(6):
        az = math.pi / 6 + k * math.pi / 3
        pts, nrm = [], []
        for el in np.radians([78, 62, 46, 30, 16]):
            d = np.array([math.cos(el) * math.sin(az) * a * f, math.sin(el) * ry, math.cos(el) * math.cos(az) * b * f])
            pts.append(np.array([0, yd, zc]) + d)
            nrm.append(d / np.linalg.norm(d))
        dome = P.groove(dome, pts, nrm, 0.011 * hs, 0.15 * hs)
    top, tn = hit(dome, (0, yd + 2 * hs, zc), (0, -1, 0), 2.5 * hs)
    vent = P.union(P.ellipsoid(top + np.array([0, 0.01 * hs, 0]), (0.085 * hs, 0.05 * hs, 0.085 * hs)),
                   P.torus(top - np.array([0, 0.004 * hs, 0]), 0.085 * hs, 0.017 * hs), k=0.01 * hs)
    band = P.intersect(P.offset(dome, 0.016 * hs), P.slab(yb - 0.02 * hs, yb + 0.2 * hs), k=0.007 * hs)
    # brim: a sloping skirt, 0.39hs wide front and back, 0.24hs at the sides, rolled edge; flatter in front
    A, B = a, b
    tb = 0.04 * hs

    def brim_f(p):
        x, y, z = p[:, 0], p[:, 1], p[:, 2] - zc
        e = np.sqrt((x / A) ** 2 + (z / B) ** 2)
        th = np.arctan2(x / A, z / B)
        Rl = np.sqrt((A * np.sin(th)) ** 2 + (B * np.cos(th)) ** 2)
        w = 0.24 * hs + 0.15 * hs * np.cos(th) ** 2
        slope = 0.42 - 0.2 * np.maximum(np.cos(th), 0)
        ym = yb + 0.015 * hs - slope * np.maximum(e - 1.0, 0) * Rl
        dy = (np.abs(y - ym) - tb) * 0.92
        dr = np.maximum((e - 1.0) * Rl - w, (0.9 - e) * Rl)
        rr = tb * 0.9
        u, v = dr + rr, dy + rr
        return np.sqrt(np.maximum(u, 0) ** 2 + np.maximum(v, 0) ** 2) + np.minimum(np.maximum(u, v), 0) - rr
    m = max(A, B) + 0.48 * hs
    brim = P.Sdf(brim_f, [-m, yb - 0.3 * hs, zc - m], [m, yb + 0.1 * hs, zc + m])
    to_head = lambda s: P.xform(s, pos=O, rot=Rm)
    khaki = ck.clay(KHAKI, 0.85)
    meshes = [part("Helmet_dome", to_head(P.union(dome, vent, k=0.006 * hs)), khaki, r.head, 0.0013 * H, 1000, lumps=0.0005 * H, seed=81),
              part("Helmet_brim", to_head(brim), khaki, r.head, 0.0012 * H, 620, lumps=0.0004 * H, seed=82),
              part("Helmet_band", to_head(band), ck.clay(NAVY, 0.8), r.head, 0.0011 * H, 300)]
    column = P.loft([yb + 0.1 * hs, yb + 3.0 * hs], [a * 0.985] * 2, [b * 0.985] * 2, [zc] * 2)
    return meshes, to_head(dome), to_head(P.union(dome, column))


# ====================================================================== satchel and strap (Body-local, meters like the JS)
BAG_C = np.array([-0.21, 0.045, 0.172])        # JS (-.2, .05, .14), nudged out of the body and the walking thigh
BAG_R = P.rotm((-0.17, -0.25, 0.0))            # bottom swung forward, face turned out to his right
BAG_HALF = (0.148, 0.135, 0.044)               # JS box .32 x .3 x .12, a little slimmer


def bag_to_body(s):
    return P.xform(s, pos=BAG_C, rot=BAG_R)


def bag_point(p):
    return BAG_C + BAG_R @ np.asarray(p, float)


def satchel(r, seed=5):
    """The leather mail satchel at his right hip front: stitched welt, a front pocket with a buckled flap,
    brass rings, an open top stuffed with letters."""
    rnd = random.Random(seed)
    hx, hy_, hz = BAG_HALF
    body = P.union(P.rbox((0, 0, 0), (hx, hy_, hz), 0.022), P.ellipsoid((0, -0.012, 0.012), (0.128, 0.118, 0.044)), k=0.02)
    body = P.subtract(body, P.rbox((0, hy_ + 0.004, -0.004), (hx - 0.014, 0.034, hz - 0.016), 0.01), k=0.006)
    ex, ey, ez = hx - 0.0065, hy_ - 0.0065, hz - 0.0065
    welt = P.tube([(-ex, hy_ - 0.012, ez), (-ex, -ey + 0.02, ez), (-ex + 0.02, -ey, ez), (ex - 0.02, -ey, ez), (ex, -ey + 0.02, ez), (ex, hy_ - 0.012, ez)], 0.0052, n=5)
    body = P.union(body, welt, k=0.003)
    pocket = P.rbox((0, -0.045, hz + 0.008), (0.094, 0.06, 0.012), 0.012)
    flap = P.intersect(P.rbox((0, 0.004, hz + 0.017), (0.1, 0.034, 0.008), 0.008), P.halfspace((0, 0.04, 0), (0, 1, 0)), k=0.004)
    tab = P.rbox((0, -0.032, hz + 0.024), (0.011, 0.03, 0.0035), 0.003)
    buckle = P.subtract(P.rbox((0, -0.036, hz + 0.028), (0.016, 0.013, 0.003), 0.003), P.rbox((0, -0.036, hz + 0.03), (0.0095, 0.0065, 0.004), 0.002))
    rings = P.union(*[P.torus((sx * (hx + 0.004), hy_ - 0.01, 0.0), 0.016, 0.0036, rot=P.frame_y((1, 0, 0))) for sx in (-1, 1)])
    letters = {CREAM: [], "#e6d4a0": [], "#f8f6f0": []}
    cols = list(letters)
    for i, x in enumerate((-0.09, -0.047, -0.004, 0.04, 0.086)):
        w = rnd.uniform(0.1, 0.13) / 2
        hgt = rnd.uniform(0.006, 0.03)
        z = rnd.uniform(-0.012, 0.01)
        env = P.rbox((0, 0, 0), (w, 0.045, 0.0024), 0.0018)
        letters[cols[i % 3]].append(P.xform(env, pos=(x, hy_ - 0.03 + hgt, z), rot=(rnd.uniform(-0.12, 0.12), 0.0, rnd.uniform(-0.2, 0.2))))
    leather = ck.clay(LEATHER, 0.7)
    out = [part("Satchel", bag_to_body(P.union(body, pocket, k=0.004)), leather, r.body, 0.0013, 640, lumps=0.0007, seed=91),
           part("SatchelFlap", bag_to_body(P.union(flap, tab, k=0.002)), ck.clay(P.shade(LEATHER, 0.86), 0.65), r.body, 0.0009, 220),
           part("SatchelBrass", bag_to_body(P.union(buckle, rings)), ck.metal(BRASS, 0.35), r.body, 0.0007, 220)]
    for c, envs in letters.items():
        out.append(part("SatchelLetters", bag_to_body(P.union(*envs)), ck.clay(c, 0.85), r.body, 0.0008, 50 * len(envs)))
    return out


def strap(r):
    """Cross-body strap: over his left shoulder, across the chest to the satchel at his right hip and round
    the back. (The JS box is rotated z .7, which runs it to the left hip, away from the bag; mirrored so it
    reaches the bag.) A brass adjuster on the chest, tabs to the bag rings."""
    torso = r.sdf["torso"]
    ang = -0.7
    n = np.array([math.cos(ang), math.sin(ang), 0.0])
    t, w = 0.0068, 0.025
    band = P.intersect(P.offset(torso, t), P.plane_slab((0, 0.35, 0), n, w), k=0.003)
    band = P.subtract(band, P.offset(torso, -0.006), k=0.002)
    along = np.array([-n[1], n[0], 0.0])             # up the strap, toward his left shoulder
    # brass adjuster on the chest
    c0 = np.array([0.0, 0.35, 0.0]) + along * 0.07
    bp, bn = hit(P.offset(torso, t), c0 + np.array([0, 0, 0.5]), (0, 0, -1), 0.6)
    adj = P.subtract(P.rbox((0, 0, 0), (0.032, 0.02, 0.003), 0.003), P.rbox((0, 0, 0.002), (0.022, 0.01, 0.004), 0.002))
    adj = place(bounded(adj, [-0.05] * 3, [0.05] * 3), bp, bn, up=along, lift=0.002)
    # tabs from the bag's rings to the strap
    inner_ring = bag_point((BAG_HALF[0] + 0.004, BAG_HALF[1] - 0.01, 0.0))
    outer_ring = bag_point((-BAG_HALF[0] - 0.004, BAG_HALF[1] - 0.01, 0.0))
    y_in = inner_ring[1] + 0.05
    x_in = -(y_in - 0.35) * n[1] / n[0]                  # the strap's center line at that height
    p_in, n_in = hit(P.offset(torso, t), (x_in, y_in, 0.5), (0, 0, -1), 0.6)
    p_out, n_out = hit(P.offset(torso, t), (-0.5, 0.075, 0.0), (1, 0, 0), 0.6)
    tabs = [P.tube([inner_ring + np.array([0, 0.012, 0]), 0.5 * (inner_ring + p_in) + np.array([0, 0.01, 0.012]), p_in + n_in * 0.002], 0.0075, n=4),
            P.tube([outer_ring + np.array([0, 0.012, 0]), 0.5 * (outer_ring + p_out) + np.array([-0.01, 0.0, 0.0]), p_out + n_out * 0.002], 0.0075, n=4)]
    leather = ck.clay(LEATHER, 0.7)
    return [part("Strap", band, leather, r.body, 0.0012, 520, lumps=0.0005, seed=92),
            part("StrapTabs", P.union(*tabs), leather, r.body, 0.001, 160),
            part("StrapAdjuster", adj, ck.metal(BRASS, 0.35), r.body, 0.0006, 90)]


# ====================================================================== uniform details
def trouser_stripes(r):
    """A dark stripe down the outside of each trouser leg."""
    H = r.H
    leg = r.sdf["leg"]
    reg = P.intersect(P.Sdf(lambda p: np.abs(p[:, 2] - 0.002 * H) - 0.0062 * H, [-BIG] * 3, [BIG] * 3),
                      P.intersect(P.halfspace((0.025 * H, 0, 0), (-1, 0, 0)), P.halfspace((0, -0.035 * H, 0), (0, 1, 0))))
    s = P.intersect(P.offset(leg, 0.0021 * H), reg, k=0.0008 * H)
    m = ck.clay("#1c2648", 0.85)
    return {"LegL": [part("LegL_stripe", s, m, r.legL, 0.0011 * H, 240)],
            "LegR": [part("LegR_stripe", P.mirror_x(s), m, r.legR, 0.0011 * H, 240)]}


def sleeve_patches(r):
    """Round navy patches with a little white envelope on both upper sleeves (generic, no logos)."""
    H = r.H
    sleeve = long_sleeve(r)
    yc = -0.085 * H
    outer = P.halfspace((0.01 * H, 0, 0), (-1, 0, 0))
    disc = P.Sdf(lambda p: np.sqrt(p[:, 2] ** 2 + (p[:, 1] - yc) ** 2) - 0.021 * H, [-BIG] * 3, [BIG] * 3)
    base = P.patch(sleeve, P.intersect(disc, outer), 0.0026 * H, k=0.0008 * H)
    env = prism_x([(-0.0115 * H, yc - 0.0075 * H), (0.0115 * H, yc - 0.0075 * H), (0.0115 * H, yc + 0.0075 * H), (-0.0115 * H, yc + 0.0075 * H)])
    icon = P.patch(sleeve, P.intersect(env, outer), 0.0037 * H, k=0.0006 * H)
    vee = [(0.06 * H, yc + 0.0072 * H, -0.0112 * H), (0.06 * H, yc - 0.0005 * H, 0.0), (0.06 * H, yc + 0.0072 * H, 0.0112 * H)]
    pts = P.snap(sleeve, vee, [(1, 0, 0)], 0.04 * H, lift=0.0037 * H)
    icon = P.subtract(icon, P.tube(list(pts), 0.0011 * H, n=3), k=0.0005 * H)
    out = {}
    for side, key in ((1, "ArmL"), (-1, "ArmR")):
        fx = (lambda s: s) if side > 0 else P.mirror_x
        piv = r.armL if side > 0 else r.armR
        out[key] = [part(f"{key}_patch", fx(base), ck.clay(NAVY, 0.8), piv, 0.0007 * H, 150),
                    part(f"{key}_patchicon", fx(icon), ck.clay("#f8f6f0", 0.8), piv, 0.0005 * H, 110)]
    return out


# ====================================================================== the Letter
def letter(r):
    """state.js W.letter: cream box .26 x .14 x .01 in the right hand at arm-local (0, -.36H, .08).
    Origin at its own center, no rotation (the game turns it about y to bend it). Slightly bowed, a red
    stamp with a postmark, address lines on the front; the flap's V on the back."""
    w, h, t, bow = 0.13, 0.07, 0.005, 0.006

    def bend(s):
        return P.warp(s, lambda p: p + np.stack([np.zeros(len(p)), np.zeros(len(p)), bow * (p[:, 0] / w) ** 2], 1), pad=bow)
    env = P.rbox((0, 0, 0), (w, h, t), 0.0032)
    flap = P.union(*[P.capsule((sx * (w - 0.006), h - 0.006, -t), (0.0, -0.012, -t), 0.0017) for sx in (-1, 1)])
    ink = P.union(P.torus((w - 0.058, h - 0.036, t + 0.0004), 0.0145, 0.0012, rot=(math.pi / 2, 0, 0)),
                  *[P.capsule((-0.075, y, t + 0.0002), (x1, y, t + 0.0002), 0.0017) for y, x1 in ((-0.002, 0.035), (-0.018, 0.022), (-0.034, 0.03))])
    sx, sy = w - 0.03, h - 0.032                       # the stamp, a crisp little box riding the bow
    stamp = ck.box(0.034, 0.04, 0.0036, (sx, sy, t - bow * (sx / w) ** 2 + 0.0004), ck.clay("#c4162a", 0.7),
                   rot=(0, math.atan(2 * bow * sx / w ** 2), 0), name="Letter_stamp", bevel=0.0009, bevel_segs=2)
    objs = [P.sdf_mesh("Letter", bend(P.union(env, flap, k=0.0008)), ck.clay(CREAM, 0.85), 0.0009, 200), stamp,
            P.sdf_mesh("Letter_ink", bend(ink), ck.clay(INK, 0.7), 0.0005, 150)]
    lt = ck.join([o for o in objs if o], "Letter")
    cull_hidden(lt, bend(env), 0.0008)
    return P.in_hand(r, "R", lt, pos=(0, -0.06 * r.H, 0.08))


# ====================================================================== build
def make_mailman():
    ck.reset()
    random.seed(31)
    r = P.make_person(h=H_MAIL, skin="#e8b48a", top="#6a8ac8", pants=NAVY, hair="#5a3a1a", style="bald", mustache=True,
                      collar="button", pocket=True, tuck=True, belt="#2a2018", button_color="#f4f0e6",
                      lid=0.3, lid_tilt=0.16, lid_low=0.12, smile=0.95, mouth_w=1.05, mustache_style="handlebar",
                      nose="long", nose_size=1.05, cheeks=1.08, chin=1.05, gaze=(0.16, 0.0),
                      brow=dict(arch=1.6, tilt=-0.3, thick=1.1, raise_=0.003), seed=31)
    H = r.H
    meshes, dome, cutter = pith_helmet(r)
    join_into(r, "Head", meshes + [hat_hair(r, cutter, target=800)])
    join_into(r, "Body", satchel(r) + strap(r))
    for key, objs in list(sleeve_patches(r).items()) + list(trouser_stripes(r).items()):
        join_into(r, key, objs)
    cull_person(r, head_solid=P.union(r.sdf["head"], dome))
    lt = letter(r)
    return r, lt


def tiles(r):
    H = r.H
    hc = 0.47 * H + 0.36 * H + r.hy
    walk = dict(walk=0.5, armR=(-0.3, 0.1), armL=(0.2, 0.1))
    bend = dict(armR=(-1.4, -0.25), armL=(-1.4, 0.3), nod=0.2)
    return {
        "_pose": [dict(pose=bend, eye=(0.75 * H, 1.0 * H, 1.5 * H), look=(0.03 * H, 0.75 * H, 0.15 * H), lens=45),
                  dict(pose=bend, eye=(0.05 * H, 1.55 * H, 0.75 * H), look=(0.03 * H, 0.75 * H, 0.2 * H), lens=40),
                  dict(pose=walk, eye=(2.3 * H, 0.6 * H, 0.45 * H), look=(0, 0.5 * H, 0), lens=45),
                  dict(pose=dict(walk=0.5, phase=-math.pi / 2, armR=(-0.3, 0.1), armL=(0.2, 0.1)), eye=(-2.0 * H, 0.65 * H, 1.2 * H), look=(0, 0.45 * H, 0), lens=45)],
        "_pose2": [dict(pose=dict(armR=(-0.2, 0.1), armL=(-0.2, 0.1)), eye=(-0.9 * H, 0.85 * H, -1.6 * H), look=(0, 0.55 * H, 0), lens=45),
                   dict(pose=dict(armR=(-0.2, 0.15), armL=(-0.2, 0.15)), eye=(0.3 * H, hc + 0.05 * H, 0.8 * H), look=(0, hc - 0.02 * H, 0), lens=50),
                   dict(pose=dict(armR=(-0.2, 0.1), armL=(-0.2, 0.1)), eye=(-0.55 * H, 0.45 * H, 0.75 * H), look=(-0.12 * H, 0.47 * H, 0.08 * H), lens=45),
                   dict(pose=bend, eye=(-0.35 * H, 0.95 * H, 0.7 * H), look=(-0.05 * H, 0.76 * H, 0.2 * H), lens=45)],
    }


def build():
    r, lt = make_mailman()
    report(r, "mailman")
    P.export_character("mailman")
    for label, pose in (("bend as given", dict(armR=(-1.4, -0.25), armL=(-1.4, 0.3), nod=0.2)),
                        ("bend outward flipped", dict(armR=(-1.4, 0.25), armL=(-1.4, -0.3), nod=0.2)),
                        ("walk", dict(walk=0.5, armR=(-0.3, 0.1), armL=(0.2, 0.1)))):
        hand_report(r, pose, label, lt)
    ck.preview("mailman")
    for suffix, tl in tiles(r).items():
        P.pose_sheet(r, "mailman" + suffix, tl)
    return r


if __name__ == "__main__":
    build()
