"""Run the game from the command line: import its art, take a screenshot, or play.

    python tools/shot.py --import                       # import new art, no window
    python tools/shot.py out.png [--cam=wide] [--char=a] [--at=x,z] [--no-ceiling] [--no-actor]
    python tools/shot.py --play                         # open the game

A screenshot needs a real window (the headless driver draws nothing), so one opens
briefly. Fails if Godot prints an ERROR line or the PNG is not written.

Godot is found the way PLAY.cmd finds it: GODOT_EXE, then godot_path.txt in the
project folder, then a Godot*.exe there, then godot or godot4 on the PATH.

Windows open on monitor 2 (Windows' \\\\.\\DISPLAY2) when there is one, so they do
not pop up over whatever is on the main screen. Set POPUP_MONITOR to another
display number, or to 0 to let Godot choose.

When this folder sits inside the full Tattletale working folder (next to its
godot/ folder), runs wait for that project's one-Godot-at-a-time lock.
"""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
POPUP = os.path.dirname(HERE)
SHARED = os.path.join(os.path.dirname(POPUP), "godot", "tools")


def find_godot():
    """The Godot to run. Where there is a console build beside it (Windows), that one, so its output can be read."""
    named = os.environ.get("GODOT_EXE", "").strip()
    note = os.path.join(POPUP, "godot_path.txt")
    if not named and os.path.isfile(note):
        with open(note, encoding="utf-8") as f:
            named = f.readline().strip().strip('"')
    found = shutil.which(named) if named else None
    if named and not found:
        raise SystemExit("Godot was not found at: " + named)
    if not found:
        here = sorted(glob.glob(os.path.join(POPUP, "Godot*.exe")))
        found = here[0] if here else (shutil.which("godot") or shutil.which("godot4"))
    if not found:
        raise SystemExit("Godot 4.7 or newer was not found: set GODOT_EXE, write its path in godot_path.txt, or put it on the PATH")
    stem, ext = os.path.splitext(found)
    console = stem + "_console" + ext
    return console if ext.lower() == ".exe" and os.path.isfile(console) else found


class NoLock:
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


if os.path.isfile(os.path.join(SHARED, "godot_preview.py")):
    sys.path.insert(0, SHARED)
    from godot_preview import GodotLock, GODOT  # noqa: E402
else:
    GodotLock, GODOT = NoLock, find_godot()

SIZE = (1600, 900)


def window_place():
    """Godot arguments that put the window in the middle of the chosen monitor, or [] to let Godot choose."""
    want = os.environ.get("POPUP_MONITOR", "2")
    if want == "0" or os.name != "nt":
        return []
    import ctypes
    from ctypes import wintypes

    class Info(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("rcMonitor", wintypes.RECT), ("rcWork", wintypes.RECT),
                    ("dwFlags", wintypes.DWORD), ("szDevice", wintypes.WCHAR * 32)]

    found = {}

    def each(handle, _dc, _rect, _data):
        info = Info()
        info.cbSize = ctypes.sizeof(Info)
        if ctypes.windll.user32.GetMonitorInfoW(handle, ctypes.byref(info)):
            found[info.szDevice] = info.rcWork
        return 1

    proc = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HMONITOR, wintypes.HDC, ctypes.POINTER(wintypes.RECT), wintypes.LPARAM)
    ctypes.windll.user32.EnumDisplayMonitors(None, None, proc(each), 0)
    area = found.get("\\\\.\\DISPLAY" + want)
    if area is None:
        return []
    x = area.left + max((area.right - area.left - SIZE[0]) // 2, 0)
    y = area.top + max((area.bottom - area.top - SIZE[1]) // 2, 0)
    return ["--position", "%d,%d" % (x, y)]


def run(cmd, timeout):
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if l.strip()]
    errors = [l for l in lines if l.lstrip().startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:", "Parse Error"))]
    for i, l in enumerate(lines):
        if l in errors or "WARNING:" in l or "[shot]" in l or (i and lines[i - 1] in errors):
            print(l)
    return p.returncode, bool(errors)


def main():
    args = sys.argv[1:]
    with GodotLock():
        if args and args[0] == "--import":
            code, bad = run([GODOT, "--headless", "--path", POPUP, "--import"], 600)
            raise SystemExit(1 if bad else 0)
        if args and args[0] == "--play":
            raise SystemExit(subprocess.call([GODOT, "--path", POPUP] + window_place()))
        out = os.path.abspath(args[0]).replace("\\", "/")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if os.path.exists(out):
            os.remove(out)
        code, bad = run([GODOT, "--path", POPUP, "--resolution", "%dx%d" % SIZE] + window_place()
                        + ["--", "--shot=" + out] + args[1:], 180)
        if bad or not os.path.exists(out):
            raise SystemExit(f"shot failed (exit {code}, errors {bad}, written {os.path.exists(out)})")


if __name__ == "__main__":
    main()
