extends RefCounted
## Things for Pen Lucy Park (plans/park.gd): the painted court and its hoops,
## the floodlights, the bleachers, park benches, drum bins, the drinking
## fountain, the signs and the chalk; and across the alley, the backs of the
## rowhouses with their yards, steps, cans, washing, aerials, poles and wires.
##
##   const Park := preload("res://scripts/props_park.gd")
##   Park.hoop(p, band, u, v, 90.0)
##
## Same rules as props.gd: `p` is the Place, `b` the band, (u, v) the middle of
## the thing's floor space on the plan, `yaw` the way its front faces (0 the
## street, 90 right, 180 the back, 270 left). Things with floor space keep it
## clear of walkers; the houses across the alley are never walked to, so they
## are built straight into a node and take none.

const Props := preload("res://scripts/props.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const PARK_GREEN := Color(0.16, 0.42, 0.3)
const STEEL := Color(0.62, 0.64, 0.67)
const GALV := Color(0.5, 0.53, 0.56)          # galvanised poles
const IRON := Color(0.17, 0.18, 0.2)
const ALUMINIUM := Color(0.8, 0.82, 0.84)
const LINE := Color(0.96, 0.95, 0.88)
const RIM := Color(0.98, 0.42, 0.1)
const CONCRETE := Color(0.64, 0.63, 0.6)
const COPING := Color(0.3, 0.28, 0.27)
const TAR := Color(0.16, 0.16, 0.18)
const LAMP_COOL := Color(0.9, 0.95, 1.0)
const SODIUM := Color(1.0, 0.7, 0.38)
const WARM := Color(1.0, 0.82, 0.52)
const NIGHT_GLASS := Color(0.13, 0.16, 0.24)
const PLYWOOD := Color(0.66, 0.55, 0.38)
const WOOD := Color(0.52, 0.36, 0.22)
const WOOD_DARK := Color(0.3, 0.2, 0.13)
const CHAIN := Color(0.72, 0.76, 0.78, 0.22)  # the same see-through grey as place.gd's chain-link
const CHALK := [Color(0.96, 0.95, 0.9), Color(1.0, 0.62, 0.78), Color(1.0, 0.92, 0.42), Color(0.55, 0.82, 1.0)]


# ------------------------------------------------------------------- helpers

## A round rod from a to b (points in the parent's space).
static func rod(parent: Node3D, a: Vector3, b: Vector3, r: float, look: Variant, sides := 5) -> MeshInstance3D:
	var d := b - a
	var mi := Kit.cyl(parent, r, d.length(), (a + b) * 0.5, look, Vector3.ZERO, sides)
	var dir := d.normalized()
	if dir.y < 0.0:
		dir = -dir
	if dir.distance_to(Vector3.UP) > 0.0001:
		mi.quaternion = Quaternion(Vector3.UP, dir)
	return mi


## A wire hanging from a to b, sagging `sag` metres in the middle.
static func wire(parent: Node3D, a: Vector3, b: Vector3, sag := 0.3, look: Variant = Color(0.07, 0.07, 0.08), r := 0.014, n := 6) -> void:
	var last := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var at := a.lerp(b, t) - Vector3(0, 4.0 * sag * t * (1.0 - t), 0)
		rod(parent, last, at, r, look, 4)
		last = at


## Where a wire from a to b hangs at t (0..1 along it).
static func wire_at(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, 4.0 * sag * t * (1.0 - t), 0)


## A painted stripe on the ground from a to b (points at the paint's middle height), w wide and h thick.
static func stroke(parent: Node3D, a: Vector3, b: Vector3, w: float, h: float, look: Variant) -> MeshInstance3D:
	var d := b - a
	var l := Vector2(d.x, d.z).length()
	var turn := rad_to_deg(atan2(-d.z, d.x))
	if absf(turn) < 0.001:
		turn = 0.0
	return Kit.box(parent, Vector3(l, h, w), (a + b) * 0.5, look, Vector3(0, turn, 0))


## A painted arc round c, radius r, from angle a0 to a1 (radians: 0 is +x, turning
## towards +z). Dashed leaves out every other piece.
static func arc(parent: Node3D, c: Vector3, r: float, a0: float, a1: float, w: float, h: float, look: Variant, dashed := false) -> void:
	var n := maxi(int(absf(a1 - a0) * r / (0.3 if dashed else 0.26)), 6)
	if dashed and n % 2 == 0:
		n += 1
	for i in n:
		if dashed and i % 2 == 1:
			continue
		var t0 := a0 + (a1 - a0) * float(i) / float(n)
		var t1 := a0 + (a1 - a0) * float(i + 1) / float(n)
		var p0 := c + Vector3(cos(t0), 0, sin(t0)) * r
		var p1 := c + Vector3(cos(t1), 0, sin(t1)) * r
		var ext := Vector3.ZERO if dashed else (p1 - p0).normalized() * w * 0.35      # a little over the chord, so the joins do not gap
		stroke(parent, p0 - ext, p1 + ext, w, h, look)


## Words lying flat on the ground (paint, chalk), reading from the street side.
static func ground_words(parent: Node3D, text: String, pos: Vector3, height: float, colour: Color, yaw := 0.0) -> Label3D:
	var l := Props.words(parent, text, pos, height, colour)
	l.rotation_degrees = Vector3(-90, yaw, 0)
	return l


# ------------------------------------------------------------------- the court

## The painted court: its long side runs along u from u0 to u1, the far
## sideline at v0, the near one at v1. The asphalt round it is laid by the
## plan; this is the coloured surface (in quarters, so no one mesh is lit by
## more lamps than the renderer takes: the alley's reach the far half, the
## street's the near), the keys, the centre circle and every line, each a few
## millimetres over the last.
static func court(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, surface: Variant, paint: Variant) -> Node3D:
	var n := Kit.group(p.node_of(b), Vector3.ZERO, Vector3.ZERO, "Court")
	var white := Kit.flat(LINE)
	var mid_u := (u0 + u1) * 0.5
	var mid_v := (v0 + v1) * 0.5
	var wide := v1 - v0
	# The surface (0.031 .. 0.045), the keys and circle (0.046 .. 0.052), the lines (0.053 .. 0.059).
	for half: Array in [[u0, mid_u], [mid_u, u1]]:
		for depth: Array in [[v0, mid_v], [mid_v, v1]]:
			Kit.box(n, Vector3(half[1] - half[0], 0.014, depth[1] - depth[0]), p.pt((half[0] + half[1]) * 0.5, (depth[0] + depth[1]) * 0.5, 0.038), surface)
	var ky := 0.049
	var ly := 0.056
	var lw := 0.1
	var lh := 0.006
	Kit.cyl(n, 1.8, lh, p.pt(mid_u, mid_v, ky), paint, Vector3.ZERO, 32)
	# The boundary and the centre line and circle.
	Kit.box(n, Vector3(u1 - u0 + lw, lh, lw), p.pt(mid_u, v0, ly), white)
	Kit.box(n, Vector3(u1 - u0 + lw, lh, lw), p.pt(mid_u, v1, ly), white)
	Kit.box(n, Vector3(lw, lh, wide), p.pt(u0, mid_v, ly), white)
	Kit.box(n, Vector3(lw, lh, wide), p.pt(u1, mid_v, ly), white)
	Kit.box(n, Vector3(lw, lh, wide), p.pt(mid_u, mid_v, ly), white)
	arc(n, p.pt(mid_u, mid_v, ly), 1.8, 0.0, TAU, lw, lh, white)
	# Each end: the key, the free-throw circle, the lane marks, the three-point
	# line and the little arc under the rim. s is the way in from the baseline.
	var three := minf(6.75, wide * 0.5 - 0.75)
	var corner := wide * 0.5 - 0.9
	var reach := asin(corner / three)
	for s: float in [1.0, -1.0]:
		var base := u0 if s > 0.0 else u1
		var lane := base + s * 5.8
		var rim := base + s * 1.575
		var face := 0.0 if s > 0.0 else PI        # the angle that points from the rim to the middle of the court
		Kit.box(n, Vector3(5.8, lh, 4.9), p.pt(base + s * 2.9, mid_v, ky), paint)
		for side: float in [-2.45, 2.45]:
			Kit.box(n, Vector3(5.8, lh, lw), p.pt(base + s * 2.9, mid_v + side, ly), white)
			for d: float in [1.75, 2.6, 3.45, 4.3]:
				Kit.box(n, Vector3(0.07, lh, 0.2), p.pt(base + s * d, mid_v + side + signf(side) * 0.15, ly), white)
		Kit.box(n, Vector3(lw, lh, 4.9 + lw), p.pt(lane, mid_v, ly), white)
		arc(n, p.pt(lane, mid_v, ly), 1.8, face - PI * 0.5, face + PI * 0.5, lw, lh, white)
		arc(n, p.pt(lane, mid_v, ly), 1.8, face + PI * 0.5, face + PI * 1.5, lw, lh, white, true)
		arc(n, p.pt(rim, mid_v, ly), 1.25, face - PI * 0.5, face + PI * 0.5, lw, lh, white)
		arc(n, p.pt(rim, mid_v, ly), three, face - reach, face + reach, lw, lh, white)
		var meet := rim + s * three * cos(reach)
		for side: float in [-corner, corner]:
			Kit.box(n, Vector3(absf(meet - base), lh, lw), p.pt((base + meet) * 0.5, mid_v + side, ly), white)
	return n


## A hoop on its pole. The pole stands at (u, v), behind the baseline, and
## the board faces `yaw`, into the court: it is 2.1 m in front of the pole
## (1.2 m in from the baseline when the pole is 0.9 m behind it) and the rim
## is 3.05 m up. Only the padded pole takes floor; he walks under the rest.
static func hoop(p: Node3D, b: int, u: float, v: float, yaw: float, pole_look := Color(0.18, 0.34, 0.62), pad := Color(0.92, 0.72, 0.16)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.42, 0.42)
	Kit.cyl(g, 0.3, 0.06, Vector3(0, 0.03, 0), CONCRETE, Vector3.ZERO, 10)
	Kit.box(g, Vector3(0.17, 3.7, 0.17), Vector3(0, 1.85, 0), pole_look)
	Kit.box(g, Vector3(0.32, 1.6, 0.32), Vector3(0, 0.86, 0), pad)                     # the pad round the bottom
	Kit.box(g, Vector3(0.34, 0.08, 0.34), Vector3(0, 1.67, 0), pad.darkened(0.2))
	# The arm out over the court to the back of the board, and the brace under it.
	Kit.box(g, Vector3(0.13, 0.15, 2.06), Vector3(0, 3.62, 1.0), pole_look)
	rod(g, Vector3(0, 2.75, 0.1), Vector3(0, 3.56, 1.45), 0.05, pole_look, 6)
	Kit.box(g, Vector3(0.6, 0.12, 0.08), Vector3(0, 3.62, 2.02), pole_look)             # the plate the board hangs on
	# The board: white, an orange edge and shooter's square, the rim and a chain net.
	var board := Kit.group(g, Vector3(0, 3.45, 2.1))
	Kit.box(board, Vector3(1.8, 1.05, 0.06), Vector3.ZERO, Color(0.97, 0.97, 0.95))
	var edge := Kit.flat(RIM)
	for piece: Array in [         # the edge stands a little outside the board all round, or its faces flicker on the board's
		[Vector3(1.83, 0.06, 0.02), Vector3(0, 0.51, 0.035)], [Vector3(1.83, 0.06, 0.02), Vector3(0, -0.51, 0.035)],
		[Vector3(0.06, 1.08, 0.02), Vector3(-0.885, 0, 0.035)], [Vector3(0.06, 1.08, 0.02), Vector3(0.885, 0, 0.035)],
		[Vector3(0.59, 0.05, 0.02), Vector3(0, -0.175, 0.035)], [Vector3(0.59, 0.05, 0.02), Vector3(0, 0.275, 0.035)],
		[Vector3(0.05, 0.45, 0.02), Vector3(-0.295, 0.05, 0.035)], [Vector3(0.05, 0.45, 0.02), Vector3(0.295, 0.05, 0.035)]]:
		Kit.box(board, piece[0], piece[1], edge)
	Kit.box(g, Vector3(0.22, 0.06, 0.2), Vector3(0, 3.035, 2.2), RIM.darkened(0.25))   # the bracket
	Kit.ring(g, 0.235, 0.032, Vector3(0, 3.05, 2.475), RIM, Vector3(-90, 0, 0))
	var net := Color(0.86, 0.87, 0.86)
	for i in 12:
		var t := TAU * float(i) / 12.0
		var top := Vector3(0.22 * cos(t), 3.035, 2.475 + 0.22 * sin(t))
		var low := Vector3(0.13 * cos(t + 0.35), 2.62, 2.475 + 0.13 * sin(t + 0.35))
		rod(g, top, low, 0.009, net, 3)
	Kit.ring(g, 0.17, 0.014, Vector3(0, 2.84, 2.475), net, Vector3(-90, 0, 0))
	Kit.ring(g, 0.135, 0.014, Vector3(0, 2.63, 2.475), net, Vector3(-90, 0, 0))
	return g


## A basketball lying on the ground at pos (in the parent's space).
static func ball(parent: Node3D, pos: Vector3, turn := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, turn, 18))
	var seam := Color(0.16, 0.08, 0.05)
	Kit.ball(g, 0.12, Vector3(0, 0.12, 0), Color(0.9, 0.42, 0.13), 12)
	Kit.ring(g, 0.122, 0.01, Vector3(0, 0.12, 0), seam)
	Kit.ring(g, 0.122, 0.01, Vector3(0, 0.12, 0), seam, Vector3(0, 90, 0))
	Kit.ring(g, 0.122, 0.01, Vector3(0, 0.12, 0), seam, Vector3(-90, 0, 0))
	return g


# ------------------------------------------------------------------ the lights

## A floodlight on a tall galvanised pole at (u, v), its bar across `yaw`. The
## light is a real spot from the heads, `energy` strong, thrown at `aim` (a
## point on the plan; without it, `reach` metres straight ahead), the heads
## turned and tipped to it: it lays a pool on the ground `spread` degrees wide
## (the half angle) with an edge as soft as `edge` (higher is harder), and
## gives out a little past twice the throw. `beam` draws a faint cone of light
## under each lamp; `spill` (an energy) hangs a small lamp round the pole's top.
static func floodlight(p: Node3D, b: int, u: float, v: float, yaw: float, h := 7.6, heads := 2, energy := 4.0, reach := 4.5, beam := true, aim := Vector2(INF, INF), spread := 34.0, edge := 1.6, spill := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.5)
	Kit.block(g, Vector3(0.5, 0.3, 0.5), Vector3.ZERO, CONCRETE)
	Kit.cyl(g, 0.13, h, Vector3(0, h * 0.5, 0), GALV, Vector3.ZERO, 8, 0.085)
	Kit.box(g, Vector3(0.24, 0.36, 0.14), Vector3(0, 1.5, 0.14), Color(0.34, 0.38, 0.36))          # the switch box
	Kit.box(g, Vector3(0.16, 0.06, 0.02), Vector3(0, 1.6, 0.215), Color(0.85, 0.75, 0.2))
	for k in 6:                                                                                    # the climbing pegs
		Kit.box(g, Vector3(0.3, 0.035, 0.035), Vector3(0, 2.6 + k * 0.7, 0), GALV.darkened(0.15), Vector3(0, 90.0 * (k % 2), 0))
	var bar := heads * 0.78 + 0.2
	Kit.box(g, Vector3(bar, 0.1, 0.1), Vector3(0, h - 0.12, 0.0), GALV)
	Kit.box(g, Vector3(bar, 0.08, 0.08), Vector3(0, h + 0.32, 0.0), GALV)
	var glow := Kit.flat(LAMP_COOL, 4.0)
	var cone := Kit.flat(Color(0.85, 0.92, 1.0, 0.06), 0.6)
	# Where the light falls, in the pole's own space, and the way the heads turn and tip to it.
	var target: Vector3 = g.to_local(p.pt(aim.x, aim.y)) if aim.x != INF else Vector3(0, 0, reach + 1.8)
	var flat_reach := Vector2(target.x, target.z).length()
	var turn := rad_to_deg(atan2(target.x, target.z))
	var tip := rad_to_deg(atan2(h + 0.1, flat_reach))
	for i in heads:
		var x := (float(i) - float(heads - 1) * 0.5) * 0.78
		var head := Kit.group(g, Vector3(x, h + 0.1, 0.16), Vector3(tip, turn, 0))
		Kit.box(head, Vector3(0.64, 0.5, 0.24), Vector3.ZERO, Color(0.28, 0.3, 0.33))
		Kit.box(head, Vector3(0.54, 0.4, 0.02), Vector3(0, 0, 0.125), glow)
		Kit.box(head, Vector3(0.7, 0.05, 0.32), Vector3(0, 0.27, 0.05), Color(0.28, 0.3, 0.33))   # the visor
		if beam:
			# A cone from the lamp face to the ground where it shines, opening out as it falls.
			var from := Vector3(x, h + 0.02, 0.28)
			var to := Vector3(target.x + x * 0.6, 0.06, target.z)
			var d := from - to
			var c := Kit.cyl(g, d.length() * tan(deg_to_rad(spread * 0.42)), d.length(), (from + to) * 0.5, cone, Vector3.ZERO, 14, 0.24)
			c.quaternion = Quaternion(Vector3.UP, d.normalized())
			(c.mesh as CylinderMesh).cap_top = false
			(c.mesh as CylinderMesh).cap_bottom = false
	# The lamp: a spot from the heads. Its pool has an edge, and outside it the
	# court is left to the dark.
	var spot := SpotLight3D.new()
	spot.light_color = LAMP_COOL
	spot.light_energy = energy
	spot.spot_angle = spread
	spot.spot_angle_attenuation = edge
	spot.spot_attenuation = 0.45
	g.add_child(spot)
	spot.position = Vector3(0, h + 0.05, 0.3)
	spot.spot_range = (target - spot.position).length() * 2.1
	spot.look_at(g.to_global(target), Vector3.UP)
	if spill > 0.0:
		Kit.omni(g, Vector3(0, h - 1.2, 0.9), LAMP_COOL, spill, 6.5)
	return g


## An alley light: a cobra head on an arm, hung from a pole's group at height y,
## reaching `out` metres to the group's front. Sodium orange.
static func cobra(g: Node3D, y: float, out := 1.6, energy := 3.6, reach := 11.0) -> void:
	rod(g, Vector3(0, y - 0.35, 0.12), Vector3(0, y, out * 0.5), 0.035, GALV, 5)
	Kit.box(g, Vector3(0.07, 0.07, out), Vector3(0, y, out * 0.5 + 0.1), GALV)
	Kit.box(g, Vector3(0.36, 0.16, 0.62), Vector3(0, y - 0.02, out + 0.3), Color(0.55, 0.57, 0.58))
	Kit.box(g, Vector3(0.28, 0.04, 0.46), Vector3(0, y - 0.11, out + 0.32), Kit.flat(SODIUM, 3.0))
	Kit.omni(g, Vector3(0, y - 0.7, out + 0.3), SODIUM, energy, reach)


# --------------------------------------------------------------- park furniture

## Aluminium bleachers, `rows` rows rising to the back on green frames, w long.
static func bleachers(p: Node3D, b: int, u: float, v: float, yaw: float, w := 6.0, rows := 3) -> Node3D:
	var step := 0.62
	var d := rows * step + 0.12
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var frame := PARK_GREEN.darkened(0.25)
	var front := d * 0.5 - 0.06
	var top := 0.45 + (rows - 1) * 0.42
	for x: float in [-w * 0.5 + 0.2, 0.0, w * 0.5 - 0.2]:
		rod(g, Vector3(x, 0.0, front - 0.05), Vector3(x, top - 0.05, -d * 0.5 + 0.12), 0.045, frame, 6)    # the stringer
		for r in rows:
			var z := front - step * r - 0.42
			Kit.box(g, Vector3(0.07, 0.45 + r * 0.42, 0.07), Vector3(x, (0.45 + r * 0.42) * 0.5, z), frame)
			Kit.box(g, Vector3(0.07, 0.07, step), Vector3(x, 0.4 + r * 0.42, z + step * 0.3), frame)
		Kit.box(g, Vector3(0.07, 0.95, 0.07), Vector3(x, top + 0.45, -d * 0.5 + 0.06), frame)              # the back guard rail's posts
	for r in rows:
		var z := front - step * r
		Kit.box(g, Vector3(w, 0.05, 0.3), Vector3(0, 0.45 + r * 0.42, z - 0.42), ALUMINIUM)               # the seat plank
		if r > 0:
			Kit.box(g, Vector3(w, 0.04, 0.24), Vector3(0, r * 0.42, z - 0.12), ALUMINIUM.darkened(0.14))  # the foot plank in front of it
		Kit.box(g, Vector3(w, 0.18, 0.02), Vector3(0, 0.33 + r * 0.42, z - 0.27), ALUMINIUM.darkened(0.3)) # the kick board under the seat's front
	Kit.box(g, Vector3(w + 0.08, 0.06, 0.06), Vector3(0, top + 0.9, -d * 0.5 + 0.06), frame)
	Kit.box(g, Vector3(w + 0.08, 0.06, 0.06), Vector3(0, top + 0.5, -d * 0.5 + 0.06), frame)
	return g


## A park bench: green slats with a back, on black iron ends.
static func park_bench(p: Node3D, b: int, u: float, v: float, yaw: float, w := 1.9, slat := Color(0.2, 0.46, 0.32)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.62)
	for x: float in [-w * 0.5 + 0.16, w * 0.5 - 0.16]:
		Kit.box(g, Vector3(0.07, 0.44, 0.07), Vector3(x, 0.22, 0.2), IRON)
		Kit.box(g, Vector3(0.07, 0.44, 0.07), Vector3(x, 0.22, -0.16), IRON)
		Kit.box(g, Vector3(0.07, 0.06, 0.5), Vector3(x, 0.4, 0.02), IRON)
		Kit.box(g, Vector3(0.07, 0.55, 0.07), Vector3(x, 0.68, -0.25), IRON, Vector3(-10, 0, 0))
		Kit.box(g, Vector3(0.08, 0.05, 0.42), Vector3(x, 0.66, 0.05), IRON)                           # the arm
		Kit.box(g, Vector3(0.07, 0.22, 0.06), Vector3(x, 0.55, 0.23), IRON)
	for k in 3:
		Kit.box(g, Vector3(w, 0.045, 0.13), Vector3(0, 0.46, 0.18 - k * 0.15), slat)
	for k in 3:
		Kit.box(g, Vector3(w, 0.1, 0.035), Vector3(0, 0.6 + k * 0.14, -0.24 - k * 0.025), slat, Vector3(-10, 0, 0))
	return g


## A 55-gallon drum painted as a park bin, with a black bag in it and a stencil.
static func barrel(p: Node3D, b: int, u: float, v: float, look := Color(0.12, 0.42, 0.62), text := "", full := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.62, 0.62)
	Kit.cyl(g, 0.29, 0.88, Vector3(0, 0.44, 0), look, Vector3.ZERO, 12)
	for y: float in [0.3, 0.6]:
		Kit.cyl(g, 0.302, 0.035, Vector3(0, y, 0), look.darkened(0.18), Vector3.ZERO, 12)
	Kit.cyl(g, 0.3, 0.03, Vector3(0, 0.865, 0), look.darkened(0.25), Vector3.ZERO, 12)
	Kit.cyl(g, 0.255, 0.03, Vector3(0, 0.875, 0), Color(0.08, 0.08, 0.09), Vector3.ZERO, 12)        # the bag inside
	if full:
		Kit.ball(g, 0.2, Vector3(0.02, 0.9, -0.03), Color(0.1, 0.1, 0.11), 7)
		Kit.box(g, Vector3(0.16, 0.2, 0.012), Vector3(0.12, 1.02, 0.04), Color(0.92, 0.9, 0.82), Vector3(14, 30, 22))
		Kit.cyl(g, 0.04, 0.13, Vector3(-0.1, 1.02, 0.08), Color(0.85, 0.15, 0.12), Vector3(0, 0, 28), 8, 0.05)
	if text != "":
		Props.words(g, text, Vector3(0, 0.45, 0.296), 0.1, Color(0.97, 0.96, 0.9))
	return g


## A drinking fountain on a pedestal, the button to the front.
static func drinking_fountain(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.55, 0.55)
	Kit.block(g, Vector3(0.6, 0.05, 0.6), Vector3.ZERO, CONCRETE)
	Kit.cyl(g, 0.14, 0.8, Vector3(0, 0.45, 0), PARK_GREEN, Vector3.ZERO, 8, 0.11)
	Kit.cyl(g, 0.2, 0.14, Vector3(0, 0.9, 0), STEEL, Vector3.ZERO, 12, 0.25)
	Kit.cyl(g, 0.205, 0.012, Vector3(0, 0.972, 0), Color(0.36, 0.4, 0.44), Vector3.ZERO, 12)
	Kit.cyl(g, 0.022, 0.08, Vector3(0.04, 1.01, -0.07), STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.08, 0.08, 0.05), Vector3(0, 0.9, 0.24), STEEL.darkened(0.2))
	Kit.block(g, Vector3(0.32, 0.18, 0.2), Vector3(0, 0.05, 0.33), CONCRETE.darkened(0.1))          # the step for small ones
	Kit.cyl(g, 0.5, 0.004, Vector3(0.18, 0.003, 0.32), Color(0.14, 0.18, 0.24, 0.55), Vector3.ZERO, 14)   # the puddle
	return g


## A painted board on two posts, `w` x `h`, its bottom `y0` up, its face to `yaw`.
## Fixed to a fence (`on_fence`), it takes no floor and has no posts of its own.
static func board(p: Node3D, b: int, u: float, v: float, yaw: float, w: float, h: float, y0: float, look: Color, on_fence := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w + 0.2, 0.2, not on_fence)
	if not on_fence:
		for x: float in [-w * 0.5 + 0.25, w * 0.5 - 0.25]:
			Kit.box(g, Vector3(0.1, y0 + h + 0.08, 0.1), Vector3(x, (y0 + h + 0.08) * 0.5, -0.09), WOOD_DARK)
	else:
		for x: float in [-w * 0.5 + 0.25, w * 0.5 - 0.25]:
			Kit.box(g, Vector3(0.06, h + 0.3, 0.04), Vector3(x, y0 + h * 0.5, -0.06), GALV)     # the brackets on the wire
	Kit.box(g, Vector3(w, h, 0.05), Vector3(0, y0 + h * 0.5, 0), look)
	Kit.box(g, Vector3(w + 0.1, 0.07, 0.09), Vector3(0, y0 + h + 0.035, 0.0), look.darkened(0.4))
	Kit.box(g, Vector3(w + 0.1, 0.05, 0.09), Vector3(0, y0 - 0.025, 0.0), look.darkened(0.4))
	return g


## A park scoreboard someone made: plywood on the fence, painted, with hung
## number plates, and the next game's names chalked underneath.
static func scoreboard(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g := board(p, b, u, v, yaw, 2.4, 1.3, 1.5, Color(0.12, 0.3, 0.24), true)
	var cream := Color(0.97, 0.95, 0.86)
	Props.words(g, "HOME", Vector3(-0.6, 2.55, 0.03), 0.17, Color(1.0, 0.86, 0.3))
	Props.words(g, "GUEST", Vector3(0.6, 2.55, 0.03), 0.17, Color(1.0, 0.86, 0.3))
	for x: float in [-0.6, 0.6]:
		Kit.box(g, Vector3(0.78, 0.56, 0.02), Vector3(x, 2.05, 0.035), Color(0.06, 0.07, 0.08))
		Kit.cyl(g, 0.015, 0.05, Vector3(x, 2.36, 0.05), STEEL, Vector3(90, 0, 0), 5)
	Props.words(g, "18", Vector3(-0.6, 2.05, 0.05), 0.42, cream)
	Props.words(g, "21", Vector3(0.6, 2.05, 0.05), 0.42, cream)
	Kit.box(g, Vector3(0.05, 0.9, 0.02), Vector3(0, 2.15, 0.035), Color(1.0, 0.86, 0.3))
	Props.words(g, "GAME TO 21  /  WIN BY 2", Vector3(0, 1.66, 0.03), 0.09, cream)
	return g


## The milk crate everybody sits on (or shoots into).
static func crate(parent: Node3D, pos: Vector3, turn := 0.0, look := Color(0.9, 0.62, 0.12)) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, turn, 0))
	for x: float in [-0.155, 0.155]:
		Kit.box(g, Vector3(0.03, 0.28, 0.33), Vector3(x, 0.14, 0), look)
	for z: float in [-0.155, 0.155]:
		Kit.box(g, Vector3(0.28, 0.28, 0.03), Vector3(0, 0.14, z), look)
	Kit.box(g, Vector3(0.3, 0.03, 0.3), Vector3(0, 0.015, 0), look.darkened(0.2))
	for x: float in [-0.155, 0.155]:                    # the handle slots
		Kit.box(g, Vector3(0.012, 0.05, 0.12), Vector3(x * 1.06, 0.21, 0), look.darkened(0.45))
	return g


## Bits of litter on the ground round pos: cups, a can, paper. They do not block.
static func litter(parent: Node3D, pos: Vector3, key: float, n := 4) -> void:
	for i in n:
		var k := key + i * 7.31
		var at := pos + Vector3((Props.rnd(k) - 0.5) * 1.2, 0.0, (Props.rnd(k + 1.0) - 0.5) * 0.9)
		match i % 4:
			0:
				Kit.box(parent, Vector3(0.16, 0.012, 0.12), at + Vector3(0, 0.04, 0), Color(0.93, 0.92, 0.85), Vector3(0, 360.0 * Props.rnd(k + 2.0), 6))
			1:
				Kit.cyl(parent, 0.033, 0.12, at + Vector3(0, 0.07, 0), [Color(0.8, 0.15, 0.12), Color(0.2, 0.4, 0.8), Color(0.25, 0.6, 0.3)][int(Props.rnd(k + 3.0) * 3.0) % 3], Vector3(90, 360.0 * Props.rnd(k + 4.0), 0), 8)
			2:
				Kit.cyl(parent, 0.045, 0.14, at + Vector3(0, 0.07, 0), Color(0.95, 0.94, 0.9), Vector3(90, 360.0 * Props.rnd(k + 5.0), 0), 8, 0.035)
			_:
				Kit.ball(parent, 0.05, at + Vector3(0, 0.07, 0), Color(0.88, 0.86, 0.78), 5)


## A hopscotch chalked on the asphalt, running away from the street from pos.
static func hopscotch(parent: Node3D, pos: Vector3) -> void:
	var chalk := Kit.flat(CHALK[0])
	var pink := CHALK[1]
	var y := 0.0325
	var rows := [[0.0], [0.0], [-0.27, 0.27], [0.0], [-0.27, 0.27], [0.0], [0.0]]
	var num := 1
	for r in rows.size():
		var z := -0.56 * float(r)
		for x: float in rows[r]:
			var w := 0.54
			var c := pos + Vector3(x, y, z - 0.28)
			for e: Array in [[Vector3(w, 0.004, 0.04), Vector3(0, 0, 0.26)], [Vector3(w, 0.004, 0.04), Vector3(0, 0, -0.26)], [Vector3(0.04, 0.004, 0.56), Vector3(-0.25, 0, 0)], [Vector3(0.04, 0.004, 0.56), Vector3(0.25, 0, 0)]]:
				Kit.box(parent, e[0], c + e[1], chalk)
			ground_words(parent, str(num), c + Vector3(0, 0.003, 0), 0.26, pink)
			num += 1
	# The half-circle at the top, and the stone.
	arc(parent, pos + Vector3(0, y, -0.56 * rows.size()), 0.36, PI, TAU, 0.04, 0.004, chalk)
	Kit.cyl(parent, 0.05, 0.03, pos + Vector3(0.12, 0.045, -0.56 * 3.5), Color(0.5, 0.5, 0.52), Vector3.ZERO, 6)


# ---------------------------------------------------- across the alley: houses

## The back of one rowhouse across the alley, u0 to u0 + w on the plan: its
## main block, the narrower back building (`side`: "l" or "r", which half it
## is on) with its rear wall at v = back, the light court beside it, and the
## yard down to the alley fence at v = alley. Built straight into node n.
## o (all optional): "brick", "bb" (looks), "trim", "door" (colours), "h",
## "bb_h" (heights; a back building under 4.5 m is one storey), "lit" (which
## windows glow: "k" the kitchen, "u" over it, "c" the light court's, "cu"
## over that, "m" the main block's back window over a one-storey back
## building), "curtain" (a colour), "porch" (the light by the back door is
## on), "boarded", "aerial", "chimney", "fence" ("chain", "wood", "brick",
## "broken", "none"), "gate_open", "line" (colours of the washing), "ac" (an
## air conditioner in the upper window), "bars", "storm" (a storm door),
## "awning" (a colour), "cans" (how many), "cans_out" (they stand in the
## alley), "extra" (a list: "grill", "chair", "bike", "doghouse", "planters",
## "trike", "weeds", "tyre").
static func house_back(p: Node3D, n: Node3D, u0: float, w: float, back: float, alley: float, o: Dictionary) -> void:
	var brick: Variant = o.get("brick", Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2)))
	var bb_look: Variant = o.get("bb", brick)
	var h: float = o.get("h", 7.0)
	var bb_h: float = o.get("bb_h", 6.0)
	var side: String = o.get("side", "l")
	var lit: Array = o.get("lit", [])
	var boarded: bool = o.get("boarded", false)
	var bb_w := 3.0
	var bb_d := 3.2
	var floor_y := 0.45                     # the ground floor stands this far above the yard
	var main_back := back - bb_d
	var bb_u0 := u0 if side == "l" else u0 + w - bb_w
	var bb_u1 := bb_u0 + bb_w
	var lc_u0 := bb_u1 if side == "l" else u0           # the light court beside the back building
	var lc_u1 := u0 + w if side == "l" else bb_u0
	var lc_mid := (lc_u0 + lc_u1) * 0.5
	# The main block, its roof and coping; the back building and its coping; the yard.
	Kit.box(n, Vector3(w, h, 8.0), p.pt(u0 + w * 0.5, main_back - 4.0, h * 0.5), brick)
	Kit.box(n, Vector3(w - 0.02, 0.05, 7.6), p.pt(u0 + w * 0.5, main_back - 4.1, h + 0.025), TAR)
	Kit.box(n, Vector3(w, 0.2, 0.34), p.pt(u0 + w * 0.5, main_back - 0.11, h + 0.1), COPING)
	Kit.box(n, Vector3(bb_w, bb_h, bb_d), p.pt(bb_u0 + bb_w * 0.5, back - bb_d * 0.5, bb_h * 0.5), bb_look)
	Kit.box(n, Vector3(bb_w - 0.02, 0.04, bb_d - 0.3), p.pt(bb_u0 + bb_w * 0.5, back - bb_d * 0.5 - 0.1, bb_h + 0.02), TAR)
	Kit.box(n, Vector3(bb_w, 0.16, 0.3), p.pt(bb_u0 + bb_w * 0.5, back - 0.09, bb_h + 0.08), COPING)
	# Gutters under both copings, and their downspouts, both on the light court's
	# side of the back building (clear of the fences between the yards): the back
	# building's just past its rear corner, its gutter run on to meet it, the main
	# block's down the inside corner. Each kicks out at the foot towards the alley.
	var tin := Color(0.88, 0.87, 0.82)
	var out_u := bb_u1 if side == "l" else bb_u0          # the back building's light-court side
	var s_sign := 1.0 if side == "l" else -1.0
	Kit.box(n, Vector3(bb_w + 0.13, 0.1, 0.1), p.pt(bb_u0 + bb_w * 0.5 + s_sign * 0.075, back + 0.11, bb_h - 0.08), tin)
	Kit.box(n, Vector3(w - 0.02, 0.1, 0.1), p.pt(u0 + w * 0.5, main_back + 0.11, h - 0.08), tin)
	for s: Array in [[out_u + s_sign * 0.1, back, bb_h], [out_u + s_sign * 0.07, main_back, h]]:
		Kit.box(n, Vector3(0.08, s[2] - 0.28, 0.08), p.pt(s[0], s[1] + 0.11, (s[2] - 0.28) * 0.5 + 0.15), tin)
		Kit.box(n, Vector3(0.08, 0.08, 0.24), p.pt(s[0], s[1] + 0.27, 0.15), tin)
	# (The yard's top is the ground, y = 0, where the walls stand: were it any
	# higher, its ends would lie in the same plane as the walls' and the fences'.)
	Kit.box(n, Vector3(w, 0.1, alley - main_back), p.pt(u0 + w * 0.5, (main_back + alley) * 0.5, -0.05), o.get("yard", Outdoor.tex("out_paving", 4.8, CONCRETE, Color(0.92, 0.92, 0.9))))
	if o.get("chimney", false):
		Kit.box(n, Vector3(0.55, 1.1, 0.75), p.pt(u0 + (0.4 if side == "l" else w - 0.4), main_back - 2.8, h + 0.55), brick)
		Kit.box(n, Vector3(0.62, 0.08, 0.82), p.pt(u0 + (0.4 if side == "l" else w - 0.4), main_back - 2.8, h + 1.14), COPING)
	# The back door, up its steps, and the kitchen window beside it.
	var door_u := (bb_u1 - 0.75) if side == "l" else (bb_u0 + 0.75)
	var kitchen_u := (bb_u0 + 0.9) if side == "l" else (bb_u1 - 0.9)
	_door(n, p.pt(door_u, back), 0.0, floor_y, o)
	_steps(n, p.pt(door_u, back), floor_y, o.get("rail", true))
	_window(n, p.pt(kitchen_u, back), 0.0, 0.8, floor_y + 1.05, floor_y + 2.05, "k" in lit, o, true)
	if bb_h > 4.5:
		_window(n, p.pt(bb_u0 + 1.5, back), 0.0, 0.92, 3.95, 5.3, "u" in lit, o, false, o.get("ac", false))
	else:
		_window(n, p.pt(bb_u0 + 1.5, main_back), 0.0, 0.92, 4.05, 5.45, "m" in lit, o, false, o.get("ac", false))
	# The light court: the main block's back windows and the back building's side ones.
	_window(n, p.pt(lc_mid, main_back), 0.0, 0.9, floor_y + 0.95, floor_y + 2.25, "c" in lit, o, true)
	_window(n, p.pt(lc_mid, main_back), 0.0, 0.9, 4.0, 5.45, "cu" in lit, o)
	var side_u := bb_u1 if side == "l" else bb_u0
	var side_yaw := 90.0 if side == "l" else 270.0
	_window(n, p.pt(side_u, back - 1.7), side_yaw, 0.7, floor_y + 1.0, floor_y + 2.0, false, o, true)
	if bb_h > 4.5:
		_window(n, p.pt(side_u, back - 1.7), side_yaw, 0.7, 4.0, 5.2, false, o)
	if o.get("aerial", false):
		_aerial(n, p.pt(u0 + w * (0.3 if side == "l" else 0.7), main_back - 1.2, h + 0.05))
	_yard(p, n, u0, w, back, main_back, alley, door_u, side, o)


## The yard: the fence along the alley with its gate, the fence down the side,
## the cans, the washing, whatever else lives out there.
static func _yard(p: Node3D, n: Node3D, u0: float, w: float, back: float, main_back: float, alley: float, door_u: float, side: String, o: Dictionary) -> void:
	var fence: String = o.get("fence", "chain")
	var at := alley - 0.06
	var g0 := clampf(door_u - 0.5, u0 + 0.15, u0 + w - 1.15)
	var g1 := g0 + 1.0
	var open: bool = o.get("gate_open", false)
	# Down the left side, between this yard and the one before it.
	var side_from := back if side == "l" else main_back
	match fence:
		"wood":
			_boards(p, n, true, at, u0, g0, 1.8)
			_boards(p, n, true, at, g1, u0 + w, 1.8)
			_board_gate(p, n, at, g0, g1, 1.8, open)
			_boards(p, n, false, u0 + 0.03, side_from, at, 1.8)
		"brick":
			var wall := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.85, 0.7, 0.66))
			for run: Array in [[u0, g0], [g1, u0 + w]]:
				if run[1] - run[0] > 0.05:
					Kit.box(n, Vector3(run[1] - run[0], 0.9, 0.24), p.pt((run[0] + run[1]) * 0.5, at, 0.45), wall)
					Kit.box(n, Vector3(run[1] - run[0] + 0.04, 0.06, 0.3), p.pt((run[0] + run[1]) * 0.5, at, 0.93), CONCRETE)
			_chain(p, n, false, u0 + 0.03, side_from, at - 0.12, 1.2)
			_chain_gate(p, n, at, g0, g1, 1.0, open, IRON)
		"none":
			_chain(p, n, false, u0 + 0.03, side_from, at, 1.2)
		"broken":
			_chain(p, n, true, at, u0, g0, 1.2)
			_chain(p, n, false, u0 + 0.03, side_from, at, 1.2)
			# The rest of it is down: a post leaning out, the wire lying in the weeds.
			rod(n, p.pt(g1 + 0.3, at, 0.0), p.pt(g1 + 0.7, at + 0.6, 1.05), 0.03, GALV, 5)
			Kit.box(n, Vector3(w - (g1 - u0) - 0.3, 0.012, 0.9), p.pt((g1 + u0 + w) * 0.5 + 0.1, at - 0.35, 0.03), Outdoor.chain_link(), Vector3(0, 0, 4))
		_:
			_chain(p, n, true, at, u0, g0, 1.2)
			_chain(p, n, true, at, g1, u0 + w, 1.2)
			_chain_gate(p, n, at, g0, g1, 1.2, open, GALV)
			_chain(p, n, false, u0 + 0.03, side_from, at, 1.2)
	# The cans: in the yard by the fence, or out in the alley for the truck.
	var cans: int = o.get("cans", 0)
	var out: bool = o.get("cans_out", false)
	var looks := [Color(0.6, 0.62, 0.64), Color(0.2, 0.34, 0.26), Color(0.42, 0.44, 0.47), Color(0.6, 0.62, 0.64)]
	var lids := ["on", "off", "on", "tilt"]
	var start := (g1 + 0.45) if g1 + 0.45 + 0.55 * cans < u0 + w else (g0 - 0.45 - 0.55 * float(cans - 1))
	for i in cans:
		var k := u0 * 3.1 + float(i)
		var cu := start + 0.56 * float(i)
		var cv := (alley + 0.42) if out else (alley - 0.45)
		_can(n, p.pt(cu, cv), looks[int(Props.rnd(k) * 4.0) % 4], lids[(i + int(u0)) % 4], 40.0 * Props.rnd(k + 1.0))
	if cans > 0 and out:
		Kit.ball(n, 0.24, p.pt(start + 0.56 * float(cans) - 0.05, alley + 0.4, 0.17), Color(0.09, 0.09, 0.1), 7)   # a bag that did not fit
	# The washing line along the yard, clothes pegged out on it.
	var line: Array = o.get("line", [])
	if not line.is_empty():
		var lv := alley - 0.75
		var a: Vector3 = p.pt(u0 + 0.35, lv, 1.95)
		var bb: Vector3 = p.pt(u0 + w - 0.35, lv, 1.95)
		for at_u: float in [u0 + 0.35, u0 + w - 0.35]:
			Kit.cyl(n, 0.035, 2.0, p.pt(at_u, lv, 1.0), GALV, Vector3.ZERO, 5)
			Kit.box(n, Vector3(0.05, 0.05, 0.7), p.pt(at_u, lv, 1.97), GALV)
		wire(n, a + Vector3(0, 0, 0.3), bb + Vector3(0, 0, 0.3), 0.14, Color(0.85, 0.85, 0.82), 0.007, 8)
		wire(n, a - Vector3(0, 0, 0.3), bb - Vector3(0, 0, 0.3), 0.14, Color(0.85, 0.85, 0.82), 0.007, 8)
		var sizes := [Vector2(0.5, 0.62), Vector2(0.62, 0.86), Vector2(0.36, 0.95), Vector2(1.1, 0.9), Vector2(0.24, 0.3), Vector2(0.5, 0.56)]
		var t := 0.12
		for i in line.size():
			var s: Vector2 = sizes[i % sizes.size()]
			var span := (w - 0.7)
			var tc := t + s.x * 0.5 / span
			if tc + s.x * 0.5 / span > 0.95:
				break
			var top := wire_at(a + Vector3(0, 0, 0.3), bb + Vector3(0, 0, 0.3), 0.14, tc)
			Kit.box(n, Vector3(s.x, s.y, 0.012), top - Vector3(0, s.y * 0.5 + 0.01, 0), line[i], Vector3(0, 3.0 + 4.0 * Props.rnd(i + u0), 1.5 * (Props.rnd(i * 2.0 + u0) - 0.5)))
			for e: float in [-s.x * 0.4, s.x * 0.4]:
				Kit.box(n, Vector3(0.02, 0.06, 0.02), top + Vector3(e, 0.0, 0.0), Color(0.7, 0.55, 0.35))
			t = tc + s.x * 0.5 / span + 0.04
	# Odds and ends.
	for thing: String in o.get("extra", []):
		match thing:
			"grill":
				var gr := Kit.group(n, p.pt(lc_u_or(u0, w, side) + 0.2, back + 1.2), Vector3(0, 20, 0))
				for t2 in 3:
					var ang := TAU * float(t2) / 3.0
					rod(gr, Vector3(0.24 * cos(ang), 0.0, 0.24 * sin(ang)), Vector3(0.1 * cos(ang), 0.6, 0.1 * sin(ang)), 0.015, IRON, 4)
				Kit.ball(gr, 0.27, Vector3(0, 0.72, 0), Color(0.08, 0.08, 0.09), 10)
				Kit.box(gr, Vector3(0.1, 0.04, 0.03), Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.3))
			"chair":
				var ch := Kit.group(n, p.pt(lc_u_or(u0, w, side), alley - 1.3), Vector3(0, 200, 0))
				var web := Color(0.2, 0.6, 0.45)
				Kit.box(ch, Vector3(0.5, 0.04, 0.46), Vector3(0, 0.36, 0), web)
				Kit.box(ch, Vector3(0.5, 0.5, 0.04), Vector3(0, 0.63, -0.25), web, Vector3(-12, 0, 0))
				for x: float in [-0.25, 0.25]:
					rod(ch, Vector3(x, 0.0, 0.24), Vector3(x, 0.36, -0.2), 0.012, ALUMINIUM, 4)
					rod(ch, Vector3(x, 0.0, -0.24), Vector3(x, 0.36, 0.2), 0.012, ALUMINIUM, 4)
					Kit.box(ch, Vector3(0.03, 0.03, 0.4), Vector3(x, 0.55, 0.0), ALUMINIUM)
			"bike":
				var bk := Kit.group(n, p.pt(u0 + w - 1.2, alley - 0.25), Vector3(0, 0, 8))
				var frame := Color(0.8, 0.15, 0.2)
				for x: float in [-0.5, 0.5]:
					Kit.ring(bk, 0.32, 0.035, Vector3(x, 0.34, 0), Color(0.1, 0.1, 0.1))
				rod(bk, Vector3(-0.5, 0.34, 0), Vector3(0.0, 0.66, 0), 0.02, frame, 4)
				rod(bk, Vector3(0.0, 0.66, 0), Vector3(0.5, 0.34, 0), 0.02, frame, 4)
				rod(bk, Vector3(-0.5, 0.34, 0), Vector3(-0.1, 0.34, 0), 0.02, frame, 4)
				rod(bk, Vector3(-0.1, 0.34, 0), Vector3(0.0, 0.66, 0), 0.02, frame, 4)
				rod(bk, Vector3(0.45, 0.4, 0), Vector3(0.42, 0.88, 0), 0.02, frame, 4)
				Kit.box(bk, Vector3(0.05, 0.03, 0.5), Vector3(0.42, 0.9, 0), IRON)
				Kit.box(bk, Vector3(0.24, 0.06, 0.1), Vector3(-0.05, 0.74, 0), IRON)
			"doghouse":
				var dh := Kit.group(n, p.pt(lc_u_or(u0, w, side), back + 1.0), Vector3(0, 0, 0))
				var red := Color(0.62, 0.2, 0.15)
				Kit.block(dh, Vector3(0.8, 0.6, 0.9), Vector3.ZERO, red)
				Kit.box(dh, Vector3(0.5, 0.05, 1.0), Vector3(-0.2, 0.75, 0), Color(0.3, 0.3, 0.32), Vector3(0, 0, 32))
				Kit.box(dh, Vector3(0.5, 0.05, 1.0), Vector3(0.2, 0.75, 0), Color(0.3, 0.3, 0.32), Vector3(0, 0, -32))
				Kit.box(dh, Vector3(0.3, 0.36, 0.02), Vector3(0, 0.2, 0.455), Color(0.05, 0.05, 0.06))
				Kit.cyl(dh, 0.12, 0.06, Vector3(0.35, 0.03, 0.7), STEEL, Vector3.ZERO, 8)
			"planters":
				for i in 3:
					var pu := lc_u_or(u0, w, side) - 0.5 + 0.5 * float(i)
					Kit.cyl(n, 0.18, 0.34, p.pt(pu, alley - 0.42, 0.17), Color(0.75, 0.75, 0.72), Vector3.ZERO, 8, 0.2)
					Kit.cyl(n, 0.012, 0.9, p.pt(pu, alley - 0.42, 0.75), WOOD, Vector3.ZERO, 4)
					Kit.ball(n, 0.2, p.pt(pu, alley - 0.42, 0.68), Color(0.25, 0.5, 0.22), 6)
					Kit.ball(n, 0.05, p.pt(pu + 0.1, alley - 0.33, 0.6), Color(0.85, 0.18, 0.12), 5)
			"trike":
				var tk := Kit.group(n, p.pt(u0 + 1.0, back + 1.4), Vector3(0, 35, 0))
				Kit.cyl(tk, 0.2, 0.1, Vector3(0, 0.2, 0.4), Color(0.95, 0.75, 0.15), Vector3(0, 0, 90), 12)
				Kit.box(tk, Vector3(0.36, 0.08, 0.7), Vector3(0, 0.16, 0.0), Color(0.85, 0.15, 0.12))
				Kit.box(tk, Vector3(0.3, 0.26, 0.06), Vector3(0, 0.3, -0.24), Color(0.85, 0.15, 0.12))
				for x: float in [-0.22, 0.22]:
					Kit.cyl(tk, 0.1, 0.06, Vector3(x, 0.1, -0.28), Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 8)
				Kit.box(tk, Vector3(0.4, 0.04, 0.04), Vector3(0, 0.46, 0.36), Color(0.95, 0.75, 0.15))
			"weeds":
				for i in 9:
					var k := u0 + float(i) * 2.17
					var wu := u0 + 0.3 + (w - 0.6) * Props.rnd(k)
					var wv := back + 1.0 + (alley - back - 1.2) * Props.rnd(k + 1.0)
					for j in 4:
						Kit.box(n, Vector3(0.05, 0.35 + 0.4 * Props.rnd(k + j), 0.05), p.pt(wu + 0.05 * j, wv, 0.25), Color(0.3, 0.45 + 0.1 * Props.rnd(k + j + 3.0), 0.2), Vector3(18.0 * (Props.rnd(k + j + 5.0) - 0.5), 70.0 * j, 18.0 * (Props.rnd(k + j + 7.0) - 0.5)))
			"tyre":
				Kit.ring(n, 0.32, 0.12, p.pt(u0 + w - 0.9, alley + 0.5, 0.06), Color(0.08, 0.08, 0.09), Vector3(-90, 0, 0))
			"mattress":
				var mat := Kit.group(n, p.pt(u0 + 1.2, alley + 0.32, 0.0), Vector3(-14, 6, 0))
				Kit.box(mat, Vector3(1.3, 1.9, 0.18), Vector3(0, 0.95, 0), Color(0.82, 0.78, 0.66))
				Kit.box(mat, Vector3(0.6, 0.45, 0.01), Vector3(0.2, 1.1, 0.095), Color(0.62, 0.52, 0.38))   # the stain


static func lc_u_or(u0: float, w: float, side: String) -> float:
	return u0 + (w - 1.0 if side == "l" else 1.0)


## A window in a wall that faces `yaw` (0 the street side); `at` is the foot of
## the wall below the window's middle. Its frame stands proud, the glass sits
## back in it; lit ones glow behind their curtains; bars on the ground floor.
static func _window(n: Node3D, at: Vector3, yaw: float, w: float, y0: float, y1: float, lit: bool, o: Dictionary, ground := false, ac := false) -> void:
	var g := Kit.group(n, at, Vector3(0, yaw, 0))
	var trim: Color = o.get("trim", Color(0.86, 0.84, 0.76))
	var h := y1 - y0
	var f := 0.07
	var cy := (y0 + y1) * 0.5
	Kit.box(g, Vector3(w + 0.24, 0.14, 0.03), Vector3(0, y1 + 0.07, 0.0), o.get("lintel", Color(0.7, 0.66, 0.6)))
	Kit.box(g, Vector3(w + 0.16, 0.06, 0.14), Vector3(0, y0 - 0.03, 0.05), o.get("lintel", Color(0.7, 0.66, 0.6)))
	if o.get("boarded", false):
		Kit.box(g, Vector3(w + 0.08, h + 0.08, 0.04), Vector3(0, cy, 0.03), PLYWOOD)
		Kit.box(g, Vector3(0.05, h + 0.1, 0.02), Vector3(-w * 0.3, cy, 0.06), PLYWOOD.darkened(0.3))
		Kit.box(g, Vector3(0.05, h + 0.1, 0.02), Vector3(w * 0.3, cy, 0.06), PLYWOOD.darkened(0.3))
		return
	for x: float in [-w * 0.5 + f * 0.5, w * 0.5 - f * 0.5]:
		Kit.box(g, Vector3(f, h, 0.08), Vector3(x, cy, 0.0), trim)
	Kit.box(g, Vector3(w, f, 0.08), Vector3(0, y1 - f * 0.5, 0.0), trim)
	var glass_h := h - f
	var glass_y := y0 + glass_h * 0.5
	Kit.box(g, Vector3(w - 2.0 * f, glass_h, 0.04), Vector3(0, glass_y, 0.0), Kit.flat(WARM, 1.15) if lit else Kit.flat(NIGHT_GLASS))
	Kit.box(g, Vector3(w - 2.0 * f + 0.02, 0.05, 0.05), Vector3(0, glass_y, 0.01), trim)   # the sash rail, its ends in the frame
	if lit:
		var cloth: Color = o.get("curtain", Color(0.75, 0.3, 0.25))
		for x: float in [-1.0, 1.0]:
			Kit.box(g, Vector3((w - 2.0 * f) * 0.26, glass_h, 0.01), Vector3(x * (w - 2.0 * f) * 0.37, glass_y, 0.027), Kit.flat(cloth, 0.5))
	elif o.get("blinds", true):
		Kit.box(g, Vector3(w - 2.0 * f, glass_h * 0.4, 0.01), Vector3(0, y1 - f - glass_h * 0.2, 0.027), Color(0.82, 0.8, 0.72))
	if ground and o.get("bars", false):
		var bars := int(w / 0.13)
		for i in range(1, bars):
			Kit.cyl(g, 0.011, h + 0.08, Vector3(-w * 0.5 + w * float(i) / float(bars), cy, 0.085), IRON, Vector3.ZERO, 4)
		for y: float in [y0 + 0.08, y1 - 0.08]:
			Kit.box(g, Vector3(w + 0.04, 0.03, 0.02), Vector3(0, y, 0.1), IRON)
	if ac:
		var unit := Color(0.84, 0.82, 0.74)
		Kit.box(g, Vector3(0.62, 0.42, 0.56), Vector3(0, y0 + 0.24, 0.2), unit)
		for i in 5:
			Kit.box(g, Vector3(0.5, 0.02, 0.01), Vector3(0, y0 + 0.1 + i * 0.065, 0.485), unit.darkened(0.3))
		Kit.box(g, Vector3(0.2, 0.06, 0.012), Vector3(0, y0 + 0.4, 0.486), Color(0.4, 0.4, 0.4))
		Kit.box(g, Vector3(0.08, 0.5, 0.012), Vector3(0.12, y0 - 0.3, 0.012), Color(0.3, 0.26, 0.24, 0.45))   # the drip stain under it


## The back door, at the foot of a wall facing `yaw`; its sill is floor_y up.
static func _door(n: Node3D, at: Vector3, yaw: float, floor_y: float, o: Dictionary) -> void:
	var g := Kit.group(n, at, Vector3(0, yaw, 0))
	var trim: Color = o.get("trim", Color(0.86, 0.84, 0.76))
	var colour: Color = o.get("door", Color(0.25, 0.4, 0.32))
	var dw := 0.86
	var top := floor_y + 2.05
	Kit.box(g, Vector3(dw + 0.32, 0.14, 0.03), Vector3(0, top + 0.13, 0.0), o.get("lintel", Color(0.7, 0.66, 0.6)))
	for x: float in [-dw * 0.5 - 0.04, dw * 0.5 + 0.04]:
		Kit.box(g, Vector3(0.08, 2.1, 0.1), Vector3(x, floor_y + 1.05, 0.0), trim)
	Kit.box(g, Vector3(dw + 0.16, 0.08, 0.1), Vector3(0, top + 0.03, 0.0), trim)
	Kit.box(g, Vector3(dw + 0.2, 0.05, 0.16), Vector3(0, floor_y - 0.015, 0.06), Color(0.9, 0.89, 0.86))   # the marble sill, a centimetre over the top step
	if o.get("boarded", false):
		Kit.box(g, Vector3(dw + 0.12, 2.12, 0.04), Vector3(0, floor_y + 1.04, 0.065), PLYWOOD)
		Kit.box(g, Vector3(dw + 0.14, 0.06, 0.02), Vector3(0, floor_y + 0.6, 0.095), PLYWOOD.darkened(0.3))
		Kit.box(g, Vector3(dw + 0.14, 0.06, 0.02), Vector3(0, floor_y + 1.5, 0.095), PLYWOOD.darkened(0.3))
		return
	Kit.box(g, Vector3(dw, 2.05, 0.05), Vector3(0, floor_y + 1.025, 0.0), colour)
	var lit: bool = o.get("porch", false)
	Kit.box(g, Vector3(dw * 0.56, 0.5, 0.01), Vector3(0, floor_y + 1.55, 0.03), Kit.flat(WARM, 0.9) if "k" in o.get("lit", []) else Kit.flat(NIGHT_GLASS))
	Kit.box(g, Vector3(0.03, 0.5, 0.012), Vector3(0, floor_y + 1.55, 0.036), colour)
	Kit.box(g, Vector3(dw * 0.56, 0.03, 0.012), Vector3(0, floor_y + 1.55, 0.036), colour)
	Kit.box(g, Vector3(dw - 0.12, 0.22, 0.01), Vector3(0, floor_y + 0.16, 0.03), ALUMINIUM)
	Kit.ball(g, 0.035, Vector3(dw * 0.5 - 0.1, floor_y + 1.0, 0.06), Color(0.85, 0.7, 0.3), 6)
	if o.get("storm", false):
		var al := ALUMINIUM.darkened(0.05)
		for x: float in [-dw * 0.5 + 0.03, dw * 0.5 - 0.03]:
			Kit.box(g, Vector3(0.05, 2.0, 0.03), Vector3(x, floor_y + 1.02, 0.09), al)
		for y: float in [floor_y + 0.04, floor_y + 1.0, floor_y + 2.0]:
			Kit.box(g, Vector3(dw, 0.05, 0.03), Vector3(0, y, 0.09), al)
		Kit.box(g, Vector3(dw - 0.06, 0.94, 0.01), Vector3(0, floor_y + 1.5, 0.085), Color(0.7, 0.85, 0.92, 0.2))
	if o.has("awning"):
		var aw: Color = o["awning"]
		var roof := Kit.group(g, Vector3(0, top + 0.42, 0.42), Vector3(22, 0, 0))
		Kit.box(roof, Vector3(1.5, 0.04, 0.95), Vector3.ZERO, aw)
		for k in 4:
			Kit.box(roof, Vector3(0.18, 0.045, 0.96), Vector3(-0.56 + k * 0.37, 0.0, 0.0), Color(0.95, 0.94, 0.9))
		Kit.box(g, Vector3(1.5, 0.18, 0.02), Vector3(0, top + 0.16, 0.86), aw)
	# The porch light beside the door.
	var side := dw * 0.5 + 0.28
	Kit.box(g, Vector3(0.12, 0.18, 0.05), Vector3(side, top - 0.05, 0.03), IRON)
	Kit.box(g, Vector3(0.14, 0.2, 0.14), Vector3(side, top - 0.05, 0.12), Kit.flat(WARM, 2.4) if lit else Color(0.7, 0.72, 0.68))
	Kit.box(g, Vector3(0.18, 0.04, 0.18), Vector3(side, top + 0.07, 0.12), IRON)
	if lit:
		Kit.omni(g, Vector3(side, top - 0.2, 0.7), WARM, 0.9, 4.2)


## Concrete steps down from a back door to the yard, with an iron rail.
static func _steps(n: Node3D, at: Vector3, floor_y: float, with_rail: bool) -> void:
	var g := Kit.group(n, at)
	var look := Color(0.7, 0.69, 0.66)
	var risers := int(round(floor_y / 0.15))
	for k in risers:
		var top := floor_y - 0.15 * float(k)
		Kit.block(g, Vector3(1.1, top, 0.3), Vector3(0, 0, 0.15 + 0.3 * float(k)), look.darkened(0.03 * float(k)))
	if with_rail:
		var x := 0.52
		var a := Vector3(x, floor_y + 0.85, 0.05)
		var b := Vector3(x, 0.85, 0.3 * float(risers) + 0.1)
		rod(g, a, b, 0.02, IRON, 4)
		rod(g, Vector3(x, floor_y, 0.12), Vector3(x, floor_y + 0.85, 0.12), 0.02, IRON, 4)
		rod(g, Vector3(x, 0.0, 0.3 * float(risers) + 0.05), Vector3(x, 0.85, 0.3 * float(risers) + 0.05), 0.02, IRON, 4)


## A TV aerial on a mast, standing on a roof at `at`.
static func _aerial(n: Node3D, at: Vector3) -> void:
	var g := Kit.group(n, at, Vector3(0, 25, 0))
	var metal := Color(0.7, 0.72, 0.74)
	Kit.cyl(g, 0.03, 2.9, Vector3(0, 1.45, 0), metal, Vector3.ZERO, 5)
	Kit.box(g, Vector3(0.05, 0.05, 1.8), Vector3(0, 2.75, 0), metal)                  # the boom
	var widths := [1.5, 1.3, 1.1, 0.95, 0.8, 0.7]
	for i in widths.size():
		Kit.box(g, Vector3(widths[i], 0.03, 0.03), Vector3(0, 2.75, -0.8 + i * 0.32), metal)
	rod(g, Vector3(-0.35, 2.75, 0.85), Vector3(0, 2.95, 0.85), 0.012, metal, 3)
	rod(g, Vector3(0.35, 2.75, 0.85), Vector3(0, 2.95, 0.85), 0.012, metal, 3)
	for k in 3:                                                                         # the guy wires
		var ang := TAU * float(k) / 3.0 + 0.4
		rod(g, Vector3(0, 1.8, 0), Vector3(1.2 * cos(ang), 0.0, 1.2 * sin(ang)), 0.006, Color(0.5, 0.5, 0.52), 3)


## A metal or plastic garbage can at `at`. lid: "on", "off" (on the ground beside it) or "tilt".
static func _can(n: Node3D, at: Vector3, look: Color, lid := "on", turn := 0.0) -> void:
	var g := Kit.group(n, at, Vector3(0, turn, 0))
	Kit.cyl(g, 0.22, 0.74, Vector3(0, 0.37, 0), look, Vector3.ZERO, 10, 0.25)
	for y: float in [0.2, 0.5]:
		Kit.cyl(g, 0.23 + 0.04 * y, 0.03, Vector3(0, y, 0), look.darkened(0.15), Vector3.ZERO, 10)
	for x: float in [-0.26, 0.26]:
		Kit.box(g, Vector3(0.04, 0.05, 0.12), Vector3(x, 0.62, 0), look.darkened(0.3))
	match lid:
		"off":
			Kit.cyl(g, 0.24, 0.24, Vector3(0, 0.62, 0), Color(0.09, 0.09, 0.1), Vector3.ZERO, 8, 0.2)    # the bag showing
			var cap := Kit.group(g, Vector3(0.36, 0.27, 0.12), Vector3(0, 0, 78))
			Kit.cyl(cap, 0.28, 0.05, Vector3.ZERO, look.darkened(0.08), Vector3.ZERO, 10)
			Kit.box(cap, Vector3(0.14, 0.05, 0.03), Vector3(0, 0.05, 0), look.darkened(0.3))
		"tilt":
			var cap := Kit.group(g, Vector3(0.0, 0.8, 0.0), Vector3(0, 0, 14))
			Kit.cyl(cap, 0.28, 0.05, Vector3.ZERO, look.darkened(0.08), Vector3.ZERO, 10)
			Kit.box(cap, Vector3(0.14, 0.05, 0.03), Vector3(0, 0.05, 0), look.darkened(0.3))
			Kit.ball(g, 0.18, Vector3(-0.05, 0.74, 0.02), Color(0.09, 0.09, 0.1), 6)
		_:
			Kit.cyl(g, 0.28, 0.05, Vector3(0, 0.765, 0), look.darkened(0.08), Vector3.ZERO, 10)
			Kit.box(g, Vector3(0.14, 0.05, 0.03), Vector3(0, 0.81, 0), look.darkened(0.3))


## A run of low chain link (it is never walked to, so it takes no floor).
static func _chain(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, h: float) -> void:
	var length := to - from
	if length < 0.05:
		return
	var mid := (from + to) * 0.5
	if along_u:
		Kit.box(n, Vector3(length, h - 0.08, 0.01), p.pt(mid, at, (h - 0.08) * 0.5 + 0.04), Outdoor.chain_link())
		rod(n, p.pt(from, at, h), p.pt(to, at, h), 0.02, GALV, 5)
	else:
		Kit.box(n, Vector3(0.01, h - 0.08, length), p.pt(at, mid, (h - 0.08) * 0.5 + 0.04), Outdoor.chain_link())
		rod(n, p.pt(at, from, h), p.pt(at, to, h), 0.02, GALV, 5)
	var posts := maxi(int(round(length / 2.4)), 1)
	for i in posts + 1:
		var w := from + length * float(i) / float(posts)
		Kit.cyl(n, 0.03, h + 0.06, p.pt(w, at, (h + 0.06) * 0.5) if along_u else p.pt(at, w, (h + 0.06) * 0.5), GALV, Vector3.ZERO, 6)


## A chain-link gate between g0 and g1 on the alley fence, hung at g0; open swings it into the yard.
static func _chain_gate(p: Node3D, n: Node3D, at: float, g0: float, g1: float, h: float, open: bool, look: Color) -> void:
	var leaf := Kit.group(n, p.pt(g0 + 0.04, at), Vector3(0, 70.0 if open else 0.0, 0))
	var w := g1 - g0 - 0.08
	Kit.box(leaf, Vector3(w, h - 0.12, 0.01), Vector3(w * 0.5, h * 0.5, 0), Outdoor.chain_link())
	for y: float in [0.06, h - 0.06]:
		rod(leaf, Vector3(0, y, 0), Vector3(w, y, 0), 0.018, look, 4)
	for x: float in [0.0, w]:
		rod(leaf, Vector3(x, 0.06, 0), Vector3(x, h - 0.06, 0), 0.018, look, 4)
	Kit.cyl(n, 0.04, h + 0.1, p.pt(g1, at, (h + 0.1) * 0.5), look, Vector3.ZERO, 6)


## A board fence (the old wooden kind, gone grey), h high.
static func _boards(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, h: float) -> void:
	var length := to - from
	if length < 0.05:
		return
	var mid := (from + to) * 0.5
	var look := Outdoor.tex("out_boards", 1.2, Color(0.45, 0.38, 0.3))
	var rail := Color(0.36, 0.32, 0.28)
	if along_u:
		Kit.box(n, Vector3(length, h, 0.04), p.pt(mid, at, h * 0.5), look)
		for y: float in [0.3, h - 0.3]:
			Kit.box(n, Vector3(length, 0.09, 0.05), p.pt(mid, at - 0.045, y), rail)
	else:
		Kit.box(n, Vector3(0.04, h, length), p.pt(at, mid, h * 0.5), look)
		for y: float in [0.3, h - 0.3]:
			Kit.box(n, Vector3(0.05, 0.09, length), p.pt(at + 0.045, mid, y), rail)


## A board gate, hung at g0; open swings it into the yard.
static func _board_gate(p: Node3D, n: Node3D, at: float, g0: float, g1: float, h: float, open: bool) -> void:
	var leaf := Kit.group(n, p.pt(g0 + 0.02, at), Vector3(0, 80.0 if open else 0.0, 0))
	var w := g1 - g0 - 0.04
	Kit.box(leaf, Vector3(w, h - 0.05, 0.04), Vector3(w * 0.5, h * 0.5, 0.0), Outdoor.tex("out_boards", 1.2, Color(0.45, 0.38, 0.3), Color.WHITE, false))
	Kit.box(leaf, Vector3(w, 0.1, 0.03), Vector3(w * 0.5, 0.4, -0.035), Color(0.36, 0.32, 0.28))
	Kit.box(leaf, Vector3(w, 0.1, 0.03), Vector3(w * 0.5, h - 0.4, -0.035), Color(0.36, 0.32, 0.28))
	Kit.box(leaf, Vector3(0.1, 0.03, 0.03), Vector3(w - 0.12, 1.0, 0.035), IRON)


# ---------------------------------------------------- across the alley: poles

## A wooden utility pole at (u, v) in the alley: a crossarm with three wires'
## insulators, a lower arm for the phone line, perhaps a transformer and a
## light. Returns where the wires hang from, in world space: [left end, middle,
## right end, phone]; the plan strings them pole to pole.
static func utility_pole(p: Node3D, n: Node3D, u: float, v: float, h := 9.4, transformer := false, light := false) -> Array:
	var g := Kit.group(n, p.pt(u, v))
	var wood := Color(0.36, 0.28, 0.22)
	Kit.cyl(g, 0.15, h, Vector3(0, h * 0.5, 0), wood, Vector3.ZERO, 8, 0.11)
	Kit.box(g, Vector3(2.4, 0.12, 0.12), Vector3(0, h - 0.45, 0), wood.darkened(0.1))
	for x: float in [-1.0, 1.0]:
		rod(g, Vector3(0, h - 1.05, 0), Vector3(x * 0.85, h - 0.47, 0), 0.025, IRON, 4)         # the braces
	var glass := Color(0.42, 0.62, 0.55)
	for x: float in [-1.05, 1.05]:
		Kit.cyl(g, 0.045, 0.16, Vector3(x, h - 0.31, 0.0), glass, Vector3.ZERO, 6)
	Kit.cyl(g, 0.045, 0.16, Vector3(0, h + 0.02, 0), glass, Vector3.ZERO, 6)            # the middle one rides on the pole's top
	Kit.box(g, Vector3(1.2, 0.1, 0.1), Vector3(0, h - 2.0, 0), wood.darkened(0.1))
	var tops: Array = [p.pt(u - 1.05, v, h - 0.22), p.pt(u, v, h + 0.1), p.pt(u + 1.05, v, h - 0.22), p.pt(u - 0.5, v, h - 1.95)]
	for k in 9:                                                                                  # the climbing steps
		Kit.box(g, Vector3(0.24, 0.03, 0.03), Vector3(0, 2.4 + k * 0.45, 0), IRON, Vector3(0, 90.0 * (k % 2), 0))
	Kit.box(g, Vector3(0.16, 0.08, 0.01), Vector3(0, 1.8, 0.155), Color(0.85, 0.75, 0.2))       # the pole's tag
	if transformer:
		Kit.cyl(g, 0.3, 0.95, Vector3(0, h - 2.9, -0.42), Color(0.5, 0.53, 0.52), Vector3.ZERO, 10)
		Kit.cyl(g, 0.32, 0.05, Vector3(0, h - 2.4, -0.42), Color(0.45, 0.47, 0.46), Vector3.ZERO, 10)
		Kit.box(g, Vector3(0.08, 0.5, 0.2), Vector3(0, h - 2.9, -0.15), Color(0.4, 0.42, 0.42))
	if light:
		cobra(g, h - 3.3, 1.7, 6.0, 10.0)
	return tops
