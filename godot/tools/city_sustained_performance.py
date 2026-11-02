"""Root-owned no-focus sustained renderer runner; `snapshot` never starts Godot.

python godot/tools/city_sustained_performance.py snapshot --name baseline --ref c77e972
python godot/tools/city_sustained_performance.py run --name baseline --prepare-only
python godot/tools/city_sustained_performance.py run --name baseline --seconds 180
python godot/tools/city_sustained_performance.py snapshot --name candidate
python godot/tools/city_sustained_performance.py run --name candidate --seconds 180
python godot/tools/city_sustained_performance.py run --name instrumented-v2 --fixture life --seconds 15 --profile-city --profile-vehicle

Snapshots are private, immutable source copies, not worktrees or live junctions.
Both receive the same new fixture. The known no-focus launcher prepares a separate
window-safe project over each snapshot, while the existing A/B child runner owns
bounded cleanup and external CPU/memory telemetry. Only `run` starts an engine.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot"
WORK = ROOT / ".work" / "five-priorities-20261101" / "performance"
HARNESS = ("tests/city_sustained_performance.gd", "tests/city_sustained_performance_runner.gd",
           "tests/city_steady_endurance.gd", "tests/city_steady_endurance_runner.gd")
SAFE_NAME = re.compile(r"^[a-zA-Z0-9_-]{1,40}$")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(root):
    return {str(p.relative_to(root)).replace("\\", "/"): sha(p)
            for p in sorted(root.rglob("*")) if p.is_file()
            and not {".godot", "__pycache__"}.intersection(p.relative_to(root).parts) and p.suffix != ".pyc"}


def snapshot(name, revision=None, cache_from=None):
    target = WORK / name / "source" / "godot"
    if target.parent.exists():
        raise ValueError(f"Snapshot already exists; use a new name: {target.parent}")
    target.parent.mkdir(parents=True)
    if revision:
        commit = subprocess.check_output(["git", "rev-parse", "--verify", revision + "^{commit}"], cwd=ROOT, text=True).strip()
        archive = target.parent / "source.zip"
        subprocess.run(["git", "archive", "--format=zip", "--output", str(archive), commit, "godot"], cwd=ROOT, check=True)
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                out = (target.parent / member.filename).resolve()
                if not out.is_relative_to(target.parent.resolve()) or (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError("Unsafe archive member: " + member.filename)
            bundle.extractall(target.parent)
        source_origin = {"git_commit": commit, "archive_sha256": sha(archive)}
    else:
        before = manifest(SOURCE)
        shutil.copytree(SOURCE, target, ignore=shutil.ignore_patterns(".godot", "__pycache__", "*.pyc"))
        after = manifest(SOURCE)
        if before != after or manifest(target) != before:
            raise ValueError("Source changed during copy; snapshot is not acceptable. Use a new name after workers settle.")
        source_origin = {"working_tree": str(SOURCE), "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()}
    original = manifest(target)
    for file in HARNESS:
        (target / file).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / file, target / file)
    # Copy, never hardlink or junction, so later imports cannot mutate a baseline.
    cache_source = WORK / cache_from / "source" / "godot" / ".godot" if cache_from else SOURCE / ".godot"
    shutil.copytree(cache_source, target / ".godot", ignore=shutil.ignore_patterns("editor"))
    record = {"name": name, "created_unix": time.time(), "source": source_origin,
              "original_manifest": original, "staged_manifest": manifest(target),
              "harness_sha256": {file: sha(target / file) for file in HARNESS},
              "cache_source": str(cache_source),
              "cache": "Private byte copy of .godot imported resources; no import run; source tracked asset hashes define baseline"}
    (target.parent / "snapshot.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps({"snapshot": str(target), "files": len(record["staged_manifest"]), "source": source_origin}))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def run(options):
    source = WORK / options.name / "source" / "godot"
    record = json.loads((source.parent / "snapshot.json").read_text(encoding="utf-8"))
    if manifest(source) != record["staged_manifest"]:
        raise ValueError("Frozen snapshot changed; refusing incomparable run")
    life = options.fixture == "life"
    transitions = options.fixture == "transitions"
    steady = options.fixture == "steady"
    minimum, maximum = (5, 30) if life else ((32, 120) if transitions else ((60, 900) if steady else (180, 900)))
    if not minimum <= options.seconds <= maximum:
        raise ValueError("Life samples require 5–30s, transition diagnostics32–120s, steady60–900s, traversal180–900s")
    resolution_match = re.fullmatch(r"(\d{3,4})x(\d{3,4})", options.resolution)
    if not resolution_match:
        raise ValueError("Use an explicit WIDTHxHEIGHT render resolution")
    width, height = map(int, resolution_match.groups())
    if not (640 <= width <= 7680 and 480 <= height <= 4320):
        raise ValueError("Render resolution must be640–7680 by480–4320")
    if life and options.resolution != "1280x720":
        raise ValueError("The existing life fixture is fixed at1280x720; use steady/traversal for another resolution")
    if options.profile_vehicle and not options.profile_city:
        raise ValueError("--profile-vehicle requires --profile-city")
    if not life and (options.profile_city or options.profile_vehicle):
        raise ValueError("Existing query profiler belongs to --fixture life; sustained fixture is unchanged")
    if life and options.profile_transitions:
        raise ValueError("--profile-transitions requires the sustained district traversal fixture")
    launch = module("sustained_no_focus", ROOT / ".work" / "pacifist-foundation" / "run_render_validation.py")
    launch.SOURCE = source
    launch.WORK = WORK / options.name
    launch.STAGE_PARENT = WORK / options.name / "render"
    launch.STAGE = launch.STAGE_PARENT / "godot"
    run_id = ("life-profile-" if life else "sustained-") + options.name + "-" + str(time.time_ns())[-12:]
    # Short profile paths avoid Windows shader-cache MAX_PATH failures.
    profile = ROOT / ".work" / "sp" / run_id
    if profile.exists():
        raise ValueError("Profile already exists")
    sys.path.insert(0, str(SOURCE / "tools"))
    import godot_run
    import city_perf_ab as perf
    prefix = "[city_life_benchmark]" if life else "[sustained_performance]"
    perf.SAMPLE_BEGIN = prefix + " SAMPLE_BEGIN"
    perf.SAMPLE_END = prefix + " SAMPLE_END"
    output = WORK / options.name / run_id
    output.mkdir(parents=True)
    profiler_flags = (["--profile-city"] if options.profile_city else []) + (["--profile-vehicle"] if options.profile_vehicle else [])
    if options.profile_transitions or transitions:
        profiler_flags.append("--profile-transitions")
    if transitions:
        profiler_flags.append("--transition-probe")
    if life:
        args = ["--resolution", "1280x720", "--script", "res://tools/city_life_benchmark.gd", "--",
                "--offscreen-validation", "--sample-seconds", str(options.seconds), "--no-cpu-probe",
                "--outdir", str(output / "fixture"), *profiler_flags]
    else:
        script = "res://tests/city_steady_endurance.gd" if steady else "res://tests/city_sustained_performance.gd"
        args = ["--resolution", options.resolution, "--script", script, "--",
                "--offscreen-validation", "--session-run-id=" + run_id, "--sustained-seconds=" + str(options.seconds),
                "--render-width=" + str(width), "--render-height=" + str(height), "--steady-mode=" + options.steady_mode,
                *profiler_flags]
    launch.validate_args(args)
    with godot_run.GodotLock():
        receipt = launch.prepare()
        # Windows _console.exe is a tiny launcher, not the render process. Own
        # the native engine so telemetry and timeout cleanup target that process.
        engine = perf.resolve_engine_executable(godot_run.GODOT)
        command = [engine, "--path", str(launch.STAGE), "--windowed", "--position", "-10000,-10000",
                   "--audio-driver", "Dummy", *args]
        receipt.update({"command": command, "profile": str(profile), "run_id": run_id,
                        "snapshot": str(source.parent / "snapshot.json"), "prepare_only": options.prepare_only,
                        "fixture": options.fixture, "profiling_flags": profiler_flags,
                        "render_resolution": [width, height], "steady_mode": options.steady_mode if steady else None,
                        "measurement_kind": "short active-play query attribution; profiler overhead included" if life else ("short transition attribution; not sustained acceptance" if transitions else ("bounded-memory same-neighborhood endurance" if steady else "sustained world traversal"))})
        if not options.prepare_only:
            api = perf.WinApi()
            env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile / "Local"))
            (profile / "Local").mkdir(parents=True)
            receipt["run"] = perf.run_godot(command, launch.STAGE, env, options.seconds + 420, output / "engine.log", api,
                                            "normal", None, False, None, output / "gpu.csv")
            perf.write_telemetry_csv(output / "process-telemetry.csv", receipt["run"].pop("telemetry_samples"))
            result_path = output / "fixture" / "metrics.json" if life else ROOT / ".work" / "priorities-five" / "session-validation" / run_id / "result.json"
            receipt["result_path"] = str(result_path)
            receipt["result"] = json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else None
            receipt["source_unchanged"] = manifest(source) == record["staged_manifest"]
        (output / "launch.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(json.dumps({"receipt": str(output / "launch.json"), "result": receipt.get("result_path"), "prepare_only": options.prepare_only}))
        if not options.prepare_only:
            result = receipt["result"] or {}
            valid = result.get("valid_active_play") if life else result.get("passed")
            if life and options.profile_vehicle:
                valid = valid and result.get("vehicle_query_profiling") and bool(result.get("vehicle_queries"))
            if (receipt["run"]["exit_code"] != 0 or receipt["run"]["timed_out"] or not valid
                    or not receipt["source_unchanged"] or receipt["run"]["log"]["error_lines"]):
                return 1
    return 0


def trend(values):
    """OLS trend in units/second, plus endpoint and peak evidence."""
    if len(values) < 2:
        return {}
    xmean = statistics.mean(x for x, _ in values)
    ymean = statistics.mean(y for _, y in values)
    denominator = sum((x - xmean) ** 2 for x, _ in values)
    slope = sum((x - xmean) * (y - ymean) for x, y in values) / denominator if denominator else 0
    return {"first": values[0][1], "last": values[-1][1], "peak": max(y for _, y in values),
            "delta": values[-1][1] - values[0][1], "per_second": slope, "samples": len(values)}


def analyze(name):
    results = []
    for receipt_path in sorted((WORK / name).glob("sustained-*/launch.json")):
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("prepare_only"):
            continue
        result = receipt.get("result") or {}
        metrics = result.get("details", {}).get("sustained", {})
        sample_path = Path(receipt.get("result_path", "")).parent / "samples.jsonl"
        samples = [json.loads(line) for line in sample_path.read_text(encoding="utf-8").splitlines()] if sample_path.is_file() else []
        telemetry_path = receipt_path.parent / "process-telemetry.csv"
        external = list(csv.DictReader(telemetry_path.open(encoding="utf-8"))) if telemetry_path.is_file() else []
        external = [row for row in external if metrics.get("unix_start", float("inf")) <= float(row["unix"]) <= metrics.get("unix_end", 0)]
        memory = {key: trend([(float(row["wall_seconds"]), float(row[key])) for row in samples])
                  for key in ("memory_static", "objects", "nodes", "orphans") if samples and key in samples[0]}
        process = {key: trend([(float(row["unix"]), float(row[key])) for row in external if row.get(key)])
                   for key in (external[0].keys() if external else []) if key != "unix"}
        rendered_frames = samples[-1]["render_frame"] - samples[0]["render_frame"] if len(samples) >= 2 else 0
        native_process = not str(receipt.get("command", [""])[0]).lower().endswith("_console.exe")
        trace_path = sample_path.parent / "frames.json"
        windows = {}
        if trace_path.is_file():
            for frame in json.loads(trace_path.read_text(encoding="utf-8")):
                windows.setdefault(int(float(frame[0]) // 30), []).append(float(frame[2]))
        frame_windows = []
        for bucket, times in sorted(windows.items()):
            times.sort()
            frame_windows.append({"start_seconds": bucket * 30, "frames": len(times),
                                  "median_ms": statistics.median(times), "p95_ms": times[math.ceil(len(times) * .95) - 1],
                                  "max_ms": max(times)})
        entry = {"receipt": str(receipt_path), "passed": result.get("passed", False), "checks": result.get("checks", []),
                 "clean_run": bool(result.get("passed") and receipt.get("source_unchanged")
                                   and receipt.get("run", {}).get("exit_code") == 0
                                   and not receipt.get("run", {}).get("timed_out")
                                   and receipt.get("run", {}).get("log", {}).get("error_lines") == 0),
                 "runtime_log": receipt.get("run", {}).get("log", {}), "metrics": metrics,
                 "memory_trends": memory, "process_trends": process,
                 "population_ranges": {key: [min(row[key] for row in samples), max(row[key] for row in samples)]
                                       for key in ("ambient", "daily", "traffic") if samples},
                 "rendered_frame_delta": rendered_frames, "renderer_progress_verified": rendered_frames >= 60,
                 "external_process_telemetry_valid": native_process,
                 "frame_windows_30_seconds": frame_windows,
                 "gpu_timing_available": metrics.get("frame_metrics", {}).get("gpu_ms", {}).get("max", 0) > 0,
                 "traffic_distance_delta": samples[-1]["traffic_distance"] - samples[0]["traffic_distance"] if samples else None}
        results.append(entry)
    output = WORK / name / "analysis.json"
    output.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps({"analysis": str(output), "runs": len(results)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    snap = sub.add_parser("snapshot")
    snap.add_argument("--name", required=True)
    snap.add_argument("--ref")
    snap.add_argument("--cache-from", help="Reuse a frozen snapshot cache while the live project is being imported")
    runner = sub.add_parser("run")
    runner.add_argument("--name", required=True)
    runner.add_argument("--seconds", type=int, default=180)
    runner.add_argument("--fixture", choices=["sustained", "life", "transitions", "steady"], default="sustained")
    runner.add_argument("--resolution", default="1280x720", help="Explicit render size; set the actual display size to test native resolution")
    runner.add_argument("--steady-mode", choices=["stationary", "walk"], default="stationary")
    runner.add_argument("--profile-city", action="store_true")
    runner.add_argument("--profile-vehicle", action="store_true")
    runner.add_argument("--profile-transitions", action="store_true", help="Attribute relocation and streaming CPU; preserves the sustained workload")
    runner.add_argument("--prepare-only", action="store_true")
    reader = sub.add_parser("analyze")
    reader.add_argument("--name", required=True)
    options = parser.parse_args()
    if not SAFE_NAME.fullmatch(options.name):
        raise ValueError("Use a short alphanumeric snapshot name")
    if options.action == "snapshot":
        if options.cache_from and not SAFE_NAME.fullmatch(options.cache_from):
            raise ValueError("Use a short alphanumeric cache snapshot name")
        snapshot(options.name, options.ref, options.cache_from)
        return 0
    if options.action == "analyze":
        analyze(options.name)
        return 0
    return run(options)


if __name__ == "__main__":
    raise SystemExit(main())
