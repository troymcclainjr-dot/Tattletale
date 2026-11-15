extends RefCounted
## The back lot's props (plans/alley.gd): the club's back door and loading
## door, dumpsters, rubbish bags, a car stripped and left on blocks, tyres, a
## mattress, a sleeper under his blanket, a burning drum, steam off a grate, a
## street lamp gone dark, the lookout's perch, the backs of the row with its
## boarded house, the stash room's things, and the watcher that cuts the lot's
## fence down when the camera is behind it. As in
## props.gd each takes (u, v) on the plan and `yaw` (0 faces the street, 90
## right, 180 the back, 270 left), keeps its floor clear through place.gd's
## `prop` unless it says not, and returns its group. Every word on them is a
## placeholder.

const Props := preload("res://scripts/props.gd")
const Club := preload("res://scripts/props_club.gd")
const Street := preload("res://scripts/props_street.gd")
const Park := preload("res://scripts/props_park.gd")

const RUBBER := Color(0.13, 0.13, 0.14)        # old rubber, gone grey (black reads as a hole in the ground)
const RUST := Color(0.42, 0.21, 0.1)
const BAGS := [Color(0.26, 0.3, 0.27), Color(0.8, 0.8, 0.76), Color(0.3, 0.32, 0.38)]      # rubbish bags: dark green-grey, white, blue-grey
const PERCH := 0.305                          # the top of the lookout's perch (perch): where her feet go
const PLY := Color(0.55, 0.42, 0.26)          # plywood over the vacant's door and windows (houses.gd's)
const BLOCK := Color(0.52, 0.52, 0.5)         # cinder block
const STEEL := Color(0.3, 0.33, 0.36)
const BLACK := Color(0.07, 0.07, 0.08)
const STONE := Color(0.6, 0.58, 0.53)         # sills and lintels


## Tags in spray paint on a face of `parent` that faces +z, at depth z: each
## mark [text, x, y, height, tilt] (made-up words, placeholders; props_club.gd's spray).
static func tags_on(parent: Node3D, marks: Array, z: float, seed := 0.0) -> void:
	for i in marks.size():
		var m: Array = marks[i]
		var c: Color = Club.SPRAY[int(Props.rnd(seed + i * 4.1) * Club.SPRAY.size()) % Club.SPRAY.size()]
		Club.spray(parent, String(m[0]), Vector3(float(m[1]), float(m[2]), z + i * 0.003), float(m[3]), c, float(m[4]), seed + i * 7.7)


## Rust come through paint, on a face of `parent` that faces +z, round `at`
## (its z just off the face), about `size` across: three blots of rust, one
## over another, each its own shape and turned its own way (never a square).
static func rust(parent: Node3D, at: Vector3, size: float, seed := 0.0) -> void:
	var tones := [RUST, RUST.darkened(0.25), Color(0.56, 0.3, 0.14)]
	for k in 3:
		var r1 := Props.rnd(seed + k * 1.9)
		var r2 := Props.rnd(seed + k * 3.7 + 0.3)
		var turn := Kit.group(parent, at + Vector3((r1 - 0.5) * size * 0.5, (r2 - 0.5) * size * 0.35, 0.0006 * k), Vector3(0, 0, r2 * 180.0))
		var blot := Kit.cyl(turn, size * (0.5 - 0.13 * k), 0.001, Vector3.ZERO, tones[k], Vector3(90, 0, 0), 7)
		blot.scale = Vector3(1.0 + 0.7 * r1, 1.0, 0.45 + 0.4 * r2)


## Black bin-bag plastic, in a colour: a shine on it where the lamps catch it.
static func plastic(look: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = look
	m.roughness = 0.32
	m.metallic_specular = 0.8
	return m


## Rubbish bags, n in a heap round (u, v) on the plan: props_street.gd's filled
## sacks (`Street.sack`: slumped, lumpy low down, gathered at the neck, the tied
## ends standing up) in dark green-grey, white or blue-grey bin-bag film, matte
## (a round black bag reads as a bomb, or as a hole in the ground; balls one on
## another, as something else again). Decoration: they do not block.
static func bags(p: Node3D, b: int, u: float, v: float, n := 2, seed := 0.0) -> void:
	var node: Node3D = p.node_of(b)
	for i in n:
		var r := Props.rnd(seed + i * 3.3 + u * 0.7)
		var at: Vector3 = p.pt(u + (i - (n - 1) * 0.5) * 0.46 + (r - 0.5) * 0.08, v + (0.14 if i % 2 == 1 else -0.06))
		Street.sack(node, at, 0.22 + 0.07 * r, BAGS[(i + int(seed)) % BAGS.size()], Vector3(0, r * 360.0, (r - 0.5) * 12.0))


# ----------------------------------------------------------- the club's back

## The club's back door, from the alley (a picture of one on the wall: where it
## goes is a use point in front of it): a steel door in its frame with a pull
## plate and no handle, its foot kicked dull, a stencil, a strip of tape.
static func back_door(p: Node3D, n: Node3D, u: float, v: float, yaw: float) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(1.12, 2.2, 0.04), Vector3(0, 1.1, 0.02), Color(0.16, 0.17, 0.18))
	Kit.box(g, Vector3(0.96, 2.08, 0.03), Vector3(0, 1.04, 0.05), STEEL)
	Kit.box(g, Vector3(0.96, 0.3, 0.004), Vector3(0, 0.17, 0.067), STEEL.darkened(0.3))
	Kit.box(g, Vector3(0.1, 0.3, 0.02), Vector3(0.34, 1.05, 0.075), Props.STEEL)
	Props.words(g, "FIRE EXIT\nKEEP CLEAR", Vector3(0, 1.62, 0.072), 0.07, Color(0.95, 0.9, 0.8), 0.0, false)
	Club.tape(g, Vector3(-0.25, 1.22, 0.068), 0.25, 30.0)
	return g


## A roll-up loading door in a wall facing `yaw`, w wide and h high round (u, v)
## on its face: the housing over it, the rails, ribbed slats to the ground with
## a padlock at the foot, the stencil on the housing.
static func loading_door(p: Node3D, n: Node3D, u: float, v: float, yaw: float, w := 2.6, h := 2.6) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	var slats := Kit.tex("in_ribbed", 0.5, Color(0.48, 0.5, 0.52), false, Color(0.52, 0.54, 0.58))
	var iron := Color(0.24, 0.25, 0.28)
	Kit.box(g, Vector3(w + 0.3, 0.42, 0.3), Vector3(0, h + 0.21, 0.15), iron)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.1, h, 0.1), Vector3(s * (w * 0.5 + 0.05), h * 0.5, 0.05), iron)
	Kit.box(g, Vector3(w, h, 0.04), Vector3(0, h * 0.5, 0.05), slats)
	Kit.box(g, Vector3(w - 0.02, 0.08, 0.07), Vector3(0, 0.04, 0.06), iron.darkened(0.3))      # the bottom bar, its ends in the rails
	Kit.box(g, Vector3(0.07, 0.1, 0.03), Vector3(w * 0.3, 0.13, 0.11), Props.STEEL)
	Props.words(g, "DELIVERIES", Vector3(0, h + 0.21, 0.31), 0.12, Color(0.95, 0.85, 0.2))
	return g


## A steel dumpster on casters with its back to a wall: black plastic lids (one
## thrown back and the bags heaped over the rim when `open`), fork pockets on
## its ends, rust, a stencil, tags. 1.9 wide, 1.1 deep.
static func dumpster(p: Node3D, b: int, u: float, v: float, yaw: float, look: Color, open := false, marks := [], seed := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.9, 1.1)
	var lid := Color(0.1, 0.1, 0.11)
	Kit.box(g, Vector3(1.8, 1.0, 1.0), Vector3(0, 0.62, 0), look)
	Kit.box(g, Vector3(1.86, 0.07, 1.06), Vector3(0, 1.135, 0), look.darkened(0.3))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.06, 0.14, 1.04), Vector3(s * 0.93, 0.62, 0), look.darkened(0.4))
	for x: float in [-0.75, 0.75]:
		for z: float in [-0.36, 0.36]:
			Kit.box(g, Vector3(0.08, 0.05, 0.08), Vector3(x, 0.095, z), STEEL)
			Kit.cyl(g, 0.05, 0.035, Vector3(x, 0.05, z), RUBBER, Vector3(0, 0, 90), 8)
	if open:
		Kit.box(g, Vector3(0.88, 0.04, 1.04), Vector3(0.45, 1.19, 0), lid)
		var up := Kit.group(g, Vector3(-0.45, 1.17, -0.5), Vector3(-93, 0, 0))       # thrown back, against the wall
		Kit.box(up, Vector3(0.88, 0.04, 1.04), Vector3(0, 0.02, 0.52), lid)
		for k in 3:
			var bag := Kit.ball(g, 0.25, Vector3(-0.72 + k * 0.24, 1.16 + 0.07 * (k % 2), -0.12 + 0.13 * k), Street.bag_look(BAGS[k % BAGS.size()]), 7)
			bag.scale = Vector3(1.0, 0.72, 0.9)
		Kit.box(g, Vector3(0.18, 0.22, 0.012), Vector3(-0.35, 1.32, 0.2), Props.PAPER, Vector3(20, 35, 15))
	else:
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.88, 0.04, 1.04), Vector3(s * 0.45, 1.19, 0), lid, Vector3(0, 0, s * 2.0))
	for k in 3:
		var r := Props.rnd(u * 1.7 + v + k * 3.1 + seed)
		rust(g, Vector3(-0.6 + k * 0.55, 0.3 + 0.45 * r, 0.502), 0.2 + 0.2 * r, u + k * 2.7 + seed)
	Props.words(g, "KEEP LID CLOSED", Vector3(0.0, 0.98, 0.51), 0.055, Color(0.9, 0.88, 0.8), 0.0, false)
	tags_on(g, marks, 0.514, seed)
	return g


# ------------------------------------------------------------------ the lot

## A car stripped and left on blocks: no wheels, no doors on its near side
## (its left), no hood, no glass, the boot lid up, rust through faded paint.
## Its front faces `yaw`. 1.9 wide, 4.6 long. `marks`: tags on its near side.
static func stripped_car(p: Node3D, b: int, u: float, v: float, yaw: float, paint := Color(0.3, 0.38, 0.52), marks := []) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.9, 4.6)
	var w := 1.8
	var l := 4.5
	var y0 := 0.3            # the body's underside, on the blocks
	var y1 := 0.92           # the belt line
	var y2 := 1.38           # the roof
	var mid := (y0 + y1) * 0.5
	var faded := paint.lerp(Color(0.48, 0.48, 0.5), 0.4)
	var inside := Color(0.15, 0.13, 0.12)          # grimy, not black: the seat and the dash show against it
	var x := w * 0.5 - 0.025
	# Two cinder blocks crossed under each corner, where the wheels were.
	for bx: float in [-w * 0.5 + 0.32, w * 0.5 - 0.32]:
		for bz: float in [-l * 0.5 + 0.85, l * 0.5 - 0.85]:
			Kit.box(g, Vector3(0.39, 0.19, 0.19), Vector3(bx, 0.095, bz), BLOCK)
			Kit.box(g, Vector3(0.19, 0.1, 0.38), Vector3(bx, 0.24, bz), BLOCK.darkened(0.12))
	# The floor pan, the far side whole, the near side with its door openings.
	Kit.box(g, Vector3(w - 0.1, 0.05, l - 0.1), Vector3(0, y0 + 0.025, 0), inside)
	Kit.box(g, Vector3(0.05, y1 - y0, l), Vector3(x, mid, 0), faded)
	Kit.box(g, Vector3(0.05, y1 - y0, 1.1), Vector3(-x, mid, l * 0.5 - 0.55), faded)       # the front wing
	Kit.box(g, Vector3(0.05, y1 - y0, 1.2), Vector3(-x, mid, -l * 0.5 + 0.6), faded)       # the rear wing
	Kit.box(g, Vector3(0.05, y1 - y0, 0.1), Vector3(-x, mid, 0.05), faded)                 # the post between the doors
	Kit.box(g, Vector3(0.05, 0.16, 2.2), Vector3(-x, y0 + 0.08, 0.05), faded)              # the sill under them
	# The nose (the lamps gone, black holes), the tail, the bumpers.
	Kit.box(g, Vector3(w - 0.1, y1 - y0 - 0.1, 0.05), Vector3(0, y0 + (y1 - y0 - 0.1) * 0.5, l * 0.5 - 0.025), faded)
	Kit.box(g, Vector3(w - 0.1, y1 - y0, 0.05), Vector3(0, mid, -l * 0.5 + 0.025), faded)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.26, 0.13, 0.01), Vector3(s * 0.58, y1 - 0.24, l * 0.5 + 0.005), BLACK)
		Kit.box(g, Vector3(0.28, 0.13, 0.01), Vector3(s * 0.6, y1 - 0.2, -l * 0.5 - 0.005), BLACK)
	Kit.box(g, Vector3(w + 0.04, 0.13, 0.12), Vector3(0, y0 + 0.06, l * 0.5 + 0.03), Color(0.36, 0.3, 0.26), Vector3(0, 0, 5))        # hanging by one end
	Kit.box(g, Vector3(w + 0.04, 0.13, 0.12), Vector3(0, y0 + 0.07, -l * 0.5 - 0.06), Color(0.4, 0.38, 0.36))
	# Where the engine was: a dark hole, a few loose hoses.
	Kit.box(g, Vector3(w - 0.12, 0.5, 0.95), Vector3(0, y0 + 0.3, l * 0.5 - 0.6), inside)
	for k in 3:
		Kit.tube(g, Vector3(-0.5 + k * 0.45, y1 - 0.08, l * 0.5 - 0.3), Vector3(-0.3 + k * 0.4, y0 + 0.4, l * 0.5 - 0.9), 0.025, Color(0.12, 0.12, 0.12), 5)
	# Inside: the dash and the wheel, the front seats gone, the back seat torn.
	Kit.box(g, Vector3(w - 0.14, 0.18, 0.32), Vector3(0, y1 - 0.06, 1.0), Color(0.13, 0.12, 0.12))
	Kit.ring(g, 0.17, 0.025, Vector3(-0.38, y1 + 0.06, 0.82), BLACK, Vector3(-155, 0, 0))
	Kit.box(g, Vector3(w - 0.16, 0.4, 0.5), Vector3(0, y0 + 0.25, -0.78), Color(0.3, 0.2, 0.15))
	Kit.box(g, Vector3(w - 0.16, 0.5, 0.14), Vector3(0, y0 + 0.65, -1.02), Color(0.3, 0.2, 0.15), Vector3(-12, 0, 0))
	Club.tape(g, Vector3(0.2, y0 + 0.451, -0.7), 0.35, 0.0, Vector3(-90, 30, 0))
	# The pillars with no glass in them, the roof, the boot lid propped up.
	for s: float in [-1.0, 1.0]:
		Kit.tube(g, Vector3(s * (w * 0.5 - 0.07), y1, 1.15), Vector3(s * (w * 0.5 - 0.12), y2, 0.62), 0.035, faded, 5)
		Kit.box(g, Vector3(0.06, y2 - y1, 0.1), Vector3(s * (w * 0.5 - 0.1), (y1 + y2) * 0.5, 0.05), faded)
		Kit.tube(g, Vector3(s * (w * 0.5 - 0.07), y1, -1.32), Vector3(s * (w * 0.5 - 0.12), y2, -0.88), 0.035, faded, 5)
	Kit.box(g, Vector3(w - 0.18, 0.05, 1.56), Vector3(0, y2 + 0.025, -0.13), faded)
	rust(Kit.group(g, Vector3(0.2, y2 + 0.05, -0.4), Vector3(-90, 0, 0)), Vector3(0, 0, 0.002), 0.42, u + 0.5)      # (a face looking up)
	Kit.box(g, Vector3(w - 0.12, 0.42, 0.85), Vector3(0, y0 + 0.21, -l * 0.5 + 0.5), inside)
	var boot := Kit.group(g, Vector3(0, y1 + 0.02, -1.34), Vector3(68, 0, 0))
	Kit.box(boot, Vector3(w - 0.08, 0.04, 0.84), Vector3(0, 0, -0.42), faded)
	# Rust on the near side's wings (never out over the door holes), the tags.
	var near := Kit.group(g, Vector3(-w * 0.5, 0, 0), Vector3(0, -90, 0))         # its +z looks out of the near side
	for k in 4:
		var r := Props.rnd(u * 2.1 + v * 0.3 + k * 1.9)
		var along: float = [l * 0.5 - 0.47, -l * 0.5 + 0.45, l * 0.5 - 0.75, -l * 0.5 + 0.8][k]
		rust(near, Vector3(along, y0 + 0.14 + 0.24 * r, 0.002), 0.18 + 0.12 * r, u + k * 3.3)
	if not marks.is_empty():
		var side := Kit.group(g, Vector3(-w * 0.5 - 0.01, 0, 0), Vector3(0, -90, 0))
		tags_on(side, marks, 0.0, u)
	return g


## A car door lying where it was dropped (decoration: it does not block).
static func car_door(parent: Node3D, pos: Vector3, turn: float, paint := Color(0.3, 0.38, 0.52)) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, turn, 0))
	var faded := paint.lerp(Color(0.48, 0.48, 0.5), 0.4)
	Kit.box(g, Vector3(1.05, 0.06, 0.62), Vector3(0, 0.03, 0), faded, Vector3(0, 0, 3))
	Kit.box(g, Vector3(0.9, 0.012, 0.36), Vector3(0.0, 0.066, 0.06), Color(0.1, 0.09, 0.09), Vector3(0, 0, 3))
	return g


## Old tyres: n lying in a stack, and one more standing against them when
## `lean`. The stack takes 0.8 square of floor.
static func tyres(p: Node3D, b: int, u: float, v: float, n := 3, lean := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.8, 0.8)
	for i in n:
		var r := Props.rnd(u * 1.1 + v * 1.3 + i * 2.7)
		Kit.ring(g, 0.33, 0.16, Vector3(0.06 * (r - 0.5), 0.08 + i * 0.16, 0.06 * (0.5 - r)), RUBBER, Vector3(-90, 0, 0))
	if lean:
		Kit.ring(g, 0.33, 0.16, Vector3(0.05, 0.32, 0.3), RUBBER, Vector3(-14, 25, 0))
	return g


## A stained mattress standing on its end against a wall or a fence behind it,
## leaning back `lean` degrees. It takes 1.5 by 0.6 of floor.
static func mattress(p: Node3D, b: int, u: float, v: float, yaw: float, lean := 14.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 0.6)
	var tick := Kit.tex("in_stripe", 0.3, Color(0.76, 0.74, 0.66), false, Color(0.82, 0.8, 0.72))
	var m := Kit.group(g, Vector3(0, 0, 0.18), Vector3(-lean, 0, 0))
	Kit.bevel(m, Vector3(1.4, 1.95, 0.2), Vector3(0, 0.975, -0.1), tick, 0.06)
	for s: Array in [[0.25, 1.15, 0.3, 1.3], [-0.35, 0.6, 0.22, 0.8], [0.1, 0.35, 0.14, 1.6]]:
		var stain := Kit.disc(m, s[2], Vector3(s[0], s[1], 0.004), Color(0.55, 0.44, 0.28), 0.004, 12)
		stain.scale = Vector3(s[3], 1.0, 1.0)
	for i in 3:
		for k in 4:
			Kit.disc(m, 0.018, Vector3(-0.4 + i * 0.4, 0.4 + k * 0.4, 0.006), Color(0.4, 0.38, 0.34), 0.006, 6)
	return g


## Somebody asleep under a blanket on flattened cardboard, seen only as the
## lump of him, the back of his woolly hat, the soles of his shoes and his
## pack (no face: he has turned it to the wall). His head is at the +z end; it
## faces `yaw`. It takes 1.0 by 2.1 of floor.
static func sleeper(p: Node3D, b: int, u: float, v: float, yaw: float, blanket := Color(0.32, 0.34, 0.24)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.0, 2.1)
	var card := Color(0.58, 0.45, 0.3)
	Kit.box(g, Vector3(0.95, 0.012, 2.0), Vector3(0, 0.006, 0), card)
	Kit.box(g, Vector3(0.8, 0.008, 0.7), Vector3(0.05, 0.016, 0.6), card.darkened(0.15), Vector3(0, 9, 0))
	Kit.box(g, Vector3(0.78, 0.03, 1.75), Vector3(0, 0.03, -0.05), blanket.darkened(0.12), Vector3(0, -3, 0))
	for s: Array in [[0.0, 0.62, 0.21, 0.16], [0.04, 0.24, 0.27, 0.21], [-0.02, -0.2, 0.25, 0.19], [0.03, -0.6, 0.19, 0.14]]:
		var lump := Kit.ball(g, s[2], Vector3(s[0], s[3] * 0.62, s[1]), blanket, 10)
		lump.scale = Vector3(1.05, float(s[3]) / float(s[2]), 1.7)
	for x: float in [-0.08, 0.1]:                 # the soles of his shoes, out of the end of it
		Kit.box(g, Vector3(0.1, 0.25, 0.05), Vector3(x, 0.13, -0.92), Color(0.82, 0.8, 0.74), Vector3(-15, x * 60.0, 0))
	var wool := Color(0.5, 0.16, 0.14)
	var hat := Kit.ball(g, 0.13, Vector3(-0.02, 0.12, 0.9), wool, 10)
	hat.scale = Vector3(1.0, 0.95, 1.1)
	Kit.cyl(g, 0.135, 0.06, Vector3(-0.02, 0.12, 0.8), wool.darkened(0.25), Vector3(90, 0, 0), 10)        # its turned-up brim, where the blanket comes up to it
	var pack := Kit.group(g, Vector3(0.36, 0.0, 0.62), Vector3(0, -12, 0))                                  # his pack by his head, lying on its back
	Kit.bevel(pack, Vector3(0.3, 0.13, 0.42), Vector3(0, 0.075, 0), Color(0.22, 0.3, 0.46), 0.04)
	Kit.bevel(pack, Vector3(0.22, 0.05, 0.18), Vector3(0, 0.15, 0.08), Color(0.18, 0.24, 0.38), 0.02)
	Kit.cyl(g, 0.04, 0.1, Vector3(-0.38, 0.05, 1.0), Color(0.92, 0.9, 0.84), Vector3.ZERO, 8, 0.05)      # a cup for change
	return g


## A drum somebody burns rubbish in to keep warm: rusted, the fire over its rim
## (flames, each a picture turned to the camera, stretching and shrinking), holes
## punched round its foot glowing, and a warm light round it (`energy`) that
## wavers with the flames (Flicker).
static func burn_barrel(p: Node3D, b: int, u: float, v: float, energy := 1.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.62, 0.62)
	var drum := Color(0.3, 0.17, 0.1)
	Kit.cyl(g, 0.29, 0.86, Vector3(0, 0.43, 0), drum, Vector3.ZERO, 12)
	for y: float in [0.29, 0.58]:
		Kit.cyl(g, 0.3, 0.035, Vector3(0, y, 0), drum.darkened(0.25), Vector3.ZERO, 12)
	Kit.cyl(g, 0.3, 0.03, Vector3(0, 0.85, 0), drum.darkened(0.35), Vector3.ZERO, 12)
	Kit.cyl(g, 0.27, 0.02, Vector3(0, 0.83, 0), Kit.flat(Color(1.0, 0.45, 0.12), 2.2), Vector3.ZERO, 12)     # the coals under the rim
	var orange := Kit.flat(Color(1.0, 0.5, 0.12), 2.6)
	for k in 5:
		var a := TAU * k / 5.0 + 0.4
		Kit.cyl(g, 0.03, 0.01, Vector3(sin(a) * 0.292, 0.12, cos(a) * 0.292), orange, Vector3(90, rad_to_deg(a), 0), 8)
	var fire := Flicker.new()
	fire.name = "Fire"
	g.add_child(fire)
	var art := _flame()
	for f: Array in [[Vector3(-0.07, 0.83, 0.03), 0.4, 0.66], [Vector3(0.1, 0.83, -0.05), 0.32, 0.5], [Vector3(0.0, 0.83, 0.09), 0.26, 0.4], [Vector3(-0.12, 0.83, -0.08), 0.22, 0.34]]:
		var q := QuadMesh.new()
		q.size = Vector2(f[1], f[2])
		q.center_offset = Vector3(0, float(f[2]) * 0.5, 0)       # its foot in the drum: it grows up from there
		var flame := MeshInstance3D.new()
		flame.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.albedo_texture = art
		flame.material_override = m
		flame.position = f[0]
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.add_child(flame)
		fire.flames.append(flame)
	fire.light = Kit.omni(g, Vector3(0, 1.3, 0), Color(1.0, 0.62, 0.3), energy, 5.5)
	fire.energy = energy
	fire.step(0.0)
	return g


## A flame: a teardrop, round at its foot and drawn up to a point, white-yellow
## in its heart, orange to red at its edges and its tip, its edges soft.
static func _flame() -> Texture2D:
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := 1.0 - float(y) / float(h - 1)                       # 0 at its foot, 1 at its tip
		var half := 0.46 * pow(1.0 - t, 0.6) * sqrt(clampf(t * 5.0, 0.0, 1.0))
		for x in w:
			var d := absf((x + 0.5) / w - 0.5)
			var a := clampf((half - d) / maxf(half * 0.45, 0.002), 0.0, 1.0)
			var heart := clampf(1.0 - d / maxf(half, 0.002), 0.0, 1.0)
			var c := Color(0.95, 0.25, 0.05).lerp(Color(1.0, 0.68, 0.2), heart).lerp(Color(1.0, 0.95, 0.75), heart * heart * (1.0 - t))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * (1.0 - 0.4 * t)))
	return ImageTexture.create_from_image(img)


## A fire's flicker: its flames stretch and shrink and sway, each to its own
## beat, and its light wavers with them.
class Flicker extends Node3D:
	var flames: Array = []
	var light: OmniLight3D = null
	var energy := 1.4
	var _t := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			step(delta)

	func step(delta: float) -> void:
		_t += delta
		for i in flames.size():
			var f: Node3D = flames[i]
			var up := 1.0 + 0.2 * sin(_t * (8.0 + i * 2.3) + i * 1.7) + 0.1 * sin(_t * (17.0 + i * 3.1) + i)
			f.scale = Vector3(1.0 + 0.1 * sin(_t * (6.0 + i) + i * 2.9), up, 1.0)
		if light:
			light.light_energy = energy * (0.84 + 0.1 * sin(_t * 9.0) + 0.06 * sin(_t * 23.0 + 1.3))


## An extractor fan in a wall facing `yaw` (its face at (u, v)), its middle y up:
## a steel box, the fan's black mouth, a grille over it, grease run down the wall.
static func vent(p: Node3D, n: Node3D, u: float, v: float, yaw: float, y: float) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.7, 0.7, 0.32), Vector3(0, y, 0.16), Color(0.5, 0.52, 0.54))
	Kit.disc(g, 0.27, Vector3(0, y, 0.326), Color(0.08, 0.08, 0.09), 0.012, 16)
	for k in 5:
		Kit.box(g, Vector3(0.56, 0.02, 0.012), Vector3(0, y - 0.24 + k * 0.12, 0.338), Color(0.4, 0.42, 0.44))
	Kit.box(g, Vector3(0.5, 1.4, 0.004), Vector3(0.05, y - 1.05, 0.002), Color(0.2, 0.16, 0.1, 0.55))
	return g


## A storm grate in the alley with steam coming off it to about head height
## (decoration: it does not block; nobody trips on a grate): soft puffs, each a
## picture turned to the camera, that rise off it, grow, lean off on the draught
## and thin out, one after another (Drift).
static func steam_grate(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v))
	Kit.box(g, Vector3(0.94, 0.012, 0.66), Vector3(0, 0.006, 0), Color(0.04, 0.04, 0.05))
	for k in 7:
		Kit.box(g, Vector3(0.03, 0.012, 0.6), Vector3(-0.39 + k * 0.13, 0.018, 0), Color(0.22, 0.23, 0.25))
	var drift := Drift.new()
	drift.name = "Steam"
	g.add_child(drift)
	var soft := _puff()
	for k in 10:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = soft
		m.albedo_color = Color(0.8, 0.82, 0.86, 0.0)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var puff := MeshInstance3D.new()
		puff.mesh = q
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drift.add_child(puff)
		drift.puffs.append(puff)
	drift.step(0.0)                  # placed before the first frame
	return g


## A soft round puff: white, thick in the middle, gone at the edge.
static func _puff() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.5, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Steam off a grate: each puff rises from the grate to about head height in
## LIFE seconds, growing, leaning off with the draught and thinning out, then
## starts again; they are spread along the climb, so there is always a column.
class Drift extends Node3D:
	const LIFE := 3.4
	var puffs: Array = []
	var _t := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			step(delta)

	func step(delta: float) -> void:
		_t += delta
		var n := puffs.size()
		for i in n:
			var s := fposmod(_t / LIFE + float(i) / n, 1.0)            # how far up this one is, 0..1
			var puff: MeshInstance3D = puffs[i]
			var size := 0.32 + 0.9 * s
			puff.position = Vector3(0.3 * s * s + 0.05 * sin(i * 1.9 + _t * 0.8), 0.14 + 1.8 * s, -0.1 * s)
			puff.scale = Vector3(size, size * 0.85, 1.0)
			var m := puff.material_override as StandardMaterial3D
			var c := m.albedo_color
			c.a = 0.36 * smoothstep(0.0, 0.12, s) * pow(1.0 - s, 1.4)
			m.albedo_color = c


## A street lamp that has gone out: a cobra head like the street's, dark.
static func dead_lamp(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g: Node3D = Street.cobra_lamp(p, b, u, v, yaw, 1.17, 0.0)
	var lit := Kit.flat(Street.LAMP, 2.6)
	for c in g.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == lit:
			(c as MeshInstance3D).material_override = Kit.flat(Color(0.17, 0.18, 0.19))
	return g


## A heap of broken brick and plaster on a mound of dirt.
static func rubble(p: Node3D, b: int, u: float, v: float, w := 1.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, w, w * 0.7)
	var mound := Kit.ball(g, w * 0.5, Vector3(0, 0, 0), Color(0.3, 0.25, 0.2), 10)
	mound.scale = Vector3(1.0, 0.36, 0.7)
	for k in 9:
		var r1 := Props.rnd(u * 3.1 + k * 1.7)
		var r2 := Props.rnd(v * 2.3 + k * 2.9)
		var c: Color = [Color(0.55, 0.26, 0.2), Color(0.62, 0.3, 0.22), Color(0.82, 0.8, 0.74)][k % 3]
		Kit.box(g, Vector3(0.21, 0.07, 0.1), Vector3((r1 - 0.5) * w * 0.7, 0.12 + 0.08 * r2 - 0.1 * absf(r1 - 0.5), (r2 - 0.5) * w * 0.4), c, Vector3(20.0 * r2, 360.0 * r1, 15.0 * r1))
	return g


## Two milk crates side by side with a scrap of board across them: a seat, a
## step, a lookout's perch, its long side along x turned `yaw` (to lie across
## the camera's view, under the width of whoever stands on it). Its top is
## PERCH high. It does not keep its floor clear: whoever stands on it does.
static func perch(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.88, 0.6, 0.12)) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	Park.crate(g, Vector3(-0.185, 0, 0), 4.0, look)
	Park.crate(g, Vector3(0.195, 0, 0.02), -5.0, look.darkened(0.15))
	Kit.box(g, Vector3(0.8, 0.025, 0.3), Vector3(0.0, PERCH - 0.0125, 0.0), PLY.darkened(0.15), Vector3(0, -3, 0))
	return g


# ------------------------------------------------------------- the row's backs

## A window in the back of a house (on a wall facing `yaw`, its face at (u, v)),
## w by h from y0: kind "lit" (warm, half behind a curtain), "dark", "bars" (dark
## behind bars) or "boarded" (plywood and battens). A stone sill and lintel.
static func house_window(p: Node3D, n: Node3D, u: float, v: float, yaw: float, y0: float, w: float, h: float, kind: String, cloth := Color(0.85, 0.3, 0.32)) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w + 0.16, 0.07, 0.1), Vector3(0, y0 - 0.035, 0.05), STONE)
	Kit.box(g, Vector3(w + 0.12, 0.12, 0.03), Vector3(0, y0 + h + 0.06, 0.015), STONE)
	if kind == "boarded":
		Kit.box(g, Vector3(w + 0.1, h + 0.08, 0.02), Vector3(0, y0 + h * 0.5, 0.012), PLY)
		for y: float in [0.25, 0.72]:
			Kit.box(g, Vector3(w + 0.16, 0.08, 0.015), Vector3(0, y0 + h * y, 0.0295), PLY.darkened(0.3))
		return g
	var trim := Color(0.8, 0.78, 0.7) if kind == "lit" else Color(0.5, 0.48, 0.44)
	Kit.box(g, Vector3(w, h, 0.03), Vector3(0, y0 + h * 0.5, 0.015), trim)
	var glass: Variant = Kit.flat(Color(1.0, 0.78, 0.45), 0.9) if kind == "lit" else Color(0.05, 0.06, 0.09)
	Kit.box(g, Vector3(w - 0.12, h - 0.12, 0.01), Vector3(0, y0 + h * 0.5, 0.034), glass)
	if kind == "lit":
		Kit.box(g, Vector3((w - 0.12) * 0.45, h - 0.14, 0.008), Vector3(-(w - 0.12) * 0.27, y0 + h * 0.5, 0.043), Kit.flat(cloth, 0.35))
	Kit.box(g, Vector3(w - 0.12, 0.04, 0.012), Vector3(0, y0 + h * 0.5, 0.054), trim)
	if kind == "bars":
		for k in 5:
			Kit.cyl(g, 0.012, h + 0.04, Vector3(-w * 0.4 + k * w * 0.2, y0 + h * 0.5, 0.09), Props.IRON, Vector3.ZERO, 5)
	return g


## A back door on a house (a picture of one on a wall facing `yaw`): its frame,
## a door with a little window, a concrete step. `ply`: boarded over.
static func house_door(p: Node3D, n: Node3D, u: float, v: float, yaw: float, look := Color(0.3, 0.36, 0.3), ply := false) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(1.04, 2.14, 0.04), Vector3(0, 1.07 + 0.18, 0.02), Color(0.75, 0.73, 0.66))
	if ply:
		Kit.box(g, Vector3(1.0, 2.1, 0.02), Vector3(0, 1.05 + 0.18, 0.05), PLY)
	else:
		Kit.box(g, Vector3(0.88, 2.02, 0.03), Vector3(0, 1.01 + 0.18, 0.05), look)
		Kit.box(g, Vector3(0.4, 0.5, 0.01), Vector3(0, 1.72, 0.07), Color(0.05, 0.06, 0.09))
		Kit.ball(g, 0.03, Vector3(0.33, 1.15, 0.085), Club.BRASS, 6)
	Kit.box(g, Vector3(1.3, 0.18, 0.45), Vector3(0, 0.09, 0.225), Color(0.58, 0.57, 0.54))
	return g


# ----------------------------------------------------------- the stash room

## A small digital scale (pos: where it stands on a table top).
static func scale(parent: Node3D, pos: Vector3, turn := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, turn, 0))
	Kit.box(g, Vector3(0.17, 0.035, 0.21), Vector3(0, 0.0175, 0), Color(0.12, 0.12, 0.13))
	Kit.box(g, Vector3(0.14, 0.006, 0.14), Vector3(0, 0.038, -0.02), Color(0.74, 0.76, 0.78))
	Kit.box(g, Vector3(0.08, 0.02, 0.004), Vector3(0, 0.02, 0.107), Kit.flat(Color(0.4, 1.0, 0.5), 1.2))
	return g


## A camping stove on a milk crate with a board across it: two burners, one
## lit blue, a dented pot on it; the gas can on the floor beside it.
static func camp_stove(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.45)
	Park.crate(g, Vector3(0.08, 0, 0), 5.0, Color(0.2, 0.42, 0.7))
	var top := 0.296
	Kit.box(g, Vector3(0.4, 0.016, 0.36), Vector3(0.08, 0.288, 0), PLY.darkened(0.15))
	var green := Color(0.2, 0.4, 0.26)
	Kit.box(g, Vector3(0.36, 0.07, 0.24), Vector3(0.08, top + 0.035, 0), green)
	Kit.box(g, Vector3(0.36, 0.2, 0.01), Vector3(0.08, top + 0.17, -0.125), green, Vector3(-8, 0, 0))
	for x: float in [-0.01, 0.17]:
		Kit.ring(g, 0.05, 0.012, Vector3(x, top + 0.074, 0.0), BLACK, Vector3(-90, 0, 0))
	Kit.cyl(g, 0.035, 0.03, Vector3(0.17, top + 0.09, 0), Kit.flat(Color(0.35, 0.6, 1.0), 2.0), Vector3.ZERO, 10, 0.012)
	Kit.cyl(g, 0.09, 0.13, Vector3(0.17, top + 0.14, 0), Color(0.62, 0.62, 0.64), Vector3(0, 0, 3), 12)
	Kit.cyl(g, 0.05, 0.16, Vector3(-0.24, 0.08, 0.08), Color(0.78, 0.2, 0.14), Vector3.ZERO, 10)
	return g


## A cooler: white tub, blue lid.
static func cooler(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.6, 0.4)
	Kit.bevel(g, Vector3(0.56, 0.32, 0.36), Vector3(0, 0.16, 0), Color(0.9, 0.9, 0.88), 0.03)
	Kit.bevel(g, Vector3(0.58, 0.06, 0.38), Vector3(0, 0.35, 0), Color(0.2, 0.36, 0.7), 0.02)
	return g


## A duffel bag on the floor, zipped.
static func duffel(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.1, 0.1, 0.12)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.8, 0.4)
	var body := Kit.cyl(g, 0.17, 0.72, Vector3(0, 0.16, 0), look, Vector3(0, 0, 90), 10)
	body.scale = Vector3(1.0, 1.0, 0.82)
	for s: float in [-1.0, 1.0]:                # its round ends, black, and a stripe round it by each
		Kit.cyl(g, 0.15, 0.012, Vector3(s * 0.362, 0.16, 0), BLACK, Vector3(0, 0, 90), 10).scale = Vector3(1.0, 1.0, 0.82)
		Kit.cyl(g, 0.172, 0.05, Vector3(s * 0.26, 0.16, 0), Color(0.92, 0.9, 0.84), Vector3(0, 0, 90), 10).scale = Vector3(1.0, 1.0, 0.82)
	Kit.box(g, Vector3(0.6, 0.012, 0.02), Vector3(0, 0.3, 0.0), Props.STEEL)
	for x: float in [-0.13, 0.13]:              # the handles, up in a loop
		Kit.tube(g, Vector3(x, 0.29, -0.05), Vector3(x * 0.6, 0.42, 0), 0.012, BLACK, 4)
		Kit.tube(g, Vector3(x, 0.29, 0.05), Vector3(x * 0.6, 0.42, 0), 0.012, BLACK, 4)
	return g


## A patch of a wall's paper and plaster fallen away to the lath, on a face that
## faces +z in `parent` at depth z: about w by h round (x, y), its edge ragged
## (the hole is three overlapping pieces, and each strip of lath stops short
## where the plaster still holds, at a different place).
static func lath(parent: Node3D, x: float, y: float, z: float, w: float, h: float) -> void:
	var hole := Color(0.16, 0.12, 0.09)
	var pieces := [[0.0, 0.0, w, h * 0.7], [-w * 0.18, h * 0.12, w * 0.6, h], [w * 0.22, -h * 0.2, w * 0.5, h * 0.6]]
	for piece: Array in pieces:              # (one colour: overlapping, they are one shape)
		Kit.box(parent, Vector3(piece[2], piece[3], 0.004), Vector3(x + piece[0], y + piece[1], z + 0.002), hole)
	var rows := int(h / 0.05)
	for k in rows:
		var at := -h * 0.5 + 0.03 + k * 0.05
		var span := 0.0
		var mid := 0.0
		for piece: Array in pieces:          # how much of this row the hole takes: the widest piece it crosses
			if absf(at - float(piece[1])) < float(piece[3]) * 0.5 - 0.02 and float(piece[2]) > span:
				span = piece[2]
				mid = piece[0]
		if span <= 0.0:
			continue
		var cut := 0.06 + 0.12 * Props.rnd(x * 3.1 + k * 1.7)
		Kit.box(parent, Vector3(span - cut, 0.03, 0.006), Vector3(x + mid + (Props.rnd(y + k) - 0.5) * (cut - 0.04), y + at, z + 0.007), Color(0.55, 0.42, 0.28))


# ------------------------------------------------------------------- the fences

## The watcher (see Cutaway) for a fence along u at v on the plan, built in
## `tall`, with its stub built in `stub` (hidden till it is wanted).
static func cutaway(p: Node3D, b: int, tall: Node3D, stub: Node3D, v: float) -> Cutaway:
	var c := Cutaway.new()
	c.name = "Cutaway"
	c.tall = tall
	c.stub = stub
	c.line_z = p.pt(0.0, v).z
	stub.visible = false
	p.node_of(b).add_child(c)
	p.watchers.append(c)
	return c


## The watcher for a fence the camera comes round behind (the lot's chain link
## along the street): while the camera is past its line and he is on the far
## side of it, the fence is put away and a knee-high stub of it stands in its
## place, so the mesh is never a screen over him (props_street.gd's CarFade
## only fades it, and so near the camera even a ghost of it is a screen). It
## blocks the same either way: what stops him is the place's, not these.
## The place tells it where he is (place.watchers), or it finds him.
class Cutaway extends Node3D:
	var tall: Node3D = null          # the fence as it stands
	var stub: Node3D = null          # the low one shown in its place
	var line_z := 0.0                # the fence's line, world z: the camera is past it when its z is greater
	var _at := Vector3.INF
	var _lead: Node3D = null

	func watch(at: Vector3, _delta: float) -> void:
		_at = at

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or tall == null or stub == null or not is_visible_in_tree():
			return
		if _lead == null and get_tree().current_scene:
			_lead = get_tree().current_scene.get_node_or_null("Player") as Node3D
		if _lead:
			_at = _lead.global_position
		var eye := cam.global_position
		var cut := _at != Vector3.INF and eye.z > line_z and _at.z < line_z and eye.distance_to(_at) < 16.0
		tall.visible = not cut
		stub.visible = cut
