"""Collect the neighborhood pass's measured evidence; run from the repo root."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/neighborhood-pass"
WORK = ROOT / ".work/neighborhood-pass"

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def compact_benchmark(name):
    data = read(ROOT / "artifacts/civic-build" / name / "metrics.json")
    return {key: data.get(key) for key in (
        "delivered_fps", "frame_ms", "viewport_gpu_ms", "viewport_render_cpu_ms",
        "draw_calls", "valid_active_play", "cars")}

reports = {}
for name in ("facade-layout-check.json", "fleet-batch-report.json", "park-crowd-audit.json",
             "police-lot-report.json", "street-parking-audit.json", "vehicle-engine-acceptance.json"):
    reports[name] = read(WORK / name)
    (OUT / name).write_text(json.dumps(reports[name], indent=2) + "\n", encoding="utf-8")

tests = {}
for name in ("expansion-final-engine.log", "finalvehicles-engine.log", "inspector-final.log",
             "traffic-run.log", "utilities-material-engine.log", "acceptance-visual-engine.log"):
    text = (WORK / name).read_text(encoding="utf-8-sig")
    tests[name] = {"pass": len(re.findall(r"\bPASS\b", text)),
                   "fail": len(re.findall(r"\bFAIL\b", text)),
                   "script_or_shader_errors": len(re.findall(r"SCRIPT ERROR|SHADER ERROR", text))}
park_lines = (WORK / "parks-clearance-engine.log").read_text(encoding="utf-8-sig").splitlines()
park = next(json.loads(line) for line in reversed(park_lines) if line.startswith('{"failures"'))
tests["parks-clearance-engine.log"] = park

visual = read(OUT / "visual/integration-report.json")
source_paths = list((ROOT / "godot/scripts/city").glob("*.gd")) + [
    ROOT / "blender/city/kits.py", ROOT / "blender/city/process.py", ROOT / "blender/city/runtime.py",
    ROOT / "godot/assets/models/city/pen_lucy.glb"]
source_paths += list((ROOT / "godot/assets/data").glob("pen_lucy*.json"))
acceptance = {
    "scope": "Neighborhood architecture, civic parking, crowds, parks, utilities and fly-camera map",
    "complete": True,
    "desktop_control_used": False,
    "render_validation": "Private GPU SubViewport; no desktop input or foreground game window",
    "visual_report": "visual/integration-report.json",
    "runtime_counts": {key: visual.get(key) for key in ("parking", "fleet", "parks", "power", "details", "vegetation")},
    "tests": tests,
    "performance": {
        "conditions": "1920x1080 Balanced, 4x MSAA, 20-second active Old York route, private viewport",
        "runs": {name: compact_benchmark(name) for name in (
            "neighborhood-before", "neighborhood-runtime", "neighborhood-no-fleet",
            "neighborhood-batched", "neighborhood-final", "neighborhood-final-repeat",
            "neighborhood-final-no-fleet")},
        "finding": "Civic fleet surface batching fixes a confirmed submission explosion (447 to 39 surfaces). Final full-build runs vary substantially; they do not establish baseline performance parity.",
        "limitation": "Final full-build FPS 100.8 to 125.5 versus an earlier 166.8 baseline. Final no-fleet control 122.1 FPS. System-wide CPU sampling found Spotify and browser activity, but does not prove this explains the deficit. Three overlapping playground shrubs were removed after these timing samples; functional and visual validation was rerun.",
        "no_density_or_quality_reduction": True,
    },
    "agents": {
        "native": "Three reused GPT-6 Astra workers, high reasoning, native collaboration route",
        "architecture": "Claude Opus 5.5 high, headless CLI --no-session-persistence, no wall-clock timeout; receipt verified actual claude-opus-5-5 and exit 0",
        "root": "Exact model and reasoning effort not exposed by runtime",
    },
    "source_sha256": {str(path.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths},
}
(OUT / "acceptance.json").write_text(json.dumps(acceptance, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"written": "artifacts/neighborhood-pass/acceptance.json", "tests": {key: (value.get("fail", value.get("failures", []))) for key, value in tests.items()}}))
