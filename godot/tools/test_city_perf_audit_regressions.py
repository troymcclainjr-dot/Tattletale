"""Focused file-only performance audit regressions; never starts Godot.

PERF_AUDIT_MODULE may point to an isolated patched preview for pre-apply review.
"""
from __future__ import annotations

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE = Path(os.environ.get("PERF_AUDIT_MODULE", Path(__file__).with_name("city_perf_ab.py")))
spec = importlib.util.spec_from_file_location("perf_audit_target", MODULE)
ab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ab)


def valid_record():
    return {"exit_code": 0, "log": {"sample_markers": True, "lines_during_sample": 0, "error_lines": 0},
            "metrics": {"schema": "city_life_benchmark/2", "valid_active_play": True,
                        "mean_frame_ms": 10.0, "delivered_fps": 100.0, "sample_seconds": 2.0,
                        "rendered_frames": 200, "sample_unix_start": 100.0, "sample_unix_end": 102.0}}


class FakeChild:
    def __init__(self, *, stubborn=False):
        self.stdout = io.StringIO("[city_life_benchmark] SAMPLE_BEGIN\n[city_life_benchmark] SAMPLE_END\n")
        self.returncode = None
        self._handle = 0
        self.stubborn = stubborn
        self.terminated = False
        self.killed = False
        self.waits = 0

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminated = True
        if not self.stubborn:
            self.returncode = 1

    def kill(self):
        self.killed = True
        self.returncode = 1

    def wait(self, timeout=None):
        self.waits += 1
        if self.stubborn and not self.killed:
            raise subprocess.TimeoutExpired("fake", timeout)
        self.returncode = 0 if self.returncode is None else self.returncode
        return self.returncode


class EvidenceTests(unittest.TestCase):
    def test_valid_sample_without_optional_telemetry_is_accepted(self):
        self.assertEqual(ab.run_flags(valid_record(), {}), [])

    def test_missing_process_or_log_evidence_is_rejected(self):
        for field in ("exit_code", "log"):
            run = valid_record()
            del run[field]
            with self.subTest(field=field):
                self.assertTrue(ab.run_flags(run, {}))

    def test_missing_or_nonfinite_required_measurements_are_rejected(self):
        for field in ("sample_seconds", "rendered_frames", "mean_frame_ms", "delivered_fps"):
            for value in (None, 0, -1, True, float("nan"), float("inf")):
                run = valid_record()
                run["metrics"][field] = value
                with self.subTest(field=field, value=value):
                    self.assertTrue(ab.run_flags(run, {}))
        run = valid_record()
        run["metrics"]["rendered_frames"] = 2.5
        self.assertTrue(ab.run_flags(run, {}))

    def test_invalid_interval_is_rejected(self):
        for start, end in ((None, 102), (100, None), (102, 100), (100, 100), (100, float("nan"))):
            run = valid_record()
            run["metrics"].update(sample_unix_start=start, sample_unix_end=end)
            with self.subTest(start=start, end=end):
                self.assertTrue(ab.run_flags(run, {}))

    def test_nonfinite_optional_metric_is_missing_instead_of_comparable(self):
        result = ab.extract_metrics({"work_ms": {"mean": float("nan")}, "delivered_fps": float("inf")})
        self.assertIsNone(result["work_mean_ms"])
        self.assertIsNone(result["mean_frame_ms"])

    def test_same_complete_pairs_determine_medians_spread_and_percentage(self):
        observations = [("A", 10, False), ("B", 5, False), ("B", 5, False), ("A", 10, False),
                        ("A", 100, False), ("B", 50, True), ("B", 50, True), ("A", 100, False),
                        ("A", 100, False), ("B", 50, True)]
        records = [{"name": str(i), "variant": v, "flags": ["invalid"] if invalid else [],
                    "values": {"mean_frame_ms": value}} for i, (v, value, invalid) in enumerate(observations)]
        result = ab.compare(records)["metrics"]["mean_frame_ms"]
        self.assertEqual(result["a_runs"], [10, 10])
        self.assertEqual(result["b_runs"], [5, 5])
        self.assertEqual(result["delta_pct"], -50.0)
        self.assertEqual(result["within_variant_spread"], 0.0)

    def test_metric_missing_from_one_partner_drops_both_metric_observations(self):
        records = [{"name": "A", "variant": "A", "flags": [], "values": {"mean_frame_ms": 10}},
                   {"name": "B", "variant": "B", "flags": [], "values": {}}]
        result = ab.compare(records)["metrics"]["mean_frame_ms"]
        self.assertIsNone(result["a_median"])
        self.assertIsNone(result["b_median"])
        self.assertEqual(result["verdict"], "insufficient pairs")


class CleanupTests(unittest.TestCase):
    def invoke(self, directory, gpu=None, api=None):
        return ab.run_godot(["fake-engine"], directory, {}, 2, directory / "out.log",
                            api or mock.Mock(available=False, errors=[]), "normal", None, True, gpu,
                            directory / "gpu.csv")

    def test_successful_child_stdout_is_closed(self):
        child = FakeChild()
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ab.subprocess, "Popen", return_value=child):
            result = self.invoke(Path(directory))
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(child.stdout.closed)

    def test_engine_launch_failure_reaps_started_gpu_and_closes_its_output(self):
        gpu = FakeChild(stubborn=True)
        handles = []

        def launch(*args, **kwargs):
            if not handles:
                handles.append(kwargs["stdout"])
                return gpu
            raise FileNotFoundError("fake missing engine")

        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ab.subprocess, "Popen", side_effect=launch):
            with self.assertRaises(FileNotFoundError):
                self.invoke(Path(directory), ("fake-gpu", "timestamp"))
        self.assertTrue(gpu.terminated)
        self.assertTrue(gpu.killed)
        self.assertEqual(gpu.waits, 2, "must wait again after kill")
        self.assertTrue(handles[0].closed)
        gpu.stdout.close()  # Fake GPU has a stream; a real GPU writes directly to the file.

    def test_process_control_exception_reaps_child_and_closes_stdout(self):
        child = FakeChild()
        child._handle = 1
        api = mock.Mock(available=False, errors=[])
        api.disable_power_throttling.side_effect = RuntimeError("fake control failure")
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ab.subprocess, "Popen", return_value=child):
            with self.assertRaises(RuntimeError):
                self.invoke(Path(directory), api=api)
        self.assertTrue(child.terminated)
        self.assertTrue(child.stdout.closed)

    def test_timed_out_child_is_killed_reaped_and_pipe_closed(self):
        child = FakeChild(stubborn=True)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ab.subprocess, "Popen", return_value=child):
            result = self.invoke(Path(directory))
        self.assertTrue(result["timed_out"])
        self.assertTrue(child.killed)
        self.assertEqual(child.waits, 3)
        self.assertTrue(child.stdout.closed)


if __name__ == "__main__":
    unittest.main()
