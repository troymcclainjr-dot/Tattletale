"""Per-house window ownership, independent of the renderer's joined row meshes."""
from yards import atomic_json, RESIDENTIAL


def export(buildings, output):
    homes = []
    for building in sorted(buildings, key=lambda value: value["id"]):
        if not building.get("object"):
            continue
        polygon = building["poly"]
        homes.append({"id": building["id"], "source_mesh": building["object"],
                      "residential": building.get("arch") in RESIDENTIAL,
                      "center": [round(polygon.centroid.x, 4), round(-polygon.centroid.y, 4)],
                      "polygon": [[round(x, 4), round(-y, 4)] for x, y in polygon.exterior.coords]})
    atomic_json(output, {"version": 1, "homes": homes})
