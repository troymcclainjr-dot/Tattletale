extends RefCounted
## Large Fry's place: the ground-floor flat of a three-storey apartment block,
## Argonne Court. Nothing like the crib: that is a narrow house, one room behind
## another on two floors; this is one wide floor, the rooms side by side, reached
## through the block's shared entry hall. 11 x 9.6 m inside, two bands from the
## street back:
##
##   living room | entry hall (the lift is out of order)
##   kitchen | bathroom | bedroom
##
## He is at home, wandering the living room, and will talk.
## The money is on show: a projection television and a wall of gold records,
## a leather couch, a fish tank, a keyboard under the window.
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 9.6.
##
## The rest of the block: beside the entry hall, through an arch, the stair hall
## (APT 2's door, the stairs); upstairs the 2nd floor's hall (APT 3, APT 4, the
## lift's other door, the stairwell and the flight on up), drawn UP to the
## right on the plan; the roof, drawn ROOF to the right: tar, a parapet, the
## stair's bulkhead, the water tank, a pigeon loft, aerials, and the city all
## round. A fire escape down the block's side into the vacant lot beside it;
## the street runs east past two more houses to the park's corner (TO THE PARK).

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Houses := preload("res://scripts/houses.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Park := preload("res://scripts/props_park.gd")
const Fry := preload("res://scripts/props_fry.gd")
const F := 9.675          # the street face of the front wall
const BLOCK := 14.0       # the block's front, with the stair hall (u 11 .. 14) beside the entry hall
const UP := 40.0          # the 2nd floor's hall is drawn this far to the right on the plan (level 1)
const ROOF := 80.0        # and the roof this far (level 2)
const STAIR_V := 7.35     # the flights' middle: v 6.15 .. 8.55, the foot at the street end
const STAIR_L := 2.4
const FLIGHT_U := 13.4    # the flight up from the ground floor, and its well on the 2nd floor (5 cm off the wall)
const ON_U := 12.35       # the flight on up from the 2nd floor
const LOT := [14.0, 19.0]     # the vacant lot beside the block
const LOT_BACK := 3.4         # its back fence
const GAP := [15.3, 16.5]     # the gap in its fence on the street
const EAST := 30.0            # the street's east end: the park's corner
const FLOORS := [3.0, 5.85]   # the fire escape's landings, the 2nd and 3rd floors
const DROP_S := 1.75          # along the side wall from its front corner: the drop ladder
const NECK_S := 4.05          # and the gooseneck ladder up over the parapet
const ROOF_Y := 8.88          # the roof over the street; its parapet's top:
const PARAPET := 9.68


static func build(p: Node3D) -> void:
	p.setup("LARGE FRY'S PLACE", 11.0, 9.6)
	var plum := Kit.tex("stucco", 2.0, Color(0.5, 0.36, 0.5), true, Color(0.78, 0.6, 0.8))            # the living room
	var gold := Kit.tex("stucco", 2.0, Color(0.8, 0.68, 0.4), true, Color(1.0, 0.86, 0.55))           # the bedroom
	var hall_look := Kit.tex("block_plain", 1.2, Color(0.78, 0.76, 0.72), true, Color(0.82, 0.8, 0.76))
	var tile := Kit.tex("block_plain", 0.6, Color(0.88, 0.86, 0.92), true, Color(0.95, 0.92, 1.0))
	var kitchen_look := Kit.tex("stucco", 2.0, Color(0.85, 0.8, 0.6), true, Color(1.0, 0.95, 0.72))
	var shag := Kit.tex("carpet", 2.0, Color(0.5, 0.2, 0.2), true, Color(1.0, 0.55, 0.5))
	var bed_carpet := Kit.tex("carpet", 2.0, Color(0.3, 0.25, 0.4), true, Color(0.7, 0.6, 0.95))
	var lino := Kit.tex("lino", 1.2, Color(0.7, 0.66, 0.56), true, Color(0.96, 0.93, 0.86))
	var bath_floor := Kit.tex("in_tile", 0.32, Color(0.88, 0.88, 0.9), true, Color(0.99, 0.99, 1.0))     # little white floor tiles
	var hall_floor := Kit.tex("in_terrazzo", 1.4, Color(0.74, 0.72, 0.66), true, Color(0.9, 0.87, 0.8))  # the block's terrazzo
	var warm := Color(1.0, 0.82, 0.6)
	var trim := Color(0.3, 0.22, 0.2)
	var door_red := Color(0.5, 0.14, 0.12)
	var white_door := Color(0.82, 0.8, 0.72)
	var brick_look := Houses.wall("brick")

	var st: int = p.street(-4.0, EAST)
	var b1: int = p.band()
	var b2: int = p.band()
	var h1: int = p.band(1)
	var top: int = p.band(2)
	p.arrive = p.pt(9.65, 10.8)

	p.room("LIVING ROOM", b1, 0, 5, 8.4, 9.6, shag, {"light": warm, "energy": 0.65})
	p.room("ENTRY HALL", b1, 8.4, 5, 11, 9.6, hall_floor, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("STAIR HALL", b1, 11, 5, BLOCK, 9.6, hall_floor, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("KITCHEN", b2, 0, 0, 3.8, 5, lino, {"light": Color(0.95, 1.0, 0.9), "energy": 0.45})
	p.room("BATHROOM", b2, 3.8, 0, 6.2, 5, bath_floor, {"light": Color(0.95, 1.0, 1.0), "energy": 0.4})
	p.room("BEDROOM", b2, 6.2, 0, 11, 5, bed_carpet, {"light": warm, "energy": 0.5})
	p.room("VACANT LOT", st, LOT[0], LOT_BACK, LOT[1], 9.6, Outdoor.tex("out_dirt", 2.6, Color(0.42, 0.36, 0.28), Color(0.86, 0.78, 0.66)), {"street": true})
	p.room("2ND FLOOR", h1, UP + 8.4, 5, UP + BLOCK, 9.6, hall_floor, {"light": Color(0.96, 0.98, 0.95), "energy": 0.45,
		"hole": [UP + FLIGHT_U - 0.475, STAIR_V - STAIR_L * 0.5, UP + FLIGHT_U + 0.475, STAIR_V + STAIR_L * 0.5]})
	p.room("ROOF", top, ROOF, 0, ROOF + BLOCK, 9.6, Kit.tex("asphalt", 3.0, Fry.TAR, true, Color(0.62, 0.62, 0.66)), {"street": true})

	var front: Node3D = p.cross(b1, 9.6, 0, BLOCK, Houses.wall("brick"), [
		{"a": 1.0, "b": 3.4, "kind": "window", "sill": 0.8, "head": 2.1, "blinds": true, "frame": trim},
		{"a": 4.6, "b": 7.4, "kind": "window", "sill": 0.8, "head": 2.1, "blinds": true, "frame": trim},
		{"a": 9.2, "b": 10.1, "head": 2.1, "colour": Color(0.2, 0.26, 0.24), "frame": trim},
		{"a": 11.55, "b": 12.55, "kind": "window", "sill": 0.8, "head": 2.1, "frame": trim},
	], {"h": 9.0})
	p.side(b1, 0.0, 5, 9.6, plum)
	p.side(b1, 11.0, 5, 9.6, hall_look, [{"a": 6.0, "b": 7.2, "kind": "arch", "head": 2.3, "frame": trim}])      # the arch to the stair hall
	p.side(b1, BLOCK, 5, 9.6, hall_look)
	p.cross(b1, 5.0, 11.0, BLOCK, hall_look, [{"a": 11.3, "b": 12.2, "colour": Color(0.36, 0.26, 0.2), "frame": trim}], {"back": true})
	_shut(p)                   # APT 2's door: not his to open
	p.side(b1, 8.4, 5, 9.6, plum, [{"a": 7.5, "b": 8.4, "hinge": "a", "swing": -1, "colour": door_red, "frame": trim}])
	p.cross(b2, 5.0, 0, 11, plum, [
		{"a": 1.6, "b": 2.6, "kind": "arch", "head": 2.1, "frame": trim},
		{"a": 4.5, "b": 5.4, "colour": white_door, "frame": trim},
		{"a": 6.9, "b": 7.8, "colour": white_door, "frame": trim},
	])
	p.side(b2, 0.0, 0, 5, kitchen_look)
	p.side(b2, 3.8, 0, 5, tile)
	p.side(b2, 6.2, 0, 5, gold)
	p.side(b2, 11.0, 0, 5, gold)
	p.cross(b2, 0.0, 0, 11, gold, [{"a": 0.7, "b": 1.9, "kind": "window", "sill": 1.15, "head": 2.0, "frame": trim}], {"back": true})
	# The 2nd floor's hall, over the entry and stair halls: APT 3 over his door,
	# APT 4 and the lift's other door at the back, a window over the well onto
	# the fire escape.
	var apt := Color(0.36, 0.26, 0.2)
	p.cross(h1, 9.6, UP + 8.4, UP + BLOCK, Houses.wall("brick"), [
		{"a": UP + 9.05, "b": UP + 10.25, "kind": "window", "sill": 0.6, "head": 2.05, "frame": trim},
		{"a": UP + 11.9, "b": UP + 13.1, "kind": "window", "sill": 0.6, "head": 2.05, "frame": trim},
	])
	p.side(h1, UP + 8.4, 5, 9.6, hall_look, [{"a": 7.5, "b": 8.4, "hinge": "a", "swing": -1, "colour": apt, "frame": trim}])
	_shut(p)                   # APT 3
	p.side(h1, UP + BLOCK, 5, 9.6, hall_look, [{"a": 6.575, "b": 7.575, "kind": "window", "sill": 0.6, "head": 2.0, "frame": trim}])
	p.cross(h1, 5.0, UP + 8.4, UP + BLOCK, hall_look, [{"a": UP + 10.65, "b": UP + 11.55, "colour": apt, "frame": trim}], {"back": true})
	_shut(p)                   # APT 4
	# The roof's parapet all round, never cut away: he looks out over it.
	for v: float in [0.0, 9.6]:
		p.cross(top, v, ROOF, ROOF + BLOCK, brick_look, [], {"back": true, "h": PARAPET - ROOF_Y - 0.08})
	for u: float in [ROOF, ROOF + BLOCK]:
		p.side(top, u, 0, 9.6, brick_look, [], {"h": PARAPET - ROOF_Y - 0.08})

	_street(p, st, front)
	_lot(p, st)
	_east(p, st)
	_front_rooms(p, b1)
	_stair_hall(p, b1)
	_back_rooms(p, b2)
	_upstairs(p, h1)
	_roof(p, top)
	_dress(p, b1, b2, h1)


## The last door made is a neighbour's: drawn, shut, not his to open
## (usables() leaves out a door marked "mate").
static func _shut(p: Node3D) -> void:
	(p.doors.back() as Node3D).set_meta("mate", true)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var stone := Color(0.78, 0.74, 0.64)
	var trim := Color(0.3, 0.22, 0.2)
	var brick := Houses.wall("brick")
	# The block's own front, a brick walk-up as the old Pen Lucy's apartment
	# blocks are: a grey base course, stone sills and lintels on the ground
	# floor, a stone band over it with the name; two more floors of sash windows
	# in pairs under formstone lintels (an air conditioner in one, a window box
	# under another); along the top a corbelled brick cornice under a metal
	# flashing, the flat roof behind it, and dark rain leaders down the corners.
	# Over the door a broad rain hood on slim braces, a lit transom, the lantern
	# hanging under the hood, the buzzers beside the door; a patch of concrete
	# where the brick was mended. Its sides stand bare over the low houses either
	# side.
	var g := Kit.group(front, p.pt(0.0, F))
	_proud(p, front, 0.0, 9.05, 0.0, 0.5, 0.04, Houses.BASE)
	_proud(p, front, 10.25, BLOCK - 0.01, 0.0, 0.5, 0.04, Houses.BASE)        # stopping short of the wall's end, which shares no face with them
	for w: Array in [[1.0, 3.4], [4.6, 7.4], [11.55, 12.55]]:
		Houses.fb(g, w[0] - 0.12, w[1] + 0.12, 2.17, 2.38, 0.0, 0.08, Houses.STONE)
		Houses.fb(g, w[0] - 0.1, w[1] + 0.1, 0.62, 0.735, 0.0, 0.14, Houses.STONE)
	Houses.fb(g, 7.75, 8.55, 0.5, 1.3, 0.0, 0.012, Houses.CONCRETE)
	var curtains := [Color(0.85, 0.3, 0.3), Color(0.95, 0.93, 0.86), Color(0.4, 0.65, 0.4), Color(0.9, 0.8, 0.5)]
	for row in 2:
		var y: float = 3.6 + row * 2.85
		for k in 4:
			var c: float = [2.2, 6.0, 9.65, 12.5][k]          # 12.5: the stair hall's
			var lit: Variant = Houses.LIT if Props.rnd(c + row * 3.1) > 0.5 else null          # the same windows lit as before
			if c > 9.0:
				Houses.sash(g, c, y, 1.2, 1.45, trim, lit, curtains[k], Houses.STONE)
				if row == 0 and k == 2:          # a window box
					Houses.fb(g, c - 0.6, c + 0.6, y - 0.42, y - 0.16, 0.03, 0.3, Houses.BROWN)
					for i in 6:
						Kit.ball(g, 0.075, Vector3(c - 0.5 + i * 0.2, y - 0.12, 0.19), [Color(0.85, 0.2, 0.25), Color(0.95, 0.8, 0.3), Color(0.3, 0.55, 0.3)][i % 3], 6)
				continue
			for side: float in [-1.0, 1.0]:
				Houses.sash(g, c + side * 0.6, y, 0.9, 1.45, trim, lit, curtains[k], null, row == 1 and k == 1)
			Houses.fb(g, c - 1.15, c + 1.15, y + 1.49, y + 1.69, 0.0, 0.08, Houses.STONE)     # one lintel over the pair
			if row == 1 and k == 0:          # an air conditioner in the lower sash
				var s := c + 0.6
				Houses.fb(g, s - 0.31, s + 0.31, y + 0.08, y + 0.5, -0.05, 0.42, Color(0.86, 0.85, 0.8))
				for i in 4:
					Houses.fb(g, s - 0.25, s + 0.25, y + 0.14 + i * 0.09, y + 0.17 + i * 0.09, 0.42, 0.44, Houses.SHUTTER)
	Houses.cornice(g, BLOCK, 9.0, stone, 4, brick)
	Houses.fb(g, -0.08, BLOCK, 8.84, 8.88, -9.75, -0.25, Houses.TAR)          # the flat roof
	# The sides: the left bare over the neighbours (whose houses run 3 m back);
	# the right over the lot, its parapet capped, windows on the upper floors,
	# the fire escape down it.
	Houses.fb(g, -0.1, -0.08, 0.0, 8.9, -9.75, -3.08, brick)
	Houses.fb(g, -0.1, 0.0, 7.0, 8.9, -3.08, 0.0, brick)
	_east_side(g, brick, trim)
	for s: float in [0.14, BLOCK - 0.14]:          # the rain leaders, a head and straps on each
		Houses.pipe(g, Vector3(s, 0.02, 0.1), Vector3(s, 8.0, 0.1), 0.05, Houses.BARS)
		Houses.fb(g, s - 0.1, s + 0.1, 8.0, 8.22, 0.0, 0.2, Houses.BARS)
		for y: float in [1.6, 3.7, 5.8]:
			Houses.fb(g, s - 0.07, s + 0.07, y, y + 0.05, 0.0, 0.16, Houses.BARS)
	p.slab(front, true, 9.66, -0.02, BLOCK + 0.02, 2.95, 3.15, 0.1, stone)
	Props.words(front, "ARGONNE COURT", p.pt(9.65, 9.715, 3.05), 0.15, Color(0.3, 0.22, 0.2))
	# The door: a lit transom over it, a broad rain hood on two slim braces.
	Houses.fb(g, 9.145, 10.155, 2.17, 2.5, 0.0, 0.04, trim)
	Houses.fb(g, 9.23, 10.07, 2.22, 2.44, 0.04, 0.05, Kit.flat(Houses.LIT, 1.1))
	Houses.fb(g, 8.7, 10.6, 2.6, 2.68, -0.01, 0.9, Houses.SHUTTER)
	Houses.fb(g, 8.7, 10.6, 2.52, 2.6, 0.86, 0.9, Houses.SHUTTER)
	for s: float in [8.8, 10.5]:
		Houses.pipe(g, Vector3(s, 1.95, 0.02), Vector3(s, 2.6, 0.8), 0.02, Houses.BARS, 4)
	In.lantern(front, p.pt(9.65, 10.05, 2.52), 0.4)
	p.slab(front, true, 9.69, 8.72, 8.98, 1.2, 1.6, 0.02, Props.STEEL)
	for k in 4:
		p.slab(front, true, 9.702, 8.76, 8.94, 1.24 + k * 0.09, 1.29 + k * 0.09, 0.008, Props.DARK)
	Kit.block(n, Vector3(1.3, 0.07, 0.5), p.pt(9.65, 9.9), Color(0.8, 0.8, 0.78))
	# Either side: the end of a brick row on the left; on the right, past the
	# lot, two more of the same (their bodies drawn on back, as the lot shows them).
	Props.rowhouse(p, n, -5.0, 9.6, Houses.wall("brick_2"), false, true)
	Props.rowhouse(p, n, -10.0, 9.6, Houses.wall("painted"))
	Props.rowhouse(p, n, LOT[1], 9.6, Houses.wall("formstone"), true)
	Props.rowhouse(p, n, LOT[1] + 5.0, 9.6, Houses.wall("brick_dark"), false, true)
	for k in 2:
		var body := Kit.group(n, p.pt(LOT[1] + 5.0 * k, 9.675))
		Houses.fb(body, 0.0, 5.0, 0.0, 6.9, -9.0, -3.0, Houses.wall(["formstone", "brick_dark"][k]))
	var lot_side := Houses.sub_face(Kit.group(n, p.pt(LOT[1], 9.675)), Vector2(0.0, -9.0), Vector2(0.0, 0.0))
	Fry.ghost(lot_side, 9.0, 6.9)              # where the house in the lot stood against it
	var row_end := Kit.group(n, p.pt(LOT[1] + 5.0, 9.675))
	Houses.end_windows(row_end, 5.0, 9.0, 1, 0.36, 6.9, Color(0.92, 0.9, 0.84), 3.3)
	Props.street_lamp(p, st, 5.4, 11.65)
	Props.cans(p, st, 11.6, 9.95, 3)
	Props.hydrant(p, st, 12.6, 11.6)
	Props.bench(p, st, 3.0, 10.02, 0.0, 1.8, Props.IRON, true)


## The block's right-hand side, over the lot, on the front's face g: the wall
## up to its parapet's coping; sashes on the upper floors (the 2nd floor hall's
## over its stairwell, the flats' further back), APT 2's barred window below;
## the fire escape down it. Built twice: over the street, and seen from the roof.
static func _east_side(g: Node3D, brick: Variant, trim: Color) -> void:
	Houses.fb(g, BLOCK, BLOCK + 0.1, 0.0, PARAPET - 0.08, -9.75, 0.0, brick)
	Houses.fb(g, BLOCK - 0.08, BLOCK + 0.16, PARAPET - 0.08, PARAPET, -9.79, 0.04, Houses.STONE)
	var f := Houses.sub_face(g, Vector2(BLOCK + 0.1, 0.0), Vector2(BLOCK + 0.1, -9.75))     # s from the front corner back, t out over the lot
	for y: float in [3.6, 6.45]:
		Houses.sash(f, 2.6, y, 1.0, 1.4, trim, null, null, Houses.STONE)
		Houses.sash(f, 7.0, y, 1.0, 1.4, trim, Houses.LIT if y < 4.0 else null, Color(0.85, 0.75, 0.55), Houses.STONE)
	Houses.sash(f, 5.6, 0.9, 0.9, 1.2, trim, null, Color(0.7, 0.6, 0.45))
	for i in range(1, 6):
		var s := 5.15 + 0.9 * float(i) / 6.0
		Houses.fb(f, s - 0.012, s + 0.012, 0.92, 2.08, 0.12, 0.145, Houses.BARS)
	Fry.fire_escape(f, FLOORS, 1.0, 4.4, 1.1, DROP_S, NECK_S, PARAPET)


## The vacant lot beside the block, where a house came down: dirt and dead
## grass, weeds, a mattress against the back fence, tyres, a heap of its bricks,
## a chair someone sits on, paper and cans; chain link on the street with a gap
## in it, boards at the back, and over them the tall back of a building across
## the alley. The fire escape's ladder comes down into it.
static func _lot(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var a: float = LOT[0]
	var e: float = LOT[1]
	var dead := Outdoor.tex("out_dead_grass", 2.0, Color(0.55, 0.5, 0.3))
	for patch: Array in [[14.9, 4.5, 1.6, 1.3], [17.4, 6.3, 2.0, 1.6], [15.7, 8.6, 1.4, 0.9]]:
		Kit.box(n, Vector3(patch[2], 0.01, patch[3]), p.pt(patch[0], patch[1], 0.005), dead)
	p.fence(st, true, 9.6, a + 0.1, e - 0.03, [GAP], 1.9, "chain")      # short of the house wall and its old plaster
	p.fence(st, true, LOT_BACK, a + 0.1, e - 0.03, [], 2.0, "wood", Color(0.46, 0.34, 0.24))
	Fry.mattress(p, st, 17.7, LOT_BACK + 0.5, 0.0)
	Fry.tyres(p, st, 18.0, 5.7)
	Fry.rubble(p, st, 16.4, 4.7)
	Props.chair(p, st, 17.6, 8.3, 200.0, Color(0.55, 0.45, 0.3))
	for w: Array in [[14.75, 6.9, 0.5], [16.9, 3.95, 0.6], [18.5, 7.4, 0.45], [15.0, 9.3, 0.35], [18.55, 9.3, 0.5], [16.6, 6.2, 0.3]]:
		Fry.weeds(n, p.pt(w[0], w[1]), w[2], w[0] + w[1])
	Fry.litter(n, p, 14.6, 4.0, 18.4, 9.2, 9, 5.0)
	# Up the drop ladder (its foot kept clear) to the roof, by the gooseneck.
	var ladder := F - DROP_S
	p.block(BLOCK + 1.1, ladder - 0.25, BLOCK + 1.2, ladder + 0.25)
	p.portal(st, "UP THE FIRE ESCAPE", BLOCK + 1.95, ladder, ROOF + 13.0, F - NECK_S)
	# Across the alley behind: the back of a three-storey building, closing the view.
	var back := Houses.face(p, st, 12.0, -3.5, 0.0)
	Houses.fb(back, 0.0, 12.0, 0.0, 9.6, -6.0, 0.0, Houses.wall("brick_3"))
	Houses.fb(back, -0.05, 12.05, 9.6, 9.75, -6.05, 0.08, Houses.STONE)
	for s: float in [3.0, 5.6]:
		for y: float in [3.4, 6.3]:
			Houses.simple_window(back, s, y, 1.0, 1.4, Color(0.8, 0.78, 0.72), Houses.LIT if s + y > 9.5 else null, Color(0.7, 0.55, 0.4))


## East of the row: the street runs on past the park's corner (its lawn behind a
## low wall and an iron railing, trees; the court behind its fence, a hoop at
## its near end) and out of sight. TO THE PARK where the walk ends.
static func _east(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var e0 := EAST + 8.0                 # where street()'s own boxes end
	var e1 := EAST + 100.0
	_flat(p, n, e0, e1, 9.6, 12.1, -0.3, 0.0, Outdoor.pavement())
	_flat(p, n, e0, e1, 12.1, 12.3, -0.3, 0.02, Outdoor.KERB)
	_flat(p, n, e0, e1, 12.3, 19.3, -0.44, -0.14, Outdoor.road())
	_flat(p, n, e0 + 0.01, e1 - 0.01, 12.3, 12.66, -0.142, -0.13, Color(0.42, 0.43, 0.46))
	var dash := -10.5 + 3.4 * 14.0       # street()'s dashes, carried on
	while dash < e1 - 1.0:
		_flat(p, n, dash - 0.7, dash + 0.7, 15.44, 15.56, -0.14, -0.13, Color(0.85, 0.8, 0.55))
		dash += 3.4
	var row_end: float = LOT[1] + 10.0
	var lawn := Outdoor.tex("out_grass", 3.6, Color(0.3, 0.5, 0.24), Color(0.8, 0.9, 0.78))
	_flat(p, n, row_end + 0.02, e1, -22.0, 9.3, -0.3, 0.0, lawn)
	var iron := Color(0.14, 0.15, 0.17)
	_flat(p, n, row_end + 0.3, e1, 9.3, 9.6, 0.0, 0.32, Color(0.62, 0.6, 0.56))
	for y: float in [0.42, 1.12]:
		_flat(p, n, row_end + 0.4, e1, 9.43, 9.47, y, y + 0.05, iron)
	var u := row_end + 0.45
	while u < e1:
		_flat(p, n, u - 0.013, u + 0.013, 9.437, 9.463, 0.32, 1.17, iron)
		u += 0.2 if u < row_end + 12.0 else 0.5
	u = row_end + 0.45
	while u < e1:
		_flat(p, n, u - 0.04, u + 0.04, 9.41, 9.49, 0.32, 1.3, iron)
		u += 2.4
	# The court behind its fence, its near end and a hoop facing down it.
	var green := Color(0.2, 0.52, 0.4)
	var blue := Color(0.18, 0.36, 0.66)
	var line := Color(0.92, 0.92, 0.88)
	var c0 := row_end + 7.5
	_flat(p, n, c0, e1 - 1.0, -14.0, 4.5, -0.29, 0.015, Outdoor.tex("out_court", 9.6, green, green))
	_flat(p, n, c0 + 0.6, c0 + 6.4, -7.2, -1.2, 0.015, 0.021, Outdoor.tex("out_court", 9.6, blue, blue))
	_flat(p, n, c0 + 0.55, c0 + 0.65, -12.5, 3.8, 0.015, 0.024, line)
	_flat(p, n, c0 + 6.35, c0 + 6.45, -7.25, -1.15, 0.021, 0.024, line)
	_flat(p, n, c0 + 0.55, e1 - 1.0, 3.75, 3.85, 0.015, 0.024, line)
	Park.hoop(p, st, c0 + 1.1, -4.2, 90.0)
	p.fence(st, false, c0, -14.0, 4.5, [], 3.6, "chain")
	p.fence(st, true, 4.5, c0, e1, [], 3.6, "chain")
	Outdoor.tree(p, st, row_end + 3.0, 4.5, "b", 1.1, 60.0)
	Outdoor.tree(p, st, row_end + 5.5, -6.0, "a", 0.8, 140.0)
	Outdoor.tree(p, st, row_end + 14.0, 7.2, "d", 1.0, 230.0)
	Outdoor.tree(p, st, row_end + 26.0, 7.0, "c", 0.95, 310.0)
	Outdoor.shrub(p, st, row_end + 1.6, 7.6, "b", 1.0, 20.0)
	# The pavement runs on to the park's own (plans/park.gd: TO ARGONNE COURT
	# at its west end). (Placeholder: the label.)
	p.use_point(st, "TO THE PARK", EAST - 0.7, 10.85, "goto:park", 1.2, 1.9)


## The stair hall, through the arch from the entry hall: the flight up, APT 2's
## door at the back with its mat, the hall's globe.
static func _stair_hall(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	Props.stairs(p, b, FLIGHT_U, STAIR_V, 0.0, 0.95, STAIR_L)
	p.portal(b, "GO UPSTAIRS", FLIGHT_U, 9.0, UP + FLIGHT_U - 0.2, 5.62)
	_number(n, "APT 2", p.pt(12.6, 5.09, 1.75))
	In.mat(p, b, 11.75, 5.42, 0.8, 0.36, Color(0.3, 0.26, 0.2))


## A flat's number by its door, on a dark plate screwed to the wall (the words
## alone on a wall read as the game's own labels, not a sign). `at` is where the
## words stand, the plate a centimetre behind them.
static func _number(n: Node3D, text: String, at: Vector3, yaw := 0.0) -> void:
	var g := Kit.group(n, at, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.44, 0.17, 0.012), Vector3(0, 0, -0.008), Color(0.27, 0.22, 0.18))
	for x: float in [-0.19, 0.19]:
		Kit.box(g, Vector3(0.016, 0.016, 0.006), Vector3(x, 0, -0.001), Color(0.7, 0.62, 0.42))       # the screws
	Props.words(g, text, Vector3.ZERO, 0.1, Color(0.9, 0.86, 0.72))


## The 2nd floor's hall: the well the flight comes up, the flight on up to the
## roof beside it, the doors to APT 3 and APT 4, the lift that does not come.
static func _upstairs(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	Props.stairwell(p, b, UP + FLIGHT_U, STAIR_V, 0.0, 0.95, STAIR_L)
	p.portal(b, "GO DOWNSTAIRS", UP + FLIGHT_U, 5.62, FLIGHT_U - 0.2, 9.0)
	Props.stairs(p, b, UP + ON_U, STAIR_V, 0.0, 0.95, STAIR_L)
	p.portal(b, "UP TO THE ROOF", UP + ON_U, 9.0, ROOF + 12.45, 4.15)
	p.slab(n, true, 5.09, UP + 9.05, UP + 10.35, 0.0, 2.15, 0.03, Props.IRON)
	p.slab(n, true, 5.1, UP + 9.12, UP + 9.69, 0.0, 2.08, 0.03, Props.STEEL)
	p.slab(n, true, 5.1, UP + 9.71, UP + 10.28, 0.0, 2.08, 0.03, Props.STEEL)
	p.slab(n, true, 5.12, UP + 9.3, UP + 10.1, 1.25, 1.55, 0.006, Props.PAPER)
	Props.words(n, "OUT OF ORDER", p.pt(UP + 9.7, 5.128, 1.4), 0.07, Color(0.7, 0.1, 0.1))
	_number(n, "APT 3", p.pt(UP + 8.49, 7.1, 1.75), 90.0)
	_number(n, "APT 4", p.pt(UP + 11.1, 5.07, 1.55))          # (on the door itself: beside it, the flight on up would hide it)
	In.mat(p, b, UP + 8.8, 7.95, 0.36, 0.8, Color(0.3, 0.26, 0.2))
	In.mat(p, b, UP + 11.1, 5.42, 0.8, 0.36, Color(0.24, 0.3, 0.26))


## The roof: tar, its seams and a silver-painted patch; the parapet's coping;
## the stair's bulkhead (its door the way down); the water tank on its stand,
## the pigeon loft and its birds, a chimney, vents, aerials, a chair; the
## gooseneck of the fire escape over the right-hand parapet (the way down to the
## lot); and all round, the view: the street and the lot below, the neighbours'
## roofs, the rows beyond, the park, the city in the haze, the sky.
static func _roof(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var h := PARAPET - ROOF_Y - 0.08
	for v: float in [0.0, 9.6]:
		p.slab(n, true, v, ROOF - 0.12, ROOF + BLOCK - 0.08, h, h + 0.08, 0.3, Houses.STONE)
	p.slab(n, false, ROOF, 0.15, 9.45, h, h + 0.08, 0.3, Houses.STONE)
	for k in 8:
		_flat(p, n, ROOF + 0.1, ROOF + BLOCK - 0.1, 0.9 + k * 1.1, 0.96 + k * 1.1, 0.0, 0.004, Fry.TAR.lightened(0.12))
	_flat(p, n, ROOF + 3.6, ROOF + 6.4, 5.4, 7.6, 0.0, 0.006, Fry.SILVER)
	Fry.bulkhead(p, b, ROOF + 11.2, 0.3, ROOF + 13.8, 3.6, ROOF + 12.45)
	p.portal(b, "GO DOWNSTAIRS", ROOF + 12.45, 3.95, UP + ON_U, 9.0)
	Fry.water_tank(p, b, ROOF + 2.6, 2.3)
	Fry.pigeon_loft(p, b, ROOF + 7.0, 1.35)
	Fry.chimney(p, b, ROOF + 0.5, 6.2)
	Fry.vent(p, b, ROOF + 4.6, 4.6, 0)
	Fry.vent(p, b, ROOF + 9.9, 4.6, 1)
	Fry.vent(p, b, ROOF + 6.3, 8.6, 0)
	Fry.aerial(n, p.pt(ROOF + 12.0, 1.4, 2.72), 2.4, 30.0)
	Fry.aerial(n, p.pt(ROOF + 1.2, 8.6), 3.2, -20.0)
	p.block(ROOF + 1.04, 8.44, ROOF + 1.36, 8.76)
	Props.chair(p, b, ROOF + 9.7, 3.1, 200.0, Color(0.3, 0.5, 0.45))
	# Down the fire escape: the gooseneck's feet on the roof, kept clear.
	p.block(ROOF + BLOCK - 0.52, F - NECK_S - 0.27, ROOF + BLOCK - 0.42, F - NECK_S + 0.27)
	p.portal(b, "DOWN THE FIRE ESCAPE", ROOF + 12.95, F - NECK_S, BLOCK + 1.95, F - DROP_S)
	# The view. Under it all the street's level, ROOF_Y down.
	var ground := -ROOF_Y
	var down := Kit.group(n, p.pt(ROOF, F, ground))          # the front's face, as over the street
	_east_side(down, Houses.wall("brick"), Color(0.3, 0.22, 0.2))
	_flat(p, n, ROOF - 60.0, ROOF + 120.0, F, F + 2.4, ground - 0.3, ground, Outdoor.pavement())
	_flat(p, n, ROOF - 60.0, ROOF + 120.0, F + 2.6, F + 9.6, ground - 0.44, ground - 0.14, Outdoor.road())
	_flat(p, n, ROOF + LOT[0] + 0.1, ROOF + LOT[1], -0.2, F, ground - 0.3, ground, Outdoor.tex("out_dirt", 2.6, Color(0.42, 0.36, 0.28), Color(0.86, 0.78, 0.66)))
	Houses.fb(Houses.face(p, b, ROOF + LOT[0] + 0.1, LOT_BACK), 0.0, LOT[1] - LOT[0] - 0.1, ground, ground + 2.0, -0.03, 0.03, Color(0.46, 0.34, 0.24))
	Fry.roof_row(n, p, ROOF - 40.0, ROOF - 0.1, -0.3, F, ground + 6.9, ground, 1.0, true)
	Fry.roof_row(n, p, ROOF + LOT[1], ROOF + LOT[1] + 10.0, 0.675, F, ground + 6.9, ground, 2.0, true)
	for r in 4:
		var v1 := -9.0 - 26.0 * r
		Fry.roof_row(n, p, ROOF - 150.0, ROOF + LOT[1] + 10.0 + 12.0 * r, v1 - 12.0, v1, ground + 6.6 + 0.9 * Props.rnd(r * 1.7 + 0.3), ground, 3.0 + r, r == 0)
	var lawn := Outdoor.tex("out_grass", 3.6, Color(0.3, 0.5, 0.24), Color(0.8, 0.9, 0.78))
	_flat(p, n, ROOF + LOT[1] + 10.0, ROOF + 160.0, -120.0, F, ground - 0.3, ground, lawn)
	for t: Array in [[32.0, 4.5, "b", 1.1], [34.5, -6.0, "a", 0.8], [43.0, 7.2, "d", 1.0], [55.0, 7.0, "c", 0.95], [50.0, -20.0, "a", 1.0], [66.0, -12.0, "b", 1.1]]:
		var tree := Outdoor.tree(p, b, ROOF + t[0], t[1], t[2], t[3], 40.0 * t[0])
		tree.position.y += ground
	Fry.day_sky(n, p.pt(ROOF + 7.0, 4.8, ground), 1.0)


static func _flat(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look)


static func _front_rooms(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var leather := Color(0.16, 0.13, 0.13)
	# The living room. The left wall is the show: the television between two
	# speakers, the gold records over it.
	Props.big_tv(p, b, 0.38, 7.7, 90.0)
	Props.speaker(p, b, 0.3, 6.45, 90.0)
	Props.speaker(p, b, 0.3, 8.95, 90.0)
	for v: float in [6.3, 7.25, 8.15, 9.1]:
		Props.gold_record(p, b, 0.08, v, 90.0, 2.0)
	Props.table(p, b, 1.9, 7.7, 90.0, 1.1, 0.6, Props.WOOD_DARK, 0.42)
	Props.rug(p, b, 2.0, 7.7, 2.2, 2.6, Color(0.15, 0.14, 0.16))
	Props.couch(p, b, 3.6, 7.7, 270.0, 2.4, leather, 0.95)
	Props.couch(p, b, 3.5, 5.56, 0.0, 1.1, leather, 0.95)                 # his chair
	Props.aquarium(p, b, 6.15, 5.31)
	Props.poster(p, b, 6.15, 5.08, 0.0, 0.9, 0.6, Color(0.45, 0.2, 0.55), "LARGE FRY", 2.05)
	# Under the windows: crates of records, and where the beats get made.
	Props.crates(p, b, 1.6, 9.3, 180.0, 3)
	Props.keyboard(p, b, 6.4, 9.3, 180.0)
	Props.chair(p, b, 6.4, 8.7, 0.0, leather)
	var deck := Props.table(p, b, 7.55, 9.25, 0.0, 0.7, 0.5, Props.WOOD_DARK)
	Props.boombox(deck, Vector3(0, 0.74, 0), 180.0)
	# The man himself, at home: he wanders the living room and will talk.
	p.person(b, "fry", 5.6, 7.4, {"name": "LARGE FRY", "roam": [0, 5, 8.4, 9.6], "talk": "talk_fry_home.json", "reach": 0.5})
	# The entry hall: the lift that does not work, the letter boxes, his door.
	p.slab(n, true, 5.09, 9.05, 10.35, 0.0, 2.15, 0.03, Props.IRON)
	p.slab(n, true, 5.1, 9.12, 9.69, 0.0, 2.08, 0.03, Props.STEEL)
	p.slab(n, true, 5.1, 9.71, 10.28, 0.0, 2.08, 0.03, Props.STEEL)
	p.slab(n, true, 5.12, 9.3, 10.1, 1.25, 1.55, 0.006, Props.PAPER)
	Props.words(n, "OUT OF ORDER", p.pt(9.7, 5.128, 1.4), 0.07, Color(0.7, 0.1, 0.1))
	Kit.box(n, Vector3(0.08, 0.14, 0.02), p.pt(10.6, 5.09, 1.15), Props.STEEL)
	Props.mailboxes(p, b, 8.48, 6.2, 90.0)
	Props.words(n, "APT 1", p.pt(8.49, 7.1, 1.75), 0.1, Color(0.9, 0.86, 0.72), 90.0)
	Props.rug(p, b, 9.0, 7.95, 0.5, 0.8, Color(0.3, 0.26, 0.2))


static func _back_rooms(p: Node3D, b: int) -> void:
	# The kitchen: the units along the back wall, a table buried in pizza boxes.
	Props.sink_unit(p, b, 1.2, 0.39, 0.0, 1.6)
	Props.stove(p, b, 2.45, 0.41, 0.0)
	Props.fridge(p, b, 3.3, 0.44, 0.0)
	var table := Props.table(p, b, 1.7, 3.0, 0.0, 1.2, 0.8, Color(0.82, 0.8, 0.74))
	for k in 4:
		Kit.block(table, Vector3(0.44, 0.045, 0.44), Vector3(0.15, 0.74 + k * 0.046, 0.0), Color(0.72, 0.58, 0.4).darkened(0.07 * (k % 2)), Vector3(0, 9.0 * k - 12.0, 0))
	Kit.cyl(table, 0.045, 0.14, Vector3(-0.35, 0.81, 0.15), Color(0.8, 0.15, 0.15), Vector3.ZERO, 8)
	Props.seat(p, b, 1.7, 2.28, 0.0)
	Props.seat(p, b, 1.7, 3.72, 180.0)
	Props.clock(p, b, 3.0, 0.08, 0.0, 2.3)
	# The bathroom.
	Props.tub(p, b, 4.26, 1.0)
	Props.toilet(p, b, 5.75, 0.42)
	Props.basin(p, b, 5.05, 0.31)
	Props.rug(p, b, 5.0, 2.6, 1.0, 0.7, Color(0.55, 0.3, 0.6))
	# The bedroom: a bed for a big man, the wardrobe, weights he does not lift.
	Props.bed(p, b, 8.2, 1.14, 0.0, 2.0, 2.1, Color(0.42, 0.16, 0.4))
	Props.wardrobe(p, b, 10.3, 0.4, 0.0, 1.1)
	var chest := Props.dresser(p, b, 6.55, 2.8, 90.0, 1.4, Props.WOOD_DARK)
	Props.boombox(chest, Vector3(0, 0.9, 0))
	Props.weights(p, b, 10.0, 3.7)
	Props.rug(p, b, 8.2, 3.2, 2.2, 1.4, Color(0.75, 0.6, 0.2))
	for u: float in [7.6, 8.2, 8.8]:
		Props.gold_record(p, b, u, 0.08, 0.0, 1.9)


static func _paint(c: Color) -> StandardMaterial3D:
	return Kit.tex("in_plaster", 2.0, c, true, c)


## A slab on the street face of the front, d proud of it, its back a centimetre into the wall.
static func _proud(p: Node3D, n: Node3D, a: float, b: float, y0: float, y1: float, d: float, look: Variant) -> void:
	p.slab(n, true, F + (d - 0.01) * 0.5, a, b, y0, y1, d + 0.01, look)


## Each room's walls, floor edges and lights (props_in.gd). Nothing here takes
## floor space; nothing hangs lower than 1.95 m where anyone walks.
static func _dress(p: Node3D, b1: int, b2: int, h1: int) -> void:
	var n1: Node3D = p.node_of(b1)
	var n2: Node3D = p.node_of(b2)
	var gilt := Color(0.88, 0.68, 0.26)
	var cream := Color(0.97, 0.94, 0.84)
	var black := Color(0.11, 0.1, 0.11)
	var through := [{"a": 1.6, "b": 2.6, "kind": "arch", "head": 2.1}, {"a": 4.5, "b": 5.4}, {"a": 6.9, "b": 7.8}]
	var his_door := [{"a": 7.5, "b": 8.4}]

	# The living room, where the money is on show: plum panelling to a gilt dado,
	# a pink trellis paper over it, a gilt picture rail under a plum frieze and a
	# cream cornice, gilt architraves; his own portrait by the arch, a sunburst
	# mirror over his chair, a chandelier where the room's light hangs.
	var living := {
		"lower": Kit.tex("in_panel", 0.92, Color(0.36, 0.15, 0.34), true, Color(0.54, 0.24, 0.5)),
		"upper": Kit.tex("in_trellis", 0.8, Color(0.74, 0.44, 0.68), true, Color(0.92, 0.58, 0.86)),
		"dado": gilt, "dado_y": 0.92, "rail": gilt, "frieze": _paint(Color(0.6, 0.27, 0.58)),
		"skirt": Color(0.24, 0.08, 0.22), "cornice": Color(0.98, 0.9, 0.66), "surround": gilt}
	In.room_walls(p, b1, 0, 5, 8.4, 9.6, living, through, [], his_door)
	In.picture(p, b1, 0.78, 5.085, 0.0, 0.62, 0.78, "face", gilt, 1.62, Color(0.36, 0.14, 0.34))
	In.sunburst(p, b1, 3.55, 5.085, 0.0, 0.2, 1.75)
	In.chandelier(p, b1, 4.2, 7.3, 2.2)

	# The entry hall is the block's, not his: cream glazed tile to a green cap,
	# green paint over it, terrazzo with a green border, a mat inside the street
	# door, a milk-glass globe, and over the lift its floor dial, the needle stuck.
	var hall := {
		"lower": Kit.tex("in_tile", 0.6, Color(0.86, 0.82, 0.7), true, Color(1.0, 0.96, 0.84)),
		"upper": _paint(Color(0.42, 0.64, 0.54)), "dado": Color(0.14, 0.32, 0.24), "dado_y": 1.3,
		"skirt": Color(0.14, 0.26, 0.2), "skirt_h": 0.12, "cornice": cream, "surround": cream}
	var arch := [{"a": 6.0, "b": 7.2, "kind": "arch", "head": 2.3}]
	In.room_walls(p, b1, 8.4, 5, 11, 9.6, hall, [{"a": 9.105, "b": 10.295, "head": 2.095, "bare": true}], his_door, arch)
	In.border(p, b1, 8.4, 5, 11, 9.6, Color(0.2, 0.38, 0.3), 0.18)
	In.mat(p, b1, 9.65, 9.2, 1.0, 0.5, Color(0.22, 0.2, 0.2), Color(0.55, 0.14, 0.12))
	In.pendant(p, b1, 10.3, 7.0, 2.25, cream, "globe")            # off to the side, clear of the lift's dial
	# The stair hall and the 2nd floor's hall are the block's too: the same tile and paint.
	In.room_walls(p, b1, 11, 5, BLOCK, 9.6, hall, [{"a": 11.3, "b": 12.2}], arch, [])
	In.border(p, b1, 11, 5, BLOCK, 9.6, Color(0.2, 0.38, 0.3), 0.18)
	In.pendant(p, b1, 12.0, 7.6, 2.25, cream, "globe")
	In.room_walls(p, h1, UP + 8.4, 5, UP + BLOCK, 9.6, hall, [{"a": UP + 9.105, "b": UP + 10.295, "head": 2.095, "bare": true}, {"a": UP + 10.65, "b": UP + 11.55}],
		his_door, [{"a": 6.575, "b": 7.575, "kind": "window", "sill": 0.6, "head": 2.0}])
	In.border(p, h1, UP + 8.4, 5, UP + BLOCK, 9.6, Color(0.2, 0.38, 0.3), 0.18)
	In.pendant(p, h1, UP + 10.4, 7.4, 2.25, cream, "globe")
	var dial := Kit.group(n1, p.pt(9.7, 5.085, 2.34))
	Kit.box(dial, Vector3(0.36, 0.28, 0.02), Vector3(0, 0, 0.01), In.BRASS)
	Kit.disc(dial, 0.11, Vector3(0, 0, 0.024), Color(0.96, 0.93, 0.82), 0.008, 18)
	for k in 5:
		var tick := Kit.group(dial, Vector3(0, 0, 0.029), Vector3(0, 0, 60.5 - k * 30.0))
		Kit.box(tick, Vector3(0.012, 0.03, 0.003), Vector3(0, 0.085, 0), Props.DARK)
	var needle := Kit.group(dial, Vector3(0, 0, 0.032), Vector3(0, 0, 71.0))
	Kit.box(needle, Vector3(0.012, 0.09, 0.003), Vector3(0, 0.04, 0), Color(0.75, 0.12, 0.1))
	Kit.cyl(dial, 0.016, 0.01, Vector3(0, 0, 0.034), Props.DARK, Vector3(90, 0, 0), 8)

	# The kitchen: turquoise tile to a white cap at splashback height, sunny yellow
	# over it; café curtains in tomato red at the window and the back lot beyond
	# it, a shade over the table, the phone on the wall, a shelf of jars.
	var kitchen := {
		"lower": Kit.tex("in_tile", 0.45, Color(0.36, 0.66, 0.66), true, Color(0.5, 0.86, 0.84)),
		"upper": _paint(Color(1.0, 0.86, 0.42)), "dado": Color(0.97, 0.96, 0.92), "dado_y": 1.45,
		"skirt": Color(0.18, 0.4, 0.4), "skirt_h": 0.12, "cornice": cream, "surround": cream}
	In.room_walls(p, b2, 0, 0, 3.8, 5, kitchen, [{"a": 0.7, "b": 1.9, "kind": "window", "sill": 1.15, "head": 2.0}], [], [])
	In.night_view(p, b2, true, 0.0, -1.0, 0.7, 1.9, 1.15, 2.0, "lot")
	var red := Color(0.9, 0.26, 0.2)
	for k in 8:                                    # the half curtain on its rod, in folds
		var a0 := 0.62 + k * 0.17
		p.slab(n2, true, 0.14 + 0.012 * (k % 2), a0, a0 + 0.17, 1.12, 1.55, 0.02, red.darkened(0.12 * (k % 2)))
	p.slab(n2, true, 0.16, 0.58, 2.02, 1.555, 1.575, 0.02, Props.STEEL)
	p.slab(n2, true, 0.15, 0.5, 2.1, 2.07, 2.3, 0.04, red)                       # the pelmet, a white band along its foot
	p.slab(n2, true, 0.174, 0.5, 2.1, 2.07, 2.1, 0.008, Color(0.98, 0.96, 0.92))
	In.pendant(p, b2, 1.7, 3.35, 1.95, Color(0.95, 0.5, 0.15), "cone")
	In.wall_phone(p, b2, 3.715, 3.7, 270.0, 1.5)
	var shelf := Kit.group(n2, p.pt(2.45, 0.085, 1.62))
	Kit.box(shelf, Vector3(0.66, 0.03, 0.16), Vector3(0, 0, 0.08), Color(0.62, 0.42, 0.24))
	for x: float in [-0.26, 0.26]:
		Kit.box(shelf, Vector3(0.03, 0.12, 0.12), Vector3(x, -0.075, 0.06), Color(0.55, 0.36, 0.2))
	var jars := [Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.2), Color(0.3, 0.6, 0.3), Color(0.95, 0.92, 0.82), Color(0.6, 0.32, 0.18)]
	for k in 5:
		var hgt := 0.1 + 0.05 * Props.rnd(k * 2.7 + 1.0)
		Kit.cyl(shelf, 0.036, hgt, Vector3(-0.24 + k * 0.12, 0.015 + hgt * 0.5, 0.08), jars[k], Vector3.ZERO, 8)
		Kit.cyl(shelf, 0.038, 0.025, Vector3(-0.24 + k * 0.12, 0.0275 + hgt, 0.08), Color(0.92, 0.9, 0.86), Vector3.ZERO, 8)

	# The bathroom: pink tile to a black cap, mint over it, black skirting, the
	# little white floor tiles bordered in black; a glass-block panel over the
	# bath and a row of bulbs over the mirror.
	var bath := {
		"lower": Kit.tex("in_tile", 0.45, Color(0.82, 0.52, 0.62), true, Color(1.0, 0.72, 0.82)),
		"upper": _paint(Color(0.66, 0.9, 0.8)), "dado": black, "dado_y": 1.12,
		"skirt": black, "skirt_h": 0.12, "cornice": cream}
	In.room_walls(p, b2, 3.8, 0, 6.2, 5, bath, [], [], [])
	In.border(p, b2, 3.8, 0, 6.2, 5, black, 0.1)
	In.glass_blocks(p, b2, 4.26, 0.085, 0.0, 0.4, 0.8, 1.85)
	var bulbs := Kit.group(n2, p.pt(5.05, 0.085, 1.97))
	Kit.box(bulbs, Vector3(0.6, 0.06, 0.04), Vector3(0, 0, 0.02), Props.STEEL)
	for k in 4:
		Kit.ball(bulbs, 0.04, Vector3(-0.225 + k * 0.15, 0, 0.065), Kit.flat(Color(1.0, 0.95, 0.82), 2.0), 8)

	# The bedroom: black lacquer panelling to a gilt dado, teal regency stripes
	# over it, a gilt cornice; a shaded lamp each side of the bed, a city at night
	# over the chest of drawers.
	var bedroom := {
		"lower": Kit.tex("in_panel", 0.92, Color(0.14, 0.12, 0.14), true, Color(0.26, 0.22, 0.26)),
		"upper": Kit.tex("in_stripe", 0.9, Color(0.24, 0.46, 0.54), true, Color(0.38, 0.68, 0.78)),
		"dado": gilt, "dado_y": 0.92, "skirt": black, "cornice": Color(0.98, 0.9, 0.66)}
	In.room_walls(p, b2, 6.2, 0, 11, 5, bedroom, [], [], [])
	for u: float in [6.9, 9.5]:
		In.sconce(p, b2, u, 0.085, 0.0, "shade", 1.5)
	In.picture(p, b2, 6.285, 2.8, 90.0, 0.9, 0.6, "city", gilt, 1.75)

	# Brass thresholds in the doorways.
	Kit.box(n2, Vector3(1.0, 0.012, 0.19), p.pt(2.1, 5.0, 0.006), In.BRASS)
	Kit.box(n2, Vector3(0.9, 0.012, 0.19), p.pt(4.95, 5.0, 0.006), In.BRASS)
	Kit.box(n2, Vector3(0.9, 0.012, 0.19), p.pt(7.35, 5.0, 0.006), In.BRASS)
	Kit.box(n1, Vector3(0.19, 0.012, 0.9), p.pt(8.4, 7.95, 0.006), In.BRASS)
