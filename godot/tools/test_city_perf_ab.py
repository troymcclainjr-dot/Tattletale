"""No engine needed: matched A/B harness planning, staging, scanning, telemetry and verdicts.

    python -m unittest godot/tools/test_city_perf_ab.py -v
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import city_perf_ab as ab  # noqa: E402

HEX = "0123456789abcdef0123456789abcdef"


def write(path: Path, text: str = "x", mtime: float | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


def metrics(**overrides) -> dict:
    """A minimal schema-2 metrics.json for a valid, clean run."""
    data = {
        "schema": "city_life_benchmark/2", "driver_sha256": "d" * 64, "valid_active_play": True,
        "measurement_issues": [], "mean_frame_ms": 6.0, "delivered_fps": 166.7,
        "frame_ms": {"median": 5.0, "p95": 12.0, "p99": 16.0},
        "timeline_ms": {"render_ms": {"mean": 2.0, "per_second": 333.0}, "process_scripts_ms": {"mean": 0.5, "per_second": 83.0}},
        "physics_components_ms_per_second": {"traffic": 180.0}, "cpu_probe": {"before": {"script_usec": 10000.0}},
        "engine_counters_end": {"static_memory_peak_bytes": 900 * 1048576.0}, "render_optimizer": {"cache_hit": True},
        "sample_unix_start": 100.0, "sample_unix_end": 120.0,
        "sample_seconds": 20.0, "rendered_frames": 3334,
    }
    for key, value in overrides.items():
        data[key] = value
    return data


def record(name: str, variant: str, values: dict, flags=None, warmup=False) -> dict:
    return {"name": name, "variant": variant, "values": values, "flags": list(flags or []), "warmup": warmup}


class PlanTests(unittest.TestCase):
    def test_abba_order_counterbalances_and_every_pair_holds_both_variants(self):
        order = ab.plan_order(3, "abba")
        self.assertEqual(order, ["A", "B", "B", "A", "A", "B"])
        for mode in ("abba", "alternate", "random"):
            sequence = ab.plan_order(4, mode, seed=7)
            for index in range(0, len(sequence), 2):
                self.assertEqual(sorted(sequence[index:index + 2]), ["A", "B"], mode)
        self.assertEqual(ab.plan_order(5, "random", seed=7), ab.plan_order(5, "random", seed=7))
        with self.assertRaises(ValueError):
            ab.plan_order(0)
        with self.assertRaises(ValueError):
            ab.plan_order(2, "sideways")

    def test_command_matches_offscreen_runner_and_appends_variant_args_last(self):
        options = {"sample_seconds": 20, "width": 1920, "height": 1080, "quality": "balanced", "fps_cap": 120,
                   "mission_route": True, "profile_city": True}
        command = ab.build_command("godot.exe", Path("C:/stage/A"), Path("C:/work/runs/01-A"), options, ["--perf-counters"])
        separator = command.index("--")
        engine, driver = command[:separator], command[separator + 1:]
        for expected in (["--path", str(Path("C:/stage/A"))], ["--position", "-10000,-10000"], ["--audio-driver", "Dummy"],
                         ["--resolution", "1920x1080"], ["--script", ab.ENTRY]):
            self.assertIn(expected[0], engine)
            self.assertEqual(engine[engine.index(expected[0]) + 1], expected[1])
        self.assertIn("--windowed", engine)
        self.assertEqual(driver[:2], ["--offscreen-validation", "--private-viewport"])
        self.assertEqual(driver[driver.index("--outdir") + 1], "C:/work/runs/01-A")
        self.assertEqual(driver[driver.index("--fps-cap") + 1], "120")
        self.assertIn("--mission-route", driver)
        self.assertEqual(driver[-1], "--perf-counters")
        walk = ab.build_command("godot.exe", None, Path("C:/r"), dict(options, mission_route=False, profile_city=False), [])
        self.assertNotIn("--path", walk)
        self.assertNotIn("--mission-route", walk)
        self.assertNotIn("--profile-city", walk)


class EngineAndProfileTests(unittest.TestCase):
    def test_pipeline_policy_preserves_old_exclusions_and_background_gates(self):
        data = metrics(pipeline_compilations_during_sample=6,
                       pipeline_compilation_policy="canvas_draw_blocking_v1",
                       pipeline_blocking_compilations_during_sample=0,
                       pipeline_async_specializations_during_sample=6)
        run = {"exit_code": 0, "metrics": data,
               "log": {"sample_markers": True, "lines_during_sample": 0, "error_lines": 0},
               "telemetry": {"other_cores_mean": 0.1}, "gpu": {}}
        self.assertEqual(ab.run_flags(run, {}), [])
        for issue in ("pipeline compilations during sample: 6",
                      "blocking canvas/draw pipeline compilations during sample: 1"):
            data["measurement_issues"] = [issue]
            self.assertIn(issue, ab.run_flags(run, {}))
        data["measurement_issues"] = []
        run["telemetry"]["other_cores_mean"] = 2.0
        self.assertTrue(ab.run_flags(run, {}), "async specialization policy must not relax background gates")

    def test_windows_console_launcher_resolves_native_sibling_with_spaces_and_unicode(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "Engine files café"
            console = write(folder / "Godot_v4.7.2-stable_win64_console.exe")
            native = write(folder / "Godot_v4.7.2-stable_win64.exe")
            self.assertEqual(ab.resolve_engine_executable(str(console), "nt"), str(native.resolve()))
            with mock.patch.object(ab.shutil, "which", return_value=str(console)):
                self.assertEqual(ab.resolve_engine_executable(console.name, "nt"), str(native.resolve()))

    def test_missing_native_sibling_cannot_silently_measure_launcher(self):
        with tempfile.TemporaryDirectory() as temp:
            console = write(Path(temp) / "godot_console.exe")
            with self.assertRaisesRegex(SystemExit, "native engine executable"):
                ab.resolve_engine_executable(str(console), "nt")

    def test_native_and_nonwindows_choices_are_preserved(self):
        self.assertEqual(ab.resolve_engine_executable("godot.exe", "nt"), "godot.exe")
        self.assertEqual(ab.resolve_engine_executable("godot_console.exe", "posix"), "godot_console.exe")

    def test_profiles_are_short_fresh_per_session_and_preserve_previous_data(self):
        with tempfile.TemporaryDirectory() as temp:
            profile_root = Path(temp) / "pf"
            first = ab.allocate_profiles(profile_root)
            sentinel = write(first["A"] / "Roaming" / "saved-user-data", "keep")
            second = ab.allocate_profiles(profile_root)
            self.assertNotEqual(first["A"].parent, second["A"].parent)
            self.assertEqual(first["A"].parent, first["B"].parent)
            self.assertEqual(sentinel.read_text(), "keep")
            for profiles in (first, second):
                for variant, path in profiles.items():
                    self.assertEqual(path.parent.parent, profile_root.resolve())
                    self.assertEqual(path.name, variant)
                    self.assertLessEqual(len(path.parent.name), 12)
                    self.assertTrue((path / ab.PROFILE_MARKER).is_file())
                    self.assertTrue((path / "temp").is_dir())
            self.assertFalse((second["A"] / "Roaming" / "saved-user-data").exists())
            base = {"APPDATA": "personal", "LOCALAPPDATA": "personal-local", "PATH": "unchanged"}
            env_a, env_b = (ab.isolated_env(second[v], base) for v in ("A", "B"))
            self.assertNotEqual(env_a["APPDATA"], env_b["APPDATA"])
            self.assertEqual(base["APPDATA"], "personal")
            self.assertEqual(env_a["PATH"], "unchanged")
            for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
                self.assertTrue(Path(env_a[key]).is_relative_to(second["A"]))

    def test_default_profile_root_is_independent_of_long_result_labels(self):
        self.assertEqual(ab.PROFILE_ROOT, ab.ROOT / ".work" / "pf")
        self.assertNotIn("priorities-five", ab.PROFILE_ROOT.parts[-2:])
        with mock.patch.object(ab, "allocate_profiles", side_effect=AssertionError("dry run wrote profiles")):
            with contextlib.redirect_stdout(io.StringIO()):
                args = ab.parser().parse_args(["run", "--label", "x" * 80,
                                              "--baseline", str(ab.PROJECT), "--dry-run"])
                self.assertEqual(ab.cmd_run(args), 0)


class FingerprintTests(unittest.TestCase):
    def test_categories_digest_runtime_content_and_ignore_editor_state(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write(root / "project.godot", "config")
            write(root / "scripts/a.gd", "func a(): pass")
            write(root / "tests/t.gd", "test")
            write(root / "tools/x.py", "tool")
            write(root / "README.md", "doc")
            write(root / ".godot/imported/a.scn", "cache")
            write(root / ".godot/editor/state.cfg", "editor")
            write(root / "scripts/__pycache__/a.pyc", "bytecode")
            first = ab.fingerprint(root)
            self.assertEqual(sorted(first["manifest"]["runtime"]), ["project.godot", "scripts/a.gd"])
            self.assertEqual(list(first["manifest"]["import_cache"]), [".godot/imported/a.scn"])
            self.assertEqual(set(first["manifest"]), {"runtime", "tests", "tools", "docs", "import_cache"})
            write(root / ".godot/editor/state.cfg", "editor moved")
            self.assertEqual(ab.fingerprint(root)["digests"], first["digests"])
            write(root / "scripts/a.gd", "func a(): return 1")
            second = ab.fingerprint(root)
            self.assertNotEqual(second["digests"]["runtime"], first["digests"]["runtime"])
            self.assertEqual(second["digests"]["tests"], first["digests"]["tests"])
            diff = ab.manifest_diff(first["manifest"]["runtime"], dict(second["manifest"]["runtime"], **{"scripts/b.gd": "1"}))
            self.assertEqual(diff, {"added": ["scripts/b.gd"], "removed": [], "changed": ["scripts/a.gd"]})

    def test_import_freshness_distinguishes_stale_missing_invalid_and_orphans(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = write(root / "assets/a.png", "pixels")
            cached = write(root / f".godot/imported/a.png-{HEX}.s3tc.ctex", "texture")
            sidecar = root / f".godot/imported/a.png-{HEX}.md5"
            write(sidecar, f'source_md5="{hashlib.md5(b"pixels").hexdigest()}"\ndest_md5="0"\n')
            write(root / "assets/a.png.import", '[remap]\n\nimporter="texture"\npath.s3tc="res://.godot/imported/'
                  f'a.png-{HEX}.s3tc.ctex"\n\n[deps]\n\nsource_file="res://assets/a.png"\n'
                  f'dest_files=["res://.godot/imported/a.png-{HEX}.s3tc.ctex"]\n')
            write(root / "assets/broken.png.import", '[remap]\n\nimporter="texture"\nvalid=false\n')
            write(root / "assets/gone.glb.import", '[deps]\n\nsource_file="res://assets/gone.glb"\n'
                  f'dest_files=["res://.godot/imported/gone.glb-{HEX}.scn"]\n')
            report = ab.import_freshness(root)
            self.assertTrue(report["fresh"])
            self.assertEqual((report["checked"], report["invalid"], report["orphans"]),
                             (1, ["assets/broken.png.import"], ["assets/gone.glb.import"]))
            source.write_text("edited pixels", encoding="utf-8")
            stale = ab.import_freshness(root)
            self.assertFalse(stale["fresh"])
            self.assertEqual(stale["stale"], ["assets/a.png.import"])
            cached.unlink()
            missing = ab.import_freshness(root)
            self.assertEqual(missing["missing"], ["assets/a.png.import"])
            self.assertFalse(missing["fresh"])


class StagingTests(unittest.TestCase):
    def test_stage_injects_identical_harness_preserves_mtimes_and_reuses_only_unchanged_copies(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            source = temp / "tree"
            old = 1_600_000_000.0
            write(source / "project.godot", "config", old)
            write(source / "scripts/x.gd", "x", old)
            write(source / "tools/city_life_benchmark_driver.gd", "old driver")
            write(source / ".godot/editor/filesystem_cache", "big")
            write(source / ".godot/imported/m.scn", "mesh", old)
            payload = {"tools/city_life_benchmark_driver.gd": b"new driver", "tools/city_perf_stats.gd": b"stats"}
            stage = temp / "stage"
            first = ab.stage_tree(source, stage, payload)
            self.assertTrue(first["copy_identical"])
            self.assertFalse(first["reused"])
            self.assertEqual((stage / "tools/city_life_benchmark_driver.gd").read_bytes(), b"new driver")
            self.assertEqual((stage / "tools/city_perf_stats.gd").read_bytes(), b"stats")
            self.assertEqual(first["harness_replaced_tree_files"], ["tools/city_life_benchmark_driver.gd"])
            self.assertAlmostEqual((stage / "scripts/x.gd").stat().st_mtime, old, delta=1)
            self.assertAlmostEqual((stage / ".godot/imported/m.scn").stat().st_mtime, old, delta=1)
            self.assertFalse((stage / ".godot/editor").exists())
            self.assertEqual((source / "tools/city_life_benchmark_driver.gd").read_text(encoding="utf-8"), "old driver")
            self.assertTrue(ab.stage_tree(source, stage, payload, reuse=True)["reused"])
            write(stage / "scripts/x.gd", "tampered")
            again = ab.stage_tree(source, stage, payload, reuse=True)
            self.assertFalse(again["reused"])
            self.assertEqual((stage / "scripts/x.gd").read_text(encoding="utf-8"), "x")
            write(source / "scripts/x.gd", "changed source")
            self.assertFalse(ab.stage_tree(source, stage, payload, reuse=True)["reused"])
            foreign = temp / "foreign"
            write(foreign / "keep.txt", "user data")
            with self.assertRaises(SystemExit):
                ab.stage_tree(source, foreign, payload)
            self.assertTrue((foreign / "keep.txt").is_file())

    def test_profiles_are_isolated_and_only_harness_profiles_are_cleared(self):
        with tempfile.TemporaryDirectory() as temp:
            profile = ab.fresh_profile(Path(temp) / "profile")
            write(profile / "Roaming/Godot/app_userdata/x/cache.bin", "cache")
            ab.fresh_profile(profile)
            self.assertFalse((profile / "Roaming/Godot").exists())
            before = dict(os.environ)
            env = ab.isolated_env(profile)
            self.assertEqual(dict(os.environ), before)
            for variable in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
                self.assertTrue(Path(env[variable]).is_relative_to(profile))
                self.assertTrue(Path(env[variable]).is_dir())
            foreign = write(Path(temp) / "user/settings.cfg", "mine").parent
            with self.assertRaises(SystemExit):
                ab.fresh_profile(foreign)
            self.assertTrue((foreign / "settings.cfg").is_file())

    def test_real_harness_payload_is_present_in_this_project(self):
        payload = ab.harness_payload()
        self.assertEqual(sorted(payload), sorted(ab.HARNESS_FILES))
        for relative, content in payload.items():
            self.assertEqual(content, (ab.PROJECT / relative).read_bytes())
        self.assertIn(b"SAMPLE_BEGIN", payload["tools/city_life_benchmark_driver.gd"])


class LogAndTelemetryTests(unittest.TestCase):
    def test_log_scan_counts_only_engine_output_inside_the_sample(self):
        lines = ["boot\n", "WARNING: early\n", "[city_life_benchmark] SAMPLE_BEGIN unix=1.0\n", "WARNING: inside\n",
                 "\n", "  ERROR: inside failure\n", "[city_life_benchmark] SAMPLE_END unix=2.0\n", "ERROR: late\n",
                 "[city_life_benchmark] {\"valid\": true}\n"]
        scan = ab.scan_log(lines)
        self.assertTrue(scan["sample_markers"])
        self.assertEqual(scan["lines_during_sample"], 2)
        self.assertEqual((scan["error_lines"], scan["error_lines_during_sample"], scan["warning_lines"]), (2, 1, 2))
        self.assertFalse(ab.scan_log(["[city_life_benchmark] SAMPLE_BEGIN\n", "x\n"])["sample_markers"])

    def test_telemetry_window_reports_other_process_load_inside_the_sample_only(self):
        samples = [{"unix": 99.0, "system_cores": 9.0, "child_cores": 1.0},
                   {"unix": 100.5, "system_cores": 2.0, "child_cores": 1.5, "working_set": 2 * 1048576, "peak_working_set": 3 * 1048576,
                    "cpu_performance_pct": 110.0, "cpu_nominal_mhz": 3000.0},
                   {"unix": 101.0, "system_cores": 1.8, "child_cores": 1.4, "working_set": 1048576},
                   {"unix": 130.0, "system_cores": 9.0, "child_cores": 0.0}]
        window = ab.telemetry_window(samples, 100.0, 120.0)
        self.assertEqual(window["samples"], 2)
        self.assertAlmostEqual(window["other_cores_mean"], 0.45)
        self.assertAlmostEqual(window["other_cores_max"], 0.5)
        self.assertAlmostEqual(window["working_set_max_mb"], 2.0)
        self.assertAlmostEqual(window["peak_working_set_mb"], 3.0)
        self.assertAlmostEqual(window["cpu_effective_mhz_mean"], 3300.0)
        self.assertEqual(ab.telemetry_window(samples, None, 120.0), {})

    def test_gpu_csv_skips_unsupported_values_and_keeps_boundary_seconds(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "gpu.csv"
            fields = ab.GPU_FIELDS[1]
            start = time.mktime(time.strptime("2026/10/31 18:00:10", "%Y/%m/%d %H:%M:%S"))
            path.write_text("2026/10/31 18:00:09.900, 1900, 9501, 70, 180.5, 60, P0, 0x0000000000000000\n"
                            "2026/10/31 18:00:12.100, 1500, 9501, 72, [Not Supported], 61, P0, 0x0000000000000004\n"
                            "garbage line\n"
                            "2026/10/31 18:00:40.000, 300, 405, 0, 20.0, 50, P8, 0x0000000000000001\n", encoding="utf-8")
            rows = ab.parse_gpu_csv(path, fields)
            self.assertEqual(len(rows), 3)
            window = ab.gpu_window(rows, start, start + 5)
            self.assertEqual(window["samples"], 2)
            self.assertEqual((window["graphics_clock_min_mhz"], window["graphics_clock_max_mhz"]), (1500.0, 1900.0))
            self.assertAlmostEqual(window["power_mean_w"], 180.5)
            self.assertEqual(window["clock_reasons"], ["0x0000000000000000", "0x0000000000000004"])
            self.assertEqual(ab.parse_gpu_csv(path, None), [])

    def test_owned_child_run_records_exit_log_window_and_process_controls(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            child = ("import sys,time; print('boot'); print('[city_life_benchmark] SAMPLE_BEGIN unix=1', flush=True); "
                     "print('WARNING: noisy', flush=True); time.sleep(0.8); "
                     "print('[city_life_benchmark] SAMPLE_END unix=2', flush=True); print('ERROR: late', flush=True); sys.exit(3)")
            result = ab.run_godot([sys.executable, "-u", "-c", child], temp, dict(os.environ), 20, temp / "out.log",
                                  ab.WinApi(), "normal", None, True, None, temp / "gpu.csv")
            self.assertEqual(result["exit_code"], 3)
            self.assertFalse(result["timed_out"])
            self.assertEqual(result["log"]["lines_during_sample"], 1)
            self.assertEqual(result["log"]["error_lines"], 1)
            self.assertIn("SAMPLE_END", (temp / "out.log").read_text(encoding="utf-8"))
            if os.name == "nt":
                self.assertIsInstance(result["controls"]["power_throttling"]["applied"], bool)
                self.assertTrue(result["telemetry_samples"])
                self.assertTrue(any("working_set" in s and s["working_set"] > 0 for s in result["telemetry_samples"]))
                self.assertTrue(any("child_cores" in s for s in result["telemetry_samples"]))

    def test_owned_child_timeout_is_reaped_promptly(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            began = time.monotonic()
            result = ab.run_godot([sys.executable, "-u", "-c", "import time; print('up', flush=True); time.sleep(60)"],
                                  temp, dict(os.environ), 0.5, temp / "out.log", ab.WinApi(), "normal", None, False, None,
                                  temp / "gpu.csv")
            self.assertTrue(result["timed_out"])
            self.assertLess(time.monotonic() - began, 15)
            self.assertIn("up", (temp / "out.log").read_text(encoding="utf-8"))

    def test_lock_keepalive_refreshes_a_stale_looking_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            lock = Path(temp) / "godot.lock"
            lock.mkdir()
            os.utime(lock, (1_600_000_000, 1_600_000_000))
            keepalive = ab.LockKeepalive(str(lock), interval=0.05)
            keepalive.start()
            time.sleep(0.3)
            keepalive.stop()
            keepalive.join(timeout=2)
            self.assertGreater(lock.stat().st_mtime, time.time() - 60)
            self.assertFalse(keepalive.is_alive())


class AnalysisTests(unittest.TestCase):
    def test_metric_extraction_converts_bytes_and_tolerates_older_schemas(self):
        values = ab.extract_metrics(metrics())
        self.assertEqual(values["mean_frame_ms"], 6.0)
        self.assertEqual(values["render_ms_per_frame"], 2.0)
        self.assertEqual(values["static_memory_peak_mb"], 900.0)
        self.assertIsNone(values["tick_engine_ms"])
        legacy = ab.extract_metrics({"delivered_fps": 200.0, "frame_ms": {"median": 4.0}, "valid_active_play": True})
        self.assertAlmostEqual(legacy["mean_frame_ms"], 5.0)
        self.assertIsNone(legacy["render_ms_per_frame"])
        self.assertIsNone(ab.extract_metrics({"mean_frame_ms": True})["mean_frame_ms"])

    def test_run_flags_name_each_confound(self):
        session = {"probe_median_usec": 10000.0, "gpu_clock_median_mhz": 1900.0, "driver_sha256": "d" * 64}
        clean = {"metrics": metrics(), "exit_code": 0, "log": {"sample_markers": True, "lines_during_sample": 0, "error_lines": 0},
                 "telemetry": {"other_cores_mean": 0.1}, "gpu": {"graphics_clock_median_mhz": 1880.0}}
        self.assertEqual(ab.run_flags(clean, session), [])
        self.assertEqual(ab.run_flags(dict(clean, metrics=metrics(cpu_probe={"before": {"script_usec": 10250.0}})), session), [])
        cases = {
            "active-play validity failed": dict(clean, metrics=metrics(valid_active_play=False)),
            "driver schema": dict(clean, metrics=metrics(schema=None)),
            "driver bytes differ": dict(clean, metrics=metrics(driver_sha256="e" * 64)),
            "pipeline compilations": dict(clean, metrics=metrics(measurement_issues=["pipeline compilations during sample: 3"])),
            "engine log lines during sample": dict(clean, log={"sample_markers": True, "lines_during_sample": 2, "error_lines": 0}),
            "sample markers missing": dict(clean, log={"sample_markers": False, "lines_during_sample": 0, "error_lines": 0}),
            "CPU probe +4.0%": dict(clean, metrics=metrics(cpu_probe={"before": {"script_usec": 10400.0}})),
            "other processes used 0.80": dict(clean, telemetry={"other_cores_mean": 0.8}),
            "GPU clock -21.1%": dict(clean, gpu={"graphics_clock_median_mhz": 1500.0}),
            "render batch cache miss": dict(clean, metrics=metrics(render_optimizer={"cache_hit": False})),
            "exit code 1": dict(clean, exit_code=1),
            "timed out": dict(clean, timed_out=True),
            "no metrics.json": dict(clean, metrics={}),
        }
        for expected, run in cases.items():
            with self.subTest(expected=expected):
                self.assertTrue(any(expected in flag for flag in ab.run_flags(run, session)), ab.run_flags(run, session))
        self.assertIn("staged tree changed during the session", ab.run_flags(clean, dict(session, stage_drift=True)))

    def test_verdicts_need_consistent_pairs_beyond_run_spread(self):
        def runs(a_values, b_values, flags_b=None):
            built = []
            for index, (a, b) in enumerate(zip(a_values, b_values)):
                pair = [record(f"{2 * index + 1:02d}-A", "A", {"mean_frame_ms": a, "delivered_fps": 1000 / a}),
                        record(f"{2 * index + 2:02d}-B", "B", {"mean_frame_ms": b, "delivered_fps": 1000 / b},
                               flags=(flags_b or {}).get(index))]
                built.extend(pair if index % 2 == 0 else pair[::-1])
            return [record("w01-A", "A", {"mean_frame_ms": 50.0}, warmup=True)] + built

        worse = ab.compare(runs([6.0, 6.1, 5.9], [6.6, 6.65, 6.5]))
        entry = worse["metrics"]["mean_frame_ms"]
        self.assertEqual(entry["verdict"], "B worse (consistent)")
        self.assertAlmostEqual(entry["delta_median"], 0.6)
        self.assertEqual(worse["metrics"]["delivered_fps"]["verdict"], "B worse (consistent)")
        self.assertEqual(worse["usable_pairs"], 3)
        self.assertEqual(ab.compare(runs([6.0, 6.1, 5.9], [6.3, 5.9, 6.2]))["metrics"]["mean_frame_ms"]["verdict"], "inconclusive")
        small = ab.compare(runs([6.0, 6.4, 5.6], [6.1, 6.5, 5.7]))["metrics"]["mean_frame_ms"]
        self.assertEqual(small["verdict"], "inconclusive", "a 0.1ms shift inside a 0.8ms run spread is not a result")
        better = ab.compare(runs([6.0, 6.1, 5.9], [5.0, 5.1, 4.9]))["metrics"]["mean_frame_ms"]
        self.assertEqual(better["verdict"], "B better (consistent)")
        flagged = ab.compare(runs([6.0, 6.1, 5.9], [6.6, 6.65, 6.5], flags_b={1: ["CPU probe +5%"], 2: ["timed out"]}))
        self.assertEqual(flagged["usable_pairs"], 1)
        self.assertEqual(flagged["metrics"]["mean_frame_ms"]["verdict"], "insufficient pairs")

    def test_analyze_round_trip_writes_markdown_and_json(self):
        with tempfile.TemporaryDirectory() as temp:
            results = Path(temp)
            names = ["w01-A", "w02-B", "01-A", "02-B", "03-B", "04-A"]
            frames = {"01-A": 6.0, "02-B": 6.6, "03-B": 6.7, "04-A": 6.1, "w01-A": 9.0, "w02-B": 9.0}
            for name in names:
                run_dir = results / "runs" / name
                run_dir.mkdir(parents=True)
                (run_dir / "metrics.json").write_text(json.dumps(metrics(mean_frame_ms=frames[name])), encoding="utf-8")
                (run_dir / "run.json").write_text(json.dumps({
                    "name": name, "variant": name[-1], "warmup": name.startswith("w"), "exit_code": 0,
                    "log": {"sample_markers": True, "lines_during_sample": 0, "error_lines": 0},
                    "telemetry": {"other_cores_mean": 0.05}, "gpu": {}}), encoding="utf-8")
            (results / "session.json").write_text(json.dumps({
                "label": "fixture", "runs": names, "order": ["A", "B", "B", "A"], "warmups": ["A", "B"],
                "driver_sha256_expected": "d" * 64, "fingerprints": {"A": {"runtime": "a" * 64}, "B": {"runtime": "b" * 64}}}),
                encoding="utf-8")
            summary = ab.analyze(results)
            self.assertEqual(summary["comparison"]["usable_pairs"], 2)
            self.assertEqual(summary["comparison"]["metrics"]["mean_frame_ms"]["verdict"], "B worse (consistent)")
            text = (results / "summary.md").read_text(encoding="utf-8")
            self.assertIn("| mean_frame_ms |", text)
            self.assertIn("(warm-up)", text)
            self.assertTrue(json.loads((results / "summary.json").read_text(encoding="utf-8"))["runs"])


class CommandTests(unittest.TestCase):
    def test_dry_run_prints_every_planned_command_and_creates_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            for tree in ("a", "b"):
                write(temp / tree / "project.godot", "config")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = ab.main(["run", "--label", "fixture", "--dry-run", "--baseline", str(temp / "a"),
                                "--candidate", str(temp / "b"), "--results", str(temp / "results"), "--work", str(temp / "work"),
                                "--pairs", "2", "--candidate-driver-arg=--perf-counters"])
            self.assertEqual(code, 0)
            text = output.getvalue()
            self.assertEqual(text.count("--offscreen-validation"), 6)
            self.assertEqual(text.count("--perf-counters"), 3)
            self.assertIn("w01-A warm-up", text)
            self.assertFalse((temp / "results").exists())
            self.assertFalse((temp / "work").exists())

    def test_invalid_labels_and_non_projects_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            write(Path(temp) / "a" / "project.godot", "config")
            with self.assertRaises(SystemExit):
                ab.main(["run", "--label", "bad label", "--dry-run", "--baseline", str(Path(temp) / "a"),
                         "--candidate", str(Path(temp) / "a")])
            with self.assertRaises(SystemExit):
                ab.main(["run", "--label", "ok", "--dry-run", "--baseline", str(Path(temp) / "a"),
                         "--candidate", str(Path(temp) / "missing")])


if __name__ == "__main__":
    unittest.main()
