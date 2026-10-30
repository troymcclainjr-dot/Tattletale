"""Turn the raw downloads into game-space geometry for blender/assets/pen_lucy.py (the massing pass).

    .work/city/venv/Scripts/python.exe blender/city/process.py

Writes
- .work/city/build/pen_lucy_geom.json     every mesh, in Blender coords, ready to build
- .work/city/build/pen_lucy_report.json   numbers for checking the run
- blender/city/data/pen_lucy_buildings.geojson   one record per site building, for the detail passes
- blender/city/data/pen_lucy_area.geojson        the playable area polygon

Heights: OSM has the footprints but no heights, so every building takes its heights from the
USGS LiDAR points inside its footprint. Houses are profiled front to back (front = the end of the
footprint's long axis nearest a street), which finds the main roof (a plane, usually sloping to the
rear), a lower front porch and a lower rear addition.

Coordinates: local meters east/north of the Old York Rd / Wyanoke Ave intersection, which is the
game origin. Blender coords are (east, north, elevation - origin elevation), so the glTF lands in
Godot as x east, y up, z south.
"""
import glob, json, math, os, sys, time

import laspy
import numpy as np
import shapely
from pyproj import CRS, Transformer
from scipy import ndimage
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, Polygon, mapping
from shapely.geometry.polygon import orient
from shapely.ops import polygonize, unary_union, nearest_points

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config as C
import kits
import runtime
import vegetation
import street_geometry

T0 = time.time()


def log(*a):
    print(f"[process {time.time() - T0:5.0f}s]", *a, flush=True)


# ------------------------------------------------------------------ tuning
CARRIAGEWAY = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
               "living_street", "road", "motorway_link", "trunk_link", "primary_link", "secondary_link",
               "tertiary_link"}
ROAD_W = {"primary": 15.0, "secondary": 13.0, "tertiary": 11.0, "residential": 9.5, "unclassified": 8.0,
          "living_street": 7.0, "road": 8.0}          # curb to curb, m (links: 7)
SIDEWALK_W = {"primary": 3.2, "secondary": 3.0, "tertiary": 2.6}   # others 2.4
SERVICE_W = {"alley": 4.0, "driveway": 3.0, "parking_aisle": 6.0}  # other service roads 4.5
PATHS = {"footway", "path", "pedestrian", "steps", "cycleway"}
LIFT = {"road": 0.0, "lot": 0.01, "alley": 0.02, "grass": 0.10, "sidewalk": 0.15}  # tops above LiDAR ground
SKIRT = 0.08            # raised zones get an outward skirt down to ground - SKIRT (this is also the curb)
DICE, CONTEXT_DICE = 4.0, 12.0   # ground meshes are diced into cells so they follow the terrain
GROUND, NOISE, VEG = 2, {7, 18}, {3, 4, 5}

# material id -> (kind, hex, roughness). Hexes come from the claykit palette where one exists.
MATS = {
    "asphalt": ("clay", "#3a3a40", 0.95), "sidewalk": ("clay", "#a8a49a", 0.86), "curb": ("clay", "#c8c4b8", 0.86),
    "alley": ("clay", "#8a8a90", 0.9), "grass": ("clay", "#6a8a3a", 0.95), "dirt": ("clay", "#6e5a3c", 0.95),
    "context_ground": ("clay", "#7d7a70", 0.95), "brick": ("clay", "#9a5a44", 0.9), "siding": ("clay", "#c8b89a", 0.86),
    "stone": ("clay", "#b0a890", 0.9), "roof": ("clay", "#5a5a62", 0.9), "porch_roof": ("clay", "#6a5846", 0.86),
    "context_bldg": ("clay", "#9a9aa0", 0.9), "bark": ("clay", "#5a3a24", 0.9), "leaves": ("clay", "#5f7d36", 0.95),
    "siding_white": ("clay", "#e6e2d6", 0.86), "siding_gray": ("clay", "#a8aca8", 0.86),
    "siding_yellow": ("clay", "#d8c890", 0.86), "siding_green": ("clay", "#9aa88a", 0.86),
}
MATS.update(kits.KIT_MATS)
MATS.update(vegetation.MATERIALS)
SIDINGS = ["siding", "siding_white", "siding_gray", "siding_yellow", "siding_green"]
CIVIC = {"church", "chapel", "cathedral", "school", "kindergarten", "commercial", "retail", "civic", "public",
         "office", "industrial", "warehouse"}
MAT_ID = {k: i for i, k in enumerate(MATS)}
MAT_NAMES = list(MATS)
ZONE_MAT = {"road": "asphalt", "lot": "asphalt", "alley": "alley", "grass": "grass", "sidewalk": "sidewalk"}
SKIRT_MAT = {"lot": "asphalt", "alley": "alley", "grass": "dirt", "sidewalk": "curb"}


# ------------------------------------------------------------------ OSM
def way_ll(e):
    return [(p["lon"], p["lat"]) for p in e["geometry"]]


def highway_lines(els, name):
    return [LineString(way_ll(e)) for e in els if e["type"] == "way" and "highway" in e.get("tags", {})
            and e["tags"].get("name") == name and len(e.get("geometry", [])) > 1]


def street_pts(els, name):
    return [(p["lon"], p["lat"]) for e in els if e["type"] == "way" and "highway" in e.get("tags", {})
            and e["tags"].get("name") == name for p in e["geometry"]]


def area_ring(els):
    north = sorted({p for p in street_pts(els, C.NORTH) if p[0] >= C.WEST_LON}, key=lambda p: p[0])
    east = sorted({p for p in street_pts(els, C.EAST) if p[0] <= C.ARGONNE_MAX_LON and p[1] <= C.ARGONNE_MAX_LAT},
                  key=lambda p: -p[1])
    south = sorted({p for p in street_pts(els, C.SOUTH) if p[0] >= C.WEST_LON}, key=lambda p: -p[0])
    if not (north and east and south):
        raise SystemExit("[process] a boundary street is missing from osm.json")
    return north + east + south


def origin_ll(els, fallback):
    a = unary_union(highway_lines(els, C.ORIGIN_STREETS[0]))
    b = unary_union(highway_lines(els, C.ORIGIN_STREETS[1]))
    hit = a.intersection(b)
    pts = [g for g in getattr(hit, "geoms", [hit]) if g.geom_type == "Point"]
    if not pts:
        log("WARNING: origin streets don't meet; using the area centroid")
        return fallback
    return min(pts, key=lambda p: p.distance(Point(fallback))).coords[0]


def building_shapes(els):
    for e in els:
        t = e.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "construction"):
            continue
        if e["type"] == "way":
            g = way_ll(e)
            if len(g) < 4:
                continue
            ll = Polygon(g)
        elif e["type"] == "relation":
            ring = lambda role: [LineString([(p["lon"], p["lat"]) for p in m["geometry"]])
                                 for m in e.get("members", []) if m.get("role") == role and m.get("geometry")]
            outer = list(polygonize(ring("outer")))
            if not outer:
                continue
            ll = unary_union(outer)
            inner = list(polygonize(ring("inner")))
            if inner:
                ll = ll.difference(unary_union(inner))
        else:
            continue
        if not ll.is_valid:
            ll = ll.buffer(0)
        if ll.geom_type == "MultiPolygon":
            ll = max(ll.geoms, key=lambda g: g.area)
        if ll.geom_type == "Polygon" and not ll.is_empty:
            yield f"{e['type'][0]}{e['id']}", t, ll


def levels(t):
    try:
        return float(t.get("building:levels", "").split(";")[0])
    except ValueError:
        return None


# ------------------------------------------------------------------ meshes
class MB:
    """Collects triangles (k, 3, 3) in local meters + absolute elevation, with a material per triangle."""

    def __init__(s, name, smooth=False, props=None):
        s.name, s.smooth, s.props, s.tris, s.mats, s.smooths = name, smooth, props or {}, [], [], []

    def add(s, tri, mat, smooth=None):
        """smooth: shade these triangles smooth (None = the object's default). Kit parts are smooth,
        so their chamfers read as soft clay; walls and roofs stay flat."""
        tri = np.asarray(tri, np.float64)
        if len(tri):
            s.tris.append(tri)
            s.mats.append(np.full(len(tri), MAT_ID[mat], np.int32))
            s.smooths.append(np.full(len(tri), s.smooth if smooth is None else smooth, bool))

    def quads(s, p, q, bp, bq, tp, tq, mat):
        """Vertical quads p->q from bottom b to top t; they face the right side of p->q."""
        v0, v1 = np.column_stack([p, bp]), np.column_stack([q, bq])
        v2, v3 = np.column_stack([q, tq]), np.column_stack([p, tp])
        s.add(np.concatenate([np.stack([v0, v1, v2], 1), np.stack([v0, v2, v3], 1)]), mat)

    def tri_count(s):
        return sum(len(t) for t in s.tris)

    def build(s, y0):
        T = np.concatenate(s.tris)
        M = np.concatenate(s.mats)
        S = np.concatenate(s.smooths)
        V = T.reshape(-1, 3).copy()
        V[:, 2] -= y0
        # smooth and flat triangles never share a vertex, so a soft part can't round off a wall corner
        precision = 6 if s.name in ("Ground", "Curbs", "Ground_Context") else 3
        key = np.column_stack([np.round(V, precision), np.repeat(S, 3)])
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        F = inv.reshape(-1)[:len(V)].reshape(-1, 3)
        ok = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
        F, M, S = F[ok], M[ok], S[ok]
        used = sorted(set(M.tolist()))
        local = np.searchsorted(np.array(used), M)
        out = {"name": s.name, "smooth": s.smooth, "props": s.props,
               "verts": np.round(uniq[:, :3], precision).ravel().tolist(), "faces": F.ravel().tolist(),
               "mats": local.tolist(), "matnames": [MAT_NAMES[i] for i in used]}
        if S.any() and not S.all():
            out["smooth_faces"] = S.astype(int).tolist()
        else:
            out["smooth"] = bool(S.all())
        return out


def ccw(tri):
    """Flip (k, 3, 2+) triangles so they wind counter-clockwise seen from above."""
    a = (tri[:, 1, 0] - tri[:, 0, 0]) * (tri[:, 2, 1] - tri[:, 0, 1]) - (tri[:, 2, 0] - tri[:, 0, 0]) * (tri[:, 1, 1] - tri[:, 0, 1])
    tri[a < 0] = tri[a < 0][:, ::-1]
    return tri[np.abs(a) > 1e-7]


def triangulate(polys):
    """Constrained Delaunay triangles (k, 3, 2) for an iterable of polygonal geometries."""
    parts = shapely.get_parts(np.asarray(list(polys), dtype=object))
    parts = parts[shapely.get_type_id(parts) == 3]
    if not len(parts):
        return np.zeros((0, 3, 2))
    bad = ~shapely.is_valid(parts)
    if bad.any():
        fixed = shapely.get_parts(shapely.make_valid(parts[bad]))
        parts = np.concatenate([parts[~bad], fixed[shapely.get_type_id(fixed) == 3]])
    parts = parts[shapely.area(parts) > 1e-4]
    tris = shapely.get_parts(shapely.constrained_delaunay_triangles(parts))
    tris = tris[shapely.get_type_id(tris) == 3]
    return ccw(shapely.get_coordinates(tris).reshape(-1, 4, 2)[:, :3].copy())


def dice(geom, cell):
    """Split a polygonal geometry into grid cells: (lower-left corners of full cells, partial pieces)."""
    full, part = [], []
    if geom.is_empty:
        return np.zeros((0, 2)), part
    minx, miny, maxx, maxy = geom.bounds
    x0, y0 = math.floor(minx / cell) * cell, math.floor(miny / cell) * cell
    n = max(maxx - x0, maxy - y0) / cell
    size = cell * 2 ** max(0, math.ceil(math.log2(max(n, 1.0))))
    stack = [(geom, x0, y0, size)]
    while stack:
        g, qx, qy, sz = stack.pop()
        if g.is_empty or g.area < 1e-6:
            continue
        if abs(g.area - sz * sz) < 1e-6 * sz * sz:
            k = int(round(sz / cell))
            gx, gy = np.meshgrid(qx + np.arange(k) * cell, qy + np.arange(k) * cell)
            full.append(np.column_stack([gx.ravel(), gy.ravel()]))
            continue
        if sz <= cell * 1.0001:
            part.append(g)
            continue
        h = sz / 2
        for ox, oy in ((0, 0), (h, 0), (0, h), (h, h)):
            r = (qx + ox, qy + oy, qx + ox + h, qy + oy + h)
            try:
                sub = shapely.clip_by_rect(g, *r)
            except shapely.errors.GEOSException:     # clip_by_rect can't take the odd degenerate ring
                sub = shapely.make_valid(g).intersection(shapely.box(*r))
            stack.append((sub, qx + ox, qy + oy, h))
    return (np.concatenate(full) if full else np.zeros((0, 2))), part


def ground_tris(geom, cell, field_aligned=False):
    corners, part = dice(geom, cell)
    x, y = corners[:, 0], corners[:, 1]
    v0, v1 = np.column_stack([x, y]), np.column_stack([x + cell, y])
    v2, v3 = np.column_stack([x + cell, y + cell]), np.column_stack([x, y + cell])
    sq = np.concatenate([np.stack([v0, v1, v2], 1), np.stack([v0, v2, v3], 1)]) if len(x) else np.zeros((0, 3, 2))
    if field_aligned and part:
        # Each piece belongs to one grid cell; cut along the same diagonal as
        # the height sampler before triangulation. Every resulting triangle
        # lies on one known bounded plane, including narrow boundary slivers.
        pieces = []
        for piece in part:
            cx, cy = piece.centroid.coords[0]
            qx, qy = math.floor(cx / cell) * cell, math.floor(cy / cell) * cell
            lower = Polygon([(qx, qy), (qx + cell, qy), (qx + cell, qy + cell)])
            upper = Polygon([(qx, qy), (qx + cell, qy + cell), (qx, qy + cell)])
            pieces.extend([piece.intersection(lower), piece.intersection(upper)])
        part = pieces
    return np.concatenate([sq, triangulate(part)])



def graded_ground_tris(geom, height):
    """Exact heightfield facets with larger cells only where fully coplanar.

    A four-metre cell can remain two triangles when all its one-metre field
    nodes lie on one plane. Curved cells and polygon boundaries retain the
    exact one-metre field triangulation, so narrow alley/lot pieces cannot
    invent an uncontrolled gradient between otherwise safe height samples.
    """
    corners, partial = dice(geom, 4.0)
    coarse, fine = np.zeros((0, 2)), np.zeros((0, 2))
    if len(corners):
        ox, oy = np.meshgrid(np.arange(5), np.arange(5))
        offsets = np.column_stack([ox.ravel(), oy.ravel()])
        sample = corners[:, None, :] + offsets[None, :, :]
        z = height(sample[..., 0].ravel(), sample[..., 1].ravel()).reshape(len(corners), 25)
        plane = z[:, :1] + offsets[None, :, 0] * ((z[:, 4] - z[:, 0]) / 4)[:, None] + offsets[None, :, 1] * ((z[:, 20] - z[:, 0]) / 4)[:, None]
        flat = np.max(np.abs(z - plane), axis=1) < 1e-7
        coarse = corners[flat]
        sx, sy = np.meshgrid(np.arange(4), np.arange(4))
        fine = (corners[~flat, None, :] + np.column_stack([sx.ravel(), sy.ravel()])[None, :, :]).reshape(-1, 2)
    triangles = []
    for starts, size in ((coarse, 4.0), (fine, 1.0)):
        if not len(starts): continue
        p0 = starts; p1 = starts + (size, 0); p2 = starts + (size, size); p3 = starts + (0, size)
        triangles.extend([np.stack([p0, p1, p2], axis=1), np.stack([p0, p2, p3], axis=1)])
    for piece in partial:
        triangles.append(ground_tris(piece, 1.0, field_aligned=True))
    output = np.concatenate(triangles) if triangles else np.zeros((0, 3, 2))
    return output, {"coplanar_4m_cells": len(coarse), "curved_1m_cells": len(fine), "boundary_4m_cells": len(partial), "triangles": len(output)}


def polys_of(geom):
    return [g for g in shapely.get_parts(geom) if g.geom_type == "Polygon" and g.area > 0.05]


# ------------------------------------------------------------------ roofs
def strip(c, n, sa, sb):
    """A band from sa to sb along unit axis n (measured from c), 1 km wide across it."""
    t = np.array([-n[1], n[0]]) * 500.0
    p0, p1 = c + n * sa, c + n * sb
    return Polygon([p0 - t, p1 - t, p1 + t, p0 + t])


def fit_roof(s, t, z, tol=0.35):
    """Fit the main roof's LiDAR points (s along the depth, t across it): a plane (rowhouse roofs
    slope to the rear) or a gable with its ridge along s (z = a + k|t - u0|) or along t. Each fit
    is trimmed to points within tol; the winner has the most inliers, and the simpler model wins
    unless a gable is clearly better. Returns None when nothing fits."""
    best = None
    one = np.ones(len(z))

    def score(A, kind, extra):
        nonlocal best
        coef = np.linalg.lstsq(A, z, rcond=None)[0]
        for _ in range(3):
            inl = np.abs(z - A @ coef) < tol
            if inl.sum() < max(8, A.shape[1] + 2):
                return
            coef = np.linalg.lstsq(A[inl], z[inl], rcond=None)[0]
        if kind == "plane" and max(abs(coef[1]), abs(coef[2])) > 0.35:
            return
        if kind != "plane" and not (-1.2 < coef[1] < -0.1):    # a ridge has to slope down both ways
            return
        frac = float((np.abs(z - A @ coef) < tol).mean())
        if best is None or frac > best["inliers"] + (0.03 if kind != "plane" else 0.0):
            best = {"kind": kind, "coef": [float(v) for v in coef], "inliers": frac, **extra}

    score(np.column_stack([one, s, t]), "plane", {})
    for axis, u in (("t", t), ("s", s)):
        for u0 in np.arange(np.percentile(u, 15), np.percentile(u, 85) + 0.01, 0.25):
            score(np.column_stack([one, np.abs(u - u0)]), "gable_" + axis, {"u0": float(u0)})
    return best


def roof_pieces(roof, geom, c, n, perp):
    """[(polygon, top function)] for the main roof: one plane, or two planes split at the ridge."""
    proj = lambda xy, ax: (xy[:, 0] - c[0]) * ax[0] + (xy[:, 1] - c[1]) * ax[1]
    if roof["kind"] == "flat":
        return [(geom, lambda xy, a=roof["a"]: np.full(len(xy), a))]
    if roof["kind"] == "plane":
        a, kb, kc = roof["coef"]
        return [(geom, lambda xy: a + kb * proj(xy, n) + kc * proj(xy, perp))]
    a, k = roof["coef"]
    u0 = roof["u0"]
    ax = perp if roof["kind"] == "gable_t" else n          # gable_t: ridge runs along the depth
    return [(geom.intersection(strip(c, ax, u0 - 500, u0)), lambda xy: a + k * (u0 - proj(xy, ax))),
            (geom.intersection(strip(c, ax, u0, u0 + 500)), lambda xy: a + k * (proj(xy, ax) - u0))]


def roof_fn(roof, c, n, perp):
    """The main roof as one function of xy (both halves of a gable), for placing parts on it."""
    proj = lambda xy, ax: (xy[:, 0] - c[0]) * ax[0] + (xy[:, 1] - c[1]) * ax[1]
    if roof["kind"] == "flat":
        return lambda xy, a=roof["a"]: np.full(len(xy), a)
    if roof["kind"] == "plane":
        a, kb, kc = roof["coef"]
        return lambda xy: a + kb * proj(xy, n) + kc * proj(xy, perp)
    a, k = roof["coef"]
    ax = perp if roof["kind"] == "gable_t" else n
    return lambda xy: a + k * np.abs(proj(xy, ax) - roof["u0"])


def roof_pitch(roof):
    if roof["kind"] == "plane":
        return round(math.degrees(math.atan(math.hypot(roof["coef"][1], roof["coef"][2]))), 1)
    if roof["kind"].startswith("gable"):
        return round(math.degrees(math.atan(abs(roof["coef"][1]))), 1)
    return 0.0


# ------------------------------------------------------------------ the build
def main():
    els = json.load(open(C.OSM_JSON, encoding="utf-8"))["elements"]
    laz = sorted(glob.glob(os.path.join(C.RAW, "*.laz")))
    if not laz:
        raise SystemExit("[process] no LiDAR tiles; run fetch.py first")

    # ---- projection: whatever the LiDAR uses, then meters relative to the origin
    with laspy.open(laz[0]) as f:
        crs = f.header.parse_crs()
    if crs is None:
        log("WARNING: LiDAR header has no CRS; assuming NAD83(2011) UTM 18N + NAVD88 m")
        crs = CRS.from_epsg(6347)
    horiz = crs.sub_crs_list[0] if crs.is_compound else crs
    vert = crs.sub_crs_list[1] if crs.is_compound and len(crs.sub_crs_list) > 1 else None
    fxy = horiz.axis_info[0].unit_conversion_factor
    fz = vert.axis_info[0].unit_conversion_factor if vert else fxy
    log(f"LiDAR CRS: {horiz.name} | {vert.name if vert else 'no vertical CRS'} (xy x{fxy}, z x{fz})")
    tf = Transformer.from_crs("EPSG:4326", horiz, always_xy=True)

    ring_ll = area_ring(els)
    area_ll = Polygon(ring_ll).buffer(0)
    o_ll = origin_ll(els, area_ll.centroid.coords[0])
    ax, ay = tf.transform(o_ll[0], o_ll[1])
    AX, AY = ax * fxy, ay * fxy

    def P(a):
        a = np.asarray(a, float)
        x, y = tf.transform(a[:, 0], a[:, 1])
        return np.column_stack([np.asarray(x) * fxy - AX, np.asarray(y) * fxy - AY])

    local = lambda g: shapely.transform(g, P)
    area = local(area_ll)
    if area.geom_type == "MultiPolygon":
        area = max(area.geoms, key=lambda g: g.area)
    site = area.buffer(C.SITE_BUFFER)
    context = area.buffer(C.SITE_BUFFER + C.CONTEXT_BUFFER)
    log(f"area {area.area / 1e6:.3f} km2, site {site.area / 1e6:.3f} km2, context {context.area / 1e6:.3f} km2; "
        f"origin {o_ll[1]:.6f}, {o_ll[0]:.6f}")

    # ---- LiDAR points inside the context bounds
    xmin, ymin, xmax, ymax = context.bounds
    xmin, ymin, xmax, ymax = xmin - 10, ymin - 10, xmax + 10, ymax + 10
    cols = {k: [] for k in "xyzcr"}
    for p in laz:
        with laspy.open(p) as f:
            for pts in f.chunk_iterator(5_000_000):
                x = np.asarray(pts.x) * fxy - AX
                y = np.asarray(pts.y) * fxy - AY
                m = (x >= xmin) & (x <= xmax) & (y >= ymin) & (y <= ymax)
                if m.any():
                    cols["x"].append(x[m].astype(np.float32))
                    cols["y"].append(y[m].astype(np.float32))
                    cols["z"].append((np.asarray(pts.z)[m] * fz).astype(np.float32))
                    cols["c"].append(np.asarray(pts.classification)[m].astype(np.uint8))
                    rn, nr = np.asarray(pts.return_number)[m], np.asarray(pts.number_of_returns)[m]
                    cols["r"].append((rn == nr).astype(np.uint8) | ((nr > 1).astype(np.uint8) << 1))
    X, Y, Z, K, RT = (np.concatenate(cols[k]) for k in "xyzcr")
    del cols
    # This survey classifies only ground and noise, so roofs and trees are told apart by returns:
    # a pulse through bare winter branches comes back several times, a roof gives one (last) return.
    LAST, MULTI = (RT & 1) > 0, (RT & 2) > 0
    hist = {int(c): int(n) for c, n in zip(*np.unique(K, return_counts=True))}
    has_veg = any(hist.get(c, 0) > 1000 for c in VEG)
    log(f"{len(X):,} LiDAR points in bounds; classes {hist}")

    # ---- bare-earth grid (1 m) from the ground points
    RES = 1.0
    gx0, gy0 = xmin, ymin
    nx, ny = int(math.ceil((xmax - xmin) / RES)), int(math.ceil((ymax - ymin) / RES))
    g = K == GROUND
    cell = (np.clip(((Y[g] - gy0) / RES).astype(np.int64), 0, ny - 1) * nx
            + np.clip(((X[g] - gx0) / RES).astype(np.int64), 0, nx - 1))
    cnt = np.bincount(cell, minlength=nx * ny)
    dtm = np.full(nx * ny, np.nan)
    dtm[cnt > 0] = np.bincount(cell, weights=Z[g], minlength=nx * ny)[cnt > 0] / cnt[cnt > 0]
    dtm = dtm.reshape(ny, nx)
    hole = np.isnan(dtm)
    log(f"ground grid {nx}x{ny}, {hole.mean() * 100:.0f}% filled from neighbors (under buildings)")
    dtm = dtm[tuple(ndimage.distance_transform_edt(hole, return_distances=False, return_indices=True))]
    dtm = ndimage.uniform_filter(dtm, 3)
    # Remove meter-scale survey spikes that made adjacent sidewalk triangles
    # look like tipped slabs. A symmetric filter preserves linear street grades;
    # bounded residual detail keeps mild unevenness instead of flattening hills.
    surveyed_dtm = dtm
    broad_ground = ndimage.gaussian_filter(surveyed_dtm, sigma=2.2)
    dtm = broad_ground + np.clip(surveyed_dtm - broad_ground, -0.04, 0.04) * 0.35
    terrain_adjustment = {
        "smoothing_radius_m": 2.2, "retained_small_detail_m": 0.014,
        "height_delta_p50_m": round(float(np.median(np.abs(dtm - surveyed_dtm))), 4),
        "height_delta_p95_m": round(float(np.percentile(np.abs(dtm - surveyed_dtm), 95)), 4),
    }
    log("coherent terrain smoothing " + json.dumps(terrain_adjustment))
    grid = {"x0": gx0, "y0": gy0}

    def H(px, py):
        u = (np.asarray(px) - grid["x0"]) / RES - 0.5
        v = (np.asarray(py) - grid["y0"]) / RES - 0.5
        i = np.clip(np.floor(u).astype(np.int64), 0, nx - 2)
        j = np.clip(np.floor(v).astype(np.int64), 0, ny - 2)
        tu, tv = np.clip(u - i, 0, 1), np.clip(v - j, 0, 1)
        return (dtm[j, i] * (1 - tu) * (1 - tv) + dtm[j, i + 1] * tu * (1 - tv)
                + dtm[j + 1, i] * (1 - tu) * tv + dtm[j + 1, i + 1] * tu * tv)

    # ---- buildings (OSM footprints in local meters)
    bld = []
    for bid, t, ll in building_shapes(els):
        poly = local(ll)
        c = poly.centroid
        if not context.contains(c):
            continue
        zone = "core" if area.contains(c) else "site" if site.contains(c) else "context"
        bld.append({"id": bid, "tags": t, "ll": ll, "poly": poly, "zone": zone})
    site_b = [b for b in bld if b["zone"] != "context"]
    log(f"{len(bld)} buildings: {sum(b['zone'] == 'core' for b in bld)} core, "
        f"{sum(b['zone'] == 'site' for b in bld)} site edge, {sum(b['zone'] == 'context' for b in bld)} context")

    # ---- line OSM up with the LiDAR: shift that best overlaps footprints with high points
    other = (K != GROUND) & ~np.isin(K, list(NOISE | {9}))
    tall = other & LAST & (Z - H(X, Y) > 2.5)
    if has_veg:
        tall &= ~np.isin(K, list(VEG))
    ar = 0.5
    bx0, by0, bx1, by1 = site.bounds
    anx, any_ = int((bx1 - bx0) / ar) + 1, int((by1 - by0) / ar) + 1
    L = np.zeros((any_, anx), bool)
    ix = ((X[tall] - bx0) / ar).astype(np.int64)
    iy = ((Y[tall] - by0) / ar).astype(np.int64)
    ok = (ix >= 0) & (ix < anx) & (iy >= 0) & (iy < any_)
    L[iy[ok], ix[ok]] = True
    L = ndimage.binary_closing(L)
    cx, cy = np.meshgrid(bx0 + (np.arange(anx) + 0.5) * ar, by0 + (np.arange(any_) + 0.5) * ar)
    U = unary_union([b["poly"] for b in site_b])
    shapely.prepare(U)
    F = shapely.contains_xy(U, cx.ravel(), cy.ravel()).reshape(any_, anx)
    best, iou0 = (0, 0, -1.0), None
    R = int(4.0 / ar)
    for dj in range(-R, R + 1):
        for di in range(-R, R + 1):
            Fs = np.roll(F, (dj, di), axis=(0, 1))
            iou = np.count_nonzero(Fs & L) / max(np.count_nonzero(Fs | L), 1)
            if di == 0 and dj == 0:
                iou0 = iou
            if iou > best[2]:
                best = (di, dj, iou)
    sx, sy = best[0] * ar, best[1] * ar
    log(f"OSM->LiDAR shift {sx:+.1f} m east, {sy:+.1f} m north (footprint/roof overlap {iou0:.3f} -> {best[2]:.3f})")
    X -= np.float32(sx)
    Y -= np.float32(sy)
    grid["x0"], grid["y0"] = gx0 - sx, gy0 - sy
    del F, L, cx, cy, tall

    HAG = Z - H(X, Y)
    y0 = float(H(np.array([0.0]), np.array([0.0]))[0])
    log(f"origin ground elevation {y0:.2f} m (game y = 0)")

    # roof candidates: everything off the ground except noise/water (and vegetation when classified)
    rmask = other & LAST & (HAG > 1.5)
    if has_veg:
        rmask &= ~np.isin(K, list(VEG))
    RX, RY, RZ = X[rmask].astype(np.float64), Y[rmask].astype(np.float64), Z[rmask].astype(np.float64)
    pc = 2.0
    rx0, ry0 = RX.min(), RY.min()
    pnx = int((RX.max() - rx0) / pc) + 1
    pny = int((RY.max() - ry0) / pc) + 1
    key = ((RY - ry0) / pc).astype(np.int64) * pnx + ((RX - rx0) / pc).astype(np.int64)
    order = np.argsort(key, kind="stable")
    starts = np.searchsorted(key[order], np.arange(pnx * pny + 1))

    def pts_in(poly):
        x0_, y0_, x1_, y1_ = poly.bounds
        i0, i1 = max(int((x0_ - rx0) / pc), 0), min(int((x1_ - rx0) / pc), pnx - 1)
        j0, j1 = max(int((y0_ - ry0) / pc), 0), min(int((y1_ - ry0) / pc), pny - 1)
        if i0 > i1 or j0 > j1:
            return np.zeros(0, np.int64)
        idx = np.concatenate([order[starts[j * pnx + i0]:starts[j * pnx + i1 + 1]] for j in range(j0, j1 + 1)])
        return idx[shapely.contains_xy(poly, RX[idx], RY[idx])]

    # ---- streets
    cw, svc, paths, lots = [], [], [], []
    for e in els:
        t = e.get("tags", {})
        if e["type"] != "way" or len(e.get("geometry", [])) < 2:
            continue
        hw = t.get("highway")
        if hw in CARRIAGEWAY:
            base = hw.replace("_link", "")
            w = 7.0 if hw.endswith("_link") else ROAD_W.get(base, 8.0)
            try:
                w = float(t["width"].replace("m", "").strip()) if "width" in t else w
            except ValueError:
                pass
            cw.append((local(LineString(way_ll(e))), w, SIDEWALK_W.get(base, 2.4), t.get("name", "")))
        elif hw == "service":
            svc.append((local(LineString(way_ll(e))), SERVICE_W.get(t.get("service"), 4.5)))
        elif hw in PATHS and t.get("footway") not in ("sidewalk", "crossing"):
            paths.append(local(LineString(way_ll(e))))
        elif t.get("amenity") == "parking" and t.get("parking", "surface") == "surface" and way_ll(e)[0] == way_ll(e)[-1]:
            lots.append(local(Polygon(way_ll(e))).buffer(0))
    road_lines = [c_[0] for c_ in cw]
    road_tree = shapely.STRtree(road_lines)
    log(f"{len(cw)} street ways, {len(svc)} service ways, {len(paths)} paths, {len(lots)} parking lots")

    # Streets and all adjoining surfaces share an engineered crown/profile.
    H = street_geometry.EngineeredHeight(cw, H)
    bld, road_surface, clearance_audit = street_geometry.repair_footprints(bld, cw)
    paved_profile_area = unary_union([site, road_surface, *[line.buffer(0.9) for line in paths]])
    H.build_surface_field(context.bounds, paved_profile_area)
    H.field_audit["coverage"] = "Entire playable site, plus context road and pedestrian corridors; smooth 20m outer transition"
    y0 = float(H(0.0, 0.0))
    site_b = [b for b in bld if b["zone"] != "context"]
    inverse = Transformer.from_crs(horiz, "EPSG:4326", always_xy=True)
    def unproject(xy):
        lon, lat = inverse.transform((xy[:, 0] + AX) / fxy, (xy[:, 1] + AY) / fxy)
        return np.column_stack([lon, lat])
    for b in bld:
        if b.get("road_clearance_repaired"): b["ll"] = shapely.transform(b["poly"], unproject)
    parks = []
    for e in els:
        t = e.get("tags", {})
        if t.get("leisure") not in ("park", "garden", "playground", "pitch") and t.get("landuse") not in ("recreation_ground", "village_green"): continue
        if e["type"] != "way" or len(e.get("geometry", [])) < 4: continue
        ll = way_ll(e)
        if ll[0] != ll[-1]: continue
        geom = local(Polygon(ll)).buffer(0).intersection(site)
        for part in polys_of(geom):
            if part.area > 20:
                parks.append({"name": t.get("name", "Neighborhood " + t.get("leisure", "green")), "kind": t.get("leisure", "park"), "poly": part})
    protected_parks = unary_union([p["poly"] for p in parks])
    log(f"engineered streets: {H.audit()}; repaired {len(clearance_audit['trimmed'])} road-overlap footprints; protected {len(parks)} parks")

    # ---- rows: footprints that touch belong to one row (one Blender object per row)
    union = unary_union([b["poly"].buffer(0.3) for b in site_b])
    comps = sorted(polys_of(union), key=lambda g: (-round(g.centroid.y / 25), g.centroid.x))
    ctree = shapely.STRtree(comps)
    members = {i: [] for i in range(len(comps))}
    for b in site_b:
        hit = ctree.query(b["poly"].representative_point(), predicate="intersects")
        i = int(hit[0]) if len(hit) else int(ctree.nearest(b["poly"].representative_point()))
        members[i].append(b)
        b["row"] = i
    for i, ms in members.items():
        for b in ms:
            b["attached"] = len(ms) > 1

    def depth_axis(poly, c):
        """Unit vector along the footprint's depth, pointing at the nearest street."""
        r = np.array(poly.minimum_rotated_rectangle.exterior.coords)[:4]
        e1, e2 = r[1] - r[0], r[2] - r[1]
        l1, l2 = np.linalg.norm(e1), np.linalg.norm(e2)
        long_ = e1 / max(l1, 1e-9) if l1 >= l2 else e2 / max(l2, 1e-9)
        short = np.array([-long_[1], long_[0]])
        half = max(l1, l2) / 2
        cand = [long_, -long_] if max(l1, l2) / max(min(l1, l2), 1e-9) >= 1.3 else [long_, -long_, short, -short]
        ends = [Point(c + d * half) for d in cand]
        dist = [road_tree.query_nearest(p, return_distance=True)[1][0] for p in ends]
        return cand[int(np.argmin(dist))]

    # ---- heights for every building
    flags_count = {}
    for b in bld:
        poly, t = b["poly"], b["tags"]
        c = np.array(poly.centroid.coords[0])
        per = np.array(shapely.segmentize(poly.exterior, 1.0).coords)
        gz = H(per[:, 0], per[:, 1])
        b["base"], b["ground"] = float(gz.min()), float(np.median(gz))
        surveyed_gz = H.surveyed_height(per[:, 0], per[:, 1])
        b["survey_ground"] = float(np.median(surveyed_gz))
        b["grade_shift"] = b["ground"] - b["survey_ground"]
        shrunk = poly.buffer(-0.35)
        sel = pts_in(shrunk if (not shrunk.is_empty and shrunk.area > 4) else poly)
        b["pts"], b["flags"] = int(len(sel)), []
        lv = levels(t)
        fallback = b["ground"] + (lv * 3.1 + 0.8 if lv else 8.5)
        surveyed_roof = RZ[sel].astype(np.float64)
        z = street_geometry.rebase_roof_returns(surveyed_roof, b["survey_ground"], b["ground"])
        b["roof_relative_height_error"] = float(np.max(np.abs((z - b["ground"]) - (surveyed_roof - b["survey_ground"])))) if len(z) else 0.0
        if b["zone"] == "context" or len(sel) < 10:
            top = float(np.percentile(z, 75)) if len(sel) >= 10 else fallback
            if len(sel) < 10:
                b["flags"].append("no_lidar")
            flat_top = (lambda v: lambda xy: np.full(len(xy), v))(top)
            b["pieces"] = [("main", poly, flat_top)]
            n_ = depth_axis(poly, c) if b["zone"] != "context" else None
            sr_ = (np.array(poly.exterior.coords) - c) @ n_ if n_ is not None else np.zeros(1)
            b.update(main=top, eave=top, roof="flat", roof_fit=0.0, pitch=0.0, porch=0.0, rear=0.0, n=n_,
                     s0=float(sr_.min()), s1=float(sr_.max()), roof_at=flat_top)
            continue
        n = depth_axis(poly, c)
        s = (RX[sel] - c[0]) * n[0] + (RY[sel] - c[1]) * n[1]
        sr = (np.array(poly.exterior.coords) - c) @ n
        s0, s1 = float(sr.min()), float(sr.max())
        step = 0.5
        nb = max(int(math.ceil((s1 - s0) / step)), 1)
        bi = np.clip(((s - s0) / step).astype(np.int64), 0, nb - 1)
        med = np.full(nb, np.nan)
        for k in range(nb):
            zz = z[bi == k]
            if len(zz) >= 2:
                med[k] = np.median(zz)
        valid = ~np.isnan(med)
        main_lvl = float(np.percentile(med[valid], 75)) if valid.sum() >= 3 else float(np.percentile(z, 75))
        low = valid & (med < main_lvl - 1.6) & (med > b["ground"] + 1.8)

        def run(ks):
            skip = cnt = 0
            for k in ks:
                if not valid[k] and cnt == 0 and skip < 2:
                    skip += 1
                    continue
                if not low[k]:
                    break
                cnt += 1
            return (cnt + skip) * step if cnt * step >= 1.5 else 0.0

        residential = t.get("building") in ("yes", "house", "residential", "terrace", "semidetached_house", "detached", "apartments")
        split = residential and (s1 - s0) >= 8.0
        d_f = min(run(range(nb - 1, -1, -1)), 0.45 * (s1 - s0)) if split else 0.0
        d_r = min(run(range(nb)), 0.45 * (s1 - s0)) if split else 0.0
        m_lo, m_hi = s0 + d_r, s1 - d_f
        mm = (s >= m_lo) & (s <= m_hi) & (z >= main_lvl - 1.6)
        main_poly = poly.intersection(strip(c, n, m_lo, m_hi)) if (d_f or d_r) else poly
        perp = np.array([-n[1], n[0]])
        tt = (RX[sel] - c[0]) * perp[0] + (RY[sel] - c[1]) * perp[1]
        roof = fit_roof(s[mm], tt[mm], z[mm]) if mm.sum() >= 12 else None
        if roof is None or roof["inliers"] < 0.5:
            roof = {"kind": "flat", "a": float(np.percentile(z[mm], 60)) if mm.sum() >= 3 else main_lvl, "inliers": 0.0}
            b["flags"].append("complex_roof")
        main_pieces = roof_pieces(roof, main_poly, c, n, perp)
        vz = np.concatenate([fn(np.array(g.exterior.coords)) for geom, fn in main_pieces for g in polys_of(geom)] or [np.zeros(1)])
        lo_top, hi_top = b["ground"] + 2.0, b["ground"] + 45.0     # 2 m: back-alley garages and sheds
        if vz.min() < lo_top or vz.max() > hi_top:
            roof = {"kind": "flat", "a": float(np.clip(np.median(vz), lo_top, hi_top)), "inliers": roof["inliers"]}
            main_pieces = roof_pieces(roof, main_poly, c, n, perp)
            vz = np.array([roof["a"]])
            b["flags"].append("height_clamped")
        pieces = [("main", g, fn) for g, fn in main_pieces]
        porch_top = rear_top = 0.0
        if d_f:
            zz = z[(s > s1 - d_f) & (z < main_lvl - 1.0)]
            porch_top = max(float(np.median(zz)) if len(zz) else b["ground"] + 3.2, b["ground"] + 2.4)
            pieces.append(("porch", poly.intersection(strip(c, n, s1 - d_f, s1 + 1)),
                           lambda xy, v=porch_top: np.full(len(xy), v)))
        if d_r:
            zz = z[(s < s0 + d_r) & (z < main_lvl - 1.0)]
            rear_top = max(float(np.median(zz)) if len(zz) else b["ground"] + 3.2, b["ground"] + 2.4)
            pieces.append(("rear", poly.intersection(strip(c, n, s0 - 1, s0 + d_r)),
                           lambda xy, v=rear_top: np.full(len(xy), v)))
        b["pieces"] = pieces
        b.update(main=float(vz.max()), eave=float(vz.min()), roof=roof["kind"], roof_fit=roof["inliers"],
                 pitch=roof_pitch(roof), porch=d_f, rear=d_r, n=n, porch_top=porch_top, rear_top=rear_top,
                 s0=s0, s1=s1, roof_at=roof_fn(roof, c, n, perp))
    for b in bld:
        for fl in b["flags"]:
            flags_count[fl] = flags_count.get(fl, 0) + 1
    log(f"heights done; flags {flags_count}")

    # ---- archetypes, looks and door sides for the site buildings
    fp_tree = shapely.STRtree([b["poly"] for b in bld])

    def exposed(pt):
        return len(fp_tree.query(Point(pt), predicate="intersects")) == 0

    for b in site_b:
        t = b["tags"]
        kind, fa, h = t.get("building"), b["poly"].area, b["main"] - b["ground"]
        if fa < 45 and h < 4.6:
            arch = "garage"
        elif kind in CIVIC or fa > 700 or t.get("amenity"):
            arch = "civic"
        elif b["attached"]:
            near = cw[int(road_tree.nearest(b["poly"].centroid))][3]
            on_greenmount = "Greenmount Avenue" in (t.get("addr:street"), near)
            arch = "storefront" if on_greenmount and b["porch"] == 0 else "row_porch" if b["porch"] > 0 else "row"
        else:
            arch = "detached_porch" if b["porch"] > 0 else "detached"
        st = kits.style(b, f"row{b['row']}")
        if arch == "civic":
            st["wall"] = "stone"
        elif arch == "garage":
            st["wall"] = "brick" if b["attached"] else "siding"
        elif arch.startswith("detached"):
            st["wall"] = SIDINGS[int(st["rng"].integers(len(SIDINGS)))]
            if b["roof"].startswith("gable"):
                st["roof"] = "roof_tar"
        b["arch"], b["style"] = arch, st
    for ms in members.values():          # doors alternate along a row, so neighbors mirror each other
        if len(ms) > 1 and ms[0]["n"] is not None:
            ax = np.array([-ms[0]["n"][1], ms[0]["n"][0]])
            for k, b in enumerate(sorted(ms, key=lambda b: np.array(b["poly"].centroid.coords[0]) @ ax)):
                b["door_left"] = k % 2 == 0
    rear_headroom_audit = street_geometry.ensure_rear_headroom(site_b, H)
    business_audit = street_geometry.assign_businesses(site_b, cw, H, exposed)
    arch_count = {}
    for b in site_b:
        arch_count[b["arch"]] = arch_count.get(b["arch"], 0) + 1
    log(f"archetypes {arch_count}")

    # ---- building meshes
    def open_porch(b):
        return b.get("arch") in ("row_porch", "detached_porch") and b["porch"] > 0.8

    kit_ctx = {"H": H, "exposed": exposed}
    kit_forbidden = road_surface.buffer(0.04)
    shapely.prepare(kit_forbidden)

    def prism(mb, geom, base, topfn, wmat, rmat):
        for part in polys_of(geom):
            part = orient(part, 1.0)
            for ring in [part.exterior, *part.interiors]:
                r = np.array(ring.coords)
                p, q = r[:-1], r[1:]
                mb.quads(p, q, np.full(len(p), base), np.full(len(q), base), topfn(p), topfn(q), wmat)
            tri = triangulate([part])
            if len(tri):
                flat = tri.reshape(-1, 2)
                mb.add(np.concatenate([tri, topfn(flat).reshape(-1, 3, 1)], 2), rmat)

    objects = []
    for i, ms in members.items():
        if not ms:
            continue
        name = (f"Row_{i + 1:03d}" if len(ms) > 1 else f"Bldg_{i + 1:03d}")
        mb = MB(name, props={"osm_ids": " ".join(b["id"] for b in ms),
                             "addresses": "; ".join(f"{b['tags'].get('addr:housenumber', '')} {b['tags'].get('addr:street', '')}".strip() for b in ms)})
        for b in ms:
            b["object"] = name
            st = b["style"]
            for kind, geom, fn in b["pieces"]:
                if kind == "porch" and open_porch(b):
                    continue                     # the kit builds it open: deck, posts, railing, roof
                prism(mb, geom, b["base"] - 0.3, fn, st["wall"], "porch_roof" if kind == "porch" else st["roof"])
            P = kits.Parts(kit_forbidden)
            kits.build(P, b, kit_ctx)
            b["kit_rejections"] = dict(P.rejected_sections)
            P.emit(mb)
        objects.append(mb)
    missing_shop_facades = [b["id"] for b in site_b if b.get("business") and "sign_xyz" not in b["business"]]
    if missing_shop_facades:
        raise ValueError("Selected commercial wall did not generate its facade: " + ", ".join(missing_shop_facades))
    ctx = MB("Context_Buildings")
    for b in bld:
        if b["zone"] == "context":
            for kind, geom, fn in b["pieces"]:
                prism(ctx, geom, b["base"] - 0.3, fn, "context_bldg", "context_bldg")
    objects.append(ctx)
    log(f"{len(objects) - 1} row/building objects, {sum(o.tri_count() for o in objects):,} building tris")

    # ---- ground zones (site)
    blds_all = unary_union([b["poly"] for b in bld])
    # the ground runs on under open porches (their decks stand on it), so cut only the closed pieces
    cut = unary_union([g for b in bld for kind, g, fn in b["pieces"] if not (kind == "porch" and open_porch(b))])
    roads = unary_union([l.buffer(w / 2, quad_segs=4) for l, w, sw, _ in cw]).intersection(site)
    walks = unary_union([l.buffer(w / 2 + sw, quad_segs=4) for l, w, sw, _ in cw]
                        + [l.buffer(0.9, quad_segs=2) for l in paths])
    walks = walks.difference(roads).difference(blds_all).intersection(site)
    alleys = unary_union([l.buffer(w / 2, cap_style="flat", quad_segs=2) for l, w in svc])
    alleys = alleys.difference(roads).difference(walks).difference(blds_all).intersection(site)
    lot = unary_union(lots).difference(unary_union([roads, walks, alleys, blds_all])).intersection(site) if lots else Polygon()
    open_green = site.difference(unary_union([blds_all.buffer(7.0), roads.buffer(4.0), walks, alleys, lot, protected_parks]))
    broad_green = sorted((p for p in polys_of(open_green) if p.area >= 600 and not p.buffer(-7).is_empty), key=lambda p: p.area, reverse=True)
    for index, green in enumerate(broad_green[:3]):
        parks.append({"name": "Community green " + str(index + 1), "kind": "community_green", "poly": green})
    protected_parks = unary_union([p["poly"] for p in parks])
    yards = street_geometry.urban_yards(blds_all, protected_parks, roads, walks, alleys, lot, site)
    entrances = []
    for b in site_b:
        shop = b.get("business", {})
        if "door_xyz" not in shop: continue
        door_point = Point(shop["door_xyz"][:2])
        target = nearest_points(door_point, walks)[1]
        path = LineString([door_point, target]).buffer(0.85, cap_style="square")
        if not path.intersects(protected_parks) and path.intersection(blds_all.buffer(-0.15)).area < 0.05:
            entrances.append(path.difference(unary_union([blds_all, roads, walks])).intersection(site))
    alleys = unary_union([alleys, yards, *entrances])
    grass = site.difference(unary_union([roads, walks, alleys, lot, cut]))
    residential = [b for b in site_b if b["arch"] in ("row", "row_porch", "detached", "detached_porch")]
    rear_omissions = [{"building_id": b["id"], "source_mesh": b.get("object"), "reason": b.get("rear_door_status", "not_processed"),
                       "address": b["tags"].get("addr:housenumber", "") + " " + b["tags"].get("addr:street", ""),
                       "eave_above_ground_m": round(b["eave"] - b["ground"], 3)} for b in residential if "rear_door" not in b]
    stair_omissions = [{"building_id": b["id"], "source_mesh": b.get("object"), "rejected_parts": b["porch_stair"]["rejected_parts"]}
                      for b in site_b if b.get("porch_stair") and not b["porch_stair"].get("geometry_complete", True)]
    rejection_sections = {}
    for b in site_b:
        for section, count in b.get("kit_rejections", {}).items():
            rejection_sections[section] = rejection_sections.get(section, 0) + count
    datum_shifts = np.array([b["grade_shift"] for b in site_b])
    building_datum_audit = {"method": "Rigidly translate surveyed roof returns by graded-minus-surveyed median footing before profiling",
                            "buildings": len(site_b), "minimum_shift_m": float(datum_shifts.min()), "maximum_shift_m": float(datum_shifts.max()),
                            "median_absolute_shift_m": float(np.median(np.abs(datum_shifts))),
                            "max_roof_relative_height_error_m": max(b["roof_relative_height_error"] for b in site_b)}
    if building_datum_audit["max_roof_relative_height_error_m"] > 1e-8:
        raise ValueError("Grading changed a surveyed building's relative roof height")
    construction_audit = {"building_height_datum": building_datum_audit, "rear_addition_headroom": rear_headroom_audit, "rear_door_coverage": {"residential_footprints": len(residential), "built": len(residential) - len(rear_omissions), "omissions": rear_omissions},
                          "porch_stair_omissions": stair_omissions, "rejected_kit_sections": rejection_sections,
                          "street_profiles": H.audit(), "road_clearance": clearance_audit,
                          "sidewalk_grades": street_geometry.sidewalk_grade_audit(cw, H, walks),
                          "businesses": business_audit, "hardscape_yards_m2": round(yards.area, 2),
                          "protected_parks_m2": round(protected_parks.area, 2), "kits": dict(kits.BUILD_STATS)}
    zones = {"road": roads, "sidewalk": walks, "alley": alleys, "lot": lot, "grass": grass}
    gmb, curbs = MB("Ground", smooth=True), MB("Curbs")
    zone_area = {}
    against_wall = cut.buffer(0.05)         # skirts along a building wall are hidden inside it; skip them
    shapely.prepare(against_wall)
    for zname, geom in zones.items():
        geom = shapely.set_precision(geom, 0.001)     # snap to mm: drops near-degenerate slivers
        zone_area[zname] = round(geom.area)
        tri, mesh_cells = graded_ground_tris(geom, H)
        construction_audit.setdefault("ground_mesh_cells", {})[zname] = mesh_cells
        if len(tri):
            flat = tri.reshape(-1, 2)
            gmb.add(np.concatenate([tri, (H(flat[:, 0], flat[:, 1]) + LIFT[zname]).reshape(-1, 3, 1)], 2), ZONE_MAT[zname])
        if zname == "road":
            continue
        for part in polys_of(geom):
            part = orient(part, 1.0)
            for ring in [part.exterior, *part.interiors]:
                r = np.array(shapely.segmentize(ring, 2.0).coords)
                p, q = r[:-1], r[1:]
                mid = (p + q) / 2
                keep = ~shapely.contains_xy(against_wall, mid[:, 0], mid[:, 1])
                p, q = p[keep], q[keep]
                hp, hq = H(p[:, 0], p[:, 1]), H(q[:, 0], q[:, 1])
                curbs.quads(p, q, hp - SKIRT, hq - SKIRT, hp + LIFT[zname], hq + LIFT[zname], SKIRT_MAT[zname])
    cg = MB("Ground_Context", smooth=True)
    tri = ground_tris(shapely.set_precision(context.difference(site), 0.001), CONTEXT_DICE)
    flat = tri.reshape(-1, 2)
    cg.add(np.concatenate([tri, (H(flat[:, 0], flat[:, 1]) - 0.03).reshape(-1, 3, 1)], 2), "context_ground")
    objects += [gmb, curbs, cg]
    log(f"ground: {gmb.tri_count():,} tris, curbs {curbs.tri_count():,}, context {cg.tri_count():,}; zone m2 {zone_area}")

    # ---- trees from the LiDAR canopy (leaf-off, so only the bigger trees show up)
    vmask = (np.isin(K, list(VEG)) if has_veg else ((K == 1) & MULTI & ~LAST)) & (HAG > 2.5) & (HAG < 35)
    VX, VY, VH = X[vmask].astype(np.float64), Y[vmask].astype(np.float64), HAG[vmask].astype(np.float64)
    near_bld = blds_all.buffer(1.5)
    shapely.prepare(near_bld)
    keep = ~shapely.contains_xy(near_bld, VX, VY)
    keep &= shapely.contains_xy(context, VX, VY)
    VX, VY, VH = VX[keep], VY[keep], VH[keep]
    trees = []
    if len(VX):
        tx0, ty0 = VX.min(), VY.min()
        tnx, tny = int(VX.max() - tx0) + 1, int(VY.max() - ty0) + 1
        tk = ((VY - ty0).astype(np.int64)) * tnx + (VX - tx0).astype(np.int64)
        o = np.lexsort((VH, tk))
        last = np.r_[tk[o][1:] != tk[o][:-1], True]
        chm = np.zeros(tnx * tny)
        chm[tk[o][last]] = VH[o][last]
        chm = ndimage.gaussian_filter(chm.reshape(tny, tnx), 1.0)
        peaks = np.argwhere((chm == ndimage.maximum_filter(chm, size=7)) & (chm > 4.5))
        kd = cKDTree(np.column_stack([VX, VY]))
        for j, i in peaks:
            px, py = tx0 + i + 0.5, ty0 + j + 0.5
            near = kd.query_ball_point((px, py), 3.0)
            if len(near) < 12:
                continue
            hh = VH[near]
            if np.percentile(hh, 90) - np.percentile(hh, 10) < 2.0:
                continue
            h = float(hh.max())
            # crown radius: how far out the upper canopy points reach (most of the crown is above 45% of the height)
            wide = np.asarray(kd.query_ball_point((px, py), 8.0))
            crown = wide[VH[wide] > 0.45 * h]
            d = np.hypot(VX[crown] - px, VY[crown] - py)
            r = np.percentile(d, 80) if len(d) >= 8 else 0.3 * h
            trees.append((px, py, h, float(np.clip(min(r, 0.45 * h), 2.0, 7.0))))
    # A canopy maximum can overhang the street; it is not evidence of a trunk in pavement.
    # Keep sidewalk trees, but reject inferred trunk centres inside mapped road surfaces.
    canopy_candidates = len(trees)
    trees = [tree for tree in trees if not roads.covers(Point(tree[0], tree[1]))]
    log(f"excluded {canopy_candidates - len(trees)} canopy peaks over road pavement")
    tmb = MB("Trees", smooth=True)
    vegetation_path = os.path.join(C.ROOT, "godot", "assets", "data", "pen_lucy_vegetation.json")
    vegetation_report = vegetation.build(trees, grass, blds_all, H, y0, tmb, vegetation_path)
    if tmb.tris:
        objects.append(tmb)
    log(f"vegetation {vegetation_report}; fallback trees {tmb.tri_count():,} tris")

    # ---- preview cameras (game coords: x east, y up from the origin's ground, z south), placed on the terrain
    def gy(x, z, above):
        return round(float(H(np.array([x]), np.array([-z]))[0]) - y0 + above, 2)

    ax0, ay0_, ax1, ay1 = area.bounds
    mx, mz = (ax0 + ax1) / 2, -(ay0_ + ay1) / 2
    gm = unary_union([l for l, w, sw, nm in cw if nm == "Greenmount Avenue"])

    def on_gm(north):   # x of Greenmount Ave at this northing
        hit = gm.intersection(LineString([(-1e4, north), (1e4, north)]))
        return hit.centroid.x if not hit.is_empty else ax0

    gs, gn = ay0_ + 60, ay0_ + 200
    views = [
        {"name": "overview", "eye": [mx - 480, gy(mx, mz, 430), mz + 520], "look": [mx, gy(mx, mz, 0), mz], "fov": 42},
        {"name": "top", "eye": [mx, gy(mx, mz, 900), mz + 60], "look": [mx, gy(mx, mz, 0), mz], "fov": 40},
        {"name": "greenmount", "eye": [on_gm(gs) + 1.5, gy(on_gm(gs) + 1.5, -gs, 1.7), -gs],
         "look": [on_gm(gn), gy(on_gm(gn), -gn, 3.0), -gn], "fov": 55},
        {"name": "old_york", "eye": [70, gy(70, 150, 45), 150], "look": [0, gy(0, 0, 0), 0], "fov": 50},
    ]

    # close-ups for judging the kits: stand across the street from a typical house of each kind
    def facing(b, back=12.0, side=5.0, up=1.8, fov=50):
        c = np.array(b["poly"].centroid.coords[0])
        n, perp = b["n"], np.array([-b["n"][1], b["n"][0]])
        f = c + n * b["s1"]
        eye, look = f + n * back + perp * side, f - perp * side * 0.3
        return {"name": b["arch"], "fov": fov,
                "eye": [round(eye[0], 2), gy(eye[0], -eye[1], up), round(-eye[1], 2)],
                "look": [round(look[0], 2), gy(look[0], -look[1], 3.2), round(-look[1], 2)]}

    acx, acy = area.centroid.x, area.centroid.y
    by_dist = sorted((b for b in site_b if b["n"] is not None and b["zone"] == "core"),
                     key=lambda b: b["poly"].centroid.distance(Point(acx, acy)))
    closeups = []
    for arch in ("row_porch", "storefront", "detached_porch", "row"):
        pool = [b for b in by_dist if b["arch"] == arch and b["main"] - b["ground"] > 6.0
                and (arch not in ("row_porch", "row") or len(members[b["row"]]) >= 4)]
        if pool:
            closeups.append(facing(pool[0]))

    # ---- write everything
    runtime_path, runtime_data = runtime.export(cw, bld, area, site, context, zones, H, y0, o_ll, objects, parks=parks, construction_audit=construction_audit)
    log(f"runtime metadata: {len(runtime_data['landmarks'])} landmarks, "
        f"{len(runtime_data['dressing'])} props -> {runtime_path}")
    os.makedirs(C.BUILD, exist_ok=True)
    os.makedirs(C.DATA, exist_ok=True)
    out = {"area": C.AREA, "origin_lonlat": o_ll, "origin_elevation_m": y0, "views": views, "closeups": closeups,
           "materials": {k: list(v) for k, v in MATS.items()},
           "objects": [o.build(y0) for o in objects if o.tris]}
    with open(C.GEOM_JSON, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    tris = sum(len(o["faces"]) // 3 for o in out["objects"])

    feats = []
    for b in site_b:
        t = b["tags"]
        az = None if b["n"] is None else round(math.degrees(math.atan2(b["n"][0], b["n"][1])) % 360, 1)
        c = b["poly"].centroid
        props = {
            "osm_id": b["id"], "zone": b["zone"], "object": b.get("object"), "row_size": len(members[b["row"]]),
            "archetype": b.get("arch"), "door_left": b.get("door_left"),
            "address": f"{t.get('addr:housenumber', '')} {t.get('addr:street', '')}".strip() or None,
            "building": t.get("building"), "name": t.get("name"), "attached": b["attached"],
            "game_x": round(c.x, 2), "game_z": round(-c.y, 2), "ground_y": round(b["ground"] - y0, 2),
            "surveyed_ground_elevation_m": round(b["survey_ground"], 4), "grade_shift_m": round(b["grade_shift"], 4),
            "front_azimuth_deg": az, "height_m": round(b["main"] - b["ground"], 2), "eave_m": round(b["eave"] - b["ground"], 2),
            "roof": b["roof"], "roof_pitch_deg": b["pitch"], "roof_fit": round(b["roof_fit"], 2),
            "porch_depth_m": round(b["porch"], 2), "porch_height_m": round(b.get("porch_top", 0) - b["ground"], 2) if b["porch"] else 0,
            "rear_depth_m": round(b["rear"], 2), "rear_height_m": round(b.get("rear_top", 0) - b["ground"], 2) if b["rear"] else 0,
            "lidar_points": b["pts"], "flags": b["flags"],
        }
        feats.append({"type": "Feature", "properties": props,
                      "geometry": mapping(shapely.set_precision(b["ll"], 1e-7))})
    with open(C.BUILDINGS_GEOJSON, "w") as f:
        json.dump({"type": "FeatureCollection",
                   "attribution": "Footprints © OpenStreetMap contributors (ODbL); heights from USGS 3DEP LiDAR " + C.LIDAR_PROJECT,
                   "features": feats}, f, indent=1)
    with open(C.AREA_GEOJSON, "w") as f:
        json.dump({"type": "Feature", "properties": {"name": C.AREA, "origin_lonlat": o_ll},
                   "geometry": mapping(shapely.set_precision(area_ll, 1e-7))}, f, indent=1)

    hts = np.array([b["main"] - b["ground"] for b in site_b])
    porch = np.array([b["porch"] > 0 for b in site_b])
    report = {
        "buildings": {"core": sum(b["zone"] == "core" for b in bld), "site_edge": sum(b["zone"] == "site" for b in bld),
                      "context": sum(b["zone"] == "context" for b in bld)},
        "row_objects": sum(o.name.startswith(("Row_", "Bldg_")) for o in objects), "osm_lidar_shift_m": [sx, sy], "overlap_before_after": [round(iou0, 3), round(best[2], 3)],
        "site_height_m": {"p10": round(float(np.percentile(hts, 10)), 2), "median": round(float(np.median(hts)), 2),
                          "p90": round(float(np.percentile(hts, 90)), 2), "max": round(float(hts.max()), 2)},
        "site_with_porch": int(porch.sum()), "archetypes": arch_count, "flags": flags_count, "trees": len(trees), "triangles": tris,
        "zone_m2": zone_area, "lidar_classes": hist, "origin_elevation_m": round(y0, 2),
        "porch_detail": dict(kits.BUILD_STATS), "terrain_smoothing": terrain_adjustment,
        "vegetation": vegetation_report, "construction_audit": construction_audit,
    }
    with open(C.REPORT_JSON, "w") as f:
        json.dump(report, f, indent=1)
    log(f"wrote {C.GEOM_JSON} ({os.path.getsize(C.GEOM_JSON) / 1e6:.1f} MB, {tris:,} tris)")
    log("report " + json.dumps(report))


if __name__ == "__main__":
    main()
