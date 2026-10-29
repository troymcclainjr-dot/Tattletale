"""Run Godot on this project while holding the shared lock (several agents share it).

    python godot/tools/godot_run.py --import                      # import new/changed assets only
    python godot/tools/godot_run.py --import -- --headless --quit-after 600
    python godot/tools/godot_run.py -- --headless --script res://tests/smoke.gd
    python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 --script res://tools/game_shot.gd -- --out C:/x.png

Everything after the first "--" goes to Godot (which gets --path godot automatically).
Use --import whenever models or other assets changed since the last run.
Exit code is Godot's. Output is printed, minus engine banner noise.
"""
import os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from godot_preview import GodotLock, godot_import, GODOT, GODOT_DIR  # noqa: E402


def main():
    a = sys.argv[1:]
    godot_args = []
    if "--" in a:
        i = a.index("--")
        a, godot_args = a[:i], a[i + 1:]
    timeout = 600
    if "--timeout" in a:
        timeout = int(a[a.index("--timeout") + 1])
    with GodotLock():
        if "--import" in a:
            godot_import()
        if not godot_args:
            return 0
        p = subprocess.run([GODOT, "--path", GODOT_DIR] + godot_args, cwd=GODOT_DIR, capture_output=True, text=True,
                           timeout=timeout, encoding="utf-8", errors="replace")
        noise = ("Godot Engine v", "Vulkan ", "OpenGL API")
        for line in ((p.stdout or "") + (p.stderr or "")).splitlines():
            if line.strip() and not line.startswith(noise):
                print(line)
        return p.returncode


if __name__ == "__main__":
    sys.exit(main() or 0)
