"""Engineered street surfaces and deterministic building/carriageway separation.

The survey remains the terrain reference away from streets. Inside the paved
corridor a shared road profile replaces raw lateral hillside slope; every ground,
curb, building footing and runtime anchor samples this same continuous function.
"""
import math
import numpy as np
import shapely
from scipy import ndimage
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import unary_union


class EngineeredHeight:
    def __init__(self, roads, surveyed_height, max_grade=0.06, crossfall=0.015):
        self.surveyed_height = surveyed_height
        self.max_grade, self.crossfall = max_grade, crossfall
        positions, levels, node_ids, segments, road_ids, widths, sidewalks = [], [], {}, [], [], [], []
        self.lines = []
        for road_id, (line, width, sidewalk, name) in enumerate(roads):
            xy = np.asarray(shapely.segmentize(line, 5.0).coords, float)
            if len(xy) < 2:
                continue
            z = ndimage.gaussian_filter1d(surveyed_height(xy[:, 0], xy[:, 1]), 1.1, mode="nearest")
            ids = []
            for point, elevation in zip(xy, z):
                key = tuple(np.round(point, 3))
                if key not in node_ids:
                    node_ids[key] = len(positions)
                    positions.append(point)
                    levels.append([])
                index = node_ids[key]
                levels[index].append(float(elevation))
                ids.append(index)
            self.lines.append((xy, ids, width, sidewalk, name))
            for a, b in zip(ids, ids[1:]):
                if a != b:
                    segments.append((a, b)); road_ids.append(road_id)
                    widths.append(width); sidewalks.append(sidewalk)
        self.xy = np.asarray(positions, float)
        self.z = np.asarray([np.mean(values) for values in levels])
        self.edges = np.asarray(segments, np.int64)
        self.a, self.b = self.xy[self.edges[:, 0]], self.xy[self.edges[:, 1]]
        self.direction = self.b - self.a
        self.length = np.linalg.norm(self.direction, axis=1)
        # Two shortest-path envelopes enforce a global Lipschitz bound on
        # arbitrarily long slopes. Local relaxation cannot converge promptly
        # on a long hill. Their midpoint preserves broad surveyed elevation.
        count = len(self.z)
        # Nearby carriageways can be distinct OSM ways without sharing a
        # vertex. Constrain their relative height too, or blending two valid
        # 6% profiles can still create a steep cross-street ridge.
        neighbor_pairs = cKDTree(self.xy).query_pairs(24.0, output_type="ndarray")
        constraint_edges = np.unique(np.sort(np.vstack([self.edges, neighbor_pairs]), axis=1), axis=0)
        edge_a, edge_b = constraint_edges[:, 0], constraint_edges[:, 1]
        constraint_length = np.linalg.norm(self.xy[edge_b] - self.xy[edge_a], axis=1)
        def lower_envelope(values):
            floor = float(values.min())
            rows = np.concatenate([edge_a, edge_b, np.full(count, count)])
            cols = np.concatenate([edge_b, edge_a, np.arange(count)])
            costs = np.concatenate([max_grade * constraint_length, max_grade * constraint_length, values - floor + 1e-8])
            graph = coo_matrix((costs, (rows, cols)), shape=(count + 1, count + 1)).tocsr()
            return dijkstra(graph, indices=count, directed=True)[:count] + floor - 1e-8
        self.z = (lower_envelope(self.z) - lower_envelope(-self.z)) * 0.5
        self.half = np.asarray(widths) * 0.5
        self.sidewalk = np.asarray(sidewalks)
        self.road_ids = np.asarray(road_ids)
        self.tree = cKDTree((self.a + self.b) * 0.5)
        degree = np.bincount(self.edges.ravel(), minlength=count)
        junctions = np.flatnonzero(degree >= 3)
        self.junction_xy = self.xy[junctions]
        self.junction_z = self.z[junctions]
        self.junction_gradient = []
        self.junction_inner = []
        for node in junctions:
            adjacent_edges = np.flatnonzero(np.any(self.edges == node, axis=1))
            neighbors = self.edges[adjacent_edges].ravel()
            neighbors = neighbors[neighbors != node]
            gradient = np.linalg.lstsq(self.xy[neighbors] - self.xy[node], self.z[neighbors] - self.z[node], rcond=None)[0]
            magnitude = np.linalg.norm(gradient)
            if magnitude > max_grade: gradient *= max_grade / magnitude
            self.junction_gradient.append(gradient)
            self.junction_inner.append(float(np.max(self.half[adjacent_edges] + self.sidewalk[adjacent_edges])) + 2.0)
        self.junction_gradient = np.asarray(self.junction_gradient)
        self.junction_inner = np.asarray(self.junction_inner)
        self.junction_tree = cKDTree(self.junction_xy) if len(junctions) else None

    def build_surface_field(self, bounds, road_surface, spacing=1.0):
        """A continuous triangular field with bounded paved-surface gradients.

        Road profile bounds alone do not bound an intersection blend. Project
        the final paved field onto per-axis 4.5% constraints, including a 3m
        apron. This limits any direction to 6.37%, while preserving ordinary
        1.5% sidewalk crossfall wherever it already satisfies the constraints.
        """
        x0, y0, x1, y1 = bounds
        self.field_x0, self.field_y0 = np.floor(x0) - 2, np.floor(y0) - 2
        self.field_spacing = spacing
        xs = np.arange(self.field_x0, np.ceil(x1) + 3, spacing)
        ys = np.arange(self.field_y0, np.ceil(y1) + 3, spacing)
        xx, yy = np.meshgrid(xs, ys)
        values = self(xx.ravel(), yy.ravel()).reshape(xx.shape)
        apron = road_surface.buffer(float(self.sidewalk.max()) + 3.0)
        active = shapely.contains_xy(apron, xx, yy)
        ids = np.full(active.shape, -1, np.int32)
        ids[active] = np.arange(int(active.sum()), dtype=np.int32)
        edges_a, edges_b, edge_costs = [], [], []
        point_xy = np.column_stack([xx[active], yy[active]])
        for left, right in ((ids[:, :-1], ids[:, 1:]), (ids[:-1, :], ids[1:, :]),
                            (ids[:-1, :-1], ids[1:, 1:]), (ids[1:, :-1], ids[:-1, 1:])):
            valid = (left >= 0) & (right >= 0)
            ia, ib = left[valid], right[valid]
            delta = point_xy[ib] - point_xy[ia]
            _, segment = self.tree.query((point_xy[ia] + point_xy[ib]) * 0.5)
            tangent = self.direction[segment] / self.length[segment, None]
            along = np.abs(np.sum(delta * tangent, axis=1))
            across = np.abs(delta[:, 0] * tangent[:, 1] - delta[:, 1] * tangent[:, 0])
            # Eight grid directions constrain both street-aligned and diagonal
            # crossfall, with a conservative universal component bound.
            cost = np.minimum(0.045 * np.abs(delta).sum(axis=1), 0.045 * along + 0.018 * across)
            edges_a.append(ia); edges_b.append(ib); edge_costs.append(cost)
        aa, bb = np.concatenate(edges_a), np.concatenate(edges_b)
        count = int(active.sum())
        rows = np.concatenate([aa, bb, np.full(count, count)])
        cols = np.concatenate([bb, aa, np.arange(count)])
        one_way_cost = np.concatenate(edge_costs)
        edge_cost = np.concatenate([one_way_cost, one_way_cost])
        def envelope(z):
            floor = float(z.min())
            costs = np.concatenate([edge_cost, z - floor + 1e-8])
            graph = coo_matrix((costs, (rows, cols)), shape=(count + 1, count + 1)).tocsr()
            return dijkstra(graph, indices=count, directed=True)[:count] + floor - 1e-8
        before = values[active]
        projected = (envelope(before) - envelope(-before)) * 0.5
        correction = np.zeros(values.shape)
        correction[active] = projected - before
        distance, nearest = ndimage.distance_transform_edt(~active, return_indices=True)
        influence = np.clip(1 - distance * spacing / 20.0, 0, 1)
        influence = influence * influence * (3 - 2 * influence)
        values += correction[nearest[0], nearest[1]] * influence
        self.field_audit = {"spacing_m": spacing, "paved_nodes": count, "max_axis_grade": 0.045,
                            "max_direction_grade_bound": float(np.sqrt(2) * 0.045), "cross_street_constraint": 0.018,
                            "max_projection_adjustment_m": float(np.max(np.abs(values[active] - before)))}
        self.surface_field = values

    def __call__(self, x, y):
        if hasattr(self, "surface_field"):
            x, y = np.broadcast_arrays(np.asarray(x, float), np.asarray(y, float))
            fx = np.clip((x.ravel() - self.field_x0) / self.field_spacing, 0, self.surface_field.shape[1] - 1.000001)
            fy = np.clip((y.ravel() - self.field_y0) / self.field_spacing, 0, self.surface_field.shape[0] - 1.000001)
            ix, iy = fx.astype(np.int64), fy.astype(np.int64)
            fx, fy = fx - ix, fy - iy
            z00, z10 = self.surface_field[iy, ix], self.surface_field[iy, ix + 1]
            z01, z11 = self.surface_field[iy + 1, ix], self.surface_field[iy + 1, ix + 1]
            value = np.where(fx >= fy, z00 + fx * (z10 - z00) + fy * (z11 - z10),
                             z00 + fx * (z11 - z01) + fy * (z01 - z00))
            return value.reshape(x.shape)
        x, y = np.broadcast_arrays(np.asarray(x, float), np.asarray(y, float))
        shape = x.shape
        points = np.column_stack([x.ravel(), y.ravel()])
        result = np.empty(len(points))
        for start in range(0, len(points), 32768):
            p = points[start:start + 32768]
            raw = self.surveyed_height(p[:, 0], p[:, 1])
            _, choices = self.tree.query(p, k=min(12, len(self.a)))
            if choices.ndim == 1:
                choices = choices[:, None]
            a, direction = self.a[choices], self.direction[choices]
            t = np.clip(np.sum((p[:, None, :] - a) * direction, axis=2) / self.length[choices] ** 2, 0, 1)
            nearest = a + direction * t[..., None]
            distance = np.linalg.norm(p[:, None, :] - nearest, axis=2)
            # Keep the closest segment of each road. Otherwise endpoints on a
            # dense polyline would flatten the longitudinal grade unequally.
            valid = np.ones_like(distance, bool)
            ids = self.road_ids[choices]
            for i in range(choices.shape[1]):
                for j in range(i):
                    same = ids[:, i] == ids[:, j]
                    valid[:, i] &= ~(same & (distance[:, j] <= distance[:, i]))
                    valid[:, j] &= ~(same & (distance[:, i] < distance[:, j]))
            half, walk = self.half[choices], self.sidewalk[choices]
            paved = half + walk
            center = self.z[self.edges[choices, 0]] * (1 - t) + self.z[self.edges[choices, 1]] * t
            profile = center - np.minimum(distance, half) * self.crossfall + np.maximum(distance - half, 0) * self.crossfall
            # Blend only at junctions. Away from other roads the crossfall is
            # exactly 1.5%, and the curb adds its separate 15cm vertical rise.
            weight = np.maximum(0, 1 - distance / (paved + 1.5)) ** 3 * valid
            total = weight.sum(axis=1)
            graded = (profile * weight).sum(axis=1) / np.maximum(total, 1e-9)
            best = np.argmin(np.where(valid, distance - paved, np.inf), axis=1)
            gap = np.maximum(0, (distance - paved)[np.arange(len(p)), best])
            blend = np.clip(1 - gap / 10.0, 0, 1)
            blend = blend * blend * (3 - 2 * blend)
            # Beyond the weighted corridor use the nearest road's continuation
            # for the transition, rather than interpolating toward zero height.
            graded = np.where(total > 1e-8, graded, profile[np.arange(len(p)), best])
            if self.junction_tree is not None:
                jd, ji = self.junction_tree.query(p)
                plane = self.junction_z[ji] + np.sum((p - self.junction_xy[ji]) * self.junction_gradient[ji], axis=1)
                strength = np.clip(1 - (jd - self.junction_inner[ji]) / 16.0, 0, 1)
                strength = strength * strength * (3 - 2 * strength)
                graded = graded * (1 - strength) + plane * strength
            result[start:start + len(p)] = raw * (1 - blend) + graded * blend
        return result.reshape(shape)

    def audit(self):
        longitudinal = np.abs(self.z[self.edges[:, 1]] - self.z[self.edges[:, 0]]) / self.length
        return {"profile_nodes": len(self.xy), "profile_segments": len(self.edges),
                "max_profile_grade": round(float(longitudinal.max()), 6),
                "p95_profile_grade": round(float(np.percentile(longitudinal, 95)), 6),
                "target_max_longitudinal_grade": self.max_grade, "sidewalk_crossfall": self.crossfall,
                "road_crown_crossfall": self.crossfall, "terrain_blend_width_m": 10.0, "junction_planes": len(self.junction_xy), "neighbor_profile_constraint_radius_m": 24.0, "surface_field": getattr(self, "field_audit", {})}


def repair_footprints(buildings, roads, margin=0.35):
    road_surface = unary_union([line.buffer(width * 0.5, quad_segs=4) for line, width, _, _ in roads])
    forbidden = road_surface.buffer(margin, quad_segs=2)
    repaired, changed, removed, lost_area = [], [], [], 0.0
    for building in buildings:
        original = building["poly"]
        if not original.intersects(forbidden):
            repaired.append(building)
            continue
        parts = [p for p in shapely.get_parts(original.difference(forbidden)) if p.geom_type == "Polygon" and p.area >= 8.0]
        if not parts:
            removed.append(building["id"]); lost_area += original.area
            continue
        fixed = max(parts, key=lambda p: p.area)
        if fixed.area < max(8.0, original.area * 0.20):
            removed.append(building["id"]); lost_area += original.area
            continue
        changed.append({"id": building["id"], "before_m2": round(original.area, 3), "after_m2": round(fixed.area, 3)})
        lost_area += original.area - fixed.area
        building["poly"] = fixed
        building["road_clearance_repaired"] = True
        repaired.append(building)
    remaining = sum(b["poly"].intersection(road_surface).area for b in repaired)
    return repaired, road_surface, {"margin_m": margin, "trimmed": changed, "removed": removed,
                                   "removed_overlap_area_m2": round(lost_area, 3), "remaining_footprint_overlap_m2": round(remaining, 8)}


def urban_yards(buildings, protected, roads, sidewalks, alleys, lots, site):
    """Paved service yards and narrow gaps, without paving surveyed parks/gardens."""
    envelope = buildings.buffer(4.5, join_style="mitre")
    excluded = unary_union([buildings, protected.buffer(0.4), roads, sidewalks, alleys, lots])
    return envelope.difference(excluded).intersection(site)


BUSINESSES = [
    ("Juniper Spirits", "liquor", "WINE  /  BEER  /  SPIRITS"),
    ("Blue Basket Laundry", "laundromat", "SELF SERVICE  /  WASH & FOLD"),
    ("Northside Clippers", "barber", "BARBER SHOP"),
    ("Maple Kitchen", "takeout", "HOT FOOD  /  TAKEOUT"),
    ("Everyday Market", "market", "GROCERIES  /  HOUSEHOLD"),
    ("Corner Pantry", "market", "MILK  /  BREAD  /  PRODUCE"),
    ("York Bottle Shop", "liquor", "WINE  /  BEER  /  SPIRITS"),
    ("Spin Cycle", "laundromat", "COIN LAUNDRY"),
    ("Cedar Barber", "barber", "CUTS  /  SHAVES"),
    ("Warm Plate", "takeout", "LUNCH  /  DINNER  /  TAKEOUT"),
    ("Hilltop Foods", "market", "NEIGHBORHOOD GROCER"),
    ("Mend & Stitch", "tailor", "ALTERATIONS  /  REPAIRS"),
    ("Parkway Spirits", "liquor", "WINE  /  BEER"),
    ("Fresh Fold", "laundromat", "LAUNDRY  /  WASH & FOLD"),
    ("Elm Street Barber", "barber", "WALK INS WELCOME"),
    ("Little Skillet", "takeout", "BREAKFAST  /  TAKEOUT"),
    ("Common Shelf", "market", "PANTRY  /  DAILY GOODS"),
    ("Second Chapter", "books", "USED BOOKS  /  STATIONERY"),
]


def assign_businesses(buildings, roads, height, exposed):
    """Select complete, clear, porch-free ground floors before any facade kit runs."""
    import kits
    candidates = []
    for b in buildings:
        if b["arch"] not in ("storefront", "row", "detached") or b["porch"] > 0.01: continue
        main = kits._main_poly(b)
        if main is None or b["n"] is None: continue
        n = b["n"]; c = np.array(main.centroid.coords[0])
        faces = []
        for p0, p1 in kits._edges(main):
            w = kits.Wall(p0, p1)
            if w.L >= 4.0 and w.b @ n > 0.85:
                faces.append((float((w.at(w.L / 2) - c) @ n), w))
        if not faces: continue
        w = max(faces, key=lambda v: (round(v[0], 1), v[1].L))[1]
        if w.L > 24: continue
        front = w.at(w.L / 2, 0.4)
        if not all(exposed(w.at(u, d)) for u in (0.7, w.L / 2, w.L - 0.7) for d in (0.5, 1.5)): continue
        g = float(height(front[0], front[1]))
        eave = float(b["roof_at"](np.array([w.at(0.05), w.at(w.L - 0.05)])).min())
        if eave - g < 4.6: continue
        road_dist = min(line.distance(Point(front)) - width / 2 for line, width, _, _ in roads)
        if road_dist < 1.65 or road_dist > 22: continue
        candidates.append((b, front, b["arch"] == "storefront", [w.p0.tolist(), w.at(w.L).tolist()]))
    selected = []
    # Existing commercial corridor first; remaining shops expand local coverage.
    while candidates and len(selected) < len(BUSINESSES):
        def score(item):
            if not selected: return (item[2], -abs(item[1][1]))
            spread = min(np.linalg.norm(item[1] - v[1]) for v in selected)
            return ((item[2] and len(selected) < 10), spread)
        best = max(candidates, key=score)
        selected.append(best); candidates = [item for item in candidates if item is not best]
    for b in buildings:
        if b["arch"] == "storefront": b["arch"] = "row"
    for (b, front, old_shop, front_edge), (name, kind, subtitle) in zip(selected, BUSINESSES):
        b["arch"] = "storefront"
        b["business"] = {"name": name, "type": kind, "subtitle": subtitle, "front_edge": front_edge}
        b["style"].update(trim="trim_cream", door="door_black", sign={"liquor":"sign_navy", "laundromat":"sign_navy", "barber":"sign_red", "takeout":"sign_red"}.get(kind,"sign_green"),
                           awning={"liquor":None, "laundromat":"awning_white", "barber":"awning_red", "takeout":"awning_red"}.get(kind,"awning_green"))
    return {"target": len(BUSINESSES), "selected": len(selected), "porch_fronts_selected": 0,
            "selection": "Complete porch-free ground floors; original corridor plus geographically spread local shops"}


def sidewalk_grade_audit(roads, height, sidewalks):
    cross_a, cross_b, along_a, along_b = [], [], [], []
    for line, width, sw, _ in roads:
        for distance in np.arange(3, line.length - 3, 5):
            mid = line.interpolate(distance)
            before, after = line.interpolate(distance - 0.5), line.interpolate(distance + 0.5)
            tangent = np.array([after.x - before.x, after.y - before.y]); tangent /= max(np.linalg.norm(tangent), 1e-9)
            normal = np.array([-tangent[1], tangent[0]])
            for sign in (-1, 1):
                xy = np.array([mid.x, mid.y]) + normal * sign * (width / 2 + sw / 2)
                pa, pb = xy - normal * 0.4, xy + normal * 0.4
                if not sidewalks.covers(LineString([pa, pb])): continue
                cross_a.append(pa); cross_b.append(pb)
                along_a.append(xy - tangent * 0.4); along_b.append(xy + tangent * 0.4)
    if not cross_a: return {"sample_count": 0}
    def grade(a, b):
        a, b = np.asarray(a), np.asarray(b)
        return np.abs(height(b[:, 0], b[:, 1]) - height(a[:, 0], a[:, 1])) / 0.8
    lateral, longitudinal = grade(cross_a, cross_b), grade(along_a, along_b)
    return {"sample_count": len(lateral), "max_crossfall": float(lateral.max()),
            "p95_crossfall": float(np.percentile(lateral, 95)),
            "max_longitudinal_grade": float(longitudinal.max()),
            "p95_longitudinal_grade": float(np.percentile(longitudinal, 95))}


def ensure_rear_headroom(buildings, height):
    """Give rear service additions usable local headroom before prism generation.

    Survey roof splits sometimes leave a 2.4m addition above the median house
    footing, but an uphill rear yard reduces the actual doorway wall to 2m.
    Raise the entire addition wall and roof coherently, below the main eave.
    """
    changes = []
    for b in buildings:
        if b.get("arch") not in ("row", "row_porch", "detached", "detached_porch") or b.get("rear", 0) <= 0: continue
        rear_parts = [geom for kind, geom, fn in b["pieces"] if kind == "rear"]
        if not rear_parts: continue
        rear = shapely.union_all(rear_parts)
        boundary = shapely.segmentize(rear.buffer(0.85).boundary, 0.75)
        xy = shapely.get_coordinates(boundary)
        local_ground = float(np.max(height(xy[:, 0], xy[:, 1])))
        target = min(local_ground + 2.55, b["eave"] - 0.30)
        previous = b["rear_top"]
        if target <= previous + 0.01: continue
        b["rear_top"] = target
        b["pieces"] = [(kind, geom, (lambda points, z=target: np.full(len(points), z)) if kind == "rear" else fn)
                       for kind, geom, fn in b["pieces"]]
        changes.append({"building_id": b["id"], "roof_raise_m": round(target - previous, 4),
                        "minimum_local_wall_height_m": round(target - local_ground, 4)})
    return {"adjusted_additions": len(changes), "changes": changes}


def rebase_roof_returns(roof_returns, surveyed_ground, graded_ground):
    """Translate a surveyed building rigidly with its newly graded footing.

    Roof fitting and porch detection must see the same above-ground profile
    after a grade change. Moving only the footing changes measured storeys,
    erases low porch roofs and triggers artificial minimum-height clamps.
    """
    return np.asarray(roof_returns, dtype=np.float64) + (graded_ground - surveyed_ground)
