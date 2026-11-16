extends RefCounted
## The pieces of Linden Square's corners (plans/park2_corners.gd; the civic
## worker's): the little brick public convenience, locked; the parks' tool shed
## with a barrow, leaf sacks and pots by it; the torn ends of the railing at the
## gap; trodden grass; a milk crate, a cool box and the cans left behind the
## bandstand.
##
## As in props.gd: `p` is the Place, `b` the band a thing stands in, (u, v) the
## middle of the floor it takes, `yaw` the way its front faces (0 the street, 90
## right, 180 the back, 270 left). Each takes up floor nobody can walk on, unless
## it says otherwise (the litter, the trodden grass and the torn bars are
## walked over).

const Props := preload("res://scripts/props.gd")
const Park := preload("res://scripts/props_park2.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const SLATE := Color(0.33, 0.35, 0.39)
const DOOR := Color(0.12, 0.32, 0.22)          # the square's green (props_park2.gd's DOORS)
const ENAMEL := Color(0.93, 0.93, 0.9)
const INK := Color(0.13, 0.18, 0.34)           # the figures on the plates
const SHED := Color(0.24, 0.4, 0.3)            # the shed's painted boards
const TRIM := Color(0.84, 0.86, 0.74)
const FELT := Color(0.29, 0.3, 0.32)
const RAW := Color(0.66, 0.52, 0.36)           # new wood: the boards over the window, the tools' handles
const BRASS := Color(0.8, 0.63, 0.27)
const KRAFT := Color(0.72, 0.58, 0.4)           # paper leaf sacks, a paper bag
const LEAVES := Color(0.58, 0.42, 0.2)
const WORN := Color(0.62, 0.57, 0.4)            # grass trodden to earth


## A padlock through a hasp, on a face whose plane is at `pos` (facing +z).
static func padlock(g: Node3D, pos: Vector3) -> void:
	Kit.box(g, Vector3(0.15, 0.04, 0.012), pos + Vector3(-0.05, 0.0, 0.006), Props.STEEL)          # the hasp
	Kit.box(g, Vector3(0.03, 0.05, 0.03), pos + Vector3(0.03, 0.0, 0.015), Props.STEEL.darkened(0.2))   # the staple
	Kit.ring(g, 0.024, 0.007, pos + Vector3(0.03, -0.035, 0.034), Props.STEEL)                     # the shackle
	Kit.box(g, Vector3(0.06, 0.065, 0.028), pos + Vector3(0.03, -0.08, 0.034), BRASS)             # the lock


## A white enamel plate with a figure on it, a man or a woman, at `pos` (the
## middle of the plate's back, on a face facing +z).
static func figure_plate(g: Node3D, pos: Vector3, woman: bool) -> void:
	Kit.box(g, Vector3(0.2, 0.24, 0.012), pos + Vector3(0, 0, 0.006), ENAMEL)
	var ink := Kit.flat(INK)
	var f := pos + Vector3(0, 0, 0.014)
	Kit.disc(g, 0.022, f + Vector3(0, 0.072, 0), ink, 0.004, 10)                  # the head
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.012, 0.06, 0.004), f + Vector3(s * 0.034, 0.012, 0), ink, Vector3(0, 0, s * 12.0))   # the arms
	if woman:
		Kit.prism(g, Vector3(0.09, 0.09, 0.004), f + Vector3(0, 0.0, 0), ink)     # the dress
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.012, 0.04, 0.004), f + Vector3(s * 0.016, -0.064, 0), ink)
	else:
		Kit.box(g, Vector3(0.048, 0.07, 0.004), f + Vector3(0, 0.012, 0), ink)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.018, 0.062, 0.004), f + Vector3(s * 0.014, -0.054, 0), ink)


## The square's old public convenience: the piers' brick on a stone plinth, a
## stone cornice, a slate roof in four slopes up to a little louvred vent. Two
## green doors in stone surrounds, a plate over each (a man, a woman: no
## words), each padlocked; a paper stuck on one; an iron lantern on the pier
## between them, its glass dull (it is not lit). A louvred vent high in its
## right side. 2.6 x 2.0.
static func convenience(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var w := 2.6
	var d := 2.0
	var h := 2.62
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var brick := Kit.tex("brick", 0.9, Color(0.6, 0.3, 0.22), false, Color(1.0, 0.86, 0.8))
	var stone := Park.STONE
	var z := d * 0.5
	Kit.block(g, Vector3(w + 0.08, 0.2, d + 0.08), Vector3.ZERO, stone.darkened(0.12))            # the plinth
	Kit.block(g, Vector3(w, h - 0.2, d), Vector3(0, 0.2, 0), brick)
	Kit.block(g, Vector3(w + 0.18, 0.16, d + 0.18), Vector3(0, h, 0), stone)                     # the cornice
	Kit.block(g, Vector3(w + 0.08, 0.07, d + 0.08), Vector3(0, h - 0.06, 0), stone.darkened(0.08))  # (its top hidden in the cornice)
	# the roof: four slopes up to a point (a square pyramid, stretched to the walls)
	var top := h + 0.16
	var roof := Kit.group(g, Vector3(0, top, 0))
	roof.scale = Vector3((w + 0.36) * 0.5, 1.0, (d + 0.36) * 0.5)
	Kit.cyl(roof, 1.4142, 0.72, Vector3(0, 0.36, 0), SLATE, Vector3(0, 45, 0), 4, 0.0)
	# the vent on the top, its louvres on the sides that show, a little cap
	Kit.block(g, Vector3(0.34, 0.3, 0.34), Vector3(0, top + 0.5, 0), stone)
	for k in 3:
		var y := top + 0.59 + k * 0.07
		Kit.box(g, Vector3(0.26, 0.025, 0.012), Vector3(0, y, 0.172), SLATE.darkened(0.25))
		Kit.box(g, Vector3(0.012, 0.025, 0.26), Vector3(0.172, y, 0), SLATE.darkened(0.25))
	Kit.cyl(g, 0.3, 0.16, Vector3(0, top + 0.88, 0), SLATE, Vector3(0, 45, 0), 4, 0.0)
	# the doors in their surrounds; over each its plate
	for i in 2:
		var x := -0.62 if i == 0 else 0.62
		Kit.block(g, Vector3(0.8, 1.95, 0.03), Vector3(x, 0.2, z), DOOR)
		for py: float in [0.32, 1.12]:
			Kit.block(g, Vector3(0.58, 0.68, 0.012), Vector3(x, 0.2 + py, z + 0.021), DOOR.lightened(0.1))
		Kit.box(g, Vector3(0.8, 0.14, 0.006), Vector3(x, 0.27, z + 0.018), Props.STEEL.darkened(0.2))   # the kick plate
		for s: float in [-1.0, 1.0]:
			Kit.block(g, Vector3(0.1, 1.95, 0.08), Vector3(x + s * 0.45, 0.2, z + 0.02), stone)       # the jambs
		Kit.block(g, Vector3(1.04, 0.14, 0.09), Vector3(x, 2.15, z + 0.025), stone)                  # the lintel
		padlock(g, Vector3(x + 0.28, 1.08, z + 0.02))
		figure_plate(g, Vector3(x, 2.43, z), i == 1)
	# a paper stuck on the right-hand door, a few lines on it, taped at the top
	var paper := Kit.group(g, Vector3(0.58, 1.52, z + 0.036), Vector3(0, 0, 4))
	Kit.box(paper, Vector3(0.21, 0.28, 0.003), Vector3.ZERO, Props.PAPER)
	for k in 4:
		Kit.box(paper, Vector3(0.15 - 0.04 * (k % 2), 0.014, 0.002), Vector3(-0.01, 0.07 - k * 0.045, 0.002), Color(0.6, 0.58, 0.55))
	for s: float in [-1.0, 1.0]:
		Kit.box(paper, Vector3(0.07, 0.022, 0.002), Vector3(s * 0.095, 0.135, 0.003), Color(0.86, 0.84, 0.72), Vector3(0, 0, -s * 35.0))
	# the lantern on its bracket over the pier between the doors: unlit
	Kit.box(g, Vector3(0.05, 0.05, 0.3), Vector3(0, 2.36, z + 0.15), Park.IRON)
	Kit.box(g, Vector3(0.18, 0.04, 0.18), Vector3(0, 2.29, z + 0.26), Park.IRON)
	Kit.box(g, Vector3(0.15, 0.22, 0.15), Vector3(0, 2.16, z + 0.26), Color(0.66, 0.7, 0.66))
	Kit.cyl(g, 0.15, 0.1, Vector3(0, 2.36, z + 0.26), Park.IRON, Vector3(0, 45, 0), 4, 0.02)
	Kit.box(g, Vector3(0.17, 0.03, 0.17), Vector3(0, 2.04, z + 0.26), Park.IRON)
	# the vent high in the right-hand side
	Kit.box(g, Vector3(0.03, 0.34, 0.66), Vector3(w * 0.5 + 0.015, 2.2, -0.1), stone)
	for k in 3:
		Kit.box(g, Vector3(0.012, 0.03, 0.56), Vector3(w * 0.5 + 0.034, 2.1 + k * 0.1, -0.1), SLATE.darkened(0.2))
	return g


## The parks' tool shed: green boards on a low concrete base, cream corner
## boards, a felt roof with its ridge running back and cream barge boards. The
## door in its front gable, ledged and braced, padlocked; a hose coiled on a
## hook by it; a broom and a rake leant on the front; its one window, in its
## right side, boarded over. A stack of pots by its front corner. 2.2 x 2.2,
## facing the front.
static func shed(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var w := 2.2
	var d := 2.2
	var h := 2.0                       # the eaves
	var rise := 0.62
	var g: Node3D = p.prop(b, u, v, 0.0, w, d)
	p.block(u + 0.28, v + d * 0.5, u + 1.0, v + d * 0.5 + 0.32)          # the broom and the rake leant on it
	var boards := Outdoor.tex("out_boards", 1.2, SHED, Color(SHED.r / 0.54, SHED.g / 0.48, SHED.b / 0.41))
	var z := d * 0.5
	Kit.block(g, Vector3(w + 0.06, 0.1, d + 0.06), Vector3.ZERO, Color(0.55, 0.55, 0.52))       # the base
	Kit.block(g, Vector3(w, h - 0.1, d), Vector3(0, 0.1, 0), boards)
	Kit.prism(g, Vector3(w, rise, d), Vector3(0, h + rise * 0.5, 0), boards)                     # the gables
	for s: float in [-1.0, 1.0]:
		for t: float in [-1.0, 1.0]:
			Kit.block(g, Vector3(0.08, h - 0.13, 0.08), Vector3(s * (w * 0.5 - 0.02), 0.1, t * (z - 0.02)), TRIM)
	# the roof: two felt slopes over the walls, the ridge, the barge boards down the front
	var slope := atan2(rise, w * 0.5)
	var run := (w * 0.5 + 0.16) / cos(slope)
	for s: float in [-1.0, 1.0]:
		var mid := Vector3(s * run * 0.5 * cos(slope), h + rise - run * 0.5 * sin(slope) + 0.03, 0)
		var tilt := Vector3(0, 0, -s * rad_to_deg(slope))
		Kit.box(g, Vector3(run, 0.05, d + 0.3), mid, FELT, tilt)
		Kit.box(g, Vector3(run, 0.12, 0.04), mid + Vector3(0, -0.05, z + 0.17), TRIM, tilt)
	Kit.box(g, Vector3(0.1, 0.06, d + 0.32), Vector3(0, h + rise + 0.055, 0), FELT.darkened(0.15))
	# the door: boards, three ledges and two braces, strap hinges, a padlock
	var dx := -0.25
	var dz := z + 0.02
	Kit.block(g, Vector3(0.94, 1.88, 0.03), Vector3(dx, 0.1, z + 0.005), TRIM)
	Kit.block(g, Vector3(0.8, 1.8, 0.04), Vector3(dx, 0.13, dz), Outdoor.tex("out_boards", 0.9, SHED, Color(SHED.r / 0.6, SHED.g / 0.55, SHED.b / 0.46)))
	for y: float in [0.3, 1.0, 1.7]:
		Kit.box(g, Vector3(0.72, 0.1, 0.025), Vector3(dx, 0.13 + y, dz + 0.032), SHED.lightened(0.14))
	for k in 2:             # (each brace rising from the hinge side)
		Park.strut(g, Vector3(dx - 0.3, 0.13 + 0.36 + k * 0.7, dz + 0.032), Vector3(dx + 0.3, 0.13 + 0.94 + k * 0.7, dz + 0.032), 0.07, SHED.lightened(0.14))
	for y: float in [0.3, 1.7]:
		Kit.box(g, Vector3(0.36, 0.045, 0.012), Vector3(dx - 0.2, 0.13 + y, dz + 0.05), Color(0.25, 0.26, 0.28))
	padlock(g, Vector3(dx + 0.33, 1.05, dz + 0.045))
	# the hose on its hook, left of the door
	Kit.box(g, Vector3(0.05, 0.05, 0.1), Vector3(-0.87, 1.42, z + 0.05), Color(0.25, 0.26, 0.28))
	for r: float in [0.15, 0.12]:
		Kit.ring(g, r, 0.032, Vector3(-0.87, 1.27, z + 0.07 + (0.15 - r)), Color(0.2, 0.55, 0.26))
	# a broom (its head on the ground) and a rake (its head up) leant on the front
	Kit.tube(g, Vector3(0.5, 0.1, z + 0.27), Vector3(0.6, 1.42, z + 0.035), 0.018, RAW)
	Kit.box(g, Vector3(0.34, 0.06, 0.1), Vector3(0.5, 0.1, z + 0.27), Color(0.4, 0.3, 0.2), Vector3(12, 0, 0))
	Kit.box(g, Vector3(0.32, 0.08, 0.08), Vector3(0.5, 0.04, z + 0.27), Color(0.62, 0.48, 0.28), Vector3(12, 0, 0))
	Kit.tube(g, Vector3(0.85, 0.0, z + 0.3), Vector3(0.82, 1.62, z + 0.06), 0.016, RAW)
	Kit.box(g, Vector3(0.42, 0.04, 0.04), Vector3(0.82, 1.64, z + 0.06), Props.STEEL.darkened(0.3))
	for k in 6:
		Kit.box(g, Vector3(0.012, 0.08, 0.012), Vector3(0.63 + k * 0.076, 1.6, z + 0.09), Props.STEEL.darkened(0.3), Vector3(-25, 0, 0))
	# the window in the right side, boarded over
	var sx := w * 0.5
	Kit.box(g, Vector3(0.03, 0.54, 0.68), Vector3(sx + 0.01, 1.35, -0.15), TRIM)
	Kit.box(g, Vector3(0.03, 0.44, 0.58), Vector3(sx + 0.02, 1.35, -0.15), Color(0.3, 0.35, 0.4))
	for k in 2:
		Kit.box(g, Vector3(0.025, 0.12, 0.78), Vector3(sx + 0.045, 1.25 + k * 0.2, -0.15), RAW.darkened(0.08 * k), Vector3(7.0 - k * 15.0, 0, 0))
	# pots stacked by the front left corner
	var pots: Node3D = p.prop(b, u - 0.82, v + z + 0.24, 0.0, 0.34, 0.34)
	var clay := Color(0.72, 0.38, 0.24)
	for k in 3:
		Kit.cyl(pots, 0.13, 0.2, Vector3(0.0, 0.1 + k * 0.08, 0.0), clay.darkened(0.04 * k), Vector3.ZERO, 10, 0.16)
	Kit.cyl(pots, 0.166, 0.03, Vector3(0.0, 0.405, 0.0), clay.lightened(0.06), Vector3.ZERO, 10)
	return g


## A wheelbarrow with leaves heaped in its tray: the wheel at its front (+z),
## the legs and handles behind.
static func barrow(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.66, 1.4)
	Kit.cyl(g, 0.19, 0.07, Vector3(0, 0.19, 0.5), Color(0.2, 0.2, 0.22), Vector3(0, 0, 90), 12)       # the tyre
	Kit.cyl(g, 0.08, 0.08, Vector3(0, 0.19, 0.5), Props.STEEL, Vector3(0, 0, 90), 8)
	var tray := Kit.group(g, Vector3(0, 0.5, 0.05), Vector3(-6, 0, 0))
	Kit.bevel_block(tray, Vector3(0.6, 0.26, 0.82), Vector3(0, -0.13, 0), Color(0.22, 0.45, 0.33), 0.04)
	Kit.box(tray, Vector3(0.52, 0.08, 0.74), Vector3(0, 0.12, 0), LEAVES)
	for k in 4:
		Kit.box(tray, Vector3(0.09, 0.012, 0.06), Vector3(-0.18 + k * 0.12, 0.165, -0.2 + Props.rnd(u + k) * 0.4), Color(0.85, 0.6, 0.2).darkened(0.1 * (k % 2)), Vector3(0, k * 40.0, 0))
	for s: float in [-1.0, 1.0]:
		Kit.tube(g, Vector3(s * 0.12, 0.19, 0.5), Vector3(s * 0.25, 0.42, -0.62), 0.018, Props.STEEL)     # the frame, out to the handles
		Kit.box(g, Vector3(0.035, 0.3, 0.035), Vector3(s * 0.2, 0.15, -0.3), Props.STEEL)              # a leg
		Kit.cyl(g, 0.026, 0.14, Vector3(s * 0.255, 0.43, -0.68), Color(0.2, 0.2, 0.22), Vector3(90, 0, 0), 6)   # a grip
	return g


## Two paper sacks of leaves standing, their tops rolled over, a green leaf
## printed on each, and a third lying on its side in front.
static func sacks(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.9, 0.56)
	for k in 2:
		var x := -0.2 + k * 0.42
		var tall := 0.6 - k * 0.07
		Kit.bevel_block(g, Vector3(0.38, tall, 0.28), Vector3(x, 0, -0.1), KRAFT.darkened(k * 0.06), 0.04)
		Kit.cyl(g, 0.06, 0.38, Vector3(x, tall + 0.02, -0.1), KRAFT.lightened(0.08), Vector3(0, 0, 90), 8)
		Kit.box(g, Vector3(0.09, 0.09, 0.006), Vector3(x, tall * 0.55, 0.043), Color(0.24, 0.5, 0.26), Vector3(0, 0, 45))
		Kit.box(g, Vector3(0.012, 0.07, 0.006), Vector3(x + 0.03, tall * 0.55 - 0.08, 0.043), Color(0.24, 0.5, 0.26), Vector3(0, 0, 30))
	var lying := Kit.bevel(g, Vector3(0.56, 0.26, 0.3), Vector3(0.08, 0.13, 0.14), KRAFT.darkened(0.03), 0.05)
	lying.rotation_degrees = Vector3(0, -8, 0)
	Kit.box(g, Vector3(0.22, 0.1, 0.2), Vector3(-0.28, 0.06, 0.18), LEAVES, Vector3(0, 20, 0))       # leaves spilt out of it
	return g


## A milk crate turned upside down for a seat.
static func crate(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.34, 0.34)
	var look := Color(0.74, 0.16, 0.14)
	Kit.block(g, Vector3(0.33, 0.26, 0.33), Vector3.ZERO, look)
	Kit.block(g, Vector3(0.336, 0.04, 0.336), Vector3(0, 0.26, 0), look.lightened(0.1))      # its bottom, now its top
	for k in 3:
		Kit.box(g, Vector3(0.06, 0.15, 0.004), Vector3(-0.1 + k * 0.1, 0.13, 0.166), look.darkened(0.4))
		Kit.box(g, Vector3(0.004, 0.15, 0.06), Vector3(0.166, 0.13, -0.1 + k * 0.1), look.darkened(0.4))
	return g


## A picnic cool box: a blue tub, a white lid, a handle over it.
static func cool_box(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.38)
	Kit.bevel_block(g, Vector3(0.54, 0.3, 0.36), Vector3.ZERO, Color(0.2, 0.42, 0.75), 0.03)
	Kit.bevel_block(g, Vector3(0.56, 0.07, 0.38), Vector3(0, 0.29, 0), ENAMEL, 0.025)
	Kit.box(g, Vector3(0.3, 0.03, 0.04), Vector3(0, 0.39, 0), ENAMEL.darkened(0.12))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.03, 0.05, 0.04), Vector3(s * 0.15, 0.37, 0), ENAMEL.darkened(0.12))
	return g


## What was left lying about: cans on their sides and one standing, a bottle
## in a brown paper bag. Walked over.
static func litter(p: Node3D, b: int, u: float, v: float, key := 0) -> void:
	var g: Node3D = p.prop(b, u, v, key * 37.0, 0.1, 0.1, false)
	var cans := Props.CANS
	Kit.cyl(g, 0.033, 0.12, Vector3(0.0, 0.06, 0.0), cans[key % cans.size()], Vector3.ZERO, 8)
	Kit.cyl(g, 0.033, 0.12, Vector3(0.22, 0.033, 0.12), cans[(key + 2) % cans.size()], Vector3(0, 30, 90), 8)
	Kit.cyl(g, 0.033, 0.12, Vector3(-0.26, 0.033, 0.16), cans[(key + 4) % cans.size()], Vector3(0, -50, 90), 8)
	Kit.cyl(g, 0.05, 0.22, Vector3(-0.08, 0.11, -0.18), KRAFT, Vector3.ZERO, 7, 0.04)
	Kit.cyl(g, 0.016, 0.08, Vector3(-0.08, 0.25, -0.18), Color(0.22, 0.4, 0.22), Vector3.ZERO, 6)


## A patch of grass trodden down to pale earth, an oval w x d turned `turn`
## (pale: a dark patch on the grass reads as a hole); `lift` keeps patches that
## overlap off one another. Walked over.
static func worn(p: Node3D, b: int, u: float, v: float, w: float, d: float, turn := 0.0, lift := 0.0) -> void:
	var mi := Kit.cyl(p.node_of(b), 0.5, 0.008, p.pt(u, v, 0.004 + lift), WORN, Vector3(0, turn, 0), 16)
	mi.scale = Vector3(w, 1.0, d)


## The gap broken in a railing that runs along v at u = `at`, from v a to v bb
## (place.gd's fence leaves the gap, a post either side of it, and the kerb
## built to each post): a stub of kerb knocked off short past each post, a bar
## bent out towards the pavement (+u) off it and one snapped short, the rails'
## torn ends twisted out, lumps of the kerb lying about.
static func broken_ends(p: Node3D, b: int, at: float, a: float, bb: float) -> void:
	var n: Node3D = p.node_of(b)
	var iron := Park.IRON
	var kerb := Kit.tex("block_plain", 0.9, Park.STONE, true, Color(0.84, 0.8, 0.72))
	for end: Array in [[a, 1.0], [bb, -1.0]]:
		var e: float = end[0]
		var s: float = end[1]
		Kit.box(n, Vector3(0.3, 0.22, 0.14), p.pt(at, e + s * 0.1, 0.11), kerb, Vector3(8.0 * s, 0, 0))    # sagging into the gap
		Kit.tube(n, p.pt(at, e + s * 0.1, 0.2), p.pt(at, e + s * 0.12, 0.6), 0.011, iron)
		Kit.tube(n, p.pt(at, e + s * 0.12, 0.6), p.pt(at + 0.3, e + s * 0.22, 0.97), 0.011, iron)
		Kit.tube(n, p.pt(at, e + s * 0.16, 0.2), p.pt(at + 0.02, e + s * 0.17, 0.42), 0.011, iron)
		for y: float in [0.145, 0.985]:
			Park.strut(n, p.pt(at, e, y), p.pt(at + 0.1, e + s * 0.19, y - 0.06), 0.045, iron)
	# lumps of the kerb, to the sides of the way through
	for l: Array in [[at - 0.1, a + 0.36, 0.16, 0.08, 0.12, 20.0], [at + 0.15, bb - 0.33, 0.13, 0.07, 0.1, -35.0], [at + 0.6, a + 0.42, 0.1, 0.06, 0.09, 50.0]]:
		Kit.box(n, Vector3(l[2], l[3], l[4]), p.pt(l[0], l[1], l[3] * 0.5), kerb, Vector3(0, l[5], 8.0))
