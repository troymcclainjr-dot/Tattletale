extends RefCounted
## Miss Bea's house: the frame house where Miss Bea (who keeps the corner
## grocery, plans/store.gd) has lived for forty years. Nothing like the crib
## (a brick rowhouse, one room behind another) or Large Fry's flat (one wide
## floor in a block): it stands on its own, clapboard painted butter yellow,
## behind a picket fence and a front yard, with a deep porch across the whole
## front. A side-hall plan: the front door opens at the foot of the stairs,
## which climb the hall's left wall, the parlour through an arch beside it.
## 9 x 11 m, two floors; everything in it forty years' worth of hers.
##
##   street band:  the pavement | FRONT YARD (11.4 x 2.2) | PORCH (9 x 2.4)
##   band 1:       PARLOUR (5.6 x 4.6)  | FRONT HALL (3.4 x 4.6, the stairs)
##   band 2:       DINING ROOM (5 x 3.4) | KITCHEN (4 x 3.4)
##   band 3:       SUN ROOM (5 x 3)      | PANTRY (4 x 3)
##   upstairs 1:   BEDROOM (5.6 x 5.4)  | UPSTAIRS HALL (3.4 x 5.4)
##   upstairs 2:   SEWING ROOM (5 x 3)   | BATHROOM (4 x 3)
##
## Ways through: front door; parlour arch to the hall and to the dining room;
## a doorway hall to kitchen; a door dining room to kitchen; wide openings to
## the sun room and the pantry (a door in a cut-away wall stands between the
## camera and the room); upstairs, doors to the bedroom, the sewing room
## (through the bedroom) and the bathroom.
##
## The game floor is flat, so the porch is at the yard's level and the stairs
## are a spot you use (E), as in the crib. Upstairs is its own stack of bands,
## drawn 40 m to the right on the plan (UP). The neighbours either side are
## frame houses too, seen from the street only.
##
## Numbers are metres on the plan (see place.gd): u from the house's left
## wall, v from its back wall. The house front is at v = 11, the porch runs to
## v = 13.4, and the front fence stands on the edge of the pavement at v = 15.6
## (the plan's depth). The new furniture is in props_bea.gd.
##
## Invented here (placeholders): the house number 3912, the WELCOME mat, "GOD
## BLESS OUR HOME" on the sampler over her bed, "MARCH 1994" on the calendar
## from her shop (the shop's name on it is the owners' own: MISS BEA'S CORNER
## GROCERY), and the door names FRONT DOOR, SEWING ROOM DOOR, BATHROOM DOOR.

const Props := preload("res://scripts/props.gd")
const Bea := preload("res://scripts/props_bea.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const UP := 40.0
const FRONT := 11.0           # the house front
const PORCH := 13.4           # the front edge of the porch
const LOT := 15.6             # the front fence, on the edge of the pavement
const STAIR_U := 6.15         # the middle of the flight, on both floors
const STAIR_V := 7.9
const STAIR_L := 2.8          # v 6.5 (the top) to 9.3 (the foot)
const DOOR := [5.75, 6.65]    # the front door, at the foot of the stairs; the porch steps and the gate line up with it
const STEPS := [5.6, 6.8]
const GATE := [5.6, 6.8]
const HALL_WINDOW := [7.45, 8.25]
const PANTRY_WINDOW := {"a": 5.45, "b": 7.15, "kind": "window", "sill": 2.02, "head": 2.6}   # high, over her shelves

const BUTTER := Color(0.94, 0.83, 0.5)
const LINE := Color(0.8, 0.66, 0.36)
const SHUTTER := Color(0.2, 0.4, 0.3)
const GLOW := Color(1.0, 0.84, 0.55)
const NIGHT := Color(0.16, 0.2, 0.3)


static func build(p: Node3D) -> void:
	p.setup("MISS BEA'S HOUSE", 9.0, LOT)
	var warm := Color(1.0, 0.84, 0.6)
	var white := Bea.WHITE
	var trim := Color(0.92, 0.9, 0.82)
	var door_red := Color(0.62, 0.14, 0.14)
	var white_door := Color(0.9, 0.88, 0.8)
	var boards := Kit.tex("wood_panel", 1.6, Color(0.5, 0.36, 0.24), true, Color(0.74, 0.6, 0.54))
	var deck := Kit.tex("wood_panel", 1.2, Color(0.55, 0.57, 0.6), true, Color(0.55, 0.62, 0.72))
	var grass := Kit.tex("stucco", 2.5, Color(0.35, 0.5, 0.25), true, Color(0.44, 0.74, 0.36))
	var lino := Kit.tex("lino", 0.8, Color(0.7, 0.7, 0.66), true, Color(1.0, 0.98, 0.9))
	var pantry_floor := Kit.tex("lino", 0.8, Color(0.6, 0.3, 0.3), true, Color(1.0, 0.55, 0.5))
	var terracotta := Kit.tex("block_plain", 0.9, Color(0.8, 0.5, 0.36), true, Color(0.95, 0.6, 0.45))
	var bath_floor := Kit.tex("lino", 0.3, Color(0.7, 0.7, 0.7), true, Color(0.9, 0.9, 0.92))

	var st: int = p.street(-7.0, 16.0)
	var g1: int = p.band()
	var g2: int = p.band()
	var g3: int = p.band()
	var h1: int = p.band(1)
	var h2: int = p.band(1)
	p.arrive = p.pt((GATE[0] + GATE[1]) * 0.5, 16.7)

	p.room("PORCH", st, 0, FRONT, 9, PORCH, deck, {"street": true, "cam_y": 2.4, "look_y": 1.1})
	p.room("FRONT YARD", st, -1.2, PORCH, 10.2, LOT, grass, {"street": true})
	p.room("PARLOUR", g1, 0, 6.4, 5.6, FRONT, boards, {"light": warm, "energy": 0.5})
	p.room("FRONT HALL", g1, 5.6, 6.4, 9, FRONT, boards, {"light": warm, "energy": 0.4})
	p.room("DINING ROOM", g2, 0, 3.0, 5.0, 6.4, boards, {"light": warm, "energy": 0.55})
	p.room("KITCHEN", g2, 5.0, 3.0, 9, 6.4, lino, {"light": Color(1.0, 0.96, 0.86), "energy": 0.55})
	p.room("SUN ROOM", g3, 0, 0, 5.0, 3.0, terracotta, {"light": Color(1.0, 0.92, 0.78), "energy": 0.45})
	p.room("PANTRY", g3, 5.0, 0, 9, 3.0, pantry_floor, {"light": Color(1.0, 0.94, 0.8), "energy": 0.4})
	p.room("BEDROOM", h1, UP, 5.6, UP + 5.6, FRONT, boards, {"light": warm, "energy": 0.5})
	p.room("UPSTAIRS HALL", h1, UP + 5.6, 5.6, UP + 9, FRONT, boards, {"light": warm, "energy": 0.4, "hole": [UP + STAIR_U - 0.475, STAIR_V - STAIR_L * 0.5, UP + STAIR_U + 0.475, STAIR_V + STAIR_L * 0.5]})
	p.room("SEWING ROOM", h2, UP, 2.6, UP + 5.0, 5.6, boards, {"light": Color(1.0, 0.95, 0.85), "energy": 0.5})
	p.room("BATHROOM", h2, UP + 5.0, 2.6, UP + 9, 5.6, bath_floor, {"light": Color(1.0, 0.96, 0.95), "energy": 0.45})

	# ---- the looks of the papered rooms: the paper, its stripe, the wainscot, the dado rail
	var parlour := {"paper": Kit.tex("stucco", 2.0, Color(0.85, 0.62, 0.6), true, Color(1.0, 0.8, 0.76)), "stripe": Color(0.97, 0.9, 0.78), "wainscot": Kit.tex("wood_panel", 1.0, Bea.MAHOGANY, false, Color(0.62, 0.42, 0.38)), "rail": Bea.MAHOGANY}
	var hall := {"paper": Color(0.7, 0.79, 0.6), "stripe": Color(0.55, 0.67, 0.46), "wainscot": Color(0.93, 0.92, 0.86), "rail": Props.WOOD}
	var dining := {"paper": Kit.tex("stucco", 2.0, Color(0.85, 0.72, 0.4), true, Color(1.0, 0.9, 0.55)), "stripe": Color(0.6, 0.2, 0.22), "wainscot": Kit.tex("wood_panel", 1.0, Bea.WALNUT, false, Color(0.7, 0.55, 0.45)), "rail": Bea.WALNUT}
	# (The stucco picture is pink: the light rooms are plain paint, their paper the stripes.)
	var bedroom := {"paper": Color(0.8, 0.74, 0.9), "stripe": Color(0.96, 0.93, 0.98), "wainscot": Color(0.95, 0.93, 0.95), "rail": Color(0.66, 0.56, 0.72)}
	var sewing := {"paper": Color(0.74, 0.85, 0.93), "stripe": Color(0.98, 0.9, 0.55), "wainscot": Color(0.95, 0.94, 0.88), "rail": Color(0.56, 0.66, 0.78)}
	var kitchen_paint := Color(0.98, 0.93, 0.66)
	var sun_paint := Color(0.9, 0.97, 0.93)
	var pantry_look := Color(0.92, 0.9, 0.8)
	var bath_tile := Kit.tex("block_plain", 0.45, Color(0.95, 0.75, 0.8), true, Color(1.0, 0.76, 0.84))

	# ---- the ground floor walls
	var front_ops := [
		{"a": 1.0, "b": 4.4, "kind": "window", "sill": 0.55, "head": 2.3, "frame": trim},
		{"a": DOOR[0], "b": DOOR[1], "head": 2.15, "colour": door_red, "frame": trim, "name": "FRONT DOOR"},
		{"a": HALL_WINDOW[0], "b": HALL_WINDOW[1], "kind": "window", "sill": 0.9, "head": 2.2, "frame": trim},
	]
	var front: Node3D = p.cross(g1, FRONT, 0, 9, BUTTER, front_ops, {"h": 6.0})
	var arch_ops := [{"a": 9.5, "b": 10.7, "kind": "arch", "head": 2.25, "frame": Bea.MAHOGANY}]
	var parlour_back_ops := [{"a": 0.5, "b": 2.2, "kind": "arch", "head": 2.3, "frame": Bea.MAHOGANY}]
	var hall_back_ops := [{"a": 7.9, "b": 8.8, "kind": "arch", "head": 2.15, "frame": Props.WOOD}]     # (a doorway: a door here would stand between the camera and the kitchen)
	p.side(g1, 0.0, 6.4, FRONT, parlour["paper"])
	p.side(g1, 5.6, 6.4, FRONT, hall["paper"], arch_ops)
	p.side(g1, 9.0, 6.4, FRONT, hall["paper"])
	p.cross(g2, 6.4, 0, 5.6, parlour["paper"], parlour_back_ops)
	p.cross(g2, 6.4, 5.6, 9, hall["paper"], hall_back_ops)
	var kitchen_side_ops := [{"a": 5.3, "b": 6.2, "colour": white_door, "frame": Props.WOOD, "hinge": "b", "swing": -1}]
	var dining_back_ops := [{"a": 0.6, "b": 2.0, "kind": "arch", "head": 2.2, "frame": white}]      # a wide opening: doors here would stand between the camera and the sun room
	var kitchen_back_ops := [{"a": 8.0, "b": 8.85, "kind": "arch", "head": 2.1, "frame": Props.WOOD}]
	p.side(g2, 0.0, 3.0, 6.4, dining["paper"])
	p.side(g2, 5.0, 3.0, 6.4, kitchen_paint, kitchen_side_ops)
	p.side(g2, 9.0, 3.0, 6.4, kitchen_paint)
	p.cross(g3, 3.0, 0, 5.0, dining["paper"], dining_back_ops)
	p.cross(g3, 3.0, 5.0, 9, kitchen_paint, kitchen_back_ops)
	var sun_side_ops := [
		{"a": 0.35, "b": 1.4, "kind": "window", "sill": 0.6, "head": 2.3, "frame": white},
		{"a": 1.6, "b": 2.65, "kind": "window", "sill": 0.6, "head": 2.3, "frame": white},
	]
	var sun_back_ops := [
		{"a": 0.35, "b": 1.55, "kind": "window", "sill": 0.6, "head": 2.3, "frame": white},
		{"a": 1.75, "b": 3.25, "kind": "window", "sill": 0.6, "head": 2.3, "frame": white},
		{"a": 3.45, "b": 4.65, "kind": "window", "sill": 0.6, "head": 2.3, "frame": white},
	]
	p.side(g3, 0.0, 0, 3.0, sun_paint, sun_side_ops)
	p.side(g3, 5.0, 0, 3.0, pantry_look)
	p.side(g3, 9.0, 0, 3.0, pantry_look)
	p.cross(g3, 0.0, 0, 5.0, sun_paint, sun_back_ops, {"back": true})
	p.cross(g3, 0.0, 5.0, 9, pantry_look, [PANTRY_WINDOW.merged({"frame": white})], {"back": true})

	# ---- upstairs walls
	var bed_side_ops := [{"a": 9.4, "b": 10.5, "kind": "window", "sill": 0.85, "head": 2.15, "frame": white}]
	var bed_door_ops := [{"a": 9.6, "b": 10.5, "hinge": "a", "colour": white_door, "frame": Props.WOOD}]
	var bed_back_ops := [{"a": UP + 3.95, "b": UP + 4.85, "colour": white_door, "frame": Props.WOOD, "name": "SEWING ROOM DOOR", "swing": 1}]
	var uphall_back_ops := [{"a": UP + 7.95, "b": UP + 8.85,"colour": white_door, "frame": Props.WOOD, "name": "BATHROOM DOOR", "swing": 1}]
	var sew_back_ops := [{"a": UP + 1.6, "b": UP + 3.2, "kind": "window", "sill": 1.1, "head": 2.2, "frame": white}]
	var bath_back_ops := [{"a": UP + 5.5, "b": UP + 6.6, "kind": "window", "sill": 1.3, "head": 2.05, "frame": white, "pane": Color(0.86, 0.92, 0.96, 0.92)}]
	p.cross(h1, FRONT, UP, UP + 9, bedroom["paper"])
	p.side(h1, UP, 5.6, FRONT, bedroom["paper"], bed_side_ops)
	p.side(h1, UP + 5.6, 5.6, FRONT, hall["paper"], bed_door_ops)
	p.side(h1, UP + 9, 5.6, FRONT, hall["paper"])
	p.cross(h2, 5.6, UP, UP + 5.6, bedroom["paper"], bed_back_ops)
	p.cross(h2, 5.6, UP + 5.6, UP + 9, hall["paper"], uphall_back_ops)
	p.side(h2, UP, 2.6, 5.6, sewing["paper"])
	p.side(h2, UP + 5.0, 2.6, 5.6, bath_tile)
	p.side(h2, UP + 9, 2.6, 5.6, bath_tile)
	p.cross(h2, 2.6, UP, UP + 5.0, sewing["paper"], sew_back_ops, {"back": true})
	p.cross(h2, 2.6, UP + 5.0, UP + 9, bath_tile, bath_back_ops, {"back": true})

	# ---- the papered walls: stripes, wainscot and rail on each face the room shows
	_dress(p, g1, false, 0.0, 6.475, 10.925, 1.0, parlour)
	_dress(p, g1, true, 6.4, 0.075, 5.525, 1.0, parlour, parlour_back_ops)
	_dress(p, g1, false, 5.6, 6.475, 10.925, -1.0, parlour, arch_ops, true)
	_dress(p, g1, false, 5.6, 6.475, 10.925, 1.0, hall, arch_ops)
	_dress(p, g1, true, 6.4, 5.675, 8.925, 1.0, hall, hall_back_ops)
	_dress(p, g1, false, 9.0, 6.475, 10.925, -1.0, hall)
	_dress(p, g2, false, 0.0, 3.075, 6.325, 1.0, dining)
	_dress(p, g2, true, 3.0, 0.075, 4.925, 1.0, dining, dining_back_ops)
	_dress(p, g2, false, 5.0, 3.075, 6.325, -1.0, dining, kitchen_side_ops, true)
	_dress(p, h1, false, UP, 5.675, 10.925, 1.0, bedroom, bed_side_ops)
	_dress(p, h1, true, 5.6, UP + 0.075, UP + 5.525, 1.0, bedroom, bed_back_ops)
	_dress(p, h1, false, UP + 5.6, 5.675, 10.925, -1.0, bedroom, bed_door_ops, true)
	_dress(p, h1, false, UP + 5.6, 5.675, 10.925, 1.0, hall, bed_door_ops)
	_dress(p, h1, true, 5.6, UP + 5.675, UP + 8.925, 1.0, hall, uphall_back_ops)
	_dress(p, h1, false, UP + 9, 5.675, 10.925, -1.0, hall)
	_dress(p, h2, false, UP, 2.675, 5.525, 1.0, sewing)
	_dress(p, h2, true, 2.6, UP + 0.075, UP + 4.925, 1.0, sewing, sew_back_ops)
	_dress(p, h2, false, UP + 5.0, 2.675, 5.525, -1.0, sewing, [], true)

	_street(p, st, front, front_ops)
	_porch(p, st)
	_yard(p, st)
	_front_rooms(p, g1)
	_middle_rooms(p, g2, kitchen_paint)
	_back_rooms(p, g3, sun_paint)
	_bedroom(p, h1)
	_upstairs_back(p, h2)


## A papered wall face: props_bea.papered in band b's node. `overlay` lays the
## room's paper over the face first (a wall whose own look is the next room's).
static func _dress(p: Node3D, b: int, along_u: bool, at: float, from: float, to: float, side: float, look: Dictionary, openings := [], overlay := false) -> void:
	Bea.papered(p, p.node_of(b), along_u, at, from, to, side, look["stripe"], look["wainscot"], look["rail"], Bea.holes(openings), look["paper"] if overlay else null)


# ------------------------------------------------------------------ outside

static func _street(p: Node3D, st: int, front: Node3D, front_ops: Array) -> void:
	var n: Node3D = p.node_of(st)
	var white := Bea.WHITE
	var grass := Kit.tex("stucco", 2.5, Color(0.35, 0.5, 0.25), true, Color(0.44, 0.74, 0.36))
	# The ground round the house: side yards, the back, the neighbours' yards.
	for piece: Array in [[-13.0, -4.0, 0.0, 11.0], [9.0, -4.0, 22.0, 11.0], [0.0, -4.0, 9.0, 0.0], [-13.0, 11.0, -1.2, LOT], [10.2, 11.0, 22.0, LOT], [-1.2, 11.0, 0.0, PORCH], [9.0, 11.0, 10.2, PORCH]]:
		var r: Rect2 = p.rect(piece[0], piece[1], piece[2], piece[3])
		Kit.box(n, Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, -0.15, r.get_center().y), grass)

	# The house front: clapboards, shutters, the upstairs windows, the eaves.
	var upstairs := [[1.0, 2.2, true], [3.2, 4.4, false], [6.6, 7.6, true]]
	var hole_list := Bea.holes(front_ops)
	for w: Array in upstairs:
		hole_list.append([w[0] - 0.12, w[1] + 0.12, 3.38, 5.02])
	Bea.siding(p, front, true, FRONT, -0.0, 9.0, 1.0, 0.0, 6.0, LINE, hole_list)
	for w: Array in [[1.0, 4.4, 0.55, 2.3], [HALL_WINDOW[0], HALL_WINDOW[1], 0.9, 2.2], [1.0, 2.2, 3.5, 4.9], [3.2, 4.4, 3.5, 4.9], [6.6, 7.6, 3.5, 4.9]]:
		for side: float in [-1.0, 1.0]:
			var u0: float = w[0] - 0.55 if side < 0 else w[1] + 0.09
			p.slab(front, true, FRONT + 0.105, u0, u0 + 0.46, w[2], w[3], 0.03, SHUTTER)
			var y: float = w[2] + 0.12
			while y < w[3] - 0.1:
				p.slab(front, true, FRONT + 0.125, u0 + 0.06, u0 + 0.4, y, y + 0.03, 0.01, SHUTTER.darkened(0.3))
				y += 0.13
	for w: Array in upstairs:
		p.slab(front, true, FRONT + 0.1, w[0] - 0.08, w[1] + 0.08, 3.42, 4.98, 0.04, white)
		p.slab(front, true, FRONT + 0.115, w[0], w[1], 3.5, 4.9, 0.03, Kit.flat(GLOW, 0.5) if w[2] else NIGHT)
		p.slab(front, true, FRONT + 0.13, w[0] + 0.006, w[1] - 0.006, 4.18, 4.22, 0.02, white)
		p.slab(front, true, FRONT + 0.132, (w[0] + w[1]) * 0.5 - 0.02, (w[0] + w[1]) * 0.5 + 0.02, 3.506, 4.894, 0.02, white)
	p.slab(front, true, FRONT, -0.35, 9.35, 6.0, 6.22, 0.5, white)
	# Lace curtains in the parlour window (on the front, so they go when he is indoors).
	var lace := Color(0.98, 0.97, 0.92, 0.82)
	for seg: Array in [[1.04, 1.75], [3.65, 4.36]]:
		p.slab(front, true, FRONT - 0.13, seg[0], seg[1], 0.6, 2.18, 0.02, lace)
	p.slab(front, true, FRONT - 0.13, HALL_WINDOW[0] + 0.02, HALL_WINDOW[1] - 0.02, 0.95, 1.55, 0.02, lace)
	p.slab(front, true, FRONT - 0.15, 1.0, 4.4, 2.0, 2.27, 0.02, Color(0.75, 0.25, 0.3))
	p.slab(front, true, FRONT, 1.02, 4.38, 1.45, 1.49, 0.04, trim_of(front_ops))
	p.slab(front, true, FRONT + 0.003, 2.12, 2.16, 0.57, 2.28, 0.04, trim_of(front_ops))
	p.slab(front, true, FRONT + 0.003, 3.24, 3.28, 0.57, 2.28, 0.04, trim_of(front_ops))
	# The sides: clapboard skins outside the rooms' own walls, seen from the street only.
	for side: float in [-1.0, 1.0]:
		var u := 9.0 if side > 0 else 0.0
		var wins := [[8.2, 9.2, 1.0, 2.2, false], [4.4, 5.4, 1.0, 2.2, true], [1.0, 2.0, 1.2, 2.0, false], [8.0, 9.0, 3.5, 4.9, true], [3.6, 4.6, 3.5, 4.9, false]]
		if side < 0:
			wins = [[7.6, 8.6, 1.0, 2.2, true], [4.3, 5.3, 1.0, 2.2, false], [0.35, 2.65, 0.6, 2.3, true], [9.4, 10.5, 3.5, 4.9, true], [3.5, 4.5, 3.5, 4.9, false]]
		_skin(p, front, u, side, wins)
	# The roof: a gable to the street, the sun room's lean-to at the back.
	var roof := Color(0.3, 0.27, 0.3)
	Kit.box(front, Vector3(5.6, 0.14, 9.2), p.pt(2.15, 6.7, 7.32), roof, Vector3(0, 0, 28.6))
	Kit.box(front, Vector3(5.6, 0.14, 9.2), p.pt(6.85, 6.7, 7.32), roof, Vector3(0, 0, -28.6))
	var gable := Kit.cyl(front, 5.6, 0.15, p.pt(4.5, FRONT, 6.0 + 0.5 * 5.6 * 0.3155), BUTTER, Vector3(-90, 0, 0), 3)
	gable.scale = Vector3(1, 1, 0.3155)
	p.slab(front, true, FRONT + 0.1, 3.9, 5.1, 6.55, 7.35, 0.04, white)
	p.slab(front, true, FRONT + 0.115, 4.0, 5.0, 6.65, 7.25, 0.03, NIGHT)
	Kit.box(front, Vector3(9.8, 0.12, 2.9), p.pt(4.5, 1.3, 3.15), roof, Vector3(-12, 0, 0))

	# The neighbours: frame houses with porches too.
	Bea.neighbour(p, st, -11.4, FRONT, 9.0, Color(0.68, 0.82, 0.66), Color(0.52, 0.66, 0.5), Color(0.95, 0.95, 0.9), Color(0.2, 0.3, 0.45), true, 1)
	Bea.neighbour(p, st, 11.4, FRONT, 9.0, Kit.tex("painted_block", 0.6, Color(0.7, 0.74, 0.8), true, Color(0.78, 0.86, 0.98)), Color(0.55, 0.6, 0.7), Color(0.2, 0.36, 0.3), Color(0.75, 0.68, 0.5), false, -1)
	Bea.hoop_fence(p, n, true, LOT - 0.05, -11.3, -1.3)
	Bea.hoop_fence(p, n, false, -1.3, 11.1, LOT - 0.05)
	p.fence(st, true, LOT - 0.05, 10.3, 20.4, [], 1.0, "chain")
	Outdoor.tree(p, st, -1.4, 6.2, "a", 1.0, 30.0)
	Outdoor.tree(p, st, 10.4, 6.8, "b", 1.1, 200.0)
	Outdoor.shrub(p, st, -6.0, 14.0, "c", 1.2)
	Outdoor.shrub(p, st, 14.8, 14.2, "a", 1.1)
	# On the pavement.
	Props.street_lamp(p, st, 2.2, 17.85)
	Props.hydrant(p, st, 10.9, 17.8)
	Props.cans(p, st, 11.9, 16.2, 2)


static func trim_of(ops: Array) -> Color:
	return ops[0].get("frame", Bea.WHITE)


## A clapboard skin on one side of the house, just outside the rooms' own wall
## at u (side -1 the left, +1 the right), with painted-on windows: [v0, v1,
## y0, y1, lit]. Built in the house front's node, so it shows from the street only.
static func _skin(p: Node3D, n: Node3D, u: float, side: float, wins: Array) -> void:
	var at := u + side * 0.018           # its outer face is 9.3 cm out from the wall's middle
	var white := Bea.WHITE
	var hole_list: Array = []
	for w: Array in wins:
		hole_list.append([w[0] - 0.1, w[1] + 0.1, w[2] - 0.1, w[3] + 0.1])
	Bea.panel(p, n, false, at, 2.6, FRONT + 0.1, side, 0.0, 6.0, 0.015, BUTTER, [], -0.015)
	Bea.panel(p, n, false, at, -0.1, 2.6, side, 0.0, 3.0, 0.015, BUTTER, [], -0.015)
	Bea.siding(p, n, false, at, 2.6, FRONT + 0.1, side, 0.0, 6.0, LINE, hole_list)
	Bea.siding(p, n, false, at, -0.1, 2.6, side, 0.0, 3.0, LINE, hole_list)
	for w: Array in wins:
		var face := at + side * 0.09
		p.slab(n, false, face + side * 0.01, w[0] - 0.08, w[1] + 0.08, w[2] - 0.08, w[3] + 0.08, 0.04, white)
		p.slab(n, false, face + side * 0.025, w[0], w[1], w[2], w[3], 0.03, Kit.flat(GLOW, 0.5) if w[4] else NIGHT)
		p.slab(n, false, face + side * 0.04, w[0] + 0.006, w[1] - 0.006, (w[2] + w[3]) * 0.5 - 0.02, (w[2] + w[3]) * 0.5 + 0.02, 0.02, white)
	p.slab(n, false, at + side * 0.2, -0.3, FRONT + 0.3, 6.0, 6.22, 0.5, white)
	p.slab(n, false, at + side * 0.2, -0.3, 2.6, 3.0, 3.15, 0.4, white)


static func _porch(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var white := Bea.WHITE
	var post_v := PORCH - 0.12
	# Posts along the front edge, the railing between them (a gap at the steps), the ends.
	for u: float in [0.12, 3.2, STEPS[0] - 0.1, STEPS[1] + 0.1, 8.88]:
		Bea.porch_post(p, st, u, post_v)
	for run: Array in [[0.22, 3.1], [3.3, STEPS[0] - 0.2], [STEPS[1] + 0.2, 8.78]]:
		Bea.porch_rail(p, st, true, post_v, run[0], run[1])
	Bea.porch_rail(p, st, false, 0.12, FRONT + 0.1, post_v - 0.1)
	Bea.porch_rail(p, st, false, 8.88, FRONT + 0.1, post_v - 0.1)
	p.fence(st, true, PORCH, STEPS[0], STEPS[1], [[STEPS[0], STEPS[1]]])        # the way down the steps
	# The roof: the ceiling painted blue, the shingles over it, a white fascia.
	var mid_v := (FRONT + 0.075 + PORCH + 0.2) * 0.5
	var long := PORCH + 0.2 - FRONT - 0.075
	Kit.box(n, Vector3(9.5, 0.03, long), p.pt(4.5, mid_v, 2.635), Color(0.62, 0.82, 0.86))
	Kit.box(n, Vector3(9.5, 0.1, long), p.pt(4.5, mid_v, 2.7), Color(0.85, 0.84, 0.78))
	Kit.box(n, Vector3(9.7, 0.08, long + 0.2), p.pt(4.5, mid_v + 0.05, 2.98), Color(0.3, 0.27, 0.3), Vector3(9, 0, 0))
	p.slab(n, true, PORCH + 0.22, -0.27, 9.27, 2.45, 2.8, 0.05, white)
	p.slab(n, false, -0.27, FRONT + 0.08, PORCH + 0.195, 2.45, 2.8, 0.05, white)
	p.slab(n, false, 9.27, FRONT + 0.08, PORCH + 0.195, 2.45, 2.8, 0.05, white)
	Props.words(n, "3912", p.pt((STEPS[0] + STEPS[1]) * 0.5, PORCH + 0.255, 2.62), 0.18, Color(0.15, 0.15, 0.18))
	# By the door: the lantern, the mailbox, the mat.
	Bea.lantern(n, p.pt(DOOR[0] - 0.36, FRONT + 0.075, 1.95))
	Bea.mailbox(n, p.pt(DOOR[0] - 0.36, FRONT + 0.075, 1.3))
	var mat := Kit.box(n, Vector3(0.9, 0.012, 0.5), p.pt((DOOR[0] + DOOR[1]) * 0.5, FRONT + 0.4, 0.006), Color(0.55, 0.42, 0.25))
	Props.words(n, "WELCOME", mat.position + Vector3(0, 0.008, 0), 0.1, Color(0.3, 0.2, 0.12)).rotation_degrees = Vector3(-90, 0, 0)
	# Her porch: the glider under the window, a little table, two rockers, ferns.
	Bea.glider(p, st, 1.75, FRONT + 0.47)
	var table := Props.table(p, st, 3.08, FRONT + 0.4, 0.0, 0.48, 0.48, white, 0.62)
	Kit.cyl(table, 0.06, 0.2, Vector3(-0.08, 0.72, 0), Color(0.85, 0.92, 0.95, 0.6), Vector3.ZERO, 10)
	Kit.cyl(table, 0.05, 0.16, Vector3(-0.08, 0.7, 0), Color(0.6, 0.35, 0.15, 0.85), Vector3.ZERO, 10)
	for x: float in [0.1, 0.18]:
		Kit.cyl(table, 0.035, 0.12, Vector3(x, 0.68, 0.08 - x * 0.5), Color(0.85, 0.92, 0.95, 0.6), Vector3.ZERO, 8)
	Bea.rocker(p, st, 3.85, FRONT + 0.72, 12.0)
	Bea.rocker(p, st, 4.8, FRONT + 0.72, -12.0, white, Color(0.3, 0.5, 0.8))
	var stand := Props.table(p, st, 8.42, FRONT + 0.35, 0.0, 0.42, 0.42, white, 0.5)
	Bea.fern(stand, Vector3(0, 0.5, 0), 0.9)
	for u: float in [1.65, 4.7]:
		Bea.hanging_fern(n, p.pt(u, PORCH - 0.3, 2.62), 0.58)


static func _yard(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var white := Bea.WHITE
	# The fence: pickets along the pavement with the gate, and down both sides.
	# (Low, so he shows over it from the street.)
	Bea.pickets(p, st, true, LOT, -1.2, 10.2, [[GATE[0], GATE[1]]], 0.78)
	Bea.pickets(p, st, false, -1.2, PORCH, LOT - 0.06, [], 0.78, white, 1.0)
	Bea.pickets(p, st, false, 10.2, PORCH, LOT - 0.06, [], 0.78, white, -1.0)
	# The gate stands open, folded back against the inside of the fence.
	var leaf := Kit.group(n, p.pt(GATE[0] - 0.02, LOT - 0.12))
	for k in 8:
		Kit.box(leaf, Vector3(0.075, 0.68, 0.022), Vector3(-0.07 - k * 0.13, 0.37, 0), white.darkened(0.04))
	for y: float in [0.2, 0.55]:
		Kit.box(leaf, Vector3(1.08, 0.06, 0.03), Vector3(-0.52, y, -0.03), white.darkened(0.12))
	p.block(GATE[0] - 1.16, LOT - 0.17, GATE[0], LOT - 0.09)
	# Flower beds along the porch, shrubs at its ends, brick cheeks at the steps.
	Bea.flower_bed(p, st, (-1.15 + STEPS[0] - 0.25) * 0.5, PORCH + 0.3, STEPS[0] - 0.25 + 1.15, 0.56, 1.0)
	Bea.flower_bed(p, st, (STEPS[1] + 0.25 + 10.15) * 0.5, PORCH + 0.3, 10.15 - STEPS[1] - 0.25, 0.56, 7.0)
	Outdoor.shrub(p, st, -0.6, 12.2, "a", 1.15)
	Outdoor.shrub(p, st, 9.6, 12.2, "b", 1.15)
	var brick := Kit.tex("brick", 1.0, Color(0.6, 0.3, 0.24), false)
	for u: float in [STEPS[0] - 0.1, STEPS[1] + 0.1]:
		var cheek: Node3D = p.prop(st, u, PORCH + 0.3, 0.0, 0.22, 0.56)
		Kit.block(cheek, Vector3(0.22, 0.42, 0.56), Vector3.ZERO, brick)
		Kit.box(cheek, Vector3(0.26, 0.04, 0.6), Vector3(0, 0.44, 0), Color(0.75, 0.74, 0.7))
		Bea.geraniums(cheek, Vector3(0, 0.46, 0.05))
	# The steps (two low concrete treads, the riser's shadow on each), the path to the gate.
	var stone := Color(0.74, 0.73, 0.7)
	for k in 2:
		var v0 := PORCH + 0.02 + k * 0.27
		Kit.box(n, Vector3(STEPS[1] - STEPS[0] - 0.04, 0.012, 0.26), p.pt((STEPS[0] + STEPS[1]) * 0.5, v0 + 0.13, 0.014 - 0.005 * k), stone.lightened(0.06 * (1 - k)))
		Kit.box(n, Vector3(STEPS[1] - STEPS[0] - 0.04, 0.004, 0.05), p.pt((STEPS[0] + STEPS[1]) * 0.5, v0 + 0.235, 0.022 - 0.005 * k), stone.darkened(0.45))
	var v := PORCH + 0.62
	var k := 0
	while v < LOT - 0.2:
		var w := 0.85 + 0.12 * Props.rnd(k * 2.1)
		Kit.box(n, Vector3(w, 0.01, 0.42), p.pt((DOOR[0] + DOOR[1]) * 0.5 + 0.06 * (Props.rnd(k * 3.7) - 0.5), v + 0.21, 0.005), stone.darkened(0.06 * (k % 2)))
		v += 0.5
		k += 1


# ------------------------------------------------------------- ground floor

static func _front_rooms(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The parlour, the good room. On the back wall the piano with the family
	# on it and the console television; the plastic-covered sofa down the left wall.
	Bea.piano(p, b, 3.1, 6.475 + 0.535)
	Bea.console_tv(p, b, 4.78, 6.475 + 0.27)
	Bea.plastic_sofa(p, b, 0.075 + 0.5, 9.0, 90.0)
	Props.rug(p, b, 2.5, 8.9, 3.0, 2.4, Color(0.48, 0.14, 0.18))
	var coffee := Props.table(p, b, 1.75, 9.0, 90.0, 1.0, 0.55, Bea.MAHOGANY, 0.45)
	Bea.doily(coffee, Vector3(0, 0.45, 0), 0.2)
	Kit.cyl(coffee, 0.11, 0.06, Vector3(0, 0.49, 0.0), Color(0.75, 0.85, 0.8, 0.7), Vector3.ZERO, 12, 0.13)    # the candy dish
	for k in 5:
		Kit.ball(coffee, 0.025, Vector3(-0.05 + k * 0.025, 0.53, 0.02 * (k % 2)), Bea.BLOOMS[k], 5)
	Kit.block(coffee, Vector3(0.24, 0.05, 0.3), Vector3(0.0, 0.45, 0.3), Color(0.12, 0.1, 0.1))         # the big Bible
	var end := Props.table(p, b, 0.36, 7.38, 0.0, 0.5, 0.5, Bea.MAHOGANY, 0.62)
	Bea.doily(end, Vector3(0, 0.62, 0), 0.18)
	Bea.table_lamp(end, Vector3(0, 0.63, 0))
	Bea.floor_lamp(p, b, 0.38, 10.55)
	Bea.fern_stand(p, b, 4.75, 10.62)        # by the window, where it is out of the way of the camera
	for k in 3:
		Bea.wall_picture(p, b, 0.075, 8.25 + k * 0.75, 90.0, 0.42 if k != 1 else 0.5, 0.52 if k != 1 else 0.62, 1.75, "portrait", 2.0 + k * 1.9)
	Bea.wall_picture(p, b, 3.1, 6.475, 0.0, 0.9, 0.6, 2.05, "scene", 4.0)
	Bea.wall_picture(p, b, 4.78, 6.475, 0.0, 0.38, 0.48, 1.6, "portrait", 9.0)
	Props.clock(p, b, 1.35, 6.475, 0.0, 2.55)
	# The front hall: the stairs up the left wall, her church hats on the stand,
	# the telephone on its bench.
	Props.stairs(p, b, STAIR_U, STAIR_V, 0.0, 0.95, STAIR_L, 2.9, Bea.MAHOGANY.lightened(0.15))
	p.portal(b, "GO UPSTAIRS", STAIR_U, 9.72, UP + 6.5, 6.05)
	Bea.hat_stand(p, b, 7.25, 6.475 + 0.34)
	Bea.mirror(p, b, 7.25, 6.475, 0.0, 0.5, 0.7, 1.75)
	Bea.gossip_bench(p, b, 8.925 - 0.24, 8.3, 270.0)
	Bea.wall_picture(p, b, 8.925, 8.3, 270.0, 0.4, 0.5, 1.75, "portrait", 13.0)
	Props.radiator(p, b, 8.8, 10.2, 270.0, 0.9)
	Props.rug(p, b, 7.35, 8.6, 0.95, 3.4, Color(0.25, 0.32, 0.5))


static func _middle_rooms(p: Node3D, b: int, kitchen_paint: Variant) -> void:
	var n: Node3D = p.node_of(b)
	# The dining room: the china cabinet on the left wall, the table under its
	# lace cloth, the sideboard by the doors to the sun room.
	Bea.china_cabinet(p, b, 0.075 + 0.28, 4.7, 90.0)
	var table := Bea.lace_table(p, b, 2.65, 4.9, 0.0, 1.3, 0.85)
	Bea.fruit_bowl(table, Vector3(0, 0.75, 0))
	for x: float in [-0.45, 0.45]:
		Bea.candlestick(table, Vector3(x, 0.75, 0.05))
	for x: float in [2.3, 3.0]:
		Props.seat(p, b, x, 4.05, 0.0, Bea.MAHOGANY, Color(0.62, 0.2, 0.25))
	Props.seat(p, b, 3.68, 4.9, 270.0, Bea.MAHOGANY, Color(0.62, 0.2, 0.25))
	var side := Props.dresser(p, b, 4.12, 3.075 + 0.26, 0.0, 1.45, Bea.MAHOGANY, 0.86, 0.5)
	Bea.runner(side, Vector3(0, 0.86, 0), 1.1, 0.3, 0.1)
	Bea.candlestick(side, Vector3(-0.5, 0.866, 0.0))
	Bea.candlestick(side, Vector3(0.5, 0.866, 0.0))
	Kit.cyl(side, 0.17, 0.1, Vector3(0, 0.92, 0.0), Color(0.82, 0.8, 0.74), Vector3.ZERO, 12, 0.2)      # the cake dish
	Kit.cyl(side, 0.15, 0.12, Vector3(0, 1.03, 0.0), Color(0.95, 0.92, 0.85), Vector3.ZERO, 12)
	Kit.cyl(side, 0.16, 0.05, Vector3(0, 1.11, 0.0), Color(0.55, 0.32, 0.2), Vector3.ZERO, 12)
	Bea.wall_picture(p, b, 4.12, 3.075, 0.0, 1.0, 0.55, 1.95, "scene", 21.0)
	Bea.wall_picture(p, b, 0.075, 4.7, 90.0, 0.45, 0.55, 2.4, "portrait", 17.0)
	# Her good plates, hung on the wall in a row.
	for k in 3:
		var pu := 2.45 + k * 0.38
		var py := 2.05 + 0.08 * float(k % 2)
		Kit.cyl(n, 0.15, 0.02, p.pt(pu, 3.075 + 0.01, py), Color(0.96, 0.95, 0.9), Vector3(90, 0, 0), 16)
		Kit.cyl(n, 0.115, 0.02, p.pt(pu, 3.075 + 0.016, py), [Color(0.3, 0.45, 0.8), Color(0.75, 0.3, 0.35), Color(0.3, 0.6, 0.45)][k], Vector3(90, 0, 0), 16)
		Kit.cyl(n, 0.075, 0.02, p.pt(pu, 3.075 + 0.022, py), Color(0.96, 0.95, 0.9), Vector3(90, 0, 0), 14)
	Props.rug(p, b, 2.65, 4.85, 2.4, 1.9, Color(0.3, 0.32, 0.5))
	# The kitchen: the stove with her big pot on, the sink, the fridge, the
	# table with a pie on it, the calendar from her shop.
	var stove := Props.stove(p, b, 6.3, 3.075 + 0.34)
	Bea.stockpot(stove, Vector3(-0.19, 0.915, -0.12))
	Kit.cyl(stove, 0.08, 0.14, Vector3(0.19, 0.985, 0.17), Color(0.85, 0.2, 0.18), Vector3.ZERO, 10, 0.06)     # the kettle
	Kit.box(stove, Vector3(0.04, 0.03, 0.1), Vector3(0.28, 1.0, 0.17), Props.DARK)
	var sink := Props.sink_unit(p, b, 7.32, 3.075 + 0.33, 0.0, 1.2)
	Bea.dish_rack(sink, Vector3(0.38, 0.905, 0.0))
	Bea.canisters(sink, Vector3(-0.52, 0.905, -0.15))
	Bea.wall_cupboards(p, b, 6.85, 3.075, 0.0, 2.1)
	Bea.panel(p, n, true, 3.0, 5.075, 7.95, 1.0, 0.9, 1.5, 0.012, Kit.tex("block_plain", 0.3, Color(0.75, 0.9, 0.82), true, Color(0.8, 1.0, 0.88)), Bea.holes([{"a": 8.0, "b": 8.85}]))
	var fridge := Props.fridge(p, b, 5.075 + 0.37, 4.0, 90.0)
	Kit.box(fridge, Vector3(0.12, 0.12, 0.006), Vector3(-0.15, 1.45, 0.356), Color(0.95, 0.85, 0.4), Vector3(0, 0, -8))
	Kit.box(fridge, Vector3(0.14, 0.1, 0.006), Vector3(0.1, 1.05, 0.356), Color(0.6, 0.8, 0.95), Vector3(0, 0, 5))
	var kt := Bea.kitchen_table(p, b, 6.9, 5.05, 0.0, 0.95, 0.72)
	Bea.pie(kt, Vector3(0.1, 0.75, 0.02))
	Kit.cyl(kt, 0.04, 0.1, Vector3(-0.28, 0.8, -0.15), Color(0.95, 0.95, 0.92), Vector3.ZERO, 8)        # salt and pepper
	Kit.cyl(kt, 0.04, 0.1, Vector3(-0.2, 0.8, -0.15), Color(0.2, 0.2, 0.22), Vector3.ZERO, 8)
	Props.seat(p, b, 6.2, 5.05, 90.0, Color(0.85, 0.85, 0.82), Color(0.8, 0.2, 0.18))
	Props.seat(p, b, 7.6, 5.05, 270.0, Color(0.85, 0.85, 0.82), Color(0.8, 0.2, 0.18))
	Bea.calendar(p, b, 5.075, 4.85, 90.0, 1.55, "MARCH 1994", 1.35)
	Props.clock(p, b, 8.42, 3.075, 0.0, 2.5)
	var oval := Kit.cyl(n, 0.6, 0.012, p.pt(6.9, 5.05, 0.006), Color(0.45, 0.55, 0.75), Vector3.ZERO, 18)
	oval.scale = Vector3(1.4, 1, 1)


static func _back_rooms(p: Node3D, b: int, sun_paint: Variant) -> void:
	var n: Node3D = p.node_of(b)
	# The sun room, all windows on the back and the left: where she sits.
	Bea.panel(p, n, false, 5.0, 0.075, 2.925, -1.0, 0.0, 2.86, 0.005, sun_paint)
	Bea.wicker_chair(p, b, 2.5, 0.075 + 0.4, 0.0, 1.3, Color(0.85, 0.45, 0.4))
	Bea.wicker_chair(p, b, 4.1, 1.35, -35.0)
	Bea.radio_table(p, b, 3.55, 0.45)
	Bea.violets(p, b, 0.075 + 0.26, 2.0, 90.0)
	Bea.rubber_plant(p, b, 0.45, 0.45, 1.05)
	Bea.bird_cage(p, b, 4.55, 2.45)
	Bea.fern_stand(p, b, 1.2, 0.4, 0.8)
	var rug := Kit.cyl(n, 0.7, 0.012, p.pt(2.6, 1.55, 0.006), Color(0.6, 0.45, 0.65), Vector3.ZERO, 18)
	rug.scale = Vector3(1.5, 1, 1)
	var rug2 := Kit.cyl(n, 0.5, 0.012, p.pt(2.6, 1.55, 0.009), Color(0.85, 0.75, 0.5), Vector3.ZERO, 18)
	rug2.scale = Vector3(1.5, 1, 1)
	# Out the windows: the back yard, a clothes line, the next fence.
	var grass := Kit.tex("stucco", 2.5, Color(0.35, 0.5, 0.25), true, Color(0.44, 0.74, 0.36))
	Kit.box(n, Vector3(30.0, 0.3, 6.0), p.pt(4.5, -3.0, -0.18), grass)
	var boardfence := Color(0.52, 0.42, 0.32)
	p.slab(n, true, -5.0, -6.0, 15.0, 0.0, 1.5, 0.04, boardfence)
	var gu := -5.85
	while gu < 15.0:
		p.slab(n, true, -4.975, gu, gu + 0.02, 0.0, 1.5, 0.01, boardfence.darkened(0.25))
		gu += 0.15
	for pu: float in [-4.0, -1.0, 2.0, 5.0, 8.0, 11.0, 14.0]:
		Kit.block(n, Vector3(0.1, 1.6, 0.1), p.pt(pu, -4.9), boardfence.darkened(0.15))
	for u: float in [0.5, 7.5]:
		Kit.cyl(n, 0.04, 2.0, p.pt(u, -2.2, 1.0), Props.STEEL, Vector3.ZERO, 6)
	p.slab(n, true, -2.2, 0.5, 7.5, 1.9, 1.91, 0.01, Color(0.9, 0.9, 0.9))
	for k in 3:
		p.slab(n, true, -2.2, 1.4 + k * 1.9, 2.6 + k * 1.9, 1.15, 1.9, 0.02, [Color(0.95, 0.95, 0.92), Color(0.75, 0.82, 0.95), Color(0.95, 0.8, 0.85)][k])
	# The pantry: shelves of her canning, the wringer washer, the back door.
	Bea.preserves(p, b, 6.3, 0.075 + 0.2, 0.0, 2.2)
	Bea.wringer(p, b, 5.5, 2.35)
	Bea.mops(p, b, 8.65, 0.4)
	Props.boxes(p, b, 8.4, 1.55, 2)
	Bea.stripes(p, n, false, 5.0, 0.075, 2.925, 1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, [], 0.0)
	Bea.stripes(p, n, false, 9.0, 0.075, 2.925, -1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, [], 0.0)
	Bea.stripes(p, n, true, 0.0, 5.075, 8.925, 1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, Bea.holes([PANTRY_WINDOW, {"a": 7.75, "b": 8.6, "head": 2.1}]), 0.0)
	# The back door, shut: a panel door with a window and a curtain.
	p.slab(n, true, 0.1, 7.7, 8.65, 0.0, 2.15, 0.04, Props.WOOD)
	p.slab(n, true, 0.12, 7.78, 8.57, 0.0, 2.08, 0.03, Color(0.88, 0.86, 0.78))
	p.slab(n, true, 0.14, 7.9, 8.45, 1.2, 1.9, 0.02, Color(0.2, 0.25, 0.35))
	p.slab(n, true, 0.155, 7.92, 8.43, 1.6, 1.88, 0.02, Color(0.95, 0.85, 0.55))
	Kit.ball(n, 0.035, p.pt(7.88, 0.19, 1.0), Bea.BRASS, 6)


static func pantry_groove() -> Color:
	return Color(0.78, 0.76, 0.66)


# ----------------------------------------------------------------- upstairs

static func _bedroom(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Her room: the bed under its quilt, the dressing table, the hat boxes.
	# The bed stands left of the room's middle, so he does not hide the quilt.
	var bed_u := UP + 1.85
	Bea.quilt_bed(p, b, bed_u, 5.675 + 1.04, 0.0, 1.5, 2.05)
	Bea.nightstand(p, b, bed_u - 1.1, 5.675 + 0.23)
	Bea.nightstand(p, b, bed_u + 1.1, 5.675 + 0.23, 0.0, false)
	Bea.wall_picture(p, b, bed_u, 5.675, 0.0, 0.8, 0.45, 1.95, "words", 0.0, "GOD BLESS OUR HOME")
	Bea.cedar_chest(p, b, bed_u, 8.0)
	Bea.vanity(p, b, UP + 0.075 + 0.46, 8.4, 90.0)
	Bea.hat_boxes(p, b, UP + 0.35, 10.6)
	Props.wardrobe(p, b, UP + 5.525 - 0.31, 7.4, 270.0, 1.2, Bea.MAHOGANY)
	Bea.rocker(p, b, UP + 4.2, 9.4, -40.0, Bea.MAHOGANY, Color(0.6, 0.35, 0.65))
	Bea.wall_picture(p, b, UP + 0.075, 6.6, 90.0, 0.4, 0.5, 1.7, "portrait", 31.0)
	Props.rug(p, b, bed_u + 0.05, 7.15, 2.6, 2.6, Color(0.78, 0.5, 0.56))
	var rug := Kit.cyl(n, 0.65, 0.012, p.pt(UP + 2.4, 9.3, 0.006), Color(0.55, 0.35, 0.55), Vector3.ZERO, 18)
	rug.scale = Vector3(1.6, 1, 1)
	var rug2 := Kit.cyl(n, 0.45, 0.012, p.pt(UP + 2.4, 9.3, 0.009), Color(0.85, 0.8, 0.9), Vector3.ZERO, 18)
	rug2.scale = Vector3(1.6, 1, 1)
	# Curtains at the side window, on the wall either side of it.
	for v: float in [9.18, 10.72]:
		p.slab(n, false, UP + 0.1, v - 0.16, v + 0.16, 0.7, 2.35, 0.03, Color(0.95, 0.85, 0.9))
	# The hall at the top of the stairs.
	Props.stairwell(p, b, UP + STAIR_U, STAIR_V, 0.0, 0.95, STAIR_L, 2.9, Bea.MAHOGANY.lightened(0.15))
	p.portal(b, "GO DOWNSTAIRS", UP + 6.3, 6.1, 6.3, 9.75)
	var linen := Props.dresser(p, b, UP + 8.925 - 0.25, 7.6, 270.0, 1.1, Color(0.9, 0.88, 0.82), 0.9, 0.45)
	Bea.doily(linen, Vector3(0, 0.9, 0), 0.2)
	Bea.table_lamp(linen, Vector3(0, 0.91, 0))
	for k in 3:
		Bea.wall_picture(p, b, UP + 6.3 + k * 0.42, 5.675, 0.0, 0.32, 0.4, 1.7 + 0.12 * (k % 2), "portrait", 40.0 + k * 2.3)
	Props.rug(p, b, UP + 7.5, 8.5, 0.9, 3.2, Color(0.25, 0.32, 0.5))


static func _upstairs_back(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The sewing room: the treadle machine under the window, the dummy, the
	# fabric, a day bed under an afghan.
	Bea.sewing_machine(p, b, UP + 3.05, 2.675 + 0.5)
	Bea.dress_form(p, b, UP + 4.35, 3.05)
	Bea.fabric_shelf(p, b, UP + 0.9, 2.675 + 0.2, 0.0, 1.1)
	Bea.day_bed(p, b, UP + 0.075 + 0.45, 4.55, 90.0, 1.9)
	Props.rug(p, b, UP + 2.6, 4.4, 1.6, 1.0, Color(0.85, 0.6, 0.3))
	# Curtains at the window, and a valance over them.
	var curtain := Color(0.98, 0.86, 0.5)
	for seg: Array in [[UP + 1.3, UP + 1.72], [UP + 3.08, UP + 3.5]]:
		p.slab(n, true, 2.73, seg[0], seg[1], 1.0, 2.35, 0.03, curtain)
		for k in 3:
			p.slab(n, true, 2.75, seg[0] + 0.06 + k * 0.13, seg[0] + 0.09 + k * 0.13, 1.0, 2.2, 0.01, curtain.darkened(0.12))
	p.slab(n, true, 2.752, UP + 1.28, UP + 3.52, 2.2, 2.44, 0.03, Color(0.95, 0.55, 0.45))
	# The bathroom: pink tile to the shoulder, the claw-foot tub under the window.
	var paint := Color(0.98, 0.9, 0.9)
	for wall: Array in [[false, UP + 5.0, 2.675, 5.525, 1.0, []], [true, 2.6, UP + 5.075, UP + 8.925, 1.0, [{"a": UP + 5.5, "b": UP + 6.6, "kind": "window", "sill": 1.3, "head": 2.05}]], [false, UP + 9.0, 2.675, 5.525, -1.0, []]]:
		Bea.panel(p, n, wall[0], wall[1], wall[2], wall[3], wall[4], 1.45, 2.86, 0.008, paint, Bea.holes(wall[5]))
		Bea.panel(p, n, wall[0], wall[1], wall[2], wall[3], wall[4], 1.38, 1.45, 0.025, Color(0.15, 0.12, 0.16), Bea.holes(wall[5]))
	Bea.clawfoot(p, b, UP + 6.05, 2.675 + 0.4, 90.0)
	var loo := Props.toilet(p, b, UP + 7.4, 2.675 + 0.34)
	Bea.toilet_cover(loo)
	Bea.roll_doll(loo, Vector3(0.0, 0.89, -0.22))
	# (Her things keep off the right-hand wall: the bathroom door, see-through
	# in the cut-away wall, stands between the camera and it.)
	Bea.hamper(p, b, UP + 5.3, 3.85)
	Props.basin(p, b, UP + 8.2, 2.675 + 0.23)
	Bea.towels(p, b, UP + 5.075, 4.6, 90.0)
	var mat := Kit.cyl(n, 0.4, 0.012, p.pt(UP + 6.1, 3.75, 0.006), Color(0.95, 0.65, 0.8), Vector3.ZERO, 16)
	mat.scale = Vector3(1.4, 1, 1)
