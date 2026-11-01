"""Facade kits for the Pen Lucy archetype pass.

process.py hands every site building to build(): its pieces (main body, porch, rear addition) with
their roof functions, its front axis, porch depth and height, and its archetype. The kits add what
a model maker would sculpt on a Baltimore street: windows with frames, meeting rails and sills,
doors with transoms, cornices on brackets, open front porches (deck, posts, railings, roof, steps),
marble stoops, storefronts with sign bands and awnings, neighborhood corner shops, and chimneys.

Parts use restrained edge bevels and the shared weathered city materials. Pure numpy,
so the thousand-odd houses build in seconds.

Facade layout invariant (every house, front, side and rear): an upper storey never loses its
windows to a low eave or a porch roof. Upper sashes shorten, then lift, before a storey goes
blind; the open porch roof sits between the door head (2.40 m clear ceiling over the deck)
and the first upper sill (0.14 m clear air under the sill), keeping the surveyed porch
height whenever it fits. LAYOUT_AUDIT records the counts and minimum gaps.
"""
import json
import os
import zlib

import numpy as np
import shapely
from shapely.geometry import MultiPoint, Point, Polygon
from shapely.geometry.polygon import orient

BUILD_STATS = {"porches": 0, "stair_rail_terminal_posts": 0, "rear_doors": 0, "businesses": 0, "road_parts_rejected": 0, "max_stair_riser_m": 0.0, "min_stair_tread_m": 0.30}
LAYOUT_AUDIT = {"front_upper_floors": 0, "front_upper_floors_blind": 0, "front_sashes_shortened": 0,
                "porch_houses": 0, "porch_roofs_lowered": 0, "porch_roof_lowered_max_m": 0.0,
                "upper_sills_raised_for_porch": 0, "upper_sill_raised_max_m": 0.0,
                "min_porch_roof_to_upper_sill_m": None, "min_porch_ceiling_m": None, "porch_ceiling_below_target": 0,
                "upper_sash_overlapping_porch_roof": 0, "rear_side_sashes_fitted": 0, "rear_side_window_omissions": 0,
                "metal_awnings": 0, "awnings_omitted_under_cornice": 0, "neighborhood_shops": 0, "blind_upper_ids": [],
                "narrow_fronts_detailed": 0, "narrow_front_ids": []}

# Vertical facade rules shared by the layout and its audit (metres).
SILL_DROP = 0.13           # a full sash's sill box hangs this far below the opening
PORCH_SILL_GAP = 0.14      # clear air between the porch roof top and the upper sill underside
PORCH_SLAB = 0.20          # porch roof slab thickness
PORCH_MIN_CEILING = 2.40   # deck to porch roof underside: 2.16 m door leaf plus head room
MIN_SASH = 0.85            # shortest believable upper sash before a storey would go blind

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
    # Painted sheet-metal window awnings (clay kind so the shared shader weathers them).
    "tin_red": ("clay", "#9c3b30", 0.62), "tin_green": ("clay", "#3d6b4c", 0.62),
    "tin_brown": ("clay", "#6e4c34", 0.62), "tin_white": ("clay", "#dcdcd2", 0.62),
    # Neighborhood shop finishes.
    "shop_green": ("clay", "#2f6a44", 0.8), "shop_yellow": ("clay", "#d6ae2c", 0.72),
    "shutter_grey": ("clay", "#8e9094", 0.6), "shutter_dark": ("clay", "#5c5e62", 0.65),
    "fascia_white": ("clay", "#e8e6dc", 0.84), "fascia_worn": ("clay", "#cfc6ac", 0.9), "sign_pale": ("clay", "#e0d8bc", 0.88),
    "grime": ("clay", "#5a5044", 0.95), "plywood": ("clay", "#b08e5a", 0.92), "bars_dark": ("clay", "#2c2c30", 0.55),
    "concrete": ("clay", "#b6b2a6", 0.9),
}
TIN = {"awning_green": "tin_green", "awning_red": "tin_red", "awning_brown": "tin_brown", "awning_white": "tin_white"}
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

    def __init__(s, forbidden=None):
        s.items = {}
        s.prisms = []
        s.forbidden = forbidden
        s.section = "facade"
        s.rejected_sections = {}

    def box(s, c, size, a, mat, r=0.0, back=True, axis="a"):
        if min(size) <= 1e-3:
            return
        if s.forbidden is not None:
            aa = np.asarray(a); bb = np.array([aa[1], -aa[0]])
            footprint = Polygon([np.asarray(c[:2]) + aa * u * size[0] / 2 + bb * v * size[1] / 2
                                 for u, v in ((-1,-1),(1,-1),(1,1),(-1,1))])
            if footprint.intersects(s.forbidden):
                BUILD_STATS["road_parts_rejected"] += 1
                s.rejected_sections[s.section] = s.rejected_sections.get(s.section, 0) + 1
                return
        s.items.setdefault(mat, []).append((c, size, a, r, back, axis))

    def emit(s, mb):
        for mat, it in s.items.items():
            c, size, a, r, back, axis = zip(*it)
            mb.add(boxes(np.array(c), np.array(size), np.array(a), np.array(r), np.array(back, float), np.array(axis)),
                   mat, smooth=True)
        for triangles, mat in s.prisms:
            mb.add(triangles, mat, smooth=False)
        s.prisms = []
        s.items = {}

    def prism(s, polygon, bottom, top, mat):
        """Closed convex bay shell with flat walls and caps; no extra mesh/material."""
        poly = orient(Polygon(polygon), 1.0)
        if s.forbidden is not None and poly.intersects(s.forbidden):
            raise ValueError("Bay shell intersects protected roadway")
        ring = np.asarray(poly.exterior.coords[:-1])
        low = np.column_stack([ring, np.full(len(ring), bottom)])
        high = np.column_stack([ring, np.full(len(ring), top)])
        triangles = []
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            triangles.extend([[low[i], low[j], high[j]], [low[i], high[j], high[i]]])
        for i in range(1, len(ring) - 1):
            triangles.extend([[low[0], low[i + 1], low[i]], [high[0], high[i], high[i + 1]]])
        s.prisms.append((np.asarray(triangles), mat))

    def solid(s, corners, mat):
        """Closed convex hexahedron: ring 0-3 and the matching ring 4-7. Repeated corners
        collapse faces, so sloped pans, wedges and ramps share one flat-shaded path."""
        V = np.asarray(corners, float)
        if s.forbidden is not None and MultiPoint(V[:, :2]).convex_hull.intersects(s.forbidden):
            BUILD_STATS["road_parts_rejected"] += 1
            s.rejected_sections[s.section] = s.rejected_sections.get(s.section, 0) + 1
            return False
        T = V[_HEXA_F]
        nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        good = np.linalg.norm(nrm, axis=1) > 1e-9
        inward = (nrm * (T.mean(1) - V.mean(0))).sum(1) < 0
        T[inward] = T[inward][:, ::-1]
        s.prisms.append((T[good], mat))
        return True


_HEXA_F = np.array([[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7]]
                   + [f for i in range(4) for f in ([i, (i + 1) % 4, 4 + (i + 1) % 4], [i, 4 + (i + 1) % 4, 4 + i])])


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

    def pt(s, u, v, z):
        return np.array([*s.at(u, v), z])

    def box(s, P, u0, u1, v0, v1, z0, z1, mat, r=0.0, back=None, axis="a"):
        m = s.at((u0 + u1) / 2, (v0 + v1) / 2)
        P.box((m[0], m[1], (z0 + z1) / 2), (u1 - u0, v1 - v0, z1 - z0), s.a, mat, r,
              back if back is not None else v0 > 1e-3, axis)


# ------------------------------------------------------------------ parts
def window(P, W, u, zs, ww, wh, st, simple=False, awning=None, awning_top=None):
    """A double-hung window: frame, dark pane, meeting rail, sill, and a lintel on brick fronts.
    awning_top: wall flashing height of the window's metal awning (default: just over the lintel);
    a hood mounted lower than the lintel's top replaces the lintel."""
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
    zt = (awning_top if awning_top is not None else zs + wh + awning_rise(st)) if awning else None
    if st["lintel"] and (zt is None or zt >= zs + wh + 0.5):
        W.box(P, u - ww / 2 - 0.13, u + ww / 2 + 0.13, 0, 0.08, zs + wh + 0.04, zs + wh + 0.24, st["lintel"], r=0.03)
    if awning:
        metal_awning(P, W, u - ww / 2 - 0.14, u + ww / 2 + 0.14, zt, TIN.get(awning, awning))


def awning_rise(st):
    """Height of a window awning's wall flashing above the sash top (clears the lintel)."""
    return 0.52 if st.get("lintel") else 0.40


def metal_awning(P, W, u0, u1, zt, mat, depth=0.62, drop=0.34, valance=0.15, grime=True):
    """One pitched sheet-metal pan from the wall flashing at zt down to a front valance, closed
    by two side cheeks that run from the wall to the valance. Every piece touches the next."""
    t, zf = 0.035, zt - drop
    zb = zf - valance
    P.solid([W.pt(u0, 0.0, zt - t), W.pt(u1, 0.0, zt - t), W.pt(u1, depth, zf - t), W.pt(u0, depth, zf - t),
             W.pt(u0, 0.0, zt), W.pt(u1, 0.0, zt), W.pt(u1, depth, zf), W.pt(u0, depth, zf)], mat)
    W.box(P, u0 - 0.012, u1 + 0.012, depth - 0.03, depth + 0.006, zb, zf + 0.012, mat, back=True)   # valance
    for c0, c1 in ((u0 - 0.022, u0), (u1, u1 + 0.022)):                                          # side cheeks
        P.solid([W.pt(c0, 0.0, zt), W.pt(c0, depth + 0.006, zf), W.pt(c0, depth + 0.006, zb), W.pt(c0, 0.0, zb),
                 W.pt(c1, 0.0, zt), W.pt(c1, depth + 0.006, zf), W.pt(c1, depth + 0.006, zb), W.pt(c1, 0.0, zb)], mat)
    W.box(P, u0 - 0.03, u1 + 0.03, 0.0, 0.05, zt - 0.02, zt + 0.06, mat, r=0.01)                 # wall flashing
    if grime:                                                                                     # rust line on the valance hem
        W.box(P, u0 + 0.04, u1 - 0.04, depth + 0.006, depth + 0.011, zb, zb + 0.035, "grime")
    LAYOUT_AUDIT["metal_awnings"] += 1


def upper_layout(floor0, floors, fh, wh, roof_line, eave, porch_lidar=None, band=None):
    """Sill height and sash height for each upper storey, and the porch roof they must clear.

    Rows are (floor, sill_z or None, sash_h). A storey keeps windows by shortening its sash to
    the roof line, then lifting or lowering the sill inside its legal range; only a storey with
    no room for a MIN_SASH window is blind. With a porch, the first upper sill rises to
    porch top + SILL_DROP + PORCH_SILL_GAP (towards the surveyed porch height when the
    sash still fits), and the porch roof is held between the door-head minimum and that sill.
    band: lowest sill over the ground-floor shop sign. Later storeys clear the
    previous sash; the ground-floor sign offset must not be added a second time.
    """
    rows, prev_top = [], None
    p_lo = floor0 + PORCH_MIN_CEILING + PORCH_SLAB
    clear = SILL_DROP + PORCH_SILL_GAP
    for f in range(1, floors):
        # A high surveyed porch must not consume the next storey's window space.
        # Reserve a minimum sash plus the existing inter-storey gap for every
        # later row before fitting this one; the main roof/eave is unchanged.
        row_limit = roof_line - (floors - f - 1) * (MIN_SASH + 0.75)
        nominal = floor0 + f * fh + 0.75
        lo = floor0 + f * fh + 0.30
        if f == 1 and porch_lidar is not None:
            lo = max(lo, p_lo + clear)
            nominal = max(nominal, min(porch_lidar + clear, row_limit - wh))
        if band is not None and f == 1:
            lo = max(lo, band)
        if prev_top is not None:
            lo = max(lo, prev_top + 0.75)                    # lintel, awning and sill room between storeys
        zs = max(nominal, lo)
        h = min(wh, row_limit - zs)
        if h < MIN_SASH:
            zs = max(lo, row_limit - MIN_SASH)
            h = min(wh, row_limit - zs)
        if h < MIN_SASH - 1e-6:
            rows.append((f, None, 0.0))
            continue
        rows.append((f, float(zs), float(h)))
        prev_top = zs + h
    porch_top = None
    if porch_lidar is not None:
        first = rows[0] if rows and rows[0][1] is not None else None
        hi = first[1] - clear if first else eave - 0.4
        # A single-storey front has no upper sash to clear. The old eave-0.4
        # preference could override the door-head minimum even though the roof
        # itself is high enough (build() requires >=2.6 m above the deck).
        porch_top = float(max(p_lo, min(max(porch_lidar, p_lo), hi)))
    return rows, porch_top


def _audit_min(key, value):
    value = round(float(value), 4)
    LAYOUT_AUDIT[key] = value if LAYOUT_AUDIT[key] is None else min(LAYOUT_AUDIT[key], value)


def layout_audit():
    """Summary for construction_audit: counts and the tightest measured gaps."""
    out = dict(LAYOUT_AUDIT)
    out["blind_upper_ids"] = sorted(set(out["blind_upper_ids"]))
    out["rules_m"] = {"sill_drop": SILL_DROP, "porch_roof_to_sill_clear_air": PORCH_SILL_GAP,
                      "porch_slab": PORCH_SLAB, "porch_min_ceiling": PORCH_MIN_CEILING, "min_upper_sash": MIN_SASH}
    return out


def bay_family(b):
    """Sparse, row-coherent oriels; Rose Hill retains its established treatment.

    A separate seed avoids shifting doors, awnings or any gameplay placement.
    Wider porch-front groups carry canted bays; a few stoop rows get shallow
    rectangular oriels. These are interpretive details, not surveyed additions.
    """
    if b.get("tags", {}).get("addr:street") == "Rose Hill Terrace":
        return "rose_hill"
    group = b.get("row", b["id"])
    selection = int(seeded(str(group) + ":oriel-family").integers(8))
    if b["arch"] == "row_porch" and selection < 3:
        return "canted"
    if b["arch"] == "row" and selection == 0:
        return "box"
    return None


def upper_bay(P, W, b, floor0, fh, eave, roof_line, door_left):
    """Three-sided projecting upper sash bays, above the porch roof.

    Independent seed preserves all existing doors, chimneys and ground-floor parts.
    White/cream/gray cladding, shallow cornices and varied projection stay inexpensive.
    """
    family = bay_family(b)
    if family is None:
        return False
    if b["arch"] not in ("row_porch", "row") or W.L < 4.3:
        return False
    rng = seeded(b["id"] + ":upper-bay")
    variant = int(rng.integers(3))
    width = min(W.L * 0.43, [2.25, 2.05, 2.35][variant])
    depth = [0.64, 0.52, 0.72][variant]
    if family == "box":
        width = min(width, 2.05)
        depth = 0.42
    u = W.L * (0.66 if door_left else 0.34)
    bottom = max(floor0 + fh + 0.10, float(b.get("porch_top", 0)) + 0.035)
    # A three-storey house must keep its third-floor sash grid above this bay.
    top = min(eave - 0.48, roof_line + 0.22, floor0 + 2 * fh - 0.25)
    wh = min(1.72, top - bottom - 0.48)
    if wh < 0.95:
        return False
    z = top - wh - 0.22
    half_front = width * [0.29, 0.32, 0.27][variant]
    if family == "box":
        half_front = width / 2
    outline = [W.at(u - width / 2, -0.025), W.at(u - half_front, depth),
               W.at(u + half_front, depth), W.at(u + width / 2, -0.025)]
    if P.forbidden is not None and Polygon(outline).buffer(0.19).intersects(P.forbidden):
        return False
    body = ["trim_white", "trim_cream", "formstone"][variant]
    trim = "trim_cream" if variant == 1 else "trim_white"
    P.prism(outline, bottom, top, body)
    faces = [Wall(outline[i], outline[i + 1]) for i in range(3)]
    sash = {"trim": trim, "lintel": None}
    for face in faces:
        window(P, face, face.L / 2, z, face.L - 0.24, wh, sash)
        # Closed sill and layered cornice wrap all three faces.
        face.box(P, -0.03, face.L + 0.03, -0.025, 0.09, bottom, bottom + 0.11, trim)
        face.box(P, -0.045, face.L + 0.045, -0.03, 0.12, top - 0.02, top + 0.10, trim)
        face.box(P, -0.065, face.L + 0.065, -0.04, 0.17, top + 0.10, top + 0.17, trim)
        for zz in np.arange(bottom + 0.20, z - 0.12, 0.18):
            face.box(P, 0.02, face.L - 0.02, 0.002, 0.012, zz, zz + 0.018, "formstone")
    # Small opaque weathered roof closes the top when seen from above.
    P.prism(outline, top + 0.17, top + 0.205, "roof_tar")
    b["upper_bay"] = {"xyz": [*W.at(u, depth), (bottom + top) / 2],
                      "normal_xy": W.b.tolist(), "width_m": width, "depth_m": depth,
                      "base_z": bottom, "top_z": top + 0.205, "storey_height_m": fh, "variant": variant,
                      "porch_clearance_m": bottom - float(b.get("porch_top", bottom)), "family": family}
    counter = "rose_hill_upper_bays" if family == "rose_hill" else "neighborhood_upper_bays"
    BUILD_STATS[counter] = BUILD_STATS.get(counter, 0) + 1
    return True


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
    """Four low-cost profiles within the existing sash/road-clearance envelope."""
    t = st["trim"]
    profile = st.get("cornice_profile", 0)
    if profile == 0:
        W.box(P, -0.04, W.L + 0.04, 0, 0.34, eave - 0.42, eave + 0.1, t, r=0.025)
    else:
        W.box(P, -0.02, W.L + 0.02, 0, 0.16, eave - 0.42, eave - 0.10, t)
        W.box(P, -0.04, W.L + 0.04, 0, 0.34, eave - 0.10, eave + 0.04, t, r=0.015)
        W.box(P, -0.03, W.L + 0.03, 0, 0.27, eave + 0.04, eave + 0.10, st["roof"])
        if profile == 2:
            # Raised central parapet tablet: readable silhouette, no tiny texture.
            W.box(P, W.L * .34, W.L * .66, 0, .16, eave + .10, eave + .31, st["wall"])
            W.box(P, W.L * .34 - .04, W.L * .66 + .04, 0, .24, eave + .31, eave + .39, t)
        elif profile == 3:
            for u in np.linspace(.22, W.L - .22, max(2, int(W.L / .75))):
                W.box(P, u - .055, u + .055, .16, .25, eave - .25, eave - .10, t)
    if brackets and profile in (0, 1):
        for u in np.linspace(0.22, W.L - 0.22, max(2, int(W.L / 1.6) + 1)):
            W.box(P, u - 0.08, u + 0.08, 0, 0.27, eave - 0.78, eave - 0.42, t)
    key = "cornice_profile_" + str(profile)
    BUILD_STATS[key] = BUILD_STATS.get(key, 0) + 1


def garage_front(P, W, ground, eave, st):
    """Inset reading for an existing garage mass; no new openings or colliders."""
    height = min(2.25, eave - ground - .24)
    width = min(W.L - .40, 3.5)
    if height < 1.35 or width < 1.8:
        return False
    left, right = (W.L - width) / 2, (W.L + width) / 2
    bottom, top = ground + .08, ground + height
    W.box(P, left - .06, right + .06, 0, .055, bottom, top + .07, st["trim"])
    W.box(P, left, right, .055, .075, bottom, top, "shutter_dark")
    for z in np.linspace(bottom + .18, top - .14, 5):
        W.box(P, left + .04, right - .04, .075, .085, z, z + .025, "shutter_grey")
    W.box(P, W.L / 2 - .16, W.L / 2 + .16, .085, .105, bottom + .85, bottom + .90, "bars_dark")
    BUILD_STATS["garage_fronts"] = BUILD_STATS.get("garage_fronts", 0) + 1
    return True


def steps(P, W, u, top, ground, v0, mat, width=1.25, max_run=1.8):
    """Treads down from a deck at height top to the ground, starting at v0 and stepping outward."""
    rise_total = top - ground
    if rise_total < 0.12:
        return
    n = max(1, int(np.ceil(rise_total / 0.18)))
    run = max(0.28, min(0.30, max_run / n))
    rise = rise_total / n
    BUILD_STATS["max_stair_riser_m"] = max(BUILD_STATS["max_stair_riser_m"], float(rise))
    BUILD_STATS["min_stair_tread_m"] = min(BUILD_STATS["min_stair_tread_m"], float(run))
    for i in range(1, n):
        W.box(P, u - width / 2, u + width / 2, v0 + (i - 1) * run, v0 + i * run, ground - 0.3, top - i * rise, mat, r=0.03)


def porch(P, W, d, floor0, top, g_front, st, door_u):
    """An open front porch across the whole front: deck on a solid base, posts, railing with
    a gap at the steps, a roof slab with a fascia, and steps down to the walk."""
    L, t = W.L, st["trim"]
    BUILD_STATS["porches"] += 1
    W.box(P, 0.03, L - 0.03, 0.0, d - 0.02, g_front - 0.6, floor0, "porch_floor", r=0.04)
    posts = np.linspace(0.16, L - 0.16, max(2, int(L / 2.4) + 1))
    for u in posts:
        W.box(P, u - 0.1, u + 0.1, d - 0.33, d - 0.13, floor0, top - 0.2, t, r=0.035, axis="z")
        if st.get("porch_profile", 0):
            # Capitals stay above walking headroom; shafts/entry gaps do not move.
            W.box(P, u - .14, u + .14, d - .37, d - .09, max(top - .37, floor0 + PORCH_MIN_CEILING), top - .24, t)
            if st["porch_profile"] == 2:
                W.box(P, u - .12, u + .12, d - .35, d - .11, max(top - .51, floor0 + PORCH_MIN_CEILING), top - .37, t)
    W.box(P, -0.03, L + 0.03, 0.0, d + 0.18, top - 0.2, top, "porch_roof", r=0.04)
    W.box(P, -0.03, L + 0.03, d + 0.06, d + 0.2, top - 0.44, top - 0.18, t, r=0.03)
    gap = (door_u - 0.66, door_u + 0.66)
    for u0, u1 in zip(posts[:-1], posts[1:]):
        for a0, a1 in ((u0 + 0.1, min(u1 - 0.1, gap[0])), (max(u0 + 0.1, gap[1]), u1 - 0.1)):
            if a1 - a0 < 0.25:
                continue
            # Cutting the rail for the stair opening must leave a supported end.
            # Newels sit outside the opening, preserving its full clear width.
            if abs(a1 - gap[0]) < 1e-6:
                W.box(P, a1 - 0.13, a1, d - 0.30, d - 0.16, floor0, floor0 + 1.0, t, r=0.02, axis="z")
                BUILD_STATS["stair_rail_terminal_posts"] += 1
            if abs(a0 - gap[1]) < 1e-6:
                W.box(P, a0, a0 + 0.13, d - 0.30, d - 0.16, floor0, floor0 + 1.0, t, r=0.02, axis="z")
                BUILD_STATS["stair_rail_terminal_posts"] += 1
            W.box(P, a0, a1, d - 0.28, d - 0.18, floor0 + 0.82, floor0 + 0.93, t, r=0.025)
            W.box(P, a0, a1, d - 0.27, d - 0.19, floor0 + 0.1, floor0 + 0.18, t)
            nb = max(1, int((a1 - a0) / 0.6))
            for k in range(nb):
                uu = a0 + (k + 0.5) * (a1 - a0) / nb
                W.box(P, uu - 0.035, uu + 0.035, d - 0.26, d - 0.2, floor0 + 0.18, floor0 + 0.82, t)
    for u in (0.08, L - 0.08):                                                     # side rails
        W.box(P, u - 0.05, u + 0.05, 0.0, d - 0.3, floor0 + 0.82, floor0 + 0.93, t, r=0.025)
    steps(P, W, door_u, floor0, g_front, d, "porch_floor")


def storefront(P, W, z0, st, door_u, business=None):
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
    # Commercial ground floor is generated instead of residential windows.
    kind = (business or {}).get("type", "market")
    if kind == "barber":
        for k in range(8):
            W.box(P, L - 0.27, L - 0.08, 0.18, 0.37, z0 + 0.8 + k * 0.17, z0 + 0.96 + k * 0.17,
                  ["trim_red", "trim_white", "door_blue"][k % 3], r=0.025, axis="z")
    elif kind == "laundromat":
        for u in np.arange(1.7, L - 0.6, 1.05):
            if abs(u - door_u) < 1.0: continue
            W.box(P, u - 0.38, u + 0.38, 0.08, 0.12, z0 + 0.63, z0 + 1.48, "trim_white")
            W.box(P, u - 0.24, u + 0.24, 0.12, 0.14, z0 + 0.84, z0 + 1.32, "glass", r=0.10, axis="z")
    elif kind == "liquor":
        for u in np.arange(0.55, L - 0.4, 0.24):
            if abs(u - door_u) < 0.72: continue
            W.box(P, u - 0.016, u + 0.016, 0.09, 0.13, z0 + 0.65, z0 + 2.88, "door_black")
    elif kind == "takeout":
        u = L - 0.65 if door_u < L / 2 else 0.65
        W.box(P, u - 0.37, u + 0.37, 0.10, 0.14, z0 + 0.9, z0 + 1.9, "trim_cream")
        for k in range(5):
            W.box(P, u - 0.28, u + 0.28, 0.14, 0.15, z0 + 1.05 + k * 0.14, z0 + 1.08 + k * 0.14, "trim_red")
    if st["awning"]:
        # One continuous pitched shop awning with a deep valance, same construction as the window hoods.
        metal_awning(P, W, 0.15, L - 0.15, z0 + 3.05, st["awning"], depth=1.3, drop=0.42, valance=0.28)


def windows_grid(P, W, floor0, floors, fh, st, eave, ground, ww=0.95, door_u=None, door_top=None,
                 first_floor=0, min_sill=None):
    """Plain windows on a side or back wall, on the same floor levels as the front.

    A low side/rear eave shortens, then lowers, the sash instead of dropping the storey; the
    window above a rear door lifts its sill clear of the door head. Shops pass first_floor=1
    (no residential ground-floor windows) and min_sill (above their sign band)."""
    n = int((W.L - 0.6) / 2.6)
    if n < 1:
        return
    limit = eave - 0.35
    for f in range(first_floor, floors):
        if f == 0 and floor0 + 0.85 < ground + 0.4:
            continue                          # a storey buried by an uphill yard keeps its blank wall
        lo = max(floor0 + f * fh + 0.35, ground + 0.4)
        if f >= 1 and min_sill is not None:
            lo = max(lo, min_sill)
        zs = max(floor0 + f * fh + 0.85, lo)
        wh = min(1.55, fh - 1.05)
        for k in range(n):
            u = (k + 0.5) * W.L / n
            near_door = door_u is not None and abs(u - door_u) < 0.7 + ww / 2
            if f == 0 and near_door:
                continue
            low = max(lo, door_top + 0.18) if near_door and door_top is not None else lo
            z = max(zs, low)
            h = min(wh, limit - z)
            if h < 0.8:
                z = max(low, limit - 0.8)
                h = min(wh, limit - z)
            if h < 0.8 - 1e-6:
                LAYOUT_AUDIT["rear_side_window_omissions"] += 1
                continue
            if h < wh - 1e-6 or z > zs + 1e-6 or z < zs - 1e-6:
                LAYOUT_AUDIT["rear_side_sashes_fitted"] += 1
            window(P, W, u, z, ww, h, st, simple=True)


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
        "cornice_profile": int(seeded(str(row_seed) + ":cornice-profile").integers(4)),
        "porch_profile": int(seeded(str(row_seed) + ":porch-profile").integers(3)),
    }


def _main_poly(b):
    parts = [g for kind, geom, fn in b["pieces"] if kind == "main" for g in shapely.get_parts(geom)
             if g.geom_type == "Polygon" and g.area > 1.0]
    merged = [g for g in shapely.get_parts(shapely.union_all(parts).simplify(0.025, preserve_topology=True)) if g.geom_type == "Polygon"]
    return max(merged, key=lambda g: g.area) if merged else None


def _edges(poly):
    r = np.array(orient(poly, 1.0).exterior.coords)
    return [(r[i], r[i + 1]) for i in range(len(r) - 1)]


def rear_entry(P, b, ctx, ground, floor0, n, roof_at):
    """Independent rear service entry; a low front eave must not skip it."""
    closed = shapely.union_all([geom for kind, geom, fn in b["pieces"] if kind != "porch"]).simplify(0.025, preserve_topology=True)
    center = np.array(closed.centroid.coords[0])
    candidates = []
    reasons = {"narrow_rear_wall": 0, "neighbor_obstructs_rear_wall": 0, "insufficient_rear_headroom": 0}
    for poly in shapely.get_parts(closed):
        if poly.geom_type != "Polygon": continue
        for p0, p1 in _edges(poly):
            w = Wall(p0, p1)
            facing = float(w.b @ n)
            if facing > 0.20: continue
            if w.L < 1.45:
                reasons["narrow_rear_wall"] += 1; continue
            positions = [w.L / 2] if facing < -0.65 else [0.75, w.L - 0.75, *[w.L * f for f in (0.25, 0.35, 0.45, 0.55, 0.65, 0.75)]]
            for u in positions:
                if u < 0.7 or u > w.L - 0.7: continue
                if facing > -0.65 and (w.at(u) - center) @ n > -0.5: continue
                if not all(ctx["exposed"](w.at(u + side, gap)) for side in (-0.58, 0.0, 0.58) for gap in (0.25, 0.85)):
                    reasons["neighbor_obstructs_rear_wall"] += 1; continue
                inside = Point(w.at(u, -0.04))
                covering = [(geom, fn) for kind, geom, fn in b["pieces"] if kind != "porch" and geom.buffer(0.03).covers(inside)]
                corners = np.array([w.at(u - 0.62), w.at(u + 0.62)])
                top = min((float(fn(corners).min()) for geom, fn in covering), default=float(roof_at(corners).min()))
                g = ground(w.at(u, 0.8))
                threshold = g + 0.15
                if top - threshold < 2.12:
                    reasons["insufficient_rear_headroom"] += 1; continue
                candidates.append((facing < -0.65, w.L, w, u, g, top, threshold))
    if not candidates:
        b["rear_door_status"] = next((key for key in ("insufficient_rear_headroom", "neighbor_obstructs_rear_wall", "narrow_rear_wall") if reasons[key]), "no_rear_facing_wall")
        b["rear_door_reasons"] = reasons
        return None
    _, _, w, u, g, top, threshold = max(candidates, key=lambda q: (q[0], q[1]))
    previous_section = P.section; P.section = "rear_entry"
    prior_rejected = P.rejected_sections.get("rear_entry", 0)
    door(P, w, u, threshold, b["style"], top=top - 0.12)
    w.box(P, u - 0.65, u + 0.65, 0, 0.45, g - 0.2, threshold, "porch_floor")
    steps(P, w, u, threshold, g, 0.45, "porch_floor")
    P.section = previous_section
    if P.rejected_sections.get("rear_entry", 0) > prior_rejected:
        b["rear_door_status"] = "carriageway_clearance_rejected_entry_part"
        return None
    b["rear_door"] = {"xyz": [*w.at(u, 0.20), threshold], "normal_xy": w.b.tolist(), "wall_u": u,
                      "head_z": min(threshold + 2.78, top - 0.12)}
    b["rear_door_status"] = "built"
    BUILD_STATS["rear_doors"] += 1
    return w


def _audit_front(b, rows, floor0, fh, wh, porch_lidar, porch_top):
    """Per-house front layout record plus the map-wide counters and minimum gaps."""
    LAYOUT_AUDIT["front_upper_floors"] += len(rows)
    blind = [f for f, zs, h in rows if zs is None]
    if blind:
        LAYOUT_AUDIT["front_upper_floors_blind"] += len(blind)
        LAYOUT_AUDIT["blind_upper_ids"].append(b["id"])
    LAYOUT_AUDIT["front_sashes_shortened"] += sum(1 for f, zs, h in rows if zs is not None and h < wh - 1e-6)
    record = {"floor0_z": round(floor0, 3), "storey_m": round(fh, 3),
              "upper_sills_z": [None if zs is None else round(zs, 3) for f, zs, h in rows],
              "upper_sash_m": [round(h, 3) for f, zs, h in rows]}
    if porch_lidar is not None:
        LAYOUT_AUDIT["porch_houses"] += 1
        record.update(porch_roof_z=round(porch_top, 3), porch_roof_surveyed_z=round(porch_lidar, 3))
        if porch_top < porch_lidar - 1e-3:
            LAYOUT_AUDIT["porch_roofs_lowered"] += 1
            LAYOUT_AUDIT["porch_roof_lowered_max_m"] = round(max(LAYOUT_AUDIT["porch_roof_lowered_max_m"], porch_lidar - porch_top), 4)
        elif porch_top > porch_lidar + 1e-3:
            LAYOUT_AUDIT["porch_roofs_raised_for_door_head"] = LAYOUT_AUDIT.get("porch_roofs_raised_for_door_head", 0) + 1
        ceiling = porch_top - PORCH_SLAB - floor0
        _audit_min("min_porch_ceiling_m", ceiling)
        if ceiling < PORCH_MIN_CEILING - 1e-6:
            LAYOUT_AUDIT["porch_ceiling_below_target"] += 1
        if rows and rows[0][1] is not None:
            gap = rows[0][1] - SILL_DROP - porch_top
            record["porch_to_sill_m"] = round(gap, 3)
            _audit_min("min_porch_roof_to_upper_sill_m", gap)
            if gap < PORCH_SILL_GAP - 1e-6:
                LAYOUT_AUDIT["upper_sash_overlapping_porch_roof"] += 1
            raised = rows[0][1] - (floor0 + fh + 0.75)
            if raised > 1e-3:
                LAYOUT_AUDIT["upper_sills_raised_for_porch"] += 1
                LAYOUT_AUDIT["upper_sill_raised_max_m"] = round(max(LAYOUT_AUDIT["upper_sill_raised_max_m"], raised), 4)
    b["facade_layout"] = record


def build(P, b, ctx):
    """Add the archetype's parts for one site building to P. ctx: H(x, y) ground sampler and
    exposed(xy) -> True when no footprint covers that point. b["roof_at"](xy) -> main roof z."""
    arch = b["arch"]
    b["rear_door_status"] = "main_front_geometry_unavailable"
    main = _main_poly(b)
    if main is None:
        return
    st = b["style"]
    n = b["n"] if b["n"] is not None else np.array([0.0, 1.0])
    c = np.array(main.centroid.coords[0])
    roof_at = b["roof_at"]

    def ground(pt):
        return float(ctx["H"](np.array([pt[0]]), np.array([pt[1]]))[0])

    rear_wall = None if arch == "garage" else rear_entry(P, b, ctx, ground, ground(c) + 0.15, n, roof_at)
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
    selected_edge = b.get("business", {}).get("front_edge")
    if selected_edge:
        # Use precisely the wall whose width, height, ground and pedestrian
        # clearance passed commercial selection. A small projecting bay can
        # otherwise win the independent residential front-wall heuristic.
        selected_wall = Wall(selected_edge[0], selected_edge[1])
        front = (float(selected_wall.b @ n), float((selected_wall.at(selected_wall.L / 2) - c) @ n),
                 selected_wall.L, np.asarray(selected_edge[0]), np.asarray(selected_edge[1]))
    if front is None:
        return
    W = Wall(front[3], front[4])
    L = W.L
    g = ground(W.at(L / 2, 0.4))
    ends = roof_at(np.array([W.at(0.05), W.at(L - 0.05)]))
    eave = float(ends.min())
    if arch == "garage":
        garage_front(P, W, g, eave, st)
        return
    shop = arch == "storefront"
    kit_shop = (b.get("business") or {}).get("kit")
    rise = float(b["business"].get("floor_rise", 0.15)) if kit_shop else (0.15 if shop else 0.7)
    floor0 = g + rise
    clear = eave - floor0                     # floor of the first storey up to the roof edge
    if clear < (2.3 if kit_shop else 2.6):
        return                                # too low for a storey: leave the plain mass
    usable = clear - 0.45
    floors = int(np.clip(round(usable / 3.05), 1, 5))
    fh = usable / floors
    door_left = b.get("door_left", True)
    door_u = min(0.9, L / 2) if door_left else max(L - 0.9, L / 2)
    rng = st["rng"]
    # A one-storey neighborhood shop carries a parapet signboard instead of a bracketed cornice.
    has_cornice = arch in ("row_porch", "row", "storefront") and clear >= 3.4 and not (kit_shop and floors == 1)
    roof_line = eave - (0.85 if has_cornice else 0.4)     # window tops stay under the cornice brackets
    shop_top = None
    # Preserve the actual selected facade for footprint-clipped front gardens.
    b["front_yard"] = {"edge": [W.p0.tolist(), W.at(W.L).tolist()],
                       "door": W.at(door_u).tolist(), "normal": W.b.tolist()}

    # ---- front
    # Narrow Baltimore row fronts can be below 3m after the surveyed porch
    # split. They still need a real entrance and upper sash (Row_170 was blank).
    if L >= 3.0 or (not shop and L >= 2.4):
        if L < 3.0:
            LAYOUT_AUDIT["narrow_fronts_detailed"] += 1
            LAYOUT_AUDIT["narrow_front_ids"].append(str(b["id"]))
        porch_house = arch in ("row_porch", "detached_porch") and b["porch"] > 0.8
        up = max(1, min(4, int(L / 1.7)))
        wh = float(np.clip(fh - 1.15, 0.9, 1.65))
        shop_front = shop and not kit_shop and clear >= 4.2
        if kit_shop:
            shop_top = neighborhood_shop(P, W, b, floor0, g, eave, floors, st, ground)
            door_u = b["business"]["door_u"]
            BUILD_STATS["businesses"] += 1
            LAYOUT_AUDIT["neighborhood_shops"] += 1
        band = shop_top + 0.35 if kit_shop else (floor0 + 4.05 if shop_front else None)
        porch_lidar = float(b["porch_top"]) if porch_house else None
        rows, porch_top = upper_layout(floor0, floors, fh, wh, roof_line, eave, porch_lidar, band)
        if porch_house:
            # Geometry and exported data share the built porch roof; keep the survey value too.
            b["porch_top_surveyed"] = porch_lidar
            b["porch_top"] = porch_top
        if kit_shop:
            pass
        elif shop_front:
            shop_u = door_u if L >= 6 else L / 2
            storefront(P, W, floor0, st, shop_u, b.get("business"))
            if b.get("business"):
                b["business"].update(sign_xyz=[*W.at(L / 2, 0.18), floor0 + 3.45], sign_width=L - 0.32,
                                     door_xyz=[*W.at(shop_u, 0.35), floor0], normal_xy=W.b.tolist())
                BUILD_STATS["businesses"] += 1
        else:
            door_top = eave - 0.15
            if porch_top is not None:
                door_top = min(door_top, porch_top - PORCH_SLAB - 0.02)
            door(P, W, door_u, floor0, st, top=door_top)
            span = (door_u + 0.75, L - 0.3) if door_left else (0.3, door_u - 0.75)
            k = max(0, min(3, int((span[1] - span[0]) / 1.45)))
            sash_width = 0.95
            if L < 3.0 and span[1] - span[0] >= 0.72:
                k = 1
                sash_width = min(0.95, span[1] - span[0] - 0.12)
            wh0 = min(1.7, roof_line - (floor0 + 0.7) if floors == 1 else 1.7)
            if porch_top is not None:                  # lintel stays under the porch ceiling
                wh0 = min(wh0, porch_top - PORCH_SLAB - 0.30 - (floor0 + 0.7))
            for i in range(k if wh0 >= 0.7 else 0):
                window(P, W, span[0] + (i + 0.5) * (span[1] - span[0]) / k, floor0 + 0.7, sash_width, wh0, st)
        b["front_yard"]["door"] = W.at(door_u).tolist()
        awning_cap = eave - 0.80 if has_cornice else eave - 0.12
        for f, zs, h in rows:
            if zs is None:
                continue
            if f == 1 and upper_bay(P, W, b, floor0, fh, eave, roof_line, door_left):
                # Replace the original window grid on this floor, retaining a
                # single recessed sash above the doorway as in the reference.
                window(P, W, door_u, zs, 0.95, h, st)
                continue
            awning = st["awnings"] if f == 1 else None
            awning_top = min(zs + h + awning_rise(st), awning_cap) if awning else None
            # Under a low cornice the hood may drop over the sash head, never past its upper half.
            if awning and awning_top - 0.49 < zs + 0.55 * h:
                awning = awning_top = None     # every window on the storey loses it alike
                LAYOUT_AUDIT["awnings_omitted_under_cornice"] += 1
            for i in range(up):
                window(P, W, (i + 0.5) * L / up, zs, 0.95, h, st, awning=awning, awning_top=awning_top)
        _audit_front(b, rows, floor0, fh, wh, porch_lidar, porch_top)
        if has_cornice:
            cornice(P, W, eave, st, brackets=arch != "storefront" or L < 9)
        elif arch in ("detached", "detached_porch") and float(np.ptp(ends)) < .25:
            # A slim eave fascia only on a nearly level surveyed roof edge.
            # Never draw a floating horizontal beam across a pitched gable.
            W.box(P, -.02, L + .02, 0, .16, eave - .16, eave + .025, st["trim"])
            BUILD_STATS["detached_fascias"] = BUILD_STATS.get("detached_fascias", 0) + 1
        W.box(P, 0, L, 0, 0.04, g - 0.45, floor0 - 0.04, st["base"])                  # base course
        if porch_house:
            top = porch_top
            g_front = ground(W.at(L / 2, b["porch"] + 0.7))
            porch_depth = b["porch"]
            stair_ground = min(g_front, floor0 - 0.1)
            stair_n = max(1, int(np.ceil((floor0 - stair_ground) / 0.18)))
            run = max(0.28, min(0.30, 1.8 / stair_n))
            if P.forbidden is not None:
                while porch_depth > 0.9:
                    flight = Polygon([W.at(door_u + u, v) for u, v in
                                      ((-0.7, porch_depth), (0.7, porch_depth), (0.7, porch_depth + stair_n * run), (-0.7, porch_depth + stair_n * run))])
                    if not flight.intersects(P.forbidden): break
                    porch_depth -= 0.1
            P.section = "porch_and_stairs"
            before_rejected = P.rejected_sections.get(P.section, 0)
            porch(P, W, porch_depth, floor0, top, stair_ground, st, door_u)
            porch_rejected = P.rejected_sections.get(P.section, 0) - before_rejected
            P.section = "facade"
            stair_n = max(1, int(np.ceil((floor0 - stair_ground) / 0.18)))
            stair_run = max(0.28, min(0.30, 1.8 / stair_n))
            b["porch_stair"] = {"landing_xyz": [*W.at(door_u, porch_depth - 0.45), floor0],
                                "approach_xyz": [*W.at(door_u, porch_depth + stair_n * stair_run + 0.6), g_front],
                                "normal_xy": W.b.tolist(), "riser": (floor0 - stair_ground) / stair_n, "tread": stair_run,
                                "geometry_complete": porch_rejected == 0, "rejected_parts": porch_rejected}
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
        rear_u = rear_top = None
        if rear_wall is not None:
            entry_xy = np.asarray(b["rear_door"]["xyz"][:2]) - rear_wall.b * 0.20
            along = float((entry_xy - W2.p0) @ W2.a)
            if 0 <= along <= W2.L and abs(float((entry_xy - W2.p0) @ W2.b)) < 0.08:
                rear_u, rear_top = along, b["rear_door"]["head_z"]
        # Shops keep blank (or shop-glazed) ground-floor side walls: no residential sashes.
        windows_grid(P, W2, floor0, floors, fh, st, e2, ground(W2.at(W2.L / 2, 0.4)), door_u=rear_u, door_top=rear_top,
                     first_floor=1 if kit_shop else 0, min_sill=shop_top + 0.35 if shop_top is not None else None)

    # ---- chimney toward the back, near a party wall
    if st["chimney"] and b["arch"] in ("row_porch", "row", "detached", "detached_porch"):
        depth = min(8.0, max(2.0, (b["s1"] - b["s0"]) * 0.5))
        u = 0.55 if rng.random() < 0.5 else L - 0.55
        pt = W.at(u, -depth)
        if main.buffer(-0.4).contains(Point(pt)):
            z = float(roof_at(np.array([pt]))[0])
            P.box((pt[0], pt[1], z + 0.45), (0.7, 0.5, 1.3), W.a, st["wall"], r=0.05, back=True, axis="z")
            P.box((pt[0], pt[1], z + 1.15), (0.82, 0.62, 0.14), W.a, "formstone", r=0.03, back=True)


# ------------------------------------------------------------------ neighborhood shops
# Exact OSM ids (blender/city/data/pen_lucy_buildings.geojson). Row_163's one-storey pair on the
# east side of Old York Rd and the low detached store across the road become shops; ids,
# footprints and source meshes are unchanged, only their kit and archetype change.
NEIGHBORHOOD_SHOPS = {
    "w336344480": ("mini_mart", "Miss Dot's Mini Mart", "GROCERY  /  SNACKS  /  COLD DRINKS"),     # 4003 Old York Rd, Row_163
    "w336344475": ("shuttered", "Old York Variety", "HOUSEHOLD  /  HARDWARE  /  PHONE CARDS"),     # 4005 Old York Rd, Row_163
    "w336344477": ("corner_market", "Old York Corner Market", "GROCERY  /  DELI  /  LOTTERY"),   # 4009 Old York Rd, explicit user-selected third unit
    "w336346142": ("corner_market", "Lucy's Corner Market", "GROCERY  /  DELI  /  LOTTERY"),        # 4018 Old York Rd, Bldg_101
}
# Further sites are chosen from the map (low one-storey stores first, then addressed corner end
# units), spread apart and away from the existing commercial corridor.
AUTO_SHOP_NAMES = {
    "corner_market": [("Two Sisters Market", "GROCERY  /  DELI  /  LOTTERY"),
                      ("Pen Lucy Food Market", "MEAT  /  PRODUCE  /  DAIRY"),
                      ("Hillside Corner Grocery", "GROCERY  /  HOT COFFEE"),
                      ("Wilsby Corner Market", "GROCERY  /  HOT COFFEE")],
    "mini_mart": [("Ruth's Mini Mart", "SNACKS  /  SODA  /  ICE"),
                  ("Mr. Lee's Corner Store", "CANDY  /  CHIPS  /  COLD DRINKS")],
    "shuttered": [("Lucky Variety", "HOUSEHOLD  /  CLEANING  /  PHONE CARDS"),
                  ("Northwood Discount", "DOLLAR ITEMS  /  HOUSEHOLD")],
}
AUTO_SHOP_KITS = ["corner_market", "mini_mart", "shuttered", "corner_market", "mini_mart", "shuttered"]
# Civic demolitions, hospital-retained Argonne rows and the eight civic replacement businesses
# (pen_lucy_civic_build.json / pen_lucy_new_businesses.json at the time of this pass). The
# same files are also read at build time, so later civic edits are excluded automatically.
SHOP_EXCLUDED_IDS = frozenset("""
w336345679 w336346078 w336346079 w336327923 w336327925 w336328093 w336328424 w336328437 w336328712
w336328900 w336328901 w336329168 w336329696 w336329702 w336327521 w336327522 w336327523 w336327524
w336327525 w336327526 w336327527 w336327528 w336327773 w336327774 w336327775 w336327776 w336327777
w336327778 w336328479 w336328480 w336328483 w336328492 w336328496 w336328500 w336328504 w336328509
w336338569 w336339838 w336340998 w336341156 w336344621 w336349082 w336349403 w336350065
""".split())
ROUTE_STREET = "Old York Road"      # the authored walk: no raised entries on its sidewalks


def _bays(a0, a1, n, post):
    span = (a1 - a0 - post * (n - 1)) / n
    return [(a0 + i * (span + post), a0 + i * (span + post) + span) for i in range(n)]


def _grime(P, W, rng, u0, u1, z0, z1, v, n=3, mat="grime"):
    """A few thin stains laid flat on the surface at v (never off it)."""
    if u1 - u0 < 0.3 or z1 - z0 < 0.08:
        return
    for _ in range(n):
        w = float(rng.uniform(0.18, min(0.55, u1 - u0)))
        h = float(rng.uniform(0.06, min(0.32, z1 - z0)))
        u = float(rng.uniform(u0 + w / 2, max(u0 + w / 2, u1 - w / 2)))
        z = float(rng.uniform(z0, max(z0, z1 - h)))
        W.box(P, u - w / 2, u + w / 2, v, v + 0.006, z, z + h, mat)


def _glass_door(P, W, du, floor0, head, frame="shutter_grey"):
    """Aluminium shop door with push bar; a transom light when the head allows it."""
    W.box(P, du - 0.55, du + 0.55, 0.0, 0.07, floor0, head, frame)
    W.box(P, du - 0.45, du + 0.45, 0.07, 0.09, floor0 + 0.06, floor0 + 2.1, "glass")
    W.box(P, du - 0.48, du + 0.48, 0.07, 0.11, floor0 + 2.1, floor0 + 2.2, frame)
    W.box(P, du - 0.48, du + 0.48, 0.07, 0.11, floor0, floor0 + 0.12, frame)
    W.box(P, du - 0.36, du + 0.36, 0.11, 0.15, floor0 + 1.0, floor0 + 1.05, "knob")
    if head - (floor0 + 2.2) > 0.22:
        W.box(P, du - 0.45, du + 0.45, 0.07, 0.09, floor0 + 2.24, head - 0.05, "glass")


def _shop_glazing(P, W, a0, a1, base_z, floor0, head, knee="concrete"):
    """Knee wall, aluminium frame, display glass and mullions between a0 and a1."""
    W.box(P, a0 - 0.04, a1 + 0.04, 0.0, 0.1, base_z, floor0 + 0.5, knee)
    W.box(P, a0 - 0.04, a1 + 0.04, 0.0, 0.06, floor0 + 0.5, head, "shutter_grey")
    W.box(P, a0 + 0.03, a1 - 0.03, 0.06, 0.08, floor0 + 0.56, head - 0.06, "glass")
    for u in np.linspace(a0, a1, max(2, int((a1 - a0) / 1.4) + 1))[1:-1]:
        W.box(P, u - 0.03, u + 0.03, 0.06, 0.1, floor0 + 0.56, head - 0.06, "shutter_grey")


def neighborhood_shop(P, W, b, floor0, g, eave, floors, st, ground):
    """Ground-floor shop bays on the selected front wall; returns the top of the sign band.

    mini_mart: green-clad front, full-width yellow frame round three bays (roll shutters, one
      half raised over display glass, one rolled up over the glass door) and a worn signboard.
    shuttered: brick front, one continuous pale signboard, barred plywood windows, steel door.
    corner_market: worn white fascia wrapping onto the street-side wall, display glass, and a
      raised concrete entry with steps, a ramp along the facade and metal rails when it fits.
    On a low roof the sign band rises past the eave as a parapet with a solid back-up wall.
    """
    biz, L = b["business"], W.L
    kit, corner_end = biz["kit"], biz.get("corner_end")
    rng = seeded(b["id"] + ":neighborhood-shop")
    if corner_end == "end":
        door_pref = L - 0.95
    elif corner_end == "start":
        door_pref = 0.95
    else:
        door_pref = min(0.95, L / 2) if b.get("door_left", True) else max(L - 0.95, L / 2)
    if kit == "corner_market":
        head = floor0 + float(np.clip(eave - floor0 - 0.5, 2.32, 2.6))
    else:
        head = floor0 + 2.6                  # room for a rolled shutter coil over a 2.2 m door
    top = head + 0.74 if floors > 1 else max(head + 0.74, eave + 0.32)
    previous_section, P.section = P.section, "neighborhood_shop"
    parapet = top > eave + 0.05
    if parapet:
        W.box(P, 0.0, L, -0.22, 0.0, eave - 0.06, top, st["wall"], back=True)
        W.box(P, -0.02, L + 0.02, -0.26, 0.0, top, top + 0.06, "concrete", r=0.02, back=True)
    text = "#f3e6c4"

    if kit == "mini_mart":
        post = 0.18
        W.box(P, 0.0, L, 0.0, 0.03, g - 0.25, top, "shop_green", back=True)             # green cladding
        a0, a1 = 0.1 + post, L - 0.1 - post
        nb = 3 if a1 - a0 >= 3.4 else 2
        bays = _bays(a0, a1, nb, post)
        door_bay = min(range(nb), key=lambda i: abs((bays[i][0] + bays[i][1]) / 2 - door_pref))
        du = (bays[door_bay][0] + bays[door_bay][1]) / 2
        open_bay = (door_bay + 1) % nb if nb == 3 else None
        for p0 in [0.1] + [bays[i][1] for i in range(nb - 1)] + [a1]:                 # yellow frame posts
            W.box(P, p0, p0 + post, 0.03, 0.17, floor0 - 0.12, top, "shop_yellow", r=0.02, axis="z")
        W.box(P, 0.1, L - 0.1, 0.03, 0.17, head, head + 0.16, "shop_yellow", r=0.02)
        W.box(P, 0.1, L - 0.1, 0.03, 0.17, top - 0.14, top, "shop_yellow", r=0.02, back=True)
        W.box(P, a0, a1, 0.03, 0.1, head + 0.16, top - 0.14, "shop_green")              # recessed signboard
        hb = head - 0.3                                                                 # shutter coil underside
        for i, (u0, u1) in enumerate(bays):
            W.box(P, u0, u1, 0.03, 0.25, hb, head, "shutter_grey", r=0.03)
            if i == door_bay:
                W.box(P, u0, u1, 0.0, 0.07, floor0, hb, "shutter_grey")
                _glass_door(P, W, du, floor0, hb)
                for s0, s1 in ((u0 + 0.06, du - 0.6), (du + 0.6, u1 - 0.06)):
                    if s1 - s0 >= 0.22:
                        W.box(P, s0, s1, 0.07, 0.09, floor0 + 0.5, hb - 0.06, "glass")
                continue
            cb = floor0 + 1.3 if i == open_bay else floor0 + 0.02                       # curtain bottom
            W.box(P, u0, u0 + 0.05, 0.03, 0.11, floor0, hb, "shutter_dark")              # guide rails
            W.box(P, u1 - 0.05, u1, 0.03, 0.11, floor0, hb, "shutter_dark")
            W.box(P, u0 + 0.05, u1 - 0.05, 0.05, 0.085, cb, hb, "shutter_grey")
            for z in np.arange(cb + 0.2, hb - 0.08, 0.22):
                W.box(P, u0 + 0.05, u1 - 0.05, 0.085, 0.095, z, z + 0.025, "shutter_dark")
            W.box(P, u0 + 0.05, u1 - 0.05, 0.05, 0.11, cb, cb + 0.07, "shutter_dark")
            if i == open_bay:
                W.box(P, u0 + 0.05, u1 - 0.05, 0.03, 0.08, floor0 - 0.1, floor0 + 0.45, "shop_green")
                W.box(P, u0 + 0.05, u1 - 0.05, 0.03, 0.06, floor0 + 0.45, cb, "shutter_grey")
                W.box(P, u0 + 0.1, u1 - 0.1, 0.06, 0.08, floor0 + 0.5, cb - 0.02, "glass")
            else:
                um = (u0 + u1) / 2
                W.box(P, um - 0.05, um + 0.05, 0.085, 0.12, cb + 0.1, cb + 0.2, "shutter_dark")  # padlock hasp
        _grime(P, W, rng, a0, a1, head + 0.18, top - 0.16, 0.1, 3)
        _grime(P, W, rng, 0.2, L - 0.2, head + 0.01, head + 0.15, 0.17, 2)
        _grime(P, W, rng, 0.2, L - 0.2, top - 0.13, top - 0.01, 0.17, 1, "fascia_worn")
        sign_v, sign_z, sign_w = 0.11, (head + top + 0.02) / 2, a1 - a0 - 0.2

    elif kit == "shuttered":
        W.box(P, 0.0, L, 0.0, 0.15, head, head + 0.1, "shutter_dark")                   # steel lintel
        W.box(P, 0.04, L - 0.04, 0.0, 0.12, head + 0.1, top - 0.07, "sign_pale", r=0.02, back=True)
        W.box(P, 0.0, L, 0.0, 0.15, top - 0.07, top, "shutter_dark", back=True)          # flashing cap
        du = float(np.clip(door_pref, 0.75, L - 0.75))
        hb = head - 0.28
        W.box(P, du - 0.58, du + 0.58, 0.0, 0.06, floor0, hb, "shutter_dark")              # door frame
        W.box(P, du - 0.47, du + 0.47, 0.06, 0.1, floor0 + 0.02, floor0 + 2.15, "shutter_grey")
        for z in (floor0 + 0.45, floor0 + 1.1, floor0 + 1.75):
            W.box(P, du - 0.43, du + 0.43, 0.1, 0.11, z, z + 0.04, "shutter_dark")
        W.box(P, du + 0.25, du + 0.33, 0.1, 0.15, floor0 + 1.0, floor0 + 1.1, "knob")
        if hb - (floor0 + 2.2) > 0.12:
            W.box(P, du - 0.47, du + 0.47, 0.06, 0.09, floor0 + 2.2, hb - 0.03, "plywood")
        W.box(P, du - 0.6, du + 0.6, 0.0, 0.22, hb, head, "shutter_grey", r=0.03)          # rolled grille coil
        for a0, a1 in ((0.32, du - 0.78), (du + 0.78, L - 0.32)):
            if a1 - a0 < 0.8:
                continue
            W.box(P, a0 - 0.1, a1 + 0.1, 0.0, 0.15, floor0 + 0.36, floor0 + 0.46, "concrete", r=0.02)
            W.box(P, a0 - 0.07, a0, 0.0, 0.09, floor0 + 0.46, hb, "shutter_dark")
            W.box(P, a1, a1 + 0.07, 0.0, 0.09, floor0 + 0.46, hb, "shutter_dark")
            W.box(P, a0, a1, 0.0, 0.04, floor0 + 0.46, hb, "plywood")
            sheets = max(1, int(np.ceil((a1 - a0) / 1.22)))
            for k in range(1, sheets):
                u = a0 + k * (a1 - a0) / sheets
                W.box(P, u - 0.012, u + 0.012, 0.04, 0.046, floor0 + 0.46, hb, "grime")
            _grime(P, W, rng, a0, a1, floor0 + 0.5, hb - 0.05, 0.04, 2, "fascia_worn")
            W.box(P, a0 - 0.1, a1 + 0.1, 0.0, 0.22, hb, head, "shutter_grey", r=0.03)
            nbar = max(3, int((a1 - a0) / 0.13))
            for k in range(nbar):
                u = a0 + (k + 0.5) * (a1 - a0) / nbar
                W.box(P, u - 0.014, u + 0.014, 0.06, 0.088, floor0 + 0.5, hb - 0.04, "bars_dark")
            for z in (floor0 + 0.52, (floor0 + hb) / 2, hb - 0.1):
                W.box(P, a0 - 0.07, a1 + 0.07, 0.05, 0.1, z, z + 0.045, "bars_dark")
        _grime(P, W, rng, 0.2, L - 0.2, head + 0.12, top - 0.09, 0.12, 4)
        sign_v, sign_z, sign_w, text = 0.13, (head + 0.1 + top - 0.07) / 2, L - 0.4, "#2b2722"

    else:                                                                                  # corner_market
        du = float(np.clip(door_pref, 0.75, L - 0.75))
        f0 = head + 0.04
        e0 = -0.16 if corner_end == "start" else 0.0
        e1 = L + 0.16 if corner_end == "end" else L
        W.box(P, e0, e1, 0.0, 0.16, f0, top, "fascia_white", r=0.02, back=True)
        W.box(P, e0, e1, 0.0, 0.19, f0 - 0.07, f0, "shutter_dark")                        # drip edge
        W.box(P, e0 - 0.02, e1 + 0.02, 0.0, 0.2, top, top + 0.05, "concrete", back=True)   # coping
        for a0, a1 in ((0.22, du - 0.62), (du + 0.62, L - 0.22)):
            if a1 - a0 >= 0.5:
                _shop_glazing(P, W, a0, a1, g - 0.2, floor0, f0 - 0.07)
        W.box(P, du - 0.6, du + 0.6, 0.0, 0.07, floor0, f0 - 0.07, "shutter_grey")
        _glass_door(P, W, du, floor0, f0 - 0.07)
        _grime(P, W, rng, e0 + 0.2, e1 - 0.2, f0 + 0.02, top - 0.04, 0.16, 3)
        _grime(P, W, rng, e0 + 0.2, e1 - 0.2, f0 + 0.02, top - 0.04, 0.16, 2, "fascia_worn")
        if biz.get("corner_edge"):
            S = Wall(*biz["corner_edge"])
            span = min(S.L - 0.25, 7.5)
            s0, s1 = (0.0, span) if corner_end == "end" else (S.L - span, S.L)
            S.box(P, s0, s1, 0.0, 0.16, f0, top, "fascia_white", r=0.02, back=True)
            S.box(P, s0, s1, 0.0, 0.19, f0 - 0.07, f0, "shutter_dark")
            S.box(P, s0, s1, 0.0, 0.2, top, top + 0.05, "concrete", back=True)
            side_eave = float(b["roof_at"](np.array([S.at(s0 + 0.05), S.at(s1 - 0.05)])).min())
            if top > side_eave + 0.05:
                S.box(P, s0, s1, -0.22, 0.0, side_eave - 0.06, top, st["wall"], back=True)
            g_side = ground(S.at((s0 + s1) / 2, 0.4))
            w0, w1 = (s0 + 0.45, s1 - 0.35) if corner_end == "end" else (s0 + 0.35, s1 - 0.45)
            if w1 - w0 >= 0.8 and floor0 + 0.5 >= g_side + 0.25:
                _shop_glazing(P, S, w0, w1, min(g_side, floor0) - 0.2, floor0, f0 - 0.07)
            _grime(P, S, rng, s0 + 0.2, s1 - 0.2, f0 + 0.02, top - 0.04, 0.16, 2)
            biz["corner_fascia_m"] = round(span, 3)
        entry = "flush"
        if floor0 - g > 0.2:
            entry = _raised_entry(P, W, b, du, floor0, g, corner_end, ground)
        biz["entry"] = entry
        sign_v, sign_z, sign_w, text = 0.17, (f0 + top) / 2, L - 0.5, "#2b2722"

    biz.update(door_u=du, sign_xyz=[*W.at(L / 2, sign_v), sign_z], sign_width=round(sign_w, 3),
               door_xyz=[*W.at(du, 0.35), floor0], normal_xy=W.b.tolist(), storeys=floors,
               sign_text_color=text, parapet=parapet)
    biz.setdefault("entry", "flush")
    P.section = previous_section
    return top


def _raised_entry(P, W, b, du, floor0, g, corner_end, ground):
    """Concrete landing at floor level, steps straight out from the door, a ramp along the
    facade (when it fits at 1:5 or gentler) and metal guard rails on every open drop."""
    L, depth = W.L, 1.45
    pw0, pw1 = max(0.05, du - 0.95), min(L - 0.05, du + 0.95)
    P.section = "shop_entry"
    before = P.rejected_sections.get("shop_entry", 0)
    W.box(P, pw0, pw1, 0.0, depth, g - 0.3, floor0, "concrete", r=0.02)
    g_step = ground(W.at(du, depth + 0.45))
    steps(P, W, du, floor0, min(g_step, floor0 - 0.1), depth, "concrete", width=1.3, max_run=0.6)
    toward_start = corner_end == "end" or (corner_end is None and du > L / 2)
    start = pw0 if toward_start else pw1
    room = (start - 0.1) if toward_start else (L - 0.1 - start)
    far = start + (-1.0 if toward_start else 1.0) * min(room, 3.2)
    run = abs(far - start)
    g_far = ground(W.at(far, depth / 2))
    ramp = run >= 2.0 and 0.1 < floor0 - g_far <= run / 5
    rail = "bars_dark"
    if ramp:
        P.solid([W.pt(start, 0.02, g - 0.3), W.pt(far, 0.02, g_far - 0.3), W.pt(far, depth, g_far - 0.3), W.pt(start, depth, g - 0.3),
                 W.pt(start, 0.02, floor0), W.pt(far, 0.02, g_far + 0.02), W.pt(far, depth, g_far + 0.02), W.pt(start, depth, floor0)],
                "concrete")
        for t in (0.0, 0.5, 1.0):
            u = start + (far - start) * t
            zb = floor0 + (g_far + 0.02 - floor0) * t
            W.box(P, u - 0.03, u + 0.03, depth - 0.07, depth - 0.01, zb, zb + 0.95, rail, axis="z")
        P.solid([W.pt(start, depth - 0.065, floor0 + 0.88), W.pt(far, depth - 0.065, g_far + 0.9),
                 W.pt(far, depth - 0.015, g_far + 0.9), W.pt(start, depth - 0.015, floor0 + 0.88),
                 W.pt(start, depth - 0.065, floor0 + 0.93), W.pt(far, depth - 0.065, g_far + 0.95),
                 W.pt(far, depth - 0.015, g_far + 0.95), W.pt(start, depth - 0.015, floor0 + 0.93)], rail)
    for a0, a1 in ((pw0, du - 0.72), (du + 0.72, pw1)):                                    # front guard, open at the steps
        if a1 - a0 < 0.15:
            continue
        W.box(P, a0, a1, depth - 0.065, depth - 0.015, floor0 + 0.88, floor0 + 0.93, rail)
        for u in (a0 + 0.03, a1 - 0.03):
            W.box(P, u - 0.03, u + 0.03, depth - 0.07, depth - 0.01, floor0, floor0 + 0.93, rail, axis="z")
    for end in ((pw1,) if toward_start else (pw0,)) if ramp else (pw0, pw1):              # closed platform ends
        e0 = end - 0.06 if end == pw1 else end
        W.box(P, e0, e0 + 0.05, 0.05, depth - 0.07, floor0 + 0.88, floor0 + 0.93, rail)
        W.box(P, e0, e0 + 0.05, 0.05, 0.11, floor0, floor0 + 0.93, rail, axis="z")
    P.section = "neighborhood_shop"
    if P.rejected_sections.get("shop_entry", 0) > before:
        b["business"]["entry_rejected_parts"] = P.rejected_sections["shop_entry"] - before
    return "raised_ramp" if ramp else "raised_steps"


def _height(height, xy):
    return float(np.asarray(height(np.array([xy[0]]), np.array([xy[1]]))).ravel()[0])


def _shop_site(b, roads, height, exposed, min_gap=1.6, max_gap=16.0):
    """Front wall, street gap, eave and (optional) street-side corner wall for a shop, or a reason."""
    main = _main_poly(b)
    if main is None or b.get("n") is None:
        return None, "no_front_axis"
    n, c = np.asarray(b["n"], float), np.array(main.centroid.coords[0])
    walls = [Wall(p0, p1) for p0, p1 in _edges(main)]
    faces = [w for w in walls if w.L >= 3.6 and float(w.b @ n) > 0.85]
    if not faces:
        return None, "no_front_wall"
    w = max(faces, key=lambda v: (round(float((v.at(v.L / 2) - c) @ n), 1), v.L))
    if w.L > 16.0:
        return None, "front_too_wide"
    if not all(exposed(w.at(u, d)) for u in (0.5, w.L / 2, w.L - 0.5) for d in (0.6, 1.6)):
        return None, "front_obstructed"
    mid = Point(w.at(w.L / 2))
    gap, street = min((line.distance(mid) - width / 2, name) for line, width, _, name in roads)
    if not min_gap <= gap <= max_gap:
        return None, "street_distance"
    g = _height(height, w.at(w.L / 2, 0.4))
    eave = float(b["roof_at"](np.array([w.at(0.05), w.at(w.L - 0.05)])).min())
    if eave - g < 2.75:
        return None, "too_low"
    corner = None
    for s in walls:
        if s is w or s.L < 3.0 or abs(float(s.b @ n)) > 0.4:
            continue
        if np.linalg.norm(s.p0 - w.at(w.L)) < 0.05:
            end = "end"
        elif np.linalg.norm(s.at(s.L) - w.p0) < 0.05:
            end = "start"
        else:
            continue
        if not all(exposed(s.at(u, 0.8)) for u in (0.5, s.L / 2, s.L - 0.5)):
            continue
        side_gap = min(line.distance(Point(s.at(s.L / 2))) - width / 2 for line, width, _, _ in roads)
        if side_gap <= 16.0:
            corner = {"edge": [s.p0.tolist(), s.at(s.L).tolist()], "end": end, "street_gap_m": round(float(side_gap), 3)}
            break
    return {"wall": w, "gap": float(gap), "street": street, "ground": g, "eave": eave, "rise": eave - g,
            "low": eave - g < 4.9, "corner": corner, "center": np.array(b["poly"].centroid.coords[0])}, None


def _protected(data_dir):
    """Ids and footprints owned by the civic district and its replacement businesses."""
    ids, polys = set(SHOP_EXCLUDED_IDS), []
    def ring(points):
        if points and len(points) >= 3:
            polys.append(Polygon([(float(p[0]), -float(p[-1])) for p in points]).buffer(0))
    path = os.path.join(data_dir or "", "pen_lucy_civic_build.json")
    if data_dir and os.path.exists(path):
        civic = json.load(open(path, encoding="utf-8"))
        ids.update(civic.get("global_preserve_ids", []))
        for site in civic.get("sites", []):
            ids.update(site.get("demolition_ids", []))
            ids.update(site.get("preserve_ids", []))
            ring(site.get("footprint_xz"))
    path = os.path.join(data_dir or "", "pen_lucy_new_businesses.json")
    if data_dir and os.path.exists(path):
        for entry in json.load(open(path, encoding="utf-8")).get("businesses", []):
            ids.update(entry.get("building_ids", []))
            ring(entry.get("polygon"))
    return ids, (shapely.union_all(polys) if polys else None)


def _make_shop(b, site, kit, name, subtitle, auto):
    raised = kit == "corner_market" and site["gap"] >= 3.4 and site["rise"] >= 3.0 and site["street"] != ROUTE_STREET
    corner = site["corner"] if kit == "corner_market" else None
    b["arch"] = "storefront"
    b["business"] = {"name": name, "type": "variety" if kit == "shuttered" else "market", "subtitle": subtitle,
                     "front_edge": [site["wall"].p0.tolist(), site["wall"].at(site["wall"].L).tolist()],
                     "kit": kit, "floor_rise": 0.36 if raised else 0.15, "neighborhood": True,
                     "corner_edge": corner["edge"] if corner else None, "corner_end": corner["end"] if corner else None}
    st = b["style"]
    if kit == "shuttered" and not st["wall"].startswith("brick"):
        st["wall"] = "brick_2"
    elif kit == "corner_market" and not (st["wall"].startswith("brick") or st["wall"] in ("formstone", "formstone_tan", "painted")):
        st["wall"] = "painted"                         # siding detached stores get a painted masonry shell
    st.update(trim="trim_white", door="door_black", awnings=None)
    return {"building_id": b["id"], "kit": kit, "name": name, "street": site["street"], "auto": auto,
            "street_gap_m": round(site["gap"], 3), "eave_above_ground_m": round(site["rise"], 3),
            "one_storey": bool(site["low"]), "corner_wrap": corner is not None, "raised_entry": raised,
            "game_xz": [round(float(site["center"][0]), 2), round(-float(site["center"][1]), 2)]}


def assign_neighborhood_shops(buildings, roads, height, exposed, data_dir=None, max_auto=6):
    """Turn the named low Old York shops and a spread of corner sites into neighborhood shops.

    Runs after street_geometry.assign_businesses. Never touches existing businesses, civic
    demolitions, hospital-retained homes, replacement-business sites or Rose Hill Terrace.
    Building ids, footprints and source meshes are preserved; only arch/style/business change.
    """
    excluded, protected = _protected(data_dir)
    audit = {"forced": [], "auto": [], "rejected": []}
    shop_pts = []
    biz_pts = [np.array(b["poly"].centroid.coords[0]) for b in buildings if b.get("business")]
    by_id = {b["id"]: b for b in buildings}
    for bid, (kit, name, subtitle) in NEIGHBORHOOD_SHOPS.items():
        b = by_id.get(bid)
        # The third pictured Old York unit is explicitly authorized despite its
        # source church tag. Every other civic building keeps the exclusion.
        if b is None or b.get("business") or bid in excluded or b["arch"] == "garage" or (b["arch"] == "civic" and bid != "w336344477") or b["porch"] > 0.01:
            audit["rejected"].append({"building_id": bid, "reason": "missing_or_reserved"})
            continue
        site, why = _shop_site(b, roads, height, exposed, min_gap=1.0, max_gap=30.0)
        if site is None:
            audit["rejected"].append({"building_id": bid, "reason": why})
            continue
        audit["forced"].append(_make_shop(b, site, kit, name, subtitle, False))
        shop_pts.append(site["center"])
    candidates = []
    for b in sorted(buildings, key=lambda v: v["id"]):
        if b["id"] in NEIGHBORHOOD_SHOPS or b["id"] in excluded or b.get("business"):
            continue
        if b.get("zone") != "core" or b["arch"] not in ("row", "detached") or b["porch"] > 0.01 or b["poly"].area < 45:
            continue
        if b.get("tags", {}).get("addr:street") == "Rose Hill Terrace":
            continue
        if protected is not None and b["poly"].distance(protected) < 12.0:
            continue
        site, why = _shop_site(b, roads, height, exposed)
        if site is None:
            continue
        addressed = bool(b.get("tags", {}).get("addr:housenumber"))
        if site["low"]:
            if not addressed and (b["poly"].area < 60 or site["wall"].L < 5.0 or site["gap"] > 8.0):
                continue
        elif not (addressed and site["corner"]):
            continue
        candidates.append((b, site))
    used = {k: 0 for k in AUTO_SHOP_NAMES}
    while len(audit["auto"]) < max_auto:
        best = None
        for b, site in candidates:
            if b.get("business"):
                continue
            d_shop = min((float(np.linalg.norm(site["center"] - q)) for q in shop_pts), default=1e9)
            d_biz = min((float(np.linalg.norm(site["center"] - q)) for q in biz_pts), default=1e9)
            if d_shop < 85.0 or d_biz < 40.0:
                continue
            key = (site["low"], min(d_shop, 2.0 * d_biz))      # low stores first, then the widest spread
            if best is None or key > best[0]:
                best = (key, b, site)
        if best is None:
            break
        _, b, site = best
        kit = AUTO_SHOP_KITS[len(audit["auto"]) % len(AUTO_SHOP_KITS)]
        if kit != "corner_market" and site["corner"] and not site["low"] and used["corner_market"] < len(AUTO_SHOP_NAMES["corner_market"]):
            kit = "corner_market"
        name, subtitle = AUTO_SHOP_NAMES[kit][used[kit] % len(AUTO_SHOP_NAMES[kit])]
        used[kit] += 1
        audit["auto"].append(_make_shop(b, site, kit, name, subtitle, True))
        shop_pts.append(site["center"])
    audit.update(candidates=len(candidates), selected=len(audit["forced"]) + len(audit["auto"]),
                 excluded_ids=len(excluded), rule="Named low Old York stores, then low one-storey stores and addressed "
                 "street-corner end units; >=85 m apart, >=40 m from existing businesses, >=12 m from civic sites")
    return audit
