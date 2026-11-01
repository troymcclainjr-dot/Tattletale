"""Serialized full-world session/soak gates; run only when implementation workers idle.

Examples (root agent owns engine execution):
  python godot/tools/validate_priorities_session.py --mode session
  python godot/tools/validate_priorities_session.py --mode soak --seconds 120
  python godot/tools/validate_priorities_session.py --mode soak --seconds 900 --render
  python godot/tools/validate_priorities_session.py --mode soak --seconds 3600 --render

Headless draw-call values are deliberately marked unavailable. The wrapper fails
on any engine diagnostic, missing completion, failed check, timeout or source drift.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from validate_city import source_hashes

ROOT = Path(__file__).resolve().parents[2]
ERROR_MARKERS = ("SCRIPT ERROR:", "SHADER ERROR:", "ERROR:", "Parse Error")
SESSION_PHASES = {"supplies", "stopped-civilian-input", "parked-promotion-drive-impact",
                  "gunfire-cruiser-pursuit-loss-surrender", "shop-after-recovery",
                  "branching-story", "save-scene-reload"}
SOAK_PHASES = {"soak-warmup", "soak-walk", "soak-drive", "soak-modals", "soak-checkpoint",
               "soak-cycle-boundary", "soak-budgets"}


def provenance() -> dict:
    hashes = source_hashes()
    this_file = Path(__file__).resolve()
    hashes[str(this_file.relative_to(ROOT))] = hashlib.sha256(this_file.read_bytes()).hexdigest()
    return hashes


def isolated_environment(scratch: Path) -> dict[str, str]:
    """Give the runner and its engine child a fresh, writable Windows profile."""
    appdata = scratch / "profile" / "AppData" / "Roaming"
    local_appdata = scratch / "profile" / "AppData" / "Local"
    (appdata / "Godot" / "app_userdata" / "Tattletale 2-Pack" / "logs").mkdir(parents=True, exist_ok=False)
    local_appdata.mkdir(parents=True, exist_ok=False)
    environment = os.environ.copy()
    environment["APPDATA"] = str(appdata.resolve())
    environment["LOCALAPPDATA"] = str(local_appdata.resolve())
    return environment


def evaluate(result: dict, log: str, returncode: int, frozen: bool, mode: str = "session") -> dict:
    errors = [line for line in log.splitlines() if any(token in line for token in ERROR_MARKERS)]
    complete = result.get("complete") is True and "[priorities_session] COMPLETE " in log
    required = SESSION_PHASES | (SOAK_PHASES if mode == "soak" else set())
    phases = result.get("phases", {})
    missing = sorted(phase for phase in required if phases.get(phase, 0) < 1)
    details = result.get("details", {})
    soak_complete = True
    if mode == "soak":
        requested = details.get("requested_soak_seconds", 0)
        measured = details.get("measured_soak_seconds", 0)
        soak_complete = (isinstance(requested, (float, int)) and not isinstance(requested, bool)
                         and isinstance(measured, (float, int)) and not isinstance(measured, bool)
                         and 30 <= requested <= measured
                         and details.get("aborted_after_primary_failure") is False
                         and details.get("cycles_settled") is True)
    passed = (returncode == 0 and complete and result.get("passed") is True
              and result.get("failures") == 0 and result.get("passes", 0) > 0
              and not errors and not missing and frozen and soak_complete)
    return {"passed": passed, "complete": complete, "returncode": returncode,
            "soak_duration_complete": soak_complete if mode == "soak" else None,
            "frozen_tree": frozen, "engine_errors": errors, "missing_phases": missing, "fixture": result}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("session", "soak"), default="session")
    parser.add_argument("--seconds", type=int, default=900,
                        help="real wall-clock soak seconds, excluding boot/integration gate")
    parser.add_argument("--render", action="store_true", help="private offscreen Vulkan render")
    parser.add_argument("--branch", default="report", choices=("report", "protect", "negotiate", "intimidate"))
    args = parser.parse_args()
    if not 30 <= args.seconds <= 14400:
        parser.error("--seconds must be between 30 and 14400")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%f") + "_" + args.mode
    scratch = ROOT / ".work/priorities-five/session-validation" / run_id
    destination = ROOT / "artifacts/priorities-five/session-validation" / run_id
    scratch.mkdir(parents=True, exist_ok=False)
    destination.mkdir(parents=True, exist_ok=False)
    environment = isolated_environment(scratch)
    timeout = args.seconds + 660 if args.mode == "soak" else 660
    engine = ["--resolution", "1920x1080"] if args.render else ["--headless"]
    command = [sys.executable, str(ROOT / "godot/tools/godot_run.py"), "--timeout", str(timeout), "--",
               *engine, "--max-fps", "60", "--script", f"res://tests/city_priorities_{args.mode}.gd", "--",
               "--offscreen-validation", f"--session-run-id={run_id}",
               f"--session-seconds={args.seconds if args.mode == 'soak' else 0}", f"--session-branch={args.branch}"]
    before = provenance()
    (destination / "source-before.json").write_text(json.dumps(before, indent=2), encoding="utf-8")
    (destination / "command.json").write_text(json.dumps(command, indent=2), encoding="utf-8")
    began = time.monotonic()
    log_path = destination / "engine.log"
    # godot_run owns the shared engine lock, hidden child process, timeout, and
    # diagnostic-aware termination. Do not bypass it with a direct executable.
    with log_path.open("w", encoding="utf-8") as stream:
        process = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                 env=environment,
                                 creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
    after = provenance()
    (destination / "source-after.json").write_text(json.dumps(after, indent=2), encoding="utf-8")
    result_path = scratch / "result.json"
    try:
        result = json.loads(result_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        result = {}
    log = log_path.read_text(encoding="utf-8", errors="replace")
    verdict = evaluate(result, log, process.returncode, before == after, args.mode)
    verdict.update({"mode": args.mode, "requested_soak_seconds": args.seconds if args.mode == "soak" else 0,
                    "wall_seconds": time.monotonic() - began, "rendered": args.render,
                    "draw_calls_available": args.render, "scratch": str(scratch),
                    "isolated_appdata": environment["APPDATA"]})
    for name in ("result.json", "samples.jsonl"):
        if (scratch / name).exists():
            (destination / name).write_bytes((scratch / name).read_bytes())
    (destination / "verdict.json").write_text(json.dumps(verdict, indent=2), encoding="utf-8")
    print(json.dumps({"passed": verdict["passed"], "evidence": str(destination)}, indent=2))
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
