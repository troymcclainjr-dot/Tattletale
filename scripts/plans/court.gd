extends RefCounted
## The courthouse: a district court. A tired 1970s building, not a marble
## palace: brown brick, lino, worn pews, one courtroom. 18 x 22.5 m inside, one
## floor, four bands from the street back:
##
##   security lobby | clerk's office      everyone is screened at the door
##   lawyer room | public hall
##   lockup, holding cell | courtroom | jury room
##   records | judge's chambers
##
## Three ways in that never mix: the public by the hall, the judge from
## chambers, prisoners from the lockup straight into the well of the court.
## Numbers are metres on the plan (see place.gd): u from the left wall, v from
## the back wall; the street is at v = 22.5.

const Props := preload("res://scripts/props.gd")


static func build(p: Node3D) -> void:
	p.setup("COURTHOUSE", 18.0, 22.5)
	var beige := Kit.tex("stucco", 2.0, Color(0.8, 0.76, 0.64), true, Color(0.95, 1.0, 0.86))
	var panel := Kit.tex("wood_panel", 1.2, Color(0.5, 0.33, 0.2), true, Color(0.5, 0.44, 0.48))      # dark oak
	var block := Kit.tex("block_plain", 1.2, Color(0.62, 0.64, 0.68), true, Color(0.68, 0.71, 0.78))
	var lino := Kit.tex("lino", 1.6, Color(0.66, 0.6, 0.5), true, Color(1.0, 0.86, 0.72))
	var boards := Kit.tex("wood_panel", 1.6, Color(0.45, 0.32, 0.22), true, Color(0.6, 0.62, 0.7))
	var carpet := Kit.tex("carpet", 2.0, Color(0.45, 0.14, 0.18), true, Color(0.95, 0.8, 0.85))
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76))
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.28, 0.2), true, Color(0.78, 0.74, 0.66))
	var strip := Color(1.0, 0.96, 0.84)
	var oak := Color(0.36, 0.24, 0.15)
	var steel_door := Color(0.36, 0.4, 0.44)

	var st: int = p.street(-4.0, 22.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	var b4: int = p.band()
	p.arrive = p.pt(6.0, 23.7)

	p.room("SECURITY LOBBY", b1, 0, 17.5, 11, 22.5, lino, {"light": strip})
	p.room("CLERK'S OFFICE", b1, 11, 17.5, 18, 22.5, lino, {"light": strip})
	p.room("LAWYER ROOM", b2, 0, 13.5, 4, 17.5, lino, {"light": strip})
	p.room("PUBLIC HALL", b2, 4, 13.5, 18, 17.5, lino, {"light": strip, "energy": 0.6})
	p.room("LOCKUP", b3, 0, 4.5, 3, 8.6, concrete, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("HOLDING CELL", b3, 0, 8.6, 3, 13.5, concrete)
	p.room("COURTROOM", b3, 3, 4.5, 15, 13.5, boards, {"light": strip, "energy": 0.75})
	p.room("JURY ROOM", b3, 15, 4.5, 18, 13.5, lino, {"light": strip, "energy": 0.4})
	p.room("RECORDS", b4, 0, 0, 9, 4.5, concrete, {"light": Color(0.96, 0.98, 0.95), "energy": 0.4})
	p.room("JUDGE'S CHAMBERS", b4, 9, 0, 18, 4.5, carpet, {"light": Color(1.0, 0.88, 0.7)})

	var bronze := Color(0.3, 0.25, 0.18)
	var front: Node3D = p.cross(b1, 22.5, 0, 18, brick, [
		{"a": 1.0, "b": 3.4, "kind": "window", "sill": 1.1, "head": 2.4, "frame": bronze},
		{"a": 5.1, "b": 6.9, "kind": "double", "head": 2.2, "colour": Color(0.32, 0.26, 0.18), "frame": bronze},
		{"a": 8.2, "b": 10.2, "kind": "window", "sill": 1.1, "head": 2.4, "frame": bronze},
		{"a": 12.4, "b": 16.6, "kind": "window", "sill": 1.1, "head": 2.4, "blinds": true, "frame": bronze},
	], {"h": 4.2})
	p.side(b1, 0.0, 17.5, 22.5, beige)
	p.side(b1, 18.0, 17.5, 22.5, beige)
	p.side(b1, 11.0, 17.5, 22.5, beige, [{"a": 17.9, "b": 19.8, "kind": "window", "sill": 1.05, "head": 2.0, "frame": Props.STEEL}])

	p.cross(b2, 17.5, 0, 18, beige, [
		{"a": 5.1, "b": 6.9, "kind": "arch"},
		{"a": 15.6, "b": 16.5, "swing": 1, "colour": oak},
	])
	p.side(b2, 0.0, 13.5, 17.5, beige)
	p.side(b2, 18.0, 13.5, 17.5, beige)
	p.side(b2, 4.0, 13.5, 17.5, beige, [{"a": 13.8, "b": 14.7, "hinge": "a", "swing": -1, "colour": oak}])

	p.cross(b3, 13.5, 0, 18, panel, [{"a": 8.1, "b": 9.9, "kind": "double", "swing": 1, "head": 2.2, "colour": oak}])
	p.side(b3, 0.0, 4.5, 13.5, block)
	p.side(b3, 18.0, 4.5, 13.5, beige)
	p.side(b3, 3.0, 4.5, 13.5, panel, [{"a": 6.6, "b": 7.5, "hinge": "a", "swing": -1, "colour": steel_door}])
	p.side(b3, 15.0, 4.5, 13.5, panel, [{"a": 5.3, "b": 6.2, "hinge": "a", "swing": 1, "colour": oak}])
	p.bars(b3, true, 8.6, 0.0, 3.0, [[1.0, 2.0]])

	p.cross(b4, 4.5, 0, 18, panel, [{"a": 13.3, "b": 14.2, "colour": oak}])
	p.cross(b4, 0.0, 0, 18, beige, [], {"back": true})
	p.side(b4, 0.0, 0, 4.5, beige)
	p.side(b4, 18.0, 0, 4.5, beige)
	p.side(b4, 9.0, 0, 4.5, beige, [{"a": 2.7, "b": 3.6, "hinge": "a", "swing": -1, "colour": oak}])

	_street(p, st, front)
	_lobby(p, b1)
	_hall(p, b2)
	_court(p, b3)
	_back(p, b4)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var concrete := Color(0.7, 0.69, 0.65)
	# A concrete band along the top, a canopy over the doors on two posts, the name.
	p.slab(front, true, 22.5, -0.05, 18.05, 4.2, 4.5, 0.3, concrete)
	Kit.box(front, Vector3(4.36, 0.2, 1.5), p.pt(6.0, 23.3, 2.95), concrete)
	for u in [4.0, 8.0]:
		var post: Node3D = p.prop(st, u, 23.9, 0.0, 0.2, 0.2)
		Kit.cyl(post, 0.07, 2.85, Vector3(0, 1.425, 0), Color(0.3, 0.25, 0.18), Vector3.ZERO, 8)
	Props.words(front, "DISTRICT COURT", p.pt(9.6, 22.585, 3.5), 0.42, Color(0.9, 0.86, 0.72))
	Kit.disc(front, 0.42, p.pt(3.4, 22.59, 3.45), Color(0.78, 0.63, 0.25), 0.03, 16)
	Kit.disc(front, 0.32, p.pt(3.4, 22.6, 3.45), Color(0.2, 0.25, 0.45), 0.03, 16)
	Props.words(front, "ALL PERSONS SUBJECT TO SEARCH", p.pt(9.2, 22.585, 0.8), 0.09, Color(0.9, 0.86, 0.72), 0.0, false)
	# Next door: a cheque casher on the left, a lawyer's shopfront on the right.
	p.slab(n, true, 22.5, -12.0, 0.0, 0.0, 3.6, 0.15, Kit.tex("stucco", 2.0, Color(0.7, 0.66, 0.4), true, Color(1.0, 0.95, 0.6)))
	p.slab(n, true, 22.585, -8.6, -3.4, 0.5, 2.3, 0.03, Kit.flat(Color(1.0, 0.95, 0.75), 0.9))
	p.slab(n, true, 22.6, -2.6, -1.7, 0.0, 2.1, 0.03, Color(0.5, 0.52, 0.55))
	Props.words(n, "CHECKS CASHED", p.pt(-6.0, 22.59, 2.95), 0.34, Color(0.75, 0.12, 0.1))
	Props.words(n, "PAYDAY LOANS  -  MONEY ORDERS", p.pt(-6.0, 22.62, 1.0), 0.13, Color(0.75, 0.12, 0.1), 0.0, false)
	p.slab(n, true, 22.5, 18.0, 30.0, 0.0, 3.8, 0.15, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74)))
	p.slab(n, true, 22.585, 19.0, 22.4, 0.6, 2.3, 0.03, Color(0.16, 0.2, 0.26))
	p.slab(n, true, 22.6, 23.0, 23.9, 0.0, 2.1, 0.03, Color(0.3, 0.2, 0.14))
	Props.words(n, "ATTORNEY AT LAW", p.pt(21.4, 22.59, 2.95), 0.3, Color(0.92, 0.8, 0.35))
	Props.words(n, "DUI - TRAFFIC - BAIL", p.pt(20.7, 22.62, 1.5), 0.14, Color(0.92, 0.8, 0.35), 0.0, false)
	Props.bench(p, st, 2.2, 22.92, 0.0, 2.2, Props.IRON, true)
	Props.bin(p, st, 7.6, 22.95)
	Props.street_lamp(p, st, -1.6, 24.75)
	Props.hydrant(p, st, 12.5, 24.7)


static func _lobby(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# Screening: in at the doors, the belt on your left, through the arch, the guard beyond.
	Props.detector(p, b, 6.0, 20.2)
	Props.xray(p, b, 4.33, 20.3)
	var tray: Node3D = p.prop(b, 5.06, 20.2, 0.0, 0.6, 0.5)
	Kit.block(tray, Vector3(0.56, 0.72, 0.46), Vector3.ZERO, Props.STEEL)
	Kit.box(tray, Vector3(0.44, 0.06, 0.34), Vector3(0, 0.75, 0), Props.OFFICE)
	p.rail(b, true, 20.2, 0.1, 3.9, Props.IRON)
	p.rail(b, true, 20.2, 6.65, 10.9, Props.IRON)
	Props.desk(p, b, 8.2, 19.2, 180.0, Props.OFFICE, 3, true, 1.4)
	Props.words(n, "EMPTY YOUR POCKETS", p.pt(0.09, 21.3, 1.9), 0.13, Color(0.6, 0.12, 0.1), 90.0)
	Props.bench(p, b, 0.36, 18.75, 90.0, 2.0, Props.WOOD)
	Props.board(p, b, 2.6, 17.58, 0.0, 2.0, "notices")
	Props.words(n, "DIRECTORY", p.pt(2.6, 17.59, 2.3), 0.14, Color(0.25, 0.2, 0.15))
	Props.clock(p, b, 8.4, 17.58)
	Props.plant(p, b, 10.4, 21.9)
	Props.flag(p, b, 0.5, 21.95, Color(0.16, 0.2, 0.45), 0.0, true)
	Props.words(n, "PAY FINES HERE", p.pt(10.91, 18.85, 2.3), 0.14, Color(0.25, 0.2, 0.15), 270.0)
	# The clerk's office, behind the glass.
	var counter := Props.counter(p, b, 11.45, 18.85, 90.0, 2.1, 0.6, 1.04, Props.OFFICE)
	Kit.box(counter, Vector3(0.3, 0.02, 0.4), Vector3(0.4, 1.05, 0), Props.PAPER)
	Kit.block(counter, Vector3(0.34, 0.22, 0.3), Vector3(-0.5, 1.04, 0.05), Props.CREAM)
	Props.chair(p, b, 12.2, 18.85, 270.0)
	Props.desk(p, b, 14.2, 20.0, 180.0, Props.OFFICE, 1)
	Props.desk(p, b, 14.2, 21.45, 180.0, Props.OFFICE.darkened(0.08), 3)
	Props.files(p, b, 17.6, 20.4, 270.0, 6)
	Props.cooler(p, b, 17.6, 18.0)
	Props.board(p, b, 12.9, 17.58, 0.0, 1.4, "notices")


static func _hall(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	Props.bench(p, b, 6.1, 13.86, 0.0, 3.0, Props.WOOD_DARK, true)
	Props.bench(p, b, 11.9, 13.86, 0.0, 3.0, Props.WOOD_DARK, true)
	Props.words(n, "COURTROOM 1", p.pt(9.0, 13.59, 2.45), 0.16, Color(0.92, 0.86, 0.7))
	Props.board(p, b, 14.9, 13.58, 0.0, 1.8, "notices")
	Props.words(n, "TODAY'S DOCKET", p.pt(14.9, 13.59, 2.3), 0.13, Color(0.92, 0.86, 0.7))
	Props.fountain(p, b, 17.74, 14.5, 270.0)
	Props.payphone(p, b, 4.08, 16.4, 90.0)
	Props.clock(p, b, 16.6, 13.58)
	Props.bin(p, b, 17.55, 17.05)
	# Two doors that stay shut.
	for row: Array in [[15.6, "MEN"], [16.75, "WOMEN"]]:
		var v: float = row[0]
		p.slab(n, false, 17.9, v - 0.42, v + 0.42, 0.0, 2.05, 0.04, Color(0.36, 0.24, 0.15))
		Props.words(n, row[1], p.pt(17.87, v, 1.6), 0.09, Color(0.92, 0.86, 0.7), 270.0)
	# The lawyer room: where a deal gets made five minutes before the hearing.
	Props.table(p, b, 1.9, 15.6, 0.0, 1.8, 0.9, Props.WOOD)
	Props.chair(p, b, 1.4, 14.85, 0.0, Props.VINYL)
	Props.chair(p, b, 2.4, 14.85, 0.0, Props.VINYL)
	Props.chair(p, b, 1.9, 16.35, 180.0, Props.VINYL)
	Props.poster(p, b, 0.08, 15.6, 90.0, 0.7, 0.9, Color(0.2, 0.3, 0.5), "KNOW YOUR RIGHTS")


static func _court(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The bench and the witness stand are out from the wall: there is room to
	# walk round behind them (and, later, to step in and sit).
	Props.judge_bench(p, b, 9.0, 6.2)
	Kit.disc(n, 0.5, p.pt(9.0, 4.59, 2.25), Color(0.78, 0.63, 0.25), 0.03, 16)
	Kit.disc(n, 0.38, p.pt(9.0, 4.6, 2.25), Color(0.2, 0.25, 0.45), 0.03, 16)
	Props.desk(p, b, 5.65, 5.75, 180.0, Props.WOOD, 1, true, 1.3)
	Props.witness_stand(p, b, 12.3, 6.0)
	Props.jury_box(p, b, 13.98, 8.45, 270.0, 2.4)      # clear of the witness stand: the way to the back rooms runs between them
	Props.table(p, b, 5.9, 8.7, 0.0, 2.8, 0.8, Props.WOOD)
	Props.table(p, b, 11.5, 8.7, 0.0, 2.6, 0.8, Props.WOOD)
	for u in [5.2, 6.6, 10.9, 12.1]:
		Props.chair(p, b, u, 9.4, 180.0, Props.VINYL)
	Props.lectern(p, b, 9.0, 8.55, 180.0)
	p.rail(b, true, 9.75, 3.1, 8.35)
	p.rail(b, true, 9.75, 9.65, 14.9)
	for v in [10.65, 11.65, 12.65]:
		Props.pew(p, b, 5.8, v, 180.0, 4.6)
		Props.pew(p, b, 12.2, v, 180.0, 4.6)
	Props.clock(p, b, 14.92, 11.6, 270.0)
	# The lockup: a deputy's desk, and the holding cell behind bars.
	Props.desk(p, b, 0.6, 5.5, 90.0, Props.OFFICE.darkened(0.2), 1, false, 1.2, 0.6)
	Props.chair(p, b, 1.35, 5.5, 270.0)
	Props.bench(p, b, 0.36, 11.2, 90.0, 3.4, Props.IRON)
	Props.cell_toilet(p, b, 2.6, 13.05, 180.0)
	p.slab(n, false, 0.09, 4.9, 5.8, 0.0, 2.05, 0.04, Color(0.36, 0.4, 0.44))       # the prisoner door, shut
	Props.words(n, "HOLDING", p.pt(1.5, 8.64, 2.55), 0.18, Color(0.9, 0.9, 0.85))
	# The jury room.
	Props.table(p, b, 16.6, 9.0, 90.0, 3.2, 1.1, Props.WOOD)
	for v in [8.0, 9.0, 10.0]:
		Props.chair(p, b, 17.5, v, 270.0, Props.VINYL)
	Props.chair(p, b, 16.6, 7.05, 0.0, Props.VINYL)
	Props.chair(p, b, 16.6, 10.95, 180.0, Props.VINYL)
	Props.coffee(p, b, 16.95, 4.97)
	Props.cooler(p, b, 17.6, 13.05)
	Props.poster(p, b, 17.92, 12.0, 270.0, 0.8, 0.6, Color(0.5, 0.45, 0.3), "NO VERDICT, NO LUNCH", 1.7)


static func _back(p: Node3D, b: int) -> void:
	# Records: dead files, boxes, and a bucket under the leak.
	Props.shelves(p, b, 4.0, 0.33, 0.0, 7.4)
	Props.shelves(p, b, 4.0, 1.55, 0.0, 7.4)
	Props.boxes(p, b, 1.2, 3.8, 5)
	Props.boxes(p, b, 5.4, 3.9, 3)
	Props.bucket(p, b, 7.2, 3.3)
	# Chambers: law books, a big desk, a couch, the robe on its stand.
	Props.shelves(p, b, 12.0, 0.33, 0.0, 5.2, "books", Props.WOOD_DARK)
	Props.desk(p, b, 12.6, 1.95, 180.0, Props.WOOD_DARK.lightened(0.1), 2, true, 2.2, 0.9)
	Props.chair(p, b, 12.1, 3.15, 180.0, Props.VINYL)
	Props.chair(p, b, 13.1, 3.15, 180.0, Props.VINYL)
	Props.couch(p, b, 17.45, 2.3, 270.0, 2.4, Color(0.32, 0.18, 0.14))
	Props.robe(p, b, 15.8, 0.5)
	Props.flag(p, b, 16.9, 0.45)
	Props.rug(p, b, 13.0, 2.9, 3.4, 2.0, Color(0.4, 0.14, 0.14))
	Props.poster(p, b, 9.09, 1.4, 90.0, 0.6, 0.45, Color(0.85, 0.82, 0.7), "", 1.8)
	Props.poster(p, b, 9.09, 4.05, 90.0, 0.5, 0.4, Color(0.85, 0.82, 0.7), "", 1.8)
