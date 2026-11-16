extends RefCounted
## Miss Bea's house: the frame house where Miss Bea (who keeps the corner
## grocery, plans/store.gd) has lived for forty years: the end house of one of
## the old Pen Lucy's porch-front rows, wider than the crib (a narrow brick
## rowhouse, one room behind another) and nothing like Large Fry's flat (one
## wide floor in a block). Brick, a flat roof behind a pressed-metal cornice, a
## three-sided sash bay upstairs standing on the roof of the deep porch that
## runs across the whole front, a picket fence round a little front yard; the
## row's other porches go on to the right, and her end wall, with its side
## windows, looks across a passage at the next row's end. A side-hall plan: the
## front door opens at the foot of the stairs, which climb the hall's left
## wall, the parlour through an arch beside it.
## 9 x 11 m, two floors; everything in it forty years' worth of hers.
##
## It is number 510 Rose Hill Terrace, the left end of the row he lives at the
## other end of. Her front door opens onto Rose Hill (plans/street.gd): E by
## the door inside takes him out onto her porch steps there, and the travel
## list (OUTSIDE) puts him at them. The front, the porch (the row's, on its
## 0.7 m deck) and the front yard are drawn there, by `front` below, with the
## door and the windows where these rooms have them. (Placeholder: the number.)
##
##   band 1:       PARLOUR (5.6 x 4.6)  | FRONT HALL (3.4 x 4.6, the stairs)
##   band 2:       DINING ROOM (5 x 3.4) | KITCHEN (4 x 3.4)
##   band 3:       SUN ROOM (5 x 3)      | PANTRY (4 x 3)
##   upstairs 1:   BEDROOM (5.6 x 5.4)  | UPSTAIRS HALL (3.4 x 5.4)
##   upstairs 2:   SEWING ROOM (5 x 3)   | BATHROOM (4 x 3)
##
## Ways through: front door (to Rose Hill); parlour arch to the hall and to the dining room;
## a doorway hall to kitchen; a door dining room to kitchen; wide openings to
## the sun room and the pantry (a door in a cut-away wall stands between the
## camera and the room); upstairs, doors to the bedroom, the sewing room
## (through the bedroom) and the bathroom.
##
## The game floor is flat, so the stairs are a spot you use (E), as in the
## crib. Upstairs is its own stack of bands, drawn 40 m to the right on the
## plan (UP).
##
## Numbers are metres on the plan (see place.gd): u from the house's left
## wall, v from its back wall. The house front is at v = 11 (the plan's depth
## is 15.6, where the front fence stood before her front moved to Rose Hill).
## The new furniture is in props_bea.gd.
##
## Invented here (placeholders): the house number 510, the WELCOME mat, "GOD
## BLESS OUR HOME" on the sampler over her bed, "MARCH 1994" on the calendar
## from her shop (the shop's name on it is the owners' own: MISS BEA'S CORNER
## GROCERY), and the door names FRONT DOOR, SEWING ROOM DOOR, BATHROOM DOOR,
## BACK DOOR (E by the pantry's back door: out into her yard and the alley,
## plans/backs.gd).

const Props := preload("res://scripts/props.gd")
const Bea := preload("res://scripts/props_bea.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const In := preload("res://scripts/props_in.gd")
const Houses := preload("res://scripts/houses.gd")

const UP := 40.0
const FRONT := 11.0           # the house front
const LOT := 15.6             # the plan's depth (where her front fence stood)
const STAIR_U := 6.15         # the middle of the flight, on both floors
const STAIR_V := 7.9
const STAIR_L := 2.8          # v 6.5 (the top) to 9.3 (the foot)
const DOOR := [5.75, 6.65]    # the front door, at the foot of the stairs; the porch steps and the gate line up with it
const STEPS := [5.6, 6.8]
const GATE := [5.6, 6.8]
const HALL_WINDOW := [7.45, 8.25]
const PANTRY_WINDOW := {"a": 5.45, "b": 7.15, "kind": "window", "sill": 2.02, "head": 2.6}   # high, over her shelves

const HEIGHT := 6.9           # the top of the cornice
const GLOW := Color(1.0, 0.84, 0.55)
const NIGHT := Color(0.16, 0.2, 0.3)
const OUTSIDE := "street"     # the place her front door opens onto (main.gd's _travel_to puts him there, at her steps)
const NUMBER := "510"
const W := 9.0
const PARLOUR_WINDOW := [1.0, 4.4]


static func build(p: Node3D) -> void:
	p.setup("MISS BEA'S HOUSE", 9.0, LOT)
	var warm := Color(1.0, 0.84, 0.6)
	var white := Bea.WHITE
	var trim := Color(0.92, 0.9, 0.82)
	var door_red := Color(0.62, 0.14, 0.14)
	var white_door := Color(0.9, 0.88, 0.8)
	var boards := Kit.tex("wood_panel", 1.6, Color(0.5, 0.36, 0.24), true, Color(0.74, 0.6, 0.54))
	var lino := Kit.tex("lino", 0.8, Color(0.7, 0.7, 0.66), true, Color(1.0, 0.98, 0.9))
	var pantry_floor := Kit.tex("lino", 0.8, Color(0.6, 0.3, 0.3), true, Color(1.0, 0.55, 0.5))
	var terracotta := Kit.tex("block_plain", 0.9, Color(0.8, 0.5, 0.36), true, Color(0.95, 0.6, 0.45))
	var bath_floor := Kit.tex("lino", 0.3, Color(0.7, 0.7, 0.7), true, Color(0.9, 0.9, 0.92))

	var g1: int = p.band()
	var g2: int = p.band()
	var g3: int = p.band()
	var h1: int = p.band(1)
	var h2: int = p.band(1)
	p.arrive = p.pt(6.4, 10.35)          # just inside the front door, at the foot of the stairs

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
	p.cross(g1, FRONT, 0, 9, Houses.wall("brick_3"), front_ops, {"h": 6.0})
	# The front door's leaf is not drawn in here: its wall is always cut away (the
	# camera looks in through it), so the leaf was only ever a ghost, and that
	# stood over him as he came in. Rose Hill has the door (`front`); E in the
	# doorway takes him out of it onto her porch steps there. (usables() leaves
	# out a door marked "mate".)
	var front_door: Node3D = p.doors.back()
	front_door.set_meta("mate", true)
	for part: Node in front_door.leaf.get_children():
		part.free()
	p.use_point(g1, "FRONT DOOR", (DOOR[0] + DOOR[1]) * 0.5, 10.55, "goto:" + OUTSIDE, 0.8, 2.0)
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

	_front_rooms(p, g1)
	_middle_rooms(p, g2, kitchen_paint)
	_back_rooms(p, g3, sun_paint)
	_bedroom(p, h1)
	_upstairs_back(p, h2)
	_lights(p, g1, g2, g3, h1, h2)


## The lights in her ceilings and on her walls (props_in.gd), the kitchen's
## tiled walls, and the night outside the upstairs windows.
static func _lights(p: Node3D, g1: int, g2: int, g3: int, h1: int, h2: int) -> void:
	var brass := In.BRASS
	In.pendant(p, g1, 7.7, 7.3, 2.3, brass, "globe")                                    # the front hall: back by the arch, clear of her hats
	In.chandelier(p, g2, 2.65, 4.9, 2.34, 0.32, 5, brass)                              # over the dining table, up clear of her plates
	In.pendant(p, g2, 6.9, 4.6, 2.2, brass, "globe")                                    # the kitchen
	In.pendant(p, g3, 2.6, 1.6, 2.42, Color(0.82, 0.66, 0.4), "drum")                   # the sun room: a rattan shade, up over the window heads
	In.pendant(p, g3, 7.0, 1.6, 2.25, Props.STEEL, "bulb")                              # the pantry
	In.pendant(p, h2, UP + 2.5, 4.3, 2.2, Color(0.3, 0.5, 0.45), "cone")                # the sewing room
	In.wall_strip(p, h2, UP + 8.2, 2.685, 0.0, 0.5, 1.97, In.WARM)                     # a strip light over the bathroom mirror
	# The kitchen's side walls: white tile to a red rail, a skirting; her wall
	# phone by the back door's arch.
	var kitchen := {"lower": Kit.tex("in_tile", 0.6, Color(0.92, 0.9, 0.84), true, Color(1.0, 0.98, 0.92)), "dado": Color(0.78, 0.18, 0.16),
			"dado_y": 1.2, "skirt": Color(0.5, 0.16, 0.14), "skirt_h": 0.12}
	var calendar := {"a": 4.625, "b": 5.075, "kind": "window", "sill": 1.122, "head": 1.978, "bare": true}     # the tile and rail stop round her calendar
	In.dress(p, g2, false, 5.0, 1.0, 3.075, 6.325, [{"a": 5.3, "b": 6.2}, calendar], kitchen)
	In.dress(p, g2, false, 9.0, -1.0, 3.075, 6.325, [], kitchen)
	In.wall_phone(p, g2, 8.915, 3.8, 270.0, 1.5, Color(0.92, 0.86, 0.66))
	# Out of the upstairs windows: the night over the roofs.
	In.night_view(p, h2, true, 2.6, -1.0, UP + 1.6, UP + 3.2, 1.1, 2.2, "sky")
	In.night_view(p, h1, false, UP, -1.0, 9.4, 10.5, 0.85, 2.15, "sky")


## A papered wall face: props_bea.papered in band b's node. `overlay` lays the
## room's paper over the face first (a wall whose own look is the next room's).
static func _dress(p: Node3D, b: int, along_u: bool, at: float, from: float, to: float, side: float, look: Dictionary, openings := [], overlay := false) -> void:
	Bea.papered(p, p.node_of(b), along_u, at, from, to, side, look["stripe"], look["wainscot"], look["rail"], Bea.holes(openings), look["paper"] if overlay else null)


# ------------------------------------------------------------------ outside

## Her front as Rose Hill Terrace shows it (street.gd builds it there, on Rose
## Hill's place p, her left end wall at u0 on the row's front line d, the
## pavement starting at `pave`). The row's porch-front house (houses.gd) with
## her own openings: the parlour's wide window, the door at the foot of the
## stairs (the number on its transom) and the hall window, where her rooms
## have them; upstairs the white sash bay over the parlour, sashes over the door
## and the hall window, the cornice; her end wall on the passage with the side
## windows her bedroom and sun room have; the low roof over the sun room and the
## pantry at the back. The porch is the row's (its 0.7 m deck, its heights), its
## steps at her door; on it her glider, table, rockers and ferns, the lantern
## and the mailbox by the door, the WELCOME mat. In front a little yard: pickets
## along the pavement with the gate standing open, beds of flowers along the
## porch, stones to the steps. The porch and its steps take up floor. Returns
## {"door": u of the door's middle, "steps": v the steps' foot reaches}.
static func front(p: Node3D, st: int, u0: float, d: float, pave: float) -> Dictionary:
	var g: Node3D = Houses.face(p, st, u0, d)
	var n: Node3D = p.node_of(st)
	var f0 := Houses.F0
	var pd := Houses.PD
	var height := 8.22
	var brick := Houses.wall("brick_3")
	var white := Bea.WHITE
	var trim := Color(0.92, 0.9, 0.82)                  # the frames (build's trim)
	var lace := Color(0.98, 0.97, 0.92)
	var main := FRONT - 3.0                             # back to the dining room's back wall
	Houses.fb(g, 0.0, W, 0.0, height, -main, 0.0, brick)
	Houses.fb(g, 0.0, W, height, height + 0.04, -main, -0.36, Houses.SILVER)
	Houses.fb(g, 0.0, W, 0.0, f0 + 3.0, -FRONT, -main, brick)
	Houses.fb(g, -0.1, W, f0 + 3.0, f0 + 3.06, -FRONT, -main, Houses.TAR)
	# The door (the row's, the number on its transom), the porch and its steps.
	var ds: float = (DOOR[0] + DOOR[1]) * 0.5
	Houses._door(g, ds, {"f0": f0, "trim": trim, "door": Color(0.62, 0.14, 0.14), "door_left": false, "no": NUMBER, "lit": "00001"})
	Houses._porch(g, W, ds, -1.0, {"trim": white, "porch_light": true})
	p.block(u0, d, u0 + W, d + pd)
	p.block(u0 + ds - 0.625, d + pd, u0 + ds + 0.625, d + pd + 0.9)
	# The parlour window: three lights, lace at either side, a red valance.
	var pw: Array = PARLOUR_WINDOW
	Houses.fb(g, pw[0] - 0.07, pw[1] + 0.07, f0 + 0.48, f0 + 2.37, 0.0, 0.04, trim)
	Houses.fb(g, pw[0] - 0.12, pw[1] + 0.12, f0 + 0.4, f0 + 0.5, 0.0, 0.15, trim)
	Kit.pane(Houses.fb(g, pw[0], pw[1], f0 + 0.55, f0 + 2.3, 0.04, 0.055, Kit.flat(GLOW, 1.0)))
	for seg: Array in [[1.04, 1.75], [3.65, 4.36]]:
		Houses.fb(g, seg[0], seg[1], f0 + 0.6, f0 + 2.18, 0.055, 0.062, lace)
	Houses.fb(g, pw[0], pw[1], f0 + 2.0, f0 + 2.27, 0.062, 0.068, Color(0.75, 0.25, 0.3))
	for x: float in [2.14, 3.26]:
		Houses.fb(g, x - 0.025, x + 0.025, f0 + 0.55, f0 + 2.3, 0.055, 0.075, trim)
	Houses.fb(g, pw[0], pw[1], f0 + 1.45, f0 + 1.49, 0.055, 0.075, trim)
	# The hall window, lit.
	Houses.sash(g, (HALL_WINDOW[0] + HALL_WINDOW[1]) * 0.5, f0 + 0.9, HALL_WINDOW[1] - HALL_WINDOW[0], 1.3, trim, GLOW, lace)
	# Upstairs: the bay on the porch roof, sashes over the door and the hall window, the cornice.
	var top := height - 0.855
	Houses.canted_bay(g, 2.7, "white", Houses.PROOF + 0.05, top, GLOW, lace)
	for s: float in [6.2, 7.85]:
		Houses.sash(g, s, top - 1.87, 0.95, 1.65, white, GLOW if s > 7.0 else null, lace, white)
	Houses.cornice(g, W, height, white, 1, brick, 2.7, 2.25)
	# Her end wall, on the passage: the bedroom's side window upstairs, the sun room's pair at the back.
	var end := Houses.sub_face(g, Vector2(0.0, -FRONT), Vector2(0.0, 0.0))     # s from her back wall (v = 0) to the front
	for w: Array in [[9.95, Houses.PROOF + 0.9, 1.1, 1.4], [0.875, f0 + 0.6, 1.05, 1.7], [2.125, f0 + 0.6, 1.05, 1.7]]:
		Houses.simple_window(end, w[0], w[1], w[2], w[3], white, GLOW, lace)
	# On the porch: the lantern and the mailbox by the door, the mat; her glider,
	# table, rockers and ferns (lifted onto the deck).
	Bea.lantern(g, Vector3(DOOR[0] - 0.36, f0 + 1.95, 0.0))
	Bea.mailbox(g, Vector3(DOOR[0] - 0.36, f0 + 1.3, 0.0))
	var mat := Kit.box(g, Vector3(0.9, 0.012, 0.5), Vector3(ds, f0 + 0.006, 0.35), Color(0.55, 0.42, 0.25))
	Props.words(g, "WELCOME", mat.position + Vector3(0, 0.008, 0), 0.1, Color(0.3, 0.2, 0.12)).rotation_degrees = Vector3(-90, 0, 0)
	var things: Array[Node3D] = []
	things.append(Bea.glider(p, st, u0 + 1.75, d + 0.47))
	var table := Props.table(p, st, u0 + 3.08, d + 0.4, 0.0, 0.48, 0.48, white, 0.62)
	Kit.cyl(table, 0.06, 0.2, Vector3(-0.08, 0.72, 0), Color(0.85, 0.92, 0.95, 0.6), Vector3.ZERO, 10)
	Kit.cyl(table, 0.05, 0.16, Vector3(-0.08, 0.7, 0), Color(0.6, 0.35, 0.15, 0.85), Vector3.ZERO, 10)
	for x: float in [0.1, 0.18]:
		Kit.cyl(table, 0.035, 0.12, Vector3(x, 0.68, 0.08 - x * 0.5), Color(0.85, 0.92, 0.95, 0.6), Vector3.ZERO, 8)
	things.append(table)
	things.append(Bea.rocker(p, st, u0 + 3.85, d + 0.72, 12.0))
	things.append(Bea.rocker(p, st, u0 + 4.8, d + 0.72, -12.0, white, Color(0.3, 0.5, 0.8)))
	var stand := Props.table(p, st, u0 + 8.42, d + 0.35, 0.0, 0.42, 0.42, white, 0.5)
	Bea.fern(stand, Vector3(0, 0.5, 0), 0.9)
	things.append(stand)
	for thing: Node3D in things:
		thing.position.y += f0
	for s: float in [2.3, 7.7]:
		Bea.hanging_fern(g, Vector3(s, Houses.CEIL - 0.02, pd - 0.3), 0.95)
	# The yard: grass, beds along the porch, stones to the steps, the pickets
	# along the pavement and down both sides, the gate folded back open.
	var grass := Kit.tex("stucco", 2.5, Color(0.35, 0.5, 0.25), true, Color(0.44, 0.74, 0.36))
	var yard: Rect2 = p.rect(u0, d + pd, u0 + W, pave)
	Kit.box(n, Vector3(yard.size.x, 0.29, yard.size.y), Vector3(yard.get_center().x, -0.145, yard.get_center().y), grass)
	Bea.flower_bed(p, st, u0 + (0.1 + ds - 0.8) * 0.5, d + pd + 0.3, ds - 0.9, 0.56, 1.0)
	Bea.flower_bed(p, st, u0 + (ds + 0.8 + W - 0.1) * 0.5, d + pd + 0.3, W - 0.9 - ds, 0.56, 7.0)
	var stone := Color(0.74, 0.73, 0.7)
	var v := d + pd + 0.95
	var k := 0
	while v < pave - 0.3:
		Kit.box(n, Vector3(0.85 + 0.12 * Props.rnd(k * 2.1), 0.01, 0.42), p.pt(u0 + ds + 0.06 * (Props.rnd(k * 3.7) - 0.5), v + 0.21, 0.005), stone.darkened(0.06 * (k % 2)))
		v += 0.5
		k += 1
	Bea.pickets(p, st, true, pave, u0, u0 + W, [[u0 + GATE[0], u0 + GATE[1]]], 0.78)
	Bea.pickets(p, st, false, u0 + 0.06, d + pd, pave - 0.06, [], 0.78, white, 1.0)
	Bea.pickets(p, st, false, u0 + W - 0.06, d + pd, pave - 0.06, [], 0.78, white, -1.0)
	var leaf := Kit.group(n, p.pt(u0 + GATE[0] - 0.02, pave - 0.12))
	for i in 8:
		Kit.box(leaf, Vector3(0.075, 0.68, 0.022), Vector3(-0.07 - i * 0.13, 0.37, 0), white.darkened(0.04))
	for y: float in [0.2, 0.55]:
		Kit.box(leaf, Vector3(1.08, 0.06, 0.03), Vector3(-0.52, y, -0.03), white.darkened(0.12))
	p.block(u0 + GATE[0] - 1.16, pave - 0.17, u0 + GATE[0], pave - 0.09)
	return {"door": u0 + ds, "steps": d + pd + 0.9}


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
	Props.boxes(p, b, 6.75, 2.5, 2)       # against the front wall, clear of both doors (between them they hemmed in whoever came in at the back)
	Bea.stripes(p, n, false, 5.0, 0.075, 2.925, 1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, [], 0.0)
	Bea.stripes(p, n, false, 9.0, 0.075, 2.925, -1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, [], 0.0)
	Bea.stripes(p, n, true, 0.0, 5.075, 8.925, 1.0, 0.0, 2.86, pantry_groove(), 0.12, 0.012, Bea.holes([PANTRY_WINDOW, {"a": 7.75, "b": 8.6, "head": 2.1}]), 0.0)
	# The back door, shut: a panel door with a window and a curtain.
	p.slab(n, true, 0.1, 7.7, 8.65, 0.0, 2.15, 0.04, Props.WOOD)
	p.slab(n, true, 0.12, 7.78, 8.57, 0.0, 2.08, 0.03, Color(0.88, 0.86, 0.78))
	p.slab(n, true, 0.14, 7.9, 8.45, 1.2, 1.9, 0.02, Color(0.2, 0.25, 0.35))
	p.slab(n, true, 0.155, 7.92, 8.43, 1.6, 1.88, 0.02, Color(0.95, 0.85, 0.55))
	Kit.ball(n, 0.035, p.pt(7.88, 0.19, 1.0), Bea.BRASS, 6)
	p.use_point(b, "BACK DOOR", 7.9, 0.55, "goto:backs", 1.0, 2.0)      # out into her yard in the backs (plans/backs.gd)


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
