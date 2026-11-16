extends RefCounted
## The prisoner tunnel (the civic worker's): the old tunnel under the street
## that prisoners are walked through from the police station's cells to the
## courthouse's lockup and back. Its ends: the steel door in the cell block's
## left wall (plans/police.gd) and the lockup's prisoner door (plans/court.gd).
## Seen from the side like every place, its near wall cut away; one floor, two
## bands:
##
##   the tunnel, left to right: the station's end in the station's own gloss
##   paint (the steel door up to the cells, the intercom, the gun lockers, a
##   laundry cart), a barred gate; the long middle, old brick sweating under
##   its three pipes (the hot water lagged, the fire main, the cold), a yellow
##   line down the floor to walk on: the guard post's window and door, the arch
##   and the steel door of the pump room, the holding cage's bars; a second
##   barred gate; the courthouse's end in its glazed tile (lockers, a camera,
##   the steel door up to the lockup, the phone by it);
##   behind it: the guard post (the officer at his window, the log, the
##   monitors, the phone, a door through to the pump room), the pump room (two
##   pumps, the hot-water tank, the big pipes, a valve, a gauge, the damp, and
##   the man who keeps it all going) and the holding cage (a steel bench, rings
##   to cuff a man to, someone waiting on the court).
##
## The pump room is a second way along the middle: in at its arch and out at
## its door (or through the guard post), round the wall between.
##
## Numbers are metres on the plan (see place.gd): u from the station's end, v
## from the back wall of the rooms behind; the tunnel's far wall is v = BACK.
##
## Invented here (placeholders): the place's name PRISONER TUNNEL and its note
## UNDER THE STREET (main.gd's list); the rooms' names; the use points' labels
## POLICE STATION and COURTHOUSE here and PRISONER TUNNEL on the two doors that
## lead here; the gates' name GATE; the officer's name POST OFFICER; his,
## RELL's and SNOOZY's lines (talk_tunnel_*.json). SECURE ALL FIREARMS is the
## jail's sign (props_prison.gd).

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Service := preload("res://scripts/props_service.gd")
const Prison := preload("res://scripts/props_prison.gd")
const Tun := preload("res://scripts/props_tunnel.gd")

const NAME := "PRISONER TUNNEL"
const W := 36.0
const D := 6.0                       # the tunnel's near wall (cut away)
const BACK := 3.0                    # its far wall: the rooms behind are from v 0 to here
const FACE := BACK + 0.075           # the far wall's face, on the tunnel's side
const H := 2.8                       # the walls
const GATES := [6.0, 30.0]           # the barred gates across the tunnel (u)
const GATE_DOOR := [4.0, 5.0]        # each gate's door (v)
const BARS_H := 2.25                 # the gates' and the cage's bars, under the pipes
const POLICE_DOOR := 1.6             # the steel doors up (u), on the far wall
const COURT_DOOR := 34.4
const POST := [8.0, 12.4]            # the guard post (u)
const PUMPS := [12.4, 23.0]          # the pump room
const CAGE := [23.0, 28.0]           # the holding cage
const WINDOW := [8.6, 10.8]          # the guard post's window onto the tunnel
const POST_DOOR := [11.35, 12.25]
const ARCH := [13.4, 14.6]           # the pump room's arch...
const PUMP_DOOR := [21.35, 22.25]    # ...and its door
const CAGE_DOOR := [25.0, 26.0]
const SIDE_DOOR := [0.9, 1.8]        # the guard post's door through to the pump room (v)
const LAMPS := [2.65, 7.6, 15.6, 20.6, 28.9, 33.1]     # the caged lamps along the far wall (u)
const PIPES := [[2.38, 0.07], [2.56, 0.05], [2.7, 0.04]]     # along the far wall: [y, r] of the hot, the fire main, the cold


static func build(p: Node3D) -> void:
	p.setup(NAME, W, D)
	p.wall_h = H
	# Underground: no sun, little light that falls on everything; the lamps
	# light it (main.gd sets both when he arrives).
	p.ambient = 0.2
	p.sun_energy = 0.0
	var tun: int = p.band()
	var rooms: int = p.band()
	p.arrive = p.pt(POLICE_DOOR, 3.75)

	var concrete := Outdoor.tex("out_concrete", 2.56, Color(0.46, 0.46, 0.44), Color(0.62, 0.6, 0.56))
	var lino := Kit.tex("lino", 1.6, Color(0.5, 0.52, 0.5), true, Color(0.72, 0.72, 0.68))
	var brick := Kit.tex("brick", 1.5, Color(0.36, 0.25, 0.21), true, Color(0.6, 0.48, 0.42))
	var block := Kit.tex("block_plain", 1.2, Color(0.6, 0.62, 0.62), true, Color(0.7, 0.72, 0.72))
	var steel_door := Color(0.36, 0.4, 0.44)

	for r: Array in [["POLICE END", 0.0, GATES[0]], ["TUNNEL", GATES[0], GATES[1]], ["COURT END", GATES[1], W]]:
		var i: int = p.room(r[0], tun, r[1], BACK, r[2], D, concrete)
		p.rooms[i]["cam_max_x"] = p.pt(W - 1.7, 0.0).x       # the camera runs on along it (it sees through the gates' bars)
	p.room("GUARD POST", rooms, POST[0], 0.0, POST[1], BACK, lino)
	p.room("PUMP ROOM", rooms, PUMPS[0], 0.0, PUMPS[1], BACK, concrete)
	p.room("HOLDING CAGE", rooms, CAGE[0], 0.0, CAGE[1], BACK, concrete)

	var ops := {
		"far": [
			{"a": WINDOW[0], "b": WINDOW[1], "kind": "window", "sill": 1.0, "head": 2.0, "frame": Props.IRON},
			{"a": POST_DOOR[0], "b": POST_DOOR[1], "hinge": "b", "swing": -1, "colour": steel_door},      # (into the post, not across the tunnel)
			{"a": ARCH[0], "b": ARCH[1], "kind": "arch", "head": 2.2, "frame": Props.IRON},
			{"a": PUMP_DOOR[0], "b": PUMP_DOOR[1], "hinge": "a", "swing": 1, "colour": steel_door},
		],
		"side": [{"a": SIDE_DOOR[0], "b": SIDE_DOOR[1], "hinge": "a", "swing": -1, "colour": steel_door}],
	}
	# The tunnel's far wall is the rooms' front: whole while he is in the
	# tunnel, a stub while he is in a room (place.gd's cross). What is on its
	# tunnel side is built in its node (`far`), so it goes with it.
	var far: Node3D = p.cross(rooms, BACK, 0.0, CAGE[0], brick, ops["far"])
	p.cross(rooms, BACK, CAGE[1], W, brick)
	p.bars(rooms, true, BACK, CAGE[0], CAGE[1], [CAGE_DOOR], BARS_H)
	p.slab(far, true, BACK, CAGE[0], CAGE[1], BARS_H, H, 0.13, brick)          # the wall over the cage's bars
	p.cross(rooms, 0.0, POST[0], CAGE[1], brick, [], {"back": true})
	p.side(rooms, POST[0], 0.0, BACK, block)
	p.side(rooms, POST[1], 0.0, BACK, block, ops["side"])
	p.side(rooms, CAGE[0], 0.0, BACK, brick)
	p.side(rooms, CAGE[1], 0.0, BACK, brick)
	# Behind the far wall where there is no room, the ground: a dark mass of
	# old brick, so there is no hole beside the rooms when he is in one.
	var earth := Kit.tex("brick", 1.5, Color(0.2, 0.15, 0.13), true, Color(0.32, 0.26, 0.24))
	for run: Array in [[0.0, POST[0] - 0.1], [CAGE[1] + 0.1, W]]:
		Service.gb(p, p.node_of(rooms), run[0], run[1], 0.0, BACK - 0.1, 0.0, H - 0.04, earth)
	p.cross(tun, D, 0.0, W, brick)
	p.side(tun, 0.0, BACK, D, brick)
	p.side(tun, W, BACK, D, brick)
	for u: float in GATES:
		p.bars(tun, false, u, BACK, D, [GATE_DOOR], BARS_H)
		var gate: Node3D = p.doors[p.doors.size() - 1]
		gate.open_name = "OPEN GATE"
		gate.shut_name = "CLOSE GATE"

	var styles := _far_wall(p, far, ops)
	_ends(p, tun, far, styles)
	_floor(p, tun)
	_post(p, rooms, ops)
	_pump_room(p, rooms, ops)
	_cage(p, rooms)
	_lamps(p, rooms, far)
	_people(p, tun, rooms)
	# The ways out: up to the cell block (it comes out of its PRISONER TUNNEL
	# door, plans/police.gd), up to the lockup (plans/court.gd).
	p.use_point(tun, "POLICE STATION", POLICE_DOOR, 3.75, "goto:police", 1.0, 2.0)
	p.use_point(tun, "COURTHOUSE", COURT_DOOR, 3.75, "goto:court", 1.0, 2.0)


## Gloss paint over block (Kit.tex's own texture, tinted), as plans/police.gd's.
static func _paint(c: Color) -> StandardMaterial3D:
	return Kit.tex("block_plain", 1.2, c * 0.92, true, c)


# ---------------------------------------------------------------- the tunnel

## The far wall's tunnel side: the station's paint at its end, the old
## tunnel's grey-green dado on the brick down the middle, the courthouse's
## glazed tile at its end; the three pipes along the top on their brackets, a
## valve, a gauge; the guard post's tray and grille; the fire hose. Returns the
## two ends' dressings (for their end walls).
static func _far_wall(p: Node3D, far: Node3D, ops: Dictionary) -> Array:
	var rubber := Color(0.15, 0.15, 0.17)
	var station := {"lower": _paint(Color(0.5, 0.66, 0.56)), "upper": _paint(Color(0.86, 0.85, 0.76)), "dado": Color(0.26, 0.4, 0.32), "skirt": rubber, "skirt_h": 0.12}
	var old := {"lower": Kit.tex("block_plain", 1.2, Color(0.32, 0.36, 0.34), true, Color(0.46, 0.52, 0.48)), "dado": Color(0.19, 0.21, 0.2), "dado_y": 1.1}
	var court := {
		"lower": Kit.tex("in_tile", 0.6, Color(0.56, 0.68, 0.56), true, Color(0.7, 0.84, 0.7)),       # the lockup's glazed tile
		"upper": Kit.tex("block_plain", 1.2, Color(0.78, 0.76, 0.66), true, Color(0.9, 0.88, 0.78)),
		"dado": Color(0.18, 0.34, 0.26), "dado_y": 1.4, "skirt": Color(0.18, 0.34, 0.26), "skirt_h": 0.15,
	}
	In.dress(p, far, true, BACK, 1.0, 0.075, GATES[0], [], station)
	In.dress(p, far, true, BACK, 1.0, GATES[0], CAGE[0], ops["far"], old)
	In.dress(p, far, true, BACK, 1.0, CAGE[1], GATES[1], [], old)
	In.dress(p, far, true, BACK, 1.0, GATES[1], W - 0.075, [], court)
	# The pipes, into the end walls at both ends.
	var hot := Tun.pipe(p, far, 0.06, W - 0.06, FACE, PIPES[0][0], PIPES[0][1], Tun.LAG, 1.5, true)
	var fire := Tun.pipe(p, far, 0.06, W - 0.06, FACE, PIPES[1][0], PIPES[1][1], Tun.RED, 3.0)
	var cold := Tun.pipe(p, far, 0.06, W - 0.06, FACE, PIPES[2][0], PIPES[2][1], Tun.GREEN, 2.6)
	var under := [[PIPES[0][0] - PIPES[0][1], hot], [PIPES[1][0] - PIPES[1][1], fire], [PIPES[2][0] - PIPES[2][1], cold]]
	Tun.brackets(p, far, [0.9, 3.3, 5.2, 7.1, 9.7, 12.0, 14.2, 16.0, 18.6, 21.0, 23.3, 25.5, 27.7, 29.5, 31.9, 34.4], FACE, 2.28, 2.78, under)
	Tun.valve(p, far, 12.82, fire, PIPES[1][0], PIPES[1][1])
	Tun.valve(p, far, 29.35, cold, PIPES[2][0], PIPES[2][1], Color(0.2, 0.36, 0.62))
	Tun.gauge(p, far, 20.1, hot, PIPES[0][0], PIPES[0][1])
	# The guard post's window: a steel tray through under it, a grille to speak through in the glass.
	Kit.box(far, Vector3(0.56, 0.03, 0.2), p.pt((WINDOW[0] + WINDOW[1]) * 0.5, FACE + 0.1, 1.03), Props.STEEL)
	Kit.cyl(far, 0.07, 0.012, p.pt((WINDOW[0] + WINDOW[1]) * 0.5, BACK + 0.016, 1.52), Props.STEEL, Vector3(90, 0, 0), 14)
	Tun.hose(p, far, 17.7, FACE + 0.009, 1.3)
	return [station, court]


## The two ends: their end walls dressed as their far wall is, the steel door up
## at each (pictures of doors: E at the use point in front goes up), and what
## stands there. The station's end: the intercom by its door, the gun lockers,
## the extinguisher, a laundry cart. The courthouse's: lockers, the phone, a camera.
static func _ends(p: Node3D, b: int, far: Node3D, styles: Array) -> void:
	In.dress(p, b, false, 0.0, 1.0, BACK + 0.075, D - 0.075, [], styles[0])
	In.dress(p, b, false, W, -1.0, BACK + 0.075, D - 0.075, [], styles[1])
	Service.steel_door(Kit.group(far, p.pt(POLICE_DOOR, FACE + 0.009), Vector3.ZERO, "StationDoor"))
	Service.steel_door(Kit.group(far, p.pt(COURT_DOOR, FACE + 0.009), Vector3.ZERO, "CourtDoor"))
	# (built in the tunnel's band, then moved onto the far wall's node: they go with it)
	(Prison.intercom(p, b, POLICE_DOOR + 0.82, FACE + 0.009, 0.0, 1.35) as Node3D).reparent(far, false)
	(Prison.gun_lockers(p, b, 3.75, FACE + 0.009, 0.0) as Node3D).reparent(far, false)
	In.extinguisher(p, b, 0.084, 5.3, 90.0)
	Prison.cart(p, b, 5.0, 3.5, 0.0, 0.9)
	Props.lockers(p, b, 31.4, 3.36, 0.0, 3)
	In.wall_phone(p, far, W - 0.6, FACE + 0.009, 0.0, 1.5)
	In.camera(p, b, W - 0.084, 5.55, 270.0, 2.45)


## The tunnel's floor: the yellow line they walk on, wet under the leaks,
## drains, a wet floor sign; a hand truck of files left by the guard post, file
## boxes by the pump room's door.
static func _floor(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	In.hatch(p, b, W * 0.5, 4.5, 1, W - 0.7, 0.08, 0.0, Color(0.88, 0.72, 0.18))
	Tun.wet(p, n, 16.6, 3.62, 0.42, 12.0)
	Tun.wet(p, n, 28.4, 3.6, 0.3, -20.0)
	Tun.drain(p, n, 12.8, 5.3)
	Tun.drain(p, n, 27.6, 5.3)
	Prison.wet_floor(p, b, 17.35, 3.74, -20.0)
	Service.hand_truck(p, b, 7.15, 3.42, 0.0, Color(0.62, 0.48, 0.3))
	Props.boxes(p, b, 19.95, 3.42, 3)


# ------------------------------------------------------------ the rooms behind

## The guard post: a desk under the window (the officer stands behind it,
## looking out), the monitors on the back wall over his shoulder, lockers, the
## phone, the clock, a spare chair, the strip light.
static func _post(p: Node3D, b: int, ops: Dictionary) -> void:
	var n: Node3D = p.node_of(b)
	var style := {"lower": _paint(Color(0.42, 0.5, 0.58)), "upper": _paint(Color(0.88, 0.87, 0.8)), "dado": Color(0.2, 0.26, 0.32), "skirt": Color(0.15, 0.15, 0.17), "skirt_h": 0.12}
	In.room_walls(p, b, POST[0], 0.0, POST[1], BACK, style, [], [], ops["side"])
	var mid := (WINDOW[0] + WINDOW[1]) * 0.5
	Props.desk(p, b, mid, 2.5, 180.0, Props.OFFICE.darkened(0.15), 1, false, 1.8, 0.7)
	Prison.monitors(p, b, mid, 0.084, 0.0, 3, 2, 1.25)
	Props.lockers(p, b, POST[0] + 0.36, 1.55, 90.0, 2)
	In.wall_phone(p, b, POST[0] + 0.084, 0.75, 90.0, 1.5)
	Props.clock(p, b, 11.55, 0.08, 0.0, 2.3)
	Props.chair(p, b, 10.9, 0.55, 200.0)
	In.wall_strip(p, b, mid, 0.08, 0.0, 1.2, 2.45)
	Kit.omni(n, p.pt(10.2, 1.5, 2.3), In.TUBE, 0.5, 4.2)


## The pump room: the big pipes along its back wall, two pumps feeding the cold
## main, the hot-water tank feeding the hot, the panel, a valve and a gauge;
## the damp, a drain, the mop and bucket; a bare bulb.
static func _pump_room(p: Node3D, b: int, ops: Dictionary) -> void:
	var n: Node3D = p.node_of(b)
	var style := {"lower": Kit.tex("block_plain", 1.2, Color(0.3, 0.33, 0.32), true, Color(0.42, 0.46, 0.44)), "dado": Color(0.19, 0.21, 0.2), "dado_y": 0.9}
	In.room_walls(p, b, PUMPS[0], 0.0, PUMPS[1], BACK, style, [], ops["side"], [])
	var face := 0.075
	var u0: float = PUMPS[0] + 0.06
	var u1: float = PUMPS[1] - 0.06
	var hot := Tun.pipe(p, n, u0, u1, face, 1.98, 0.13, Tun.LAG, 1.2, true)
	var cold := Tun.pipe(p, n, u0, u1, face, 2.38, 0.09, Tun.GREEN, 2.6)
	var fire := Tun.pipe(p, n, u0, u1, face, 2.64, 0.06, Tun.RED, 2.2)
	Tun.brackets(p, n, [13.0, 15.95, 18.5, 22.4], face, 1.8, 2.76, [[1.85, hot], [2.29, cold], [2.58, fire]])
	for u: float in [15.0, 16.9]:
		Tun.pump(p, b, u, 0.75, 0.0, 2.38, 0.75 - cold)
	Tun.tank(p, b, 20.4, 1.0, 0.0, 2.4, 0.5, 1.98, 1.0 - hot)
	Tun.panel(p, n, 13.3, face + 0.009, 1.4, 1.8)
	Tun.valve(p, n, 14.05, cold, 2.38, 0.09)
	Tun.gauge(p, n, 18.0, hot, 1.98, 0.13)
	Tun.wet(p, n, 16.2, 1.95, 0.5, 15.0)
	Tun.drain(p, n, 17.0, 2.15)
	Prison.mop_bucket(p, b, 18.35, 0.55, 10.0)
	In.pendant(p, b, 18.3, 1.6, 2.15, Props.DARK, "bulb", In.WARM, 0.0, H)
	Kit.omni(n, p.pt(18.3, 1.6, 1.95), In.WARM, 0.45, 5.0)


## The holding cage: a steel bench along the back with rings over it to cuff
## a man to, a drain in the floor; its bars are its front (build).
static func _cage(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var style := {"lower": _paint(Color(0.5, 0.56, 0.58)), "upper": _paint(Color(0.8, 0.8, 0.76)), "dado": Color(0.25, 0.28, 0.3), "dado_y": 1.2}
	In.room_walls(p, b, CAGE[0], 0.0, CAGE[1], BACK, style, [], [], [])
	Props.bench(p, b, 25.5, 0.36, 0.0, 3.6, Props.IRON)
	Tun.cuff_rings(p, n, 24.3, 0.084, 0.95, 4, 0.8)
	Tun.drain(p, n, 26.6, 1.9, 0.3)


## The caged lamps along the far wall, over the pipes' brackets' feet; each
## one's light is in the rooms' band (on whichever side of the wall he is, it is on).
static func _lamps(p: Node3D, rooms: int, far: Node3D) -> void:
	for u: float in LAMPS:
		In.sconce(p, far, u, FACE + 0.006, 0.0, "cage", 2.02)
		Kit.omni(p.node_of(rooms), p.pt(u, BACK + 0.5, 1.95), In.WARM, 0.55, 4.6)


static func _people(p: Node3D, tun: int, rooms: int) -> void:
	p.person(rooms, "cop", (WINDOW[0] + WINDOW[1]) * 0.5, 1.8, {"name": "POST OFFICER", "face": "bored", "talk": "talk_tunnel_post.json"})
	p.person(rooms, "snoozy", 18.35, 1.4, {"name": "SNOOZY", "face": "content", "talk": "talk_tunnel_pump.json"})      # back off the way through, by his bucket
	p.person(rooms, "rell", 24.2, 2.05, {"name": "RELL", "face": "nervous", "talk": "talk_tunnel_cage.json"})
	p.person(tun, "cop", 32.2, 5.0, {"face": "focused"})          # the court's deputy, waiting on the next one
