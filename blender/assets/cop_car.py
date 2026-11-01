"""Cop car: black-and-white cruiser, POLICE on both doors, light bar, push bar (local asset, faces +x)."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math, random
import claykit as ck
import car_kit as kit

ck.reset()
random.seed(9)

BLACK = ck.gloss("#141418", 0.35)          # JS body
WHITE = ck.gloss("#f4f2ee", 0.35)          # JS door band + cabin
GLASS = ck.gloss("#26353e", 0.34)          # opaque, subdued neighborhood glass
UNDER = ck.clay("#1a1a1c", 0.9)
TIRE = ck.clay("#121214", 0.5)             # JS wheels
STEEL = ck.clay("#2a2a2e", 0.6)
CHROME = ck.gloss("alu", 0.25)             # chrome: metal_ renders as dark gunmetal under the game's flat sky
PUSH = ck.clay("#1c1c20", 0.6)
RUBBER = ck.clay("#2e2e32", 0.9)
GRILLE = ck.clay("#0e0e10", 0.8)
LETTER = ck.clay("#141414", 0.6)           # JS POLICE lettering
GOLD = ck.gloss("gold", 0.3)
AMBER = ck.gloss("#f2a030", 0.3)
LENS = ck.gloss("#e8ecd8", 0.1)
HEAD = ck.glow("#fff6c8", 1.0)             # JS headlights
TAIL = ck.glow("#ff2a2a", 0.8)

root = ck.empty("CopCar")
parts = []

# ---------------------------------------------------------------- body shell
# JS: box 4.4 x 0.9 x 1.9 at y 0.75 (y 0.3..1.2). Shell 2.05..-2.12 leaves room for the push bar and bumper
# inside the 4.4 m collision box. Sides are flat at the doors so the band, lettering and handles sit true.
B = kit.P(x_nose=2.05, x_tail=-2.12, yb_base=0.30, wheel_x=(-1.4, 1.4), wheel_y=0.36, arch_r=0.44,
          rb=0.06, rt=0.09, step=0.19, front=(0.14, 0.09, 0.10, 0.05), rear=(0.12, 0.10, 0.08, 0.05),
          tuck_y=0.5, tuck_k=1.2, extra_x=(-1.0, 1.2))
B.hw = lambda x: 0.95 - 0.035 * max(0.0, (abs(x) - 1.55) / 0.55) ** 2
B.yt = lambda x: (1.2 - 0.09 * min(1.0, (x - 1.2) / 0.85) ** 1.7 if x > 1.2 else
                  1.2 - 0.03 * min(1.0, (-1.55 - x) / 0.57) ** 2 if x < -1.55 else 1.2)
B.yb_extra = lambda x: 0.0
B.crown = lambda x: 0.018 * min(1.0, max(0.0, (x - 1.05) / 0.3)) + 0.012 * min(1.0, max(0.0, (-1.45 - x) / 0.3))
B.side_fracs = kit.side_fracs(B, (0.45, 0.55, 0.85, 1.05), 1.2)
BAND = (1, 3, -1.0, 1.2)                   # JS door band 2.2 x 0.5 at (0.1, 0.8): side points 0.55..1.05


def body_mat(xm, a, b):
    if a[2] == "bot" or b[2] == "bot":
        return 2
    if a[2] == b[2] == "side" and BAND[0] <= min(a[3], b[3]) and max(a[3], b[3]) <= BAND[1] and BAND[2] <= xm <= BAND[3]:
        return 1
    return 0


SEAMS = [(0.92, "side", 0.006), (-0.1, "side", 0.006), (-0.92, "side", 0.006),   # door seams
         (1.26, "top", 0.005), (-1.64, "top", 0.005)]                              # hood and trunk lid
body = kit.body_loft("Body", B, [BLACK, WHITE, UNDER], body_mat, SEAMS)
parts.append(body)
parts.append(ck.box(3.9, 0.78, 1.4, (0, 0.61, 0), UNDER, name="Chassis"))   # fills the wheel tunnels

# ---------------------------------------------------------------- cabin (JS: 2.4 x 0.75 x 1.7 at (-0.2, 1.5))
C = kit.P(ys=(1.12, 1.2, 1.34, 1.48, 1.62), y_roof=1.86, r_roof=0.08, rc=0.09, crown=0.012)
KF, KB, KS = 0.53 / 0.66, 0.44 / 0.66, 0.08 / 0.66
C.xf = lambda y: 1.15 - (y - 1.2) * KF
C.xb = lambda y: -1.52 + (y - 1.2) * KB
C.hw = lambda y: 0.85 - (y - 1.2) * KS
cabin = kit.cabin_loft("Cabin", C, [WHITE])
parts.append(cabin)

# glass: windshield (JS x 0.9), rear window, side windows (JS 1 x 0.5 at x -0.75 / 0.45, y 1.55)
wz = lambda y: C.hw(y) - C.rc - 0.035
ws = kit.rounded_poly([(-wz(1.3), 1.3), (wz(1.3), 1.3), (wz(1.755), 1.755), (-wz(1.755), 1.755)], 0.05)
parts.append(kit.surface_slab("Windshield", ws, lambda u, v: (C.xf(v), v, u), (1, KF, 0), GLASS))
rw = kit.rounded_poly([(-wz(1.31), 1.31), (wz(1.31), 1.31), (wz(1.75), 1.75), (-wz(1.75), 1.75)], 0.05)
parts.append(kit.surface_slab("RearWindow", rw, lambda u, v: (C.xb(v), v, u), (-1, KB, 0), GLASS))
y_lo, y_hi = 1.31, 1.775
front_win = [(-0.05, y_lo), (min(0.95, C.xf(y_lo) - C.rc - 0.03), y_lo), (C.xf(y_hi) - C.rc - 0.03, y_hi), (-0.05, y_hi)]
rear_win = [(max(-1.25, C.xb(y_lo) + C.rc + 0.03), y_lo), (-0.25, y_lo), (-0.25, y_hi), (C.xb(y_hi) + C.rc + 0.03, y_hi)]
for s in (-1, 1):
    for nm, pts in (("Front", front_win), ("Rear", rear_win)):
        outline = kit.rounded_poly(pts, 0.045)
        parts.append(kit.surface_slab(f"WindowSeal{nm}{s}",
                                      kit.rounded_poly(kit.offset_poly(pts, 0.014), 0.055),
                                      lambda u, v, s=s: (u, v, s * C.hw(v)), (0, KS, s), RUBBER, 0.002, -0.003))
        parts.append(kit.surface_slab(f"Window{nm}{'L' if s < 0 else 'R'}", outline,
                                      lambda u, v, s=s: (u, v, s * C.hw(v)), (0, KS, s), GLASS))

# Blackout B-pillars and a modest door molding give the working cruiser its
# own silhouette breaks without changing the collision shell or wheel mounts.
for s in (-1, 1):
    pillar = [(-0.235, 1.30), (-0.065, 1.30), (-0.065, 1.78), (-0.235, 1.78)]
    parts.append(kit.surface_slab("PillarTrim", pillar, lambda u, v, s=s: (u, v, s*C.hw(v)), (0, KS, s), RUBBER, 0.005, -0.002))
    parts.append(ck.box(1.74, 0.038, 0.016, (-0.02, 0.57, s*0.954), RUBBER, name="DoorMolding"))
parts += kit.road_details(B, C, RUBBER, BLACK)

# ---------------------------------------------------------------- doors: lettering, star, handles
for s in (-1, 1):
    t = kit.text("POLICE", 0.336, 0.014, LETTER, name="Police")          # JS sign 1.6 x 0.3 at (0.1, 0.85, +-0.98): glyphs ~0.59 x 0.185
    kit.place(t, (0.1, 0.85, s * 0.951), (0, 0 if s > 0 else math.pi, 0))
    parts.append(t)
    star = kit.surface_slab("Star", kit.star_outline(0.105, 0.045),
                            lambda u, v, s=s: (0.71 + s * u, 0.85 + v, s * 0.95), (0, 0, s), GOLD, 0.006, -0.006)
    parts.append(star)
    for hx in (0.1, -0.78):
        parts.append(ck.box(0.15, 0.03, 0.024, (hx, 1.0, s * 0.955), BLACK, name="Handle", bevel=0.009, bevel_segs=1))

# ---------------------------------------------------------------- nose: grille, headlights, signals, bumper, push bar
XN = B.x_nose
parts.append(ck.box(0.03, 0.22, 0.74, (XN + 0.004, 0.855, 0), GRILLE, name="Grille", bevel=0.01, bevel_segs=2))
for y in (0.745, 0.965):
    parts.append(ck.box(0.026, 0.026, 0.8, (XN + 0.018, y, 0), CHROME, name="GrilleFrame", bevel=0.01, bevel_segs=1))
for z in (-0.39, 0.39):
    parts.append(ck.box(0.026, 0.245, 0.026, (XN + 0.018, 0.855, z), CHROME, name="GrilleFrame", bevel=0.01, bevel_segs=1))
for y in (0.81, 0.9):
    parts.append(ck.box(0.016, 0.014, 0.76, (XN + 0.018, y, 0), CHROME, name="GrilleBar", bevel=0.005, bevel_segs=1))
parts.append(ck.box(0.016, 0.22, 0.016, (XN + 0.018, 0.855, 0), CHROME, name="GrilleBar", bevel=0.005, bevel_segs=1))
lenses = []
for s in (-1, 1):
    parts.append(ck.box(0.03, 0.23, 0.36, (XN + 0.008, 0.85, s * 0.6), CHROME, name="HeadBezel", bevel=0.014, bevel_segs=2))
    lenses.append(ck.box(0.03, 0.17, 0.29, (XN + 0.018, 0.85, s * 0.6), HEAD, name="Headlights", bevel=0.012, bevel_segs=2))
    parts.append(ck.box(0.02, 0.06, 0.2, (XN + 0.004, 0.675, s * 0.6), AMBER, name="Signal", bevel=0.01, bevel_segs=1))
heads = ck.join(lenses, "Headlights")
kit.set_origin(heads, (XN + 0.03, 0.85, 0))

bumper_prof = kit.rr_profile(0.12, 0.2, 0.045, 2)
strip_prof = kit.rr_profile(0.03, 0.05, 0.012, 1, 0.055)
parts.append(kit.sweep("BumperF", kit.u_path(2.08, 0.89, 0.22, 1.88, 0.43), bumper_prof, CHROME))
parts.append(kit.sweep("BumperFStrip", kit.u_path(2.08, 0.89, 0.22, 1.88, 0.43), strip_prof, RUBBER))
for s in (-1, 1):                                                       # push bar
    parts.append(ck.box(0.05, 0.6, 0.07, (2.164, 0.68, s * 0.3), PUSH, name="PushBar", bevel=0.018, bevel_segs=2))
    parts.append(ck.box(0.05, 0.2, 0.07, (2.112, 1.0, s * 0.3), PUSH, rot=(0, 0, 0.6), name="PushBar", bevel=0.018, bevel_segs=2))
    parts.append(ck.box(0.012, 0.42, 0.05, (2.186, 0.68, s * 0.3), RUBBER, name="PushPad", bevel=0.005, bevel_segs=1))
    parts.append(ck.box(0.08, 0.06, 0.06, (2.13, 0.44, s * 0.3), PUSH, name="PushMount", bevel=0.012, bevel_segs=1))
for y in (0.6, 0.86):
    parts.append(ck.box(0.045, 0.045, 0.66, (2.157, y, 0), PUSH, name="PushBar", bevel=0.016, bevel_segs=1))

# ---------------------------------------------------------------- tail: lights, PRECINCT 9, bumper, exhaust, antenna
XT = B.x_tail
for s in (-1, 1):
    parts.append(ck.box(0.03, 0.2, 0.34, (XT - 0.008, 0.86, s * 0.6), CHROME, name="TailBezel", bevel=0.012, bevel_segs=2))
    parts.append(ck.box(0.03, 0.15, 0.28, (XT - 0.018, 0.86, s * 0.6), TAIL, name="Taillight", bevel=0.01, bevel_segs=2))
t = kit.text("PRECINCT 9", 0.15, 0.016, ck.clay("#f4f2ee", 0.6), res=2, name="Precinct")
kit.place(t, (XT - 0.002, 0.88, 0), (0, -math.pi / 2, 0))
parts.append(t)
parts.append(kit.sweep("BumperR", kit.u_path(2.13, 0.89, 0.22, 1.9, 0.43, rear=True), bumper_prof, CHROME))
parts.append(kit.sweep("BumperRStrip", kit.u_path(2.13, 0.89, 0.22, 1.9, 0.43, rear=True), strip_prof, RUBBER))
parts.append(ck.cyl(0.035, 0.035, 0.2, (-2.085, 0.26, 0.5), STEEL, rot=(0, 0, math.pi / 2), name="Exhaust", segs=12))
parts.append(ck.cyl(0.022, 0.022, 0.01, (-2.185, 0.26, 0.5), ck.clay("#0a0a0c", 0.9), rot=(0, 0, math.pi / 2), name="ExhaustHole", segs=12))
parts.append(ck.cyl(0.022, 0.026, 0.03, (-1.86, 1.195, 0.5), PUSH, name="AntennaBase", segs=10))
whip = ck.cyl(0.005, 0.008, 0.62, (-1.86, 1.51, 0.5), PUSH, name="Antenna", segs=6)
ck.wobble(whip, 0.006, 2.0, seed=5)
parts.append(whip)
parts.append(ck.sph(0.013, (-1.86, 1.82, 0.5), PUSH, name="AntennaTip", segs=8, rings=6))

# ---------------------------------------------------------------- mirrors, A-pillar spotlight (driver side = -z)
for s in (-1, 1):
    tw = random.uniform(-0.06, 0.06)                                   # hand-set, never quite square
    parts.append(ck.box(0.05, 0.03, 0.1, (0.84, 1.235, s * 0.885), BLACK, name="MirrorArm", bevel=0.01, bevel_segs=1))
    parts.append(ck.box(0.09, 0.1, 0.14, (0.84, 1.29, s * 0.94), BLACK, rot=(0, tw, 0), name="Mirror", bevel=0.035, bevel_segs=2))
    parts.append(ck.box(0.008, 0.075, 0.11, (0.794, 1.29, s * 0.94), ck.metal("alu", 0.15), rot=(0, tw, 0), name="MirrorGlass", bevel=0.003, bevel_segs=1))
SP = (0.97, 1.47, -0.93)
parts.append(ck.cyl(0.043, 0.048, 0.13, SP, CHROME, rot=(0, 0, math.pi / 2), name="Spotlight", segs=14, bevel=0.008))
parts.append(ck.cyl(0.037, 0.037, 0.012, (SP[0] + 0.064, SP[1], SP[2]), LENS, rot=(0, 0, math.pi / 2), name="SpotLens", segs=14))
parts.append(ck.cyl(0.012, 0.012, 0.13, (0.93, 1.47, -0.86), CHROME, rot=(math.pi / 2, 0, 0), name="SpotStalk", segs=8))
parts.append(ck.cyl(0.03, 0.03, 0.012, (0.93, 1.47, -0.82), CHROME, rot=(math.pi / 2, 0, 0), name="SpotMount", segs=10))

# ---------------------------------------------------------------- light bar (JS lamps 0.4 x 0.18 x 0.35 at (-0.2, 1.97, +-0.25))
LX = -0.2
parts.append(ck.box(0.46, 0.045, 0.98, (LX, 1.872, 0), CHROME, name="LightBarBase", bevel=0.018, bevel_segs=2))
for z in (-0.36, 0.36):
    parts.append(ck.box(0.3, 0.03, 0.08, (LX, 1.852, z), CHROME, name="LightBarFoot", bevel=0.01, bevel_segs=1))
parts.append(ck.box(0.34, 0.15, 0.14, (LX, 1.96, 0), ck.gloss("#1c1c20", 0.3), name="LightBarCenter", bevel=0.03, bevel_segs=2))
for s in (-1, 1):
    parts.append(ck.box(0.36, 0.15, 0.05, (LX, 1.96, s * 0.45), CHROME, name="LightBarCap", bevel=0.022, bevel_segs=2))
red = ck.box(0.4, 0.18, 0.35, (LX, 1.97, -0.25), ck.glow("#ff1a1a", 1.0), name="LightRed", bevel=0.045)
blue = ck.box(0.4, 0.18, 0.35, (LX, 1.97, 0.25), ck.glow("#1a4aff", 1.0), name="LightBlue", bevel=0.045)

# ---------------------------------------------------------------- wheels (JS r 0.36, 0.3 wide at (+-1.4, 0.36, +-0.9))
WHEEL = kit.TIRE_PROFILE + [                                            # black steel rim, chrome dog-dish cap
    (0.285, 0.15, "tire"), (0.245, 0.146, "tire"),
    (0.236, 0.14, "steel"), (0.215, 0.115, "steel"), (0.155, 0.10, "steel"),
    (0.148, 0.108, "chrome"), (0.12, 0.132, "chrome"), (0.06, 0.147, "chrome"), (0.0, 0.151, "chrome"),
]
for nm, x, z in (("WheelFL", 1.4, -0.9), ("WheelFR", 1.4, 0.9), ("WheelRL", -1.4, -0.9), ("WheelRR", -1.4, 0.9)):
    piv = ck.empty(nm, (x, 0.36, z), parent=root)
    w = kit.lathe(nm + "_Tire", WHEEL, 22, {"steel": STEEL, "tire": TIRE, "chrome": CHROME}, mirror=z < 0, perturb=kit.tread)
    kit.attach(w, piv)

# ---------------------------------------------------------------- assemble
THIN = ("Antenna", "AntennaTip", "SpotStalk", "SpotMount", "GrilleBar", "GrilleFrame", "Exhaust", "ExhaustHole", "Wiper", "ArchLip", "WindowSeal", "PillarTrim")
kit.lumpy_world([o for o in parts if not o.name.startswith(THIN)], 0.0028, 2.4, seed=3)
kit.lumpy_world([red, blue], 0.0015, 4.0, seed=8)
kit.tri_report(parts + [heads, red, blue] + [o for o in root.children_recursive if o.type == "MESH"])
body = ck.join(parts, "Body")
for o in (body, heads, red, blue):
    ck.set_parent(o, root)
kit.report("CopCar")
ck.export("cop_car")
ck.preview("cop_car")
ck.preview("cop_car_close", views=[
    {"eye": (4.6, 2.9, 5.0), "look": (0.2, 0.8, 0), "lens": 35},
    {"eye": (-4.9, 2.4, -4.4), "look": (-0.2, 0.8, 0), "lens": 35},
    {"eye": (3.7, 1.35, -2.3), "look": (1.6, 0.85, -0.35), "lens": 35},
    {"eye": (-3.5, 1.5, 1.9), "look": (-1.8, 0.85, 0.15), "lens": 35}])
