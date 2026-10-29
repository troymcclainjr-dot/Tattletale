"""Render the city GLB inside the Godot port, with the game's clay shader and lighting.

    python blender/city/godot_shot.py [out.png]

The GLB is read at runtime (city_shot.gd), so nothing is imported into the Godot project. Uses the
port's shared Godot lock and binary from godot/tools/godot_preview.py. The cameras are the ones
process.py placed on the terrain. Set TATTLETALE_GODOT to point at a different Godot project.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config as C

GODOT_PROJECT = os.environ.get("TATTLETALE_GODOT") or next(
    p for p in (os.path.join(C.ROOT, "godot"), r"C:\files\projects\Tattletale\godot")
    if os.path.exists(os.path.join(p, "project.godot")))
sys.path.insert(0, os.path.join(GODOT_PROJECT, "tools"))
import godot_preview as gp

GLB = os.path.join(C.ROOT, "godot", "assets", "models", "city", C.AREA + ".glb")
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "city_shot.gd")


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(C.ROOT, ".work", "previews", C.AREA + "_godot.png"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    views = json.load(open(C.GEOM_JSON))["views"]
    arg = ";".join("|".join([",".join(f"{c:.2f}" for c in v["eye"]), ",".join(f"{c:.2f}" for c in v["look"]), str(v["fov"])])
                   for v in views[:4])
    fwd = lambda p: p.replace("\\", "/")
    cmd = [gp.GODOT, "--path", GODOT_PROJECT, "--resolution", "1280x720", "--script", fwd(SCRIPT), "--",
           "--glb", fwd(GLB), "--out", fwd(out), "--views", arg]
    with gp.GodotLock():
        p = subprocess.run(cmd, cwd=GODOT_PROJECT, capture_output=True, text=True, timeout=600, encoding="utf-8", errors="replace")
    for line in ((p.stdout or "") + (p.stderr or "")).splitlines():
        if "[city_shot]" in line or "[shot]" in line or "ERROR" in line:
            print(line)
    if not os.path.exists(out):
        raise SystemExit(f"[godot_shot] no image written (exit {p.returncode})")
    print("[godot_shot] wrote", out)


if __name__ == "__main__":
    main()
