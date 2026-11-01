"""Author small private-lot repairs against the final exported terrain.

Run after the full city build, shrub growth and pointed-shrub publication.
This never modifies source architecture, roads, courts or existing vegetation.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Point, Polygon, LineString, box
from shapely.ops import unary_union, triangulate, nearest_points
from shapely.strtree import STRtree
from terrain_datum import TerrainDatum
import lawn_collision

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "godot/assets/data"


def read(name):
    return json.loads((DATA / name).read_text())


class Ground:
    def __init__(self, source):
        ground = next(o for o in source["objects"] if o["name"] == "Ground")
        vertices = np.asarray(ground["verts"]).reshape(-1, 3)[:, [0, 2, 1]]
        vertices[:, 2] *= -1
        self.triangles = vertices[np.asarray(ground["faces"]).reshape(-1, 3)]
        self.materials = np.asarray([ground["matnames"][i] for i in ground["mats"]])
        self.polygons = shapely.polygons(self.triangles[:, :, [0, 2]])
        valid = shapely.area(self.polygons) > 1e-7
        self.triangles = self.triangles[valid]
        self.materials = self.materials[valid]
        self.polygons = self.polygons[valid]
        self.index = STRtree(self.polygons)

    def height(self, x, z):
        ids = self.index.query(Point(x, z), predicate="intersects")
        if not len(ids):
            return None
        return self.interpolate(int(ids[0]), (x, z))

    def interpolate(self, index, point):
        tri = self.triangles[index]
        weights = np.linalg.solve(np.vstack((tri[:, [0, 2]].T, np.ones(3))), [*point, 1])
        return float(weights @ tri[:, 1])

    def coverage(self, polygon, materials):
        ids = self.index.query(polygon, predicate="intersects")
        return unary_union([self.polygons[i] for i in ids if self.materials[i] in materials])

    def clipped_triangles(self, polygon, materials=None, lift=.025, datum=None):
        result = []
        # Intersect the local disconnected part rather than every distant lot.
        # Geometry is identical, but a map-wide cleanup union is much larger.
        parts = [p for p in shapely.get_parts(polygon) if p.geom_type == "Polygon"]
        if not parts:
            return result
        part_index = STRtree(parts)
        for i in self.index.query(polygon, predicate="intersects"):
            if materials is not None and self.materials[i] not in materials:
                continue
            local = [parts[j] for j in part_index.query(self.polygons[i], predicate="intersects")]
            clipped = self.polygons[i].intersection(unary_union(local))
            for tri in triangulate(clipped):
                if tri.area < 1e-6 or tri.difference(clipped).area > 1e-7:
                    continue
                points = list(tri.exterior.coords)[:3]
                result.append([[round(x, 5), round(self.interpolate(i, (x, z)) + lift, 5), round(z, 5)] for x, z in points])
        if datum is not None and result:
            # One lawn must have one surface, even when it replaces both a
            # former 2cm paved yard and a 10cm grass bed. Otherwise the old
            # border protrudes through the lower replacement as a long spike.
            result = datum.normalize(result, .125, overlay_lift=lift).round(5).tolist()
        return result


def footprint(center, normal, width, depth):
    normal = np.asarray(normal)
    side = np.array([normal[1], -normal[0]])
    return Polygon([np.asarray(center) + side * a * width / 2 + normal * b * depth / 2
                    for a, b in [(-1, -1), (1, -1), (1, 1), (-1, 1)]])


def main():
    source_path = ROOT / ".work/city/build/pen_lucy_geom.json"
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    ground = Ground(json.loads(source_path.read_text()))
    level, yards = read("pen_lucy_level.json"), read("pen_lucy_yards.json")
    homes = read("pen_lucy_window_homes.json")["homes"]
    civic = read("pen_lucy_civic_build.json")
    removed = {i for site in civic["sites"] for i in site["demolition_ids"]}
    business_path = DATA / "pen_lucy_new_businesses.json"
    businesses = json.loads(business_path.read_text()).get("businesses", []) if business_path.exists() else []
    for business in businesses:
        removed.update(business.get("building_ids", []))
    homes = [h for h in homes if h["id"] not in removed]
    homes_by_id = {h["id"]: h for h in homes}
    building_polygons = [Polygon(h["polygon"]).buffer(.25) for h in homes]
    doors = []
    for entry in level["porch_stairs"]:
        doors.append(LineString([(p[0], p[2]) for p in (entry["landing"], entry["approach"])]).buffer(1.1, cap_style="square"))
    for entry in level["rear_doors"]:
        p, n = np.asarray(entry["position"])[[0, 2]], np.asarray(entry["normal"])[[0, 2]]
        doors.append(LineString([p, p + n * 3.2]).buffer(.95, cap_style="square"))
    civic_polygons = [Polygon(s["footprint_xz"]).buffer(.5) for s in civic["sites"]]
    civic_polygons += [Polygon(b.get("clearance_polygon", b.get("polygon", []))).buffer(.5) for b in businesses]
    for s in civic["sites"]:
        for key in ("parking_lot_xz", "apron_xz"):
            if s.get(key):
                civic_polygons.append(Polygon(s[key]).buffer(.5))
        if s.get("approach_center"):
            civic_polygons.append(LineString([(p[0], p[2]) for p in (s["approach_center"], s["position"])]).buffer(2.8, cap_style="square"))
        if s.get("landscape_clear_zone"):
            civic_polygons.append(shapely.geometry.shape(s["landscape_clear_zone"]))
    fixed = building_polygons + doors + civic_polygons
    fixed += [Polygon(c["footprint"]).buffer(.5) for c in read("pen_lucy_courts.json")["courts"]]
    # Ground materials are the exact street test; buffered centerlines are an
    # additional conservative exclusion for fences near public intersections.
    roads = [LineString([(p[0], p[2]) for p in r["points"]]).buffer(float(r["width"]) / 2 + float(r.get("sidewalk_width", 2.4)) + .25)
             for r in level["roads"] if len(r["points"]) > 1]
    fixed += roads
    street_data = read("pen_lucy_street_surfaces.json")["surfaces"]
    datum = TerrainDatum(ground.triangles, ground.materials)
    exact_walks = unary_union([Polygon(r["polygon"], r.get("holes", [])) for r in street_data["sidewalk"]])
    exact_roads = unary_union([Polygon(r["polygon"], r.get("holes", [])) for r in street_data["road"]])
    # Repair the same discretized-lawn condition across residential frontages.
    # Reconstruct the private bed from its real front edge, porch and sidewalk;
    # fill only homes already containing grass (retain intentional paved yards).
    front_beds, front_zones, cleanup_zones, paths = [], [], [], []
    front_normals = {p["building_id"]: np.asarray(p["normal"])[[0, 2]] for p in level["porch_stairs"]}
    architecture = unary_union(building_polygons)
    redevelopment = unary_union(civic_polygons)
    for stair in level["porch_stairs"]:
        home = homes_by_id.get(stair["building_id"])
        if not home or not home.get("residential"):
            continue
        n = np.asarray(stair["normal"])[[0, 2]]
        tangent = np.array([n[1], -n[0]])
        coords = np.asarray(home["polygon"])
        lo, hi = min(coords @ tangent) + .16, max(coords @ tangent) - .16
        landing, approach = np.asarray(stair["landing"])[[0, 2]], np.asarray(stair["approach"])[[0, 2]]
        target = np.asarray(nearest_points(Point(approach), exact_walks)[1].coords[0])
        start = float(landing @ n) - .15
        end = float(target @ n) + .15
        if end - start < .7 or end - start > 11 or hi - lo < 1.5:
            continue
        zone = Polygon([tangent * u + n * v for u, v in [(lo, start), (hi, start), (hi, end), (lo, end)]])
        path = LineString([landing, approach, target]).buffer(.86, cap_style="square", join_style="mitre")
        bed = zone.difference(exact_walks.buffer(.06)).difference(exact_roads.buffer(.12)).difference(architecture).difference(redevelopment).difference(path)
        existing = ground.coverage(bed, {"grass"}).intersection(bed)
        if bed.area < 1.5 or existing.area < max(.8, bed.area * .08):
            continue
        front_beds.append(bed)
        front_zones.append(zone)
        # A source raster cell can leave a tongue or detached island beyond
        # the intended bed without intersecting the exact sidewalk polygon.
        # Reserve a bounded frontage apron for removing those remnants too.
        cleanup_zones.append(Polygon([tangent * u + n * v for u, v in
                                      [(lo - 1, start), (hi + 1, start), (hi + 1, end + 4), (lo - 1, end + 4)]]))
        paths.append(path)
    path_space = unary_union(paths)
    lawn_space = unary_union(front_beds).difference(path_space)
    # Pave the true public sidewalk and door paths wherever old grass fragments
    # escaped the private beds; this also removes detached curbside rectangles.
    repair_neighborhood = unary_union(front_zones).buffer(4)
    # The photographed East 41st frontage has wider inter-house aprons than
    # the generic one-metre side allowance. Keep every straight lawn bed but
    # remove remaining old grass islands across those specific shared gaps.
    row050_apron = box(119, -258, 157, -250)
    cleanup_space = unary_union(cleanup_zones).union(row050_apron).difference(lawn_space)
    paving_space = exact_walks.intersection(repair_neighborhood).union(path_space).union(cleanup_space).difference(architecture).difference(redevelopment).difference(exact_roads)
    lawn_triangles = ground.clipped_triangles(lawn_space, datum=datum)
    lawn_collision_triangles, lawn_collision_audit = lawn_collision.build(lawn_triangles, ground.triangles)
    paving_triangles = ground.clipped_triangles(paving_space, {"grass", "earth", "soil"}, lift=.03)
    for record in yards["records"]:
        radius = max(record.get("scale", [0, 0, 0])) * .5 if str(record["kind"]).startswith("hedge") else float(record.get("radius", .7))
        fixed.append(Point(record["position"][0], record["position"][2]).buffer(radius + .25))
    base_plants = read("pen_lucy_vegetation.json")["plants"]
    grown = {p["index"]: p for p in read("pen_lucy_shrub_growth.json")["plants"]}
    for index, plant in enumerate(base_plants):
        radius = .7 if str(plant["kind"]).startswith("tree") else float(grown.get(index, plant)["radius"])
        fixed.append(Point(plant["position"][0], plant["position"][2]).buffer(radius + .25))
    for plant in read("pen_lucy_pointed_shrubs.json")["plants"]:
        fixed.append(Point(plant["position"][0], plant["position"][2]).buffer(float(plant["radius"]) + .25))
    for item in read("pen_lucy_backlots.json")["records"]:
        fixed.append(Point(item["position"][0], item["position"][2]).buffer(2.7 if item["kind"] == "car" else 1.3))
    obstacles = STRtree(fixed)
    occupied, plants, fences, dumpsters = [], [], [], []

    def clear(area):
        return not len(obstacles.query(area, predicate="intersects")) and not any(area.intersects(p) for p in occupied)

    # Fill the irregular lawn as a small cluster, with the entire crown on grass.
    target_homes = [h for h in homes if h["source_mesh"] == "Row_050"]
    target_region = unary_union([Polygon(h["polygon"]) for h in target_homes]).buffer(8)
    bounds = target_region.bounds
    candidates = [(x, z) for z in np.arange(bounds[1], bounds[3], 1.35) for x in np.arange(bounds[0], bounds[2], 1.35)]
    candidates.sort(key=lambda p: (abs(p[1] + 252), abs(p[0] - 137)))
    for x, z in candidates:
        radius = .65
        crown = Point(x, z).buffer(radius + .15, quad_segs=10)
        if not target_region.covers(crown) or not clear(crown):
            continue
        supported_lawn = ground.coverage(crown, {"grass"}).union(lawn_space.intersection(crown))
        if crown.difference(supported_lawn).area > 1e-6:
            continue
        y = ground.height(x, z)
        if y is None:
            continue
        nearest = min(target_homes, key=lambda h: Polygon(h["polygon"]).distance(Point(x, z)))
        plants.append({"kind": "bush" + str(len(plants) % 3), "building_id": nearest["id"], "source_mesh": "Row_050",
                       "position": [round(x, 4), round(y, 4), round(z, 4)], "radius": radius,
                       "height": 1.25 + .1 * (len(plants) % 3), "trunk_radius": 0, "yaw": len(plants) * 1.21, "authored_size": True})
        occupied.append(crown.buffer(.3))
        if len(plants) == 8:
            break

    # Side fences belong beside exposed residential end walls, never across
    # front/rear door corridors or a public walking surface. Sparse map-wide set.
    target_id = "w336340628"
    sorted_homes = sorted(homes, key=lambda h: (h["id"] != target_id, hashlib.sha256(h["id"].encode()).hexdigest()))
    fence_cells = {}
    for home in sorted_homes:
        if not home.get("residential") or home["id"] not in front_normals:
            continue
        cell = tuple(np.floor(np.asarray(home["center"]) / 48).astype(int))
        if fence_cells.get(cell, 0) >= 2:
            continue
        poly = Polygon(home["polygon"])
        points = list(poly.exterior.coords)
        chosen = None
        for a, b in zip(points, points[1:]):
            a, b = np.asarray(a), np.asarray(b)
            length = np.linalg.norm(b - a)
            if length < 7:
                continue
            tangent = (b - a) / length
            normal = np.array([-tangent[1], tangent[0]])
            if poly.covers(Point((a + b) / 2 + normal * .1)):
                normal *= -1
            if abs(float(normal @ front_normals[home["id"]])) > .4:
                continue
            for offset in [2.4, 1.8, 1.2, .8, 3.1]:
                center = (a + b) / 2 + normal * offset
                half = min(5.5, length / 2 - 2.5)
                start, end = center - tangent * half, center + tangent * half
                line = LineString([start, end])
                area = line.buffer(.23, cap_style="square")
                if not clear(area):
                    continue
                grass_supported = area.difference(ground.coverage(area, {"grass"})).area <= 1e-5
                # The requested Frisby lot is privately paved (the source
                # classifies that concrete side strip as alley). Only permit
                # this beside a public sidewalk, parallel to an end wall,
                # never in a rear service alley or between interior row homes.
                private_paved = (offset <= 1.8 and area.distance(exact_walks) <= 3.0
                                  and not area.intersects(exact_walks.buffer(.25))
                                  and area.difference(ground.coverage(area, {"alley", "concrete", "grass"})).area <= 1e-5)
                if not grass_supported and not private_paved:
                    continue
                segments = max(2, int(np.ceil(line.length / 1.8)))
                posts = []
                for j in range(segments + 1):
                    x, z = start + (end - start) * j / segments
                    y = ground.height(x, z)
                    if y is None:
                        break
                    posts.append([round(x, 4), round(y, 4), round(z, 4)])
                if len(posts) != segments + 1 or any(abs(posts[j + 1][1] - posts[j][1]) > .3 for j in range(segments)):
                    continue
                if home["id"] == target_id:
                    # Wrap the front end back to the end wall, near the porch.
                    # The only permitted architecture contact is that wall;
                    # every public/door corridor and other obstruction remains
                    # reserved. Keep the existing south-facing front entrance.
                    front_index = 0 if np.asarray(posts[0])[[0, 2]] @ front_normals[home["id"]] > np.asarray(posts[-1])[[0, 2]] @ front_normals[home["id"]] else -1
                    edge = np.asarray(posts[front_index])[[0, 2]]
                    corner = edge + front_normals[home["id"]] * 2.0
                    wall = np.asarray(nearest_points(Point(corner), poly)[1].coords[0])
                    attach = wall + (corner - wall) / np.linalg.norm(corner - wall) * .3
                    wrap = LineString([edge, corner, attach]).buffer(.13, cap_style="square")
                    own_index = homes.index(home)
                    hits = [int(i) for i in obstacles.query(wrap, predicate="intersects") if int(i) != own_index]
                    wrap_heights = [ground.height(*point) for point in (corner, attach)]
                    if not hits and not any(wrap.intersects(p) for p in occupied) and all(h is not None for h in wrap_heights) and wrap.difference(ground.coverage(wrap, {"alley", "concrete", "grass"})).area < 1e-5:
                        additions = [[round(float(p[0]), 4), round(float(y), 4), round(float(p[1]), 4)] for p, y in zip((corner, attach), wrap_heights)]
                        posts = list(reversed(additions)) + posts if front_index == 0 else posts + additions
                    else:
                        continue  # The requested front return must actually fit.
                chosen = {"id": "SideFence_" + home["id"], "building_id": home["id"], "source_mesh": home["source_mesh"],
                          "posts": posts, "height": 1.1, "target_frisby": home["id"] == target_id,
                          "surface": "grass" if grass_supported else "private_paved"}
                occupied.append(area)
                break
            if chosen:
                break
        if chosen:
            fences.append(chosen)
            fence_cells[cell] = fence_cells.get(cell, 0) + 1
        if len(fences) >= 32:
            break

    # Rear service bins sit to the side of the existing door corridor. Use the
    # same runtime terrain/body checks as the already tested backlot dumpsters.
    for door in level["rear_doors"]:
        if door["source_mesh"] != "Row_170":
            continue
        n = np.asarray(door["normal"])[[0, 2]]
        side = np.array([n[1], -n[0]])
        p = np.asarray(door["position"])[[0, 2]]
        placed = False
        for forward in [2.0, 2.6, 3.2, 3.8, 4.4]:
            for across in [-1.8, 1.8, -2.5, 2.5, -3.2, 3.2]:
                center = p + n * forward + side * across
                area = footprint(center, n, 1.92, 1.18).buffer(.22)
                if not clear(area) or area.difference(ground.coverage(area, {"alley", "asphalt", "concrete"})).area > .01:
                    continue
                heights = [ground.height(*v) for v in list(area.exterior.coords)]
                if any(y is None for y in heights) or max(heights) - min(heights) > .25:
                    continue
                y = ground.height(*center)
                dumpsters.append({"id": "DumbartonRearDumpster_" + door["building_id"], "kind": "dumpster", "building_id": door["building_id"],
                                  "position": [round(float(center[0]), 4), round(y, 4), round(float(center[1]), 4)],
                                  "yaw": float(np.arctan2(n[0], n[1])), "mandatory": True})
                occupied.append(area.buffer(.3))
                placed = True
                break
            if placed:
                break
        if len(dumpsters) >= 3:
            break

    # Narrow lawns outside the actual 18m-wide firehouse, beyond its apron.
    # Clip to existing supported terrain, retained buildings and public paving;
    # no geometry bridges a terrain hole or changes the apparatus access.
    grass_triangles, fire_areas, fire_lawns = [], {}, []
    public = unary_union(roads)
    architecture = unary_union(building_polygons)
    for side, strip in [("west", box(-35.7, 130, -33.7, 145.3)), ("east", box(-14.3, 130, -12.3, 145.3))]:
        area = strip.difference(public).difference(architecture)
        fire_lawns.append(area)
        triangles = ground.clipped_triangles(area)
        grass_triangles.extend(triangles)
        fire_areas[side] = round(sum(Polygon([(v[0], v[2]) for v in t]).area for t in triangles), 3)
    fire_cleanup = box(-40, 112, -6, 150).difference(unary_union(fire_lawns)).difference(architecture).difference(exact_roads)
    old_fire_grass = ground.coverage(fire_cleanup, {"grass", "earth", "soil"}).intersection(fire_cleanup)
    # Include the immediately adjacent material boundary, not just green face
    # interiors; otherwise a thin original edge survives the colour overlay.
    fire_cleanup_triangles = ground.clipped_triangles(old_fire_grass.buffer(.12).intersection(fire_cleanup), lift=.035)
    paving_triangles.extend(fire_cleanup_triangles)
    audit = {"shrubs": len(plants), "fences": len(fences), "frisby_fence": any(f["building_id"] == target_id for f in fences),
             "dumpsters": len(dumpsters), "fire_grass_area_m2": fire_areas, "fire_grass_triangles": len(grass_triangles),
             "door_clearance_m": .95, "all_fences_private_setbacks": True,
             "paved_side_fences": sum(f["surface"] == "private_paved" for f in fences), "existing_plants_removed": 0}
    audit["fire_old_grass_cleanup_triangles"] = len(fire_cleanup_triangles)
    audit["fire_cleanup_edge_buffer_m"] = .12
    audit["row050_apron_cleanup_bounds_xz"] = list(row050_apron.bounds)
    audit["frisby_front_return"] = any(f["building_id"] == target_id and len(f["posts"]) > 8 for f in fences)
    audit.update({"normalized_front_beds": len(front_beds), "lawn_triangles": len(lawn_triangles), "paving_repair_triangles": len(paving_triangles),
                  "lawn_collision": lawn_collision_audit,
                  "lawn_height_datum": "shared terrain below raised source finishes", "lawn_base_offset_m": .125,
                  "lawn_path_overlap_m2": round(lawn_space.intersection(path_space).area, 8),
                  "lawn_public_walk_overlap_m2": round(lawn_space.intersection(exact_walks).area, 8)})
    result = {"version": 1, "source_geometry_sha256": source_hash, "plants": plants, "fences": fences,
              "dumpsters": dumpsters, "fire_grass_triangles": grass_triangles, "lawn_triangles": lawn_triangles,
              "lawn_collision_triangles": lawn_collision_triangles,
              "paving_triangles": paving_triangles, "audit": audit}
    report = ROOT / ".work/alive-next/world-author-audit.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(audit, indent=2) + "\n")
    assert plants, "Row050 needs a supported shrub cluster"
    assert audit["frisby_fence"], "Requested Frisby private-side fence could not fit safely"
    assert dumpsters, "Row170 needs at least one safe rear service dumpster"
    assert min(fire_areas.values()) > 5, "Both firehouse side lawns require supported grass"
    for folder in (DATA, ROOT / "blender/city/data"):
        (folder / "pen_lucy_alive_world.json").write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(json.dumps(audit))


if __name__ == "__main__":
    main()
