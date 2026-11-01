"""Material-only alley repair, shared by source publication and Blender export.

Source preparation uses Shapely to partition mapped corridors exactly. Blender
only verifies the staged signature. Original triangles are partitioned on their
planes, never overlaid; grades, closed skirts and importer LODs remain authoritative.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).with_name("data") / "pen_lucy_alley_repairs.json"
GEOMETRY = ROOT / ".work/city/build/pen_lucy_geom.json"
ALGORITHM = "mapped-corridor-alley-asphalt-v2"


def covered(points, ring, tolerance=.002):
    """Boundary-inclusive point-in-polygon; tolerance handles source mm snaps."""
    points = np.asarray(points, float).reshape(-1, 2)
    ring = np.asarray(ring, float)
    inside = np.zeros(len(points), dtype=bool)
    boundary = inside.copy()
    for a, b in zip(ring[:-1], ring[1:]):
        delta = b - a
        length2 = float(delta @ delta)
        if length2 < 1e-16:
            continue
        t = np.clip((points - a) @ delta / length2, 0, 1)
        boundary |= np.sum((points - a - t[:, None] * delta) ** 2, axis=1) <= tolerance ** 2
        if abs(delta[1]) > 1e-12:
            crossing = (a[1] > points[:, 1]) != (b[1] > points[:, 1])
            inside ^= crossing & (points[:, 0] < a[0] + (points[:, 1] - a[1]) * delta[0] / delta[1])
    return inside | boundary


def repair_object(obj, regions, corridor_geometry):
    from shapely.geometry import Polygon, shape
    from shapely.ops import unary_union
    from shapely.strtree import STRtree
    from shapely import get_parts
    from surface_repairs import planar_pieces, vertical_remainder
    names = obj["matnames"]
    original = obj["mats"]
    vertices = np.asarray(obj["verts"], float).reshape(-1, 3)[:, [0, 2, 1]].copy()
    vertices[:, 2] *= -1
    faces = np.asarray(obj["faces"], dtype=np.int32).reshape(-1, 3)
    smooth = obj.get("smooth_faces", [obj["smooth"]] * len(faces))
    asphalt = names.index("asphalt") if "asphalt" in names else len(names)
    corridor = shape(corridor_geometry)
    strips = unary_union([shape(r["geometry"]) for r in regions])
    # Rounded source corners and closed skirts can differ by several mm.
    skirt_strip = strips.buffer(.01)
    masks = {"alley": corridor, "grass": strips, "dirt": skirt_strip}
    eligible = {"alley", "grass"} if obj["name"] == "Ground" else {"alley", "dirt"}
    parts = {m: list(get_parts(masks[m])) for m in eligible}
    trees = {m: STRtree(parts[m]) for m in eligible}
    bounds = {m: masks[m].bounds for m in eligible}
    output_vertices = list(vertices)
    output_faces, output_mats, output_smooth = [], [], []
    changed = added = 0
    area_by_kind = {m: 0.0 for m in eligible}
    faces_by_kind = {m: 0 for m in eligible}
    protected_counts = {m: original.count(names.index(m)) if m in names else 0 for m in ("sidewalk", "curb")}
    for i, face in enumerate(faces):
        material = names[original[i]]
        triangle = vertices[face]
        keep_original = True
        pieces = []
        if material in eligible:
            lo, hi = triangle[:, [0, 2]].min(axis=0), triangle[:, [0, 2]].max(axis=0)
            bb = bounds[material]
            if hi[0] >= bb[0] and lo[0] <= bb[2] and hi[1] >= bb[1] and lo[1] <= bb[3]:
                polygon = Polygon(triangle[:, [0, 2]])
                if polygon.area < 1e-9:
                    if obj["name"] == "Curbs":
                        kept, touched = vertical_remainder(triangle, masks[material])
                        if touched:
                            painted, _ = vertical_remainder(triangle, masks[material], inside=True)
                            pieces = [(t, original[i]) for t in kept] + [(t, asphalt) for t in painted]
                            keep_original = False
                else:
                    candidates = trees[material].query(polygon, predicate="intersects")
                    if len(candidates):
                        local = unary_union([parts[material][j] for j in candidates])
                        inside = polygon.intersection(local)
                        if inside.area > 1e-8:
                            area_by_kind[material] += inside.area
                            if polygon.area - inside.area < 1e-8:
                                output_faces.append(face.tolist()); output_mats.append(asphalt); output_smooth.append(smooth[i])
                                changed += 1; faces_by_kind[material] += 1
                                continue
                            pieces = [(t, original[i]) for t in planar_pieces(triangle, polygon.difference(local))]
                            pieces += [(t, asphalt) for t in planar_pieces(triangle, inside)]
                            keep_original = False
        if keep_original:
            output_faces.append(face.tolist()); output_mats.append(original[i]); output_smooth.append(smooth[i])
            continue
        changed += 1
        faces_by_kind[material] += 1
        if not pieces:
            raise ValueError("Alley partition attempted to remove a terrain triangle")
        # Check exact 3D coverage before rounded output. No open height skirts.
        before = np.linalg.norm(np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])) * .5
        after = sum(np.linalg.norm(np.cross(t[1] - t[0], t[2] - t[0])) * .5 for t, _ in pieces)
        if abs(before - after) > 1e-6:
            raise ValueError(f"Alley partition lost terrain coverage: {before} vs {after}")
        for tri, mat in pieces:
            start = len(output_vertices)
            output_vertices.extend(tri)
            output_faces.append([start, start + 1, start + 2]); output_mats.append(mat); output_smooth.append(smooth[i])
            added += 1
    if obj["name"] == "Ground":
        expected = sum(float(r["expected_ground_area_m2"]) for r in regions)
        if abs(area_by_kind["grass"] - expected) > .002:
            raise ValueError(f"Reviewed grass island changed: {area_by_kind['grass']} vs {expected}")
    if changed:
        if "asphalt" not in names:
            names.append("asphalt")
        native = np.asarray(output_vertices)[:, [0, 2, 1]]
        native[:, 1] *= -1
        obj["verts"] = obj["verts"] + native[len(vertices):].round(6).ravel().tolist()
        obj["faces"] = np.asarray(output_faces, dtype=np.int32).ravel().tolist()
        obj["mats"] = output_mats
        if "smooth_faces" in obj:
            obj["smooth_faces"] = [int(s) for s in output_smooth]
    for material, count in protected_counts.items():
        assert (obj["mats"].count(names.index(material)) if material in names else 0) == count
    return {"changed_source_triangles": changed, "changed_by_kind": faces_by_kind,
            "reclassified_projected_area_m2": {m: round(a, 8) for m, a in area_by_kind.items()},
            "original_triangles": len(faces), "final_triangles": len(output_faces),
            "replacement_triangles": added, "deleted_area_m2": 0, "protected_face_counts": protected_counts,
            "original_vertices_moved": 0, "added_interpolated_vertices": len(output_vertices) - len(vertices)}


def apply(geometry, spec_path=SPEC):
    payload = Path(spec_path).read_bytes()
    signature = hashlib.sha256(ALGORITHM.encode() + b"\n" + payload).hexdigest()
    if geometry.get("alley_repair_signature") == signature:
        return geometry["alley_repair_audit"]
    if geometry.get("alley_repair_signature"):
        raise ValueError("Changed alley specification requires fresh process.py source")
    spec = json.loads(payload)
    audit = {"algorithm": ALGORITHM, "sidewalks_preserved": True, "curbs_preserved": True,
             "original_vertex_positions_preserved": True, "collision_surface_preserved": True,
             "closed_vertical_skirts_preserved": True, "extra_render_nodes": 0, "extra_collision_shapes": 0}
    for obj in geometry["objects"]:
        if obj["name"] in ("Ground", "Curbs"):
            audit[obj["name"]] = repair_object(obj, spec["regions"], spec["alley_corridors"])
    if "Ground" not in audit or "Curbs" not in audit:
        raise ValueError("Expected source Ground and Curbs objects")
    geometry["alley_repair_signature"] = signature
    geometry["alley_repair_audit"] = audit
    return audit


def verify_staged(geometry, spec_path=SPEC):
    signature = hashlib.sha256(ALGORITHM.encode() + b"\n" + Path(spec_path).read_bytes()).hexdigest()
    if geometry.get("alley_repair_signature") != signature:
        raise ValueError("Run .work/city/venv/Scripts/python.exe blender/city/alley_surfaces.py --stage before Blender export")
    return geometry["alley_repair_audit"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", action="store_true", help="Atomically publish repaired source for the root-owned Blender export")
    args = parser.parse_args()
    geometry = json.loads(GEOMETRY.read_text())
    audit = apply(geometry)
    if args.stage:
        temporary = GEOMETRY.with_suffix(".alley.tmp")
        temporary.write_text(json.dumps(geometry, separators=(",", ":")))
        temporary.replace(GEOMETRY)
        # Only provenance changes: existing terrain support and detail records
        # remain identical because this repair never moves a vertex.
        digest = hashlib.sha256(GEOMETRY.read_bytes()).hexdigest()
        for folder in (ROOT / "godot/assets/data", ROOT / "blender/city/data"):
            manifest = folder / "pen_lucy_alive_world.json"
            data = json.loads(manifest.read_text())
            data["source_geometry_sha256"] = digest
            manifest.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    report = ROOT / "artifacts/sandbox-foundations/alley-surface-audit.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(audit, indent=2) + "\n")
    print(json.dumps(audit))


if __name__ == "__main__":
    main()
