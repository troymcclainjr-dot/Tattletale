extends RefCounted
## Fittings for the prisoner tunnel under the civic row (plans/tunnel.gd; the
## civic worker's): pipes along a wall with their brackets, flanges, valves and
## gauges; the pump room's pumps and its hot-water tank; a fire hose cupboard;
## an electrical panel; steel rings to cuff a man to; a drain; wet on the
## concrete.
##
## As in props.gd: `p` is the Place, `b` the band a thing stands in, (u, v) the
## middle of the floor it takes, `yaw` the way its front faces (0 the street, 90
## right, 180 the back, 270 left). Things on a wall take `n`, the node to build
## in (a band's, or a front wall's so that they go when it is cut away), and the
## wall's face: its plane, `face`, a wall facing +v (towards the camera).

const Props := preload("res://scripts/props.gd")

const IRON := Color(0.2, 0.21, 0.23)
const STEEL := Color(0.46, 0.48, 0.51)
const RED := Color(0.62, 0.13, 0.11)            # the fire main
const GREEN := Color(0.24, 0.42, 0.3)           # cold water
const LAG := Color(0.8, 0.78, 0.7)              # lagging, on the hot water
const BAND := Color(0.56, 0.53, 0.46)           # the lagging's straps
const SAFETY := Color(0.93, 0.74, 0.12)
const PUMP := Color(0.2, 0.36, 0.55)


## A pipe along a wall facing +v (its face at v = `face`), from u0 to u1, its
## middle `y` up, `r` thick, standing `gap` off the wall: in pieces 9 m long at
## most (a mesh takes eight lamps at most), with a flange every `every` metres,
## or (`strap` true, for lagging) a strap round it every `every` metres.
## Returns the v of its middle.
static func pipe(p: Node3D, n: Node3D, u0: float, u1: float, face: float, y: float, r: float, look: Color, every := 3.0, strap := false, gap := 0.03) -> float:
	var v := face + gap + r
	var pieces := maxi(ceili((u1 - u0) / 9.0), 1)
	var step := (u1 - u0) / pieces
	for i in pieces:
		Kit.cyl(n, r, step, p.pt(u0 + (i + 0.5) * step, v, y), look, Vector3(0, 0, 90), 12)
	var k := u0 + every * 0.5
	while k < u1 - 0.2:
		if strap:
			Kit.cyl(n, r + 0.006, 0.035, p.pt(k, v, y), BAND, Vector3(0, 0, 90), 12)
		else:
			Kit.cyl(n, r + 0.018, 0.05, p.pt(k, v, y), look.darkened(0.3), Vector3(0, 0, 90), 12)
		k += every
	return v


## The steel brackets that hold a wall's pipes: an upright channel on the wall
## from y0 to y1 at each of `us`, and an arm out from it under each pipe
## (`under`: a list of [y of the pipe's underside, how far out its middle is]).
static func brackets(p: Node3D, n: Node3D, us: Array, face: float, y0: float, y1: float, under: Array) -> void:
	for u: float in us:
		Kit.box(n, Vector3(0.05, y1 - y0, 0.024), p.pt(u, face + 0.012, (y0 + y1) * 0.5), IRON)
		for arm: Array in under:
			var out: float = arm[1]
			Kit.box(n, Vector3(0.04, 0.03, out - face), p.pt(u, (face + out) * 0.5, float(arm[0]) - 0.015), IRON)


## A gate valve on a pipe that runs along u, its middle at (u, v, y), r thick:
## the body round the pipe, the bonnet out towards +v (the camera), the hand
## wheel on it facing +v.
static func valve(p: Node3D, n: Node3D, u: float, v: float, y: float, r: float, wheel := Color(0.74, 0.14, 0.1)) -> void:
	var g := Kit.group(n, p.pt(u, v, y))
	Kit.cyl(g, r + 0.035, 0.18, Vector3.ZERO, IRON, Vector3(0, 0, 90), 12)
	Kit.cyl(g, 0.03, r + 0.13, Vector3(0, 0, (r + 0.13) * 0.5), IRON, Vector3(90, 0, 0), 8)
	var w := r + 0.15
	Kit.ring(g, 0.11, 0.022, Vector3(0, 0, w), wheel)
	for k in 3:
		Kit.box(g, Vector3(0.2, 0.016, 0.016), Vector3(0, 0, w), wheel, Vector3(0, 0, 30.0 + k * 60.0))
	Kit.cyl(g, 0.026, 0.045, Vector3(0, 0, w), IRON, Vector3(90, 0, 0), 8)


## A pressure gauge on the front of a pipe along u (its middle at u, v, y, r
## thick): a short stem out towards +v, the dial on it facing +v, the needle.
static func gauge(p: Node3D, n: Node3D, u: float, v: float, y: float, r: float) -> void:
	var g := Kit.group(n, p.pt(u, v, y))
	Kit.cyl(g, 0.014, 0.07, Vector3(0, 0, r + 0.025), STEEL, Vector3(90, 0, 0), 6)
	Kit.cyl(g, 0.075, 0.04, Vector3(0, 0, r + 0.08), IRON, Vector3(90, 0, 0), 16)
	Kit.cyl(g, 0.062, 0.004, Vector3(0, 0, r + 0.102), Color(0.95, 0.94, 0.88), Vector3(90, 0, 0), 16)
	Kit.box(g, Vector3(0.008, 0.055, 0.003), Vector3(0.012, 0.012, r + 0.106), Color(0.75, 0.12, 0.1), Vector3(0, 0, -38))
	Kit.cyl(g, 0.011, 0.006, Vector3(0, 0, r + 0.107), IRON, Vector3(90, 0, 0), 6)


## The steel cupboard of a fire hose on a wall facing +v (its face at v =
## `face`), its middle at u, y up: red, a window in its door onto the red hose
## coiled on its reel.
static func hose(p: Node3D, n: Node3D, u: float, face: float, y := 1.3) -> void:
	var g := Kit.group(n, p.pt(u, face, 0.0))
	Kit.bevel(g, Vector3(0.66, 0.74, 0.2), Vector3(0, y, 0.1), Color(0.7, 0.12, 0.1), 0.02)
	Kit.box(g, Vector3(0.5, 0.5, 0.01), Vector3(0, y + 0.04, 0.203), Color(0.16, 0.12, 0.12))
	Kit.ring(g, 0.2, 0.07, Vector3(0, y + 0.04, 0.2), Color(0.8, 0.2, 0.14))
	Kit.cyl(g, 0.05, 0.02, Vector3(0, y + 0.04, 0.204), STEEL, Vector3(90, 0, 0), 10)
	Kit.box(g, Vector3(0.5, 0.5, 0.004), Vector3(0, y + 0.04, 0.212), Color(0.75, 0.86, 0.9, 0.22))
	Kit.box(g, Vector3(0.04, 0.12, 0.03), Vector3(0.27, y - 0.18, 0.215), STEEL)


## A grey electrical panel on a wall facing +v (face at v = `face`), its middle
## at u, y up: two doors, a handle, a yellow warning flash, a steel conduit up
## out of its top to the wall's top.
static func panel(p: Node3D, n: Node3D, u: float, face: float, y := 1.45, top := 2.7) -> void:
	var g := Kit.group(n, p.pt(u, face, 0.0))
	Kit.bevel(g, Vector3(0.56, 0.76, 0.18), Vector3(0, y, 0.09), Color(0.55, 0.57, 0.55), 0.02)
	Kit.box(g, Vector3(0.012, 0.66, 0.008), Vector3(0, y, 0.182), IRON)
	Kit.box(g, Vector3(0.03, 0.09, 0.025), Vector3(0.06, y, 0.19), IRON)
	Kit.prism(g, Vector3(0.14, 0.12, 0.004), Vector3(-0.15, y + 0.22, 0.183), SAFETY)
	Kit.box(g, Vector3(0.012, 0.05, 0.003), Vector3(-0.15, y + 0.215, 0.186), Props.DARK, Vector3(0, 0, -20))
	var rise := top - (y + 0.38)
	if rise > 0.05:
		Kit.cyl(g, 0.028, rise, Vector3(0.12, y + 0.38 + rise * 0.5, 0.06), STEEL, Vector3.ZERO, 8)


## A pump set on its plinth, its front +z: the motor lying along x with its
## fins and fan cowl, the pump's round casing, the suction pipe in at its end
## and the delivery pipe up out of its top to `up` metres, then `back` metres
## back (-z) into the main on the wall behind.
static func pump(p: Node3D, b: int, u: float, v: float, yaw := 0.0, up := 1.8, back := 0.5, look := PUMP) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.3, 0.7)
	Kit.block(g, Vector3(1.3, 0.14, 0.7), Vector3.ZERO, Color(0.56, 0.56, 0.53))       # the plinth
	Kit.block(g, Vector3(1.04, 0.05, 0.42), Vector3(0, 0.14, 0), IRON)                    # the base frame
	Kit.cyl(g, 0.17, 0.56, Vector3(-0.2, 0.37, 0), look, Vector3(0, 0, 90), 14)          # the motor
	for k in 5:
		Kit.cyl(g, 0.182, 0.022, Vector3(-0.42 + k * 0.1, 0.37, 0), look.darkened(0.22), Vector3(0, 0, 90), 14)
	Kit.cyl(g, 0.13, 0.09, Vector3(-0.52, 0.37, 0), look.darkened(0.35), Vector3(0, 0, 90), 12)
	Kit.cyl(g, 0.22, 0.17, Vector3(0.29, 0.38, 0), look.darkened(0.1), Vector3(0, 0, 90), 16)   # the casing
	Kit.cyl(g, 0.08, 0.2, Vector3(0.47, 0.34, 0), IRON, Vector3(0, 0, 90), 10)
	Kit.cyl(g, 0.065, up - 0.6, Vector3(0.29, 0.6 + (up - 0.6) * 0.5, 0), look.darkened(0.1), Vector3.ZERO, 10)
	Kit.ball(g, 0.072, Vector3(0.29, up, 0), look.darkened(0.1), 10)                       # the bend
	Kit.tube(g, Vector3(0.29, up, 0), Vector3(0.29, up, -back), 0.065, look.darkened(0.1), 10)
	Kit.cyl(g, 0.085, 0.05, Vector3(0.29, 0.66, 0), IRON, Vector3.ZERO, 10)
	Kit.cyl(g, 0.085, 0.05, Vector3(0.29, up - 0.4, 0), IRON, Vector3.ZERO, 10)
	Kit.box(g, Vector3(0.12, 0.09, 0.012), Vector3(-0.2, 0.37, 0.176), Color(0.85, 0.85, 0.8))   # the motor's plate
	return g


## A hot-water tank lying on two concrete saddles, l long along x, r round, its
## front +z: lagged and strapped, its ends steel, a gauge on its front, a
## lagged pipe up out of its top to `up` metres and `back` metres back (-z)
## into the main on the wall behind.
static func tank(p: Node3D, b: int, u: float, v: float, yaw := 0.0, l := 2.4, r := 0.5, up := 1.95, back := 0.7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, l + 0.2, r * 2.0 + 0.1)
	var mid := 0.3 + r
	for x: float in [-l * 0.3, l * 0.3]:
		Kit.block(g, Vector3(0.18, 0.32, r * 1.5), Vector3(x, 0, 0), Color(0.56, 0.56, 0.53))
	Kit.cyl(g, r, l, Vector3(0, mid, 0), LAG, Vector3(0, 0, 90), 20)
	for k in 5:
		Kit.cyl(g, r + 0.008, 0.05, Vector3(-l * 0.4 + k * l * 0.2, mid, 0), BAND, Vector3(0, 0, 90), 20)
	for s: float in [-1.0, 1.0]:
		Kit.cyl(g, r - 0.03, 0.05, Vector3(s * (l * 0.5 + 0.02), mid, 0), STEEL, Vector3(0, 0, 90), 20)
	Kit.cyl(g, 0.07, up - mid - r, Vector3(l * 0.25, mid + r + (up - mid - r) * 0.5, 0), LAG, Vector3.ZERO, 10)
	Kit.ball(g, 0.075, Vector3(l * 0.25, up, 0), LAG, 10)
	Kit.tube(g, Vector3(l * 0.25, up, 0), Vector3(l * 0.25, up, -back), 0.07, LAG, 10)
	var dial := Kit.group(g, Vector3(-l * 0.22, mid + 0.12, r))
	Kit.cyl(dial, 0.07, 0.04, Vector3(0, 0, 0.02), IRON, Vector3(90, 0, 0), 16)
	Kit.cyl(dial, 0.058, 0.004, Vector3(0, 0, 0.042), Color(0.95, 0.94, 0.88), Vector3(90, 0, 0), 16)
	Kit.box(dial, Vector3(0.008, 0.05, 0.003), Vector3(0.01, 0.01, 0.046), Color(0.75, 0.12, 0.1), Vector3(0, 0, 40))
	return g


## Steel rings fixed to a wall facing +v (face at v = `face`): `count` of them
## from u0, `gap` apart, y up, each on its plate, to cuff a man to the bench.
static func cuff_rings(p: Node3D, n: Node3D, u0: float, face: float, y: float, count: int, gap: float) -> void:
	for i in count:
		var g := Kit.group(n, p.pt(u0 + i * gap, face, y))
		Kit.box(g, Vector3(0.08, 0.08, 0.014), Vector3(0, 0, 0.007), IRON)
		Kit.ring(g, 0.05, 0.013, Vector3(0, -0.055, 0.026), STEEL)


## A drain in the floor: a steel frame and grate over the dark under it, s across.
static func drain(p: Node3D, n: Node3D, u: float, v: float, s := 0.36) -> void:
	var g := Kit.group(n, p.pt(u, v, 0.0))
	Kit.box(g, Vector3(s, 0.004, s), Vector3(0, 0.002, 0), Color(0.09, 0.09, 0.1))
	for z: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(s + 0.05, 0.007, 0.025), Vector3(0, 0.0035, z * (s * 0.5 + 0.0125)), STEEL)
		Kit.box(g, Vector3(0.025, 0.007, s), Vector3(z * (s * 0.5 + 0.0125), 0.0035, 0), STEEL)
	var bars := 6
	for i in bars:
		Kit.box(g, Vector3(0.022, 0.0045, s), Vector3(-s * 0.5 + (i + 0.5) * s / bars, 0.00425, 0), STEEL.darkened(0.15))      # (tops under the frame's)


## Wet on the concrete: a faint sheen lighter than the floor with a lamp in it
## (a darker patch read as a hole), r across, turned `turn`.
static func wet(p: Node3D, n: Node3D, u: float, v: float, r: float, turn := 0.0) -> void:
	var g := Kit.group(n, p.pt(u, v, 0.0), Vector3(0, turn, 0))
	var patch := Kit.cyl(g, r, 0.004, Vector3(0, 0.011, 0), Color(0.66, 0.7, 0.74, 0.2), Vector3.ZERO, 16)
	patch.scale = Vector3(1.4, 1.0, 0.75)
	var glint := Kit.cyl(g, r * 0.2, 0.004, Vector3(r * 0.3, 0.015, -r * 0.1), Color(1.0, 0.9, 0.68, 0.4), Vector3.ZERO, 12)
	glint.scale = Vector3(1.7, 1.0, 0.5)
