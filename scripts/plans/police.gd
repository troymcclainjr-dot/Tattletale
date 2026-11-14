extends RefCounted
## The police station: Pen Lucy Precinct. An old city station house that nobody
## has spent money on: painted block walls, lino, mismatched government desks.
## 16 x 22 m inside, one floor, four bands from the street back:
##
##   lobby | front desk      the public gets no further than this
##   squad room | captain
##   interview | booking | evidence
##   cells and the drunk tank | sally port      prisoners come in at the back
##
## Numbers are metres on the plan (see place.gd and the layouts folder): u from
## the left wall, v from the back wall; the street is at v = 22.
##
## Each part of the station is painted its own way, the way old station houses
## are: gloss paint to dado height in a dark colour, a lighter one above, a
## painted stripe between and a rubber skirting. Lobby and desk navy and gold,
## squad room institutional green, the captain's oak and green stripe, interview
## slate and acoustic tile, booking teal, the cells pale jail green, the sally
## port safety stripes (props_in.gd).

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")


static func build(p: Node3D) -> void:
	p.setup("POLICE STATION", 16.0, 22.0)
	var drab := Kit.tex("block_plain", 1.2, Color(0.76, 0.74, 0.7), true, Color(0.86, 0.84, 0.79))        # institutional beige
	var grey := Kit.tex("block_plain", 1.2, Color(0.62, 0.64, 0.68), true, Color(0.68, 0.71, 0.78))        # the secure end: colder
	var lino := Kit.tex("lino", 1.6, Color(0.6, 0.66, 0.6), true, Color(0.86, 0.84, 0.74))
	var lino_dark := Kit.tex("lino", 1.6, Color(0.45, 0.5, 0.48), true, Color(0.6, 0.62, 0.6))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var carpet := Kit.tex("carpet", 2.0, Color(0.25, 0.3, 0.4), true, Color(0.5, 0.62, 0.9))
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.9, 0.82, 0.8))
	var tube := Color(0.97, 0.98, 0.94)      # strip-light white
	var steel_door := Color(0.36, 0.4, 0.44)

	var st: int = p.street(-4.0, 20.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	var b4: int = p.band()
	p.arrive = p.pt(5.1, 23.2)

	p.room("PUBLIC LOBBY", b1, 0, 17, 10.5, 22, lino, {"light": tube})
	p.room("FRONT DESK", b1, 10.5, 17, 16, 22, lino, {"light": tube})
	p.room("SQUAD ROOM", b2, 0, 11, 12, 17, lino, {"light": tube, "energy": 0.6})
	p.room("CAPTAIN", b2, 12, 11, 16, 17, carpet, {"light": Color(1.0, 0.9, 0.75)})
	p.room("INTERVIEW", b3, 0, 5, 4, 11, concrete, {"light": Color(1.0, 0.85, 0.6), "energy": 0.7})
	p.room("BOOKING", b3, 4, 5, 11, 11, lino_dark, {"light": tube})
	p.room("EVIDENCE", b3, 11, 5, 16, 11, concrete, {"light": tube, "energy": 0.4})
	p.room("CELL BLOCK", b4, 0, 2.6, 12, 5, concrete, {"light": tube, "energy": 0.45})
	p.room("CELL 1", b4, 0, 0, 3, 2.6, concrete)
	p.room("CELL 2", b4, 3, 0, 6, 2.6, concrete)
	p.room("CELL 3", b4, 6, 0, 9, 2.6, concrete)
	p.room("DRUNK TANK", b4, 9, 0, 12, 2.6, concrete)
	p.room("SALLY PORT", b4, 12, 0, 16, 5, concrete, {"light": tube, "energy": 0.4})

	# ---- walls. Each `cross` is the wall in FRONT of its band. The openings
	# are kept by name: the paint and trim stop at each (_walls).
	var ops := {
		"front": [
			{"a": 0.8, "b": 3.0, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "frame": Color(0.2, 0.22, 0.26)},
			{"a": 4.2, "b": 6.0, "kind": "double", "head": 2.2, "colour": Color(0.2, 0.26, 0.4), "frame": Color(0.2, 0.22, 0.26)},
			{"a": 7.2, "b": 9.4, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "frame": Color(0.2, 0.22, 0.26)},
			{"a": 12.2, "b": 15.0, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "blinds": true, "frame": Color(0.2, 0.22, 0.26)},
		],
		"glass": [{"a": 18.4, "b": 20.7, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.STEEL}],
		"gate": [
			{"a": 8.2, "b": 9.1, "colour": steel_door, "name": "GATE"},
			{"a": 10.9, "b": 11.8, "colour": steel_door},
		],
		"captain": [
			{"a": 11.8, "b": 14.6, "kind": "window", "sill": 0.95, "head": 2.1, "blinds": true},
			{"a": 15.2, "b": 16.1, "hinge": "a", "swing": 1, "colour": Color(0.42, 0.3, 0.2)},
		],
		"back2": [
			{"a": 0.6, "b": 1.5, "colour": steel_door},
			{"a": 6.0, "b": 6.9, "colour": steel_door},
		],
		"mirror": [{"a": 6.3, "b": 8.6, "kind": "window", "sill": 0.95, "head": 1.9, "pane": Color(0.1, 0.12, 0.18, 0.93), "frame": Props.IRON}],    # the one-way mirror
		"cage": [
			{"a": 7.5, "b": 8.9, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.IRON},     # the property window
			{"a": 9.6, "b": 10.5, "hinge": "a", "swing": 1, "colour": steel_door, "name": "CAGE"},
		],
		"back3": [{"a": 7.6, "b": 8.5, "colour": steel_door}],
		"port": [{"a": 12.7, "b": 15.3, "kind": "window", "sill": 0.0, "head": 2.7, "pane": Color(0, 0, 0, 0), "frame": Props.IRON}],
		"turn": [{"a": 3.4, "b": 4.3, "hinge": "a", "swing": 1, "colour": steel_door}],
	}
	# The front is two floors: the station's offices upstairs are not ours to visit.
	var front: Node3D = p.cross(b1, 22.0, 0, 16, brick, ops["front"], {"h": 7.4})
	p.side(b1, 0.0, 17, 22, drab)
	p.side(b1, 16.0, 17, 22, drab)
	p.side(b1, 10.5, 17, 22, drab, ops["glass"])

	p.cross(b2, 17.0, 0, 16, drab, ops["gate"])
	p.side(b2, 0.0, 11, 17, drab)
	p.side(b2, 16.0, 11, 17, drab)
	p.side(b2, 12.0, 11, 17, drab, ops["captain"])

	p.cross(b3, 11.0, 0, 16, grey, ops["back2"])
	p.side(b3, 0.0, 5, 11, grey)
	p.side(b3, 16.0, 5, 11, grey)
	p.side(b3, 4.0, 5, 11, grey, ops["mirror"])
	p.side(b3, 11.0, 5, 11, grey, ops["cage"])

	p.cross(b4, 5.0, 0, 16, grey, ops["back3"])
	# The back wall. The sally port's roll-up door is up, with the prisoner van backed half in.
	p.cross(b4, 0.0, 0, 16, grey, ops["port"], {"back": true})
	p.side(b4, 0.0, 0, 5, grey)
	p.side(b4, 16.0, 0, 5, grey)
	p.side(b4, 12.0, 0, 5, grey, ops["turn"])
	for u in [3.0, 6.0, 9.0]:
		p.side(b4, u, 0, 2.6, grey)
	p.bars(b4, true, 2.6, 0.0, 12.0, [[1.0, 2.0], [4.0, 5.0], [7.0, 8.0], [10.0, 11.0]])

	_street(p, st, front)
	_walls(p, b1, b2, b3, b4, ops)
	_lobby(p, b1)
	_squad(p, b2)
	_booking(p, b3)
	_cells(p, b4)


## Gloss paint over the block (Kit.tex's own texture, tinted).
static func _paint(c: Color) -> StandardMaterial3D:
	return Kit.tex("block_plain", 1.2, c * 0.92, true, c)


## Each room's walls painted and trimmed, its floor edged, its lights on the walls.
static func _walls(p: Node3D, b1: int, b2: int, b3: int, b4: int, ops: Dictionary) -> void:
	var rubber := Color(0.15, 0.15, 0.17)
	var lobby := {"lower": _paint(Color(0.34, 0.42, 0.74)), "dado": Color(0.88, 0.7, 0.24), "skirt": rubber, "skirt_h": 0.12}
	var squad := {"lower": _paint(Color(0.5, 0.7, 0.54)), "upper": _paint(Color(0.92, 0.95, 0.84)), "dado": Color(0.2, 0.38, 0.27), "skirt": rubber, "skirt_h": 0.12}
	var oak := Color(0.36, 0.22, 0.13)
	var captain := {
		"lower": Kit.tex("in_panel", 0.9, Color(0.55, 0.36, 0.22), true, Color(0.78, 0.52, 0.32)),
		"upper": Kit.tex("in_stripe", 0.8, Color(0.3, 0.46, 0.36), true, Color(0.46, 0.66, 0.52)),
		"dado": oak, "skirt": oak, "surround": Color(0.5, 0.32, 0.19),
	}
	var interview := {"lower": _paint(Color(0.4, 0.42, 0.47)), "upper": Kit.tex("in_acoustic", 1.2, Color(0.8, 0.8, 0.76), true, Color(0.88, 0.88, 0.82)), "dado": Color(0.2, 0.21, 0.24), "skirt": rubber, "skirt_h": 0.12}
	var booking := {"lower": _paint(Color(0.34, 0.62, 0.64)), "upper": _paint(Color(0.9, 0.9, 0.86)), "dado": Color(0.12, 0.2, 0.22), "skirt": rubber, "skirt_h": 0.12}
	var evidence := {"lower": _paint(Color(0.52, 0.55, 0.6)), "dado": Color(0.94, 0.74, 0.16), "skirt": rubber, "skirt_h": 0.12}
	var block := {"lower": _paint(Color(0.56, 0.74, 0.63)), "upper": _paint(Color(0.94, 0.93, 0.83)), "dado": Color(0.28, 0.44, 0.35), "skirt": rubber, "skirt_h": 0.12}
	var cell := {"lower": _paint(Color(0.5, 0.64, 0.56)), "upper": _paint(Color(0.86, 0.85, 0.75)), "dado": Color(0.28, 0.4, 0.33)}
	var port := {"lower": Kit.tex("in_hazard", 0.8, Color(0.9, 0.75, 0.2)), "dado_y": 0.42, "dado": Color(0.18, 0.18, 0.2)}

	In.room_walls(p, b1, 0, 17, 10.5, 22, lobby, ops["gate"], [], ops["glass"])
	In.room_walls(p, b1, 10.5, 17, 16, 22, lobby, ops["gate"], ops["glass"], [])
	In.room_walls(p, b2, 0, 11, 12, 17, squad, ops["back2"], [], ops["captain"])
	In.room_walls(p, b2, 12, 11, 16, 17, captain, ops["back2"], ops["captain"], [])
	In.room_walls(p, b3, 0, 5, 4, 11, interview, ops["back3"], [], ops["mirror"])
	In.room_walls(p, b3, 4, 5, 11, 11, booking, ops["back3"], ops["mirror"], ops["cage"])
	In.room_walls(p, b3, 11, 5, 16, 11, evidence, ops["back3"], ops["cage"], [])
	for i in 4:
		In.room_walls(p, b4, i * 3.0, 0, i * 3.0 + 3.0, 2.6, cell, [], [], [])
	In.dress(p, b4, false, 0.0, 1.0, 2.6, 4.925, [], block)
	In.dress(p, b4, false, 12.0, -1.0, 2.6, 4.925, ops["turn"], block)
	In.room_walls(p, b4, 12, 0, 16, 5, port, ops["port"], ops["turn"], [])

	# Floors: a dark border round the public rooms, a mat inside the doors, a
	# line to stand behind in front of the cells.
	In.border(p, b1, 0, 17, 10.5, 22, Color(0.28, 0.31, 0.42), 0.25)
	In.mat(p, b1, 5.1, 21.32, 2.3, 0.95, Color(0.13, 0.13, 0.14), Color(0.24, 0.24, 0.26))
	In.border(p, b2, 0, 11, 12, 17, Color(0.26, 0.4, 0.31), 0.25)
	In.hatch(p, b4, 6.0, 3.12, 1, 11.6, 0.07, 0.0, Color(0.95, 0.78, 0.18))

	# Lights: fluorescent fittings high on the back walls, cages in the cells.
	In.wall_strip(p, b1, 5.5, 17.08, 0.0, 1.2, 2.62)
	In.wall_strip(p, b1, 14.6, 17.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b2, 3.7, 11.08, 0.0, 1.4, 2.62)
	In.wall_strip(p, b2, 9.1, 11.08, 0.0, 1.2, 2.62)
	In.wall_strip(p, b3, 9.6, 5.08, 0.0, 1.1, 2.6)
	In.wall_strip(p, b3, 13.6, 5.08, 0.0, 1.2, 2.6)
	for i in 4:
		In.sconce(p, b4, i * 3.0 + 0.55, 0.08, 0.0, "cage", 2.5)      # up over the bars' top rail, well clear of the cell's number
	In.sconce(p, b4, 0.08, 4.62, 90.0, "cage", 2.2)
	In.sconce(p, b4, 12.33, 0.08, 0.0, "cage", 2.3)
	In.sconce(p, b4, 15.67, 0.08, 0.0, "cage", 2.3)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	# The station's own front: a granite base, a stone belt course between the
	# floors, stone quoins at the corners, dressings round the doors and windows,
	# the POLICE panel and two blue globes; upstairs a row of windows, a
	# bracketed cornice, a parapet and the flag.
	var stone := Color(0.74, 0.72, 0.66)
	var dressed := Color(0.86, 0.84, 0.78)
	var granite := Kit.tex("in_ashlar", 1.0, Color(0.56, 0.56, 0.58), true, Color(0.64, 0.64, 0.68))
	var f := 22.075        # the street face of the front wall
	p.slab(front, true, 22.0, -0.05, 16.05, 4.0, 4.22, 0.3, stone)
	for run: Array in [[-0.02, 4.14], [6.06, 16.02]]:       # the granite base stops either side of the doors
		p.slab(front, true, 22.06, run[0], run[1], 0.0, 0.5, 0.1, granite)
	p.slab(front, true, 22.1, 3.6, 6.6, 2.55, 3.45, 0.06, Color(0.14, 0.2, 0.4))
	Props.words(front, "POLICE", p.pt(5.1, 22.135, 3.07), 0.5, Color(0.93, 0.9, 0.78))
	Props.words(front, "PEN LUCY PRECINCT", p.pt(5.1, 22.135, 2.68), 0.11, Color(0.93, 0.9, 0.78), 0.0, false)
	for u in [3.85, 6.35]:
		Props.globe_lamp(front, p.pt(u, 22.075, 1.9))
	# The doorway: stone pilasters and a hood over the doors.
	for run: Array in [[3.9, 4.12], [6.08, 6.3]]:
		p.slab(front, true, f + 0.04, run[0], run[1], 0.56, 2.3, 0.08, stone)
		p.slab(front, true, f + 0.055, run[0] - 0.025, run[1] + 0.025, 0.0, 0.56, 0.11, stone.darkened(0.1))
	p.slab(front, true, f + 0.09, 3.75, 6.45, 2.3, 2.42, 0.18, dressed)
	p.slab(front, true, f + 0.11, 3.7, 6.5, 2.42, 2.5, 0.22, stone)
	# The ground floor's windows: a stone lintel with a keystone over each, a sill under it.
	for w: Array in [[0.8, 3.0], [7.2, 9.4], [12.2, 15.0]]:
		var a: float = w[0]
		var e: float = w[1]
		var m := (a + e) * 0.5
		p.slab(front, true, f + 0.035, a - 0.16, e + 0.16, 2.36, 2.56, 0.07, stone)
		p.slab(front, true, f + 0.05, m - 0.1, m + 0.1, 2.33, 2.62, 0.1, dressed)
		p.slab(front, true, f + 0.06, a - 0.12, e + 0.12, 0.97, 1.045, 0.12, stone)
	# Quoins up both corners, long and short by turns.
	var k := 0
	var y := 0.52
	while y + 0.3 < 6.7:
		var long := 0.5 if k % 2 == 0 else 0.32
		if y > 4.26 or y + 0.3 < 3.96:          # the belt course crosses the corners here
			p.slab(front, true, f + 0.025, 0.0, long, y, y + 0.3, 0.05, stone)
			p.slab(front, true, f + 0.025, 16.0 - long, 16.0, y, y + 0.3, 0.05, stone)
		y += 0.34
		k += 1
	# Upstairs.
	for i in 6:
		In.front_window(p, front, 1.5 + i * 2.6, 22.0, 4.75, 1.05, 1.5, i in [0, 2, 3, 5], Color(0.9, 0.88, 0.82), stone, "", 3.0)
	In.cornice(p, front, 22.0, 0.0, 16.0, 7.4, stone, dressed, 0.45)
	In.parapet(p, front, 22.0, 0.0, 16.0, 7.4, 0.55, Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.9, 0.82, 0.8)), dressed)
	Props.flag_on(front, p.pt(8.0, 22.0, 8.05), Color(0.16, 0.2, 0.45), true)
	# Next door: a boarded-up shop on the left, a bail bondsman on the right.
	var stucco := Kit.tex("stucco", 2.0, Color(0.6, 0.56, 0.5), true, Color(0.72, 0.68, 0.62))
	p.slab(n, true, 22.0, -12.0, 0.0, 0.0, 3.5, 0.15, stucco)
	p.slab(n, true, 22.0, -12.0, 0.0, 3.5, 4.0, 0.15, stucco)
	p.slab(n, true, 22.0, -12.06, 0.0, 4.0, 4.09, 0.28, Color(0.7, 0.66, 0.6))
	p.slab(n, true, f + 0.05, -12.0, 0.0, 3.36, 3.46, 0.1, Color(0.62, 0.58, 0.52))
	for u in [-9.6, -6.4, -3.2]:
		p.slab(n, true, 22.085, u, u + 2.4, 0.5, 2.4, 0.03, Color(0.55, 0.42, 0.26))       # plywood
		p.slab(n, true, 22.1, u + 0.3, u + 2.1, 1.3, 1.36, 0.03, Color(0.45, 0.33, 0.2))
	Props.words(n, "FOR LEASE", p.pt(-5.2, 22.09, 2.9), 0.26, Color(0.75, 0.2, 0.15))
	p.slab(n, true, 22.0, 16.0, 28.0, 0.0, 3.8, 0.15, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74)))
	In.cornice(p, n, 22.0, 16.25, 28.0, 3.8, Color(0.24, 0.2, 0.2), Color(0.8, 0.74, 0.62), 0.35)
	p.slab(n, true, 22.085, 17.2, 20.6, 0.4, 2.3, 0.03, Kit.flat(Color(1.0, 0.92, 0.7), 0.9))
	p.slab(n, true, 22.1, 21.2, 22.1, 0.0, 2.1, 0.03, Color(0.2, 0.3, 0.26))
	Props.words(n, "BAIL BONDS", p.pt(19.6, 22.09, 2.95), 0.34, Color(0.98, 0.85, 0.3))
	Props.words(n, "OPEN 24 HOURS", p.pt(18.9, 22.11, 1.4), 0.16, Color(0.75, 0.15, 0.12))
	# On the pavement and at the kerb.
	Props.bin(p, st, 6.7, 22.45)
	Props.street_lamp(p, st, -1.4, 24.25)
	Props.hydrant(p, st, 9.6, 24.2)
	Props.car(p, st, 12.6, 25.95, 90.0, "cruiser", false)


static func _lobby(p: Node3D, b: int) -> void:
	Props.bench(p, b, 0.36, 19.3, 90.0, 3.2, Props.WOOD)
	Props.bench(p, b, 2.95, 17.36, 0.0, 2.9, Props.WOOD)
	Props.board(p, b, 2.95, 17.08, 0.0, 2.4, "wanted")
	Props.words(p.node_of(b), "WANTED", p.pt(2.95, 17.09, 2.3), 0.16, Color(0.7, 0.12, 0.1))
	Props.board(p, b, 0.08, 19.3, 90.0, 2.0, "notices")
	In.picture(p, b, 0.08, 17.72, 90.0, 0.6, 0.76, "face", Color(0.78, 0.6, 0.22), 1.75)       # the commissioner
	Props.vending(p, b, 5.5, 17.5)
	Props.payphone(p, b, 6.9, 17.08)
	Props.clock(p, b, 7.6, 17.08)
	Props.plant(p, b, 9.95, 21.45)
	Props.flag(p, b, 0.5, 21.45, Color(0.16, 0.2, 0.45), 0.0, true)
	Props.words(p.node_of(b), "DESK SERGEANT", p.pt(10.42, 19.55, 2.3), 0.13, Color(0.15, 0.18, 0.3), 270.0)
	Props.poster(p, b, 10.42, 17.6, 270.0, 0.5, 0.7, Color(0.85, 0.75, 0.3), "NO LOITERING", 1.6)
	# Behind the glass.
	var counter := Props.counter(p, b, 10.95, 19.55, 90.0, 2.7, 0.65, 1.04, Props.OFFICE)
	Kit.box(counter, Vector3(0.3, 0.02, 0.4), Vector3(0.3, 1.06, 0), Props.PAPER)
	Kit.block(counter, Vector3(0.2, 0.07, 0.16), Vector3(-0.7, 1.05, 0.05), Props.DARK)
	Props.chair(p, b, 11.75, 19.55, 270.0)
	Props.radio(p, b, 14.95, 17.5)
	Props.desk(p, b, 13.6, 20.85, 180.0, Props.OFFICE, 3)
	Props.files(p, b, 15.6, 20.3, 270.0, 2)
	Props.board(p, b, 15.92, 18.6, 270.0, 1.2, "notices")
	Props.clock(p, b, 13.3, 17.08)
	In.picture(p, b, 12.55, 17.08, 0.0, 0.9, 0.66, "map", Props.WOOD_DARK, 1.6)              # the precinct
	p.person(b, "cop", 12.5, 19.3, {"face": "bored"})          # the desk sergeant
	p.person(b, "cop", 9.7, 18.2)                             # on the gate


static func _squad(p: Node3D, b: int) -> void:
	var stuff := [1, 2, 3, 1, 3, 2]
	for i in 3:
		var u := 2.1 + i * 3.3
		Props.desk(p, b, u, 13.875, 180.0, Props.OFFICE.darkened(0.08 * (i % 2)), stuff[i * 2])
		Props.desk(p, b, u, 14.625, 0.0, Props.OFFICE.lightened(0.06 * (i % 2)), stuff[i * 2 + 1])
	Props.board(p, b, 3.7, 11.08, 0.0, 2.6, "wanted", 1.1)
	Props.words(p.node_of(b), "OPEN CASES", p.pt(3.7, 11.09, 2.32), 0.13, Color(0.2, 0.2, 0.22))
	Props.board(p, b, 0.08, 12.6, 90.0, 2.0, "notices")
	In.picture(p, b, 0.08, 14.45, 90.0, 0.56, 0.7, "face", Props.WOOD_DARK, 1.8)            # a fallen officer
	In.picture(p, b, 9.1, 11.08, 0.0, 1.2, 0.84, "map", Color(0.3, 0.3, 0.32), 1.62)        # the beat map
	Props.files(p, b, 0.4, 15.6, 90.0, 4)
	Props.lockers(p, b, 2.3, 16.65, 180.0, 4)
	Props.coffee(p, b, 10.3, 11.45)
	Props.cooler(p, b, 11.6, 11.3)
	Props.flag(p, b, 10.0, 16.55, Color(0.6, 0.12, 0.14))      # clear of the door to the front desk
	Props.clock(p, b, 8.0, 11.08)
	p.person(b, "cop", 3.8, 12.2, {"face": "focused"})
	p.person(b, "cop", 7.0, 16.0)
	p.person(b, "cop", 10.6, 12.5, {"face": "happy"})         # by the coffee
	# The captain's office. His couch stands along the right wall (where it
	# stood, in front of the desk, it hid the room from the camera).
	Props.desk(p, b, 14.1, 12.9, 180.0, Props.WOOD, 2, true, 2.0, 0.85)
	Props.chair(p, b, 13.6, 14.1, 180.0, Props.VINYL)
	Props.chair(p, b, 14.6, 14.1, 180.0, Props.VINYL)
	Props.shelves(p, b, 15.68, 13.3, 270.0, 2.4, "books", Props.WOOD_DARK)
	Props.flag(p, b, 12.55, 11.45, Color(0.16, 0.2, 0.45), 0.0, true)
	Props.couch(p, b, 15.49, 15.64, 270.0, 1.9, Color(0.3, 0.22, 0.16))
	In.picture(p, b, 15.92, 15.64, 270.0, 1.0, 0.62, "city", Color(0.78, 0.6, 0.22), 1.62)
	Props.poster(p, b, 14.1, 11.08, 0.0, 0.9, 0.6, Color(0.7, 0.58, 0.3), "", 1.9)
	In.picture(p, b, 15.45, 11.08, 0.0, 0.4, 0.5, "certificate", Color(0.78, 0.6, 0.22), 1.55)
	for u in [13.32, 14.88]:
		In.sconce(p, b, u, 11.08, 0.0, "shade", 1.95)
	Props.rug(p, b, 14.0, 14.3, 2.6, 1.6, Color(0.35, 0.16, 0.16))


static func _booking(p: Node3D, b: int) -> void:
	# Interview: a table, three chairs, the mirror, a bare bulb over the table.
	Props.table(p, b, 2.0, 7.6, 0.0, 1.4, 0.9, Props.IRON)
	Props.chair(p, b, 2.0, 6.75, 0.0, Props.IRON)
	Props.chair(p, b, 2.0, 8.45, 180.0, Props.IRON)
	Props.chair(p, b, 0.5, 5.5, 90.0, Props.IRON)
	In.pendant(p, b, 2.0, 7.6, 1.95, Props.STEEL, "bulb", Color(1.0, 0.88, 0.6))
	# Booking: the counter, prints, the mugshot wall, the cuff bench.
	var counter := Props.counter(p, b, 4.46, 7.75, 90.0, 3.1, 0.7, 1.05, Props.OFFICE.darkened(0.15))
	Kit.block(counter, Vector3(0.36, 0.1, 0.3), Vector3(0.9, 1.05, 0), Color(0.25, 0.3, 0.28))
	Kit.box(counter, Vector3(0.6, 0.03, 0.4), Vector3(-0.6, 1.065, 0), Color(0.2, 0.3, 0.2))
	Props.words(p.node_of(b), "BOOKING", p.pt(4.09, 9.2, 2.3), 0.16, Color(0.9, 0.9, 0.85), 90.0)
	var prints := Props.table(p, b, 4.46, 10.25, 90.0, 0.9, 0.7, Props.STEEL)
	Kit.box(prints, Vector3(0.3, 0.02, 0.2), Vector3(0, 0.75, 0), Props.DARK)
	Kit.box(prints, Vector3(0.24, 0.01, 0.3), Vector3(0.28, 0.745, 0.05), Props.PAPER)
	Props.height_chart(p, b, 6.3, 5.08)
	# where the prisoner stands for his picture: a yellow box painted on the floor
	In.mat(p, b, 6.3, 5.72, 0.72, 0.56, Kit.tex("lino", 1.6, Color(0.45, 0.5, 0.48), true, Color(0.6, 0.62, 0.6)), Color(0.95, 0.78, 0.18))
	Props.tripod(p, b, 6.3, 6.9, 180.0)
	var cuffs := Props.bench(p, b, 9.85, 5.43, 0.0, 1.9, Props.IRON)
	Kit.box(cuffs, Vector3(1.9, 0.04, 0.04), Vector3(0, 0.75, -0.2), Props.STEEL)
	Props.lockers(p, b, 10.65, 6.55, 270.0, 3)
	Props.counter(p, b, 10.7, 8.2, 270.0, 1.4, 0.4, 1.0, Props.OFFICE.darkened(0.15))
	Props.words(p.node_of(b), "PROPERTY", p.pt(10.91, 8.2, 2.25), 0.13, Color(0.9, 0.9, 0.85), 270.0)
	p.person(b, "cop", 5.6, 8.4, {"face": "focused"})          # booking
	# Evidence: shelving round the walls behind the cage door, the floor between
	# kept low (the old rows of shelves across the room hid him from the camera).
	Props.shelves(p, b, 13.6, 5.42, 0.0, 4.2)
	Props.shelves(p, b, 15.68, 7.55, 270.0, 2.3)
	Props.shelves(p, b, 15.68, 9.9, 270.0, 1.9)
	Props.counter(p, b, 11.32, 8.2, 90.0, 1.4, 0.4, 1.0, Props.OFFICE.darkened(0.15))


static func _cells(p: Node3D, b: int) -> void:
	for i in 3:
		var u0 := i * 3.0
		Props.bunk(p, b, u0 + 1.1, 0.5)
		Props.cell_toilet(p, b, u0 + 2.55, 0.4)
		Props.words(p.node_of(b), str(i + 1), p.pt(u0 + 1.5, 2.64, 2.55), 0.22, Color(0.9, 0.9, 0.85))
	# days scratched on the wall of cell 2
	for k in 7:
		var x := 4.55 + k * 0.045 + (0.03 if k > 4 else 0.0)
		Kit.box(p.node_of(b), Vector3(0.012, 0.16, 0.004), p.pt(x, 0.087, 1.42), Color(0.24, 0.26, 0.24), Vector3(0, 0, 62.0 if k == 4 else 0.0))
	Props.bench(p, b, 10.5, 0.38, 0.0, 2.6, Props.IRON)
	Props.bench(p, b, 11.6, 1.75, 270.0, 1.2, Props.IRON)
	Props.words(p.node_of(b), "TANK", p.pt(10.5, 2.64, 2.55), 0.2, Color(0.9, 0.9, 0.85))
	Kit.cyl(p.node_of(b), 0.09, 0.006, p.pt(10.6, 1.4, 0.003), Color(0.2, 0.2, 0.22), Vector3.ZERO, 10)        # the drain
	Props.desk(p, b, 10.9, 4.45, 0.0, Props.OFFICE.darkened(0.2), 1, false, 1.4, 0.6)
	Props.chair(p, b, 9.75, 4.45, 90.0)
	Props.board(p, b, 0.08, 3.8, 90.0, 1.2, "notices")
	p.person(b, "cop", 6.0, 3.9, {"face": "bored"})            # the turnkey
	p.person(b, "cop", 13.3, 3.0)                             # waiting on the van
	# The sally port: the roll-up door is up and the prisoner van stands half
	# in, half out on the back lot. (A whole van indoors hid him from the camera.)
	Props.car(p, b, 14.0, -0.55, 0.0, "van")
	var n: Node3D = p.node_of(b)
	Kit.box(n, Vector3(9.0, 0.3, 5.0), p.pt(14.0, -2.5, -0.16), Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27)))
	p.slab(n, true, 0.0, 12.72, 15.28, 2.7, 2.86, 0.22, Color(0.45, 0.47, 0.5))      # the door, rolled up
	var hazard := Kit.tex("in_hazard", 0.8, Color(0.9, 0.75, 0.2))
	for run: Array in [[12.47, 12.645], [15.355, 15.53]]:      # striped jambs either side of the door
		p.slab(n, true, 0.075 + 0.006, run[0], run[1], 0.465, 2.6, 0.012, hazard)       # standing on the dado rail
	for u in [12.42, 15.58]:      # oil drums fill the corners beside the van
		var drum: Node3D = p.prop(b, u, 0.75, 0.0, 0.62, 1.25)
		for k in 2:
			Kit.cyl(drum, 0.28, 0.85, Vector3(0, 0.425, -0.3 + k * 0.6), Color(0.2, 0.36, 0.5) if k == 0 else Color(0.6, 0.3, 0.12), Vector3.ZERO, 10)
	Props.words(n, "NO PRISONER LEFT UNATTENDED", p.pt(15.91, 3.2, 2.2), 0.1, Color(0.75, 0.15, 0.12), 270.0)
