extends RefCounted
## The club's props (plans/club.gd), and the few the back lot shares with it
## (plans/alley.gd). As in props.gd each takes (u, v) on the plan and `yaw`, the
## way it faces (0 the street, 90 right, 180 the back, 270 left), keeps its
## floor space clear of walkers through place.gd's `prop` unless it says not,
## and returns its group. Every name and word on them is a placeholder.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")

const CHROME := Color(0.7, 0.72, 0.76)
const RED := Color(0.5, 0.07, 0.1)            # the club's red vinyl
const TAPE := Color(0.33, 0.34, 0.36)         # gaffer tape, over every split and loose cable
const BRASS := Color(0.7, 0.55, 0.24)
const BLACK := Color(0.07, 0.07, 0.08)
const TOP := Color(0.2, 0.12, 0.08)           # dark varnished wood, gone sticky
const FELT := Color(0.1, 0.36, 0.2)
const PAPERS := [Color(0.98, 0.42, 0.62), Color(0.98, 0.86, 0.2), Color(0.5, 0.9, 0.45), Color(0.98, 0.6, 0.2),
		Color(0.92, 0.92, 0.88), Color(0.45, 0.7, 0.98)]
const SPRAY := [Color(0.95, 0.3, 0.6), Color(0.3, 0.8, 0.95), Color(0.98, 0.82, 0.2), Color(0.45, 0.9, 0.4), Color(0.95, 0.95, 0.92), Color(0.6, 0.4, 0.95)]


## Buttoned red vinyl (the bar front, the booths), turning with the prop.
static func quilt(tint := Color(0.78, 0.14, 0.17)) -> Material:
	return Kit.tex("kit_quilt", 0.42, RED, false, tint)


## A strip of gaffer tape: w long, `along` its way in the plane it lies in, on a
## face that faces +z at `pos` (turned `tilt` degrees in that plane).
static func tape(parent: Node3D, pos: Vector3, w: float, tilt := 0.0, rot := Vector3.ZERO) -> void:
	var g := Kit.group(parent, pos, rot)
	Kit.box(g, Vector3(w, 0.05, 0.003), Vector3.ZERO, TAPE, Vector3(0, 0, tilt))


# ------------------------------------------------------------------- the bar

## A bar stool: a chrome post on a round foot, a foot ring, a red vinyl seat.
## `torn`: a cross of gaffer tape over the split in its seat.
static func stool(p: Node3D, b: int, u: float, v: float, torn := false, h := 0.76) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	Kit.cyl(g, 0.17, 0.03, Vector3(0, 0.015, 0), CHROME.darkened(0.4), Vector3.ZERO, 12)
	Kit.cyl(g, 0.026, h - 0.1, Vector3(0, (h - 0.1) * 0.5 + 0.03, 0), CHROME, Vector3.ZERO, 8)
	Kit.ring(g, 0.15, 0.016, Vector3(0, 0.32, 0), CHROME, Vector3(-90, 0, 0))
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		Kit.tube(g, Vector3(0, 0.32, 0), Vector3(cos(a) * 0.14, 0.32, sin(a) * 0.14), 0.009, CHROME, 4)
	Kit.cyl(g, 0.17, 0.024, Vector3(0, h - 0.068, 0), CHROME, Vector3.ZERO, 14)
	Kit.cyl(g, 0.185, 0.08, Vector3(0, h - 0.016, 0), RED, Vector3.ZERO, 14)
	if torn:
		for a: float in [35.0, -55.0]:
			Kit.box(g, Vector3(0.05, 0.004, 0.27), Vector3(0.02, h + 0.026 + (0.0 if a > 0.0 else 0.003), 0.0), TAPE, Vector3(0, a, 0))
	return g


## The bar: a padded red front split here and there and gaffer-taped, a black
## armrest roll along it, a brass foot rail, a dark wooden top with the rings
## of old drinks, and on it glasses, bottles, an ashtray and napkins. Its
## customers' side is its front. The top is at 1.12.
static func bar(p: Node3D, b: int, u: float, v: float, yaw: float, w: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.66)
	Kit.box(g, Vector3(w - 0.06, 0.12, 0.56), Vector3(0, 0.06, -0.02), BLACK)
	Kit.box(g, Vector3(w, 0.94, 0.49), Vector3(0, 0.59, -0.065), TOP.darkened(0.35))      # meeting the padding's back, not under it
	Kit.box(g, Vector3(w, 0.86, 0.08), Vector3(0, 0.55, 0.22), quilt())
	Kit.cyl(g, 0.055, w, Vector3(0, 1.0, 0.27), BLACK, Vector3(0, 0, 90), 8)
	Kit.bevel(g, Vector3(w + 0.06, 0.06, 0.68), Vector3(0, 1.09, 0.0), TOP, 0.015)
	Kit.tube(g, Vector3(-w * 0.5 + 0.08, 0.2, 0.43), Vector3(w * 0.5 - 0.08, 0.2, 0.43), 0.024, BRASS, 8)
	var n := maxi(int(w / 1.3), 1)
	for i in n + 1:
		var x := -w * 0.5 + 0.12 + (w - 0.24) * float(i) / float(n)
		Kit.box(g, Vector3(0.03, 0.03, 0.17), Vector3(x, 0.2, 0.345), BRASS.darkened(0.2))
	# Splits in the vinyl, taped over.
	for k in int(w / 1.6):
		var x := -w * 0.5 + 0.7 + k * 1.6 + Props.rnd(u + k * 1.7) * 0.4
		tape(g, Vector3(x, 0.45 + 0.25 * Props.rnd(v + k), 0.2615), 0.3, 70.0 + 30.0 * Props.rnd(k + w))
	# What has been left on it.
	var glass := Color(0.72, 0.84, 0.86)
	for k in int(w / 0.7):
		var x := -w * 0.5 + 0.35 + k * 0.7
		var r := Props.rnd(u * 2.3 + k * 3.7)
		var z := 0.12 - 0.1 * Props.rnd(v + k * 1.1)
		Kit.ring(g, 0.042, 0.007, Vector3(x + 0.1, 1.121, z - 0.06), TOP.lightened(0.18), Vector3(-90, 0, 0))
		if r < 0.35:
			Kit.cyl(g, 0.033, 0.12, Vector3(x, 1.18, z), glass, Vector3.ZERO, 8, 0.038)
			Kit.cyl(g, 0.03, 0.05, Vector3(x, 1.145, z), Color(0.75, 0.5, 0.12), Vector3.ZERO, 8)
		elif r < 0.6:
			Kit.cyl(g, 0.03, 0.17, Vector3(x, 1.205, z), Color(0.36, 0.2, 0.08), Vector3.ZERO, 8)
			Kit.cyl(g, 0.012, 0.08, Vector3(x, 1.33, z), Color(0.36, 0.2, 0.08), Vector3.ZERO, 6, 0.01)
		elif r < 0.75:
			Kit.cyl(g, 0.06, 0.02, Vector3(x, 1.13, z), BLACK, Vector3.ZERO, 10)
			Kit.box(g, Vector3(0.06, 0.012, 0.012), Vector3(x + 0.03, 1.145, z), Color(0.92, 0.9, 0.84), Vector3(0, 30, 0))
		else:
			Kit.box(g, Vector3(0.13, 0.03, 0.13), Vector3(x, 1.135, z), Props.PAPER, Vector3(0, 12, 0))
	return g


## The back bar, against the wall behind the bartender: a low cabinet with the
## till on it, two glass shelves of bottles in front of a long mirror, a lit
## beer sign over them. Its front faces the room.
static func back_bar(p: Node3D, b: int, u: float, v: float, yaw: float, w: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.5)
	Kit.box(g, Vector3(w, 0.88, 0.46), Vector3(0, 0.44, 0.01), TOP.darkened(0.3))
	var n := maxi(int(w / 0.62), 1)
	var dw := w / n
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * dw
		Kit.box(g, Vector3(dw - 0.06, 0.66, 0.012), Vector3(x, 0.46, 0.245), TOP.darkened(0.12))
		Kit.box(g, Vector3(0.016, 0.12, 0.024), Vector3(x + dw * 0.32 * (1.0 if i % 2 == 0 else -1.0), 0.6, 0.258), BRASS)
	Kit.bevel(g, Vector3(w + 0.04, 0.04, 0.5), Vector3(0, 0.9, 0.01), TOP, 0.012)
	Kit.box(g, Vector3(w - 0.12, 0.92, 0.012), Vector3(0, 1.66, -0.234), Color(0.42, 0.48, 0.54))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.05, 1.02, 0.04), Vector3(s * (w * 0.5 - 0.06), 1.66, -0.22), TOP)
	Kit.box(g, Vector3(w - 0.12, 0.05, 0.04), Vector3(0, 2.15, -0.22), TOP)
	var k := 0
	for y: float in [1.26, 1.66]:
		Kit.box(g, Vector3(w - 0.16, 0.018, 0.2), Vector3(0, y, -0.13), Color(0.66, 0.76, 0.76))
		var x := -w * 0.5 + 0.2
		while x < w * 0.5 - 0.2:
			var r := Props.rnd(u * 1.3 + v * 0.7 + k * 2.9)
			var tall := 0.22 + 0.1 * r
			Kit.cyl(g, 0.034, tall, Vector3(x, y + 0.009 + tall * 0.5, -0.13 + 0.04 * (r - 0.5)), Props.BOTTLES[k % Props.BOTTLES.size()], Vector3.ZERO, 6, 0.016)
			x += 0.1 + (0.12 if r > 0.85 else 0.0)
			k += 1
	Props.till(g, Vector3(-w * 0.5 + 0.6, 0.92, 0.05), 0.0)
	Kit.box(g, Vector3(0.5, 0.36, 0.42), Vector3(w * 0.5 - 0.5, 1.1, 0.0), Color(0.6, 0.62, 0.66))      # the ice bin
	Kit.box(g, Vector3(0.44, 0.02, 0.36), Vector3(w * 0.5 - 0.5, 1.281, 0.0), Color(0.85, 0.92, 0.95))
	Props.neon(g, "ICE COLD", Vector3(w * 0.25, 2.42, -0.2), 0.12, Color(0.35, 0.75, 1.0))
	return g


## The doorman's stool: tall, black, a ring to rest his boots on.
static func tall_stool(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		Kit.tube(g, Vector3(cos(a) * 0.16, 0.0, sin(a) * 0.16), Vector3(cos(a) * 0.1, 0.8, sin(a) * 0.1), 0.014, BLACK, 5)
	Kit.ring(g, 0.15, 0.014, Vector3(0, 0.3, 0), Color(0.25, 0.25, 0.27), Vector3(-90, 0, 0))
	Kit.cyl(g, 0.17, 0.06, Vector3(0, 0.83, 0), Color(0.12, 0.12, 0.13), Vector3.ZERO, 12)
	return g


## Brass posts on heavy round feet with a red rope hung between each pair: the
## line the queue waits along, at v, the posts at each u in `us`.
static func rope(p: Node3D, b: int, us: Array, v: float) -> void:
	var cord := Color(0.62, 0.06, 0.1)
	for i in us.size():
		var post: Node3D = p.prop(b, us[i], v, 0.0, 0.3, 0.3)
		Kit.cyl(post, 0.14, 0.04, Vector3(0, 0.02, 0), BRASS.darkened(0.25), Vector3.ZERO, 12)
		Kit.cyl(post, 0.025, 0.86, Vector3(0, 0.47, 0), BRASS, Vector3.ZERO, 8)
		Kit.ball(post, 0.045, Vector3(0, 0.92, 0), BRASS, 8)
		if i + 1 < us.size():
			var span: float = float(us[i + 1]) - float(us[i])
			var last := Vector3(0.03, 0.86, 0)
			for k in range(1, 7):
				var t := k / 6.0
				var at := Vector3(0.03 + t * (span - 0.06), 0.86 - 0.24 * sin(PI * t), 0)
				Kit.tube(post, last, at, 0.022, cord, 6)
				last = at
			p.block(float(us[i]), v - 0.03, float(us[i + 1]), v + 0.03)


## A jukebox, its back to a wall: a rounded hood lit in bands of colour over a
## window of record titles, a grille, chrome trim. It still works.
static func jukebox(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.86, 0.6)
	var wood := Color(0.36, 0.16, 0.1)
	Kit.box(g, Vector3(0.86, 1.1, 0.56), Vector3(0, 0.55, -0.02), wood)
	Kit.cyl(g, 0.43, 0.56, Vector3(0, 1.1, -0.02), wood, Vector3(90, 0, 0), 16)
	Kit.cyl(g, 0.36, 0.02, Vector3(0, 1.1, 0.265), Kit.flat(Color(1.0, 0.45, 0.2), 1.6), Vector3(90, 0, 0), 16)
	Kit.cyl(g, 0.28, 0.02, Vector3(0, 1.1, 0.27), Kit.flat(Color(1.0, 0.85, 0.3), 1.6), Vector3(90, 0, 0), 16)
	Kit.box(g, Vector3(0.6, 0.3, 0.03), Vector3(0, 1.0, 0.27), Kit.flat(Color(0.95, 0.92, 0.8), 0.7))
	for r in 4:
		Kit.box(g, Vector3(0.5, 0.025, 0.006), Vector3(0, 0.9 + r * 0.06, 0.288), Color(0.3, 0.2, 0.18))
	Kit.box(g, Vector3(0.6, 0.36, 0.02), Vector3(0, 0.45, 0.265), Color(0.2, 0.18, 0.2))
	for r in 5:
		Kit.box(g, Vector3(0.56, 0.02, 0.012), Vector3(0, 0.32 + r * 0.065, 0.278), CHROME)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.05, 1.06, 0.04), Vector3(s * 0.41, 0.53, 0.26), Kit.flat(Color(0.95, 0.3, 0.55), 1.4))      # stopping under the cabinet's top
	return g


# ---------------------------------------------------------------- the floor

## One side of a booth: a bench with a high back in buttoned red vinyl, split
## and taped. It faces `yaw`; its back is at the back of its floor space.
static func booth_seat(p: Node3D, b: int, u: float, v: float, yaw: float, w: float, torn := 1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	var pad := quilt()
	Kit.box(g, Vector3(w, 0.38, 0.5), Vector3(0, 0.19, 0.04), BLACK)
	Kit.bevel(g, Vector3(w - 0.02, 0.13, 0.52), Vector3(0, 0.445, 0.05), pad, 0.04)
	Kit.bevel(g, Vector3(w, 0.88, 0.14), Vector3(0, 0.84, -0.22), pad, 0.04)
	Kit.box(g, Vector3(w + 0.02, 0.05, 0.16), Vector3(0, 1.3, -0.22), BLACK)
	for k in torn:
		var x := -w * 0.3 + w * 0.6 * Props.rnd(u * 1.9 + v + k * 2.3)
		tape(g, Vector3(x, 0.513, 0.1 + 0.08 * k), 0.26, 0.0, Vector3(-90, 25.0 * (1.0 - 2.0 * k), 0))
		tape(g, Vector3(-x * 0.7, 0.95 - 0.2 * k, -0.149), 0.24, 60.0 - 100.0 * k)
	return g


## A booth's table: a dark top on one black pedestal, a candle in red glass,
## an ashtray, a glass or two.
static func booth_table(p: Node3D, b: int, u: float, v: float, yaw: float, w := 1.1, d := 0.7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.cyl(g, 0.24, 0.03, Vector3(0, 0.015, 0), BLACK, Vector3.ZERO, 10)
	Kit.cyl(g, 0.045, 0.7, Vector3(0, 0.38, 0), BLACK, Vector3.ZERO, 8)
	Kit.bevel(g, Vector3(w, 0.04, d), Vector3(0, 0.75, 0), Color(0.15, 0.13, 0.14), 0.012)
	Kit.cyl(g, 0.045, 0.09, Vector3(0.1, 0.815, 0), Kit.flat(Color(0.85, 0.12, 0.12), 0.9), Vector3.ZERO, 8, 0.04)
	Kit.cyl(g, 0.055, 0.02, Vector3(-0.25, 0.78, 0.12), BLACK, Vector3.ZERO, 10)
	Kit.cyl(g, 0.032, 0.12, Vector3(-0.3, 0.83, -0.14), Color(0.72, 0.84, 0.86), Vector3.ZERO, 8, 0.036)
	Kit.cyl(g, 0.029, 0.05, Vector3(-0.3, 0.795, -0.14), Color(0.55, 0.3, 0.1), Vector3.ZERO, 8)
	return g


## The DJ's table: black pyramid foam on its front in a steel frame, and on top
## two turntables either side of a mixer, a lamp on a gooseneck, headphones; a
## cable taped down across the floor at its foot. Its front faces `yaw`.
static func dj_booth(p: Node3D, b: int, u: float, v: float, yaw: float, w := 2.2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	var foam := Kit.tex("foam", 0.4, BLACK, false, Color(0.62, 0.6, 0.7))
	var steel := Color(0.42, 0.44, 0.48)
	Kit.box(g, Vector3(w, 0.95, 0.56), Vector3(0, 0.475, -0.02), Color(0.1, 0.1, 0.11))
	Kit.box(g, Vector3(w - 0.1, 0.82, 0.03), Vector3(0, 0.49, 0.275), foam)
	for s: float in [-1.0, 1.0]:          # the frame's posts 5 mm out from the table's ends, their tops in its top
		Kit.box(g, Vector3(0.05, 0.97, 0.05), Vector3(s * (w * 0.5 - 0.02), 0.485, 0.27), steel)
	Kit.box(g, Vector3(w - 0.04, 0.05, 0.05), Vector3(0, 0.055, 0.27), steel)
	Kit.bevel(g, Vector3(w + 0.04, 0.04, 0.62), Vector3(0, 0.97, 0), BLACK, 0.01)
	for s: float in [-1.0, 1.0]:
		var x := s * (w * 0.5 - 0.42)
		Kit.bevel(g, Vector3(0.48, 0.08, 0.38), Vector3(x, 1.03, 0.0), Color(0.22, 0.22, 0.24), 0.02)
		Kit.cyl(g, 0.16, 0.014, Vector3(x - 0.04, 1.077, 0.01), Color(0.5, 0.5, 0.52), Vector3.ZERO, 16)
		Kit.cyl(g, 0.15, 0.008, Vector3(x - 0.04, 1.088, 0.01), BLACK, Vector3.ZERO, 16)
		Kit.cyl(g, 0.045, 0.008, Vector3(x - 0.04, 1.094, 0.01), [Color(0.85, 0.2, 0.15), Color(0.2, 0.4, 0.85)][int(s > 0.0)], Vector3.ZERO, 10)
		Kit.cyl(g, 0.025, 0.04, Vector3(x + 0.17, 1.09, -0.12), steel, Vector3.ZERO, 8)
		Kit.tube(g, Vector3(x + 0.17, 1.11, -0.12), Vector3(x + 0.08, 1.11, 0.1), 0.007, CHROME, 5)
	Kit.bevel(g, Vector3(0.3, 0.08, 0.34), Vector3(0, 1.03, 0.0), Color(0.16, 0.16, 0.18), 0.02)
	for k in 3:
		Kit.box(g, Vector3(0.02, 0.02, 0.06), Vector3(-0.08 + k * 0.08, 1.075, 0.09), CHROME)
		for r in 3:
			Kit.cyl(g, 0.012, 0.02, Vector3(-0.08 + k * 0.08, 1.08, -0.11 + r * 0.055), Kit.flat([Color(1.0, 0.3, 0.2), Color(0.3, 1.0, 0.5), Color(1.0, 0.85, 0.3)][r], 0.8), Vector3.ZERO, 6)
	Kit.tube(g, Vector3(w * 0.5 - 0.12, 0.99, -0.22), Vector3(w * 0.5 - 0.16, 1.4, -0.12), 0.01, steel, 5)
	Kit.cyl(g, 0.05, 0.08, Vector3(w * 0.5 - 0.17, 1.42, -0.08), BLACK, Vector3(60, 0, 0), 8, 0.03)
	Kit.cyl(g, 0.035, 0.01, Vector3(w * 0.5 - 0.17, 1.39, -0.05), Kit.flat(Color(1.0, 0.9, 0.7), 1.5), Vector3(60, 0, 0), 8)
	Kit.ring(g, 0.09, 0.018, Vector3(-0.15, 1.0, -0.2), BLACK, Vector3(-90, 0, 0))
	for k in 2:
		Kit.box(g, Vector3(0.6, 0.004, 0.05), Vector3(-0.3 + k * 0.5, 0.002, 0.65 + k * 0.25), TAPE, Vector3(0, 8.0 - k * 20.0, 0))
	return g


## The light rig over the dance floor: a black truss on chains from the
## ceiling, a can light for each colour along it, tipped down, and under each
## a coloured lamp that floods the floor; a mirror ball off its middle.
static func light_rig(p: Node3D, b: int, u0: float, u1: float, v: float, y: float, colours: Array, ceil := 2.9) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt((u0 + u1) * 0.5, v), Vector3.ZERO)
	var w := u1 - u0
	for dz: float in [-0.13, 0.13]:
		Kit.tube(g, Vector3(-w * 0.5, y, dz), Vector3(w * 0.5, y, dz), 0.022, BLACK, 6)
	var bays := maxi(int(w / 0.35), 1)
	for i in bays:
		var x := -w * 0.5 + w * float(i) / float(bays)
		var x1 := -w * 0.5 + w * float(i + 1) / float(bays)
		Kit.tube(g, Vector3(x, y, -0.13 if i % 2 == 0 else 0.13), Vector3(x1, y, 0.13 if i % 2 == 0 else -0.13), 0.009, BLACK, 4)
	for x: float in [-w * 0.38, w * 0.38]:
		Kit.tube(g, Vector3(x, y, 0), Vector3(x, ceil, 0), 0.007, Color(0.2, 0.2, 0.22), 4)
	var n := colours.size()
	for i in n:
		var c: Color = colours[i]
		var x := -w * 0.5 + (i + 0.5) * w / n
		var toward := 1.0 if i % 2 == 0 else -1.0
		Kit.box(g, Vector3(0.24, 0.025, 0.025), Vector3(x, y - 0.035, 0), BLACK)
		var can := Kit.group(g, Vector3(x, y - 0.17, 0), Vector3(-30.0 * toward, 0, 0))
		Kit.cyl(can, 0.085, 0.26, Vector3.ZERO, BLACK, Vector3.ZERO, 10)
		Kit.cyl(can, 0.074, 0.01, Vector3(0, -0.131, 0), Kit.flat(c, 3.0), Vector3.ZERO, 10)
		Kit.omni(g, Vector3(x, y - 0.55, 0.45 * toward), c, 1.5, 5.0)
	Kit.tube(g, Vector3(0, y, 0), Vector3(0, y - 0.3, 0), 0.006, CHROME, 4)
	Kit.ball(g, 0.15, Vector3(0, y - 0.45, 0), Kit.flat(Color(0.82, 0.84, 0.9), 0.35), 8)
	return g


## A pool table: green felt with a taped-over rip, in fat wooden rails with
## pockets at the corners and sides, on four turned legs; the balls and a cue
## left on it, its long lamp hanging over it on two chains.
static func pool_table(p: Node3D, b: int, u: float, v: float, yaw: float, ceil := 2.9) -> Node3D:
	var w := 2.3
	var d := 1.3
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var wood := Color(0.34, 0.18, 0.1)
	for x: float in [-w * 0.5 + 0.22, w * 0.5 - 0.22]:
		for z: float in [-d * 0.5 + 0.18, d * 0.5 - 0.18]:
			Kit.cyl(g, 0.075, 0.6, Vector3(x, 0.3, z), wood.darkened(0.25), Vector3.ZERO, 8, 0.1)
	Kit.box(g, Vector3(w - 0.16, 0.2, d - 0.16), Vector3(0, 0.68, 0), wood)
	Kit.box(g, Vector3(w - 0.22, 0.04, d - 0.22), Vector3(0, 0.79, 0), FELT)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(g, Vector3(w, 0.08, 0.12), Vector3(0, 0.82, s * (d * 0.5 - 0.06)), wood, 0.025)
		Kit.bevel(g, Vector3(0.12, 0.08, d - 0.24), Vector3(s * (w * 0.5 - 0.06), 0.82, 0), wood, 0.025)
		for x: float in [-w * 0.5 + 0.1, 0.0, w * 0.5 - 0.1]:
			Kit.cyl(g, 0.055, 0.012, Vector3(x, 0.861, s * (d * 0.5 - 0.1)), BLACK, Vector3.ZERO, 10)
	var balls := [Color(0.95, 0.94, 0.88), Color(0.95, 0.78, 0.15), Color(0.2, 0.3, 0.75), Color(0.85, 0.18, 0.15), Color(0.45, 0.2, 0.5), Color(0.08, 0.08, 0.08), Color(0.2, 0.55, 0.3)]
	for i in balls.size():
		var r1 := Props.rnd(u * 2.1 + i * 3.3)
		var r2 := Props.rnd(v * 1.7 + i * 5.1)
		Kit.ball(g, 0.029, Vector3(-0.85 + 1.7 * r1, 0.839, -0.45 + 0.9 * r2), balls[i], 8)
	Kit.tube(g, Vector3(-0.95, 0.845, 0.36), Vector3(0.45, 0.835, -0.12), 0.012, Color(0.78, 0.62, 0.38), 6)
	Kit.box(g, Vector3(0.42, 0.003, 0.05), Vector3(0.45, 0.8115, 0.2), TAPE, Vector3(0, 25, 0))
	Kit.box(g, Vector3(0.025, 0.02, 0.025), Vector3(w * 0.5 - 0.06, 0.87, d * 0.5 - 0.3), Color(0.2, 0.4, 0.8))
	# Its lamp: a long green shade, lit underneath.
	for x: float in [-0.5, 0.5]:
		Kit.tube(g, Vector3(x, 2.46, 0), Vector3(x, ceil, 0), 0.007, Color(0.2, 0.2, 0.22), 4)
	Kit.bevel(g, Vector3(1.3, 0.16, 0.34), Vector3(0, 2.38, 0), Color(0.12, 0.34, 0.2), 0.04)
	Kit.box(g, Vector3(1.2, 0.01, 0.26), Vector3(0, 2.297, 0), Kit.flat(Color(1.0, 0.92, 0.7), 1.6))
	Kit.omni(g, Vector3(0, 1.9, 0), Color(1.0, 0.88, 0.62), 1.2, 3.4)
	return g


## An arcade machine that has given up: its screen dark and cracked, its
## marquee dead, a sheet of paper taped over the coin door saying so.
static func arcade(p: Node3D, b: int, u: float, v: float, yaw: float, title := "STREET KINGS") -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.66, 0.9)
	var body := Color(0.16, 0.12, 0.3)
	Kit.box(g, Vector3(0.66, 1.84, 0.62), Vector3(0, 0.92, -0.14), body)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.008, 1.3, 0.5), Vector3(s * 0.334, 1.0, -0.14), Color(0.9, 0.3, 0.2))
		Kit.box(g, Vector3(0.008, 0.5, 0.3), Vector3(s * 0.337, 1.2, -0.1), Color(0.98, 0.8, 0.2))
	Kit.box(g, Vector3(0.56, 0.5, 0.02), Vector3(0, 1.36, 0.18), BLACK)
	Kit.box(g, Vector3(0.46, 0.38, 0.01), Vector3(0, 1.36, 0.193), Color(0.05, 0.07, 0.07))
	for c: Array in [[0.02, 1.4, 50.0, 0.3], [0.06, 1.33, -20.0, 0.2], [-0.1, 1.42, 110.0, 0.16]]:
		Kit.box(g, Vector3(c[3], 0.006, 0.003), Vector3(c[0], c[1], 0.2), Color(0.55, 0.6, 0.6), Vector3(0, 0, c[2]))
	Kit.box(g, Vector3(0.64, 0.22, 0.16), Vector3(0, 1.75, 0.1), Color(0.3, 0.28, 0.32))      # its top 2 cm over the cabinet's
	Props.words(g, title, Vector3(0, 1.75, 0.182), 0.07, Color(0.52, 0.42, 0.5))
	Kit.box(g, Vector3(0.66, 0.08, 0.26), Vector3(0, 0.98, 0.29), body.lightened(0.1), Vector3(-12, 0, 0))
	Kit.cyl(g, 0.012, 0.08, Vector3(-0.15, 1.06, 0.3), BLACK, Vector3.ZERO, 6)
	Kit.ball(g, 0.026, Vector3(-0.15, 1.1, 0.3), Color(0.85, 0.15, 0.15), 8)
	for k in 3:
		Kit.cyl(g, 0.022, 0.02, Vector3(0.04 + k * 0.08, 1.04, 0.31), Color(0.95, 0.8, 0.2) if k != 1 else Color(0.2, 0.5, 0.95), Vector3(-12, 0, 0), 8)
	Kit.box(g, Vector3(0.64, 0.84, 0.04), Vector3(0, 0.46, 0.16), body.darkened(0.2))
	Kit.box(g, Vector3(0.24, 0.28, 0.012), Vector3(0, 0.6, 0.176), Color(0.3, 0.3, 0.34))
	var sheet := Kit.group(g, Vector3(0.01, 0.62, 0.186), Vector3(0, 0, 4))
	Kit.box(sheet, Vector3(0.3, 0.21, 0.003), Vector3.ZERO, Props.PAPER)
	Props.words(sheet, "OUT OF ORDER", Vector3(0, 0.02, 0.003), 0.04, Color(0.15, 0.15, 0.2), 0.0, false)
	for x: float in [-0.14, 0.14]:
		Kit.box(sheet, Vector3(0.06, 0.03, 0.002), Vector3(x, 0.1, 0.002), Color(0.8, 0.78, 0.7), Vector3(0, 0, -x * 200.0))
	return g


## A dropped ceiling of square tiles, seen only from below (it never hides the
## room from a camera over it): the tiles in `stains` (their corners, [u, v],
## on the 0.6 m grid) are water-stained, and at `hole` one is gone, a cable
## hanging out of the dark and the tile itself dangling by a corner.
static func ceiling(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, y: float, stains: Array, hole: Array) -> void:
	var n: Node3D = p.node_of(b)
	_under(n, p.rect(u0, v0, u1, v1), y, Kit.tex("ceiling_tile", 0.6, Color(0.5, 0.46, 0.4), true, Color(0.44, 0.4, 0.34)))      # gone yellow-brown with smoke
	var stain := Kit.tex("ceiling_tile", 0.6, Color(0.42, 0.33, 0.21), true, Color(0.4, 0.31, 0.19))
	var ring := Kit.tex("ceiling_tile", 0.6, Color(0.32, 0.24, 0.15), true, Color(0.3, 0.22, 0.13))
	for s: Array in stains:
		_under(n, p.rect(s[0], s[1], s[0] + 0.6, s[1] + 0.6), y - 0.002, ring)
		_under(n, p.rect(s[0] + 0.07, s[1] + 0.06, s[0] + 0.52, s[1] + 0.55), y - 0.004, stain)
	if hole.size() == 2:
		var r: Rect2 = p.rect(hole[0], hole[1], hole[0] + 0.6, hole[1] + 0.6)
		_under(n, r.grow(-0.01), y - 0.002, BLACK)
		var c := Vector3(r.get_center().x, y, r.get_center().y)
		Kit.tube(n, c + Vector3(0.1, 0.0, 0.05), c + Vector3(0.16, -0.45, 0.1), 0.008, BLACK, 4)
		Kit.tube(n, c + Vector3(0.16, -0.45, 0.1), c + Vector3(0.1, -0.62, 0.02), 0.008, BLACK, 4)
		var hang := Kit.group(n, Vector3(r.position.x, y - 0.01, r.end.y), Vector3(-62, 0, 0))
		Kit.box(hang, Vector3(0.58, 0.012, 0.58), Vector3(0.29, 0.0, -0.29), Kit.tex("ceiling_tile", 0.6, Color(0.5, 0.46, 0.4), false, Color(0.42, 0.37, 0.3)))


## Litter on a floor (decoration: it does not block): crushed cups, cans,
## napkins, butts and trodden flyers, n of them over w by d round (u, v). Each
## lies at a slant to the room, so none lines up with a mat or a border.
static func litter(p: Node3D, b: int, u: float, v: float, w: float, d: float, n: int, seed := 0.0) -> void:
	var node: Node3D = p.node_of(b)
	for i in n:
		var k := seed + i * 5.17 + u * 1.3 + v * 0.7
		var at: Vector3 = p.pt(u + (Props.rnd(k) - 0.5) * w, v + (Props.rnd(k + 1.0) - 0.5) * d)
		var turn := 15.0 + 60.0 * Props.rnd(k + 2.0)
		match i % 5:
			0:
				Kit.cyl(node, 0.042, 0.1, at + Vector3(0, 0.042, 0), Color(0.86, 0.16, 0.16), Vector3(90, turn, 0), 8, 0.03)
			1:
				Kit.cyl(node, 0.032, 0.12, at + Vector3(0, 0.032, 0), [Color(0.75, 0.75, 0.78), Color(0.2, 0.35, 0.75), Color(0.85, 0.7, 0.15)][int(Props.rnd(k + 3.0) * 3.0) % 3], Vector3(90, turn * 3.0, 0), 8)
			2:
				Kit.box(node, Vector3(0.14, 0.004, 0.14), at + Vector3(0, 0.013, 0), Color(0.92, 0.9, 0.84), Vector3(0, turn, 0))
			3:
				for j in 3:
					Kit.cyl(node, 0.006, 0.035, at + Vector3(0.05 * j, 0.006, 0.03 * (j % 2)), Color(0.9, 0.82, 0.62), Vector3(90, turn + j * 40.0, 0), 5)
			_:
				Kit.box(node, Vector3(0.2, 0.004, 0.28), at + Vector3(0, 0.013, 0), (PAPERS[int(Props.rnd(k + 4.0) * PAPERS.size()) % PAPERS.size()] as Color).darkened(0.3), Vector3(0, turn, 0))


static func _under(n: Node3D, r: Rect2, y: float, look: Variant) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = r.size
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = Kit._mat(look)
	mi.position = Vector3(r.get_center().x, y, r.get_center().y)
	mi.rotation_degrees = Vector3(180, 0, 0)          # face down
	n.add_child(mi)
	return mi


# ------------------------------------------------------------------ walls

## A patch of flyers pasted on a wall facing `yaw`, round (u, v) on its face,
## about w wide and h high from y0: bright sheets at odd angles, each over the
## last, with bars of print on them. `b` is a band, or a node (a street front).
static func flyers(p: Node3D, b: Variant, u: float, v: float, yaw: float, w: float, h: float, y0: float, n := 9) -> Node3D:
	var g := Kit.group(In._node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	var laid: Array = []        # [where each sheet lies (grown for its tilt), its layer]
	for i in n:
		var r1 := Props.rnd(u * 3.7 + v * 1.3 + i * 7.1)
		var r2 := Props.rnd(u * 1.9 + v * 4.1 + i * 3.3)
		var fw := 0.21 + 0.08 * r1
		var fh := 0.29 + 0.06 * r2
		var x := -w * 0.5 + fw * 0.5 + r1 * (w - fw)
		var y := y0 + fh * 0.5 + r2 * (h - fh)
		var spot := Rect2(x - fw * 0.5, y - fh * 0.5, fw, fh).grow(0.03)
		var layer := 0             # one layer over every sheet it covers, so the patch stays thin
		for q: Array in laid:
			if (q[0] as Rect2).intersects(spot):
				layer = maxi(layer, int(q[1]) + 1)
		laid.append([spot, layer])
		# A layer is 2.5 mm, the print 1.2 mm over its sheet: faces closer than a millimetre flicker.
		var sheet := Kit.group(g, Vector3(x, y, 0.0015 + layer * 0.0025), Vector3(0, 0, (Props.rnd(i * 5.3 + u) - 0.5) * 16.0))
		var look: Color = PAPERS[int(Props.rnd(i * 2.9 + v + u) * PAPERS.size()) % PAPERS.size()]
		var ink := look.darkened(0.62)
		Kit.box(sheet, Vector3(fw, fh, 0.0006), Vector3.ZERO, look)
		Kit.box(sheet, Vector3(fw * 0.8, fh * 0.17, 0.0006), Vector3(0, fh * 0.29, 0.0012), ink)
		for k in 3:
			Kit.box(sheet, Vector3(fw * (0.7 - 0.12 * k), fh * 0.045, 0.0006), Vector3(0, -fh * (0.02 + 0.12 * k), 0.0012), ink)
	return g


## Tags in spray paint on a wall facing `yaw` (made-up words, placeholders):
## each [text, u or v along the wall, y, height, tilt], at the wall's face (u, v).
static func tags(p: Node3D, b: Variant, u: float, v: float, yaw: float, marks: Array, seed := 0.0) -> void:
	var g := Kit.group(In._node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	for i in marks.size():
		var m: Array = marks[i]
		var c: Color = SPRAY[int(Props.rnd(seed + i * 4.1) * SPRAY.size()) % SPRAY.size()]
		var l := Props.words(g, String(m[0]), Vector3(float(m[1]), float(m[2]), 0.004 + i * 0.002), float(m[3]), c)
		l.rotation_degrees.z = float(m[4])
		l.outline_size = 10
		l.outline_modulate = Color(0.05, 0.05, 0.06)


## The club's sign over its door: a black board on brackets with the name in
## neon that has died (grey tubes, unlit) and the word under it still glowing.
static func dead_sign(p: Node3D, n: Node3D, u: float, v: float, y: float, w: float, name: String, lit: String, colour: Color) -> void:
	Kit.box(n, Vector3(w, 0.9, 0.08), p.pt(u, v + 0.12, y), BLACK)
	Kit.box(n, Vector3(w + 0.06, 0.04, 0.1), p.pt(u, v + 0.12, y + 0.47), Color(0.2, 0.2, 0.22))
	for s: float in [-1.0, 1.0]:
		Kit.box(n, Vector3(0.05, 0.05, 0.12), p.pt(u + s * (w * 0.5 - 0.3), v + 0.06, y - 0.3), Color(0.2, 0.2, 0.22))
	var dead := Props.words(n, name, p.pt(u, v + 0.17, y + 0.12), 0.38, Color(0.42, 0.36, 0.4))
	dead.outline_size = 6
	dead.outline_modulate = Color(0.2, 0.18, 0.2)
	Props.neon(n, lit, p.pt(u, v + 0.17, y - 0.25), 0.16, colour)
	Kit.omni(n, p.pt(u, v + 0.6, y - 0.3), colour, 0.5, 2.5)


## A roll-down shutter on a street front (its street face at v): the housing over
## the window's head, guide rails down each side, the slats down to y1 and the
## bottom bar with its padlock eye.
static func shutter(p: Node3D, n: Node3D, v: float, a: float, e: float, y1: float, head: float) -> void:
	var slats := Kit.tex("in_ribbed", 0.5, Color(0.55, 0.56, 0.58), true, Color(0.62, 0.63, 0.66))
	var iron := Color(0.32, 0.33, 0.36)
	p.slab(n, true, v + 0.17, a - 0.12, e + 0.12, head + 0.06, head + 0.42, 0.26, iron)
	for x: Array in [[a - 0.1, a + 0.02], [e - 0.02, e + 0.1]]:
		p.slab(n, true, v + 0.11, x[0], x[1], 0.0, head + 0.06, 0.08, iron)
	p.slab(n, true, v + 0.12, a + 0.02, e - 0.02, y1, head + 0.06, 0.03, slats)
	p.slab(n, true, v + 0.125, a + 0.01, e - 0.01, y1 - 0.05, y1 + 0.03, 0.06, iron.darkened(0.2))      # its ends in the rails
	Kit.ring(n, 0.03, 0.01, p.pt((a + e) * 0.5, v + 0.16, y1 - 0.06), CHROME)


## A steel fire door in a wall facing `yaw` (a picture of one on the whole wall:
## where it goes is a use point beside it): frame, leaf, push bar, kick plate,
## the lit EXIT sign over it.
static func fire_door(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	var steel := Color(0.36, 0.4, 0.43)
	Kit.box(g, Vector3(1.1, 2.18, 0.03), Vector3(0, 1.09, 0.015), Color(0.2, 0.21, 0.23))
	Kit.box(g, Vector3(0.96, 2.08, 0.03), Vector3(0, 1.04, 0.04), steel)
	Kit.box(g, Vector3(0.96, 0.26, 0.004), Vector3(0, 0.15, 0.057), steel.lightened(0.15))
	Kit.box(g, Vector3(0.8, 0.07, 0.05), Vector3(0, 1.0, 0.08), Props.STEEL)
	for x: float in [-0.4, 0.4]:
		Kit.box(g, Vector3(0.06, 0.12, 0.08), Vector3(x, 1.0, 0.07), Color(0.2, 0.21, 0.23))      # 5 mm proud of the bar
	tape(g, Vector3(0.2, 1.6, 0.057), 0.3, 20.0)
	Props.sign_box(g, "EXIT", Vector3(0, 2.4, 0.06), Vector2(0.38, 0.15), Color(0.95, 0.12, 0.1), Color(1.0, 0.96, 0.9), 0.0, 1.4, 0.09)
	return g


## A keg standing on the floor.
static func keg(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.46, 0.46)
	Kit.cyl(g, 0.21, 0.58, Vector3(0, 0.29, 0), Props.STEEL, Vector3.ZERO, 12)
	for y: float in [0.1, 0.48]:
		Kit.cyl(g, 0.222, 0.04, Vector3(0, y, 0), Props.STEEL.darkened(0.2), Vector3.ZERO, 12)
	Kit.cyl(g, 0.04, 0.05, Vector3(0, 0.6, 0), BLACK, Vector3.ZERO, 8)
	return g


## A grey fuse box on a wall facing `yaw`, its conduit up to the ceiling, a
## warning label, its door taped shut.
static func fuse_box(p: Node3D, b: int, u: float, v: float, yaw: float, y := 1.5) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.42, 0.56, 0.12), Vector3(0, y, 0.06), Color(0.52, 0.54, 0.56))
	Kit.box(g, Vector3(0.38, 0.52, 0.01), Vector3(0, y, 0.124), Color(0.58, 0.6, 0.62))
	Kit.box(g, Vector3(0.12, 0.08, 0.004), Vector3(-0.08, y + 0.14, 0.131), Color(0.98, 0.82, 0.15))
	Kit.cyl(g, 0.02, 2.9 - y - 0.28, Vector3(0.1, (2.9 + y + 0.28) * 0.5, 0.04), Color(0.45, 0.47, 0.5), Vector3.ZERO, 6)
	tape(g, Vector3(0.17, y - 0.05, 0.131), 0.16, 90.0)
	return g


## A hand dryer on a wall facing `yaw`.
static func hand_dryer(p: Node3D, b: int, u: float, v: float, yaw: float, y := 1.15) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.28, 0.24, 0.16), Vector3(0, y, 0.08), Color(0.86, 0.86, 0.84), 0.04)
	Kit.cyl(g, 0.035, 0.06, Vector3(0, y - 0.13, 0.1), Props.STEEL, Vector3.ZERO, 8)
	Kit.box(g, Vector3(0.18, 0.06, 0.004), Vector3(0, y + 0.05, 0.161), Color(0.3, 0.3, 0.32))
	return g


## A row of n toilet stalls with their backs to the back wall (v0, facing the
## street), from u0 (a side wall), each w wide and d deep: grey steel partitions
## on feet, a door in each front (the last off its top hinge, hanging), a toilet
## in each, tags in marker. The stalls' floor is kept clear of walkers.
static func stalls(p: Node3D, b: int, u0: float, v0: float, n: int, w := 1.0, d := 1.5) -> void:
	var node: Node3D = p.node_of(b)
	var steel := Color(0.46, 0.5, 0.52)
	var front := v0 + d
	for i in range(1, n + 1):
		var x := u0 + i * w
		Kit.box(node, Vector3(0.03, 1.72, d - 0.02), p.pt(x, v0 + d * 0.5 - 0.01, 0.17 + 0.86), steel)
		for z: float in [v0 + 0.2, front - 0.15]:
			Kit.box(node, Vector3(0.05, 0.17, 0.05), p.pt(x, z, 0.085), Props.STEEL)
	for i in n:
		var x := u0 + (i + 0.5) * w
		Props.toilet(p, b, x, v0 + 0.36, 0.0)
		Kit.box(node, Vector3(0.06, 1.72, 0.04), p.pt(x - w * 0.5 + 0.03, front, 0.17 + 0.86), steel.darkened(0.1))
		if i < n - 1:
			Kit.box(node, Vector3(w - 0.1, 1.6, 0.03), p.pt(x + 0.02, front, 0.22 + 0.8), steel.lightened(0.08))
			Kit.box(node, Vector3(0.05, 0.08, 0.02), p.pt(x + w * 0.36, front + 0.025, 1.05), Props.IRON)
			tags(p, b, x, front + 0.016, 0.0, [["VORPO", -0.1, 1.3, 0.11, 8.0], ["OOKS", 0.15, 0.7, 0.08, -12.0]], u0 + i)
		else:
			var hang := Kit.group(node, p.pt(x - w * 0.5 + 0.06, front, 0.22), Vector3(0, -28, -7))
			Kit.box(hang, Vector3(w - 0.1, 1.6, 0.03), Vector3((w - 0.1) * 0.5, 0.8, 0.0), steel.lightened(0.08))
			Props.words(hang, "ZAYDO", Vector3((w - 0.1) * 0.5, 1.1, 0.018), 0.1, SPRAY[0])
			p.block(x - w * 0.5 + 0.06, front, x + w * 0.5 - 0.1, front + 0.45)      # the door hanging open
	p.block(u0, v0, u0 + n * w, front + 0.03)
