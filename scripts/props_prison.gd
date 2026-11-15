extends RefCounted
## Fittings for the county jail (plans/prison.gd): razor wire, the visiting
## booths and their handsets, the dayroom's bolted-down tables, the mess hall's
## tables and serving line, the officer's station, the steel stair to the upper
## tier, showers, the vehicle gate, the gun tower and the rest. Every word on
## them is a placeholder.
##
## As in props.gd: `p` is the Place, `b` the band a thing stands in, (u, v) the
## middle of the floor it takes, `yaw` the way its front faces (0 the street, 90
## right, 180 the back, 270 left). Things on a wall go on the wall's face.

const Props := preload("res://scripts/props.gd")
const Park := preload("res://scripts/props_park.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const WIRE := Color(0.8, 0.82, 0.85)          # razor wire: bright galvanised, so it shows against the sky and the chain link
const STEEL := Props.STEEL
const IRON := Props.IRON
const DARK := Props.DARK
const PAINTED := Color(0.4, 0.5, 0.62)        # the dayroom's painted steel
const STAINLESS := Color(0.76, 0.78, 0.8)
const SAFETY := Color(0.95, 0.76, 0.16)
const ORANGE := Color(0.91, 0.44, 0.14)        # the jumpsuit's (prison_jumpsuit.py: 232, 112, 36)
const CONCRETE := Color(0.66, 0.65, 0.62)
const GLASS := Color(0.62, 0.8, 0.88, 0.25)


# ------------------------------------------------------------------ the wire

## A coil of razor wire from a to b (in the parent's space): loops of bright wire
## leaning forward and back by turns along the run, the way a concertina coil
## lies along the top of a fence. One mesh for the whole run.
static func razor(parent: Node3D, a: Vector3, b: Vector3, r := 0.24) -> MultiMeshInstance3D:
	var run := b - a
	var length := run.length()
	var n := maxi(int(length / 0.085), 2)
	var ring := TorusMesh.new()
	ring.inner_radius = r - 0.014
	ring.outer_radius = r
	ring.rings = 14
	ring.ring_segments = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ring
	mm.instance_count = n
	var along := run / length
	var face := Basis(Quaternion(Vector3.UP, along))         # a torus's axis is its Y: along the run
	var across := along.cross(Vector3.UP).normalized() if absf(along.y) < 0.99 else Vector3.RIGHT
	for i in n:
		var lean := deg_to_rad(32.0 if i % 2 == 0 else -32.0)
		var size := 1.0 - 0.08 * Props.rnd(float(i) * 1.7 + length)
		var turn := Basis(across, lean) * face * Basis.from_scale(Vector3(size, 1.0, size))     # (the loop a little smaller by turns)
		mm.set_instance_transform(i, Transform3D(turn, a + run * ((float(i) + 0.5) / float(n))))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = Kit.flat(WIRE)
	parent.add_child(mi)
	return mi


## Razor wire along the top of a fence on the plan: over each run between the
## gaps, sitting on the top rail (h). Built in `n`.
static func wire_on(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, gaps: Array, h: float) -> void:
	var cursor := from
	var runs: Array = []
	for g: Array in gaps:
		runs.append([cursor, g[0]])
		cursor = g[1]
	runs.append([cursor, to])
	for run: Array in runs:
		if run[1] - run[0] < 0.3:
			continue
		var a: Vector3 = p.pt(run[0] + 0.1, at, h + 0.2) if along_u else p.pt(at, run[0] + 0.1, h + 0.2)
		var e: Vector3 = p.pt(run[1] - 0.1, at, h + 0.2) if along_u else p.pt(at, run[1] - 0.1, h + 0.2)
		razor(n, a, e)


## A gate leaf of chain link swung right back against the inside of the fence
## (it is open): hung at u = hinge on the fence at v, reaching `w` to the left.
static func open_leaf(p: Node3D, n: Node3D, v: float, hinge: float, w: float, h: float) -> void:
	var leaf := Kit.group(n, p.pt(hinge - w, v - 0.09))
	Kit.box(leaf, Vector3(w - 0.06, h - 0.14, 0.01), Vector3(w * 0.5, h * 0.5, 0), Outdoor.chain_link())
	for y: float in [0.07, h * 0.5, h - 0.07]:
		Kit.box(leaf, Vector3(w, 0.04, 0.04), Vector3(w * 0.5, y, 0), Park.GALV)
	for x: float in [0.02, w - 0.02]:
		Kit.box(leaf, Vector3(0.04, h, 0.04), Vector3(x, h * 0.5, 0), Park.GALV)
	Kit.cyl(n, 0.055, h + 0.12, p.pt(hinge, v - 0.04, (h + 0.12) * 0.5), Park.GALV, Vector3.ZERO, 8)


## The vehicle gate in the front fence, shut: chain link in a heavy steel frame
## with a cross brace, on its track, from u0 to u1 along the fence at v, h high,
## razor wire along its top and a sign on it.
static func vehicle_gate(p: Node3D, n: Node3D, v: float, u0: float, u1: float, h: float) -> void:
	var mid := (u0 + u1) * 0.5
	var w := u1 - u0
	Kit.box(n, Vector3(w - 0.2, h - 0.2, 0.012), p.pt(mid, v, h * 0.5 + 0.06), Outdoor.chain_link())
	var frame := Color(0.36, 0.38, 0.4)
	for y: float in [0.12, h * 0.52, h - 0.02]:
		Kit.box(n, Vector3(w - 0.1, 0.08, 0.08), p.pt(mid, v, y), frame)
	for k in 5:
		var x := u0 + 0.08 + (w - 0.16) * float(k) / 4.0
		Kit.box(n, Vector3(0.08, h - 0.04, 0.08), p.pt(x, v, h * 0.5 + 0.02), frame)
	for half: Array in [[u0 + 0.1, mid], [mid, u1 - 0.1]]:            # the braces, one in each half
		Kit.tube(n, p.pt(half[0], v + 0.05, 0.16), p.pt(half[1], v + 0.05, h - 0.06), 0.03, frame, 5)
	for u: float in [u0, u1]:                                          # the posts it runs between
		Kit.cyl(n, 0.09, h + 0.3, p.pt(u, v + 0.12, (h + 0.3) * 0.5), frame.darkened(0.2), Vector3.ZERO, 10)
	Kit.box(n, Vector3(w + 0.6, 0.05, 0.22), p.pt(mid, v, 0.025), DARK)     # the track
	Kit.box(n, Vector3(1.6, 0.6, 0.03), p.pt(mid, v + 0.06, 1.55), Color(0.92, 0.9, 0.84))
	Props.words(n, "AUTHORIZED", p.pt(mid, v + 0.08, 1.66), 0.13, Color(0.7, 0.12, 0.1))
	Props.words(n, "VEHICLES ONLY", p.pt(mid, v + 0.08, 1.45), 0.13, Color(0.7, 0.12, 0.1))
	razor(n, p.pt(u0 + 0.1, v, h + 0.2), p.pt(u1 - 0.1, v, h + 0.2))


## A gun tower outside the wire, empty: four concrete legs, a cab glazed all
## round under a flat roof with a searchlight on it, a ladder up one leg.
static func tower(p: Node3D, n: Node3D, u: float, v: float, h := 7.0) -> Node3D:
	var g := Kit.group(n, p.pt(u, v))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.3, h, 0.3), Vector3(x, h * 0.5, z), CONCRETE)
	for y: float in [h * 0.35, h * 0.7]:        # ties between the legs
		Kit.box(g, Vector3(2.0, 0.14, 0.14), Vector3(0, y, 1.0), CONCRETE.darkened(0.08))
		Kit.box(g, Vector3(2.0, 0.14, 0.14), Vector3(0, y, -1.0), CONCRETE.darkened(0.08))
	Kit.box(g, Vector3(3.0, 0.25, 3.0), Vector3(0, h + 0.125, 0), CONCRETE)
	var cab := Color(0.58, 0.6, 0.6)
	Kit.box(g, Vector3(2.8, 1.0, 2.8), Vector3(0, h + 0.75, 0), cab)
	for x: float in [-1.36, 1.36]:
		for z: float in [-1.36, 1.36]:
			Kit.box(g, Vector3(0.1, 1.3, 0.1), Vector3(x, h + 1.9, z), cab.darkened(0.2))
	Kit.pane(Kit.box(g, Vector3(2.62, 1.24, 2.62), Vector3(0, h + 1.88, 0), Color(0.3, 0.42, 0.5, 0.55)))
	Kit.box(g, Vector3(3.3, 0.18, 3.3), Vector3(0, h + 2.64, 0), cab.darkened(0.35))
	Kit.cyl(g, 0.2, 0.32, Vector3(0.8, h + 2.9, 0.8), DARK, Vector3(-60, 45, 0), 10)        # the searchlight
	Kit.cyl(g, 0.17, 0.02, Vector3(0.8, h + 3.04, 0.88), Kit.flat(Color(0.9, 0.95, 1.0), 0.6), Vector3(-60, 45, 0), 10)
	for k in int(h / 0.32):                     # the ladder up the front left leg
		Kit.box(g, Vector3(0.36, 0.03, 0.03), Vector3(-1.0, 0.3 + k * 0.32, 1.2), IRON)
	for x: float in [-1.17, -0.83]:
		Kit.box(g, Vector3(0.04, h, 0.04), Vector3(x, h * 0.5, 1.2), IRON)
	return g


# ------------------------------------------------------------- front of house

## A roll-up steel door on a wall's face, shut: ribbed slats, the guides either
## side, the hood over it. u0..u1 along the wall at v, its face to `face` (+1
## the street side), h high. Built in `n`.
static func rollup(p: Node3D, n: Node3D, v: float, face: float, u0: float, u1: float, h: float) -> void:
	var at := v + face * 0.075
	var slats := Kit.tex("in_ribbed", 0.5, Color(0.62, 0.64, 0.66), false, Color(0.78, 0.8, 0.82))
	p.slab(n, true, at + face * 0.03, u0, u1, 0.0, h, 0.04, slats)
	p.slab(n, true, at + face * 0.06, u0 - 0.06, u1 + 0.06, h, h + 0.42, 0.12, Color(0.42, 0.44, 0.46))     # the hood
	for u: float in [u0 - 0.05, u1 + 0.05]:
		p.slab(n, true, at + face * 0.045, u - 0.05, u + 0.05, 0.0, h, 0.07, Color(0.36, 0.38, 0.4))
	p.slab(n, true, at + face * 0.06, u0 + 0.01, u1 - 0.01, 0.0, 0.12, 0.06, DARK)       # the bottom bar's rubber (its ends off the slats')


## A slit window in a wall's face: a deep, dark recess in a concrete surround
## (no glass shows: it is too narrow and too deep). `face` +1 the street side.
static func slit(p: Node3D, n: Node3D, v: float, face: float, u: float, y0: float, h := 1.3, w := 0.2) -> void:
	var at := v + face * 0.075
	p.slab(n, true, at + face * 0.02, u - w * 0.5 - 0.08, u + w * 0.5 + 0.08, y0 - 0.08, y0 + h + 0.08, 0.04, CONCRETE.lightened(0.12))
	p.slab(n, true, at + face * 0.045, u - w * 0.5, u + w * 0.5, y0, y0 + h, 0.02, Color(0.12, 0.13, 0.16))


## A flagpole: a tall white pole on a concrete foot, a gold ball, a flag
## (stripes and a blue corner) out from its top. Takes a little floor.
static func flagpole(p: Node3D, b: int, u: float, v: float, h := 7.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	Kit.block(g, Vector3(0.5, 0.2, 0.5), Vector3.ZERO, CONCRETE)
	Kit.cyl(g, 0.06, h, Vector3(0, h * 0.5 + 0.2, 0), Color(0.92, 0.92, 0.9), Vector3.ZERO, 8, 0.035)
	Kit.ball(g, 0.08, Vector3(0, h + 0.27, 0), Color(0.85, 0.7, 0.28), 8)
	var flag := Kit.group(g, Vector3(0.05, h - 0.5, 0))
	for k in 7:
		Kit.box(flag, Vector3(1.6, 0.13, 0.01), Vector3(0.8, -k * 0.13, 0.0), Color(0.75, 0.15, 0.15) if k % 2 == 0 else Color(0.95, 0.94, 0.9))
	Kit.box(flag, Vector3(0.7, 0.52, 0.012), Vector3(0.35, -0.2, 0.004), Color(0.16, 0.2, 0.45))      # (its faces off the stripes')
	return g


## The jail's name on a low concrete wall out front, its face to `yaw`.
static func name_wall(p: Node3D, b: int, u: float, v: float, yaw: float, text: String, w := 3.2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.4)
	Kit.bevel_block(g, Vector3(w, 0.95, 0.4), Vector3.ZERO, CONCRETE.lightened(0.08), 0.03)
	Kit.box(g, Vector3(w + 0.1, 0.08, 0.48), Vector3(0, 0.99, 0), CONCRETE.darkened(0.12))
	Props.words(g, text, Vector3(0, 0.55, 0.205), 0.26, Color(0.16, 0.2, 0.3))
	return g


## The visitors' walk-through metal detector: two grey pillars and a head, the
## way through running along `yaw` (0: front to back; 90: left to right).
## Each pillar takes floor; the way between them is about a metre.
static func walk_frame(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	var grey := Color(0.72, 0.72, 0.7)
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.14, 2.05, 0.55), Vector3(side * 0.57, 0, 0), grey)
		Kit.box(g, Vector3(0.03, 1.2, 0.04), Vector3(side * 0.5, 1.0, 0.0), Color(0.2, 0.21, 0.23))
		if posmod(int(round(yaw / 90.0)), 2) == 1:
			p.block(u - 0.275, v + side * 0.57 - 0.07, u + 0.275, v + side * 0.57 + 0.07)
		else:
			p.block(u + side * 0.57 - 0.07, v - 0.275, u + side * 0.57 + 0.07, v + 0.275)
	Kit.box(g, Vector3(1.28, 0.16, 0.55), Vector3(0, 2.13, 0), grey)
	Kit.box(g, Vector3(0.16, 0.07, 0.02), Vector3(0, 2.13, 0.285), Kit.flat(Color(0.3, 0.95, 0.4), 1.2))
	return g


# --------------------------------------------------------------- the visiting room

## A visiting booth's telephone on a wall's face: a steel box, the black
## handset hung on its side, its armoured cord in a loop under it. Built in `n`.
static func handset(p: Node3D, n: Node3D, u: float, v: float, yaw: float, y := 1.3) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.12, 0.2, 0.06), Vector3(0, y, 0.03), STAINLESS, 0.012)
	Kit.box(g, Vector3(0.06, 0.07, 0.01), Vector3(-0.012, y + 0.03, 0.065), Color(0.24, 0.25, 0.28))
	var hs := Kit.group(g, Vector3(0.1, y - 0.02, 0.05))
	Kit.bevel(hs, Vector3(0.045, 0.2, 0.04), Vector3.ZERO, DARK, 0.015)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(hs, Vector3(0.06, 0.055, 0.06), Vector3(0, s * 0.095, 0.008), DARK, 0.02)
	Kit.tube(g, Vector3(0.0, y - 0.1, 0.04), Vector3(0.04, y - 0.36, 0.05), 0.008, STEEL, 5)
	Kit.tube(g, Vector3(0.04, y - 0.36, 0.05), Vector3(0.1, y - 0.14, 0.05), 0.008, STEEL, 5)
	return g


## The visiting booths along a glass wall that runs left to right at v = at,
## from u0 to u1: on its `face` side (+1 the street side, -1 the back), a steel
## shelf `deep` out from the wall under the windows, a partition `out` further
## between each two windows, and a handset on the wall beside each. `windows`:
## [[a, b], ...] along u. The shelf and partitions take floor; `numbers` paints
## each booth's number over its window. Built in `n`; the handsets and numbers
## in `on_wall` if it is given (the wall's own node, when it is a front: they go
## with it when it is cut away, and the shelf stays).
static func booths(p: Node3D, n: Node3D, at: float, face: float, u0: float, u1: float, windows: Array, deep := 0.2, numbers := false, out := 0.3, on_wall: Node3D = null) -> void:
	var hung: Node3D = on_wall if on_wall else n
	var wall := at + face * 0.075 + face * 0.004              # off the wall's face (and its paint)
	var outer := wall + face * deep
	var mid := (u0 + u1) * 0.5
	var lo := minf(wall, outer)
	var hi := maxf(wall, outer)
	Kit.box(n, Vector3(u1 - u0, 0.04, deep), p.pt(mid, (lo + hi) * 0.5, 0.8), STAINLESS)
	Kit.box(n, Vector3(u1 - u0 - 0.01, 0.76, 0.025), p.pt(mid, outer - face * 0.03, 0.39), IRON)       # the panel under it
	p.block(u0, lo, u1, hi)
	for i in windows.size():
		var w: Array = windows[i]
		handset(p, hung, float(w[1]) + 0.14, at + face * 0.075, 0.0 if face > 0.0 else 180.0)
		if numbers:
			Props.words(hung, str(i + 1), p.pt((float(w[0]) + float(w[1])) * 0.5, at + face * 0.085, 2.3), 0.2, Color(0.95, 0.94, 0.88), 0.0 if face > 0.0 else 180.0)
		if i + 1 < windows.size():                              # a partition between this window and the next
			var pu := (float(w[1]) + float(windows[i + 1][0])) * 0.5
			var reach := deep + out
			var foot := wall + face * 0.006                     # (its end off the shelf's and the paint's faces)
			var pl := minf(foot, foot + face * reach)
			var ph := maxf(foot, foot + face * reach)
			Kit.box(n, Vector3(0.04, 1.45, reach), p.pt(pu, (pl + ph) * 0.5, 0.725), Color(0.5, 0.56, 0.62))
			Kit.box(n, Vector3(0.06, 0.04, reach + 0.01), p.pt(pu, (pl + ph) * 0.5 + face * 0.005, 1.47), IRON)
			p.block(pu - 0.02, pl, pu + 0.02, ph)


# ---------------------------------------------------------------- inside

## A dayroom table: a round steel top on a pedestal bolted to the floor, four
## round stools on arms from its foot. Painted steel.
static func steel_table(p: Node3D, b: int, u: float, v: float, look := PAINTED, turn := 45.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 1.5, 1.5)
	Kit.cyl(g, 0.24, 0.03, Vector3(0, 0.015, 0), look.darkened(0.3), Vector3.ZERO, 12)
	Kit.cyl(g, 0.07, 0.72, Vector3(0, 0.38, 0), look, Vector3.ZERO, 10)
	Kit.cyl(g, 0.485, 0.02, Vector3(0, 0.725, 0), look.darkened(0.18), Vector3.ZERO, 18)
	Kit.cyl(g, 0.48, 0.04, Vector3(0, 0.755, 0), look.lightened(0.14), Vector3.ZERO, 18)
	for k in 4:
		var a := deg_to_rad(turn + 90.0 * k)
		var at := Vector3(sin(a), 0, cos(a)) * 0.6
		Kit.tube(g, Vector3(0, 0.12, 0), at + Vector3(0, 0.12, 0), 0.025, look.darkened(0.12), 6)
		Kit.cyl(g, 0.03, 0.32, at + Vector3(0, 0.28, 0), look.darkened(0.12), Vector3.ZERO, 6)
		Kit.cyl(g, 0.15, 0.04, at + Vector3(0, 0.46, 0), look.lightened(0.14), Vector3.ZERO, 12)
	return g


## A mess hall table: a long stainless top with a fixed bench along each side,
## all on one steel frame bolted down. w long, along the yaw's left and right.
static func mess_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.4, look := STAINLESS) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 1.7)
	Kit.box(g, Vector3(w, 0.04, 0.76), Vector3(0, 0.76, 0), look)
	for x: float in [-w * 0.5 + 0.25, w * 0.5 - 0.25]:
		Kit.box(g, Vector3(0.06, 0.73, 0.06), Vector3(x, 0.375, 0), IRON)
		Kit.box(g, Vector3(0.05, 0.05, 1.6), Vector3(x, 0.15, 0), IRON)
		for z: float in [-0.65, 0.65]:
			Kit.box(g, Vector3(0.05, 0.29, 0.05), Vector3(x, 0.3, z), IRON)
	for z: float in [-0.65, 0.65]:
		Kit.box(g, Vector3(w - 0.1, 0.04, 0.3), Vector3(0, 0.465, z), look.darkened(0.14))
	return g


## A food tray on a table top (in the table's group, on its top at y).
static func tray(parent: Node3D, pos: Vector3, turn := 0.0) -> void:
	var t := Kit.group(parent, pos, Vector3(0, turn, 0))
	Kit.box(t, Vector3(0.42, 0.02, 0.3), Vector3(0, 0.01, 0), Color(0.86, 0.55, 0.2))
	Kit.box(t, Vector3(0.16, 0.02, 0.12), Vector3(-0.1, 0.025, -0.06), Color(0.9, 0.84, 0.62))      # the beans, the bread
	Kit.box(t, Vector3(0.12, 0.02, 0.1), Vector3(0.12, 0.025, -0.07), Color(0.55, 0.35, 0.22))
	Kit.box(t, Vector3(0.2, 0.025, 0.09), Vector3(0.0, 0.026, 0.08), Color(0.92, 0.9, 0.82))


## The mess hall's serving line, w long, its front at +z: a stainless counter
## with the pans let into its top, the tray slide along its front, the glass
## guard over the pans on steel posts. Takes 1.0 m of floor front to back.
static func serving_line(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 3.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 1.0)
	Kit.block(g, Vector3(w, 0.9, 0.7), Vector3(0, 0, -0.15), STAINLESS)
	Kit.box(g, Vector3(w - 0.04, 0.12, 0.66), Vector3(0, 0.08, -0.15), DARK)        # the kick plate
	var food := [Color(0.85, 0.72, 0.4), Color(0.45, 0.6, 0.3), Color(0.6, 0.38, 0.24), Color(0.92, 0.88, 0.74), Color(0.8, 0.5, 0.25)]
	var pans := int(w / 0.62)
	for i in pans:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(pans)
		Kit.box(g, Vector3(0.5, 0.012, 0.36), Vector3(x, 0.906, -0.15), Color(0.5, 0.52, 0.54))
		Kit.box(g, Vector3(0.44, 0.012, 0.3), Vector3(x, 0.913, -0.15), food[i % food.size()])
	Kit.box(g, Vector3(w, 0.03, 0.28), Vector3(0, 0.86, 0.36), STAINLESS.darkened(0.1))     # the tray slide
	for x: float in [-w * 0.5 + 0.1, 0.0, w * 0.5 - 0.1]:
		Kit.box(g, Vector3(0.03, 0.2, 0.2), Vector3(x, 0.74, 0.3), IRON)
		Kit.cyl(g, 0.014, 0.55, Vector3(x, 1.17, -0.05), STEEL, Vector3.ZERO, 6)
	Kit.pane(Kit.box(g, Vector3(w - 0.1, 0.02, 0.42), Vector3(0, 1.42, 0.02), GLASS, Vector3(-18, 0, 0)))
	for i in 3:                                 # a stack of trays at the start of the line
		Kit.box(g, Vector3(0.42, 0.02, 0.3), Vector3(w * 0.5 - 0.3, 0.885 + 0.025 * i, 0.36), Color(0.86, 0.55, 0.2).darkened(0.05 * i))
	return g


## The officer's station on the dayroom floor: a tall closed desk, w wide, its
## front (+z) to the dayroom and the officer behind it: a monitor, the log, the
## phone, a radio on its charger, the unit's letter on its front.
static func station(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.2, letter := "A") -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.75)
	var body := Color(0.28, 0.33, 0.42)
	Kit.bevel_block(g, Vector3(w, 1.1, 0.6), Vector3(0, 0, 0.0), body, 0.02)
	Kit.box(g, Vector3(w + 0.08, 0.05, 0.75), Vector3(0, 1.125, -0.05), Color(0.62, 0.6, 0.55))
	Kit.box(g, Vector3(w - 0.3, 0.42, 0.012), Vector3(0, 0.62, 0.306), body.lightened(0.12))
	Props.words(g, letter, Vector3(0, 0.66, 0.314), 0.3, Color(0.95, 0.76, 0.18))
	Kit.bevel(g, Vector3(0.5, 0.34, 0.06), Vector3(-0.45, 1.36, -0.22), DARK, 0.015)
	Kit.box(g, Vector3(0.44, 0.27, 0.01), Vector3(-0.45, 1.37, -0.187), Kit.flat(Color(0.48, 0.66, 0.74), 0.8))
	Kit.box(g, Vector3(0.06, 0.12, 0.06), Vector3(-0.45, 1.2, -0.24), DARK)
	Kit.box(g, Vector3(0.34, 0.03, 0.24), Vector3(0.35, 1.165, -0.05), Color(0.2, 0.3, 0.55))       # the log
	Kit.box(g, Vector3(0.3, 0.01, 0.22), Vector3(0.36, 1.185, -0.05), Props.PAPER)
	Kit.box(g, Vector3(0.12, 0.05, 0.18), Vector3(0.82, 1.175, -0.15), DARK)                         # the radio's charger
	Kit.box(g, Vector3(0.06, 0.18, 0.04), Vector3(0.82, 1.29, -0.15), Color(0.2, 0.2, 0.22))
	return g


## A cell's slab bed: a concrete plinth with a thin blue mattress on it.
static func slab_bed(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.95, 0.75)
	Kit.block(g, Vector3(1.95, 0.42, 0.75), Vector3.ZERO, CONCRETE)
	Kit.box(g, Vector3(1.8, 0.06, 0.66), Vector3(0, 0.45, 0.0), Color(0.34, 0.42, 0.52))
	return g


## Steel wire shelving w wide, its front +z, stacked with what a new prisoner is
## issued: folded orange jumpsuits, white towels and sheets, pairs of rubber
## sandals on the bottom shelf.
static func issue_shelf(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.45)
	_rack(g, w, 0.45, 1.8)
	var cols := int(w / 0.4)
	for i in cols:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(cols)
		for k in 3:          # top shelf: jumpsuits; middle: towels and sheets
			Kit.box(g, Vector3(0.32, 0.06, 0.3), Vector3(x, 1.27 + k * 0.065, 0.0), ORANGE.darkened(0.04 * (k % 2)))
			Kit.box(g, Vector3(0.32, 0.06, 0.3), Vector3(x, 0.72 + k * 0.065, 0.0), Color(0.94, 0.94, 0.92) if i % 2 == 0 else Color(0.86, 0.9, 0.94))
		Kit.box(g, Vector3(0.12, 0.04, 0.26), Vector3(x - 0.07, 0.18, 0.0), Color(0.2, 0.3, 0.55))      # sandals
		Kit.box(g, Vector3(0.12, 0.04, 0.26), Vector3(x + 0.07, 0.18, 0.0), Color(0.2, 0.3, 0.55))
	return g


## Shelving of people's own things, bagged and tagged: a soft lump of clothes
## in each clear sack, a white tag on each. w wide, its front +z.
static func property_shelf(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.45)
	_rack(g, w, 0.45, 1.8)
	var cloth := [Color(0.25, 0.35, 0.6), Color(0.15, 0.15, 0.17), Color(0.7, 0.2, 0.18), Color(0.55, 0.5, 0.42), Color(0.3, 0.45, 0.3), Color(0.85, 0.82, 0.75)]
	var cols := int(w / 0.36)
	for row in 3:
		for i in cols:
			var x := -w * 0.5 + (float(i) + 0.5) * w / float(cols)
			var y := 0.17 + row * 0.55
			var k := Props.rnd(u * 3.1 + v * 1.7 + i * 2.3 + row * 5.9)
			Kit.bevel(g, Vector3(0.28, 0.24 + 0.06 * k, 0.3), Vector3(x, y + 0.13, 0.0), cloth[int(k * 6.0) % 6], 0.06)
			Kit.box(g, Vector3(0.07, 0.05, 0.01), Vector3(x + 0.06, y + 0.12, 0.158), Props.PAPER)
	return g


## The steel wire rack under the two kinds of shelving: four posts and four shelves.
static func _rack(g: Node3D, w: float, d: float, h: float) -> void:
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		for z: float in [-d * 0.5 + 0.02, d * 0.5 - 0.02]:
			Kit.box(g, Vector3(0.03, h, 0.03), Vector3(x, h * 0.5, z), STEEL)
	for y: float in [0.15, 0.7, 1.25, 1.78]:
		Kit.box(g, Vector3(w, 0.02, d), Vector3(0, y, 0), Color(0.68, 0.7, 0.72))


## A rolling laundry cart (a canvas bin on a steel frame), w long, front +z.
static func cart(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.9, stuff := ORANGE) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	Kit.bevel_block(g, Vector3(w, 0.62, 0.6), Vector3(0, 0.22, 0), Color(0.72, 0.68, 0.58), 0.03)
	Kit.bevel(g, Vector3(w - 0.12, 0.08, 0.48), Vector3(0, 0.81, 0), stuff, 0.04)
	for x: float in [-w * 0.5 + 0.06, w * 0.5 - 0.06]:
		for z: float in [-0.24, 0.24]:
			Kit.cyl(g, 0.06, 0.04, Vector3(x, 0.06, z), DARK, Vector3(0, 0, 90), 8)
			Kit.box(g, Vector3(0.03, 0.14, 0.03), Vector3(x, 0.15, z), STEEL)
	return g


## The inmates' telephones on a wall's face: n steel boxes in a row with a
## black handset each on its armoured cord, a hood over the row and the rules
## over that. Nothing on the floor.
static func phones(p: Node3D, b: int, u: float, v: float, yaw: float, n := 3) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	var w := n * 0.62
	Kit.box(g, Vector3(w + 0.1, 0.05, 0.36), Vector3(0, 1.82, 0.18), STAINLESS.darkened(0.1))      # the hood
	for i in n:
		var x := -w * 0.5 + (float(i) + 0.5) * 0.62
		var at := Kit.group(g, Vector3(x, 0, 0))
		Kit.bevel(at, Vector3(0.2, 0.3, 0.08), Vector3(0, 1.38, 0.04), STAINLESS, 0.015)
		for k in 4:
			for j in 3:
				Kit.box(at, Vector3(0.03, 0.025, 0.01), Vector3(-0.04 + j * 0.04, 1.44 - k * 0.04, 0.085), Color(0.25, 0.26, 0.28))
		var hs := Kit.group(at, Vector3(0.14, 1.36, 0.06))
		Kit.bevel(hs, Vector3(0.05, 0.22, 0.045), Vector3.ZERO, DARK, 0.015)
		for s: float in [-1.0, 1.0]:
			Kit.bevel(hs, Vector3(0.065, 0.06, 0.065), Vector3(0, s * 0.105, 0.008), DARK, 0.02)
		Kit.tube(at, Vector3(0.0, 1.22, 0.05), Vector3(0.06, 1.0, 0.06), 0.009, STEEL, 5)
		Kit.tube(at, Vector3(0.06, 1.0, 0.06), Vector3(0.14, 1.24, 0.06), 0.009, STEEL, 5)
		if i > 0:            # a little steel wing between each two
			Kit.box(g, Vector3(0.02, 0.5, 0.3), Vector3(x - 0.31, 1.45, 0.15), STAINLESS.darkened(0.06))
	Kit.box(g, Vector3(0.9, 0.24, 0.012), Vector3(0, 2.1, 0.006), Color(0.95, 0.93, 0.86))
	Props.words(g, "COLLECT CALLS ONLY", Vector3(0, 2.1, 0.014), 0.075, Color(0.2, 0.22, 0.3))
	return g


## A bank of security monitors on a wall's face: cols x rows dark cases with
## the cameras' grey-green pictures glowing on them, on a steel frame.
static func monitors(p: Node3D, b: int, u: float, v: float, yaw: float, cols := 3, rows := 2, y := 1.55) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	var w := cols * 0.52
	Kit.box(g, Vector3(w + 0.08, rows * 0.4 + 0.08, 0.04), Vector3(0, y + rows * 0.2 - 0.2, 0.02), IRON)
	for c in cols:
		for r in rows:
			var x := -w * 0.5 + (float(c) + 0.5) * 0.52
			var yy := y + r * 0.4
			Kit.bevel(g, Vector3(0.48, 0.36, 0.12), Vector3(x, yy, 0.1), DARK, 0.02)
			var lit := snappedf(0.6 + 0.4 * Props.rnd(u + c * 1.3 + r * 2.9), 0.1)
			Kit.box(g, Vector3(0.42, 0.3, 0.01), Vector3(x, yy, 0.165), Kit.flat(Color(0.5 * lit, 0.62 * lit, 0.56 * lit), 0.8))
			Kit.box(g, Vector3(0.2, 0.08, 0.01), Vector3(x - 0.06, yy - 0.06, 0.172), Kit.flat(Color(0.32 * lit, 0.4 * lit, 0.36 * lit), 0.8))
	return g


## A yellow mop bucket on its wheels with the wringer on it, the mop standing in it.
static func mop_bucket(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.4)
	Kit.bevel_block(g, Vector3(0.44, 0.34, 0.38), Vector3(0, 0.06, 0), SAFETY, 0.05)
	Kit.box(g, Vector3(0.36, 0.02, 0.3), Vector3(0, 0.41, 0), Color(0.42, 0.5, 0.42))             # the grey water
	Kit.box(g, Vector3(0.2, 0.16, 0.36), Vector3(0.1, 0.48, 0), Color(0.86, 0.68, 0.14))           # the wringer
	for x: float in [-0.17, 0.17]:
		for z: float in [-0.15, 0.15]:
			Kit.cyl(g, 0.03, 0.05, Vector3(x, 0.03, z), DARK, Vector3(0, 0, 90), 6)
	Kit.tube(g, Vector3(-0.08, 0.3, 0.0), Vector3(-0.16, 1.4, -0.08), 0.013, Props.WOOD, 5)
	Kit.cyl(g, 0.09, 0.2, Vector3(-0.08, 0.32, 0.0), Color(0.88, 0.86, 0.78), Vector3.ZERO, 8, 0.05)
	return g


## A wet floor sign, folded open on the floor.
static func wet_floor(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.32, 0.36)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.3, 0.62, 0.012), Vector3(0, 0.3, s * 0.09), SAFETY, Vector3(s * 16.0, 0, 0))
	Props.words(g, "WET", Vector3(0, 0.38, 0.106), 0.07, DARK, 0.0).rotation_degrees.x = 16.0
	return g


## A steel stair: open diamond-plate treads between two channel stringers, a
## pipe rail up its open side (+x of its own). It stands at (u, v), w wide and
## l long, rising `rise` towards its back as Props.stairs does: the top tread is
## level with the floor above at its back end.
static func stairs(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, l := 3.6, rise := 2.9) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var n := 13
	var plate := Kit.tex("in_diamond", 0.5, STEEL, false, Color(0.72, 0.74, 0.78))
	var paint := PAINTED.darkened(0.15)
	for i in n:
		var h := rise * float(i + 1) / float(n)
		var z := l * 0.5 - (float(i) + 0.5) * l / float(n)
		Kit.box(g, Vector3(w - 0.1, 0.035, l / n + 0.02), Vector3(0, h - 0.0175, z), plate)
		Kit.box(g, Vector3(w - 0.11, 0.03, 0.03), Vector3(0, h - 0.02, z + l / n * 0.5 + 0.004), SAFETY)     # the nosing (narrower than the tread: their ends apart)
	var slope := atan2(rise, l)
	var run := sqrt(rise * rise + l * l)
	for x: float in [-w * 0.5 + 0.03, w * 0.5 - 0.03]:
		Kit.box(g, Vector3(0.05, 0.24, run), Vector3(x, rise * 0.5 - 0.06, 0), paint, Vector3(rad_to_deg(slope), 0, 0))
	# The rail: a post at the foot and at the head, the pipe along the slope 0.95 over the treads.
	var x := w * 0.5 - 0.02
	Kit.box(g, Vector3(0.05, 1.05, 0.05), Vector3(x, 0.525, l * 0.5 - 0.05), paint)
	Kit.box(g, Vector3(0.05, 1.05, 0.05), Vector3(x, rise + 0.525, -l * 0.5 + 0.05), paint)
	Kit.tube(g, Vector3(x, 1.05, l * 0.5 - 0.05), Vector3(x, rise + 1.05, -l * 0.5 + 0.05), 0.025, paint, 6)
	Kit.tube(g, Vector3(x, 0.55, l * 0.5 - 0.05), Vector3(x, rise + 0.55, -l * 0.5 + 0.05), 0.018, paint, 6)
	return g


## A shower on a wall's face: the riser pipe, the arm and the head, the push
## button. (u, v) on the wall's face, facing `yaw`.
static func shower(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.cyl(g, 0.02, 1.0, Vector3(0, 1.55, 0.04), STAINLESS, Vector3.ZERO, 6)
	Kit.tube(g, Vector3(0, 2.05, 0.04), Vector3(0, 2.1, 0.26), 0.018, STAINLESS, 6)
	Kit.cyl(g, 0.07, 0.05, Vector3(0, 2.07, 0.3), STAINLESS.darkened(0.1), Vector3(25, 0, 0), 10, 0.04)
	Kit.box(g, Vector3(0.12, 0.12, 0.04), Vector3(0, 1.15, 0.02), STAINLESS)
	Kit.cyl(g, 0.03, 0.02, Vector3(0, 1.15, 0.05), Color(0.2, 0.4, 0.7), Vector3(90, 0, 0), 8)
	return g


## A tiled half wall between two showers: from a wall's face out `deep`, h high.
## Takes floor.
static func shower_wall(p: Node3D, b: int, u: float, v: float, yaw: float, deep := 1.1, h := 1.8, look: Variant = Color(0.85, 0.9, 0.92)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.1, deep)
	Kit.box(g, Vector3(0.1, h, deep), Vector3(0, h * 0.5, 0), look)
	Kit.box(g, Vector3(0.14, 0.04, deep + 0.02), Vector3(0, h + 0.02, 0.0), Color(0.62, 0.66, 0.68))
	return g


## A pull-up bar and dip bars for the yard: two posts, the high bar between
## them, a pair of low parallel bars beside. Takes floor.
static func pullup(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 0.6)
	var paint := Color(0.2, 0.32, 0.5)
	for x: float in [-0.7, 0.2]:
		Kit.cyl(g, 0.045, 2.35, Vector3(x, 1.175, 0), paint, Vector3.ZERO, 8)
	Kit.cyl(g, 0.02, 0.9, Vector3(-0.25, 2.3, 0), STEEL, Vector3(0, 0, 90), 6)
	for z: float in [-0.22, 0.22]:
		for x: float in [0.35, 0.68]:
			Kit.cyl(g, 0.035, 1.2, Vector3(x, 0.6, z), paint, Vector3.ZERO, 8)
		Kit.cyl(g, 0.022, 0.5, Vector3(0.515, 1.2, z), STEEL, Vector3(0, 0, 90), 6)
	return g


## A rubber floor mat for the weights, w by d, its edge a shade darker.
static func gym_mat(p: Node3D, b: int, u: float, v: float, w: float, d: float) -> void:
	var n: Node3D = p.node_of(b)
	Kit.box(n, Vector3(w, 0.014, d), p.pt(u, v, 0.007), Color(0.16, 0.16, 0.18))
	Kit.box(n, Vector3(w - 0.1, 0.014, d - 0.1), p.pt(u, v, 0.009), Color(0.21, 0.21, 0.23))


## A small grey box on a wall's face: an intercom with its speaker grille and a
## call button, and a bell push under a sign.
static func intercom(p: Node3D, b: int, u: float, v: float, yaw: float, y := 1.4) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.18, 0.26, 0.05), Vector3(0, y, 0.025), STAINLESS, 0.012)
	for k in 4:
		Kit.box(g, Vector3(0.1, 0.012, 0.01), Vector3(0, y + 0.07 - k * 0.03, 0.053), DARK)
	Kit.cyl(g, 0.025, 0.02, Vector3(0, y - 0.07, 0.055), Color(0.85, 0.2, 0.15), Vector3(90, 0, 0), 10)
	return g


## The steel lockers in a sally port where officers put their guns before
## they go in: a cabinet of small numbered doors on a wall's face, each with
## its key, and the sign over it.
static func gun_lockers(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.9, 0.6, 0.3), Vector3(0, 1.4, 0.15), Color(0.42, 0.45, 0.48))
	for c in 3:
		for r in 2:
			var x := -0.3 + c * 0.3
			var y := 1.25 + r * 0.29
			Kit.box(g, Vector3(0.27, 0.26, 0.01), Vector3(x, y, 0.305), Color(0.5, 0.53, 0.56))
			Kit.box(g, Vector3(0.03, 0.04, 0.02), Vector3(x + 0.09, y, 0.315), Color(0.85, 0.7, 0.25))
	Kit.box(g, Vector3(0.96, 0.2, 0.012), Vector3(0, 1.88, 0.006), Color(0.95, 0.93, 0.86))
	Props.words(g, "SECURE ALL FIREARMS", Vector3(0, 1.88, 0.014), 0.07, Color(0.7, 0.12, 0.1))
	return g


## A yellow steel bollard (a post a van backs up to), takes a little floor.
static func bollard(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.24, 0.24)
	Kit.cyl(g, 0.11, 1.0, Vector3(0, 0.5, 0), SAFETY, Vector3.ZERO, 10)
	Kit.cyl(g, 0.115, 0.08, Vector3(0, 0.82, 0), DARK, Vector3.ZERO, 10)
	Kit.ball(g, 0.11, Vector3(0, 1.0, 0), SAFETY, 8)
	return g


## A traffic cone.
static func cone(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.34, 0.34)
	Kit.box(g, Vector3(0.34, 0.03, 0.34), Vector3(0, 0.015, 0), Color(0.85, 0.35, 0.1))
	Kit.cyl(g, 0.13, 0.62, Vector3(0, 0.34, 0), Color(0.95, 0.45, 0.12), Vector3.ZERO, 10, 0.02)
	Kit.cyl(g, 0.088, 0.1, Vector3(0, 0.38, 0), Color(0.95, 0.95, 0.92), Vector3.ZERO, 10, 0.07)
	return g


## A small square window high in a wall's face (a cell's): wired glass in a
## steel frame. `face` the side it faces (+1 the street side); along u at v.
static func high_window(p: Node3D, n: Node3D, v: float, face: float, u: float, y: float, w := 0.5, h := 0.3) -> void:
	var at := v + face * 0.075
	p.slab(n, true, at + face * 0.02, u - w * 0.5 - 0.05, u + w * 0.5 + 0.05, y - h * 0.5 - 0.05, y + h * 0.5 + 0.05, 0.04, IRON)
	Kit.pane(p.slab(n, true, at + face * 0.045, u - w * 0.5, u + w * 0.5, y - h * 0.5, y + h * 0.5, 0.012, Kit.flat(Color(0.72, 0.84, 0.9), 0.5)))


## Bars on a level of the cell block nobody walks (the upper tier, seen from
## the dayroom): the bars of a run of cell fronts along u at v, from u0 to u1,
## y0 to y1, a door frame every `every` metres from u0 + `first`. One mesh for all the bars.
static func bar_screen(p: Node3D, n: Node3D, v: float, u0: float, u1: float, y0: float, y1: float, every := 2.5, first := 0.0) -> void:
	var count := int((u1 - u0) / 0.12)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.013
	rod.bottom_radius = 0.013
	rod.height = y1 - y0 - 0.1
	rod.radial_segments = 5
	rod.rings = 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rod
	mm.instance_count = count + 1
	for i in count + 1:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p.pt(u0 + (u1 - u0) * float(i) / float(count), v, (y0 + y1) * 0.5)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = Kit.flat(Props.IRON)
	n.add_child(mi)
	p.slab(n, true, v, u0, u1, y0, y0 + 0.06, 0.06, Props.IRON)
	p.slab(n, true, v, u0, u1, y1 - 0.06, y1, 0.06, Props.IRON)
	var k := u0 + first
	while k < u1 - 0.1:              # each door: a frame bar either side, a cross bar and its lock
		for x: float in [k + 0.3, k + 1.3]:
			p.slab(n, true, v + 0.012, x - 0.025, x + 0.025, y0 + 0.06, y1 - 0.06, 0.07, Props.IRON)
		p.slab(n, true, v + 0.014, k + 0.33, k + 1.27, (y0 + y1) * 0.5 - 0.03, (y0 + y1) * 0.5 + 0.03, 0.06, Props.IRON)
		p.slab(n, true, v + 0.03, k + 1.12, k + 1.24, y0 + 0.95, y0 + 1.15, 0.08, Color(0.2, 0.21, 0.24))
		k += every


# ------------------------------------------------------------------ the sky

## The watcher (see SkyWatch) for the sky and far city behind the yard (`what`, from
## outdoor.gd's backdrop): it shows only while he is outside the building, which
## runs from v0 to v1 on the plan.
static func sky_outside(p: Node3D, b: int, what: Node3D, v0: float, v1: float) -> SkyWatch:
	var s := SkyWatch.new()
	s.name = "SkyOutside"
	s.what = what
	s.z0 = p.pt(0.0, v0).z
	s.z1 = p.pt(0.0, v1).z
	p.node_of(b).add_child(s)
	p.watchers.append(s)
	return s


## No roof is drawn, so from inside the jail the open sky behind the yard showed
## over the tops of the walls. While he is inside (the yard's wall to the street
## front) it is put away and the walls stand against the dark, as in every other
## place; out in the yard or out front it is shown. The place tells it where he is
## (place.watchers), or it finds him (main.gd's "Player").
class SkyWatch extends Node3D:
	var what: Node3D = null
	var z0 := 0.0                    # world z: inside from here ...
	var z1 := 0.0                    # ... to here
	var _at := Vector3.INF
	var _lead: Node3D = null

	func watch(at: Vector3, _delta: float) -> void:
		_at = at

	func _process(_delta: float) -> void:
		if what == null:
			return
		if _lead == null and get_tree().current_scene:
			_lead = get_tree().current_scene.get_node_or_null("Player") as Node3D
		if _lead:
			_at = _lead.global_position
		if _at != Vector3.INF:
			what.visible = _at.z < z0 or _at.z > z1
