extends RefCounted
## The props of Rose Hill's backs (plans/backs.gd), and the restroom block
## Pen Lucy Park's corner shares with it (plans/park.gd): roll-up doors and the
## garages behind them, a car under a tarp with one corner up on blocks, a
## cable spool somebody made a table of, a board fence that has fallen in, a
## fence of corrugated sheets, a clothes line, the park's restroom block. As in
## props.gd each takes (u, v) on the plan and `yaw` (0 faces the street, 90
## right, 180 the back, 270 left), keeps its floor clear through place.gd's
## `prop` or `block` unless it says not, and returns its group. Every word on
## them is a placeholder.

const Props := preload("res://scripts/props.gd")
const Alley := preload("res://scripts/props_alley.gd")
const Club := preload("res://scripts/props_club.gd")
const Park := preload("res://scripts/props_park.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const BLOCK := Color(0.56, 0.55, 0.52)          # cinder block
const INSIDE := Color(0.2, 0.2, 0.21)           # a garage's inside, grimy (not black: black reads as a hole)
const RUST := Color(0.46, 0.25, 0.14)
const TARP := Color(0.2, 0.38, 0.66)
const SPOOL := Color(0.58, 0.44, 0.28)
const IRON := Color(0.24, 0.25, 0.28)
const DOOR := Color(0.62, 0.6, 0.55)            # a roll-up door's galvanised slats, gone dull
## Rubbish bags: the kitchen's white, the yard's green, a grey (no dark ones: at
## dusk a round dark bag tied at the top reads as a cartoon bomb; the green is a
## light one for that reason).
const BAGS := [Color(0.9, 0.9, 0.86), Color(0.52, 0.74, 0.5), Color(0.78, 0.8, 0.82)]


## A box on the plan: u0..u1, v0..v1, y0..y1.
static func _gb(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look)


## Rubbish bags out for the truck, n in a heap round (u, v): props_alley.gd's
## sacks (`Alley.bags`, the same shape), in BAGS' colours. Loose rubbish: they
## take no floor.
static func bags(p: Node3D, b: int, u: float, v: float, n := 2, seed := 0.0) -> void:
	var node: Node3D = p.node_of(b)
	for i in n:
		var r := Props.rnd(seed + i * 3.3 + u * 0.7)
		var size := 0.22 + 0.07 * r
		var at: Vector3 = p.pt(u + (i - (n - 1) * 0.5) * 0.46 + (r - 0.5) * 0.08, v + (0.14 if i % 2 == 1 else -0.06))
		var g := Kit.group(node, at, Vector3(0, r * 360.0, (r - 0.5) * 16.0))
		var m := Alley.plastic(BAGS[(i + int(seed)) % BAGS.size()])
		var sack := Kit.ball(g, size, Vector3(0, size * 0.92, 0), m, 12)
		sack.scale = Vector3(1.0, 0.98, 0.9)
		for s: Array in [[0.46, 0.5, 0.22, 0.6], [-0.42, 0.46, -0.24, 0.56], [0.05, 0.42, 0.5, 0.5]]:
			Kit.ball(g, size * float(s[3]), Vector3(size * float(s[0]), size * float(s[1]), size * float(s[2])), m, 8)
		Kit.cyl(g, size * 0.24, size * 0.26, Vector3(0, size * 1.92, 0), m, Vector3.ZERO, 7, size * 0.1)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(size * 0.22, size * 0.36, size * 0.02), Vector3(s * size * 0.1, size * 2.16, 0), m, Vector3(0, 0, s * -26.0))


## A board fence h high along u (or v) at `at`, from `from` to `to`: place.gd's
## "wood" fence (out_boards in `look`'s colour, two rails on the `back` side,
## square posts every bay or less), with the rails stopping inside the end
## posts, so no rail's end lies in the plane of the boards' end. It takes its
## line of floor. A gateway in it is two of these and place.gd's fence over the
## gap alone (as props_bea.gd's pickets do).
static func boards(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, h: float, look: Color, back := -1.0) -> void:
	var face := Outdoor.tex("out_boards", 1.2, look, Color(minf(look.r / 0.54, 1.0), minf(look.g / 0.48, 1.0), minf(look.b / 0.41, 1.0)))
	p.slab(n, along_u, at, from, to, 0.05, h, 0.04, face)
	for y: float in [h * 0.3, h * 0.8]:
		p.slab(n, along_u, at + back * 0.03, from + 0.03, to - 0.03, y, y + 0.08, 0.03, look.darkened(0.18))
	var bays := maxi(int(round((to - from) / 1.8)), 1)
	for i in bays + 1:
		var w := from + (to - from) * float(i) / float(bays)
		Kit.box(n, Vector3(0.1, h + 0.06, 0.1), p.pt(w, at, (h + 0.06) * 0.5) if along_u else p.pt(at, w, (h + 0.06) * 0.5), look.darkened(0.25))
	if along_u:
		p.block(from, at - 0.04, to, at + 0.04)
	else:
		p.block(at - 0.04, from, at + 0.04, to)


## A yard's gate, shut, in place.gd's rails (`rail`, h high along u or v at
## `at`) between their posts at a and b: a steel frame, a middle rail and a
## brace corner to corner, hinge straps round the stile on the hinge side (a,
## or b with `hinge_b`), a latch on the other (a slab alone read as a grey
## board). Lay the rails as two runs, ending at a and at b. It takes its line
## of floor.
static func rail_gate(p: Node3D, n: Node3D, along_u: bool, at: float, a: float, b: float, h: float, look: Color, hinge_b := false) -> Node3D:
	var w := b - a
	var g := Kit.group(n, p.pt(a, at) if along_u else p.pt(at, a), Vector3(0, 0.0 if along_u else -90.0, 0))
	var s := 0.045
	var low := 0.1
	var top := h - 0.05
	for x: float in [0.065, w - 0.065]:                                   # the stiles
		Kit.box(g, Vector3(s, top - low + s, s), Vector3(x, (low + top) * 0.5, 0), look)
	for y: float in [low, 0.78, top]:                                     # bottom, middle and top rails
		Kit.box(g, Vector3(w - 0.13 - s, s * 0.8, s * 0.8), Vector3(w * 0.5, y, 0), look)
	var run := w - 0.13 - s
	var rise := top - low
	var hinge := w - 0.065 if hinge_b else 0.065
	var brace := Kit.box(g, Vector3(sqrt(run * run + rise * rise) - 0.03, s * 0.7, s * 0.6), Vector3(w * 0.5, (low + top) * 0.5, 0), look)
	brace.rotation_degrees = Vector3(0, 0, rad_to_deg(atan2(rise, run)) * (-1.0 if hinge_b else 1.0))      # from the foot of the hinge stile up to the latch
	var dark := look.darkened(0.35)
	var out := -1.0 if hinge_b else 1.0
	for y: float in [0.3, h - 0.35]:                                      # the hinge straps, round the stile to the post
		Kit.box(g, Vector3(0.16, 0.04, s + 0.03), Vector3(hinge - out * 0.035, y, 0), dark)
	var latch := w - hinge
	Kit.box(g, Vector3(0.12, 0.05, s + 0.024), Vector3(latch + out * 0.03, 0.98, 0), dark)        # the latch, over to the post
	if along_u:
		p.block(a, at - 0.045, b, at + 0.045)
	else:
		p.block(at - 0.045, a, at + 0.045, b)
	return g


## Where a chain-link fence (place.gd's "chain", h high, along u or v at `at`)
## has been cut open from a to b: the mesh cut down the post at b and peeled
## back along the fence beyond it, out on the `side` side (-1: towards -v, or
## -u), swung `swing` degrees out of the fence's line, drooping, the rest of it
## rolled up on itself in a leaning roll (swung only a little, the flap lies in
## the fence's own mesh seen square on, and the gap does not read: a way
## through wants it swung well out); with `rail`, the top rail still across
## the gap (only where people pass under it); with `back`, cut down the post
## at a and peeled back the other way (the same gap seen from its other side,
## as the park sees the backs' one). Decoration: the way through is the
## fence's gap; flap and roll reach out from the post on `side` (0.4 m at 15
## degrees, 0.9 m at 55), so keep walkers off that if they could reach it.
static func torn(p: Node3D, n: Node3D, along_u: bool, at: float, a: float, b: float, h: float, side := -1.0, rail := false, back := false, swing := 15.0) -> void:
	if rail:
		var mid := (a + b) * 0.5
		Kit.cyl(n, 0.024, b - a + 0.1, p.pt(mid, at, h - 0.03) if along_u else p.pt(at, mid, h - 0.03), Color(0.55, 0.58, 0.6), Vector3(0, 0, 90) if along_u else Vector3(90, 0, 0), 8)
	var yaw: float
	if along_u:
		yaw = 180.0 + side * swing if back else -side * swing
	else:
		yaw = 90.0 - side * swing if back else -90.0 + side * swing
	var post := a if back else b
	var hinge := Kit.group(n, p.pt(post, at + side * 0.04, 0.0) if along_u else p.pt(at + side * 0.04, post, 0.0), Vector3(0, yaw, 0))
	var tall := h - 0.3
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, tall)
	sheet.mesh = q
	sheet.material_override = Outdoor.chain_link()
	sheet.position = Vector3(0.33, 0.12 + tall * 0.5, 0.0)
	sheet.rotation_degrees = Vector3(0, 0, -5)
	hinge.add_child(sheet)
	var out := (side if along_u else -side) * (-1.0 if back else 1.0)     # the hinge's local z that points out on `side`
	# The roll: two turns of mesh round each other, leaning back, its foot kicked out.
	for r: Array in [[0.11, 0.0], [0.07, 0.025]]:
		Kit.cyl(hinge, r[0], tall - 0.06, Vector3(0.74 + r[1], 0.13 + (tall - 0.06) * 0.5, out * (0.09 + r[1])), Outdoor.chain_link(), Vector3(0, 0, -7), 10, r[0] * 0.85)


## A puddle r across at (u, v): a wet sheen with the dusk sky in it and a glint
## (any darker than the ground round it, a disc reads as a hole or a shadow).
## Decoration: it takes no floor.
static func puddle(p: Node3D, n: Node3D, u: float, v: float, r: float, turn := 0.0) -> void:
	var g := Kit.group(n, p.pt(u, v, 0.0), Vector3(0, turn, 0))
	var wet := Kit.cyl(g, r, 0.004, Vector3(0, 0.011, 0), Color(0.46, 0.46, 0.6, 0.45), Vector3.ZERO, 14)
	wet.scale = Vector3(1.3, 1.0, 0.8)
	var sky := Kit.cyl(g, r * 0.55, 0.004, Vector3(r * 0.2, 0.014, -r * 0.1), Color(0.88, 0.68, 0.82, 0.55), Vector3.ZERO, 12)
	sky.scale = Vector3(1.5, 1.0, 0.55)
	var glint := Kit.cyl(g, r * 0.2, 0.004, Vector3(-r * 0.35, 0.017, r * 0.12), Color(0.97, 0.94, 0.98, 0.6), Vector3.ZERO, 10)
	glint.scale = Vector3(1.8, 1.0, 0.35)


# ------------------------------------------------------------- garages

## A roll-up door filling an opening w wide and h high in a wall facing
## `yaw`, the foot of the opening's middle at (u, v) on the wall's inner face:
## its guide rails down both sides of the opening, the curtain of ribbed slats
## between them down to the bottom bar, raised `up` metres (0 is shut), a
## handle, and a padlock at the foot when it is shut. Built into node n; it
## takes no floor (what it is in does).
static func roll_door(p: Node3D, n: Node3D, u: float, v: float, yaw: float, w := 2.4, h := 2.1, up := 0.0, look := DOOR) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	var slats := Kit.tex("in_ribbed", 0.5, look, false, look.lightened(0.05))
	var inner := w - 0.16
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.08, h, 0.09), Vector3(s * (w * 0.5 - 0.04), h * 0.5, 0.045), IRON)
	if h - up > 0.02:
		Kit.box(g, Vector3(inner, h - up, 0.03), Vector3(0, up + (h - up) * 0.5, 0.05), slats)
	Kit.box(g, Vector3(inner - 0.01, 0.07, 0.06), Vector3(0, up + 0.04, 0.055), look.darkened(0.35))   # the bottom bar (a few mm off the ground when shut)
	Kit.box(g, Vector3(0.16, 0.04, 0.04), Vector3(-inner * 0.3, up + 0.16, 0.1), Props.STEEL)        # the handle
	if up < 0.01:
		Kit.box(g, Vector3(0.07, 0.09, 0.03), Vector3(inner * 0.32, 0.12, 0.1), Club.BRASS)
		Kit.ring(g, 0.028, 0.009, Vector3(inner * 0.32, 0.19, 0.1), Props.STEEL)
	return g


## A garage at the back of a lot, u0..u1 by v0..v1 on the plan, its roll-up door
## on the alley side (v1): block walls h high under a flat tar roof with a
## coping along the front, the door `door_w` wide, raised `up` (0: shut).
## Raised, it shows the inside: grimy walls, a bulb on, a bench, tyres. It
## keeps its whole floor clear.
static func garage(p: Node3D, b: int, u0: float, u1: float, v0: float, v1: float, h: float, look: Variant, door_w := 2.4, up := 0.0, door_look := DOOR) -> void:
	var n: Node3D = p.node_of(b)
	var t := 0.2
	var mid := (u0 + u1) * 0.5
	var d0 := mid - door_w * 0.5
	var d1 := mid + door_w * 0.5
	var door_h := 2.1
	# The walls (those running front to back a centimetre lower, so the tops do
	# not meet in one plane), the piers and lintel round the door.
	_gb(p, n, u0, u1, v0, v0 + t, 0.0, h, look)
	_gb(p, n, u0, u0 + t, v0 + t, v1 - t, 0.0, h - 0.01, look)
	_gb(p, n, u1 - t, u1, v0 + t, v1 - t, 0.0, h - 0.01, look)
	_gb(p, n, u0, d0, v1 - t, v1, 0.0, h, look)
	_gb(p, n, d1, u1, v1 - t, v1, 0.0, h, look)
	_gb(p, n, d0, d1, v1 - t, v1, door_h, h, look)
	_gb(p, n, u0 - 0.06, u1 + 0.06, v0 - 0.06, v1 + 0.04, h, h + 0.1, Park.TAR)
	_gb(p, n, u0 - 0.08, u1 + 0.08, v1 + 0.04, v1 + 0.12, h - 0.06, h + 0.16, Park.COPING)
	roll_door(p, n, mid, v1 - t, 0.0, door_w, door_h, up, door_look)
	p.block(u0, v0, u1, v1)
	if up <= 0.0:
		return
	# Inside: the walls' inner faces grimy, a concrete floor, a bulb hanging on
	# its flex, the bench along the back, tyres in the corner, a can of oil.
	var inside := Kit.flat(INSIDE)
	_gb(p, n, u0 + t, u1 - t, v0 + t, v0 + t + 0.01, 0.0, h - 0.02, inside)
	_gb(p, n, u0 + t, u0 + t + 0.01, v0 + t + 0.01, v1 - t, 0.0, h - 0.03, inside)
	_gb(p, n, u1 - t - 0.01, u1 - t, v0 + t + 0.01, v1 - t, 0.0, h - 0.03, inside)
	_gb(p, n, d0 + 0.01, d1 - 0.01, v1 - t - 0.01, v1 - t, door_h + 0.01, h - 0.02, inside)
	_gb(p, n, u0 + t + 0.01, u1 - t - 0.01, v0 + t + 0.01, v1 - t, 0.0, 0.012, Color(0.34, 0.33, 0.31))
	_gb(p, n, u0 + t, u1 - t, v0 + t, v1 - t, h - 0.03, h - 0.02, inside)          # the underside of the roof
	var bulb: Vector3 = p.pt(mid, (v0 + v1) * 0.5 - 0.6, h - 0.55)
	Kit.cyl(n, 0.006, 0.5, bulb + Vector3(0, 0.3, 0), IRON, Vector3.ZERO, 4)
	Kit.ball(n, 0.05, bulb, Kit.flat(Color(1.0, 0.86, 0.55), 2.2), 8)
	Kit.omni(n, bulb - Vector3(0, 0.1, 0), Color(1.0, 0.8, 0.5), 0.9, 4.0)
	var wood := Color(0.42, 0.32, 0.22)
	_gb(p, n, u0 + t + 0.2, u1 - t - 0.2, v0 + t + 0.02, v0 + t + 0.62, 0.86, 0.92, wood)
	for x: float in [u0 + t + 0.28, u1 - t - 0.28]:
		_gb(p, n, x - 0.03, x + 0.03, v0 + t + 0.52, v0 + t + 0.58, 0.0, 0.86, wood.darkened(0.2))
	_gb(p, n, u0 + t + 0.3, u1 - t - 0.3, v0 + t + 0.011, v0 + t + 0.03, 1.1, 1.9, Color(0.5, 0.42, 0.3))   # the pegboard
	for k in 5:
		var x := u0 + t + 0.5 + k * (u1 - u0 - 2.0 * t - 1.0) / 4.0
		_gb(p, n, x - 0.02, x + 0.02, v0 + t + 0.03, v0 + t + 0.05, 1.3 + 0.1 * (k % 3), 1.7 + 0.08 * (k % 2), Color(0.55, 0.57, 0.6))
	var cv := (v0 + v1) * 0.5 + 0.8
	for i in 3:
		Kit.ring(n, 0.32, 0.12, p.pt(u1 - t - 0.42, cv, 0.06 + i * 0.12), Alley.RUBBER, Vector3(-90, 0, 0))
	Kit.cyl(n, 0.12, 0.36, p.pt(u0 + t + 0.3, v1 - t - 0.5, 0.18), Color(0.62, 0.18, 0.14), Vector3.ZERO, 10)


# ------------------------------------------------------------ in the yards

## A car under a blue tarp, its front to `yaw`: the tarp over the body and the
## cabin with its folds hanging down the sides, a rope across it, a brick on
## each corner and an old tyre thrown on the roof; the sills and bumpers and the
## wheels showing under its hem, one back wheel gone and that corner up on
## cinder blocks. 1.9 wide, 4.6 long.
static func tarp_car(p: Node3D, b: int, u: float, v: float, yaw: float, look := TARP) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.9, 4.6)
	var tarp := Alley.plastic(look)
	var fold := Alley.plastic(look.darkened(0.25))
	var paint := Color(0.46, 0.2, 0.17)
	var chrome := Color(0.62, 0.63, 0.65)
	for x: float in [-0.78, 0.78]:
		for z: float in [-1.42, 1.42]:
			if x < 0.0 and z < 0.0:
				Kit.box(g, Vector3(0.39, 0.19, 0.19), Vector3(x + 0.04, 0.095, z), BLOCK)
				Kit.box(g, Vector3(0.19, 0.19, 0.39), Vector3(x + 0.04, 0.285, z), BLOCK.darkened(0.12))
				continue
			Kit.cyl(g, 0.31, 0.2, Vector3(x, 0.31, z), Alley.RUBBER, Vector3(0, 0, 90), 14)
			Kit.cyl(g, 0.15, 0.012, Vector3(x * 1.135, 0.31, z), Color(0.5, 0.51, 0.53), Vector3(0, 0, 90), 10)
	# What shows under the hem: the sills, the bumpers, a blank plate.
	Kit.box(g, Vector3(1.7, 0.2, 4.36), Vector3(0, 0.47, 0), paint)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(1.82, 0.14, 0.12), Vector3(0, 0.45, s * 2.24), chrome)
	Kit.box(g, Vector3(0.36, 0.13, 0.012), Vector3(0, 0.52, -2.306), Color(0.86, 0.84, 0.72))
	# The tarp: over the body and the cabin, its folds down the sides and the ends.
	Kit.bevel(g, Vector3(1.86, 0.62, 4.42), Vector3(0, 0.86, 0.0), tarp, 0.17)
	Kit.bevel(g, Vector3(1.5, 0.5, 2.2), Vector3(0, 1.36, -0.25), tarp, 0.18)
	for k in 5:
		var z := -1.8 + k * 0.9 + 0.2 * (Props.rnd(u + k) - 0.5)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.05, 0.42, 0.16), Vector3(s * 0.925, 0.66, z), fold, Vector3(0, 0, s * -6.0))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(1.2, 0.36, 0.05), Vector3(0.1 * s, 0.68, s * 2.205), fold, Vector3(s * 7.0, 0, 0))
	# A rope over it, tied off under the sills; a brick holding each corner.
	var rope := Color(0.82, 0.74, 0.5)
	for z: float in [0.95, -1.25]:
		Kit.box(g, Vector3(1.9, 0.025, 0.03), Vector3(0, 1.175 if z > 0.0 else 1.62, z), rope)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.025, 0.6 if z > 0.0 else 1.05, 0.03), Vector3(s * 0.94, (1.175 if z > 0.0 else 1.62) * 0.5 + 0.3, z), rope, Vector3(0, 0, s * 4.0))
	for c: Vector2 in [Vector2(-0.62, 1.95), Vector2(0.64, 1.9), Vector2(-0.6, -1.9), Vector2(0.62, -1.95)]:
		Kit.box(g, Vector3(0.21, 0.065, 0.1), Vector3(c.x, 1.2, c.y), Color(0.6, 0.28, 0.2), Vector3(0, 20.0 * c.x, 0))
	Kit.ring(g, 0.33, 0.12, Vector3(0.12, 1.66, -0.4), Alley.RUBBER, Vector3(-90, 0, 0))
	return g


## A cable spool stood on end for a table: its two wooden drums and the core,
## a can, a bottle in a paper bag, the boombox. It keeps its floor clear.
static func spool(p: Node3D, b: int, u: float, v: float, r := 0.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, r * 2.0, r * 2.0)
	var wood := Outdoor.tex("out_boards", 1.2, SPOOL)
	Kit.cyl(g, r, 0.06, Vector3(0, 0.03, 0), wood, Vector3.ZERO, 16)
	Kit.cyl(g, r * 0.4, 0.56, Vector3(0, 0.34, 0), SPOOL.darkened(0.25), Vector3.ZERO, 12)
	Kit.cyl(g, r, 0.06, Vector3(0, 0.65, 0), wood, Vector3.ZERO, 16)
	var top := 0.68
	Kit.cyl(g, 0.033, 0.12, Vector3(-0.22, top + 0.06, 0.12), Color(0.82, 0.16, 0.14), Vector3.ZERO, 8)
	var bag := Color(0.62, 0.48, 0.32)
	Kit.cyl(g, 0.06, 0.22, Vector3(0.18, top + 0.11, 0.16), bag, Vector3.ZERO, 8, 0.045)
	Kit.cyl(g, 0.02, 0.1, Vector3(0.18, top + 0.27, 0.16), Color(0.32, 0.42, 0.3), Vector3.ZERO, 6)
	Props.boombox(g, Vector3(0.0, top, -0.18), 10.0)
	return g


## A board fence along the alley at v = `at` that has fallen in. Each of `runs`
## ([from, to, high]) still stands, its boards ragged at the top (some snapped
## off short), a rail behind them; it is kept clear of walkers. `fallen` ([u, v,
## length, turn]) are the boards lying where they went down (loose: decoration).
static func broken_boards(p: Node3D, n: Node3D, at: float, runs: Array, fallen: Array, seed := 0.0) -> void:
	var look := Outdoor.tex("out_boards", 1.2, Color(0.45, 0.38, 0.3))
	var grey := Outdoor.tex("out_boards", 1.2, Color(0.45, 0.38, 0.3), Color(0.8, 0.8, 0.84))
	for run: Array in runs:
		var a: float = run[0]
		var c: float = run[1]
		var high: float = run[2]
		var u := a
		var k := 0
		while u + 0.13 <= c + 0.001:
			var r := Props.rnd(seed + u * 7.3 + k)
			var h := high if r > 0.7 else high * (0.5 + 0.5 * r / 0.7)
			Kit.box(n, Vector3(0.13, h, 0.025), p.pt(u + 0.065, at, h * 0.5), grey if k % 3 == 1 else look)
			u += 0.14
			k += 1
		Kit.box(n, Vector3(c - a, 0.08, 0.04), p.pt((a + c) * 0.5, at - 0.0325, high * 0.3), Color(0.36, 0.32, 0.28))
		p.block(a, at - 0.04, c, at + 0.04)
	for f: Array in fallen:
		var lie := Kit.group(n, p.pt(f[0], f[1]), Vector3(0, f[3], 0))
		Kit.box(lie, Vector3(0.13, 0.025, f[2]), Vector3(0, 0.02, 0), look, Vector3(0, 0, 4.0 * (Props.rnd(f[0] * 3.1) - 0.5)))


## A fence of corrugated sheets nailed to posts, h high, along u (or v) at `at`
## from `from` to `to`: sheets about 0.9 wide overlapping, each leaning its own
## way a little, most rusted through, a few still galvanised; the ribs upright.
## Posts and two rails behind, on the `side` side (-1: -v or -u). It is kept
## clear of walkers.
static func corrugated(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, h: float, seed := 0.0, side := -1.0) -> void:
	var count := maxi(int(round((to - from) / 0.9)), 1)
	var sw := (to - from) / float(count)
	for i in count:
		var r := Props.rnd(seed + i * 3.1)
		var tint: Color = RUST.lerp(Color(0.62, 0.64, 0.66), 0.85 if r > 0.72 else 0.12 * r)
		var sheet := Kit.tex("in_ribbed", 0.5, tint, false, tint)      # (finer and the ribs shimmer into arcs at a distance)
		var hh := h - 0.14 * Props.rnd(seed + i * 5.7)
		var mid := from + sw * (float(i) + 0.5)
		var off := 0.006 * float(i % 2)
		var lean := 1.5 + 2.5 * Props.rnd(seed + i * 2.3)
		if along_u:
			Kit.box(n, Vector3(hh, sw + 0.05, 0.02), p.pt(mid, at + off, hh * 0.5 + 0.02), sheet, Vector3(-lean, 0, 90))
		else:
			Kit.box(n, Vector3(hh, sw + 0.05, 0.02), p.pt(at + off, mid, hh * 0.5 + 0.02), sheet, Vector3(-lean, 90, 90))
	var post := Color(0.3, 0.26, 0.22)
	var posts := maxi(int(round((to - from) / 2.4)), 1)
	for i in posts + 1:
		var w := from + (to - from) * float(i) / float(posts)
		Kit.box(n, Vector3(0.08, h, 0.08), p.pt(w, at + side * 0.1, h * 0.5) if along_u else p.pt(at + side * 0.1, w, h * 0.5), post)
	var r0 := at + minf(side * 0.13, side * 0.07)
	var r1 := at + maxf(side * 0.13, side * 0.07)
	for y: float in [h * 0.25, h * 0.8]:
		if along_u:
			_gb(p, n, from, to, r0, r1, y, y + 0.07, post.lightened(0.05))
		else:
			_gb(p, n, r0, r1, from, to, y, y + 0.07, post.lightened(0.05))
	var k0 := at + minf(side * 0.16, -side * 0.06)
	var k1 := at + maxf(side * 0.16, -side * 0.06)
	if along_u:
		p.block(from, k0, to, k1)
	else:
		p.block(k0, from, k1, to)


## A clothes line between posts at u0 and u1 along v, h high, and `pieces`
## pegged on it, each [from, to, colour, drop]: sheets, towels, shirts.
static func washing(p: Node3D, n: Node3D, u0: float, u1: float, v: float, h: float, pieces: Array) -> void:
	for u: float in [u0, u1]:
		Kit.cyl(n, 0.035, h + 0.1, p.pt(u, v, (h + 0.1) * 0.5), Park.GALV, Vector3.ZERO, 6)
		Kit.box(n, Vector3(0.05, 0.05, 0.5), p.pt(u, v, h + 0.02), Park.GALV)
	var a: Vector3 = p.pt(u0, v, h - 0.005)
	var c: Vector3 = p.pt(u1, v, h - 0.005)
	Park.wire(n, a, c, 0.06, Color(0.88, 0.88, 0.86), 0.006, 8)
	for piece: Array in pieces:
		var from: float = piece[0]
		var to: float = piece[1]
		var drop: float = piece[3]
		var top := Park.wire_at(a, c, 0.06, ((from + to) * 0.5 - u0) / (u1 - u0))
		Kit.box(n, Vector3(to - from, drop, 0.012), top - Vector3(0, drop * 0.5 + 0.012, 0), piece[2], Vector3(0, 2.0 + 3.0 * Props.rnd(from), 0))
		for e: float in [from + 0.06, to - 0.06]:
			var peg: Vector3 = p.pt(e, v)
			Kit.box(n, Vector3(0.02, 0.06, 0.025), Vector3(peg.x, top.y - 0.01, peg.z), Color(0.7, 0.55, 0.35))


# --------------------------------------------------------- the park's corner

## Pen Lucy Park's restroom block, shut for the season: painted cinder block
## under a flat roof with a deep fascia; on its front (`yaw`) two steel doors
## with a sign over them and a paper one taped across, a caged lamp over each
## (with `lit`, the right-hand one on); round the back high glass-block
## windows, a vent, the downspout, tags. 5 by 3.4. It keeps its floor clear.
static func restroom(p: Node3D, b: int, u: float, v: float, yaw: float, lit := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 5.0, 3.4)
	var paint := Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), false, Color(0.82, 0.86, 0.76))
	var trim := Color(0.22, 0.36, 0.29)
	var steel := Color(0.48, 0.52, 0.5)
	var hd := 1.7
	var h := 2.7
	Kit.box(g, Vector3(5.0, h, 3.4), Vector3(0, h * 0.5, 0), paint)
	Kit.box(g, Vector3(5.04, 0.22, 3.44), Vector3(0, 0.11, 0), Color(0.42, 0.42, 0.4))       # the darker footing, splashed
	Kit.box(g, Vector3(5.5, 0.12, 3.9), Vector3(0, h + 0.06, 0), Color(0.3, 0.3, 0.32))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(5.62, 0.32, 0.06), Vector3(0, h - 0.02, s * 1.98), trim)
		Kit.box(g, Vector3(0.06, 0.32, 3.9), Vector3(s * 2.78, h - 0.02, 0), trim)
	# The front: the two doors in their frames, padlocked; the sign; the paper.
	for x: float in [-1.25, 1.25]:
		Kit.box(g, Vector3(1.04, 2.14, 0.04), Vector3(x, 1.07, hd + 0.02), Color(0.2, 0.22, 0.24))
		Kit.box(g, Vector3(0.9, 2.02, 0.03), Vector3(x, 1.06, hd + 0.055), steel)
		Kit.box(g, Vector3(0.9, 0.3, 0.004), Vector3(x, 0.2, hd + 0.072), steel.darkened(0.25))   # kicked dull at its foot
		Kit.box(g, Vector3(0.1, 0.05, 0.03), Vector3(x + 0.3, 1.05, hd + 0.085), IRON)          # the hasp, the lock
		Kit.box(g, Vector3(0.06, 0.08, 0.03), Vector3(x + 0.3, 0.98, hd + 0.1), Club.BRASS)
		var lamp := Kit.group(g, Vector3(x, 2.38, hd + 0.03))
		var on := lit and x > 0.0
		Kit.box(lamp, Vector3(0.2, 0.2, 0.06), Vector3(0, 0, 0.0), IRON)
		Kit.box(lamp, Vector3(0.14, 0.14, 0.1), Vector3(0, 0, 0.08), Kit.flat(Color(1.0, 0.86, 0.6), 1.4) if on else Color(0.78, 0.76, 0.66))
		if on:
			Kit.omni(g, Vector3(x, 2.2, hd + 0.6), Color(1.0, 0.82, 0.55), 1.6, 6.5)
		for k in 3:
			Kit.box(lamp, Vector3(0.012, 0.16, 0.012), Vector3(-0.05 + k * 0.05, 0, 0.135), IRON)
	var board := Kit.group(g, Vector3(0, 2.45, hd + 0.02))
	Kit.box(board, Vector3(1.0, 0.24, 0.04), Vector3.ZERO, Color(0.9, 0.88, 0.8))
	Props.words(board, "RESTROOMS", Vector3(0, 0, 0.025), 0.12, trim)
	var paper := Kit.group(g, Vector3(1.25, 1.5, hd + 0.072), Vector3(0, 0, -5))
	Kit.box(paper, Vector3(0.34, 0.24, 0.003), Vector3.ZERO, Color(0.96, 0.95, 0.9))
	Props.words(paper, "CLOSED", Vector3(0, 0.0, 0.003), 0.07, Color(0.75, 0.12, 0.1))
	Club.tape(paper, Vector3(-0.14, 0.11, 0.003), 0.12, 40.0)
	Club.tape(paper, Vector3(0.14, 0.11, 0.003), 0.12, -40.0)
	# The back: glass-block windows up high, the vent, the downspout, tags.
	var back := Kit.group(g, Vector3(0, 0, -hd), Vector3(0, 180, 0))
	for x: float in [-1.25, 1.25]:
		Kit.box(back, Vector3(1.0, 0.36, 0.04), Vector3(x, 2.17, 0.02), Color(0.62, 0.62, 0.58))
		Kit.pane(Kit.box(back, Vector3(0.9, 0.28, 0.03), Vector3(x, 2.17, 0.03), Kit.flat(Color(0.72, 0.8, 0.82, 0.85))))
		for k in 5:
			Kit.box(back, Vector3(0.012, 0.28, 0.034), Vector3(x - 0.36 + k * 0.18, 2.17, 0.03), Color(0.6, 0.62, 0.6))
	Kit.box(back, Vector3(0.56, 0.4, 0.1), Vector3(0.0, 2.15, 0.05), Color(0.5, 0.52, 0.5))
	for k in 5:
		Kit.box(back, Vector3(0.5, 0.025, 0.04), Vector3(0.0, 2.0 + k * 0.075, 0.11), Color(0.36, 0.38, 0.38), Vector3(-30, 0, 0))
	var tin := Color(0.62, 0.64, 0.62)
	Kit.box(back, Vector3(0.09, h - 0.2, 0.09), Vector3(2.32, (h - 0.2) * 0.5 + 0.2, 0.06), tin)
	Kit.box(back, Vector3(0.09, 0.09, 0.3), Vector3(2.32, 0.16, 0.15), tin)
	Alley.tags_on(Kit.group(back, Vector3(0, 0, 0.008)), [["PARK B", -1.45, 1.2, 0.42, 4.0], ["T2K", 1.2, 1.05, 0.36, -6.0]], 0.0, u)
	# A side: the water's shut-off box, a hose bib.
	var side := Kit.group(g, Vector3(2.5, 0, 0), Vector3(0, 90, 0))
	Kit.box(side, Vector3(0.36, 0.5, 0.14), Vector3(0.6, 1.3, 0.07), Color(0.42, 0.46, 0.44))
	Kit.cyl(side, 0.025, 0.12, Vector3(-0.8, 0.5, 0.06), Club.BRASS, Vector3(90, 0, 0), 6)
	return g
