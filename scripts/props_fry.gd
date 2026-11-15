extends RefCounted
## Things for Large Fry's block, Argonne Court (plans/fry.gd): the fire escape
## down its side and the vacant lot it comes down into; on the roof, the stair's
## bulkhead, the water tank on its stand, the pigeon loft and its birds, aerials,
## vents and a chimney; and the view from up there: the neighbours' roofs, the
## rows beyond, the city in the day's haze, the sky.
##
##   const Fry := preload("res://scripts/props_fry.gd")
##
## Same rules as props.gd: `p` is the Place, `b` the band, (u, v) the middle of
## the thing's floor space on the plan. Things with floor space keep it clear of
## walkers; the view is built straight into a node and takes none. A face
## (houses.gd's face or sub_face) has s along it, y up and t out of it.

const Props := preload("res://scripts/props.gd")
const Houses := preload("res://scripts/houses.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const RUST := Color(0.42, 0.23, 0.16)          # the fire escape: its black paint gone to rust
const STEEL := Color(0.32, 0.32, 0.34)
const GALV := Color(0.6, 0.62, 0.64)           # galvanised sheet
const AERIAL := Color(0.68, 0.7, 0.72)         # aerials in light metal: thin black lines read as cables
const CEDAR := Color(0.5, 0.37, 0.26)          # the water tank's staves, weathered
const WASH := Color(0.88, 0.86, 0.78)          # the pigeon loft's whitewash
const LOFT_TRIM := Color(0.22, 0.4, 0.3)
const TAR := Color(0.21, 0.21, 0.23)
const SILVER := Color(0.66, 0.67, 0.68)        # aluminium-painted roofs
const HAZE := Color(0.82, 0.85, 0.86)
const PIGEON := Color(0.56, 0.6, 0.68)


# ---------------------------------------------------------- the fire escape

## A fire escape on a side wall `f` (a face: s along the wall, y up, t out of
## it): a landing at each height in `floors`, s0..s1 along the wall and `out`
## deep, railed round; a stair from each landing up to the next; a drop ladder
## from the first down to the ground at `drop_s` (left down: someone used it);
## and a gooseneck ladder from the last up the wall and over the parapet (its
## top `top` high) onto the roof, at `neck_s`.
static func fire_escape(f: Node3D, floors: Array, s0: float, s1: float, out: float, drop_s: float, neck_s: float, top: float) -> void:
	var dark := RUST.darkened(0.3)
	var deck := RUST.darkened(0.12)
	for k in floors.size():
		var y: float = floors[k]
		# The landing: a grating on angle irons, two brackets under it to the wall.
		Houses.fb(f, s0, s1, y - 0.04, y, 0.02, out, deck)
		for t: float in [0.06, out - 0.03]:
			Houses.fb(f, s0, s1, y - 0.1, y - 0.04, t - 0.03, t + 0.03, RUST)
		for s: float in [s0 + 0.25, s1 - 0.25]:
			Houses.pipe(f, Vector3(s, y - 0.9, 0.02), Vector3(s, y - 0.08, out - 0.1), 0.03, dark, 4)
		# The railing round its open sides: a top rail, a toe bar, flat bars.
		var rail := y + 0.95
		Houses.fb(f, s0 - 0.02, s1 + 0.02, rail - 0.045, rail, out - 0.05, out, RUST)
		Houses.fb(f, s0, s1, y + 0.08, y + 0.12, out - 0.045, out - 0.01, RUST)
		var n := maxi(int((s1 - s0) / 0.24), 1)
		for i in n + 1:
			var s := s0 + (s1 - s0) * float(i) / float(n)
			Houses.fb(f, s - 0.014, s + 0.014, y, rail - 0.045, out - 0.04, out - 0.012, RUST)
		for s: float in [s0, s1]:
			Houses.fb(f, s - 0.02, s + 0.02, rail - 0.045, rail, 0.0, out - 0.05, RUST)
			for i in 3:
				var t := 0.14 + (out - 0.3) * float(i) / 2.0
				Houses.fb(f, s - 0.014, s + 0.014, y, rail - 0.045, t - 0.014, t + 0.014, RUST)
		# The stair up to the next landing: two stringers, treads, a handrail.
		if k + 1 < floors.size():
			var y2: float = floors[k + 1]
			var foot := Vector3(s1 - 0.3, y, 0.0)
			var head := Vector3(s0 + 0.8, y2, 0.0)
			for t: float in [out * 0.42, out - 0.1]:
				Houses.pipe(f, foot + Vector3(0, 0.06, t), head + Vector3(0, 0.06, t), 0.035, dark, 4)
			var steps := 11
			for i in range(1, steps):
				var q := foot.lerp(head, float(i) / float(steps))
				Houses.fb(f, q.x - 0.1, q.x + 0.1, q.y + 0.02, q.y + 0.06, out * 0.42, out - 0.1, deck)
			Houses.pipe(f, foot + Vector3(0, 0.95, out - 0.08), head + Vector3(0, 0.95, out - 0.08), 0.022, RUST, 5)
	# The drop ladder from the first landing to the ground.
	var low: float = floors[0]
	for d: float in [-0.2, 0.2]:
		Houses.fb(f, drop_s + d - 0.024, drop_s + d + 0.024, 0.0, low + 1.0, out + 0.02, out + 0.07, RUST)
	var rung := 0.3
	while rung < low + 0.9:
		Houses.fb(f, drop_s - 0.2, drop_s + 0.2, rung - 0.016, rung + 0.016, out + 0.03, out + 0.06, RUST)
		rung += 0.3
	# The gooseneck: up the wall from the top landing, over the parapet, down onto the roof.
	var last: float = floors[floors.size() - 1]
	for d: float in [-0.22, 0.22]:
		var s := neck_s + d
		Houses.fb(f, s - 0.024, s + 0.024, last, top + 0.12, 0.28, 0.33, RUST)
		Houses.fb(f, s - 0.024, s + 0.024, top + 0.07, top + 0.12, -0.55, 0.33, RUST)
		Houses.fb(f, s - 0.024, s + 0.024, top - 0.8, top + 0.12, -0.6, -0.55, RUST)
	rung = last + 0.3
	while rung < top:
		Houses.fb(f, neck_s - 0.22, neck_s + 0.22, rung - 0.016, rung + 0.016, 0.29, 0.32, RUST)
		rung += 0.3


# ------------------------------------------------------------------ the lot

## A clump of weeds: blades leaning out every way. Decorative: walked through.
static func weeds(n: Node3D, pos: Vector3, h: float, key: float) -> void:
	for i in 5:
		var a := key * 37.0 + i * 72.0
		var lean := 8.0 + 16.0 * Props.rnd(key + i)
		var tall := h * (0.55 + 0.45 * Props.rnd(key * 3.1 + i))
		var c := Color(0.4, 0.5, 0.22).lerp(Color(0.68, 0.62, 0.36), Props.rnd(key * 1.7 + i * 0.3))
		Kit.box(n, Vector3(0.05, tall, 0.014), pos + Vector3(0, tall * 0.45, 0), c, Vector3(lean * cos(deg_to_rad(a)), a, lean * sin(deg_to_rad(a))))


## An old mattress stood against a fence, ticking stripes, a stain.
static func mattress(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> void:
	var g: Node3D = p.prop(b, u, v, yaw, 1.4, 0.6)
	var lean := Kit.group(g, Vector3(0, 0, -0.12), Vector3(-12, 0, 0))
	Kit.bevel_block(lean, Vector3(1.35, 1.9, 0.2), Vector3.ZERO, Color(0.84, 0.82, 0.74), 0.05)
	for i in 7:
		Kit.box(lean, Vector3(0.05, 1.82, 0.006), Vector3(-0.54 + i * 0.18, 0.95, 0.1), Color(0.56, 0.64, 0.74))
	Kit.box(lean, Vector3(0.42, 0.3, 0.008), Vector3(0.22, 0.7, 0.102), Color(0.62, 0.5, 0.32))


## A stack of old tyres and one leaning on it.
static func tyres(p: Node3D, b: int, u: float, v: float, n := 3) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.75, 0.75)
	var rubber := Color(0.17, 0.17, 0.18)
	for i in n:
		var at := Vector3(0.02 * float(i % 2), 0.1 + i * 0.205, 0.0)
		Kit.cyl(g, 0.34, 0.2, at, rubber, Vector3(0, 9.0 * i, 0), 14)
		Kit.cyl(g, 0.2, 0.202, at, Color(0.07, 0.07, 0.08), Vector3.ZERO, 12)
		Kit.cyl(g, 0.345, 0.03, at, rubber.lightened(0.08), Vector3.ZERO, 14)


## A heap of broken brick and a few cinder blocks.
static func rubble(p: Node3D, b: int, u: float, v: float, w := 1.4, d := 0.9) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, w, d)
	var reds := [Color(0.58, 0.3, 0.24), Color(0.5, 0.26, 0.2), Color(0.66, 0.4, 0.3)]
	for i in 16:
		var x := (Props.rnd(i * 1.3 + u) - 0.5) * (w - 0.2)
		var z := (Props.rnd(i * 2.7 + v) - 0.5) * (d - 0.2)
		var y := 0.04 + 0.22 * (1.0 - absf(x) / w - absf(z) / d) * Props.rnd(i * 0.7)
		Kit.box(g, Vector3(0.21, 0.065, 0.1), Vector3(x, y, z), reds[i % 3], Vector3(20.0 * (Props.rnd(i * 3.3) - 0.5), 180.0 * Props.rnd(i * 4.1), 30.0 * (Props.rnd(i * 5.9) - 0.5)))
	for i in 2:
		Kit.block(g, Vector3(0.4, 0.2, 0.2), Vector3(w * 0.3 - i * 0.45, 0.0, d * 0.32), Color(0.62, 0.62, 0.6), Vector3(0, 12.0 * i, 0))


## Paper and cans on the ground: loose trash, decorative.
static func litter(n: Node3D, p: Node3D, u0: float, v0: float, u1: float, v1: float, count: int, key: float) -> void:
	for i in count:
		var at: Vector3 = p.pt(lerpf(u0, u1, Props.rnd(key + i * 1.9)), lerpf(v0, v1, Props.rnd(key * 2.3 + i * 3.1)), 0.006)
		if i % 3 == 0:
			Kit.cyl(n, 0.033, 0.12, at + Vector3(0, 0.03, 0), [Color(0.7, 0.2, 0.18), Color(0.3, 0.5, 0.7), Color(0.8, 0.78, 0.7)][i % 3], Vector3(90, 70.0 * i, 0), 8)
		else:
			Kit.box(n, Vector3(0.2, 0.004, 0.26), at, Color(0.9, 0.88, 0.8).darkened(0.1 * float(i % 2)), Vector3(0, 41.0 * i, 0))


## Where a house once stood against this wall: its outline in old plaster, the
## papers of its rooms, the line of its stair. On a face whose s runs from the
## back (0) to the front (deep).
static func ghost(f: Node3D, deep: float, h: float) -> void:
	Houses.fb(f, 0.4, deep - 0.05, 0.25, h - 0.3, 0.0, 0.012, Color(0.72, 0.64, 0.56))
	Houses.fb(f, 0.6, deep * 0.5 - 0.1, 0.5, 2.5, 0.012, 0.018, Color(0.62, 0.72, 0.6))     # a green paper downstairs
	Houses.fb(f, deep * 0.5 + 0.1, deep - 0.3, 3.3, 5.6, 0.012, 0.018, Color(0.82, 0.62, 0.64))   # pink upstairs
	Houses.fb(f, 0.4, deep - 0.05, 2.9, 3.05, 0.012, 0.02, Color(0.5, 0.42, 0.36))   # where the floor was
	Houses.pipe(f, Vector3(1.0, 0.3, 0.016), Vector3(3.6, 2.95, 0.016), 0.05, Color(0.55, 0.46, 0.4), 4)   # the stair


# ------------------------------------------------------------------ the roof

## The stair's bulkhead on the roof: a brick box under a coping and a tar top, a
## steel door in its front (its middle at door_u) under a caged lamp, a vent on top.
static func bulkhead(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, door_u: float, h := 2.6) -> void:
	var n: Node3D = p.node_of(b)
	p.block(u0, v0, u1, v1)
	var mid: Vector3 = p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5)
	Kit.box(n, Vector3(u1 - u0, h, v1 - v0), mid + Vector3(0, h * 0.5, 0), Houses.wall("brick"))
	Kit.box(n, Vector3(u1 - u0 + 0.16, 0.1, v1 - v0 + 0.16), mid + Vector3(0, h + 0.05, 0), Color(0.62, 0.6, 0.56))
	Kit.box(n, Vector3(u1 - u0 - 0.1, 0.02, v1 - v0 - 0.1), mid + Vector3(0, h + 0.11, 0), TAR)
	var f := Houses.face(p, b, door_u - 0.6, v1, 0.0)
	Houses.fb(f, 0.06, 1.14, 0.0, 2.14, 0.0, 0.04, STEEL)
	Houses.fb(f, 0.13, 1.07, 0.02, 2.07, 0.04, 0.07, Color(0.4, 0.48, 0.44))
	Houses.fb(f, 0.13, 1.07, 0.02, 0.32, 0.07, 0.076, GALV)
	Houses.fb(f, 0.9, 0.98, 0.98, 1.06, 0.07, 0.12, GALV)
	Houses.fb(f, 0.48, 0.72, 2.3, 2.52, 0.0, 0.03, STEEL)           # the lamp in its cage
	Houses.fb(f, 0.52, 0.68, 2.33, 2.48, 0.03, 0.13, Kit.flat(Color(1.0, 0.92, 0.7), 1.2))
	for s: float in [0.51, 0.6, 0.69]:
		Houses.fb(f, s - 0.008, s + 0.008, 2.32, 2.5, 0.12, 0.15, STEEL)
	var top := Kit.group(n, mid + Vector3(0.35, h + 0.12, -0.3))
	Kit.cyl(top, 0.12, 0.45, Vector3(0, 0.22, 0), GALV, Vector3.ZERO, 10)
	Kit.cyl(top, 0.22, 0.12, Vector3(0, 0.5, 0), GALV.darkened(0.1), Vector3.ZERO, 12, 0.08)


## A rooftop water tank: cedar staves in steel hoops under a conical lid, on a
## steel stand with cross braces, a ladder up the front to its hatch.
static func water_tank(p: Node3D, b: int, u: float, v: float, r := 1.15, legs := 2.0, h := 2.5) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, r * 2.0 + 0.2, r * 2.0 + 0.2)
	var a := r * 0.76
	for x: float in [-a, a]:
		for z: float in [-a, a]:
			Kit.box(g, Vector3(0.14, legs, 0.14), Vector3(x, legs * 0.5, z), STEEL)
			Kit.box(g, Vector3(0.3, 0.05, 0.3), Vector3(x, 0.025, z), STEEL.darkened(0.2))
	for side in 4:            # an X of flat bars between each pair of legs
		var turn := Basis(Vector3.UP, PI * 0.5 * side)
		var p0 := turn * Vector3(-a, 0.15, a)
		var p1 := turn * Vector3(a, legs - 0.15, a)
		var p2 := turn * Vector3(a, 0.15, a)
		var p3 := turn * Vector3(-a, legs - 0.15, a)
		Houses.pipe(g, p0, p1, 0.022, STEEL, 4)
		Houses.pipe(g, p2, p3, 0.022, STEEL, 4)
	for z: float in [-a, a]:
		Kit.box(g, Vector3(a * 2.0 + 0.3, 0.16, 0.12), Vector3(0, legs - 0.08, z), STEEL)
	for x: float in [-a * 0.5, 0.0, a * 0.5]:
		Kit.box(g, Vector3(0.1, 0.12, a * 2.0 + 0.3), Vector3(x, legs + 0.06, 0), STEEL.darkened(0.1))
	var body := legs + 0.12
	Kit.cyl(g, r, h, Vector3(0, body + h * 0.5, 0), CEDAR, Vector3.ZERO, 16)
	for k in 5:
		Kit.cyl(g, r + 0.025, 0.05, Vector3(0, body + 0.25 + k * (h - 0.5) / 4.0, 0), STEEL, Vector3.ZERO, 16)
	Kit.cyl(g, r + 0.1, 0.7, Vector3(0, body + h + 0.35, 0), CEDAR.darkened(0.3), Vector3.ZERO, 16, 0.12)
	Kit.cyl(g, 0.09, 0.22, Vector3(0, body + h + 0.8, 0), STEEL, Vector3.ZERO, 8)
	for x: float in [-0.2, 0.2]:              # the ladder
		Kit.box(g, Vector3(0.04, body + h + 0.2, 0.04), Vector3(x, (body + h + 0.2) * 0.5, r + 0.12), STEEL)
	var y := 0.3
	while y < body + h:
		Kit.box(g, Vector3(0.4, 0.03, 0.03), Vector3(0, y, r + 0.12), STEEL)
		y += 0.3


## A pigeon: blocks, not balls (round ones read as stones). Its feet at pos.
static func pigeon(parent: Node3D, pos: Vector3, yaw: float, tone := 0.0) -> void:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	var body := PIGEON.darkened(tone)
	Kit.box(g, Vector3(0.11, 0.1, 0.2), Vector3(0, 0.08, 0), body, Vector3(-12, 0, 0))
	Kit.box(g, Vector3(0.1, 0.06, 0.04), Vector3(0, 0.13, 0.08), Color(0.38, 0.52, 0.46))
	Kit.box(g, Vector3(0.075, 0.07, 0.08), Vector3(0, 0.17, 0.1), body.darkened(0.12))
	Kit.box(g, Vector3(0.022, 0.02, 0.045), Vector3(0, 0.165, 0.155), Color(0.32, 0.3, 0.28))
	Kit.box(g, Vector3(0.085, 0.02, 0.12), Vector3(0, 0.07, -0.15), body.darkened(0.4), Vector3(12, 0, 0))
	for x: float in [-0.057, 0.057]:
		Kit.box(g, Vector3(0.006, 0.022, 0.09), Vector3(x, 0.09, -0.02), Color(0.22, 0.22, 0.26))
		Kit.box(g, Vector3(0.016, 0.03, 0.016), Vector3(x * 0.5, 0.015, 0.02), Color(0.86, 0.46, 0.46))


## A pigeon loft: a whitewashed shed on short legs, its front wire mesh over a
## landing board and the trap, a sloping tar-paper roof; birds on the board,
## the roof and the perches inside.
static func pigeon_loft(p: Node3D, b: int, u: float, v: float, w := 3.2, d := 1.6, h := 2.0) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, w + 0.2, d + 0.5)
	var boards: Variant = Outdoor.tex("out_boards", 1.2, WASH, Color(1.0, 0.99, 0.92))
	var lift := 0.32
	for x: float in [-w * 0.5 + 0.06, w * 0.5 - 0.06]:
		for z: float in [-d * 0.5 + 0.06, d * 0.5 - 0.06]:
			Kit.box(g, Vector3(0.09, lift, 0.09), Vector3(x, lift * 0.5, z), Props.WOOD_DARK)
	Kit.box(g, Vector3(w, 0.06, d), Vector3(0, lift + 0.03, 0), Props.WOOD)
	Kit.box(g, Vector3(w, h - lift, 0.05), Vector3(0, (lift + h) * 0.5, -d * 0.5 + 0.025), boards)
	for x: float in [-w * 0.5 + 0.025, w * 0.5 - 0.025]:
		Kit.box(g, Vector3(0.05, h - lift, d), Vector3(x, (lift + h) * 0.5, 0), boards)
	var front := d * 0.5 - 0.025
	Kit.box(g, Vector3(w, 0.55, 0.05), Vector3(0, lift + 0.275, front), boards)
	# Inside, behind the mesh: the dark of the loft, perches, a bird or two.
	Kit.box(g, Vector3(w - 0.1, h - lift - 0.6, 0.01), Vector3(0, lift + 0.55 + (h - lift - 0.6) * 0.5, -d * 0.5 + 0.06), Color(0.32, 0.3, 0.27))
	for k in 2:
		Kit.box(g, Vector3(w - 0.2, 0.03, 0.22), Vector3(0, lift + 0.95 + k * 0.45, -d * 0.5 + 0.17), Props.WOOD)
	pigeon(g, Vector3(-0.7, lift + 0.965, -d * 0.5 + 0.17), 20.0, 0.1)
	pigeon(g, Vector3(0.6, lift + 1.415, -d * 0.5 + 0.17), -30.0, 0.25)
	# The mesh front, its frame and the trap in the middle.
	var mesh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w - 0.1, h - lift - 0.6)
	mesh.mesh = q
	mesh.material_override = Outdoor.chain_link()
	mesh.position = Vector3(0, lift + 0.55 + (h - lift - 0.6) * 0.5, front)
	g.add_child(mesh)
	for x: float in [-w * 0.5 + 0.05, -0.35, 0.35, w * 0.5 - 0.05]:
		Kit.box(g, Vector3(0.07, h - lift - 0.55, 0.06), Vector3(x, lift + 0.55 + (h - lift - 0.55) * 0.5, front), LOFT_TRIM)
	Kit.box(g, Vector3(w, 0.07, 0.06), Vector3(0, h - 0.035, front), LOFT_TRIM)
	Kit.box(g, Vector3(0.7, 0.32, 0.03), Vector3(0, lift + 0.72, front + 0.02), Color(0.2, 0.19, 0.18))
	for i in 6:
		Kit.box(g, Vector3(0.012, 0.3, 0.012), Vector3(-0.3 + i * 0.12, lift + 0.72, front + 0.05), STEEL, Vector3(10, 0, 0))
	# The landing board along the front, birds on it and on the roof.
	Kit.box(g, Vector3(w + 0.1, 0.04, 0.4), Vector3(0, lift + 0.55, front + 0.2), Props.WOOD)
	for bird: Array in [[-1.2, 25.0, 0.0], [-0.85, -40.0, 0.2], [0.75, 160.0, 0.05], [1.1, 10.0, 0.3]]:
		pigeon(g, Vector3(bird[0], lift + 0.57, front + 0.22), bird[1], bird[2])
	var roof := Kit.group(g, Vector3(0, h + 0.02, 0), Vector3(-7, 0, 0))
	Kit.box(roof, Vector3(w + 0.24, 0.06, d + 0.36), Vector3.ZERO, TAR)
	Kit.box(roof, Vector3(w + 0.26, 0.08, 0.05), Vector3(0, 0.0, (d + 0.36) * 0.5), LOFT_TRIM)
	pigeon(roof, Vector3(-0.4, 0.03, 0.3), 70.0, 0.15)
	pigeon(roof, Vector3(1.0, 0.03, 0.1), 200.0, 0.0)


## A television aerial on a foot: a mast, a boom, its elements. Light metal.
static func aerial(parent: Node3D, pos: Vector3, h := 3.0, yaw := 0.0) -> void:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.32, 0.05, 0.32), Vector3(0, 0.025, 0), Color(0.42, 0.42, 0.44))
	Kit.cyl(g, 0.03, h, Vector3(0, h * 0.5, 0), AERIAL, Vector3.ZERO, 6)
	for level: Array in [[h - 0.12, 1.7, 1.1], [h - 0.75, 1.1, 0.7]]:
		Kit.cyl(g, 0.02, level[1], Vector3(0, level[0], 0.15), AERIAL, Vector3(90, 0, 0), 5)
		for k in 6:
			var z: float = 0.15 - level[1] * 0.45 + k * level[1] * 0.18
			Kit.cyl(g, 0.012, level[2] - k * 0.09, Vector3(0, level[0], z), AERIAL, Vector3(0, 0, 90), 4)


## A vent stack (kind 0) or a mushroom vent (1). Small, but in the way.
static func vent(p: Node3D, b: int, u: float, v: float, kind := 0) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.34, 0.34)
	Kit.cyl(g, 0.15, 0.05, Vector3(0, 0.025, 0), TAR.lightened(0.15), Vector3.ZERO, 10)
	if kind == 0:
		Kit.cyl(g, 0.07, 0.85, Vector3(0, 0.425, 0), STEEL, Vector3.ZERO, 8)
		Kit.cyl(g, 0.09, 0.06, Vector3(0, 0.85, 0), STEEL.darkened(0.2), Vector3.ZERO, 8)
	else:
		Kit.cyl(g, 0.12, 0.5, Vector3(0, 0.25, 0), GALV, Vector3.ZERO, 10)
		Kit.cyl(g, 0.22, 0.14, Vector3(0, 0.57, 0), GALV.darkened(0.1), Vector3.ZERO, 12, 0.08)


## A brick chimney stack with two clay pots.
static func chimney(p: Node3D, b: int, u: float, v: float, w := 0.8, d := 0.6, h := 1.5) -> void:
	var g: Node3D = p.prop(b, u, v, 0.0, w, d)
	Kit.box(g, Vector3(w, h, d), Vector3(0, h * 0.5, 0), Houses.wall("brick_dark"))
	Kit.box(g, Vector3(w + 0.1, 0.08, d + 0.1), Vector3(0, h + 0.04, 0), Color(0.56, 0.54, 0.5))
	for x: float in [-w * 0.22, w * 0.22]:
		Kit.cyl(g, 0.11, 0.34, Vector3(x, h + 0.25, 0), Color(0.62, 0.36, 0.26), Vector3.ZERO, 8)


# -------------------------------------------------------------- the view

## A row of houses seen from above: one brick body from `ground` up to its flat
## roofs at y, u0..u1 along the plan and v0 (the backs) to v1 (the fronts);
## the roofs in tar or silver a run of houses at a time, the party walls a
## little proud on the nearer rows (`walls`), chimneys on some.
static func roof_row(n: Node3D, p: Node3D, u0: float, u1: float, v0: float, v1: float, y: float, ground: float, key: float, walls := false) -> void:
	Kit.box(n, Vector3(u1 - u0, y - ground, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y + ground) * 0.5), Houses.wall("brick_2"))
	var u := u0
	var k := 0
	while u < u1 - 0.1:
		var e := minf(u + 5.0 * float(1 + int(Props.rnd(key + k * 1.3) * 3.0)), u1)
		var r := Props.rnd(key + k * 2.9)
		Kit.box(n, Vector3(e - u - 0.06, 0.06, v1 - v0 - 0.4), p.pt((u + e) * 0.5, (v0 + v1) * 0.5 - 0.2, y + 0.03), SILVER if r > 0.45 else TAR)
		Kit.box(n, Vector3(e - u, 0.3, 0.24), p.pt((u + e) * 0.5, v1 - 0.12, y + 0.15), Houses.wall("brick_2"))     # the front's cornice line
		if walls:
			var s := u
			while s < e - 0.1:
				Kit.box(n, Vector3(0.16, 0.24, v1 - v0 - 0.4), p.pt(s, (v0 + v1) * 0.5 - 0.2, y + 0.12), Houses.wall("brick_2"))
				if Props.rnd(key + s * 0.37) > 0.45:
					Kit.box(n, Vector3(0.5, 0.9, 0.5), p.pt(s, v0 + 2.0 + 3.0 * Props.rnd(s), y + 0.45), Houses.wall("brick_dark"))
				s += 5.0
		u = e
		k += 1


## The day's sky all round, far off, a haze at the horizon going up into a
## clear blue, a lid over it; a plain of far city under it, and the towers on
## the horizon pale in the haze. `centre` is on the ground, under the roof.
static func day_sky(parent: Node3D, centre: Vector3, key := 1.0, dist := 700.0) -> void:
	var g := Kit.group(parent, centre, Vector3.ZERO, "DaySky")
	var rows := [[-0.2, HAZE.darkened(0.12)], [0.0, HAZE], [0.06, Color(0.74, 0.83, 0.9)], [0.25, Color(0.52, 0.69, 0.88)], [0.8, Color(0.38, 0.56, 0.82)]]
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a0 := TAU * float(i) / 48.0
		var a1 := TAU * float(i + 1) / 48.0
		for j in rows.size() - 1:
			var lo: Array = rows[j]
			var hi: Array = rows[j + 1]
			for corner: Array in [[a0, lo], [a1, lo], [a1, hi], [a0, lo], [a1, hi], [a0, hi]]:
				var col: Color = corner[1][1]
				band.set_color(col)
				band.add_vertex(Vector3(cos(corner[0]) * dist, float(corner[1][0]) * dist, sin(corner[0]) * dist))
	var sky := MeshInstance3D.new()
	sky.mesh = band.commit()
	sky.material_override = _sheet(Color.WHITE, true)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(sky)
	var lid := Kit.cyl(g, dist, 2.0, Vector3(0, dist * 0.8, 0), _sheet(Color(0.38, 0.56, 0.82)), Vector3.ZERO, 48)
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plain := Kit.box(g, Vector3(dist * 2.0, 0.1, dist * 2.0), Vector3(0, -0.6, 0), _sheet(Color(0.5, 0.52, 0.5)))
	plain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The city: pale towers in two ranks, the tall part off to the north-west.
	for rank in 2:
		var look := _far_look(HAZE.darkened(0.08 + 0.1 * rank).lerp(Color(0.62, 0.68, 0.78), 0.4))
		var z := -dist * (0.62 - 0.14 * rank)
		var x := -dist * 0.7
		var k := key * 5.3 + rank * 17.0
		while x < dist * 0.7:
			var r1 := Props.rnd(k * 1.1)
			var r2 := Props.rnd(k * 2.3)
			var r3 := Props.rnd(k * 3.7)
			k += 1.0
			var w := 16.0 + 22.0 * r1
			var mid := 1.0 - clampf(absf(x + dist * 0.15) / (dist * 0.5), 0.0, 1.0)
			var h := (18.0 + 90.0 * r2 * r2) * (0.3 + 0.7 * mid) * (1.15 if rank == 0 else 0.9)
			if r3 > 0.2:
				var tower := Kit.box(g, Vector3(w, h, 18.0), Vector3(x + w * 0.5, h * 0.5, z - 30.0 * r3), look)
				tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			x += w + 5.0 + 24.0 * r3


## A far tower's look: a pale sheet with its windows faintly over it (the
## out_far_windows picture in a second pass, as outdoor.gd's night skyline has them).
static func _far_look(c: Color) -> StandardMaterial3D:
	var m := _sheet(c)
	var path := Kit.TEX_DIR + "out_far_windows.png"
	if ResourceLoader.exists(path):
		var w := StandardMaterial3D.new()
		w.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		w.albedo_texture = load(path)
		w.albedo_color = Color(0.36, 0.4, 0.5, 0.4)
		w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		w.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		w.uv1_triplanar = true
		w.uv1_world_triplanar = true
		w.uv1_scale = Vector3.ONE / 22.0
		m.next_pass = w
	return m


## An unshaded sheet for the far view: it takes no light and casts no shadow.
static func _sheet(c: Color, vertex := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if vertex:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	return m
