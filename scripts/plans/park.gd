extends RefCounted
## Pen Lucy Park: the neighbourhood basketball court, under its floodlights on
## an evening, with the backs of a row of houses across the alley behind it.
## All of it is out of doors, so all of it is in the street's own band and
## always on show:
##
##   the alley, the yards and the backs of the houses (seen, not walked)
##   ---- tall chain-link along the alley ---------------------------------
##   COURT: 40 x 21.4 m inside the fence. A full court (28 x 15 m) runs left
##     to right, broadside to the camera. Behind it, along the fence: four
##     floodlights, the bleachers, the two team benches, the park's name
##     board and the scoreboard; behind the bleachers a strip to slip into
##     between them and the fence (somebody sits back there). The ends: a
##     hoop each, a bench, the drinking fountain and a hopscotch on the
##     left, a bench and the chalked list of who has next on the right, and
##     there a path through the bed to an opening in the fence. Along the
##     near side, two backless benches and a bin; a fifth floodlight in the
##     near left corner. Planted beds along the sides and the front (not
##     walked on; trees only in the left one, so none ever stands between
##     the camera and him).
##   CORNER LOT, through the opening: the park's corner by the end of Rose
##     Hill's row (504, plans/street.gd), grass with the restroom block in
##     its far corner, shut, a path worn past it to where the chain-link
##     along the alley has been cut open (E there: out into the alley
##     behind the row, plans/backs.gd, whose TO THE PARK comes back in);
##     a planted bed from there to the railing on the pavement.
##   ---- a low iron railing, the gate in the middle ----------------------
##   street: the pavement he arrives on, and the road
##
## The tall fence runs along the back and down both sides to the near
## sideline; on the camera side there is only the low railing. Outside the
## fence there is lawn and trees to the left, the corner lot and the end of
## Rose Hill's row to the right, and the row of houses across the alley.
## Numbers are metres on the plan (see place.gd): u from the left fence, v
## from the alley's far edge (the houses' yards are behind it, v < 0); the
## railing is at v = 25.
##
## Names and words invented here (placeholders): the board "PEN LUCY PARK /
## RECREATION AND PARKS", the scoreboard ("HOME", "GUEST", "18", "21", "GAME
## TO 21 / WIN BY 2"), the stencils "PARKS" and "TRASH" on the drum bins,
## the chalk "I GOT NEXT" with "DRE", "MOOK" and "LIL T", the hopscotch
## numbers, and "NO DUMPING" in the alley; the homes worker's (15 Nov): the
## use point "TO THE ALLEY", the room's name CORNER LOT, RELL and LIL and
## their lines (talk_park_*.json); the restroom's words are props_backs.gd's.

const Props := preload("res://scripts/props.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Park := preload("res://scripts/props_park.gd")
const Backs := preload("res://scripts/props_backs.gd")
const Street := preload("res://scripts/props_street.gd")
const Houses := preload("res://scripts/houses.gd")
const Walk := preload("res://scripts/sidewalk.gd")
const StreetPlan := preload("res://scripts/plans/street.gd")

const W := 40.0               # the park, fence to fence
const D := 25.0               # the alley's far edge (0) to the railing on the street
const FENCE_V := 3.6          # the tall fence along the alley
const ALLEY := 0.0            # the yards end, the alley begins
const BACKS := -3.2           # the houses' back buildings' rear walls
const CU0 := 6.0              # the court: u 6 .. 34, v 7 .. 22
const CU1 := 34.0
const CV0 := 7.0
const CV1 := 22.0
const PAD := [1.8, 23.4, 38.2]     # where the asphalt stops: the left bed, the front bed, the right bed
const GATE := [19.2, 20.8]
const OPENING := [8.0, 9.4]   # the way through the right-hand fence into the corner lot
const HOUSE := 48.54          # 504's end wall (Rose Hill's ROW_END): the corner lot from W to here
const CUT := [46.9, 48.2]     # where the chain-link along the alley is cut open (the backs' TO THE PARK)
const LOT_BED := 12.6         # the corner lot's bed, from here to the railing
## The bed's shrubs, low ones: u, v, kind, size, turn (plans/backs.gd draws them too).
const LOT_SHRUBS := [[41.5, 15.4, "a", 1.0, 20.0], [47.3, 14.3, "d", 0.9, 140.0], [44.6, 18.2, "c", 0.85, 3.0], [42.6, 21.9, "d", 1.0, 260.0], [46.4, 22.6, "a", 0.9, 80.0]]


static func build(p: Node3D) -> void:
	p.setup("PEN LUCY PARK", W, D)
	var st: int = p.street(-6.0, 46.0)
	p.arrive = p.pt(20.0, 26.1)
	# The pavement runs east to Rose Hill Terrace (plans/street.gd: its west end
	# is the park's corner). (Placeholder: the label.)
	p.use_point(st, "TO ROSE HILL", 45.3, 26.2, "goto:street", 1.2, 1.9)
	# And west to Argonne Court, Large Fry's street (plans/fry.gd: TO THE PARK
	# at its east end). (Placeholder: the label.)
	p.use_point(st, "TO ARGONNE COURT", -5.3, 26.2, "goto:fry", 1.2, 1.9)
	# And in the corner lot, the cut in the chain-link along the alley: out into
	# Rose Hill's backs (plans/backs.gd: its TO THE PARK is on the other side).
	# (Placeholder: the label.)
	p.use_point(st, "TO THE ALLEY", (CUT[0] + CUT[1]) * 0.5, FENCE_V + 0.75, "goto:backs", 1.0, 1.9)
	# Across the road from the kerb, Linden Square (plans/park2.gd: its TO PEN
	# LUCY PARK comes back). (Civic worker, 15 Nov; placeholder: the label.)
	p.use_point(st, "TO LINDEN SQUARE", 9.5, 27.0, "goto:park2", 1.1, 1.9)
	# Night: the floodlights lay pools on the court, the alley lights and the
	# windows do the rest; a cool moon (_sky) stands in for main.gd's warm sun.
	p.ambient = 0.11
	p.sun_energy = 0.0
	# Three from the neighbourhood, on the court (working names).
	p.person(st, "tre", 15.5, 15.2, {"name": "TRE", "face": "happy"})
	p.person(st, "dee", 18.2, 13.6, {"name": "BIG DEE", "face": "smug"})
	p.person(st, "chuy", 24.5, 16.4, {"name": "CHUY", "face": "content"})
	# One sitting it out behind the bleachers, one at the shut restrooms
	# (placeholder names and lines).
	p.person(st, "rell", 23.25, 4.2, {"name": "RELL", "face": "suspicious", "talk": "talk_park_bleachers.json"})
	p.person(st, "lil", 43.0, 7.85, {"name": "LIL", "face": "neutral", "talk": "talk_park_corner.json"})
	p.room("COURT", st, 0.0, FENCE_V, W, D, null, {"street": true})
	# The corner lot: walked from the court's fence to 504's and from the alley's
	# to its bed; the camera kept off 504's end wall.
	var lot: int = p.room("CORNER LOT", st, W, FENCE_V, HOUSE, D, null, {"street": true, "areas": [[W, FENCE_V, HOUSE, LOT_BED]]})
	p.rooms[lot]["cam_max_x"] = p.pt(47.0, 0.0).x
	_ground(p, st)
	_fences(p, st)
	var green := Color(0.2, 0.52, 0.4)
	var blue := Color(0.18, 0.36, 0.66)
	Park.court(p, st, CU0, CV0, CU1, CV1, Outdoor.tex("out_court", 9.6, green, green), Outdoor.tex("out_court", 9.6, blue, blue))
	_court(p, st)
	_beds(p, st)
	_outside(p, st)
	_corner(p, st)
	_alley(p, st)
	_houses(p, st)
	_sky(p, st)


# ------------------------------------------------------------------- the ground

static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var grass := Outdoor.tex("out_grass", 3.0, Color(0.32, 0.62, 0.26))
	var lawn := Outdoor.tex("out_grass", 3.6, Color(0.24, 0.46, 0.22), Color(0.68, 0.76, 0.72))
	var tar := Outdoor.tex("out_asphalt", 6.4, Color(0.22, 0.24, 0.29), Color(0.9, 0.92, 1.0))
	var concrete := Outdoor.pavement()
	# Inside the fence: the beds' earth and grass under everything, the asphalt
	# pad on it (in quarters, so no one mesh is lit by more lamps than the
	# renderer takes: the alley lights reach the back ones, the gate's lamp and
	# the street's the front ones), and the path in from the gate.
	# (They are cut in different places: two ends of different looks in one plane would flicker.)
	for half: Array in [[0.0, 19.5], [19.5, W]]:
		for depth: Array in [[FENCE_V, 14.0], [14.0, D]]:
			Kit.box(n, Vector3(half[1] - half[0], 0.3, depth[1] - depth[0]), p.pt((half[0] + half[1]) * 0.5, (depth[0] + depth[1]) * 0.5, -0.15), grass)
	for half: Array in [[PAD[0], 20.5], [20.5, PAD[2]]]:
		for depth: Array in [[FENCE_V, 13.5], [13.5, PAD[1]]]:
			Kit.box(n, Vector3(half[1] - half[0], 0.2, depth[1] - depth[0]), p.pt((half[0] + half[1]) * 0.5, (depth[0] + depth[1]) * 0.5, -0.07), tar)
	Kit.box(n, Vector3(GATE[1] - GATE[0], 0.2, D - PAD[1] - 0.01), p.pt(20.0, (PAD[1] + D - 0.01) * 0.5, -0.065), concrete)
	# Outside the fence: lawn to the left, the corner lot's to the right (as far
	# as 504's end wall), and the dark ground running off beyond.
	for side: Array in [[-34.0, 0.0], [W, HOUSE]]:
		Kit.box(n, Vector3(side[1] - side[0], 0.3, D - FENCE_V), p.pt((side[0] + side[1]) * 0.5, (FENCE_V + D) * 0.5, -0.15), lawn)
	var dark := Outdoor.tex("out_grass", 3.6, Color(0.16, 0.2, 0.17), Color(0.6, 0.67, 0.64))
	for side: Array in [[-110.0, -34.0], [HOUSE, 140.0]]:
		Kit.box(n, Vector3(side[1] - side[0], 0.3, 60.0), p.pt((side[0] + side[1]) * 0.5, D - 30.0, -0.155), dark)
	# The street runs on out of sight both ways (place.gd lays the middle of it,
	# u -14 .. 54): the same slabs, kerb, gutter, road and centre dashes.
	for side: Array in [[-110.0, -14.0], [54.0, 150.0]]:
		var mid: float = (side[0] + side[1]) * 0.5
		var long: float = side[1] - side[0]
		Kit.box(n, Vector3(long, 0.3, 2.5), p.pt(mid, D + 1.25, -0.15), Outdoor.pavement())
		Kit.box(n, Vector3(long, 0.32, 0.2), p.pt(mid, D + 2.6, -0.14), Outdoor.KERB)
		Kit.box(n, Vector3(long, 0.3, 7.0), p.pt(mid, D + 6.2, -0.29), Outdoor.road())
		Kit.box(n, Vector3(long - 0.02, 0.012, 0.36), p.pt(mid, D + 2.88, -0.136), Outdoor.GUTTER)
		var dash: float = -12.5 + 3.4 * ceilf((side[0] + 12.5) / 3.4)
		while dash + 0.7 < side[1]:
			if dash - 0.7 > side[0]:
				Kit.box(n, Vector3(1.4, 0.01, 0.12), p.pt(dash, D + 5.9, -0.135), Color(0.85, 0.8, 0.55))
			dash += 3.4


# ------------------------------------------------------------------- the fences

static func _fences(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var green := Color(0.13, 0.3, 0.22)
	# Tall chain link along the alley and down both sides as far as the near
	# sideline; from there to the street, and along it, a low iron railing.
	var tall := CV1 + 0.6
	p.fence(st, true, FENCE_V, 0.0, W, [], 3.6, "chain")
	p.fence(st, false, 0.0, FENCE_V, tall, [], 3.6, "chain")
	p.fence(st, false, W, FENCE_V, tall, [OPENING], 3.6, "chain")
	# Over the opening into the corner lot the chain-link goes on above a rail at
	# head height, so it reads as a way in, not a hole.
	var mid: float = (OPENING[0] + OPENING[1]) * 0.5
	var span: float = OPENING[1] - OPENING[0]
	for y: float in [2.2, 3.57]:
		Kit.cyl(n, 0.024, span, p.pt(W, mid, y), Color(0.55, 0.58, 0.6), Vector3(90, 0, 0), 8)
	var header := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(span - 0.04, 3.53 - 2.24)
	header.mesh = q
	header.material_override = Outdoor.chain_link()
	header.position = p.pt(W, mid, (2.24 + 3.53) * 0.5)
	header.rotation_degrees = Vector3(0, 90, 0)
	n.add_child(header)
	p.fence(st, false, 0.0, tall, D, [], 1.05, "rail", green)
	p.fence(st, false, W, tall, D, [], 1.05, "rail", green)
	p.fence(st, true, D, 0.0, W, [GATE], 1.05, "rail", green)
	# A concrete kerb under the alley fence, all along but where the worn path
	# crosses it at the cut in the corner lot's (broken out there, _corner).
	for run: Array in [[-35.0, CUT[0] + 0.16], [CUT[1] - 0.16, 65.0]]:
		Kit.box(n, Vector3(run[1] - run[0], 0.16, 0.3), p.pt((run[0] + run[1]) * 0.5, FENCE_V, 0.0), Color(0.6, 0.6, 0.58))
	# The gateposts, each with a globe lamp on it (the warm light at the way in,
	# one lamp between them), and the gate, swung open into the park.
	var globe := Kit.flat(Color(1.0, 0.86, 0.6), 1.2)
	for u: float in GATE:
		var post: Node3D = p.prop(st, u + (-0.07 if u < 20.0 else 0.07), D, 0.0, 0.14, 0.14)
		Kit.box(post, Vector3(0.12, 1.3, 0.12), Vector3(0, 0.65, 0), green)
		Kit.box(post, Vector3(0.16, 0.05, 0.16), Vector3(0, 1.32, 0), green)
		Kit.cyl(post, 0.03, 0.08, Vector3(0, 1.38, 0), green, Vector3.ZERO, 6)
		Kit.ball(post, 0.105, Vector3(0, 1.5, 0), globe, 10)
		Kit.cyl(post, 0.05, 0.04, Vector3(0, 1.61, 0), green, Vector3.ZERO, 8, 0.02)
	Kit.omni(n, p.pt(20.0, D + 0.1, 1.55), Color(1.0, 0.84, 0.58), 2.6, 6.0)
	var leaf := Kit.group(n, p.pt(GATE[0] - 0.02, D - 0.04), Vector3(0, 97, 0))
	Park.rod(leaf, Vector3(0.05, 0.12, 0), Vector3(1.5, 0.12, 0), 0.02, green, 4)
	Park.rod(leaf, Vector3(0.05, 0.98, 0), Vector3(1.5, 0.98, 0), 0.02, green, 4)
	for i in 12:
		Kit.cyl(leaf, 0.011, 0.9, Vector3(0.12 + i * 0.12, 0.55, 0), green, Vector3.ZERO, 4)


# ------------------------------------------------------------------- the court

static func _court(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var mid_v := (CV0 + CV1) * 0.5
	Park.hoop(p, st, CU0 - 0.9, mid_v, 90.0)
	Park.hoop(p, st, CU1 + 0.9, mid_v, 270.0)
	# The lights: four along the back, one in the near left corner. Each lays a
	# pool on the court (the outer two on the keys, the inner two either side of
	# the middle); outside them, and outside the fence, it is night.
	var lights := [[2.6, Vector2(7.8, 11.6)], [14.5, Vector2(15.0, 11.8)], [25.5, Vector2(25.0, 11.8)], [37.4, Vector2(32.2, 11.6)]]
	for l: Array in lights:
		Park.floodlight(p, st, l[0], 4.15, 0.0, 7.6, 2, 12.0, 6.5, true, l[1], 30.0)
	Park.floodlight(p, st, 0.9, 23.9, 135.0, 7.6, 2, 9.0, 5.0, true, Vector2(8.5, 17.8), 30.0)
	# Along the back: the bleachers, the team benches, the name board, the scoreboard.
	# (The bleachers stand out from the fence far enough to get behind them.)
	var stands := Park.bleachers(p, st, 20.0, 5.7, 0.0, 6.0, 3)
	Props.boombox(stands, Vector3(1.7, 1.315, -0.73), 8.0)
	Kit.box(stands, Vector3(0.42, 0.06, 0.32), Vector3(-1.9, 0.925, -0.11), Color(0.8, 0.2, 0.2), Vector3(0, 12, 0))   # somebody's jacket
	# Behind them they would hide him from the camera: they fade while they do,
	# as the parked cars on the street do (props_street.gd's CarFade).
	var fade = Street.car_fade(p, st)
	fade.add(stands)
	Props.bench(p, st, 11.0, 6.1, 0.0, 3.0, Color(0.2, 0.46, 0.32))
	Props.bench(p, st, 29.0, 6.1, 0.0, 3.0, Color(0.2, 0.46, 0.32))
	var jug := Kit.group(n, p.pt(11.9, 6.1, 0.47))
	Kit.cyl(jug, 0.11, 0.3, Vector3(0, 0.15, 0), Color(0.9, 0.3, 0.15), Vector3.ZERO, 10)
	Kit.cyl(jug, 0.115, 0.05, Vector3(0, 0.32, 0), Color(0.95, 0.95, 0.92), Vector3.ZERO, 10)
	Kit.box(n, Vector3(0.5, 0.08, 0.36), p.pt(28.2, 6.1, 0.51), Color(0.18, 0.2, 0.42), Vector3(0, -8, 0))         # a folded sweatshirt
	var name_board := Park.board(p, st, 20.0, FENCE_V + 0.09, 0.0, 4.8, 0.95, 2.35, Color(0.1, 0.32, 0.22), true)
	Props.words(name_board, "PEN LUCY PARK", Vector3(0, 2.92, 0.03), 0.42, Color(1.0, 0.86, 0.3))
	Props.words(name_board, "RECREATION AND PARKS", Vector3(0, 2.52, 0.03), 0.13, Color(0.95, 0.93, 0.84))
	Park.scoreboard(p, st, 32.4, FENCE_V + 0.09, 0.0)
	Park.barrel(p, st, 7.8, 4.35, Color(0.12, 0.42, 0.62), "PARKS")
	Park.barrel(p, st, 34.6, 4.35, Color(0.12, 0.42, 0.62), "PARKS")
	# The ends: the left one has the bench, the fountain and the hopscotch.
	Park.park_bench(p, st, 2.45, 10.2, 90.0)
	Park.barrel(p, st, 2.35, 13.0, Color(0.85, 0.45, 0.12), "TRASH")
	Park.drinking_fountain(p, st, 2.5, 20.6, 90.0)
	Park.hopscotch(n, p.pt(3.4, 19.4))
	# The right end: a bench, a bin, and who has next, in chalk.
	Park.park_bench(p, st, 37.55, 11.0, 270.0)
	Park.barrel(p, st, 37.6, 18.0, Color(0.85, 0.45, 0.12), "TRASH", false)
	var chalk: Array = Park.CHALK
	Park.ground_words(n, "I GOT NEXT", p.pt(36.4, 19.3, 0.034), 0.3, chalk[2], -6.0)
	Park.ground_words(n, "DRE", p.pt(36.0, 19.85, 0.034), 0.24, chalk[0], 4.0)
	Park.ground_words(n, "MOOK", p.pt(36.2, 20.3, 0.034), 0.24, chalk[3], -3.0)
	Park.ground_words(n, "LIL T", p.pt(36.1, 20.75, 0.034), 0.24, chalk[1], 2.0)
	# Balls, a crate, the litter round the bins.
	Park.ball(n, p.pt(8.6, 17.4, 0.045))
	Park.ball(n, p.pt(10.2, 6.22, 0.03), 40.0)
	var crate := Park.crate(n, p.pt(36.6, 7.9, 0.03), 12.0)
	Park.ball(crate, Vector3(0, 0.2, 0), 70.0)
	Park.litter(n, p.pt(8.6, 4.6, 0.03), 3.0, 3)
	Park.litter(n, p.pt(18.5, 6.4, 0.03), 9.0, 4)
	Park.litter(n, p.pt(36.8, 18.6, 0.03), 17.0, 3)
	Park.litter(n, p.pt(3.4, 12.6, 0.03), 23.0, 2)
	_behind_bleachers(p, n)
	# Along the near side: two long benches for watching from, backless so the
	# camera sees over them. The bin for the gate stands out on the pavement to
	# its left, where it never comes between the camera and him (inside, right of
	# the gate, it hid his feet as he came in).
	Props.bench(p, st, 12.0, 22.95, 0.0, 3.0, Color(0.2, 0.46, 0.32))
	Props.bench(p, st, 28.0, 22.95, 0.0, 3.0, Color(0.2, 0.46, 0.32))
	Kit.box(n, Vector3(0.36, 0.05, 0.26), p.pt(27.1, 22.95, 0.5), Color(0.85, 0.85, 0.82), Vector3(0, 14, 0))   # a folded newspaper
	Park.barrel(p, st, 18.2, 25.45, Color(0.12, 0.42, 0.62), "PARKS")
	Park.litter(n, p.pt(17.5, 25.75, 0.03), 31.0, 2)


## Behind the bleachers, out of the light: a strip of the pad between them and
## the fence, a crate, a flattened box, bottles and cans, paper; under them a
## bag with a bottle in it. All of it loose: nothing here takes floor.
static func _behind_bleachers(p: Node3D, n: Node3D) -> void:
	var top := 0.03                                     # the pad's top
	Park.crate(n, p.pt(18.85, 4.12, top), 24.0, Color(0.2, 0.42, 0.7))
	Kit.box(n, Vector3(0.85, 0.012, 0.55), p.pt(20.55, 4.16, top + 0.006), Color(0.6, 0.47, 0.3), Vector3(0, 8, 0))       # a box, flattened to sit on
	Kit.box(n, Vector3(0.5, 0.012, 0.36), p.pt(20.2, 4.3, top + 0.018), Color(0.66, 0.53, 0.36), Vector3(0, -21, 0))
	for b: Array in [[19.6, 4.36, 70.0, Color(0.42, 0.26, 0.12)], [17.9, 4.18, -35.0, Color(0.7, 0.78, 0.74)], [22.1, 3.86, 15.0, Color(0.24, 0.42, 0.24)]]:
		Kit.cyl(n, 0.035, 0.24, p.pt(b[0], b[1], top + 0.035), b[3], Vector3(0, b[2], 90), 8)        # bottles, lying
	Kit.cyl(n, 0.035, 0.24, p.pt(21.35, 3.82, top + 0.12), Color(0.42, 0.26, 0.12), Vector3.ZERO, 8)
	Kit.cyl(n, 0.014, 0.06, p.pt(21.35, 3.82, top + 0.27), Color(0.42, 0.26, 0.12), Vector3.ZERO, 6)
	for c: Array in [[18.3, 4.42, Color(0.8, 0.16, 0.14), true], [21.7, 4.4, Color(0.75, 0.77, 0.8), false], [19.25, 3.84, Color(0.2, 0.36, 0.7), true]]:
		if c[3]:
			Kit.cyl(n, 0.033, 0.12, p.pt(c[0], c[1], top + 0.033), c[2], Vector3(0, 40.0 * c[0], 90), 8)        # cans, crushed and kicked about
		else:
			Kit.cyl(n, 0.033, 0.12, p.pt(c[0], c[1], top + 0.06), c[2], Vector3.ZERO, 8)
	Park.litter(n, p.pt(20.4, 4.2, top), 61.0, 4)
	var bag := Kit.group(n, p.pt(21.6, 5.55, top), Vector3(0, 30, 0))
	Kit.box(bag, Vector3(0.16, 0.26, 0.11), Vector3(0, 0.13, 0), Color(0.62, 0.48, 0.32))
	Kit.cyl(bag, 0.016, 0.12, Vector3(0.02, 0.3, 0), Color(0.42, 0.26, 0.12), Vector3.ZERO, 6)


## The planted beds along the sides and the front: earth and grass behind a low
## kerb, shrubs, two small trees on the left. Nobody walks in them, so nothing
## planted there ever stands between the camera and him.
static func _beds(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var kerb := Color(0.7, 0.69, 0.66)
	p.block(0.0, FENCE_V, PAD[0], D)
	p.block(PAD[2], FENCE_V, W, OPENING[0])
	p.block(PAD[2], OPENING[1], W, D)
	p.block(PAD[0], PAD[1], GATE[0], D)
	p.block(GATE[1], PAD[1], PAD[2], D)
	# (The side kerbs stop a centimetre short of the asphalt's edges, so no face of
	# one lies in a face of the other.)
	Kit.box(n, Vector3(0.12, 0.14, PAD[1] - FENCE_V - 0.02), p.pt(PAD[0] + 0.07, (FENCE_V + PAD[1]) * 0.5, 0.06), kerb)
	Kit.box(n, Vector3(0.12, 0.14, OPENING[0] - FENCE_V - 0.01), p.pt(PAD[2] - 0.07, (FENCE_V + 0.01 + OPENING[0]) * 0.5, 0.06), kerb)
	Kit.box(n, Vector3(0.12, 0.14, PAD[1] - 0.01 - OPENING[1]), p.pt(PAD[2] - 0.07, (OPENING[1] + PAD[1] - 0.01) * 0.5, 0.06), kerb)
	# The path through the right-hand bed to the opening, concrete as the gate's,
	# on out into the corner lot (_corner wears the rest of the way).
	Kit.box(n, Vector3(40.6 - PAD[2], 0.2, OPENING[1] - OPENING[0]), p.pt((PAD[2] + 40.6) * 0.5, (OPENING[0] + OPENING[1]) * 0.5, -0.065), Outdoor.pavement())
	Kit.box(n, Vector3(GATE[0] - PAD[0] + 0.12, 0.14, 0.12), p.pt((PAD[0] + GATE[0]) * 0.5 - 0.06, PAD[1] + 0.06, 0.07), kerb)
	Kit.box(n, Vector3(PAD[2] - GATE[1] + 0.12, 0.14, 0.12), p.pt((GATE[1] + PAD[2]) * 0.5 + 0.06, PAD[1] + 0.06, 0.07), kerb)
	# Two trees in the left bed, clear of the floodlight in the corner. (The camera
	# looks in from the right, so the left bed is the one place a tree can stand
	# inside the fence without ever coming between it and him.)
	Outdoor.tree(p, st, 0.9, 11.6, "b", 0.72, 30.0)
	Outdoor.tree(p, st, 0.85, 16.4, "c", 0.68, 200.0)
	# Shrubs: anything goes in the left bed; on the right and along the front,
	# which the camera looks across, only the low kinds.
	var kinds := ["a", "b", "c", "d"]
	var low := ["a", "d", "c"]
	var i := 0
	# (The long hedge kind, "c", always lies along its bed; the round ones any way.)
	for v: float in [5.0, 7.6, 9.0, 14.0, 19.0, 21.4]:
		var k: String = kinds[i % 4]
		Outdoor.shrub(p, st, 0.9, v, k, 0.85 + 0.2 * Props.rnd(v), (90.0 + 8.0 * (Props.rnd(v * 2.0) - 0.5)) if k == "c" else 40.0 * i)
		i += 1
	Outdoor.shrub(p, st, 39.1, 5.2, "b", 0.95, 10.0)
	for v: float in [6.7, 11.2, 14.5, 17.4, 20.3, 22.8]:          # (none on the path to the opening)
		var k: String = low[i % 3]
		Outdoor.shrub(p, st, 39.1, v, k, 0.7 + 0.15 * Props.rnd(v), (90.0 + 8.0 * (Props.rnd(v * 2.0) - 0.5)) if k == "c" else 55.0 * i)
		i += 1
	for u: float in [2.8, 5.6, 8.6, 11.0, 14.2, 17.2, 22.8, 25.6, 28.8, 31.4, 34.4, 37.0]:
		var k: String = low[i % 3]
		Outdoor.shrub(p, st, u, 24.2, k, 0.68 + 0.18 * Props.rnd(u), (8.0 * (Props.rnd(u * 2.0) - 0.5)) if k == "c" else 70.0 * i)
		i += 1
	# Weeds along the foot of the alley fence.
	for k in 40:
		var u := 0.4 + float(k) * 0.98 + 0.4 * Props.rnd(k * 1.3)
		Kit.box(n, Vector3(0.05, 0.3 + 0.3 * Props.rnd(k * 2.1), 0.05), p.pt(u, FENCE_V + 0.12, 0.2), Color(0.3, 0.5, 0.24), Vector3(15.0 * (Props.rnd(k * 3.7) - 0.5), 30.0 * k, 20.0 * (Props.rnd(k * 5.3) - 0.5)))


## Outside the fence: lawn and trees to the left, a lamp on the street. (To the
## right the corner lot and 504: _corner. No tree there: it would stand where
## the camera does, or between it and him.)
static func _outside(p: Node3D, st: int) -> void:
	var kinds := ["a", "b", "c", "d"]
	# Each: u, v, kind, size. The big kind ("a", twelve metres at full size) only
	# further off and cut down; the smaller ones near the fence.
	var trees := [[-6.6, 7.6, "d", 1.0], [-10.0, 14.6, "b", 0.78], [-6.4, 21.0, "c", 0.9], [-15.5, 8.0, "a", 0.62],
		[-19.5, 17.0, "b", 0.85], [-13.0, 22.6, "d", 1.1], [-25.5, 10.0, "a", 0.7], [-29.0, 19.5, "c", 1.0], [-22.5, 23.2, "d", 0.9]]
	for i in trees.size():
		var t: Array = trees[i]
		Outdoor.tree(p, st, t[0], t[1], t[2], t[3], 47.0 * i)
	for s: Array in [[-1.6, 12.0], [-3.0, 5.0], [-2.0, 23.4]]:
		Outdoor.shrub(p, st, s[0], s[1], kinds[int(s[1]) % 4], 1.1, s[0] * 10.0)
	Props.street_lamp(p, st, -2.5, 27.1)
	Props.hydrant(p, st, 44.0, 27.0)


# -------------------------------------------------------------- the corner lot

## The corner lot, right of the court (plans/backs.gd sees it from the alley,
## turned round): the path worn from the opening to where the chain-link along
## the alley has been cut open, the restroom block in the far corner with its
## back to the alley, shut, the lamp over one door left on; south of the path a
## bed behind a kerb to the railing on the pavement. Along its right side the
## end of 504, the first of Rose Hill's row (plans/street.gd's): the corrugated
## sheets round its yard, its back building over them, the end wall with its
## windows, its front on the pavement.
static func _corner(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var green := Color(0.13, 0.3, 0.22)
	# The path, worn into the grass (the concrete one through the bed comes out to
	# 40.6), on through the cut over the broken kerb and out into the alley.
	var dirt := Outdoor.tex("out_dirt", 2.0, Color(0.36, 0.3, 0.22))
	Kit.box(n, Vector3(47.3 - 40.6, 0.012, 0.9), p.pt((40.6 + 47.3) * 0.5, (OPENING[0] + OPENING[1]) * 0.5, 0.006), dirt)
	Kit.box(n, Vector3(1.0, 0.016, 8.9 - FENCE_V + 0.5), p.pt((CUT[0] + CUT[1]) * 0.5, (FENCE_V - 0.5 + 8.9) * 0.5, 0.008), dirt)
	# The bed: a kerb, low shrubs only (the camera stands over it).
	Kit.box(n, Vector3(HOUSE - W - 0.06, 0.14, 0.12), p.pt((W + HOUSE) * 0.5, LOT_BED + 0.06, 0.06), Color(0.7, 0.69, 0.66))
	for s: Array in LOT_SHRUBS:
		Outdoor.shrub(p, st, s[0], s[1], s[2], s[3], s[4])
	# The railing along the pavement goes on to 504; along the alley a lower
	# chain-link than the court's, cut open, the mesh peeled back well out into
	# the lot and the top rail still across (as the backs see it).
	p.fence(st, true, D, W, HOUSE, [], 1.05, "rail", green)
	p.fence(st, true, FENCE_V, W, HOUSE, [CUT], 1.8, "chain")
	Backs.torn(p, n, true, FENCE_V, CUT[0], CUT[1], 1.8, 1.0, true, true, 55.0)
	p.block(46.4, FENCE_V, CUT[0] + 0.02, 4.55)          # (the flap, and the roll of mesh it was peeled back into)
	# The restroom block (props_backs.gd's), shut, the lamp over its right-hand door on.
	Backs.restroom(p, st, 43.0, 5.5, 0.0, true)
	# Where people stand about, round its corner: a crate to sit on, litter, a bottle.
	Park.crate(n, p.pt(46.15, 6.7, 0.0), -12.0, Color(0.85, 0.2, 0.18))
	p.block(45.95, 6.5, 46.35, 6.9)
	Park.litter(n, p.pt(47.3, 4.7, 0.02), 125.0, 3)
	Park.litter(n, p.pt(44.4, 8.1, 0.02), 131.0, 3)
	Kit.cyl(n, 0.035, 0.24, p.pt(45.3, 8.4, 0.035), Color(0.24, 0.42, 0.24), Vector3(0, 125, 90), 8)
	# 504's yard: corrugated sheets along the lot and the alley (posts on the
	# yard's side: plans/backs.gd's, turned round), the gate in them; its back
	# building over them, a lit window on its side.
	var brick: Material = StreetPlan._brick(Color(0.9, 0.86, 0.9))
	Backs.corrugated(p, n, false, HOUSE + 0.04, FENCE_V + 0.06, 10.2, 2.1, 3.0, 1.0)
	Backs.corrugated(p, n, true, FENCE_V + 0.06, HOUSE + 0.03, 52.19, 2.1, 2.0, 1.0)
	Backs.corrugated(p, n, true, FENCE_V + 0.06, 53.19, 54.91, 2.1, 1.0, 1.0)
	var leaf := Kit.tex("in_ribbed", 0.5, Backs.RUST.lerp(Color(0.62, 0.64, 0.66), 0.3), false, Color(0.9, 0.86, 0.82))
	Kit.box(n, Vector3(0.9, 1.94, 0.02), p.pt(52.69, 3.68, 1.01), leaf)
	for y: float in [0.3, 1.6]:
		Kit.box(n, Vector3(0.9, 0.07, 0.06), p.pt(52.69, 3.72, y + 0.035), Color(0.3, 0.26, 0.22))
	Kit.box(n, Vector3(0.1, 0.06, 0.03), p.pt(52.37, 3.65, 1.03), Props.STEEL)
	Kit.box(n, Vector3(3.0, 6.0, 3.2), p.pt(53.44, 8.6, 3.0), brick)
	Kit.box(n, Vector3(3.0, 0.2, 0.34), p.pt(53.44, 7.11, 6.1), Park.COPING)
	Houses.simple_window(Houses.face(p, st, 51.94, 7.0, 270.0), 1.6, 3.6, 0.95, 1.3, Street.WHITE, Houses.LIT, Color(0.95, 0.93, 0.86))
	# 504 itself, as Rose Hill has it (plans/street.gd's row), its front 4 m back
	# from the pavement as there: the main block runs back to the yard, its end
	# windows down the lot's side; the paved strip from its porch to the pavement.
	var front := D - 4.0
	var deep := front - 10.2
	var h504 := {"no": "504", "wall": brick, "trim": Street.WHITE, "door": Street.DOORS["blue"], "door_left": true, "bay": "white", "lintel": Color(0.72, 0.71, 0.68),
		"height": 8.3, "chimney": true, "lit": "01001", "curtain": Color(0.95, 0.93, 0.86), "porch_light": true, "deep": deep}
	var house: Node3D = Street.porch_house(p, st, HOUSE, front, 6.4, h504)
	# Its end windows where Rose Hill has them (plans/street.gd's: from the front
	# back 9 m), the dark ones with their blinds pulled down (a bare dark pane at
	# night, close by the camera, read as a hole in the wall).
	var ends: Node3D = Houses.end_windows(house, 6.4, 9.0, -1, Houses.F0, 8.3, Street.WHITE, 6.4)
	var unlit := Kit.flat(Houses.PANE)
	for c: Node in ends.get_children():
		var pane := c as MeshInstance3D
		if pane == null or pane.material_override != unlit:
			continue
		var size: Vector3 = (pane.mesh as BoxMesh).size
		Kit.box(ends, Vector3(size.x - 0.06, size.y * 0.62, 0.006), pane.position + Vector3(0, size.y * 0.19, size.z * 0.5 + 0.003), Color(0.74, 0.7, 0.6))
	var door := HOUSE + 0.9
	Walk.front(p, n, HOUSE + Walk.WIDE * 0.5, HOUSE + 6.4 - Walk.WIDE * 0.5, front + 2.0, D - Walk.GAP * 0.5, door, "a", HOUSE)
	Walk.footing(p, n, HOUSE, HOUSE + 6.4, front + 2.0, door, 1.25, 0.9)
	# Rose Hill's yard trees behind it (plans/street.gd's, over the roofs).
	Outdoor.tree(p, st, 59.4, 5.1, "a", 1.1, 300.0)
	Outdoor.tree(p, st, 64.4, 5.4, "d", 1.1, 20.0)


# ------------------------------------------------------------------- the alley

static func _alley(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.66, 0.66, 0.7))
	for run: Array in [[-62.0, -8.0], [-8.0, 20.0], [20.0, 48.0], [48.0, 80.0]]:
		Kit.box(n, Vector3(run[1] - run[0], 0.3, FENCE_V - ALLEY - 0.1), p.pt((run[0] + run[1]) * 0.5, (ALLEY + FENCE_V - 0.1) * 0.5, -0.15), concrete)
	Kit.box(n, Vector3(141.9, 0.012, 0.36), p.pt(9.0, 1.75, 0.004), Color(0.3, 0.31, 0.33))      # the gutter down the middle
	for s: Array in [[6.0, 1.3, 0.7], [21.5, 2.2, 0.5], [31.0, 1.6, 0.9], [-4.0, 2.0, 0.6]]:  # puddles and oil
		Kit.cyl(n, s[2], 0.004, p.pt(s[0], s[1], 0.011), Color(0.12, 0.14, 0.2, 0.6), Vector3.ZERO, 12)
	# The poles, pole to pole the wires, and from the poles the wires to the houses.
	var poles := [-45.0, -27.0, -9.0, 9.0, 27.0, 45.0, 63.0]
	var tops: Array = []
	for u: float in poles:
		tops.append(Park.utility_pole(p, n, u, ALLEY + 0.35, 9.4, u == 27.0 or u == -27.0, u == 9.0 or u == 27.0))
	for i in poles.size() - 1:
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		for k in 4:
			Park.wire(n, a[k], b[k], 0.45 if k < 3 else 0.6)
	# A pair of sneakers thrown over the phone line.
	var hang := Park.wire_at(tops[3][3], tops[4][3], 0.6, 0.38)
	for k in 2:
		var shoe := Kit.group(n, hang + Vector3(-0.08 + 0.16 * k, -0.42 - 0.06 * k, 0), Vector3(0, 60 + 30 * k, 0))
		Kit.box(shoe, Vector3(0.12, 0.1, 0.3), Vector3.ZERO, Color(0.95, 0.95, 0.93))
		Kit.box(shoe, Vector3(0.125, 0.035, 0.31), Vector3(0, -0.05, 0), Color(0.75, 0.15, 0.15))
		Park.rod(n, hang, hang + Vector3(-0.08 + 0.16 * k, -0.38 - 0.06 * k, 0), 0.006, Color(0.9, 0.9, 0.88), 3)
	# The drops to the houses: from the phone arm to the top of each back wall.
	for d: Array in [[-9.0, -5.4], [-9.0, 0.1], [9.0, 10.6], [9.0, 15.9], [27.0, 26.1], [27.0, 31.3], [45.0, 41.7], [45.0, 46.9]]:
		var from: Vector3 = tops[poles.find(d[0])][3]
		Park.wire(n, from, p.pt(d[1], BACKS - 3.12, 6.6), 0.35, Color(0.07, 0.07, 0.08), 0.01, 5)
	# A shopping cart somebody left, an old sign.
	var cart := Kit.group(n, p.pt(36.8, 1.1), Vector3(0, -25, 0))
	var wire_look := Color(0.72, 0.74, 0.76)
	for e: Array in [[Vector3(-0.28, 0.45, -0.42), Vector3(0.28, 0.45, -0.42)], [Vector3(-0.32, 0.95, -0.48), Vector3(0.32, 0.95, -0.48)],
		[Vector3(-0.28, 0.45, 0.42), Vector3(0.28, 0.45, 0.42)], [Vector3(-0.34, 0.95, 0.5), Vector3(0.34, 0.95, 0.5)],
		[Vector3(-0.28, 0.45, -0.42), Vector3(-0.28, 0.45, 0.42)], [Vector3(0.28, 0.45, -0.42), Vector3(0.28, 0.45, 0.42)],
		[Vector3(-0.32, 0.95, -0.48), Vector3(-0.34, 0.95, 0.5)], [Vector3(0.32, 0.95, -0.48), Vector3(0.34, 0.95, 0.5)],
		[Vector3(-0.34, 0.95, 0.5), Vector3(-0.34, 1.05, 0.62)], [Vector3(0.34, 0.95, 0.5), Vector3(0.34, 1.05, 0.62)],
		[Vector3(-0.34, 1.05, 0.62), Vector3(0.34, 1.05, 0.62)]]:
		Park.rod(cart, e[0], e[1], 0.012, wire_look, 3)
	for x: float in [-0.28, 0.28]:
		for z: float in [-0.42, 0.42]:
			Park.rod(cart, Vector3(x, 0.08, z), Vector3(x * 1.1, 0.95, z * 1.12), 0.012, wire_look, 3)
			Kit.cyl(cart, 0.06, 0.04, Vector3(x, 0.06, z), Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 8)
	for side: float in [-1.0, 1.0]:
		Kit.box(cart, Vector3(0.012, 0.5, 0.9), Vector3(side * 0.31, 0.7, 0.04), Color(0.72, 0.74, 0.76, 0.3), Vector3(0, 0, side * -3))
	var sign_post := Kit.group(n, p.pt(-14.0, ALLEY + 0.25))
	Kit.cyl(sign_post, 0.03, 2.4, Vector3(0, 1.2, 0), Park.GALV, Vector3.ZERO, 6)
	Kit.box(sign_post, Vector3(0.6, 0.4, 0.02), Vector3(0, 2.15, 0.04), Color(0.92, 0.9, 0.84), Vector3(0, 0, 4))
	Props.words(sign_post, "NO DUMPING", Vector3(0, 2.15, 0.055), 0.09, Color(0.75, 0.12, 0.1)).rotation_degrees.z = 4.0


# ------------------------------------------------------------------- the houses

## The row across the alley, left to right. Pairs of houses share their back
## buildings, so the sides alternate. The middle stretch, behind the court, is
## dressed in full; the ends run on more plainly.
static func _houses(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	# (A shade duskier than the same bricks and paint by day, so the court under
	# its lights and the lit windows are the brightest things in the picture.)
	var red := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.8, 0.66, 0.62))
	var dark := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.6, 0.52, 0.56))
	var brown := Kit.tex("brick", 1.5, Color(0.45, 0.3, 0.22), true, Color(0.68, 0.56, 0.47))
	# The old Pen Lucy's walls (houses.gd): brick, formstone grey and tan, painted
	# brick; no clapboard or pastels, which it kept for its few detached houses.
	var form := Outdoor.tex("out_formstone", 2.0, Color(0.6, 0.59, 0.55), Color(0.8, 0.8, 0.84))
	var tan := Outdoor.tex("out_formstone", 2.0, Color(0.7, 0.65, 0.54), Color(0.84, 0.76, 0.62))
	var painted := Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.68, 0.66, 0.84))
	var light := Kit.tex("brick", 1.5, Color(0.54, 0.29, 0.23), true, Color(0.86, 0.8, 0.76))
	var silver := Color(0.5, 0.5, 0.53)          # the silver-coated roofs, by night
	var green_door := Color(0.2, 0.42, 0.3)
	var red_door := Color(0.6, 0.16, 0.13)
	var blue_door := Color(0.18, 0.3, 0.55)
	var cream_door := Color(0.84, 0.8, 0.68)
	var wash := [Color(0.95, 0.95, 0.92), Color(0.85, 0.25, 0.25), Color(0.25, 0.4, 0.75), Color(0.95, 0.85, 0.35), Color(0.3, 0.65, 0.4), Color(0.95, 0.6, 0.75)]
	var wash2 := [Color(0.3, 0.35, 0.6), Color(0.96, 0.96, 0.94), Color(0.96, 0.96, 0.94), Color(0.6, 0.3, 0.6), Color(0.9, 0.5, 0.2)]
	var row := [
		[-18.0, 5.2, {"brick": red, "lit": ["k"], "cans": 2, "cans_out": true, "door": red_door}],
		[-12.8, 5.0, {"brick": painted, "fence": "wood", "porch": true, "aerial": true, "lit": ["cu"], "door": blue_door, "trim": Color(0.27, 0.4, 0.3)}],
		[-7.8, 5.4, {"brick": red, "bb_h": 3.3, "line": wash2, "lit": ["m"], "door": green_door, "chimney": true}],
		[-2.4, 5.0, {"brick": form, "cans": 3, "cans_out": true, "extra": ["grill"], "lit": ["k", "cu"], "aerial": true, "door": cream_door, "bars": true}],
		[2.6, 5.2, {"brick": red, "bb": painted, "fence": "wood", "gate_open": true, "porch": true, "lit": ["k"], "ac": true, "extra": ["bike"], "awning": Color(0.2, 0.55, 0.35), "door": green_door, "curtain": Color(0.95, 0.85, 0.4)}],
		[7.8, 5.6, {"brick": dark, "boarded": true, "fence": "broken", "extra": ["weeds", "mattress", "tyre"], "chimney": true}],
		[13.4, 5.0, {"brick": tan, "line": wash, "lit": ["u", "c"], "cans": 2, "extra": ["trike"], "aerial": true, "door": blue_door, "trim": Color(0.96, 0.95, 0.9), "curtain": Color(0.4, 0.6, 0.85)}],
		[18.4, 5.2, {"brick": red, "fence": "brick", "porch": true, "lit": ["k"], "extra": ["planters", "chair"], "storm": true, "door": cream_door, "bars": true}],
		[23.6, 5.0, {"brick": light, "bb_h": 3.3, "extra": ["doghouse"], "cans": 2, "cans_out": true, "lit": ["m"], "aerial": true, "door": red_door, "trim": Color(0.55, 0.3, 0.2)}],
		[28.6, 5.4, {"brick": dark, "fence": "wood", "ac": true, "lit": ["cu"], "porch": true, "bars": true, "door": green_door, "awning": Color(0.75, 0.2, 0.18), "chimney": true}],
		[34.0, 5.2, {"brick": form, "gate_open": true, "line": wash, "lit": ["k", "u"], "cans": 3, "door": cream_door, "trim": Color(0.96, 0.95, 0.9), "curtain": Color(0.85, 0.3, 0.35)}],
		[39.2, 5.0, {"brick": red, "fence": "none", "lit": ["c"], "cans": 2, "cans_out": true, "extra": ["grill"], "aerial": true, "bars": true, "door": blue_door}],
		[44.2, 5.4, {"brick": form, "lit": ["u"], "door": red_door, "chimney": true}],
		[49.6, 5.2, {"brick": brown, "fence": "wood", "door": green_door}],
	]
	# The ends of the row: lived in like the middle, a little less to look at.
	var looks := [brown, red, dark, form, red, painted, brown, dark]
	var fences := ["chain", "wood", "chain", "none", "chain", "wood"]
	var dress_l := [
		{"line": wash2, "extra": ["chair"], "chimney": true, "curtain": Color(0.4, 0.6, 0.85)},
		{"bb": painted, "awning": Color(0.43, 0.3, 0.2), "porch": true, "extra": ["planters"], "trim": Color(0.96, 0.95, 0.9)},
		{"ac": true, "bars": true, "extra": ["grill"]},
		{"bb": light, "line": wash, "chimney": true, "curtain": Color(0.95, 0.85, 0.4)},
		{"extra": ["bike"], "trim": Color(0.96, 0.95, 0.9), "bars": true, "storm": true},
		{"porch": true, "extra": ["doghouse"], "awning": Color(0.75, 0.2, 0.18)},
		{"bb": tan, "line": wash2, "ac": true, "chimney": true},
		{"extra": ["trike", "planters"], "trim": Color(0.55, 0.3, 0.2)},
	]
	var u := -18.0
	for i in 8:
		var w := 5.0 + 0.2 * float((i * 3) % 3)
		u -= w
		var o := {"brick": looks[i], "fence": fences[i % fences.size()], "lit": [["k"], ["c"], ["cu"], ["k", "u"], ["u", "k"], ["c"], ["c"], ["cu"]][i], "cans": (i * 2) % 3, "cans_out": i % 2 == 0, "aerial": i % 3 == 1, "door": [green_door, red_door, blue_door, cream_door][i % 4]}
		o.merge(dress_l[i])
		row.push_front([u, w, o])
	var dress_r := [
		{"line": wash, "extra": ["grill"], "chimney": true, "curtain": Color(0.85, 0.3, 0.35)},
		{"bb": painted, "awning": Color(0.2, 0.55, 0.35), "porch": true, "trim": Color(0.96, 0.95, 0.9)},
		{"ac": true, "extra": ["chair", "planters"], "bars": true},
		{"bb": form, "line": wash2, "chimney": true},
		{"extra": ["trike"], "storm": true, "curtain": Color(0.4, 0.6, 0.85)},
	]
	u = 54.8
	for i in 5:
		var w := 5.2 - 0.2 * float(i % 2)
		var o := {"brick": looks[(i + 3) % looks.size()], "fence": fences[(i + 2) % fences.size()], "lit": [["u"], ["k"], ["k", "c"], ["cu"], ["cu"]][i], "cans": (i + 1) % 3, "aerial": i % 2 == 0, "door": [red_door, cream_door, green_door, blue_door][i % 4]}
		o.merge(dress_r[i])
		row.push_back([u, w, o])
		u += w
	# Which side each back building is on: they pair up, sharing a wall, and
	# each pair shares a height. (Eight were put on the front: an even number,
	# so the pairs line up with the dressed houses' pairs.)
	for i in row.size():
		var h: Array = row[i]
		var o: Dictionary = h[2]
		o["side"] = "r" if i % 2 == 0 else "l"
		o["h"] = 7.0 + 0.3 * float(posmod(floori(i / 2.0), 3) - 1)
		if posmod(i * 7, 5) < 3:          # three roofs in five silver-coated, as the old game's
			o["roof"] = silver
		Park.house_back(p, n, h[0], h[1], BACKS, ALLEY, o)
	# Two yard trees, over the fences.
	Outdoor.tree(p, st, 11.6, -1.0, "d", 1.1, 15.0)
	Outdoor.tree(p, st, 47.5, -1.2, "b", 0.78, 120.0)


# ------------------------------------------------------------------- the night

## The night over it all: the moon's cool light in place of main.gd's sun; the
## trees of the houses' own street, beyond them, showing over the roofs; and
## far off the city's glow on the sky, the moon, the towers on the skyline.
static func _sky(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.24)
	var kinds := ["a", "b", "d", "a", "b", "d", "a"]
	var i := 0
	var u := -64.0
	while u < 104.0:
		Outdoor.tree(p, st, u + 3.0 * Props.rnd(u), -21.0 - 1.5 * Props.rnd(u * 1.7), kinds[i % kinds.size()], 0.95 + 0.25 * Props.rnd(u * 2.3), 37.0 * i)
		u += 10.0 + 6.0 * Props.rnd(u * 3.1)
		i += 1
	Outdoor.backdrop(n, p.pt(20.0, BACKS), [Color(0.34, 0.2, 0.38), Color(0.16, 0.12, 0.26)], p.pt(-120.0, -500.0, 70.0), 3.0)
