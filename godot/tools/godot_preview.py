"""Render a model/scene in Godot with the game's clay materials and lighting.

    python godot/tools/godot_preview.py res://assets/models/payphone.glb .work/previews/payphone_godot.png
    python godot/tools/godot_preview.py res://assets/models/street.glb out.png --eye 10,6,20 --look 6,0,0 --fov 50

Imports any new/changed assets first. Several agents share this Godot project, so all
Godot runs go through one lock (.work/godot.lock, a directory). Also usable as
    python godot/tools/godot_preview.py --import-only
"""
import os, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GODOT_DIR = os.path.join(ROOT, "godot")
GODOT = r"C:\files\Godot\Godot_v4.7.2-stable_win64_console.exe"
LOCK = os.path.join(ROOT, ".work", "godot.lock")
STALE = 15 * 60


class GodotLock:
    def __enter__(self):
        os.makedirs(os.path.dirname(LOCK), exist_ok=True)
        t0 = time.time()
        while True:
            try:
                os.mkdir(LOCK)
                with open(os.path.join(LOCK, "owner.txt"), "w") as f:
                    f.write(f"pid {os.getpid()} at {time.ctime()}\n")
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(LOCK) > STALE:
                        print("[godot_preview] breaking stale lock")
                        for n in os.listdir(LOCK):
                            os.remove(os.path.join(LOCK, n))
                        os.rmdir(LOCK)
                        continue
                except FileNotFoundError:
                    continue
                if time.time() - t0 > 30 * 60:
                    raise SystemExit("[godot_preview] gave up waiting for the Godot lock")
                time.sleep(2)

    def __exit__(self, *a):
        try:
            for n in os.listdir(LOCK):
                os.remove(os.path.join(LOCK, n))
            os.rmdir(LOCK)
        except FileNotFoundError:
            pass


def run(cmd, timeout):
    p = subprocess.run(cmd, cwd=GODOT_DIR, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    noise = ("Godot Engine v", "Vulkan", "OpenGL API", "WARNING: Blend file import is enabled", "   at:")
    lines = [l for l in out.splitlines() if l.strip() and not l.startswith(noise)]
    return p.returncode, lines


def godot_import():
    code, lines = run([GODOT, "--headless", "--path", GODOT_DIR, "--import"], 900)
    errs = [l for l in lines if "ERROR" in l or "SCRIPT ERROR" in l or "Parse Error" in l]
    for l in errs[:40]:
        print("[import]", l)
    return code


def main():
    a = sys.argv[1:]
    with GodotLock():
        godot_import()
        if "--import-only" in a:
            return
        scene, out = a[0], os.path.abspath(a[1])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        extra = a[2:]
        res = "960x720" if "--eye" not in extra else "1280x720"
        cmd = [GODOT, "--path", GODOT_DIR, "--resolution", res, "--script", "res://tools/shot.gd", "--",
               "--scene", scene, "--out", out.replace("\\", "/")] + extra
        code, lines = run(cmd, 300)
        for l in lines:
            if "[shot]" in l or "ERROR" in l or "error" in l.lower():
                print(l)
        if not os.path.exists(out):
            raise SystemExit(f"[godot_preview] no image written (exit {code})")
        print("[godot_preview] wrote", out)


if __name__ == "__main__":
    main()
