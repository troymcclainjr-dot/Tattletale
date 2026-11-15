extends RefCounted
## The corner store: Miss Bea's Corner Grocery, on the ground floor of the last
## house in a brick row, where two streets meet. One long room and two small
## ones behind it. 9 x 11 m inside, two bands from the street back:
##
##   the shop: behind the counter (left) | the aisles
##   back office | stock room
##
## The clerk sits behind plexiglass down the left side; the way in behind the
## counter is round its far end, by the coolers. Everything worth looking at is
## on the left and back walls, because that is what the camera sees.
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 11 and the cross street is on the right.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const F := 11.075            # the shop's street face


static func build(p: Node3D) -> void:
	p.setup("CORNER STORE", 9.0, 11.0)
	var cream := Kit.tex("painted_block", 1.2, Color(0.86, 0.82, 0.68), true, Color(1.0, 0.96, 0.78))
	var lino := Kit.tex("lino", 1.2, Color(0.7, 0.68, 0.6), true, Color(0.95, 0.9, 0.8))
	var carpet := Kit.tex("in_carpet", 0.6, Color(0.55, 0.36, 0.22), true, Color(0.78, 0.5, 0.32))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.95, 0.8, 0.72))
	var tube := Color(0.98, 0.99, 0.95)
	var trim := Color(0.16, 0.36, 0.28)
	var grey_door := Color(0.5, 0.52, 0.5)

	var st: int = p.street(-4.0, 11.2)
	var b1: int = p.band()
	var b2: int = p.band()
	p.arrive = p.pt(7.45, 12.2)

	p.room("SHOP", b1, 0, 4.2, 9, 11, lino, {"light": tube, "energy": 0.7})
	p.room("BACK OFFICE", b2, 0, 0, 4, 4.2, carpet, {"light": Color(1.0, 0.88, 0.7), "energy": 0.4})
	p.room("STOCK ROOM", b2, 4, 0, 9, 4.2, concrete, {"light": tube, "energy": 0.4})

	var front: Node3D = p.cross(b1, 11.0, 0, 9, brick, [
		{"a": 1.0, "b": 6.0, "kind": "window", "sill": 0.75, "head": 2.25, "bars": true, "frame": trim},
		{"a": 7.0, "b": 7.9, "head": 2.1, "colour": trim.lightened(0.1), "frame": trim},
	], {"h": 6.6})
	p.side(b1, 0.0, 4.2, 11, cream)
	p.side(b1, 9.0, 4.2, 11, cream)
	p.cross(b2, 4.2, 0, 9, cream, [
		{"a": 0.8, "b": 1.7, "colour": grey_door, "name": "OFFICE"},
		{"a": 7.2, "b": 8.1, "colour": grey_door, "name": "STOCK ROOM"},
	])
	p.side(b2, 0.0, 0, 4.2, cream)
	p.side(b2, 9.0, 0, 4.2, cream)
	p.side(b2, 4.0, 0, 4.2, cream, [{"a": 2.4, "b": 3.3, "hinge": "a", "swing": 1, "colour": grey_door}])
	p.cross(b2, 0.0, 0, 9, cream, [], {"back": true})

	_street(p, st, front, brick)
	_shop(p, b1)
	_back(p, b2)
	_dress(p, b1, b2)
	# The pavement's ends go on (main.gd's "goto:"): left along the strip to the
	# gun store, right round the corner to Rose Hill Terrace (plans/street.gd).
	p.use_point(st, "TO THE GUN STORE", -3.25, 12.2, "goto:gunstore", 1.2, 1.9)
	p.use_point(st, "TO ROSE HILL", 10.45, 12.1, "goto:street", 1.2, 1.9)


static func _street(p: Node3D, st: int, front: Node3D, brick: Variant) -> void:
	var n: Node3D = p.node_of(st)
	var cream := Color(0.9, 0.86, 0.72)
	var green := Color(0.16, 0.36, 0.28)
	# The shop's own front: the name board in a lip with a moulded cap, lit by
	# gooseneck lamps; the flat upstairs; a bracketed cornice; stone up the corner.
	p.slab(front, true, 11.09, 0.4, 8.6, 2.45, 3.15, 0.06, green)
	Props.words(front, "MISS BEA'S CORNER GROCERY", p.pt(4.5, 11.125, 2.93), 0.26, cream)
	Props.words(front, "GROCERY  /  DELI  /  LOTTERY", p.pt(4.5, 11.125, 2.6), 0.15, cream, 0.0, false)
	for lip: Array in [[0.4, 8.6, 3.11, 3.15], [0.4, 8.6, 2.45, 2.49], [0.4, 0.44, 2.49, 3.11], [8.56, 8.6, 2.49, 3.11]]:
		p.slab(front, true, 11.1275, lip[0], lip[1], lip[2], lip[3], 0.015, cream)
	_proud(p, front, 0.3, 8.7, 3.15, 3.22, 0.12, cream)
	_proud(p, front, 0.25, 8.75, 3.22, 3.29, 0.17, green.darkened(0.3))
	var stone := Color(0.86, 0.82, 0.72)
	for u: float in [1.6, 4.5, 7.4]:
		In.gooseneck(p, front, u, 11.0, 3.42, green.darkened(0.2))
		In.front_window(p, front, u, 11.0, 3.75, 1.3, 1.3, u > 4.0, cream, stone, "", u)
	In.cornice(p, front, 11.0, 0.0, 9.13, 6.6, green, cream)
	In.quoins(p, front, 11.0, 9.13, 0.3, 5.7, stone)
	# The roll-down shutters, up: their boxes under the board and over the
	# door, the tracks they run down; and a tiled riser under the window.
	var galv := Color(0.66, 0.68, 0.7)
	_proud(p, front, 0.87, 6.13, 2.305, 2.45, 0.18, galv)
	_proud(p, front, 6.88, 8.02, 2.155, 2.3, 0.16, galv)
	for rail: Array in [[0.875, 0.94, 2.305], [6.06, 6.125, 2.305], [6.88, 6.94, 2.155], [7.96, 8.02, 2.155]]:
		_proud(p, front, rail[0], rail[1], 0.0, rail[2], 0.06, galv.darkened(0.15))
	_proud(p, front, 0.945, 6.055, 0.0, 0.63, 0.04, Kit.tex("in_tile", 0.5, Color(0.3, 0.5, 0.4), true, Color(0.42, 0.66, 0.52)))
	_proud(p, front, 0.94, 6.06, 0.63, 0.695, 0.09, stone)
	# Signs taped up in the window, and the one that is lit.
	var notes := [["MILK", 1.5, Color(0.95, 0.9, 0.55)], ["ICE", 2.5, Color(0.8, 0.9, 0.95)], ["COLD CUTS", 3.6, Color(0.95, 0.8, 0.75)]]
	for note: Array in notes:
		var u: float = note[1]
		p.slab(front, true, 11.025, u - 0.4, u + 0.4, 1.0, 1.5, 0.008, note[2])
		Props.words(front, note[0], p.pt(u, 11.032, 1.25), 0.11, Color(0.7, 0.12, 0.1))
	Props.neon(front, "OPEN", p.pt(5.1, 11.03, 1.95), 0.2, Color(1.0, 0.35, 0.3))
	Kit.block(n, Vector3(1.2, 0.06, 0.4), p.pt(7.45, 11.2), Color(0.8, 0.8, 0.78))
	# The row runs off to the left.
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	var formstone := Kit.tex("painted_block", 0.7, Color(0.62, 0.6, 0.56), true, Color(0.75, 0.78, 0.86))
	Props.rowhouse(p, n, -5.0, 11.0, formstone, false, true)
	Props.rowhouse(p, n, -10.0, 11.0, old_brick, true)
	# The corner: the shop's side wall with the flat's windows in it, the cross
	# street, the row beyond it.
	p.slab(n, false, 9.1, 0.0, 11.075, 0.0, 6.6, 0.06, brick)
	p.slab(n, true, 11.0, 9.0, 9.13, 0.0, 6.6, 0.15, brick)          # the front wall carried on to the corner
	for sv: float in [3.6, 7.6]:
		Kit.window(n, 1.1, 1.3, p.pt(9.13, sv, 4.4), cream, Kit.flat(Color(1.0, 0.84, 0.52), 0.55) if sv > 5.0 else Color(0.18, 0.21, 0.32), 2, Color(0.86, 0.82, 0.72), Vector3(0, 90, 0))
	Kit.box(n, Vector3(2.4, 0.3, 11.0), p.pt(10.3, 5.5, -0.15), Kit.tex("sidewalk", 2.4, Color(0.66, 0.64, 0.6)))
	var tar := Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27))
	Kit.box(n, Vector3(7.0, 0.3, 11.0), p.pt(15.0, 5.5, -0.29), tar)
	Kit.box(n, Vector3(7.0, 0.02, 2.85), p.pt(15.0, 12.325, -0.004), tar)
	for i in 6:
		Kit.box(n, Vector3(0.5, 0.01, 2.0), p.pt(12.2 + i * 1.1, 12.3, 0.008), Color(0.85, 0.85, 0.8))
	Props.rowhouse(p, n, 19.0, 11.0, old_brick, false, true)
	Props.rowhouse(p, n, 24.0, 11.0, formstone, true)
	var post: Node3D = p.prop(st, 10.75, 13.1, 0.0, 0.2, 0.2)
	Kit.cyl(post, 0.03, 3.0, Vector3(0, 1.5, 0), Color(0.45, 0.47, 0.5), Vector3.ZERO, 6)
	Kit.disc(post, 0.3, Vector3(0, 2.1, 0.04), Color(0.78, 0.12, 0.1), 0.02, 8)
	Props.words(post, "STOP", Vector3(0, 2.1, 0.055), 0.16, Color(0.95, 0.93, 0.88))
	Kit.box(post, Vector3(0.9, 0.16, 0.02), Vector3(0, 2.8, 0.05), Color(0.12, 0.35, 0.22))
	Props.words(post, "ARGONNE DR", Vector3(0, 2.8, 0.063), 0.09, Color(0.95, 0.93, 0.88))
	Kit.box(post, Vector3(0.02, 0.16, 0.9), Vector3(0.05, 2.97, 0), Color(0.12, 0.35, 0.22))
	Props.words(post, "WILSBY AVE", Vector3(0.063, 2.97, 0), 0.09, Color(0.95, 0.93, 0.88), 90.0)
	# On the pavement.
	Props.ice_box(p, st, 0.3, 11.44)
	Props.payphone(p, st, 8.45, 11.08)
	Props.bin(p, st, 6.4, 11.45)
	Props.street_lamp(p, st, 2.6, 13.05)
	Props.hydrant(p, st, 5.4, 13.0)


## A piece standing `d` proud of the shop's street face, its back 1 cm into the wall.
static func _proud(p: Node3D, n: Node3D, a: float, b: float, y0: float, y1: float, d: float, look: Variant) -> void:
	p.slab(n, true, F + (d - 0.01) * 0.5, a, b, y0, y1, d + 0.01, look)


static func _shop(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Behind the plexiglass: the counter runs from the front wall most of the way
	# back, the cigarettes and the lottery are out of reach behind it.
	var counter := Props.counter(p, b, 2.5, 8.6, 90.0, 4.6, 0.6, 1.05, Color(0.5, 0.42, 0.3), Color(0.8, 0.78, 0.7))
	Props.screen(counter, 4.6, 0.2)
	Props.till(counter, Vector3(0.6, 1.05, -0.08), 180.0)
	Props.lotto(counter, Vector3(-1.3, 1.05, -0.05))
	Kit.box(counter, Vector3(0.5, 0.012, 0.3), Vector3(0.0, 1.056, 0.02), Color(0.2, 0.3, 0.2))
	Props.words(counter, "NO CREDIT", Vector3(1.5, 1.9, 0.222), 0.1, Color(0.75, 0.12, 0.1))
	Props.shelves(p, b, 0.21, 8.6, 90.0, 3.6, "goods", Color(0.3, 0.3, 0.32), 1.9, 0.26)
	Props.chair(p, b, 1.3, 10.3, 90.0)
	p.person(b, "clerk", 1.45, 8.5, {"face": "happy"})
	# Along the back wall: the coolers.
	Props.fridge_case(p, b, 4.7, 4.63, 0.0, 4)
	Props.words(n, "STAFF ONLY", p.pt(7.65, 4.29, 2.3), 0.1, Color(0.3, 0.3, 0.32))
	Props.clock(p, b, 2.4, 4.28)
	# Two runs of shelves, front to back.
	Props.gondola(p, b, 4.35, 7.4, 90.0, 2.6)
	Props.gondola(p, b, 6.25, 7.4, 90.0, 2.6)
	# Under the window: the ice-cream chest and the papers.
	Props.chest_freezer(p, b, 3.6, 10.55, 180.0)
	Props.news_rack(p, b, 5.2, 10.66, 180.0)
	# Down the right wall: coffee, and the cash machine by the door.
	Props.coffee(p, b, 8.6, 6.0, 270.0)
	Props.atm(p, b, 8.65, 9.9, 270.0)
	Props.poster(p, b, 8.92, 8.0, 270.0, 0.6, 0.8, Color(0.85, 0.7, 0.2), "LOTTERY", 1.7)


static func _back(p: Node3D, b: int) -> void:
	# The office: a desk with the camera screen, the safe, the files.
	Props.desk(p, b, 1.6, 0.5, 0.0, Props.WOOD, 3)
	Props.safe(p, b, 0.36, 2.9, 90.0)
	Props.files(p, b, 3.2, 0.4, 0.0, 2)
	Props.poster(p, b, 3.2, 0.08, 0.0, 0.4, 0.55, Color(0.85, 0.82, 0.7), "", 1.8)
	Props.clock(p, b, 0.6, 0.08)
	# The stock room.
	Props.shelves(p, b, 6.9, 0.31, 0.0, 3.8)
	Props.case_stack(p, b, 6.2, 2.0, 0.0, 3, 2)
	Props.boxes(p, b, 8.3, 1.5, 3)
	Props.bucket(p, b, 4.5, 0.5)


## The rooms' walls, floors and lights. The shop is the yellow block over green
## tiles, framed in the green of the sign; the office behind it is wood-look
## panelling and mustard paper over a rust carpet; the stock room is grey block
## with a hazard band.
static func _dress(p: Node3D, b1: int, b2: int) -> void:
	var n2: Node3D = p.node_of(b2)
	var green := Color(0.16, 0.36, 0.28)
	var black := Color(0.13, 0.13, 0.15)
	var walnut := Color(0.36, 0.22, 0.13)
	# The shop: tiles to the shoulder, a black cove at the floor, the doors to
	# the back in green architraves, a green border round the lino.
	var shop := {"lower": Kit.tex("in_tile", 0.6, Color(0.5, 0.75, 0.6), true, Color(0.62, 0.86, 0.7)), "dado": green, "dado_y": 1.2,
			"skirt": black, "skirt_h": 0.1, "cornice": green.lightened(0.12), "surround": green}
	In.room_walls(p, b1, 0.0, 4.2, 9.0, 11.0, shop, [{"a": 0.8, "b": 1.7}, {"a": 7.2, "b": 8.1}], [], [])
	In.border(p, b1, 0.0, 4.2, 9.0, 11.0, Color(0.2, 0.42, 0.32), 0.3)
	In.mat(p, b1, 7.45, 10.5, 1.1, 0.7, Color(0.22, 0.22, 0.24), Color(0.12, 0.12, 0.13))
	# A strip light over the coolers; the cigarettes' lit header over the shelves
	# behind the counter; the licence and the round mirror the till watches by.
	In.wall_strip(p, b1, 4.7, 4.275, 0.0, 2.6, 2.45)
	In.wall_strip(p, b1, 8.925, 6.0, 270.0, 1.4, 2.45)
	In.lightbox(p, b1, 0.075, 8.6, 90.0, 3.5, 0.34, 2.12, [Color(0.9, 0.18, 0.16), Color(0.97, 0.97, 0.94), Color(0.2, 0.4, 0.85),
			Color(0.95, 0.75, 0.15), Color(0.2, 0.6, 0.35), Color(0.9, 0.18, 0.16), Color(0.55, 0.3, 0.7)])
	In.picture(p, b1, 0.085, 5.5, 90.0, 0.42, 0.52, "certificate", Color(0.2, 0.2, 0.22), 1.65)
	In.mirror(p, b1, 0.075, 4.275, 45.0)
	In.pegboard(p, b1, 2.5, 4.275, 0.0, 1.1, 0.62, 1.62, "snacks")
	# The office: panelling to a rail, flowered paper over it, a cork board, a
	# map of the deliveries, a green lamp over the desk.
	var office := {"lower": Kit.tex("in_planks", 1.2, Color(0.55, 0.38, 0.24), true, Color(0.8, 0.56, 0.36)),
			"upper": Kit.tex("in_flower", 0.7, Color(0.9, 0.78, 0.5), true, Color(1.0, 0.86, 0.48)),
			"dado": walnut, "dado_y": 1.3, "skirt": walnut, "cornice": Color(0.96, 0.92, 0.8), "surround": walnut}
	In.room_walls(p, b2, 0.0, 0.0, 4.0, 4.2, office, [], [], [{"a": 2.4, "b": 3.3}])
	In.corkboard(p, b2, 0.085, 1.6, 90.0, 0.9, 0.6, 1.72)
	In.picture(p, b2, 3.915, 1.2, 270.0, 0.7, 0.5, "map", walnut, 1.72)
	In.pendant(p, b2, 1.6, 1.25, 1.95, Color(0.2, 0.42, 0.3), "cone", In.WARM, 0.35)
	# The stock room: grey block under a hazard band, a strip light over the
	# shelves, a bare bulb, the fuse box, tools on a pegboard, a line on the floor.
	var stock := {"lower": Kit.tex("painted_block", 1.2, Color(0.55, 0.57, 0.6), true, Color(0.7, 0.74, 0.8)),
			"dado": Kit.tex("in_hazard", 0.5, Color(0.9, 0.75, 0.15)), "dado_y": 1.2, "skirt": black, "skirt_h": 0.1, "surround": black}
	In.room_walls(p, b2, 4.0, 0.0, 9.0, 4.2, stock, [], [{"a": 2.4, "b": 3.3}], [])
	In.wall_strip(p, b2, 6.9, 0.075, 0.0, 2.4, 2.45)
	In.pendant(p, b2, 7.2, 2.6, 2.05, Props.DARK, "bulb", In.WARM, 0.3)
	In.pegboard(p, b2, 8.925, 3.0, 270.0, 1.0, 0.7, 1.65, "tools")
	In.mat(p, b2, 6.9, 0.85, 3.8, 0.06, Color(0.95, 0.78, 0.15))
	var fuse := Kit.group(n2, p.pt(4.075, 1.0), Vector3(0, 90, 0))
	Kit.box(fuse, Vector3(0.42, 0.56, 0.1), Vector3(0, 1.58, 0.05), Color(0.58, 0.6, 0.6))
	Kit.box(fuse, Vector3(0.36, 0.5, 0.008), Vector3(0, 1.58, 0.104), Color(0.66, 0.68, 0.68))
	Kit.box(fuse, Vector3(0.03, 0.08, 0.02), Vector3(0.14, 1.58, 0.115), Props.DARK)
	Kit.cyl(fuse, 0.018, 0.95, Vector3(0, 2.335, 0.04), Props.STEEL, Vector3.ZERO, 6)
	# Thresholds in the doorways out of the shop and between the back rooms.
	Kit.box(n2, Vector3(0.9, 0.012, 0.19), p.pt(1.25, 4.2, 0.006), In.BRASS)
	Kit.box(n2, Vector3(0.9, 0.012, 0.19), p.pt(7.65, 4.2, 0.006), Props.STEEL)
	Kit.box(n2, Vector3(0.19, 0.012, 0.9), p.pt(4.0, 2.85, 0.006), Props.STEEL)
