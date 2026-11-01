"""Place narrow evergreen shrubs in otherwise unplanted residential lawns.

Run with the city Python environment after court/yard metadata is regenerated.
The rendered ground triangles are authoritative: no shrub footprint may spill
onto a paved approach, sidewalk, road, hedge, or other existing plant.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "godot/assets/data"

def read(name):
    return json.loads((DATA / name).read_text())

def main():
    level = read("pen_lucy_level.json")
    yards = read("pen_lucy_yards.json")
    plants = read("pen_lucy_vegetation.json")["plants"]
    growth = read("pen_lucy_shrub_growth.json")
    grown = {p["index"]: p for p in growth["plants"]}
    source = json.loads((ROOT / ".work/city/build/pen_lucy_geom.json").read_text())
    ground = next(obj for obj in source["objects"] if obj["name"] == "Ground")
    verts = np.asarray(ground["verts"]).reshape(-1, 3)[:, [0, 2, 1]]
    verts[:, 2] *= -1
    triangles = verts[np.asarray(ground["faces"]).reshape(-1, 3)]
    mask = np.asarray([ground["matnames"][i] == "grass" for i in ground["mats"]])
    triangles = triangles[mask]
    polygons = shapely.polygons(triangles[:, :, [0, 2]])
    valid = shapely.area(polygons) > 1e-7
    triangles, polygons = triangles[valid], polygons[valid]
    grass = STRtree(polygons)
    del source, ground, verts
    blocked = []
    hedged = set()
    for entry in yards["records"]:
        if entry["kind"].startswith("hedge"):
            hedged.add(entry["building_id"])
            blocked.append(Point(entry["position"][0], entry["position"][2]).buffer(max(entry["scale"][0], entry["scale"][2]) * .5 + .25))
        elif entry.get("radius", 0) > 0:
            blocked.append(Point(entry["position"][0], entry["position"][2]).buffer(entry["radius"] + .2))
    for entry in level["porch_stairs"]:
        blocked.append(LineString([(p[0], p[2]) for p in (entry["landing"], entry["approach"])]).buffer(1.05, cap_style="square"))
    for index, entry in enumerate(plants):
        radius = grown.get(index, entry).get("radius", .5)
        if entry["kind"].startswith("tree"):
            radius = .75  # Keep the trunk clear; crowns can naturally overlap.
        blocked.append(Point(entry["position"][0], entry["position"][2]).buffer(radius + .3))
    for court in read("pen_lucy_courts.json")["courts"]:
        blocked.append(Polygon(court["footprint"]).buffer(.4))
    for home in read("pen_lucy_window_homes.json")["homes"]:
        blocked.append(Polygon(home["polygon"]).buffer(.25))
    obstacles = STRtree(blocked)
    selected, occupied, seen = [], [], set()
    cell_counts = {}
    target_checks = []
    targeted = "w336338678"
    stairs = sorted(level["porch_stairs"], key=lambda item: (item["building_id"] != targeted, hashlib.sha256(item["building_id"].encode()).hexdigest()))
    for entry in stairs:
        home = entry["building_id"]
        if home in seen or home in hedged:
            continue
        seen.add(home)
        seed = int(hashlib.sha256(home.encode()).hexdigest()[:8], 16)
        if home != targeted and seed % 3 == 0:
            continue
        radius = .47 + (seed % 4) * .035
        normal = np.asarray(entry["normal"])[[0, 2]]
        tangent = np.array([-normal[1], normal[0]])
        base = np.asarray(entry["approach"])[[0, 2]]
        for side, forward in [(s, f) for s in (2.6, -2.6, 3.2, -3.2, 1.9, -1.9) for f in (0, -.45, -.65, -.9, .45)]:
            point = base + tangent * side + normal * forward
            cell = tuple(np.floor(point / 48).astype(int))
            if cell_counts.get(cell, 0) >= 2:
                continue
            circle = Point(*point).buffer(radius + .12, quad_segs=10)
            indices = grass.query(circle, predicate="intersects")
            outside = circle.difference(unary_union(polygons[indices])).area if len(indices) else circle.area
            obstacle_hits = obstacles.query(circle, predicate="intersects")
            if home == targeted:
                target_checks.append({"point": point.tolist(), "outside_grass_m2": outside, "obstacles": obstacle_hits.tolist()})
            if not len(indices) or outside > 1e-6:
                continue
            if len(obstacle_hits) or any(circle.intersects(other) for other in occupied):
                continue
            center_ids = grass.query(Point(*point), predicate="intersects")
            if not len(center_ids):
                continue
            tri = triangles[center_ids[0]]
            weights = np.linalg.solve(np.vstack((tri[:, [0, 2]].T, np.ones(3))), np.array([*point, 1]))
            y = float(weights @ tri[:, 1])
            selected.append({"kind": "bush_spire", "building_id": home, "source_mesh": entry["source_mesh"],
                             "position": [round(float(point[0]), 4), round(y, 4), round(float(point[1]), 4)],
                             "radius": radius, "trunk_radius": 0.0, "height": round(1.9 + (seed % 8) * .1, 2),
                             "yaw": (seed % 628) * .01})
            occupied.append(circle.buffer(.8))
            cell_counts[cell] = cell_counts.get(cell, 0) + 1
            break
        if len(selected) >= 100:
            break
    result = {"version": 1, "plants": selected, "audit": {"count": len(selected), "target_home": targeted,
              "target_placed": any(p["building_id"] == targeted for p in selected), "min_height_m": 1.9,
              "max_height_m": 2.6, "spatial_cells": len(cell_counts), "paving_or_obstacle_overlap": 0, "only_unhedged_homes": True}}
    assert result["audit"]["target_placed"], "The screenshot's empty lawn must receive a pointed shrub: " + json.dumps(target_checks)
    for directory in (DATA, ROOT / "blender/city/data"):
        (directory / "pen_lucy_pointed_shrubs.json").write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(json.dumps(result["audit"]))

if __name__ == "__main__":
    main()
