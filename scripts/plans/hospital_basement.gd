extends RefCounted
## The hospital's basement (the civic worker's): built by plans/hospital.gd, not
## a place of its own. The service lift in the supply room's back wall goes down
## (LIFT DOWN; LIFT UP comes back); the stair at the far end of the basement
## comes up by the ambulance ramp, out on the pavement at its mouth (UP TO THE
## RAMP; DOWN TO THE BASEMENT there goes back down). Down here, on a level of its
## own (-1), drawn BU to the right of the hospital on the plan, two bands:
##
##   the service corridor, the whole width, old pipes along its far wall, a
##   blue line down its floor: the boiler room's arch and door, the morgue's
##   double doors, the lift lobby open off it, the laundry's door and its
##   hatch; at its right end the stair up (the EXIT over its foot);
##   behind it: the boiler room (the boiler in the middle, a way round it and
##   someone keeping out of sight behind it), the morgue (the cold store's
##   doors, the steel table, the drain at its foot, the attendant's desk, one
##   under a sheet waiting for a drawer), the lift lobby (the lift's doors, a
##   trolley) and the laundry (washers, driers, the chute the linen comes
##   down, the folding table, clean linen on the shelves).
##
## Numbers are the hospital's plan (u from its left wall, v from its back wall;
## see hospital.gd), BU added to u down here. The lift is under itself: at u
## LIFT on both floors. Invented here (placeholders): the rooms' names (SERVICE
## CORRIDOR, BOILER ROOM, MORGUE, LIFT LOBBY, LAUNDRY), the labels LIFT DOWN,
## LIFT UP, UP TO THE RAMP and DOWN TO THE BASEMENT, the plates MORGUE and
## LAUNDRY, the name ATTENDANT, and the lines in talk_basement_*.json.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Service := preload("res://scripts/props_service.gd")
const Prison := preload("res://scripts/props_prison.gd")
const Tun := preload("res://scripts/props_tunnel.gd")
const Bm := preload("res://scripts/props_basement.gd")

const BU := 40.0                     # the basement is drawn this far to the right on the plan
const FAR := 6.5                     # the corridor's far wall: the rooms are from v 0 to here
const FACE := FAR + 0.075            # its face on the corridor's side
const NEAR := 9.5                    # the corridor's near wall (cut away)
const W := 26.0                      # the corridor's length
const END := 22.6                    # the rooms end here; behind the stair, the ground
const BOILER := [0.0, 6.5]
const MORGUE := [6.5, 13.2]
const LOBBY := [13.2, 16.6]
const LAUNDRY := [16.6, 22.6]
const LIFT := 14.3                   # the lift's middle (u), on both floors
const SIDE_DOOR := [1.5, 2.4]        # the morgue's door through to the lift lobby (v)
const STAIR := 24.12                 # the stair's middle (u): its foot at the left, 3.6 long
const RAMP_U := 21.0                 # where the pavement meets the ramp's mouth (hospital.gd's _street)
const H := 2.9
const TUBE_LIGHT := Color(0.96, 0.99, 1.0)


static func build(p: Node3D, st: int, supply: int) -> void:
	# Up here: the lift's doors in the supply room's back wall, and the way down
	# at the ramp's mouth on the pavement.
	Bm.lift(p, p.node_of(supply), LIFT, 0.075, 1)
	p.portal(supply, "LIFT DOWN", LIFT, 0.75, BU + LIFT, 0.85)
	p.portal(st, "DOWN TO THE BASEMENT", RAMP_U, 18.55, BU + 21.75, 7.35)

	var cor: int = p.band(-1)
	var rms: int = p.band(-1)
	var lino := Kit.tex("lino", 1.6, Color(0.56, 0.58, 0.55), true, Color(0.78, 0.8, 0.76))
	var concrete := Outdoor.tex("out_concrete", 2.56, Color(0.46, 0.46, 0.44), Color(0.62, 0.6, 0.56))
	var terrazzo := Kit.tex("in_terrazzo", 1.4, Color(0.66, 0.68, 0.68), true, Color(0.82, 0.84, 0.84))
	var lino_blue := Kit.tex("lino", 1.6, Color(0.5, 0.58, 0.64), true, Color(0.7, 0.82, 0.9))
	var block := _block(Color(0.74, 0.75, 0.72))
	var frame := Color(0.5, 0.54, 0.56)
	var ward_door := Color(0.6, 0.7, 0.72)
	var steel_door := Color(0.36, 0.4, 0.44)

	p.room("SERVICE CORRIDOR", cor, BU, FAR, BU + W, NEAR, lino)
	p.room("BOILER ROOM", rms, BU + BOILER[0], 0.0, BU + BOILER[1], FAR, concrete)
	p.room("MORGUE", rms, BU + MORGUE[0], 0.0, BU + MORGUE[1], FAR, terrazzo, {"light": TUBE_LIGHT, "energy": 0.55})
	p.room("LIFT LOBBY", rms, BU + LOBBY[0], 0.0, BU + LOBBY[1], FAR, lino)
	p.room("LAUNDRY", rms, BU + LAUNDRY[0], 0.0, BU + LAUNDRY[1], FAR, lino_blue, {"light": TUBE_LIGHT, "energy": 0.5})

	var ops := {
		"far": [
			{"a": BU + 1.2, "b": BU + 2.6, "kind": "arch", "head": 2.2, "frame": Props.IRON},
			{"a": BU + 4.6, "b": BU + 5.5, "hinge": "b", "colour": steel_door, "frame": Props.IRON},
			{"a": BU + 8.9, "b": BU + 10.7, "kind": "double", "head": 2.2, "colour": ward_door, "frame": frame},
			{"a": BU + 13.7, "b": BU + 16.1, "kind": "arch", "head": 2.4, "frame": frame},
			{"a": BU + 17.3, "b": BU + 18.2, "hinge": "a", "colour": ward_door, "frame": frame},
			{"a": BU + 19.4, "b": BU + 21.4, "kind": "window", "sill": 1.0, "head": 1.95, "frame": Props.STEEL},
		],
		"side": [{"a": SIDE_DOOR[0], "b": SIDE_DOOR[1], "hinge": "a", "swing": 1, "colour": ward_door, "frame": frame}],
	}
	# The corridor's far wall is the rooms' front: whole while he is in the
	# corridor, a stub while he is in a room. What is on its corridor side is
	# built in its node (`far`), so it goes with it. Past the rooms, behind the
	# stair, it is the corridor's own back wall.
	var far: Node3D = p.cross(rms, FAR, BU, BU + END, block, ops["far"])
	p.cross(cor, FAR, BU + END, BU + W, block, [], {"back": true})
	p.cross(rms, 0.0, BU, BU + END, block, [], {"back": true})
	p.side(rms, BU, 0.0, FAR, block)
	p.side(rms, BU + BOILER[1], 0.0, FAR, block)
	p.side(rms, BU + MORGUE[1], 0.0, FAR, block, ops["side"])
	p.side(rms, BU + LOBBY[1], 0.0, FAR, block)
	p.side(rms, BU + END, 0.0, FAR, block)
	p.cross(cor, NEAR, BU, BU + W, block)
	p.side(cor, BU, FAR, NEAR, block)
	p.side(cor, BU + W, FAR, NEAR, block)
	# Behind the stair, where there is no room: the ground.
	var earth := Kit.tex("brick", 1.5, Color(0.2, 0.15, 0.13), true, Color(0.32, 0.26, 0.24))
	Service.gb(p, p.node_of(rms), BU + END + 0.1, BU + W, 0.0, FAR - 0.1, 0.0, H - 0.04, earth)

	_corridor(p, cor, far, ops)
	_boiler(p, rms)
	_morgue(p, rms, ops)
	_lobby(p, rms, ops)
	_laundry(p, rms)
	_people(p, cor, rms)
	p.portal(rms, "LIFT UP", BU + LIFT, 0.75, LIFT, 0.85)
	p.portal(cor, "UP TO THE RAMP", BU + 21.75, 7.3, RAMP_U, 18.6)


## Painted block in one colour (as hospital.gd's).
static func _block(c: Color) -> Material:
	return Kit.tex("block_plain", 1.2, c, true, c)


## The corridor and the lift lobby: green paint to a grey bumper rail, cream
## over it. `rail` is how far the rail stands off the wall.
static func _green(rail := 0.05) -> Dictionary:
	return {"lower": _block(Color(0.5, 0.6, 0.56)), "upper": _block(Color(0.9, 0.88, 0.8)),
			"dado": Color(0.42, 0.44, 0.47), "dado_y": 0.9, "dado_h": 0.14, "dado_d": rail,
			"skirt": Color(0.25, 0.27, 0.28), "skirt_h": 0.12}


## The corridor: the old pipes along the top of the far wall on their
## brackets, turning up into the ceiling before the stair; the plates over the
## morgue's and the laundry's doors, the fire hose, an extinguisher; a trolley
## and carts left along the wall, the yellow bin, the mop; the blue line down
## the floor, two drains; the stair up at the end, the EXIT over its foot;
## three strip lights.
static func _corridor(p: Node3D, b: int, far: Node3D, ops: Dictionary) -> void:
	var n: Node3D = p.node_of(b)
	var style := _green()
	In.dress(p, far, true, FAR, 1.0, BU + 0.075, BU + END, ops["far"], style)
	In.dress(p, b, true, FAR, 1.0, BU + END, BU + W - 0.075, [], style)
	In.dress(p, b, false, BU, 1.0, FAR + 0.075, NEAR - 0.075, [], style)
	In.dress(p, b, false, BU + W, -1.0, FAR + 0.075, NEAR - 0.075, [], style)
	# The pipes, from the left end wall to a bend up into the ceiling short of the stair.
	var u1 := BU + END - 0.2
	var hot := Tun.pipe(p, far, BU + 0.06, u1, FACE, 2.72, 0.07, Tun.LAG, 1.5, true)
	var cold := Tun.pipe(p, far, BU + 0.06, u1, FACE, 2.55, 0.04, Tun.GREEN, 2.6)
	for pipe: Array in [[hot, 2.72, 0.07, Tun.LAG], [cold, 2.55, 0.04, Tun.GREEN]]:
		var y: float = pipe[1]
		var r: float = pipe[2]
		Kit.ball(far, r + 0.004, p.pt(u1, pipe[0], y), pipe[3], 10)
		Kit.cyl(far, r, H - y, p.pt(u1, pipe[0], (y + H) * 0.5), pipe[3], Vector3.ZERO, 12)
	var at := [0.6, 3.4, 6.2, 7.9, 11.4, 13.3, 16.6, 18.8, 22.0].map(func(x: float) -> float: return BU + x)
	Tun.brackets(p, far, at, FACE, 2.45, 2.85, [[2.65, hot], [2.51, cold]])
	Tun.valve(p, far, BU + 12.3, cold, 2.55, 0.04, Color(0.2, 0.36, 0.62))
	Tun.gauge(p, far, BU + 7.2, hot, 2.72, 0.07)
	Bm.plate(p, far, "MORGUE", BU + 9.8, FACE + 0.009, 2.38, 0.9)
	Bm.plate(p, far, "LAUNDRY", BU + 17.75, FACE + 0.009, 2.38, 0.9)
	Tun.hose(p, far, BU + 3.1, FACE + 0.009, 1.45)
	In.extinguisher(p, far, BU + 18.8, FACE + 0.01, 0.0, 1.08)
	In.sconce(p, far, BU + 22.1, FACE, 0.0, "exit", 2.3)
	# Along the far wall.
	Props.gurney(p, b, BU + 6.6, 7.06, 90.0, Bm.SHEET, true, 0.85, 1.9)
	Prison.cart(p, b, BU + 3.95, 6.95, 0.0, 0.9, Bm.SHEET)
	Prison.mop_bucket(p, b, BU + 11.25, 6.9, 15.0)
	Prison.cart(p, b, BU + 12.65, 6.95, 0.0, 0.9, Color(0.72, 0.82, 0.92))
	Service.wheelie_bin(p, b, BU + 16.7, 7.0, 0.0, Color(0.92, 0.76, 0.16))
	# The floor: the blue line, the drains, wet where the mop has been.
	In.mat(p, b, BU + 11.4, 8.55, 21.0, 0.07, Color(0.22, 0.4, 0.74))
	Tun.drain(p, n, BU + 8.2, 8.95, 0.32)
	Tun.drain(p, n, BU + 15.1, 8.95, 0.32)
	Tun.wet(p, n, BU + 11.3, 8.05, 0.36, 20.0)
	# The stair up to the ramp: its foot at the left, by the EXIT.
	Props.stairs(p, b, BU + STAIR, 7.125, 270.0, 1.1, 3.6, H, Color(0.6, 0.6, 0.58), H)
	# The strip lights; their lamps in the corridor's band.
	for u: float in [4.5, 12.0, 19.8]:
		In.strip_light(p, b, BU + u, 8.0, 0.0, 1.3, 2.5, In.TUBE, H)
		Kit.omni(n, p.pt(BU + u, 8.0, 2.35), TUBE_LIGHT, 0.5, 6.0)


## The boiler room: soot-dark paint to a black rail, old brick over it; the
## boiler in the middle (a way round it), a pump against the back, the pipes
## along the back wall, the panel; a chair in the corner behind the boiler; a
## bare bulb.
static func _boiler(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.28, 0.23), true, Color(0.66, 0.52, 0.46))
	var style := {"lower": _block(Color(0.34, 0.36, 0.35)), "upper": brick, "dado": Color(0.16, 0.16, 0.17), "dado_y": 1.2}
	In.room_walls(p, b, BU + BOILER[0], 0.0, BU + BOILER[1], FAR, style, [], [], [])
	Bm.boiler(p, b, BU + 3.2, 2.9, 0.0, H)
	var face := 0.075
	var hot := Tun.pipe(p, n, BU + 0.06, BU + BOILER[1] - 0.06, face, 2.5, 0.08, Tun.LAG, 1.2, true)
	var fire := Tun.pipe(p, n, BU + 0.06, BU + BOILER[1] - 0.06, face, 2.72, 0.05, Tun.RED, 2.0)
	Tun.brackets(p, n, [BU + 0.5, BU + 2.6, BU + 4.4, BU + 6.0], face, 2.3, 2.85, [[2.42, hot], [2.67, fire]])
	Tun.pump(p, b, BU + 1.0, 0.75, 0.0, 2.5, 0.75 - hot)
	Tun.panel(p, n, BU + 3.4, face + 0.009, 1.4, 2.3)
	Tun.gauge(p, n, BU + 4.9, hot, 2.5, 0.08)
	Props.chair(p, b, BU + 5.75, 0.62, 200.0, Color(0.42, 0.3, 0.22))
	Tun.drain(p, n, BU + 5.6, 4.9, 0.32)
	Tun.wet(p, n, BU + 4.9, 4.5, 0.34, -15.0)
	In.pendant(p, b, BU + 3.3, 4.7, 2.2, Props.DARK, "bulb", In.WARM, 0.5, H)


## The morgue: white tile to a grey-blue rail, pale green over it; the cold
## store's doors across the back, the steel table in the middle with the drain
## at its foot and the lamp over it, the counter and its sink down the left,
## one under a sheet waiting for a drawer, the attendant's desk at the right
## with the notices over it, the clock, the phone.
static func _morgue(p: Node3D, b: int, ops: Dictionary) -> void:
	var n: Node3D = p.node_of(b)
	var style := {"lower": Kit.tex("in_tile", 0.6, Color(0.82, 0.86, 0.86), true, Color(0.95, 0.98, 0.98)), "upper": _block(Color(0.8, 0.86, 0.84)),
			"dado": Color(0.32, 0.42, 0.46), "dado_y": 1.8, "skirt": Color(0.3, 0.36, 0.38), "skirt_h": 0.12}
	In.room_walls(p, b, BU + MORGUE[0], 0.0, BU + MORGUE[1], FAR, style, [], [], ops["side"])
	Bm.drawers(p, b, BU + 9.85, 0.325, 4, 3)
	Bm.steel_table(p, b, BU + 9.85, 3.0, 0.0)
	Tun.drain(p, n, BU + 11.3, 3.0, 0.3)
	Props.exam_lamp(p, b, BU + 9.4, 3.95, 180.0)
	In.strip_light(p, b, BU + 9.85, 3.0, 0.0, 1.3, 2.55, In.TUBE, H)
	var counter := Props.counter(p, b, BU + 6.885, 1.85, 90.0, 1.6, 0.62, 0.9, Bm.STAINLESS.darkened(0.2), Bm.STAINLESS)
	Kit.box(counter, Vector3(0.5, 0.008, 0.38), Vector3(-0.2, 0.904, 0.02), Props.IRON)          # the sink in it
	Kit.tube(counter, Vector3(-0.2, 0.9, -0.25), Vector3(-0.2, 1.22, -0.25), 0.014, Bm.STAINLESS.darkened(0.1))
	Kit.tube(counter, Vector3(-0.2, 1.22, -0.25), Vector3(-0.2, 1.22, -0.06), 0.014, Bm.STAINLESS.darkened(0.1))
	Kit.bevel_block(counter, Vector3(0.24, 0.12, 0.18), Vector3(0.45, 0.9, -0.05), Color(0.3, 0.32, 0.36), 0.02)      # a box of gloves
	Bm.covered(p, b, BU + 7.55, 4.5, 0.0)
	Props.desk(p, b, BU + 12.75, 4.75, 270.0, Props.OFFICE, 2, false, 1.3, 0.7)
	Props.chair(p, b, BU + 12.0, 4.75, 90.0)
	Props.board(p, b, BU + 13.12, 4.75, 270.0, 1.0, "notices", 0.7, 1.65)
	Props.clock(p, b, BU + 12.4, 0.08, 0.0, 2.35)
	In.wall_phone(p, b, BU + 6.585, 4.0, 90.0, 1.5)


## The lift lobby: the corridor's paint (its rail kept behind the lift's
## frame); the lift's doors in the back wall, a trolley left against the right
## wall, the extinguisher, a strip light.
static func _lobby(p: Node3D, b: int, ops: Dictionary) -> void:
	In.room_walls(p, b, BU + LOBBY[0], 0.0, BU + LOBBY[1], FAR, _green(0.03), [], ops["side"], [])
	Bm.lift(p, p.node_of(b), BU + LIFT, 0.075, 0)
	Props.gurney(p, b, BU + 15.95, 3.5, 0.0, Bm.SHEET, true)
	In.extinguisher(p, b, BU + 13.285, 4.8, 90.0, 1.08)
	In.wall_strip(p, b, BU + 15.65, 0.08, 0.0, 0.9, 2.6)


## The laundry: pale blue paint to a navy rail, white over it; two washers and
## two driers across the back, the chute down in the corner into a cart, the
## folding table with the clean stacks, the shelves of linen down the left,
## another cart by the right wall.
static func _laundry(p: Node3D, b: int) -> void:
	var style := {"lower": _block(Color(0.6, 0.68, 0.76)), "upper": _block(Color(0.92, 0.92, 0.88)), "dado": Color(0.24, 0.32, 0.46), "dado_y": 1.2}
	In.room_walls(p, b, BU + LAUNDRY[0], 0.0, BU + LAUNDRY[1], FAR, style, [], [], [])
	var k := 0
	for u: float in [17.32, 18.38, 19.44, 20.5]:
		Bm.machine(p, b, BU + u, 0.5, 0.0, k >= 2)
		k += 1
	Bm.chute(p, p.node_of(b), BU + 21.75, 0.075, 1.45, H)
	Prison.cart(p, b, BU + 21.75, 0.55, 0.0, 0.9, Color(0.72, 0.82, 0.92))
	var table := Props.table(p, b, BU + 19.6, 3.4, 0.0, 1.8, 0.8, Color(0.82, 0.8, 0.74), 0.9)
	Bm.folded(table, 0.9, -0.85, 0.85, 3.0)
	Bm.linen(p, b, BU + 16.9, 3.4, 90.0, 1.8)
	Prison.cart(p, b, BU + 21.8, 3.6, 270.0, 0.9, Bm.SHEET)
	In.strip_light(p, b, BU + 19.6, 3.4, 0.0, 1.3, 2.55, In.TUBE, H)


static func _people(p: Node3D, cor: int, rms: int) -> void:
	p.person(rms, "nurse", BU + 11.45, 4.05, {"name": "ATTENDANT", "face": "bored", "talk": "talk_basement_morgue.json"})
	p.person(rms, "nia", BU + 20.98, 3.45, {"name": "NIA", "face": "content", "talk": "talk_basement_laundry.json"})     # at the folding table's end (behind it, the stacks were over his face as they talked)
	p.person(rms, "vic", BU + 5.2, 1.15, {"name": "VIC", "face": "smug", "talk": "talk_basement_boiler.json"})      # behind the boiler
	p.person(cor, "kesha", BU + 11.85, 7.55, {"face": "bored"})          # by her mop
