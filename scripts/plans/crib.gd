extends RefCounted
## Tattletale's crib: a two-bay Baltimore rowhouse in the same brick row as the
## original game's houses. No hallway: you step off the pavement into the
## living room, and the rooms run front to back in one line.
##
## It is number 532 Rose Hill Terrace, the corner house at Old York Road. Its
## front door opens onto Rose Hill (plans/street.gd): E by the door inside
## takes him out of it there, and the travel list (OUTSIDE) puts him on Rose
## Hill at the door. The front is drawn there, by `front` below, with the door
## and the windows where these rooms have them. E at the back yard's gate goes
## out into the alley behind the row (plans/backs.gd). (Placeholders: the
## number, the gate's BACK GATE.)
##
##   ground floor:  living room | dining room (the stairs) | kitchen wing, side yard | back yard
##   upstairs:      his room | hall, bathroom | back bedroom
##
## The game floor is flat, so the stairs are a spot you use (E): the picture
## fades and he is on the other floor. Upstairs is its own stack of bands, drawn
## 40 m to the right on the plan (UP). The flight climbs from its foot in the
## dining room towards the back of the house, so upstairs it comes up at the
## back of the hall and the well drops away towards the street. A real house like this is about 4 m wide;
## this one is 5 m so there is room to walk round the furniture.
## Numbers are metres on the plan (see place.gd): u from the left party wall,
## v from the alley; the street is at v = 15.8.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Houses := preload("res://scripts/houses.gd")
const UP := 40.0
const STAIR_U := 0.6          # the middle of the flight, on both floors
const STAIR_V := 9.15
const STAIR_L := 2.2          # v 8.05 (the top) to 10.25 (the foot)
const OUTSIDE := "street"     # the place his front door opens onto (main.gd's _travel_to puts him there, at the door)
const NUMBER := "532"
const W := 5.0
const DOOR := [0.6, 1.5]      # the front door, from the left party wall: the living room's, and 532's on Rose Hill
const WINDOW := [2.6, 4.5]    # the barred front window beside it


static func build(p: Node3D) -> void:
	p.setup("TATTLETALE'S CRIB", 5.0, 15.8)
	var paper := Kit.tex("stucco", 2.0, Color(0.85, 0.8, 0.66), true, Color(1.0, 1.0, 0.82))       # yellowed wallpaper
	var blue := Kit.tex("stucco", 2.0, Color(0.6, 0.68, 0.8), true, Color(0.66, 0.84, 1.0))        # his room
	var tile := Kit.tex("block_plain", 0.6, Color(0.86, 0.88, 0.9), true, Color(0.9, 0.94, 0.97)) # the bathroom
	var boards := Kit.tex("in_boards", 1.3, Color(0.5, 0.36, 0.24), true, Color(0.74, 0.48, 0.3))  # stained oak boards
	var lino := Kit.tex("lino", 1.2, Color(0.7, 0.66, 0.56), true, Color(1.0, 0.9, 0.8))
	var check := Kit.tex("in_check", 0.5, Color(0.8, 0.8, 0.82), true, Color(0.97, 0.97, 1.0))     # small bathroom tiles
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2))
	var warm := Color(1.0, 0.86, 0.62)
	var white_door := Color(0.82, 0.8, 0.72)
	var trim := Color(0.7, 0.67, 0.58)             # door and window frames: a shade darker than the doors, so each door reads in its frame

	var g1: int = p.band()
	var g2: int = p.band()
	var g3: int = p.band()
	var g4: int = p.band()
	var h1: int = p.band(1)
	var h2: int = p.band(1)
	var h3: int = p.band(1)
	p.arrive = p.pt(1.05, 14.9)          # just inside the front door

	p.room("LIVING ROOM", g1, 0, 11.2, 5, 15.8, boards, {"light": warm, "energy": 0.6})
	p.room("DINING ROOM", g2, 0, 7.2, 5, 11.2, boards, {"light": warm})
	p.room("KITCHEN", g3, 0, 3.4, 3.6, 7.2, lino, {"light": Color(0.95, 1.0, 0.9)})
	# The back yard runs round the side of the kitchen wing.
	p.room("BACK YARD", g4, 0, 0, 5, 3.4, concrete, {"areas": [[0, 0, 5, 3.4], [3.6, 2.4, 5, 7.2]], "cam_y": 2.9, "look_y": 1.0})
	Kit.box(p.node_of(g4), Vector3(1.4, 0.3, 3.8), p.pt(4.3, 5.3, -0.15), concrete)
	p.room("HIS ROOM", h1, UP, 11.2, UP + 5, 15.8, boards, {"light": Color(0.9, 0.94, 1.0), "energy": 0.6})     # a cool light: his room is the blue one
	p.room("HALL", h2, UP, 7.2, UP + 2.5, 11.2, boards, {"light": warm, "energy": 0.4, "hole": [UP + STAIR_U - 0.475, STAIR_V - STAIR_L * 0.5, UP + STAIR_U + 0.475, STAIR_V + STAIR_L * 0.5]})
	p.room("BATHROOM", h2, UP + 2.5, 7.2, UP + 5, 11.2, check, {"light": Color(0.95, 1.0, 1.0), "energy": 0.4})
	p.room("BACK BEDROOM", h3, UP, 3.4, UP + 3.6, 7.2, boards, {"light": warm, "energy": 0.4})

	# ---- ground floor walls
	p.cross(g1, 15.8, 0, 5, brick, [
		{"a": DOOR[0], "b": DOOR[1], "head": 2.1, "colour": Color(0.5, 0.14, 0.12), "frame": trim},
		{"a": WINDOW[0], "b": WINDOW[1], "kind": "window", "sill": 0.8, "head": 2.2, "bars": true, "blinds": true, "frame": trim},
	], {"h": 6.6})
	# The front door's leaf is not drawn in here: its wall is always cut away (the
	# camera looks in through it), so the leaf was only ever a ghost, and that
	# stood over him as he came in. Rose Hill has the door (`front`); E in the
	# doorway takes him out of it there. (usables() leaves out a door marked "mate".)
	var front_door: Node3D = p.doors.back()
	front_door.set_meta("mate", true)
	for part: Node in front_door.leaf.get_children():
		part.free()
	p.use_point(g1, "FRONT DOOR", 1.05, 15.2, "goto:" + OUTSIDE, 1.0, 2.0)
	p.side(g1, 0.0, 11.2, 15.8, paper)
	p.side(g1, 5.0, 11.2, 15.8, paper)
	p.cross(g2, 11.2, 0, 5, paper, [{"a": 1.5, "b": 3.5, "kind": "arch", "frame": trim}])
	p.side(g2, 0.0, 7.2, 11.2, paper)
	p.side(g2, 5.0, 7.2, 11.2, paper)
	p.cross(g3, 7.2, 0, 5, paper, [{"a": 1.5, "b": 2.4, "kind": "arch", "head": 2.05, "frame": trim}])     # an open doorway, no door
	p.side(g3, 0.0, 3.4, 7.2, paper)
	p.side(g3, 3.6, 3.4, 7.2, paper, [{"a": 4.3, "b": 5.2, "kind": "window", "sill": 1.0, "head": 2.0, "frame": trim}])
	p.cross(g4, 3.4, 0, 3.6, paper, [{"a": 2.5, "b": 3.4, "colour": white_door, "frame": trim, "name": "BACK DOOR"}])
	# The yard: chain-link on three sides, a gate to the alley that stays shut.
	var wire := Color(0.5, 0.52, 0.52)
	p.rail(g4, false, 0.05, 0.05, 3.3, wire, 1.5)
	p.rail(g4, false, 4.95, 0.05, 7.1, wire, 1.5)
	p.rail(g4, true, 0.05, 0.1, 4.9, wire, 1.5)

	# ---- upstairs walls
	p.cross(h1, 15.8, UP, UP + 5, blue, [
		{"a": UP + 0.6, "b": UP + 2.0, "kind": "window", "sill": 0.8, "head": 2.1, "frame": trim},
		{"a": UP + 3.0, "b": UP + 4.4, "kind": "window", "sill": 0.8, "head": 2.1, "frame": trim},
	])
	p.side(h1, UP, 11.2, 15.8, blue)
	p.side(h1, UP + 5.0, 11.2, 15.8, blue)
	p.cross(h2, 11.2, UP, UP + 5, blue, [{"a": UP + 1.2, "b": UP + 2.1, "swing": 1, "colour": white_door, "frame": trim}])
	p.side(h2, UP, 7.2, 11.2, paper)
	p.side(h2, UP + 5.0, 7.2, 11.2, tile)
	p.side(h2, UP + 2.5, 7.2, 11.2, tile, [{"a": 9.6, "b": 10.5, "hinge": "a", "swing": 1, "colour": white_door, "frame": trim}])
	p.cross(h3, 7.2, UP, UP + 5, paper, [{"a": UP + 1.2, "b": UP + 2.1, "colour": white_door, "frame": trim}])
	p.cross(h3, 3.4, UP, UP + 3.6, paper, [{"a": UP + 1.0, "b": UP + 2.4, "kind": "window", "sill": 0.9, "head": 2.1, "frame": trim}], {"back": true})
	p.side(h3, UP, 3.4, 7.2, paper)
	p.side(h3, UP + 3.6, 3.4, 7.2, paper)

	_ground(p, g1, g2, g3, g4)
	_upstairs(p, h1, h2, h3)
	_dress(p, g1, g2, g3, h1, h2, h3)


## Paint on plaster in colour c.
static func _paint(c: Color) -> StandardMaterial3D:
	return Kit.tex("stucco", 2.0, c.darkened(0.14), true, c)


## The dining room's paper, rose stripes (the boxed-in cupboard under the
## landing is papered to match).
static func _rose() -> StandardMaterial3D:
	return Kit.tex("in_stripe", 1.0, Color(0.8, 0.52, 0.5), true, Color(0.97, 0.64, 0.62))


## His front as Rose Hill Terrace shows it (street.gd builds it there, on
## Rose Hill's place p, its left party wall at u0 on the row's front line d).
## The door and the barred window are where the living room has them (DOOR,
## WINDOW), the two sashes upstairs are his room's two windows, the number is
## on the transom; on the row's 0.7 m floor over a base course with a barred
## cellar window, the brick carried up to his green pressed-metal cornice,
## marble lintels and sills, marble steps. Behind, the main block (back to the
## dining room's wall) and the back building over the kitchen, lower, on the
## left party wall, with the kitchen's side window over the side yard. The
## steps take up floor. Returns {"door": u of the door's middle, "steps": v
## their foot reaches}.
static func front(p: Node3D, st: int, u0: float, d: float) -> Dictionary:
	var g: Node3D = Houses.face(p, st, u0, d)
	var f0 := Houses.F0
	var height := 6.6 + 0.4 + f0                        # (the front wall's 6.6 m and the brick over it, on the row's floor)
	var marble := Color(0.9, 0.9, 0.88)
	var cream := Color(0.82, 0.8, 0.72)
	var trim := Color(0.7, 0.67, 0.58)                  # the door's and the window's frames (build's trim)
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2))
	var main := 15.8 - 7.2                              # the living and dining rooms
	var wing := 7.2 - 3.4                               # the kitchen
	Houses.fb(g, 0.0, W, 0.0, height, -main, 0.0, brick)
	Houses.fb(g, 0.0, W, height, height + 0.04, -main, -0.36, Houses.SILVER)
	Houses.fb(g, 0.0, 3.6, 0.0, f0 + 5.8, -main - wing, -main, brick)
	Houses.fb(g, 0.0, 3.6, f0 + 5.8, f0 + 5.84, -main - wing, -main, Houses.SILVER)
	Houses.fb(g, 0.0, W, 0.0, f0 - 0.04, 0.0, 0.04, Houses.BASE)
	# The door in its frame under a dark transom with the number on it, a
	# marble lintel over; the knob away from the hinge (the hinge is on the
	# right, as the living room has it); a lamp by it, lit; the steps.
	var ds: float = (DOOR[0] + DOOR[1]) * 0.5
	var leaf := Color(0.5, 0.14, 0.12)
	Houses.fb(g, DOOR[0] - 0.055, DOOR[1] + 0.055, f0, f0 + 2.57, 0.0, 0.04, trim)
	Houses.fb(g, DOOR[0], DOOR[1], f0, f0 + 2.1, 0.04, 0.07, leaf)
	for y: float in [0.25, 1.2]:
		Houses.fb(g, DOOR[0] + 0.12, DOOR[1] - 0.12, f0 + y, f0 + y + 0.72, 0.07, 0.085, leaf.lightened(0.12))
	Houses.fb(g, DOOR[0] + 0.08, DOOR[0] + 0.16, f0 + 1.0, f0 + 1.08, 0.07, 0.11, Houses.GOLD)
	Kit.pane(Houses.fb(g, DOOR[0], DOOR[1], f0 + 2.155, f0 + 2.5, 0.04, 0.05, Color(0.16, 0.19, 0.28)))
	Props.words(g, NUMBER, Vector3(ds, f0 + 2.33, 0.06), 0.14, cream)
	Houses.fb(g, DOOR[0] - 0.14, DOOR[1] + 0.14, f0 + 2.57, f0 + 2.74, 0.0, 0.07, marble)
	Houses.fb(g, DOOR[1] + 0.26, DOOR[1] + 0.42, f0 + 2.0, f0 + 2.32, 0.0, 0.04, Houses.IRON)
	Kit.box(g, Vector3(0.14, 0.24, 0.14), Vector3(DOOR[1] + 0.34, f0 + 2.1, 0.12), Kit.flat(Color(1.0, 0.86, 0.55), 1.6))
	Kit.omni(g, Vector3(DOOR[1] + 0.34, f0 + 2.0, 0.8), Color(1.0, 0.84, 0.58), 2.0, 4.8)
	var reach := Houses.stoop(g, ds, f0, 0.65)
	p.block(u0 + ds - 0.65, d, u0 + ds + 0.65, d + reach)
	# The window: a blind half down behind bars, a marble lintel.
	var ws: float = (WINDOW[0] + WINDOW[1]) * 0.5
	var ww: float = WINDOW[1] - WINDOW[0]
	Houses.sash(g, ws, f0 + 0.8, ww, 1.4, trim, Houses.LIT, null, null, true)
	Houses.fb(g, WINDOW[0] - 0.15, WINDOW[1] + 0.15, f0 + 2.255, f0 + 2.43, 0.0, 0.07, marble)
	var bars := 10                    # (a bar every 19 cm: the glass's quarter points, where a shot is aimed, fall between them)
	for k in range(1, bars):
		Kit.cyl(g, 0.012, 1.38, Vector3(WINDOW[0] + ww * k / bars, f0 + 1.5, 0.12), Props.IRON, Vector3.ZERO, 5)
	for y: float in [0.86, 2.12]:
		Houses.fb(g, WINDOW[0] - 0.02, WINDOW[1] + 0.02, f0 + y, f0 + y + 0.04, 0.1, 0.14, Props.IRON)
	# The cellar window in the base course, marble round it, barred.
	Houses.fb(g, 2.75, 3.65, 0.1, 0.44, 0.04, 0.05, Houses.PANE)
	for x: float in [2.67, 3.65]:
		Houses.fb(g, x, x + 0.08, 0.02, 0.52, 0.0, 0.06, marble)
	for y: float in [0.02, 0.44]:
		Houses.fb(g, 2.75, 3.65, y, y + 0.08, 0.0, 0.06, marble)
	for k in 5:
		Kit.cyl(g, 0.011, 0.34, Vector3(2.9 + k * 0.15, 0.27, 0.07), Props.IRON, Vector3.ZERO, 5)
	# Upstairs: a blind half down in one sash, red curtains in the other; the cornice.
	for s: float in [1.3, 3.7]:
		var blind := Props.rnd(s + s * 1.7) > 0.5
		Houses.sash(g, s, f0 + 3.75, 1.1, 1.5, cream, Houses.LIT, null if blind else Color(0.86, 0.3, 0.28), marble, blind)
	Houses.cornice(g, W, height, Houses.GREEN, 1)
	# The kitchen's window, its red curtains, over the side yard.
	var side := Houses.sub_face(g, Vector2(3.6, -main), Vector2(3.6, -main - wing))
	Houses.simple_window(side, 2.45, f0 + 1.0, 0.9, 1.0, trim, Houses.LIT, Color(0.9, 0.26, 0.22))
	return {"door": u0 + ds, "steps": d + reach}


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
	Props.stairs(p, g2, STAIR_U, STAIR_V, 0.0, 0.95, STAIR_L)
	p.portal(g2, "GO UPSTAIRS", STAIR_U, 10.62, UP + STAIR_U + 0.25, 7.66)
	# Behind the top of the flight, under the landing: a cupboard, boxed in.
	var cupboard: Node3D = p.prop(g2, STAIR_U, 7.665, 0.0, 0.95, 0.77)
	Kit.block(cupboard, Vector3(0.95, 2.89, 0.77), Vector3.ZERO, _rose())
	Kit.box(cupboard, Vector3(0.03, 1.7, 0.56), Vector3(0.485, 0.86, 0.0), Color(0.82, 0.8, 0.72))
	Kit.ball(cupboard, 0.03, Vector3(0.51, 0.9, 0.2), Color(0.85, 0.68, 0.25))
	Props.table(p, g2, 3.45, 9.1, 0.0, 1.5, 0.9, Props.WOOD_DARK)
	Props.chair(p, g2, 3.45, 8.3, 0.0, Props.WOOD)
	Props.chair(p, g2, 3.45, 9.9, 180.0, Props.WOOD)
	Props.cabinet(p, g2, 4.69, 8.2, 270.0, 1.6)
	Props.poster(p, g2, 2.9, 7.28, 0.0, 0.7, 0.5, Color(0.6, 0.5, 0.3), "", 1.8)
	# Kitchen: stove, sink and fridge down one wall, a small table.
	Props.stove(p, g3, 0.43, 3.95, 90.0)
	Props.sink_unit(p, g3, 0.41, 5.25, 90.0, 1.6)
	Props.fridge(p, g3, 0.46, 6.62, 90.0)
	Props.table(p, g3, 2.85, 5.6, 0.0, 0.8, 1.0, Color(0.8, 0.78, 0.7))
	Props.chair(p, g3, 2.85, 4.8, 0.0, Props.VINYL)
	Props.chair(p, g3, 2.85, 6.4, 180.0, Props.VINYL)
	Props.poster(p, g3, 1.7, 3.48, 0.0, 0.45, 0.6, Color(0.85, 0.82, 0.7), "", 1.7)
	# The yard: dustbins, and the gate to the alley (E there: out into the backs, plans/backs.gd).
	Props.cans(p, g4, 4.3, 0.55, 2)
	Props.bench(p, g4, 0.45, 1.6, 90.0, 1.4, Color(0.4, 0.3, 0.2))
	var n: Node3D = p.node_of(g4)
	p.slab(n, true, 0.05, 1.9, 2.9, 0.0, 1.7, 0.07, Color(0.36, 0.38, 0.4))
	p.use_point(g4, "BACK GATE", 2.4, 0.6, "goto:backs", 1.0, 1.9)
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
	p.use_point(h1, "SLEEP", UP + 2.95, 12.4, "sleep")          # the day ends here: the next one begins (main.gd's _use_point)
	var chest := Props.dresser(p, h1, UP + 0.36, 14.0, 90.0, 1.6)
	Props.boombox(chest, Vector3(0, 0.9, 0))
	p.use_point(h1, "STASH", UP + 1.1, 14.0, "stash")          # his weapons kept in the dresser (combat_foes.gd), so he can go to court without them
	Props.desk(p, h1, UP + 3.5, 15.32, 180.0, Props.WOOD, 2, true, 1.6)
	Props.rug(p, h1, UP + 2.2, 13.6, 2.0, 1.6, Color(0.2, 0.25, 0.4))
	Props.poster(p, h1, UP + 0.08, 12.2, 90.0, 0.7, 0.95, Color(0.15, 0.3, 0.7), "TATTLETALE")
	Props.poster(p, h1, UP + 2.9, 11.28, 0.0, 0.6, 0.8, Color(0.75, 0.2, 0.2), "JUST SAY NO")
	Props.poster(p, h1, UP + 4.92, 14.4, 270.0, 0.55, 0.4, Color(0.7, 0.58, 0.25), "CITIZEN OF THE MONTH", 1.7)
	Props.poster(p, h1, UP + 4.92, 15.1, 270.0, 0.55, 0.4, Color(0.7, 0.58, 0.25), "BLOCK WATCH", 1.7)
	# The hall and the bathroom.
	Props.stairwell(p, h2, UP + STAIR_U, STAIR_V, 0.0, 0.95, STAIR_L)
	p.portal(h2, "GO DOWNSTAIRS", UP + STAIR_U + 0.1, 7.75, STAIR_U + 0.1, 10.68)
	Props.tub(p, h2, UP + 4.55, 8.32)
	Props.toilet(p, h2, UP + 4.58, 10.2, 270.0)
	Props.basin(p, h2, UP + 3.3, 7.52)
	Props.rug(p, h2, UP + 3.6, 9.3, 1.0, 0.7, Color(0.6, 0.75, 0.8))
	# The back bedroom.
	Props.bed(p, h3, UP + 0.96, 4.52, 0.0, 1.5, 2.0, Color(0.7, 0.55, 0.6))
	Props.dresser(p, h3, UP + 2.9, 3.76, 0.0, 1.2, Props.WOOD_DARK)
	Props.chair(p, h3, UP + 3.2, 6.3, 270.0, Props.WOOD)
	Props.poster(p, h3, UP + 0.08, 6.0, 90.0, 0.5, 0.65, Color(0.75, 0.7, 0.55), "", 1.7)


## The rooms' walls: paper, paint, panelling and tiles on the back and side
## walls with their mouldings and door trim; the lamps, the pictures, and what
## changes on the floors. (The front walls are the ones cut away to look in.)
static func _dress(p: Node3D, g1: int, g2: int, g3: int, h1: int, h2: int, h3: int) -> void:
	var white := Color(0.95, 0.93, 0.86)
	var walnut := Color(0.36, 0.22, 0.13)
	var gilt := Color(0.8, 0.64, 0.3)
	# The living room: gold flowered paper up to a picture rail, a cream frieze
	# over it, a walnut skirting; a lamp each side of the arch and a picture
	# beyond each, a mat inside the door, a sill of walnut under the arch.
	var living := {"upper": Kit.tex("in_flower", 0.8, Color(0.86, 0.7, 0.44), true, Color(1.0, 0.82, 0.5)),
		"rail": walnut, "rail_y": 2.2, "frieze": _paint(Color(0.98, 0.93, 0.8)), "skirt": walnut, "skirt_h": 0.18,
		"cornice": Color(0.97, 0.94, 0.84), "surround": white}
	In.room_walls(p, g1, 0, 11.2, 5, 15.8, living, [{"a": 1.5, "b": 3.5, "kind": "arch"}])
	for u: float in [1.18, 3.82]:
		In.sconce(p, g1, u, 11.285, 0.0, "shade", 1.95)
	In.picture(p, g1, 0.64, 11.285, 0.0, 0.62, 0.5, "sea", gilt, 1.6)
	In.picture(p, g1, 4.36, 11.285, 0.0, 0.62, 0.5, "flowers", gilt, 1.6)
	In.mat(p, g1, 1.05, 15.38, 0.95, 0.55, Color(0.66, 0.5, 0.28), Color(0.36, 0.24, 0.14))
	Kit.box(p.node_of(g2), Vector3(2.0, 0.012, 0.19), p.pt(2.5, 11.2, 0.006), walnut)
	# The dining room: white panelling to a dado rail, rose stripes over it; the
	# stair wall in the paper alone. Both start at the boxed-in cupboard. A lamp
	# over the table and a rug under it, a landscape on the back wall.
	var rose := _rose()
	var dining := {"lower": Kit.tex("in_panel", 0.8, Color(0.85, 0.82, 0.74), true, Color(0.98, 0.95, 0.87)),
		"upper": rose, "dado": white, "dado_y": 0.95, "skirt": white, "cornice": white, "surround": white}
	In.dress(p, g2, true, 7.2, 1.0, STAIR_U + 0.475, 4.925, [{"a": 1.5, "b": 2.4, "kind": "arch", "head": 2.05}], dining)
	In.dress(p, g2, false, 5.0, -1.0, 7.275, 11.125, [], dining)
	In.dress(p, g2, false, 0.0, 1.0, STAIR_V - STAIR_L * 0.5, 11.125, [], {"upper": rose, "skirt": white, "cornice": white})
	In.pendant(p, g2, 3.45, 9.1, 1.85, Color(0.97, 0.9, 0.72), "drum", In.WARM, 0.5)
	Props.rug(p, g2, 3.45, 9.1, 1.9, 2.3, Color(0.24, 0.32, 0.55))
	In.picture(p, g2, 4.05, 7.285, 0.0, 0.6, 0.48, "hills", gilt, 1.6)
	# The kitchen: white tiles to a red cap, sunny yellow paint over them, a black
	# cove at the floor; a red enamel lamp over the table, curtains at the window,
	# a steel strip where the boards meet the lino.
	var kitchen := {"lower": Kit.tex("in_tile", 0.6, Color(0.9, 0.9, 0.88), true, Color(0.99, 0.98, 0.95)),
		"upper": _paint(Color(1.0, 0.95, 0.5)), "dado": Color(0.82, 0.16, 0.14), "dado_y": 1.3,
		"skirt": Color(0.16, 0.16, 0.18), "skirt_h": 0.1, "cornice": white}
	In.room_walls(p, g3, 0, 3.4, 3.6, 7.2, kitchen, [{"a": 2.5, "b": 3.4}], [], [{"a": 4.3, "b": 5.2, "kind": "window", "sill": 1.0, "head": 2.0}])
	In.curtains(p, g3, false, 3.6, -1.0, 4.3, 5.2, 1.0, 2.0, Color(0.9, 0.26, 0.22))
	In.pendant(p, g3, 2.85, 5.6, 1.75, Color(0.86, 0.2, 0.16), "cone", In.WARM, 0.5)
	Kit.box(p.node_of(g3), Vector3(0.9, 0.01, 0.19), p.pt(1.95, 7.2, 0.005), Props.STEEL)
	# His room: royal blue to a white dado rail, sky blue over it; a ceiling lamp.
	var his := {"lower": _paint(Color(0.22, 0.38, 0.74)), "upper": _paint(Color(0.6, 0.82, 1.0)), "dado": white,
		"skirt": white, "cornice": white, "surround": white}
	In.room_walls(p, h1, UP, 11.2, UP + 5, 15.8, his, [{"a": UP + 1.2, "b": UP + 2.1}])
	In.pendant(p, h1, UP + 2.5, 12.3, 2.42, Color(0.98, 0.95, 0.85), "drum", In.WARM)
	# The hall: white panelling to a dado rail, green trellis paper over it; a
	# lamp by the bedroom door, a portrait over the stairs, a runner.
	var hall := {"lower": Kit.tex("in_panel", 0.8, Color(0.85, 0.82, 0.74), true, Color(0.98, 0.95, 0.87)),
		"upper": Kit.tex("in_trellis", 0.9, Color(0.6, 0.72, 0.56), true, Color(0.74, 0.88, 0.68)),
		"dado": white, "dado_y": 0.95, "skirt": white, "cornice": white, "surround": white}
	In.room_walls(p, h2, UP, 7.2, UP + 2.5, 11.2, hall, [{"a": UP + 1.2, "b": UP + 2.1}], [], [{"a": 9.6, "b": 10.5}])
	In.sconce(p, h2, UP + 0.62, 7.285, 0.0, "shade", 1.95)
	In.picture(p, h2, UP + 0.085, 9.4, 90.0, 0.5, 0.62, "face", gilt, 1.75)
	In.mat(p, h2, UP + 1.78, 9.3, 0.62, 3.3, Kit.tex("in_carpet", 0.8, Color(0.5, 0.14, 0.12), true, Color(0.72, 0.2, 0.18)), gilt)
	# The bathroom: pink tiles to a black cap, pale pink paint over them, a black
	# cove at the floor, a light over the mirror.
	var black := Color(0.13, 0.13, 0.15)
	var bath := {"lower": Kit.tex("in_tile", 0.6, Color(0.9, 0.7, 0.74), true, Color(1.0, 0.74, 0.8)),
		"upper": _paint(Color(1.0, 0.9, 0.92)), "dado": black, "dado_y": 1.4, "skirt": black, "skirt_h": 0.1,
		"cornice": white, "surround": white}
	In.room_walls(p, h2, UP + 2.5, 7.2, UP + 5, 11.2, bath, [], [{"a": 9.6, "b": 10.5}], [])
	In.wall_strip(p, h2, UP + 3.3, 7.285, 0.0, 0.56, 2.02)
	# The back bedroom: lilac flowered paper to a picture rail, white over it;
	# curtains at the window (short of the headboard), the backs of the next row
	# across the alley through it, a lamp each side, a mat by the bed.
	var lilac := {"upper": Kit.tex("in_flower", 0.7, Color(0.72, 0.62, 0.8), true, Color(0.88, 0.78, 0.98)),
		"rail": white, "rail_y": 2.2, "frieze": _paint(Color(0.98, 0.96, 0.94)), "skirt": white, "cornice": white}
	In.room_walls(p, h3, UP, 3.4, UP + 3.6, 7.2, lilac, [{"a": UP + 1.0, "b": UP + 2.4, "kind": "window", "sill": 0.9, "head": 2.1}])
	In.curtains(p, h3, true, 3.4, 1.0, UP + 1.0, UP + 2.4, 1.2, 2.1, Color(0.92, 0.52, 0.64))
	In.night_view(p, h3, true, 3.4, -1.0, UP + 1.0, UP + 2.4, 0.9, 2.1, "brick")
	for u: float in [UP + 0.34, UP + 3.12]:
		In.sconce(p, h3, u, 3.485, 0.0, "shade", 1.75)
	In.picture(p, h3, UP + 0.085, 4.6, 90.0, 0.55, 0.45, "flowers", Color(0.92, 0.9, 0.86), 1.62)
	In.mat(p, h3, UP + 2.05, 4.9, 0.62, 1.1, Color(0.96, 0.86, 0.9), Color(0.78, 0.5, 0.62))
