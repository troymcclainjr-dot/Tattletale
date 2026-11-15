extends RefCounted
## The courthouse: a district court. A tired 1970s building, not a marble
## palace: brown brick, lino, worn pews, one courtroom. 18 x 22.5 m inside, one
## floor, four bands from the street back:
##
##   security lobby | clerk's office      everyone is screened at the door
##   lawyer room | public hall
##   lockup, holding cell | courtroom | jury room
##   records | judge's chambers
##
## Three ways in that never mix: the public by the hall, the judge from
## chambers, prisoners from the lockup straight into the well of the court.
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 22.5.
##
## The front is the 1970s idea of a courthouse: brick and precast concrete, a
## portico of two columns and a pediment over the doors, a second floor of tall
## windows between concrete fins. Inside, each room is dressed its own way
## (props_in.gd): the lobby green marble and cream, the hall walnut and oxblood,
## the courtroom walnut and federal blue with a panelled wall behind the bench,
## the clerk's office oak and butter yellow, the jury room 1970s oak and avocado,
## chambers walnut and green stripe, the cells glazed tile, records grey block.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")

const WALNUT := Color(0.36, 0.22, 0.13)
const WALNUT_DARK := Color(0.24, 0.14, 0.08)
const GILT := Color(0.8, 0.64, 0.28)
const CREAM := Color(0.92, 0.88, 0.76)


static func build(p: Node3D) -> void:
	p.setup("COURTHOUSE", 18.0, 22.5)
	var beige := Kit.tex("stucco", 2.0, Color(0.8, 0.76, 0.64), true, Color(0.95, 1.0, 0.86))
	var panel := Kit.tex("wood_panel", 1.2, Color(0.5, 0.33, 0.2), true, Color(0.5, 0.44, 0.48))      # dark oak
	var block := Kit.tex("block_plain", 1.2, Color(0.62, 0.64, 0.68), true, Color(0.68, 0.71, 0.78))
	var lino := Kit.tex("lino", 1.6, Color(0.66, 0.6, 0.5), true, Color(1.0, 0.86, 0.72))
	var boards := Kit.tex("in_boards", 1.4, Color(0.5, 0.36, 0.22), true, Color(0.8, 0.58, 0.38))     # honey oak boards
	var carpet := Kit.tex("carpet", 2.0, Color(0.45, 0.14, 0.18), true, Color(0.95, 0.8, 0.85))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.28, 0.2), true, Color(0.78, 0.74, 0.66))
	var strip := Color(1.0, 0.96, 0.84)
	var oak := Color(0.36, 0.24, 0.15)
	var steel_door := Color(0.36, 0.4, 0.44)

	var st: int = p.street(-4.0, 22.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	var b4: int = p.band()
	p.arrive = p.pt(6.0, 23.7)

	p.room("SECURITY LOBBY", b1, 0, 17.5, 11, 22.5, lino, {"light": strip})
	p.room("CLERK'S OFFICE", b1, 11, 17.5, 18, 22.5, lino, {"light": strip})
	p.room("LAWYER ROOM", b2, 0, 13.5, 4, 17.5, lino, {"light": strip})
	p.room("PUBLIC HALL", b2, 4, 13.5, 18, 17.5, lino, {"light": strip, "energy": 0.6})
	p.room("LOCKUP", b3, 0, 4.5, 3, 8.6, concrete, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("HOLDING CELL", b3, 0, 8.6, 3, 13.5, concrete)
	p.room("COURTROOM", b3, 3, 4.5, 15, 13.5, boards, {"light": strip, "energy": 0.75})
	p.room("JURY ROOM", b3, 15, 4.5, 18, 13.5, lino, {"light": strip, "energy": 0.4})
	p.room("RECORDS", b4, 0, 0, 9, 4.5, concrete, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("JUDGE'S CHAMBERS", b4, 9, 0, 18, 4.5, carpet, {"light": Color(1.0, 0.88, 0.7)})

	# The walls' openings, kept by name: the paint and trim stop at each (_walls).
	var bronze := Color(0.3, 0.25, 0.18)
	var ops := {
		"front": [
			{"a": 1.0, "b": 3.4, "kind": "window", "sill": 1.1, "head": 2.4, "frame": bronze},
			{"a": 5.1, "b": 6.9, "kind": "double", "head": 2.2, "colour": Color(0.32, 0.26, 0.18), "frame": bronze},
			{"a": 8.2, "b": 10.2, "kind": "window", "sill": 1.1, "head": 2.4, "frame": bronze},
			{"a": 12.4, "b": 16.6, "kind": "window", "sill": 1.1, "head": 2.4, "blinds": true, "frame": bronze},
		],
		"clerk": [{"a": 17.9, "b": 19.8, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.STEEL}],
		"hall": [
			{"a": 5.1, "b": 6.9, "kind": "arch"},
			{"a": 15.6, "b": 16.5, "swing": 1, "colour": oak},
		],
		"lawyer": [{"a": 13.8, "b": 14.7, "hinge": "a", "swing": -1, "colour": oak}],
		"court": [{"a": 8.1, "b": 9.9, "kind": "double", "swing": 1, "head": 2.2, "colour": oak}],
		"lockup": [{"a": 6.6, "b": 7.5, "hinge": "a", "swing": -1, "colour": steel_door}],
		"jury": [{"a": 5.3, "b": 6.2, "hinge": "a", "swing": 1, "colour": oak}],
		"chambers": [{"a": 13.3, "b": 14.2, "colour": oak}],
		"records": [{"a": 2.7, "b": 3.6, "hinge": "a", "swing": -1, "colour": oak}],
	}
	# The front is two floors: the offices upstairs are not ours to visit.
	var front: Node3D = p.cross(b1, 22.5, 0, 18, brick, ops["front"], {"h": 7.45})
	p.side(b1, 0.0, 17.5, 22.5, beige)
	p.side(b1, 18.0, 17.5, 22.5, beige)
	p.side(b1, 11.0, 17.5, 22.5, beige, ops["clerk"])

	p.cross(b2, 17.5, 0, 18, beige, ops["hall"])
	p.side(b2, 0.0, 13.5, 17.5, beige)
	p.side(b2, 18.0, 13.5, 17.5, beige)
	p.side(b2, 4.0, 13.5, 17.5, beige, ops["lawyer"])

	p.cross(b3, 13.5, 0, 18, panel, ops["court"])
	p.side(b3, 0.0, 4.5, 13.5, block)
	p.side(b3, 18.0, 4.5, 13.5, beige)
	p.side(b3, 3.0, 4.5, 13.5, panel, ops["lockup"])
	p.side(b3, 15.0, 4.5, 13.5, panel, ops["jury"])
	p.bars(b3, true, 8.6, 0.0, 3.0, [[1.0, 2.0]])

	p.cross(b4, 4.5, 0, 18, panel, ops["chambers"])
	p.cross(b4, 0.0, 0, 18, beige, [], {"back": true})
	p.side(b4, 0.0, 0, 4.5, beige)
	p.side(b4, 18.0, 0, 4.5, beige)
	p.side(b4, 9.0, 0, 4.5, beige, ops["records"])

	_street(p, st, front)
	_walls(p, b1, b2, b3, b4, ops)
	_lobby(p, b1)
	_hall(p, b2)
	_court(p, b3)
	_back(p, b4)


## Plaster, cloudy as plaster is, in a colour.
static func _plaster(c: Color) -> StandardMaterial3D:
	return Kit.tex("stucco", 2.0, c * 0.86, true, c)


## Each room's walls dressed, its floor edged, its lights on the walls.
static func _walls(p: Node3D, b1: int, b2: int, b3: int, b4: int, ops: Dictionary) -> void:
	var walnut_panel := Kit.tex("in_panel", 0.9, Color(0.4, 0.25, 0.15), true, Color(0.58, 0.36, 0.22))
	var oak_panel := Kit.tex("in_panel", 0.8, Color(0.62, 0.45, 0.28), true, Color(0.86, 0.62, 0.4))
	var cream := _plaster(Color(1.0, 0.96, 0.84))
	var lobby := {
		"lower": Kit.tex("in_marble", 1.2, Color(0.3, 0.46, 0.38), true, Color(0.4, 0.62, 0.5)),      # green marble
		"upper": cream, "dado": Color(0.5, 0.38, 0.2), "dado_y": 0.92,
		"skirt": Color(0.12, 0.15, 0.13), "skirt_h": 0.14, "cornice": CREAM,
	}
	var clerk := {
		"lower": oak_panel, "upper": _plaster(Color(1.0, 0.9, 0.56)), "dado": Color(0.45, 0.3, 0.17), "dado_y": 0.92,
		"skirt": Color(0.22, 0.16, 0.1), "skirt_h": 0.12,
	}
	var lawyer := {
		"lower": _plaster(Color(0.28, 0.54, 0.56)), "upper": Kit.tex("in_stripe", 0.7, Color(0.78, 0.86, 0.84), true, Color(0.86, 0.96, 0.94)),
		"dado": WALNUT, "skirt": WALNUT_DARK,
	}
	var hall := {
		"lower": walnut_panel, "upper": _plaster(Color(0.72, 0.28, 0.25)), "dado": WALNUT_DARK, "dado_y": 0.95,
		"skirt": WALNUT_DARK, "skirt_h": 0.14, "cornice": CREAM, "surround": WALNUT.darkened(0.1),
	}
	var court := {
		"lower": walnut_panel, "upper": _plaster(Color(0.3, 0.38, 0.6)), "dado": WALNUT_DARK, "dado_y": 1.1,
		"rail": GILT, "frieze": cream, "skirt": WALNUT_DARK, "cornice": CREAM, "surround": WALNUT.darkened(0.1),
	}
	var jury := {
		"lower": oak_panel, "upper": Kit.tex("in_trellis", 0.6, Color(0.6, 0.62, 0.36), true, Color(0.76, 0.8, 0.46)),
		"dado": Color(0.5, 0.34, 0.18), "dado_y": 0.95, "skirt": Color(0.3, 0.2, 0.12), "skirt_h": 0.12,
	}
	var cells := {
		"lower": Kit.tex("in_tile", 0.6, Color(0.62, 0.74, 0.62), true, Color(0.76, 0.9, 0.76)),       # glazed tile
		"upper": Kit.tex("block_plain", 1.2, Color(0.86, 0.84, 0.74), true, Color(0.98, 0.96, 0.86)),
		"dado": Color(0.18, 0.34, 0.26), "dado_y": 1.4, "skirt": Color(0.18, 0.34, 0.26), "skirt_h": 0.15,
	}
	var records := {
		"lower": Kit.tex("block_plain", 1.2, Color(0.44, 0.5, 0.56), true, Color(0.54, 0.62, 0.7)),
		"upper": Kit.tex("block_plain", 1.2, Color(0.86, 0.85, 0.78), true, Color(0.96, 0.95, 0.86)),
		"dado": Color(0.88, 0.7, 0.2), "dado_y": 1.2, "skirt": Color(0.14, 0.14, 0.16), "skirt_h": 0.12,
	}
	var chambers := {
		"lower": walnut_panel, "upper": Kit.tex("in_stripe", 0.8, Color(0.3, 0.45, 0.35), true, Color(0.44, 0.62, 0.5)),
		"dado": WALNUT_DARK, "rail": GILT, "frieze": cream, "skirt": WALNUT_DARK, "cornice": CREAM,
	}
	# The two doors that stay shut in the hall's right wall (_hall) are trimmed
	# like the real ones: each slab is the door, its frame is the trim's opening.
	var loos: Array = []
	for v: float in [15.6, 16.75]:
		loos.append({"a": v - 0.42 + In.FRAME, "b": v + 0.42 - In.FRAME, "head": 2.05 - In.FRAME})

	In.room_walls(p, b1, 0, 17.5, 11, 22.5, lobby, ops["hall"], [], ops["clerk"])
	In.room_walls(p, b1, 11, 17.5, 18, 22.5, clerk, ops["hall"], ops["clerk"], [])
	In.room_walls(p, b2, 0, 13.5, 4, 17.5, lawyer, ops["court"], [], ops["lawyer"])
	In.room_walls(p, b2, 4, 13.5, 18, 17.5, hall, ops["court"], ops["lawyer"], loos)
	# The lockup and the holding cell: one run each side, behind the bars too.
	In.dress(p, b3, true, 4.5, 1.0, 0.075, 2.925, [], cells)
	In.dress(p, b3, false, 0.0, 1.0, 4.575, 13.425, [], cells)
	In.dress(p, b3, false, 3.0, -1.0, 4.575, 13.425, ops["lockup"], cells)
	# The courtroom: the wall behind the bench is panelled to the cornice (_reredos).
	In.dress(p, b3, true, 4.5, 1.0, 3.075, 6.2, [], court)
	In.dress(p, b3, true, 4.5, 1.0, 6.2, 11.8, [], {"cornice": CREAM})
	In.dress(p, b3, true, 4.5, 1.0, 11.8, 14.925, ops["chambers"], court)
	In.dress(p, b3, false, 3.0, 1.0, 4.575, 13.425, ops["lockup"], court)
	In.dress(p, b3, false, 15.0, -1.0, 4.575, 13.425, ops["jury"], court)
	In.room_walls(p, b3, 15, 4.5, 18, 13.5, jury, [], ops["jury"], [])
	In.room_walls(p, b4, 0, 0, 9, 4.5, records, [], [], ops["records"])
	In.room_walls(p, b4, 9, 0, 18, 4.5, chambers, [], ops["records"], [])

	# Floors: a dark border round the lobby and the hall, a mat inside the doors,
	# the court's seal let into the lobby floor, a red runner up the courtroom's aisle.
	In.border(p, b1, 0, 17.5, 11, 22.5, Color(0.3, 0.22, 0.16), 0.25)
	In.mat(p, b1, 6.0, 21.95, 2.2, 0.85, Color(0.13, 0.13, 0.14), Color(0.24, 0.24, 0.26))
	var inlay: Node3D = p.node_of(b1)
	Kit.cyl(inlay, 0.66, 0.008, p.pt(6.0, 18.6, 0.004), GILT, Vector3.ZERO, 24)
	Kit.cyl(inlay, 0.58, 0.011, p.pt(6.0, 18.6, 0.0055), Color(0.2, 0.25, 0.45), Vector3.ZERO, 24)
	Kit.cyl(inlay, 0.3, 0.014, p.pt(6.0, 18.6, 0.007), GILT, Vector3.ZERO, 16)
	Kit.cyl(inlay, 0.22, 0.017, p.pt(6.0, 18.6, 0.0085), Color(0.2, 0.25, 0.45), Vector3.ZERO, 16)
	In.border(p, b2, 4, 13.5, 18, 17.5, Color(0.3, 0.2, 0.14), 0.25)
	In.mat(p, b3, 9.0, 11.65, 1.3, 3.4, Kit.tex("in_carpet", 1.0, Color(0.55, 0.12, 0.14), true, Color(0.82, 0.2, 0.22)), GILT)

	# Lights: fluorescent fittings in the public offices, globes in the hall and
	# the courtroom, cages in the cells and records, little shades in chambers.
	In.wall_strip(p, b1, 2.6, 17.58, 0.0, 1.2, 2.62)
	In.wall_strip(p, b1, 9.7, 17.58, 0.0, 1.0, 2.62)
	In.wall_strip(p, b1, 14.4, 17.58, 0.0, 1.0, 2.62)
	for u: float in [6.1, 11.9]:
		In.sconce(p, b2, u, 13.585, 0.0, "globe", 2.05)
	for u: float in [5.0, 12.7]:
		In.sconce(p, b3, u, 4.585, 0.0, "globe", 2.15)
	for v: float in [8.7, 13.0]:
		In.sconce(p, b3, 3.085, v, 90.0, "globe", 2.1)
	In.sconce(p, b3, 1.5, 4.585, 0.0, "cage", 2.2)
	In.wall_strip(p, b3, 16.5, 4.58, 0.0, 1.0, 2.6)
	In.wall_strip(p, b4, 4.0, 0.08, 0.0, 1.4, 2.62)
	for u: float in [9.3, 14.85]:
		In.sconce(p, b4, u, 0.085, 0.0, "shade", 2.05)


## The panelled wall behind the judge's bench, from u0 to u1 on the back wall's
## face (v 4.575): a walnut field to the cornice, a fluted pilaster at each end
## with a plinth, a capital and a block of entablature over it, and the seal
## (_court) in a gilt ring in the middle.
static func _reredos(p: Node3D, b: int, u0: float, u1: float) -> void:
	var n: Node3D = p.node_of(b)
	var v := 4.575
	var field := Kit.tex("in_panel", 1.1, Color(0.4, 0.25, 0.15), true, Color(0.52, 0.32, 0.2))
	p.slab(n, true, v + 0.012, u0, u1, 0.0, 2.73, 0.024, field)
	for x0: float in [u0 + 0.01, u1 - 0.34]:
		var x1 := x0 + 0.33
		p.slab(n, true, v + 0.035, x0, x1, 0.0, 0.3, 0.07, WALNUT_DARK)               # plinth
		p.slab(n, true, v + 0.0275, x0 + 0.03, x1 - 0.03, 0.3, 2.35, 0.055, WALNUT)     # shaft
		for k in 3:
			var fx := x0 + 0.085 + k * 0.07
			p.slab(n, true, v + 0.0575, fx, fx + 0.022, 0.42, 2.25, 0.006, WALNUT_DARK)     # flutes
		p.slab(n, true, v + 0.04, x0 - 0.015, x1 + 0.015, 2.35, 2.47, 0.08, WALNUT_DARK)   # capital
		p.slab(n, true, v + 0.045, x0 - 0.035, x1 + 0.035, 2.47, 2.725, 0.09, WALNUT)      # entablature
		p.slab(n, true, v + 0.0505, x0 - 0.04, x1 + 0.04, 2.53, 2.56, 0.101, GILT)         # a gilt line in it
	Kit.ring(n, 0.6, 0.045, p.pt((u0 + u1) * 0.5, v + 0.05, 2.25), GILT, Vector3(90, 0, 0))


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var concrete := Color(0.7, 0.69, 0.65)
	var precast := Color(0.84, 0.82, 0.76)
	var bronze := Color(0.3, 0.25, 0.18)
	var granite := Kit.tex("in_ashlar", 1.0, Color(0.42, 0.41, 0.42), true, Color(0.5, 0.49, 0.52))
	var f := 22.575        # the street face of the front wall
	# The band between the floors, the canopy over the doors on two columns, the name.
	p.slab(front, true, 22.5, -0.05, 18.05, 4.2, 4.5, 0.3, concrete)
	Kit.box(front, Vector3(4.36, 0.2, 1.5), p.pt(6.0, 23.3, 2.95), concrete)
	for u in [4.0, 8.0]:
		var post: Node3D = p.prop(st, u, 23.9, 0.0, 0.2, 0.2)
		In.column(post, Vector3.ZERO, 2.85, 0.1, precast)
	# The portico: a beam along the canopy's front on the columns, and a pediment
	# over it with the scales of justice in gilt on a slate-blue tympanum.
	Kit.box(front, Vector3(4.5, 0.36, 0.2), p.pt(6.0, 23.98, 2.97), precast)
	In.pediment(front, p.pt(6.0, 23.98, 3.15), 4.5, 0.72, 0.2, precast, Color(0.3, 0.36, 0.5))
	In.scales(front, p.pt(6.0, 24.085, 3.3), 0.44)
	# The name on a bronze panel (the letters as they were, brought forward onto it).
	p.slab(front, true, f + 0.025, 6.95, 12.25, 3.15, 3.85, 0.05, Color(0.26, 0.22, 0.17))
	Props.words(front, "DISTRICT COURT", p.pt(9.6, f + 0.062, 3.5), 0.42, Color(0.9, 0.86, 0.72))
	Kit.disc(front, 0.42, p.pt(3.4, 22.59, 3.45), Color(0.78, 0.63, 0.25), 0.03, 16)
	Kit.disc(front, 0.32, p.pt(3.4, 22.6, 3.45), Color(0.2, 0.25, 0.45), 0.03, 16)
	Props.words(front, "ALL PERSONS SUBJECT TO SEARCH", p.pt(9.2, 22.585, 0.8), 0.09, Color(0.9, 0.86, 0.72), 0.0, false)
	# A granite base either side of the doors, precast piers at the corners,
	# a precast surround round the doors with a lantern each side.
	for run: Array in [[-0.02, 4.84], [7.16, 18.02]]:
		p.slab(front, true, f + 0.04, run[0], run[1], 0.0, 0.45, 0.08, granite)
	for run: Array in [[-0.02, 0.45], [17.55, 18.02]]:
		p.slab(front, true, f + 0.035, run[0], run[1], 0.45, 4.2, 0.07, precast)
	for run: Array in [[4.84, 5.045], [6.955, 7.16]]:
		p.slab(front, true, f + 0.05, run[0], run[1], 0.0, 2.255, 0.1, precast)
	p.slab(front, true, f + 0.06, 4.8, 7.2, 2.255, 2.45, 0.12, precast)
	for u in [4.6, 7.4]:
		In.sconce(p, front, u, f, 0.0, "globe", 1.95, Color(1.0, 0.86, 0.55))
	# The ground floor's windows: precast reveals, a lintel and a sill round each.
	for w: Array in [[1.0, 3.4], [8.2, 10.2], [12.4, 16.6]]:
		var a: float = w[0]
		var e: float = w[1]
		p.slab(front, true, f + 0.04, a - 0.2, a - 0.055, 1.045, 2.455, 0.08, precast)
		p.slab(front, true, f + 0.04, e + 0.055, e + 0.2, 1.045, 2.455, 0.08, precast)
		p.slab(front, true, f + 0.05, a - 0.2, e + 0.2, 2.455, 2.7, 0.1, precast)
		p.slab(front, true, f + 0.06, a - 0.25, e + 0.25, 0.97, 1.045, 0.12, precast)
	# Upstairs: tall windows between concrete fins, a deep fascia, a coping, two flags.
	for i in 6:
		In.front_window(p, front, 1.5 + i * 3.0, 22.5, 4.85, 1.6, 1.75, i in [1, 2, 4], bronze, precast, "", 7.0, false)
	for x: float in [3.0, 6.0, 9.0, 12.0, 15.0]:
		p.slab(front, true, f + 0.09, x - 0.14, x + 0.14, 4.5, 6.8, 0.18, precast)
	for run: Array in [[-0.02, 0.45], [17.55, 18.02]]:
		p.slab(front, true, f + 0.09, run[0], run[1], 4.5, 6.8, 0.18, precast)
	p.slab(front, true, f + 0.13, -0.1, 18.1, 6.85, 7.45, 0.26, precast)
	p.slab(front, true, f + 0.11, -0.04, 18.04, 6.8, 6.85, 0.2, concrete.darkened(0.2))
	p.slab(front, true, 22.6, -0.12, 18.12, 7.45, 7.53, 0.52, concrete)
	Props.flag_on(front, p.pt(4.6, 22.45, 7.53), Color(0.16, 0.2, 0.45), true, 5.0)
	Props.flag_on(front, p.pt(7.4, 22.45, 7.53), Color(0.75, 0.6, 0.2), false, -5.0)
	# Next door: a cheque casher on the left, a lawyer's shopfront on the right.
	p.slab(n, true, 22.5, -12.0, 0.0, 0.0, 3.6, 0.15, Kit.tex("stucco", 2.0, Color(0.7, 0.66, 0.4), true, Color(1.0, 0.95, 0.6)))
	p.slab(n, true, 22.5, -12.06, 0.0, 3.6, 3.69, 0.28, Color(0.82, 0.78, 0.6))
	p.slab(n, true, 22.585, -8.6, -3.4, 0.5, 2.3, 0.03, Kit.flat(Color(1.0, 0.95, 0.75), 0.9))
	var alu := Color(0.62, 0.64, 0.66)
	for run: Array in [[-8.7, -8.6], [-3.4, -3.3]]:
		p.slab(n, true, f + 0.025, run[0], run[1], 0.4, 2.4, 0.05, alu)
	p.slab(n, true, f + 0.025, -8.6, -3.4, 0.4, 0.5, 0.05, alu)
	p.slab(n, true, f + 0.025, -8.6, -3.4, 2.3, 2.4, 0.05, alu)
	p.slab(n, true, f + 0.11, -8.8, -3.2, 2.4, 2.66, 0.22, Kit.tex("in_ribbed", 0.6, Color(0.6, 0.6, 0.62), true, Color(0.78, 0.78, 0.8)))     # the shutter's box
	p.slab(n, true, 22.6, -2.6, -1.7, 0.0, 2.1, 0.03, Color(0.5, 0.52, 0.55))
	Props.words(n, "CHECKS CASHED", p.pt(-6.0, 22.59, 2.95), 0.34, Color(0.75, 0.12, 0.1))
	Props.words(n, "PAYDAY LOANS  -  MONEY ORDERS", p.pt(-6.0, 22.62, 1.0), 0.13, Color(0.75, 0.12, 0.1), 0.0, false)
	p.slab(n, true, 22.5, 18.0, 30.0, 0.0, 3.8, 0.15, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74)))
	In.cornice(p, n, 22.5, 18.25, 30.0, 3.8, Color(0.22, 0.24, 0.3), Color(0.82, 0.78, 0.66), 0.35)
	p.slab(n, true, 22.585, 19.0, 22.4, 0.6, 2.3, 0.03, Color(0.16, 0.2, 0.26))
	for run: Array in [[18.9, 19.0], [22.4, 22.5]]:
		p.slab(n, true, f + 0.03, run[0], run[1], 0.5, 2.4, 0.06, bronze)
	p.slab(n, true, f + 0.03, 19.0, 22.4, 0.5, 0.6, 0.06, bronze)
	p.slab(n, true, f + 0.03, 18.9, 22.5, 2.3, 2.4, 0.06, bronze)
	p.slab(n, true, 22.6, 23.0, 23.9, 0.0, 2.1, 0.03, Color(0.3, 0.2, 0.14))
	Kit.awning(n, 1.3, 0.55, 0.3, p.pt(23.45, f, 2.62), Color(0.16, 0.22, 0.4), Color(0.9, 0.86, 0.72), 0.26)
	Props.words(n, "ATTORNEY AT LAW", p.pt(21.4, 22.59, 2.95), 0.3, Color(0.92, 0.8, 0.35))
	Props.words(n, "DUI - TRAFFIC - BAIL", p.pt(20.7, 22.62, 1.5), 0.14, Color(0.92, 0.8, 0.35), 0.0, false)
	Props.bench(p, st, 2.2, 22.92, 0.0, 2.2, Props.IRON, true)
	Props.bin(p, st, 7.6, 22.95)
	Props.street_lamp(p, st, -1.6, 24.75)
	Props.hydrant(p, st, 12.5, 24.7)


static func _lobby(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Screening: in at the doors, the belt on your left, through the arch, the guard beyond.
	Props.detector(p, b, 6.0, 20.2)
	Props.xray(p, b, 4.33, 20.3)
	var tray: Node3D = p.prop(b, 5.06, 20.2, 0.0, 0.6, 0.5)
	Kit.block(tray, Vector3(0.56, 0.72, 0.46), Vector3.ZERO, Props.STEEL)
	Kit.box(tray, Vector3(0.44, 0.06, 0.34), Vector3(0, 0.75, 0), Props.OFFICE)
	p.rail(b, true, 20.2, 0.1, 3.9, Props.IRON)
	p.rail(b, true, 20.2, 6.65, 10.9, Props.IRON)
	Props.desk(p, b, 8.2, 19.2, 180.0, Props.OFFICE, 3, true, 1.4)
	p.person(b, "cop", 5.0, 18.0, {"face": "focused"})          # the far side of the arch, back from it: from here he can walk up to whoever it goes red for (towards the camera, the way he faces)
	p.person(b, "cop", 9.5, 19.2, {"face": "bored"})
	p.person(b, "cop", 2.6, 19.3)                              # watching the belt (west of the X-ray's screen, so it is not in front of his face)
	Props.words(n, "EMPTY YOUR POCKETS", p.pt(0.09, 21.3, 1.9), 0.13, Color(0.6, 0.12, 0.1), 90.0)
	Props.bench(p, b, 0.36, 18.75, 90.0, 2.0, Props.WOOD)
	Props.board(p, b, 2.6, 17.58, 0.0, 2.0, "notices")
	Props.words(n, "DIRECTORY", p.pt(2.6, 17.59, 2.3), 0.14, Color(0.25, 0.2, 0.15))
	Props.clock(p, b, 8.4, 17.58)
	Props.plant(p, b, 10.4, 21.9)
	Props.flag(p, b, 0.5, 21.95, Color(0.16, 0.2, 0.45), 0.0, true)
	Props.words(n, "PAY FINES HERE", p.pt(10.91, 18.85, 2.3), 0.14, Color(0.25, 0.2, 0.15), 270.0)
	# The clerk's office, behind the glass.
	var counter := Props.counter(p, b, 11.45, 18.85, 90.0, 2.1, 0.6, 1.04, Props.OFFICE)
	Kit.box(counter, Vector3(0.3, 0.02, 0.4), Vector3(0.4, 1.05, 0), Props.PAPER)
	Kit.block(counter, Vector3(0.34, 0.22, 0.3), Vector3(-0.5, 1.04, 0.05), Props.CREAM)
	Props.chair(p, b, 12.2, 18.85, 270.0)
	Props.desk(p, b, 14.2, 20.0, 180.0, Props.OFFICE, 1)
	Props.desk(p, b, 14.2, 21.45, 180.0, Props.OFFICE.darkened(0.08), 3)
	Props.files(p, b, 17.6, 20.4, 270.0, 6)
	Props.cooler(p, b, 17.6, 18.0)
	Props.board(p, b, 12.9, 17.58, 0.0, 1.4, "notices")
	In.picture(p, b, 14.4, 17.585, 0.0, 0.9, 0.66, "map", WALNUT, 1.6)       # the district


static func _hall(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	Props.bench(p, b, 6.1, 13.86, 0.0, 3.0, Props.WOOD_DARK, true)
	Props.bench(p, b, 11.9, 13.86, 0.0, 3.0, Props.WOOD_DARK, true)
	Props.words(n, "COURTROOM 1", p.pt(9.0, 13.59, 2.45), 0.16, Color(0.92, 0.86, 0.7))
	Props.board(p, b, 14.9, 13.58, 0.0, 1.8, "notices")
	Props.words(n, "TODAY'S DOCKET", p.pt(14.9, 13.59, 2.3), 0.13, Color(0.92, 0.86, 0.7))
	Props.fountain(p, b, 17.74, 14.5, 270.0)
	Props.payphone(p, b, 4.08, 16.4, 90.0)
	Props.clock(p, b, 16.6, 13.58)
	Props.bin(p, b, 17.55, 17.05)
	# Two doors that stay shut.
	for row: Array in [[15.6, "MEN"], [16.75, "WOMEN"]]:
		var v: float = row[0]
		p.slab(n, false, 17.9, v - 0.42, v + 0.42, 0.0, 2.05, 0.04, Color(0.36, 0.24, 0.15))
		Props.words(n, row[1], p.pt(17.87, v, 1.6), 0.09, Color(0.92, 0.86, 0.7), 270.0)
	# The lawyer room: where a deal gets made five minutes before the hearing.
	Props.table(p, b, 1.9, 15.6, 0.0, 1.8, 0.9, Props.WOOD)
	Props.chair(p, b, 1.4, 14.85, 0.0, Props.VINYL)
	Props.chair(p, b, 2.4, 14.85, 0.0, Props.VINYL)
	Props.chair(p, b, 1.9, 16.35, 180.0, Props.VINYL)
	Props.poster(p, b, 0.08, 15.6, 90.0, 0.7, 0.9, Color(0.2, 0.3, 0.5), "KNOW YOUR RIGHTS")
	In.pendant(p, b, 1.9, 15.6, 2.1, Color(0.18, 0.4, 0.28), "cone")
	In.picture(p, b, 2.0, 13.585, 0.0, 0.5, 0.4, "certificate", WALNUT, 1.7)


static func _court(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The bench and the witness stand are out from the wall: there is room to
	# walk round behind them (and, later, to step in and sit). The seal hangs on
	# the panelled wall behind the bench, in its gilt ring (_reredos).
	Props.judge_bench(p, b, 9.0, 6.2)
	_reredos(p, b, 6.2, 11.8)
	Kit.disc(n, 0.5, p.pt(9.0, 4.614, 2.25), Color(0.78, 0.63, 0.25), 0.03, 16)
	Kit.disc(n, 0.38, p.pt(9.0, 4.624, 2.25), Color(0.2, 0.25, 0.45), 0.03, 16)
	Props.desk(p, b, 5.65, 5.75, 180.0, Props.WOOD, 1, true, 1.3)
	Props.witness_stand(p, b, 12.3, 6.0)
	Props.jury_box(p, b, 13.98, 8.45, 270.0, 2.4)      # clear of the witness stand: the way to the back rooms runs between them
	Props.table(p, b, 5.9, 8.7, 0.0, 2.8, 0.8, Props.WOOD)
	Props.table(p, b, 11.5, 8.7, 0.0, 2.6, 0.8, Props.WOOD)
	for u in [5.2, 6.6, 10.9, 12.1]:
		Props.chair(p, b, u, 9.4, 180.0, Props.VINYL)
	Props.lectern(p, b, 9.0, 8.55, 180.0)
	p.rail(b, true, 9.75, 3.1, 8.35)
	p.rail(b, true, 9.75, 9.65, 14.9)
	for v in [10.65, 11.65, 12.65]:
		Props.pew(p, b, 5.8, v, 180.0, 4.6)
		Props.pew(p, b, 12.2, v, 180.0, 4.6)
	Props.clock(p, b, 14.92, 11.6, 270.0)
	for v: float in [10.1, 11.9]:          # judges who sat here before
		In.picture(p, b, 3.085, v, 90.0, 0.52, 0.66, "face", GILT, 1.75)
	# The lockup: a deputy's desk, and the holding cell behind bars.
	Props.desk(p, b, 0.6, 5.5, 90.0, Props.OFFICE.darkened(0.2), 1, false, 1.2, 0.6)
	Props.chair(p, b, 1.35, 5.5, 270.0)
	Props.bench(p, b, 0.36, 11.2, 90.0, 3.4, Props.IRON)
	Props.cell_toilet(p, b, 2.6, 13.05, 180.0)
	p.slab(n, false, 0.09, 4.9, 5.8, 0.0, 2.05, 0.04, Color(0.36, 0.4, 0.44))       # the prisoner door, shut
	Props.words(n, "HOLDING", p.pt(1.5, 8.64, 2.55), 0.18, Color(0.9, 0.9, 0.85))
	# The jury room.
	Props.table(p, b, 16.6, 9.0, 90.0, 3.2, 1.1, Props.WOOD)
	for v in [8.0, 9.0, 10.0]:
		Props.chair(p, b, 17.5, v, 270.0, Props.VINYL)
	Props.chair(p, b, 16.6, 7.05, 0.0, Props.VINYL)
	Props.chair(p, b, 16.6, 10.95, 180.0, Props.VINYL)
	Props.coffee(p, b, 16.95, 4.97)
	Props.cooler(p, b, 17.6, 13.05)
	Props.poster(p, b, 17.92, 12.0, 270.0, 0.8, 0.6, Color(0.5, 0.45, 0.3), "NO VERDICT, NO LUNCH", 1.7)
	In.picture(p, b, 15.085, 9.0, 90.0, 0.9, 0.66, "shapes", Color(0.85, 0.55, 0.2), 1.62)
	Props.clock(p, b, 15.8, 4.58)


static func _back(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Records: dead files, boxes, a bucket under the leak, the pipes along the wall.
	Props.shelves(p, b, 4.0, 0.33, 0.0, 7.4)
	Props.shelves(p, b, 4.0, 1.55, 0.0, 7.4)
	Props.boxes(p, b, 1.2, 3.8, 5)
	Props.boxes(p, b, 5.4, 3.9, 3)
	Props.bucket(p, b, 7.2, 3.3)
	for row: Array in [[2.34, 0.05, Color(0.6, 0.3, 0.2)], [2.46, 0.035, Color(0.5, 0.52, 0.55)]]:
		Kit.cyl(n, row[1], 8.7, p.pt(4.5, 0.075 + 0.07, row[0]), row[2], Vector3(0, 0, 90), 8)
	for u: float in [0.6, 3.0, 5.4, 7.8]:
		Kit.box(n, Vector3(0.04, 0.2, 0.08), p.pt(u, 0.115, 2.4), Props.IRON)
	Kit.cyl(n, 0.05, 2.34, p.pt(8.6, 0.145, 1.17), Color(0.6, 0.3, 0.2), Vector3.ZERO, 8)
	# Chambers: law books, a big desk, a couch, the robe on its stand, and the
	# judges before him over the shelves.
	Props.shelves(p, b, 12.0, 0.33, 0.0, 5.2, "books", Props.WOOD_DARK)
	Props.desk(p, b, 12.6, 1.95, 180.0, Props.WOOD_DARK.lightened(0.1), 2, true, 2.2, 0.9)
	Props.chair(p, b, 12.1, 3.15, 180.0, Props.VINYL)
	Props.chair(p, b, 13.1, 3.15, 180.0, Props.VINYL)
	Props.couch(p, b, 17.45, 2.3, 270.0, 2.4, Color(0.32, 0.18, 0.14))
	Props.robe(p, b, 15.8, 0.5)
	Props.flag(p, b, 16.9, 0.45)
	Props.rug(p, b, 13.0, 2.9, 3.4, 2.0, Color(0.4, 0.14, 0.14))
	Props.poster(p, b, 9.09, 1.4, 90.0, 0.6, 0.45, Color(0.85, 0.82, 0.7), "", 1.8)
	Props.poster(p, b, 9.09, 4.05, 90.0, 0.5, 0.4, Color(0.85, 0.82, 0.7), "", 1.8)
	for u: float in [10.7, 12.0, 13.3]:
		In.picture(p, b, u, 0.085, 0.0, 0.38, 0.44, "face", GILT, 2.17)
