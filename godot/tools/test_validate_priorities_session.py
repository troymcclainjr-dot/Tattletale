"""No engine needed: verify that session evidence cannot falsely pass."""
import unittest
import os
from pathlib import Path
import tempfile

from validate_priorities_session import ROOT, SESSION_PHASES, SOAK_PHASES, evaluate, isolated_environment


class SessionEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.result = {"complete": True, "passed": True, "passes": 40, "failures": 0,
                       "phases": dict.fromkeys(SESSION_PHASES, 1)}
        self.log = "[priorities_session] COMPLETE 40 passed; 0 failed\n"

    def test_complete_clean_frozen_run_passes(self):
        self.assertTrue(evaluate(self.result, self.log, 0, True)["passed"])

    def test_parse_error_cannot_hide_behind_zero_exit_or_pass_marker(self):
        for error in ("SCRIPT ERROR: Parse Error: bad type", "ERROR: Invalid RID", "SHADER ERROR: broken"):
            with self.subTest(error=error):
                self.assertFalse(evaluate(self.result, error + "\n" + self.log, 0, True)["passed"])

    def test_missing_completion_or_structured_result_fails(self):
        self.assertFalse(evaluate(self.result, "", 0, True)["passed"])
        self.assertFalse(evaluate({}, self.log, 0, True)["passed"])

    def test_failure_timeout_and_drift_each_fail(self):
        self.assertFalse(evaluate(self.result, self.log, 124, True)["passed"])
        self.assertFalse(evaluate(self.result, self.log, 0, False)["passed"])
        self.assertFalse(evaluate(dict(self.result, failures=1), self.log, 0, True)["passed"])
        self.assertFalse(evaluate(dict(self.result, passes=0), self.log, 0, True)["passed"])

    def test_incomplete_scenarios_cannot_report_success(self):
        partial = dict(self.result, phases={"supplies": 1})
        self.assertFalse(evaluate(partial, self.log, 0, True)["passed"])
        self.assertFalse(evaluate(self.result, self.log, 0, True, "soak")["passed"])
        soaked = dict(self.result, phases=dict.fromkeys(SESSION_PHASES | SOAK_PHASES, 1),
                      details={"requested_soak_seconds": 900, "measured_soak_seconds": 902,
                               "aborted_after_primary_failure": False, "cycles_settled": True})
        self.assertTrue(evaluate(soaked, self.log, 0, True, "soak")["passed"])

    def test_aborted_unsettled_or_short_soak_cannot_claim_success(self):
        details = {"requested_soak_seconds": 900, "measured_soak_seconds": 902,
                   "aborted_after_primary_failure": False, "cycles_settled": True}
        for change in ({"aborted_after_primary_failure": True}, {"cycles_settled": False},
                       {"measured_soak_seconds": 87}, {"requested_soak_seconds": "900"}):
            with self.subTest(change=change):
                forged = dict(self.result, phases=dict.fromkeys(SESSION_PHASES | SOAK_PHASES, 1),
                              details=dict(details, **change))
                self.assertFalse(evaluate(forged, self.log, 0, True, "soak")["passed"])

    def test_each_run_has_fresh_writable_profile_without_changing_parent(self):
        workspace = ROOT / ".work" / "priorities-five"
        workspace.mkdir(parents=True, exist_ok=True)
        parent_profile = (os.environ.get("APPDATA"), os.environ.get("LOCALAPPDATA"))
        with tempfile.TemporaryDirectory(prefix="profile-test-", dir=workspace) as directory:
            base = Path(directory)
            first = isolated_environment(base / "first")
            second = isolated_environment(base / "second")
            self.assertNotEqual(first["APPDATA"], second["APPDATA"])
            for environment in (first, second):
                roaming = Path(environment["APPDATA"])
                self.assertTrue(roaming.is_relative_to(base))
                self.assertTrue(Path(environment["LOCALAPPDATA"]).is_dir())
                log = roaming / "Godot" / "app_userdata" / "Tattletale 2-Pack" / "logs" / "probe.log"
                self.assertEqual(list(log.parent.iterdir()), [])
                log.write_text("fixture log", encoding="utf-8")
                self.assertEqual(log.read_text(encoding="utf-8"), "fixture log")
                self.assertEqual(environment.get("PATH"), os.environ.get("PATH"))
            with self.assertRaises(FileExistsError):
                isolated_environment(base / "first")
        self.assertEqual(parent_profile, (os.environ.get("APPDATA"), os.environ.get("LOCALAPPDATA")))


if __name__ == "__main__":
    unittest.main()
