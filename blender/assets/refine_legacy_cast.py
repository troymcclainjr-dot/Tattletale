"""Fast, idempotent rebuild of the authored legacy cast's anatomical finish.

Run Blender headless with --python this_file -- [character IDs]. Uses the current
GLBs (not old preview/posed blend files); preserves all authored surface detail.
The ordinary full SDF generators apply the same finish at export_character().
"""
import os
import sys
import argparse
import json
import struct
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bpy
import claykit as ck
from lib.character_finish import HEIGHTS, apply_scene


def build(asset_id, source_dir=None):
    ck.reset()
    path = os.path.join(source_dir or os.path.join(ck.MODELS, "characters"), asset_id + ".glb")
    if source_dir:
        # Frozen baseline is read-only input, never a destination or a scene
        # restore. Explicit IDs prevent accidentally rebuilding the adult cast.
        with open(path, "rb") as source:
            raw = source.read()
        if raw[:4] != b"glTF":
            raise ValueError("Expected original GLB input: " + path)
        length = struct.unpack_from("<I", raw, 12)[0]
        document = json.loads(raw[20:20+length])
        rig = next(node for node in document["nodes"] if node.get("name") == "Rig")
        if rig.get("extras", {}).get("anatomy_version", 0):
            raise ValueError("--source-dir must contain unrefitted original GLBs: " + path)
    bpy.ops.import_scene.gltf(filepath=path)
    if apply_scene(asset_id):
        ck.export(asset_id, subdir="characters")
    else:
        print("[character_finish] already current: " + asset_id)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", help="Read frozen original baby/timmy GLBs; export only named IDs to normal destinations")
    parser.add_argument("ids", nargs="*")
    options = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if options.source_dir and (not options.ids or any(cid not in ("baby", "timmy") for cid in options.ids)):
        parser.error("--source-dir requires explicit baby and/or timmy IDs; other cast assets are not rewritten")
    ids = options.ids or list(HEIGHTS)
    for asset_id in ids:
        if asset_id not in HEIGHTS:
            parser.error("Unknown character: " + asset_id)
        build(asset_id, options.source_dir)
