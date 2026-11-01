"""Footprint-clipped rowhouse gardens and deterministic, auditable yard dressing.

All geometry is generated before ground triangulation, so beds replace concrete
instead of hovering over it. Coordinates here are east/north/surveyed elevation.
"""
import json
import math
import struct
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union, nearest_points
import vegetation

RESIDENTIAL = ("row", "row_porch", "detached", "detached_porch")


def atomic_json(output, payload):
    path = Path(output)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    temporary.replace(path)


def paving_boundary(geometry):
    """Polygon edges only: clipped paving can also contain line remnants.

    GeometryCollection.boundary is None in GEOS; dissolve its polygon members
    before measuring clearance from sidewalk-height transitions.
    """
    pending, polygons = [geometry], []
    while pending:
        part = pending.pop()
        if part.geom_type == "Polygon" and not part.is_empty:
            polygons.append(part)
        elif hasattr(part, "geoms"):
            pending.extend(part.geoms)
    return unary_union(polygons).boundary if polygons else LineString()


def gardens(buildings, footprints, roads, walks, alleys, lots, site):
    blocked = unary_union([footprints.buffer(0.18), roads.buffer(0.15), walks.buffer(0.12), alleys, lots])
    beds, paths, dry, borders, records = [], [], [], [], []
    for index, b in enumerate(sorted(buildings, key=lambda b: b["id"])):
        front = b.get("front_yard")
        if b.get("arch") not in RESIDENTIAL or not front:
            continue
        a, end = np.asarray(front["edge"])
        normal = np.asarray(front["normal"])
        tangent = (end - a) / np.linalg.norm(end - a)
        a, end = a + tangent * 0.16, end - tangent * 0.16
        depth = min(9.0, Point((a + end) / 2).distance(walks) + 0.25)
        if depth < 0.7:
            continue
        strip = Polygon([a, end, end + normal * depth, a + normal * depth])
        stair = b.get("porch_stair", {})
        approach = np.asarray(stair.get("approach_xyz", [*(np.asarray(front["door"]) + normal * 1.9), 0])[:2])
        landing = np.asarray(stair.get("landing_xyz", [*front["door"], 0])[:2])
        target = nearest_points(Point(approach), walks)[1]
        path = LineString([landing, approach, target.coords[0]]).buffer(0.84, cap_style="square", join_style="mitre")
        paths.append(path)
        # A minority retain their concrete patio, preserving real block variety.
        if index % 7 == 0:
            continue
        bed = strip.difference(blocked).difference(path).intersection(site)
        parts = [p for p in shapely.get_parts(bed) if p.geom_type == "Polygon" and p.area >= 0.75 and not p.buffer(-0.25).is_empty]
        if not parts:
            continue
        bed = unary_union(parts)
        beds.append(bed)
        records.append({"building_id": b["id"], "poly": bed, "normal": normal, "path": path})
        # Continuous lawns: former circular dirt cutouts read as detached dark
        # disks below the clipped hedges. Keep the terrain flush and grass-filled.
        if index % 4 == 0:
            borders.append(bed.difference(bed.buffer(-0.10)))
    path_union = unary_union(paths)
    # Another house's approach can cross a corner lot; reserve ALL paths last.
    bed_union = unary_union(beds).difference(path_union)
    edge_union = unary_union(borders).intersection(bed_union)
    dry_union = unary_union(dry).intersection(bed_union).difference(edge_union)
    for record in records:
        record["poly"] = record["poly"].intersection(bed_union).difference(edge_union)
    assert bed_union.intersection(blocked).area < 1e-6
    assert bed_union.intersection(path_union).area < 1e-6
    audit = {"homes_with_beds": len(records), "lawn_beds_m2": round(bed_union.area, 3),
             "dry_soil_m2": round(dry_union.area, 3), "brick_edge_m2": round(edge_union.area, 3),
             "minimum_walk_width_m": 1.68, "bed_path_overlap_m2": round(bed_union.intersection(path_union).area, 8),
             "bed_forbidden_overlap_m2": round(bed_union.intersection(blocked).area, 8)}
    return bed_union, dry_union, edge_union, path_union, records, audit


def can_template(path):
    """Reuse the original port's sculpted metal can, extracted from TrashCans."""
    blob = Path(path).read_bytes()
    length = struct.unpack_from("<I", blob, 12)[0]
    data = json.loads(blob[20:20 + length])
    binary = blob[28 + length:]
    def accessor(index):
        acc = data["accessors"][index]; view = data["bufferViews"][acc["bufferView"]]
        count = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[acc["componentType"]]
        return np.frombuffer(binary, dtype=dtype, count=acc["count"] * count,
                             offset=view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, count)
    node = next(n for n in data["nodes"] if n.get("name") == "TrashCans")
    vertices, normals, colors = [], [], []
    for primitive in data["meshes"][node["mesh"]]["primitives"]:
        pos = accessor(primitive["attributes"]["POSITION"])
        norm = accessor(primitive["attributes"]["NORMAL"])
        idx = accessor(primitive["indices"]).reshape(-1, 3)
        # Joined source mesh is in world coordinates. Keep the leftmost can.
        keep = pos[idx, 0].mean(axis=1) < -10
        selected = idx[keep][:, ::-1].ravel()  # glTF CCW -> Godot clockwise
        hex_ = data["materials"][primitive["material"]]["name"].split("_")[1]
        color = [int(hex_[i:i + 2], 16) / 255 for i in (0, 2, 4)] + [1]
        vertices.extend((pos[selected] - np.array([-15.8, 0.11, -3.5])).round(5).ravel().tolist())
        normals.extend(norm[selected].round(5).ravel().tolist())
        colors.extend(color * len(selected))
    if not vertices:
        raise ValueError("Original TrashCans geometry not found")
    return {"vertices": vertices, "normals": normals, "colors": colors}


def hedge_template(variant):
    """A clipped, continuous hedge with flat top and small leaf facets, not blobs."""
    rng = np.random.default_rng(7021 + variant)
    vertices, normals, colors = [], [], []
    # Coherent cultivated greens replace alternating checkerboard facets.
    base = np.array([[.25,.37,.24], [.32,.43,.25], [.29,.40,.27]])[variant % 3]
    palette = np.array([base * shade for shade in (.94, .98, 1.02, 1.06)])
    def face(points, normal, color):
        points = np.asarray(points, float)
        for indices in ((0, 1, 2), (0, 2, 3)) if len(points) == 4 else ((0, 1, 2),):
            tri = points[list(indices)]
            cross = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            if cross @ normal < 0: tri = tri[::-1]
            vertices.extend(tri[::-1].round(5).ravel().tolist())
            normals.extend(list(normal) * 3)
            colors.extend([*color, 1] * 3)
    # Cross-section has vertical lower sides and clipped shoulders, with a
    # broad nearly flat crown. Twelve contiguous sections form a living row.
    profile = [(-.48, .0), (-.50, .72), (-.43, .93), (-.30, .99), (.30, .99), (.43, .93), (.50, .72), (.48, .0)]
    xs = np.linspace(-.5, .5, 13)
    rings = []
    for i, x in enumerate(xs):
        jitter = 0.010 * np.sin(i * 1.3 + variant)
        rings.append(np.array([[x, y + jitter if y > .8 else y, z * (1 - .055 * (1 + np.cos(i * 1.3 + variant)) * .5)] for z, y in profile]))
    for i in range(len(rings) - 1):
        for j in range(len(profile)):
            k = (j + 1) % len(profile)
            points = np.array([rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][k]])
            n = np.array([0, points[:, 1].mean() - .5, points[:, 2].mean()]); n /= np.linalg.norm(n)
            # Slow color changes along the row; upward faces catch a little more light.
            tone = .96 + .035 * np.sin(i*.63 + variant) + .04 * max(0., n[1])
            face(points, n, base * tone)
    for ring, nx in ((rings[0], -1), (rings[-1], 1)):
        center = ring.mean(axis=0)
        for j in range(len(ring)):
            face([center, ring[j], ring[(j + 1) % len(ring)]], [nx, 0, 0], palette[(j + variant) % 4])
    # Tiny leaf diamonds on the clipped faces break up broad planar shading.
    for side in (-1, 1):
        for x in np.linspace(-.46, .46, 12):
            for y in (.30, .53, .76):
                x += float(rng.uniform(-.012, .012)); y += float(rng.uniform(-.04, .04))
                # Follow the narrowed living surface so tips remain attached.
                section = (x + .5) * 12
                z = side * .50 * (1 - .055 * (1 + np.cos(section * 1.3 + variant)) * .5)
                face([[x-.017,y,z],[x,y+.05,z+side*.008],[x+.017,y,z],[x,y-.04,z]], [0,0,side], palette[int(rng.integers(4))]*1.02)
    return {"vertices": vertices, "normals": normals, "colors": colors, "triangles": len(vertices)//9}


def hedge_rows(garden, reserved):
    """Parallel strips on the porch side of each bed, with full-width path gaps."""
    normal = np.asarray(garden["normal"], float)
    tangent = np.array([normal[1], -normal[0]])
    rows = []
    for part in shapely.get_parts(garden["poly"]):
        if part.geom_type != "Polygon": continue
        safe = part.buffer(-.38).difference(reserved.buffer(.02))
        if safe.is_empty: continue
        coords = shapely.get_coordinates(part)
        lo, hi = np.min(coords @ tangent), np.max(coords @ tangent)
        front = np.min(coords @ normal)
        for offset in (.42, .62, .82):
            line = LineString([tangent * lo + normal * (front + offset), tangent * hi + normal * (front + offset)])
            pieces = [v for v in shapely.get_parts(line.intersection(safe)) if v.geom_type == "LineString" and v.length >= 1.35]
            if not pieces: continue
            for segment in pieces:
                # Cap long detached frontages, retaining a small gap at each end.
                length = min(5.8, segment.length - .05)
                p = segment.interpolate(.5, normalized=True)
                xy = np.array(p.coords[0])
                footprint = Polygon([xy + tangent*u + normal*v for u,v in ((-length/2,-.35),(length/2,-.35),(length/2,.35),(-length/2,.35))])
                if part.covers(footprint) and footprint.intersection(reserved).area < 1e-8:
                    rows.append((p, length, math.atan2(tangent[1], tangent[0]), footprint, offset))
            break
    return rows


def export_street_surfaces(zones, output):
    """Exact road/walk pieces in bounded 64m tiles for runtime fixture checks."""
    surfaces = {}
    for name in ("road", "sidewalk"):
        geom = zones[name]
        xmin,ymin,xmax,ymax = geom.bounds
        records = []
        for x in range(math.floor(xmin/64)*64,math.ceil(xmax/64)*64,64):
            for y in range(math.floor(ymin/64)*64,math.ceil(ymax/64)*64,64):
                clipped = geom.intersection(shapely.box(x,y,x+64,y+64))
                for poly in shapely.get_parts(clipped):
                    if poly.geom_type != "Polygon" or poly.area < 1e-5: continue
                    ring = lambda r: [[round(a,3),round(-b,3)] for a,b in r.coords]
                    records.append({"polygon":ring(poly.exterior),"holes":[ring(r) for r in poly.interiors]})
        surfaces[name] = records
    atomic_json(output, {"version":1,"coordinate_system":"x east,z south","tile_size_m":64,"surfaces":surfaces})


def export(buildings, footprints, zones, paths, gardens_, height, origin_y, runtime_data, output, court_space=None):
    rng = np.random.default_rng(429017)
    records, occupied, hedges = [], [], []
    route = LineString([(p[0], -p[2]) for p in runtime_data["route"]["points"]])
    rear_paths = []
    for b in buildings:
        rear = b.get("rear_door")
        if rear:
            p = np.asarray(rear["xyz"][:2]); n = np.asarray(rear["normal_xy"])
            rear_paths.append(LineString([p, p + n * 3.2]).buffer(0.95))
    court_space = court_space if court_space is not None else Polygon()
    reserved = unary_union([paths, *rear_paths, route.buffer(1.2), court_space.buffer(.25)])
    forbidden = unary_union([footprints.buffer(0.18), zones["road"].buffer(0.4), zones["sidewalk"].buffer(0.15), reserved])
    bins_allowed = zones["alley"].difference(forbidden)
    # Existing service-road center lanes remain fully open; bin sites hug homes.
    service = zones.get("service_lanes", Polygon()).buffer(0.35)
    bins_allowed = bins_allowed.difference(service)
    def position(p, lift):
        return [round(p.x, 4), round(float(height(np.array([p.x]), np.array([p.y]))[0]) - origin_y + lift, 4), round(-p.y, 4)]
    def add(kind, p, yaw=0.0, scale=None, radius=0.0, lift=0.02, building=""):
        records.append({"kind": kind, "position": position(p, lift), "yaw": round(yaw, 5),
                        "scale": scale or [1, 1, 1], "radius": radius, "building_id": building})
    for index, b in enumerate(sorted(buildings, key=lambda b: b["id"])):
        if b.get("arch") not in RESIDENTIAL or index % 4 == 3:
            continue
        poly = shapely.orient_polygons(b["poly"])
        coords = list(poly.exterior.coords)
        placed = False
        for a, c in zip(coords, coords[1:]):
            a, c = np.asarray(a), np.asarray(c)
            length = np.linalg.norm(c - a)
            if length < 2:
                continue
            tangent = (c - a) / length; normal = np.array([tangent[1], -tangent[0]])
            if b.get("n") is not None and normal @ b["n"] > 0.4:
                continue
            for kind, radius, offset in ([("dumpster", 1.35, 1.55), ("can", 0.46, 0.72)] if index % 8 == 0 else [("can", 0.46, 0.72)]):
                for fraction in (0.28, 0.72, 0.5):
                    p = Point(a + (c - a) * fraction + normal * offset)
                    disk = p.buffer(radius)
                    if not bins_allowed.covers(disk) or any(p.distance(q) < radius + r + 0.5 for q, r in occupied):
                        continue
                    add(kind, p, math.atan2(normal[0], -normal[1]), radius=radius, building=b["id"])
                    occupied.append((p, radius)); placed = True
                    break
                if placed: break
            if placed: break
    for index, garden in enumerate(gardens_):
        if index % 3 == 0: continue
        for p, length, yaw, footprint, offset in hedge_rows(garden, reserved):
            add("hedge" + str(index % 3), p, yaw, [length, .72 + (index % 4) * .075, .68], lift=.10, building=garden["building_id"])
            eps = .15
            dx = float(height(np.array([p.x+eps]), np.array([p.y]))[0] - height(np.array([p.x-eps]), np.array([p.y]))[0])/(2*eps)
            dn = float(height(np.array([p.x]), np.array([p.y+eps]))[0] - height(np.array([p.x]), np.array([p.y-eps]))[0])/(2*eps)
            normal = np.array([-dx,1,dn]); normal /= np.linalg.norm(normal)
            records[-1]["normal"] = normal.round(6).tolist()
            records[-1]["front_offset_m"] = offset
            hedges.append((footprint, length, garden["building_id"]))
    # Stratified coverage across the complete map, plus small bin-side clusters.
    litter_allowed = unary_union([zones["sidewalk"], zones["alley"], zones["lot"]]).difference(footprints.buffer(0.25))
    xmin, ymin, xmax, ymax = litter_allowed.bounds
    xs, ys = np.meshgrid(np.arange(xmin, xmax, 5.0), np.arange(ymin, ymax, 5.0))
    candidates = np.column_stack([xs.ravel(), ys.ravel()]) + rng.uniform(-2.1, 2.1, (xs.size, 2))
    clusters = [np.array(p.coords[0]) + rng.uniform(-2.2, 2.2, 2) for p, _ in occupied for _ in range(6)]
    if clusters: candidates = np.vstack([candidates, clusters])
    kinds = ["paper", "wrapper", "cardboard", "loose_can", "cup"]
    litter_positions = []
    for xy in candidates:
        p = Point(xy)
        if not litter_allowed.covers(p.buffer(0.24)) or reserved.distance(p) < 0.2:
            continue
        if any(p.distance(q) < r + 0.25 for q, r in occupied): continue
        # Vertex ground normals supplied to renderer avoid float on graded paving.
        lift = 0.15 if zones["sidewalk"].covers(p) else 0.01 if zones["lot"].covers(p) else 0.02
        add(kinds[int(rng.integers(5))], p, float(rng.uniform(-math.pi, math.pi)), lift=lift + 0.008)
        eps = 0.15
        dx = float(height(np.array([p.x + eps]), np.array([p.y]))[0] - height(np.array([p.x - eps]), np.array([p.y]))[0]) / (2 * eps)
        dn = float(height(np.array([p.x]), np.array([p.y + eps]))[0] - height(np.array([p.x]), np.array([p.y - eps]))[0]) / (2 * eps)
        n = np.array([-dx, 1.0, dn]); n /= np.linalg.norm(n)
        records[-1]["normal"] = n.round(6).tolist()
        litter_positions.append(p)
    # The union-of-paving test permits a piece to straddle a 13cm sidewalk /
    # alley step. Keep the complete loose prop away from that height transition;
    # tiny boundary triangles may also be culled from imported physics meshes.
    walk_boundary = paving_boundary(zones["sidewalk"])
    rejected_transition = {tuple(record["position"]) for record in records if record["kind"] in kinds
        and walk_boundary.distance(Point(record["position"][0], -record["position"][2])) < .24}
    records = [record for record in records if tuple(record["position"]) not in rejected_transition]
    litter_positions = [Point(record["position"][0], -record["position"][2]) for record in records if record["kind"] in kinds]
    templates = {"can": can_template(Path(output).parents[1] / "models" / "furniture.glb")}
    for index in range(3): templates["hedge" + str(index)] = hedge_template(index)
    counts = {kind: sum(r["kind"] == kind for r in records) for kind in sorted(set(r["kind"] for r in records))}
    cells = {(math.floor(p.x / 48), math.floor(p.y / 48)) for p in litter_positions}
    audit = {"counts": counts, "litter": len(litter_positions), "litter_cells": len(cells),
             "bin_road_walk_path_overlap": sum(not bins_allowed.covers(p.buffer(r)) for p, r in occupied),
             "loose_litter_colliders": 0, "seed": 429017,
             "litter_paving_transition_rejections": len(rejected_transition),
             "hedge_rows": len(hedges), "hedge_homes": len({h[2] for h in hedges}), "hedge_length_m": round(sum(h[1] for h in hedges),2),
             "hedge_reserved_overlap_m2": round(sum(h[0].intersection(reserved).area for h in hedges),8),
             "court_overlap_m2": round(sum(h[0].intersection(court_space).area for h in hedges)
                 + sum(p.buffer(r).intersection(court_space).area for p,r in occupied)
                 + sum(p.buffer(.24).intersection(court_space).area for p in litter_positions),8),
             "litter_span_x_m": round(max(p.x for p in litter_positions) - min(p.x for p in litter_positions), 2),
             "litter_span_z_m": round(max(p.y for p in litter_positions) - min(p.y for p in litter_positions), 2)}
    assert audit["bin_road_walk_path_overlap"] == 0
    assert audit["court_overlap_m2"] == 0, audit
    assert 450 <= counts.get("can", 0) + counts.get("dumpster", 0) <= 600, audit
    assert audit["hedge_rows"] >= 200 and audit["hedge_reserved_overlap_m2"] == 0, audit
    assert len(litter_positions) > 1500 and len(cells) > 60, audit
    atomic_json(output, {"version": 1, "records": records, "templates": templates, "audit": audit})
    return audit
