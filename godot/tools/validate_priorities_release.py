"""Isolated Windows export plus gameplay, API reload, and normal startup restore.

--check does file-only checks. --build is root-only engine work under GodotLock.
Every build ID is immutable; this tool never replaces an existing destination.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import uuid
import zipfile

import export_city_release as release

ROOT = release.ROOT
DESTINATION = ROOT / "artifacts/priorities-five/release"
WORK = ROOT / ".work/priorities-five/release"
PROFILE_ROOT = ROOT / ".work/rp"
SHADER_CACHE_TAIL_BUDGET = 130
WINDOWS_PATH_BUDGET = 259
PROBE = Path(__file__).with_name("priorities_release_probe.gd")
POINTER_GUARD_ARGUMENT = "--priorities-release-phase=startup"
PRIVATE_STARTUP_OVERRIDE = """; Private standalone validation only; never package this file.
[display]
window/size/no_focus=true
window/size/mode=0
window/size/initial_position_type=0
window/size/initial_position=Vector2i(-10000, -10000)
window/size/always_on_top=false
"""
POINTER_GUARD_REPLACEMENTS = (
    ("\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE if offscreen_validation else Input.MOUSE_MODE_CAPTURED",
     '\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE if (offscreen_validation or OS.get_cmdline_user_args().has("'
     + POINTER_GUARD_ARGUMENT + '")) else Input.MOUSE_MODE_CAPTURED'),
    ("\t\t\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED",
     '\t\t\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.get_cmdline_user_args().has("'
     + POINTER_GUARD_ARGUMENT + '") else Input.MOUSE_MODE_CAPTURED'),
)
COMMON_CHECKS = {"world_ready", "release_template", "main_scene", "population", "no_placeholders", "inspector_present", "packed_credits", "packed_fonts_and_licenses",
                 "pacifist_policy", "foundation_services", "phone_bicycle_schema", "foundation_bridges",
                 "packed_case_library", "foundation_schema", "foundation_checkpoint", "foundation_restore"}
PHASE_CHECKS = {
    "fresh": {"fresh_save_absent", "fresh_settings_absent", "input_moves_player", "production_progression_transaction", "settings_apply", "production_save", "foundation_fixture_created"},
    "reload": {"reload_save_present", "production_reload", "progression_restored", "settings_loaded_on_startup"},
    "startup": {"normal_startup_mode", "save_enabled_by_startup", "automatic_world_restore", "startup_save_present",
                "startup_progression_restored", "startup_clock_restored", "settings_loaded_on_startup",
                "startup_private_window", "startup_mouse_uncaptured", "startup_guard_kept_mouse_visible", "startup_project_no_focus"},
}


def fingerprint(directory: Path) -> dict[str, str]:
    return {p.relative_to(directory).as_posix(): release.sha256(p) for p in sorted(directory.rglob("*")) if p.is_file()}


def source_fingerprint() -> dict[str, str]:
    return {p.relative_to(release.PROJECT).as_posix(): release.sha256(p) for p in release.runtime_sources(release.PROJECT)}


def private_startup_override(install: Path, create: bool = False) -> dict:
    """Godot reads this beside the private EXE before creating its native window.

    EXE/PCK and shipping project settings remain byte-identical to the release.
    The private copy includes this file in its read-only-install fingerprint.
    """
    directory = install.absolute()
    if directory.resolve() != directory or not directory.is_relative_to(WORK.resolve()) or not directory.is_dir():
        raise ValueError("Startup override requires a private, unlinked validation install")
    path = directory / "override.cfg"
    if path.is_symlink() or (path.exists() and path.stat().st_nlink > 1):
        raise ValueError("Startup override must not be linked")
    if create:
        with path.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(PRIVATE_STARTUP_OVERRIDE)
    if not path.is_file() or path.read_bytes() != PRIVATE_STARTUP_OVERRIDE.encode("utf-8"):
        raise ValueError("Missing or changed private startup no-focus override")
    return {"path": str(path), "sha256": release.sha256(path), "settings": PRIVATE_STARTUP_OVERRIDE,
            "scope": "Private validation install only; absent from shipped output and PCK"}


def startup_pointer_guard(source: str) -> str:
    """Change only stage-copy capture assignments; refuse source-shape drift."""
    for function, (before, after) in zip(("resume_exploring", "_input"), POINTER_GUARD_REPLACEMENTS):
        match = re.search(rf"(?ms)^func {function}\([^\n]*\n.*?(?=^func |\Z)", source)
        if source.splitlines().count(before) != 1 or match is None or before not in match.group():
            raise ValueError(f"Startup pointer guard target changed: {function}")
        source = source.replace(before + "\n", after + "\n", 1)
    return source


def shader_cache_path_budget(profile: Path) -> int:
    """Worst-case UTF-16 path length including shader name/hash suffix space."""
    cache = profile.resolve() / "Roaming/Godot/app_userdata/Tattletale 2-Pack/shader_cache"
    return len(str(cache).encode("utf-16-le")) // 2 + SHADER_CACHE_TAIL_BUDGET


def reserve_profiles(build_id: str) -> dict[str, Path]:
    """Claim one compact, immutable profile namespace; collisions fail closed."""
    base = PROFILE_ROOT.resolve()
    if not base.is_relative_to((ROOT / ".work").resolve()):
        raise ValueError("Release profiles must remain inside the project workspace")
    root = base / hashlib.sha256(build_id.encode("utf-8")).hexdigest()[:12]
    profiles = {"editor": root / "e", "boot": root / "b", "runtime": root / "é 東京"}
    if any(shader_cache_path_budget(path) > WINDOWS_PATH_BUDGET for path in profiles.values()):
        raise ValueError("Isolated profile exceeds Windows shader-cache path budget")
    root.mkdir(parents=True, exist_ok=False)
    for profile in profiles.values():
        profile.mkdir(exist_ok=False)
    return profiles


def private_startup_window(window: dict) -> bool:
    def valid_rect(rect):
        return (isinstance(rect, list) and len(rect) == 4 and all(type(v) is int for v in rect)
                and rect[2] > 0 and rect[3] > 0)
    if not isinstance(window, dict):
        return False
    rect, screens = window.get("rect"), window.get("screen_rects")
    if (window.get("outside_all_screens") is not True or window.get("unfocusable") is not True
            or type(window.get("focused")) is not bool or type(window.get("mouse_mode")) is not int
            or window["mouse_mode"] != 0 or not valid_rect(rect)
            or not isinstance(screens, list) or not screens or not all(valid_rect(s) for s in screens)):
        return False
    x, y, width, height = rect
    return all(x + width <= sx or sx + sw <= x or y + height <= sy or sy + sh <= y
               for sx, sy, sw, sh in screens)


def native_focus_private(evidence: dict, runtime_pid: int) -> bool:
    if not isinstance(evidence, dict) or type(runtime_pid) is not int or runtime_pid <= 0:
        return False
    pids = evidence.get("foreground_pids")
    return (evidence.get("runtime_pid") == runtime_pid and evidence.get("runtime_was_foreground") is False
            and evidence.get("errors") == [] and type(evidence.get("samples")) is int and evidence["samples"] >= 2
            and isinstance(pids, list) and bool(pids) and all(type(pid) is int and pid > 0 and pid != runtime_pid for pid in pids))


def native_foreground_reader():
    """Read-only Win32 query, independent of Godot's cached window focus."""
    if os.name != "nt":
        raise ValueError("Native startup focus evidence requires Windows")
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD

    def read():
        handle = user32.GetForegroundWindow()
        pid = wintypes.DWORD()
        if handle:
            user32.GetWindowThreadProcessId(handle, ctypes.byref(pid))
        return int(pid.value)
    return read


def run_startup_checked(argv: list[str], cwd: Path, log: Path, timeout: int, env: dict) -> dict:
    """Observe only our child; never changes another window, cursor or focus."""
    query = native_foreground_reader()  # Establish support before launching.
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace", startupinfo=startup)
    evidence = {"runtime_pid": process.pid, "samples": 0, "unknown_samples": 0,
                "foreground_pids": [], "runtime_was_foreground": False, "errors": []}
    stopped = threading.Event()

    def monitor():
        while not stopped.is_set() and process.poll() is None:
            try:
                pid = query()
                if pid > 0:
                    evidence["samples"] += 1
                    if pid not in evidence["foreground_pids"]:
                        evidence["foreground_pids"].append(pid)
                    if pid == process.pid:
                        evidence["runtime_was_foreground"] = True
                        process.terminate()  # Only the owned probe; fail immediately.
                        return
                else:
                    evidence["unknown_samples"] += 1
            except Exception as error:
                evidence["errors"].append(str(error))
                process.terminate()
                return
            stopped.wait(0.02)

    watcher = threading.Thread(target=monitor, daemon=True)
    watcher.start()
    output = ""
    try:
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
            raise
    finally:
        stopped.set()
        watcher.join(timeout=2)
        if watcher.is_alive():
            evidence["errors"].append("native foreground monitor did not stop")
        log.write_text(output, encoding="utf-8")
        release.write_json(log.with_suffix(".native-foreground.json"), evidence)
    errors = [line for line in output.splitlines() if line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:"))]
    if process.returncode or errors or not native_focus_private(evidence, process.pid):
        raise RuntimeError(f"Startup runtime/focus validation failed; inspect {log}")
    return evidence


def validate_receipt(receipt: dict, phase: str, nonce: str, profile: Path, install: Path) -> None:
    if receipt.get("passed") is not True or receipt.get("phase") != phase or receipt.get("nonce") != nonce:
        raise ValueError("Missing, stale, or failed standalone gameplay receipt")
    checks = receipt.get("checks", {})
    if any(checks.get(key) is not True for key in COMMON_CHECKS | PHASE_CHECKS[phase]):
        raise ValueError(f"Incomplete standalone assertions for {phase}")
    if receipt.get("editor") is not False or receipt.get("debug") is not False or receipt.get("main_scene") != release.ENTRY:
        raise ValueError("Smoke did not run the release main scene/template")
    for key in ("user_data_dir", "save_path", "settings_path"):
        if not Path(receipt[key]).resolve().is_relative_to(profile.resolve()):
            raise ValueError(f"Runtime {key} escaped isolated profile")
    if Path(receipt["executable"]).resolve() != (install / "Tattletale-PenLucy.exe").resolve():
        raise ValueError("Receipt came from a different executable")
    if not re.fullmatch(r"[0-9a-f]{64}", receipt.get("save_sha256", "")):
        raise ValueError("Missing checkpoint digest")
    if phase == "startup":
        if type(receipt.get("startup_mouse_before_pause")) is not int or receipt["startup_mouse_before_pause"] != 0:
            raise ValueError("Startup pointer guard did not prevent capture before probe pause")
        window = receipt.get("startup_window", {})
        if not private_startup_window(window):
            raise ValueError("Startup probe did not remain offscreen, unfocusable and mouse-uncaptured")
        if not native_focus_private(receipt.get("native_foreground"), receipt.get("runtime_pid")):
            raise ValueError("Startup lacks independent native foreground evidence for its owned runtime PID")
        loaded = receipt.get("startup_load", {})
        if (receipt.get("save_enabled_at_startup") is not True or receipt.get("offscreen_validation") is not False
                or receipt.get("display_server") in (None, "", "headless")
                or loaded.get("ok") is not True or loaded.get("partial") is not False):
            raise ValueError("Normal startup did not automatically restore the checkpoint")
    resources = receipt.get("resource_files", [])
    if "res://assets/data/release_notices.txt" not in resources or "res://assets/fonts/SOURCES.json" not in resources:
        raise ValueError("Resource manifest is missing packaged attribution")
    if any(p.startswith(("res://tests/", "res://tools/")) for p in resources):
        raise ValueError("Development tests/tools leaked into PCK")


def command(command: list[str], log: Path, cwd: Path, timeout: int, env: dict | None = None) -> dict | None:
    # Never inherit an editor/player profile or rely on the parent's scratch env.
    for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
        directory = Path((env or {}).get(key, ""))
        owned = any(directory.resolve().is_relative_to(root.resolve()) for root in (WORK, PROFILE_ROOT))
        if not directory.is_absolute() or not owned or not directory.is_dir():
            raise ValueError(f"Child {key} must use an existing isolated workspace directory")
    command = list(command)
    engine_args = command[:command.index("--")] if "--" in command else command
    if "--log-file" not in engine_args:
        command[1:1] = ["--log-file", str(log.with_suffix(".engine.log").resolve())]
    # Log exact argv as data, never as a shell expression. Logs are outside install.
    release.write_json(log.with_suffix(".argv.json"), command)
    if POINTER_GUARD_ARGUMENT in command:
        if Path(command[0]).resolve().parent != cwd.resolve():
            raise ValueError("Startup executable must be in its private validation cwd")
        private_startup_override(cwd)  # Fail before Popen if creation-time guard is absent.
        return run_startup_checked(command, cwd, log, timeout, env)
    release.run_checked(command, cwd, log, timeout, env)


def runtime_command(executable: Path, phase: str, receipt: Path, nonce: str, profile: Path) -> list[str]:
    if phase not in PHASE_CHECKS:
        raise ValueError(f"Unknown standalone phase: {phase}")
    if phase == "startup":
        # A real display server and ordinary startup are required: both headless
        # and offscreen-validation intentionally disable production save loading.
        engine = ["--windowed", "--position", "-10000,-10000", "--resolution", "960x540",
                  "--audio-driver", "Dummy", "--max-fps", "60"]
        user = []
    else:
        engine = ["--headless"]
        user = ["--offscreen-validation"]
    return [str(executable), *engine, "--log-file", str(profile / f"{phase}-engine.log"), "--", *user,
            f"--priorities-release-phase={phase}", f"--priorities-release-report={receipt}",
            f"--priorities-release-nonce={nonce}"]


@contextmanager
def deny_install_writes(install: Path, work: Path):
    """Deny only current user's writes in a brand-new owned install, then restore.

    File attributes alone do not make a Windows directory unwritable. Fail closed
    if the ACL cannot be set or the write probe unexpectedly succeeds.
    """
    if os.name != "nt" or not install.resolve().is_relative_to(work.resolve()):
        raise ValueError("Read-only installation test requires owned Windows work directory")
    sid_output = subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"], text=True, encoding="utf-8", errors="replace")
    match = re.search(r"S-1-\d+(?:-\d+)+", sid_output)
    if not match:
        raise ValueError("Cannot resolve current Windows user SID")
    sid = "*" + match[0]
    # Deny concrete mutation rights, not generic W (which also denies
    # SYNCHRONIZE and can prevent Windows from opening the executable at all).
    result = subprocess.run(["icacls", str(install), "/deny", sid + ":(OI)(CI)(WD,AD,WEA,WA,DE,DC)"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    try:
        if result.returncode:
            raise RuntimeError("Cannot apply owned-install write denial: " + result.stdout + result.stderr)
        probe = install / ".write-denial-test"
        try:
            with probe.open("xb") as stream:
                stream.write(b"write denial failed")
        except PermissionError:
            pass
        else:
            raise RuntimeError("Install remains writable; read-only assertion is invalid")
        yield
    finally:
        restored = subprocess.run(["icacls", str(install), "/remove:d", sid], capture_output=True, text=True, encoding="utf-8", errors="replace")
        if restored.returncode:
            raise RuntimeError("Failed to restore this run's install ACL: " + str(install))


def verify_zip(archive: Path, output: Path) -> dict:
    expected = fingerprint(output)
    with zipfile.ZipFile(archive) as zipped:
        actual = zipped.namelist()
        if len(actual) != len(set(actual)) or set(actual) != {output.name + "/" + p for p in expected}:
            raise ValueError("ZIP members do not exactly match the verified release")
        import hashlib
        for relative, digest in expected.items():
            if hashlib.sha256(zipped.read(output.name + "/" + relative)).hexdigest() != digest:
                raise ValueError(f"ZIP checksum mismatch: {relative}")
    return {"files": len(expected), "sha256": release.sha256(archive)}


def build(args: argparse.Namespace) -> dict:
    if os.name != "nt":
        raise ValueError("This Windows standalone validator must run on Windows")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", args.build_id):
        raise ValueError("Build ID must be a short directory name")
    checks = release.validate_sources()
    template = args.templates_dir / "windows_release_x86_64.exe"
    if not template.is_file():
        raise FileNotFoundError(template)
    output = DESTINATION / args.build_id
    work = WORK / args.build_id
    archive = output.parent / (output.name + ".zip")
    for path in (output, work, archive):
        if path.exists():
            raise FileExistsError(f"Refusing to overwrite: {path}")
    profiles = reserve_profiles(args.build_id)
    before = source_fingerprint()
    stage = work / "stage"
    snapshot = release.stage_project(release.PROJECT, stage, args.templates_dir)
    if before != snapshot:
        raise RuntimeError("Source changed while staging; use a new build ID after writers finish")
    guarded_level = stage / "scripts/city/pen_lucy_level.gd"
    guarded_level.write_text(startup_pointer_guard(guarded_level.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copy2(PROBE, stage / "scripts/priorities_release_probe.gd")
    config = stage / "project.godot"
    config.write_text(config.read_text(encoding="utf-8").replace("[autoload]", '[autoload]\nPrioritiesReleaseProbe="*res://scripts/priorities_release_probe.gd"', 1), encoding="utf-8")
    preset = stage / "export_presets.cfg"
    preset.write_text(preset.read_text(encoding="utf-8").replace('include_filter="*.json,assets/data/release_notices.txt"', 'include_filter="*.json,assets/data/release_notices.txt,assets/fonts/*-OFL.txt"'), encoding="utf-8")
    release.package_documents(output, snapshot)
    release.write_json(work / "source-fingerprint.json", before)
    profile_manifest = {name: {"path": str(path), "shader_cache_path_budget": shader_cache_path_budget(path)}
                        for name, path in profiles.items()}
    release.write_json(work / "profiles.json", profile_manifest)
    release.write_json(output / "stage-overrides.json", {
        "purpose": "Stage-only entry scene, dormant probes, explicit templates, packed font notices and startup-only pointer guard",
        "startup_pointer_guard": {
            "file": "scripts/city/pen_lucy_level.gd", "argument": POINTER_GUARD_ARGUMENT,
            "changes": [{"before": old, "after": new} for old, new in POINTER_GUARD_REPLACEMENTS],
            "scope": "Only mouse capture assignments; automatic world-save setup/load and normal launch behavior unchanged",
        },
        "sha256": {str(p.relative_to(stage).as_posix()): release.sha256(p) for p in (
            config, preset, guarded_level, stage / "scripts/city_release_boot_probe.gd", stage / "scripts/priorities_release_probe.gd")},
    })
    nonce = uuid.uuid4().hex
    install = work / "Standalone install é 東京"  # Windows path portability exercised.
    profile = profiles["runtime"]
    from godot_preview import GODOT, GodotLock, LOCK
    with GodotLock():
        stopped = threading.Event()
        def heartbeat():
            while not stopped.wait(20):
                os.utime(LOCK, None)
        worker = threading.Thread(target=heartbeat, daemon=True)
        worker.start()
        try:
            env = release.isolated_environment(profiles["editor"])
            command([GODOT, "--headless", "--path", str(stage), "--import"], work / "import.log", stage, args.timeout, env)
            exe = output / "Tattletale-PenLucy.exe"
            command([GODOT, "--headless", "--path", str(stage), "--export-release", release.PRESET, str(exe)], work / "export.log", stage, args.timeout, env)
            # Make the exact source/import-cache path used by the exporter cease
            # to exist before any exported runtime starts. Only our stage moves.
            stage.rename(work / "stage-offline")
            boot = work / "standalone-boot.json"
            command([str(exe), "--headless", "--", "--offscreen-validation", "--release-smoke", f"--release-report={boot}", f"--release-license-dir={output / 'notices'}"], work / "boot.log", output, args.timeout, release.isolated_environment(profiles["boot"]))
            shutil.copytree(output, install)
            startup_override = private_startup_override(install, create=True)
            release.write_json(work / "startup-project-override.json", startup_override)
            original_install = fingerprint(install)
            # Runtime cwd is source-free; no --path, --script, editor executable,
            # copied import cache, or development test scripts are supplied.
            env = release.isolated_environment(profile)
            receipts = {}
            with deny_install_writes(install, work):
                for phase in ("fresh", "reload", "startup"):
                    receipt_path = work / f"{phase}.json"
                    native_focus = command(runtime_command(install / exe.name, phase, receipt_path, nonce, profile),
                                           work / f"{phase}.log", install, args.timeout, env)
                    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                    if phase == "startup":
                        receipt["native_foreground"] = native_focus
                        release.write_json(receipt_path, receipt)
                    validate_receipt(receipt, phase, nonce, profile, install)
                    for key in ("save_path", "settings_path"):
                        if not Path(receipt[key]).is_file():
                            raise ValueError(f"Missing {key} after {phase}")
                    if not (profile / f"{phase}-engine.log").is_file():
                        raise ValueError("Engine log did not use the isolated log path")
                    receipts[phase] = receipt
            if original_install != fingerprint(install):
                raise ValueError("Standalone runtime modified installation files")
            for phase in ("reload", "startup"):
                if receipts["fresh"]["money"] != receipts[phase]["money"] or receipts["fresh"]["save_sha256"] != receipts[phase]["save_sha256"]:
                    raise ValueError(f"{phase} process did not preserve first process checkpoint")
        finally:
            if (work / "stage-offline").exists() and not stage.exists():
                (work / "stage-offline").rename(stage)
            stopped.set()
            worker.join(timeout=2)
    if source_fingerprint() != before:
        raise RuntimeError("Source runtime changed during build; candidate is not final")
    boot_receipt = json.loads(boot.read_text(encoding="utf-8"))
    summary = {"passed": True, **receipts, "install_write_denial_verified": True, "install_unchanged": True,
               "source_runtime_unchanged": True,
               "startup_project_override": startup_override,
               "isolated_profiles": profile_manifest,
               "scope": "Headless exported gameplay/input/settings/save-load API plus ordinary graphical startup automatic world restore; not GPU visual acceptance"}
    release.write_json(output / "standalone-gameplay-validation.json", summary)
    release.finalize(output, boot_receipt, args.build_id, checks["source_project_sha256"])
    result = release.verify(output)
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as zipped:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                zipped.write(path, output.name + "/" + path.relative_to(output).as_posix())
    result.update(zip=str(archive), zip_integrity=verify_zip(archive, output), gameplay_passed=True, work=str(work))
    release.write_json(work / "receipt.json", result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--build", action="store_true")
    mode.add_argument("--verify", type=Path)
    parser.add_argument("--build-id", default=datetime.now(timezone.utc).strftime("priorities-%Y%m%d-%H%M%S"))
    parser.add_argument("--templates-dir", type=Path, default=Path.home() / "AppData/Roaming/Godot/export_templates" / release.TEMPLATE_VERSION)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.check:
        result = release.validate_sources()
        result.update(probe_sha256=release.sha256(PROBE), engine_started=False)
    elif args.verify:
        result = release.verify(args.verify.resolve())
        result["zip_integrity"] = verify_zip(args.verify.resolve().parent / (args.verify.name + ".zip"), args.verify.resolve())
    else:
        result = build(args)
    print(json.dumps(result, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"[priorities_release] FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
