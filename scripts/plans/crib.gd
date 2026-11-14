extends RefCounted
## Tattletale's crib: a two-bay Baltimore rowhouse in the same brick row as the
## original game's houses. No hallway: you step off the pavement into the
## living room, and the rooms run front to back in one line.
##
##   ground floor:  living room | dining room (the stairs) | kitchen wing, side yard | back yard
##   upstairs:      his room | hall, bathroom | back bedroom
##
## The game floor is flat, so the stairs are a spot you use (E): the picture
## fades and he is on the other floor. Upstairs is its own stack of bands, drawn
## 40 m to the right on the plan (UP). A real house like this is about 4 m wide;
## this one is 5 m so there is room to walk round the furniture.
## Numbers are metres on the plan (see place.gd): u from the left party wall,
## v from the alley; the street is at v = 15.8.

const Props := preload("res://scripts/props.gd")
const UP := 40.0


static func build(p: Node3D) -> void:
	p.setup("TATTLETALE'S CRIB", 5.0, 15.8)
	var paper := Kit.tex("stucco", 2.0, Color(0.85, 0.8, 0.66), true, Color(1.0, 1.0, 0.82))       # yellowed wallpaper
	var blue := Kit.tex("stucco", 2.0, Color(0.6, 0.68, 0.8), true, Color(0.66, 0.84, 1.0))        # his room
	var tile := Kit.tex("painted_block", 0.6, Color(0.8, 0.86, 0.84), true, Color(0.82, 1.0, 1.0)) # the bathroom
	var boards := Kit.tex("wood_panel", 1.6, Color(0.5, 0.36, 0.24), true, Color(0.62, 0.6, 0.62))
	var lino := Kit.tex("lino", 1.2, Color(0.7, 0.66, 0.56), true, Color(1.0, 0.9, 0.8))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2))
	var warm := Color(1.0, 0.86, 0.62)
	var white_door := Color(0.82, 0.8, 0.72)

	var st: int = p.street(-5.0, 10.0)
	var g1: int = p.band()
	var g2: int = p.band()
	var g3: int = p.band()
	var g4: int = p.band()
	var h1: int = p.band(1)
	var h2: int = p.band(1)
	var h3: int = p.band(1)
	p.arrive = p.pt(1.05, 16.9)

	p.room("LIVING ROOM", g1, 0, 11.2, 5, 15.8, boards, {"light": warm, "energy": 0.6})
	p.room("DINING ROOM", g2, 0, 7.2, 5, 11.2, boards, {"light": warm})
	p.room("KITCHEN", g3, 0, 3.4, 3.6, 7.2, lino, {"light": Color(0.95, 1.0, 0.9)})
	# The back yard runs round the side of the kitchen wing.
	p.room("BACK YARD", g4, 0, 0, 5, 3.4, concrete, {"areas": [[0, 0, 5, 3.4], [3.6, 2.4, 5, 7.2]], "cam_y": 2.9, "look_y": 1.0})
	Kit.box(p.node_of(g4), Vector3(1.4, 0.3, 3.8), p.pt(4.3, 5.3, -0.15), concrete)
	p.room("HIS ROOM", h1, UP, 11.2, UP + 5, 15.8, boards, {"light": warm, "energy": 0.6})
	p.room("HALL", h2, UP, 7.2, UP + 2.2, 11.2, boards, {"light": warm, "energy": 0.4})
	p.room("BATHROOM", h2, UP + 2.2, 7.2, UP + 5, 11.2, lino, {"light": Color(0.95, 1.0, 1.0), "energy": 0.4})
	p.room("BACK BEDROOM", h3, UP, 3.4, UP + 3.6, 7.2, boards, {"light": warm, "energy": 0.4})

	# ---- ground floor walls
	var front: Node3D = p.cross(g1, 15.8, 0, 5, brick, [
		{"a": 0.6, "b": 1.5, "head": 2.1, "colour": Color(0.5, 0.14, 0.12), "frame": white_door},
		{"a": 2.6, "b": 4.5, "kind": "window", "sill": 0.8, "head": 2.2, "bars": true, "blinds": true, "frame": white_door},
	], {"h": 6.3})
	p.side(g1, 0.0, 11.2, 15.8, paper)
	p.side(g1, 5.0, 11.2, 15.8, paper)
	p.cross(g2, 11.2, 0, 5, paper, [{"a": 1.5, "b": 3.5, "kind": "arch", "frame": white_door}])
	p.side(g2, 0.0, 7.2, 11.2, paper)
	p.side(g2, 5.0, 7.2, 11.2, paper)
	p.cross(g3, 7.2, 0, 5, paper, [{"a": 1.5, "b": 2.4, "colour": white_door, "frame": white_door}])
	p.side(g3, 0.0, 3.4, 7.2, paper)
	p.side(g3, 3.6, 3.4, 7.2, paper, [{"a": 4.3, "b": 5.2, "kind": "window", "sill": 1.0, "head": 2.0, "frame": white_door}])
	p.cross(g4, 3.4, 0, 3.6, paper, [{"a": 2.5, "b": 3.4, "colour": white_door, "frame": white_door, "name": "BACK DOOR"}])
	# The yard: chain-link on three sides, a gate to the alley that stays shut.
	var wire := Color(0.5, 0.52, 0.52)
	p.rail(g4, false, 0.05, 0.05, 3.3, wire, 1.5)
	p.rail(g4, false, 4.95, 0.05, 7.1, wire, 1.5)
	p.rail(g4, true, 0.05, 0.1, 4.9, wire, 1.5)

	# ---- upstairs walls
	p.cross(h1, 15.8, UP, UP + 5, blue, [
		{"a": UP + 0.6, "b": UP + 2.0, "kind": "window", "sill": 0.8, "head": 2.1, "frame": white_door},
		{"a": UP + 3.0, "b": UP + 4.4, "kind": "window", "sill": 0.8, "head": 2.1, "frame": white_door},
	])
	p.side(h1, UP, 11.2, 15.8, blue)
	p.side(h1, UP + 5.0, 11.2, 15.8, blue)
	p.cross(h2, 11.2, UP, UP + 5, blue, [{"a": UP + 1.2, "b": UP + 2.1, "swing": 1, "colour": white_door, "frame": white_door}])
	p.side(h2, UP, 7.2, 11.2, paper)
	p.side(h2, UP + 5.0, 7.2, 11.2, tile)
	p.side(h2, UP + 2.2, 7.2, 11.2, tile, [{"a": 9.5, "b": 10.4, "hinge": "a", "swing": 1, "colour": white_door, "frame": white_door}])
	p.cross(h3, 7.2, UP, UP + 5, paper, [{"a": UP + 1.2, "b": UP + 2.1, "colour": white_door, "frame": white_door}])
	p.cross(h3, 3.4, UP, UP + 3.6, paper, [{"a": UP + 1.0, "b": UP + 2.4, "kind": "window", "sill": 0.9, "head": 2.1, "frame": white_door}], {"back": true})
	p.side(h3, UP, 3.4, 7.2, paper)
	p.side(h3, UP + 3.6, 3.4, 7.2, paper)

	_street(p, st, front)
	_ground(p, g1, g2, g3, g4)
	_upstairs(p, h1, h2, h3)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var marble := Color(0.9, 0.9, 0.88)
	var cream := Color(0.82, 0.8, 0.72)
	# His own front: the upstairs windows, a cornice, the house number, one low marble step.
	for u in [1.3, 3.7]:
		p.slab(front, true, 15.88, u - 0.75, u + 0.75, 3.65, 5.15, 0.03, cream)
		p.slab(front, true, 15.895, u - 0.65, u + 0.65, 3.75, 5.05, 0.03, Kit.flat(Color(1.0, 0.85, 0.55), 0.5))
		p.slab(front, true, 15.91, u - 0.64, u + 0.64, 4.37, 4.43, 0.03, cream)
	p.slab(front, true, 15.8, -0.02, 5.02, 6.3, 6.6, 0.4, Color(0.3, 0.28, 0.27))
	Props.words(front, "2409", p.pt(1.05, 15.885, 2.35), 0.14, cream)
	Kit.block(n, Vector3(1.3, 0.07, 0.6), p.pt(1.05, 16.18), marble)
	Kit.block(n, Vector3(1.1, 0.05, 0.3), p.pt(1.05, 16.02, 0.07), marble)
	# The row: a boarded-up vacant on the left, a formstone front with a metal awning on the right.
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	var formstone := Kit.tex("painted_block", 0.7, Color(0.62, 0.6, 0.56), true, Color(0.75, 0.78, 0.86))
	var looks := [old_brick, old_brick, formstone, old_brick]
	var starts := [-10.0, -5.0, 5.0, 10.0]
	for i in 4:
		var u0: float = starts[i]
		var boarded: bool = i == 1
		p.slab(n, true, 15.8, u0, u0 + 5.0, 0.0, 6.2, 0.15, looks[i])
		p.slab(n, true, 15.8, u0, u0 + 5.0, 6.2, 6.5, 0.4, Color(0.3, 0.28, 0.27))
		var wood := Color(0.55, 0.42, 0.26)
		var glass: Variant = wood if boarded else Kit.flat(Color(0.95, 0.8, 0.5) if i == 2 else Color(0.2, 0.24, 0.32), 0.45 if i == 2 else 0.0)
		p.slab(n, true, 15.885, u0 + 0.55, u0 + 1.5, 0.3, 2.35, 0.03, wood.darkened(0.25) if boarded else Color(0.24, 0.3, 0.26))     # the door
		p.slab(n, true, 15.885, u0 + 2.6, u0 + 4.5, 1.1, 2.5, 0.03, glass)
		for uu in [u0 + 0.55, u0 + 3.0]:
			p.slab(n, true, 15.885, uu, uu + 1.4, 3.75, 5.05, 0.03, glass)
		# Three marble steps up to the door.
		var stoop: Node3D = p.prop(st, u0 + 1.02, 16.2, 0.0, 1.3, 0.75)
		for k in 3:
			Kit.block(stoop, Vector3(1.3, 0.1 * (3 - k), 0.25), Vector3(0, 0, -0.25 + k * 0.25), marble.darkened(0.04 * k))
		if i == 2:
			Kit.box(n, Vector3(2.0, 0.06, 0.9), p.pt(u0 + 1.02, 16.25, 2.6), Color(0.6, 0.66, 0.62), Vector3(14, 0, 0))     # the awning
			for k in 5:
				Kit.box(n, Vector3(0.2, 0.065, 0.905), p.pt(u0 + 0.22 + k * 0.4, 16.25, 2.6), Color(0.86, 0.86, 0.8), Vector3(14, 0, 0))
	Props.words(n, "NO LOITERING", p.pt(-3.4, 15.9, 1.7), 0.12, Color(0.75, 0.15, 0.12))
	Props.street_lamp(p, st, 6.4, 18.05)
	Props.cans(p, st, 4.3, 16.15, 2)
	Props.hydrant(p, st, -2.2, 18.0)


static func _ground(p: Node3D, g1: int, g2: int, g3: int, g4: int) -> void:
	# Living room: the couch in its plastic cover, the television, a radiator under the window.
	Props.couch(p, g1, 0.53, 13.3, 90.0, 2.4, Color(0.55, 0.42, 0.36))
	Props.tv(p, g1, 4.65, 13.2, 270.0)
	Props.table(p, g1, 2.5, 13.3, 90.0, 1.1, 0.6, Props.WOOD, 0.42)
	Props.rug(p, g1, 2.5, 13.3, 2.4, 2.8, Color(0.42, 0.2, 0.2))
	Props.couch(p, g1, 4.2, 11.74, 0.0, 0.95, Color(0.3, 0.4, 0.34))
	Props.radiator(p, g1, 3.55, 15.6, 180.0, 1.4)
	Props.poster(p, g1, 0.08, 13.3, 90.0, 0.9, 0.6, Color(0.45, 0.35, 0.25), "", 1.75)
	Props.clock(p, g1, 4.92, 14.6, 270.0, 2.0)
	# Dining room: the stairs up the party wall, the table, the cabinet with the good plates.
	Props.stairs(p, g2, 0.6, 8.75, 0.0, 0.95, 2.9)
	p.portal(g2, "GO UPSTAIRS", 0.6, 10.5, UP + 0.6, 10.55)
	Props.table(p, g2, 3.1, 9.1, 0.0, 1.5, 0.9, Props.WOOD_DARK)
	Props.chair(p, g2, 3.1, 8.3, 0.0, Props.WOOD)
	Props.chair(p, g2, 3.1, 9.9, 180.0, Props.WOOD)
	Props.chair(p, g2, 2.05, 9.1, 90.0, Props.WOOD)
	Props.cabinet(p, g2, 4.69, 8.2, 270.0, 1.6)
	Props.poster(p, g2, 2.9, 7.28, 0.0, 0.7, 0.5, Color(0.6, 0.5, 0.3), "", 1.8)
	# Kitchen: stove, sink and fridge down one wall, a small table.
	Props.stove(p, g3, 0.43, 3.95, 90.0)
	Props.sink_unit(p, g3, 0.41, 5.25, 90.0, 1.6)
	Props.fridge(p, g3, 0.46, 6.62, 90.0)
	Props.table(p, g3, 2.8, 5.1, 0.0, 0.9, 1.0, Color(0.8, 0.78, 0.7))
	Props.chair(p, g3, 2.8, 4.3, 0.0, Props.VINYL)
	Props.chair(p, g3, 2.8, 5.9, 180.0, Props.VINYL)
	Props.poster(p, g3, 1.7, 3.48, 0.0, 0.45, 0.6, Color(0.85, 0.82, 0.7), "", 1.7)
	# The yard: dustbins, and a gate to the alley that stays shut.
	Props.cans(p, g4, 4.3, 0.55, 2)
	Props.bench(p, g4, 0.45, 1.6, 90.0, 1.4, Color(0.4, 0.3, 0.2))
	var n: Node3D = p.node_of(g4)
	p.slab(n, true, 0.05, 1.9, 2.9, 0.0, 1.7, 0.07, Color(0.36, 0.38, 0.4))
	Kit.box(n, Vector3(16.0, 0.3, 3.0), p.pt(2.5, -1.5, -0.2), Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27)))      # the alley
	# Across the alley: the backs of the next row's garages.
	p.slab(n, true, -3.0, -5.5, 10.5, 0.0, 2.7, 0.2, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.6, 0.56, 0.62)))
	for u in [-3.6, 0.6, 4.8]:
		p.slab(n, true, -2.88, u, u + 3.0, 0.0, 2.2, 0.04, Color(0.42, 0.44, 0.46))
		for k in 7:
			p.slab(n, true, -2.86, u + 0.02, u + 2.98, 0.2 + k * 0.28, 0.22 + k * 0.28, 0.04, Color(0.3, 0.32, 0.35))
	# The neighbours' yards either side.
	for u in [-0.16, 5.16]:
		p.slab(n, false, u, 0.0, 7.15, 0.0, 1.9, 0.06, Color(0.4, 0.3, 0.2))


static func _upstairs(p: Node3D, h1: int, h2: int, h3: int) -> void:
	# His room: the bed, the desk where the rhymes get written, the boombox, the plaques.
	Props.bed(p, h1, UP + 4.15, 12.32, 0.0, 1.4, 2.0, Color(0.2, 0.3, 0.55))
	var chest := Props.dresser(p, h1, UP + 0.36, 14.0, 90.0, 1.6)
	Props.boombox(chest, Vector3(0, 0.9, 0))
	Props.desk(p, h1, UP + 3.5, 15.32, 180.0, Props.WOOD, 2, true, 1.6)
	Props.rug(p, h1, UP + 2.2, 13.6, 2.0, 1.6, Color(0.2, 0.25, 0.4))
	Props.poster(p, h1, UP + 0.08, 12.2, 90.0, 0.7, 0.95, Color(0.15, 0.3, 0.7), "TATTLETALE")
	Props.poster(p, h1, UP + 2.9, 11.28, 0.0, 0.6, 0.8, Color(0.75, 0.2, 0.2), "JUST SAY NO")
	Props.poster(p, h1, UP + 4.92, 14.4, 270.0, 0.55, 0.4, Color(0.7, 0.58, 0.25), "CITIZEN OF THE MONTH", 1.7)
	Props.poster(p, h1, UP + 4.92, 15.1, 270.0, 0.55, 0.4, Color(0.7, 0.58, 0.25), "BLOCK WATCH", 1.7)
	# The hall and the bathroom.
	Props.stairwell(p, h2, UP + 0.6, 8.75, 0.0, 0.95, 2.9)
	p.portal(h2, "GO DOWNSTAIRS", UP + 0.6, 10.5, 0.6, 10.55)
	Props.tub(p, h2, UP + 4.55, 8.32)
	Props.toilet(p, h2, UP + 4.58, 10.2, 270.0)
	Props.basin(p, h2, UP + 3.0, 7.52)
	Props.rug(p, h2, UP + 3.3, 9.3, 1.0, 0.7, Color(0.6, 0.75, 0.8))
	# The back bedroom.
	Props.bed(p, h3, UP + 0.96, 4.52, 0.0, 1.5, 2.0, Color(0.7, 0.55, 0.6))
	Props.dresser(p, h3, UP + 2.9, 3.76, 0.0, 1.2, Props.WOOD_DARK)
	Props.chair(p, h3, UP + 3.2, 6.3, 270.0, Props.WOOD)
	Props.poster(p, h3, UP + 0.08, 6.0, 90.0, 0.5, 0.65, Color(0.75, 0.7, 0.55), "", 1.7)
