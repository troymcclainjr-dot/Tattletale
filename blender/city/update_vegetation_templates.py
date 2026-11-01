"""Refresh visual templates only; preserve surveyed placements and ground datum.

Run with the city Python environment after changing vegetation.py or the hedge
template. No terrain/Blender rebuild is required for the runtime presentation.
"""
import hashlib
import json
from pathlib import Path

import vegetation
import yards

ROOT = Path(__file__).resolve().parents[2]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def refresh(directory):
    vegetation_path = directory / "pen_lucy_vegetation.json"
    growth_path = directory / "pen_lucy_shrub_growth.json"
    yards_path = directory / "pen_lucy_yards.json"
    source = vegetation_path.read_bytes()
    data = json.loads(source)
    before = digest(data["plants"])
    growth = json.loads(growth_path.read_text()) if growth_path.exists() else None
    if growth is not None and growth["source_sha256"] != hashlib.sha256(source).hexdigest():
        raise ValueError(f"Refusing to bless stale shrub growth: {growth_path}")
    old_triangles = {kind: {lod: template.get("triangles", len(template["vertices"]) // 9)
                            for lod, template in lods.items()} for kind, lods in data["templates"].items()}
    for bush, count in ((False, 6), (True, 3)):
        for variant in range(count):
            key = ("bush" if bush else "tree") + str(variant)
            data["templates"][key] = {lod: vegetation.encode(vegetation.make_template(variant, bush, lod == "near"))
                                      for lod in ("near", "far")}
    data["templates"]["bush_spire"] = {lod: vegetation.encode(vegetation.pointed_template(lod == "near"))
                                       for lod in ("near", "far")}
    data["counts"]["shared_variants"] = len(data["templates"])
    assert digest(data["plants"]) == before
    yards.atomic_json(vegetation_path, data)
    if growth is not None:
        growth["source_sha256"] = hashlib.sha256(vegetation_path.read_bytes()).hexdigest()
        yards.atomic_json(growth_path, growth)
    garden = json.loads(yards_path.read_text())
    records_before = digest(garden["records"])
    for variant in range(3):
        garden["templates"]["hedge" + str(variant)] = yards.hedge_template(variant)
    assert digest(garden["records"]) == records_before
    yards.atomic_json(yards_path, garden)
    return {"directory": str(directory), "plants": len(data["plants"]), "plant_digest": before,
            "yard_records": len(garden["records"]), "yard_record_digest": records_before,
            "old_triangles": old_triangles,
            "triangles": {kind: {lod: mesh["triangles"] for lod, mesh in lods.items()}
                          for kind, lods in data["templates"].items()}}


if __name__ == "__main__":
    print(json.dumps(refresh(ROOT / "godot/assets/data"), indent=2))
