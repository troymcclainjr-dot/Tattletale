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
	var hall_floor := Kit.tex("lino", 1.6, Color(0.5, 0.5, 0.48), true, Color(0.7, 0.72, 0.7))
	var tan_brick := Kit.tex("stucco", 2.0, Color(0.8, 0.72, 0.56), true, Color(1.0, 0.9, 0.7))        # the block is buff stucco, not the row's red brick
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
	p.room("BATHROOM", b2, 3.8, 0, 6.2, 5, lino, {"light": Color(0.95, 1.0, 1.0), "energy": 0.4})
	p.room("BEDROOM", b2, 6.2, 0, 11, 5, bed_carpet, {"light": warm, "energy": 0.5})

	var front: Node3D = p.cross(b1, 9.6, 0, 11, tan_brick, [
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


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var stone := Color(0.78, 0.74, 0.64)
	# The block's own front: two more floors of windows, a stone band, the door under a canopy.
	for row in 2:
		var y: float = 3.9 + row * 2.9
		for u: float in [2.2, 6.0, 9.65]:
			var half := 0.7 if u > 9.0 else 1.1
			p.slab(front, true, 9.68, u - half - 0.12, u + half + 0.12, y - 0.1, y + 1.4, 0.03, stone)
			p.slab(front, true, 9.695, u - half, u + half, y, y + 1.3, 0.03, Kit.flat(Color(1.0, 0.85, 0.55), 0.5) if Props.rnd(u + row * 3.1) > 0.5 else Color(0.2, 0.24, 0.32))
	p.slab(front, true, 9.6, -0.02, 11.02, 9.0, 9.3, 0.4, stone.darkened(0.3))
	p.slab(front, true, 9.66, -0.02, 11.02, 2.95, 3.15, 0.1, stone)
	Kit.box(front, Vector3(1.7, 0.1, 0.9), p.pt(9.65, 10.05, 2.45), Color(0.2, 0.26, 0.24))
	Props.words(front, "ARGONNE COURT", p.pt(9.65, 9.715, 3.05), 0.15, Color(0.3, 0.22, 0.2))
	p.slab(front, true, 9.69, 8.72, 8.98, 1.2, 1.6, 0.02, Props.STEEL)
	for k in 4:
		p.slab(front, true, 9.702, 8.76, 8.94, 1.24 + k * 0.09, 1.29 + k * 0.09, 0.008, Props.DARK)
	Kit.block(n, Vector3(1.3, 0.07, 0.5), p.pt(9.65, 9.9), Color(0.8, 0.8, 0.78))
	# Either side: the end of a brick row on the left, more of the same on the right.
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	var formstone := Kit.tex("painted_block", 0.7, Color(0.62, 0.6, 0.56), true, Color(0.75, 0.78, 0.86))
	Props.rowhouse(p, n, -5.0, 9.6, old_brick, false, true)
	Props.rowhouse(p, n, -10.0, 9.6, formstone)
	Props.rowhouse(p, n, 11.0, 9.6, old_brick, false, true)
	Props.rowhouse(p, n, 16.0, 9.6, formstone, true)
	Props.rowhouse(p, n, 21.0, 9.6, old_brick)
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
