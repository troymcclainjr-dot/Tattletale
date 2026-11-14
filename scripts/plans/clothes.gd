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
	var lino := Kit.tex("lino", 1.2, Color(0.7, 0.7, 0.72), true, Color(0.95, 0.95, 1.0))
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

	p.room("SALES FLOOR", b1, 0, 3.8, 10, 11, lino, {"light": tube, "energy": 0.75})
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


## The shop door is mostly glass, with a push bar: added to the plain leaf
## place.gd made (its hinge on the right, so the leaf runs to -x).
static func _glaze(door: Node3D, w: float, h: float) -> void:
	Kit.box(door.leaf, Vector3(w - 0.16, 1.5, 0.116), Vector3(-w * 0.5, 1.25, 0), Kit.flat(Color(0.6, 0.76, 0.8), 0.25))
	Kit.box(door.leaf, Vector3(w - 0.22, 0.05, 0.14), Vector3(-w * 0.5, 1.02, 0), Color(0.78, 0.8, 0.84))


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var steel := Color(0.56, 0.58, 0.62)
	var cream := Color(0.9, 0.86, 0.76)
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
	# Upstairs: two windows, one lit, and a cornice.
	for u: float in [2.3, 7.7]:
		p.slab(front, true, 11.08, u - 0.75, u + 0.75, 4.1, 5.5, 0.03, cream)
		p.slab(front, true, 11.095, u - 0.65, u + 0.65, 4.2, 5.4, 0.03, Kit.flat(Color(1.0, 0.82, 0.55), 0.5) if u > 5.0 else Color(0.2, 0.24, 0.32))
		p.slab(front, true, 11.11, u - 0.64, u + 0.64, 4.77, 4.83, 0.03, cream)
	p.slab(front, true, 11.0, 0.0, 10.0, 6.2, 6.5, 0.4, Color(0.3, 0.28, 0.27))
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
	# Next door on the left: a check-cashing place. On the right: the row.
	p.slab(n, true, 11.0, -12.0, 0.0, 0.0, 4.2, 0.15, Kit.tex("brick", 1.5, Color(0.5, 0.3, 0.24), true, Color(0.9, 0.8, 0.72)))
	p.slab(n, true, 11.085, -9.0, -3.4, 0.7, 2.3, 0.03, Kit.flat(Color(0.95, 0.95, 0.85), 0.8))
	for i in 15:
		var bu := -8.86 + i * 0.37
		p.slab(n, true, 11.12, bu, bu + 0.04, 0.66, 2.34, 0.03, Props.IRON)
	p.slab(n, true, 11.125, -9.0, -3.4, 2.3, 2.36, 0.045, Props.IRON)
	p.slab(n, true, 11.125, -9.0, -3.4, 0.64, 0.7, 0.045, Props.IRON)
	Props.words(n, "MONEY ORDERS  -  FOOD STAMPS", p.pt(-6.2, 11.155, 1.95), 0.15, Color(0.75, 0.1, 0.1))
	p.slab(n, true, 11.1, -2.8, -1.9, 0.0, 2.1, 0.03, Color(0.45, 0.47, 0.5))
	Props.sign_box(n, "CHECKS CASHED", p.pt(-6.0, 11.14, 3.05), Vector2(5.2, 0.62), YELLOW, Color(0.1, 0.2, 0.45), 0.0, 0.6)
	p.slab(n, true, 11.0, -12.0, 0.0, 4.2, 4.45, 0.35, Color(0.3, 0.28, 0.27))
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
	Wear.garment_rack(p, b, 6.55, 0.38, 0.0, 1.5)
	Props.shelves(p, b, 8.7, 0.31, 0.0, 2.2, "boxes")
	Wear.shoe_boxes(p, b, 9.62, 2.2, 270.0, 6, 7)
	Props.boxes(p, b, 8.4, 1.0, 3)
	Props.clock(p, b, 6.55, 0.08, 0.0, 2.45)
