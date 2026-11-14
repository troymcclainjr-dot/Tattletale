extends RefCounted
## The hospital: the emergency department of Cator-Elkader Hospital, on the
## ground floor of a five-storey block. Walk-ins come through the front and wait;
## ambulances back up to the bay behind and go straight into the trauma room.
## 18 x 18 m inside, three bands from the street back:
##
##   triage and registration | waiting room
##   trauma room | treatment: three curtained bays and the nurses' station
##   ambulance bay | staff room | supply room
##
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 18.

const Props := preload("res://scripts/props.gd")
const WHITE := Color(0.9, 0.92, 0.9)


static func build(p: Node3D) -> void:
	p.setup("HOSPITAL", 18.0, 18.0)
	var pale := Kit.tex("block_plain", 1.2, Color(0.84, 0.86, 0.88), true, Color(0.9, 0.93, 0.95))            # off-white, a touch cool
	var peach := Kit.tex("stucco", 2.0, Color(0.86, 0.78, 0.68), true, Color(1.0, 0.92, 0.82))
	var white := Kit.tex("block_plain", 0.6, Color(0.9, 0.91, 0.93), true, Color(0.97, 0.98, 1.0))
	var lino := Kit.tex("lino", 1.6, Color(0.68, 0.7, 0.7), true, Color(0.93, 0.95, 0.96))
	var lino_blue := Kit.tex("lino", 1.6, Color(0.5, 0.6, 0.66), true, Color(0.7, 0.86, 0.95))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var panel := Kit.tex("sidewalk", 3.0, Color(0.74, 0.76, 0.78), true, Color(0.95, 0.97, 1.0))       # concrete panels
	var tube := Color(0.96, 0.99, 1.0)
	var frame := Color(0.5, 0.54, 0.56)
	var ward_door := Color(0.6, 0.7, 0.72)

	var st: int = p.street(-4.0, 22.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	p.arrive = p.pt(12.5, 19.2)

	p.room("TRIAGE", b1, 0, 12.5, 7.5, 18, lino, {"light": tube})
	p.room("WAITING ROOM", b1, 7.5, 12.5, 18, 18, lino, {"light": tube, "energy": 0.6})
	p.room("TRAUMA ROOM", b2, 0, 6.5, 6, 12.5, lino_blue, {"light": tube, "energy": 0.6})
	p.room("TREATMENT", b2, 6, 6.5, 18, 12.5, lino, {"light": tube, "energy": 0.7})
	p.room("AMBULANCE BAY", b3, 0, 0, 7, 6.5, concrete, {"light": tube, "energy": 0.45})
	p.room("STAFF ROOM", b3, 7, 0, 13.5, 6.5, lino, {"light": Color(1.0, 0.92, 0.78), "energy": 0.45})
	p.room("SUPPLY ROOM", b3, 13.5, 0, 18, 6.5, concrete, {"light": tube, "energy": 0.4})

	var front: Node3D = p.cross(b1, 18.0, 0, 18, panel, [
		{"a": 1.5, "b": 5.5, "kind": "window", "sill": 1.1, "head": 2.3, "blinds": true, "frame": frame},
		{"a": 8.6, "b": 10.6, "kind": "window", "sill": 0.9, "head": 2.3, "frame": frame},
		{"a": 11.6, "b": 13.4, "kind": "double", "head": 2.3, "colour": ward_door, "frame": frame},
		{"a": 14.6, "b": 16.8, "kind": "window", "sill": 0.9, "head": 2.3, "frame": frame},
	], {"h": 4.2})
	p.side(b1, 0.0, 12.5, 18, pale)
	p.side(b1, 18.0, 12.5, 18, peach)
	# Between triage and the waiting room: the registration window, and the door they call you through.
	p.side(b1, 7.5, 12.5, 18, peach, [
		{"a": 14.4, "b": 16.4, "kind": "window", "sill": 1.0, "head": 2.0, "frame": Props.STEEL},
		{"a": 16.8, "b": 17.7, "hinge": "a", "swing": -1, "colour": ward_door, "frame": frame},
	])

	p.cross(b2, 12.5, 0, 18, pale, [
		{"a": 6.3, "b": 7.2, "colour": ward_door, "frame": frame},
		{"a": 9.4, "b": 11.2, "kind": "double", "head": 2.2, "colour": ward_door, "frame": frame, "name": "WARD DOORS"},
	])
	p.side(b2, 0.0, 6.5, 12.5, white)
	p.side(b2, 18.0, 6.5, 12.5, pale)
	p.side(b2, 6.0, 6.5, 12.5, white, [{"a": 10.4, "b": 11.5, "hinge": "a", "swing": 1, "colour": ward_door, "frame": frame}])

	p.cross(b3, 6.5, 0, 18, pale, [
		{"a": 2.4, "b": 4.2, "kind": "double", "head": 2.2, "colour": ward_door, "frame": frame},
		{"a": 7.6, "b": 8.5, "colour": ward_door, "frame": frame},
	])
	p.side(b3, 0.0, 0, 6.5, pale)
	p.side(b3, 18.0, 0, 6.5, pale)
	p.side(b3, 7.0, 0, 6.5, pale, [{"a": 3.0, "b": 3.9, "hinge": "a", "swing": 1, "colour": ward_door, "frame": frame}])
	p.side(b3, 13.5, 0, 6.5, pale, [{"a": 3.0, "b": 3.9, "hinge": "a", "swing": 1, "colour": ward_door, "frame": frame}])
	# The back wall. The bay's roll-up door is up, with an ambulance backed half in.
	p.cross(b3, 0.0, 0, 18, pale, [{"a": 1.4, "b": 5.6, "kind": "window", "sill": 0.0, "head": 2.7, "pane": Color(0, 0, 0, 0), "frame": Props.IRON}], {"back": true})

	_street(p, st, front, panel)
	_front_rooms(p, b1)
	_ward(p, b2)
	_back(p, b3)


static func _street(p: Node3D, st: int, front: Node3D, panel: Variant) -> void:
	var n: Node3D = p.node_of(st)
	var red := Color(0.8, 0.12, 0.1)
	var dark_glass := Color(0.2, 0.24, 0.32)
	var lit_glass := Kit.flat(Color(0.95, 0.95, 0.8), 0.5)
	# Four more floors of wards over the door, the name, the canopy and its sign.
	p.slab(front, true, 18.0, -0.05, 18.05, 4.2, 13.2, 0.3, panel)
	for row in 4:
		for col in 7:
			var u: float = 1.3 + col * 2.4
			var y: float = 5.0 + row * 2.2
			p.slab(front, true, 18.16, u, u + 1.5, y, y + 1.2, 0.02, lit_glass if Props.rnd(col * 3.7 + row * 9.1) > 0.45 else dark_glass)
	Props.words(front, "CATOR-ELKADER HOSPITAL", p.pt(5.2, 18.09, 3.45), 0.3, Color(0.25, 0.3, 0.36))
	Kit.box(front, Vector3(4.6, 0.25, 1.8), p.pt(12.5, 18.9, 2.95), Color(0.86, 0.86, 0.84))
	Props.sign_box(front, "EMERGENCY", p.pt(12.5, 19.87, 2.95), Vector2(3.6, 0.5), red, Color(0.98, 0.96, 0.92))
	for u: float in [10.4, 14.6]:
		var post: Node3D = p.prop(st, u, 19.62, 0.0, 0.2, 0.2)
		Kit.cyl(post, 0.07, 2.83, Vector3(0, 1.415, 0), Color(0.5, 0.54, 0.56), Vector3.ZERO, 8)
	# The rest of the hospital on the left; the ambulance ramp on the right.
	p.slab(n, true, 18.0, -12.0, 0.0, 0.0, 13.2, 0.15, panel)
	for row in 5:
		for col in 4:
			var u: float = -11.0 + col * 2.8
			var y: float = 1.2 + row * 2.2 + (0.4 if row > 0 else 0.0)
			p.slab(n, true, 18.085, u, u + 1.7, y, y + 1.2, 0.02, lit_glass if Props.rnd(col * 5.3 + row * 2.9) > 0.5 else dark_glass)
	p.slab(n, true, 18.0, 18.0, 30.0, 0.0, 4.2, 0.15, Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.8, 0.8, 0.8)))
	p.slab(n, true, 18.085, 19.6, 25.0, 0.0, 2.9, 0.03, Color(0.07, 0.07, 0.1))
	Props.words(n, "AMBULANCES ONLY", p.pt(22.3, 18.09, 3.45), 0.3, red)
	# On the pavement and at the kerb.
	Props.bench(p, st, 9.6, 18.42, 0.0, 2.0, Props.IRON, true)
	Props.bin(p, st, 15.6, 18.45)
	Props.street_lamp(p, st, -1.5, 20.25)
	Props.hydrant(p, st, 17.2, 20.2)
	var board: Node3D = p.prop(st, 7.4, 20.25, 0.0, 0.2, 0.2)
	Kit.cyl(board, 0.03, 2.6, Vector3(0, 1.3, 0), Color(0.45, 0.47, 0.5), Vector3.ZERO, 6)
	Kit.box(board, Vector3(0.6, 0.6, 0.03), Vector3(0, 2.3, 0), Color(0.12, 0.3, 0.7))
	Props.words(board, "H", Vector3(0, 2.3, 0.02), 0.4, Color(0.95, 0.95, 0.92))
	Props.car(p, st, 3.6, 21.95, 90.0, "ambulance", false)


static func _front_rooms(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var ink := Color(0.2, 0.3, 0.36)
	# The waiting room: rows of seats, the television nobody can hear, a machine that ate your money.
	Props.seats(p, b, 13.5, 12.86, 0.0, 5)
	Props.seats(p, b, 15.2, 15.0, 180.0, 4, Color(0.6, 0.35, 0.2))
	Props.seats(p, b, 15.2, 15.56, 0.0, 4, Color(0.6, 0.35, 0.2))
	Props.seats(p, b, 17.6, 15.3, 270.0, 4)
	Props.wall_tv(p, b, 13.5, 12.58)
	Props.vending(p, b, 8.45, 12.98)
	Props.payphone(p, b, 11.7, 12.58)
	Props.clock(p, b, 16.0, 12.58)
	Props.poster(p, b, 15.4, 12.58, 0.0, 0.5, 0.7, Color(0.8, 0.2, 0.2), "NO SMOKING", 1.55)
	Props.plant(p, b, 17.45, 13.0)
	Props.table(p, b, 16.9, 17.4, 0.0, 0.9, 0.5, Props.WOOD, 0.45)
	Props.wheelchair(p, b, 9.0, 17.3, 90.0)
	# The registration window, from the waiting side: a ledge, the sign, take a number.
	p.slab(n, false, 7.675, 14.4, 16.4, 0.95, 1.0, 0.2, Props.STEEL)
	Props.words(n, "REGISTRATION", p.pt(7.59, 15.4, 2.3), 0.16, ink, 90.0)
	Kit.box(n, Vector3(0.1, 0.2, 0.16), p.pt(7.63, 14.1, 1.3), Color(0.8, 0.15, 0.12))
	Props.words(n, "TAKE A NUMBER", p.pt(7.59, 14.1, 1.55), 0.05, ink, 90.0, false)
	# Triage, behind the window: the clerk's counter, the nurse's desk, a couch to be looked at on.
	var counter := Props.counter(p, b, 7.13, 15.4, 270.0, 2.2, 0.5, 1.0, Props.CREAM, Color(0.8, 0.8, 0.78))
	Kit.block(counter, Vector3(0.4, 0.34, 0.36), Vector3(0.45, 1.0, 0.0), Props.CREAM.darkened(0.08))
	Kit.box(counter, Vector3(0.3, 0.24, 0.01), Vector3(0.45, 1.18, 0.184), Kit.flat(Color(0.2, 0.5, 0.3), 0.5))
	Kit.box(counter, Vector3(0.26, 0.012, 0.34), Vector3(-0.4, 1.006, 0.0), Props.PAPER, Vector3(0, 8, 0))
	Props.chair(p, b, 6.5, 15.4, 90.0)
	Props.desk(p, b, 2.8, 13.9, 180.0, Props.CREAM, 2)
	Props.chair(p, b, 2.8, 14.9, 180.0, Color(0.2, 0.45, 0.6))
	p.person(b, "nurse", 1.7, 15.4)                              # triage
	Props.gurney(p, b, 0.56, 15.6, 0.0, Color(0.82, 0.9, 0.92), false)
	Props.monitor_stand(p, b, 0.5, 14.1)
	Props.lockers(p, b, 0.9, 12.83, 0.0, 2, WHITE)
	Props.poster(p, b, 4.4, 12.58, 0.0, 0.45, 0.7, Color(0.92, 0.92, 0.88), "", 1.6)
	Props.words(n, "E", p.pt(4.4, 12.6, 1.82), 0.16, Props.DARK)
	Props.words(n, "F P", p.pt(4.4, 12.6, 1.62), 0.1, Props.DARK)
	Props.words(n, "T O Z", p.pt(4.4, 12.6, 1.47), 0.07, Props.DARK)
	var weigh: Node3D = p.prop(b, 5.3, 12.96, 0.0, 0.4, 0.5)
	Kit.block(weigh, Vector3(0.38, 0.08, 0.46), Vector3.ZERO, Props.STEEL)
	Kit.block(weigh, Vector3(0.05, 1.4, 0.05), Vector3(0, 0, -0.2), Props.STEEL)
	Kit.box(weigh, Vector3(0.36, 0.06, 0.06), Vector3(0, 1.42, -0.2), Props.DARK)


static func _ward(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var ink := Color(0.2, 0.3, 0.36)
	# Treatment: three bays along the back wall, a curtain between each.
	for i in 3:
		var u: float = 10.5 + i * 3.0
		Props.curtain(p, b, u - 1.5, 7.25, 90.0, 1.3)
		Props.gurney(p, b, u, 7.6, 0.0, [Color(0.82, 0.9, 0.92), Color(0.9, 0.86, 0.7), Color(0.75, 0.85, 0.95)][i])
		Props.iv_stand(p, b, u - 0.72, 6.8)
		Props.monitor_stand(p, b, u + 0.72, 6.83)
		Props.words(n, str(i + 1), p.pt(u, 6.59, 2.45), 0.22, ink)
	# The nurses' station: a counter on three sides, open towards the beds.
	var desk := Props.counter(p, b, 13.9, 11.25, 0.0, 3.4, 0.55, 1.1, Props.CREAM, Props.WOOD)
	Props.counter(p, b, 12.475, 10.475, 90.0, 1.0, 0.55, 1.1, Props.CREAM, Props.WOOD)
	Props.counter(p, b, 15.325, 10.475, 90.0, 1.0, 0.55, 1.1, Props.CREAM, Props.WOOD)
	Props.words(desk, "NURSES' STATION", Vector3(0, 0.62, 0.28), 0.13, ink)
	Kit.block(desk, Vector3(0.4, 0.34, 0.36), Vector3(-0.7, 1.1, -0.02), Props.CREAM.darkened(0.08))
	Kit.box(desk, Vector3(0.3, 0.24, 0.01), Vector3(-0.7, 1.28, -0.204), Kit.flat(Color(0.2, 0.5, 0.3), 0.5))
	Kit.block(desk, Vector3(0.2, 0.07, 0.16), Vector3(0.5, 1.1, -0.05), Props.DARK)
	for k in 4:
		Kit.box(desk, Vector3(0.03, 0.3, 0.22), Vector3(1.1 + k * 0.06, 1.25, -0.05), [Color(0.75, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.25, 0.55, 0.3), Color(0.85, 0.7, 0.2)][k], Vector3(0, 0, 6))
	Props.chair(p, b, 13.9, 10.4, 0.0)
	p.person(b, "nurse", 14.6, 10.35)                            # at the station
	p.person(b, "nurse", 12.55, 8.4, {"face": "happy"})         # at a bedside
	# The rest of the room.
	Props.basin(p, b, 6.62, 6.82)
	Props.crash_cart(p, b, 6.33, 8.6, 90.0)
	Props.board(p, b, 6.08, 9.6, 90.0, 1.4, "notices")
	Props.wheelchair(p, b, 17.3, 11.7, 270.0)
	Props.oxygen(p, b, 17.6, 9.4, 1)
	Props.clock(p, b, 8.05, 6.58)
	# The trauma room: one bed under the big lamp, everything else within arm's reach.
	Props.gurney(p, b, 3.0, 9.4, 0.0, WHITE, false)
	Props.exam_lamp(p, b, 2.25, 9.4, 90.0)
	Props.monitor_stand(p, b, 3.9, 8.55)
	Props.iv_stand(p, b, 3.8, 9.9)
	Props.crash_cart(p, b, 0.33, 8.2, 90.0)
	Props.sink_unit(p, b, 0.41, 10.8, 90.0, 1.6)
	Props.lockers(p, b, 1.2, 6.83, 0.0, 2, WHITE)
	Props.lightbox(p, b, 5.1, 6.58)
	Props.oxygen(p, b, 5.6, 7.0, 2)
	Props.words(n, "TRAUMA 1", p.pt(1.2, 6.59, 2.45), 0.16, ink)


static func _back(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The ambulance bay: the door is up and an ambulance stands backed half in.
	Props.car(p, b, 3.5, -0.6, 180.0, "ambulance")
	Kit.box(n, Vector3(10.0, 0.3, 5.0), p.pt(3.5, -2.5, -0.16), Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27)))
	p.slab(n, true, 0.0, 1.42, 5.58, 2.7, 2.86, 0.22, Color(0.45, 0.47, 0.5))
	Props.gurney(p, b, 0.56, 4.4)
	Props.shelves(p, b, 0.31, 1.6, 90.0, 1.8)
	Props.wheelchair(p, b, 6.4, 5.7, 270.0)
	Props.oxygen(p, b, 6.55, 0.5, 2)
	Props.words(n, "AMBULANCE ENTRANCE", p.pt(0.09, 3.4, 2.4), 0.14, Color(0.75, 0.15, 0.12), 90.0)
	# The staff room.
	Props.lockers(p, b, 8.6, 0.33, 0.0, 4)
	Props.fridge(p, b, 10.1, 0.44)
	Props.couch(p, b, 11.9, 0.52, 0.0, 2.0, Color(0.3, 0.4, 0.42))
	var table := Props.table(p, b, 10.2, 3.6, 0.0, 1.6, 0.9, Color(0.82, 0.8, 0.74))
	Kit.box(table, Vector3(0.3, 0.02, 0.4), Vector3(0.3, 0.75, 0.0), Props.PAPER, Vector3(0, 12, 0))
	Props.seat(p, b, 10.2, 2.83, 0.0, Props.STEEL, Color(0.2, 0.45, 0.6))
	Props.seat(p, b, 10.2, 4.37, 180.0, Props.STEEL, Color(0.2, 0.45, 0.6))
	Props.coffee(p, b, 7.45, 1.4, 90.0)
	Props.board(p, b, 7.08, 5.0, 90.0, 1.4, "notices")
	Props.cooler(p, b, 13.05, 5.8)
	Props.clock(p, b, 12.2, 0.08)
	# The supply room.
	Props.shelves(p, b, 15.75, 0.31, 0.0, 3.8, "boxes", Props.STEEL)
	Props.shelves(p, b, 13.81, 5.2, 90.0, 1.8, "boxes", Props.STEEL)
	Props.oxygen(p, b, 17.5, 5.9, 2)
	Props.boxes(p, b, 16.9, 3.3, 4)
	Props.bucket(p, b, 17.4, 1.6)
