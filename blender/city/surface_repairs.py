"""Local source-surface repairs for the reviewed East41st/firehouse frontages.

Runs in process.py before geometry publication; the CLI applies the same repair
to an already generated source without rebuilding buildings or changing grades.
Only Ground material partitions and obsolete private dirt/brick skirt finishes
change. Vertical skirts must stay closed; they are paving, never deleted faces.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Polygon, LineString, shape
from shapely.ops import triangulate, unary_union

ROOT = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).with_name("data") / "pen_lucy_surface_repairs.json"


def clip_parameter(vertices, origin, direction, threshold, greater):
    """Clip a 3D polygon by a horizontal half-plane; retain exact grade."""
    result = []
    denominator = float(direction @ direction)
    for a, b in zip(vertices, vertices[1:] + vertices[:1]):
        ta = float((a[[0, 2]] - origin) @ direction / denominator)
        tb = float((b[[0, 2]] - origin) @ direction / denominator)
        inside_a = ta >= threshold - 1e-10 if greater else ta <= threshold + 1e-10
        inside_b = tb >= threshold - 1e-10 if greater else tb <= threshold + 1e-10
        if inside_a:
            result.append(a)
        if inside_a != inside_b and abs(tb - ta) > 1e-12:
            result.append(a + (b - a) * ((threshold - ta) / (tb - ta)))
    return result


def vertical_remainder(triangle, mask, inside=False):
    """Clip a vertical skirt in its (horizontal distance, height) plane."""
    pairs = [(a, b) for a in range(3) for b in range(a + 1, 3)]
    a, b = max(pairs, key=lambda pair: np.linalg.norm(triangle[pair[0], [0, 2]] - triangle[pair[1], [0, 2]]))
    origin, end = triangle[a, [0, 2]], triangle[b, [0, 2]]
    direction = end - origin
    if float(direction @ direction) < 1e-12:
        return ([] if inside else [triangle]), False
    line = LineString([origin, end])
    if line.intersection(mask).length < 1e-7:
        return ([] if inside else [triangle]), False
    kept = []
    selected = line.intersection(mask) if inside else line.difference(mask)
    for part in shapely.get_parts(selected):
        if part.geom_type != "LineString" or part.length < 1e-7:
            continue
        ts = [(np.asarray(point) - origin) @ direction / (direction @ direction) for point in part.coords]
        polygon = clip_parameter(list(triangle), origin, direction, min(ts), True)
        if polygon:
            polygon = clip_parameter(polygon, origin, direction, max(ts), False)
        for i in range(1, len(polygon) - 1):
            tri = np.array([polygon[0], polygon[i], polygon[i + 1]])
            if np.linalg.norm(np.cross(tri[1] - tri[0], tri[2] - tri[0])) > 1e-9:
                kept.append(tri)
    return kept, True


def planar_pieces(triangle, polygon):
    """Re-triangulate a clipped horizontal projection on its original plane."""
    result = []
    inverse = np.linalg.inv(np.vstack([triangle[:, [0, 2]].T, np.ones(3)]))
    original_normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
    for piece in triangulate(polygon):
        if piece.area < 1e-8 or piece.difference(polygon).area > 1e-8:
            continue
        vertices = []
        for x, z in list(piece.exterior.coords)[:3]:
            y = float((inverse @ np.array([x, z, 1])) @ triangle[:, 1])
            vertices.append([x, y, z])
        tri = np.asarray(vertices)
        if np.dot(np.cross(tri[1] - tri[0], tri[2] - tri[0]), original_normal) < 0:
            tri = tri[::-1]
        result.append(tri)
    return result


def repair_object(obj, mask, bounds):
    vertices = np.asarray(obj["verts"], float).reshape(-1, 3)[:, [0, 2, 1]].copy()
    vertices[:, 2] *= -1
    faces = np.asarray(obj["faces"], int).reshape(-1, 3)
    mats = obj["mats"]
    smooth = obj.get("smooth_faces", [obj["smooth"]] * len(faces))
    output_vertices = list(vertices)
    output_faces, output_mats, output_smooth = [], [], []
    sidewalk = obj["matnames"].index("sidewalk") if "sidewalk" in obj["matnames"] else len(obj["matnames"])
    eligible = {"grass", "brick", "alley", "dirt"} if obj["name"] == "Ground" else {"dirt", "brick"}
    changed = removed = added = 0
    changed_area = 0.0
    for index, face in enumerate(faces):
        material = str(obj["matnames"][mats[index]])
        triangle = vertices[face]
        lo, hi = triangle[:, [0, 2]].min(axis=0), triangle[:, [0, 2]].max(axis=0)
        overlaps = any(hi[0] >= b[0] and lo[0] <= b[2] and hi[1] >= b[1] and lo[1] <= b[3] for b in bounds)
        if material not in eligible or not overlaps:
            output_faces.append(face.tolist()); output_mats.append(mats[index]); output_smooth.append(smooth[index])
            continue
        polygon = Polygon(triangle[:, [0, 2]])
        pieces = []
        if polygon.area < 1e-8:
            if obj["name"] == "Ground":
                output_faces.append(face.tolist()); output_mats.append(mats[index]); output_smooth.append(smooth[index])
                continue
            kept, touched = vertical_remainder(triangle, mask)
            if not touched:
                output_faces.append(face.tolist()); output_mats.append(mats[index]); output_smooth.append(smooth[index])
                continue
            pieces = [(tri, mats[index]) for tri in kept]
            painted, _ = vertical_remainder(triangle, mask, inside=True)
            pieces += [(tri, sidewalk) for tri in painted]
        else:
            inside = polygon.intersection(mask)
            if inside.area < 1e-8:
                output_faces.append(face.tolist()); output_mats.append(mats[index]); output_smooth.append(smooth[index])
                continue
            changed_area += inside.area
            if obj["name"] == "Ground" and abs(inside.area - polygon.area) < 1e-8:
                # Interior faces retain all original topology and exact vertices.
                output_faces.append(face.tolist()); output_mats.append(sidewalk); output_smooth.append(smooth[index])
                changed += 1
                continue
            pieces += [(tri, mats[index]) for tri in planar_pieces(triangle, polygon.difference(mask))]
            pieces += [(tri, sidewalk) for tri in planar_pieces(triangle, inside)]
        changed += 1
        removed += int(not pieces)
        for tri, material_index in pieces:
            start = len(output_vertices)
            output_vertices.extend(tri)
            output_faces.append([start, start + 1, start + 2])
            output_mats.append(material_index)
            output_smooth.append(smooth[index])
            added += 1
    if changed:
        if "sidewalk" not in obj["matnames"]:
            obj["matnames"].append("sidewalk")
        native = np.asarray(output_vertices)[:, [0, 2, 1]]
        native[:, 1] *= -1
        obj["verts"] = native.round(6).ravel().tolist()
        obj["faces"] = np.asarray(output_faces, int).ravel().tolist()
        obj["mats"] = output_mats
        if "smooth_faces" in obj:
            obj["smooth_faces"] = [int(s) for s in output_smooth]
    return {"changed_source_triangles": changed, "removed_triangles": removed, "replacement_triangles": added,
            "reclassified_area_m2": round(changed_area, 5), "final_triangles": len(output_faces)}


def apply(geometry, spec_path=SPEC):
    if not spec_path.exists():
        return {"enabled": False, "reason": "no reviewed source repair specification"}
    payload = spec_path.read_bytes()
    signature = hashlib.sha256(b"preserve-skirts-v2\n" + payload).hexdigest()
    if geometry.get("surface_repair_signature") == signature:
        return geometry["surface_repair_audit"]
    if geometry.get("surface_repair_signature"):
        raise ValueError("Changed repair specification requires fresh process.py geometry")
    spec = json.loads(payload)
    regions = [shape(record["geometry"]) for record in spec["regions"]]
    mask = unary_union(regions)
    bounds = [region.bounds for region in regions]
    audit = {"enabled": True, "scope": [r["id"] for r in spec["regions"]], "heights_preserved": True,
             "algorithm": "preserve-skirts-v2", "all_vertical_skirts_closed": True,
             "street_curb_materials_preserved": ["curb", "asphalt", "alley"]}
    for obj in geometry["objects"]:
        if obj["name"] in ("Ground", "Curbs"):
            audit[obj["name"]] = repair_object(obj, mask, bounds)
    geometry["surface_repair_signature"] = signature
    geometry["surface_repair_audit"] = audit
    return audit


def main():
    path = ROOT / ".work/city/build/pen_lucy_geom.json"
    geometry = json.loads(path.read_text())
    legacy_signature = hashlib.sha256(SPEC.read_bytes()).hexdigest()
    if geometry.get("surface_repair_signature") == legacy_signature:
        # Recover the one legacy staged source from the prepatch Blender backup.
        # Its original vertex prefix is still present in the v1 source, so use
        # those exact coordinates rather than Blender's float32 round trip.
        backup = ROOT / ".work/alive-next/original-curbs.json"
        original = json.loads(backup.read_text())
        index = next(i for i, obj in enumerate(geometry["objects"]) if obj["name"] == "Curbs")
        current = geometry["objects"][index]
        count = len(original["verts"])
        restored = np.asarray(current["verts"][:count])
        assert np.max(np.abs(restored - np.asarray(original["verts"]))) < .0001, "Backup vertex order does not match source"
        original["verts"] = current["verts"][:count]
        assert len(original["faces"]) // 3 == 155504, "Wrong original Curbs backup"
        geometry["objects"][index] = original
        geometry.pop("surface_repair_signature")
        geometry.pop("surface_repair_audit")
    audit = apply(geometry)
    temporary = path.with_suffix(".repair.tmp")
    temporary.write_text(json.dumps(geometry, separators=(",", ":")))
    temporary.replace(path)
    # All support heights and placed detail records are unchanged. Keep their
    # provenance pointing at the exact final source rather than stale bytes.
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    for folder in (ROOT / "godot/assets/data", ROOT / "blender/city/data"):
        manifest = folder / "pen_lucy_alive_world.json"
        data = json.loads(manifest.read_text())
        data["source_geometry_sha256"] = digest
        data["audit"]["source_surface_repairs"] = audit
        manifest.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    report = ROOT / ".work/alive-next/source-surface-repair.json"
    report.write_text(json.dumps(audit, indent=2) + "\n")
    print(json.dumps(audit))


if __name__ == "__main__":
    main()
