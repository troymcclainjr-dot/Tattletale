"""Facade kits for the Pen Lucy archetype pass.

process.py hands every site building to build(): its pieces (main body, porch, rear addition) with
their roof functions, its front axis, porch depth and height, and its archetype. The kits add what
a model maker would sculpt on a Baltimore street: windows with frames, meeting rails and sills,
doors with transoms, cornices on brackets, open front porches (deck, posts, railings, roof, steps),
marble stoops, storefronts with sign bands and awnings, and chimneys.

Every part is a box with chamfered edges, smooth shaded so it reads as soft clay; the thumbprints
come from the Godot clay shader. Pure numpy, so the thousand-odd houses build in seconds.
"""
import zlib

import numpy as np
import shapely
from shapely.geometry import Point
from shapely.geometry.polygon import orient

# material id -> (kind, hex, roughness), merged into process.py's MATS
KIT_MATS = {
    "brick_2": ("clay", "#8a4a3a", 0.9), "brick_3": ("clay", "#a8644a", 0.9), "brick_dark": ("clay", "#6e3a30", 0.9),
    "formstone": ("clay", "#9a968c", 0.92), "formstone_tan": ("clay", "#b4a68a", 0.92), "painted": ("clay", "#d8d0c0", 0.86),
    "trim_white": ("clay", "#f4f0e6", 0.8), "trim_cream": ("clay", "#e2d4b4", 0.8), "trim_green": ("clay", "#3f5a44", 0.8),
    "trim_brown": ("clay", "#5a3a28", 0.8), "trim_red": ("clay", "#8a2a24", 0.8),
    "door_red": ("gloss", "#8a2420", 0.45), "door_green": ("gloss", "#2f4a34", 0.45), "door_blue": ("gloss", "#2a3a5a", 0.45),
    "door_black": ("gloss", "#1e1c1c", 0.45), "door_wood": ("gloss", "#6a4426", 0.5), "door_white": ("gloss", "#e8e4da", 0.45),
    "glass": ("gloss", "#1a2230", 0.25), "knob": ("metal", "#c8a040", 0.35),
    "porch_floor": ("clay", "#8a8a90", 0.9), "marble": ("clay", "#eeeae0", 0.6),
    "awning_green": ("clay", "#3f6a4a", 0.85), "awning_red": ("clay", "#9a3a32", 0.85),
    "awning_brown": ("clay", "#6a4a32", 0.85), "awning_white": ("clay", "#d8d8d0", 0.85),
    "sign_navy": ("clay", "#1a2a5a", 0.8), "sign_red": ("clay", "#8a2420", 0.8), "sign_green": ("clay", "#2f4a34", 0.8),
    "roof_silver": ("clay", "#a8a8ae", 0.7), "roof_tar": ("clay", "#3e3e44", 0.95),
}
BRICKS = ["brick", "brick_2", "brick_3", "brick_dark"]
FRONT_OVERRIDE = [("formstone", 0.12), ("formstone_tan", 0.06), ("painted", 0.07)]
TRIMS = [("trim_white", 0.5), ("trim_cream", 0.2), ("trim_green", 0.1), ("trim_brown", 0.1), ("trim_red", 0.1)]
DOORS = ["door_red", "door_green", "door_blue", "door_black", "door_wood", "door_white"]
AWNINGS = ["awning_green", "awning_red", "awning_brown", "awning_white"]
SIGNS = ["sign_navy", "sign_red", "sign_green"]


def seeded(key):
    return np.random.default_rng(zlib.crc32(str(key).encode()))


def pick(rng, weighted):
    names, w = zip(*weighted)
    return names[int(rng.choice(len(names), p=np.array(w) / sum(w)))]


# ------------------------------------------------------------------ soft boxes
def _soft_template():
    """A box with the four edges along one axis cut at 45 degrees: an octagon (in p, q) swept
    along s. 16 vertices, 28 triangles (8 side quads, 2 capping fans). Vertex columns: end sign,
    p sign, q sign, p cut, q cut; side[t] = which side quad a triangle belongs to (-1 for caps)."""
    oct_ = [(1, 1, 0, 1), (1, 1, 1, 0), (-1, 1, 1, 0), (-1, 1, 0, 1),
            (-1, -1, 0, 1), (-1, -1, 1, 0), (1, -1, 1, 0), (1, -1, 0, 1)]
    V = np.array([(e, *o) for e in (-1, 1) for o in oct_], float)
    F, side = [], []
    for k in range(8):
        k1 = (k + 1) % 8
        F += [[k, k1, 8 + k1], [k, 8 + k1, 8 + k]]
        side += [k, k]
    for e in (0, 8):
        for i in range(1, 7):
            F.append([e, e + i, e + i + 1])
            side.append(-1)
    return V, np.array(F), np.array(side)


_V, _F, _SIDE = _soft_template()
# where s, p, q go in (a, b, up): long horizontal parts sweep along a, posts and chimneys along up
_AXES = {"a": (0, 1, 2), "z": (2, 0, 1)}
_BACK = {"a": 3, "z": 5}            # the side quad lying on -b, against the wall


def boxes(c, size, a, r, back, axis):
    """Triangles (k, 3, 3) for many boxes: center c (N,3), size (N,3) along (a, b, up) where b is a
    turned 90 degrees clockwise (outward from a wall running along a), edge cut r (N,), keep the
    back face or not (N,), and which way the cut edges run, "a" or "z" (N,). r = 0 gives a plain box."""
    c, size, a, r, back = (np.asarray(x, float) for x in (c, size, a, r, back))
    axis = np.asarray(axis)
    out = []
    for ax, (ia, ib, iz) in _AXES.items():
        m = axis == ax
        if not m.any():
            continue
        cc, h, aa, bk = c[m], size[m] / 2, a[m], back[m]
        hs, hp, hq = h[:, ia], h[:, ib], h[:, iz]
        rr = np.minimum(r[m], np.minimum(hp, hq) * 0.45)
        loc = np.empty((len(cc), 16, 3))
        loc[..., ia] = _V[None, :, 0] * hs[:, None]
        loc[..., ib] = _V[None, :, 1] * (hp[:, None] - rr[:, None] * _V[None, :, 3])
        loc[..., iz] = _V[None, :, 2] * (hq[:, None] - rr[:, None] * _V[None, :, 4])
        bb = np.column_stack([aa[:, 1], -aa[:, 0]])
        W = np.empty_like(loc)
        W[..., 0] = cc[:, None, 0] + loc[..., 0] * aa[:, None, 0] + loc[..., 1] * bb[:, None, 0]
        W[..., 1] = cc[:, None, 1] + loc[..., 0] * aa[:, None, 1] + loc[..., 1] * bb[:, None, 1]
        W[..., 2] = cc[:, None, 2] + loc[..., 2]
        T = W[:, _F]                                                        # (n, 28, 3, 3)
        keep = ~((bk < 0.5)[:, None] & (_SIDE == _BACK[ax])[None, :])
        ctr = np.broadcast_to(cc[:, None, :], (len(cc), len(_F), 3))[keep]
        T = T[keep]
        nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        good = np.linalg.norm(nrm, axis=1) > 1e-9                          # drops the cuts of plain boxes
        inward = (nrm * (T.mean(1) - ctr)).sum(1) < 0                       # boxes are convex: face away from the center
        T[inward] = T[inward][:, ::-1]
        out.append(T[good])
    return np.concatenate(out) if out else np.zeros((0, 3, 3))


class Parts:
    """Boxes collected for one mesh, emitted per material in one vectorized call."""

    def __init__(s):
        s.items = {}

    def box(s, c, size, a, mat, r=0.0, back=True, axis="a"):
        if min(size) <= 1e-3:
            return
        s.items.setdefault(mat, []).append((c, size, a, r, back, axis))

    def emit(s, mb):
        for mat, it in s.items.items():
            c, size, a, r, back, axis = zip(*it)
            mb.add(boxes(np.array(c), np.array(size), np.array(a), np.array(r), np.array(back, float), np.array(axis)),
                   mat, smooth=True)
        s.items = {}


class Wall:
    """A wall seen from outside: u runs left to right from p0 to p1, v outward, z absolute."""

    def __init__(s, p0, p1):
        s.p0 = np.asarray(p0, float)
        d = np.asarray(p1, float) - s.p0
        s.L = float(np.hypot(*d))
        s.a = d / max(s.L, 1e-9)
        s.b = np.array([s.a[1], -s.a[0]])

    def at(s, u, v=0.0):
        return s.p0 + s.a * u + s.b * v

    def box(s, P, u0, u1, v0, v1, z0, z1, mat, r=0.0, back=None, axis="a"):
        m = s.at((u0 + u1) / 2, (v0 + v1) / 2)
        P.box((m[0], m[1], (z0 + z1) / 2), (u1 - u0, v1 - v0, z1 - z0), s.a, mat, r,
              back if back is not None else v0 > 1e-3, axis)


# ------------------------------------------------------------------ parts
def window(P, W, u, zs, ww, wh, st, simple=False, awning=None):
    """A double-hung window: frame, dark pane, meeting rail, sill, and a lintel on brick fronts."""
    t = st["trim"]
    if simple:
        W.box(P, u - ww / 2 - 0.07, u + ww / 2 + 0.07, 0, 0.04, zs, zs + wh, t)
        W.box(P, u - ww / 2, u + ww / 2, 0.04, 0.065, zs + 0.07, zs + wh - 0.07, "glass")
        W.box(P, u - ww / 2 - 0.1, u + ww / 2 + 0.1, 0, 0.12, zs - 0.09, zs, t, r=0.03)
        return
    W.box(P, u - ww / 2 - 0.09, u + ww / 2 + 0.09, 0, 0.05, zs - 0.02, zs + wh + 0.02, t)
    W.box(P, u - ww / 2, u + ww / 2, 0.05, 0.075, zs + 0.07, zs + wh - 0.07, "glass")
    W.box(P, u - ww / 2 + 0.02, u + ww / 2 - 0.02, 0.05, 0.095, zs + wh * 0.5 - 0.04, zs + wh * 0.5 + 0.04, t)
    W.box(P, u - ww / 2 - 0.15, u + ww / 2 + 0.15, 0, 0.17, zs - 0.13, zs - 0.01, t, r=0.035)
    if st["lintel"]:
        W.box(P, u - ww / 2 - 0.13, u + ww / 2 + 0.13, 0, 0.08, zs + wh + 0.04, zs + wh + 0.24, st["lintel"], r=0.03)
    if awning:
        z = zs + wh + 0.3
        for k, (v0, v1) in enumerate(((0, 0.22), (0.2, 0.42), (0.4, 0.62))):     # stepped slope, sculpted
            W.box(P, u - ww / 2 - 0.12, u + ww / 2 + 0.12, v0, v1, z - 0.12 * k - 0.07, z - 0.12 * k, awning, r=0.02)
        W.box(P, u - ww / 2 - 0.12, u + ww / 2 + 0.12, 0.56, 0.63, z - 0.62, z - 0.24, awning, r=0.02)


def door(P, W, u, z0, st, top=None):
    """Door with a transom; top caps the frame under a low eave."""
    t = st["trim"]
    fz = min(z0 + 2.78, top) if top else z0 + 2.78
    W.box(P, u - 0.62, u + 0.62, 0, 0.05, z0, fz, t)                               # frame
    W.box(P, u - 0.48, u + 0.48, 0.05, 0.085, z0, min(z0 + 2.16, fz - 0.1), st["door"], r=0.02)
    if fz - z0 > 2.6:
        W.box(P, u - 0.48, u + 0.48, 0.05, 0.075, z0 + 2.26, fz - 0.12, "glass")    # transom
    W.box(P, u + 0.28, u + 0.36, 0.085, 0.14, z0 + 1.0, z0 + 1.08, "knob")


def cornice(P, W, eave, st, brackets=True):
    t = st["trim"]
    W.box(P, -0.04, W.L + 0.04, 0, 0.34, eave - 0.42, eave + 0.1, t, r=0.05)
    if brackets:
        for u in np.linspace(0.22, W.L - 0.22, max(2, int(W.L / 1.6) + 1)):
            W.box(P, u - 0.08, u + 0.08, 0, 0.27, eave - 0.78, eave - 0.42, t)


def steps(P, W, u, top, ground, v0, mat, width=1.25, max_run=1.8):
    """Treads down from a deck at height top to the ground, starting at v0 and stepping outward."""
    rise_total = top - ground
    if rise_total < 0.12:
        return
    n = int(np.clip(round(rise_total / 0.19), 1, 8))
    run = min(0.3, max_run / n)
    rise = rise_total / n
    for i in range(1, n):
        W.box(P, u - width / 2, u + width / 2, v0 + (i - 1) * run, v0 + i * run, ground - 0.3, top - i * rise, mat, r=0.03)


def porch(P, W, d, floor0, top, g_front, st, door_u):
    """An open front porch across the whole front: deck on a solid base, posts, railing with
    a gap at the steps, a roof slab with a fascia, and steps down to the walk."""
    L, t = W.L, st["trim"]
    W.box(P, 0.03, L - 0.03, 0.0, d - 0.02, g_front - 0.6, floor0, "porch_floor", r=0.04)
    posts = np.linspace(0.16, L - 0.16, max(2, int(L / 2.4) + 1))
    for u in posts:
        W.box(P, u - 0.1, u + 0.1, d - 0.33, d - 0.13, floor0, top - 0.2, t, r=0.035, axis="z")
    W.box(P, -0.03, L + 0.03, 0.0, d + 0.18, top - 0.2, top, "porch_roof", r=0.04)
    W.box(P, -0.03, L + 0.03, d + 0.06, d + 0.2, top - 0.44, top - 0.18, t, r=0.03)
    gap = (door_u - 0.66, door_u + 0.66)
    for u0, u1 in zip(posts[:-1], posts[1:]):
        for a0, a1 in ((u0 + 0.1, min(u1 - 0.1, gap[0])), (max(u0 + 0.1, gap[1]), u1 - 0.1)):
            if a1 - a0 < 0.25:
                continue
            W.box(P, a0, a1, d - 0.28, d - 0.18, floor0 + 0.82, floor0 + 0.93, t, r=0.025)
            W.box(P, a0, a1, d - 0.27, d - 0.19, floor0 + 0.1, floor0 + 0.18, t)
            nb = max(1, int((a1 - a0) / 0.6))
            for k in range(nb):
                uu = a0 + (k + 0.5) * (a1 - a0) / nb
                W.box(P, uu - 0.035, uu + 0.035, d - 0.26, d - 0.2, floor0 + 0.18, floor0 + 0.82, t)
    for u in (0.08, L - 0.08):                                                     # side rails
        W.box(P, u - 0.05, u + 0.05, 0.2, d - 0.3, floor0 + 0.82, floor0 + 0.93, t, r=0.025)
    steps(P, W, door_u, floor0, g_front, d, "porch_floor")


def storefront(P, W, z0, st, door_u):
    """Ground floor shop: knee wall, display glass with mullions, door, sign band, maybe an awning."""
    L, t = W.L, st["trim"]
    W.box(P, 0.12, L - 0.12, 0, 0.07, z0 - 0.2, z0 + 0.5, st["base"], r=0.03)
    spans = [(0.25, door_u - 0.7), (door_u + 0.7, L - 0.25)]
    for a0, a1 in spans:
        if a1 - a0 < 0.6:
            continue
        W.box(P, a0 - 0.06, a1 + 0.06, 0, 0.05, z0 + 0.5, z0 + 3.0, t)
        W.box(P, a0, a1, 0.05, 0.075, z0 + 0.58, z0 + 2.92, "glass")
        for u in np.linspace(a0, a1, max(2, int((a1 - a0) / 1.6) + 1))[1:-1]:
            W.box(P, u - 0.04, u + 0.04, 0.05, 0.1, z0 + 0.58, z0 + 2.92, t)
    door(P, W, door_u, z0, st)
    W.box(P, 0.08, L - 0.08, 0, 0.14, z0 + 3.1, z0 + 3.8, st["sign"], r=0.04)
    if st["awning"]:
        for k, (v0, v1) in enumerate(((0, 0.45), (0.42, 0.87), (0.84, 1.3))):
            W.box(P, 0.15, L - 0.15, v0, v1, z0 + 3.05 - 0.16 * k - 0.08, z0 + 3.05 - 0.16 * k, st["awning"], r=0.025)
        W.box(P, 0.15, L - 0.15, 1.24, 1.32, z0 + 2.35, z0 + 2.75, st["awning"], r=0.02)


def windows_grid(P, W, floor0, floors, fh, st, eave, ground, ww=0.95):
    """Plain windows on a side or back wall, on the same floor levels as the front."""
    n = int((W.L - 0.6) / 2.6)
    if n < 1:
        return
    for f in range(floors):
        zs = floor0 + f * fh + 0.85
        wh = min(1.55, fh - 1.05)
        if zs + wh > eave - 0.35 or wh < 0.8 or zs < ground + 0.4:
            continue
        for k in range(n):
            window(P, W, (k + 0.5) * W.L / n, zs, ww, wh, st, simple=True)


# ------------------------------------------------------------------ houses
def style(b, row_seed):
    """Per-house look, seeded by the OSM id (rows share their brick and roof)."""
    rng, rr = seeded(b["id"]), seeded(row_seed)
    wall = BRICKS[int(rr.integers(len(BRICKS)))]
    for name, p in FRONT_OVERRIDE:
        if rng.random() < p:
            wall = name
            break
    trim = pick(rng, TRIMS)
    return {
        "wall": wall, "roof": "roof_silver" if rr.random() < 0.6 else "roof_tar",
        "trim": trim, "door": DOORS[int(rng.integers(len(DOORS)))],
        "lintel": (["trim_white", "trim_cream", "formstone"][int(rng.integers(3))] if wall.startswith("brick") and rng.random() < 0.6 else None),
        "awnings": AWNINGS[int(rng.integers(len(AWNINGS)))] if rng.random() < 0.25 else None,
        "awning": AWNINGS[int(rng.integers(len(AWNINGS)))] if rng.random() < 0.5 else None,
        "sign": SIGNS[int(rng.integers(len(SIGNS)))], "base": "formstone" if wall != "formstone" else "porch_floor",
        "chimney": rng.random() < 0.55, "rng": rng,
    }


def _main_poly(b):
    parts = [g for kind, geom, fn in b["pieces"] if kind == "main" for g in shapely.get_parts(geom)
             if g.geom_type == "Polygon" and g.area > 1.0]
    return max(parts, key=lambda g: g.area) if parts else None


def _edges(poly):
    r = np.array(orient(poly, 1.0).exterior.coords)
    return [(r[i], r[i + 1]) for i in range(len(r) - 1)]


def build(P, b, ctx):
    """Add the archetype's parts for one site building to P. ctx: H(x, y) ground sampler and
    exposed(xy) -> True when no footprint covers that point. b["roof_at"](xy) -> main roof z."""
    arch = b["arch"]
    if arch == "garage":
        return
    main = _main_poly(b)
    if main is None:
        return
    st = b["style"]
    n = b["n"] if b["n"] is not None else np.array([0.0, 1.0])
    c = np.array(main.centroid.coords[0])
    roof_at = b["roof_at"]

    def ground(pt):
        return float(ctx["H"](np.array([pt[0]]), np.array([pt[1]]))[0])

    cand = []
    for p0, p1 in _edges(main):
        d = p1 - p0
        L = float(np.hypot(*d))
        if L < 2.0:
            continue
        out = np.array([d[1], -d[0]]) / L
        mid = (p0 + p1) / 2
        cand.append((float(out @ n), float((mid - c) @ n), L, p0, p1))
    front = max((e for e in cand if e[0] > 0.85), key=lambda e: (round(e[1], 1), e[2]), default=None)
    if front is None:
        return
    W = Wall(front[3], front[4])
    L = W.L
    g = ground(W.at(L / 2, 0.4))
    ends = roof_at(np.array([W.at(0.05), W.at(L - 0.05)]))
    eave = float(ends.min())
    shop = arch == "storefront"
    floor0 = g + (0.15 if shop else 0.7)
    clear = eave - floor0                     # floor of the first storey up to the roof edge
    if clear < 2.6:
        return                                # too low for a storey: leave the plain mass
    usable = clear - 0.45
    floors = int(np.clip(round(usable / 3.05), 1, 5))
    fh = usable / floors
    door_left = b.get("door_left", True)
    door_u = min(0.9, L / 2) if door_left else max(L - 0.9, L / 2)
    rng = st["rng"]
    has_cornice = arch in ("row_porch", "row", "storefront") and clear >= 3.4
    roof_line = eave - (0.85 if has_cornice else 0.4)     # window tops stay under the cornice brackets

    # ---- front
    if L >= 3.0:
        if shop and clear >= 4.2:
            storefront(P, W, floor0, st, door_u if L >= 6 else L / 2)
        else:
            door(P, W, door_u, floor0, st, top=eave - 0.15)
            span = (door_u + 0.75, L - 0.3) if door_left else (0.3, door_u - 0.75)
            k = max(0, min(3, int((span[1] - span[0]) / 1.45)))
            wh0 = min(1.7, roof_line - (floor0 + 0.7) if floors == 1 else 1.7)
            for i in range(k if wh0 >= 0.7 else 0):
                window(P, W, span[0] + (i + 0.5) * (span[1] - span[0]) / k, floor0 + 0.7, 0.95, wh0, st)
        up = max(1, min(4, int(L / 1.7)))
        wh = float(np.clip(fh - 1.15, 0.9, 1.65))
        shop_front = shop and clear >= 4.2
        for f in range(1, floors):
            zs = floor0 + f * fh + 0.75
            if shop_front:                    # upper floors start above the sign band
                zs = max(zs, floor0 + 4.05 + (f - 1) * fh)
            if zs + wh > roof_line:
                continue
            for i in range(up):
                window(P, W, (i + 0.5) * L / up, zs, 0.95, wh, st, awning=st["awnings"] if f == 1 else None)
        if has_cornice:
            cornice(P, W, eave, st, brackets=arch != "storefront" or L < 9)
        W.box(P, 0, L, 0, 0.04, g - 0.45, floor0 - 0.04, st["base"])                  # base course
        if b["arch"] in ("row_porch", "detached_porch") and b["porch"] > 0.8:
            top = float(np.clip(b["porch_top"], floor0 + 2.4, eave - 0.4))
            g_front = ground(W.at(L / 2, b["porch"] + 0.7))
            porch(P, W, b["porch"], floor0, top, min(g_front, floor0 - 0.1), st, door_u)
        elif not shop:                                                               # marble stoop
            g_front = ground(W.at(door_u, 1.2))
            W.box(P, door_u - 0.7, door_u + 0.7, 0, 0.45, g_front - 0.3, floor0, "marble", r=0.035)
            steps(P, W, door_u, floor0, min(g_front, floor0 - 0.1), 0.45, "marble", width=1.4, max_run=1.2)

    # ---- side and back walls that nobody leans on (end units, rear walls, detached houses)
    for dot, smid, L2, p0, p1 in cand:
        if p0 is front[3] or dot > 0.85:
            continue
        W2 = Wall(p0, p1)
        if not ctx["exposed"](W2.at(W2.L / 2, 0.4)):
            continue
        e2 = float(roof_at(np.array([W2.at(0.05), W2.at(W2.L - 0.05)])).min())
        windows_grid(P, W2, floor0, floors, fh, st, e2, ground(W2.at(W2.L / 2, 0.4)))

    # ---- chimney toward the back, near a party wall
    if st["chimney"] and b["arch"] in ("row_porch", "row", "detached", "detached_porch"):
        depth = min(8.0, max(2.0, (b["s1"] - b["s0"]) * 0.5))
        u = 0.55 if rng.random() < 0.5 else L - 0.55
        pt = W.at(u, -depth)
        if main.buffer(-0.4).contains(Point(pt)):
            z = float(roof_at(np.array([pt]))[0])
            P.box((pt[0], pt[1], z + 0.45), (0.7, 0.5, 1.3), W.a, st["wall"], r=0.05, back=True, axis="z")
            P.box((pt[0], pt[1], z + 1.15), (0.82, 0.62, 0.14), W.a, "formstone", r=0.03, back=True)
