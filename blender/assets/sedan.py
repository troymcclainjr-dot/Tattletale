"""Sedan: 2-Pack's mama's boxy, slightly beat-up pink 80s family car with the roof pom (local asset, faces +x)."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math, random
import bpy
import claykit as ck
import car_kit as kit

ck.reset()
random.seed(17)

PINK = ck.gloss("pink", 0.3)               # JS clay("#e84a9a", .3)
GLASS = ck.gloss("#1a2230", 0.1)           # JS windows
UNDER = ck.clay("#1a1a1c", 0.9)
TIRE = ck.clay("#121214", 0.5)             # JS wheels
STEEL = ck.clay("#3a3a3e", 0.75)           # bare wheel where the hubcap fell off
CHROME = ck.gloss("alu", 0.25)             # chrome: metal_ renders as dark gunmetal under the game's flat sky
RUBBER = ck.clay("#26262a", 0.85)
WHITEWALL = ck.clay("#f4f0e6", 0.6)
GRILLE = ck.clay("#0e0e10", 0.8)
AMBER = ck.gloss("#f2a030", 0.3)
PLATE = ck.clay("#f4f4ee", 0.6)            # JS plate backing
PLATE_RIM = ck.clay("navy", 0.6)           # JS plate ink #14203f
POM = ck.clay("pink", 0.6)                 # JS clay("#e84a9a", .6)
RUST = ck.clay("#8a5a3a", 0.95)
HEAD = ck.glow("#fff6c8", 1.0)             # JS headlights
TAIL = ck.glow("#ff2a2a", 1.2)             # JS taillights

root = ck.empty("Sedan")
parts = []

# ---------------------------------------------------------------- body shell (JS box 4.2 x 0.85 x 1.85 at y 0.72)
DENT = (-0.5, 1.0, -0.93)                  # dents sit on the driver's-side shoulder (the side the player sees) so the
DING = (1.66, 1.06, -0.93)                 # top catches the light; that side is always in shade
B = kit.P(x_nose=2.09, x_tail=-2.09, yb_base=0.30, wheel_x=(-1.35, 1.35), wheel_y=0.36, arch_r=0.43,
          rb=0.05, rt=0.07, step=0.19, front=(0.08, 0.06, 0.06, 0.04), rear=(0.07, 0.05, 0.05, 0.04),
          tuck_y=0.48, tuck_k=1.0, extra_x=[DENT[0] + 0.05 * k for k in range(-4, 5)] + [DING[0] + 0.05 * k for k in range(-2, 3)])
B.hw = lambda x: 0.925 - 0.02 * max(0.0, (abs(x) - 1.6) / 0.49) ** 2
B.yt = lambda x: (1.145 - 0.035 * min(1.0, (x - 1.15) / 0.94) ** 1.5 if x > 1.15 else
                  1.145 - 0.012 * min(1.0, (-1.5 - x) / 0.59) if x < -1.5 else 1.145)
B.yb_extra = lambda x: 0.0
B.crown = lambda x: 0.012 * min(1.0, max(0.0, (x - 1.0) / 0.25)) + 0.008 * min(1.0, max(0.0, (-1.4 - x) / 0.25))
B.side_fracs = kit.side_fracs(B, (0.44, 0.6, 0.76, 0.9, 0.98, 1.04), 1.145)
SEAMS = [(0.87, "side", 0.008), (-0.12, "side", 0.008), (-0.88, "side", 0.008),   # doors
         (1.13, "top", 0.006), (-1.58, "top", 0.006)]                              # hood, trunk lid
body = kit.body_loft("Body", B, [PINK, UNDER], lambda xm, a, b: 1 if "bot" in (a[2], b[2]) else 0, SEAMS)
kit.push(body, DENT, 0.21, (0, -0.016, 0.03))
kit.push(body, DING, 0.14, (0, -0.014, 0.018))
parts.append(body)
parts.append(ck.box(3.8, 0.78, 1.36, (0, 0.61, 0), UNDER, name="Chassis"))

# ---------------------------------------------------------------- cabin (JS 2.3 x 0.7 x 1.7 at (-0.2, 1.45)): upright 80s glass
C = kit.P(ys=(1.07, 1.145, 1.3, 1.45, 1.6), y_roof=1.8, r_roof=0.06, rc=0.07, crown=0.01)
KF, KB, KS = 0.43 / 0.655, 0.29 / 0.655, 0.07 / 0.655
C.xf = lambda y: 1.05 - (y - 1.145) * KF
C.xb = lambda y: -1.42 + (y - 1.145) * KB
C.hw = lambda y: 0.85 - (y - 1.145) * KS
parts.append(kit.cabin_loft("Cabin", C, [PINK]))


def glazed(nm, pts, to3d, n, r=0.04):
    """Glass with a chrome surround (the trim is the same outline grown 2.2 cm, set behind the glass)."""
    parts.append(kit.surface_slab(nm + "Trim", kit.rounded_poly(kit.offset_poly(pts, 0.022), r + 0.02), to3d, n, CHROME, 0.004, -0.004))
    parts.append(kit.surface_slab(nm, kit.rounded_poly(pts, r), to3d, n, GLASS, 0.0075, -0.003))


wz = lambda y: C.hw(y) - C.rc - 0.045
glazed("Windshield", [(-wz(1.24), 1.24), (wz(1.24), 1.24), (wz(1.7), 1.7), (-wz(1.7), 1.7)],
       lambda u, v: (C.xf(v), v, u), (1, KF, 0))
glazed("RearWindow", [(-wz(1.25), 1.25), (wz(1.25), 1.25), (wz(1.7), 1.7), (-wz(1.7), 1.7)],
       lambda u, v: (C.xb(v), v, u), (-1, KB, 0))
y_lo, y_hi = 1.27, 1.715                   # JS side windows 0.95 x 0.48 at x -0.75 / 0.4, y 1.5
front_win = [(-0.075, y_lo), (min(0.875, C.xf(y_lo) - C.rc - 0.045), y_lo), (C.xf(y_hi) - C.rc - 0.045, y_hi), (-0.075, y_hi)]
rear_win = [(max(-1.225, C.xb(y_lo) + C.rc + 0.045), y_lo), (-0.275, y_lo), (-0.275, y_hi), (C.xb(y_hi) + C.rc + 0.045, y_hi)]
for s in (-1, 1):
    for nm, pts in (("Front", front_win), ("Rear", rear_win)):
        glazed(f"Window{nm}{'L' if s < 0 else 'R'}", pts, lambda u, v, s=s: (u, v, s * C.hw(v)), (0, KS, s))

# ---------------------------------------------------------------- sides: moldings, handles, mirrors, rust
mold = kit.rr_profile(0.016, 0.045, 0.007, 1)
for s in (-1, 1):
    path = [(x, 0.74, s * 0.925) for x in ((-0.84, 0.84) if s < 0 else (0.84, -0.84))]
    parts.append(kit.sweep("Molding", path, mold, RUBBER))
    path = [(x, 0.74, s * 0.925) for x in ((-0.83, 0.83) if s < 0 else (0.83, -0.83))]
    parts.append(kit.sweep("MoldingChrome", path, kit.rr_profile(0.006, 0.01, 0.0025, 1, 0.01), CHROME))
    for hx in (0.12, -0.74):
        parts.append(ck.box(0.16, 0.032, 0.024, (hx, 0.99, s * 0.929), CHROME, name="Handle", bevel=0.009, bevel_segs=1))
    tw = random.uniform(-0.07, 0.07)
    parts.append(ck.box(0.05, 0.03, 0.09, (0.82, 1.17, s * 0.87), CHROME, name="MirrorArm", bevel=0.01, bevel_segs=1))
    parts.append(ck.box(0.09, 0.1, 0.13, (0.82, 1.22, s * 0.925), CHROME, rot=(0, tw, 0), name="Mirror", bevel=0.035, bevel_segs=2))
    parts.append(ck.box(0.008, 0.075, 0.1, (0.774, 1.22, s * 0.925), ck.metal("alu", 0.12), rot=(0, tw, 0), name="MirrorGlass", bevel=0.003, bevel_segs=1))
for (x, y, r) in ((-1.84, 0.47, 0.034), (-1.9, 0.56, 0.022), (-1.815, 0.42, 0.018)):  # rust by the rear arch
    parts.append(ck.sph(r, (x, y, -0.917), RUST, scale=(1, 0.8, 0.22), name="Rust", segs=8, rings=5))

# ---------------------------------------------------------------- nose: grille, headlights, signals, bumper, ornament
XN = B.x_nose
parts.append(ck.box(0.03, 0.24, 0.78, (XN + 0.002, 0.81, 0), GRILLE, name="Grille", bevel=0.01, bevel_segs=1))
for y in (0.685, 0.935):
    parts.append(ck.box(0.028, 0.03, 0.84, (XN + 0.018, y, 0), CHROME, name="GrilleFrame", bevel=0.012, bevel_segs=1))
for z in (-0.41, 0.41):
    parts.append(ck.box(0.028, 0.28, 0.03, (XN + 0.018, 0.81, z), CHROME, name="GrilleFrame", bevel=0.012, bevel_segs=1))
for y in (0.745, 0.79, 0.835, 0.88):
    parts.append(ck.box(0.016, 0.016, 0.8, (XN + 0.016, y, 0), CHROME, name="GrilleBar", bevel=0.006, bevel_segs=1))
lenses = []
for s in (-1, 1):
    parts.append(ck.box(0.03, 0.21, 0.36, (XN + 0.006, 0.8, s * 0.6), CHROME, name="HeadBezel", bevel=0.012, bevel_segs=2))
    lenses.append(ck.box(0.03, 0.16, 0.3, (XN + 0.016, 0.8, s * 0.6), HEAD, name="Headlights", bevel=0.012, bevel_segs=2))
    parts.append(ck.box(0.02, 0.06, 0.26, (XN + 0.003, 0.625, s * 0.6), AMBER, name="Signal", bevel=0.01, bevel_segs=1))
heads = ck.join(lenses, "Headlights")
kit.set_origin(heads, (XN + 0.03, 0.8, 0))
bump_prof = kit.rr_profile(0.13, 0.19, 0.045, 2)
strip_prof = kit.rr_profile(0.03, 0.05, 0.012, 1, 0.06)
bf = kit.sweep("BumperF", kit.u_path(2.122, 0.875, 0.16, 1.86, 0.4), bump_prof, CHROME)
bfs = kit.sweep("BumperFStrip", kit.u_path(2.122, 0.875, 0.16, 1.86, 0.4), strip_prof, RUBBER)
for o in (bf, bfs):                                                     # the bent corner
    kit.push(o, (2.12, 0.4, -0.8), 0.24, (-0.028, -0.012, 0.01))
parts += [bf, bfs]
parts.append(ck.cyl(0.022, 0.024, 0.016, (1.99, 1.13, 0), CHROME, name="OrnamentBase", segs=10))
parts.append(ck.tor(0.03, 0.0065, (1.99, 1.17, 0), CHROME, name="Ornament", major_segs=12, minor_segs=5))

# ---------------------------------------------------------------- tail: lights, plate, bumper, exhaust
XT = B.x_tail
tails = []
for s in (-1, 1):
    parts.append(ck.box(0.03, 0.19, 0.36, (XT - 0.006, 0.8, s * 0.6), CHROME, name="TailBezel", bevel=0.012, bevel_segs=2))
    tails.append(ck.box(0.03, 0.14, 0.3, (XT - 0.016, 0.8, s * 0.6), TAIL, name="Taillights", bevel=0.01, bevel_segs=2))
tails = ck.join(tails, "Taillights")
kit.set_origin(tails, (XT - 0.03, 0.8, 0))
parts.append(ck.cyl(0.03, 0.03, 0.03, (XT - 0.004, 0.93, 0), CHROME, rot=(0, 0, math.pi / 2), name="TrunkLock", segs=10))
# plate: JS 0.62 x 0.24 at (-2.12, 0.62, 0) facing -x. Chrome frame, cream backing, embossed navy rim, no digits.
PX = -2.115
plate_to3d = lambda u, v: (XT, 0.62 + v, -u)                          # u runs +z -> -z seen from behind
parts.append(kit.surface_slab("PlateFrame", kit.rounded_poly([(-0.345, -0.15), (0.345, -0.15), (0.345, 0.15), (-0.345, 0.15)], 0.03),
                              plate_to3d, (-1, 0, 0), CHROME, XT - (PX + 0.008), -0.01))
parts.append(kit.surface_slab("PlateBack", kit.rounded_poly([(-0.31, -0.12), (0.31, -0.12), (0.31, 0.12), (-0.31, 0.12)], 0.02),
                              plate_to3d, (-1, 0, 0), PLATE, XT - PX, -0.01))
for (u, v, w, h) in ((0, 0.1, 0.58, 0.012), (0, -0.1, 0.58, 0.012), (0.29, 0, 0.012, 0.212), (-0.29, 0, 0.012, 0.212)):
    parts.append(ck.box(0.006, h, w, (PX - 0.002, 0.62 + v, u), PLATE_RIM, name="PlateRim"))
plate = ck.empty("Plate", (PX - 0.01, 0.62, 0), rot=(0, -math.pi / 2, 0), parent=root)   # 1 cm behind the face, +z -> -x
br = kit.sweep("BumperR", kit.u_path(2.122, 0.875, 0.16, 1.86, 0.39, rear=True), kit.rr_profile(0.13, 0.18, 0.045, 2), CHROME)
brs = kit.sweep("BumperRStrip", kit.u_path(2.122, 0.875, 0.16, 1.86, 0.39, rear=True), strip_prof, RUBBER)
for o in (br, brs):                                                     # knocked a little askew
    kit.tilt(o, (-2.13, 0.39, 0), (0.035, 0, 0))
parts += [br, brs]
parts.append(ck.cyl(0.034, 0.03, 0.2, (-2.07, 0.25, -0.5), STEEL, rot=(0, 0, math.pi / 2), name="Exhaust", segs=12))
parts.append(ck.cyl(0.021, 0.021, 0.01, (-2.17, 0.25, -0.5), ck.clay("#0a0a0c", 0.9), rot=(0, 0, math.pi / 2), name="ExhaustHole", segs=12))

# ---------------------------------------------------------------- the pom (JS sphere r 0.12 at (0.3, 1.95, -0.3), "it's her car")
parts.append(ck.cyl(0.011, 0.013, 0.1, (0.3, 1.85, -0.3), CHROME, name="PomStem", segs=8))
pom = kit.fuzzy_ball("Pom", 0.12, POM, seed=4, subdiv=4, fuzz=0.22)
kit.place(pom, (0.3, 1.95, -0.3))

# ---------------------------------------------------------------- wheels (JS r 0.36 at (+-1.35, 0.36, +-0.88)): whitewalls, chrome covers
OUT = [(0.315, 0.149, "tire"), (0.305, 0.151, "white"), (0.268, 0.151, "white"), (0.256, 0.148, "tire"), (0.243, 0.145, "tire")]
COVER = kit.TIRE_PROFILE + OUT + [(0.236, 0.143, "chrome"), (0.226, 0.152, "chrome"), (0.19, 0.144, "chrome"), (0.12, 0.137, "chrome"),
                                  (0.08, 0.147, "chrome"), (0.062, 0.16, "chrome"), (0.0, 0.164, "chrome")]
BARE = kit.TIRE_PROFILE + OUT + [(0.236, 0.14, "steel"), (0.222, 0.12, "steel"), (0.17, 0.104, "steel"), (0.09, 0.104, "steel"),
                                 (0.06, 0.118, "steel"), (0.0, 0.122, "steel")]


def ribs(k, j, r, z):
    r, z = kit.tread(k, j, r, z)
    if j in (19, 20):                      # turbine ribs pressed into the wheel cover
        z += 0.006 if k % 2 else -0.004
    return r, z


WMATS = {"steel": STEEL, "tire": TIRE, "white": WHITEWALL, "chrome": CHROME}
for nm, x, z in (("WheelFL", 1.35, -0.88), ("WheelFR", 1.35, 0.88), ("WheelRL", -1.35, -0.88), ("WheelRR", -1.35, 0.88)):
    piv = ck.empty(nm, (x, 0.36, z), parent=root)
    bare = nm == "WheelRL"                 # this one lost its hubcap years ago
    w = kit.lathe(nm + "_Tire", BARE if bare else COVER, 22, WMATS, mirror=z < 0, perturb=kit.tread if bare else ribs)
    kit.attach(w, piv)
    if bare:
        nuts = []
        for k in range(5):
            a = 2 * math.pi * k / 5 + 0.3
            nuts.append(ck.cyl(0.016, 0.016, 0.026, (0.075 * math.cos(a), 0.075 * math.sin(a), -0.112), ck.clay("#2a2a2e", 0.7),
                               rot=(math.pi / 2, 0, 0), parent=piv, name="LugNut", segs=6))
        ck.join([w] + nuts, w.name)

# ---------------------------------------------------------------- assemble
THIN = ("GrilleBar", "GrilleFrame", "Exhaust", "ExhaustHole", "PomStem", "Ornament", "OrnamentBase", "PlateRim", "MoldingChrome", "Rust")
kit.lumpy_world([o for o in parts if not o.name.startswith(THIN)], 0.0032, 2.2, seed=6)
kit.tri_report(parts + [heads, tails, pom] + [o for o in root.children_recursive if o.type == "MESH"])
body = ck.join(parts, "Body")
for o in (body, heads, tails, pom):
    ck.set_parent(o, root)
kit.report("Sedan")
bpy.context.view_layer.update()
mw = plate.matrix_world
zl = mw.to_3x3() @ ck.G(0, 0, 1)
print(f"[contract] Plate local +z in game coords = ({zl.x:.3f}, {zl.z:.3f}, {-zl.y:.3f})")
ck.export("sedan")
ck.preview("sedan")
ck.preview("sedan_close", views=[
    {"eye": (4.6, 2.9, 5.0), "look": (0.2, 0.8, 0), "lens": 35},
    {"eye": (-4.9, 2.4, -4.4), "look": (-0.2, 0.8, 0), "lens": 35},
    {"eye": (3.7, 1.35, -2.3), "look": (1.6, 0.85, -0.35), "lens": 35},
    {"eye": (-3.4, 1.2, 1.4), "look": (-2.0, 0.7, 0.0), "lens": 35}])
