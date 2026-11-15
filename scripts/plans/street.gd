extends RefCounted
## Rose Hill Terrace: a street to walk down, and where the homes are. A short
## copy of the old Pen Lucy's Rose Hill Terrace, the side street that runs one
## long block (166 m) west from Old York Road to Greenmount Avenue. This is its
## east end: about 100 m of the north side, 504 to 532, from where the row
## ends at Pen Lucy Park up to the corner of Old York Road. Two-storey
## rowhouses about 6.4 m wide, mirrored in pairs so the doors and the steps
## come two together, each with an open porch on a solid grey deck, four steps
## down to a paved strip, and the street's own mark: a three-sided sash bay
## upstairs standing on the porch roof. The road is 9.5 m kerb to kerb,
## two-way, parked along the north kerb only.
##
## Two of the houses are homes he can go into, their fronts drawn by their own
## plans so that outside and inside agree: 532 at the corner, a stoop front
## with no porch, is his (plans/crib.gd); 510, the left end of the row (a
## passage between it and 508's row), the widest house on the street, a picket
## fence round a little front yard, is Miss Bea's (plans/bea.gd). E at the foot
## of his steps or of hers goes in; leaving by the front door brings him out
## there again.
##
## One band, all out of doors, so nothing is ever hidden. One room:
##
##   ROSE HILL TERRACE   the paved strips in front of the porches, Miss Bea's
##                       yard, the north pavement, the road, the corner, and
##                       Old York Road from 10 m up it across to a step onto its
##                       far pavement, and its near pavement on up to the alley's
##                       mouth behind 532 (E there goes into the backs,
##                       plans/backs.gd). The cars, poles, lamps, steps and the
##                       rest stand in it. West of the row only the pavement and
##                       the road, along the park's railing: at its end E goes
##                       on to the park (plans/park.gd).
##
## The camera stands on the near (south) side looking across, so only the far
## side is built; the near pavement is bare. Only the two homes have insides;
## the other doors do not open.
##
## Copied from the old game (pen_lucy_level.json, kits.py and the measured
## street): the house numbers, widths and heights, each house's wall, trim and
## door colours, which side its door is on, its bay's cladding, its lintels and
## chimney; the 0.7 m floor, the porch and stoop sizes; the 2.0 m paved strip,
## the 2.4 m pavement, the 9.5 m road and its worn yellow dash pairs every 12 m;
## the utility poles (north side, 29 m apart, the wires at 9.2 m) and the cobra
## lamps (42 m apart); the parked cars (8 m apart, facing west) in the old
## game's paints. No street trees, no fences in front, no corner shop.
##
## Where it departs: the kerb is a 6 cm step, not 15 cm (he walks on one flat
## floor); the second street lamp stands on the north pavement (the real one is
## across the street, on the camera's side); the stop sign is on the corner post
## facing the eastbound lane (the real one stands on the south corner); the
## trash cans, the lit windows, curtains, blinds, painted screens, porch chairs,
## ferns and pots, the mural on 532's end wall, the mailbox, the hydrant, the
## bus stop and its bench, and Old York Road (its width, houses and lamp) are
## the pop-up's own; the trees are only behind the houses, crowns over the roofs.
## So are the homes' two fronts (510 is 9 m wide, not 6.54; 532 5 m, not 4.9),
## the 2.4 m passage between 508 and 510 (0.7 m in the old game: 508's row is
## moved 4.16 m left), 504 and 506 (the row run on to the park) and the park
## at the street's west end.
## The old game's two residents here (Pearl Sutton, mid-block on the north
## pavement; Camille Porter across from her) are not added.
##
## Invented words (placeholders): "BUS STOP", "MAIL", and the use points'
## "HOME", "MISS BEA'S", "TO THE PARK", "TO THE ALLEY". "STOP" is the road sign. The house
## numbers are the old game's.
##
## Numbers are metres on the plan (see place.gd): u from the left end of 516,
## v from behind the houses. The fronts are on v = 10, the porches run to 12,
## the paved strip to 14, the pavement to 16.4, the road 16.4 to 25.9.

const Props := preload("res://scripts/props.gd")
const Street := preload("res://scripts/props_street.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Walk := preload("res://scripts/sidewalk.gd")
const Houses := preload("res://scripts/houses.gd")
const Park := preload("res://scripts/props_park.gd")
const Backs := preload("res://scripts/props_backs.gd")
const CribPlan := preload("res://scripts/plans/crib.gd")
const BeaPlan := preload("res://scripts/plans/bea.gd")

const NAME := "ROSE HILL TERRACE"
const SIGN := "ROSE HILL TER"

const D := 10.0           # the house fronts
const STRIP := 12.0       # the porch fronts; the paved strip to 14
const PAVE := 14.0        # the pavement, 14 to 16.4
const KERB := 16.25       # the kerb stone
const ROAD := 16.4        # the road: Rose Hill's 9.5 m
const FAR := 25.9
const MID := 21.15        # the middle of the road
const NEAR := 28.45       # the back of the near pavement
const CORNER := 56.68     # 532's end wall; Old York Road's pavement beyond it
const OY0 := 59.08        # Old York Road, kerb to kerb
const OY1 := 68.58
const OYE := 70.98        # the back of Old York's far pavement
const EAST := 72.9        # the fronts across Old York Road
const LEFT := -80.0       # how far the street is drawn to the left
const ROW_END := -44.46   # 504's end wall, the west end of the row; the park beyond
const WEST := -48.0       # how far he may walk: the end of the park's railing, the way on to the park
const PASSAGE := [-24.15, -21.75]       # between 508's row and Miss Bea's end wall
const BACK := -60.0       # and up Old York Road (the yards behind the row)
const NORTH := -170.0     # how far Old York Road itself runs on up, into the dusk
const FRONT := 40.0       # and down it
## The party walls (and the ends of the rows), where the pavement has its expansion joints.
const WALLS := [-44.46, -38.06, -31.66, -24.15, -21.75, -12.75, -6.38, 0.0, 6.33, 12.86, 19.24, 25.64, 32.02, 38.53, 45.0, 51.68]
## What each house has between its steps and the pavement, 504 to 532 (sidewalk.gd's front()); 510's is her yard.
const FRONTS := ["a", "brick", "old", "yard", "brick", "a", "yard", "paint", "a", "old", "new", "yard", "brick", "new", "a"]


static func build(p: Node3D) -> void:
	p.setup(NAME, 60.0, D)
	var st: int = p.band()
	p.arrive = p.pt(53.4, 15.0)
	# Dusk: the light going, the street lamps and the porch lights on. main.gd's
	# sun is off; _sky hangs the last of the sun and the sky's own light.
	p.ambient = 0.16
	p.sun_energy = 0.0
	var right := OY1 + 1.0                                  # a step onto Old York's far pavement
	# The camera stands back and low enough to see the cornices over him from
	# the pavement; the parked cars it looks across fade while they are in the way.
	var street: int = p.room(NAME, st, WEST, 2.0, right, FAR, null, {
		"street": true,
		"areas": [[ROW_END, STRIP, right, FAR], [WEST, PAVE, ROW_END + 2.0, FAR], [51.68, D, CORNER, PAVE], [CORNER, 2.0, right, PAVE], [CORNER, -7.5, OY0 - 0.15, 3.0]],
		"cam_near": 1.9, "cam_y": 3.4, "look_y": 3.0})
	p.rooms[street]["cam_max_x"] = p.pt(EAST - 2.6, 0.0).x  # never up against the houses across Old York Road
	Walk.begin()                    # the ground's thousands of pieces, gathered into a few meshes
	_ground(p, st)
	var homes := _row(p, st)
	_park_end(p, st)
	Walk.end()
	_kerbside(p, st)
	_corner(p, st)
	_context(p, st)
	_sky(p, st)
	# The homes' doors (E at the foot of the steps goes in: main.gd's "goto:"),
	# and the way on to the park at the west end.
	p.use_point(st, "HOME", homes["crib"]["door"], homes["crib"]["steps"] + 0.35, "goto:crib", 0.9, 2.4)
	p.use_point(st, "MISS BEA'S", homes["bea"]["door"], homes["bea"]["steps"] + 0.4, "goto:bea", 0.9, 2.4)
	p.use_point(st, "TO THE PARK", WEST + 0.75, PAVE + 1.2, "goto:park", 1.2, 1.9)
	p.use_point(st, "TO THE ALLEY", 57.88, -5.75, "goto:backs", 1.2, 1.9)      # the alley's mouth up Old York Road (plans/backs.gd)


## A box on the plan: u0..u1, v0..v1, y0..y1.
static func _gb(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look)


static func _brick(tint: Color) -> Material:
	return Kit.tex("brick", 1.5, Color(0.54, 0.29, 0.23), true, tint)


## Formstone, the stone-look render on half of Baltimore's rowhouse fronts.
static func _formstone() -> Material:
	return Outdoor.tex("out_formstone", 2.0, Color(0.6, 0.59, 0.55), Color(1.0, 1.0, 1.0))


## A box on the plan cut into pieces about `step` long along its longer side:
## the renderer lights any one thing with eight lamps at most, and a box the
## length of the street is near every porch light and street lamp at once.
static func _gb_run(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant, step := 10.0) -> void:
	var along_u := u1 - u0 >= v1 - v0
	var a0 := u0 if along_u else v0
	var a1 := u1 if along_u else v1
	var k := maxi(1, ceili((a1 - a0) / step))
	for i in k:
		var s0 := a0 + (a1 - a0) * float(i) / k
		var s1 := a0 + (a1 - a0) * float(i + 1) / k
		if along_u:
			_gb(p, n, s0, s1, v0, v1, y0, y1, look)
		else:
			_gb(p, n, u0, u1, s0, s1, y0, y1, look)


# ------------------------------------------------------------------ ground

static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var paved := Outdoor.tex("out_paving", 3.2, Color(0.6, 0.58, 0.55), Color(0.86, 0.85, 0.83))
	var tar := Walk.asphalt()                                   # Rose Hill's and Old York's, worn grey
	var alley := Outdoor.tex("out_asphalt", 4.8, Color(0.3, 0.3, 0.32))
	var dirt := Color(0.28, 0.25, 0.21)
	_gb(p, n, LEFT - 120.0, 120.0, NORTH - 20.0, FRONT + 10.0, -0.8, -0.5, Color(0.12, 0.13, 0.12))
	# Behind the row: the back yards, the alley, the next street's yards.
	_gb(p, n, LEFT, CORNER, BACK, D, -0.3, -0.02, dirt)
	_gb_run(p, n, LEFT, CORNER - 0.02, -7.5, -4.0, -0.3, -0.01, alley)
	# Under the pavements' slabs and kerbs: the dirt that shows down the joints.
	# (Its top under the ramps' feet and the tree pits' dirt; a centimetre short
	# of the kerbs' faces, so that no two faces lie in one plane.)
	_gb_run(p, n, LEFT, OY0 - 0.01, D, ROAD - 0.01, -0.31, -0.06, Walk.JOINT)
	_gb_run(p, n, CORNER, OY0 - 0.01, NORTH, D, -0.31, -0.06, Walk.JOINT, 20.0)
	_gb_run(p, n, LEFT, OY0 - 0.01, FAR, NEAR, -0.31, -0.06, Walk.JOINT)
	_gb_run(p, n, CORNER, OY0 - 0.01, NEAR, FRONT, -0.31, -0.06, Walk.JOINT)
	_gb_run(p, n, OY1, OYE, NORTH, FRONT, -0.31, -0.06, Walk.JOINT, 20.0)
	# The pavement (sidewalk.gd): concrete slabs one across, square to the kerb,
	# an expansion joint at every party wall (the porches' strips are _row's).
	# Under the lamps gum, by the cans grease; tree pits long empty, a root's
	# heave beside one; in front of 524 a run of slabs relaid every which way.
	Walk.run(p, n, true, LEFT, CORNER, PAVE, KERB, WALLS, {
		-76.0: "old", -70.0: "crack", -63.0: "patch", -57.0: "stain", -51.0: "old", -46.5: "gum", -42.0: "crack",
		-36.5: "stain", -34.0: "new", -30.5: "old", -24.0: "patch", -21.0: "crack", -19.6: "dirty", -18.4: "old", -15.0: "pit", -13.6: "heave",
		-11.9: "stain", -10.4: "new", -8.5: "crack", -5.5: "old", -2.4: "gum", 2.4: "crack", 10.4: "stain",
		14.6: "pit", 16.8: "heave", 18.4: "crack", 21.6: "old", 23.2: "stain", 26.4: "new", 28.0: "patch",
		29.6: "brick", 31.2: "half", 34.5: "pit", 36.2: "lift", 37.7: "split", 39.3: "gum", 42.5: "stain",
		44.2: "warm", 45.8: "new", 47.5: "new", 49.2: "sunk", 52.6: "old", 54.2: "crack"}, 3.0)
	# A black line where the houses' strips meet the city's pavement.
	_gb_run(p, n, LEFT, CORNER, PAVE - 0.007, PAVE + 0.007, -0.3, -0.006, Walk.FILL)
	# Old York Road's pavements, on up past 532 and the alley's mouth (its
	# kerb laid low for the cars), and the near ones across Rose Hill (bare).
	var oy_walls: Array = [10.0, 1.0, -4.0, -7.5]
	var w := -12.0
	while w > NORTH:
		oy_walls.append(w)
		w -= 4.5 if w > -44.0 else 4.6
	Walk.run(p, n, false, NORTH, PAVE, CORNER, OY0 - 0.15, oy_walls, {
		12.0: "old", 5.0: "gum", 1.5: "stain", -1.5: "crack", -4.9: "drive", -6.6: "drive", -14.0: "heave",
		-20.5: "split", -26.0: "new", -33.0: "patch", -47.0: "crack", -60.0: "old"}, 5.0)
	Walk.run(p, n, true, LEFT, CORNER, FAR + 0.15, NEAR, WALLS, {-5.0: "patch", 10.0: "crack", 30.0: "new", 47.0: "old"}, 7.0, -1)
	Walk.run(p, n, false, NEAR, FRONT, CORNER, OY0 - 0.15, [33.0], {31.0: "crack"}, 9.0)
	Walk.run(p, n, false, NORTH, PAVE, OY1 + 0.15, OYE, oy_walls, {2.0: "crack", -9.0: "new"}, 11.0, -1)
	Walk.run(p, n, false, PAVE + 1.2, FRONT, OY1 + 0.15, OYE, [], {20.0: "stain"}, 12.0, -1)
	Walk.slab(p, n, false, PAVE + Walk.GAP * 0.5, PAVE + 1.2 - Walk.GAP * 0.5, OY1 + 1.25 + Walk.GAP, OYE - Walk.GAP * 0.5, "old", 13.0, -1)
	_gb_run(p, n, OYE, EAST + 12.0, NORTH, FRONT, -0.3, 0.0, paved, 20.0)
	# Granite kerbs in stones, a storm drain's mouth in the north one; concrete gutters.
	Walk.kerb(p, n, true, LEFT, CORNER, KERB, ROAD, [[52.4, 53.3, "inlet"]], 1.0)
	Walk.kerb(p, n, false, NORTH, PAVE, OY0 - 0.15, OY0, [[-7.5, -4.0, "drop"]], 2.0)
	Walk.kerb(p, n, true, LEFT, CORNER, FAR, FAR + 0.15, [], 3.0, -1)
	Walk.kerb(p, n, false, FAR + 0.15, FRONT, OY0 - 0.15, OY0, [], 4.0)
	Walk.kerb(p, n, false, NORTH, FRONT, OY1, OY1 + 0.15, [[14.0, 15.2, "gap"]], 5.0, -1)
	Walk.gutter(p, n, true, LEFT, OY0, ROAD, ROAD + 0.45, 1.0)
	Walk.gutter(p, n, true, LEFT, OY0, FAR, FAR - 0.45, 2.0)
	Walk.gutter(p, n, false, NORTH, ROAD + 0.45, OY0, OY0 + 0.45, 3.0)
	Walk.gutter(p, n, false, FAR - 0.45, FRONT, OY0, OY0 + 0.45, 4.0)
	Walk.gutter(p, n, false, NORTH, FRONT, OY1, OY1 - 0.45, 5.0)
	Walk.drain(p, n, 52.45, 53.25, ROAD + 0.01, ROAD + 0.4)
	_corners(p, n)
	# The roads: worn asphalt, dug up and patched, cracks sealed with tar.
	_gb_run(p, n, LEFT, OY0, ROAD, FAR, -0.36, -0.06, tar)
	_gb_run(p, n, OY0, OY1, NORTH, FRONT, -0.36, -0.06, tar)
	for at: Array in [[27.6, 28.3, ROAD + 0.5, 20.6], [33.0, 35.2, 22.2, 23.8], [44.0, 55.2, 23.4, 24.2], [4.0, 5.4, 18.0, 19.1], [-14.0, -9.5, 23.9, 25.0], [60.5, 62.5, 4.0, 6.0], [64.4, 67.9, -22.0, -19.5]]:
		Walk.patch(p, n, at[0], at[1], at[2], at[3])
	# The seam where the asphalt meets the gutter, sealed: straight, a little ragged.
	var seam: Array = []
	var su := LEFT
	while true:
		seam.append(Vector2(su, ROAD + 0.47 + (Props.rnd(su * 1.3) - 0.5) * 0.016))
		if su >= OY0 + 0.47:
			break
		su = minf(su + 2.3, OY0 + 0.47)
	Walk.tar_line(p, n, seam, 0.03, 0.0)
	# Sealed cracks, all out in the lanes (none under the parked cars): down the
	# joint just off the middle where the two passes of the paver met, down the
	# far lane's wheel track, and a few short ones across.
	Walk.tar_line(p, n, Walk.wander(Vector2(-14.5, 21.8), 0.0, 6, 1.5, 2.0, 6.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(19.0, 21.8), 0.0, 7, 1.4, 3.0, 6.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(-6.0, 24.2), 0.0, 8, 1.3, 4.0, 8.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(-66.0, 21.8), 0.0, 9, 1.5, 9.0, 6.0))
	for at: Vector3 in [Vector3(9.5, 18.9, 91.0), Vector3(37.4, 19.3, 93.0), Vector3(-18.0, 19.2, 88.0)]:
		Walk.tar_line(p, n, Walk.wander(Vector2(at.x, at.y), at.z, 4, 1.15, at.x, 10.0))
	# Up Old York Road, two lengths down its east lane and one in the west, one across.
	Walk.tar_line(p, n, Walk.wander(Vector2(66.3, -58.0), 90.0, 14, 1.6, 5.0, 8.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(61.0, -12.0), 90.0, 7, 1.5, 7.0, 8.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(64.3, -6.5), 0.0, 3, 0.95, 8.0, 10.0))
	Walk.tar_line(p, n, Walk.wander(Vector2(61.0, 21.0), 95.0, 6, 1.5, 6.0))
	# Oil where cars stand, in the gaps between those parked now.
	for at: Vector3 in [Vector3(41.6, 17.5, 20.0), Vector3(33.2, 17.4, -10.0), Vector3(25.5, 17.6, 35.0), Vector3(9.4, 17.45, 0.0), Vector3(1.2, 17.55, -25.0), Vector3(17.8, 17.5, 60.0)]:
		Walk.oil(p, n, at.x, at.y, 0.9, 0.55, at.z)
	# Rose Hill's paint: pairs of yellow dashes every 12 m down the middle, worn
	# to pieces; no lines along it. Old York Road's double yellow line stops
	# either side of the crosswalk at the corner.
	var yellow := Walk.YELLOW
	var u := 3.0 - 144.0
	while u < OY0 - 2.0:
		for v: float in [MID - 0.15, MID + 0.15]:
			Walk.paint(p, n, u - 0.6, u + 0.6, v - 0.09, v + 0.09, yellow, u + v, 0.3)
		u += 12.0
	for c: float in [63.71, 63.95]:
		for span: Array in [[NORTH, 13.0], [16.2, FRONT]]:
			Walk.paint(p, n, c - 0.05, c + 0.05, span[0], span[1], Color(0.86, 0.72, 0.24), c + float(span[0]), 0.06, 3.0)
	for at: Vector2 in [Vector2(17.0, 22.4), Vector2(41.5, 19.6), Vector2(62.6, 8.5), Vector2(63.0, -30.0)]:
		Walk.manhole(p, n, at.x, at.y)


## The corner of Old York Road: a kerb cut each way across the road from the
## corner (a ramp down through the kerb, a red pad of dots at its foot), the
## crosswalks between them, faded, and the stop line; the near corner's ramp.
static func _corners(p: Node3D, n: Node3D) -> void:
	var r0 := CORNER                 # the ramp across Rose Hill, in line with Old York's pavement
	var r1 := CORNER + 1.2
	var q0 := PAVE                   # the ramp across Old York, in line with Rose Hill's
	var q1 := PAVE + 1.2
	Walk.ramp(p, n, true, r0, r1, q1 + Walk.GAP * 0.5, ROAD)
	Walk.ramp(p, n, false, q0 + Walk.GAP * 0.5, q1 - Walk.GAP * 0.5, r1 + Walk.GAP, OY0)
	Walk.slab(p, n, true, r0 + Walk.GAP * 0.5, r1 - Walk.GAP * 0.5, q0 + Walk.GAP * 0.5, q1 - Walk.GAP * 0.5, "a", 1.0)
	Walk.slab(p, n, true, r1 + Walk.GAP * 0.5, OY0 - 0.15 - Walk.GAP * 0.5, q1 + Walk.GAP * 0.5, KERB - Walk.GAP * 0.5, "b", 2.0)
	# The corner stone between the two ramps.
	Walk.piece(p, n, true, r1 + Walk.GAP * 0.5, OY0, KERB, ROAD, -0.3, Walk.KERB_TOP, Walk.look("out_granite", 1.0, Color.WHITE, Walk.GRANITE[1]))
	Walk.piece(p, n, false, q1 + Walk.GAP * 0.5, KERB, OY0 - 0.15, OY0, -0.3, Walk.KERB_TOP, Walk.look("out_granite", 1.0, Color.WHITE, Walk.GRANITE[2]))
	# Across the road on Rose Hill's near side, and on Old York's far side.
	Walk.ramp(p, n, true, r0, r1, FAR + 1.2, FAR)
	Walk.slab(p, n, true, r0 + Walk.GAP * 0.5, r1 - Walk.GAP * 0.5, FAR + 1.2 + Walk.GAP, NEAR - Walk.GAP * 0.5, "a", 3.0, -1)
	Walk.slab(p, n, true, r1 + Walk.GAP * 0.5, OY0 - 0.15 - Walk.GAP * 0.5, FAR + 0.15 + Walk.GAP * 0.5, NEAR - Walk.GAP * 0.5, "old", 4.0, -1)
	Walk.piece(p, n, true, r1 + Walk.GAP * 0.5, OY0, FAR, FAR + 0.15, -0.3, Walk.KERB_TOP, Walk.look("out_granite", 1.0, Color.WHITE, Walk.GRANITE[0]))
	Walk.ramp(p, n, false, q0 + Walk.GAP * 0.5, q1 - Walk.GAP * 0.5, OY1 + 1.25, OY1)
	# The crosswalks, ladders of wide white bars: the bars the wheels run over
	# worn to pieces and grey, the rest whole. The stop line.
	var white := Walk.WHITE_PAINT.darkened(0.12)
	var v := ROAD + 0.75
	var k := 0
	while v < FAR - 0.85:
		var worn := _near(v + 0.2, [19.2, 20.8, 22.7, 24.3]) < 0.45     # Rose Hill's wheel tracks, each way
		Walk.paint(p, n, r0 + 0.6 - 1.2, r1 - 0.6 + 1.2, v, v + 0.4, white, 10.0 + k, 0.4 if worn else 0.03, 0.3, 0.14 if worn else 0.03)
		v += 0.9
		k += 1
	var u := OY0 + 0.75
	while u < OY1 - 0.85:
		var worn := _near(u + 0.2, [60.6, 62.2, 65.4, 67.0]) < 0.45     # Old York's
		Walk.paint(p, n, u, u + 0.4, q0 + 0.6 - 1.2, q1 - 0.6 + 1.2, white, 30.0 + k, 0.4 if worn else 0.03, 0.3, 0.14 if worn else 0.03)
		u += 0.9
		k += 1
	Walk.paint(p, n, CORNER - 1.3, CORNER - 0.95, MID + 0.1, FAR - 0.5, white, 50.0, 0.25, 0.3, 0.1)


## How far `x` is from the nearest of `marks`.
static func _near(x: float, marks: Array) -> float:
	var best := INF
	for m: float in marks:
		best = minf(best, absf(x - m))
	return best


# -------------------------------------------------------------------- the row

## The north side of Rose Hill Terrace as the old game builds it: 510 to 532
## are one row, and 508's the next, across a passage. Each house's width,
## height, wall, trim and door colours, which side its door is on, the bay's
## cladding, the lintels and the chimney are the old game's (kits.py style(),
## seeded by its map id); the lit windows, curtains and porch things are the
## pop-up's, and so are 504 and 506, the row run on to the park. 510 and 532 are
## the homes, drawn by their own plans (`front`). Returns where the homes'
## doors and the feet of their steps are: {"crib": {...}, "bea": {...}}.
static func _row(p: Node3D, st: int) -> Dictionary:
	var formstone := _formstone()
	var tan := Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.8, 0.78, 0.98))
	var stone := Color(0.72, 0.71, 0.68)          # the formstone lintels
	var dc: Dictionary = Street.DOORS
	var houses := [
		[-44.46, 6.4, {"no": "504", "wall": _brick(Color(0.9, 0.86, 0.9)), "trim": Street.WHITE, "door": dc["blue"], "door_left": true, "bay": "white", "lintel": stone, "height": 8.3, "chimney": true, "lit": "01001", "curtain": Color(0.95, 0.93, 0.86), "porch_light": true}],
		[-38.06, 6.4, {"no": "506", "wall": tan, "trim": Street.BROWN, "door": dc["wood"], "door_left": false, "bay": "cream", "height": 8.36, "lit": "10010", "curtain": Color(0.85, 0.3, 0.3), "chairs": true}],
		[-31.66, 7.51, {"no": "508", "wall": formstone, "trim": Street.WHITE, "door": dc["white"], "door_left": true, "bay": "white", "height": 8.43, "chimney": true, "lit": "10100", "curtain": Color(0.9, 0.7, 0.2)}],
		[PASSAGE[1], BeaPlan.W, {"no": "510", "home": "bea"}],
		[-12.75, 6.37, {"no": "512", "wall": _brick(Color(0.86, 0.82, 0.86)), "trim": Street.BROWN, "door": dc["black"], "door_left": false, "bay": "grey", "lintel": Street.WHITE, "height": 8.15, "chimney": true, "lit": "01100", "curtain": Color(0.4, 0.65, 0.4)}],
		[-6.38, 6.38, {"no": "514", "wall": _brick(Color(0.95, 0.9, 0.92)), "trim": Street.WHITE, "door": dc["black"], "door_left": true, "bay": "white", "lintel": stone, "height": 8.01, "lit": "1t001", "curtain": Color(0.95, 0.93, 0.86), "porch_light": true, "chairs": true}],
		[0.0, 6.33, {"no": "516", "wall": _brick(Color(0.84, 0.8, 0.84)), "trim": Street.RED, "door": dc["red"], "door_left": false, "bay": "grey", "lintel": Street.WHITE, "height": 8.02, "lit": "10010", "curtain": Color(0.9, 0.6, 0.3), "screens": true}],
		[6.33, 6.53, {"no": "518", "wall": _brick(Color(0.9, 0.84, 0.84)), "trim": Street.WHITE, "door": dc["green"], "door_left": true, "bay": "grey", "lintel": Street.CREAM, "height": 7.99, "chimney": true, "lit": "00100", "curtain": Color(0.62, 0.5, 0.78), "fern": true}],
		[12.86, 6.38, {"no": "520", "wall": _brick(Color(1.0, 0.96, 0.94)), "trim": Street.WHITE, "door": dc["green"], "door_left": false, "bay": "white", "height": 7.91, "chimney": true, "lit": "11101", "curtain": Color(0.85, 0.22, 0.22), "porch_light": true, "chairs": true}],
		[19.24, 6.4, {"no": "522", "wall": formstone, "trim": Street.BROWN, "door": dc["green"], "door_left": true, "bay": "white", "height": 7.85, "lit": "01011", "curtain": Color(0.95, 0.75, 0.25), "screens": true, "fern": true}],
		[25.64, 6.38, {"no": "524", "wall": tan, "trim": Street.WHITE, "door": dc["blue"], "door_left": false, "bay": "cream", "height": 7.83, "lit": "10110", "blinds": true, "curtain": Color(0.9, 0.88, 0.78), "pots": true, "porch_light": true}],
		[32.02, 6.51, {"no": "526", "wall": _brick(Color(0.86, 0.8, 0.82)), "trim": Street.BROWN, "door": dc["red"], "door_left": true, "bay": "grey", "lintel": Street.WHITE, "height": 7.71, "chimney": true, "lit": "t1001", "curtain": Color(0.35, 0.6, 0.4), "chairs": true}],
		[38.53, 6.47, {"no": "528", "wall": _brick(Color(1.0, 0.98, 0.96)), "trim": Street.BROWN, "door": dc["blue"], "door_left": false, "bay": "white", "lintel": stone, "height": 8.0, "chimney": true, "lit": "11011", "curtain": Color(0.92, 0.5, 0.62), "screens": true, "porch_light": true, "fern": true}],
		[45.0, 6.68, {"no": "530", "wall": _brick(Color(0.9, 0.86, 0.86)), "trim": Street.CREAM, "door": dc["wood"], "door_left": true, "bay": "cream", "lintel": stone, "height": 8.41, "chimney": true, "lit": "10111", "curtain": Color(0.95, 0.93, 0.86), "pots": true, "porch_light": true}],
		[51.68, CribPlan.W, {"no": "532", "home": "crib", "porch": false}],
	]
	var n: Node3D = p.node_of(st)
	var homes := {}
	for i in houses.size():
		var row: Array = houses[i]
		var u0: float = row[0]
		var w: float = row[1]
		var h: Dictionary = row[2]
		var home: String = h.get("home", "")
		var porch: bool = h.get("porch", true)
		var door: float
		if home == "crib":
			homes[home] = CribPlan.front(p, st, u0, D)          # (its steps take up floor there)
			door = homes[home]["door"]
		elif home == "bea":
			homes[home] = BeaPlan.front(p, st, u0, D, PAVE)
			door = homes[home]["door"]
		else:
			var house: Node3D = Street.porch_house(p, st, u0, D, w, h)
			door = u0 + (0.9 if h.get("door_left", true) else w - 0.9)
			p.block(door - 0.625, STRIP, door + 0.625, STRIP + 0.9)          # the steps take up floor
			if h["no"] == "504" or h["no"] == "508":                          # the ends of 508's row: windows down them
				Houses.end_windows(house, w, 9.0, -1 if h["no"] == "504" else 1, Houses.F0, h["height"], h["trim"], w)
		# Its own strip down to the pavement (sidewalk.gd), the porch or the
		# stoop sitting on it, tar at the party wall; in the pavement its water
		# meter's lid near the kerb, its gas valve in front of the steps. (Miss
		# Bea's is her yard: bea.gd.)
		var v0 := STRIP if porch else D
		if home != "bea":
			Walk.front(p, n, u0 + Walk.WIDE * 0.5, u0 + w - Walk.WIDE * 0.5, v0, PAVE - Walk.GAP * 0.5, door, FRONTS[i], u0)
			if porch:
				Walk.footing(p, n, u0, u0 + w, STRIP, door, 1.25, 0.9)
			else:
				Walk.footing(p, n, door, door, D, door, 1.4, 1.35)
		Walk.piece(p, n, true, u0 - 0.009, u0 + 0.009, v0, PAVE - 0.007, -0.3, -0.006, Walk.FILL)
		Walk.lid(p, n, u0 + 0.8, KERB - 0.5, "water")
		Walk.lid(p, n, door, PAVE + 0.32, "gas")
	# The passage between 508's row and Miss Bea's: concrete back to the yards,
	# a chain-link gate across it in line with the porches, shut; cans inside.
	_gb(p, n, PASSAGE[0], PASSAGE[1], -4.0, STRIP, -0.3, -0.005, Color(0.5, 0.49, 0.47))
	p.fence(st, true, STRIP, PASSAGE[0] + 0.02, PASSAGE[1] - 0.02, [], 1.6, "chain")
	Walk.front(p, n, PASSAGE[0] + Walk.WIDE * 0.5, PASSAGE[1] - Walk.WIDE * 0.5, STRIP, PAVE - Walk.GAP * 0.5, (PASSAGE[0] + PASSAGE[1]) * 0.5, "dirty", 7.0)
	Props.bin(p, st, PASSAGE[0] + 0.45, STRIP - 0.8)
	Props.bin(p, st, PASSAGE[0] + 1.05, STRIP - 1.0)
	# A power company's vault by the pole, sewer cleanouts.
	Walk.lid(p, n, 21.95, KERB - 0.62, "vault")
	Walk.lid(p, n, 9.0, PAVE + 0.25, "cleanout")
	Walk.lid(p, n, 34.0, PAVE + 0.25, "cleanout")
	return homes


# ---------------------------------------------------------------- the park

## West of 504, the row's end, Pen Lucy Park (plans/park.gd) comes up to the
## pavement: its lawn behind a low wall with an iron railing on it, trees, the
## court further in behind its chain-link, a floodlight over it, and next to
## 504 the park's corner lot with the restroom block. He walks on along the
## pavement by the railing to WEST; E there goes on to the park.
static func _park_end(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var grass := Kit.tex("stucco", 2.5, Color(0.3, 0.42, 0.24), true, Color(0.42, 0.66, 0.34))
	var far := LEFT - 70.0                  # past LEFT the street runs on out of sight, plainer
	_gb(p, n, far, ROW_END - 0.05, -4.0, PAVE, -0.29, 0.0, grass)
	_gb(p, n, far, LEFT, PAVE, KERB, -0.3, 0.0, Outdoor.pavement())
	_gb(p, n, far, LEFT, KERB, ROAD, -0.3, 0.0, Outdoor.KERB)
	_gb(p, n, far, LEFT, ROAD, FAR, -0.36, -0.06, Walk.asphalt())
	_gb(p, n, far, LEFT, FAR, FAR + 0.15, -0.3, 0.0, Outdoor.KERB)
	_gb(p, n, far, LEFT, FAR + 0.15, NEAR, -0.3, 0.0, Outdoor.pavement())
	# The wall and its railing (sidewalk.gd gathers the pieces into a few meshes).
	var iron := Color(0.14, 0.15, 0.17)
	var at := PAVE - 0.3
	var end := ROW_END - 0.06                 # (on to 504's end wall, as the park has its railing)
	Walk.flat(p, n, far, end, at - 0.15, at + 0.15, 0.0, 0.32, Color(0.62, 0.6, 0.56))
	for y: float in [0.42, 1.12]:
		Walk.flat(p, n, far, end, at - 0.025, at + 0.025, y, y + 0.05, iron)
	var u := end - 0.08
	while u > far:
		Walk.flat(p, n, u - 0.013, u + 0.013, at - 0.013, at + 0.013, 0.32, 1.17, iron)
		u -= 0.16 if u > LEFT else 0.32
	u = end
	while u > far:
		Walk.flat(p, n, u - 0.04, u + 0.04, at - 0.04, at + 0.04, 0.32, 1.3, iron)
		u -= 2.4
	# The court behind its fence (the park's green, a blue key, a hoop at its
	# near end), a floodlight over it; trees on the lawn.
	var green := Color(0.2, 0.52, 0.4)
	var blue := Color(0.18, 0.36, 0.66)
	var line := Color(0.92, 0.92, 0.88)
	_gb(p, n, LEFT, -53.0, -3.5, 8.0, -0.29, 0.015, Outdoor.tex("out_court", 9.6, green, green))
	_gb(p, n, -60.2, -54.4, -0.2, 4.7, 0.015, 0.021, Outdoor.tex("out_court", 9.6, blue, blue))
	_gb(p, n, -54.45, -54.35, -2.6, 7.1, 0.015, 0.024, line)
	_gb(p, n, -60.25, -60.15, -0.25, 4.75, 0.021, 0.024, line)
	_gb(p, n, LEFT, -54.35, 7.05, 7.15, 0.015, 0.024, line)
	Park.hoop(p, st, -53.5, 2.25, 270.0)
	for run: Array in [[-4.0, 0.4], [1.8, 8.0]]:         # (two runs, not a gap: a gap is a way through, and no one walks in there from here)
		p.fence(st, false, -53.0, run[0], run[1], [], 3.6, "chain")
	p.fence(st, true, 8.0, LEFT, -53.0, [], 3.6, "chain")
	p.fence(st, false, LEFT, -4.0, 8.0, [], 3.6, "chain")
	p.fence(st, true, -4.0, LEFT, -53.0, [], 3.6, "chain")             # along the alley, the scoreboard on it (park.gd's)
	Park.scoreboard(p, st, -60.6, -3.91, 0.0)
	Park.floodlight(p, st, -55.0, 8.9, 180.0, 7.6, 2, 3.0, 4.5, false, Vector2(-59.0, 2.25))
	Outdoor.tree(p, st, -62.0, 11.6, "b", 1.15, 160.0)
	Outdoor.tree(p, st, -73.5, 10.8, "d", 1.1, 260.0)
	# Between the court and 504 the park's corner lot (plans/park.gd's: its u, v
	# are u + 93, v + 7.6 here; its bed is shorter here, the railing nearer): the
	# opening in the court's fence with the chain-link over it, the path worn from
	# it past the restroom block (shut, the lamp over one door on) to where the
	# chain-link along the alley is cut open; the bed's kerb and low shrubs. No
	# trees: the park keeps them out of the lot.
	for y: float in [2.2, 3.57]:
		Kit.cyl(n, 0.024, 1.4, p.pt(-53.0, 1.1, y), Color(0.55, 0.58, 0.6), Vector3(90, 0, 0), 8)
	var header := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.36, 3.53 - 2.24)
	header.mesh = q
	header.material_override = Outdoor.chain_link()
	header.position = p.pt(-53.0, 1.1, (2.24 + 3.53) * 0.5)
	header.rotation_degrees = Vector3(0, 90, 0)
	n.add_child(header)
	Backs.restroom(p, st, -50.0, -2.1, 0.0, true)
	var dirt := Outdoor.tex("out_dirt", 2.0, Color(0.36, 0.3, 0.22))
	_gb(p, n, -52.4, -45.7, 0.65, 1.55, 0.0, 0.012, dirt)
	_gb(p, n, -45.95, -44.95, -4.5, 1.3, 0.0, 0.016, dirt)            # (on through the cut into the alley)
	_gb(p, n, -52.97, -44.49, 5.0, 5.12, -0.01, 0.13, Color(0.7, 0.69, 0.66))
	for s: Array in [[-51.5, 7.8, "a", 1.0, 20.0], [-45.7, 6.7, "d", 0.9, 140.0], [-48.4, 10.6, "c", 0.85, 3.0]]:
		Outdoor.shrub(p, st, s[0], s[1], s[2], s[3], s[4])
	for run: Array in [[-53.0, -46.1], [-44.8, ROW_END]]:
		p.fence(st, true, -4.0, run[0], run[1], [], 1.8, "chain")
	Backs.torn(p, n, true, -4.0, -46.1, -44.8, 1.8, 1.0, true, true, 55.0)
	Props.hydrant(p, st, -49.0, ROAD - 0.45)                          # (the park's, at the lot's front)


# ---------------------------------------------------------------- kerbside

static func _kerbside(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	# The utility poles along the north kerb, 29 m apart, and their three wires.
	var poles := [50.37, 21.37, -7.63, -36.63, -65.63, -94.63, -123.63]
	for u: float in poles:
		Street.utility_pole(p, st, u, ROAD - 0.42, u == 21.37)
	var ends: Array = poles.duplicate()
	ends.append(LEFT - 70.0)
	for i in range(ends.size() - 1):
		for z: float in Street.WIRES:
			_wire(n, p.pt(ends[i], ROAD - 0.42 + z, 9.2), p.pt(ends[i + 1], ROAD - 0.42 + z, 9.2), 0.65)
	# The cobra-head lamps, 42 m apart.
	Street.cobra_lamp(p, st, 39.46, ROAD - 0.65)
	Street.cobra_lamp(p, st, -2.54, ROAD - 0.65)
	Street.cobra_lamp(p, st, -44.54, ROAD - 0.65)
	# Parked along the north kerb only, 8 m apart, facing west the way that
	# lane goes; the old game's kinds and paints in turn. The camera looks
	# across them at the pavement, so each fades while it is in the way.
	var kinds := ["box_sedan", "compact", "minivan", "midsize", "hatchback", "long_sedan"]
	var fade = Street.car_fade(p, st)
	for i in 12:
		var kind: String = kinds[i % kinds.size()]
		var w: float = Street.CAR_KINDS[kind][1]
		fade.add(Street.parked_car(p, st, 45.46 - i * 8.0, ROAD + 0.22 + w * 0.5, 270.0, kind, Street.PAINT[(i * 5) % Street.PAINT.size()], -0.06))
	# Cans out for the morning, bags beside them.
	Props.bin(p, st, 22.6, PAVE - 0.45)
	Props.bin(p, st, 23.15, PAVE - 0.45)
	Street.bags(n, p.pt(23.85, PAVE - 0.5), 2)
	Props.bin(p, st, 41.9, PAVE - 0.45)
	Street.bags(n, p.pt(9.8, PAVE - 0.5), 1)
	# Litter, about every 4 m: in the gutter, on the pavement, in the strip.
	for i in 24:
		var lu := -6.0 + i * 3.9 + Props.rnd(i * 1.37) * 1.6
		var at: Vector3
		match i % 3:
			0:
				at = p.pt(lu, ROAD + 0.08 + Props.rnd(i * 2.1) * 0.14, -0.048)
			1:
				at = p.pt(lu, PAVE + 0.25 + Props.rnd(i * 3.3) * 1.6)
			_:
				at = p.pt(lu, STRIP + 1.0 + Props.rnd(i * 4.7) * 0.8)
		Street.litter(n, at, i)


## A wire hanging between two points, sagging `sag` in the middle.
static func _wire(n: Node3D, a: Vector3, b: Vector3, sag: float) -> void:
	var last := a
	for k in range(1, 7):
		var t := k / 6.0
		var at := a.lerp(b, t) - Vector3(0, 4.0 * sag * t * (1.0 - t), 0)
		Street.pipe(n, last, at, 0.014, Props.DARK, 4)
		last = at


# ------------------------------------------------------------------ corner

static func _corner(p: Node3D, st: int) -> void:
	Street.street_sign(p, st, OY0 - 0.5, ROAD - 0.5, SIGN, "OLD YORK RD", 270.0)
	Props.hydrant(p, st, 54.9, ROAD - 0.45)
	Street.mailbox(p, st, OY0 - 0.6, 11.2, 90.0)
	Street.bus_stop(p, st, OY0 - 0.45, 5.0, 0.0)
	Props.bench(p, st, CORNER + 0.55, 6.4, 90.0, 1.5, Color(0.3, 0.45, 0.32), true, 0.5)
	Street.cobra_lamp(p, st, OY0 - 0.65, 1.2, 90.0)
	_mural(p, st)
	# 532's back yard along Old York Road: a board fence (his side yard and the kitchen's window over it).
	p.fence(st, false, CORNER - 0.08, -4.0, D - (15.8 - 7.2), [], 1.8, "wood")


## 532's end wall, along Old York Road: a sunset over the rooftops, and a rose.
static func _mural(p: Node3D, st: int) -> void:
	var g := Street.face(p, st, CORNER, D, 90.0)
	var s0 := 1.0
	var s1 := 8.3              # (his main block is 8.6 m deep)
	Street.fb(g, s0 - 0.12, s1 + 0.12, 0.35, 6.75, 0.0, 0.012, Color(0.96, 0.95, 0.9))
	var bands := [[0.45, 1.9, Color(1.0, 0.62, 0.22)], [1.9, 3.1, Color(0.98, 0.42, 0.38)], [3.1, 4.4, Color(0.78, 0.3, 0.55)], [4.4, 5.6, Color(0.45, 0.26, 0.6)], [5.6, 6.65, Color(0.2, 0.2, 0.48)]]
	for band: Array in bands:
		Street.fb(g, s0, s1, band[0], band[1], 0.012, 0.022, band[2])
	Kit.disc(g, 1.1, Vector3(5.9, 2.4, 0.03), Color(1.0, 0.86, 0.3), 0.012, 16)
	# Rooftops against the sun, their windows lit.
	var roofs := [[s0, 2.3, 1.6], [2.3, 3.9, 2.0], [3.9, 5.1, 1.35], [5.1, 6.9, 1.8], [6.9, s1, 1.5]]
	for r: Array in roofs:
		Street.fb(g, r[0], r[1], 0.45, r[2], 0.022, 0.04, Color(0.18, 0.12, 0.2))
		for k in int((r[1] - r[0]) / 0.45):
			Street.fb(g, r[0] + 0.18 + k * 0.45, r[0] + 0.36 + k * 0.45, r[2] - 0.55, r[2] - 0.32, 0.04, 0.046, Color(1.0, 0.85, 0.4))
	# Stars in the top band.
	for i in 9:
		var ss := s0 + 0.4 + Props.rnd(i * 5.1) * (s1 - s0 - 0.8)
		var sy := 5.75 + Props.rnd(i * 7.3) * 0.75
		Street.fb(g, ss - 0.05, ss + 0.05, sy - 0.05, sy + 0.05, 0.022, 0.03, Color(1.0, 0.97, 0.85))
	# The rose: a stem, two leaves, the bloom.
	Street.fb(g, 2.55, 2.75, 1.6, 4.3, 0.04, 0.058, Color(0.2, 0.55, 0.25))
	Kit.box(g, Vector3(0.9, 0.36, 0.02), Vector3(2.25, 2.7, 0.052), Color(0.25, 0.65, 0.3), Vector3(0, 0, 28))
	Kit.box(g, Vector3(0.9, 0.36, 0.02), Vector3(3.05, 3.3, 0.052), Color(0.25, 0.65, 0.3), Vector3(0, 0, -28))
	Kit.disc(g, 0.95, Vector3(2.65, 4.75, 0.07), Color(0.86, 0.12, 0.2), 0.02, 14)
	Kit.disc(g, 0.66, Vector3(2.62, 4.82, 0.09), Color(0.95, 0.28, 0.35), 0.02, 12)
	Kit.disc(g, 0.36, Vector3(2.6, 4.88, 0.11), Color(0.7, 0.06, 0.14), 0.02, 10)


# ----------------------------------------------------------------- context

## Old York Road's houses either side of the end of the street, the backs of
## the next street over the alley, trees in the back yards: plain, for the
## glimpse up Old York Road and the overview.
static func _context(p: Node3D, st: int) -> void:
	var brick_a := _brick(Color(0.82, 0.76, 0.78))
	var brick_b := _brick(Color(0.95, 0.88, 0.86))
	var formstone := _formstone()
	var siding := Color(0.82, 0.78, 0.62)
	var looks := [brick_a, formstone, brick_b, brick_a, formstone, brick_b, brick_a, brick_b]
	var trims := [Street.WHITE, Street.BROWN, Street.CREAM, Street.WHITE, Street.GREEN, Street.WHITE, Street.RED, Street.CREAM]
	var dc: Dictionary = Street.DOORS
	var doors := [dc["red"], dc["blue"], dc["black"], dc["green"], dc["wood"], dc["red"], dc["white"], dc["black"]]
	# Old York Road, west side, beyond the alley: fronts facing the road (+x).
	var v := -7.5
	for i in 8:
		var w := 4.5
		Street.plain_house(Street.face(p, st, CORNER, v, 90.0), w, 8.5 if i % 3 == 1 else 8.2, looks[i], trims[i], doors[i], ["10100", "0101", "1001", "0110", "1100", "0011", "1010", "0100"][i], 2, i % 2 == 0)
		v -= w
	# And on up the road, out of reach, into the dusk: plainer rows, lamps.
	_far_row(p, st, CORNER, v, NORTH + 12.0, 90.0, 1)
	for lv: float in [-30.0, -65.0, -100.0, -135.0]:
		Street.cobra_lamp(p, st, OY0 - 0.65, lv, 90.0, 1.17, 0.0)
	for lv: float in [-47.0, -82.0, -117.0, -152.0]:
		Street.cobra_lamp(p, st, OY1 + 0.65, lv, 270.0, 1.17, 0.0)
	# East side, facing back across it (-x): 4027 (a detached frame house) and the rows either side.
	Street.plain_house(Street.face(p, st, EAST, 7.6, 270.0), 6.0, 6.3, siding, Street.WHITE, dc["blue"], "1010", 2, false)
	var east := [[14.6, 4.8], [19.4, 4.4], [23.8, 4.7], [28.5, 4.5], [33.0, 4.6]]
	for i in east.size():
		var e: Array = east[i]
		Street.plain_house(Street.face(p, st, EAST, e[0], 270.0), e[1], 8.5, looks[(i + 2) % 8], trims[(i + 1) % 8], doors[(i + 3) % 8], ["0101", "1001", "0110", "1000", "0010"][i], 2, i % 2 == 1)
	v = 6.6
	for i in 8:
		Street.plain_house(Street.face(p, st, EAST, v - 4.6, 270.0), 4.6, 8.3, looks[i], trims[(i + 3) % 8], doors[(i + 5) % 8], ["0110", "1001", "0101", "0010", "1100", "0001", "1010", "0100"][i], 2, i % 2 == 0)
		v -= 4.6
	_far_row(p, st, EAST, v, NORTH + 12.0, 270.0, 4)
	# The backs of the next street's houses, across the alley.
	var back := Street.face(p, st, ROW_END - 6.0, -7.5, 0.0)
	var long := CORNER - 9.0 - (ROW_END - 6.0)
	Street.fb(back, 0.0, long, 0.0, 7.2, -10.0, 0.0, _brick(Color(0.66, 0.6, 0.62)))
	Street.fb(back, 0.0, long, 7.2, 7.25, -10.0, -0.02, Street.TAR)
	var s := 1.2
	var k := 0
	while s < long - 1.0:
		Street.sash(back, s, 1.2, 0.8, 1.4, Street.WHITE, Street.LIT if Props.rnd(k * 1.3) > 0.62 else null, Color(0.85, 0.75, 0.5))
		Street.sash(back, s + 1.6, 4.3, 0.8, 1.4, Street.WHITE, Street.LIT if Props.rnd(k * 2.9) > 0.7 else null, Color(0.7, 0.8, 0.9))
		s += 3.1
		k += 1
	# And on behind the park's court (the row across the park's alley,
	# plans/park.gd's), a shade lower and 2 cm back, so the two never share a face.
	var behind := Street.face(p, st, LEFT - 30.0, -7.52, 0.0)
	var wide := ROW_END - 6.0 - (LEFT - 30.0)
	Street.fb(behind, 0.0, wide, 0.0, 6.9, -10.0, 0.0, _brick(Color(0.6, 0.54, 0.58)))
	Street.fb(behind, 0.0, wide, 6.9, 6.95, -10.0, -0.02, Street.TAR)
	s = 1.2
	while s < wide - 1.0:
		Street.sash(behind, s, 1.2, 0.8, 1.4, Street.WHITE, Street.LIT if Props.rnd(k * 1.3) > 0.62 else null, Color(0.85, 0.75, 0.5))
		Street.sash(behind, s + 1.6, 4.1, 0.8, 1.4, Street.WHITE, Street.LIT if Props.rnd(k * 2.9) > 0.7 else null, Color(0.7, 0.8, 0.9))
		s += 3.1
		k += 1
	# Rose Hill's own back yards: a board fence along the alley, trees whose
	# crowns stand over the roofs (where plans/backs.gd has them in the yards).
	_gb(p, p.node_of(st), ROW_END, CORNER - 0.13, -4.05, -3.95, 0.0, 1.8, Color(0.45, 0.33, 0.23))
	Outdoor.tree(p, st, -33.6, -2.5, "a", 1.1, 120.0)
	Outdoor.tree(p, st, 11.0, -2.4, "a", 1.15, 30.0)
	Outdoor.tree(p, st, 30.5, -2.0, "b", 1.3, 140.0)
	Outdoor.tree(p, st, 47.5, -1.4, "a", 1.0, 250.0)
	Outdoor.tree(p, st, -10.6, -2.6, "b", 1.2, 80.0)
	Outdoor.tree(p, st, -28.6, -2.2, "d", 1.1, 200.0)
	Outdoor.tree(p, st, 0.5, -2.4, "d", 1.2, 310.0)
	Outdoor.tree(p, st, 15.0, 1.4, "a", 0.95, 170.0)
	Outdoor.tree(p, st, 39.0, -2.3, "d", 1.05, 60.0)


## Old York Road's rows on up past where he can go, for the long look up the
## road: plain fronts in the colours below, a cornice, a door on its step, a
## window beside it and two over, some lit. From v0 on up to v1 (v1 < v0), the
## fronts on u facing `yaw` (90: +x, the road's west side; 270: -x, its east).
static func _far_row(p: Node3D, st: int, u: float, v0: float, v1: float, yaw: float, key: int) -> void:
	var walls := [_brick(Color(0.82, 0.76, 0.78)), _formstone(), _brick(Color(0.95, 0.88, 0.86)), _brick(Color(0.72, 0.64, 0.7)), Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.8, 0.78, 0.98))]
	var trims := [Street.WHITE, Street.CREAM, Street.WHITE, Street.BROWN, Street.GREEN]
	var doors: Array = Street.DOORS.values()
	var w := 4.6
	var v := v0
	var i := 0
	while v - w > v1:
		var k := i + key
		var h := 8.2 + 0.3 * float(k % 3)
		var trim: Color = trims[k % trims.size()]
		var g := Street.face(p, st, u, v if yaw < 180.0 else v - w, yaw)
		Street.fb(g, 0.0, w, 0.0, h, -9.0, 0.0, walls[(i * 3 + key) % walls.size()])
		Street.fb(g, 0.0, w, h - 0.52, h, 0.0, 0.3, trim)
		Street.fb(g, 0.0, w, h, h + 0.04, -9.0, 0.3, Street.TAR)
		var ds := 0.9 if k % 2 == 0 else w - 0.9
		Street.fb(g, ds - 0.6, ds + 0.6, Street.F0, Street.F0 + 2.6, 0.0, 0.05, trim)
		Street.fb(g, ds - 0.46, ds + 0.46, Street.F0, Street.F0 + 2.2, 0.05, 0.08, doors[k % doors.size()])
		Street.fb(g, ds - 0.65, ds + 0.65, 0.0, Street.F0, 0.0, 0.9, Street.MARBLE)
		var ws := w - 1.3 if ds < w * 0.5 else 1.3
		for at: Vector2 in [Vector2(ws, Street.F0 + 0.8), Vector2(1.2, Street.F0 + 3.7), Vector2(w - 1.2, Street.F0 + 3.7)]:
			var lit := Props.rnd(float(k) * 7.3 + at.x * 3.1 + at.y) > 0.62
			Street.fb(g, at.x - 0.5, at.x + 0.5, at.y - 0.08, at.y + 1.58, 0.0, 0.05, trim)
			Street.fb(g, at.x - 0.42, at.x + 0.42, at.y, at.y + 1.5, 0.05, 0.07, Kit.flat(Street.LIT, 1.1) if lit else Street.PANE)
		v -= w
		i += 1


## Dusk over Rose Hill: the sun gone down in the west-north-west, the sky over
## the city still orange that way and purple overhead; a low warm light from
## where it went and the sky's own cool light from above.
static func _sky(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.22, Color(0.56, 0.6, 1.0))
	var glow := Outdoor.moonlight(n, 0.32, Color(1.0, 0.6, 0.42))
	glow.rotation_degrees = Vector3(-14, -70, 0)
	Outdoor.backdrop(n, p.pt(20.0, -30.0), [Color(1.0, 0.62, 0.3), Color(0.93, 0.4, 0.42), Color(0.34, 0.22, 0.5)], Vector3.INF, 5.0, 900.0, Vector2(-0.85, -0.5))
