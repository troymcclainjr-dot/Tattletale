"""File-only release-pipeline tests. Never starts an engine or editor."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import export_city_release as release


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.work = release.ROOT / ".work/alive-next/release-unit"
        self.work.mkdir(parents=True, exist_ok=True)
        self.temp = Path(tempfile.mkdtemp(dir=self.work)).resolve()
        self.assertTrue(self.temp.is_relative_to(self.work.resolve()))

    def tearDown(self):
        self.assertTrue(self.temp.resolve().is_relative_to(self.work.resolve()))
        shutil.rmtree(self.temp)

    def project(self):
        project = self.temp / "source"
        files = {
            "project.godot": '[application]\nrun/main_scene="res://scenes/main.tscn"\n[autoload]\n',
            "export_presets.cfg": 'custom_template/release=""\ncustom_template/debug=""\n',
            "icon.svg": "<svg/>", "assets/data/level.json": "{}",
            "scripts/game.gd": "extends Node\n", "scenes/main.tscn": "[gd_scene]\n",
            "scripts/city/city_incidents.gd": "extends Node3D\n",
            "assets/data/cases/index.json": '{"schema":1,"templates":["templates/report.json"],"cases":["parcel_report.json"]}',
            "assets/data/cases/templates/report.json": '{"schema":1,"template":"report","case":{}}',
            "assets/data/cases/parcel_report.json": '{"schema":1,"id":"parcel_report"}',
            "tools/clay_post_import.gd": "@tool\nextends EditorScenePostImport\n",
            "tools/private_tool.py": "never ship", "tests/private_fixture.gd": "never ship",
            "assets/logs/private.log": "never ship", ".godot/editor/workspace.cfg": "never copy",
            ".godot/imported/mesh.scn": "original cache", ".godot/uid_cache.bin": "uid cache",
        }
        for name, content in files.items():
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        return project

    def test_stage_only_changes_its_own_main_and_excludes_fixtures(self):
        project = self.project()
        before = release.sha256(project / "project.godot")
        with patch.object(release.subprocess, "run", side_effect=AssertionError("No process allowed")):
            snapshot = release.stage_project(project, self.temp / "stage", self.temp / "templates")
        stage = self.temp / "stage"
        self.assertEqual(before, release.sha256(project / "project.godot"))
        self.assertIn(release.ENTRY, (stage / "project.godot").read_text())
        self.assertIn("ReleaseBootProbe", (stage / "project.godot").read_text())
        self.assertNotIn("window/size/no_focus", (stage / "project.godot").read_text())
        self.assertFalse((stage / "override.cfg").exists())
        self.assertEqual(snapshot["project.godot"], before)
        self.assertFalse((stage / "tests").exists())
        self.assertFalse((stage / "tools/private_tool.py").exists())
        self.assertFalse((stage / "assets/logs").exists())
        self.assertFalse((stage / ".godot/editor").exists())
        for relative in ("scripts/city/city_incidents.gd", "assets/data/cases/index.json",
                         "assets/data/cases/templates/report.json", "assets/data/cases/parcel_report.json"):
            self.assertEqual(release.sha256(stage / relative), snapshot[relative])
        (stage / ".godot/imported/mesh.scn").write_text("staged reimport")
        self.assertEqual((project / ".godot/imported/mesh.scn").read_text(), "original cache")

    def test_existing_stage_is_never_overwritten(self):
        project = self.project()
        stage = self.temp / "existing"
        stage.mkdir()
        with self.assertRaises(FileExistsError):
            release.stage_project(project, stage, self.temp)

    def test_manifest_checks_payload_and_rejects_tampering(self):
        output = self.temp / "payload"
        (output / "notices").mkdir(parents=True)
        for name in ("Tattletale-PenLucy.exe", "Tattletale-PenLucy.pck", "notices/Godot-MIT.txt", "notices/Godot-third-party.json"):
            (output / name).write_text("unit-test payload, not a runnable build")
        release.finalize(output, {"passed": True, "main_scene": release.ENTRY}, "unit", "source-hash")
        self.assertTrue(release.verify(output)["verified"])
        (output / "Tattletale-PenLucy.pck").write_text("changed")
        with self.assertRaisesRegex(ValueError, "checksum"):
            release.verify(output)

    def test_manifest_refuses_unvalidated_candidate(self):
        with self.assertRaisesRegex(ValueError, "boot"):
            release.finalize(self.temp, {"passed": False}, "unit", "hash")

    def test_private_window_override_cannot_ship(self):
        (self.temp / "override.cfg").write_text("[display]\nwindow/size/no_focus=true\n")
        for action in (lambda: release.finalize(self.temp, {"passed": True}, "unit", "hash"),
                       lambda: release.verify(self.temp)):
            with self.assertRaisesRegex(ValueError, "must never ship"):
                action()

    def test_custom_project_overrides_are_refused_before_staging(self):
        project = self.project()
        original = (project / "project.godot").read_text()
        for setting in ("config/project_settings_override=\"user://custom.cfg\"",
                        "config/disable_project_settings_override=true",
                        "window/size/no_focus.windows=false"):
            (project / "project.godot").write_text(original + "\n" + setting + "\n")
            with self.assertRaisesRegex(ValueError, "overrides"):
                release.stage_project(project, self.temp / "stage", self.temp)
            self.assertFalse((self.temp / "stage").exists())
        (project / "project.godot").write_text(original)
        (project / "override.cfg").write_text("retain me")
        with self.assertRaisesRegex(ValueError, "Unreviewed"):
            release.stage_project(project, self.temp / "stage", self.temp)
        self.assertEqual((project / "override.cfg").read_text(), "retain me")

    def test_editor_and_runtime_profiles_are_isolated_without_mutating_host(self):
        before = dict(release.os.environ)
        editor = release.isolated_environment(self.temp / "editor-profile")
        runtime = release.isolated_environment(self.temp / "validation-profile")
        for variable in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
            self.assertTrue(Path(editor[variable]).is_relative_to(self.temp))
            self.assertTrue(Path(editor[variable]).is_dir())
            self.assertTrue(Path(runtime[variable]).is_dir())
            self.assertNotEqual(editor[variable], runtime[variable])
        self.assertEqual(dict(release.os.environ), before)

    def test_real_source_filters_and_font_provenance(self):
        report = release.validate_sources()
        self.assertTrue(report["tests_excluded"])
        self.assertEqual(report["source_main"], "res://scenes/main.tscn")
        self.assertIn("scripts/city/city_bicycle_crash.gd", report["foundation_files"])
        self.assertIn("assets/data/cases/parcel_report.json", report["indexed_case_files"])
        self.assertTrue((release.PROJECT / "scripts/city/pen_lucy_level.gd").read_text().find("KEY_F6") >= 0)


if __name__ == "__main__":
    unittest.main()
