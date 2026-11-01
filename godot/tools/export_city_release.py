"""Stage/export a standalone Windows candidate without modifying the source project.

--check and --prepare-only never launch Godot. --build uses the same shared
GodotLock as godot_run.py, then validates the exported runtime from its own folder.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
from datetime import datetime, timezone
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "godot"
PRESET = "Pen Lucy Windows"
ENTRY = "res://scenes/city/pen_lucy.tscn"
TEMPLATE_VERSION = "4.7.2.stable"
RUNTIME_DIRS = ("assets", "scripts", "scenes")
FORBIDDEN_PARTS = {".git", ".work", "tests", "__pycache__", "logs"}
FOUNDATION_RUNTIME_FILES = (
    "scripts/city/city_play_mode.gd", "scripts/city/city_incidents.gd",
    "scripts/city/city_case_engine.gd", "scripts/city/city_case_library.gd",
    "scripts/city/city_bicycle_crash.gd", "scripts/city/city_player_phone.gd",
    "scripts/city/city_phone_ui.gd", "scripts/city/city_photo_context.gd",
    "assets/data/cases/index.json", "assets/data/cases/parcel_report.json",
    "assets/models/city/pen_lucy.glb",
)
BOOT_PROBE = r'''extends Node
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
var elapsed := 0.0
var destination := ""
var license_directory := ""
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not "--release-smoke" in OS.get_cmdline_user_args():
		queue_free()
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--release-report="):
			destination = argument.trim_prefix("--release-report=")
		elif argument.begins_with("--release-license-dir="):
			license_directory = argument.trim_prefix("--release-license-dir=")
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 180.0:
		push_error("Release boot timed out before Pen Lucy became ready")
		get_tree().quit(2)
		return
	var level := get_tree().current_scene
	if level == null:
		return
	if level.scene_file_path != "res://scenes/city/pen_lucy.tscn":
		push_error("Release boot reached the wrong main scene: " + level.scene_file_path)
		get_tree().quit(2)
		return
	if not bool(level.get("ready_to_play")):
		return
	var crew_ids: Array[String] = []
	for actor_id in level.npcs.actors:
		if str(actor_id).begins_with("patrol_officer_cruiser_"):
			crew_ids.append(str(actor_id))
	crew_ids.sort()
	var expected_crew: Array[String] = ["patrol_officer_cruiser_1", "patrol_officer_cruiser_2"]
	var policy: Dictionary = PlayMode.status()
	var pacifist: bool = not PlayMode.player_combat_enabled() and not PlayMode.player_driving_enabled() and not PlayMode.alignment_enabled()
	var services: bool = level.get("incidents") != null and level.get("bicycle") != null and level.player.get("phone") != null
	var library_ready: bool = level.missions.has_method("case_library_report") and level.missions.has_method("case_library_errors")
	var library: Dictionary = level.missions.case_library_report() if library_ready else {}
	library_ready = library_ready and library.get("errors", ["missing"]).is_empty() and "parcel_report" in library.get("cases", [])
	var report := {"main_scene": level.scene_file_path, "ready": true,
		"editor": OS.has_feature("editor"), "debug": OS.is_debug_build(),
		"crowd": level.npcs.crowd.residents.size(), "daily": level.residents.actors.size(),
		"named": level.npcs.actors.size(), "base_named": level.npcs.actors.size() - crew_ids.size(),
		"cruiser_crew_ids": crew_ids, "placeholders": Assets.used_placeholder.duplicate(),
		"engine": Engine.get_version_info(), "inspector": level.get("inspector") != null,
		"play_mode": policy, "pacifist_policy": pacifist, "foundation_services": services,
		"case_library": library, "case_library_ready": library_ready}
	var ok: bool = not report.editor and not report.debug and report.crowd == 1200 and report.daily == 40 and report.named == 17 and report.base_named == 15 and crew_ids == expected_crew and report.placeholders.is_empty() and report.inspector and pacifist and services and library_ready
	report["passed"] = ok
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write release boot report")
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	DirAccess.make_dir_recursive_absolute(license_directory)
	var license := FileAccess.open(license_directory.path_join("Godot-MIT.txt"), FileAccess.WRITE)
	license.store_string(Engine.get_license_text())
	license.close()
	var third_party := FileAccess.open(license_directory.path_join("Godot-third-party.json"), FileAccess.WRITE)
	third_party.store_string(JSON.stringify({"engine": Engine.get_version_info(), "copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t"))
	third_party.close()
	print("[release_boot] " + ("PASS" if ok else "FAIL") + " standalone readiness, population, assets, F6 inspector and pacifist foundation")
	get_tree().quit(0 if ok else 2)
'''


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def runtime_sources(project: Path) -> list[Path]:
    files = [project / "project.godot", project / "export_presets.cfg", project / "icon.svg"]
    if (project / "icon.svg.import").exists():
        files.append(project / "icon.svg.import")
    for directory in RUNTIME_DIRS:
        for path in (project / directory).rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(project)
            if FORBIDDEN_PARTS.intersection(relative.parts) or path.suffix.lower() in {".py", ".log", ".tmp", ".blend", ".bak"}:
                continue
            if path.is_symlink():
                raise ValueError(f"Runtime snapshot does not follow symlinks: {relative}")
            files.append(path)
    # Required while importing copied GLBs; the export filter excludes tools.
    files.append(project / "tools" / "clay_post_import.gd")
    return sorted(set(files))


def validate_project_configuration(project: Path) -> None:
    """Unreviewed overrides could defeat a private pre-window safety config."""
    for name in ("override.cfg", "project.binary"):
        if (project / name).exists():
            raise ValueError(f"Unreviewed project configuration: {project / name}")
    source = (project / "project.godot").read_text(encoding="utf-8-sig")
    if re.search(r"^\s*config/(?:project_settings_override|disable_project_settings_override)(?:\.[^=]+)?\s*=", source, re.M):
        raise ValueError("Review custom/disabled project settings overrides before exporting")
    if re.search(r"^\s*window/size/(?:no_focus|mode|initial_position_type|initial_position|always_on_top)\.[^=]+\s*=", source, re.M):
        raise ValueError("Review platform window overrides before isolated release validation")


def validate_sources(project: Path = PROJECT) -> dict:
    validate_project_configuration(project)
    manifest = json.loads((project / "release" / "manifest.json").read_text(encoding="utf-8"))
    for relative in manifest["map_data_sources"]:
        if not (ROOT / relative).is_file():
            raise FileNotFoundError(relative)
    for name in ("bungee-OFL.txt", "barlowcondensed-OFL.txt", "courierprime-OFL.txt", "SOURCES.json"):
        if not (project / "assets" / "fonts" / name).is_file():
            raise FileNotFoundError(name)
    for font in json.loads((project / "assets/fonts/SOURCES.json").read_text(encoding="utf-8")):
        if sha256(project / "assets/fonts" / font["file"]) != font["sha256"]:
            raise ValueError(f"Font provenance hash mismatch: {font['file']}")
    files = runtime_sources(project)
    for path in files:
        if not path.is_file():
            raise FileNotFoundError(path)
    for relative in FOUNDATION_RUNTIME_FILES:
        if not (project / relative).is_file():
            raise FileNotFoundError(f"Pacifist runtime resource missing: {relative}")
    case_root = (project / "assets/data/cases").resolve()
    case_index = json.loads((case_root / "index.json").read_text(encoding="utf-8"))
    case_files = []
    for section in ("templates", "cases"):
        entries = case_index.get(section)
        if not isinstance(entries, list) or not entries:
            raise ValueError(f"Case index has no {section}")
        for relative in entries:
            if not isinstance(relative, str):
                raise ValueError("Case resource path must be text")
            path = (case_root / relative).resolve()
            if not path.is_relative_to(case_root) or path.suffix != ".json" or not path.is_file():
                raise ValueError(f"Missing or invalid case resource: {relative}")
            case_files.append(path.relative_to(project.resolve()).as_posix())
    preset = (project / "export_presets.cfg").read_text(encoding="utf-8")
    for setting in ('tests/*', 'tools/*', '"*.json,assets/data/release_notices.txt"', 'binary_format/embed_pck=false'):
        if setting not in preset:
            raise ValueError(f"Missing release resource filter/option: {setting}")
    main = re.search(r'^run/main_scene="([^"]+)"', (project / "project.godot").read_text(encoding="utf-8"), re.M)
    if main is None or main[1] != manifest["source_main_scene"]:
        raise ValueError("Source main scene changed; review the staging contract before exporting")
    return {"source_main": main[1], "release_main": ENTRY, "runtime_files": len(files), "runtime_bytes": sum(p.stat().st_size for p in files), "tests_excluded": not any("tests" in p.relative_to(project).parts for p in files), "source_project_sha256": sha256(project / "project.godot"), "foundation_files": list(FOUNDATION_RUNTIME_FILES), "indexed_case_files": case_files}


def stage_project(project: Path, stage: Path, template_dir: Path) -> dict:
    validate_project_configuration(project)
    if stage.exists():
        raise FileExistsError(f"Refusing to overwrite an existing stage: {stage}")
    stage.mkdir(parents=True)
    snapshot: dict[str, str] = {}
    for source in runtime_sources(project):
        relative = source.relative_to(project)
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        digest = sha256(target)
        if digest != sha256(source):
            raise RuntimeError(f"Source changed during snapshot: {relative}")
        snapshot[relative.as_posix()] = digest
    # Copy, never hardlink, reusable imported resources. Reimports must not mutate
    # the source checkout's cache; editor logs/shader caches/settings stay out.
    cache = project / ".godot"
    if (cache / "imported").is_dir():
        shutil.copytree(cache / "imported", stage / ".godot" / "imported")
    for name in ("global_script_class_cache.cfg", "uid_cache.bin"):
        if (cache / name).is_file():
            (stage / ".godot").mkdir(exist_ok=True)
            shutil.copy2(cache / name, stage / ".godot" / name)
    settings = (stage / "project.godot").read_text(encoding="utf-8")
    settings, count = re.subn(r'^run/main_scene=.*$', f'run/main_scene="{ENTRY}"', settings, count=1, flags=re.M)
    if count != 1 or "[autoload]" not in settings:
        raise ValueError("Staged project has no unique main scene/autoload section")
    settings = settings.replace("[autoload]", '[autoload]\n\nReleaseBootProbe="*res://scripts/city_release_boot_probe.gd"', 1)
    (stage / "project.godot").write_text(settings, encoding="utf-8")
    (stage / "scripts" / "city_release_boot_probe.gd").write_text(BOOT_PROBE, encoding="utf-8")
    preset = (stage / "export_presets.cfg").read_text(encoding="utf-8")
    for mode in ("debug", "release"):
        template = (template_dir / f"windows_{mode}_x86_64.exe").resolve().as_posix()
        preset = preset.replace(f'custom_template/{mode}=""', f'custom_template/{mode}={json.dumps(template)}')
    (stage / "export_presets.cfg").write_text(preset, encoding="utf-8")
    return snapshot


def package_documents(output: Path, snapshot: dict) -> None:
    output.mkdir(parents=True, exist_ok=False)
    notices = output / "notices"
    notices.mkdir()
    shutil.copy2(PROJECT / "release" / "PLAYING.txt", output / "PLAYING.txt")
    shutil.copy2(PROJECT / "assets" / "data" / "release_notices.txt", notices / "release_notices.txt")
    for name in ("bungee-OFL.txt", "barlowcondensed-OFL.txt", "courierprime-OFL.txt", "SOURCES.json"):
        shutil.copy2(PROJECT / "assets" / "fonts" / name, notices / name)
    write_json(output / "source-snapshot.json", {"scope": "Current runtime files, including dirty/untracked runtime content; excludes tests and development tools", "source_sha256": snapshot})
    manifest = json.loads((PROJECT / "release" / "manifest.json").read_text(encoding="utf-8"))
    with zipfile.ZipFile(output / "map-derived-data.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative in manifest["map_data_sources"]:
            archive.write(ROOT / relative, relative)
        archive.writestr("NOTICE.txt", "© OpenStreetMap contributors. Map-derived databases are provided under ODbL1.0: https://opendatacommons.org/licenses/odbl/1-0/\nSource and attribution: https://www.openstreetmap.org/copyright\n")


def isolated_environment(profile: Path) -> dict[str, str]:
    """Keep editor config, cache, and game user data inside this build's workspace."""
    env = os.environ.copy()
    for variable, child in (("APPDATA", "Roaming"), ("LOCALAPPDATA", "Local")):
        directory = profile / child
        directory.mkdir(parents=True, exist_ok=True)
        env[variable] = str(directory)
    temporary = profile / "temp"
    temporary.mkdir(parents=True, exist_ok=True)
    for variable in ("TEMP", "TMP", "TMPDIR"):
        env[variable] = str(temporary)
    return env


def run_checked(command: list[str], cwd: Path, log: Path, timeout: int, env: dict | None = None) -> None:
    startup = None
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout, startupinfo=startup)
    text = (result.stdout or "") + (result.stderr or "")
    log.write_text(text, encoding="utf-8")
    errors = [line for line in text.splitlines() if line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:"))]
    if result.returncode or errors:
        raise RuntimeError(f"Command failed ({result.returncode}); inspect {log}\n" + "\n".join(errors[:12]))


def finalize(output: Path, validation: dict, build_id: str, source_hash: str) -> dict:
    if (output / "override.cfg").exists():
        raise ValueError("Private validation override.cfg must never ship")
    if not validation.get("passed") or validation.get("main_scene") != ENTRY:
        raise ValueError("Packaged-runtime boot did not pass")
    required = ["Tattletale-PenLucy.exe", "Tattletale-PenLucy.pck", "notices/Godot-MIT.txt", "notices/Godot-third-party.json"]
    for name in required:
        if not (output / name).is_file() or (output / name).stat().st_size == 0:
            raise ValueError(f"Release payload missing: {name}")
    manifest = json.loads((PROJECT / "release" / "manifest.json").read_text(encoding="utf-8"))
    manifest.update(build_id=build_id, built_utc=datetime.now(timezone.utc).isoformat(), source_project_sha256=source_hash, boot_validation=validation)
    manifest["files"] = {p.relative_to(output).as_posix(): {"bytes": p.stat().st_size, "sha256": sha256(p)} for p in sorted(output.rglob("*")) if p.is_file()}
    write_json(output / "release-manifest.json", manifest)
    lines = [f"{sha256(p)}  {p.relative_to(output).as_posix()}" for p in sorted(output.rglob("*")) if p.is_file() and p.name != "SHA256SUMS.txt"]
    (output / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return manifest


def verify(output: Path) -> dict:
    if (output / "override.cfg").exists():
        raise ValueError("Private validation override.cfg must never ship")
    manifest = json.loads((output / "release-manifest.json").read_text(encoding="utf-8"))
    for relative, info in manifest["files"].items():
        path = (output / relative).resolve()
        if not path.is_relative_to(output.resolve()) or not path.is_file() or sha256(path) != info["sha256"]:
            raise ValueError(f"Release checksum mismatch: {relative}")
    for path in output.rglob("*"):
        if path.is_file() and (FORBIDDEN_PARTS.intersection(path.relative_to(output).parts) or path.suffix.lower() in {".log", ".py", ".gd", ".tscn"}):
            raise ValueError(f"Development file leaked into standalone folder: {path.name}")
        if path.is_file() and path.relative_to(output).as_posix() not in set(manifest["files"]) | {"release-manifest.json", "SHA256SUMS.txt"}:
            raise ValueError(f"Unmanifested release payload: {path.name}")
    for line in (output / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        digest, relative = line.split("  ", 1)
        path = (output / relative).resolve()
        if not path.is_relative_to(output.resolve()) or not path.is_file() or sha256(path) != digest:
            raise ValueError(f"Release checksum-list mismatch: {relative}")
    return {"verified": True, "files": len(manifest["files"]), "build_id": manifest["build_id"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--build", action="store_true")
    mode.add_argument("--verify", type=Path)
    parser.add_argument("--build-id", default=datetime.now(timezone.utc).strftime("rc-%Y%m%d-%H%M%S"))
    parser.add_argument("--templates-dir", type=Path, default=Path.home() / "AppData/Roaming/Godot/export_templates" / TEMPLATE_VERSION)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(verify(args.verify.resolve()), indent=2))
        return 0
    checks = validate_sources()
    if args.check:
        print(json.dumps(checks, indent=2))
        return 0
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", args.build_id):
        raise ValueError("Build ID must be a short directory name, without path separators")
    template = args.templates_dir / "windows_release_x86_64.exe"
    if not template.is_file():
        raise FileNotFoundError(f"Install matching {TEMPLATE_VERSION} Windows templates: {template}")
    build_root = ROOT / ".work" / "release-stage" / args.build_id
    stage = build_root / "project"
    output = ROOT / "artifacts" / "releases" / args.build_id
    snapshot = stage_project(PROJECT, stage, args.templates_dir)
    package_documents(output, snapshot)
    plan = {"build_id": args.build_id, "stage": str(stage), "output": str(output), "main_scene": ENTRY, "source_unchanged": sha256(PROJECT / "project.godot") == checks["source_project_sha256"], "prepared_only": not args.build}
    write_json(build_root / "release-plan.json", plan)
    if not args.build:
        print(json.dumps(plan, indent=2))
        return 0
    # Reuse the exact shared wrapper lock. Explicit stage --path avoids touching
    # the editor project and avoids nesting godot_run.py's lock inside this one.
    from godot_preview import GodotLock, GODOT, LOCK
    with GodotLock():
        stopped = threading.Event()
        def heartbeat() -> None:
            while not stopped.wait(20):
                os.utime(LOCK, None)
        worker = threading.Thread(target=heartbeat, daemon=True)
        worker.start()
        try:
            build_env = isolated_environment(build_root / "editor-profile")
            run_checked([GODOT, "--headless", "--path", str(stage), "--import"], stage, build_root / "import.log", args.timeout, build_env)
            exe = output / "Tattletale-PenLucy.exe"
            run_checked([GODOT, "--headless", "--path", str(stage), "--export-release", PRESET, str(exe)], stage, build_root / "export.log", args.timeout, build_env)
            report = build_root / "standalone-boot.json"
            env = isolated_environment(build_root / "validation-profile")
            run_checked([str(exe), "--headless", "--", "--offscreen-validation", "--release-smoke", f"--release-report={report}", f"--release-license-dir={output / 'notices'}"], output, build_root / "standalone-boot.log", args.timeout, env)
        finally:
            stopped.set()
            worker.join(timeout=2)
    if sha256(PROJECT / "project.godot") != checks["source_project_sha256"]:
        raise RuntimeError("Source project.godot changed during export; inspect before accepting build")
    validation = json.loads(report.read_text(encoding="utf-8"))
    finalize(output, validation, args.build_id, checks["source_project_sha256"])
    receipt = verify(output)
    archive = output.parent / (output.name + ".zip")
    if archive.exists():
        raise FileExistsError(archive)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                package.write(path, output.name + "/" + path.relative_to(output).as_posix())
    receipt.update(zip=str(archive), zip_sha256=sha256(archive), source_project_unchanged=True)
    write_json(build_root / "release-receipt.json", receipt)
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"[release] FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
