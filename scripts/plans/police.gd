extends RefCounted
## The police station: Pen Lucy Precinct. An old city station house that nobody
## has spent money on: painted block walls, lino, mismatched government desks.
## 16 x 22 m inside, one floor, four bands from the street back:
##
##   lobby | front desk      the public gets no further than this
##   squad room | captain
##   interview | booking | evidence
##   cells and the drunk tank | sally port      prisoners come in at the back
##
## Numbers are metres on the plan (see place.gd and the layouts folder): u from
## the left wall, v from the back wall; the street is at v = 22.

const Props := preload("res://scripts/props.gd")


static func build(p: Node3D) -> void:
	p.setup("POLICE STATION", 16.0, 22.0)
	var green := Kit.tex("painted_block", 1.2, Color(0.66, 0.74, 0.62), true, Color(0.72, 0.86, 0.76))    # institutional green
	var grey := Kit.tex("painted_block", 1.2, Color(0.6, 0.62, 0.64), true, Color(0.6, 0.68, 0.95))        # the secure end: colder
	var lino := Kit.tex("lino", 1.6, Color(0.6, 0.66, 0.6), true, Color(0.86, 0.84, 0.74))
	var lino_dark := Kit.tex("lino", 1.6, Color(0.45, 0.5, 0.48), true, Color(0.6, 0.62, 0.6))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var carpet := Kit.tex("carpet", 2.0, Color(0.25, 0.3, 0.4), true, Color(0.5, 0.62, 0.9))
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.9, 0.82, 0.8))
	var tube := Color(0.88, 1.0, 0.92)       # strip-light white, a little green
	var steel_door := Color(0.36, 0.4, 0.44)

	var st: int = p.street(-4.0, 20.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	var b4: int = p.band()
	p.arrive = p.pt(5.1, 23.2)

	p.room("PUBLIC LOBBY", b1, 0, 17, 10.5, 22, lino, {"light": tube})
	p.room("FRONT DESK", b1, 10.5, 17, 16, 22, lino, {"light": tube})
	p.room("SQUAD ROOM", b2, 0, 11, 12, 17, lino, {"light": tube, "energy": 0.6})
	p.room("CAPTAIN", b2, 12, 11, 16, 17, carpet, {"light": Color(1.0, 0.9, 0.75)})
	p.room("INTERVIEW", b3, 0, 5, 4, 11, concrete, {"light": Color(1.0, 0.85, 0.6), "energy": 0.7})
	p.room("BOOKING", b3, 4, 5, 11, 11, lino_dark, {"light": tube})
	p.room("EVIDENCE", b3, 11, 5, 16, 11, concrete, {"light": tube, "energy": 0.4})
	p.room("CELL BLOCK", b4, 0, 2.6, 12, 5, concrete, {"light": tube, "energy": 0.45})
	p.room("CELL 1", b4, 0, 0, 3, 2.6, concrete)
	p.room("CELL 2", b4, 3, 0, 6, 2.6, concrete)
	p.room("CELL 3", b4, 6, 0, 9, 2.6, concrete)
	p.room("DRUNK TANK", b4, 9, 0, 12, 2.6, concrete)
	p.room("SALLY PORT", b4, 12, 0, 16, 5, concrete, {"light": tube, "energy": 0.4})

	# ---- walls. Each `cross` is the wall in FRONT of its band.
	var front: Node3D = p.cross(b1, 22.0, 0, 16, brick, [
		{"a": 0.8, "b": 3.0, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "frame": Color(0.2, 0.22, 0.26)},
		{"a": 4.2, "b": 6.0, "kind": "double", "head": 2.2, "colour": Color(0.2, 0.26, 0.4), "frame": Color(0.2, 0.22, 0.26)},
		{"a": 7.2, "b": 9.4, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "frame": Color(0.2, 0.22, 0.26)},
		{"a": 12.2, "b": 15.0, "kind": "window", "sill": 1.1, "head": 2.3, "bars": true, "blinds": true, "frame": Color(0.2, 0.22, 0.26)},
	], {"h": 4.0})
	p.side(b1, 0.0, 17, 22, green)
	p.side(b1, 16.0, 17, 22, green)
	p.side(b1, 10.5, 17, 22, green, [{"a": 18.4, "b": 20.7, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.STEEL}])

	p.cross(b2, 17.0, 0, 16, green, [
		{"a": 8.2, "b": 9.1, "colour": steel_door, "name": "GATE"},
		{"a": 10.9, "b": 11.8, "colour": steel_door},
	])
	p.side(b2, 0.0, 11, 17, green)
	p.side(b2, 16.0, 11, 17, green)
	p.side(b2, 12.0, 11, 17, green, [
		{"a": 11.8, "b": 14.6, "kind": "window", "sill": 0.95, "head": 2.1, "blinds": true},
		{"a": 15.2, "b": 16.1, "hinge": "a", "swing": 1, "colour": Color(0.42, 0.3, 0.2)},
	])

	p.cross(b3, 11.0, 0, 16, grey, [
		{"a": 0.6, "b": 1.5, "colour": steel_door},
		{"a": 6.0, "b": 6.9, "colour": steel_door},
	])
	p.side(b3, 0.0, 5, 11, grey)
	p.side(b3, 16.0, 5, 11, grey)
	p.side(b3, 4.0, 5, 11, grey, [{"a": 6.3, "b": 8.6, "kind": "window", "sill": 0.95, "head": 1.9, "pane": Color(0.1, 0.12, 0.18, 0.93), "frame": Props.IRON}])    # the one-way mirror
	p.side(b3, 11.0, 5, 11, grey, [
		{"a": 7.5, "b": 8.9, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.IRON},     # the property window
		{"a": 9.6, "b": 10.5, "hinge": "a", "swing": 1, "colour": steel_door, "name": "CAGE"},
	])

	p.cross(b4, 5.0, 0, 16, grey, [{"a": 7.6, "b": 8.5, "colour": steel_door}])
	# The back wall. The sally port's roll-up door is up, with the prisoner van backed half in.
	p.cross(b4, 0.0, 0, 16, grey, [{"a": 12.7, "b": 15.3, "kind": "window", "sill": 0.0, "head": 2.7, "pane": Color(0, 0, 0, 0), "frame": Props.IRON}], {"back": true})
	p.side(b4, 0.0, 0, 5, grey)
	p.side(b4, 16.0, 0, 5, grey)
	p.side(b4, 12.0, 0, 5, grey, [{"a": 3.4, "b": 4.3, "hinge": "a", "swing": 1, "colour": steel_door}])
	for u in [3.0, 6.0, 9.0]:
		p.side(b4, u, 0, 2.6, grey)
	p.bars(b4, true, 2.6, 0.0, 12.0, [[1.0, 2.0], [4.0, 5.0], [7.0, 8.0], [10.0, 11.0]])

	_street(p, st, front)
	_lobby(p, b1)
	_squad(p, b2)
	_booking(p, b3)
	_cells(p, b4)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	# The station's own front: a stone band, the POLICE panel, two blue globes.
	var stone := Color(0.74, 0.72, 0.66)
	p.slab(front, true, 22.0, -0.05, 16.05, 4.0, 4.22, 0.3, stone)
	p.slab(front, true, 22.06, -0.02, 16.02, 0.0, 0.5, 0.1, stone.darkened(0.12))
	p.slab(front, true, 22.1, 3.6, 6.6, 2.55, 3.45, 0.06, Color(0.14, 0.2, 0.4))
	Props.words(front, "POLICE", p.pt(5.1, 22.135, 3.07), 0.5, Color(0.93, 0.9, 0.78))
	Props.words(front, "PEN LUCY PRECINCT", p.pt(5.1, 22.135, 2.68), 0.11, Color(0.93, 0.9, 0.78), 0.0, false)
	for u in [3.85, 6.35]:
		Props.globe_lamp(front, p.pt(u, 22.075, 1.9))
	# Next door: a boarded-up shop on the left, a bail bondsman on the right.
	p.slab(n, true, 22.0, -12.0, 0.0, 0.0, 3.5, 0.15, Kit.tex("stucco", 2.0, Color(0.6, 0.56, 0.5), true, Color(0.72, 0.68, 0.62)))
	for u in [-9.6, -6.4, -3.2]:
		p.slab(n, true, 22.085, u, u + 2.4, 0.5, 2.4, 0.03, Color(0.55, 0.42, 0.26))       # plywood
		p.slab(n, true, 22.1, u + 0.3, u + 2.1, 1.3, 1.36, 0.03, Color(0.45, 0.33, 0.2))
	Props.words(n, "FOR LEASE", p.pt(-5.2, 22.09, 2.9), 0.26, Color(0.75, 0.2, 0.15))
	p.slab(n, true, 22.0, 16.0, 28.0, 0.0, 3.8, 0.15, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74)))
	p.slab(n, true, 22.085, 17.2, 20.6, 0.4, 2.3, 0.03, Kit.flat(Color(1.0, 0.92, 0.7), 0.9))
	p.slab(n, true, 22.1, 21.2, 22.1, 0.0, 2.1, 0.03, Color(0.2, 0.3, 0.26))
	Props.words(n, "BAIL BONDS", p.pt(19.6, 22.09, 2.95), 0.34, Color(0.98, 0.85, 0.3))
	Props.words(n, "OPEN 24 HOURS", p.pt(18.9, 22.11, 1.4), 0.16, Color(0.75, 0.15, 0.12))
	# On the pavement and at the kerb.
	Props.bin(p, st, 6.7, 22.45)
	Props.street_lamp(p, st, -1.4, 24.25)
	Props.hydrant(p, st, 9.6, 24.2)
	Props.car(p, st, 12.6, 25.95, 90.0, "cruiser", false)


static func _lobby(p: Node3D, b: int) -> void:
	Props.bench(p, b, 0.36, 19.3, 90.0, 3.2, Props.WOOD)
	Props.bench(p, b, 2.95, 17.36, 0.0, 2.9, Props.WOOD)
	Props.board(p, b, 2.95, 17.08, 0.0, 2.4, "wanted")
	Props.words(p.node_of(b), "WANTED", p.pt(2.95, 17.09, 2.3), 0.16, Color(0.7, 0.12, 0.1))
	Props.board(p, b, 0.08, 19.3, 90.0, 2.0, "notices")
	Props.vending(p, b, 5.5, 17.5)
	Props.payphone(p, b, 6.9, 17.08)
	Props.clock(p, b, 7.6, 17.08)
	Props.plant(p, b, 9.95, 21.45)
	Props.flag(p, b, 0.45, 21.5)
	Props.words(p.node_of(b), "DESK SERGEANT", p.pt(10.42, 19.55, 2.3), 0.13, Color(0.15, 0.18, 0.3), 270.0)
	Props.poster(p, b, 10.42, 17.6, 270.0, 0.5, 0.7, Color(0.85, 0.75, 0.3), "NO LOITERING", 1.6)
	# Behind the glass.
	var counter := Props.counter(p, b, 10.95, 19.55, 90.0, 2.7, 0.65, 1.04, Props.OFFICE)
	Kit.box(counter, Vector3(0.3, 0.02, 0.4), Vector3(0.3, 1.06, 0), Props.PAPER)
	Kit.block(counter, Vector3(0.2, 0.07, 0.16), Vector3(-0.7, 1.05, 0.05), Props.DARK)
	Props.chair(p, b, 11.75, 19.55, 270.0)
	Props.radio(p, b, 14.95, 17.5)
	Props.desk(p, b, 13.6, 20.85, 180.0, Props.OFFICE, 3)
	Props.files(p, b, 15.6, 20.3, 270.0, 2)
	Props.board(p, b, 15.92, 18.6, 270.0, 1.2, "notices")
	Props.clock(p, b, 13.3, 17.08)


static func _squad(p: Node3D, b: int) -> void:
	var stuff := [1, 2, 3, 1, 3, 2]
	for i in 3:
		var u := 2.1 + i * 3.3
		Props.desk(p, b, u, 13.875, 180.0, Props.OFFICE.darkened(0.08 * (i % 2)), stuff[i * 2])
		Props.desk(p, b, u, 14.625, 0.0, Props.OFFICE.lightened(0.06 * (i % 2)), stuff[i * 2 + 1])
	Props.board(p, b, 3.7, 11.08, 0.0, 2.6, "wanted", 1.1)
	Props.words(p.node_of(b), "OPEN CASES", p.pt(3.7, 11.09, 2.32), 0.13, Color(0.2, 0.2, 0.22))
	Props.board(p, b, 0.08, 12.6, 90.0, 2.0, "notices")
	Props.files(p, b, 0.4, 15.6, 90.0, 4)
	Props.lockers(p, b, 2.3, 16.65, 180.0, 4)
	Props.coffee(p, b, 10.3, 11.45)
	Props.cooler(p, b, 11.6, 11.3)
	Props.flag(p, b, 11.55, 16.5, Color(0.6, 0.12, 0.14))
	Props.clock(p, b, 8.0, 11.08)
	# The captain's office.
	Props.desk(p, b, 14.1, 12.9, 180.0, Props.WOOD, 2, true, 2.0, 0.85)
	Props.chair(p, b, 13.6, 14.1, 180.0, Props.VINYL)
	Props.chair(p, b, 14.6, 14.1, 180.0, Props.VINYL)
	Props.shelves(p, b, 15.68, 13.3, 270.0, 2.4, "books", Props.WOOD_DARK)
	Props.flag(p, b, 12.5, 11.45)
	Props.couch(p, b, 14.1, 16.42, 180.0, 2.0, Color(0.3, 0.22, 0.16))
	Props.poster(p, b, 14.1, 11.08, 0.0, 0.9, 0.6, Color(0.7, 0.58, 0.3), "", 1.9)
	Props.rug(p, b, 14.0, 14.3, 2.6, 1.6, Color(0.35, 0.16, 0.16))


static func _booking(p: Node3D, b: int) -> void:
	# Interview: a table, three chairs, the mirror.
	Props.table(p, b, 2.0, 7.6, 0.0, 1.4, 0.9, Props.IRON)
	Props.chair(p, b, 2.0, 6.75, 0.0, Props.IRON)
	Props.chair(p, b, 2.0, 8.45, 180.0, Props.IRON)
	Props.chair(p, b, 0.5, 5.5, 90.0, Props.IRON)
	# Booking: the counter, prints, the mugshot wall, the cuff bench.
	var counter := Props.counter(p, b, 4.46, 7.75, 90.0, 3.1, 0.7, 1.05, Props.OFFICE.darkened(0.15))
	Kit.block(counter, Vector3(0.36, 0.1, 0.3), Vector3(0.9, 1.05, 0), Color(0.25, 0.3, 0.28))
	Kit.box(counter, Vector3(0.6, 0.03, 0.4), Vector3(-0.6, 1.065, 0), Color(0.2, 0.3, 0.2))
	Props.words(p.node_of(b), "BOOKING", p.pt(4.09, 9.2, 2.3), 0.16, Color(0.9, 0.9, 0.85), 90.0)
	var prints := Props.table(p, b, 4.46, 10.25, 90.0, 0.9, 0.7, Props.STEEL)
	Kit.box(prints, Vector3(0.3, 0.02, 0.2), Vector3(0, 0.75, 0), Props.DARK)
	Kit.box(prints, Vector3(0.24, 0.01, 0.3), Vector3(0.28, 0.745, 0.05), Props.PAPER)
	Props.height_chart(p, b, 6.3, 5.08)
	Props.tripod(p, b, 6.3, 6.9, 180.0)
	var cuffs := Props.bench(p, b, 9.85, 5.43, 0.0, 1.9, Props.IRON)
	Kit.box(cuffs, Vector3(1.9, 0.04, 0.04), Vector3(0, 0.75, -0.2), Props.STEEL)
	Props.lockers(p, b, 10.65, 6.55, 270.0, 3)
	Props.counter(p, b, 10.7, 8.2, 270.0, 1.4, 0.4, 1.0, Props.OFFICE.darkened(0.15))
	Props.words(p.node_of(b), "PROPERTY", p.pt(10.91, 8.2, 2.25), 0.13, Color(0.9, 0.9, 0.85), 270.0)
	# Evidence: rows of shelving behind the cage door.
	Props.shelves(p, b, 13.6, 5.42, 0.0, 4.2)
	for v in [7.3, 8.6, 9.9]:
		Props.shelves(p, b, 14.2, v, 0.0, 3.2)
	Props.counter(p, b, 11.32, 8.2, 90.0, 1.4, 0.4, 1.0, Props.OFFICE.darkened(0.15))


static func _cells(p: Node3D, b: int) -> void:
	for i in 3:
		var u0 := i * 3.0
		Props.bunk(p, b, u0 + 1.1, 0.5)
		Props.cell_toilet(p, b, u0 + 2.55, 0.4)
		Props.words(p.node_of(b), str(i + 1), p.pt(u0 + 1.5, 2.64, 2.55), 0.22, Color(0.9, 0.9, 0.85))
	Props.bench(p, b, 10.5, 0.38, 0.0, 2.6, Props.IRON)
	Props.bench(p, b, 11.6, 1.75, 270.0, 1.2, Props.IRON)
	Props.words(p.node_of(b), "TANK", p.pt(10.5, 2.64, 2.55), 0.2, Color(0.9, 0.9, 0.85))
	Props.desk(p, b, 10.9, 4.45, 0.0, Props.OFFICE.darkened(0.2), 1, false, 1.4, 0.6)
	Props.chair(p, b, 9.75, 4.45, 90.0)
	Props.board(p, b, 0.08, 3.8, 90.0, 1.2, "notices")
	# The sally port: the roll-up door is up and the prisoner van stands half
	# in, half out on the back lot. (A whole van indoors hid him from the camera.)
	Props.car(p, b, 14.0, -0.55, 0.0, "van")
	var n: Node3D = p.node_of(b)
	Kit.box(n, Vector3(9.0, 0.3, 5.0), p.pt(14.0, -2.5, -0.16), Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27)))
	p.slab(n, true, 0.0, 12.72, 15.28, 2.7, 2.86, 0.22, Color(0.45, 0.47, 0.5))      # the door, rolled up
	for u in [12.42, 15.58]:      # oil drums fill the corners beside the van
		var drum: Node3D = p.prop(b, u, 0.75, 0.0, 0.62, 1.25)
		for k in 2:
			Kit.cyl(drum, 0.28, 0.85, Vector3(0, 0.425, -0.3 + k * 0.6), Color(0.2, 0.36, 0.5) if k == 0 else Color(0.6, 0.3, 0.12), Vector3.ZERO, 10)
	Props.words(n, "NO PRISONER LEFT UNATTENDED", p.pt(15.91, 3.2, 2.2), 0.1, Color(0.75, 0.15, 0.12), 270.0)
