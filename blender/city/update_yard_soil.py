"""Restore continuous lawn in the existing city GLB without a Blender rebuild.

Ground dirt is exclusively the old yard_soil zone. Its top triangles must remain
because they fill holes in the surrounding grass. Both zones also generated
vertical skirts at their shared internal boundaries; discard only those skirts.
The original backup provides an unambiguous soil mask after material migration.
Requires the city Python environment (numpy/shapely).
"""
import json
import shutil
import struct
from pathlib import Path

import numpy as np
import shapely


def decode(blob):
    length, kind = struct.unpack_from("<II", blob, 12)
    assert kind == 0x4E4F534A
    return json.loads(blob[20:20 + length]), bytearray(blob[28 + length:])


def accessor(data, binary, index):
    item = data["accessors"][index]
    view = data["bufferViews"][item["bufferView"]]
    dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[item["componentType"]]
    width = {"SCALAR": 1, "VEC3": 3}[item["type"]]
    offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    return np.frombuffer(binary, dtype=dtype, count=item["count"] * width, offset=offset).reshape(-1, width)


def primitives(data, name):
    node = next(node for node in data["nodes"] if node["name"] == name)
    return data["meshes"][node["mesh"]]["primitives"]


def append_array(data, binary, values, kind, target):
    values = np.asarray(values, dtype="<u4" if kind == "SCALAR" else "<f4")
    padding = (-len(binary)) % 4
    binary.extend(b"\0" * padding)
    offset = len(binary)
    payload = values.tobytes()
    binary.extend(payload)
    view = len(data["bufferViews"])
    data["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload), "target": target})
    item = {"bufferView": view, "componentType": 5125 if kind == "SCALAR" else 5126,
            "count": len(values), "type": kind}
    if kind == "VEC3":
        item["min"] = values.min(axis=0).tolist()
        item["max"] = values.max(axis=0).tolist()
    index = len(data["accessors"])
    data["accessors"].append(item)
    return index


def merge_lawn(data, binary, lawn):
    ground = primitives(data, "Ground")
    pieces = [p for p in ground if p["material"] == lawn]
    if len(pieces) < 2:
        return 0
    assert all(set(p["attributes"]) == {"POSITION", "NORMAL"} for p in pieces)
    positions, normals, indices, offset = [], [], [], 0
    for piece in pieces:
        pos = accessor(data, binary, piece["attributes"]["POSITION"]).copy()
        positions.append(pos)
        normals.append(accessor(data, binary, piece["attributes"]["NORMAL"]).copy())
        indices.append(accessor(data, binary, piece["indices"]).ravel().copy().astype(np.uint32) + offset)
        offset += len(pos)
    # Identical seam positions and normals become genuinely shared vertices.
    # A single surface has one compression AABB and a connected LOD topology;
    # separate surface quantization/simplification caused the visible white ring.
    values = np.concatenate([np.concatenate(positions), np.concatenate(normals)], axis=1)
    welded, remap = np.unique(values, axis=0, return_inverse=True)
    merged_indices = remap[np.concatenate(indices)].astype("<u4")
    position_index = append_array(data, binary, welded[:, :3], "VEC3", 34962)
    normal_index = append_array(data, binary, welded[:, 3:], "VEC3", 34962)
    index_index = append_array(data, binary, merged_indices, "SCALAR", 34963)
    first = ground.index(pieces[0])
    ground[:] = [p for p in ground if p["material"] != lawn]
    ground.insert(first, {"attributes": {"POSITION": position_index, "NORMAL": normal_index},
                          "indices": index_index, "material": lawn})
    data["buffers"][0]["byteLength"] = len(binary)
    return len(values) - len(welded)


def migrate(path, backup):
    original = path.read_bytes()
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        shutil.copy2(path, backup)
    data, binary = decode(original)
    source, source_binary = decode(backup.read_bytes())
    materials = {item["name"]: index for index, item in enumerate(data["materials"])}
    source_dirt = next(i for i, item in enumerate(source["materials"]) if item["name"] == "clay_6e5a3c_r95")
    soil_primitive = next(p for p in primitives(source, "Ground") if p["material"] == source_dirt)
    soil_positions = accessor(source, source_binary, soil_primitive["attributes"]["POSITION"])
    soil_indices = accessor(source, source_binary, soil_primitive["indices"]).reshape(-1, 3)
    soil = shapely.union_all(shapely.polygons(soil_positions[soil_indices][:, :, [0, 2]]))
    changed = 0
    for primitive in primitives(data, "Ground"):
        if primitive["material"] == materials["clay_6e5a3c_r95"]:
            primitive["material"] = materials["clay_6a8a3a_r95"]
            changed += data["accessors"][primitive["indices"]]["count"] // 3
    removed = 0
    for primitive in primitives(data, "Curbs"):
        if primitive["material"] != materials["clay_6e5a3c_r95"]:
            continue
        positions = accessor(data, binary, primitive["attributes"]["POSITION"])
        indices = accessor(data, binary, primitive["indices"]).reshape(-1, 3)
        projected = positions[indices][:, :, [0, 2]]
        # Each vertical triangle projects to one boundary segment. All vertices
        # AND its midpoint must be on an original soil edge (1.5mm float/snap
        # tolerance); legitimate outer lawn skirts remain untouched.
        near = shapely.distance(shapely.points(projected.reshape(-1, 2)), soil.boundary).reshape(-1, 3) < 0.0015
        midpoint_near = shapely.distance(shapely.points(projected.mean(axis=1)), soil.boundary) < 0.0015
        discard = near.all(axis=1) & midpoint_near
        if not discard.any():
            continue
        kept = indices[~discard].copy().reshape(-1)
        removed += int(discard.sum())
        item = data["accessors"][primitive["indices"]]
        view = data["bufferViews"][item["bufferView"]]
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        # Rewrite only the surviving index prefix and shrink its accessor. The
        # unused tail is harmless padding; every other buffer offset stays exact.
        packed = kept.tobytes()
        binary[offset:offset + len(packed)] = packed
        item["count"] = len(kept)
        if "min" in item:
            item["min"] = [int(kept.min())]
        if "max" in item:
            item["max"] = [int(kept.max())]
    # Release buffer-backed numpy views before appending merged surface data.
    del soil_positions, soil_indices
    try:
        del positions, indices
    except UnboundLocalError:
        pass
    welded = merge_lawn(data, binary, materials["clay_6a8a3a_r95"])
    if changed or removed or welded:
        header = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        header += b" " * (-len(header) % 4)
        binary += b"\0" * (-len(binary) % 4)
        updated = struct.pack("<III", 0x46546C67, 2, 28 + len(header) + len(binary))
        updated += struct.pack("<II", len(header), 0x4E4F534A) + header
        updated += struct.pack("<II", len(binary), 0x004E4942) + binary
        temporary = path.with_suffix(".glb.tmp")
        temporary.write_bytes(updated)
        temporary.replace(path)
    # Preserve exact triangle positions/normals despite the new shared indices.
    lawn_name = "clay_6a8a3a_r95"
    old_lawn = [p for p in primitives(source, "Ground") if source["materials"][p["material"]]["name"] in [lawn_name, "clay_6e5a3c_r95"]]
    new_lawn = [p for p in primitives(data, "Ground") if p["material"] == materials[lawn_name]]
    for semantic in ["POSITION", "NORMAL"]:
        def triangle_values(doc, buffer, pieces):
            return np.concatenate([accessor(doc, buffer, p["attributes"][semantic])[accessor(doc, buffer, p["indices"]).ravel()] for p in pieces])
        assert np.array_equal(triangle_values(source, source_binary, old_lawn), triangle_values(data, binary, new_lawn))
    return {"repainted_top_triangles": changed, "removed_internal_skirt_triangles": removed,
            "welded_lawn_vertices": welded, "lawn_surfaces": len(new_lawn),
            "soil_patches": len(shapely.get_parts(soil)), "terrain_top_triangles_unchanged": True}



if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    print(json.dumps(migrate(root / "godot/assets/models/city/pen_lucy.glb",
                            root / ".work/life-reactions/pen_lucy_before_yard_soil.glb")))
