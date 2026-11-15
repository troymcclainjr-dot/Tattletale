extends RefCounted
## The gun store: PEN LUCY ARMS, a one-storey formstone shop with bars on its windows and a buzzer by its steel
## door. 10 x 16 m inside, three bands from the street back:
##
##   the sales floor          three glass cases across it, the till at their end, the clerk behind them, the long
##                            guns and the rounds on the wall behind him
##   workshop | range door    the gunsmith's bench, the safe and the desk; a lobby between the two doors of the range
##   the range                three booths along its front, a target on a track down each lane, the backstop
##
## E at the counter (the BUY spot) opens the list of what he can buy; E in a booth (NEW TARGET) sends that lane's
## target in for a fresh paper and back out. Both are gun_shop.gd's, the "GunShop" node made here; the shots, and
## the marks they leave, are combat's. Downrange is kept clear: nobody walks past the firing line.
##
## Invented names and signs (placeholders): PEN LUCY ARMS (the shop), "FIREARMS - AMMUNITION - INDOOR RANGE" under
## its name, the neons GUNS and OPEN, RING FOR ENTRY under the buzzer, RANGE over the double door, NO LOADED GUNS
## on the sales floor, "EYES AND EARS" in the lobby, RANGE RULES, BUY and NEW TARGET over the spots E works at, and
## next door PAWN with "CASH FOR GOLD". What the list sells and for how much is in gun_shop.gd.
##
## Numbers are metres on the plan (see place.gd): u from the left wall, v from the back wall; the street is at v = 16.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Gun := preload("res://scripts/props_gun.gd")
const GunShop := preload("res://scripts/gun_shop.gd")

const F := 16.075                   # the shop's street face
const LANES := [3.0, 5.0, 7.0]      # the middle of each lane of the range
const LINE := 4.6                   # the firing line: the front edge of the booths' shelves
const HOME := 1.75                  # where a target hangs downrange
const STAND := 5.3                  # where he stands in a booth
const RED := Color(0.72, 0.1, 0.08)
const CREAM := Color(0.95, 0.92, 0.84)


static func build(p: Node3D) -> void:
	p.setup("GUN STORE", 10.0, 16.0)
	var formstone := Kit.tex("in_formstone", 1.4, Color(0.6, 0.58, 0.55), true, Color(0.8, 0.78, 0.74))
	var buff := _block(Color(0.8, 0.74, 0.6))           # the sales floor: dingy tan block
	var grey := _block(Color(0.64, 0.68, 0.72))         # the back: cold grey
	var dark := _block(Color(0.36, 0.37, 0.4))          # the range
	var carpet := Kit.tex("in_carpet", 1.0, Color(0.42, 0.44, 0.48), true, Color(0.5, 0.53, 0.58))      # worn grey carpet tile
	var concrete := Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.74))
	var lino := Kit.tex("lino", 1.4, Color(0.45, 0.45, 0.44), true, Color(0.7, 0.7, 0.68))
	var tube := Color(1.0, 0.98, 0.9)
	var steel_door := Color(0.34, 0.36, 0.4)
	var frame := Color(0.2, 0.2, 0.22)

	var st: int = p.street(-4.0, 14.0)
	var b1: int = p.band()
	var b2: int = p.band()
	var b3: int = p.band()
	p.arrive = p.pt(7.1, 17.2)

	p.room("SALES FLOOR", b1, 0, 9.6, 10, 16, carpet, {"light": tube, "energy": 0.7})
	p.room("WORKSHOP", b2, 0, 6.6, 6.2, 9.6, concrete, {"light": tube, "energy": 0.45})
	p.room("RANGE DOOR", b2, 6.2, 6.6, 10, 9.6, lino, {"light": tube, "energy": 0.45})
	p.room("RANGE", b3, 0, 0, 10, 6.6, concrete, {"light": Color(1.0, 0.96, 0.88), "energy": 0.6, "look_y": 1.3})      # the targets hang high

	var front: Node3D = p.cross(b1, 16.0, 0, 10, formstone, [
		{"a": 0.7, "b": 5.6, "kind": "window", "sill": 0.8, "head": 2.3, "bars": true, "frame": frame},
		{"a": 6.6, "b": 7.55, "head": 2.15, "colour": steel_door, "frame": frame},
		{"a": 8.35, "b": 9.45, "kind": "window", "sill": 0.95, "head": 2.2, "bars": true, "frame": frame},
	], {"h": 4.4})
	_wired(p.doors[p.doors.size() - 1], 0.93)
	p.side(b1, 0.0, 9.6, 16, buff)
	p.side(b1, 10.0, 9.6, 16, buff)
	p.cross(b2, 9.6, 0, 10, buff, [{"a": 7.4, "b": 9.0, "kind": "double", "colour": steel_door, "frame": frame, "name": "RANGE"}])
	p.side(b2, 0.0, 6.6, 9.6, grey)
	p.side(b2, 10.0, 6.6, 9.6, grey)
	p.side(b2, 6.2, 6.6, 9.6, grey, [{"a": 8.3, "b": 9.2, "hinge": "a", "swing": -1, "colour": Color(0.42, 0.3, 0.2), "name": "WORKSHOP"}])
	p.cross(b3, 6.6, 0, 10, grey, [
		{"a": 6.5, "b": 8.1, "kind": "window", "sill": 0.95, "head": 2.05, "frame": frame},
		{"a": 8.55, "b": 9.5, "colour": steel_door, "frame": frame, "name": "RANGE"},
	])
	p.side(b3, 0.0, 0, 6.6, dark)
	p.side(b3, 10.0, 0, 6.6, dark)
	p.cross(b3, 0.0, 0, 10, dark, [], {"back": true})

	var shop: Node = GunShop.new()
	shop.name = "GunShop"
	p.add_child(shop)
	_street(p, st, front)
	_floor(p, b1, shop)
	_back(p, b2)
	_range(p, b3, shop)
	_dress(p, b1, b2, b3)


## The steel front door gets a small window of wired glass, barred on the street side (place.gd made the plain
## leaf: its hinge on the right, so the leaf runs to -x).
static func _wired(door: Node3D, w: float) -> void:
	var x := -w * 0.5
	Kit.pane(Kit.box(door.leaf, Vector3(0.3, 0.42, 0.116), Vector3(x, 1.5, 0), Kit.flat(Color(0.62, 0.74, 0.76), 0.2)))      # combat: a shot breaks it
	for s: float in [-1.0, 1.0]:
		Kit.box(door.leaf, Vector3(0.36, 0.03, 0.124), Vector3(x, 1.5 + s * 0.225, 0), Color(0.24, 0.25, 0.28))
		Kit.box(door.leaf, Vector3(0.03, 0.42, 0.124), Vector3(x + s * 0.165, 1.5, 0), Color(0.24, 0.25, 0.28))
	for k in 3:
		Kit.cyl(door.leaf, 0.01, 0.42, Vector3(x - 0.075 + k * 0.075, 1.5, 0.068), Props.STEEL, Vector3.ZERO, 5)
	Kit.box(door.leaf, Vector3(0.05, 0.16, 0.05), Vector3(-w + 0.12, 1.02, 0.07), Props.STEEL)          # the pull
	Kit.box(door.leaf, Vector3(0.12, 0.05, 0.02), Vector3(-w + 0.12, 1.25, 0.055), Color(0.7, 0.62, 0.3))     # the lock


## A piece standing `d` proud of the shop's street face, its back 1 cm into the wall.
static func _proud(p: Node3D, n: Node3D, a: float, b: float, y0: float, y1: float, d: float, look: Variant) -> void:
	p.slab(n, true, F + (d - 0.01) * 0.5, a, b, y0, y1, d + 0.01, look)


static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var coal := Color(0.16, 0.16, 0.18)
	var stone := Color(0.84, 0.82, 0.76)
	# The name on a lit box over it all, what the shop does on a dark band under that, three lamps over the name,
	# a stone coping along the top; a stone sill under the window; the buzzer and a camera by the door.
	Props.sign_box(front, "PEN LUCY ARMS", p.pt(5.0, F + 0.065, 3.5), Vector2(8.6, 0.9), CREAM, RED, 0.0, 0.5, 0.6)
	_proud(p, front, 0.55, 9.42, 2.5, 2.95, 0.03, coal)
	Props.words(front, "FIREARMS  -  AMMUNITION  -  INDOOR RANGE", p.pt(5.0, F + 0.035, 2.725), 0.2, CREAM)
	for u: float in [2.0, 5.0, 8.0]:
		In.gooseneck(p, front, u, 16.0, 4.1, Color(0.14, 0.14, 0.16))
	p.slab(front, true, 16.0, -0.05, 10.05, 4.4, 4.52, 0.3, stone)
	_proud(p, front, 0.6, 5.7, 0.62, 0.72, 0.07, stone)
	Gun.buzzer(front, p.pt(7.95, F, 1.4), "RING FOR ENTRY")
	In.camera(p, front, 7.95, F, 0.0, 2.32)
	# GUNS in the window, behind the bars; OPEN on the wall by the door, where the bars do not cut it up.
	Props.neon(front, "GUNS", p.pt(2.6, 16.03, 1.75), 0.42, Color(1.0, 0.25, 0.2))
	Props.neon(front, "OPEN", p.pt(7.95, F + 0.03, 1.88), 0.15, Color(0.4, 1.0, 0.5))
	# Next door on the left: a pawn shop, its window barred and lit. On the right: the row.
	var brick := Kit.tex("brick", 1.5, Color(0.5, 0.3, 0.24), true, Color(0.9, 0.8, 0.72))
	p.slab(n, true, 16.0, -12.0, 0.0, 0.0, 4.0, 0.15, brick)
	p.slab(n, true, 16.0, -12.0, -0.01, 4.0, 4.1, 0.27, stone)
	p.slab(n, true, 16.085, -9.0, -3.6, 0.7, 2.3, 0.03, Kit.flat(Color(0.95, 0.9, 0.72), 0.8))
	for i in 14:
		var bu := -8.8 + i * 0.37
		p.slab(n, true, 16.12, bu, bu + 0.04, 0.66, 2.34, 0.03, Props.IRON)
	p.slab(n, true, 16.125, -9.0, -3.6, 2.3, 2.36, 0.045, Props.IRON)
	p.slab(n, true, 16.125, -9.0, -3.6, 0.64, 0.7, 0.045, Props.IRON)
	p.slab(n, true, 16.1, -2.8, -1.9, 0.0, 2.1, 0.03, Color(0.45, 0.47, 0.5))
	Props.sign_box(n, "PAWN", p.pt(-6.3, 16.14, 3.0), Vector2(3.4, 0.7), Color(0.98, 0.84, 0.2), Color(0.1, 0.18, 0.42), 0.0, 0.6)
	Props.words(n, "CASH FOR GOLD", p.pt(-6.3, 16.155, 1.95), 0.17, RED)
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	Props.rowhouse(p, n, 10.0, 16.0, old_brick, true)
	Props.rowhouse(p, n, 15.0, 16.0, old_brick, false, true)
	# On the pavement.
	Props.street_lamp(p, st, -0.6, 18.05)          # by the party wall, clear of the shop's name
	Props.bin(p, st, 0.4, 16.45)
	Props.hydrant(p, st, 10.8, 18.0)


static func _floor(p: Node3D, b: int, shop: Node) -> void:
	var n: Node3D = p.node_of(b)
	# The cases across the floor, the till on a wooden counter at their end; the clerk behind them, with the
	# long guns and the rounds on the wall at his back. BUY is where E opens the list.
	Gun.glass_case(p, b, 1.8, 11.3, 0.0, 1.7, 0.6, ["pistol", "pistol", "pistol"])
	Gun.glass_case(p, b, 3.52, 11.3, 0.0, 1.7, 0.6, ["pistol", "uzi", "pistol"])
	Gun.glass_case(p, b, 5.24, 11.3, 0.0, 1.7, 0.6, ["uzi", "pistol", "uzi"])
	var till: Node3D = Props.counter(p, b, 6.55, 11.3, 0.0, 0.85, 0.6, 0.98, Props.WOOD_DARK, Color(0.3, 0.3, 0.32))
	Props.till(till, Vector3(0.05, 0.98, 0.0), 180.0)
	Gun.rifle_rack(p, b, 1.86, 9.865, 0.0, 3.2, 0.34, 6)
	Gun.ammo_shelves(p, b, 4.75, 9.905, 0.0, 2.1, 1.9, 0.42)
	p.person(b, "clerk", 4.1, 10.48, {"name": "CLERK", "face": "bored"})      # clear of the machine pistols on their hooks, and of the shelves
	var buy: Node3D = p.use_point(b, "BUY", 4.1, 12.05, "gun:counter", 1.0, 2.0)
	buy.used.connect(Callable(shop, "use"))
	In.picture(p, b, 6.55, 9.69, 0.0, 0.36, 0.46, "certificate", Color(0.78, 0.6, 0.22), 1.65)
	Props.sign_box(n, "RANGE", p.pt(8.2, 9.75, 2.5), Vector2(0.9, 0.26), CREAM, RED, 0.0, 0.4)          # its back on the paint
	# On the left wall, fresh targets for sale; on the right, a bench to wait for a lane on.
	Gun.target_board(p, b, 0.09, 13.2, 90.0, 3, 1.6)
	Props.bench(p, b, 9.6, 13.4, 270.0, 1.6, Props.WOOD, true, 0.5)
	_notice(n, p.pt(9.912, 11.6, 1.6), 270.0, "NO LOADED\nGUNS")          # its back on the paint (9.916 on this wall)
	In.camera(p, b, 9.915, 15.7, 270.0, 2.5)
	In.strip_light(p, b, 2.6, 11.3, 0.0, 1.3, 2.5)
	In.strip_light(p, b, 4.9, 11.3, 0.0, 1.3, 2.5)


static func _back(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The workshop: the bench under its tools, the safe, the desk with the camera pictures, shelves of parts.
	Gun.workbench(p, b, 1.65, 7.07, 0.0, 2.4, 0.75)
	In.pegboard(p, b, 1.65, 6.69, 0.0, 1.6, 0.8, 1.72, "tools")
	Gun.gun_safe(p, b, 3.55, 7.045, 0.0)
	Props.desk(p, b, 5.1, 7.07, 0.0, Props.OFFICE, 0, true, 1.3, 0.75)
	Gun.cameras_screen(n, p.pt(5.1, 6.93, 0.765), 0.0)
	Props.shelves(p, b, 0.32, 8.55, 90.0, 1.5, "boxes", Props.IRON, 1.9, 0.45)
	Props.clock(p, b, 3.55, 6.69, 0.0, 2.4)
	# The lobby: a bench to wait on (kept back from the range door, so the way in stays clear), muffs on hooks by
	# the window, the words over them.
	Props.bench(p, b, 9.6, 8.0, 270.0, 1.2, Props.WOOD, false, 0.5)
	for k in 3:
		_muffs(n, p.pt(6.285, 7.05 + k * 0.32, 1.45), [Color(0.85, 0.15, 0.1), Color(0.18, 0.18, 0.2), Color(0.95, 0.7, 0.1)][k])
	Props.sign_box(n, "EYES AND EARS", p.pt(6.35, 7.37, 1.88), Vector2(1.0, 0.18), CREAM, RED, 90.0, 0.3, 0.1)
	In.extinguisher(p, b, 9.915, 9.15, 270.0, 0.8)


## A notice on a wall's face at `at` (it faces +z after `yaw`): a red-edged cream board, the words in red on it.
static func _notice(n: Node3D, at: Vector3, yaw: float, text: String) -> void:
	var g := Kit.group(n, at, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.62, 0.42, 0.012), Vector3(0, 0, 0.006), RED)
	Kit.box(g, Vector3(0.56, 0.36, 0.004), Vector3(0, 0, 0.014), CREAM)
	Props.words(g, text, Vector3(0, 0, 0.018), 0.075, RED)


## A pair of ear muffs on a hook on the wall at `at` (the wall faces +x there): two cups on a band.
static func _muffs(n: Node3D, at: Vector3, look: Color) -> void:
	var g := Kit.group(n, at, Vector3(0, 90, 0))
	Kit.box(g, Vector3(0.02, 0.02, 0.07), Vector3(0, 0.1, 0.035), Props.STEEL)
	Kit.tube(g, Vector3(-0.07, 0.0, 0.06), Vector3(0, 0.09, 0.06), 0.012, Props.DARK)
	Kit.tube(g, Vector3(0, 0.09, 0.06), Vector3(0.07, 0.0, 0.06), 0.012, Props.DARK)
	for s: float in [-1.0, 1.0]:
		Kit.cyl(g, 0.045, 0.04, Vector3(s * 0.075, -0.03, 0.06), look, Vector3(0, 0, 90), 12)


static func _range(p: Node3D, b: int, shop: Node) -> void:
	# The booths: a partition each side of each lane, a shelf across each one's front with the target's buttons,
	# the track overhead and the target on it. NEW TARGET is where E sends a lane's target in and out again.
	for u: float in [2.0, 4.0, 6.0, 8.0]:
		Gun.partition(p, b, u, 4.4, 5.6, 1.7)
	for i in LANES.size():
		var u: float = LANES[i]
		Gun.booth_shelf(p, b, u - 0.94, u + 0.94, LINE, 0.36)
		Gun.track(p, b, u, 1.2, 4.75, 2.5)
		shop.call("add_lane", Gun.target(p, b, u, HOME, null, 2.5, "TargetPaper%d" % (i + 1)), 2.45, p.pt(u, STAND))
		var point: Node3D = p.use_point(b, "NEW TARGET", u, STAND, "range:%d" % (i + 1), 0.8, 2.0)
		point.used.connect(Callable(shop, "use"))
		In.strip_light(p, b, u, 5.15, 0.0, 1.2, 2.55)
	# The firing line either side of the booths: a rail. Past it, downrange, nobody walks.
	p.rail(b, true, LINE + 0.18, 0.1, 1.94, Props.IRON)
	p.rail(b, true, LINE + 0.18, 8.06, 9.9, Props.IRON)
	p.block(0.0, 0.0, 10.0, LINE + 0.1)
	Gun.backstop(p, b, 0.085, 9.915, 1.1, 2.5)
	for u: float in [4.0, 6.0]:
		In.pendant(p, b, u, 2.6, 2.3, Color(0.2, 0.2, 0.22), "cone")
	# By the booths: the rules on the left wall, a bucket for the brass; the extinguisher by the door.
	Props.poster(p, b, 0.085, 5.55, 90.0, 0.7, 0.9, Color(0.9, 0.86, 0.74), "RANGE RULES", 1.6)
	var can: Node3D = p.prop(b, 0.42, 5.15, 0.0, 0.4, 0.4)
	Kit.cyl(can, 0.19, 0.62, Vector3(0, 0.31, 0), Color(0.3, 0.42, 0.34), Vector3.ZERO, 12)
	Kit.cyl(can, 0.2, 0.03, Vector3(0, 0.62, 0), Color(0.22, 0.32, 0.26), Vector3.ZERO, 12)
	Kit.cyl(can, 0.17, 0.02, Vector3(0, 0.616, 0), Color(0.86, 0.68, 0.3), Vector3.ZERO, 12)      # spent brass in it
	In.extinguisher(p, b, 9.915, 5.4, 270.0, 0.8)
	var yellow := Color(0.98, 0.8, 0.15)
	In.mat(p, b, 1.0, LINE + 0.34, 1.8, 0.05, yellow)
	In.mat(p, b, 9.0, LINE + 0.34, 1.8, 0.05, yellow)


## Painted block in colour c (block_plain is near white, so the tint is the colour).
static func _block(c: Color) -> Material:
	return Kit.tex("block_plain", 1.2, c, true, c)


## The rooms' walls. The sales floor: steel tread plate to the dado, tan block over it. The workshop and the
## lobby: grey block. The range: dark block under grey sound panels.
static func _dress(p: Node3D, b1: int, b2: int, b3: int) -> void:
	var coal := Color(0.16, 0.16, 0.18)
	var steel := Props.IRON
	var sales := {"lower": Kit.tex("in_diamond", 0.5, Color(0.6, 0.62, 0.64), true, Color(0.78, 0.8, 0.84)),
			"upper": _block(Color(0.8, 0.74, 0.6)),
			"dado": steel, "dado_y": 1.0, "skirt": coal, "skirt_h": 0.1, "surround": steel}
	In.room_walls(p, b1, 0, 9.6, 10, 16, sales, [{"a": 7.4, "b": 9.0, "kind": "double"}], [], [])
	In.border(p, b1, 0, 9.6, 10, 16, coal, 0.22)
	In.mat(p, b1, 7.075, 15.5, 1.1, 0.7, Color(0.22, 0.22, 0.24), Color(0.12, 0.12, 0.13))
	var back := {"lower": _block(Color(0.42, 0.46, 0.5)),
			"upper": _block(Color(0.66, 0.7, 0.74)),
			"dado": coal, "dado_y": 1.1, "skirt": coal, "skirt_h": 0.1, "surround": coal}
	In.room_walls(p, b2, 0, 6.6, 6.2, 9.6, back, [], [], [{"a": 8.3, "b": 9.2}])
	In.room_walls(p, b2, 6.2, 6.6, 10, 9.6, back, [{"a": 6.5, "b": 8.1, "kind": "window", "sill": 0.95, "head": 2.05}, {"a": 8.55, "b": 9.5}],
			[{"a": 8.3, "b": 9.2}], [])
	In.pendant(p, b2, 2.6, 8.2, 2.25, Color(0.3, 0.3, 0.32), "bulb")
	var range_walls := {"lower": _block(Color(0.36, 0.37, 0.4)),
			"upper": Kit.tex("in_acoustic", 0.6, Color(0.55, 0.55, 0.56), true, Color(0.7, 0.7, 0.72)),
			"dado": coal, "dado_y": 1.2, "skirt": coal, "skirt_h": 0.1}
	In.room_walls(p, b3, 0, 0, 10, 6.6, range_walls, [], [], [])
