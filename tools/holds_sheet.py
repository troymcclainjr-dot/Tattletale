"""Pictures of every way a thing is held, for judging the holds (see --lineup in scripts/main.gd).

    python tools/holds_sheet.py <folder> [rig] [weapon ...]

Writes one PNG for each pair of poses of each weapon into the folder.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SETS = {
    "pistol": ["sc+sa", "sam+scw", "fc+bc", "fa+fcw", "scr+bcw"],
    "uzi": ["sc+sa", "sam+scw", "fc+bc", "fa+fcw", "scr+bcw"],
    "ak": ["sc+sa", "sam+scw", "fc+bc", "scr+fcw", "saw+bcw"],
}


# Someone with only a front drawing: what there is to see.
FRONT_ONLY = {"pistol": ["fc+fa", "fcw+fa"], "uzi": ["fc+fa"], "ak": ["fc+fcw"]}


def main():
    out = os.path.abspath(sys.argv[1])
    rig = sys.argv[2] if len(sys.argv) > 2 else "e"
    names = sys.argv[3:] or list(SETS)
    sets = SETS if os.path.exists(os.path.join(os.path.dirname(HERE), "assets", "characters", rig, "side.png")) else FRONT_ONLY
    os.makedirs(out, exist_ok=True)
    for name in names:
        for poses in sets[name]:
            path = os.path.join(out, "%s_%s_%s.png" % (rig, name, poses.replace("+", "_")))
            r = subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), path, "--lineup=%s:%s:%s" % (name, rig, poses)],
                               capture_output=True, text=True)
            bad = [l for l in (r.stdout + r.stderr).splitlines() if "ERROR" in l and "plans/" not in l and "props_" not in l]
            print(os.path.basename(path), "ok" if os.path.exists(path) else "FAILED", *bad[:3])


if __name__ == "__main__":
    main()
