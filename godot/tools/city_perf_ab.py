"""Matched A/B benchmark harness for the Pen Lucy city. Root-run only, workers idle.

    python godot/tools/city_perf_ab.py run --label final-vs-baseline --dry-run
    python godot/tools/city_perf_ab.py run --label final-vs-baseline
    python godot/tools/city_perf_ab.py run --label cap120 --fps-cap 120
    python godot/tools/city_perf_ab.py run --label counter-overhead --baseline godot --candidate godot --candidate-driver-arg=--perf-counters
    python godot/tools/city_perf_ab.py analyze artifacts/priorities-five/perf-ab/final-vs-baseline
    python godot/tools/city_perf_ab.py fingerprint godot

Each variant runs from a frozen staged copy of its tree (mtimes preserved) into which the
*same* benchmark driver bytes are injected, with its own fresh isolated user profile (never
%APPDATA%), under the shared Godot lock. One unmeasured warm-up per variant fills caches;
measured runs follow in counterbalanced ABBA order. The child is opted out of Windows power
throttling (EcoQoS) unless --keep-power-throttling. Telemetry: system/child CPU, child memory,
CPU performance counter and nvidia-smi GPU clocks when available. Driver arguments that start
with "-" must be attached with "=" (argparse), e.g. --driver-arg=--lead-in-seconds --driver-arg=2.
Results go to artifacts/priorities-five/perf-ab/<label>; staged trees and screenshots
stay in .work/priorities-five/perf-ab/<label>. Fresh profiles use short unique paths in
.work/pf/<session>/<variant> to leave room for Godot's long shader-cache names on Windows.
"""
from __future__ import annotations

import argparse
import contextlib
import csv
import hashlib
import json
import math
import os
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
ROOT = PROJECT.parent
DEFAULT_BASELINE = ROOT / ".work" / "priorities-five" / "baseline" / "godot"
DEFAULT_RESULTS = ROOT / "artifacts" / "priorities-five" / "perf-ab"
DEFAULT_WORK = ROOT / ".work" / "priorities-five" / "perf-ab"
PROFILE_ROOT = ROOT / ".work" / "pf"
# Injected into both staged trees from the harness's own project, byte for byte.
HARNESS_FILES = (
    "tools/city_life_benchmark.gd",
    "tools/city_life_benchmark_driver.gd",
    "tools/city_perf_stats.gd",
    "tools/city_perf_timeline.gd",
)
ENTRY = "res://tools/city_life_benchmark.gd"
STAGE_MARKER = "perf-ab-stage.json"
PROFILE_MARKER = "perf-ab-profile.json"
SAMPLE_BEGIN = "[city_life_benchmark] SAMPLE_BEGIN"
SAMPLE_END = "[city_life_benchmark] SAMPLE_END"
ERROR_PREFIXES = ("SCRIPT ERROR:", "SHADER ERROR:", "ERROR:")
LABEL = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
IMPORTED_STEM = re.compile(r"^(?P<stem>.+-[0-9a-f]{32})\.")
SKIP_DIRS = {"__pycache__"}
PROBE_TOLERANCE = 0.03
OTHER_CORES_LIMIT = 0.5
GPU_CLOCK_TOLERANCE = 0.10
GPU_FIELDS = (
    "timestamp,clocks.gr,clocks.mem,utilization.gpu,power.draw,temperature.gpu,pstate,clocks_event_reasons.active",
    "timestamp,clocks.gr,clocks.mem,utilization.gpu,power.draw,temperature.gpu,pstate,clocks_throttle_reasons.active",
    "timestamp,clocks.gr,clocks.mem,utilization.gpu,power.draw,temperature.gpu,pstate",
)

# (key, path into metrics.json, lower_is_better). Paths may be dotted; None if absent.
METRICS = (
    ("mean_frame_ms", "mean_frame_ms", True),
    ("frame_median_ms", "frame_ms.median", True),
    ("frame_p95_ms", "frame_ms.p95", True),
    ("frame_p99_ms", "frame_ms.p99", True),
    ("time_weighted_p95_ms", "time_weighted_frame_ms.p95", True),
    ("render_only_cycle_mean_ms", "render_only_cycle_ms.mean", True),
    ("physics_cycle_mean_ms", "physics_cycle_ms.mean", True),
    ("work_mean_ms", "work_ms.mean", True),
    ("process_scripts_ms_per_frame", "timeline_ms.process_scripts_ms.mean", True),
    ("render_ms_per_frame", "timeline_ms.render_ms.mean", True),
    ("process_pre_ms_per_frame", "timeline_ms.process_pre_ms.mean", True),
    ("process_post_ms_per_frame", "timeline_ms.process_post_ms.mean", True),
    ("tail_ms_per_frame", "timeline_ms.tail_ms.mean", True),
    ("driver_ms_per_frame", "timeline_ms.driver_ms.mean", True),
    ("process_scripts_ms_per_s", "timeline_ms.process_scripts_ms.per_second", True),
    ("render_ms_per_s", "timeline_ms.render_ms.per_second", True),
    ("physics_scripts_ms_per_s", "timeline_ms.physics_scripts_ms.per_second", True),
    ("physics_engine_ms_per_s", "timeline_ms.physics_engine_ms.per_second", True),
    ("tick_scripts_ms", "timeline_ticks_ms.scripts_ms.mean", True),
    ("tick_engine_ms", "timeline_ticks_ms.engine_ms.mean", True),
    ("traffic_ms_per_s", "physics_components_ms_per_second.traffic", True),
    ("npcs_ms_per_s", "physics_components_ms_per_second.npcs", True),
    ("residents_ms_per_s", "physics_components_ms_per_second.residents", True),
    ("combat_law_shops_ms_per_s", "physics_components_ms_per_second.combat", True),
    ("clock_ms_per_s", "physics_components_ms_per_second.clock", True),
    ("missions_ms_per_s", "physics_components_ms_per_second.missions", True),
    ("level_ui_ms_per_s", "level_ui_ms_per_second", True),
    ("player_physics_ms_per_s", "player_physics_ms_per_second", True),
    ("traffic_ms_per_tick", "physics_components_ms.traffic.mean", True),
    ("viewport_render_cpu_mean_ms", "viewport_render_cpu_ms.mean", True),
    ("viewport_gpu_median_ms", "viewport_gpu_ms.median", True),
    ("draw_calls_median", "draw_calls.median", True),
    ("objects_median", "objects_in_frame.median", True),
    ("primitives_median", "primitives_in_frame.median", True),
    ("static_memory_peak_mb", "engine_counters_end.static_memory_peak_bytes", True),
    ("video_memory_mb", "engine_counters_end.video_memory_bytes", True),
    ("nodes_end", "engine_counters_end.nodes", True),
    ("delivered_fps", "delivered_fps", False),
    ("cpu_probe_script_usec", "cpu_probe.before.script_usec", True),
    ("cpu_probe_native_usec", "cpu_probe.before.native_sort_usec", True),
)
BYTE_METRICS = {"static_memory_peak_mb", "video_memory_mb"}
HEADLINE = ("mean_frame_ms", "frame_p95_ms", "frame_p99_ms", "render_only_cycle_mean_ms", "physics_cycle_mean_ms",
            "process_scripts_ms_per_frame", "render_ms_per_frame", "physics_scripts_ms_per_s", "physics_engine_ms_per_s",
            "traffic_ms_per_s", "npcs_ms_per_s", "residents_ms_per_s", "combat_law_shops_ms_per_s", "level_ui_ms_per_s",
            "draw_calls_median", "viewport_gpu_median_ms", "static_memory_peak_mb", "delivered_fps")


# ---------------------------------------------------------------- fingerprints

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def category(relative: str) -> str:
    """Runtime content decides the comparison; tests/tools/docs are tracked separately."""
    if relative.startswith(".godot/"):
        return "import_cache"
    if relative.startswith("tests/"):
        return "tests"
    if relative.startswith("tools/"):
        return "tools"
    if relative.endswith(".md"):
        return "docs"
    return "runtime"


def tree_manifest(root: Path, skip: set[str] | None = None) -> dict[str, dict[str, str]]:
    """Category -> {posix relative path: sha256}. .godot/editor is editor state, not runtime."""
    skip = skip or set()
    result: dict[str, dict[str, str]] = {}
    for directory, folders, files in os.walk(root):
        relative_dir = Path(directory).relative_to(root).as_posix()
        folders[:] = sorted(f for f in folders if f not in SKIP_DIRS and not (relative_dir == ".godot" and f == "editor"))
        for name in sorted(files):
            if name.endswith(".pyc") or name == STAGE_MARKER:
                continue
            relative = name if relative_dir == "." else f"{relative_dir}/{name}"
            if relative in skip:
                continue
            result.setdefault(category(relative), {})[relative] = sha256_file(Path(directory) / name)
    return result


def digest(entries: dict[str, str]) -> str:
    text = "".join(f"{key}\t{entries[key]}\n" for key in sorted(entries))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def manifest_diff(before: dict[str, str], after: dict[str, str]) -> dict[str, list[str]]:
    return {
        "added": sorted(set(after) - set(before)),
        "removed": sorted(set(before) - set(after)),
        "changed": sorted(key for key in set(before) & set(after) if before[key] != after[key]),
    }


def fingerprint(root: Path, skip: set[str] | None = None) -> dict:
    manifest = tree_manifest(root, skip)
    return {
        "root": str(root),
        "digests": {name: digest(entries) for name, entries in sorted(manifest.items())},
        "file_counts": {name: len(entries) for name, entries in sorted(manifest.items())},
        "manifest": manifest,
    }


def parse_import(text: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
        elif "=" in line:
            key, value = line.split("=", 1)
            sections.setdefault(current, {})[key.strip()] = value.strip()
    return sections


def _quoted(value: str) -> list[str]:
    return re.findall(r'"([^"]*)"', value)


def _res_path(root: Path, res: str) -> Path:
    return root / res.removeprefix("res://")


def import_freshness(root: Path) -> dict:
    """Godot's .md5 sidecar stores the source MD5 the cached import was built from.
    Stale (source changed) or missing cache output blocks a run; an orphaned .import
    whose source was deleted is reported but cannot affect what the game loads."""
    checked, stale, missing, invalid, orphans = 0, [], [], [], []
    for path in sorted(root.rglob("*.import")):
        relative = path.relative_to(root).as_posix()
        if relative.startswith(".godot/") or any(part in SKIP_DIRS for part in path.parts):
            continue
        sections = parse_import(path.read_text(encoding="utf-8", errors="replace"))
        if sections.get("remap", {}).get("valid") == "false":
            invalid.append(relative)
            continue
        deps = sections.get("deps", {})
        sources = _quoted(deps.get("source_file", ""))
        destinations = _quoted(deps.get("dest_files", ""))
        if not sources or not destinations:
            continue
        source = _res_path(root, sources[0])
        if not source.is_file():
            orphans.append(relative)
            continue
        checked += 1
        match = IMPORTED_STEM.match(Path(destinations[0]).name)
        sidecar = _res_path(root, destinations[0]).parent / f"{match.group('stem')}.md5" if match else None
        if sidecar is None or not sidecar.is_file() or not all(_res_path(root, d).is_file() for d in destinations):
            missing.append(relative)
            continue
        recorded = _quoted(parse_import(sidecar.read_text(encoding="utf-8", errors="replace")).get("", {}).get("source_md5", ""))
        actual = hashlib.md5(source.read_bytes()).hexdigest()
        if not recorded or recorded[0] != actual:
            stale.append(relative)
    return {"checked": checked, "stale": stale, "missing": missing, "invalid": invalid, "orphans": orphans,
            "fresh": not stale and not missing}


# ------------------------------------------------------------- staging/profiles

def harness_payload(source_project: Path = PROJECT) -> dict[str, bytes]:
    return {relative: (source_project / relative).read_bytes() for relative in HARNESS_FILES}


def stage_tree(source: Path, destination: Path, payload: dict[str, bytes], reuse: bool = False) -> dict:
    """Frozen copy of `source` with the harness files overwritten; mtimes preserved."""
    source_print = fingerprint(source, set(payload))
    marker = destination / STAGE_MARKER
    if reuse and marker.is_file():
        recorded = json.loads(marker.read_text(encoding="utf-8"))
        harness = {k: hashlib.sha256(v).hexdigest() for k, v in payload.items()}
        current = {k: sha256_file(destination / k) if (destination / k).is_file() else None for k in payload}
        if (recorded.get("source_digests") == source_print["digests"] and recorded.get("harness") == harness
                and current == harness and fingerprint(destination, set(payload))["digests"] == recorded.get("staged_digests")):
            return recorded | {"reused": True}
    if destination.exists():
        if not marker.is_file():
            raise SystemExit(f"[perf_ab] refusing to replace {destination}: it is not a harness stage")
        shutil.rmtree(destination)

    def ignore(directory: str, names: list[str]) -> set[str]:
        ignored = {n for n in names if n in SKIP_DIRS or n.endswith(".pyc")}
        if Path(directory).name == ".godot" and "editor" in names:
            ignored.add("editor")
        return ignored

    shutil.copytree(source, destination, copy_function=shutil.copy2, ignore=ignore)
    for relative, content in payload.items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    staged_print = fingerprint(destination, set(payload))
    record = {
        "source": str(source), "destination": str(destination), "staged_unix": time.time(),
        "source_digests": source_print["digests"], "staged_digests": staged_print["digests"],
        "copy_identical": source_print["digests"] == staged_print["digests"],
        "harness": {k: hashlib.sha256(v).hexdigest() for k, v in payload.items()},
        "harness_replaced_tree_files": sorted(k for k in payload if (source / k).is_file()
                                              and (source / k).read_bytes() != payload[k]),
        "manifest": source_print["manifest"], "reused": False,
    }
    marker.write_text(json.dumps(record, indent=1), encoding="utf-8")
    return record


def fresh_profile(profile: Path) -> Path:
    if profile.exists():
        if not (profile / PROFILE_MARKER).is_file():
            raise SystemExit(f"[perf_ab] refusing to clear {profile}: it is not a harness profile")
        shutil.rmtree(profile)
    for child in ("Roaming", "Local", "temp"):
        (profile / child).mkdir(parents=True, exist_ok=True)
    (profile / PROFILE_MARKER).write_text(json.dumps({"created_unix": time.time()}), encoding="utf-8")
    return profile


def allocate_profiles(root: Path = PROFILE_ROOT) -> dict[str, Path]:
    """Reserve a new short session directory atomically; never clear previous runs."""
    root.mkdir(parents=True, exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix="", dir=root)).resolve()
    return {variant: fresh_profile(session / variant) for variant in ("A", "B")}


def resolve_engine_executable(executable: str, platform_name: str | None = None) -> str:
    """Measure the native engine, not Windows' small console-launcher process."""
    if (os.name if platform_name is None else platform_name) != "nt":
        return executable
    resolved = Path(shutil.which(executable) or executable)
    suffix = "_console.exe"
    if not resolved.name.lower().endswith(suffix):
        return executable
    native = resolved.with_name(resolved.name[:-len(suffix)] + ".exe")
    if not native.is_file():
        raise SystemExit(f"[perf_ab] console launcher {resolved} has no native engine sibling {native}; "
                         "pass --godot with the native engine executable for valid process telemetry")
    return str(native.resolve())


def isolated_env(profile: Path, base: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(os.environ if base is None else base)
    env["APPDATA"] = str(profile / "Roaming")
    env["LOCALAPPDATA"] = str(profile / "Local")
    for variable in ("TEMP", "TMP", "TMPDIR"):
        env[variable] = str(profile / "temp")
    return env


# ------------------------------------------------------------------ planning

def plan_order(pairs: int, order: str = "abba", seed: int = 0) -> list[str]:
    if pairs < 1:
        raise ValueError("at least one pair is required")
    sequence: list[str] = []
    rng = random.Random(seed)
    for index in range(pairs):
        if order == "alternate":
            pair = ["A", "B"]
        elif order == "abba":
            pair = ["A", "B"] if index % 2 == 0 else ["B", "A"]
        elif order == "random":
            pair = ["A", "B"]
            rng.shuffle(pair)
        else:
            raise ValueError(f"unknown order {order!r}")
        sequence.extend(pair)
    return sequence


def driver_arguments(options: dict, run_dir: Path, extra: list[str]) -> list[str]:
    arguments = ["--offscreen-validation", "--private-viewport", "--outdir", run_dir.as_posix(),
                 "--sample-seconds", str(options["sample_seconds"]),
                 "--render-width", str(options["width"]), "--render-height", str(options["height"]),
                 "--render-quality", options["quality"], "--fps-cap", str(options["fps_cap"])]
    if options.get("mission_route", True):
        arguments.append("--mission-route")
    if options.get("profile_city", True):
        arguments.append("--profile-city")
    return arguments + list(extra)


def build_command(godot: str, tree: Path | None, run_dir: Path, options: dict, extra: list[str]) -> list[str]:
    """Same window/audio arguments godot_run.py uses for --offscreen-validation."""
    command = [godot]
    if tree is not None:
        command += ["--path", str(tree)]
    command += ["--windowed", "--position", "-10000,-10000", "--audio-driver", "Dummy",
                "--resolution", f"{options['width']}x{options['height']}", "--script", ENTRY, "--"]
    return command + driver_arguments(options, run_dir, extra)


# ------------------------------------------------------------------ log scan

def scan_log(lines: list[str]) -> dict:
    """Lines between the driver's sample markers are engine output during measurement."""
    inside = False
    during, errors, during_errors, warnings = [], [], [], 0
    began = ended = False
    for raw in lines:
        line = raw.rstrip("\r\n")
        stripped = line.lstrip()
        if stripped.startswith(SAMPLE_BEGIN):
            inside, began = True, True
            continue
        if stripped.startswith(SAMPLE_END):
            inside, ended = False, True
            continue
        is_error = stripped.startswith(ERROR_PREFIXES)
        warnings += int(stripped.startswith("WARNING:"))
        if is_error:
            errors.append(line)
        if inside and stripped:
            during.append(line)
            if is_error:
                during_errors.append(line)
    return {"sample_markers": began and ended, "lines_during_sample": len(during),
            "first_lines_during_sample": during[:20], "error_lines": len(errors),
            "first_error_lines": errors[:20], "error_lines_during_sample": len(during_errors), "warning_lines": warnings}


# ------------------------------------------------------------------ telemetry

class WinApi:
    """ctypes wrappers; every failure is recorded, never raised into a run."""

    def __init__(self) -> None:
        self.available = os.name == "nt"
        self.errors: list[str] = []
        if not self.available:
            return
        import ctypes
        from ctypes import wintypes
        self.ctypes, self.wintypes = ctypes, wintypes

        class FILETIME(ctypes.Structure):
            _fields_ = [("low", wintypes.DWORD), ("high", wintypes.DWORD)]

        class MEMORY(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                        ("PrivateUsage", ctypes.c_size_t)]

        class THROTTLE(ctypes.Structure):
            _fields_ = [("Version", wintypes.ULONG), ("ControlMask", wintypes.ULONG), ("StateMask", wintypes.ULONG)]

        class PDHVALUE(ctypes.Structure):
            _fields_ = [("CStatus", wintypes.DWORD), ("doubleValue", ctypes.c_double)]

        self.FILETIME, self.MEMORY, self.THROTTLE, self.PDHVALUE = FILETIME, MEMORY, THROTTLE, PDHVALUE
        self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        try:
            self.pdh = ctypes.WinDLL("pdh")
        except OSError as error:
            self.pdh = None
            self.errors.append(f"pdh unavailable: {error}")
        self._pdh_query = None
        self._pdh_counters: dict[str, object] = {}

    @staticmethod
    def _ft(value) -> int:
        return (value.high << 32) | value.low

    def system_times(self) -> tuple[int, int, int] | None:
        if not self.available:
            return None
        idle, kernel, user = self.FILETIME(), self.FILETIME(), self.FILETIME()
        ok = self.kernel32.GetSystemTimes(self.ctypes.byref(idle), self.ctypes.byref(kernel), self.ctypes.byref(user))
        return (self._ft(idle), self._ft(kernel), self._ft(user)) if ok else None

    def process_times(self, handle: int) -> int | None:
        if not self.available:
            return None
        values = [self.FILETIME() for _ in range(4)]
        ok = self.kernel32.GetProcessTimes(self.wintypes.HANDLE(handle), *[self.ctypes.byref(v) for v in values])
        return self._ft(values[2]) + self._ft(values[3]) if ok else None

    def process_memory(self, handle: int) -> dict | None:
        if not self.available:
            return None
        counters = self.MEMORY()
        counters.cb = self.ctypes.sizeof(self.MEMORY)
        ok = self.kernel32.K32GetProcessMemoryInfo(self.wintypes.HANDLE(handle), self.ctypes.byref(counters), counters.cb)
        if not ok:
            return None
        return {"working_set": counters.WorkingSetSize, "peak_working_set": counters.PeakWorkingSetSize,
                "private": counters.PrivateUsage, "peak_pagefile": counters.PeakPagefileUsage}

    def disable_power_throttling(self, handle: int) -> dict:
        """ControlMask set with StateMask clear opts out of EcoQoS execution-speed throttling."""
        if not self.available:
            return {"applied": False, "reason": "not Windows"}
        state = self.THROTTLE(1, 0x1 | 0x4, 0)
        ok = self.kernel32.SetProcessInformation(self.wintypes.HANDLE(handle), 4, self.ctypes.byref(state),
                                                 self.ctypes.sizeof(state))
        return {"applied": bool(ok), "error": 0 if ok else self.ctypes.get_last_error(),
                "control_mask": "EXECUTION_SPEED|IGNORE_TIMER_RESOLUTION", "state_mask": 0}

    def set_affinity(self, handle: int, mask: int) -> dict:
        if not self.available:
            return {"applied": False, "reason": "not Windows"}
        ok = self.kernel32.SetProcessAffinityMask(self.wintypes.HANDLE(handle), self.ctypes.c_size_t(mask))
        return {"applied": bool(ok), "mask": hex(mask), "error": 0 if ok else self.ctypes.get_last_error()}

    def open_cpu_counters(self) -> bool:
        if not self.available or self.pdh is None:
            return False
        try:
            query = self.ctypes.c_void_p()
            if self.pdh.PdhOpenQueryW(None, None, self.ctypes.byref(query)) != 0:
                return False
            self._pdh_query = query
            for key, path in (("cpu_performance_pct", r"\Processor Information(_Total)\% Processor Performance"),
                              ("cpu_nominal_mhz", r"\Processor Information(_Total)\Processor Frequency")):
                counter = self.ctypes.c_void_p()
                if self.pdh.PdhAddEnglishCounterW(query, self.ctypes.c_wchar_p(path), None, self.ctypes.byref(counter)) == 0:
                    self._pdh_counters[key] = counter
            self.pdh.PdhCollectQueryData(query)
            return bool(self._pdh_counters)
        except (OSError, AttributeError) as error:
            self.errors.append(f"pdh: {error}")
            return False

    def read_cpu_counters(self) -> dict:
        if self._pdh_query is None:
            return {}
        result = {}
        try:
            if self.pdh.PdhCollectQueryData(self._pdh_query) != 0:
                return {}
            for key, counter in self._pdh_counters.items():
                value = self.PDHVALUE()
                if self.pdh.PdhGetFormattedCounterValue(counter, 0x200, None, self.ctypes.byref(value)) == 0:
                    result[key] = value.doubleValue
        except (OSError, AttributeError) as error:
            self.errors.append(f"pdh read: {error}")
        return result

    def close_cpu_counters(self) -> None:
        if self._pdh_query is not None:
            try:
                self.pdh.PdhCloseQuery(self._pdh_query)
            except (OSError, AttributeError):
                pass
            self._pdh_query = None
            self._pdh_counters = {}


class Telemetry(threading.Thread):
    """Samples every `interval` seconds: system/child CPU in logical cores, child memory, CPU perf."""

    def __init__(self, api: WinApi, handle: int, interval: float = 0.25) -> None:
        super().__init__(name="perf-telemetry", daemon=True)
        self.api, self.handle, self.interval = api, handle, interval
        self.samples: list[dict] = []
        # Not `_stop`: threading.Thread uses a private method of that name in join().
        self._halt = threading.Event()
        self.cores = os.cpu_count() or 1

    def run(self) -> None:
        cpu_counters = self.api.open_cpu_counters()
        previous_system = self.api.system_times()
        previous_child = self.api.process_times(self.handle)
        previous_time = time.time()
        while not self._halt.wait(self.interval):
            now = time.time()
            system = self.api.system_times()
            child = self.api.process_times(self.handle)
            sample: dict = {"unix": now}
            elapsed = (now - previous_time) * 1e7
            if system and previous_system and elapsed > 0:
                idle = system[0] - previous_system[0]
                busy = (system[1] - previous_system[1]) + (system[2] - previous_system[2]) - idle
                sample["system_cores"] = max(0.0, busy / elapsed)
            if child is not None and previous_child is not None and elapsed > 0:
                sample["child_cores"] = max(0.0, (child - previous_child) / elapsed)
            memory = self.api.process_memory(self.handle)
            if memory:
                sample.update(memory)
            if cpu_counters:
                sample.update(self.api.read_cpu_counters())
            self.samples.append(sample)
            previous_system, previous_child, previous_time = system, child, now
        self.api.close_cpu_counters()

    def stop(self) -> None:
        self._halt.set()


def gpu_fields(executable: str | None) -> str | None:
    if executable is None:
        return None
    for fields in GPU_FIELDS:
        try:
            probe = subprocess.run([executable, f"--query-gpu={fields}", "--format=csv,noheader,nounits"],
                                   capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if probe.returncode == 0 and probe.stdout.strip():
            return fields
    return None


def telemetry_window(samples: list[dict], start: float | None, end: float | None) -> dict:
    """Aggregate telemetry inside the driver's sample window (unix seconds)."""
    if start is None or end is None:
        return {}
    inside = [s for s in samples if start <= float(s.get("unix", 0.0)) <= end]

    def values(key: str) -> list[float]:
        return [float(s[key]) for s in inside if key in s]

    result: dict = {"samples": len(inside)}
    for key in ("system_cores", "child_cores", "cpu_performance_pct", "cpu_nominal_mhz"):
        data = values(key)
        if data:
            result[f"{key}_mean"] = statistics.fmean(data)
    pairs = [(float(s["system_cores"]), float(s["child_cores"])) for s in inside if "system_cores" in s and "child_cores" in s]
    if pairs:
        result["other_cores_mean"] = statistics.fmean(max(0.0, system - child) for system, child in pairs)
        result["other_cores_max"] = max(max(0.0, system - child) for system, child in pairs)
    for key in ("working_set", "private"):
        data = values(key)
        if data:
            result[f"{key}_max_mb"] = max(data) / 1048576.0
    peak = values("peak_working_set")
    if peak:
        result["peak_working_set_mb"] = max(peak) / 1048576.0
    if "cpu_performance_pct_mean" in result and "cpu_nominal_mhz_mean" in result:
        result["cpu_effective_mhz_mean"] = result["cpu_nominal_mhz_mean"] * result["cpu_performance_pct_mean"] / 100.0
    return result


def parse_gpu_csv(path: Path, fields: str | None) -> list[dict]:
    if fields is None or not path.is_file():
        return []
    names = [f.strip() for f in fields.split(",")]
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        cells = [c.strip() for c in line.split(",")]
        if len(cells) != len(names):
            continue
        row = dict(zip(names, cells))
        try:
            row["unix"] = time.mktime(time.strptime(row["timestamp"].split(".")[0], "%Y/%m/%d %H:%M:%S"))
        except (ValueError, KeyError):
            continue
        rows.append(row)
    return rows


def gpu_window(rows: list[dict], start: float | None, end: float | None) -> dict:
    if start is None or end is None:
        return {}
    # nvidia-smi timestamps have one-second resolution; include the boundary seconds.
    inside = [r for r in rows if start - 1.0 <= r["unix"] <= end + 1.0]

    def numbers(key: str) -> list[float]:
        found = []
        for row in inside:
            try:
                found.append(float(row[key]))
            except (KeyError, ValueError):
                pass
        return found

    result: dict = {"samples": len(inside)}
    clocks = numbers("clocks.gr")
    if clocks:
        result.update({"graphics_clock_median_mhz": statistics.median(clocks), "graphics_clock_min_mhz": min(clocks),
                       "graphics_clock_max_mhz": max(clocks)})
    for key, name in (("utilization.gpu", "utilization_mean_pct"), ("power.draw", "power_mean_w"),
                      ("temperature.gpu", "temperature_max_c")):
        data = numbers(key)
        if data:
            result[name] = max(data) if name.endswith("max_c") else statistics.fmean(data)
    reasons = sorted({r.get("clocks_event_reasons.active", r.get("clocks_throttle_reasons.active", "")) for r in inside} - {""})
    if reasons:
        result["clock_reasons"] = reasons
    return result


# ------------------------------------------------------------------ host info

def host_info(godot: str | None, nvidia: str | None) -> dict:
    info: dict = {"platform": platform.platform(), "python": sys.version.split()[0], "logical_cpus": os.cpu_count(),
                  "processor": platform.processor()}
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
                info["processor"] = winreg.QueryValueEx(key, "ProcessorNameString")[0].strip()
                info["processor_mhz"] = winreg.QueryValueEx(key, "~MHz")[0]
        except OSError:
            pass
        try:
            plan = subprocess.run(["powercfg", "/getactivescheme"], capture_output=True, text=True, timeout=10)
            info["power_plan"] = plan.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            info["power_plan"] = "unavailable"
    if nvidia:
        try:
            gpu = subprocess.run([nvidia, "--query-gpu=name,driver_version,clocks.max.gr,clocks.max.mem",
                                  "--format=csv,noheader"], capture_output=True, text=True, timeout=10)
            info["gpu"] = gpu.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            pass
    if godot:
        try:
            version = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=60)
            info["godot_version"] = version.stdout.strip().splitlines()[-1] if version.stdout.strip() else ""
        except (OSError, subprocess.TimeoutExpired):
            info["godot_version"] = "unavailable"
        if Path(godot).is_file():
            info["godot_sha256"] = sha256_file(Path(godot))
        info["godot"] = godot
    return info


# ------------------------------------------------------------------ one run

def run_godot(command: list[str], cwd: Path, env: dict, timeout: float, log_path: Path, api: WinApi,
              priority: str, affinity: int | None, throttling_optout: bool, gpu: tuple[str, str] | None,
              gpu_path: Path) -> dict:
    startup = None
    creation = 0
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        creation = {"normal": 0, "above_normal": getattr(subprocess, "ABOVE_NORMAL_PRIORITY_CLASS", 0),
                    "high": getattr(subprocess, "HIGH_PRIORITY_CLASS", 0)}[priority]
    lines: list[str] = []
    started = time.time()
    controls = {"priority": priority}
    telemetry = None
    reader = None
    timed_out = False

    def reap(child) -> None:
        if child.poll() is None:
            child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=5)

    def finish_engine(child) -> None:
        try:
            reap(child)
        finally:
            try:
                if reader is not None:
                    reader.join(timeout=5)
            finally:
                if child.stdout is not None:
                    child.stdout.close()

    def finish_telemetry() -> None:
        telemetry.stop()
        telemetry.join(timeout=2)

    # Register cleanup immediately after acquiring each resource. ExitStack also
    # runs the remaining callbacks when an earlier cleanup itself raises.
    with contextlib.ExitStack() as cleanup:
        if gpu is not None:
            gpu_handle = cleanup.enter_context(open(gpu_path, "w", encoding="utf-8"))
            gpu_process = subprocess.Popen(
                [gpu[0], f"--query-gpu={gpu[1]}", "--format=csv,noheader,nounits", "-lms", "250"],
                stdout=gpu_handle, stderr=subprocess.DEVNULL, startupinfo=startup)
            cleanup.callback(reap, gpu_process)
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", errors="replace", bufsize=1, startupinfo=startup, creationflags=creation)
        cleanup.callback(finish_engine, process)
        handle = int(getattr(process, "_handle", 0) or 0)
        if handle and throttling_optout:
            controls["power_throttling"] = api.disable_power_throttling(handle)
        if handle and affinity:
            controls["affinity"] = api.set_affinity(handle, affinity)
        telemetry = Telemetry(api, handle) if handle and api.available else None
        if telemetry:
            telemetry.start()
            cleanup.callback(finish_telemetry)

        def read() -> None:
            assert process.stdout is not None
            for line in process.stdout:
                lines.append(line)

        reader = threading.Thread(target=read, name="perf-godot-output", daemon=True)
        reader.start()
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
    log_path.write_text("".join(lines), encoding="utf-8")
    return {"command": command, "cwd": str(cwd), "exit_code": process.returncode, "timed_out": timed_out,
            "wall_seconds": time.time() - started, "controls": controls,
            "telemetry_samples": telemetry.samples if telemetry else [], "log": scan_log(lines),
            "telemetry_errors": list(api.errors)}


def write_telemetry_csv(path: Path, samples: list[dict]) -> None:
    keys = sorted({key for sample in samples for key in sample})
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(samples)


# ------------------------------------------------------------------ analysis

def lookup(data: dict, dotted: str):
    value = data
    for part in dotted.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def finite_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def extract_metrics(metrics: dict) -> dict[str, float | None]:
    result: dict[str, float | None] = {}
    for key, path, _lower in METRICS:
        value = lookup(metrics, path)
        if not finite_number(value):
            result[key] = None
            continue
        result[key] = float(value) / 1048576.0 if key in BYTE_METRICS else float(value)
    if result.get("mean_frame_ms") is None and finite_number(metrics.get("delivered_fps")) and metrics["delivered_fps"] > 0:
        result["mean_frame_ms"] = 1000.0 / float(metrics["delivered_fps"])
    return result


def run_flags(record: dict, session: dict) -> list[str]:
    """Reasons a measured run cannot support a verdict. Kept in the report either way."""
    flags: list[str] = []
    metrics = record.get("metrics") or {}
    if record.get("timed_out"):
        flags.append("timed out")
    if record.get("exit_code") != 0 or isinstance(record.get("exit_code"), bool):
        flags.append(f"exit code {record.get('exit_code')}")
    if not metrics:
        flags.append("no metrics.json")
        return flags
    if metrics.get("valid_active_play") is not True:
        flags.append("active-play validity failed")
    if metrics.get("schema") != "city_life_benchmark/2":
        flags.append(f"driver schema {metrics.get('schema')!r}")
    for key in ("sample_seconds", "rendered_frames", "mean_frame_ms", "delivered_fps"):
        value = metrics.get(key)
        if not finite_number(value) or value <= 0:
            flags.append(f"missing or invalid sample evidence: {key}")
    frames = metrics.get("rendered_frames")
    if finite_number(frames) and frames > 0 and not float(frames).is_integer():
        flags.append("rendered_frames is not an integer count")
    start, end = metrics.get("sample_unix_start"), metrics.get("sample_unix_end")
    if not finite_number(start) or not finite_number(end) or end <= start:
        flags.append("missing or invalid sample timestamp interval")
    expected = session.get("driver_sha256")
    if expected and metrics.get("driver_sha256") != expected:
        flags.append("driver bytes differ from the session driver")
    for issue in metrics.get("measurement_issues", []):
        flags.append(str(issue))
    log = record.get("log") or {}
    if log.get("sample_markers") is not True:
        flags.append("sample markers missing from log")
    if int(log.get("lines_during_sample", 0)) > 0:
        flags.append(f"{log['lines_during_sample']} engine log lines during sample")
    if int(log.get("error_lines", 0)) > 0:
        flags.append(f"{log['error_lines']} engine error lines")
    optimizer = metrics.get("render_optimizer", {})
    if isinstance(optimizer, dict) and optimizer.get("cache_hit") is False:
        flags.append("render batch cache miss")
    probe = lookup(metrics, "cpu_probe.before.script_usec")
    median_probe = session.get("probe_median_usec")
    if isinstance(probe, (int, float)) and median_probe:
        deviation = float(probe) / float(median_probe) - 1.0
        if abs(deviation) > PROBE_TOLERANCE:
            flags.append(f"CPU probe {deviation * 100:+.1f}% from session median")
    other = record.get("telemetry", {}).get("other_cores_mean")
    if isinstance(other, (int, float)) and other > OTHER_CORES_LIMIT:
        flags.append(f"other processes used {other:.2f} logical cores during sample")
    clock = record.get("gpu", {}).get("graphics_clock_median_mhz")
    median_clock = session.get("gpu_clock_median_mhz")
    if isinstance(clock, (int, float)) and median_clock:
        deviation = float(clock) / float(median_clock) - 1.0
        if abs(deviation) > GPU_CLOCK_TOLERANCE:
            flags.append(f"GPU clock {deviation * 100:+.1f}% from session median")
    if session.get("stage_drift"):
        flags.append("staged tree changed during the session")
    return flags


def session_reference(records: list[dict]) -> dict:
    probes = [lookup(r.get("metrics") or {}, "cpu_probe.before.script_usec") for r in records]
    probes = [float(p) for p in probes if finite_number(p) and p > 0]
    clocks = [r.get("gpu", {}).get("graphics_clock_median_mhz") for r in records]
    clocks = [float(c) for c in clocks if finite_number(c) and c > 0]
    drivers = {(r.get("metrics") or {}).get("driver_sha256") for r in records} - {None}
    return {"probe_median_usec": statistics.median(probes) if probes else None,
            "gpu_clock_median_mhz": statistics.median(clocks) if clocks else None,
            "driver_sha256": sorted(drivers)[0] if len(drivers) == 1 else None,
            "driver_variants": len(drivers)}


def verdict(deltas: list[float], spread: float, lower_is_better: bool) -> str:
    if len(deltas) < 2:
        return "insufficient pairs"
    if all(d < 0 for d in deltas) or all(d > 0 for d in deltas):
        if abs(statistics.median(deltas)) > spread:
            better = (statistics.median(deltas) < 0) == lower_is_better
            return "B better (consistent)" if better else "B worse (consistent)"
    return "inconclusive"


def compare(records: list[dict]) -> dict:
    """Pairs are consecutive measured runs (each holds one A and one B by construction)."""
    measured = [r for r in records if not r.get("warmup")]
    pairs = []
    for index in range(0, len(measured) - 1, 2):
        first, second = measured[index], measured[index + 1]
        if {first["variant"], second["variant"]} != {"A", "B"}:
            continue
        a, b = (first, second) if first["variant"] == "A" else (second, first)
        pairs.append({"a": a, "b": b, "usable": not a["flags"] and not b["flags"]})
    results = {}
    for key, _path, lower in METRICS:
        metric_pairs = [(p["a"]["values"].get(key), p["b"]["values"].get(key)) for p in pairs
                        if p["usable"] and finite_number(p["a"]["values"].get(key))
                        and finite_number(p["b"]["values"].get(key))]
        a_values = [a for a, _b in metric_pairs]
        b_values = [b for _a, b in metric_pairs]
        deltas = [b - a for a, b in metric_pairs]
        spread = max((max(v) - min(v)) if len(v) > 1 else 0.0 for v in (a_values, b_values)) if a_values and b_values else 0.0
        entry = {"a_median": statistics.median(a_values) if a_values else None,
                 "b_median": statistics.median(b_values) if b_values else None,
                 "a_runs": a_values, "b_runs": b_values, "paired_deltas": deltas,
                 "within_variant_spread": spread, "lower_is_better": lower}
        if deltas:
            entry.update({"delta_median": statistics.median(deltas), "delta_min": min(deltas), "delta_max": max(deltas)})
            if entry["a_median"]:
                entry["delta_pct"] = 100.0 * entry["delta_median"] / entry["a_median"]
        entry["verdict"] = verdict(deltas, spread, lower)
        results[key] = entry
    return {"pairs": [{"a": p["a"]["name"], "b": p["b"]["name"], "usable": p["usable"]} for p in pairs],
            "usable_pairs": sum(1 for p in pairs if p["usable"]), "metrics": results}


def _fmt(value, digits: int = 3) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def summary_markdown(session: dict, records: list[dict], comparison: dict) -> str:
    lines = [f"# Matched A/B: {session.get('label', '')}", "",
             f"- A: `{session.get('baseline')}` runtime `{session.get('fingerprints', {}).get('A', {}).get('runtime', '')[:16]}`",
             f"- B: `{session.get('candidate')}` runtime `{session.get('fingerprints', {}).get('B', {}).get('runtime', '')[:16]}`",
             f"- Runtime files differing A→B: {session.get('runtime_diff_counts', {})}",
             f"- Engine: {session.get('host', {}).get('godot_version', '')} `{session.get('host', {}).get('godot_sha256', '')[:16]}`",
             f"- Host: {session.get('host', {}).get('processor', '')}; {session.get('host', {}).get('gpu', '')}",
             f"- Power plan: {session.get('host', {}).get('power_plan', '')}",
             f"- Order: {' '.join(session.get('order', []))} (after warm-ups {', '.join(session.get('warmups', []))})",
             f"- Options: {json.dumps(session.get('options', {}), sort_keys=True)}",
             f"- Usable pairs: {comparison.get('usable_pairs', 0)} of {len(comparison.get('pairs', []))}", "",
             "Verdict rule: every usable pair has the same sign and |median paired delta| exceeds the larger "
             "within-variant run spread; otherwise inconclusive. Flagged runs are excluded from verdicts.", "",
             "## Runs", "", "| run | variant | mean frame ms | FPS | probe µs | other cores | GPU MHz | flags |",
             "|---|---|---:|---:|---:|---:|---:|---|"]
    for record in records:
        values = record.get("values", {})
        lines.append(f"| {record['name']}{' (warm-up)' if record.get('warmup') else ''} | {record['variant']} | "
                     f"{_fmt(values.get('mean_frame_ms'))} | {_fmt(values.get('delivered_fps'), 1)} | "
                     f"{_fmt(values.get('cpu_probe_script_usec'), 0)} | {_fmt(record.get('telemetry', {}).get('other_cores_mean'), 2)} | "
                     f"{_fmt(record.get('gpu', {}).get('graphics_clock_median_mhz'), 0)} | {'; '.join(record.get('flags', [])) or 'none'} |")
    lines += ["", "## Metrics (B − A)", "", "| metric | A median | B median | Δ median [min, max] | Δ % | verdict |",
              "|---|---:|---:|---|---:|---|"]
    ordered = list(HEADLINE) + [k for k, _p, _l in METRICS if k not in HEADLINE]
    for key in ordered:
        entry = comparison["metrics"].get(key, {})
        if entry.get("a_median") is None and entry.get("b_median") is None:
            continue
        span = f"{_fmt(entry.get('delta_median'))} [{_fmt(entry.get('delta_min'))}, {_fmt(entry.get('delta_max'))}]" if "delta_median" in entry else "—"
        lines.append(f"| {key} | {_fmt(entry.get('a_median'))} | {_fmt(entry.get('b_median'))} | {span} | "
                     f"{_fmt(entry.get('delta_pct'), 1)} | {entry.get('verdict', '')} |")
    lines += ["", "Times are milliseconds (per frame, per physics tick or per wall second as named); memory in MiB.",
              "Phases come from the driver timeline (see metrics.json notes). Single runs and FPS alone are not claims."]
    return "\n".join(lines) + "\n"


def load_records(results: Path) -> tuple[dict, list[dict]]:
    session = json.loads((results / "session.json").read_text(encoding="utf-8"))
    records = []
    for name in session.get("runs", []):
        run_dir = results / "runs" / name
        record = json.loads((run_dir / "run.json").read_text(encoding="utf-8"))
        metrics_path = run_dir / "metrics.json"
        record["metrics"] = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.is_file() else {}
        records.append(record)
    return session, records


def analyze(results: Path) -> dict:
    session, records = load_records(results)
    measured = [r for r in records if not r.get("warmup")]
    reference = session_reference(measured)
    # The harness payload hash is authoritative; per-run hashes must all equal it.
    reference["driver_sha256"] = session.get("driver_sha256_expected") or reference["driver_sha256"]
    reference["stage_drift"] = session.get("stage_drift", False)
    for record in records:
        record["values"] = extract_metrics(record.get("metrics") or {})
        record["flags"] = run_flags(record, reference)
    comparison = compare(records)
    summary = {"label": session.get("label"), "reference": reference, "comparison": comparison,
               "runs": [{"name": r["name"], "variant": r["variant"], "warmup": r.get("warmup", False), "flags": r["flags"],
                         "values": r["values"], "telemetry": r.get("telemetry", {}), "gpu": r.get("gpu", {})} for r in records]}
    (results / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    (results / "summary.md").write_text(summary_markdown(session, records, comparison), encoding="utf-8")
    return summary


# ------------------------------------------------------------------ commands

def _archive_existing(results: Path) -> Path | None:
    if results.exists() and any(results.iterdir()):
        archived = results.with_name(f"{results.name}.old-{time.strftime('%Y%m%d-%H%M%S')}")
        results.rename(archived)
        return archived
    return None


class LockKeepalive(threading.Thread):
    """GodotLock treats a lock older than 15 minutes as stale; refresh it for long sessions."""

    def __init__(self, lock_path: str, interval: float = 60.0) -> None:
        super().__init__(name="perf-lock-keepalive", daemon=True)
        self.lock_path = lock_path
        self.interval = interval
        self._halt = threading.Event()

    def run(self) -> None:
        while not self._halt.wait(self.interval):
            try:
                os.utime(self.lock_path)
            except OSError:
                pass

    def stop(self) -> None:
        self._halt.set()


def cmd_run(args: argparse.Namespace) -> int:
    if not LABEL.match(args.label):
        raise SystemExit("[perf_ab] --label may contain only letters, digits, '.', '_' and '-'")
    baseline = Path(args.baseline).resolve()
    candidate = Path(args.candidate).resolve()
    for name, tree in (("baseline", baseline), ("candidate", candidate)):
        if not (tree / "project.godot").is_file():
            raise SystemExit(f"[perf_ab] {name} {tree} is not a Godot project")
    results = Path(args.results or DEFAULT_RESULTS / args.label).resolve()
    work = Path(args.work or DEFAULT_WORK / args.label).resolve()
    options = {"sample_seconds": args.sample_seconds, "width": args.width, "height": args.height,
               "quality": args.quality, "fps_cap": args.fps_cap, "mission_route": not args.walk_only,
               "profile_city": not args.no_profile_city}
    order = plan_order(args.pairs, args.order, args.seed)
    warmups = ["A", "B"] * max(0, args.warmups)
    names: list[tuple[str, str, bool]] = [(f"w{i + 1:02d}-{v}", v, True) for i, v in enumerate(warmups)]
    names += [(f"{i + 1:02d}-{v}", v, False) for i, v in enumerate(order)]
    extra = {"A": list(args.driver_arg) + list(args.baseline_driver_arg),
             "B": list(args.driver_arg) + list(args.candidate_driver_arg)}
    trees = {"A": work / "trees" / "A", "B": work / "trees" / "B"}
    affinity = int(args.affinity, 16) if args.affinity else None
    if args.dry_run:
        print(f"[perf_ab] DRY RUN label={args.label}")
        print(f"[perf_ab] A={baseline}\n[perf_ab] B={candidate}\n[perf_ab] results={results}\n[perf_ab] work={work}")
        print(f"[perf_ab] stage harness files {', '.join(HARNESS_FILES)} from {PROJECT}")
        for name, variant, warm in names:
            command = build_command("<godot>", trees[variant], work / "runs" / name, options, extra[variant])
            print(f"[perf_ab] {name}{' warm-up' if warm else ''}: {subprocess.list2cmdline(command)}")
        return 0
    sys.path.insert(0, str(TOOLS))
    from godot_preview import GodotLock, find_godot, LOCK  # noqa: E402  (resolved only for real runs)
    requested_godot = args.godot or find_godot()
    godot = resolve_engine_executable(requested_godot)
    if godot != requested_godot:
        print(f"[perf_ab] native engine for process telemetry: {godot} (requested {requested_godot})", flush=True)
    nvidia = shutil.which("nvidia-smi") if not args.no_gpu_telemetry else None
    fields = gpu_fields(nvidia)
    archived = _archive_existing(results)
    (results / "runs").mkdir(parents=True, exist_ok=True)
    payload = harness_payload()
    print("[perf_ab] fingerprinting and staging trees…", flush=True)
    stages = {"A": stage_tree(baseline, trees["A"], payload, args.reuse_stage),
              "B": stage_tree(candidate, trees["B"], payload, args.reuse_stage)}
    for variant, stage in stages.items():
        if not stage.get("copy_identical", True):
            raise SystemExit(f"[perf_ab] staged copy of {variant} differs from its source; aborting")
    freshness = {v: import_freshness(trees[v]) for v in ("A", "B")}
    for variant, report in freshness.items():
        if not report["fresh"] and not args.allow_stale_imports:
            raise SystemExit(f"[perf_ab] {variant} import cache is stale/missing ({len(report['stale'])} stale, "
                             f"{len(report['missing'])} missing); run --import on that tree or pass --allow-stale-imports")
    runtime_a = stages["A"]["manifest"].get("runtime", {})
    runtime_b = stages["B"]["manifest"].get("runtime", {})
    diff = manifest_diff(runtime_a, runtime_b)
    profiles = allocate_profiles()
    session = {"label": args.label, "created_unix": time.time(), "baseline": str(baseline), "candidate": str(candidate),
               "results": str(results), "work": str(work), "archived_previous_results": str(archived) if archived else None,
               "engine_selection": {"requested": requested_godot, "resolved": godot},
               "profiles": {v: str(path) for v, path in profiles.items()},
               "options": options, "order": order, "warmups": warmups, "seed": args.seed,
               "driver_args": extra, "priority": args.priority, "affinity": hex(affinity) if affinity else None,
               "power_throttling_optout": not args.keep_power_throttling, "gpu_fields": fields,
               "harness_files": {k: hashlib.sha256(v).hexdigest() for k, v in payload.items()},
               "driver_sha256_expected": hashlib.sha256(payload["tools/city_life_benchmark_driver.gd"]).hexdigest(),
               "fingerprints": {v: stages[v]["source_digests"] for v in ("A", "B")},
               "harness_replaced_tree_files": {v: stages[v]["harness_replaced_tree_files"] for v in ("A", "B")},
               "runtime_diff": diff, "runtime_diff_counts": {k: len(v) for k, v in diff.items()},
               "import_freshness": freshness, "host": {}, "runs": []}
    api = WinApi()
    # This tool takes the shared lock itself; never wrap it in godot_run.py (deadlock).
    lock = GodotLock()
    lock.__enter__()
    keepalive = LockKeepalive(LOCK)
    keepalive.start()
    try:
        session["host"] = host_info(godot, nvidia)  # includes `godot --version`, so under the lock
        for name, variant, warm in names:
            run_dir = work / "runs" / name
            if run_dir.exists():
                shutil.rmtree(run_dir)
            run_dir.mkdir(parents=True)
            out_dir = results / "runs" / name
            out_dir.mkdir(parents=True, exist_ok=True)
            command = build_command(godot, trees[variant], run_dir, options, extra[variant])
            print(f"[perf_ab] {name}{' (warm-up)' if warm else ''}: {variant}", flush=True)
            record = run_godot(command, trees[variant], isolated_env(profiles[variant]),
                               args.warmup_timeout if warm else args.timeout, out_dir / "stdout.log", api,
                               args.priority, affinity, not args.keep_power_throttling,
                               (nvidia, fields) if nvidia and fields else None, out_dir / "gpu.csv")
            metrics_path = run_dir / "metrics.json"
            metrics = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.is_file() else {}
            start, end = metrics.get("sample_unix_start"), metrics.get("sample_unix_end")
            samples = record.pop("telemetry_samples")
            record.update({"name": name, "variant": variant, "warmup": warm,
                           "profile": str(profiles[variant]),
                           "telemetry": telemetry_window(samples, start, end),
                           "gpu": gpu_window(parse_gpu_csv(out_dir / "gpu.csv", fields), start, end)})
            write_telemetry_csv(out_dir / "telemetry.csv", samples)
            for artifact in ("metrics.json", "frames.csv", "ticks.csv"):
                if (run_dir / artifact).is_file():
                    shutil.copy2(run_dir / artifact, out_dir / artifact)
            (out_dir / "run.json").write_text(json.dumps(record, indent=1), encoding="utf-8")
            session["runs"].append(name)
            (results / "session.json").write_text(json.dumps(session, indent=1), encoding="utf-8")
            print(f"[perf_ab] {name}: exit {record['exit_code']}, {metrics.get('delivered_fps', 0):.1f} FPS, "
                  f"{record['log']['lines_during_sample']} log lines in sample", flush=True)
    finally:
        keepalive.stop()
        lock.__exit__(None, None, None)
    after = {v: fingerprint(trees[v], set(payload))["digests"] for v in ("A", "B")}
    session["stage_drift"] = any(after[v] != stages[v]["staged_digests"] for v in ("A", "B"))
    (results / "session.json").write_text(json.dumps(session, indent=1), encoding="utf-8")
    summary = analyze(results)
    headline = summary["comparison"]["metrics"].get("mean_frame_ms", {})
    print(f"[perf_ab] mean frame ms A {_fmt(headline.get('a_median'))} B {_fmt(headline.get('b_median'))} "
          f"Δ {_fmt(headline.get('delta_median'))}: {headline.get('verdict')}")
    print(f"[perf_ab] wrote {results / 'summary.md'}")
    # A report is still written when execution or validation yielded no evidence.
    return 0 if headline.get("paired_deltas") else 2


def cmd_analyze(args: argparse.Namespace) -> int:
    summary = analyze(Path(args.results).resolve())
    for key in HEADLINE:
        entry = summary["comparison"]["metrics"].get(key, {})
        print(f"{key}: A {_fmt(entry.get('a_median'))} B {_fmt(entry.get('b_median'))} "
              f"Δ {_fmt(entry.get('delta_median'))} {entry.get('verdict', '')}")
    return 0


def cmd_fingerprint(args: argparse.Namespace) -> int:
    tree = Path(args.tree).resolve()
    report = fingerprint(tree)
    print(json.dumps({"root": report["root"], "digests": report["digests"], "file_counts": report["file_counts"],
                      "import_freshness": import_freshness(tree)}, indent=1))
    return 0


def parser() -> argparse.ArgumentParser:
    main = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = main.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="stage both trees and run the interleaved benchmark")
    run.add_argument("--label", required=True)
    run.add_argument("--baseline", default=str(DEFAULT_BASELINE))
    run.add_argument("--candidate", default=str(PROJECT))
    run.add_argument("--results")
    run.add_argument("--work")
    run.add_argument("--pairs", type=int, default=3)
    run.add_argument("--warmups", type=int, default=1, help="unmeasured runs per variant before the pairs")
    run.add_argument("--order", choices=("abba", "alternate", "random"), default="abba")
    run.add_argument("--seed", type=int, default=2610)
    run.add_argument("--sample-seconds", type=int, default=20)
    run.add_argument("--width", type=int, default=1920)
    run.add_argument("--height", type=int, default=1080)
    run.add_argument("--quality", default="balanced", choices=("low", "balanced", "high"))
    run.add_argument("--fps-cap", type=int, default=0)
    run.add_argument("--walk-only", action="store_true", help="omit the mission route workload")
    run.add_argument("--no-profile-city", action="store_true")
    run.add_argument("--driver-arg", action="append", default=[])
    run.add_argument("--baseline-driver-arg", action="append", default=[])
    run.add_argument("--candidate-driver-arg", action="append", default=[])
    run.add_argument("--priority", choices=("normal", "above_normal", "high"), default="normal")
    run.add_argument("--affinity", help="hex CPU mask applied to both variants (default: none)")
    run.add_argument("--keep-power-throttling", action="store_true")
    run.add_argument("--no-gpu-telemetry", action="store_true")
    run.add_argument("--timeout", type=float, default=480.0)
    run.add_argument("--warmup-timeout", type=float, default=1500.0)
    run.add_argument("--godot")
    run.add_argument("--reuse-stage", action="store_true")
    run.add_argument("--allow-stale-imports", action="store_true")
    run.add_argument("--dry-run", action="store_true")
    run.set_defaults(handler=cmd_run)
    report = commands.add_parser("analyze", help="recompute summary.md/json from a results directory")
    report.add_argument("results")
    report.set_defaults(handler=cmd_analyze)
    tree = commands.add_parser("fingerprint", help="print a tree's content digests and import freshness")
    tree.add_argument("tree")
    tree.set_defaults(handler=cmd_fingerprint)
    return main


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    return int(args.handler(args) or 0)


if __name__ == "__main__":
    sys.exit(main())
