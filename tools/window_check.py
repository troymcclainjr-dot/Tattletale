"""Check that a screenshot run stays out of the way (Windows only).

    python tools/window_check.py out.png [shot.py options]

Runs one tools/shot.py picture and reports, from Windows itself: how many times
the foreground window changed (0 means it never took the keyboard) and where
every new window appeared (class "Engine" is the game; its x must be inside
the monitor shot.py aims at, and there should be no other new window).
Godot's own idea of its window position is counted from the corner of the whole
desktop, so it is not proof: this is.
"""
import ctypes
import ctypes.wintypes
import os
import subprocess
import sys
import time

u = ctypes.windll.user32
ctypes.windll.shcore.SetProcessDpiAwareness(2)


def fg():
    return u.GetForegroundWindow()


def all_windows():
    out = []

    def cb(h, l):
        if u.IsWindowVisible(h):
            c = ctypes.create_unicode_buffer(100)
            u.GetClassNameW(h, c, 100)
            r = ctypes.wintypes.RECT()
            u.GetWindowRect(h, ctypes.byref(r))
            out.append((h, c.value, r.left, r.top, r.right - r.left, r.bottom - r.top))
        return True

    u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
    return out


before = {w[0] for w in all_windows()}
start = fg()
p = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "shot.py")] + sys.argv[1:],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
changes = 0
last = start
seen = {}
while p.poll() is None:
    f = fg()
    if f != last:
        last = f
        if f != start:
            changes += 1
    for w in all_windows():
        if w[0] not in before:
            seen.setdefault(w[0], []).append(w[1:])
    time.sleep(0.02)
for line in p.stdout.read().splitlines():
    if "window at" in line:
        print(line[-60:])
print("foreground left the starting window:", changes, "times")
for spots in seen.values():
    places = []
    for s in spots:
        if not places or places[-1] != s:
            places.append(s)
    print("new window:", places)
