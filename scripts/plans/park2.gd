extends RefCounted
## The second park, nothing like the first (a fenced asphalt court under
## floodlights): an old green neighbourhood square, LINDEN SQUARE. Low iron
## railings on a stone kerb all round, brick piers at the corners and at a gate
## on each side; the front gate stands open under an iron arch with the name and
## two globe lanterns on it, the other three are chained shut. Inside: lawns, four flagstone paths
## meeting at a brick ring round a bandstand (white columns, a green roof,
## bulbs round the eaves), double-globe lamps where the paths come in, benches
## facing it. A playground in the back-left corner inside its own red railing
## (swings, a slide, a roundabout, a climbing frame, a spring rider and
## hopscotch on soft red ground), picnic tables and a grill under the trees in
## the front-left, a round lily pond with a fountain and ducks among clipped
## yews in the front-right, stone chess tables in the back-right. Hedges inside
## the railings, beds of flowers either side of the way in.
## Round the square are streets on three sides: across the back street the
## fronts of grand old rowhouses with white marble steps, a stone church with a
## bell tower and a rose window, and a low old building whose front is a
## painted mural, a works with a water tower behind; side streets left and
## right with more rowhouses facing in. All of it is in 3D, with depth.
##
## One band (the street's): everything out of doors is in it, so nothing is
## hidden when he walks in. Three rooms:
##   street      the pavement in front (u -1.5..33.5)
##   PLAYGROUND  u 0..10.6, v 0..8.6, inside its railing (gate on the front)
##   SQUARE      u 0..32, v 0..22, the rest; in through the front gate
## He arrives on the pavement outside the gate.
## Numbers are metres on the plan (see place.gd): u from the left railing, v
## from the back railing; the front railing is at v = 22.
##
## Invented here (placeholders): LINDEN SQUARE (the arch and the board), the
## board's rules, SHILOH HILL BAPTIST CHURCH and its notices, the mural's
## STAND UP  SPEAK UP and PEN LUCY YOUTH MURAL PROJECT 1993.

const Props := preload("res://scripts/props.gd")
const Park := preload("res://scripts/props_park2.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const CU := 16.0          # the middle of the square: the bandstand
const CV := 10.8


static func build(p: Node3D) -> void:
	p.setup("THE GREEN", 32.0, 22.0)
	var st: int = p.street(-1.5, 33.5)
	p.arrive = p.pt(16.0, 23.25)
	p.room("PLAYGROUND", st, 0.0, 0.0, 10.6, 8.6, null, {"street": true})
	p.room("SQUARE", st, 0.0, 0.0, 32.0, 22.0, null, {"street": true})
	_ground(p, st)
	_railings(p, st)
	_middle(p, st)
	_playground(p, st)
	_front_left(p, st)
	_front_right(p, st)
	_back_right(p, st)
	_trees(p, st)
	_streets(p, st)
	_backdrop(p, st)


## The lawns, the paths, the brick ring and the playground's soft ground.
static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var grass := Kit.tex("stucco", 2.2, Color(0.4, 0.62, 0.3), true, Color(0.5, 0.9, 0.44))
	for i in 4:
		for j in 4:
			Kit.box(n, Vector3(8.0, 0.3, 5.5), p.pt(4.0 + i * 8.0, 2.75 + j * 5.5, -0.15), grass)
	var flags := Kit.tex("sidewalk", 1.6, Color(0.78, 0.72, 0.62), true, Color(1.0, 0.94, 0.8))
	for r: Array in [[14.9, 15.4, 17.1, 22.02], [14.9, 0.0, 17.1, 6.2], [0.0, 9.7, 11.3, 11.9], [20.7, 9.7, 32.02, 11.9]]:
		var rr: Rect2 = p.rect(r[0], r[1], r[2], r[3])
		Kit.box(n, Vector3(rr.size.x, 0.032, rr.size.y), Vector3(rr.get_center().x, -0.004, rr.get_center().y), flags)
	Kit.cyl(n, 5.0, 0.04, p.pt(CU, CV, -0.004), Kit.tex("brick", 1.0, Color(0.6, 0.32, 0.25), true, Color(1.0, 0.86, 0.8)), Vector3.ZERO, 40)
	Kit.cyl(n, 5.14, 0.03, p.pt(CU, CV, -0.006), Park.STONE, Vector3.ZERO, 40)
	var rubber := Kit.tex("stucco", 1.6, Color(0.7, 0.35, 0.26), true, Color(0.88, 0.5, 0.38))
	var soft: Rect2 = p.rect(0.18, 0.18, 10.45, 8.45)
	Kit.box(n, Vector3(soft.size.x, 0.034, soft.size.y), Vector3(soft.get_center().x, 0.003, soft.get_center().y), rubber)
	# anything not built on is dark ground, not sky
	Kit.box(n, Vector3(140.0, 0.2, 90.0), p.pt(16.0, 0.0, -0.42), Color(0.16, 0.16, 0.18))


## The railings on their stone kerb, the brick piers, the gates.
static func _railings(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var iron := Park.IRON
	for c: Vector2 in [Vector2(0, 0), Vector2(32, 0), Vector2(0, 22), Vector2(32, 22)]:
		Park.pier(p, st, c.x, c.y, 1.45)
	# the front: the gate stands open under its arch, lanterns on the arch. Its
	# piers are kept low: walking in up the path he passes behind the right one
	# from the camera, and a tall pier there hid him.
	Park.pier(p, st, 14.55, 22.0, 1.15, "cap")
	Park.pier(p, st, 17.45, 22.0, 1.15, "cap")
	p.fence(st, true, 22.0, 0.3, 31.7, [[14.25, 17.75]], 1.05, "rail", iron)
	Park.plinth(p, st, true, 22.0, 0.3, 14.25)
	Park.plinth(p, st, true, 22.0, 17.75, 31.7)
	Park.gate_arch(p, st, 14.91, 17.09, 22.0, "LINDEN SQUARE")
	Park.gate_leaf(n, p.pt(14.93, 21.6), 180.0, 1.07)
	Park.gate_leaf(n, p.pt(17.07, 21.6), 0.0, 1.07)
	p.block(13.86, 21.55, 14.93, 21.65)
	p.block(17.07, 21.55, 18.14, 21.65)
	Park.notice_board(n, p.pt(19.0, 22.09), 0.0, 1.3, 0.95, "LINDEN SQUARE", ["A CITY PARK", "OPEN DAWN TO DUSK", "NO DOGS  NO BIKES", "NO LOITERING"], Color(0.1, 0.3, 0.22), Color(0.96, 0.92, 0.8), 0.55, 0.1)
	p.block(18.35, 22.0, 19.65, 22.14)
	# the back: railings either side of a gate chained shut on the path
	Park.pier(p, st, 14.55, 0.0)
	Park.pier(p, st, 17.45, 0.0)
	for run: Array in [[0.3, 14.25], [17.75, 31.7]]:
		p.fence(st, true, 0.0, run[0], run[1], [], 1.05, "rail", iron)
		Park.plinth(p, st, true, 0.0, run[0], run[1])
	Park.shut_gates(p, st, true, 0.0, 14.91, 17.09)
	# left and right: the same where the cross path meets them
	for u: float in [0.0, 32.0]:
		Park.pier(p, st, u, 9.35)
		Park.pier(p, st, u, 12.25)
		for run: Array in [[0.3, 9.05], [12.55, 21.7]]:
			p.fence(st, false, u, run[0], run[1], [], 1.05, "rail", iron)
			Park.plinth(p, st, false, u, run[0], run[1])
		Park.shut_gates(p, st, false, u, 9.71, 11.89)
	# hedges inside the railings
	Park.hedge(p, st, 0.45, 21.1, 13.65, 21.68, 0.8)
	Park.hedge(p, st, 18.35, 21.1, 31.55, 21.68, 0.8)
	Park.hedge(p, st, 30.95, 12.75, 31.55, 21.0, 0.8)
	Park.hedge(p, st, 30.95, 0.55, 31.55, 8.85, 0.8)


## The bandstand in its brick ring, the lamps where the paths come in, the
## benches round it.
static func _middle(p: Node3D, st: int) -> void:
	Park.bandstand(p, st, CU, CV)
	# (the left one stands on the far side of its path: on the near side the
	# camera, following him in at the playground gate, ran into it)
	for off: Vector2 in [Vector2(1.75, 5.1), Vector2(-4.9, -1.95), Vector2(-1.75, -5.1), Vector2(5.1, -1.75)]:
		Park.lamp_post(p, st, CU + off.x, CV + off.y, 2)
	for d: Array in [[-1.0, -1.0, 45.0], [1.0, -1.0, 315.0], [-1.0, 1.0, 135.0], [1.0, 1.0, 225.0]]:
		Park.park_bench(p, st, CU + d[0] * 4.15, CV + d[1] * 4.15, d[2])
	# beds of flowers either side of the way in from the gate
	Park.flower_bed(p, st, 11.9, 16.9, 14.3, 20.7, 3.0)
	Park.flower_bed(p, st, 17.7, 16.9, 20.1, 20.7, 11.0)


static func _playground(p: Node3D, st: int) -> void:
	var red := Color(0.82, 0.18, 0.14)
	p.fence(st, true, 8.6, 0.3, 10.6, [[6.6, 8.4]], 0.85, "rail", red)
	p.fence(st, false, 10.6, 0.3, 8.6, [], 0.85, "rail", red)
	Park.swings(p, st, 2.6, 2.2, 0.0, 2, 3.0)
	Park.slide(p, st, 8.6, 1.7)
	# the climbing frame on the left, so the middle (where he stands) stays open
	# to the camera; the low roundabout just inside the gate
	Park.climbing_frame(p, st, 2.2, 6.4, 1.8)
	Park.roundabout(p, st, 5.5, 6.7, 20.0)
	Park.spring_rider(p, st, 9.7, 7.4, 300.0)
	Park.hopscotch(p, st, 5.6, 4.3)
	Park.basket(p, st, 0.75, 8.0)


## The picnic lawn in the front-left, under the trees.
static func _front_left(p: Node3D, st: int) -> void:
	Park.picnic_table(p, st, 4.2, 15.0, 0.0, Color(0.7, 0.48, 0.28), 1.0)
	Park.picnic_table(p, st, 7.9, 18.4, 90.0, Color(0.62, 0.42, 0.26), 0.1)
	Park.grill(p, st, 2.5, 19.0)
	Park.basket(p, st, 6.2, 13.0)
	Park.drinking_fountain(p, st, 8.2, 12.65)
	Park.lamp_post(p, st, 5.5, 9.15)
	# a trail of stepping stones from the path to the tables
	var trail := [[9.5, 12.45], [9.0, 13.15], [8.75, 13.95], [8.95, 14.75], [9.4, 15.45], [9.55, 16.25], [9.2, 17.0], [5.9, 16.1], [6.45, 16.7], [6.9, 17.3]]
	for i in trail.size():
		Park.stepping_stone(p, st, trail[i][0], trail[i][1], 0.27, i * 1.7)


## The pond among clipped yews in the front-right.
static func _front_right(p: Node3D, st: int) -> void:
	Park.pond(p, st, 25.6, 16.7, 2.4)
	Park.topiary(p, st, 22.0, 13.6, "cone", 1.0)
	Park.topiary(p, st, 29.2, 13.6, "cone", 1.0)
	Park.topiary(p, st, 22.0, 19.9, "tiers", 1.0)
	Park.topiary(p, st, 29.2, 19.9, "ball", 1.0)
	Park.park_bench(p, st, 21.6, 16.7, 90.0)
	Park.lamp_post(p, st, 26.0, 9.2)
	Outdoor.shrub(p, st, 24.0, 20.3, "a", 1.0, 30.0)
	Outdoor.shrub(p, st, 27.4, 20.4, "c", 0.9, 110.0)
	Outdoor.shrub(p, st, 30.2, 16.6, "b", 1.1, 200.0)


## The chess tables in the back-right, benches at the end of the back path.
static func _back_right(p: Node3D, st: int) -> void:
	Park.chess_table(p, st, 23.0, 4.6, 1.0)
	Park.chess_table(p, st, 27.4, 4.6, 7.0)
	Park.round_bed(p, st, 20.0, 4.4, 1.1, 5.0)
	Park.park_bench(p, st, 18.6, 0.9, 0.0)
	Park.park_bench(p, st, 13.4, 0.9, 0.0)
	Park.basket(p, st, 25.2, 7.2)
	Outdoor.shrub(p, st, 11.6, 5.0, "b", 1.0, 70.0)
	Outdoor.shrub(p, st, 30.0, 8.2, "d", 1.0, 15.0)


## Trees along the left and the back, where the camera never stands in them
## or looks through them at him, and along the streets round the square.
static func _trees(p: Node3D, st: int) -> void:
	for t: Array in [
		[1.2, 13.4, "a", 1.15, 80.0], [1.5, 17.0, "c", 1.0, 140.0], [1.1, 20.5, "b", 0.95, 300.0],
		[12.6, 2.6, "a", 1.3, 200.0], [21.0, 1.6, "b", 1.15, 45.0], [25.2, 1.2, "c", 1.0, 250.0], [29.8, 1.7, "a", 1.25, 120.0],
		[9.5, -1.25, "c", 1.0, 10.0], [23.0, -1.25, "b", 0.95, 170.0],
		[-1.25, 5.0, "a", 1.0, 60.0], [-1.25, 16.5, "d", 1.05, 230.0], [33.25, 3.0, "b", 0.9, 90.0],
	]:
		Outdoor.tree(p, st, t[0], t[1], t[2], t[3], t[4])


## The pavements and roads round the square, cars parked along them.
static func _streets(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var pave := Kit.tex("sidewalk", 2.4, Color(0.66, 0.64, 0.6))
	var tar := Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27))
	var kerb := Color(0.78, 0.76, 0.72)
	# the pavements next to the railings
	_slab(p, n, -2.4, -2.4, 34.4, 0.0, 0.0, pave)
	_slab(p, n, -2.4, 0.0, 0.0, 22.0, 0.0, pave)
	_slab(p, n, 32.0, 0.0, 34.4, 22.0, 0.0, pave)
	_slab(p, n, -2.6, -2.6, 34.6, -2.4, 0.0, kerb)
	_slab(p, n, -2.6, -2.4, -2.4, 22.0, 0.0, kerb)
	_slab(p, n, 34.4, -2.4, 34.6, 22.0, 0.0, kerb)
	# the roads: along the back, and down each side to the street in front
	_slab(p, n, -30.0, -8.6, 62.0, -2.6, -0.14, tar)
	_slab(p, n, -9.6, -2.6, -2.6, 24.6, -0.14, tar)
	_slab(p, n, 34.6, -2.6, 41.6, 24.6, -0.14, tar)
	for i in 26:
		Kit.box(n, Vector3(1.4, 0.01, 0.12), p.pt(-28.0 + i * 3.4, -5.6, -0.135), Color(0.85, 0.8, 0.55))
	for side: float in [-6.1, 38.1]:
		for i in 7:
			Kit.box(n, Vector3(0.12, 0.01, 1.4), p.pt(side, -1.0 + i * 3.4, -0.135), Color(0.85, 0.8, 0.55))
		Kit.box(n, Vector3(7.0, 0.012, 2.68), p.pt(side, 23.34, 0.002), tar)          # where it crosses the pavement in front
	# the far pavements, in front of the houses
	_slab(p, n, -30.0, -11.0, 62.0, -8.8, 0.0, pave)
	_slab(p, n, -30.0, -8.8, 62.0, -8.6, 0.0, kerb)
	_slab(p, n, -12.0, -8.6, -9.8, 22.0, 0.0, pave)
	_slab(p, n, -9.8, -8.6, -9.6, 22.0, 0.0, kerb)
	_slab(p, n, 41.8, -8.6, 44.0, 22.0, 0.0, pave)
	_slab(p, n, 41.6, -8.6, 41.8, 22.0, 0.0, kerb)
	_slab(p, n, -7.2, -12.5, 6.7, -11.0, 0.0, Kit.tex("sidewalk", 1.2, Color(0.7, 0.68, 0.62), true, Color(0.9, 0.88, 0.84)))   # the church's forecourt
	# parked cars
	Park.sedan(n, p.pt(2.5, -7.55), 90.0, Color(0.6, 0.13, 0.13))
	Park.sedan(n, p.pt(12.0, -7.55), 90.0, Color(0.22, 0.36, 0.58))
	Park.sedan(n, p.pt(27.5, -3.65), 270.0, Color(0.86, 0.83, 0.72))
	Park.sedan(n, p.pt(-8.55, 6.5), 180.0, Color(0.2, 0.42, 0.3))
	Park.sedan(n, p.pt(40.55, 9.0), 0.0, Color(0.5, 0.48, 0.52))
	# on the pavement in front: a street lamp, a hydrant, a litter basket
	Props.street_lamp(p, st, 6.0, 24.25)
	Props.street_lamp(p, st, 26.5, 24.25)
	Props.hydrant(p, st, 11.4, 24.2)
	Park.basket(p, st, 13.3, 22.75)
	# the lamps on the back street
	Park.lamp_post(p, st, -3.4, -9.45)
	Park.lamp_post(p, st, 22.0, -9.45)
	Park.lamp_post(p, st, 8.5, -1.3)


## A flat slab of ground from (u0, v0) to (u1, v1), its top at `top`.
static func _slab(p: Node3D, n: Node3D, u0: float, v0: float, u1: float, v1: float, top: float, look: Variant) -> void:
	var r: Rect2 = p.rect(u0, v0, u1, v1)
	Kit.box(n, Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, top - 0.15, r.get_center().y), look)


## What stands across the streets: the church and the grand houses across the
## back street, the mural and the works with its water tower, and the rows of
## houses along the side streets, their fronts facing the square.
static func _backdrop(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var red_brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.95, 0.8, 0.72))
	var dark_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.74, 0.62, 0.64))
	var brownstone := Kit.tex("stucco", 2.0, Color(0.5, 0.36, 0.28), true, Color(0.68, 0.46, 0.36))
	var cream := Kit.tex("stucco", 2.0, Color(0.85, 0.8, 0.66), true, Color(1.0, 0.94, 0.76))
	var blue := Kit.tex("stucco", 2.0, Color(0.6, 0.66, 0.78), true, Color(0.72, 0.82, 1.0))
	var sage := Kit.tex("stucco", 2.0, Color(0.6, 0.7, 0.56), true, Color(0.78, 0.92, 0.72))
	var formstone := Kit.tex("painted_block", 0.7, Color(0.62, 0.6, 0.56), true, Color(0.78, 0.8, 0.88))
	var line := -11.0
	# across the back street, left to right
	var row := [
		[-24.0, 6.0, 11.4, dark_brick, {"door_right": true}],
		[-18.0, 6.0, 11.2, cream, {}],
		[-12.0, 5.35, 11.6, red_brick, {"bay": true, "door_right": true}],
		[6.6, 5.8, 11.3, brownstone, {"bay": true}],
		[12.4, 6.0, 11.8, blue, {"door_right": true, "cornice": Color(0.92, 0.9, 0.84)}],
		[31.6, 5.8, 11.4, sage, {}],
		[37.4, 6.0, 11.2, red_brick, {"bay": true, "door_right": true}],
		[43.4, 6.0, 11.6, formstone, {}],
	]
	for i in row.size():
		var h: Array = row[i]
		Park.townhouse(n, p.pt(h[0] + h[1] * 0.5, line), 0.0, h[1], h[2], h[3], 3.0 + i * 2.7, h[4])
	Park.church(n, p.pt(1.5, -12.5), "SHILOH HILL BAPTIST CHURCH", ["SUNDAY WORSHIP 11 AM", "BIBLE STUDY WEDNESDAY 7 PM", "ALL ARE WELCOME"])
	Park.mural_building(n, p.pt(25.0, line), 13.2, "PEN LUCY", "STAND UP  SPEAK UP", "PEN LUCY YOUTH MURAL PROJECT 1993")
	Park.works(n, p.pt(25.4, -16.0), 12.0, 7.6, 12.0)
	# along the side streets, facing in: on the left the fronts face +x, on the right -x
	var sides := [[-10.4, 4.8], [-5.6, 5.8], [0.2, 5.4], [5.6, 5.8], [11.4, 5.2], [16.6, 5.4]]
	var looks := [red_brick, formstone, brownstone, cream, dark_brick, blue]
	for i in sides.size():
		var s: Array = sides[i]
		var mid: float = s[0] + s[1] * 0.5
		var tall_l := 8.3 if i == 2 else 11.1 + Props.rnd(i * 3.3) * 0.8      # one lower house in each row
		var tall_r := 8.3 if i == 4 else 11.1 + Props.rnd(i * 5.7) * 0.8
		Park.townhouse(n, p.pt(-12.0, mid), 90.0, s[1], tall_l, looks[i], 40.0 + i * 3.1, {"bay": i % 3 == 1, "door_right": i % 2 == 0})
		Park.townhouse(n, p.pt(44.0, mid), 270.0, s[1], tall_r, looks[(i + 3) % looks.size()], 70.0 + i * 3.7, {"bay": i % 3 == 0, "door_right": i % 2 == 1})
