"""Builds the ordinary cast: Timmy, his mama, 2-Pack's daddy, the ice-cream vendor, the four people in line, the baby."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
from lib import person as P

# Colors and options straight from the JS (state.js, world.js); the rest is per-character sculpting.
CAST = {
    # state.js 16: little Timmy runs the lemonade stand
    "timmy": dict(h=0.95, skin="#8a5a3c", top="#2a8a3a", pants="#f2c21a", shoes="#c4162a", hair="#3a2414", style="short",
                  eye_size=1.06, pupil=1.12, lid=0.08, smile=1.0, nose="button", cheeks=1.15, cowlick=True,
                  brow=dict(raise_=0.004, arch=1.4, thick=0.9), hair_volume=1.15, pocket=True),
    # state.js 31: Timmy's mama
    "mama": dict(h=1.68, skin="#8a5a3c", top="#e84a9a", pants="#2a2a30", shoes="#f4f0e6", hair="#141010", style="bun",
                 collar="scoop", bust=0.65, lid=0.24, lid_tilt=0.12, lashes=True, lips="#a8384e", smile=0.6,
                 brow=dict(arch=1.8, thick=0.75, raise_=0.002), nose="button", bun_tie="#f2c230"),
    # world.js 162: 2-Pack's daddy, asleep in his hammock: undershirt, big belly, mustache
    "dad": dict(h=1.8, skin="#8a5a3c", top="#f4f0e6", pants="#4a4a5a", shoes="#2a2a2a", style="bald", belly=1.4,
                mustache=True, hair="#141010", collar="tank", rib=True, lid=0.46, lid_tilt=-0.18, nose="broad", nose_size=1.1,
                brow=dict(thick=1.45, tilt=-0.4, raise_=-0.002), mouth_shape="o", cheeks=1.1, chin=1.15),
    # world.js 185-186: the ice-cream vendor and his paper hat
    "vendor": dict(h=1.78, skin="#c48e64", top="#f4f0e6", pants="#3a3a40", hair="#141010", style="short", hair_flow="back",
                   collar="button", tuck=True, belt="#2a2018", lid=0.2, smile=0.9, nose="long", mustache=False,
                   brow=dict(thick=1.15, arch=1.2)),
    # world.js 188: the four people waiting in the ice-cream line (pants #2a2a30)
    "liner_1": dict(h=1.7, skin="#e8b48a", hair="#c8642a", style="long", top="#2ad0a8", pants="#2a2a30",
                    collar="v", bust=0.5, lashes=True, lid=0.22, lid_tilt=0.08, smile=0.7, nose="button",
                    brow=dict(arch=1.6, thick=0.7), sleeves="short", lips="#b85a5a"),
    "liner_2": dict(h=1.85, skin="#5c3a26", hair="#141010", style="curls", top="#ff8a1a", pants="#2a2a30",
                    pocket=True, lid=0.18, nose="broad", smile=0.4, brow=dict(thick=1.25), chin=1.1, ear_size=1.05),
    "liner_3": dict(h=1.6, skin="#c48e64", hair="#3a2a1a", style="bob", top="#8a2ad0", pants="#2a2a30",
                    collar="polo", bust=0.45, lashes=True, lid=0.18, smile=0.8, nose="round", nose_size=0.9,
                    brow=dict(arch=1.5, thick=0.75), glasses=False),
    "liner_4": dict(h=1.78, skin="#f0c8a8", hair="#e8c46a", style="short", hair_flow="side", top="#2a6ac8", pants="#2a2a30",
                    collar="crew", sleeves="short", lid=0.26, nose="long", smile=0.3, brow=dict(thick=1.0, tilt=0.3),
                    hair_volume=1.2),
    # world.js 191: the baby (white onesie over a diaper, bare feet, a little tuft); she crawls
    "baby": dict(h=0.55, skin="#f0c8a8", top="#f8f4ee", pants="#f8f4ee", shoes="#f0c8a8", hair="#e8c46a", style="tuft",
                 diaper=True, collar="crew", eye_size=1.12, pupil=1.2, lid=0.04, lid_low=0.05, nose="button", nose_size=0.85,
                 cheeks=1.3, smile=0.8, brow=dict(thick=0.55, raise_=0.004), ear_size=1.1, soft=True),
}


def extras(cid, r):
    """Per-character pieces on top of the builder."""
    if cid == "vendor":
        P.paper_hat(r)                       # world.js 186: white paper hat, r .12 cylinder on top of the head
        P.bow_tie(r, "#c4162a")
    elif cid == "mama":
        P.earrings(r, "#f2c230")


def pose_tiles(cid, r):
    """Pose checks: the default sheet, plus the poses this character really uses in the game."""
    H = r.H
    hc = 0.47 * H + 0.36 * H + r.hy
    sheets = {cid + "_pose": P.default_tiles(r)}
    game = {
        "timmy": dict(armR=(-1.2, 0.1), armL=(-0.8, 0.1), look=0.2),
        "mama": dict(armR=(-0.35, 0.55), armL=(-0.35, 0.55), lean=-0.05, nod=-0.05),
        "dad": dict(armR=(-0.2, 0.4), armL=(-0.4, 0.6), mouth=0.9),
        "vendor": dict(armR=(-1.1, 0.1), armL=(-0.9, 0.1)),
        "baby": dict(armR=(-1.2, 0.05), armL=(-1.2, 0.05), nod=-1.0, legs=(-1.3, -1.3)),
    }.get(cid, dict(armR=(-0.9, 0.45), armL=(-0.9, 0.45), nod=-0.1))
    t2 = [dict(pose=game, eye=(1.4 * H, 0.75 * H, 2.2 * H), look=(0, 0.5 * H, 0), lens=50),
          dict(pose=P.POSES["talk"], eye=(0.3 * H, hc, 0.8 * H), look=(0, hc - 0.03 * H, 0), lens=55),
          dict(pose=P.POSES["run"], eye=(2.4 * H, 0.6 * H, 0.6 * H), look=(0, 0.5 * H, 0), lens=50),
          dict(pose=P.POSES["binoculars"], eye=(0, hc + 0.1 * H, 1.3 * H), look=(0, hc - 0.05 * H, 0), lens=50)]
    if cid == "baby":   # the crawl: the game tilts her forward 1.15 rad and lifts her 0.12
        crawl = dict(armR=(-1.2, 0.05), armL=(-1.2, 0.05), nod=-1.0, legs=(-1.3, -1.3))
        t2[0] = dict(pose=crawl, rig_rot=(1.15, 0, 0), rig_pos=(0, 0.12, 0), eye=(1.6 * H, 0.9 * H, 1.6 * H), look=(0, 0.35 * H, 0), lens=45)
        t2[2] = dict(pose=crawl, rig_rot=(1.15, 0, 0), rig_pos=(0, 0.12, 0), eye=(2.2 * H, 0.5 * H, 0.0), look=(0, 0.35 * H, 0), lens=45)
    if cid == "dad":    # in the hammock: the game lays him on his back (outer yaw, inner x -90 deg)
        t2[2] = dict(pose=game, rig_rot=(-1.5708, 0, 0), rig_pos=(0, 1.02, 0), eye=(1.2, 2.2, 2.6), look=(0, 0.95, -0.9), lens=40)
    sheets[cid + "_pose2"] = t2
    return sheets


def build(cid):
    ck.reset()
    r = P.make_person(**CAST[cid])
    extras(cid, r)
    P.export_character(cid)
    P.binocular_check(r)
    ck.preview(cid)
    for sid, tiles in pose_tiles(cid, r).items():
        P.pose_sheet(r, sid, tiles)


if __name__ == "__main__":
    ids = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(CAST)
    for cid in ids:
        build(cid)
