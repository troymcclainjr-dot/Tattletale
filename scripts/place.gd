extends Node3D
## A place built from a floor plan: the street outside and the rooms inside.
## One of these is made for each place on the travel list (police station,
## courthouse, the crib); `plans/*.gd` say what goes where.
##
## Plans are written in metres as on the drawings in the layouts folder: u runs
## left to right, v from the back of the building (0) to the street (`depth` is
## the front wall). `pt(u, v)` turns that into the world: x right, z towards the
## camera, the front wall on z = 0 and the pavement in front of it.
##
## The building is a stack of BANDS, front to back, and a band holds one or
## more rooms side by side. The camera always looks in from the street, so
## standing in a band, every band nearer the street is hidden and the wall just
## in front becomes a low strip, as in building.gd.
## A second floor is another LEVEL: its own stack of bands, drawn off to one
## side of the plan (u + 40, say) and reached by a portal (portal.gd).
##
## A wall that is cut away keeps its doors: each stands where it was, whole
## but see-through (door.gd's cut_away), so he can still find it and see
## whether it is open.
##
##   var p = Place.new()          p.setup("POLICE STATION", 16.0, 22.0)
##   var street := p.street(-3.0, 19.0)            # band 0: the pavement
##   var b1 := p.band()                            # the first band indoors
##   p.room("LOBBY", b1, 0, 17, 10.5, 22, floor_look)
##   p.cross(b1, 22.0, 0, 16, brick, [{"a": 4.2, "b": 6.0, "kind": "double"}])   # the wall in FRONT of b1
##   p.side(b1, 10.5, 17, 22, wall_look, [{"a": 18.4, "b": 20.7, "kind": "window"}])
##   var desk := p.prop(b1, 5.0, 19.0, 0.0, 1.5, 0.75)    # a group to build a prop in; its floor space is kept clear
##
## An opening is a Dictionary: "a" and "b" (where along the wall), "kind"
## (door, double, arch, window), and optionally "sill", "head", "hinge" ("a" or
## "b"), "swing" (-1 opens towards the back or the left, +1 towards the street
## or the right), "colour", "bars", "blinds", "pane" (glass colour), "name".

const Door := preload("res://scripts/door.gd")
const Portal := preload("res://scripts/portal.gd")
const UsePoint := preload("res://scripts/use_point.gd")

const RADIUS := 0.26                 # paper_actor.gd's: how close a middle may come to a wall in front of him or behind
const REACH := 0.4                   # and to a wall beside him: his hands and feet reach that far (paper_actor.gd)
const T := 0.15                      # wall thickness
const LEAF := 0.1                    # how thick a door is: most of the way through its frame
const EDGE := Color(0.07, 0.06, 0.12)
const FRAME := Color(0.23, 0.16, 0.11)
const GLASS := Color(0.62, 0.8, 0.88, 0.22)
const STEEL := Color(0.3, 0.32, 0.36)

var title := ""
var width := 10.0
var depth := 10.0
var wall_h := 2.9
var arrive := Vector3.ZERO           # where he stands when he travels here
var ambient := 0.62                  # how bright the light that falls on everything is here, and the low sun: main.gd
var sun_energy := 0.55               # sets both when he arrives. Lower them and a place is night, lit by its own lamps
## "name", "band", "rect" (x, z), "areas" (where a middle may be), and the camera
## numbers main.gd reads: "cam_max_x", "cam_near", "cam_y", "look_y".
var rooms: Array = []
var bands: Array = []                # "node", "level", "order" (0 is nearest the street)
var doors: Array = []
var portals: Array = []
var use_points: Array = []           # spots E can be used at (use_point.gd): main.gd acts on their `id`
var obstacles: Array = []
var watchers: Array = []             # things that want to know where he is each frame (walk_light.gd): main.gd calls their `watch`
## Who stands about here. Each is a Dictionary: "rig" (a folder of
## assets/characters), "band", "at" (on the floor), and optionally "name",
## "face" (an expression), "roam" (a Rect2 of floor they wander), "talk" (a
## conversation in assets/data), "speed", "reach". main.gd makes them.
var people: Array = []
var active := -1                     # the room on show

var _fronts: Array = []              # walls that are cut away: "band", "node", "stub", "doors"
var _always: Array = []              # doorways with no door: always open


func setup(place_title: String, w: float, d: float) -> void:
	title = place_title
	width = w
	depth = d


func pt(u: float, v: float, y := 0.0) -> Vector3:
	return Vector3(u - width * 0.5, y, v - depth)


func rect(u0: float, v0: float, u1: float, v1: float) -> Rect2:
	return Rect2(u0 - width * 0.5, v0 - depth, u1 - u0, v1 - v0)


# ------------------------------------------------------------------ the plan

## A new band behind the last one on this level. Returns its number.
func band(level := 0) -> int:
	var order := 0
	for b: Dictionary in bands:
		if b["level"] == level:
			order += 1
	bands.append({"node": Kit.group(self, Vector3.ZERO, Vector3.ZERO, "Band%d" % bands.size()), "level": level, "order": order})
	return bands.size() - 1


func node_of(b: int) -> Node3D:
	return bands[b]["node"]


## The pavement, kerb and road in front: band 0. u0..u1 is how far along the
## street he may walk.
func street(u0: float, u1: float, pave := 2.5) -> int:
	var b := band()
	room("street", b, u0, depth, u1, depth + pave, null, {"street": true})
	var n := node_of(b)
	var mid := (u0 + u1) * 0.5
	var long := u1 - u0 + 16.0
	# Concrete slabs, a kerb standing a little proud of them, the gutter along its
	# foot and the road (outdoor.gd's textures, with the old ones to fall back on).
	var outdoor = load("res://scripts/outdoor.gd")
	var walk: Variant = outdoor.pavement() if outdoor else Kit.tex("sidewalk", 2.4, Color(0.66, 0.64, 0.6))
	var tar: Variant = outdoor.road() if outdoor else Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27))
	Kit.box(n, Vector3(long, 0.3, pave), pt(mid, depth + pave * 0.5, -0.15), walk)
	Kit.box(n, Vector3(long, 0.32, 0.2), pt(mid, depth + pave + 0.1, -0.14), Color(0.84, 0.82, 0.77))
	Kit.box(n, Vector3(long, 0.3, 7.0), pt(mid, depth + pave + 3.7, -0.29), tar)
	Kit.box(n, Vector3(long - 0.02, 0.012, 0.36), pt(mid, depth + pave + 0.38, -0.136), Color(0.42, 0.43, 0.46))
	for i in int(long / 3.4):
		Kit.box(n, Vector3(1.4, 0.01, 0.12), pt(mid - long * 0.5 + 1.5 + i * 3.4, depth + pave + 3.4, -0.135), Color(0.85, 0.8, 0.55))
	return b


## A room: its floor, and where it is on the plan. opts: "areas" (a list of
## [u0, v0, u1, v1], when not the whole room can be walked), "light" (a colour:
## hangs a lamp in the middle), "cam_near", "cam_y", "look_y", "hole" ([u0, v0,
## u1, v1]: no floor there, for a stairwell).
func room(room_name: String, b: int, u0: float, v0: float, u1: float, v1: float, floor_look: Variant, opts := {}) -> int:
	var r := rect(u0, v0, u1, v1)
	var mid := r.get_center()
	if floor_look != null and opts.has("hole"):
		# The floor in four pieces round the hole: left, right, behind, in front.
		var h: Array = opts["hole"]
		for piece: Array in [[u0, v0, h[0], v1], [h[2], v0, u1, v1], [h[0], v0, h[2], h[1]], [h[0], h[3], h[2], v1]]:
			if piece[2] - piece[0] > 0.001 and piece[3] - piece[1] > 0.001:
				var fr := rect(piece[0], piece[1], piece[2], piece[3])
				Kit.box(node_of(b), Vector3(fr.size.x, 0.3, fr.size.y), Vector3(fr.get_center().x, -0.15, fr.get_center().y), floor_look)
	elif floor_look != null:
		Kit.box(node_of(b), Vector3(r.size.x, 0.3, r.size.y), Vector3(mid.x, -0.15, mid.y), floor_look)
	var outdoors: bool = opts.get("street", false)
	var areas: Array = []
	for a: Array in opts.get("areas", [[u0, v0, u1, v1]]):
		areas.append(rect(a[0], a[1], a[2], a[3]).grow_individual(-(T * 0.5 + REACH), -(T * 0.5 + RADIUS), -(T * 0.5 + REACH), -(T * 0.5 + RADIUS)))
	rooms.append({
		"name": room_name, "band": b, "rect": r, "areas": areas,
		"cam_max_x": 99.0 if outdoors else r.end.x - 1.7,
		"cam_near": opts.get("cam_near", 1.45 if outdoors else 1.1),
		"cam_y": opts.get("cam_y", 2.9 if outdoors else 2.6),
		"look_y": opts.get("look_y", 1.35 if outdoors else 0.85),
	})
	if opts.has("light"):
		Kit.omni(node_of(b), Vector3(mid.x, 2.5, mid.y), opts["light"], opts.get("energy", 0.5), maxf(r.size.x, r.size.y) * 0.8 + 2.0)
	return rooms.size() - 1


## A wall running left to right at v, in FRONT of band b: it is cut away when
## someone stands in band b. Give opts "back": true for a wall behind the band
## (it is never cut). Returns the node the wall is built in, for signs and such.
func cross(b: int, v: float, u0: float, u1: float, look: Variant, openings := [], opts := {}) -> Node3D:
	var h: float = opts.get("h", wall_h)
	var t: float = opts.get("t", T)
	if opts.get("back", false):
		_run(node_of(b), node_of(b), true, v, u0, u1, h, look, openings, t)
		return node_of(b)
	var node := Kit.group(self, Vector3.ZERO, Vector3.ZERO, "Front%d" % _fronts.size())
	var made := _run(node, self, true, v, u0, u1, h, look, openings, t)
	var stub := Kit.group(self, Vector3.ZERO, Vector3.ZERO, "Front%dStub" % _fronts.size())
	var cursor := u0
	for op: Dictionary in _sorted(openings):
		if op.get("kind", "door") != "window":
			if op["a"] > cursor:
				slab(stub, true, v, cursor, op["a"], 0.0, 0.14, t, EDGE)
			cursor = op["b"]
	if u1 > cursor:
		slab(stub, true, v, cursor, u1, 0.0, 0.14, t, EDGE)
	stub.visible = false
	_fronts.append({"band": b, "node": node, "stub": stub, "doors": made})
	return node


## A wall running front to back at u, from v0 to v1, that belongs to band b.
func side(b: int, u: float, v0: float, v1: float, look: Variant, openings := [], opts := {}) -> Node3D:
	_run(node_of(b), node_of(b), false, u, v0, v1, opts.get("h", wall_h), look, openings, opts.get("t", T))
	return node_of(b)


## A run of bars (cells, cages). `gaps` is a list of [from, to]: each gets a
## barred door. The rooms either side must be separate rooms.
func bars(b: int, along_u: bool, at: float, from: float, to: float, gaps := [], h := 2.4) -> void:
	var node := node_of(b)
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var runs: Array = []
	var cursor := from
	for g: Array in cuts:
		runs.append([cursor, g[0]])
		cursor = g[1]
	runs.append([cursor, to])
	slab(node, along_u, at, from, to, h - 0.06, h, 0.06, STEEL)
	for run: Array in runs:
		var length: float = run[1] - run[0]
		if length < 0.05:
			continue
		slab(node, along_u, at, run[0], run[1], 0.0, 0.06, 0.06, STEEL)
		var n := maxi(int(length / 0.12), 1)
		for i in n + 1:
			var w: float = run[0] + length * float(i) / float(n)
			Kit.cyl(node, 0.013, h - 0.12, pt(w, at, h * 0.5) if along_u else pt(at, w, h * 0.5), STEEL, Vector3.ZERO, 5)
	for g: Array in cuts:
		var door := _door(node, along_u, at, g[0], g[1], h - 0.06, {"bars": true, "hinge": "a", "swing": 1, "name": "CELL"})
		door.open_time = 0.9


## A waist-high rail (the bar of a court, a queue rail). People walk round it.
func rail(b: int, along_u: bool, at: float, from: float, to: float, look: Variant = Color(0.36, 0.24, 0.15), h := 0.95) -> void:
	var node := node_of(b)
	slab(node, along_u, at, from, to, h - 0.07, h, 0.09, look)
	slab(node, along_u, at, from, to, 0.12, 0.17, 0.05, look)
	var n := maxi(int((to - from) / 0.6), 1)
	for i in n + 1:
		var w := from + (to - from) * float(i) / float(n)
		Kit.box(node, Vector3(0.06, h - 0.07, 0.06), pt(w, at, (h - 0.07) * 0.5) if along_u else pt(at, w, (h - 0.07) * 0.5), look)
	if along_u:
		block(from, at - 0.045, to, at + 0.045)
	else:
		block(at - 0.045, from, at + 0.045, to)


## A group to build a prop in, standing at (u, v) on the floor and turned `yaw`
## degrees (0 faces the street, 90 faces right, 180 the back, 270 left). Its
## floor space, w wide and d deep before turning, is kept clear of walkers.
func prop(b: int, u: float, v: float, yaw: float, w: float, d: float, solid := true) -> Node3D:
	var at := pt(u, v)
	if solid:
		var turned := posmod(int(round(yaw / 90.0)), 2) == 1
		var sx := d if turned else w
		var sz := w if turned else d
		obstacles.append(Rect2(at.x - sx * 0.5, at.z - sz * 0.5, sx, sz))
	return Kit.group(node_of(b), at, Vector3(0, yaw, 0))


## Someone standing at (u, v): `rig` names their folder in assets/characters.
## opts: "name", "face", "talk", "speed", "reach", and "roam": [u0, v0, u1, v1],
## the floor they wander (without it they stand where they are put).
func person(b: int, rig: String, u: float, v: float, opts := {}) -> void:
	var who := opts.duplicate()
	who["rig"] = rig
	who["band"] = b
	who["at"] = pt(u, v)
	if opts.has("roam"):
		var r: Array = opts["roam"]
		who["roam"] = rect(r[0], r[1], r[2], r[3]).grow_individual(-T * 0.5, -T * 0.5, -T * 0.5, -T * 0.5)
	people.append(who)


## Floor space nobody may walk on.
func block(u0: float, v0: float, u1: float, v1: float) -> void:
	obstacles.append(rect(u0, v0, u1, v1))


## A spot that takes him somewhere else in this place when used (stairs).
func portal(b: int, label: String, u: float, v: float, to_u: float, to_v: float) -> Node3D:
	var p: Node3D = Portal.new()
	p.label = label
	p.position = pt(u, v)
	p.to = pt(to_u, to_v)
	node_of(b).add_child(p)
	portals.append(p)
	return p


## A spot E can be used at (use_point.gd): `label` shows over it, and main.gd
## acts on `id` ("outfit:hat", "sleep", ...: see main.gd's _use_point).
func use_point(b: int, label: String, u: float, v: float, id: String, reach := 1.1, label_height := 1.5) -> Node3D:
	var point: Node3D = UsePoint.new()
	point.id = id
	point.label = label
	point.use_reach = reach
	point.label_height = label_height
	point.position = pt(u, v)
	node_of(b).add_child(point)
	use_points.append(point)
	return point


## A fence out of doors, built in band b's own node (it is never cut away): it
## runs along u (left to right) or along v, at `at`, from `from` to `to`.
## `gaps` is a list of [from, to]: gateways, always open. The ground either
## side must be separate rooms; people cross only at the gaps. kind: "rail" (a
## low iron railing), "chain" (tall chain link on steel posts: you see through
## it), "wood" (a board fence: you do not).
func fence(b: int, along_u: bool, at: float, from: float, to: float, gaps := [], h := 1.1, kind := "rail", look: Variant = null) -> void:
	var node := node_of(b)
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var runs: Array = []
	var cursor := from
	for g: Array in cuts:
		runs.append([cursor, g[0]])
		cursor = g[1]
		_always.append(_passage(along_u, at, g[0], g[1]))
	runs.append([cursor, to])
	var colour: Variant = look if look != null else {"rail": Color(0.14, 0.15, 0.17), "chain": Color(0.55, 0.58, 0.6), "wood": Color(0.5, 0.36, 0.24)}[kind]
	var dark: Variant = (colour as Color).darkened(0.25) if colour is Color else colour
	# The out-of-doors pass's materials (outdoor.gd): see-through chain link, weathered boards.
	var outdoor = load("res://scripts/outdoor.gd")
	var lying := Vector3(0, 0, 90) if along_u else Vector3(90, 0, 0)       # turns a cylinder to lie along the fence
	for run: Array in runs:
		var length: float = run[1] - run[0]
		if length < 0.05:
			continue
		var bay: float = {"rail": 0.14, "chain": 2.4, "wood": 1.8}[kind]
		var n := maxi(int(round(length / bay)), 1)
		var mid: float = (run[0] + run[1]) * 0.5
		match kind:
			"rail":
				slab(node, along_u, at, run[0], run[1], h - 0.09, h - 0.04, 0.05, colour)
				slab(node, along_u, at, run[0], run[1], 0.12, 0.17, 0.05, colour)
				for i in n + 1:
					var w: float = run[0] + length * float(i) / float(n)
					var post := i % 8 == 0 or i == n
					Kit.cyl(node, 0.03 if post else 0.011, h + (0.08 if post else 0.0), pt(w, at, (h + (0.08 if post else 0.0)) * 0.5) if along_u else pt(at, w, (h + (0.08 if post else 0.0)) * 0.5), colour, Vector3.ZERO, 5)
					if post:                       # a ball on each post
						Kit.ball(node, 0.048, pt(w, at, h + 0.11) if along_u else pt(at, w, h + 0.11), colour, 8)
			"chain":
				# Round top rail and a tension wire along the foot; the mesh in one
				# see-through panel a bay, between line posts with caps, the ends heavier.
				Kit.cyl(node, 0.024, length, pt(mid, at, h - 0.03) if along_u else pt(at, mid, h - 0.03), colour, lying, 8)
				Kit.cyl(node, 0.008, length, pt(mid, at, 0.07) if along_u else pt(at, mid, 0.07), dark, lying, 4)
				var wire: Material = outdoor.chain_link() if outdoor else Kit.flat(Color(0.72, 0.76, 0.78, 0.22))
				for i in n:
					var a: float = run[0] + length * float(i) / float(n)
					var c: float = run[0] + length * float(i + 1) / float(n)
					var panel := MeshInstance3D.new()
					var q := QuadMesh.new()
					q.size = Vector2(c - a - 0.04, h - 0.1)
					panel.mesh = q
					panel.material_override = wire
					panel.position = pt((a + c) * 0.5, at, 0.06 + (h - 0.1) * 0.5) if along_u else pt(at, (a + c) * 0.5, 0.06 + (h - 0.1) * 0.5)
					panel.rotation_degrees = Vector3.ZERO if along_u else Vector3(0, 90, 0)
					node.add_child(panel)
				for i in n + 1:
					var w: float = run[0] + length * float(i) / float(n)
					var end := i == 0 or i == n
					var r := 0.05 if end else 0.036
					var top := h + (0.1 if end else 0.04)
					Kit.cyl(node, r, top, pt(w, at, top * 0.5) if along_u else pt(at, w, top * 0.5), colour, Vector3.ZERO, 8)
					Kit.cyl(node, r + 0.012, 0.05, pt(w, at, top + 0.015) if along_u else pt(at, w, top + 0.015), dark, Vector3.ZERO, 8)
			_:
				# Boards (out_boards, tinted to the fence's colour), two rails behind, square posts.
				var face: Variant = colour
				if colour is Color and outdoor:
					var cc: Color = colour
					face = outdoor.tex("out_boards", 1.2, cc, Color(minf(cc.r / 0.54, 1.0), minf(cc.g / 0.48, 1.0), minf(cc.b / 0.41, 1.0)))
				slab(node, along_u, at, run[0], run[1], 0.05, h, 0.04, face)
				slab(node, along_u, at - 0.03, run[0], run[1], h * 0.3, h * 0.3 + 0.08, 0.03, (colour as Color).darkened(0.18) if colour is Color else colour)
				slab(node, along_u, at - 0.03, run[0], run[1], h * 0.8, h * 0.8 + 0.08, 0.03, (colour as Color).darkened(0.18) if colour is Color else colour)
				for i in n + 1:
					var w: float = run[0] + length * float(i) / float(n)
					Kit.box(node, Vector3(0.1, h + 0.06, 0.1), pt(w, at, (h + 0.06) * 0.5) if along_u else pt(at, w, (h + 0.06) * 0.5), dark)
		if along_u:
			block(run[0], at - 0.04, run[1], at + 0.04)
		else:
			block(at - 0.04, run[0], at + 0.04, run[1])


## One box of wall: from a to b along the wall, y0 to y1 high, t thick.
func slab(parent: Node3D, along_u: bool, at: float, a: float, b: float, y0: float, y1: float, t: float, look: Variant) -> MeshInstance3D:
	var mid := (a + b) * 0.5
	if along_u:
		return Kit.box(parent, Vector3(b - a, y1 - y0, t), pt(mid, at, (y0 + y1) * 0.5), look)
	return Kit.box(parent, Vector3(t, y1 - y0, b - a), pt(at, mid, (y0 + y1) * 0.5), look)


func _sorted(openings: Array) -> Array:
	var out := openings.duplicate()
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["a"] < q["a"])
	return out


## Build a wall round its openings. Returns the doors it made.
func _run(node: Node3D, door_parent: Node3D, along_u: bool, at: float, from: float, to: float, h: float, look: Variant, openings: Array, t: float) -> Array:
	var made: Array = []
	# Walls that run front to back stop a centimetre lower, so where two walls
	# meet their tops are not two surfaces in one place (that flickers).
	var top := h if along_u else h - 0.01
	var cursor := from
	for op: Dictionary in _sorted(openings):
		var a: float = op["a"]
		var b: float = op["b"]
		var kind: String = op.get("kind", "door")
		var sill: float = op.get("sill", 0.95 if kind == "window" else 0.0)
		var head: float = op.get("head", 2.1 if kind == "window" else (2.3 if kind == "arch" else 2.05))
		if a > cursor:
			slab(node, along_u, at, cursor, a, 0.0, top, t, look)
		if sill > 0.0:
			slab(node, along_u, at, a, b, 0.0, sill, t, look)
		if head < top:
			slab(node, along_u, at, a, b, head, top, t, look)
		# The frame stands 15 mm into the opening: a frame face lying exactly on
		# the cut end of the wall flickers.
		# A door's frame is shallow, so the door sits close to its face and looks
		# snug in it; a window's is deeper.
		var frame: Color = op.get("frame", FRAME)
		var deep := t + (0.06 if kind == "window" else 0.03)
		slab(node, along_u, at, a - 0.055, a + 0.015, sill, head + 0.05, deep, frame)
		slab(node, along_u, at, b - 0.015, b + 0.055, sill, head + 0.05, deep, frame)
		slab(node, along_u, at, a - 0.055, b + 0.055, head - 0.015, head + 0.055, deep, frame)
		match kind:
			"window":
				slab(node, along_u, at, a - 0.055, b + 0.055, sill - 0.055, sill + 0.015, t + 0.06, frame)
				Kit.pane(slab(node, along_u, at, a, b, sill, head, 0.02, op.get("pane", GLASS)))      # combat: a shot breaks it
				var out := t * 0.5 + 0.045         # just proud of the frame, on the street (or right-hand) side
				if op.get("bars", false):
					var n := maxi(int((b - a) / 0.16), 2)
					for i in range(1, n):
						var w := a + (b - a) * float(i) / float(n)
						Kit.cyl(node, 0.012, head - sill, pt(w, at + out, (sill + head) * 0.5) if along_u else pt(at + out, w, (sill + head) * 0.5), STEEL, Vector3.ZERO, 5)
				if op.get("blinds", false):
					var rows := int((head - sill) / 0.09)
					for i in rows:
						slab(node, along_u, at - 0.03, a + 0.02, b - 0.02, head - 0.07 - i * 0.09, head - 0.02 - i * 0.09, 0.012, Color(0.88, 0.86, 0.78))
			"arch":
				_always.append(_passage(along_u, at, a, b))
			"double":
				var mid := (a + b) * 0.5
				# The two leaves meet in the middle: each is made 8 mm wider than its half, to close the usual gap.
				var left := _door(door_parent, along_u, at, a, mid + 0.008, head, op.merged({"hinge": "a"}, true))
				var right := _door(door_parent, along_u, at, mid - 0.008, b, head, op.merged({"hinge": "b"}, true))
				left.mate = right
				left.passage = _passage(along_u, at, a, b)
				left.set_middle(pt(mid, at) if along_u else pt(at, mid))
				right.passage = Rect2()
				right.set_middle(pt(mid, at) if along_u else pt(at, mid))
				right.set_meta("mate", true)
				made.append(left)
				made.append(right)
			_:
				made.append(_door(door_parent, along_u, at, a, b, head, op))
		cursor = b
	if to > cursor:
		slab(node, along_u, at, cursor, to, 0.0, top, t, look)
	return made


func _door(parent: Node3D, along_u: bool, at: float, a: float, b: float, head: float, op: Dictionary) -> Node3D:
	var door: Node3D = Door.new()
	var at_b: bool = op.get("hinge", "b") == "b"
	var swing: int = op.get("swing", -1)
	var to_left: bool
	if along_u:
		to_left = at_b
		door.position = pt(b - 0.01 if at_b else a + 0.01, at)
		door.open_angle = (-100.0 if at_b else 100.0) * (1.0 if swing < 0 else -1.0)
	else:
		to_left = not at_b
		door.shut_angle = 90.0
		door.position = pt(at, b - 0.01 if at_b else a + 0.01)
		door.open_angle = 190.0 if (swing > 0) != at_b else -10.0
	door.rotation.y = deg_to_rad(door.shut_angle)
	parent.add_child(door)
	var w := b - a - 0.02
	if op.get("bars", false):
		door.build_bars(w, head - 0.03, to_left)
	else:
		door.build_leaf(w, head - 0.012, op.get("colour", Color(0.4, 0.33, 0.26)), to_left, LEAF)
	if op.has("name"):
		door.open_name = "OPEN " + String(op["name"])
		door.shut_name = "CLOSE " + String(op["name"])
	door.passage = _passage(along_u, at, a, b)
	doors.append(door)
	return door


## Where a middle may be while going through a doorway: a strip down it that
## reaches into the rooms either side. Through a wall that runs left to right
## he walks facing the camera or away from it, arms out to both sides, so the
## strip is narrow: his hands stay clear of the frame. (He slides along the
## wall into it: paper_actor.gd's _step.) Through a wall that runs front to back he is side-on.
func _passage(along_u: bool, at: float, a: float, b: float) -> Rect2:
	if along_u:
		var reach := T * 0.5 + RADIUS + 0.04
		var keep := minf(REACH - 0.02, (b - a) * 0.5 - 0.05)
		return rect(a + keep, at - reach, b - keep, at + reach)
	var reach_x := T * 0.5 + REACH + 0.04
	return rect(at - reach_x, a + 0.2, at + reach_x, b - 0.2)


# ------------------------------------------------------- what the scene asks

## Which room a spot is in (`was` if it is in none, as in a doorway on the edge).
func room_at_pos(pos: Vector3, was := 0) -> int:
	var p := Vector2(pos.x, pos.z)
	for i in rooms.size():
		if (rooms[i]["rect"] as Rect2).has_point(p):
			return i
	return maxi(was, 0)


## Rooms with the same key are seen from the same cut: walking between them
## needs no fade.
func cut_of(n: int) -> int:
	return rooms[n]["band"]


## Show the band room n is in and every band behind it on that floor; hide the
## rest. The wall just in front becomes a low strip.
func show_room(n: int) -> void:
	active = n
	var here: Dictionary = bands[rooms[n]["band"]]
	for b: Dictionary in bands:
		b["node"].visible = b["level"] == here["level"] and b["order"] >= here["order"]
	for f: Dictionary in _fronts:
		var fb: Dictionary = bands[f["band"]]
		var same: bool = fb["level"] == here["level"]
		var full: bool = same and here["order"] < fb["order"]
		var cut: bool = same and here["order"] == fb["order"]
		f["node"].visible = full
		f["stub"].visible = cut
		for door: Node3D in f["doors"]:
			door.visible = full or cut
			door.cut_away(cut)


## Everything E can be used on here.
func usables() -> Array:
	var out: Array = []
	for door: Node3D in doors:
		if not door.has_meta("mate"):
			out.append(door)
	out.append_array(portals)
	out.append_array(use_points)
	return out


## Everywhere someone's middle may be: the rooms' floors, in from the walls, the
## doorways with no door, and each doorway whose door is open.
func walk_areas() -> Array:
	var out: Array = []
	for r: Dictionary in rooms:
		out.append_array(r["areas"])
	out.append_array(_always)
	for door: Node3D in doors:
		if door.is_open:
			out.append(door.passage)
	return out
