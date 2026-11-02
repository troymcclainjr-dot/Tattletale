"""Correlate opt-in sustained transition timings with retained frame spikes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def analyze(result_path: Path) -> dict:
    result = json.loads(result_path.read_text(encoding="utf-8"))
    sustained = result["details"]["sustained"]
    if not sustained.get("transition_profiling"):
        raise ValueError("This run did not enable --profile-transitions")
    frames = json.loads(result_path.with_name("frames.json").read_text(encoding="utf-8"))
    if not frames or len(frames[0]) < 7:
        raise ValueError("Missing process-frame IDs; use the matching instrumented harness")
    stages = {}
    events = {}
    unloads = []
    for phase in sustained["phases"]:
        stream = phase["streaming"]
        stages = stream.get("profile_stages", stages)
        for event in stream.get("profile_slow_stages", []):
            events[(event["stage"], event["at_usec"])] = event
        batch = stream.get("profile_unload_batches", {})
        if batch and batch not in unloads:
            unloads.append(batch)
    relocations = sustained.get("relocations", [])
    compilation_events = []
    if len(frames[0]) >= 14:
        for previous, row in zip(frames, frames[1:]):
            changes = {name: row[index] - previous[index] for index, name in enumerate(
                ("canvas", "mesh", "surface", "draw", "specialization"), start=9)
                if row[index] > previous[index]}
            if changes:
                compilation_events.append({"process_frame": row[6], "changes": changes})
    worst = sorted(frames, key=lambda row: row[2], reverse=True)[:20]
    spikes = []
    for row in worst:
        process_frame = int(row[6])
        spikes.append({
            "seconds": row[0], "phase": row[1], "frame_ms": row[2], "gpu_ms": row[3],
            "render_cpu_ms": row[4], "process_frame": process_frame,
            "process_cpu_ms": row[7] if len(row) >= 14 else None,
            "physics_cpu_ms": row[8] if len(row) >= 14 else None,
            "render_setup_cpu_ms": row[14] if len(row) >= 18 else None,
            "process_to_predraw_ms": row[15] if len(row) >= 18 else None,
            "predraw_to_postdraw_ms": row[16] if len(row) >= 18 else None,
            "postdraw_to_process_ms": row[17] if len(row) >= 18 else None,
            "player_physics_cpu_ms": row[18] if len(row) >= 19 else None,
            "adjacent_player_stages": [e for e in sustained.get("player_slow_stages", []) if abs(int(e["frame"]) - process_frame) <= 1],
            "timeline": dict(zip(sustained.get("timeline_columns_after_player_cpu", []), row[19:])) if len(row) >= 31 else {},
            "adjacent_pipeline_compilations": [e for e in compilation_events if abs(int(e["process_frame"]) - process_frame) <= 1],
            "adjacent_slow_stages": [e for e in events.values() if abs(int(e["process_frame"]) - process_frame) <= 1],
            "adjacent_relocations": [e for e in relocations if abs(int(e["process_frame"]) - process_frame) <= 1],
            "adjacent_largest_unload_batches": [e for e in unloads if abs(int(e["max_frame"]) - process_frame) <= 1],
        })
    return {"source": str(result_path.resolve()), "passed": result.get("passed"),
            "stages": stages, "player_stages": sustained.get("player_stages", {}),
            "player_slow_stages": sustained.get("player_slow_stages", []),
            "relocations": relocations, "spikes": spikes, "pipeline_compilation_events": compilation_events,
            "notes": "Frames retain all relocation/loading costs. Stages are nested; do not sum inclusive totals. Adjacency includes the same/previous/next engine process frame because callback order and GPU timestamp lag differ. queue_free timing excludes deferred destruction; association alone does not establish causality."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    data = analyze(args.result)
    if args.output:
        args.output.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(json.dumps({"relocations": data["relocations"], "spikes": data["spikes"][:6]}, indent=2))
