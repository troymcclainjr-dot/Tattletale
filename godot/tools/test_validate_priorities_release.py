"""File-only adversarial receipt/package checks; never launches Godot."""
import json
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
import uuid
from unittest import mock
import zipfile

import validate_priorities_release as harness


class ValidationTests(unittest.TestCase):
    def setUp(self):
        harness.WORK.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="parser-unit-", dir=harness.WORK)).resolve()
        self.profile = self.root / "Profile é 東京"
        self.install = self.root / "Install é 東京"

    def tearDown(self):
        self.assertTrue(self.root.is_relative_to(harness.WORK.resolve()))
        shutil.rmtree(self.root)

    def receipt(self, phase="fresh"):
        return {"passed": True, "phase": phase, "nonce": "unique", "editor": False, "debug": False,
                "main_scene": harness.release.ENTRY,
                "checks": {k: True for k in harness.COMMON_CHECKS | harness.PHASE_CHECKS[phase]},
                "user_data_dir": str(self.profile / "Roaming"),
                "save_path": str(self.profile / "world.json"), "settings_path": str(self.profile / "settings.cfg"),
                "executable": str(self.install / "Tattletale-PenLucy.exe"), "save_sha256": "a" * 64,
                "runtime_pid": 4321, "startup_mouse_before_pause": 0,
                "native_foreground": {"runtime_pid": 4321, "samples": 20, "foreground_pids": [1234],
                                      "runtime_was_foreground": False, "errors": []},
                "resource_files": ["res://assets/data/release_notices.txt", "res://assets/fonts/SOURCES.json"]}

    def validate(self, data):
        harness.validate_receipt(data, "fresh", "unique", self.profile, self.install)

    def startup_window(self):
        return {"outside_all_screens": True, "unfocusable": True, "focused": False, "mouse_mode": 0,
                "rect": [-10008, -10031, 976, 579], "screen_rects": [[0, 0, 1920, 1080], [-1920, 0, 1920, 1080]]}

    def test_valid_unicode_paths(self):
        self.validate(self.receipt())

    def test_legacy_receipts_cannot_omit_pacifist_foundation_checks(self):
        required = {"pacifist_policy", "foundation_services", "phone_bicycle_schema", "foundation_bridges",
                    "packed_case_library", "foundation_schema", "foundation_checkpoint", "foundation_restore"}
        for phase in ("fresh", "reload", "startup"):
            for key in required | ({"foundation_fixture_created"} if phase == "fresh" else set()):
                for omitted in (True, False):
                    data = self.receipt(phase)
                    if omitted:
                        del data["checks"][key]
                    else:
                        data["checks"][key] = False
                    with self.subTest(phase=phase, key=key, omitted=omitted):
                        with self.assertRaisesRegex(ValueError, "Incomplete"):
                            harness.validate_receipt(data, phase, "unique", self.profile, self.install)

    def test_normal_startup_requires_automatic_load_and_normal_display(self):
        data = self.receipt("startup")
        data.update(save_enabled_at_startup=True, offscreen_validation=False, display_server="Windows",
                    startup_load={"ok": True, "partial": False},
                    startup_window=self.startup_window())
        harness.validate_receipt(data, "startup", "unique", self.profile, self.install)
        for field, value in (("save_enabled_at_startup", False), ("offscreen_validation", True),
                             ("display_server", "headless"), ("startup_load", {}),
                             ("startup_load", {"ok": True, "partial": True})):
            bad = dict(data, **{field: value})
            with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "automatically restore"):
                harness.validate_receipt(bad, "startup", "unique", self.profile, self.install)
        del data["checks"]["automatic_world_restore"]
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            harness.validate_receipt(data, "startup", "unique", self.profile, self.install)

    def test_startup_rejects_desktop_focus_or_mouse_capture(self):
        data = self.receipt("startup")
        data.update(save_enabled_at_startup=True, offscreen_validation=False, display_server="Windows",
                    startup_load={"ok": True, "partial": False},
                    startup_window=self.startup_window())
        for field, value in (("outside_all_screens", False), ("unfocusable", False), ("focused", "false"),
                             ("mouse_mode", 2), ("mouse_mode", False), ("mouse_mode", "0"),
                             ("screen_rects", []), ("rect", [-1, -1, 960, 540]),
                             ("screen_rects", [[-12000, -12000, 4000, 4000]])):
            bad = dict(data, startup_window=dict(data["startup_window"], **{field: value}))
            with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "offscreen, unfocusable"):
                harness.validate_receipt(bad, "startup", "unique", self.profile, self.install)
        del data["startup_window"]
        with self.assertRaisesRegex(ValueError, "offscreen, unfocusable"):
            harness.validate_receipt(data, "startup", "unique", self.profile, self.install)

    def test_cached_focus_requires_independent_native_pid_evidence(self):
        data = self.receipt("startup")
        data.update(save_enabled_at_startup=True, offscreen_validation=False, display_server="Windows",
                    startup_load={"ok": True, "partial": False}, startup_window=dict(self.startup_window(), focused=True))
        harness.validate_receipt(data, "startup", "unique", self.profile, self.install)
        for evidence in (None, {}, dict(data["native_foreground"], runtime_pid=99),
                         dict(data["native_foreground"], foreground_pids=[4321]),
                         dict(data["native_foreground"], runtime_was_foreground=True),
                         dict(data["native_foreground"], samples=0),
                         dict(data["native_foreground"], errors=["query failed"])):
            with self.subTest(evidence=evidence), self.assertRaisesRegex(ValueError, "native foreground evidence"):
                harness.validate_receipt(dict(data, native_foreground=evidence), "startup", "unique", self.profile, self.install)
        with self.assertRaisesRegex(ValueError, "before probe pause"):
            harness.validate_receipt(dict(data, startup_mouse_before_pause=2), "startup", "unique", self.profile, self.install)

    def test_stage_pointer_guard_changes_only_two_assignments_and_preserves_load(self):
        source_path = harness.release.PROJECT / "scripts/city/pen_lucy_level.gd"
        original_bytes = source_path.read_bytes()
        source = source_path.read_text(encoding="utf-8")
        guarded = harness.startup_pointer_guard(source)
        changed = [(old, new) for old, new in zip(source.splitlines(), guarded.splitlines()) if old != new]
        self.assertEqual(changed, list(harness.POINTER_GUARD_REPLACEMENTS))
        self.assertEqual(len(source.splitlines()), len(guarded.splitlines()))
        self.assertIn("var restored: Dictionary = world_save.load_state()", guarded)
        for old, new in harness.POINTER_GUARD_REPLACEMENTS:
            self.assertIn(harness.POINTER_GUARD_ARGUMENT, new)
            self.assertIn("else Input.MOUSE_MODE_CAPTURED", new)
        self.assertEqual(source_path.read_bytes(), original_bytes)
        for invalid in (guarded, source + source, source.replace("func resume_exploring", "func moved_resume")):
            with self.assertRaisesRegex(ValueError, "target changed"):
                harness.startup_pointer_guard(invalid)

    def test_startup_launch_requires_native_observer(self):
        env = harness.release.isolated_environment(self.profile)
        self.install.mkdir()
        harness.private_startup_override(self.install, create=True)
        argv = harness.runtime_command(self.install / "game.exe", "startup", self.root / "report.json", "unique", self.profile)
        with mock.patch.object(harness, "run_startup_checked", return_value={"observed": True}) as observe, \
                mock.patch.object(harness.release, "run_checked") as generic:
            result = harness.command(argv, self.root / "startup.log", self.install, 10, env)
        self.assertEqual(result, {"observed": True})
        self.assertEqual(observe.call_args.args[0], argv)
        self.assertIs(observe.call_args.args[-1], env)
        generic.assert_not_called()

    def test_private_startup_override_preserves_payload_and_is_fingerprinted(self):
        self.install.mkdir()
        executable = self.install / "game.exe"
        executable.write_bytes(b"test executable")
        packed = self.install / "game.pck"
        packed.write_bytes(b"test packed resources")
        before = harness.fingerprint(self.install)
        receipt = harness.private_startup_override(self.install, create=True)
        after = harness.fingerprint(self.install)
        self.assertEqual({key: after[key] for key in before}, before)
        self.assertEqual(set(after) - set(before), {"override.cfg"})
        self.assertEqual(receipt["sha256"], after["override.cfg"])
        self.assertIn("window/size/no_focus=true", receipt["settings"])
        self.assertEqual(harness.private_startup_override(self.install), receipt)
        with self.assertRaises(FileExistsError):
            harness.private_startup_override(self.install, create=True)

    def test_startup_guard_refuses_missing_changed_or_wrong_directory_before_launch(self):
        self.install.mkdir()
        env = harness.release.isolated_environment(self.profile)
        argv = harness.runtime_command(self.install / "game.exe", "startup", self.root / "report.json", "unique", self.profile)
        for payload in (None, "[display]\nwindow/size/no_focus=false\n"):
            if payload is not None:
                (self.install / "override.cfg").write_text(payload, encoding="utf-8")
            with mock.patch.object(harness, "run_startup_checked") as launch, self.assertRaisesRegex(ValueError, "no-focus override"):
                harness.command(argv, self.root / "startup.log", self.install, 10, env)
            launch.assert_not_called()
        with mock.patch.object(harness, "run_startup_checked") as launch, self.assertRaisesRegex(ValueError, "private validation cwd"):
            harness.command(argv, self.root / "startup.log", self.root, 10, env)
        launch.assert_not_called()

    def test_private_startup_override_refuses_shipping_and_linked_targets(self):
        with self.assertRaisesRegex(ValueError, "private, unlinked"):
            harness.private_startup_override(harness.release.PROJECT, create=True)
        self.assertFalse((harness.release.PROJECT / "override.cfg").exists())
        self.install.mkdir()
        original = self.root / "original.cfg"
        original.write_text("retain me", encoding="utf-8")
        target = self.install / "override.cfg"
        target.write_text("retain me", encoding="utf-8")
        # Windows sandbox can forbid creating hardlinks; model the link-count
        # evidence without requesting broader filesystem permissions.
        stat = Path.stat
        def linked_stat(path, *args, **kwargs):
            result = stat(path, *args, **kwargs)
            return SimpleNamespace(st_nlink=2, st_mode=result.st_mode) if path == target else result
        with mock.patch.object(Path, "stat", linked_stat), self.assertRaisesRegex(ValueError, "must not be linked"):
            harness.private_startup_override(self.install, create=True)
        self.assertEqual(original.read_text(encoding="utf-8"), "retain me")
        self.assertEqual(target.read_text(encoding="utf-8"), "retain me")

    def test_startup_receipt_requires_creation_time_project_setting(self):
        data = self.receipt("startup")
        data["checks"]["startup_project_no_focus"] = False
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            harness.validate_receipt(data, "startup", "unique", self.profile, self.install)

    def test_startup_command_uses_ordinary_source_free_runtime(self):
        command = harness.runtime_command(self.install / "Tattletale-PenLucy.exe", "startup", self.root / "startup.json",
                                          "unique", self.profile)
        for forbidden in ("--headless", "--offscreen-validation", "--path", "--script", "--editor"):
            self.assertNotIn(forbidden, command)
        self.assertEqual(command[command.index("--position") + 1], "-10000,-10000")
        self.assertEqual(command[command.index("--log-file") + 1], str(self.profile / "startup-engine.log"))
        self.assertIn("--priorities-release-phase=startup", command)
        for phase in ("fresh", "reload"):
            command = harness.runtime_command(self.install / "game.exe", phase, self.root / "report.json", "unique", self.profile)
            self.assertIn("--headless", command)
            self.assertIn("--offscreen-validation", command)

    def test_child_environment_and_engine_log_do_not_need_parent_overrides(self):
        before = dict(os.environ)
        env = harness.release.isolated_environment(self.profile)
        self.assertEqual(dict(os.environ), before)
        for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
            self.assertTrue(Path(env[key]).is_relative_to(self.profile))
            self.assertTrue(Path(env[key]).is_dir())
        log = self.root / "import.log"
        with mock.patch.object(harness.release, "run_checked") as run:
            harness.command(["fake-godot.exe", "--headless", "--import"], log, self.root, 10, env)
        argv = run.call_args.args[0]
        self.assertEqual(argv[argv.index("--log-file") + 1], str(log.with_suffix(".engine.log")))
        self.assertIs(run.call_args.args[-1], env)
        self.assertEqual(json.loads(log.with_suffix(".argv.json").read_text()), argv)

    def test_child_environment_cannot_fall_back_to_user_profile(self):
        env = harness.release.isolated_environment(self.profile)
        for replacement in (None, dict(env, APPDATA=str(self.root.parent.parent.parent.parent)), dict(env, TEMP="relative")):
            with mock.patch.object(harness.release, "run_checked") as run, self.assertRaises(ValueError):
                harness.command(["fake-godot.exe"], self.root / "child.log", self.root, 10, replacement)
            run.assert_not_called()

    def test_short_profiles_preserve_unicode_and_shader_cache_path_budget(self):
        owned = []
        try:
            build_id = "x" * 48 + uuid.uuid4().hex  # Maximum supported build ID length.
            first = harness.reserve_profiles(build_id)
            owned.append(first["editor"].parent)
            second = harness.reserve_profiles("y" + build_id[1:])
            owned.append(second["editor"].parent)
            self.assertNotEqual(owned[0], owned[1])
            self.assertIn("é 東京", str(first["runtime"]))
            for profiles in (first, second):
                for profile in profiles.values():
                    self.assertTrue(profile.is_relative_to(harness.PROFILE_ROOT.resolve()))
                    self.assertEqual(list(profile.iterdir()), [])
                    self.assertLessEqual(harness.shader_cache_path_budget(profile), 259)
                    env = harness.release.isolated_environment(profile)
                    self.assertTrue(Path(env["APPDATA"]).is_relative_to(profile))
                    with mock.patch.object(harness.release, "run_checked") as run:
                        harness.command(["fake-godot.exe"], self.root / "short-profile.log", self.root, 10, env)
                    run.assert_called_once()
            marker = first["runtime"] / "do-not-overwrite"
            marker.write_text("retained", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                harness.reserve_profiles(build_id)
            self.assertEqual(marker.read_text(encoding="utf-8"), "retained")
        finally:
            for directory in owned:
                self.assertTrue(directory.resolve().is_relative_to(harness.PROFILE_ROOT.resolve()))
                shutil.rmtree(directory)

    def test_profiles_reject_overlong_or_nonworkspace_root_before_creation(self):
        for root in (self.root / ("long" * 40), harness.ROOT.parent / "outside-profile-root"):
            with mock.patch.object(harness, "PROFILE_ROOT", root), self.assertRaises(ValueError):
                harness.reserve_profiles("reject-before-mkdir")
            self.assertFalse(root.exists())

    def test_generic_exit_success_or_stale_report_is_not_evidence(self):
        with self.assertRaises(ValueError):
            self.validate({"passed": True})
        data = self.receipt()
        data["nonce"] = "old-run"
        with self.assertRaisesRegex(ValueError, "stale"):
            self.validate(data)

    def test_missing_gameplay_assertion_rejected(self):
        data = self.receipt()
        del data["checks"]["input_moves_player"]
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            self.validate(data)

    def test_real_user_save_or_other_executable_rejected(self):
        for key, value in (("save_path", self.root / "outside.json"), ("settings_path", self.root / "settings.cfg"), ("executable", self.root / "other.exe")):
            data = self.receipt()
            data[key] = str(value)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(data)

    def test_missing_credits_and_development_pck_files_rejected(self):
        for resources in ([], self.receipt()["resource_files"] + ["res://tests/private.gdc"]):
            data = self.receipt()
            data["resource_files"] = resources
            with self.assertRaises(ValueError):
                self.validate(data)

    def test_zip_exact_content_and_tamper_detection(self):
        output = self.root / "payload"
        output.mkdir()
        (output / "game.pck").write_bytes(b"test payload, no engine")
        archive = self.root / "package.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.write(output / "game.pck", "payload/game.pck")
        self.assertEqual(harness.verify_zip(archive, output)["files"], 1)
        (output / "game.pck").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum"):
            harness.verify_zip(archive, output)

    def test_zip_extra_traversal_member_rejected(self):
        output = self.root / "payload"
        output.mkdir()
        archive = self.root / "package.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr("../escape.txt", "untrusted")
        with self.assertRaisesRegex(ValueError, "members"):
            harness.verify_zip(archive, output)


if __name__ == "__main__":
    unittest.main()
