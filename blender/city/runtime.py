"""Small Godot map/placement metadata derived from the same geometry as the city.

Called by process.py; never parses the rendered GLB or invents flat ground heights.
All exported positions are Godot metres: east, up, south. Prop placements are
art direction, not claims that a particular real-world fixture exists there.
"""
import json
import heapq
import math
import os

import numpy as np
import shapely
from shapely.geometry import LineString, MultiPoint, Point
from shapely.ops import nearest_points, unary_union

import config as C


def low_building_obstacles(meshes, height, corridor):
    """Project the actual lower facades and kit parts, including projecting steps.

    Mesh-builder coordinates are east/north/absolute elevation. Clip each nearby
    triangle against ground-relative -0.5..2 m before projecting, so roofs and
    high cornices cannot block a walking path underneath them.
    """
    def clip(points, limit, above):
        result = []
        for a, b in zip(points, points[1:] + points[:1]):
            inside_a = a[3] >= limit if above else a[3] <= limit
            inside_b = b[3] >= limit if above else b[3] <= limit
            if inside_a:
                result.append(a)
            if inside_a != inside_b:
                result.append(a + (b - a) * ((limit - a[3]) / (b[3] - a[3])))
        return result

    bounds = corridor.bounds
    projected = []
    for mesh in meshes:
        if not mesh.name.startswith(("Row_", "Bldg_")) or not mesh.tris:
            continue
        triangles = np.concatenate(mesh.tris)
        lo, hi = triangles[:, :, :2].min(axis=1), triangles[:, :, :2].max(axis=1)
        triangles = triangles[(hi[:, 0] >= bounds[0]) & (lo[:, 0] <= bounds[2])
                              & (hi[:, 1] >= bounds[1]) & (lo[:, 1] <= bounds[3])]
        if not len(triangles):
            continue
        flat = triangles.reshape(-1, 3)
        above_ground = (flat[:, 2] - height(flat[:, 0], flat[:, 1])).reshape(-1, 3)
        nearby = (above_ground.min(axis=1) <= 2.0) & (above_ground.max(axis=1) >= -0.5)
        for tri, hag in zip(triangles[nearby], above_ground[nearby]):
            vertices = list(np.column_stack([tri, hag]))
            clipped = clip(clip(vertices, -0.5, True), 2.0, False)
            if clipped:
                shape = MultiPoint(np.array(clipped)[:, :2]).convex_hull
                if shape.intersects(corridor):
                    projected.append(shape)
    return unary_union(projected), len(projected)


def sidewalk_route(start, end, sidewalks, roads, footprints):
    """Find a continuous, clearance-checked walk, preferring sidewalks to crossings.

    A fine local grid is cheap for each one-block leg. Every connecting segment is
    checked too: safe samples alone can jump across a projecting porch footprint.
    """
    free = unary_union([sidewalks, roads]).difference(footprints.buffer(0.5))
    xmin, ymin = min(start.x, end.x) - 12, min(start.y, end.y) - 12
    xmax, ymax = max(start.x, end.x) + 12, max(start.y, end.y) + 12
    step = 0.5
    xs, ys = np.arange(xmin, xmax, step), np.arange(ymin, ymax, step)
    xx, yy = np.meshgrid(xs, ys)
    available = shapely.contains_xy(free, xx, yy)
    on_walk = shapely.contains_xy(sidewalks.buffer(-0.2), xx, yy)

    def point(key):
        return Point(xs[key[0]], ys[key[1]])

    def closest(endpoint):
        candidates = np.argwhere(available)
        distances = (xs[candidates[:, 1]] - endpoint.x) ** 2 + (ys[candidates[:, 0]] - endpoint.y) ** 2
        for i in np.argsort(distances)[:30]:
            j, k = candidates[i]
            key = (int(k), int(j))
            if free.covers(LineString([endpoint, point(key)])):
                return key
        raise ValueError("Cannot connect a landmark to the walking route")

    first, last = closest(start), closest(end)
    frontier = [(0, first)]
    cost, previous = {first: 0.0}, {}
    while frontier:
        _, current = heapq.heappop(frontier)
        if current == last:
            keys = [last]
            while keys[-1] != first:
                keys.append(previous[keys[-1]])
            points = [start] + [point(key) for key in reversed(keys)] + [end]
            route = LineString(points)
            if route.distance(footprints) < 0.499:
                raise ValueError("Walking route clips a building")
            return [Point(p) for p in route.simplify(0.015).coords]
        for dx, dy in ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)):
            nxt = (current[0] + dx, current[1] + dy)
            i, j = nxt
            if not (0 <= i < len(xs) and 0 <= j < len(ys) and available[j, i]):
                continue
            length = step * math.hypot(dx, dy)
            value = cost[current] + length * (1 if on_walk[j, i] else 5)
            if value >= cost.get(nxt, math.inf):
                continue
            if not free.covers(LineString([point(current), point(nxt)])):
                continue
            cost[nxt], previous[nxt] = value, current
            heuristic = math.hypot(i - last[0], j - last[1]) * step
            heapq.heappush(frontier, (value + heuristic, nxt))
    raise ValueError("No safe continuous walking route between landmarks")


def export(cw, buildings, area, site, context, zones, height, origin_y, origin_ll, building_meshes, parks=None, construction_audit=None):
    def position(x, north, lift=0.0):
        return [round(float(x), 3),
                round(float(height(np.array([x]), np.array([north]))[0]) - origin_y + lift, 3),
                round(float(-north), 3)]

    def street(name):
        lines = [line for line, _, _, nm in cw if nm == name]
        if not lines:
            raise ValueError(f"Missing runtime landmark street: {name}")
        return unary_union(lines)

    # Limit triangle processing to the walk's street corridor and the extra
    # Greenmount landmark. Other parts of the city keep their OSM footprints.
    corridor = street("Old York Road").intersection(site).buffer(25).union(
        street("Greenmount Avenue").intersection(street("Wyanoke Avenue")).buffer(25))
    low_geometry, kit_triangle_count = low_building_obstacles(building_meshes, height, corridor)
    footprints = unary_union([b["poly"] for b in buildings])
    obstacles = unary_union([footprints, low_geometry])
    # Spawn, landmarks and fixture bases also clear the actual projecting kits.
    walkable = zones["sidewalk"].buffer(-0.45).difference(obstacles.buffer(1.25))
    if walkable.is_empty:
        raise ValueError("No safe sidewalk space for runtime spawn")

    def safe_near(point, region=walkable):
        result = point if region.covers(point) else nearest_points(point, region)[1]
        if result.distance(point) > 25:
            raise ValueError("Runtime placement is too far from its intended street")
        # Rounded JSON coordinates must remain in the generous underlying zone.
        if not zones["sidewalk"].covers(result) or result.distance(obstacles) < 1.2:
            raise ValueError("Unsafe sidewalk placement")
        return result

    specs = [
        ("old_york_wyanoke", "Old York & Wyanoke", "Old York Road", "Wyanoke Avenue",
         "Begin at the neighborhood crossroads, beside the porch-front rows."),
        ("old_york_dumbarton", "Dumbarton Corner", "Old York Road", "Dumbarton Avenue",
         "Follow Old York Road north to Dumbarton Avenue."),
        ("old_york_rose_hill", "Rose Hill Terrace", "Old York Road", "Rose Hill Terrace",
         "A quiet side street meets Old York Road beside the rowhouses."),
        ("old_york_cator", "Cator Avenue", "Old York Road", "Cator Avenue",
         "The north end of this neighborhood walk, at Cator Avenue."),
        ("greenmount_wyanoke", "Greenmount & Wyanoke", "Greenmount Avenue", "Wyanoke Avenue",
         "Explore west along Wyanoke Avenue to the Greenmount corridor."),
    ]
    landmarks, corners = [], []
    for key, label, a, b, description in specs:
        hit = street(a).intersection(street(b))
        points = [p for p in getattr(hit, "geoms", [hit]) if p.geom_type == "Point"]
        if not points:
            raise ValueError(f"Landmark streets do not intersect: {a}, {b}")
        cross = min(points, key=lambda p: p.distance(area.centroid))
        # Consistent west/north corner, clear of both intersecting carriageways.
        corner = safe_near(Point(cross.x - 7.5, cross.y + 8.0))
        corners.append((corner, cross, a, b))
        landmarks.append({"id": key, "label": label, "position": position(corner.x, corner.y, 0.15),
                          "description": description, "streets": [a, b]})

    first = corners[0][0]
    spawn_point = safe_near(Point(first.x, first.y - 18))
    if spawn_point.distance(first) < 8:
        raise ValueError("Spawn overlaps the first landmark trigger")
    # This game's player faces +Z at yaw=0. This walk starts northward.
    spawn = {"position": position(spawn_point.x, spawn_point.y, 0.15), "yaw": math.pi}

    roads = []
    for line, width, sidewalk_width, name in cw:
        clipped = line.intersection(site)
        for part in getattr(clipped, "geoms", [clipped]):
            if part.geom_type != "LineString" or part.length < 1:
                continue
            sampled = shapely.segmentize(part, 12)
            roads.append({"name": name, "width": width, "sidewalk_width": sidewalk_width,
                          "points": [position(x, n) for x, n in sampled.coords]})

    # Route prefers sidewalks, using the actual road surface for crossings.
    route_points = [spawn["position"]]
    for index in range(4):
        target = corners[index][0]
        previous = spawn_point if index == 0 else corners[index - 1][0]
        leg = sidewalk_route(previous, target, zones["sidewalk"], zones["road"], obstacles)
        # Keep heights terrain-following even after simplifying straight runs.
        sampled = shapely.segmentize(LineString(leg), 2)
        for xy in list(sampled.coords)[1:]:
            p = Point(xy)
            lift = 0.15 if zones["sidewalk"].covers(p) else 0.0
            route_points.append(position(p.x, p.y, lift))

    dressing = []
    used = [spawn_point] + [item[0] for item in corners]
    route_line = LineString([(p[0], -p[2]) for p in route_points])
    if route_line.distance(obstacles) < 0.48:
        raise ValueError("Rounded walking route clips a lower building kit")
    prop_space = walkable.intersection(zones["road"].buffer(0.7)).difference(zones["road"].buffer(0.5))

    def add_prop(kind, desired, yaw=0.0, **extra):
        if prop_space.is_empty:
            return
        p = safe_near(desired, prop_space)
        # Keep the sidewalk center free: place against its street-facing edge.
        if any(p.distance(q) < 2.8 for q in used):
            return
        if p.distance(obstacles) < 1.249 or p.distance(zones["road"]) < 0.44:
            return
        if p.distance(route_line) < 0.9:
            return
        used.append(p)
        dressing.append({"kind": kind, "position": position(p.x, p.y, 0.15),
                         "yaw": yaw, **extra})

    for corner, cross, a, b in corners:
        add_prop("street_sign", Point(corner.x, corner.y + 4), yaw=math.pi / 2, street_names=[a, b])
        add_prop("hydrant", Point(corner.x, corner.y + 9))
    start, end = corners[0][0], corners[3][0]
    for i, north in enumerate(np.arange(start.y + 18, end.y - 5, 22)):
        f = (north - start.y) / (end.y - start.y)
        east = start.x + f * (end.x - start.x)
        add_prop("lamp" if i % 3 != 1 else "bin", Point(east + 0.45, north), yaw=math.pi / 2)

    minx, minn, maxx, maxn = context.bounds
    sample = np.array([position(x, n) for x in np.arange(minx, maxx, 12)
                       for n in np.arange(minn, maxn, 12) if context.covers(Point(x, n))])
    def actual(xyz):
        return [round(float(xyz[0]), 4), round(float(xyz[2]) - origin_y, 4), round(-float(xyz[1]), 4)]
    def normal(xy):
        return [round(float(xy[0]), 6), 0.0, round(-float(xy[1]), 6)]
    business_records, rear_records, stair_records, facade_records = [], [], [], []
    for b in buildings:
        common = {"building_id": b["id"], "source_mesh": b.get("object", "")}
        bay = b.get("upper_bay")
        if bay:
            facade_records.append({**common, "kind": "upper_bay", "street": b.get("tags", {}).get("addr:street", ""),
                                   "family": bay.get("family", "rose_hill"),
                                   "position": actual(bay["xyz"]), "normal": normal(bay["normal_xy"]),
                                   "width_m": round(bay["width_m"], 3), "depth_m": bay["depth_m"],
                                   "base_y": round(bay["base_z"] - origin_y, 4),
                                   "top_y": round(bay["top_z"] - origin_y, 4), "variant": bay["variant"],
                                   "storey_height_m": round(bay["storey_height_m"], 4),
                                   "porch_clearance_m": round(bay["porch_clearance_m"], 4)})
        shop = b.get("business", {})
        if "sign_xyz" in shop:
            business_records.append({**common, "name": shop["name"], "type": shop["type"], "subtitle": shop["subtitle"],
                                     "sign_position": actual(shop["sign_xyz"]), "front_position": actual(shop["sign_xyz"]),
                                     "door_position": actual(shop["door_xyz"]), "sign_width": round(shop["sign_width"], 3),
                                     "normal": normal(shop["normal_xy"])})
            if shop.get("kit"):
                # Neighborhood shop kits: built geometry only; runtime adds the sign text.
                business_records[-1].update(kit=shop["kit"], storeys=shop["storeys"], entry=shop["entry"],
                                            sign_text_color=shop["sign_text_color"], parapet=bool(shop["parapet"]))
        rear = b.get("rear_door")
        if rear:
            rear_records.append({**common, "position": actual(rear["xyz"]), "normal": normal(rear["normal_xy"])})
        stair = b.get("porch_stair")
        if stair and stair.get("geometry_complete", True):
            stair_records.append({**common, "landing": actual(stair["landing_xyz"]), "approach": actual(stair["approach_xyz"]),
                                  "normal": normal(stair["normal_xy"]), "riser_m": round(stair["riser"], 5),
                                  "tread_m": round(stair["tread"], 5), "width_m": 1.25})
    park_records = [{"name": p["name"], "kind": p["kind"], "area_m2": round(p["poly"].area, 2),
                     "polygon": [position(x, n, 0.10) for x, n in p["poly"].exterior.coords],
                     "holes": [[position(x, n, 0.10) for x, n in ring.coords] for ring in p["poly"].interiors]} for p in (parks or [])]
    payload = {
        "schema_version": 1, "area": "Pen Lucy, Baltimore",
        "coordinate_system": "metres; x east, y up, z south; yaw radians (0 faces +Z/south, PI north)",
        "origin_lonlat": list(origin_ll), "origin_elevation_m": round(origin_y, 4),
        "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP (public domain)",
        "spawn": spawn, "landmarks": landmarks, "roads": roads,
        "route": {"landmark_ids": [x["id"] for x in landmarks[:4]], "points": route_points,
                  "obstacle_clearance_m": round(route_line.distance(obstacles), 4),
                  "low_building_triangles_checked": kit_triangle_count},
        "site_boundary": [position(x, n) for x, n in site.exterior.coords],
        "area_boundary": [position(x, n) for x, n in area.exterior.coords],
        "terrain_extent": {"min": [round(minx, 3), float(sample[:, 1].min()), round(-maxn, 3)],
                           "max": [round(maxx, 3), float(sample[:, 1].max()), round(-minn, 3)]},
        "dressing": dressing, "businesses": business_records, "parks": park_records,
        "rear_doors": rear_records, "porch_stairs": stair_records, "facade_details": facade_records,
        "construction_audit": construction_audit or {},
        "placement_notes": "Landmarks/spawn lie on actual generated sidewalks. Decorative fixtures are fictional; widths are processing defaults unless OSM supplies width. Route crosses side streets. Terrain extent is a bounding box; use site_boundary for playable area.",
    }
    output = os.path.join(C.ROOT, "godot", "assets", "data", "pen_lucy_level.json")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    temporary = output + ".tmp"
    with open(temporary, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(temporary, output)
    return output, payload
