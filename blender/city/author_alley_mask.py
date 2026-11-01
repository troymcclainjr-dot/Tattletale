"""Refresh the reviewable alley corridors from downloaded OSM, without builds."""
import json
from pathlib import Path
import numpy as np
from pyproj import Transformer
from shapely.geometry import LineString, box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]


def main():
    spec_path = ROOT / "blender/city/data/pen_lucy_alley_repairs.json"
    spec = json.loads(spec_path.read_text())
    level = json.loads((ROOT / "godot/assets/data/pen_lucy_level.json").read_text())
    osm = json.loads((ROOT / ".work/city/raw/osm.json").read_text())
    transform = Transformer.from_crs(4326, 6347, always_xy=True)
    origin = np.asarray(transform.transform(*level["origin_lonlat"]))
    corridors = []
    for way in osm["elements"]:
        tags = way.get("tags", {})
        if tags.get("highway") != "service" or tags.get("service") != "alley" or len(way.get("geometry", [])) < 2:
            continue
        points = [(np.asarray(transform.transform(p["lon"], p["lat"])) - origin) * [1, -1] for p in way["geometry"]]
        corridor = LineString(points).buffer(2.0, cap_style="flat", quad_segs=2)
        corridors.append({"osm_way_id": str(way["id"]), "width_m": 4.0, "geometry": mapping(corridor)})
    # This whole passage is visible in the supplied Wilsby screenshot. It has
    # opposite row walls, separate public sidewalks at the ends, and the grass
    # island from the independently audited source. Only alley material inside
    # this rectangle changes; gardens/buildings/public sidewalks are protected.
    reviewed = box(268.8, -170.5, 322.7, -157.75)
    mask = unary_union([shape(c["geometry"]) for c in corridors] + [reviewed])
    # Protect all original residential front stair/door approaches, including
    # narrow end-unit fronts that occasionally face a mapped service lane.
    front_paths = []
    for entry in level["porch_stairs"]:
        a, b = np.asarray(entry["landing"])[[0, 2]], np.asarray(entry["approach"])[[0, 2]]
        normal = np.asarray(entry["normal"])[[0, 2]]
        front_paths.append(LineString([a - normal * .4, b + normal * 1.0]).buffer(max(1.0, float(entry.get("width_m", 1.25)) * .5 + .3), cap_style="square"))
    protected = unary_union(front_paths)
    mask = mask.difference(protected)
    spec.update(version=2, policy="Only OSM service=alley corridors and the reviewed Wilsby passage become asphalt; public sidewalks and private front approaches stay unchanged.",
                projection="EPSG:6347 relative to level origin; game Z is negative northing",
                origin_lonlat=level["origin_lonlat"], source_alley_ways=corridors,
                reviewed_passage=mapping(reviewed), alley_corridors=mapping(mask),
                protected_front_approaches=mapping(protected),
                author_audit={"osm_alley_ways": len(corridors), "protected_front_approaches": len(front_paths),
                              "corridor_mask_area_m2": round(mask.area, 5), "front_approach_overlap_m2": round(mask.intersection(protected).area, 8)})
    spec_path.write_text(json.dumps(spec, separators=(",", ":")) + "\n")
    print(json.dumps(spec["author_audit"]))


if __name__ == "__main__":
    main()
