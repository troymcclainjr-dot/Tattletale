extends RefCounted
## The county jail (place `prison`). A low concrete-block building behind a
## razor-wire fence: visitors come in at the front, prisoners at the side
## through the sally port, and the cell block and its yard are at the back.
## 32 x 44 m, one floor and the cell block's upper tier; the bands from the
## street back:
##
##   forecourt (behind the wire, the visitors' gate open) | the vehicle lane (its gate shut)
##   visitor lobby | visiting room (three booths at the glass along its back) | sally port (the van)
##   the inmates' side of the glass (behind the visiting room, a band of its own)
##   control | corridor (round the inmates' side; the locked gate from the lobby) | booking | holding
##   mess hall | block gate | treatment | change room | property | segregation | the hole
##   the dayroom, eight cells along its back, the yard hall, the showers
##   the yard
##
## The upper tier (CELL 201 .. 208 off a catwalk) is a second level, drawn off
## to the right (u + 50) and reached by the steel stair in the dayroom.
##
## The free man gets no further than the lobby and the visiting room, where he
## talks through the glass to an inmate on the other side: the gate from the
## lobby to the corridor is a door nobody can open. A man under arrest
## (prison_rules.gd) is brought in at booking, in the jumpsuit, and walks the
## inside; his own cell is CELL 104, and E on its bunk is the night that lets him out.
##
## Numbers are metres on the plan: u from the left wall, v from the back of the
## yard (0); the street is at v = 44. Every name, sign and line here is a
## placeholder, written by the prison worker, not the owners'.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Jail := preload("res://scripts/props_prison.gd")
const Park := preload("res://scripts/props_park.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Alley := preload("res://scripts/props_alley.gd")

const W := 32.0
const D := 44.0
const UP := 50.0            # the upper tier is drawn this far to the right of the plan (level 1)
const TIER := 2.9           # one tier of cells: the catwalk's top is this high over the dayroom
const DECK := 2.62          # the underside of the catwalk and of the upper cells' floor
const HIGH := 6.0           # the cell block's walls: two tiers
const MARK := Vector2(21.1, 27.75)       # booking's yellow box, at the height chart: he arrives here under arrest
const BUNK := Vector2(8.7, 11.6)         # his own cell, CELL 104: where he is when he is brought back held
const BOOTHS := [[10.9, 12.1], [13.9, 15.1], [16.9, 18.1]]     # the visiting booths' windows, along the glass at v = 33

## Inmates wear the orange jumpsuit (tools/prison_jumpsuit.py): the two items over what they were drawn in.
const JUMPSUIT := {"hat": {"item": ""}, "jacket": {"item": ""}, "shirt": {"item": "jumpsuit"}, "trousers": {"item": "jumpsuit_legs"}}

const STEEL_DOOR := Color(0.36, 0.4, 0.44)
const DARK_FRAME := Color(0.2, 0.22, 0.26)
const RUBBER := Color(0.15, 0.15, 0.17)
const TUBE := Color(0.96, 0.98, 0.94)
const RED := Color(0.78, 0.14, 0.12)
const SIGN := Color(0.92, 0.92, 0.88)
const INK := Color(0.12, 0.18, 0.24)       # words painted on a light wall


static func build(p: Node3D) -> void:
	p.setup("COUNTY JAIL", W, D)
	var block := Kit.tex("block_plain", 1.2, Color(0.72, 0.72, 0.7), true, Color(0.84, 0.84, 0.82))
	var facade := Kit.tex("block_plain", 1.2, Color(0.7, 0.69, 0.66), true, Color(0.88, 0.86, 0.8))
	var terrazzo := Kit.tex("in_terrazzo", 1.6, Color(0.7, 0.68, 0.64), true, Color(0.92, 0.9, 0.86))
	var lino := Kit.tex("lino", 1.6, Color(0.6, 0.66, 0.6), true, Color(0.84, 0.85, 0.8))
	var lino_dark := Kit.tex("lino", 1.6, Color(0.45, 0.5, 0.48), true, Color(0.62, 0.64, 0.62))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.74, 0.74, 0.76))
	var sealed := Kit.tex("sidewalk", 2.4, Color(0.5, 0.52, 0.55), true, Color(0.64, 0.68, 0.74))
	var tile := Kit.tex("in_tile", 0.6, Color(0.7, 0.75, 0.76), true, Color(0.8, 0.86, 0.88))

	var st: int = p.street(-6.0, 38.0)
	var b1: int = p.band()
	var bi: int = p.band()          # the inmates' side of the visiting glass, a band of its own (cut away from the corridor behind)
	var b2: int = p.band()
	var b3: int = p.band()
	var b4: int = p.band()
	var b5: int = p.band()
	var up: int = p.band(1)
	p.arrive = p.pt(4.9, 45.3)
	p.set_meta("prison_mark", p.pt(MARK.x, MARK.y))
	p.set_meta("prison_cell", p.pt(BUNK.x, BUNK.y))

	var low := {"cam_near": 1.3, "cam_y": 3.0, "look_y": 1.0}           # a cell: seen through its bars from the dayroom
	p.room("FORECOURT", st, 0, 39, 19, 44, Outdoor.pavement(), {"street": true})
	p.room("VISITOR LOBBY", b1, 0, 33, 10, 39, terrazzo, {"light": TUBE, "energy": 0.45})
	p.room("VISITING ROOM", b1, 10, 33, 19, 39, lino)
	p.room("SALLY PORT", b1, 19, 33, 32, 39, concrete)
	p.room("INMATE SIDE", bi, 10, 31, 19, 33, lino_dark)        # (before the corridor, whose rect it is cut from)
	p.room("CONTROL", b2, 0, 27, 4, 33, lino_dark)
	p.room("CORRIDOR", b2, 4, 27, 19, 33, null, {"areas": [[4, 27, 19, 31], [4, 27, 10, 33]]})      # round the inmates' side, up to the gate
	Kit.box(p.node_of(b2), Vector3(15.0, 0.3, 4.0), p.pt(11.5, 29.0, -0.15), lino)
	Kit.box(p.node_of(b2), Vector3(6.0, 0.3, 2.0), p.pt(7.0, 32.0, -0.15), lino)
	# Floor 2 cm under the cut-away bands in front (the inmates' side, the lobby, the visiting room), so
	# the camera looking over their stubs sees floor, not the void; under their own floors when they show.
	Kit.box(p.node_of(b2), Vector3(8.98, 0.3, 1.98), p.pt(14.5, 32.0, -0.17), lino_dark)
	Kit.box(p.node_of(b2), Vector3(5.98, 0.3, 1.98), p.pt(7.0, 34.0, -0.17), terrazzo)
	Kit.box(p.node_of(bi), Vector3(8.98, 0.3, 2.98), p.pt(14.5, 34.5, -0.17), lino)
	p.room("BOOKING", b2, 19, 27, 28, 33, lino_dark, {"light": TUBE, "energy": 0.45})
	p.room("HOLDING", b2, 28, 27, 32, 33, concrete)
	p.room("MESS HALL", b3, 0, 21, 11, 27, lino, {"light": Color(1.0, 0.94, 0.8), "energy": 0.4})
	p.room("BLOCK GATE", b3, 11, 21, 14, 27, sealed, {"cam_y": 4.3, "look_y": 1.0})      # (high: seen over the bars of the gate in)
	p.room("TREATMENT", b3, 14, 21, 18, 27, lino)
	p.room("CHANGE ROOM", b3, 18, 21, 22, 27, sealed)
	p.room("PROPERTY", b3, 22, 21, 24, 27, sealed)
	p.room("SEGREGATION", b3, 24, 21, 28, 27, sealed, {"light": Color(1.0, 0.82, 0.7), "energy": 0.3})
	p.room("THE HOLE", b3, 28, 21, 32, 27, concrete)
	p.room("DAYROOM", b4, 0, 12.6, 26, 21, sealed, {"cam_near": 1.35, "cam_y": 3.6, "look_y": 1.4})
	for k in 8:
		p.room("CELL %d" % (101 + k), b4, k * 2.5, 10.0, k * 2.5 + 2.5, 12.6, sealed, low)
		p.rooms[p.rooms.size() - 1]["cam_max_x"] = p.pt(24.3, 0).x     # (as the dayroom's: it looks in through the bars from the right)
	p.room("YARD HALL", b4, 20, 10, 26, 12.6, sealed, low)
	p.room("SHOWERS", b4, 26, 10, 32, 21, tile)
	p.room("YARD", b5, 0, 0, 32, 10, Outdoor.tex("out_concrete", 2.56, Color(0.62, 0.62, 0.6), Color(0.86, 0.85, 0.82)), {"cam_near": 1.4, "cam_y": 3.2, "look_y": 1.2})
	p.room("UPPER TIER", up, UP, 12.6, UP + 20, 14.4, Kit.tex("in_diamond", 0.5, Color(0.5, 0.52, 0.55), true, Color(0.72, 0.74, 0.78)), low)
	for k in 8:
		p.room("CELL %d" % (201 + k), up, UP + k * 2.5, 10.0, UP + k * 2.5 + 2.5, 12.6, sealed, low)
		p.rooms[p.rooms.size() - 1]["cam_max_x"] = p.pt(UP + 18.3, 0).x

	# ---- walls. Each `cross` is the wall in FRONT of its band; the openings are kept by name: the paint stops at each.
	var ops := {
		"front": [           # (the public rooms' windows: no bars, or a visitor in them reads as an inmate)
			{"a": 1.0, "b": 2.2, "kind": "window", "sill": 1.1, "head": 2.5, "frame": DARK_FRAME},
			{"a": 3.6, "b": 5.4, "kind": "double", "head": 2.3, "colour": Color(0.22, 0.3, 0.42), "frame": DARK_FRAME},
			{"a": 7.0, "b": 8.2, "kind": "window", "sill": 1.1, "head": 2.5, "frame": DARK_FRAME},
			{"a": 11.9, "b": 13.1, "kind": "window", "sill": 1.1, "head": 2.5, "frame": DARK_FRAME},
			{"a": 16.4, "b": 17.4, "kind": "window", "sill": 1.1, "head": 2.5, "frame": DARK_FRAME},
		],
		"lobby": [{"a": 37.0, "b": 37.9, "colour": STEEL_DOOR, "hinge": "a", "swing": 1}],
		"b2l": [
			{"a": 0.8, "b": 3.2, "kind": "window", "sill": 0.95, "head": 2.1, "frame": Props.STEEL},
			{"a": 6.4, "b": 7.4, "colour": STEEL_DOOR, "name": "GATE"},
		],
		"glass": [],
		"inmates": [{"a": 11.05, "b": 11.95, "colour": STEEL_DOOR, "hinge": "a"}],
		"b2r": [{"a": 20.4, "b": 21.4, "colour": STEEL_DOOR}],
		"control": [{"a": 28.0, "b": 28.9, "colour": STEEL_DOOR, "hinge": "a", "swing": 1}],
		"booking": [{"a": 29.0, "b": 29.9, "colour": STEEL_DOOR, "hinge": "a", "swing": 1}],
		"mess": [{"a": 8.0, "b": 8.9, "colour": STEEL_DOOR}],
		"b3": [
			{"a": 15.5, "b": 16.4, "colour": Color(0.86, 0.88, 0.86)},
			{"a": 19.2, "b": 20.1, "colour": STEEL_DOOR},
			{"a": 22.25, "b": 23.75, "kind": "window", "sill": 0.95, "head": 1.95, "bars": true, "frame": Props.IRON},
		],
		"property": [{"a": 25.7, "b": 26.6, "colour": STEEL_DOOR, "hinge": "a", "swing": 1}],
		"hole": [{"a": 23.6, "b": 24.5, "colour": Color(0.3, 0.32, 0.35), "hinge": "a", "swing": 1}],
		"dayroom": [{"a": 5.0, "b": 6.0, "colour": STEEL_DOOR}],
		"seg": [{"a": 24.6, "b": 25.5, "colour": Color(0.5, 0.2, 0.16)}],
		"arch": [{"a": 17.0, "b": 18.6, "kind": "arch", "head": 2.3}],
		"yard": [{"a": 22.5, "b": 23.5, "colour": STEEL_DOOR}],
	}
	for w: Array in BOOTHS:              # the visiting room's glass, in the wall between it and the inmates' side
		ops["glass"].append({"a": w[0], "b": w[1], "kind": "window", "sill": 0.8, "head": 2.05, "frame": Props.IRON})

	var front: Node3D = p.cross(b1, 39.0, 0, 32, facade, ops["front"], {"h": 4.8})
	p.side(b1, 0.0, 33, 39, facade, [], {"h": 4.8})
	p.side(b1, 32.0, 33, 39, facade, [], {"h": 4.8})
	p.side(b1, 10.0, 33, 39, block, ops["lobby"])
	p.side(b1, 19.0, 33, 39, block)

	var glass: Node3D = p.cross(bi, 33.0, 10, 19, block, ops["glass"])
	var made: int = p.doors.size()
	p.cross(b2, 33.0, 0, 10, block, ops["b2l"])
	p.doors[made].use_reach = -1.0             # the inner gate, lobby to corridor: nobody opens it, from either side
	p.cross(b2, 33.0, 19, 32, block, ops["b2r"])
	p.cross(b2, 31.0, 10, 19, block, ops["inmates"])
	p.side(bi, 10.0, 31, 33, block)            # between the way in from the gate and the inmates' side (gone with it, from the corridor)
	p.side(b2, 0.0, 27, 33, block)
	p.side(b2, 32.0, 27, 33, block)
	p.side(b2, 4.0, 27, 33, block, ops["control"])
	p.side(b2, 19.0, 27, 33, block, ops["booking"])
	p.bars(b2, false, 28.0, 27.0, 33.0, [[30.4, 31.4]])

	var mess_front: Node3D = p.cross(b3, 27.0, 0, 11, block, ops["mess"])
	p.cross(b3, 27.0, 14, 28, block, ops["b3"])
	p.cross(b3, 27.0, 28, 32, block)
	p.slab(mess_front, true, 27.0, 11.0, 14.0, 2.4, 2.9, 0.15, block)          # over the barred gate in from the corridor
	p.bars(b3, true, 27.0, 11.0, 14.0, [[12.0, 13.0]])
	_gate(p)
	for u: float in [0.0, 11.0, 14.0, 18.0, 24.0, 32.0]:
		p.side(b3, u, 21, 27, block)
	p.side(b3, 22.0, 21, 27, block, ops["property"])
	p.side(b3, 28.0, 21, 27, block, ops["hole"])

	p.cross(b4, 21.0, 0, 11, block, ops["dayroom"], {"h": HIGH})
	var unit_front: Node3D = p.cross(b4, 21.0, 14, 26, block, ops["seg"], {"h": HIGH})
	p.cross(b4, 21.0, 26, 32, block, [], {"h": HIGH})
	p.slab(unit_front, true, 21.0, 11.0, 14.0, 2.4, HIGH, 0.15, block)        # over the barred gate in from the block gate
	p.bars(b4, true, 21.0, 11.0, 14.0, [[12.0, 13.0]])
	_gate(p)
	p.side(b4, 0.0, 10, 21, block, [], {"h": HIGH})
	p.side(b4, 26.0, 10, 21, block, ops["arch"], {"h": HIGH})
	p.side(b4, 32.0, 10, 21, block, [], {"h": HIGH})
	for k in range(1, 9):
		p.side(b4, k * 2.5, 10, 12.6, block, [], {"h": DECK})
	var gaps: Array = []
	for k in 8:
		gaps.append([k * 2.5 + 0.3, k * 2.5 + 1.3])
	p.bars(b4, true, 12.6, 0.0, 20.0, gaps, DECK)
	p.bars(b4, true, 12.6, 20.0, 26.0, [[22.5, 23.5]])
	_gate(p)

	p.cross(b5, 10.0, 0, 26, Kit.tex("block_plain", 1.2, Color(0.74, 0.72, 0.68), true, Color(0.86, 0.84, 0.8)), ops["yard"], {"h": HIGH})
	p.cross(b5, 10.0, 26, 32, Kit.tex("block_plain", 1.2, Color(0.74, 0.72, 0.68), true, Color(0.86, 0.84, 0.8)), [], {"h": HIGH})

	_walls(p, b1, bi, b2, b3, b4, ops)
	_street(p, st)
	_facade(p, front)
	_visiting(p, b1, bi, glass)
	_intake(p, b2)
	_services(p, b3)
	_unit(p, b4)
	_cells(p, b4)
	_upper_seen(p, b4, block)
	_yard(p, b5)
	_upper(p, up, block, sealed)


## The barred door just made is a gate, not a cell's (what it says over it).
static func _gate(p: Node3D) -> void:
	var door: Variant = p.doors[p.doors.size() - 1]
	door.open_name = "OPEN GATE"
	door.shut_name = "CLOSE GATE"


## Gloss paint over the block (its own texture, tinted), as at the police station.
static func _paint(c: Color) -> StandardMaterial3D:
	return Kit.tex("block_plain", 1.2, c.darkened(0.08), true, c)


## Each room's walls painted, the floors marked, the lights on the walls.
static func _walls(p: Node3D, b1: int, bi: int, b2: int, b3: int, b4: int, ops: Dictionary) -> void:
	var public := {"lower": _paint(Color(0.36, 0.56, 0.6)), "upper": _paint(Color(0.9, 0.9, 0.85)), "dado": Color(0.16, 0.3, 0.34), "skirt": RUBBER, "skirt_h": 0.12}
	var secure := {"lower": _paint(Color(0.42, 0.5, 0.62)), "upper": _paint(Color(0.86, 0.88, 0.88)), "dado": Color(0.2, 0.26, 0.36), "skirt": RUBBER, "skirt_h": 0.12}
	var control := {"lower": _paint(Color(0.34, 0.36, 0.4)), "upper": _paint(Color(0.8, 0.8, 0.78)), "dado": Color(0.16, 0.17, 0.2), "skirt": RUBBER, "skirt_h": 0.12}
	var port := {"lower": Kit.tex("in_hazard", 0.8, Color(0.9, 0.75, 0.2)), "dado_y": 0.42, "dado": Color(0.18, 0.18, 0.2), "upper": _paint(Color(0.7, 0.71, 0.72))}
	var booking := {"lower": _paint(Color(0.34, 0.62, 0.64)), "upper": _paint(Color(0.9, 0.9, 0.86)), "dado": Color(0.12, 0.2, 0.22), "skirt": RUBBER, "skirt_h": 0.12}
	var cage := {"lower": _paint(Color(0.56, 0.74, 0.63)), "upper": _paint(Color(0.94, 0.93, 0.83)), "dado": Color(0.28, 0.44, 0.35)}
	var mess := {"lower": _paint(Color(0.86, 0.68, 0.3)), "upper": _paint(Color(0.95, 0.92, 0.8)), "dado": Color(0.5, 0.3, 0.14), "skirt": RUBBER, "skirt_h": 0.12}
	var clinic := {"lower": Kit.tex("in_tile", 0.6, Color(0.82, 0.9, 0.9), true, Color(0.92, 0.98, 0.98)), "dado_y": 1.4, "dado": Color(0.3, 0.55, 0.6), "upper": _paint(Color(0.93, 0.95, 0.94))}
	var plain := {"lower": _paint(Color(0.58, 0.6, 0.62)), "upper": _paint(Color(0.88, 0.88, 0.86)), "dado": Color(0.26, 0.28, 0.3)}
	var seg := {"lower": _paint(Color(0.55, 0.28, 0.22)), "upper": _paint(Color(0.78, 0.76, 0.72)), "dado": Color(0.25, 0.12, 0.1)}
	var unit := {"lower": _paint(Color(0.3, 0.45, 0.66)), "upper": _paint(Color(0.9, 0.9, 0.84)), "dado": Jail.SAFETY, "dado_y": 1.25, "dado_h": 0.12, "skirt": RUBBER, "skirt_h": 0.12, "h": HIGH}
	var cell := {"lower": _paint(Color(0.62, 0.7, 0.78)), "upper": _paint(Color(0.88, 0.9, 0.9)), "dado": Color(0.3, 0.38, 0.46), "h": DECK - 0.02}
	var wet := {"lower": Kit.tex("in_tile", 0.6, Color(0.82, 0.88, 0.9), true, Color(0.88, 0.94, 0.96)), "dado_y": 1.9, "dado": Color(0.3, 0.42, 0.48), "upper": _paint(Color(0.85, 0.88, 0.88)), "h": HIGH}

	In.room_walls(p, b1, 0, 33, 10, 39, public, ops["b2l"], [], ops["lobby"])
	In.room_walls(p, b1, 10, 33, 19, 39, public, ops["glass"], ops["lobby"], [])
	In.room_walls(p, b1, 19, 33, 32, 39, port, ops["b2r"], [], [])
	In.room_walls(p, bi, 10, 31, 19, 33, secure, ops["inmates"], [], [])
	In.room_walls(p, b2, 0, 27, 4, 33, control, ops["mess"], [], ops["control"])
	In.room_walls(p, b2, 4, 27, 19, 33, secure, null, ops["control"], null)
	In.dress(p, b2, false, 19.0, -1.0, 27.075, 30.925, ops["booking"], secure)       # the corridor's right wall, up to the inmates' side
	In.dress(p, bi, false, 10.0, -1.0, 31.075, 32.925, [], secure)                   # and the inmates' side's wall, by the gate
	In.dress(p, b2, true, 27.0, 1.0, 4.075, 10.925, ops["mess"], secure)          # the corridor's back wall, either side of the barred gate
	In.dress(p, b2, true, 27.0, 1.0, 14.075, 18.925, ops["b3"], secure)
	In.room_walls(p, b2, 19, 27, 28, 33, booking, ops["b3"], ops["booking"], null)
	In.room_walls(p, b2, 28, 27, 32, 33, cage, [], null, [])
	In.room_walls(p, b3, 0, 21, 11, 27, mess, ops["dayroom"], [], [])
	In.room_walls(p, b3, 11, 21, 14, 27, secure, null, [], [])
	In.room_walls(p, b3, 14, 21, 18, 27, clinic, ops["seg"], [], [])
	In.room_walls(p, b3, 18, 21, 22, 27, plain, ops["seg"], [], ops["property"])
	In.room_walls(p, b3, 22, 21, 24, 27, plain, ops["seg"], ops["property"], [])
	In.room_walls(p, b3, 24, 21, 28, 27, seg, ops["seg"], [], ops["hole"])
	In.room_walls(p, b4, 0, 12.6, 26, 21, unit, null, [], ops["arch"])
	for k in 8:
		In.room_walls(p, b4, k * 2.5, 10, k * 2.5 + 2.5, 12.6, cell, [], [], [])
	In.room_walls(p, b4, 20, 10, 26, 12.6, cell, ops["yard"], [], [])
	In.room_walls(p, b4, 26, 10, 32, 21, wet, [], ops["arch"], [])

	# Floors: a mat in at the front doors, the line to stand behind at the gate, the
	# corridor's yellow walking line along its back wall.
	In.border(p, b1, 0, 33, 10, 39, Color(0.36, 0.38, 0.42), 0.25)
	In.mat(p, b1, 4.5, 38.38, 2.2, 0.9, Color(0.3, 0.34, 0.4), Color(0.2, 0.22, 0.26))      # (blue-grey: a black mat reads as a hole)
	In.hatch(p, b2, 11.5, 27.72, 1, 14.3, 0.08, 0.0, Jail.SAFETY)
	In.hatch(p, b2, 6.42, 32.3, 7, 0.1, 0.6, 0.06, RED)
	Park.ground_words(p.node_of(b2), "STOP", p.pt(6.9, 31.72, 0.006), 0.28, RED)
	In.hatch(p, b1, 19.7, 34.4, 6, 0.1, 1.0, 0.2, Jail.SAFETY, 35.0)

	# Lights: fluorescent fittings high on the back walls; caged lamps in the cells and the cages.
	In.wall_strip(p, b1, 2.0, 33.08, 0.0, 1.2, 2.62)
	In.wall_strip(p, b1, 8.6, 33.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b1, 13.0, 33.08, 0.0, 0.9, 2.62)
	In.wall_strip(p, b1, 16.0, 33.08, 0.0, 0.9, 2.62)
	In.wall_strip(p, b1, 25.5, 33.08, 0.0, 1.6, 2.62)
	In.wall_strip(p, b2, 2.0, 27.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b2, 6.2, 27.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b2, 17.6, 27.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b2, 25.0, 27.08, 0.0, 1.2, 2.62)
	In.sconce(p, b2, 30.0, 27.08, 0.0, "cage", 2.5)
	In.wall_strip(p, b3, 3.0, 21.08, 0.0, 1.2, 2.62)
	In.wall_strip(p, b3, 9.4, 21.08, 0.0, 1.2, 2.62)
	In.wall_strip(p, b3, 16.0, 21.08, 0.0, 1.0, 2.62)
	In.wall_strip(p, b3, 20.0, 21.08, 0.0, 1.0, 2.62)
	In.sconce(p, b3, 26.5, 21.08, 0.0, "cage", 2.4)
	In.sconce(p, b3, 30.0, 21.08, 0.0, "cage", 2.4, Color(0.75, 0.62, 0.45))
	In.sconce(p, b3, 12.5, 21.08, 0.0, "cage", 2.3)
	for k in 8:
		In.sconce(p, b4, k * 2.5 + 1.25, 10.08, 0.0, "cage", 2.3)
	In.wall_strip(p, b4, 0.08, 16.4, 90.0, 1.6, 4.8)
	In.wall_strip(p, b4, 0.08, 19.6, 90.0, 1.6, 4.8)
	In.wall_strip(p, b4, 25.92, 15.0, 270.0, 1.6, 4.8)
	In.wall_strip(p, b4, 23.0, 10.08, 0.0, 1.0, 2.3)
	In.wall_strip(p, b4, 29.0, 10.08, 0.0, 1.6, 2.7)
	In.wall_strip(p, b4, 31.92, 16.0, 270.0, 1.6, 2.7)
	var lamps: Node3D = p.node_of(b4)
	Kit.omni(lamps, p.pt(7.0, 17.5, 3.2), Color(1.0, 0.96, 0.88), 0.5, 9.0)
	Kit.omni(lamps, p.pt(19.0, 17.5, 3.2), Color(1.0, 0.96, 0.88), 0.5, 9.0)


# ------------------------------------------------------------------ outside

## The pavement and the forecourt: the jail's fence along the street, razor wire
## on it, the visitors' gate standing open, the vehicle gate shut; the lawn, the
## flagpole and the name on its low wall; grass and trees either side.
static func _street(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var grass := Outdoor.tex("out_grass", 3.0, Color(0.36, 0.6, 0.28))
	# The front fence and the vehicle gate in a group of their own, and a knee-high
	# stub of them in another that stands in for them while the camera is behind
	# them (Alley.cutaway: so near the camera, chain link is a screen over him).
	var tall := Kit.group(n, Vector3.ZERO, Vector3.ZERO, "JailFront")
	var stub := Kit.group(n, Vector3.ZERO, Vector3.ZERO, "JailFrontStub")
	for g: Node3D in [tall, stub]:
		var first := n.get_child_count()
		var kept: int = p.obstacles.size()
		p.fence(st, true, 44.0, 0.0, 19.0, [[4.0, 5.8]], 3.0 if g == tall else 0.5, "chain")
		for c: Node in n.get_children().slice(first):
			c.reparent(g)
		if g == stub:
			p.obstacles.resize(kept)                      # (the stub's: where it stands is blocked already)
	Jail.wire_on(p, tall, true, 44.0, 0.0, 19.0, [[4.0, 5.8]], 3.0)
	Jail.open_leaf(p, tall, 44.0, 4.0, 1.8, 2.7)
	Jail.vehicle_gate(p, tall, 44.0, 19.0, 32.0, 3.0)
	p.block(19.0, 43.88, 32.0, 44.12)
	Kit.box(stub, Vector3(13.0, 0.5, 0.08), p.pt(25.5, 44.0, 0.25), Color(0.36, 0.38, 0.4))
	Alley.cutaway(p, st, tall, stub, 44.0)
	Kit.box(tall, Vector3(1.2, 0.5, 0.03), p.pt(2.6, 44.06, 1.6), SIGN)
	Props.words(tall, "VISITORS", p.pt(2.6, 44.08, 1.66), 0.14, Color(0.15, 0.2, 0.4))
	Props.words(tall, "THIS WAY", p.pt(2.6, 44.08, 1.47), 0.09, Color(0.15, 0.2, 0.4))
	# The sides: chain link and wire down to the building on the left, and between the walk and the vehicle lane.
	for u: float in [0.0, 19.0]:
		p.fence(st, false, u, 39.0, 44.0, [], 3.0, "chain")
		Jail.wire_on(p, n, false, u, 39.0, 44.0, [], 3.0)
	# The ground: the lane's asphalt, the lawns, the walk to the door, grass and trees beyond the fence.
	Kit.box(n, Vector3(13.0, 0.3, 4.925), p.pt(25.5, 41.5375, -0.154), Outdoor.road())
	for lawn: Array in [[0.4, 39.4, 3.3, 43.6], [6.1, 39.4, 18.6, 43.6]]:
		Kit.box(n, Vector3(lawn[2] - lawn[0], 0.012, lawn[3] - lawn[1]), p.pt((lawn[0] + lawn[2]) * 0.5, (lawn[1] + lawn[3]) * 0.5, 0.006), grass)
	for side: Array in [[-8.0, 0.0], [32.0, 40.0]]:
		Kit.box(n, Vector3(side[1] - side[0], 0.3, 11.0), p.pt((side[0] + side[1]) * 0.5, 38.5, -0.156), grass)
	Outdoor.tree(p, st, -3.2, 41.4, "a", 1.0, 30.0)
	Outdoor.tree(p, st, -2.4, 35.6, "c", 0.9, 110.0)
	Outdoor.tree(p, st, 35.2, 41.8, "b", 1.05, 200.0)
	Outdoor.shrub(p, st, 1.2, 39.9, "a", 0.8, 0.0)
	Outdoor.shrub(p, st, 7.75, 39.9, "b", 0.8, 40.0)      # (clear of the bin)
	Jail.flagpole(p, st, 10.2, 41.5)
	Jail.name_wall(p, st, 14.4, 42.9, 0.0, "COUNTY JAIL")
	Park.park_bench(p, st, 15.6, 39.55, 0.0, 1.9)
	Props.bin(p, st, 6.7, 39.5)
	Props.street_lamp(p, st, -1.4, 46.25)
	Props.street_lamp(p, st, 24.0, 46.25)
	Props.hydrant(p, st, 11.6, 46.2)
	p.person(st, "vic", 1.4, 45.4, {"face": "bored"})
	# The pavement's right end goes on to the civic row, at the police station's
	# left end (its TO THE COUNTY JAIL comes back). Held, he cannot get out here,
	# and the trip is refused anyway (prison_rules.gd's may_go). (Placeholder: the
	# label; the civic worker's.)
	p.use_point(st, "TO THE POLICE STATION", 37.25, 45.25, "goto:police", 1.2, 1.9)
	# He comes in at that end, and from there the camera looked out past the
	# right-hand lawn onto nothing: ground on out past it and down the
	# building's side (a few mm under the lawn's, so no face is shared).
	var rough := Outdoor.tex("out_dead_grass", 2.4, Color(0.36, 0.34, 0.22), Color(0.72, 0.7, 0.6))
	Kit.box(n, Vector3(29.99, 0.3, 11.0), p.pt(55.005, 38.5, -0.162), grass)          # u 40.01 .. 70, v 33 .. 44
	Kit.box(n, Vector3(37.92, 0.3, 22.98), p.pt(51.04, 21.5, -0.162), rough)          # u 32.08 .. 70, v 10.01 .. 32.99
	Kit.box(n, Vector3(43.99, 0.3, 49.99), p.pt(68.005, -15.005, -0.162), rough)      # u 46.01 .. 90, v -40 .. 9.99 (past the yard's)


## The building's front: concrete block on a plinth under a coping, the double
## doors of the visitors' entrance under a flat canopy, barred windows, slit
## windows over them, the sally port's roll-up door, a camera on the corner.
static func _facade(p: Node3D, front: Node3D) -> void:
	var f := 39.075
	var stone := Color(0.62, 0.62, 0.6)
	for run: Array in [[-0.03, 3.49], [5.51, 21.33], [29.67, 32.03]]:
		p.slab(front, true, f + 0.03, run[0], run[1], 0.0, 0.55, 0.06, stone)
	p.slab(front, true, 39.0, -0.07, 32.07, 4.8, 4.93, 0.32, Color(0.5, 0.5, 0.5))
	# The canopy over the doors, on two posts.
	p.slab(front, true, f + 0.8, 2.8, 6.2, 2.75, 2.95, 1.6, Color(0.3, 0.33, 0.38))
	p.slab(front, true, f + 1.605, 2.8, 6.2, 2.62, 2.75, 0.03, Color(0.3, 0.33, 0.38))
	for u: float in [3.0, 6.0]:
		Kit.cyl(front, 0.06, 2.75, p.pt(u, 40.5, 1.375), Color(0.3, 0.33, 0.38), Vector3.ZERO, 8)
		p.block(u - 0.08, 40.42, u + 0.08, 40.58)
	Props.words(front, "VISITOR ENTRANCE", p.pt(4.5, 40.7, 2.82), 0.11, SIGN)
	Props.words(front, "COUNTY JAIL", p.pt(4.5, f + 0.03, 4.12), 0.42, Color(0.14, 0.18, 0.28))      # (over the wire on the fence, seen from the street)
	Props.words(front, "SALLY PORT", p.pt(25.5, f + 0.03, 4.25), 0.3, Color(0.14, 0.18, 0.28))
	Jail.rollup(p, front, 39.0, 1.0, 21.5, 29.5, 3.6)
	for u: float in [1.6, 7.6, 12.5, 16.9]:
		Jail.slit(p, front, 39.0, 1.0, u, 3.05, 1.3)
	for u: float in [20.4, 30.6]:
		Jail.slit(p, front, 39.0, 1.0, u, 1.4, 2.2)
	In.camera(p, front, 9.8, f + 0.005, 0.0, 3.4)
	In.camera(p, front, 31.6, f + 0.005, 0.0, 4.3)
	for u: float in [3.15, 5.85]:
		In.sconce(p, front, u, f + 0.005, 0.0, "cage", 2.3)


# ------------------------------------------------------- the visitors' side

## The lobby and the visiting room (band b), and the inmates' side of the glass
## (band inside): its handsets hang on the glass wall's own node (`glass`), so
## they go with the wall when it is cut away.
static func _visiting(p: Node3D, b: int, inside: int, glass: Node3D) -> void:
	var n: Node3D = p.node_of(b)
	# The lobby: the check-in counter at the control room's window, lockers for
	# what visitors may not take in, seats, the drinks machine, the walk-through
	# detector before the visiting room's door.
	var desk := Props.counter(p, b, 2.0, 33.3, 0.0, 2.6, 0.4, 1.02, Color(0.4, 0.44, 0.5))
	Kit.box(desk, Vector3(0.36, 0.02, 0.22), Vector3(0.6, 1.03, 0.0), Props.PAPER)
	Props.words(n, "VISITOR CHECK-IN", p.pt(2.0, 33.09, 2.32), 0.12, Color(0.12, 0.2, 0.24))
	Props.lockers(p, b, 0.335, 36.4, 90.0, 6)
	Props.words(n, "VISITOR LOCKERS", p.pt(0.09, 36.4, 2.15), 0.12, Color(0.12, 0.2, 0.24), 90.0)
	Props.seats(p, b, 9.6, 34.6, 270.0, 4)
	Props.vending(p, b, 8.4, 33.5)
	Jail.walk_frame(p, b, 9.2, 37.45, 90.0)
	Props.words(n, "VISITING", p.pt(9.91, 37.45, 2.45), 0.12, Color(0.12, 0.2, 0.24), 270.0)
	Props.words(n, "ALL VISITORS SUBJECT TO SEARCH", p.pt(9.91, 34.6, 1.6), 0.07, RED, 270.0)
	Props.board(p, b, 4.85, 33.08, 0.0, 1.0, "notices")
	Props.words(n, "VISITING HOURS", p.pt(4.85, 33.09, 2.25), 0.1, Color(0.12, 0.2, 0.24))
	Props.clock(p, b, 0.08, 34.3, 90.0, 2.3)
	Props.words(n, "NO ADMITTANCE", p.pt(6.9, 33.09, 2.28), 0.1, RED)
	Jail.intercom(p, b, 5.95, 33.08, 0.0, 1.35)
	Props.plant(p, b, 9.5, 38.5)
	p.person(b, "nia", 3.0, 35.3, {"face": "nervous"})          # waiting to check in (off the line from the door to the gate)
	# The visiting room: three booths along the glass at its back, a handset in
	# each, seats for those waiting, the officer by the door.
	Jail.booths(p, n, 33.0, 1.0, 10.2, 18.8, BOOTHS, 0.2, true)
	Props.seats(p, b, 18.6, 36.6, 270.0, 3)
	Props.poster(p, b, 10.08, 35.3, 90.0, 0.5, 0.7, Color(0.3, 0.45, 0.6), "NO CONTACT", 1.6)
	p.person(b, "kesha", 17.5, 34.2, {"face": "sad"})
	p.person(b, "cop", 18.3, 38.3, {"face": "bored"})
	# The inmates' side of the glass: the booths' backs, two at the windows, the door in from the corridor.
	Jail.booths(p, p.node_of(inside), 33.0, -1.0, 10.2, 18.8, BOOTHS, 0.12, false, 0.12, glass)
	In.wall_strip(p, inside, 15.0, 31.08, 0.0, 1.0, 2.62)
	p.person(inside, "tre", 14.5, 32.5, {"name": "TRE", "talk": "talk_prison_visit.json", "face": "smug", "wear": JUMPSUIT})
	p.person(inside, "chuy", 17.5, 32.5, {"face": "happy", "wear": JUMPSUIT})
	# The sally port: the van backed up to the booking door, the gun lockers, bollards and cones.
	Props.car(p, b, 27.6, 35.4, 90.0, "van")
	p.block(25.25, 34.3, 29.95, 36.5)          # (a margin round the van: its bumpers stand out past its own floor space)
	Jail.gun_lockers(p, b, 19.08, 36.8, 90.0)
	p.block(19.075, 36.35, 19.4, 37.25)
	Jail.bollard(p, b, 19.9, 33.55)
	Jail.bollard(p, b, 21.9, 33.55)
	Jail.cone(p, b, 23.6, 38.3)
	Jail.cone(p, b, 24.3, 38.45)
	Props.words(n, "BOOKING", p.pt(20.9, 33.09, 2.3), 0.13, Color(0.12, 0.12, 0.14))
	p.person(b, "cop", 23.4, 37.0, {"face": "focused"})


# ------------------------------------------------------------- intake

static func _intake(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Control: the officer at the glass, the console, the monitors.
	Props.radio(p, b, 1.8, 29.9, 0.0)
	Props.chair(p, b, 1.8, 30.85, 180.0, Color(0.2, 0.22, 0.26))
	Jail.monitors(p, b, 2.0, 27.08, 0.0, 3, 2, 1.45)
	p.person(b, "cop", 1.2, 32.55, {"name": "DESK OFFICER", "talk": "talk_prison_desk.json", "face": "bored"})
	# The corridor: a trusty mopping, an officer, the doors marked.
	Jail.mop_bucket(p, b, 8.7, 29.7)
	Jail.wet_floor(p, b, 9.4, 31.4, 20.0)
	p.person(b, "snoozy", 7.8, 29.4, {"face": "bored", "wear": JUMPSUIT})
	p.person(b, "cop", 14.8, 28.1, {"face": "focused"})
	Props.words(n, "MESS HALL", p.pt(8.45, 27.09, 2.3), 0.12, Color(0.12, 0.14, 0.2))
	Props.words(n, "MEDICAL", p.pt(15.95, 27.09, 2.3), 0.12, Color(0.12, 0.14, 0.2))
	Props.words(n, "UNIT A", p.pt(12.5, 27.09, 2.65), 0.16, Jail.SAFETY)
	Props.words(n, "CONTROL", p.pt(4.09, 28.45, 2.3), 0.11, Color(0.12, 0.14, 0.2), 90.0)
	# Booking: the height chart and the yellow box in front of it, the camera, the
	# counter, the property window into the clothes store behind, the cuff bench.
	Props.height_chart(p, b, MARK.x, 27.12)
	In.mat(p, b, MARK.x, MARK.y, 0.72, 0.56, Kit.tex("lino", 1.6, Color(0.45, 0.5, 0.48), true, Color(0.62, 0.64, 0.62)), Jail.SAFETY)
	Props.tripod(p, b, MARK.x, 30.0, 180.0)
	var counter := Props.counter(p, b, 25.0, 30.4, 0.0, 3.0, 0.65, 1.05, Props.OFFICE.darkened(0.15))
	Kit.bevel(counter, Vector3(0.48, 0.34, 0.06), Vector3(0.7, 1.28, -0.12), Props.DARK, 0.015)
	Kit.box(counter, Vector3(0.42, 0.27, 0.01), Vector3(0.7, 1.29, -0.087), Kit.flat(Color(0.5, 0.66, 0.74), 0.8))
	Kit.box(counter, Vector3(0.05, 0.14, 0.05), Vector3(0.7, 1.11, -0.15), Props.DARK)
	Kit.box(counter, Vector3(0.3, 0.02, 0.4), Vector3(-0.6, 1.06, 0.0), Props.PAPER)
	Kit.block(counter, Vector3(0.2, 0.06, 0.16), Vector3(-1.1, 1.05, 0.05), Props.DARK)        # the print scanner
	var ledge := Props.counter(p, b, 23.0, 27.33, 0.0, 1.7, 0.36, 0.98, Props.OFFICE.darkened(0.15))
	Kit.box(ledge, Vector3(0.3, 0.06, 0.22), Vector3(0.3, 1.01, 0.0), Color(0.86, 0.84, 0.78))
	Props.words(n, "PROPERTY", p.pt(23.0, 27.09, 2.2), 0.13, INK)
	Props.words(n, "BOOKING", p.pt(25.4, 27.09, 2.22), 0.16, INK)
	var cuffs := Props.bench(p, b, 19.4, 31.4, 90.0, 1.8, Props.IRON)
	Kit.box(cuffs, Vector3(1.8, 0.04, 0.04), Vector3(0, 0.75, -0.2), Props.STEEL)
	p.person(b, "cop", 25.0, 29.7, {"name": "BOOKING OFFICER", "talk": "talk_prison_booking.json", "face": "focused"})
	# Holding: benches round the walls, the steel toilet in the corner.
	Props.bench(p, b, 30.0, 27.4, 0.0, 3.0, Props.IRON)
	Props.bench(p, b, 31.6, 30.4, 270.0, 2.0, Props.IRON)
	Props.cell_toilet(p, b, 31.6, 32.45, 270.0)
	Props.words(n, "HOLDING", p.pt(30.0, 27.09, 2.25), 0.16, INK)
	p.person(b, "ronnie", 29.2, 29.6, {"face": "angry"})
	p.person(b, "rell", 31.0, 28.1, {"face": "sad"})          # (at the back: at the front he stands between the camera and anyone in here)


# ------------------------------------------------------- behind the corridor

static func _services(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The mess hall: the serving line, tables with their benches fixed to them.
	Jail.serving_line(p, b, 2.4, 22.6, 0.0, 3.6)
	p.person(b, "doc", 2.4, 21.75, {"face": "content", "wear": JUMPSUIT})
	for i in 3:
		var t := Jail.mess_table(p, b, 2.4 + i * 3.2, 25.0, 0.0, 2.4)
		for k in 2:
			Jail.tray(t, Vector3(-0.6 + k * 1.1, 0.78, 0.18 if (i + k) % 2 == 0 else -0.18), 0.0 if k == 0 else 180.0)
	Props.board(p, b, 8.4, 21.08, 0.0, 1.4, "notices")
	Props.words(n, "MENU", p.pt(8.4, 21.09, 2.22), 0.13, Color(0.4, 0.2, 0.08))
	Props.clock(p, b, 6.4, 21.08, 0.0, 2.35)
	p.person(b, "huff", 1.8, 23.6, {"face": "bored", "wear": JUMPSUIT})        # in line at the serving counter (left of the server, or they stack)
	p.person(b, "cop", 10.2, 22.4, {"face": "focused"})
	# The block gate: barred both ends, a call box.
	Jail.intercom(p, b, 11.08, 24.0, 90.0, 1.35)
	# Treatment: the trolley bed, a sink, gloves and sharps on the wall, the emergency trolley.
	Props.gurney(p, b, 16.2, 21.6, 90.0)
	Props.basin(p, b, 14.32, 25.0, 90.0)
	In.gloves(p, b, 14.08, 23.4, 90.0, 1.6)
	In.sharps(p, b, 14.08, 24.0, 90.0, 1.35)
	Props.crash_cart(p, b, 17.55, 25.8, 270.0)
	Props.iv_stand(p, b, 17.5, 22.7)
	p.person(b, "nurse", 14.9, 22.9, {"face": "neutral"})       # by the bed (not in the middle of the floor, where he would stand)
	# The change room: issue shelving (jumpsuits, towels, sandals), the bench along the wall, the laundry cart.
	Jail.issue_shelf(p, b, 20.0, 21.33, 0.0, 1.6)
	Props.bench(p, b, 21.6, 24.0, 270.0, 1.8, Props.IRON)
	Jail.cart(p, b, 18.8, 25.9, 90.0)
	Props.words(n, "ISSUE", p.pt(20.0, 21.09, 2.22), 0.12, Color(0.14, 0.16, 0.2))
	# Property: his own clothes and everyone else's, bagged and tagged.
	Jail.property_shelf(p, b, 23.0, 21.33, 0.0, 1.8)
	Jail.property_shelf(p, b, 23.68, 24.0, 270.0, 2.6)
	p.person(b, "clerk", 22.6, 22.0, {"face": "bored"})
	# Segregation: the officer at his desk by the steel door to the hole, a red line on the floor.
	Props.desk(p, b, 26.9, 25.9, 0.0, Props.OFFICE.darkened(0.2), 1, false, 1.4, 0.7)
	In.hatch(p, b, 26.0, 22.0, 1, 3.7, 0.08, 0.0, RED)
	Park.ground_words(n, "NO INMATES BEYOND THIS LINE", p.pt(26.0, 22.42, 0.006), 0.16, RED)
	Props.words(n, "SEGREGATION", p.pt(26.0, 21.09, 2.3), 0.13, INK)
	p.person(b, "cop", 26.9, 25.0, {"name": "SEG OFFICER", "talk": "talk_prison_seg.json", "face": "focused"})
	# The hole: a slab bed and a steel toilet, and nothing else.
	Jail.slab_bed(p, b, 30.4, 21.6, 0.0)
	Props.cell_toilet(p, b, 31.6, 24.6, 270.0)


# ----------------------------------------------------------- the cell block

static func _unit(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The stair up to the catwalk, along the left wall.
	Jail.stairs(p, b, 0.6, 16.23, 0.0, 0.95, 3.6, TIER)
	p.portal(b, "GO UPSTAIRS", 0.6, 18.5, UP + 0.9, 13.6)
	# The dayroom: tables and stools bolted down, the officer's station, the phones, the television.
	for row: float in [16.3, 19.2]:
		for u: float in [4.6, 8.4, 12.2]:
			Jail.steel_table(p, b, u, row, Jail.PAINTED, 45.0 if row < 18.0 else 0.0)
	Jail.station(p, b, 17.6, 18.6, 0.0, 2.2, "A")
	_box_line(p, b, 15.9, 16.7, 19.3, 19.5, 0.08, RED)
	Jail.phones(p, b, 25.92, 14.6, 270.0, 3)
	Props.wall_tv(p, b, 25.92, 20.0, 270.0, 3.0)
	Props.words(n, "UNIT A", p.pt(0.09, 19.6, 3.6), 0.5, Jail.SAFETY, 90.0)
	Props.words(n, "SHOWERS", p.pt(25.91, 17.8, 2.6), 0.12, Color(0.12, 0.14, 0.2), 270.0)
	Props.words(n, "YARD", p.pt(23.0, 10.09, 2.3), 0.14, Color(0.12, 0.14, 0.2))
	p.person(b, "cop", 17.6, 17.6, {"name": "C.O.", "talk": "talk_prison_guard.json", "face": "bored"})
	p.person(b, "dee", 22.6, 19.6, {"name": "BIG DEE", "talk": "talk_prison_dayroom.json", "face": "smug", "wear": JUMPSUIT})
	p.person(b, "chuy", 8.4, 17.75, {"face": "neutral", "wear": JUMPSUIT})
	p.person(b, "huff", 12.2, 17.75, {"face": "content", "wear": JUMPSUIT})
	p.person(b, "cop", 21.4, 13.5, {"face": "bored"})          # by the yard hall's gate, outside it
	# The showers: four heads along the back wall with tiled half walls between, a bench.
	for i in 4:
		Jail.shower(p, b, 26.8 + i * 1.5, 10.08, 0.0)
	for i in 3:
		Jail.shower_wall(p, b, 27.55 + i * 1.5, 10.64, 0.0, 1.1, 1.8)
	Props.bench(p, b, 31.6, 17.5, 270.0, 2.4, Props.IRON)
	for i in 4:
		Kit.cyl(n, 0.07, 0.006, p.pt(26.8 + i * 1.5, 11.0, 0.003), Props.DARK, Vector3.ZERO, 10)      # the drains


## A line painted on the floor round a box (u0, v0)..(u1, v1), w wide.
static func _box_line(p: Node3D, b: int, u0: float, v0: float, u1: float, v1: float, w: float, look: Color) -> void:
	In.hatch(p, b, (u0 + u1) * 0.5, v0, 1, u1 - u0 + w, w, 0.0, look)
	In.hatch(p, b, (u0 + u1) * 0.5, v1, 1, u1 - u0 + w, w, 0.0, look)
	In.hatch(p, b, u0, (v0 + v1) * 0.5, 1, w, v1 - v0 - w, 0.0, look)
	In.hatch(p, b, u1, (v0 + v1) * 0.5, 1, w, v1 - v0 - w, 0.0, look)


## In each cell of the lower tier: the bunk along its right wall, the steel toilet
## at the back, its number on the catwalk's yellow edge over its door; his own
## bunk is the one E is used on.
static func _cells(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	for k in 8:
		var a := k * 2.5
		Props.bunk(p, b, a + 2.0, 11.05, 90.0)
		Props.cell_toilet(p, b, a + 0.45, 10.4)
		Props.words(n, str(101 + k), p.pt(a + 0.8, 14.42, (DECK + TIER) * 0.5), 0.14, INK)
	p.use_point(b, "SLEEP", 9.45, 11.3, "prison:bunk", 1.1, 1.0)
	# days scratched on the wall of his cell
	for k in 9:
		Kit.box(n, Vector3(0.012, 0.16, 0.004), p.pt(8.2 + k * 0.045 + (0.03 if k > 4 else 0.0), 10.088, 1.45), Color(0.24, 0.26, 0.3), Vector3(0, 0, 62.0 if k == 4 else 0.0))
	p.person(b, "snoozy", 13.1, 11.7, {"face": "content", "wear": JUMPSUIT})


## What is seen of the upper tier from the dayroom: the catwalk and the upper
## cells' floor in one slab over the lower cells' fronts, its railing, the
## upper cells (bars over a door every 2.5 m, the walls between, a bunk in
## each), the wall over the yard hall. Nobody walks it here: the upper tier
## that is walked is level 1 (_upper).
static func _upper_seen(p: Node3D, b: int, block: Variant) -> void:
	var n: Node3D = p.node_of(b)
	var paint := Jail.PAINTED.darkened(0.1)
	Kit.box(n, Vector3(20.0, TIER - DECK, 4.325), p.pt(10.075, 12.2375, (DECK + TIER) * 0.5), Color(0.5, 0.52, 0.55))
	p.slab(n, true, 14.405, 0.075, 20.075, DECK + 0.03, TIER - 0.03, 0.01, Jail.SAFETY)
	# The railing along the catwalk's edge, from the stair head.
	for y: float in [TIER + 0.5, TIER + 1.03]:
		p.slab(n, true, 14.3, 1.1, 20.0, y, y + 0.05, 0.05, paint)
	var post := 1.1
	while post < 19.5:
		Kit.box(n, Vector3(0.05, 1.08, 0.04), p.pt(post, 14.3, TIER + 0.54), paint)
		post += 1.2
	Kit.box(n, Vector3(0.05, 1.08, 0.04), p.pt(19.97, 14.3, TIER + 0.54), paint)
	# The upper cells: their walls, the bars and the header over them, the numbers.
	for k in range(1, 9):
		p.slab(n, false, k * 2.5, 10.075, 12.55, TIER, 5.5, 0.15, block)       # (their ends behind the bars' rails)
	Jail.bar_screen(p, n, 12.6, 0.075, 20.0, TIER, 5.5)
	p.slab(n, true, 12.6, 0.075, 25.925, 5.5, HIGH, 0.15, block)
	p.slab(n, true, 12.6, 20.075, 25.925, 2.4, 5.5, 0.15, block)
	for k in 8:
		var a := k * 2.5
		Props.words(n, str(201 + k), p.pt(a + 0.8, 12.69, 5.75), 0.14, INK)
		Kit.box(n, Vector3(0.8, 0.07, 1.9), p.pt(a + 2.0, 11.05, TIER + 0.42), Props.IRON)
		Kit.box(n, Vector3(0.7, 0.08, 1.8), p.pt(a + 2.0, 11.05, TIER + 0.495), Color(0.6, 0.62, 0.55))


## The upper tier itself (level 1, drawn at u + UP): the catwalk, eight cells
## off it with barred doors, the rail along its edge, and the dayroom seen
## below over the rail (2.9 m down: not walked from here).
static func _upper(p: Node3D, b: int, block: Variant, sealed: Variant) -> void:
	var n: Node3D = p.node_of(b)
	var paint := Jail.PAINTED.darkened(0.1)
	var cell := {"lower": _paint(Color(0.62, 0.7, 0.78)), "upper": _paint(Color(0.88, 0.9, 0.9)), "dado": Color(0.3, 0.38, 0.46), "h": 2.58}
	p.cross(b, 10.0, UP, UP + 26, block, [], {"back": true, "h": HIGH - TIER})
	p.side(b, UP, 10, 14.4, block, [], {"h": HIGH - TIER})
	p.side(b, UP + 20.0, 10, 14.4, block, [], {"h": HIGH - TIER})
	for k in range(1, 8):
		p.side(b, UP + k * 2.5, 10, 12.6, block, [], {"h": 2.6})
	var gaps: Array = []
	for k in 8:
		gaps.append([UP + k * 2.5 + 0.3, UP + k * 2.5 + 1.3])
	p.bars(b, true, 12.6, UP, UP + 20.0, gaps, 2.6)
	p.slab(n, true, 12.6, UP + 0.075, UP + 19.925, 2.6, HIGH - TIER, 0.15, block)
	p.rail(b, true, 14.4, UP + 1.1, UP + 19.925, paint, 1.05)
	for k in 8:
		var a := UP + k * 2.5
		In.room_walls(p, b, a, 10, a + 2.5, 12.6, cell, [], [], [])
		Props.bunk(p, b, a + 2.0, 11.05, 90.0)
		Props.cell_toilet(p, b, a + 0.45, 10.4)
		Props.words(n, str(201 + k), p.pt(a + 0.8, 12.69, 2.85), 0.14, INK)
		In.sconce(p, b, a + 1.25, 10.08, 0.0, "cage", 2.3)
	In.wall_strip(p, b, UP + 6.9, 12.68, 0.0, 1.2, 2.85)
	In.wall_strip(p, b, UP + 14.4, 12.68, 0.0, 1.2, 2.85)
	Kit.omni(n, p.pt(UP + 10.0, 13.6, 2.4), Color(1.0, 0.96, 0.88), 0.45, 10.0)
	p.portal(b, "GO DOWNSTAIRS", UP + 0.6, 14.0, 0.75, 18.6)
	var stair: Node3D = Jail.stairs(p, b, UP + 0.6, 16.23, 0.0, 0.95, 3.6, TIER)
	stair.position.y -= TIER
	# Below the rail: the dayroom's floor (in under the catwalk too), its walls, its tables, the station;
	# under the catwalk, seen over its edge, its yellow edge and the lower tier's barred fronts (a dim
	# cell behind each, the walls between), or the gap under it is a hole into nothing.
	Kit.box(n, Vector3(26.0, 0.3, 8.4), p.pt(UP + 13.0, 16.8, -TIER - 0.15), sealed)
	p.slab(n, true, 14.405, UP + 0.075, UP + 19.925, DECK - TIER + 0.02, -0.02, 0.01, Jail.SAFETY)
	Jail.bar_screen(p, n, 12.6, UP + 0.075, UP + 19.98, -TIER, DECK - TIER, 2.5, -0.075)       # (short of the floors' ends at UP + 20)
	p.slab(n, true, 11.2, UP + 0.075, UP + 19.925, -TIER, DECK - TIER, 0.1, Color(0.36, 0.42, 0.5))
	for k in range(1, 8):
		p.slab(n, false, UP + k * 2.5, 11.25, 12.55, -TIER, DECK - TIER, 0.15, block)
	p.slab(n, false, UP, 11.25, 21.0, -TIER, -0.02, 0.15, block)       # the end wall below, its top under the floors' (no face shared)
	Kit.box(n, Vector3(5.85, 0.3, 2.45), p.pt(UP + 23.0, 11.3, -0.15), Color(0.5, 0.52, 0.55))     # over the yard hall (up to the wall over its gate)
	p.slab(n, true, 12.6, UP + 20.075, UP + 25.925, -0.5, 0.0, 0.15, block)
	Jail.bar_screen(p, n, 12.6, UP + 20.075, UP + 25.925, -TIER, -0.5, 99.0, 2.125)       # (its door where the yard hall's gate is)
	p.slab(n, false, UP, 14.4, 21.0, -0.02, HIGH - TIER, 0.15, block)
	p.slab(n, false, UP + 26.0, 10.0, 21.0, -TIER, HIGH - TIER, 0.15, block)
	for row: float in [16.3, 19.2]:
		for u: float in [4.6, 8.4, 12.2]:
			var t: Node3D = Jail.steel_table(p, b, UP + u, row, Jail.PAINTED, 45.0 if row < 18.0 else 0.0)
			t.position.y -= TIER
	var desk: Node3D = Jail.station(p, b, UP + 17.6, 18.6, 0.0, 2.2, "A")
	desk.position.y -= TIER
	p.person(b, "dee", UP + 3.55, 11.6, {"face": "content", "wear": JUMPSUIT})        # in CELL 202 (not where he would stand in 203)
	p.person(b, "cop", UP + 14.0, 13.5, {"face": "bored"})


# ------------------------------------------------------------------- the yard

## The yard behind the cell block: chain link and razor wire on three sides, a
## second fence beyond with coils of wire on the ground between, the gun tower
## on the corner; inside, half a basketball court, weights, a pull-up bar and an
## out-of-bounds strip along the far fence.
static func _yard(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var line := Kit.flat(Park.LINE)
	var court := Color(0.42, 0.5, 0.58)
	p.fence(b, true, 0.0, 0.0, 32.0, [], 3.6, "chain")
	Jail.wire_on(p, n, true, 0.0, 0.0, 32.0, [], 3.6)
	for u: float in [0.0, 32.0]:
		p.fence(b, false, u, 0.0, 10.0, [], 3.6, "chain")
		Jail.wire_on(p, n, false, u, 0.0, 10.0, [], 3.6)
	# Beyond: the ground, the outer fence, the wire between, the tower, the sky.
	var dirt := Outdoor.tex("out_dead_grass", 2.4, Color(0.36, 0.34, 0.22), Color(0.72, 0.7, 0.6))
	Kit.box(n, Vector3(60.0, 0.3, 20.0), p.pt(16.0, -10.04, -0.156), dirt)
	for side: Array in [[-14.0, -0.04], [32.04, 46.0]]:
		Kit.box(n, Vector3(side[1] - side[0], 0.3, 10.0), p.pt((side[0] + side[1]) * 0.5, 5.0, -0.156), dirt)
	p.fence(b, true, -4.0, -6.0, 38.0, [], 3.6, "chain")
	Jail.wire_on(p, n, true, -4.0, -6.0, 38.0, [], 3.6)
	Jail.razor(n, p.pt(-5.5, -2.0, 0.24), p.pt(37.5, -2.0, 0.24), 0.26)
	Jail.tower(p, n, -3.0, -7.6, 7.0)
	var sky: Node3D = Outdoor.backdrop(n, p.pt(16.0, -40.0), [Color(1.0, 0.72, 0.42), Color(0.88, 0.48, 0.56), Color(0.3, 0.25, 0.54)], Vector3.INF, 6.0, 900.0, Vector2(-0.85, -0.5))
	Jail.sky_outside(p, b, sky, 10.0, 39.0)          # (from inside, no open sky over the walls)
	# Half a court painted on the concrete, the hoop's pole at the back fence (its
	# rim 2.475 m out from the pole, the baseline 0.9 m), the key, the free-throw
	# circle and a three-point line cut short to fit the yard.
	var pole := 0.45
	var base := pole + 0.9
	var rim := pole + 2.475
	var ft := base + 5.8
	var r3 := 5.2
	var cut := 0.32
	Kit.box(n, Vector3(11.4, 0.006, 9.0), p.pt(6.3, 4.8, 0.003), court)
	Kit.box(n, Vector3(4.9, 0.006, 5.8), p.pt(6.3, base + 2.9, 0.007), Color(0.62, 0.3, 0.24))
	Kit.box(n, Vector3(11.2, 0.006, 0.1), p.pt(6.3, base, 0.011), line)
	Kit.box(n, Vector3(5.0, 0.006, 0.1), p.pt(6.3, ft, 0.011), line)
	for u: float in [3.85, 8.75]:
		Kit.box(n, Vector3(0.1, 0.006, 5.7), p.pt(u, base + 2.9, 0.011), line)
	Park.arc(n, p.pt(6.3, ft, 0.011), 1.8, 0.0, PI, 0.1, 0.006, line)
	Park.arc(n, p.pt(6.3, rim, 0.011), r3, cut, PI - cut, 0.1, 0.006, line)
	for s: float in [-1.0, 1.0]:
		var top := rim + r3 * sin(cut)
		Kit.box(n, Vector3(0.1, 0.006, top - base - 0.05), p.pt(6.3 + s * r3 * cos(cut), (base + top) * 0.5 + 0.025, 0.011), line)
	Park.hoop(p, b, 6.3, pole, 0.0)
	Park.ball(n, p.pt(8.2, 5.4), 30.0)
	# Weights on a rubber mat, the pull-up bars, benches by the wall.
	Jail.gym_mat(p, b, 21.4, 2.1, 5.0, 2.4)
	Props.weights(p, b, 20.0, 2.0, 0.0)
	Props.weights(p, b, 22.9, 2.0, 0.0)
	Jail.pullup(p, b, 26.6, 1.1, 0.0)
	Props.bench(p, b, 15.2, 9.4, 180.0, 2.2, Props.IRON)
	# Out of bounds: a red line and red stripes along the right-hand fence.
	In.hatch(p, b, 30.2, 5.1, 1, 0.08, 9.6, 0.0, RED)
	for i in 11:
		Kit.box(n, Vector3(1.6, 0.006, 0.12), p.pt(31.05, 0.6 + i * 0.75, 0.005), RED, Vector3(0, 35.0, 0))
	Park.ground_words(n, "OUT OF BOUNDS", p.pt(31.08, 9.2, 0.008), 0.17, RED)
	p.person(b, "tre", 8.0, 6.6, {"face": "happy", "wear": JUMPSUIT})
	p.person(b, "doc", 21.5, 3.9, {"face": "focused", "wear": JUMPSUIT})
	p.person(b, "cop", 28.2, 8.4, {"face": "bored"})
