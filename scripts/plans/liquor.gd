extends RefCounted
## The liquor store: Parkway Spirits. A one-storey box with a roll-down grate.
## The customer never touches a bottle: the spirits are on the wall behind a
## sheet of plexiglass that runs the width of the shop, and only the beer
## coolers and the wine are out on the floor. 10 x 12 m inside, three bands
## from the street back:
##
##   the sales floor
##   behind the counter      a strip behind the glass, the bottles on its back wall
##   office | stock room
##
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 12.

const Props := preload("res://scripts/props.gd")


static func build(p: Node3D) -> void:
	p.setup("LIQUOR STORE", 10.0, 12.0)
	var red := Kit.tex("painted_block", 1.2, Color(0.6, 0.3, 0.28), true, Color(0.9, 0.62, 0.58))
	var cream := Kit.tex("painted_block", 1.2, Color(0.86, 0.82, 0.68), true, Color(1.0, 0.96, 0.8))
	var lino := Kit.tex("lino", 1.4, Color(0.5, 0.48, 0.46), true, Color(0.8, 0.76, 0.74))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var carpet := Kit.tex("carpet", 2.0, Color(0.35, 0.3, 0.2), true, Color(0.75, 0.68, 0.5))
	var black_brick := Kit.tex("brick", 1.5, Color(0.2, 0.18, 0.2), true, Color(0.42, 0.4, 0.45))
	var tube := Color(1.0, 0.98, 0.9)
	var steel_door := Color(0.36, 0.4, 0.44)
	var frame := Color(0.2, 0.2, 0.22)

	var st: int = p.street(-4.0, 14.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	p.arrive = p.pt(7.85, 13.2)

	p.room("SALES FLOOR", b1, 0, 6.6, 10, 12, lino, {"light": tube, "energy": 0.7})
	p.room("BEHIND THE COUNTER", b2, 0, 4.2, 10, 6.6, lino, {"light": tube, "energy": 0.5})
	p.room("OFFICE", b3, 0, 0, 4, 4.2, carpet, {"light": Color(1.0, 0.88, 0.7), "energy": 0.4})
	p.room("STOCK ROOM", b3, 4, 0, 10, 4.2, concrete, {"light": tube, "energy": 0.4})

	var front: Node3D = p.cross(b1, 12.0, 0, 10, black_brick, [
		{"a": 1.0, "b": 6.2, "kind": "window", "sill": 0.8, "head": 2.3, "bars": true, "frame": frame},
		{"a": 7.4, "b": 8.3, "head": 2.1, "colour": Color(0.45, 0.1, 0.1), "frame": frame},
	], {"h": 4.2})
	p.side(b1, 0.0, 6.6, 12, red)
	p.side(b1, 10.0, 6.6, 12, red)
	# The plexiglass: a window the width of the counter, and the steel door beside it.
	p.cross(b2, 6.6, 0, 10, red, [
		{"a": 0.6, "b": 7.4, "kind": "window", "sill": 1.05, "head": 2.25, "pane": Color(0.72, 0.88, 0.84, 0.2), "frame": Props.STEEL},
		{"a": 8.3, "b": 9.2, "colour": steel_door, "name": "COUNTER DOOR"},
	])
	p.side(b2, 0.0, 4.2, 6.6, cream)
	p.side(b2, 10.0, 4.2, 6.6, cream)
	p.cross(b3, 4.2, 0, 10, cream, [{"a": 8.0, "b": 8.9, "colour": steel_door}])
	p.side(b3, 0.0, 0, 4.2, cream)
	p.side(b3, 10.0, 0, 4.2, cream)
	p.side(b3, 4.0, 0, 4.2, cream, [{"a": 1.6, "b": 2.5, "hinge": "a", "swing": -1, "colour": Color(0.42, 0.3, 0.2)}])
	p.cross(b3, 0.0, 0, 10, cream, [], {"back": true})

	_street(p, st, front)
	_floor(p, b1)
	_counter(p, b2)
	_back(p, b3)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var yellow := Color(0.98, 0.85, 0.3)
	# The front: the name on a red board, the grate rolled up over the window, neon in it.
	p.slab(front, true, 12.1, 0.5, 9.5, 2.75, 3.85, 0.08, Color(0.6, 0.1, 0.1))
	Props.words(front, "PARKWAY SPIRITS", p.pt(5.0, 12.145, 3.42), 0.5, yellow)
	Props.words(front, "BEER  /  WINE  /  LIQUOR", p.pt(5.0, 12.145, 2.97), 0.2, yellow, 0.0, false)
	p.slab(front, true, 12.0, -0.05, 10.05, 4.2, 4.4, 0.3, Color(0.2, 0.18, 0.2))
	p.slab(front, true, 12.12, 0.9, 6.3, 2.42, 2.62, 0.14, Color(0.45, 0.47, 0.5))
	Props.neon(front, "LIQUOR", p.pt(2.5, 12.03, 1.85), 0.3, Color(1.0, 0.3, 0.25))
	Props.neon(front, "COLD BEER", p.pt(4.9, 12.03, 1.95), 0.15, Color(0.4, 0.75, 1.0))
	Props.neon(front, "OPEN", p.pt(5.3, 12.03, 1.3), 0.2, Color(0.4, 1.0, 0.5))
	Props.words(front, "NO ONE UNDER 21", p.pt(7.85, 12.1, 2.32), 0.07, Color(0.92, 0.9, 0.84), 0.0, false)
	# Next door: a carry-out on the left, a boarded house on the right.
	p.slab(n, true, 12.0, -12.0, 0.0, 0.0, 3.6, 0.15, Kit.tex("stucco", 2.0, Color(0.7, 0.66, 0.4), true, Color(1.0, 0.95, 0.6)))
	p.slab(n, true, 12.085, -8.8, -3.6, 0.6, 2.3, 0.03, Kit.flat(Color(1.0, 0.95, 0.75), 0.9))
	p.slab(n, true, 12.1, -2.7, -1.8, 0.0, 2.1, 0.03, Color(0.5, 0.52, 0.55))
	Props.words(n, "CARRY OUT", p.pt(-6.2, 12.09, 2.95), 0.36, Color(0.75, 0.12, 0.1))
	Props.words(n, "CHICKEN BOX  -  LAKE TROUT  -  SUBS", p.pt(-6.2, 12.12, 1.0), 0.12, Color(0.75, 0.12, 0.1), 0.0, false)
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	Props.rowhouse(p, n, 10.0, 12.0, old_brick, true)
	Props.rowhouse(p, n, 15.0, 12.0, old_brick, false, true)
	Props.rowhouse(p, n, 20.0, 12.0, old_brick, true)
	# On the pavement.
	Props.ice_box(p, st, 9.25, 12.44)
	Props.payphone(p, st, 6.8, 12.08)
	Props.bin(p, st, 0.4, 12.45)
	Props.street_lamp(p, st, 3.2, 14.05)
	Props.hydrant(p, st, 10.6, 14.0)


static func _floor(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The beer, down the left wall.
	Props.fridge_case(p, b, 0.43, 8.9, 90.0, 4, "bottles", "COLD BEER", Color(0.7, 0.12, 0.1))
	Props.atm(p, b, 0.4, 11.3, 90.0)
	# A stack of cases on special, the wine, the ice.
	Props.case_stack(p, b, 3.3, 9.0)
	Props.gondola(p, b, 5.6, 8.9, 90.0, 2.6, "bottles")
	Props.shelves(p, b, 9.7, 9.2, 270.0, 2.4, "bottles", Props.WOOD_DARK, 1.9, 0.4)
	Props.chest_freezer(p, b, 3.0, 11.55, 180.0, 1.3, "ICE", Color(0.15, 0.35, 0.75))
	# At the glass: a ledge to count your money on, the tray, the rules.
	p.slab(n, true, 6.785, 0.6, 7.4, 1.0, 1.05, 0.22, Props.STEEL)
	Kit.box(n, Vector3(0.5, 0.06, 0.3), p.pt(4.0, 6.7, 1.085), Props.IRON)
	Props.words(n, "PAY HERE", p.pt(4.0, 6.69, 2.5), 0.16, Color(0.98, 0.95, 0.86))
	Props.words(n, "NO LOITERING  -  NO CREDIT  -  WE CARD", p.pt(4.0, 6.69, 0.6), 0.09, Color(0.92, 0.9, 0.84), 0.0, false)
	Props.words(n, "STAFF ONLY", p.pt(8.75, 6.69, 2.3), 0.09, Color(0.92, 0.9, 0.84), 0.0, false)


static func _counter(p: Node3D, b: int) -> void:
	# The wall of bottles, and the counter under the glass.
	Props.shelves(p, b, 3.9, 4.455, 0.0, 7.2, "bottles", Props.WOOD_DARK, 2.1, 0.36)
	var counter := Props.counter(p, b, 4.0, 6.3, 180.0, 6.8, 0.4, 1.0, Color(0.3, 0.2, 0.13), Color(0.75, 0.72, 0.66))
	Props.till(counter, Vector3(-0.5, 1.0, 0.0))
	Props.lotto(counter, Vector3(1.6, 1.0, 0.0), 180.0)
	Kit.block(counter, Vector3(0.34, 0.28, 0.3), Vector3(-2.6, 1.0, 0.0), Props.CREAM)
	Kit.box(counter, Vector3(0.26, 0.2, 0.01), Vector3(-2.6, 1.15, 0.154), Kit.flat(Color(0.55, 0.6, 0.62), 0.6))
	Props.chair(p, b, 0.75, 5.4, 90.0)
	p.person(b, "clerk", 4.6, 5.45, {"face": "bored"})


static func _back(p: Node3D, b: int) -> void:
	# The office: the desk, the safe, a couch for the long nights.
	Props.desk(p, b, 1.6, 0.5, 0.0, Props.WOOD, 2)
	Props.safe(p, b, 0.36, 2.6, 90.0)
	Props.files(p, b, 3.2, 0.4, 0.0, 2)
	Props.couch(p, b, 1.6, 3.69, 180.0, 1.8, Color(0.36, 0.3, 0.22))
	Props.poster(p, b, 3.2, 0.08, 0.0, 0.45, 0.6, Color(0.6, 0.12, 0.1), "", 1.8)
	# The stock room: shelves of boxes, cases by the stack, kegs.
	Props.shelves(p, b, 7.3, 0.31, 0.0, 4.6)
	Props.case_stack(p, b, 5.6, 3.2, 0.0, 3, 3, Color(0.8, 0.62, 0.15))
	Props.case_stack(p, b, 7.0, 3.2, 0.0, 3, 2, Color(0.15, 0.3, 0.6))
	var kegs: Node3D = p.prop(b, 9.45, 2.4, 0.0, 0.62, 1.25)
	for k in 2:
		Kit.cyl(kegs, 0.28, 0.6, Vector3(0, 0.3, -0.3 + k * 0.6), Props.STEEL, Vector3.ZERO, 10)
		Kit.cyl(kegs, 0.29, 0.04, Vector3(0, 0.3, -0.3 + k * 0.6), Props.IRON, Vector3.ZERO, 10)
