extends RefCounted
## Pieces for Rose Hill Terrace (plans/street.gd), the short copy of the old
## Pen Lucy's side street: the cobra-head street lamps and the wooden utility
## poles, the neighbourhood's parked cars, the corner sign post with its stop
## sign, a mailbox, a bus stop, litter. Its houses (the porch-front rowhouses
## with the projecting sash bays upstairs, the plain stoop-front ones) are
## built by the shared house kit, houses.gd; the names below hand them on, so
## Rose Hill keeps calling them here.
##
## A house front is built on a FACE (see houses.gd): a group standing at the
## front's left end, its x running along the front, y up, z out of the wall.
##
##   const Street := preload("res://scripts/props_street.gd")
##   Street.porch_house(p, band, 6.33, 10.0, 6.53, {"no": "518", "wall": brick, ...})
##   Street.parked_car(p, band, 13.5, 17.7, 270.0, "compact", Street.PAINT[1])
##
## Sizes and colours are the old game's (blender/city/kits.py, process.py and
## the measured street), the colours a touch brighter for the pop-up's night.

const Props := preload("res://scripts/props.gd")
const Houses := preload("res://scripts/houses.gd")

const WHITE := Houses.WHITE
const CREAM := Houses.CREAM
const BROWN := Houses.BROWN
const RED := Houses.RED
const GREEN := Houses.GREEN
const DOORS := Houses.DOORS
const PORCH := Houses.PORCH
const PORCH_ROOF := Houses.PORCH_ROOF
const TAR := Houses.TAR
const BASE := Houses.BASE
const MARBLE := Houses.MARBLE
const CONCRETE := Houses.CONCRETE
const PANE := Houses.PANE
const IRON := Houses.IRON
const LIT := Houses.LIT
const TV := Houses.TV
const GOLD := Houses.GOLD
const LAMP := Color(1.0, 0.88, 0.65)            # the street lamps (255, 224, 166)
## The parked cars' paints, in the old game's order.
const PAINT := [Color(0.36, 0.44, 0.52), Color(0.82, 0.78, 0.7), Color(0.36, 0.45, 0.39), Color(0.58, 0.33, 0.31), Color(0.53, 0.58, 0.62), Color(0.3, 0.33, 0.36)]

const F0 := Houses.F0
const CEIL := Houses.CEIL
const PROOF := Houses.PROOF
const PD := Houses.PD
const RISE := Houses.RISE
const BAYS := Houses.BAYS


# ------------------------------------------------------- the houses' names

static func face(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	return Houses.face(p, b, u, v, yaw)


static func sub_face(g: Node3D, a: Vector2, b: Vector2) -> Node3D:
	return Houses.sub_face(g, a, b)


static func fb(g: Node3D, s0: float, s1: float, y0: float, y1: float, t0: float, t1: float, look: Variant) -> MeshInstance3D:
	return Houses.fb(g, s0, s1, y0, y1, t0, t1, look)


static func pipe(g: Node3D, a: Vector3, b: Vector3, r: float, look: Variant, sides := 6) -> MeshInstance3D:
	return Houses.pipe(g, a, b, r, look, sides)


static func sash(g: Node3D, s: float, y0: float, ww: float, wh: float, trim: Color, lit: Variant = null, curtain: Variant = null, lintel: Variant = null, blind := false) -> void:
	Houses.sash(g, s, y0, ww, wh, trim, lit, curtain, lintel, blind)


static func painted_screen(g: Node3D, s: float, y0: float, ww: float, wh: float) -> void:
	Houses.painted_screen(g, s, y0, ww, wh)


static func porch_house(p: Node3D, b: int, u0: float, d: float, w: float, h: Dictionary) -> Node3D:
	return Houses.porch_house(p, b, u0, d, w, h)


static func porch_chair(g: Node3D, s: float, t: float, paint: Color, turn := 8.0) -> void:
	Houses.porch_chair(g, s, t, paint, turn)


static func plain_house(g: Node3D, w: float, height: float, wall: Variant, trim: Color, door: Color, lit := "", floors := 2, door_left := true) -> void:
	Houses.plain_house(g, w, height, wall, trim, door, lit, floors, door_left)


# ------------------------------------------------------------ street pieces

## A street lamp as the old game's network lamps: a dark pole straight up to
## 4.68 m, a gooseneck, and a cobra head whose lens hangs out over the road.
## It stands 0.65 m behind the kerb; `reach` is from the pole to the lens
## (the head reaches towards +z: turn the group to aim it). Its light is a spot
## from the lens tipped a little back over the pavement, `energy` strong: a pool
## with a soft edge on the pavement and the kerbside (0: only the lens glows,
## for lamps far off up a road).
static func cobra_lamp(p: Node3D, b: int, u: float, v: float, yaw := 0.0, reach := 1.17, energy := 8.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.3, 0.3)
	var pole := Color(0.18, 0.18, 0.2)          # (42, 42, 46), a little lifted
	Kit.cyl(g, 0.11, 0.5, Vector3(0, 0.25, 0), pole, Vector3.ZERO, 8, 0.08)
	Kit.cyl(g, 0.065, 4.68, Vector3(0, 2.34, 0), pole, Vector3.ZERO, 8, 0.055)
	pipe(g, Vector3(0, 4.62, 0), Vector3(0, 4.98, 0.3), 0.05, pole)
	pipe(g, Vector3(0, 4.98, 0.3), Vector3(0, 5.04, reach - 0.25), 0.05, pole)
	Kit.bevel(g, Vector3(0.3, 0.17, 0.66), Vector3(0, 5.05, reach), Color(0.5, 0.52, 0.55), 0.05)
	Kit.bevel(g, Vector3(0.32, 0.07, 0.42), Vector3(0, 5.16, reach - 0.06), Color(0.42, 0.44, 0.47), 0.025)
	Kit.box(g, Vector3(0.24, 0.05, 0.46), Vector3(0, 4.945, reach + 0.04), Kit.flat(LAMP, 2.6))
	if energy > 0.0:
		var spot := SpotLight3D.new()
		spot.light_color = LAMP
		spot.light_energy = energy
		spot.spot_range = 9.5
		spot.spot_angle = 56.0
		spot.spot_angle_attenuation = 1.5
		spot.spot_attenuation = 0.6
		spot.position = Vector3(0, 4.88, reach)
		spot.rotation_degrees = Vector3(-76, 0, 0)
		g.add_child(spot)
	return g


## A wooden utility pole, as along Rose Hill's north kerb: 9.6 m tall, a 2 m
## cross-arm at 8.93 m with three insulators for the wires, which run along u.
## `transformer`: a grey transformer can hung on its street side.
static func utility_pole(p: Node3D, b: int, u: float, v: float, transformer := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	var wood := Color(0.48, 0.39, 0.29)         # (118, 94, 69)
	Kit.cyl(g, 0.15, 9.6, Vector3(0, 4.8, 0), wood, Vector3.ZERO, 8, 0.11)
	Kit.box(g, Vector3(0.12, 0.12, 2.0), Vector3(0, 8.93, 0), wood)
	for z: float in WIRES:
		Kit.cyl(g, 0.045, 0.2, Vector3(0, 9.09, z), Color(0.5, 0.62, 0.55), Vector3.ZERO, 6)
	for y: float in [1.6, 2.1]:
		Kit.box(g, Vector3(0.16, 0.012, 0.012), Vector3(0, y, 0.15), Color(0.7, 0.7, 0.68))   # old staples, a tag
	Kit.box(g, Vector3(0.12, 0.16, 0.012), Vector3(0, 2.6, 0.151), Color(0.85, 0.8, 0.3))
	if transformer:
		var can := Color(0.52, 0.55, 0.57)
		Kit.box(g, Vector3(0.1, 0.6, 0.2), Vector3(0, 7.6, 0.22), can.darkened(0.25))
		Kit.cyl(g, 0.3, 0.9, Vector3(0, 7.6, 0.45), can, Vector3.ZERO, 10)
		Kit.cyl(g, 0.33, 0.08, Vector3(0, 8.07, 0.45), can.darkened(0.15), Vector3.ZERO, 10)
		pipe(g, Vector3(0, 8.11, 0.45), Vector3(0, 8.95, 0.8), 0.014, Props.DARK, 4)
	return g


## Where the three wires sit across a pole's cross-arm (along v).
const WIRES := [-0.8, 0.0, 0.8]


## The old game's everyday parked kinds, kept chunky. kind: "box_sedan" (the
## big square 1980s sedan), "compact", "minivan", "midsize", "hatchback",
## "long_sedan". Every one fits the old game's 2.12 x 4.70 m parking envelope.
const CAR_KINDS := {
	# length, width, body height, cabin length, cabin offset (+ towards the front), cabin height
	"box_sedan": [4.7, 1.86, 0.6, 2.05, -0.22, 0.5],
	"compact": [4.2, 1.72, 0.55, 2.0, -0.18, 0.5],
	"minivan": [4.6, 1.86, 0.72, 3.15, -0.42, 0.66],
	"midsize": [4.5, 1.8, 0.58, 2.15, -0.15, 0.5],
	"hatchback": [3.95, 1.72, 0.58, 2.05, -0.55, 0.54],
	"long_sedan": [4.7, 1.84, 0.56, 2.15, -0.28, 0.48],
}


## A parked car; its front is the front (turn it with `yaw`). Chunky and
## toy-like: a rounded body, a glasshouse with a raked windscreen and back
## window under a roof, the pillars, a grille and lamps, bumpers and plates,
## dark wheel wells. `ground`: the height of the road under it.
static func parked_car(p: Node3D, b: int, u: float, v: float, yaw: float, kind: String, paint: Color, ground := 0.0) -> Node3D:
	var c: Array = CAR_KINDS[kind]
	var car: Node3D = p.prop(b, u, v, yaw, c[1], c[0])
	car_model(car, Vector3(0, ground, 0), 0.0, kind, paint)
	return car


## The car itself (see parked_car) built into `parent` at `at` (the road under
## it), its front facing `yaw`. It takes no floor: for cars in streets nobody
## walks.
static func car_model(parent: Node3D, at: Vector3, yaw: float, kind: String, paint: Color) -> Node3D:
	var c: Array = CAR_KINDS[kind]
	var l: float = c[0]
	var w: float = c[1]
	var bh: float = c[2]
	var cl: float = c[3]
	var cz: float = c[4]
	var ch: float = c[5]
	var g := Kit.group(parent, at, Vector3(0, yaw, 0))
	var glass := Color(0.16, 0.21, 0.28)
	var chrome := Color(0.78, 0.8, 0.82)
	var rubber := Color(0.07, 0.07, 0.08)
	var seam := paint.darkened(0.45)
	var old := kind == "box_sedan" or kind == "long_sedan"
	var van := kind == "minivan"
	var floor_y := 0.3
	var top := floor_y + bh
	# The body, the old boxy sedans squarer.
	Kit.bevel_block(g, Vector3(w, bh, l), Vector3(0, floor_y, 0), paint, 0.05 if old else 0.11)
	# The glasshouse: the glass sides, the raked windscreen and back window (a
	# minivan's and a hatchback's back is near upright), the roof on top (a
	# cream vinyl one on the long sedan), the pillars.
	var cw := w - (0.16 if van else 0.22)
	var rf := 0.42 if van else 0.55
	var rb := 0.14 if van or kind == "hatchback" else 0.42
	var zf := cz + cl * 0.5
	var zb := cz - cl * 0.5
	var mid := cl - rf - rb
	var mz := (zf - rf + zb + rb) * 0.5
	var gy := top + ch * 0.5
	Kit.box(g, Vector3(cw, ch, mid), Vector3(0, gy, mz), glass)
	Kit.prism(g, Vector3(rf, ch, cw), Vector3(0, gy, zf - rf * 0.5), glass, Vector3(0, 90, 0), 1.0)
	Kit.prism(g, Vector3(rb, ch, cw), Vector3(0, gy, zb + rb * 0.5), glass, Vector3(0, 90, 0), 0.0)
	Kit.bevel(g, Vector3(cw + 0.06, 0.08, mid + 0.12), Vector3(0, top + ch + 0.03, mz), Color(0.9, 0.87, 0.78) if kind == "long_sedan" else paint, 0.03)
	for s: float in [-1.0, 1.0]:
		var x := s * (cw * 0.5 + 0.006)
		Kit.tube(g, Vector3(x, top, zf), Vector3(x, top + ch, zf - rf), 0.04, paint, 4)
		Kit.tube(g, Vector3(x, top, zb), Vector3(x, top + ch, zb + rb), 0.04, paint, 4)
		Kit.box(g, Vector3(0.02, ch, 0.12), Vector3(s * (cw * 0.5 + 0.012), gy, mz), paint)
		Kit.bevel(g, Vector3(0.1, 0.09, 0.07), Vector3(s * (cw * 0.5 + 0.09), top + 0.1, zf - 0.08), paint, 0.02)   # a mirror
		# Along the side: a trim strip (chrome on the old ones), the door seams.
		Kit.box(g, Vector3(0.02, 0.05, l - 0.8), Vector3(s * (w * 0.5 + 0.005), floor_y + bh * 0.55, 0), chrome if old else seam)
		var seams: Array = [zf - 0.05, mz - 0.3] if van else [zf - 0.05, mz, zb + rb - 0.05]
		for z: float in seams:
			Kit.box(g, Vector3(0.012, bh * 0.78, 0.02), Vector3(s * (w * 0.5 + 0.004), floor_y + bh * 0.5, z), seam)
	if van:     # a roof rack
		for x: float in [-cw * 0.36, cw * 0.36]:
			Kit.box(g, Vector3(0.05, 0.05, mid - 0.1), Vector3(x, top + ch + 0.1, mz), Color(0.2, 0.2, 0.22))
	# The front: a grille (chrome bars on the old ones), the lamps; the tail lamps.
	var nose := l * 0.5 + 0.006
	var ly := top - bh * 0.42
	Kit.box(g, Vector3(w * 0.42, bh * 0.4, 0.02), Vector3(0, ly, nose), Color(0.12, 0.12, 0.14))
	if old:
		for k in 3:
			Kit.box(g, Vector3(w * 0.42, 0.025, 0.02), Vector3(0, ly - bh * 0.12 + k * bh * 0.12, nose + 0.012), chrome)
	for x: float in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		Kit.box(g, Vector3(0.3, 0.14, 0.02), Vector3(x, ly, nose), Kit.flat(Color(0.98, 0.95, 0.8), 0.35))
		Kit.box(g, Vector3(0.32, 0.14, 0.02), Vector3(x, top - bh * 0.35, -nose), Kit.flat(Color(0.85, 0.12, 0.1), 0.45))
	# The bumpers, chrome on the old ones, and the plates on them.
	for s: float in [1.0, -1.0]:
		Kit.bevel(g, Vector3(w + 0.06, 0.17, 0.16), Vector3(0, floor_y + 0.1, s * (l * 0.5 + 0.02)), chrome if old else Color(0.22, 0.22, 0.24), 0.05)
		Kit.box(g, Vector3(0.38, 0.14, 0.02), Vector3(0, floor_y + 0.1, s * (l * 0.5 + 0.105)), Color(0.94, 0.93, 0.86))
	# The wheels: a dark well behind each, the tyre, a hubcap, the hub.
	for x: float in [-w * 0.5 + 0.08, w * 0.5 - 0.08]:
		for z: float in [-l * 0.5 + 0.85, l * 0.5 - 0.85]:
			Kit.cyl(g, 0.41, 0.03, Vector3(signf(x) * (w * 0.5 + 0.004), 0.36, z), rubber, Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.32, 0.24, Vector3(x, 0.32, z), rubber, Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.17, 0.25, Vector3(x, 0.32, z), chrome, Vector3(0, 0, 90), 8)
			Kit.cyl(g, 0.06, 0.26, Vector3(x, 0.32, z), Color(0.3, 0.3, 0.33), Vector3(0, 0, 90), 6)
	return g


## The watcher that fades the parked cars that would hide him (see CarFade):
## hand it each car as it is parked.
static func car_fade(p: Node3D, b: int) -> CarFade:
	var f := CarFade.new()
	f.name = "CarFade"
	p.node_of(b).add_child(f)
	p.watchers.append(f)
	return f


## The parked cars stand between the camera and the pavement, so any car that
## would hide him fades to a ghost of itself until he has walked on. The place
## tells it where he is (place.watchers), or it finds him (main.gd's "Player")
## when it has not been told yet; it finds the camera itself, each frame.
class CarFade extends Node3D:
	const GHOST := 0.2            # how much of a car still shows while it is in the way
	const SPEED := 5.0            # a whole fade in a fifth of a second
	var _cars: Array = []         # [the car, its box in its own space, its own materials, how much shows]
	var _at := Vector3.INF
	var _eye := Vector3.INF
	var _lead: Node3D = null

	## A car to look after: its parts get materials of their own, so it fades alone.
	func add(car: Node3D) -> void:
		var mats := {}
		var box := AABB()
		var first := true
		for node: Node in car.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := mi.transform
			var up := mi.get_parent()
			while up != car and up is Node3D:
				xf = (up as Node3D).transform * xf
				up = up.get_parent()
			var part: AABB = xf * mi.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
			var m := mi.material_override as StandardMaterial3D
			if m == null:
				continue
			if not mats.has(m):
				var own := m.duplicate() as StandardMaterial3D
				own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				own.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				mats[m] = own
			mi.material_override = mats[m]
		_cars.append([car, box.grow(0.1), mats.values(), 1.0])

	func watch(at: Vector3, _delta: float) -> void:
		_at = at

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or not is_visible_in_tree():
			return
		if _lead == null and get_tree().current_scene:
			_lead = get_tree().current_scene.get_node_or_null("Player") as Node3D
		if _lead:
			_at = _lead.global_position
		if _at == Vector3.INF:
			return
		var eye := cam.global_position
		var cut := _eye == Vector3.INF or eye.distance_to(_eye) > 2.0     # the camera jumped: no fading, just be right
		_eye = eye
		var near := eye.distance_to(_at) < 16.0                            # the game camera, not a view of the whole street
		for car: Array in _cars:
			var box: AABB = (car[0] as Node3D).global_transform * (car[1] as AABB)
			var hides := false
			if near:
				for o: Vector3 in [Vector3(0, 0.1, 0), Vector3(-0.4, 0.1, 0), Vector3(0.4, 0.1, 0), Vector3(0, 0.8, 0), Vector3(0, 1.5, 0)]:
					if box.intersects_segment(eye, _at + o) != null:
						hides = true
						break
			var want := GHOST if hides else 1.0
			var a: float = want if cut else move_toward(float(car[3]), want, delta * SPEED)
			if a != float(car[3]):
				car[3] = a
				for m: StandardMaterial3D in car[2]:
					var col := m.albedo_color
					col.a = a
					m.albedo_color = col


## A blue mailbox on its four legs, the slot under the round top.
static func mailbox(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.5)
	var blue := Color(0.16, 0.32, 0.66)
	for x: float in [-0.21, 0.21]:
		for z: float in [-0.18, 0.18]:
			Kit.box(g, Vector3(0.05, 0.3, 0.05), Vector3(x, 0.15, z), IRON)
	Kit.block(g, Vector3(0.5, 0.75, 0.44), Vector3(0, 0.3, 0), blue)
	Kit.cyl(g, 0.22, 0.5, Vector3(0, 1.05, 0), blue, Vector3(0, 0, 90), 12)
	Kit.box(g, Vector3(0.34, 0.08, 0.03), Vector3(0, 0.96, 0.235), Color(0.6, 0.62, 0.64))
	Kit.box(g, Vector3(0.4, 0.26, 0.012), Vector3(0, 0.62, 0.226), Color(0.95, 0.95, 0.92))
	Props.words(g, "MAIL", Vector3(0, 0.62, 0.234), 0.13, blue.darkened(0.2))
	return g


## A bus-stop sign on its pole; the plate faces along the kerb.
static func bus_stop(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.2, 0.2)
	Kit.cyl(g, 0.035, 2.95, Vector3(0, 1.475, 0), Color(0.55, 0.57, 0.6), Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.52, 0.68, 0.03), Vector3(0, 2.5, 0), Color(0.95, 0.95, 0.92))
	Kit.box(g, Vector3(0.46, 0.2, 0.036), Vector3(0, 2.68, 0), Color(0.15, 0.35, 0.72))
	for side: float in [1.0, -1.0]:
		Props.words(g, "BUS", Vector3(0, 2.68, 0.02 * side), 0.13, Color(0.97, 0.97, 0.95), 0.0 if side > 0 else 180.0)
		Props.words(g, "STOP", Vector3(0, 2.4, 0.017 * side), 0.13, Color(0.15, 0.35, 0.72), 0.0 if side > 0 else 180.0)
	return g


## The corner's sign post: a white-on-green blade for each street, worded on
## both faces (`along_u` names the street running left to right, `along_v` the
## one running away), and under them a stop sign facing `stop_yaw`.
static func street_sign(p: Node3D, b: int, u: float, v: float, along_u: String, along_v: String, stop_yaw := 270.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.2, 0.2)
	var green := Color(0.1, 0.42, 0.24)
	var white := Color(0.96, 0.96, 0.92)
	# The pole stops under the blades, which sit on it one across the other.
	Kit.cyl(g, 0.04, 2.74, Vector3(0, 1.37, 0), Color(0.55, 0.57, 0.6), Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.1, 0.03, 0.1), Vector3(0, 2.735, 0), Color(0.55, 0.57, 0.6))
	Kit.box(g, Vector3(1.3, 0.22, 0.03), Vector3(0, 2.86, 0), green)
	Kit.box(g, Vector3(0.06, 0.024, 0.06), Vector3(0, 2.982, 0), Color(0.55, 0.57, 0.6))
	Kit.box(g, Vector3(0.03, 0.22, 1.3), Vector3(0, 3.104, 0), green)
	for side: float in [1.0, -1.0]:
		Props.words(g, along_u, Vector3(0, 2.86, 0.017 * side), 0.12, white, 0.0 if side > 0 else 180.0)
		Props.words(g, along_v, Vector3(0.017 * side, 3.104, 0), 0.12, white, 90.0 * side)
	# The stop sign: a grey back, the red face, the white border, the word.
	var stop := Kit.group(g, Vector3(0, 2.2, 0), Vector3(0, stop_yaw, 0))
	var oct := Kit.group(stop, Vector3.ZERO, Vector3(0, 0, 22.5))      # a flat side on top
	Kit.disc(oct, 0.34, Vector3(0, 0, 0.05), Color(0.6, 0.62, 0.64), 0.01, 8)
	Kit.disc(oct, 0.335, Vector3(0, 0, 0.06), Color(0.8, 0.12, 0.1), 0.012, 8)
	Kit.disc(oct, 0.3, Vector3(0, 0, 0.069), Color(0.95, 0.94, 0.9), 0.01, 8)
	Kit.disc(oct, 0.27, Vector3(0, 0, 0.077), Color(0.8, 0.12, 0.1), 0.01, 8)
	Props.words(stop, "STOP", Vector3(0, 0, 0.087), 0.15, Color(0.97, 0.97, 0.95))
	return g


## A scrap of litter (decoration: it does not block): a paper, a can, a cup.
static func litter(parent: Node3D, pos: Vector3, n: int) -> void:
	match n % 3:
		0:
			Kit.box(parent, Vector3(0.22, 0.008, 0.28), pos + Vector3(0, 0.006, 0), Color(0.92, 0.9, 0.84), Vector3(0, n * 37.0, 0))
		1:
			Kit.cyl(parent, 0.033, 0.12, pos + Vector3(0, 0.033, 0), [Color(0.8, 0.15, 0.15), Color(0.2, 0.4, 0.8), Color(0.85, 0.85, 0.85)][int(n / 3.0) % 3], Vector3(90, n * 53.0, 0), 8)
		_:
			Kit.cyl(parent, 0.045, 0.11, pos + Vector3(0, 0.045, 0), Color(0.95, 0.95, 0.92), Vector3(90, n * 71.0, 0), 8, 0.035)


## Black rubbish bags heaped by a can (decoration: they do not block).
static func bags(parent: Node3D, pos: Vector3, n := 2) -> void:
	for i in n:
		var bag := Kit.ball(parent, 0.26, pos + Vector3(i * 0.38 - 0.19, 0.2, (i % 2) * 0.12), Color(0.08, 0.08, 0.1), 7)
		bag.scale = Vector3(1.0, 0.8, 0.9)
		Kit.cyl(parent, 0.05, 0.12, pos + Vector3(i * 0.38 - 0.19, 0.42, (i % 2) * 0.12), Color(0.08, 0.08, 0.1), Vector3.ZERO, 5)
