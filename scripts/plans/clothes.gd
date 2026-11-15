extends RefCounted
## The clothing store: Fresh Threads, a sneaker and clothes shop on the ground
## floor of a two-storey block, a roll-down shutter over its front and three
## dressed dummies in the window. 10 x 11 m inside, two bands from the street
## back:
##
##   the sales floor
##   fitting rooms | stock room
##
## The sales floor is laid out for the camera: the jacket rail and the jeans
## cubbies down the left wall, the hat wall, the sneaker wall and the glass
## counter (the clerk, and the boxes of sizes behind him) along the back. The
## middle is kept low: the shirt table with its jersey stand, the try-on bench
## and its foot mirror; a round rack of sweats and a wall mirror stand out of
## the way down the right wall. In front of each display is a spot where E tries
## something on (the "outfit:*" use points: main.gd's `_use_point`), and the
## three-way mirror by the fitting booths puts him back in his own clothes.
## The fitting rooms are through the arch in the back wall; the stock room is
## through the door at the end of them.
##
## Invented names and signs (placeholders): FRESH THREADS (the shop), "SNEAKERS
## - HATS - JEANS - JACKETS" on the shutter box, the neon OPEN and NEW KICKS,
## the SALE card, the "SALE / NEW KICKS IN" board on the pavement, the display
## signs HATS, JACKETS, DENIM and KICKS, "2 FOR $15", the SUMMER JAM poster,
## FITTING ROOMS, "LIMIT 3 ITEMS", "NO REFUNDS - EXCHANGE ONLY", STAFF ONLY,
## the jersey numbers, and next door CHECKS CASHED with "MONEY ORDERS - FOOD
## STAMPS" on its barred window.
##
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 11.

const Props := preload("res://scripts/props.gd")
const Wear := preload("res://scripts/props_clothes.gd")
const In := preload("res://scripts/props_in.gd")
const Service := preload("res://scripts/props_service.gd")      # the stock room's back door

const PURPLE := Color(0.36, 0.14, 0.5)
const YELLOW := Color(1.0, 0.85, 0.2)
const RED := Color(0.86, 0.14, 0.12)
const ROYAL := Color(0.14, 0.3, 0.82)
const GREEN := Color(0.1, 0.52, 0.3)


static func build(p: Node3D) -> void:
	p.setup("CLOTHING STORE", 10.0, 11.0)
	var teal := Kit.tex("painted_block", 1.2, Color(0.5, 0.78, 0.76), true, Color(0.62, 0.92, 0.88))
	var lilac := Kit.tex("painted_block", 1.2, Color(0.6, 0.5, 0.8), true, Color(0.66, 0.56, 1.0))
	var cream := Kit.tex("painted_block", 1.2, Color(0.72, 0.72, 0.64), true, Color(0.76, 0.8, 1.0))
	var tiles := Kit.tex("in_check", 0.7, Color(0.5, 0.82, 0.8), true, Color(0.64, 0.96, 0.93))
	var carpet := Kit.tex("carpet", 2.0, Color(0.42, 0.22, 0.34), true, Color(0.78, 0.5, 0.72))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var face := Kit.tex("stucco", 2.0, Color(0.3, 0.55, 0.55), true, Color(0.55, 0.85, 0.85))
	var tube := Color(1.0, 0.98, 0.92)
	var chrome := Color(0.7, 0.72, 0.76)
	var grey_door := Color(0.5, 0.52, 0.55)

	var st: int = p.street(-4.0, 14.0)
	var b1: int = p.band()
	var b2: int = p.band()
	p.arrive = p.pt(7.85, 12.2)

	p.room("SALES FLOOR", b1, 0, 3.8, 10, 11, tiles, {"light": tube, "energy": 0.75})
	p.room("FITTING ROOMS", b2, 0, 0, 5.6, 3.8, carpet, {"light": Color(1.0, 0.9, 0.78), "energy": 0.5})
	p.room("STOCK ROOM", b2, 5.6, 0, 10, 3.8, concrete, {"light": tube, "energy": 0.4})

	var front: Node3D = p.cross(b1, 11.0, 0, 10, face, [
		{"a": 1.4, "b": 6.6, "kind": "window", "sill": 0.45, "head": 2.4, "frame": chrome},
		{"a": 7.4, "b": 8.3, "head": 2.2, "colour": Color(0.25, 0.27, 0.32), "frame": chrome},
	], {"h": 6.2})
	_glaze(p.doors[p.doors.size() - 1], 0.88, 2.188)
	p.side(b1, 0.0, 3.8, 11, teal)
	p.side(b1, 10.0, 3.8, 11, teal)
	p.cross(b2, 3.8, 0, 10, lilac, [{"a": 1.0, "b": 2.2, "kind": "arch", "head": 2.25, "frame": PURPLE}])
	p.side(b2, 0.0, 0, 3.8, lilac)
	p.side(b2, 10.0, 0, 3.8, cream)
	p.side(b2, 5.6, 0, 3.8, cream, [{"a": 2.5, "b": 3.4, "hinge": "a", "swing": 1, "colour": grey_door, "frame": Props.IRON, "name": "STOCK ROOM"}])
	p.cross(b2, 0.0, 0, 5.6, lilac, [], {"back": true})
	p.cross(b2, 0.0, 5.6, 10, cream, [], {"back": true})

	_street(p, st, front)
	_floor(p, b1)
	_back(p, b2)
	_dress(p, b1, b2)
	# The pavement's ends go on along the strip (main.gd's "goto:"): left past the
	# check-cashing place to the club, right past the row to the studio.
	p.use_point(st, "TO THE CLUB", -3.25, 12.2, "goto:club", 1.2, 1.9)
	p.use_point(st, "TO THE STUDIO", 13.25, 12.2, "goto:studio", 1.2, 1.9)


## The shop door is mostly glass, with a push bar: added to the plain leaf
## place.gd made (its hinge on the right, so the leaf runs to -x).
static func _glaze(door: Node3D, w: float, h: float) -> void:
	Kit.pane(Kit.box(door.leaf, Vector3(w - 0.16, 1.5, 0.116), Vector3(-w * 0.5, 1.25, 0), Kit.flat(Color(0.6, 0.76, 0.8), 0.25)))      # combat: a shot breaks it
	Kit.box(door.leaf, Vector3(w - 0.22, 0.05, 0.14), Vector3(-w * 0.5, 1.02, 0), Color(0.78, 0.8, 0.84))


## Painted block that comes out the colour asked for.
static func _block(c: Color) -> Material:
	return Kit.tex("block_plain", 1.2, c, true, c)


## The rooms' walls, floors and lights (props_in.gd): the sales floor in the
## shop's purple and yellow under confetti paper, on a teal floor, a runner from
## the door to the counter; the fitting rooms in flowered paper over plum
## panelling, gold and cream, lamps by the mirror; the stock room plain block
## and a bare bulb. The display spotlights are the displays' own (props_clothes.gd).
static func _dress(p: Node3D, b1: int, b2: int) -> void:
	var n1: Node3D = p.node_of(b1)
	var plum := Color(0.3, 0.12, 0.4)
	var cream := Color(0.96, 0.93, 0.86)
	# The sales floor. The wall mirror on the right wall hangs flat on it, so the
	# paper stops round it (a bare "window" the mirror's size).
	var sales := {"lower": _block(Color(0.5, 0.26, 0.66)), "dado": YELLOW, "dado_h": 0.08,
			"upper": Kit.tex("in_memphis", 1.6, Color(0.96, 0.95, 0.9), true, Color(1, 1, 1)), "skirt": plum}
	In.room_walls(p, b1, 0, 3.8, 10, 11, sales, [{"a": 1.0, "b": 2.2, "kind": "arch", "head": 2.25}], [],
			[{"a": 6.403, "b": 6.897, "kind": "window", "sill": 0.353, "head": 1.947, "bare": true}])
	In.border(p, b1, 0, 3.8, 10, 11, plum, 0.26)
	In.mat(p, b1, 7.85, 7.9, 0.9, 4.4, Color(0.5, 0.26, 0.66), YELLOW)       # the runner, the door to the counter
	In.mat(p, b1, 7.85, 10.46, 1.1, 0.64, Color(0.18, 0.17, 0.2), YELLOW)    # the doormat
	In.neon_shape(n1, [[Vector2(0.07, 0.4), Vector2(-0.1, 0.02), Vector2(0.06, 0.04), Vector2(-0.08, -0.4)]], p.pt(0.5, 3.935, 1.62), Color(1.0, 0.3, 0.62))
	Props.poster(p, b1, 7.55, 3.88, 0.0, 0.46, 0.7, GREEN, "", 1.55)
	# The fitting rooms.
	var fit := {"lower": Kit.tex("in_panel", 0.9, plum, true, Color(0.5, 0.3, 0.62)), "dado": Wear.GOLD,
			"upper": Kit.tex("in_flower", 0.8, Color(0.94, 0.78, 0.9), true, Color(1.0, 0.84, 0.96)),
			"skirt": plum, "cornice": cream, "surround": cream}
	In.room_walls(p, b2, 0, 0, 5.6, 3.8, fit, [], [], [{"a": 2.5, "b": 3.4}])
	In.border(p, b2, 0, 0, 5.6, 3.8, plum, 0.2)
	In.picture(p, b2, 0.085, 1.45, 90.0, 0.44, 0.6, "face", Wear.GOLD, 1.6)
	for v: float in [0.95, 1.95]:
		In.sconce(p, b2, 0.085, v, 90.0, "shade", 2.05)
	# The stock room.
	var stock := {"lower": _block(Color(0.52, 0.54, 0.58)), "dado": YELLOW, "dado_h": 0.1,
			"upper": _block(Color(0.94, 0.92, 0.84)), "skirt": Color(0.22, 0.22, 0.24), "surround": Color(0.6, 0.62, 0.66)}
	In.room_walls(p, b2, 5.6, 0, 10, 3.8, stock, [], [{"a": 2.5, "b": 3.4}], [])
	In.pegboard(p, b2, 5.685, 1.35, 90.0, 1.0, 0.7, 1.55, "tools")
	In.pendant(p, b2, 7.8, 1.9, 2.25, Color(0.3, 0.3, 0.32), "bulb")
	for k in 4:      # a keep-clear box where the door swings, hatched
		var box: Array = [[6.15, 2.47, 0.84, 0.04], [6.15, 3.43, 0.84, 0.04], [6.55, 2.95, 0.04, 0.92], [5.75, 2.95, 0.04, 0.92]][k]
		In.mat(p, b2, box[0], box[1], box[2], box[3], YELLOW)
	for c: float in [2.6, 2.84, 3.08, 3.32, 3.56, 3.8]:      # each bar of the hatching cut to the box (u - v = c)
		var u0 := maxf(5.77, c + 2.49)
		var u1 := minf(6.53, c + 3.41)
		In.hatch(p, b2, (u0 + u1) * 0.5, (u0 + u1) * 0.5 - c, 1, 0.05, (u1 - u0) * 1.414 - 0.07, 0.0, YELLOW, 45.0)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var steel := Color(0.56, 0.58, 0.62)
	# The roll-down shutter: its housing over the window and the door, the
	# bottom slat showing under it, a guide rail down each side of each opening.
	p.slab(front, true, 11.26, 1.15, 8.55, 2.5, 2.86, 0.3, steel)
	p.slab(front, true, 11.415, 1.17, 8.53, 2.52, 2.55, 0.012, steel.darkened(0.2))
	p.slab(front, true, 11.415, 1.17, 8.53, 2.81, 2.84, 0.012, steel.darkened(0.2))
	Props.words(front, "SNEAKERS  -  HATS  -  JEANS  -  JACKETS", p.pt(4.85, 11.425, 2.68), 0.15, PURPLE)
	p.slab(front, true, 11.2, 1.25, 8.45, 2.46, 2.5, 0.08, steel.darkened(0.35))
	for u: float in [1.2, 6.8, 7.2, 8.5]:
		Kit.box(front, Vector3(0.06, 2.46, 0.07), p.pt(u, 11.145, 1.23), steel)
	# The name: a lit box across the front, over the shutter.
	Props.sign_box(front, "FRESH THREADS", p.pt(4.85, 11.14, 3.4), Vector2(7.6, 0.86), PURPLE, YELLOW, 0.0, 0.55, 0.56)
	# Under the window: a tiled stall riser on a dark plinth, a stone sill on it.
	var stone := Color(0.93, 0.9, 0.82)
	p.slab(front, true, 11.095, 1.36, 6.64, 0.06, 0.34, 0.04, Kit.tex("in_tile", 0.5, PURPLE, true, Color(0.72, 0.5, 0.95)))
	p.slab(front, true, 11.1, 1.33, 6.67, 0.0, 0.06, 0.05, Color(0.16, 0.14, 0.2))
	p.slab(front, true, 11.12, 1.3, 6.7, 0.34, 0.39, 0.09, stone)
	# Upstairs: a stone belt course over the name, three windows on it (the
	# middle and right ones lit, an air conditioner in the left), quoins up both
	# corners, a cornice band, and a parapet stepped up in the middle with a
	# tile diamond in it and one each side.
	var mint := Kit.tex("stucco", 2.0, Color(0.3, 0.55, 0.55), true, Color(0.55, 0.85, 0.85))
	p.slab(front, true, 11.105, 0.01, 9.99, 3.96, 4.08, 0.06, stone)
	for k in 3:
		In.front_window(p, front, [1.9, 5.0, 8.1][k], 11.0, 4.45, 1.2, 1.3, k > 0, Color(0.95, 0.95, 0.93), stone, "ac" if k == 0 else "", 2.0)
	In.quoins(p, front, 11.0, 0.0, 0.0, 6.0, stone, -1.0, false)
	In.quoins(p, front, 11.0, 9.99, 0.0, 6.0, stone, 1.0, false)      # their ends 1 cm short of the wall's
	p.slab(front, true, 11.13, 0.0, 10.0, 6.03, 6.2, 0.11, stone)
	p.slab(front, true, 11.0, 0.0, 10.0, 6.2, 6.7, 0.15, mint)
	p.slab(front, true, 11.0, 0.0, 10.0, 6.7, 6.8, 0.27, stone)
	p.slab(front, true, 11.0, 3.3, 6.7, 6.8, 7.3, 0.15, mint)
	p.slab(front, true, 11.0, 3.24, 6.76, 7.3, 7.4, 0.27, stone)
	for gem: Vector3 in [Vector3(5.0, 7.05, 0.28), Vector3(1.6, 6.45, 0.2), Vector3(8.4, 6.45, 0.2)]:
		var tile := Kit.group(front, p.pt(gem.x, 11.075, gem.y), Vector3(0, 0, 45))
		Kit.box(tile, Vector3(gem.z, gem.z, 0.03), Vector3(0, 0, 0.015), PURPLE)
		Kit.box(tile, Vector3(gem.z * 0.5, gem.z * 0.5, 0.03), Vector3(0, 0, 0.03), YELLOW)
	# In the window: the neon, a sale card. The dummies stand on the platform
	# inside (built with the floor), but they belong to the front: from inside
	# they go when the front does, and only the platform is left.
	Props.neon(front, "OPEN", p.pt(6.05, 11.03, 2.1), 0.2, Color(1.0, 0.3, 0.3))
	Props.neon(front, "NEW KICKS", p.pt(2.45, 11.03, 2.12), 0.17, Color(0.4, 0.8, 1.0))
	p.slab(front, true, 11.025, 5.95, 6.45, 0.55, 0.9, 0.008, YELLOW)
	Props.words(front, "SALE", p.pt(6.2, 11.032, 0.725), 0.13, RED)
	Wear.mannequin(front, p.pt(2.55, 10.5, 0.33), 14.0, RED, Wear.DARK, Wear.DARK, Wear.DENIM[0], [Wear.WHITE, RED], true)
	Wear.mannequin(front, p.pt(4.0, 10.45, 0.33), 0.0, ROYAL, YELLOW, RED, Wear.DENIM[4], [Color(0.85, 0.66, 0.36), Color(0.42, 0.28, 0.16)], false, true)
	Wear.mannequin(front, p.pt(5.45, 10.5, 0.33), -14.0, GREEN, YELLOW, YELLOW, Wear.DENIM[3], [Wear.DARK, YELLOW], true)
	# Next door on the left: a check-cashing place, its window and door in stone,
	# a brick parapet on top. On the right: the row.
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.3, 0.24), true, Color(0.9, 0.8, 0.72))
	p.slab(n, true, 11.0, -12.0, 0.0, 0.0, 4.2, 0.15, brick)
	p.slab(n, true, 11.12, -9.12, -3.28, 2.4, 2.58, 0.09, stone)
	p.slab(n, true, 11.13, -9.15, -3.25, 0.5, 0.6, 0.11, stone)
	for u: float in [-2.96, -1.88]:
		p.slab(n, true, 11.11, u, u + 0.14, 0.0, 2.12, 0.07, stone)
	p.slab(n, true, 11.12, -3.0, -1.7, 2.12, 2.3, 0.09, stone)
	p.slab(n, true, 11.0, -12.0, 0.0, 4.2, 4.72, 0.15, brick)
	p.slab(n, true, 11.0, -12.0, -0.01, 4.72, 4.82, 0.27, stone)
	p.slab(n, true, 11.085, -9.0, -3.4, 0.7, 2.3, 0.03, Kit.flat(Color(0.95, 0.95, 0.85), 0.8))
	for i in 15:
		var bu := -8.86 + i * 0.37
		p.slab(n, true, 11.12, bu, bu + 0.04, 0.66, 2.34, 0.03, Props.IRON)
	p.slab(n, true, 11.125, -9.0, -3.4, 2.3, 2.36, 0.045, Props.IRON)
	p.slab(n, true, 11.125, -9.0, -3.4, 0.64, 0.7, 0.045, Props.IRON)
	Props.words(n, "MONEY ORDERS  -  FOOD STAMPS", p.pt(-6.2, 11.155, 1.95), 0.15, Color(0.75, 0.1, 0.1))
	p.slab(n, true, 11.1, -2.8, -1.9, 0.0, 2.1, 0.03, Color(0.45, 0.47, 0.5))
	Props.sign_box(n, "CHECKS CASHED", p.pt(-6.0, 11.14, 3.05), Vector2(5.2, 0.62), YELLOW, Color(0.1, 0.2, 0.45), 0.0, 0.6)
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	Props.rowhouse(p, n, 10.0, 11.0, old_brick, false, true)
	Props.rowhouse(p, n, 15.0, 11.0, Kit.tex("painted_block", 0.7, Color(0.62, 0.6, 0.56), true, Color(0.75, 0.78, 0.86)), true)
	# On the pavement.
	Kit.block(n, Vector3(1.1, 0.02, 0.5), p.pt(7.85, 11.35), Wear.DARK)
	Props.street_lamp(p, st, 3.2, 13.05)
	Props.bin(p, st, 0.5, 11.45)
	Props.hydrant(p, st, 11.2, 13.0)
	Props.payphone(p, st, -0.8, 11.08)
	var board: Node3D = p.prop(st, 6.2, 11.75, -20.0, 0.6, 0.45)
	for s: float in [-1.0, 1.0]:
		Kit.box(board, Vector3(0.56, 0.9, 0.03), Vector3(0, 0.45, s * 0.12), Wear.DARK, Vector3(-s * 14.0, 0, 0))
	var face_up := Kit.group(board, Vector3(0, 0.45, 0.12), Vector3(-14, 0, 0))
	Props.words(face_up, "SALE", Vector3(0, 0.2, 0.025), 0.14, YELLOW)
	Props.words(face_up, "NEW KICKS IN", Vector3(0, 0.0, 0.025), 0.07, Wear.WHITE)


static func _floor(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var ink := Color(0.25, 0.12, 0.35)
	# Down the left wall: the jacket rail, then the jeans.
	Wear.jacket_rail(p, b, 0.385, 5.8, 90.0, 3.4)
	Wear.jeans_wall(p, b, 0.285, 9.0, 90.0, 2.0)
	Props.poster(p, b, 0.08, 7.75, 90.0, 0.36, 0.56, Color(0.98, 0.76, 0.1), "", 1.75)
	# Along the back: the hat wall, the sneaker wall; the counter, the clerk and the sizes behind him.
	Wear.hat_wall(p, b, 3.5, 4.085, 0.0, 1.8)
	Wear.sneaker_wall(p, b, 5.9, 4.075, 0.0, 2.6)
	Wear.box_shelves(p, b, 8.9, 4.07, 0.0, 2.0, 1.9)
	Props.boombox(n, p.pt(8.45, 4.07, 1.875), 0.0)
	Wear.glass_counter(p, b, 8.92, 5.3, 0.0, 1.98, 0.6)
	p.person(b, "clerk", 8.6, 4.62, {"name": "CLERK"})
	p.person(b, "huff", 2.3, 7.3, {"name": "HUFF DADDY", "face": "smug"})      # a customer (a working name): he is here every day
	Wear.security_mirror(n, p.pt(9.8, 3.95, 2.55), -45.0)
	Props.words(n, "NO REFUNDS  -  EXCHANGE ONLY", p.pt(8.55, 3.885, 2.42), 0.09, ink)
	# Down the right wall, by the door: a mirror, a poster, a round rack of tracksuits.
	Wear.wall_mirror(p, b, 9.915, 6.65, 270.0)
	Props.poster(p, b, 9.92, 8.1, 270.0, 0.7, 0.95, Color(0.98, 0.5, 0.1), "SUMMER JAM", 1.65)
	Wear.round_rack(p, b, 9.25, 9.3)
	Props.words(n, "FITTING ROOMS", p.pt(1.6, 3.885, 2.55), 0.14, ink)
	Props.poster(p, b, 2.42, 3.88, 0.0, 0.26, 0.4, Color(0.14, 0.3, 0.82), "", 1.4)
	# The middle: kept low, so he is never hidden.
	Wear.jersey_rack(p, b, 3.9, 6.9, 0.0)
	Wear.shirt_table(p, b, 3.9, 7.8, 0.0)
	Wear.try_bench(p, b, 6.1, 6.4, 0.0)
	Wear.foot_mirror(p, b, 6.55, 6.86, 0.0)
	# Under the window: the platform the dummies stand on, with a few things on it.
	var stage: Node3D = p.prop(b, 4.0, 10.48, 0.0, 5.2, 0.8)
	Kit.block(stage, Vector3(5.2, 0.3, 0.8), Vector3.ZERO, Wear.DARK)
	Kit.block(stage, Vector3(5.24, 0.03, 0.84), Vector3(0, 0.3, 0), Kit.tex("carpet", 1.5, Color(0.6, 0.15, 0.2), true, Color(1.0, 0.45, 0.5)))
	Kit.block(stage, Vector3(0.26, 0.26, 0.26), Vector3(-0.72, 0.33, 0.05), Wear.WHITE)
	Wear.sneaker(stage, Vector3(-0.72, 0.59, 0.05), -20.0, Wear.WHITE, RED)
	Wear.shoe_box(stage, Vector3(0.75, 0.33, 0.1), 3.0)
	Wear.sneaker(stage, Vector3(0.75, 0.455, 0.1), 15.0, Wear.DARK, YELLOW)
	Wear.tee_stack(stage, Vector3(2.1, 0.33, 0.05), ROYAL, 4, 5.0)
	# The spots where he tries things on (main.gd acts on the ids).
	p.use_point(b, "TRY A JACKET", 1.4, 5.8, "outfit:jacket")
	p.use_point(b, "TRY TROUSERS", 1.2, 9.0, "outfit:trousers")
	p.use_point(b, "TRY A HAT", 3.5, 5.0, "outfit:hat")
	p.use_point(b, "TRY SHOES", 5.9, 4.98, "outfit:shoes")
	p.use_point(b, "TRY A SHIRT", 3.9, 8.9, "outfit:shirt")


static func _back(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var ink := Color(0.25, 0.12, 0.35)
	# The fitting rooms: the three-way mirror, three booths, a bench to wait on.
	Wear.three_way_mirror(p, b, 0.95, 0.3, 0.0)
	Wear.fitting_booths(p, b, 3.65, 0.725, 0.0, 3, 1.2, 1.3)
	Props.bench(p, b, 0.3, 2.7, 90.0, 1.1, Props.WOOD, true, 0.42)
	Props.words(n, "LIMIT 3 ITEMS", p.pt(0.085, 2.7, 1.55), 0.09, ink, 90.0)
	Props.words(n, "STAFF ONLY", p.pt(5.515, 2.95, 2.35), 0.08, ink, 270.0)
	p.use_point(b, "HIS OWN CLOTHES", 0.95, 1.25, "outfit:reset")
	# The stock room: shelves of boxes, the sizes in stacks, new stock on a rail.
	# Its steel back door between them, out to the service alley behind the strip
	# (plans/service.gd: E goes out there, and its CLOTHING STORE door comes back in).
	Wear.garment_rack(p, b, 6.35, 0.38, 0.0, 1.2)
	Props.shelves(p, b, 8.95, 0.31, 0.0, 1.7, "boxes")
	Service.steel_door(Kit.group(p.node_of(b), p.pt(7.525, 0.084), Vector3.ZERO, "BackDoor"))
	p.use_point(b, "SERVICE ALLEY", 7.525, 0.7, "goto:service", 1.0, 2.0)
	Wear.shoe_boxes(p, b, 9.62, 2.2, 270.0, 6, 7)
	Props.boxes(p, b, 8.4, 1.0, 3)
	Props.clock(p, b, 6.55, 0.08, 0.0, 2.45)
