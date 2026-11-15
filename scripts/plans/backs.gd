extends RefCounted
## Rose Hill's backs: the alley behind Rose Hill Terrace's row (plans/street.gd),
## seen from its far (north) side looking south at the backs of the houses, so
## the row runs the other way from the street's: Old York Road on the left, the
## park on the right. One band, all out of doors. One room, ROSE HILL BACKS:
##
##   the alley, from the pavement of Old York Road (its mouth: E there goes out
##   onto Rose Hill's corner, plans/street.gd) west to the junk dumped at the
##   park's fence; 522's yard (no fence: a car under a tarp on its pad); the dead
##   yard behind 520, a vacant, where the back building came down (in through
##   the fallen boards, or round the side of the tarp and through the hole in
##   the chain-link: a couch, a spool for a table, a fire in a drum); and Miss
##   Bea's yard, through her gate (E at her back steps goes in, plans/bea.gd).
##
## The rest is seen, not walked: his yard behind its gate (E there goes in,
## plans/crib.gd), the others' yards behind their fences, two garages with
## roll-up doors (518's shut, 514's up a metre with the light on inside), the
## passage between Miss Bea's and 508's row, and at the west end the park's
## corner lot with its restroom block behind a chain-link fence that is broken
## open (E at the gap goes through into the lot, plans/park.gd); past it the
## court behind its own tall fence, the floodlights on.
##
## The camera stands on the near side of the alley, over the next street's
## yards, so nothing is built there. Poles along the yards' side carry the
## wires, three of them a lamp.
##
## Where it agrees with the others: each house's width, wall, trim and door are
## Rose Hill's (street.gd's), the backs 0.75 m lower than the fronts (the roofs
## fall to the back); his house and Miss Bea's are their own plans' rooms seen
## from behind (his yard 3.4 m deep behind the kitchen wing, its gate where
## crib.gd has it; her sun room and pantry, their windows, her back door, her
## clothes line, her board fence where bea.gd has them); the trees in the yards
## are street.gd's. The park's corner (the lot, the restroom, the gap) is
## park.gd's, and the court, its fences, lights, scoreboard and hoop are where
## park.gd has them. Where it does not, see the homes worker's notes (his lot is
## 15.8 m to the row's 14, Miss Bea's 11 m house in a 16 m lot, the park 3.4 m
## deeper than the row's lots, the poles on the other side of the alley there).
##
## Invented here (placeholders): the place's name ROSE HILL BACKS; the use
## points' labels OLD YORK ROAD and TO THE PARK (HOME and MISS BEA'S are the
## street's); the tags in the dead yard (RHT, LOOSE, KZ; the restroom's are
## props_backs.gd's); the people's names and their lines (talk_backs_*.json).
##
## Numbers are metres on the plan (see place.gd): u runs WEST, v runs north
## from the row's fronts: Rose Hill's (u, v) is (80 - u, 10 - v) here, crib.gd's
## (28.32 - u, 14 - v), bea.gd's (101.75 - u, 9 - v), park.gd's (173 - u, 17.6 - v).
## The main blocks' backs are on v = 7.4, the back buildings' on 10.6, the
## yards' fences on 14, the alley 14 to 17.5.

const Props := preload("res://scripts/props.gd")
const Street := preload("res://scripts/props_street.gd")
const Houses := preload("res://scripts/houses.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Walk := preload("res://scripts/sidewalk.gd")
const Park := preload("res://scripts/props_park.gd")
const Alley := preload("res://scripts/props_alley.gd")
const Backs := preload("res://scripts/props_backs.gd")
const StreetPlan := preload("res://scripts/plans/street.gd")
const ParkPlan := preload("res://scripts/plans/park.gd")

const NAME := "ROSE HILL BACKS"
const ALLEY := 14.0        # the yards' fences; the alley runs from here to NEAR
const NEAR := 17.5         # the alley's far side (the next street's yards: not built, the camera stands over them)
const MID := 15.85         # the gutter down the middle (in line with the park's)
const BACK := 10.6         # the back buildings' rear walls
const MAIN := 7.4          # the main blocks' backs
const KERB := 20.92        # Old York Road's west kerb (Rose Hill's OY0)
const CORNER := 23.32      # 532's end wall (Rose Hill's CORNER): Old York's pavement east of it
const LOT := 124.46        # 504's end wall: the park's corner lot from here to the court's fence
const COURT := 133.0       # the court's east fence (park.gd's u = 40)
const END := 133.6         # how far west the alley is walked: the junk dumped past the fence
const PARK_W := 173.0      # the court's west fence (park.gd's u = 0)
const WEST := 176.0        # how far it is drawn
const CRIB := [23.32, 28.32]
const BEA := [92.75, 101.75]
const PASSAGE := [101.75, 104.15]
const POLES := [38.0, 56.0, 74.0, 92.0, 110.0]


static func build(p: Node3D) -> void:
	p.setup(NAME, 150.0, NEAR)
	var st: int = p.band()
	p.arrive = p.pt(30.0, 15.75)
	# Dusk, as on Rose Hill: main.gd's sun off; _sky hangs the last of the sun
	# and the sky's own light. The camera stands back over the near yards, high
	# enough to see the roofs over him and low enough to look into the yards.
	p.ambient = 0.16
	p.sun_energy = 0.0
	p.room(NAME, st, KERB, MAIN, END, NEAR, null, {
		"street": true,
		"areas": [[KERB, ALLEY, END, NEAR], [54.36, BACK, 60.76, NEAR], [57.36, MAIN, 60.76, ALLEY], [60.76, MAIN, 67.14, NEAR], [BEA[0], 9.0, BEA[1], ALLEY]],
		"cam_near": 1.8, "cam_y": 3.3, "look_y": 2.8})
	Walk.begin()                    # the ground's pieces, gathered into a few meshes
	_ground(p, st)
	_old_york(p, st)
	Walk.end()
	_crib(p, st)
	_row(p, st)
	_dead_yard(p, st)
	_pad(p, st)
	_bea(p, st)
	_passage(p, st)
	_poles(p, st)
	Walk.begin()
	_park_end(p, st)
	_beyond(p, st)
	Walk.end()
	_sky(p, st)
	_people(p, st)
	# The ways out: his gate, Miss Bea's back steps, the alley's mouth on Old
	# York Road (Rose Hill's corner), the gap into the park's corner lot.
	p.use_point(st, "HOME", 25.92, 14.65, "goto:crib", 1.0, 1.9)
	p.use_point(st, "MISS BEA'S", 93.58, 10.3, "goto:bea", 0.9, 2.0)
	p.use_point(st, "OLD YORK ROAD", 21.6, 15.75, "goto:street", 1.2, 1.9)
	p.use_point(st, "TO THE PARK", PARK_W - (ParkPlan.CUT[0] + ParkPlan.CUT[1]) * 0.5, 14.65, "goto:park", 1.0, 1.9)


## A box on the plan: u0..u1, v0..v1, y0..y1.
static func _gb(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look)


## A block of house u0..u1 by v0..v1, its back wall on v1, h high: the walls, a
## flat roof, the coping along the back and the gutter under it (as
## props_park.gd's house_back draws them).
static func _block(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, h: float, look: Variant, roof: Variant) -> void:
	_gb(p, n, u0, u1, v0, v1, 0.0, h, look)
	_gb(p, n, u0 + 0.01, u1 - 0.01, v0 + 0.1, v1 - 0.3, h, h + 0.05, roof)
	_gb(p, n, u0, u1, v1 - 0.28, v1 + 0.06, h, h + 0.2, Park.COPING)
	_gb(p, n, u0 + 0.01, u1 - 0.01, v1 + 0.06, v1 + 0.16, h - 0.13, h - 0.03, Color(0.88, 0.87, 0.82))


## A downspout from the gutter at height h down the back wall on v, at u, to
## `foot` (the ground, or a lower roof), kicked out where it ends.
static func _spout(p: Node3D, n: Node3D, u: float, v: float, h: float, foot := 0.0) -> void:
	var tin := Color(0.88, 0.87, 0.82)
	_gb(p, n, u - 0.04, u + 0.04, v + 0.07, v + 0.15, foot + 0.15, h - 0.13, tin)
	_gb(p, n, u - 0.04, u + 0.04, v + 0.15, v + 0.39, foot + 0.11, foot + 0.19, tin)


# ------------------------------------------------------------------- the ground

static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	_gb(p, n, -60.0, 260.0, -120.0, 90.0, -0.8, -0.5, Color(0.12, 0.13, 0.12))
	# The alley: asphalt at its mouth, Old York Road's (street.gd's alley there
	# has a crack drawn in, and close to, a long black crack read as a cable),
	# then concrete (park.gd's) with a gutter down the middle. In pieces 12 m
	# long at most: the renderer lights a mesh with eight lamps at most.
	var asphalt := Walk.asphalt()
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.66, 0.66, 0.7))
	var gutter := Color(0.3, 0.31, 0.33)
	var cuts: Array = [CORNER, CORNER + 4.0]
	while cuts[cuts.size() - 1] < WEST - 0.01:
		cuts.append(minf(float(cuts[cuts.size() - 1]) + 12.0, WEST))
	for i in cuts.size() - 1:
		var u0: float = cuts[i]
		var u1: float = cuts[i + 1]
		var look: Variant = asphalt if i == 0 else concrete
		Walk.flat(p, n, u0, u1, ALLEY, MID - 0.18, -0.3, 0.0, look)
		Walk.flat(p, n, u0, u1, MID + 0.18, NEAR, -0.3, 0.0, look)
		Walk.flat(p, n, u0, u1, MID - 0.18, MID + 0.18, -0.3, -0.012, gutter)
	# Puddles in the low places.
	for s: Array in [[33.5, 16.6, 0.6, 10.0], [47.0, 15.1, 0.8, -20.0], [71.8, 15.3, 0.5, 35.0], [88.0, 16.4, 0.7, 0.0], [115.0, 15.0, 0.6, -40.0], [129.8, 16.5, 0.55, 15.0]]:
		Backs.puddle(p, n, s[0], s[1], s[2], s[3])
	# The near side: the next street's yards under the camera, dark grass, a
	# concrete edge along the alley with weeds at its foot.
	var dark := Outdoor.tex("out_grass", 3.6, Color(0.16, 0.2, 0.17), Color(0.6, 0.67, 0.64))
	var u := CORNER
	while u < WEST - 0.01:
		var u1 := minf(u + 12.0, WEST)
		Walk.flat(p, n, u, u1, NEAR + 0.15, NEAR + 12.15, -0.3, 0.0, dark)
		Walk.flat(p, n, u, u1, NEAR, NEAR + 0.15, -0.05, 0.08, Color(0.6, 0.6, 0.57))
		u = u1
	for k in 70:
		var wu := CORNER + 0.6 + float(k) * 2.2 + 0.8 * Props.rnd(k * 1.3)
		Kit.box(n, Vector3(0.05, 0.25 + 0.3 * Props.rnd(k * 2.1), 0.05), p.pt(wu, NEAR - 0.06, 0.15), Color(0.3, 0.46, 0.24), Vector3(15.0 * (Props.rnd(k * 3.7) - 0.5), 30.0 * k, 20.0 * (Props.rnd(k * 5.3) - 0.5)))


## Old York Road where the alley comes out (street.gd's, seen the other way):
## its pavements and kerbs, the road and its double yellow line, Rose Hill
## coming in from the right; the houses on its far side and on down it.
static func _old_york(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tar := Walk.asphalt()
	var pave := Outdoor.pavement()
	var paved := Outdoor.tex("out_paving", 3.2, Color(0.6, 0.58, 0.55), Color(0.86, 0.85, 0.83))
	var v := 60.0
	while v > -90.0 + 0.01:
		var v0 := maxf(v - 12.0, -90.0)
		Walk.flat(p, n, 11.42, KERB, v0, v, -0.36, -0.06, tar)
		Walk.flat(p, n, 9.02, 11.27, v0, v, -0.3, 0.0, pave)
		Walk.flat(p, n, 11.27, 11.42, v0, v, -0.3, 0.02, Outdoor.KERB)
		Walk.flat(p, n, -5.0, 9.02, v0, v, -0.3, 0.0, paved)
		v = v0
	# Its west side, and Rose Hill crossing it (its kerbs at -6.25 .. -6.4 and
	# -15.9 .. -16.05, the road between): the corner's stones, the pavements on.
	for span: Array in [[-6.4, 60.0], [-90.0, -15.9]]:
		var w0: float = span[0]
		while w0 < float(span[1]) - 0.01:
			var w1: float = minf(w0 + 12.0, span[1])
			Walk.flat(p, n, KERB, KERB + 0.15, w0, w1, -0.3, 0.02, Outdoor.KERB)
			Walk.flat(p, n, KERB + 0.15, CORNER, maxf(w0, -6.25) if w0 > -7.0 else w0, minf(w1, -16.05) if w1 < -15.0 else w1, -0.3, 0.0, pave)
			w0 = w1
	Walk.flat(p, n, KERB, CORNER + 12.0, -15.9, -6.4, -0.36, -0.06, tar)
	Walk.flat(p, n, KERB + 0.15, CORNER + 12.0, -6.4, -6.25, -0.3, 0.02, Outdoor.KERB)
	Walk.flat(p, n, KERB + 0.15, CORNER + 12.0, -16.05, -15.9, -0.3, 0.02, Outdoor.KERB)
	Walk.flat(p, n, CORNER, CORNER + 12.0, -6.25, -4.0, -0.3, 0.0, pave)
	Walk.flat(p, n, CORNER, CORNER + 12.0, -18.45, -16.05, -0.3, 0.0, pave)
	# The double yellow line, stopping either side of the crosswalk at the corner.
	for c: float in [16.05, 16.29]:
		for span: Array in [[-90.0, -6.2], [-3.0, 60.0]]:
			var a: float = span[0]
			while a < float(span[1]) - 0.01:
				var b: float = minf(a + 12.0, span[1])
				Walk.paint(p, n, c - 0.05, c + 0.05, a, b, Color(0.86, 0.72, 0.24), c + a, 0.06, 3.0)
				a = b
	# Old York's lamps: the corner's, and on down the road.
	Street.cobra_lamp(p, st, 21.57, 8.8, 270.0)
	Street.cobra_lamp(p, st, 10.77, -24.0, 90.0)
	Street.cobra_lamp(p, st, 21.57, -52.0, 270.0, 1.17, 0.0)
	# The far side, as Rose Hill has it (street.gd's _context, turned round):
	# 4027, the detached frame house, and the rows either side; then on down.
	var brick_a := StreetPlan._brick(Color(0.82, 0.76, 0.78))
	var brick_b := StreetPlan._brick(Color(0.95, 0.88, 0.86))
	var formstone := StreetPlan._formstone()
	var looks := [brick_a, formstone, brick_b, brick_a, formstone, brick_b, brick_a, brick_b]
	var trims := [Street.WHITE, Street.BROWN, Street.CREAM, Street.WHITE, Street.GREEN, Street.WHITE, Street.RED, Street.CREAM]
	var dc: Dictionary = Street.DOORS
	var doors := [dc["red"], dc["blue"], dc["black"], dc["green"], dc["wood"], dc["red"], dc["white"], dc["black"]]
	Street.plain_house(Street.face(p, st, 7.1, 2.4, 90.0), 6.0, 6.3, Color(0.82, 0.78, 0.62), Street.WHITE, dc["blue"], "1010", 2, false)
	var east := [[14.6, 4.8], [19.4, 4.4], [23.8, 4.7], [28.5, 4.5], [33.0, 4.6]]
	for i in east.size():
		var e: Array = east[i]
		Street.plain_house(Street.face(p, st, 7.1, 10.0 - e[0], 90.0), e[1], 8.5, looks[(i + 2) % 8], trims[(i + 1) % 8], doors[(i + 3) % 8], ["0101", "1001", "0110", "1000", "0010"][i], 2, i % 2 == 1)
	var sv := 6.6
	for i in 8:
		Street.plain_house(Street.face(p, st, 7.1, 10.0 - (sv - 4.6), 90.0), 4.6, 8.3, looks[i], trims[(i + 3) % 8], doors[(i + 5) % 8], ["0110", "1001", "0101", "0010", "1100", "0001", "1010", "0100"][i], 2, i % 2 == 0)
		sv -= 4.6
	StreetPlan._far_row(p, st, 7.1, 10.0 - 37.6, -90.0, 90.0, 2)
	# Its near side past Rose Hill, facing the road.
	StreetPlan._far_row(p, st, CORNER, -19.0, -90.0, 270.0, 5)


# --------------------------------------------------------------------- his house

## 532 from behind, as crib.gd has it: the main block, the kitchen wing on the
## party wall with the back bedroom over it, his back door up its steps, the
## kitchen's side window over the side yard; the yard's concrete, its rails and
## the gate that stays shut, the cans, the bench. Old York Road's board fence
## down the side (street.gd's).
static func _crib(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var o := {"trim": Color(0.7, 0.67, 0.58), "door": Color(0.82, 0.8, 0.72), "lit": ["k"], "porch": true, "curtain": Color(0.9, 0.26, 0.22)}
	var wing := 24.72
	_block(p, n, CRIB[0], CRIB[1], -1.8, 6.8, 7.45, brick, Houses.SILVER)
	_block(p, n, wing, CRIB[1], 6.8, BACK, 6.25, brick, Houses.SILVER)
	_spout(p, n, 27.9, BACK, 6.25)
	_spout(p, n, 23.62, 6.8, 7.45)
	_gb(p, n, CRIB[0], CRIB[1], 6.8, ALLEY, -0.1, 0.0, concrete)
	Park._door(n, p.pt(25.37, BACK), 0.0, 0.45, o)
	Park._steps(n, p.pt(25.37, BACK), 0.45, true)
	Park._window(n, p.pt(wing, 9.25), 270.0, 0.9, 1.45, 2.45, true, o, true)
	Park._window(n, p.pt(26.62, BACK), 0.0, 1.4, 4.3, 5.5, true, o.merged({"curtain": Color(0.86, 0.3, 0.28)}, true))
	# The yard: rails along the alley and the party wall, the gate (crib.gd's),
	# the board fence on Old York Road's side (street.gd's); the cans, the bench.
	var wire := Color(0.5, 0.52, 0.52)
	p.rail(st, true, 13.95, 23.5, 25.42, wire, 1.5)
	p.rail(st, true, 13.95, 26.42, CRIB[1] - 0.1, wire, 1.5)
	p.rail(st, false, CRIB[1] - 0.05, BACK + 0.1, 13.95, wire, 1.5)
	Backs.rail_gate(p, n, true, 13.95, 25.42, 26.42, 1.5, Color(0.36, 0.38, 0.4), true)
	Backs.boards(p, n, false, CRIB[0] + 0.08, 6.8, ALLEY, 1.8, Color(0.5, 0.36, 0.24), 1.0)
	Props.cans(p, st, 24.02, 13.45, 2)
	Props.bench(p, st, 27.87, 12.4, 270.0, 1.4, Color(0.4, 0.3, 0.2))


# ---------------------------------------------------------------------- the row

## The row's backs, 530 to 504 (props_park.gd's house_back): each one's main
## block and its back building (pairs of houses share theirs, so the sides
## alternate), the light court beside it, the back door up its steps, the yard
## and its fence. 520 (the dead yard) and 510 (Miss Bea) are drawn on their own.
static func _row(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tan := Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.8, 0.78, 0.98))
	var formstone := StreetPlan._formstone()
	var stucco := Kit.tex("stucco", 2.0, Color(0.74, 0.7, 0.6), true, Color(0.92, 0.88, 0.76))
	var dc: Dictionary = Street.DOORS
	var wash := [Color(0.95, 0.95, 0.92), Color(0.85, 0.25, 0.25), Color(0.25, 0.4, 0.75), Color(0.95, 0.85, 0.35), Color(0.3, 0.65, 0.4), Color(0.95, 0.6, 0.75)]
	var wash2 := [Color(0.3, 0.35, 0.6), Color(0.96, 0.96, 0.94), Color(0.96, 0.96, 0.94), Color(0.6, 0.3, 0.6), Color(0.9, 0.5, 0.2)]
	var houses := [
		[28.32, 6.68, {"brick": StreetPlan._brick(Color(0.9, 0.86, 0.86)), "trim": Street.CREAM, "door": dc["wood"], "h": 7.66, "bb_h": 6.0, "side": "l", "lit": ["k"], "curtain": Color(0.95, 0.93, 0.86), "fence": "wood", "porch": true, "extra": ["grill"], "cans": 2, "roof": Houses.SILVER}],
		[35.0, 6.47, {"brick": StreetPlan._brick(Color(1.0, 0.98, 0.96)), "bb": stucco, "trim": Street.BROWN, "door": dc["blue"], "h": 7.25, "bb_h": 3.3, "side": "r", "lit": ["cu"], "curtain": Color(0.92, 0.5, 0.62), "fence": "wood", "line": wash, "aerial": true}],
		[41.47, 6.51, {"brick": StreetPlan._brick(Color(0.86, 0.8, 0.82)), "trim": Street.BROWN, "door": dc["red"], "h": 6.96, "bb_h": 3.3, "side": "l", "lit": ["k", "m"], "curtain": Color(0.35, 0.6, 0.4), "fence": "chain", "gate_open": true, "line": wash2, "extra": ["trike", "planters"]}],
		[47.98, 6.38, {"brick": tan, "trim": Street.WHITE, "door": dc["blue"], "h": 7.08, "bb_h": 6.0, "side": "r", "lit": ["c"], "curtain": Color(0.9, 0.88, 0.78), "fence": "brick", "storm": true, "extra": ["chair"], "awning": Houses.TIN[1], "roof": Houses.SILVER}],
		[54.36, 6.4, {"brick": formstone, "trim": Street.BROWN, "door": dc["green"], "h": 7.1, "bb_h": 6.0, "side": "l", "lit": ["k"], "curtain": Color(0.95, 0.75, 0.25), "fence": "none", "porch": true, "yard": Outdoor.tex("out_slab_crack", 3.0, Color(0.6, 0.6, 0.58), Color(0.86, 0.86, 0.84))}],
		[67.14, 6.53, {"brick": StreetPlan._brick(Color(0.9, 0.84, 0.84)), "trim": Street.WHITE, "door": dc["green"], "h": 7.24, "bb_h": 6.0, "side": "l", "lit": ["u"], "curtain": Color(0.62, 0.5, 0.78), "fence": "none"}],
		[73.67, 6.33, {"brick": StreetPlan._brick(Color(0.84, 0.8, 0.84)), "trim": Street.RED, "door": dc["red"], "h": 7.27, "bb_h": 3.3, "side": "r", "lit": ["cu"], "curtain": Color(0.9, 0.6, 0.3), "fence": "wood", "line": wash, "aerial": true, "chimney": true, "cans": 3, "roof": Houses.SILVER}],
		[80.0, 6.38, {"brick": StreetPlan._brick(Color(0.95, 0.9, 0.92)), "trim": Street.WHITE, "door": dc["black"], "h": 7.26, "bb_h": 3.3, "side": "l", "lit": ["m"], "curtain": Color(0.95, 0.93, 0.86), "fence": "none"}],
		[86.38, 6.37, {"brick": StreetPlan._brick(Color(0.86, 0.82, 0.86)), "bb": stucco, "trim": Street.BROWN, "door": dc["black"], "h": 7.4, "bb_h": 3.3, "side": "r", "lit": ["k"], "curtain": Color(0.4, 0.65, 0.4), "fence": "chain", "extra": ["bike"], "bars": true}],
		[104.15, 7.51, {"brick": formstone, "trim": Street.WHITE, "door": dc["white"], "h": 7.68, "bb_h": 6.0, "side": "l", "lit": ["k", "cu"], "curtain": Color(0.9, 0.7, 0.2), "fence": "wood", "porch": true, "line": wash2, "extra": ["bike"], "roof": Houses.SILVER}],
		[111.66, 6.4, {"brick": tan, "trim": Street.BROWN, "door": dc["wood"], "h": 7.61, "bb_h": 6.0, "side": "r", "lit": ["u"], "curtain": Color(0.85, 0.3, 0.3), "fence": "chain", "extra": ["grill", "chair"]}],
		[118.06, 6.4, {"brick": StreetPlan._brick(Color(0.9, 0.86, 0.9)), "trim": Street.WHITE, "door": dc["blue"], "h": 7.55, "bb_h": 6.0, "side": "l", "lit": ["c"], "curtain": Color(0.95, 0.93, 0.86), "fence": "none", "aerial": true, "chimney": true}],
	]
	for h: Array in houses:
		Park.house_back(p, n, h[0], h[1], BACK, ALLEY, h[2])
	# The open ends of 508's row: windows down them, as on Rose Hill.
	Houses.end_windows(Street.face(p, st, LOT, 0.0, 180.0), 6.4, 9.0, -1, Houses.F0, 8.3, Street.WHITE, 6.4)
	Houses.end_windows(Street.face(p, st, 111.66, 0.0, 180.0), 7.51, 9.0, 1, Houses.F0, 8.43, Street.WHITE, 7.51)
	# 518's garage, shut and padlocked, and the chain-link with its gate beside it.
	Backs.garage(p, st, 70.4, 73.5, 7.6, 13.95, 2.8, Kit.tex("painted_block", 0.7, Backs.BLOCK, true, Color(0.78, 0.77, 0.72)))
	Park._chain(p, n, true, ALLEY - 0.06, 67.17, 68.89, 1.2)
	Park._chain_gate(p, n, ALLEY - 0.06, 68.89, 69.89, 1.2, false, Park.GALV)
	Park._chain(p, n, true, ALLEY - 0.06, 69.89, 70.36, 1.2)
	# 514's, its door up a metre and the light on inside; the same chain-link.
	Backs.garage(p, st, 83.25, 86.3, 7.6, 13.95, 2.7, Kit.tex("painted_block", 0.7, Backs.BLOCK, true, Color(0.82, 0.86, 0.8)), 2.3, 1.0, Color(0.56, 0.6, 0.66))
	Park._chain(p, n, true, ALLEY - 0.06, 80.03, 81.75, 1.2)
	Park._chain_gate(p, n, ALLEY - 0.06, 81.75, 82.75, 1.2, false, Park.GALV)
	Park._chain(p, n, true, ALLEY - 0.06, 82.75, 83.21, 1.2)
	# 504's corrugated sheets, two metres high round its yard, a gate of the same.
	Backs.corrugated(p, n, true, ALLEY - 0.06, 118.09, 119.81, 2.1, 1.0)
	Backs.corrugated(p, n, true, ALLEY - 0.06, 120.81, 124.43, 2.1, 2.0)
	Backs.corrugated(p, n, false, 124.42, MAIN, ALLEY - 0.06, 2.1, 3.0)
	var leaf := Kit.tex("in_ribbed", 0.5, Backs.RUST.lerp(Color(0.62, 0.64, 0.66), 0.3), false, Color(0.9, 0.86, 0.82))
	_gb(p, n, 119.86, 120.76, ALLEY - 0.09, ALLEY - 0.07, 0.04, 1.98, leaf)
	for y: float in [0.3, 1.6]:
		_gb(p, n, 119.86, 120.76, ALLEY - 0.15, ALLEY - 0.09, y, y + 0.07, Color(0.3, 0.26, 0.22))
	_gb(p, n, 120.58, 120.68, ALLEY - 0.065, ALLEY - 0.035, 1.0, 1.06, Props.STEEL)
	# Bags out by the gates for the truck, litter along the fences.
	Backs.bags(p, st, 46.2, 14.42, 2, 1.0)
	Backs.bags(p, st, 76.4, 14.45, 3, 2.0)
	Backs.bags(p, st, 113.6, 14.4, 2, 0.0)
	for k in 9:
		Park.litter(n, p.pt(30.0 + k * 11.3 + 3.0 * Props.rnd(k * 1.7), 14.42 + 2.6 * Props.rnd(k * 2.9), 0.03), 40.0 + k, 2 + k % 2)
	# The trees in the yards (street.gd's, their crowns over the roofs from the front too).
	for t: Array in [[32.5, 11.4, "a", 1.0, 250.0], [41.0, 12.3, "d", 1.05, 60.0], [49.5, 12.0, "b", 1.3, 140.0], [69.0, 12.4, "a", 1.15, 30.0], [79.5, 12.4, "d", 1.2, 310.0], [90.6, 12.6, "b", 1.2, 80.0], [108.6, 12.2, "d", 1.1, 200.0], [113.6, 12.5, "a", 1.1, 120.0]]:
		Outdoor.tree(p, st, t[0], t[1], t[2], t[3], t[4])


# ----------------------------------------------------------- 520: the dead yard

## 520 is empty, its windows boarded; its back building came down years ago
## and lies where it stood, a tree growing out of it, the plaster of its rooms
## still on the walls either side. The yard is where people go to be out of
## sight: in through the board fence along the alley that has fallen in, or
## through the hole in the chain-link from 522's pad. An old couch against the
## wall, a cable spool for a table, a fire in a drum.
static func _dead_yard(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var u0 := 60.76
	var u1 := 67.14
	var gone := 64.14                     # where the back building stood: gone .. u1, MAIN .. BACK
	var brick := StreetPlan._brick(Color(1.0, 0.96, 0.94))
	_block(p, n, u0, u1, -0.6, MAIN, 7.16, brick, Park.TAR)
	_spout(p, n, u0 + 0.2, MAIN, 7.16)
	var shut := {"boarded": true, "trim": Street.WHITE}
	Park._window(n, p.pt(62.45, MAIN), 0.0, 0.9, 1.4, 2.7, false, shut, true)
	Park._window(n, p.pt(62.45, MAIN), 0.0, 0.9, 4.0, 5.45, false, shut)
	# The back building's ghost on the main block and on 518's side wall: its
	# rooms' plaster, the floor line, a doorway and a window bricked up.
	var plaster := Kit.tex("stucco", 2.0, Color(0.7, 0.64, 0.56), true, Color(0.88, 0.82, 0.72))
	var infill := StreetPlan._brick(Color(0.7, 0.62, 0.6))
	var line := Color(0.36, 0.3, 0.26)
	_gb(p, n, gone, u1, MAIN, MAIN + 0.012, 0.0, 5.9, plaster)
	_gb(p, n, gone + 0.15, u1 - 0.1, MAIN + 0.012, MAIN + 0.022, 2.98, 3.08, line)
	_gb(p, n, gone + 0.6, gone + 1.5, MAIN + 0.012, MAIN + 0.022, 0.45, 2.55, infill)
	_gb(p, n, gone + 1.8, gone + 2.7, MAIN + 0.012, MAIN + 0.022, 3.9, 5.25, infill)
	_gb(p, n, u1 - 0.012, u1, MAIN + 0.012, BACK, 0.0, 5.9, plaster)
	_gb(p, n, u1 - 0.022, u1 - 0.012, MAIN + 0.15, BACK - 0.1, 2.98, 3.08, line)
	# What is left of it: the stumps of its walls, heaps of brick, a tree.
	_gb(p, n, gone + 0.02, gone + 0.22, MAIN + 0.3, BACK - 0.2, 0.0, 0.62, brick)
	_gb(p, n, gone + 0.4, u1 - 0.3, BACK - 0.22, BACK - 0.02, 0.0, 0.38, brick)
	Alley.rubble(p, st, 65.3, 8.5, 1.9)
	Alley.rubble(p, st, 66.2, 9.8, 1.2)
	p.block(gone, MAIN, u1, BACK)
	Outdoor.tree(p, st, 65.0, 8.6, "a", 0.95, 170.0)
	# The fences: chain-link down the left side with a hole torn in it (its mesh
	# peeled back against the rest and rolled up, the roll kept clear of walkers),
	# the boards along the alley mostly down.
	p.fence(st, false, u0 + 0.03, MAIN, ALLEY - 0.06, [[9.0, 11.0]], 1.2, "chain")
	Backs.torn(p, n, false, u0 + 0.03, 9.0, 11.0, 1.2, 1.0)
	p.block(u0 + 0.03, 11.45, u0 + 0.5, 11.95)
	Backs.broken_boards(p, n, ALLEY - 0.06, [[u0 + 0.03, 61.5, 1.3], [65.6, u1 - 0.04, 1.4]],
		[[62.3, 13.2, 1.3, 75.0], [63.4, 12.95, 1.1, 100.0], [64.6, 13.4, 1.2, 82.0], [62.9, 13.65, 0.9, 20.0], [61.9, 12.6, 0.7, 140.0]], 3.0)
	# The ground: dirt, weeds.
	_gb(p, n, u0, u1, MAIN, ALLEY, -0.1, 0.0, Outdoor.tex("out_dirt", 3.0, Color(0.33, 0.29, 0.24)))
	for i in 14:
		var k := 520.0 + float(i) * 2.17
		var wu := u0 + 0.3 + (gone - u0 - 0.5) * Props.rnd(k)
		var wv := MAIN + 0.4 + (ALLEY - MAIN - 0.8) * Props.rnd(k + 1.0)
		if i % 3 == 0:
			wu = u0 + 0.15 + 0.2 * Props.rnd(k + 2.0)      # along the fence
		for j in 4:
			Kit.box(n, Vector3(0.05, 0.3 + 0.4 * Props.rnd(k + j), 0.05), p.pt(wu + 0.05 * j, wv, 0.2), Color(0.3, 0.45 + 0.1 * Props.rnd(k + j + 3.0), 0.2), Vector3(18.0 * (Props.rnd(k + j + 5.0) - 0.5), 70.0 * j, 18.0 * (Props.rnd(k + j + 7.0) - 0.5)))
	# Where they sit: the couch against the wall, the spool, the drum, two crates.
	Props.couch(p, st, 62.45, 7.85, 0.0, 2.1, Color(0.42, 0.3, 0.26))
	Backs.spool(p, st, 62.6, 9.2, 0.45)
	Alley.burn_barrel(p, st, 63.3, 11.9, 1.4)
	Park.crate(n, p.pt(61.55, 12.75, 0.0), 24.0, Color(0.2, 0.4, 0.7))
	p.block(61.35, 12.55, 61.75, 12.95)
	Park.crate(n, p.pt(65.9, 11.3, 0.0), -15.0)
	p.block(65.7, 11.1, 66.1, 11.5)
	Park.litter(n, p.pt(62.2, 10.6, 0.03), 520.0, 4)
	Park.litter(n, p.pt(64.8, 12.6, 0.03), 521.0, 3)
	Alley.tags_on(Kit.group(n, p.pt(u0, MAIN + 0.012)), [["RHT", 0.85, 1.05, 0.5, -5.0], ["LOOSE", 2.75, 3.4, 0.34, 4.0]], 0.0, 520.0)
	Alley.tags_on(Kit.group(n, p.pt(u0, ALLEY - 0.02)), [["KZ", 0.35, 0.45, 0.3, 6.0]], 0.0, 521.0)


# ---------------------------------------------------------------- 522's pad

## 522 took its fence down to park on its yard: a car under a tarp on the pad,
## up on blocks at one corner, its owner's tools by it. (The house is in _row.)
static func _pad(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Backs.tarp_car(p, st, 58.6, 10.3, 180.0)
	p.block(56.06, BACK, 57.16, BACK + 0.9)               # 522's back steps
	var box := Kit.group(n, p.pt(58.2, 13.4), Vector3(0, 16, 0))
	Kit.box(box, Vector3(0.48, 0.22, 0.24), Vector3(0, 0.11, 0), Color(0.72, 0.16, 0.12))
	Kit.box(box, Vector3(0.3, 0.03, 0.04), Vector3(0, 0.235, 0), Props.STEEL)
	p.block(57.96, 13.28, 58.44, 13.52)
	Kit.box(n, Vector3(0.36, 0.02, 0.03), p.pt(57.9, 12.95, 0.012), Props.STEEL, Vector3(0, -30, 0))   # a wrench


# ------------------------------------------------------------------ Miss Bea

## 510 from behind, as bea.gd has it: the one-storey extension across her whole
## width (the sun room on the right, all windows, round the end too; the pantry
## on the left, its high window, her back door up its steps, the light on by
## it), the main block over it (the bathroom's and the sewing room's windows),
## her grass, her clothes line, her board fence and its gate, open.
static func _bea(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var wall := Houses.wall("brick_3")
	var trim := Color(0.94, 0.93, 0.87)
	var bo := {"trim": trim, "curtain": Color(0.95, 0.9, 0.8), "lintel": Color(0.82, 0.8, 0.74)}
	_block(p, n, BEA[0], BEA[1], -2.0, 6.0, 7.97, wall, Houses.SILVER)
	_block(p, n, BEA[0], BEA[1], 6.0, 9.0, 3.45, wall, Park.TAR)
	_spout(p, n, BEA[0] + 0.12, 9.0, 3.45)
	_spout(p, n, BEA[1] - 0.12, 6.0, 7.97, 3.5)
	Kit.box(n, Vector3(0.55, 1.1, 0.75), p.pt(BEA[0] + 0.5, 2.0, 7.97 + 0.55), wall)
	Kit.box(n, Vector3(0.62, 0.08, 0.82), p.pt(BEA[0] + 0.5, 2.0, 7.97 + 1.14), Park.COPING)
	Park._door(n, p.pt(93.575, 9.0), 0.0, 0.45, {"door": Color(0.88, 0.86, 0.78), "trim": Props.WOOD, "porch": true, "lit": ["k"]})
	Park._steps(n, p.pt(93.575, 9.0), 0.45, true)
	p.block(93.03, 9.0, 94.13, 9.9)
	Park._window(n, p.pt(95.45, 9.0), 0.0, 1.7, 2.47, 3.05, true, bo)
	for s: Array in [[97.7, 1.2], [99.25, 1.5], [100.8, 1.2]]:
		Park._window(n, p.pt(s[0], 9.0), 0.0, s[1], 1.05, 2.75, true, bo, true)
	for v: float in [8.125, 6.875]:
		Park._window(n, p.pt(BEA[1], v), 90.0, 1.05, 1.05, 2.75, true, bo, true)
	Park._window(n, p.pt(95.7, 6.0), 0.0, 1.1, 4.75, 5.5, true, bo.merged({"curtain": Color(0.95, 0.76, 0.84)}, true))
	Park._window(n, p.pt(99.35, 6.0), 0.0, 1.6, 4.55, 5.65, true, bo.merged({"curtain": Color(0.98, 0.9, 0.55)}, true))
	Park._window(n, p.pt(BEA[1], -0.95), 90.0, 1.1, 4.3, 5.6, true, bo)
	# Her yard: grass, the clothes line (sheets, a blue one, a pink one), the
	# board fence down both sides and along the alley (bea.gd's 1.5 m), the gate
	# swung right back. The camera looks over the alley's fence into the yard:
	# that fence and its gate, the far side's and the washing each fade while
	# they would hide him (props_street.gd's CarFade, as the street's cars do).
	_gb(p, n, BEA[0], BEA[1], 9.0, ALLEY, -0.1, 0.0, Kit.tex("stucco", 2.5, Color(0.35, 0.5, 0.25), true, Color(0.44, 0.74, 0.36)))
	var fade = Street.car_fade(p, st)
	var line := Kit.group(n)
	Backs.washing(p, line, 94.25, 101.25, 11.2, 1.9, [[99.15, 100.35, Color(0.95, 0.95, 0.92), 0.75], [97.25, 98.45, Color(0.75, 0.82, 0.95), 0.75], [95.35, 96.55, Color(0.95, 0.8, 0.85), 0.75]])
	p.block(94.25, 11.15, 101.25, 11.25)
	var boards := Color(0.52, 0.42, 0.32)
	var along := Kit.group(n)
	Backs.boards(p, along, true, ALLEY, BEA[0], 93.1, 1.5, boards)
	Backs.boards(p, along, true, ALLEY, 94.1, BEA[1], 1.5, boards)
	p.fence(st, true, ALLEY, 93.1, 94.1, [[93.1, 94.1]])          # the gateway (its fence is the two runs above)
	# (The side fences stop short of the alley's: their end posts would stand in
	# its corner posts, the tops in one plane, and the faded ones apart.)
	Backs.boards(p, n, false, BEA[0] + 0.03, 9.0, ALLEY - 0.11, 1.5, boards, 1.0)
	var far := Kit.group(n)
	Backs.boards(p, far, false, BEA[1] - 0.03, 9.0, ALLEY - 0.11, 1.5, boards, -1.0)
	var leaf := Outdoor.tex("out_boards", 1.2, boards, Color(0.96, 0.88, 0.78), false)
	_gb(p, along, 94.16, 95.08, ALLEY - 0.1, ALLEY - 0.06, 0.05, 1.45, leaf)
	for y: float in [0.3, 1.1]:
		_gb(p, along, 94.16, 95.08, ALLEY - 0.13, ALLEY - 0.1, y, y + 0.08, boards.darkened(0.2))
	for g: Node3D in [along, far, line]:
		fade.add(g)
	Outdoor.shrub(p, st, 100.9, 13.3, "a", 0.8, 30.0)


## The passage between Miss Bea's end wall and 508's row: concrete, a chain-link
## fence across each end, cans; the street's lamps beyond it.
static func _passage(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	_gb(p, n, PASSAGE[0], PASSAGE[1], -2.0, ALLEY, -0.1, 0.0, Color(0.5, 0.49, 0.47))
	p.fence(st, true, ALLEY - 0.06, PASSAGE[0] + 0.02, PASSAGE[1] - 0.02, [], 1.6, "chain")
	p.fence(st, true, -2.0, PASSAGE[0] + 0.02, PASSAGE[1] - 0.02, [], 1.6, "chain")
	Props.bin(p, st, 103.65, 12.95)
	Props.bin(p, st, 103.6, 12.3)
	Backs.bags(p, st, 102.5, 13.2, 1, 4.0)
	Kit.omni(n, p.pt(102.95, -3.6, 2.6), Color(1.0, 0.8, 0.55), 1.4, 9.0)


# -------------------------------------------------------------------- the poles

## The poles along the yards' side of the alley, the wires pole to pole and
## down to the houses; lamps on three, a transformer on two. At the west end
## the wires cross to the park's pole on the alley's other side (park.gd's).
static func _poles(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tops: Array = []
	for u: float in POLES:
		tops.append(Park.utility_pole(p, n, u, 14.25, 9.4, u == 56.0 or u == 92.0, u == 38.0 or u == 74.0 or u == 110.0))
		p.block(u - 0.15, 14.1, u + 0.15, 14.4)
	tops.append(Park.utility_pole(p, n, 128.0, 17.25))
	p.block(127.85, 17.1, 128.15, 17.4)
	for i in tops.size() - 1:
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		for k in 4:
			Park.wire(n, a[k], b[k], 0.45 if k < 3 else 0.6)
	# The drops: from the phone arm to the top of each back wall (none to 520).
	for d: Array in [[0, 26.0, BACK, 5.6], [0, 31.6, MAIN, 6.4], [0, 37.4, MAIN, 6.4], [1, 51.2, MAIN, 6.4], [1, 57.8, MAIN, 6.4], [2, 70.6, MAIN, 6.4],
			[2, 76.9, MAIN, 6.4], [3, 83.6, MAIN, 6.4], [3, 89.5, MAIN, 6.4], [3, 95.2, 6.0, 6.4], [4, 107.9, MAIN, 6.4], [4, 114.9, MAIN, 6.4]]:
		var from: Vector3 = tops[d[0]][3]
		Park.wire(n, from, p.pt(d[1], float(d[2]) + 0.08, d[3]), 0.35, Color(0.07, 0.07, 0.08), 0.01, 5)


# ------------------------------------------------------- the park's corner lot

## West of 504 the park's corner lot (park.gd's CORNER LOT): grass, the
## restroom block with its back to the alley, the path worn to the gap, the bed
## beyond, behind a chain-link fence along the alley broken open (E at the gap
## goes through: park.gd's TO THE ALLEY is on its far side); then the court
## behind its own tall fence with the opening into the lot, its lights on, the
## hoop, the scoreboard. Junk dumped across the alley where the court's fence
## begins.
static func _park_end(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var lawn := Outdoor.tex("out_grass", 3.6, Color(0.24, 0.46, 0.22), Color(0.68, 0.76, 0.72))
	var grass := Outdoor.tex("out_grass", 3.0, Color(0.32, 0.62, 0.26))
	for span: Array in [[3.3, ALLEY], [-7.4, 3.3]]:
		Walk.flat(p, n, LOT + 0.05, COURT, span[0], span[1], -0.3, 0.0, lawn)
	# (All of it park.gd's corner lot, turned round: the park's (u, v) is (173 - u, 17.6 - v) here.)
	Backs.restroom(p, st, PARK_W - 43.0, 17.6 - 5.5, 180.0, true)
	var dirt := Outdoor.tex("out_dirt", 2.0, Color(0.36, 0.3, 0.22))
	Walk.flat(p, n, PARK_W - 47.3, PARK_W - 40.6, 17.6 - 9.15, 17.6 - 8.25, 0.0, 0.012, dirt)          # the path worn across it
	Walk.flat(p, n, PARK_W - 48.05, PARK_W - 47.05, 17.6 - 8.9, ALLEY + 0.5, 0.0, 0.016, dirt)          # (on over the broken kerb into the alley)
	Walk.flat(p, n, PARK_W - 48.51, PARK_W - 40.03, 17.6 - 12.72, 17.6 - 12.6, -0.01, 0.13, Color(0.7, 0.69, 0.66))   # its bed's kerb
	for s: Array in ParkPlan.LOT_SHRUBS:
		Outdoor.shrub(p, st, PARK_W - float(s[0]), 17.6 - float(s[1]), s[2], s[3], float(s[4]) + 180.0)
	Park.crate(n, p.pt(PARK_W - 46.15, 17.6 - 6.7, 0.0), 168.0, Color(0.85, 0.2, 0.18))
	Kit.cyl(n, 0.035, 0.24, p.pt(PARK_W - 45.3, 17.6 - 8.4, 0.035), Color(0.24, 0.42, 0.24), Vector3(0, 305, 90), 8)
	var cut := [PARK_W - float(ParkPlan.CUT[1]), PARK_W - float(ParkPlan.CUT[0])]
	p.fence(st, true, ALLEY, LOT, COURT, [cut], 1.8, "chain")
	Backs.torn(p, n, true, ALLEY, cut[0], cut[1], 1.8, -1.0, true, false, 55.0)
	Park.litter(n, p.pt(125.7, 12.9, 0.03), 125.0, 3)
	Park.litter(n, p.pt(128.6, 9.5, 0.03), 131.0, 3)
	p.fence(st, true, -7.4, LOT, COURT, [], 1.05, "rail", Color(0.13, 0.3, 0.22))        # its railing along the park's pavement
	# The court (park.gd's, turned round): the asphalt pad in pieces, the beds'
	# grass inside the fence, the court and its lines, the fences and the
	# concrete kerb along the alley under them, the lights at this end.
	var tar := Outdoor.tex("out_asphalt", 6.4, Color(0.22, 0.24, 0.29), Color(0.9, 0.92, 1.0))
	var u := COURT + 1.8
	while u < PARK_W - 1.8 - 0.01:
		var u1 := minf(u + 10.0, PARK_W - 1.8)
		Walk.flat(p, n, u, u1, -5.8, 4.1, -0.17, 0.03, tar)
		Walk.flat(p, n, u, u1, 4.1, ALLEY, -0.17, 0.03, tar)
		u = u1
	Walk.flat(p, n, COURT, COURT + 1.8, -7.4, ALLEY, -0.3, 0.0, grass)
	# The bed's kerb, and the concrete path through it from the opening in the fence.
	var way := [17.6 - float(ParkPlan.OPENING[1]), 17.6 - float(ParkPlan.OPENING[0])]
	_gb(p, n, COURT + 1.81, COURT + 1.93, -5.79, way[0], -0.01, 0.13, Color(0.7, 0.69, 0.66))
	_gb(p, n, COURT + 1.81, COURT + 1.93, way[1], ALLEY - 0.01, -0.01, 0.13, Color(0.7, 0.69, 0.66))
	_gb(p, n, PARK_W - 40.6, COURT + 1.79, way[0], way[1], -0.165, 0.035, Outdoor.pavement())
	var green := Color(0.2, 0.52, 0.4)
	var blue := Color(0.18, 0.36, 0.66)
	Park.court(p, st, 139.0, -4.4, 167.0, 10.6, Outdoor.tex("out_court", 9.6, green, green), Outdoor.tex("out_court", 9.6, blue, blue))
	Park.hoop(p, st, 138.1, 3.1, 90.0)
	p.fence(st, true, ALLEY, COURT, PARK_W, [], 3.6, "chain")
	p.fence(st, false, COURT, -5.0, way[0], [], 3.6, "chain")         # (two runs, not a gap: no one walks in there from here)
	p.fence(st, false, COURT, way[1], ALLEY, [], 3.6, "chain")
	p.fence(st, false, COURT, -7.4, -5.0, [], 1.05, "rail", Color(0.13, 0.3, 0.22))
	var mid: float = (way[0] + way[1]) * 0.5                 # over the opening, a rail and chain-link (park.gd's)
	for y: float in [2.2, 3.57]:
		Kit.cyl(n, 0.024, way[1] - way[0], p.pt(COURT, mid, y), Color(0.55, 0.58, 0.6), Vector3(90, 0, 0), 8)
	var header := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(way[1] - way[0] - 0.04, 3.53 - 2.24)
	header.mesh = q
	header.material_override = Outdoor.chain_link()
	header.position = p.pt(COURT, mid, (2.24 + 3.53) * 0.5)
	header.rotation_degrees = Vector3(0, 90, 0)
	n.add_child(header)
	for run: Array in [[LOT, PARK_W - 48.04], [PARK_W - 47.06, COURT + 0.01]]:      # (broken out where the path crosses; its end a centimetre past the lawn's)
		_gb(p, n, run[0], run[1], ALLEY - 0.15, ALLEY + 0.15, -0.08, 0.08, Color(0.6, 0.6, 0.58))
	_gb(p, n, COURT, PARK_W, ALLEY - 0.15, ALLEY + 0.15, -0.08, 0.08, Color(0.6, 0.6, 0.58))
	Park.floodlight(p, st, 135.6, 13.45, 180.0, 7.6, 2, 12.0, 6.5, true, Vector2(140.8, 6.0), 30.0)
	Park.floodlight(p, st, 147.5, 13.45, 180.0, 7.6, 2, 12.0, 6.5, true, Vector2(148.0, 5.8), 30.0)
	Park.scoreboard(p, st, 140.6, ALLEY - 0.09, 180.0)
	Park.barrel(p, st, 138.4, 13.25, Color(0.12, 0.42, 0.62), "PARKS")
	Park.park_bench(p, st, 135.45, 6.6, 90.0)
	var low := ["a", "d", "c", "a", "d", "c"]
	var vs := [10.9, 6.4, 3.1, 0.2, -2.7, -5.2]
	for i in vs.size():
		var k: String = low[i]
		Outdoor.shrub(p, st, 133.9, vs[i], k, 0.7 + 0.15 * Props.rnd(17.6 - vs[i]), 270.0 if k == "c" else 55.0 * (i + 6) + 180.0)
	Outdoor.shrub(p, st, 133.9, 12.4, "b", 0.95, 190.0)
	# Dumped where the alley meets the court's fence: a mattress, a couch on its
	# end, tyres, bags; the city's sign over them, wired to the court's fence
	# (park.gd's words; on a pole of its own by the alley's end, it stood between
	# the camera and him).
	Alley.mattress(p, st, 134.3, 15.1, 80.0, 18.0)
	Props.couch(p, st, 135.6, 16.6, 200.0, 1.9, Color(0.38, 0.42, 0.3))
	Alley.tyres(p, st, 136.6, 14.9, 3, true)
	Backs.bags(p, st, 134.9, 16.9, 2, 5.0)
	Backs.bags(p, st, 134.6, 16.0, 1, 7.0)
	Backs.bags(p, st, 137.3, 16.2, 2, 6.0)
	var sign_board := Kit.group(n, p.pt(134.2, ALLEY + 0.04, 2.0), Vector3(0, 0, -3))         # (between the fence's end post and the next)
	Kit.box(sign_board, Vector3(0.6, 0.4, 0.02), Vector3.ZERO, Color(0.92, 0.9, 0.84))
	Props.words(sign_board, "NO DUMPING", Vector3(0, 0, 0.015), 0.09, Color(0.75, 0.12, 0.1))


# ---------------------------------------------------------- beyond the row

## What shows through the gaps (the passage, the park's lot and its court):
## Rose Hill Terrace in front of the row, the park's own pavement and road past
## the lot (park.gd's: further from the houses), the houses across the street,
## and trees in their yards over the roofs.
static func _beyond(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tar := Walk.asphalt()
	var pave := Outdoor.pavement()
	var u := 96.0
	while u < WEST - 0.01:
		var u1 := minf(u + 12.0, WEST)
		if u < LOT and u1 > LOT:
			u1 = LOT
		if u1 <= LOT + 0.01:              # Rose Hill (street.gd's): its pavement and road
			Walk.flat(p, n, u, u1, -6.25, -2.0, -0.3, 0.0, pave)
			Walk.flat(p, n, u, u1, -6.4, -6.25, -0.3, 0.02, Outdoor.KERB)
			Walk.flat(p, n, u, u1, -15.9, -6.4, -0.36, -0.06, tar)
			Walk.flat(p, n, u, u1, -16.05, -15.9, -0.3, 0.02, Outdoor.KERB)
			Walk.flat(p, n, u, u1, -18.45, -16.05, -0.3, 0.0, pave)
		else:                             # the park's
			Walk.flat(p, n, u, u1, -9.9, -7.4, -0.3, 0.0, pave)
			Walk.flat(p, n, u, u1, -10.1, -9.9, -0.3, 0.02, Outdoor.KERB)
			Walk.flat(p, n, u, u1, -17.1, -10.1, -0.36, -0.06, tar)
			Walk.flat(p, n, u, u1, -18.45, -17.1, -0.3, 0.0, pave)
		u = u1
	p.fence(st, true, -7.4, COURT, 152.2, [], 1.05, "rail", Color(0.13, 0.3, 0.22))
	p.fence(st, true, -7.4, 153.8, PARK_W, [], 1.05, "rail", Color(0.13, 0.3, 0.22))
	Street.cobra_lamp(p, st, 124.54, -5.75, 180.0)
	# Across the street: plain fronts facing the row, lit here and there.
	var walls := [StreetPlan._brick(Color(0.82, 0.76, 0.78)), StreetPlan._formstone(), StreetPlan._brick(Color(0.95, 0.88, 0.86)), Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.8, 0.78, 0.98)), StreetPlan._brick(Color(0.72, 0.64, 0.7))]
	var trims := [Street.WHITE, Street.CREAM, Street.BROWN, Street.WHITE, Street.GREEN]
	var doors: Array = Street.DOORS.values()
	var lits := ["0101", "1001", "0010", "1100", "0110", "1010", "0001", "0100"]
	u = 96.0
	var i := 0
	while u + 5.0 <= WEST:
		Houses.plain_house(Street.face(p, st, u, -18.45, 0.0), 5.0, 8.2 + 0.3 * float(i % 3), walls[(i * 3) % walls.size()], trims[i % trims.size()], doors[i % doors.size()], lits[i % lits.size()], 2, i % 2 == 0)
		u += 5.0
		i += 1
	# Trees in the yards behind them, over the roofs.
	var kinds := ["a", "b", "d", "a", "b", "d", "a"]
	u = 24.0
	i = 0
	while u < WEST:
		Outdoor.tree(p, st, u + 3.0 * Props.rnd(u), -27.0 - 2.0 * Props.rnd(u * 1.7), kinds[i % kinds.size()], 0.95 + 0.25 * Props.rnd(u * 2.3), 37.0 * i)
		u += 9.0 + 6.0 * Props.rnd(u * 3.1)
		i += 1


# ------------------------------------------------------------------- the sky

## Dusk, as over Rose Hill: the sun gone down behind the camera's right
## shoulder, the sky that way still orange and purple overhead; the low warm
## light from where it went, the sky's own cool light from above.
static func _sky(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.22, Color(0.56, 0.6, 1.0))
	var glow := Outdoor.moonlight(n, 0.32, Color(1.0, 0.6, 0.42))
	glow.rotation_degrees = Vector3(-14, 64, 0)
	Outdoor.backdrop(n, p.pt(75.0, -40.0), [Color(1.0, 0.62, 0.3), Color(0.93, 0.4, 0.42), Color(0.34, 0.22, 0.5)], Vector3.INF, 7.0, 900.0, Vector2(1.0, -0.05))


# ------------------------------------------------------------------ the people

## Two round the fire in the dead yard (one to talk to), the man with the car
## under the tarp, a neighbour at her open gate. (Names are placeholders.)
static func _people(p: Node3D, st: int) -> void:
	p.person(st, "kesha", 62.0, 11.6, {"name": "KESHA", "face": "neutral", "talk": "talk_backs_yard.json"})
	p.person(st, "vic", 64.6, 11.7, {"name": "VIC", "face": "suspicious"})
	p.person(st, "ronnie", 59.3, 13.25, {"name": "RONNIE", "face": "neutral", "talk": "talk_backs_car.json"})
	p.person(st, "nia", 43.72, 14.5, {"name": "NIA", "face": "happy", "talk": "talk_backs_gate.json"})
