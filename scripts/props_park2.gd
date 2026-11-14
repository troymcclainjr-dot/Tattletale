extends RefCounted
## The pieces of THE GREEN (plans/park2.gd): an old neighbourhood square of
## lawns, flower beds and iron railings round a bandstand, a playground in one
## corner, and the grand old houses and the church across the streets round it.
## Same style as props.gd:
##
##   const Park := preload("res://scripts/props_park2.gd")
##   Park.park_bench(p, band, u, v, yaw)
##
## `p` is the Place, `band` the band the thing stands in, (u, v) the middle of
## its floor space on the plan and `yaw` the way its front faces (0 the street,
## 90 right, 180 the back, 270 left). Each takes up floor nobody can walk on,
## unless it says otherwise. The buildings round the square are never walked
## to: they are built straight into a node at a point in the world, front
## facing +z before turning, and take no floor.

const Props := preload("res://scripts/props.gd")
const Street := preload("res://scripts/props_street.gd")

const IRON := Color(0.11, 0.14, 0.13)          # railings, lamp posts, bench ends: black-green paint
const GILT := Color(0.92, 0.72, 0.26)
const STONE := Color(0.86, 0.83, 0.74)
const MARBLE := Color(0.94, 0.94, 0.91)
const WARM := Color(1.0, 0.84, 0.58)           # lamp light
const GLOBE := Color(1.0, 0.94, 0.78)
const LIT := Color(1.0, 0.82, 0.5)             # a lit window
const DARK_GLASS := Color(0.17, 0.2, 0.3)
const LEAF := Color(0.22, 0.48, 0.25)
const SOIL := Color(0.3, 0.2, 0.14)
const SASH := Color(0.92, 0.9, 0.84)
const BLOOMS := [Color(0.96, 0.2, 0.24), Color(1.0, 0.82, 0.15), Color(0.66, 0.32, 0.88), Color(1.0, 0.56, 0.72), Color(0.97, 0.95, 0.9), Color(1.0, 0.5, 0.14)]
const DOORS := [Color(0.1, 0.1, 0.12), Color(0.12, 0.32, 0.22), Color(0.5, 0.12, 0.12), Color(0.14, 0.2, 0.42), Color(0.88, 0.85, 0.76)]
const CURTAINS := [Color(0.86, 0.3, 0.3), Color(0.96, 0.9, 0.72), Color(0.42, 0.56, 0.88), Color(0.96, 0.7, 0.3), Color(0.5, 0.75, 0.45)]
const PLAY := [Color(0.93, 0.22, 0.18), Color(0.99, 0.78, 0.15), Color(0.2, 0.62, 0.3), Color(0.18, 0.44, 0.88)]


## A box between two points on the floor plane of a group: for a rail, a rib or
## a strut that runs at a slant. `a` and `b` are its two ends.
static func strut(parent: Node3D, a: Vector3, b: Vector3, thick: float, look: Variant) -> MeshInstance3D:
	var mi := Kit.box(parent, Vector3(thick, thick, a.distance_to(b)), (a + b) * 0.5, look)
	var dir := (b - a).normalized()
	mi.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	return mi


## Floor nobody may walk on, the shape of a circle of radius r at (u, v): a
## stack of rectangles that covers it.
static func block_round(p: Node3D, u: float, v: float, r: float) -> void:
	for hw: Array in [[r, r * 0.42], [r * 0.91, r * 0.62], [r * 0.785, r * 0.785], [r * 0.62, r * 0.91], [r * 0.42, r]]:
		p.block(u - hw[0], v - hw[1], u + hw[0], v + hw[1])


# ------------------------------------------------------------------ the square

## An old cast-iron lamp post with a glowing globe on top, or two on a crossbar
## (`arms` 2). It lights the ground round it.
static func lamp_post(p: Node3D, b: int, u: float, v: float, arms := 1, h := 3.3, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.34, 0.34)
	Kit.cyl(g, 0.17, 0.12, Vector3(0, 0.06, 0), IRON, Vector3.ZERO, 8)
	Kit.cyl(g, 0.13, 0.55, Vector3(0, 0.395, 0), IRON, Vector3.ZERO, 8, 0.075)
	Kit.cyl(g, 0.1, 0.06, Vector3(0, 0.7, 0), IRON, Vector3.ZERO, 8)
	Kit.cyl(g, 0.055, h - 0.73, Vector3(0, 0.73 + (h - 0.73) * 0.5, 0), IRON, Vector3.ZERO, 8, 0.042)
	Kit.cyl(g, 0.07, 0.05, Vector3(0, 1.6, 0), GILT, Vector3.ZERO, 8)
	var tops: Array = [Vector3(0, h, 0)]
	if arms == 2:
		Kit.box(g, Vector3(1.0, 0.05, 0.05), Vector3(0, h - 0.12, 0), IRON)
		for s: float in [-1.0, 1.0]:
			strut(g, Vector3(s * 0.05, h - 0.5, 0), Vector3(s * 0.38, h - 0.14, 0), 0.03, IRON)
		Kit.ball(g, 0.07, Vector3(0, h - 0.05, 0), GILT, 6)
		tops = [Vector3(-0.46, h - 0.1, 0), Vector3(0.46, h - 0.1, 0)]
	for t: Vector3 in tops:
		Kit.cyl(g, 0.11, 0.1, t + Vector3(0, 0.05, 0), IRON, Vector3.ZERO, 8, 0.13)
		Kit.ball(g, 0.21, t + Vector3(0, 0.3, 0), Kit.flat(GLOBE, 1.8), 10)
		Kit.cyl(g, 0.06, 0.06, t + Vector3(0, 0.53, 0), IRON, Vector3.ZERO, 6, 0.02)
	Kit.omni(g, Vector3(0, h + 0.15, 0), WARM, 5.0, 7.0)
	return g


## A park bench: wooden slats on cast-iron ends, a sloping back. Any yaw: a
## bench that is not square to the plan keeps a square of floor round it.
static func park_bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.9, slat := Color(0.66, 0.42, 0.22)) -> Node3D:
	var g: Node3D
	if posmod(int(round(yaw)), 90) == 0:
		g = p.prop(b, u, v, yaw, w, 0.62)
	else:
		g = p.prop(b, u, v, yaw, w, 0.62, false)
		var s := (w + 0.62) * 0.3
		p.block(u - s, v - s, u + s, v + s)
	for x: float in [-w * 0.5 + 0.13, w * 0.5 - 0.13]:
		Kit.box(g, Vector3(0.07, 0.44, 0.07), Vector3(x, 0.22, 0.2), IRON)          # front leg
		Kit.box(g, Vector3(0.07, 0.95, 0.07), Vector3(x, 0.47, -0.21), IRON, Vector3(-11, 0, 0))   # back leg and upright
		Kit.box(g, Vector3(0.07, 0.06, 0.5), Vector3(x, 0.4, -0.01), IRON)          # under the seat
		Kit.box(g, Vector3(0.075, 0.05, 0.44), Vector3(x, 0.67, 0.01), IRON)        # the arm
		Kit.box(g, Vector3(0.06, 0.2, 0.06), Vector3(x, 0.55, 0.2), IRON)
		Kit.ball(g, 0.055, Vector3(x, 0.67, 0.24), IRON, 6)                        # the scroll on its end
	for z: float in [-0.14, 0.01, 0.16]:
		Kit.box(g, Vector3(w, 0.045, 0.12), Vector3(0, 0.452, z), slat)
	var back := Kit.group(g, Vector3(0, 0.47, -0.24), Vector3(-12, 0, 0))
	for y: float in [0.16, 0.3, 0.44]:
		Kit.box(back, Vector3(w, 0.1, 0.035), Vector3(0, y, 0), slat)
	return g


## A brick gate pier with a stone base and cap. top: "ball" (a stone ball on
## it) or "lamp" (a glowing globe, lit).
static func pier(p: Node3D, b: int, u: float, v: float, h := 1.55, top := "ball") -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.72, 0.72)
	var brick := Kit.tex("brick", 0.9, Color(0.6, 0.3, 0.22), false, Color(1.0, 0.86, 0.8))
	Kit.box(g, Vector3(0.8, 0.3, 0.8), Vector3(0, 0.15, 0), STONE.darkened(0.1))
	Kit.box(g, Vector3(0.68, h - 0.3, 0.68), Vector3(0, 0.3 + (h - 0.3) * 0.5, 0), brick)
	Kit.box(g, Vector3(0.84, 0.1, 0.84), Vector3(0, h + 0.05, 0), STONE)
	Kit.box(g, Vector3(0.72, 0.08, 0.72), Vector3(0, h + 0.14, 0), STONE.darkened(0.04))
	if top == "lamp":
		Kit.cyl(g, 0.12, 0.2, Vector3(0, h + 0.28, 0), IRON, Vector3.ZERO, 8, 0.08)
		Kit.cyl(g, 0.12, 0.08, Vector3(0, h + 0.42, 0), IRON, Vector3.ZERO, 8, 0.15)
		Kit.ball(g, 0.23, Vector3(0, h + 0.68, 0), Kit.flat(GLOBE, 1.8), 10)
		Kit.cyl(g, 0.06, 0.08, Vector3(0, h + 0.94, 0), IRON, Vector3.ZERO, 6, 0.02)
		Kit.omni(g, Vector3(0, h + 0.75, 0.2), WARM, 2.3, 6.0)
	elif top == "cap":
		Kit.box(g, Vector3(0.46, 0.08, 0.46), Vector3(0, h + 0.22, 0), STONE)
	else:
		Kit.box(g, Vector3(0.32, 0.12, 0.32), Vector3(0, h + 0.24, 0), STONE)
		Kit.ball(g, 0.2, Vector3(0, h + 0.49, 0), STONE, 10)
	return g


## The stone kerb a railing stands on, from `from` to `to` along u (or v) at `at`.
static func plinth(p: Node3D, b: int, along_u: bool, at: float, from: float, to: float) -> void:
	# a little longer than the railing, so its ends run into the piers and never
	# lie flush with the rail ends
	p.slab(p.node_of(b), along_u, at, from - 0.03, to + 0.03, 0.0, 0.22, 0.32, Kit.tex("block_plain", 0.9, STONE, true, Color(0.84, 0.8, 0.72)))
	p.slab(p.node_of(b), along_u, at, from - 0.03, to + 0.03, 0.22, 0.27, 0.22, STONE.darkened(0.06))


## One leaf of an iron gate, hinged at `pos` and running along the group's +x
## for `length`: rails, bars with gilt spear tips, a ring in the middle.
static func gate_leaf(parent: Node3D, pos: Vector3, yaw: float, length: float, h := 1.25) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.05, h + 0.1, 0.05), Vector3(0.025, (h + 0.1) * 0.5, 0), IRON)
	Kit.box(g, Vector3(0.05, h, 0.05), Vector3(length - 0.025, h * 0.5, 0), IRON)
	for y: float in [0.12, h * 0.42, h - 0.12]:
		Kit.box(g, Vector3(length - 0.1, 0.045, 0.035), Vector3(length * 0.5, y, 0), IRON)
	var n := maxi(int(length / 0.13), 2)
	for i in range(1, n):
		var x := length * float(i) / float(n)
		Kit.cyl(g, 0.012, h, Vector3(x, h * 0.5, 0), IRON, Vector3.ZERO, 5)
		Kit.cyl(g, 0.032, 0.11, Vector3(x, h + 0.05, 0), GILT, Vector3.ZERO, 4, 0.0)
	Kit.ring(g, 0.17, 0.025, Vector3(length * 0.5, h * 0.7, 0), IRON)
	Kit.ball(g, 0.05, Vector3(length * 0.5, h * 0.7, 0), GILT, 6)
	return g


## A pair of gates shut across a gateway from a to b (along u, or along v) at
## `at`, with a chain and padlock: the gateway takes floor.
static func shut_gates(p: Node3D, b: int, along_u: bool, at: float, a: float, bb: float) -> void:
	var n: Node3D = p.node_of(b)
	var half := (bb - a) * 0.5
	if along_u:
		gate_leaf(n, p.pt(a, at), 0.0, half)
		gate_leaf(n, p.pt(bb, at), 180.0, half)
		p.block(a, at - 0.05, bb, at + 0.05)
	else:
		gate_leaf(n, p.pt(at, a), -90.0, half)
		gate_leaf(n, p.pt(at, bb), 90.0, half)
		p.block(at - 0.05, a, at + 0.05, bb)
	var mid: Vector3 = p.pt((a + bb) * 0.5, at) if along_u else p.pt(at, (a + bb) * 0.5)
	var lock := Kit.group(n, mid, Vector3(0, 0 if along_u else 90, 0))
	for i in 3:
		Kit.ring(lock, 0.05, 0.012, Vector3(0, 0.62 - i * 0.07, 0.04), Props.STEEL, Vector3(0, 0, 90.0 * (i % 2)))
	Kit.box(lock, Vector3(0.08, 0.09, 0.03), Vector3(0, 0.44, 0.05), Color(0.75, 0.6, 0.25))


## The iron arch over a gateway from u0 to u1 at v: two posts, a name board
## over the way in, a curve of iron over that and a gilt finial.
static func gate_arch(p: Node3D, b: int, u0: float, u1: float, v: float, title: String) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt((u0 + u1) * 0.5, v), Vector3.ZERO)
	var half := (u1 - u0) * 0.5
	var low := 3.12                     # the underside of the board: above the game camera
	var green := Color(0.1, 0.3, 0.22)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.07, low + 0.62, 0.07), Vector3(s * (half - 0.035), (low + 0.62) * 0.5, 0), IRON)
		Kit.ring(g, 0.16, 0.025, Vector3(s * (half - 0.26), low - 0.2, 0), IRON)
		Kit.ball(g, 0.065, Vector3(s * (half - 0.035), low + 0.68, 0), GILT, 6)
		# a globe lantern hung out from each post over the pier, higher than
		# the camera's line to him
		var x := s * (half + 0.3)
		Kit.box(g, Vector3(0.4, 0.04, 0.04), Vector3(s * (half + 0.15), low + 0.62, 0), IRON)
		Kit.cyl(g, 0.015, 0.1, Vector3(x, low + 0.57, 0), IRON, Vector3.ZERO, 5)
		Kit.cyl(g, 0.1, 0.07, Vector3(x, low + 0.53, 0), IRON, Vector3.ZERO, 8, 0.03)
		Kit.ball(g, 0.17, Vector3(x, low + 0.34, 0), Kit.flat(GLOBE, 1.8), 10)
	Kit.omni(g, Vector3(0, low - 0.4, 0.6), WARM, 3.6, 6.5)
	Kit.box(g, Vector3(half * 2.0 - 0.1, 0.46, 0.05), Vector3(0, low + 0.23, 0), green)
	Kit.box(g, Vector3(half * 2.0 - 0.12, 0.04, 0.08), Vector3(0, low + 0.015, 0), GILT)
	Kit.box(g, Vector3(half * 2.0 - 0.12, 0.04, 0.08), Vector3(0, low + 0.45, 0), GILT)
	var words := Props.words(g, title, Vector3(0, low + 0.24, 0.032), 0.21, GILT)
	words.double_sided = false
	# the curve over it
	var last := Vector3(-half + 0.035, low + 0.46, 0)
	for i in range(1, 11):
		var t := PI * float(i) / 10.0
		var at := Vector3(-cos(t) * (half - 0.035), low + 0.46 + sin(t) * 0.5, 0)
		strut(g, last, at, 0.045, IRON)
		last = at
	for x: float in [-0.5, 0.0, 0.5]:
		Kit.box(g, Vector3(0.025, 0.5 - absf(x) * 0.5, 0.025), Vector3(x, low + 0.46 + (0.5 - absf(x) * 0.5) * 0.5, 0), IRON)
	Kit.ball(g, 0.09, Vector3(0, low + 1.0, 0), GILT, 8)
	Kit.cyl(g, 0.025, 0.3, Vector3(0, low + 1.2, 0), GILT, Vector3.ZERO, 5, 0.004)
	return g


## A painted board on two posts: a heading and a few lines of small letters.
## Built into `parent` at `at` (the middle of its foot), facing `yaw`.
static func notice_board(parent: Node3D, at: Vector3, yaw: float, w: float, hgt: float, heading: String, lines: Array, look := Color(0.1, 0.3, 0.22), ink := Color(0.96, 0.92, 0.8), y0 := 0.85, size := 0.13) -> Node3D:
	var g := Kit.group(parent, at, Vector3(0, yaw, 0))
	for x: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
		Kit.box(g, Vector3(0.07, y0 + hgt + 0.08, 0.07), Vector3(x, (y0 + hgt + 0.08) * 0.5, -0.055), IRON)
	Kit.box(g, Vector3(w, hgt, 0.05), Vector3(0, y0 + hgt * 0.5, 0), look)
	Kit.box(g, Vector3(w - 0.08, 0.025, 0.06), Vector3(0, y0 + hgt - 0.28, 0), GILT)
	Kit.box(g, Vector3(w + 0.1, 0.07, 0.12), Vector3(0, y0 + hgt + 0.035, 0.0), look.darkened(0.35))
	var head := Props.words(g, heading, Vector3(0, y0 + hgt - 0.14, 0.03), size, ink)
	head.double_sided = false
	for i in lines.size():
		var line := Props.words(g, lines[i], Vector3(0, y0 + hgt - 0.42 - i * 0.15, 0.03), 0.085, ink, 0.0, false)
		line.double_sided = false
	return g


## A clipped hedge filling u0..u1, v0..v1, h high.
static func hedge(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, h := 0.8) -> Node3D:
	var w := u1 - u0
	var d := v1 - v0
	var g: Node3D = p.prop(b, (u0 + u1) * 0.5, (v0 + v1) * 0.5, 0.0, w, d)
	Kit.box(g, Vector3(w, h - 0.08, d), Vector3(0, (h - 0.08) * 0.5, 0), Kit.tex("stucco", 0.8, LEAF, true, Color(0.3, 0.6, 0.3)))
	Kit.box(g, Vector3(w - 0.08, 0.1, d - 0.08), Vector3(0, h - 0.06, 0), Kit.tex("stucco", 0.8, LEAF, true, Color(0.4, 0.74, 0.36)))
	return g


## A clipped evergreen in a square stone planter. kind: "cone", "ball" (a ball
## on a stem) or "tiers" (three balls, one on another).
static func topiary(p: Node3D, b: int, u: float, v: float, kind := "cone", size := 1.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.66 * size, 0.66 * size)
	var leaf := Kit.tex("stucco", 0.7, LEAF, false, Color(0.28, 0.58, 0.3))
	Kit.box(g, Vector3(0.58 * size, 0.42, 0.58 * size), Vector3(0, 0.21, 0), STONE.darkened(0.04))
	Kit.box(g, Vector3(0.66 * size, 0.06, 0.66 * size), Vector3(0, 0.45, 0), STONE)
	match kind:
		"cone":
			Kit.cyl(g, 0.36 * size, 1.55 * size, Vector3(0, 0.48 + 0.775 * size, 0), leaf, Vector3.ZERO, 8, 0.03)
		"ball":
			Kit.cyl(g, 0.045, 0.7 * size, Vector3(0, 0.48 + 0.35 * size, 0), Color(0.36, 0.26, 0.18), Vector3.ZERO, 6)
			Kit.ball(g, 0.42 * size, Vector3(0, 0.48 + 0.95 * size, 0), leaf, 10)
		_:
			for i in 3:
				var r := (0.36 - i * 0.08) * size
				Kit.ball(g, r, Vector3(0, 0.48 + (0.3 + i * 0.55) * size, 0), leaf, 9)
	return g


## A clump of flowers: a mound of leaves with heads of one colour on it.
static func blooms(parent: Node3D, at: Vector3, colour: Color, size := 1.0, key := 0.0) -> void:
	var mound := Kit.ball(parent, 0.2 * size, at + Vector3(0, 0.07 * size, 0), LEAF.lightened(Props.rnd(key) * 0.18), 7)
	mound.scale = Vector3(1.0, 0.72, 1.0)
	for i in 4:
		var a := key * 3.0 + i * 1.7
		var off := Vector3(cos(a), 0, sin(a)) * 0.12 * size * (0.35 + Props.rnd(key + i))
		Kit.ball(parent, 0.068 * size, at + off + Vector3(0, 0.19 * size + Props.rnd(key * 2.0 + i) * 0.06, 0), Kit.flat(colour, 0.15), 6)


## A raised bed of flowers inside a low stone edge, filling u0..u1, v0..v1:
## rows of one colour each. Walked round.
static func flower_bed(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, key := 0.0, palette := BLOOMS, edge := STONE) -> Node3D:
	var w := u1 - u0
	var d := v1 - v0
	var g: Node3D = p.prop(b, (u0 + u1) * 0.5, (v0 + v1) * 0.5, 0.0, w, d)
	var t := 0.14
	Kit.box(g, Vector3(t, 0.24, d), Vector3(-w * 0.5 + t * 0.5, 0.12, 0), edge)
	Kit.box(g, Vector3(t, 0.24, d), Vector3(w * 0.5 - t * 0.5, 0.12, 0), edge)
	Kit.box(g, Vector3(w - 2.0 * t, 0.24, t), Vector3(0, 0.12, -d * 0.5 + t * 0.5), edge)
	Kit.box(g, Vector3(w - 2.0 * t, 0.24, t), Vector3(0, 0.12, d * 0.5 - t * 0.5), edge)
	Kit.box(g, Vector3(w - 2.0 * t - 0.004, 0.18, d - 2.0 * t - 0.004), Vector3(0, 0.09, 0), SOIL)
	var cols := maxi(int((w - 0.3) / 0.48), 1)
	var rows := maxi(int((d - 0.3) / 0.48), 1)
	for r in rows:
		var colour: Color = palette[int(Props.rnd(key + r * 1.31) * palette.size()) % palette.size()]
		for c in cols:
			var x := -w * 0.5 + 0.15 + (c + 0.5) * (w - 0.3) / cols + (Props.rnd(key + r * 7.0 + c) - 0.5) * 0.08
			var z := -d * 0.5 + 0.15 + (r + 0.5) * (d - 0.3) / rows
			blooms(g, Vector3(x, 0.18, z), colour, 1.0, key + r * 5.0 + c)
	return g


## A round bed of flowers with a stone edge, rings of colour round a middle.
static func round_bed(p: Node3D, b: int, u: float, v: float, r := 1.2, key := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.1, 0.1, false)
	block_round(p, u, v, r)
	Kit.cyl(g, r, 0.24, Vector3(0, 0.12, 0), STONE, Vector3.ZERO, 16)
	Kit.cyl(g, r - 0.12, 0.04, Vector3(0, 0.25, 0), SOIL, Vector3.ZERO, 16)
	var ring := 0
	var rr := r - 0.32
	while rr > 0.2:
		var n := maxi(int(TAU * rr / 0.45), 1)
		var colour: Color = BLOOMS[int(Props.rnd(key + ring * 2.3) * BLOOMS.size()) % BLOOMS.size()]
		for i in n:
			var a := TAU * float(i) / float(n) + ring * 0.4
			blooms(g, Vector3(sin(a) * rr, 0.26, cos(a) * rr), colour, 1.0, key + ring * 9.0 + i)
		rr -= 0.42
		ring += 1
	blooms(g, Vector3(0, 0.26, 0), BLOOMS[int(Props.rnd(key + 7.7) * BLOOMS.size()) % BLOOMS.size()], 1.3, key + 99.0)
	return g


## A litter basket on a post.
static func basket(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.46, 0.46)
	Kit.cyl(g, 0.045, 0.4, Vector3(0, 0.2, 0), IRON, Vector3.ZERO, 6)
	Kit.cyl(g, 0.21, 0.55, Vector3(0, 0.65, 0), Color(0.14, 0.32, 0.24), Vector3.ZERO, 10, 0.25)
	Kit.cyl(g, 0.26, 0.04, Vector3(0, 0.94, 0), IRON, Vector3.ZERO, 10)
	Kit.box(g, Vector3(0.18, 0.08, 0.1), Vector3(0.04, 0.99, 0.02), Props.PAPER, Vector3(0, 30, 12))
	return g


## A drinking fountain on a fluted iron pedestal.
static func drinking_fountain(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	var green := Color(0.16, 0.42, 0.33)
	Kit.cyl(g, 0.24, 0.1, Vector3(0, 0.05, 0), STONE, Vector3.ZERO, 8)
	Kit.cyl(g, 0.13, 0.72, Vector3(0, 0.46, 0), green, Vector3.ZERO, 8, 0.09)
	Kit.cyl(g, 0.12, 0.06, Vector3(0, 0.83, 0), GILT, Vector3.ZERO, 8)
	Kit.cyl(g, 0.3, 0.13, Vector3(0, 0.92, 0), green, Vector3.ZERO, 12, 0.34)
	Kit.cyl(g, 0.3, 0.02, Vector3(0, 0.982, 0), Kit.flat(Color(0.5, 0.75, 0.85), 0.2), Vector3.ZERO, 12)
	Kit.cyl(g, 0.02, 0.14, Vector3(0, 1.05, 0), Props.STEEL, Vector3.ZERO, 5)
	Kit.box(g, Vector3(0.12, 0.03, 0.03), Vector3(0.05, 1.12, 0), Props.STEEL)
	return g


## A charcoal grill on a post, by the picnic tables.
static func grill(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.62, 0.46)
	Kit.cyl(g, 0.05, 0.72, Vector3(0, 0.36, 0), IRON, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.62, 0.2, 0.44), Vector3(0, 0.82, 0), Color(0.16, 0.16, 0.17))
	for i in 6:
		Kit.box(g, Vector3(0.012, 0.012, 0.42), Vector3(-0.25 + i * 0.1, 0.935, 0), Props.STEEL)
	Kit.box(g, Vector3(0.56, 0.2, 0.03), Vector3(0, 1.02, -0.22), Color(0.16, 0.16, 0.17), Vector3(-20, 0, 0))
	return g


## A wooden picnic table with its benches joined on, on A-frame legs. Its long
## side runs across `yaw`.
static func picnic_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.7, 0.48, 0.28), key := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.9, 1.62)
	var dark := look.darkened(0.22)
	for z: float in [-0.26, 0.0, 0.26]:
		Kit.box(g, Vector3(1.9, 0.05, 0.24), Vector3(0, 0.75, z), look)
	for s: float in [-1.0, 1.0]:
		for z: float in [0.56, 0.71]:
			Kit.box(g, Vector3(1.9, 0.045, 0.14), Vector3(0, 0.45, s * z), look)
	for x: float in [-0.66, 0.66]:
		for s: float in [-1.0, 1.0]:
			strut(g, Vector3(x, 0.0, s * 0.74), Vector3(x, 0.73, s * 0.18), 0.07, dark)
		Kit.box(g, Vector3(0.07, 0.07, 1.56), Vector3(x, 0.39, 0), dark)
		Kit.box(g, Vector3(0.07, 0.06, 0.74), Vector3(x, 0.695, 0), dark)
	# a soda can and a paper bag somebody left
	if Props.rnd(key) > 0.3:
		Kit.cyl(g, 0.034, 0.12, Vector3(0.34, 0.835, 0.06), Color(0.85, 0.15, 0.15), Vector3.ZERO, 8)
		Kit.box(g, Vector3(0.18, 0.2, 0.12), Vector3(-0.4, 0.875, -0.05), Color(0.78, 0.64, 0.42), Vector3(0, 18, 0))
	return g


## A stone chess table with its board, a game left half-played, and a stone
## stool at each end.
static func chess_table(p: Node3D, b: int, u: float, v: float, key := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 2.0, 0.86)
	var conc := Color(0.72, 0.7, 0.66)
	Kit.cyl(g, 0.18, 0.7, Vector3(0, 0.35, 0), conc, Vector3.ZERO, 8, 0.13)
	Kit.box(g, Vector3(0.86, 0.08, 0.86), Vector3(0, 0.74, 0), conc.lightened(0.12))
	Kit.box(g, Vector3(0.58, 0.01, 0.58), Vector3(0, 0.785, 0), Color(0.22, 0.2, 0.19))
	Kit.box(g, Vector3(0.52, 0.012, 0.52), Vector3(0, 0.786, 0), Kit.tex("lino", 0.26, Color(0.6, 0.6, 0.6), false, Color(0.8, 0.76, 0.7)))
	for i in 9:
		var white := i % 2 == 0
		var x := -0.22 + Props.rnd(key + i * 3.3) * 0.44
		var z := (-0.2 + Props.rnd(key + i * 5.1) * 0.12) * (1.0 if white else -1.0)
		var colour := Color(0.95, 0.93, 0.86) if white else Color(0.12, 0.11, 0.12)
		var tall := 0.04 + Props.rnd(key + i * 1.9) * 0.05
		Kit.cyl(g, 0.02, tall, Vector3(x, 0.792 + tall * 0.5, z), colour, Vector3.ZERO, 6, 0.012)
		Kit.ball(g, 0.017, Vector3(x, 0.8 + tall, z), colour, 6)
	for s: float in [-1.0, 1.0]:      # the stools: a stem, a round seat on it
		Kit.cyl(g, 0.17, 0.38, Vector3(s * 0.78, 0.19, 0), conc, Vector3.ZERO, 8, 0.12)
		Kit.cyl(g, 0.22, 0.07, Vector3(s * 0.78, 0.415, 0), conc.lightened(0.12), Vector3.ZERO, 10)
	return g


## The bandstand: an eight-sided brick base with steps up the front, white
## iron columns and railings, a green roof with a lantern and a gilt finial,
## a string of bulbs round the eaves and a lamp inside. (u, v) is its middle;
## the steps face the street. Walked round, never on.
static func bandstand(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.1, 0.1, false)
	var apo := 2.6                     # the middle to the flat of the stone lip
	for hw: Array in [[apo, apo * 0.414], [apo * 0.9, apo * 0.5], [apo * 0.707, apo * 0.707], [apo * 0.5, apo * 0.9], [apo * 0.414, apo]]:
		p.block(u - hw[0], v - hw[1], u + hw[0], v + hw[1])
	p.block(u - 0.9, v + apo - 0.2, u + 0.9, v + apo + 0.92)          # the steps
	var brick := Kit.tex("brick", 0.9, Color(0.6, 0.3, 0.22), false, Color(1.0, 0.85, 0.8))
	var white := Color(0.95, 0.94, 0.89)
	var green := Color(0.14, 0.46, 0.36)
	var turn := Vector3(0, 22.5, 0)    # the eight sides square to the plan: one faces the street
	var deck := 0.66
	Kit.cyl(g, 2.72, 0.56, Vector3(0, 0.28, 0), brick, turn, 8)
	Kit.cyl(g, 2.82, 0.08, Vector3(0, 0.58, 0), STONE, turn, 8)
	Kit.cyl(g, 2.66, 0.04, Vector3(0, 0.64, 0), Color(0.74, 0.54, 0.34), turn, 8)
	for i in 3:
		var top := 0.165 * (i + 1)
		var reach := 0.3 * (3 - i)
		Kit.box(g, Vector3(1.7, top, reach + 0.4), Vector3(0, top * 0.5, apo + reach * 0.5 - 0.2), STONE.darkened(0.05))
	# the columns at the eight corners
	var rc := 2.45
	for k in 8:
		var a := deg_to_rad(22.5 + 45.0 * k)
		var at := Vector3(sin(a), 0, cos(a)) * rc
		Kit.cyl(g, 0.11, 0.16, at + Vector3(0, deck + 0.08, 0), white, Vector3.ZERO, 8)
		Kit.cyl(g, 0.062, 2.5, at + Vector3(0, deck + 1.33, 0), white, Vector3.ZERO, 8)
		Kit.cyl(g, 0.1, 0.12, at + Vector3(0, deck + 2.56, 0), white, Vector3.ZERO, 8, 0.13)
	# each side between them: a railing (not the front, where the steps come up) and an iron frieze at the top
	var flat := rc * cos(deg_to_rad(22.5))
	var span := 2.0 * rc * sin(deg_to_rad(22.5)) - 0.14
	for k in 8:
		var s := Kit.group(g, Vector3.ZERO, Vector3(0, 45.0 * k, 0))
		if k != 0:
			Kit.box(s, Vector3(span, 0.07, 0.1), Vector3(0, deck + 0.95, flat), white)
			Kit.box(s, Vector3(span, 0.05, 0.06), Vector3(0, deck + 0.12, flat), white)
			for i in 7:
				Kit.box(s, Vector3(0.04, 0.76, 0.04), Vector3(-span * 0.5 + (i + 0.5) * span / 7.0, deck + 0.525, flat), white)
		else:
			Kit.box(s, Vector3(span, 0.04, 0.05), Vector3(0, deck + 0.02, flat), white)
		Kit.box(s, Vector3(span, 0.05, 0.06), Vector3(0, deck + 2.3, flat), white)
		for i in 11:
			Kit.box(s, Vector3(0.025, 0.24, 0.025), Vector3(-span * 0.5 + (i + 0.5) * span / 11.0, deck + 2.45, flat), white)
		for e: float in [-1.0, 1.0]:
			strut(s, Vector3(e * span * 0.5, deck + 2.05, flat), Vector3(e * (span * 0.5 - 0.3), deck + 2.32, flat), 0.035, white)
	# the fascia, its gilt line and the boarded ceiling under it
	var eave := deck + 2.62
	Kit.cyl(g, 2.62, 0.02, Vector3(0, eave - 0.005, 0), Color(0.96, 0.9, 0.76), turn, 8)
	Kit.cyl(g, 2.76, 0.3, Vector3(0, eave + 0.15, 0), green, turn, 8)
	Kit.cyl(g, 2.785, 0.05, Vector3(0, eave + 0.07, 0), GILT, turn, 8)
	# the roof: eight sides rising to a lantern, a white rib down each corner
	var roof := eave + 0.3
	var rise := 1.6
	var edge := 3.2
	Kit.cyl(g, edge, rise, Vector3(0, roof + rise * 0.5, 0), green, turn, 8, 0.0)
	for k in 8:
		var a := deg_to_rad(22.5 + 45.0 * k)
		var out := Vector3(sin(a), 0, cos(a))
		strut(g, out * edge + Vector3(0, roof + 0.03, 0), Vector3(0, roof + rise + 0.03, 0), 0.08, white)
	var lantern := roof + rise * 0.72
	Kit.cyl(g, 0.46, 0.5, Vector3(0, lantern + 0.25, 0), white, turn, 8)
	Kit.cyl(g, 0.47, 0.2, Vector3(0, lantern + 0.27, 0), Kit.flat(GLOBE, 1.3), turn, 8)
	Kit.cyl(g, 0.64, 0.5, Vector3(0, lantern + 0.75, 0), green, turn, 8, 0.0)
	Kit.ball(g, 0.11, Vector3(0, lantern + 1.06, 0), GILT, 8)
	Kit.cyl(g, 0.026, 0.4, Vector3(0, lantern + 1.3, 0), GILT, Vector3.ZERO, 5, 0.004)
	# bulbs strung round the eaves
	var bulb := Kit.flat(Color(1.0, 0.86, 0.45), 2.4)
	var ring := edge * cos(deg_to_rad(22.5)) - 0.08
	for k in 8:
		var s := Kit.group(g, Vector3.ZERO, Vector3(0, 45.0 * k, 0))
		for i in 5:
			Kit.ball(s, 0.055, Vector3(-1.0 + i * 0.5, roof - 0.07, ring), bulb, 6)
	# the lamp inside, high under the ceiling, and its light
	Kit.cyl(g, 0.012, 0.12, Vector3(0, eave - 0.07, 0), IRON, Vector3.ZERO, 5)
	Kit.ball(g, 0.13, Vector3(0, eave - 0.2, 0), Kit.flat(GLOBE, 2.0), 10)
	Kit.omni(g, Vector3(0, eave - 0.6, 0), WARM, 3.6, 6.5)
	# chairs and a music stand the band left behind
	for c: Array in [[-0.9, -1.1, 20.0], [0.5, -1.4, -15.0], [1.4, -0.5, -60.0]]:
		var ch := Kit.group(g, Vector3(c[0], deck, c[1]), Vector3(0, c[2], 0))
		Kit.box(ch, Vector3(0.4, 0.04, 0.4), Vector3(0, 0.45, 0), Color(0.6, 0.62, 0.64))
		Kit.box(ch, Vector3(0.4, 0.3, 0.03), Vector3(0, 0.72, -0.19), Color(0.6, 0.62, 0.64))
		for x: float in [-0.17, 0.17]:
			Kit.box(ch, Vector3(0.025, 0.45, 0.025), Vector3(x, 0.225, 0.17), IRON)
			Kit.box(ch, Vector3(0.025, 0.87, 0.025), Vector3(x, 0.435, -0.19), IRON)
	var stand := Kit.group(g, Vector3(-0.3, deck, -0.2), Vector3(0, 200, 0))
	Kit.cyl(stand, 0.012, 1.1, Vector3(0, 0.55, 0), IRON, Vector3.ZERO, 5)
	Kit.box(stand, Vector3(0.48, 0.34, 0.02), Vector3(0, 1.15, 0.02), IRON, Vector3(-20, 0, 0))
	Kit.box(stand, Vector3(0.4, 0.28, 0.01), Vector3(0, 1.16, 0.04), Props.PAPER, Vector3(-20, 0, 0))
	return g


## A round pond with a stone kerb, a little fountain playing in the middle,
## lily pads and two ducks. Walked round.
static func pond(p: Node3D, b: int, u: float, v: float, r := 2.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.1, 0.1, false)
	block_round(p, u, v, r)
	var n := 18
	var chord := 2.0 * r * sin(PI / n)
	for i in n:
		var s := Kit.group(g, Vector3.ZERO, Vector3(0, 360.0 * i / n + 5.0, 0))
		Kit.box(s, Vector3(chord, 0.38, 0.3), Vector3(0, 0.19, r - 0.15), Kit.tex("block_plain", 0.8, STONE, false, Color(0.8, 0.76, 0.68)))
		Kit.box(s, Vector3(chord + 0.07, 0.07, 0.4), Vector3(0, 0.415, r - 0.15), STONE)
	var water := Kit.flat(Color(0.14, 0.4, 0.56), 0.18)
	Kit.cyl(g, r - 0.24, 0.06, Vector3(0, 0.27, 0), water, Vector3.ZERO, 24)
	for i in 9:
		var a := Props.rnd(u + i * 2.1) * TAU
		var d := 0.95 + Props.rnd(v + i * 1.3) * (r - 1.45)
		var pad_r := 0.17 + Props.rnd(i * 4.7 + u) * 0.1
		Kit.cyl(g, pad_r, 0.015, Vector3(sin(a) * d, 0.305, cos(a) * d), Color(0.3, 0.6, 0.28), Vector3(0, a * 50.0, 0), 8)
		if i % 3 == 0:
			Kit.ball(g, 0.06, Vector3(sin(a) * d, 0.34, cos(a) * d), Kit.flat(Color(1.0, 0.6, 0.78), 0.2), 6)
	# the fountain
	Kit.cyl(g, 0.22, 0.6, Vector3(0, 0.5, 0), STONE, Vector3.ZERO, 8)
	Kit.cyl(g, 0.66, 0.16, Vector3(0, 0.86, 0), STONE, Vector3.ZERO, 12, 0.72)
	Kit.cyl(g, 0.64, 0.02, Vector3(0, 0.945, 0), water, Vector3.ZERO, 12)
	var spray := Kit.flat(Color(0.82, 0.95, 1.0, 0.75), 0.7)
	Kit.cyl(g, 0.045, 0.62, Vector3(0, 1.25, 0), spray, Vector3.ZERO, 6)
	Kit.ball(g, 0.14, Vector3(0, 1.58, 0), spray, 8)
	Kit.cyl(g, 0.78, 0.6, Vector3(0, 0.63, 0), Kit.flat(Color(0.8, 0.94, 1.0, 0.3), 0.4), Vector3.ZERO, 14, 0.68)
	# two ducks
	for d: Array in [[1.2, 0.9, 40.0, Color(0.96, 0.95, 0.9)], [-0.9, 1.5, 200.0, Color(0.55, 0.42, 0.3)]]:
		var duck := Kit.group(g, Vector3(d[0], 0.3, d[1]), Vector3(0, d[2], 0))
		var body := Kit.ball(duck, 0.13, Vector3(0, 0.07, 0), d[3], 8)
		body.scale = Vector3(1.0, 0.72, 1.45)
		Kit.ball(duck, 0.075, Vector3(0, 0.2, 0.15), d[3] if d[3].r > 0.9 else Color(0.15, 0.4, 0.25), 7)
		Kit.box(duck, Vector3(0.05, 0.03, 0.08), Vector3(0, 0.19, 0.24), Color(1.0, 0.6, 0.12))
	return g


## A stepping stone: a flat grey stone set in the lawn. People walk on it.
static func stepping_stone(p: Node3D, b: int, u: float, v: float, r := 0.28, key := 0.0) -> void:
	var g: Node3D = p.prop(b, u, v, Props.rnd(key) * 90.0, 0.1, 0.1, false)
	var s := Kit.cyl(g, r, 0.04, Vector3(0, 0.005, 0), Color(0.66, 0.64, 0.6).darkened(Props.rnd(key + 1.0) * 0.1), Vector3.ZERO, 7)
	s.scale = Vector3(1.0, 1.0, 0.75 + Props.rnd(key + 2.0) * 0.25)


# ------------------------------------------------------------- the playground

## A swing set: two blue A-frames, a yellow top bar, n seats on chains (the
## first one still moving).
static func swings(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 2, w := 3.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w + 0.5, 1.9)
	var top := 2.3
	for x: float in [-w * 0.5, w * 0.5]:
		for s: float in [-1.0, 1.0]:
			strut(g, Vector3(x, 0.0, s * 0.82), Vector3(x, top, s * 0.05), 0.1, PLAY[3])
		Kit.box(g, Vector3(0.06, 0.06, 1.1), Vector3(x, 0.9, 0), PLAY[3])
	Kit.cyl(g, 0.07, w + 0.3, Vector3(0, top, 0), PLAY[1], Vector3(0, 0, 90), 8)
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		var hang := Kit.group(g, Vector3(x, top, 0), Vector3(-16.0 if i == 0 else 0.0, 0, 0))
		for s: float in [-0.21, 0.21]:
			Kit.cyl(hang, 0.012, 1.8, Vector3(s, -0.9, 0), Props.STEEL, Vector3.ZERO, 4)
			Kit.ring(hang, 0.04, 0.012, Vector3(s, -0.03, 0), Props.STEEL)
		Kit.box(hang, Vector3(0.52, 0.05, 0.2), Vector3(0, -1.82, 0), Color(0.12, 0.12, 0.14))
	return g


## A slide: a tower on four blue posts with a yellow deck, a ladder at the back
## and a red chute running forward (+v) to the ground. (u, v) is the tower.
static func slide(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.1, 0.1, false)
	p.block(u - 0.68, v - 1.5, u + 0.68, v + 0.66)
	p.block(u - 0.38, v + 0.66, u + 0.38, v + 4.05)
	var deck := 1.5
	for x: float in [-0.56, 0.56]:
		for z: float in [-0.56, 0.56]:
			Kit.cyl(g, 0.06, 2.62, Vector3(x, 1.31, z), PLAY[3], Vector3.ZERO, 8)
			Kit.ball(g, 0.08, Vector3(x, 2.66, z), PLAY[1], 7)
	Kit.box(g, Vector3(1.24, 0.08, 1.24), Vector3(0, deck, 0), PLAY[1])
	for x: float in [-0.6, 0.6]:
		Kit.box(g, Vector3(0.05, 0.62, 1.0), Vector3(x, deck + 0.41, 0), PLAY[1])
		Kit.cyl(g, 0.17, 0.06, Vector3(x * 1.01, deck + 0.44, 0), PLAY[0], Vector3(0, 0, 90), 12)
	Kit.box(g, Vector3(1.0, 0.62, 0.05), Vector3(0, deck + 0.41, -0.6), PLAY[1])
	Kit.box(g, Vector3(1.32, 0.08, 1.32), Vector3(0, 2.62, 0), PLAY[0])
	Kit.cyl(g, 0.95, 0.55, Vector3(0, 2.94, 0), PLAY[0], Vector3(0, 45, 0), 4, 0.0)
	Kit.ball(g, 0.08, Vector3(0, 3.26, 0), PLAY[1], 7)
	# the ladder, at the back
	for x: float in [-0.3, 0.3]:
		strut(g, Vector3(x, 0.0, -1.42), Vector3(x, deck + 0.05, -0.62), 0.06, Props.STEEL)
	for i in 5:
		var t := (i + 1) / 6.0
		Kit.cyl(g, 0.022, 0.6, Vector3(0, t * deck, -1.42 + t * 0.8), Props.STEEL, Vector3(0, 0, 90), 6)
	# the chute
	var from := Vector3(0, deck + 0.04, 0.6)
	var to := Vector3(0, 0.34, 3.45)
	var run := Kit.group(g, (from + to) * 0.5, Vector3.ZERO)
	run.basis = Basis.looking_at(to - from, Vector3.UP)
	var length := from.distance_to(to)
	Kit.box(run, Vector3(0.56, 0.04, length), Vector3.ZERO, PLAY[0])
	for x: float in [-0.29, 0.29]:
		Kit.box(run, Vector3(0.04, 0.2, length), Vector3(x, 0.08, 0), PLAY[0].darkened(0.12))
	Kit.box(g, Vector3(0.56, 0.04, 0.6), Vector3(0, 0.34, 3.75), PLAY[0])
	for x: float in [-0.29, 0.29]:
		Kit.box(g, Vector3(0.04, 0.2, 0.62), Vector3(x, 0.42, 3.75), PLAY[0].darkened(0.12))
		Kit.box(g, Vector3(0.05, 0.32, 0.05), Vector3(x, 0.16, 3.95), Props.STEEL)
	return g


## A roundabout: a red disc on a pivot with handle bars round a middle post.
static func roundabout(p: Node3D, b: int, u: float, v: float, turn := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 2.1, 2.1)
	Kit.cyl(g, 0.3, 0.2, Vector3(0, 0.1, 0), Props.IRON, Vector3.ZERO, 10)
	var top := Kit.group(g, Vector3.ZERO, Vector3(0, turn, 0))
	Kit.cyl(top, 1.0, 0.08, Vector3(0, 0.26, 0), PLAY[0], Vector3.ZERO, 18)
	Kit.cyl(top, 1.02, 0.03, Vector3(0, 0.235, 0), Props.STEEL, Vector3.ZERO, 18)
	for k in 4:
		Kit.box(top, Vector3(0.12, 0.012, 1.94), Vector3(0, 0.306, 0), PLAY[1], Vector3(0, 45.0 * k + 22.5, 0))
	Kit.cyl(top, 0.06, 0.66, Vector3(0, 0.63, 0), PLAY[1], Vector3.ZERO, 8)
	Kit.ball(top, 0.09, Vector3(0, 0.98, 0), PLAY[3], 8)
	for k in 4:
		var arm := Kit.group(top, Vector3.ZERO, Vector3(0, 90.0 * k + 45.0, 0))
		Kit.cyl(arm, 0.025, 0.62, Vector3(0, 0.61, 0.78), PLAY[3], Vector3.ZERO, 6)
		Kit.cyl(arm, 0.025, 0.78, Vector3(0, 0.92, 0.39), PLAY[3], Vector3(90, 0, 0), 6)
	return g


## A climbing frame: a cube of bars, each level its own colour.
static func climbing_frame(p: Node3D, b: int, u: float, v: float, size := 2.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, size, size)
	var half := size * 0.5
	for i in 3:
		for j in 3:
			var at := Vector3(-half + i * half, 0, -half + j * half)
			Kit.cyl(g, 0.038, 1.86, at + Vector3(0, 0.93, 0), PLAY[3], Vector3.ZERO, 6)
			Kit.ball(g, 0.06, at + Vector3(0, 1.88, 0), PLAY[1], 6)
	for k in 3:
		var y := 0.62 + k * 0.62
		for i in 3:
			Kit.cyl(g, 0.03, size, Vector3(-half + i * half, y, 0), PLAY[k], Vector3(90, 0, 0), 6)
			Kit.cyl(g, 0.03, size, Vector3(0, y + 0.012, -half + i * half), PLAY[k], Vector3(0, 0, 90), 6)
	return g


## A spring rider: a little horse on a big spring.
static func spring_rider(p: Node3D, b: int, u: float, v: float, yaw := 0.0, colour := Color(0.99, 0.78, 0.15)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.8)
	Kit.box(g, Vector3(0.42, 0.04, 0.42), Vector3(0, 0.02, 0), Props.IRON)
	for i in 5:
		Kit.ring(g, 0.1, 0.022, Vector3(0, 0.08 + i * 0.075, 0), Props.STEEL, Vector3(-90, 0, 0))
	var horse := Kit.group(g, Vector3(0, 0.44, 0), Vector3(-6, 0, 0))
	Kit.box(horse, Vector3(0.26, 0.26, 0.6), Vector3(0, 0.15, 0), colour)
	Kit.box(horse, Vector3(0.2, 0.34, 0.24), Vector3(0, 0.38, 0.3), colour, Vector3(22, 0, 0))
	Kit.box(horse, Vector3(0.16, 0.12, 0.2), Vector3(0, 0.46, 0.46), colour.lightened(0.15), Vector3(22, 0, 0))
	for x: float in [-0.06, 0.06]:
		Kit.box(horse, Vector3(0.04, 0.1, 0.04), Vector3(x, 0.6, 0.26), colour.darkened(0.2))
		Kit.ball(horse, 0.022, Vector3(x * 1.6, 0.48, 0.38), Color(0.1, 0.1, 0.1), 5)
	Kit.box(horse, Vector3(0.05, 0.3, 0.06), Vector3(0, 0.42, 0.14), PLAY[0])            # the mane
	Kit.box(horse, Vector3(0.3, 0.06, 0.24), Vector3(0, 0.31, -0.04), PLAY[0])           # the seat
	Kit.cyl(horse, 0.02, 0.36, Vector3(0, 0.46, 0.2), Props.STEEL, Vector3(0, 0, 90), 5)  # the handles
	Kit.box(horse, Vector3(0.06, 0.2, 0.06), Vector3(0, 0.2, -0.33), colour.darkened(0.2), Vector3(-30, 0, 0))
	return g


## Hopscotch painted on the ground, the squares numbered: it starts at (u, v)
## and runs back (-v).
static func hopscotch(p: Node3D, b: int, u: float, v: float) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.1, 0.1, false)
	var cells := [[0.0, 0.0], [0.0, -1.0], [-0.5, -2.0], [0.5, -2.0], [0.0, -3.0], [-0.5, -4.0], [0.5, -4.0], [0.0, -5.0]]
	var s := 0.46
	for i in cells.size():
		var at := Vector3(cells[i][0] * s * 1.04, 0.0, cells[i][1] * s * 1.04)
		Kit.box(g, Vector3(s, 0.006, s), at + Vector3(0, 0.024, 0), PLAY[i % 4].lightened(0.25))
		var n := Kit.label(g, str(i + 1), at + Vector3(0, 0.03, 0), 0.26, Color(0.98, 0.97, 0.94), Vector3(-90, 0, 0))
		n.font = Props.FONT


# ------------------------------------------------------- round the square

## A parked car of the time: the street's chunky cars (props_street.gd's
## car_model; `kind` one of its CAR_KINDS). Built into `parent` at `at` (the
## road under it), its front facing `yaw`; it takes no floor (it stands in a
## street nobody walks).
static func sedan(parent: Node3D, at: Vector3, yaw: float, paint: Color, kind := "box_sedan") -> Node3D:
	return Street.car_model(parent, at, yaw, kind, paint)


## One window in a wall's face: a stone surround, the glass (lit or dark), a
## sash bar, a lintel and a sill. (x, y0) is the middle of its foot and z the
## face of the wall it is in.
static func window(g: Node3D, x: float, y0: float, ww: float, wh: float, z: float, lit: bool, key: float, stone := STONE) -> void:
	Kit.box(g, Vector3(ww + 0.18, wh + 0.18, 0.05), Vector3(x, y0 + wh * 0.5, z + 0.025), stone)
	Kit.box(g, Vector3(ww, wh, 0.03), Vector3(x, y0 + wh * 0.5, z + 0.055), Kit.flat(LIT, 0.55) if lit else DARK_GLASS)
	if lit and Props.rnd(key * 1.7 + 0.3) > 0.35:
		var cloth: Color = CURTAINS[int(Props.rnd(key * 3.1) * CURTAINS.size()) % CURTAINS.size()]
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(ww * 0.27, wh - 0.06, 0.01), Vector3(x + s * ww * 0.365, y0 + wh * 0.5 - 0.02, z + 0.076), cloth)
	elif not lit and Props.rnd(key * 2.3) > 0.6:
		Kit.box(g, Vector3(ww - 0.04, wh * 0.45, 0.01), Vector3(x, y0 + wh * 0.76, z + 0.074), Color(0.85, 0.82, 0.72))    # a blind half down
	Kit.box(g, Vector3(ww, 0.05, 0.02), Vector3(x, y0 + wh * 0.52, z + 0.09), SASH)
	Kit.box(g, Vector3(ww + 0.36, 0.2, 0.1), Vector3(x, y0 + wh + 0.19, z + 0.05), stone)
	Kit.box(g, Vector3(ww + 0.3, 0.07, 0.14), Vector3(x, y0 - 0.1, z + 0.07), stone)


## A grand old rowhouse across the street: its front faces +z from `at` (the
## middle of its foot), turned `yaw`, and the house runs `deep` back. A stoop of
## white marble steps up to the door, tall parlour windows, two floors over
## them, a heavy cornice. `key` picks the lit windows. opts: "door_right",
## "bay" (the parlour and the floor over it stand out in a bay), "trim",
## "cornice", "deep", "door".
static func townhouse(parent: Node3D, at: Vector3, yaw: float, w: float, h: float, look: Variant, key: float, opts := {}) -> Node3D:
	var g := Kit.group(parent, at, Vector3(0, yaw, 0))
	var deep: float = opts.get("deep", 10.0)
	var trim: Color = opts.get("trim", STONE)
	var cornice: Color = opts.get("cornice", Color(0.24, 0.22, 0.22))
	var side := 1.0 if opts.get("door_right", false) else -1.0
	var door: Color = opts.get("door", DOORS[int(Props.rnd(key * 1.3) * DOORS.size()) % DOORS.size()])
	var fl := 1.1                                    # the parlour floor: up the steps
	var storey := 3.3
	Kit.box(g, Vector3(w, h, deep), Vector3(0, h * 0.5, -deep * 0.5), look)
	Kit.box(g, Vector3(w - 0.4, 0.05, deep - 0.6), Vector3(0, h + 0.025, -deep * 0.5 - 0.1), Color(0.2, 0.2, 0.22))
	# Everything set on the front starts a little way inside the wall, each kind
	# at its own depth, so no two backs lie flush (seen from the side rows).
	Kit.box(g, Vector3(w - 0.012, fl - 0.02, 0.09), Vector3(0, (fl - 0.02) * 0.5, 0.035), trim.darkened(0.15))
	# the door, up its marble steps, with iron rails
	var xd := side * (w * 0.5 - 1.05)
	Kit.box(g, Vector3(1.5, 2.98, 0.09), Vector3(xd, fl + 1.49, 0.025), trim)
	Kit.box(g, Vector3(1.0, 2.12, 0.05), Vector3(xd, fl + 1.08, 0.085), door)
	for y: float in [0.55, 1.5]:
		Kit.box(g, Vector3(0.7, 0.6, 0.02), Vector3(xd, fl + y, 0.118), door.lightened(0.08))
	Kit.box(g, Vector3(1.0, 0.46, 0.03), Vector3(xd, fl + 2.5, 0.08), Kit.flat(LIT, 0.5))
	Kit.box(g, Vector3(0.04, 0.46, 0.02), Vector3(xd, fl + 2.5, 0.105), SASH)
	Kit.box(g, Vector3(1.8, 0.22, 0.24), Vector3(xd, fl + 3.09, 0.09), trim)
	Kit.ball(g, 0.04, Vector3(xd - side * 0.36, fl + 1.05, 0.13), GILT, 6)
	for i in 5:
		var top := fl * (i + 1) / 5.0
		var reach := 0.3 * (5 - i)
		Kit.box(g, Vector3(1.3, top, reach + 0.04), Vector3(xd, top * 0.5, reach * 0.5 - 0.02), MARBLE)
	for s: float in [-0.68, 0.68]:
		Kit.cyl(g, 0.02, 1.05, Vector3(xd + s, 0.525, 1.42), IRON, Vector3.ZERO, 5)
		Kit.cyl(g, 0.02, 0.9, Vector3(xd + s, fl + 0.45, 0.2), IRON, Vector3.ZERO, 5)
		strut(g, Vector3(xd + s, 1.05, 1.42), Vector3(xd + s, fl + 0.9, 0.2), 0.035, IRON)
		Kit.ball(g, 0.04, Vector3(xd + s, 1.08, 1.42), GILT, 5)
	# the windows: two tall ones on the parlour floor, three on each floor over it
	var x0 := xd + side * -0.9
	var x1 := -side * (w * 0.5 - 0.6)
	var lo := minf(x0, x1)
	var hi := maxf(x0, x1)
	var cols: Array = [lo + (hi - lo) * 0.25, lo + (hi - lo) * 0.75]
	var face := 0.0
	if opts.get("bay", false):
		# the parlour and the floor over it stand out in a bay, down to the ground
		face = 0.65
		var bw := hi - lo + 0.3
		var bx := (lo + hi) * 0.5
		var tall := storey * 2.0 - 0.13
		Kit.box(g, Vector3(bw, fl - 0.02, face + 0.13), Vector3(bx, (fl - 0.02) * 0.5, (face + 0.08 - 0.05) * 0.5), trim.darkened(0.15))
		Kit.box(g, Vector3(bw, tall, face + 0.06), Vector3(bx, fl - 0.02 + tall * 0.5, (face - 0.06) * 0.5), look)
		Kit.box(g, Vector3(bw + 0.12, 0.18, face + 0.17), Vector3(bx, fl + storey * 2.0 - 0.06, (face + 0.1 - 0.07) * 0.5), trim)
	var n := 0
	for c: float in cols:
		window(g, c, fl + 0.5, 1.0, 2.15, face, Props.rnd(key + n) > 0.45, key + n, trim)
		n += 1
		# the basement under it, behind bars
		Kit.box(g, Vector3(0.8, 0.5, 0.03), Vector3(c, 0.5, 0.095 + face), DARK_GLASS)
		for k in 4:
			Kit.cyl(g, 0.012, 0.56, Vector3(c - 0.3 + k * 0.2, 0.5, 0.12 + face), IRON, Vector3.ZERO, 4)
	var floors := 2 if h >= 11.0 else 1
	for f in floors:
		var y0 := fl + storey * (f + 1) + 0.5
		Kit.box(g, Vector3(w - 0.012, 0.16, 0.075), Vector3(0, y0 - 0.62, 0.0225), trim)
		for c: float in [xd] + cols:
			var z := face if (f == 0 and c != xd) else 0.0
			window(g, c, y0, 0.95, 1.75, z, Props.rnd(key + n * 1.7) > 0.5, key + n, trim)
			n += 1
	# the cornice: a deep painted ledge on brackets, over a frieze
	Kit.box(g, Vector3(w - 0.012, 0.5, 0.555), Vector3(0, h - 0.1, 0.2425), cornice)
	Kit.box(g, Vector3(w - 0.012, 0.36, 0.145), Vector3(0, h - 0.53, 0.0475), cornice.lightened(0.12))
	var nb := maxi(int(w / 0.9), 3)
	for i in nb + 1:
		Kit.box(g, Vector3(0.14, 0.44, 0.38), Vector3(-w * 0.5 + 0.12 + (w - 0.24) * i / nb, h - 0.565, 0.2), cornice)
	return g


## The stone church across the back street, its front facing +z from `at` (the
## middle of its foot): a gabled nave with a rose window over red doors, tall
## windows, a square bell tower with a clock and a spire on the left, steps,
## a lamp over the door and the board with this week's notices.
static func church(parent: Node3D, at: Vector3, title: String, lines: Array) -> Node3D:
	var g := Kit.group(parent, at, Vector3.ZERO)
	var stone := Kit.tex("block_plain", 1.4, Color(0.78, 0.74, 0.66), true, Color(0.86, 0.8, 0.7))
	var dark := Kit.tex("block_plain", 1.4, Color(0.62, 0.58, 0.52), true, Color(0.68, 0.64, 0.58))
	var trim := Color(0.9, 0.86, 0.76)
	var slate := Color(0.25, 0.27, 0.34)
	var red := Color(0.64, 0.12, 0.12)
	var glass := [Color(0.95, 0.25, 0.25), Color(0.3, 0.5, 1.0), Color(1.0, 0.8, 0.25), Color(0.3, 0.8, 0.45)]
	var w := 9.0
	var wall_h := 8.0
	var deep := 18.0
	Kit.box(g, Vector3(w, wall_h, deep), Vector3(0, wall_h * 0.5, -deep * 0.5), stone)
	Kit.box(g, Vector3(w + 0.12, 0.55, 0.14), Vector3(0, 0.275, 0.07), dark)
	# the gable over the front, a cross on its point, and the roof behind it
	var rise := 4.6
	var half := w * 0.5 + 0.2
	var r := half / 0.866
	var gable := Kit.cyl(g, r, 0.5, Vector3(0, wall_h + 0.5 * r * rise / (1.5 * r), 0.0), stone, Vector3(-90, 0, 0), 3)
	gable.scale = Vector3(1, 1, rise / (1.5 * r))
	var r2 := (w * 0.5 + 0.5) / 0.866
	var rise2 := rise + 0.15
	var roof := Kit.cyl(g, r2, deep, Vector3(0, wall_h - 0.2 + 0.5 * r2 * rise2 / (1.5 * r2), -deep * 0.5 - 0.1), slate, Vector3(-90, 0, 0), 3)
	roof.scale = Vector3(1, 1, rise2 / (1.5 * r2))
	Kit.box(g, Vector3(0.14, 1.1, 0.14), Vector3(0, wall_h + rise + 0.5, 0.0), trim)
	Kit.box(g, Vector3(0.6, 0.14, 0.14), Vector3(0, wall_h + rise + 0.7, 0.0), trim)
	# a buttress at the right-hand corner (the tower is on the left)
	Kit.box(g, Vector3(0.7, 5.6, 0.9), Vector3(w * 0.5 - 0.05, 2.8, 0.3), dark)
	Kit.box(g, Vector3(0.6, 1.5, 0.7), Vector3(w * 0.5 - 0.05, 6.3, 0.15), dark)
	# steps up to the doors
	for i in 3:
		var top := 0.18 * (i + 1)
		var reach := 0.42 * (3 - i)
		Kit.box(g, Vector3(3.8 - i * 0.3, top, reach), Vector3(0, top * 0.5, reach * 0.5), STONE.darkened(0.08))
	# the doorway: a pointed arch of pale stone, red doors, a glowing light in the point
	var sill := 0.54
	Kit.box(g, Vector3(2.6, 3.0, 0.12), Vector3(0, sill + 1.5, 0.06), trim)
	Kit.box(g, Vector3(1.84, 1.84, 0.12), Vector3(0, sill + 3.0, 0.06), trim, Vector3(0, 0, 45))
	Kit.box(g, Vector3(1.34, 1.34, 0.04), Vector3(0, sill + 2.75, 0.14), red.darkened(0.45), Vector3(0, 0, 45))
	Kit.disc(g, 0.22, Vector3(0, sill + 3.2, 0.17), Kit.flat(glass[2], 1.2), 0.02, 12)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(1.0, 2.75, 0.06), Vector3(s * 0.51, sill + 1.375, 0.15), red)
		for y: float in [0.75, 1.95]:
			Kit.box(g, Vector3(0.7, 0.9, 0.02), Vector3(s * 0.51, sill + y, 0.19), red.lightened(0.1))
		Kit.ring(g, 0.07, 0.018, Vector3(s * 0.12, sill + 1.3, 0.2), IRON)
	# tall pointed windows either side of the doors
	for s: float in [-1.0, 1.0]:
		var x := s * 2.95
		Kit.box(g, Vector3(1.0, 2.7, 0.08), Vector3(x, 1.4 + 1.35, 0.04), trim)
		Kit.box(g, Vector3(0.71, 0.71, 0.08), Vector3(x, 4.1, 0.04), trim, Vector3(0, 0, 45))
		Kit.box(g, Vector3(0.72, 2.5, 0.03), Vector3(x, 1.5 + 1.25, 0.095), Kit.flat(glass[1], 0.85))
		Kit.box(g, Vector3(0.5, 0.5, 0.03), Vector3(x, 4.0, 0.095), Kit.flat(glass[0], 0.9), Vector3(0, 0, 45))
		Kit.box(g, Vector3(0.72, 0.06, 0.03), Vector3(x, 2.75, 0.12), trim)
		Kit.box(g, Vector3(0.05, 2.5, 0.03), Vector3(x, 2.75, 0.12), trim)
		Kit.box(g, Vector3(0.3, 0.3, 0.02), Vector3(x, 2.1, 0.13), Kit.flat(glass[2], 0.9), Vector3(0, 0, 45))
	# the rose window
	var ry := 6.42
	Kit.disc(g, 1.5, Vector3(0, ry, 0.06), trim, 0.12, 20)
	Kit.disc(g, 1.3, Vector3(0, ry, 0.13), Kit.flat(Color(1.0, 0.7, 0.3), 0.9), 0.02, 20)
	for k in 8:
		var a := TAU * k / 8.0
		Kit.disc(g, 0.28, Vector3(sin(a) * 0.8, ry + cos(a) * 0.8, 0.15), Kit.flat(glass[k % 4], 1.0), 0.02, 10)
	for k in 4:
		Kit.box(g, Vector3(0.07, 2.55, 0.03), Vector3(0, ry, 0.17), trim, Vector3(0, 0, 22.5 + 45.0 * k))
	Kit.ring(g, 1.32, 0.09, Vector3(0, ry, 0.17), trim)
	Kit.disc(g, 0.32, Vector3(0, ry, 0.19), Kit.flat(glass[1], 1.0), 0.02, 12)
	Kit.ring(g, 0.34, 0.06, Vector3(0, ry, 0.2), trim)
	# tall windows down the right side, seen across the street, buttresses between
	for i in 4:
		var z := -2.6 - i * 4.0
		Kit.box(g, Vector3(0.08, 3.4, 1.1), Vector3(w * 0.5 + 0.04, 3.9, z), trim)
		Kit.box(g, Vector3(0.03, 3.2, 0.8), Vector3(w * 0.5 + 0.095, 3.9, z), Kit.flat(glass[(i + 1) % 4], 0.75))
		Kit.box(g, Vector3(0.03, 0.06, 0.8), Vector3(w * 0.5 + 0.12, 3.9, z), trim)
		Kit.box(g, Vector3(0.6, 6.0, 0.6), Vector3(w * 0.5 + 0.25, 3.0, z - 2.0), dark)
	# the tower on the left
	var tx := -w * 0.5 - 1.8
	var top_h := 15.0
	Kit.box(g, Vector3(3.6, top_h, 3.8), Vector3(tx, top_h * 0.5, -1.5), stone)
	Kit.box(g, Vector3(3.72, 0.55, 3.92), Vector3(tx, 0.275, -1.5), dark)
	for y: float in [8.6, 11.0]:
		Kit.box(g, Vector3(3.76, 0.2, 3.96), Vector3(tx, y, -1.5), dark)
	Kit.box(g, Vector3(1.3, 2.3, 0.06), Vector3(tx, 1.15, 0.437), trim)
	Kit.box(g, Vector3(0.92, 0.92, 0.06), Vector3(tx, 2.3, 0.43), trim, Vector3(0, 0, 45))
	Kit.box(g, Vector3(0.9, 2.1, 0.05), Vector3(tx, 1.05, 0.48), red)
	Kit.box(g, Vector3(0.6, 2.2, 0.05), Vector3(tx, 5.2, 0.43), trim)
	Kit.box(g, Vector3(0.42, 2.0, 0.03), Vector3(tx, 5.2, 0.47), Kit.flat(glass[2], 0.8))
	# the clock
	Kit.disc(g, 0.9, Vector3(tx, 9.8, 0.42), trim, 0.06, 18)
	Kit.disc(g, 0.76, Vector3(tx, 9.8, 0.46), Kit.flat(Color(0.98, 0.95, 0.84), 0.6), 0.02, 18)
	for k in 12:
		var a := TAU * k / 12.0
		Kit.box(g, Vector3(0.05, 0.13, 0.01), Vector3(tx + sin(a) * 0.64, 9.8 + cos(a) * 0.64, 0.475), Color(0.1, 0.1, 0.12), Vector3(0, 0, -rad_to_deg(a)))
	Kit.box(g, Vector3(0.07, 0.42, 0.01), Vector3(tx + 0.15, 9.8 + 0.12, 0.48), Color(0.1, 0.1, 0.12), Vector3(0, 0, -50))
	Kit.box(g, Vector3(0.05, 0.62, 0.01), Vector3(tx - 0.02, 9.8 + 0.3, 0.485), Color(0.1, 0.1, 0.12), Vector3(0, 0, 4))
	# the belfry: two pointed openings with louvres, on the front and the right
	for f in 2:
		var wall := Kit.group(g, Vector3(tx, 0, -1.5), Vector3(0, 90.0 * f, 0))
		for s: float in [-0.75, 0.75]:
			Kit.box(wall, Vector3(0.95, 2.2, 0.06), Vector3(s, 12.6, 1.93), trim)
			Kit.box(wall, Vector3(0.67, 0.67, 0.06), Vector3(s, 13.7, 1.93), trim, Vector3(0, 0, 45))
			Kit.box(wall, Vector3(0.7, 2.1, 0.04), Vector3(s, 12.6, 1.97), Color(0.1, 0.09, 0.12))
			for k in 6:
				Kit.box(wall, Vector3(0.7, 0.05, 0.08), Vector3(s, 11.7 + k * 0.33, 2.0), Color(0.36, 0.3, 0.26), Vector3(-25, 0, 0))
	Kit.box(g, Vector3(4.1, 0.5, 4.3), Vector3(tx, top_h + 0.25, -1.5), dark)
	for cx: float in [-1.75, 1.75]:
		for cz: float in [-1.85, 1.85]:
			Kit.cyl(g, 0.3, 1.1, Vector3(tx + cx, top_h + 1.05, -1.5 + cz), dark, Vector3(0, 45, 0), 4, 0.0)
	Kit.cyl(g, 2.45, 7.2, Vector3(tx, top_h + 0.5 + 3.6, -1.5), slate, Vector3(0, 45, 0), 4, 0.0)
	Kit.box(g, Vector3(0.12, 1.0, 0.12), Vector3(tx, top_h + 8.15, -1.5), GILT)
	Kit.box(g, Vector3(0.55, 0.12, 0.12), Vector3(tx, top_h + 8.35, -1.5), GILT)
	# the lamp over the doors and the notice board
	Kit.box(g, Vector3(0.06, 0.06, 0.4), Vector3(0, 4.9, 0.3), IRON)
	Kit.ball(g, 0.16, Vector3(0, 4.75, 0.5), Kit.flat(GLOBE, 1.8), 8)
	Kit.omni(g, Vector3(0, 4.2, 1.6), WARM, 2.6, 7.0)
	notice_board(g, Vector3(3.3, 0, 1.3), 0.0, 2.4, 1.3, title, lines, Color(0.12, 0.12, 0.16), Color(0.97, 0.95, 0.88), 0.7, 0.1)
	return g


## A long, low old building whose blank front wall is a painted mural facing
## +z from `at`: a sunset over the rowhouses, children holding hands, the
## neighbourhood's name. A steel door at one end.
static func mural_building(parent: Node3D, at: Vector3, w: float, title: String, motto: String, credit: String) -> Node3D:
	var g := Kit.group(parent, at, Vector3.ZERO)
	var h := 4.8
	var deep := 4.6
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.86, 0.72, 0.66))
	Kit.box(g, Vector3(w, h, deep), Vector3(0, h * 0.5, -deep * 0.5), brick)
	Kit.box(g, Vector3(w + 0.1, 0.25, 0.3), Vector3(0, h + 0.1, 0.0), STONE.darkened(0.2))
	Kit.box(g, Vector3(w - 0.4, 0.05, deep - 0.6), Vector3(0, h + 0.025, -deep * 0.5), Color(0.2, 0.2, 0.22))
	# the steel door at the left end
	Kit.box(g, Vector3(1.1, 2.2, 0.05), Vector3(-w * 0.5 + 1.0, 1.1, 0.025), Color(0.42, 0.45, 0.48))
	Kit.box(g, Vector3(1.4, 0.12, 0.2), Vector3(-w * 0.5 + 1.0, 2.35, 0.1), STONE.darkened(0.2))
	# the mural: a frame, a sky in bands, the sun, the rows of houses, the people
	var x0 := -w * 0.5 + 2.0
	var x1 := w * 0.5 - 0.35
	var mw := x1 - x0
	var mx := (x0 + x1) * 0.5
	Kit.box(g, Vector3(mw + 0.2, 4.0, 0.03), Vector3(mx, 2.4, 0.015), Color(0.95, 0.92, 0.84))
	var sky := [Color(1.0, 0.82, 0.32), Color(1.0, 0.6, 0.3), Color(0.96, 0.42, 0.45), Color(0.62, 0.34, 0.66), Color(0.3, 0.3, 0.62)]
	for i in sky.size():
		Kit.box(g, Vector3(mw, 0.72, 0.02), Vector3(mx, 0.9 + 0.72 * i + 0.36, 0.04), sky[i])
	Kit.disc(g, 1.0, Vector3(x0 + 2.5, 3.05, 0.06), Color(1.0, 0.95, 0.6), 0.02, 18)
	for k in 10:
		var a := TAU * k / 10.0
		Kit.box(g, Vector3(0.12, 0.42, 0.01), Vector3(x0 + 2.5 + sin(a) * 1.28, 3.05 + cos(a) * 1.28, 0.055), Color(1.0, 0.92, 0.5), Vector3(0, 0, -rad_to_deg(a)))
	var roofs := [[0.0, 1.0, 1.5], [1.0, 1.9, 1.15], [1.9, 3.3, 1.7], [3.3, 4.2, 1.3], [4.2, 5.6, 1.85], [5.6, 6.4, 1.2], [6.4, 7.6, 1.6]]
	for r: Array in roofs:
		if x0 + r[1] > x1:
			continue
		var hx: float = x0 + (r[0] + r[1]) * 0.5
		Kit.box(g, Vector3(r[1] - r[0] - 0.05, r[2], 0.02), Vector3(hx, 0.9 + r[2] * 0.5, 0.075), Color(0.2, 0.18, 0.36))
		for k in int((r[1] - r[0]) / 0.4):
			for row in int(r[2] / 0.5):
				if Props.rnd(r[0] * 7.0 + k + row * 3.0) > 0.45:
					Kit.box(g, Vector3(0.14, 0.18, 0.01), Vector3(x0 + r[0] + 0.22 + k * 0.4, 1.2 + row * 0.5, 0.09), Color(1.0, 0.85, 0.35))
	Kit.box(g, Vector3(mw, 0.5, 0.02), Vector3(mx, 0.65, 0.1), Color(0.32, 0.7, 0.36))
	# the children, holding hands across the right half
	var shirts := [Color(0.95, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(1.0, 0.8, 0.2), Color(0.25, 0.75, 0.4), Color(0.95, 0.5, 0.75), Color(1.0, 0.6, 0.2)]
	var skin := [Color(0.45, 0.28, 0.18), Color(0.6, 0.4, 0.26), Color(0.32, 0.2, 0.14), Color(0.75, 0.55, 0.4)]
	var kids := 5
	for i in kids:
		var px := x1 - 0.6 - (kids - 1 - i) * 0.95
		var tall := 1.0 + Props.rnd(px + 0.37) * 0.4
		Kit.box(g, Vector3(0.42, tall * 0.55, 0.02), Vector3(px, 0.9 + tall * 0.45 + tall * 0.275, 0.12), shirts[i % shirts.size()])
		for s: float in [-0.1, 0.1]:
			Kit.box(g, Vector3(0.13, tall * 0.45, 0.02), Vector3(px + s, 0.9 + tall * 0.225, 0.12), Color(0.2, 0.22, 0.4))
		Kit.disc(g, 0.17, Vector3(px, 0.9 + tall + 0.17, 0.13), skin[i % skin.size()], 0.02, 12)
		if i < kids - 1:
			Kit.box(g, Vector3(0.95, 0.08, 0.02), Vector3(px + 0.475, 0.9 + tall * 0.8, 0.115), skin[i % skin.size()])
	# the words
	var big := Props.words(g, title, Vector3(mx + 1.2, 3.95, 0.14), 0.62, Color(1.0, 0.98, 0.92))
	big.outline_size = 18
	big.outline_modulate = Color(0.22, 0.12, 0.3)
	big.double_sided = false
	var small := Props.words(g, motto, Vector3(mx + 1.2, 3.38, 0.14), 0.24, Color(0.25, 0.12, 0.35))
	small.double_sided = false
	Props.words(g, credit, Vector3(x1 - 1.3, 0.55, 0.14), 0.09, Color(0.15, 0.25, 0.15), 0.0, false).double_sided = false
	return g


## A plain old brick works with rows of factory windows, a water tower on legs
## on its roof. Front facing +z from `at`.
static func works(parent: Node3D, at: Vector3, w: float, h: float, deep: float) -> Node3D:
	var g := Kit.group(parent, at, Vector3.ZERO)
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.22, 0.18), true, Color(0.7, 0.58, 0.58))
	Kit.box(g, Vector3(w, h, deep), Vector3(0, h * 0.5, -deep * 0.5), brick)
	Kit.box(g, Vector3(w + 0.1, 0.3, 0.2), Vector3(0, h - 0.14, 0.05), STONE.darkened(0.25))
	var n := int((w - 1.0) / 2.2)
	for i in n:
		var x := -w * 0.5 + 1.0 + (i + 0.5) * (w - 2.0) / n
		for row in [h - 2.6]:
			Kit.box(g, Vector3(1.6, 1.6, 0.04), Vector3(x, row + 0.8, 0.02), STONE.darkened(0.3))
			var lit := Props.rnd(x * 1.7) > 0.6
			Kit.box(g, Vector3(1.44, 1.44, 0.03), Vector3(x, row + 0.8, 0.05), Kit.flat(Color(0.95, 0.9, 0.6), 0.45) if lit else Color(0.24, 0.28, 0.32))
			for k in 2:
				Kit.box(g, Vector3(1.44, 0.04, 0.02), Vector3(x, row + 0.32 + k * 0.48 + 0.24, 0.075), IRON)
				Kit.box(g, Vector3(0.04, 1.44, 0.02), Vector3(x - 0.24 + k * 0.48, row + 0.8, 0.075), IRON)
	# the water tower
	var t := Vector3(w * 0.18, h, -deep * 0.5)
	var leg := 2.6
	for cx: float in [-1.1, 1.1]:
		for cz: float in [-1.1, 1.1]:
			Kit.box(g, Vector3(0.14, leg, 0.14), t + Vector3(cx, leg * 0.5, cz), Color(0.25, 0.24, 0.26))
	for cz: float in [-1.1, 1.1]:
		strut(g, t + Vector3(-1.1, 0.2, cz), t + Vector3(1.1, leg - 0.2, cz), 0.06, Color(0.25, 0.24, 0.26))
	for cx: float in [-1.1, 1.1]:
		strut(g, t + Vector3(cx, 0.2, -1.1), t + Vector3(cx, leg - 0.2, 1.1), 0.06, Color(0.25, 0.24, 0.26))
	Kit.box(g, Vector3(2.6, 0.15, 2.6), t + Vector3(0, leg + 0.075, 0), Color(0.25, 0.24, 0.26))
	var wood := Kit.tex("wood_panel", 1.2, Color(0.45, 0.32, 0.22), false, Color(0.62, 0.5, 0.42))
	Kit.cyl(g, 1.5, 2.8, t + Vector3(0, leg + 1.55, 0), wood, Vector3.ZERO, 14, 1.42)
	for k in 3:
		Kit.cyl(g, 1.53 - k * 0.03, 0.08, t + Vector3(0, leg + 0.5 + k * 0.9, 0), Color(0.2, 0.2, 0.22), Vector3.ZERO, 14)
	Kit.cyl(g, 1.62, 1.3, t + Vector3(0, leg + 3.6, 0), Color(0.3, 0.3, 0.33), Vector3.ZERO, 14, 0.0)
	Kit.ball(g, 0.13, t + Vector3(0, leg + 4.3, 0), Color(0.3, 0.3, 0.33), 6)
	return g
