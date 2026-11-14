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

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Houses := preload("res://scripts/houses.gd")
const F := 9.675          # the street face of the front wall


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

	var st: int = p.street(-4.0, 14.0)
	var b1: int = p.band()
	var b2: int = p.band()
	p.arrive = p.pt(9.65, 10.8)

	p.room("LIVING ROOM", b1, 0, 5, 8.4, 9.6, shag, {"light": warm, "energy": 0.65})
	p.room("ENTRY HALL", b1, 8.4, 5, 11, 9.6, hall_floor, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("KITCHEN", b2, 0, 0, 3.8, 5, lino, {"light": Color(0.95, 1.0, 0.9), "energy": 0.45})
	p.room("BATHROOM", b2, 3.8, 0, 6.2, 5, bath_floor, {"light": Color(0.95, 1.0, 1.0), "energy": 0.4})
	p.room("BEDROOM", b2, 6.2, 0, 11, 5, bed_carpet, {"light": warm, "energy": 0.5})

	var front: Node3D = p.cross(b1, 9.6, 0, 11, Houses.wall("brick"), [
		{"a": 1.0, "b": 3.4, "kind": "window", "sill": 0.8, "head": 2.1, "blinds": true, "frame": trim},
		{"a": 4.6, "b": 7.4, "kind": "window", "sill": 0.8, "head": 2.1, "blinds": true, "frame": trim},
		{"a": 9.2, "b": 10.1, "head": 2.1, "colour": Color(0.2, 0.26, 0.24), "frame": trim},
	], {"h": 9.0})
	p.side(b1, 0.0, 5, 9.6, plum)
	p.side(b1, 11.0, 5, 9.6, hall_look)
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

	_street(p, st, front)
	_front_rooms(p, b1)
	_back_rooms(p, b2)
	_dress(p, b1, b2)


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
	_proud(p, front, 10.25, 10.99, 0.0, 0.5, 0.04, Houses.BASE)        # stopping short of the wall's end, which shares no face with them
	for w: Array in [[1.0, 3.4], [4.6, 7.4]]:
		Houses.fb(g, w[0] - 0.12, w[1] + 0.12, 2.17, 2.38, 0.0, 0.08, Houses.STONE)
		Houses.fb(g, w[0] - 0.1, w[1] + 0.1, 0.62, 0.735, 0.0, 0.14, Houses.STONE)
	Houses.fb(g, 7.75, 8.55, 0.5, 1.3, 0.0, 0.012, Houses.CONCRETE)
	var curtains := [Color(0.85, 0.3, 0.3), Color(0.95, 0.93, 0.86), Color(0.4, 0.65, 0.4)]
	for row in 2:
		var y: float = 3.6 + row * 2.85
		for k in 3:
			var c: float = [2.2, 6.0, 9.65][k]
			var lit: Variant = Houses.LIT if Props.rnd(c + row * 3.1) > 0.5 else null          # the same windows lit as before
			if c > 9.0:
				Houses.sash(g, c, y, 1.2, 1.45, trim, lit, curtains[k], Houses.STONE)
				if row == 0:          # a window box
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
	Houses.cornice(g, 11.0, 9.0, stone, 4, brick)
	Houses.fb(g, -0.08, 11.0, 8.84, 8.88, -9.75, -0.25, Houses.TAR)          # the flat roof
	# The sides, bare over the neighbours (whose houses run 3 m back).
	Houses.fb(g, -0.1, -0.08, 0.0, 8.9, -9.75, -3.08, brick)
	Houses.fb(g, -0.1, 0.0, 7.0, 8.9, -3.08, 0.0, brick)
	Houses.fb(g, 11.0, 11.1, 0.0, 8.9, -9.75, -3.08, brick)
	Houses.fb(g, 11.0, 11.1, 7.0, 8.9, -3.08, 0.0, brick)
	for s: float in [0.14, 10.86]:          # the rain leaders, a head and straps on each
		Houses.pipe(g, Vector3(s, 0.02, 0.1), Vector3(s, 8.0, 0.1), 0.05, Houses.BARS)
		Houses.fb(g, s - 0.1, s + 0.1, 8.0, 8.22, 0.0, 0.2, Houses.BARS)
		for y: float in [1.6, 3.7, 5.8]:
			Houses.fb(g, s - 0.07, s + 0.07, y, y + 0.05, 0.0, 0.16, Houses.BARS)
	p.slab(front, true, 9.66, -0.02, 11.02, 2.95, 3.15, 0.1, stone)
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
	# Either side: the end of a brick row on the left, more of the same on the right.
	Props.rowhouse(p, n, -5.0, 9.6, Houses.wall("brick_2"), false, true)
	Props.rowhouse(p, n, -10.0, 9.6, Houses.wall("painted"))
	Props.rowhouse(p, n, 11.0, 9.6, Houses.wall("brick_dark"), false, true)
	Props.rowhouse(p, n, 16.0, 9.6, Houses.wall("formstone"), true)
	Props.rowhouse(p, n, 21.0, 9.6, Houses.wall("brick_2"))
	Props.street_lamp(p, st, 5.4, 11.65)
	Props.cans(p, st, 11.6, 9.95, 3)
	Props.hydrant(p, st, 12.6, 11.6)
	Props.bench(p, st, 3.0, 10.02, 0.0, 1.8, Props.IRON, true)


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
static func _dress(p: Node3D, b1: int, b2: int) -> void:
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
	In.room_walls(p, b1, 8.4, 5, 11, 9.6, hall, [{"a": 9.105, "b": 10.295, "head": 2.095, "bare": true}], his_door, [])
	In.border(p, b1, 8.4, 5, 11, 9.6, Color(0.2, 0.38, 0.3), 0.18)
	In.mat(p, b1, 9.65, 9.2, 1.0, 0.5, Color(0.22, 0.2, 0.2), Color(0.55, 0.14, 0.12))
	In.pendant(p, b1, 10.3, 7.0, 2.25, cream, "globe")            # off to the side, clear of the lift's dial
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
