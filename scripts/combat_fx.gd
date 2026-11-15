extends Node3D
## What shots look like, drawn like everything else here: flat colours inside a fat ink line, no fading
## see-through stuff (a thing that goes, shrinks away). Everything is a flat shape built once and reused:
## a muzzle flash (a paper star for a frame or two, with a quick warm light), now and then a tracer (a bright
## streak from the muzzle to where the round ended, gone in a few frames), spent cases thrown from the port that
## bounce and lie on the floor, a puff and a mark where a shot hits a wall, a spark on metal, the pieces a pane
## breaks into and crumbs of glass, drops of blood and the pool that spreads under someone who is down.
##
## What falls lands on whatever is really under it where it comes down (`world`, the place's combat_world.gd:
## a floor, a step, a porch roof, a car's bonnet, the pavement outside a window), bounces off walls, and lies
## there in the room it landed in (`node_for`). Without a world it lands at the height it was given.
##
## Capped: at most SHELLS cases, MARKS marks, SHARDS crumbs and PIECES pieces of glass lie about; past that the
## oldest is taken up and used again. Nothing is made while shooting but the marks' first round and the pieces.

const SHELLS := 40
const MARKS := 60
const SHARDS := 90
const PIECES := 120
const GRAVITY := 9.8

enum {FLASH, SHELL, PUFF, CHIP, SPARK, STREAK, SHARD, DROP, BURST, MARK, PIECE, TRACER}
const CAPS := {FLASH: 8, SHELL: SHELLS, PUFF: 10, CHIP: 24, SPARK: 6, STREAK: 30, SHARD: SHARDS, DROP: 40, BURST: 6, MARK: MARKS,
		PIECE: PIECES, TRACER: 8}
## A tracer: metres either side of its line at its head (its tail is a quarter of that), and seconds it shows.
## Further off it is drawn wider (TRACER_SPREAD per metre from the eye, to TRACER_WIDEST), so it reads at any range.
const TRACER_WIDTH := 0.024
const TRACER_SPREAD := 0.006
const TRACER_WIDEST := 0.06
const TRACER_LIFE := 0.09
## Glass that comes down this near a pane's plane (x, metres) and no further below its lowest edge (y) is on the
## window itself (its frame, its sill): it is tipped off, so it ends on the ground below (placeholder numbers).
const OFF_WINDOW := Vector2(0.3, 0.4)

const INK := Color(0.03, 0.02, 0.05)
const BRASS := Color(0.88, 0.66, 0.24)
const BRASS_DARK := Color(0.62, 0.42, 0.12)
const FIRE := Color(1.0, 0.8, 0.22)
const FIRE_CORE := Color(1.0, 0.97, 0.78)
const DUST := Color(0.8, 0.74, 0.65)
const BLOOD := Color(0.62, 0.05, 0.1)
const BLOOD_LIGHT := Color(0.8, 0.1, 0.16)
const POOL := Color(0.44, 0.03, 0.07)
const POOL_LIGHT := Color(0.58, 0.05, 0.1)
const SHARD_LOOK := Color(0.85, 0.94, 0.98)
const FIRE_EDGE := Color(0.93, 0.42, 0.08)


class Bit:
	var node: MeshInstance3D
	var kind := 0
	var alive := false
	var t := 0.0
	var life := 1.0
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var ang := 0.0
	var spin := 0.0
	var size := 1.0
	var ground := 0.0
	var resting := false
	var tumble := 0.0
	var stretch := 1.0          # a flash is this much longer than it is wide; a streak, along its way
	var turn := Basis.IDENTITY  # a piece of glass: how it lies (its face is z) ...
	var axis := Vector3.UP      # ... what it turns about as it falls ...
	var lift := 0.004           # ... and how far off what it lands on it lies
	var tips := 0               # times it has tipped off an edge it landed on
	var from := Vector3.ZERO    # a tracer: from the muzzle ...
	var to := Vector3.ZERO      # ... to where the round ended
	var pane := Vector3.ZERO    # glass: the middle of the pane it came from ...
	var pane_n := Vector3.ZERO  # ... its face (ZERO: none) ...
	var pane_low := 0.0         # ... and lower than this it is clear of the window (see _off_window)


var camera: Camera3D
var frozen := false             # a picture: nothing moves
var world: RefCounted           # the place's combat_world.gd: what falling things land on (null: at their `ground`)
var node_for := Callable()      # where something that has landed at a point goes (its room), so it hides with it
var _mat: StandardMaterial3D
var _meshes := {}               # kind: Array of meshes (a few of each, told apart by rng)
var _bits := {}                 # kind: Array of Bit, at most CAPS[kind]
var _next := {}                 # kind: which Bit to take when all are in use
var _light: OmniLight3D
var _light_t := -1.0
var _rng := RandomNumberGenerator.new()
var _pools: Array = []          # {"node", "t", "grow"}


func _init() -> void:
	set_meta("combat_fx", true)
	_rng.seed = 41
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for kind: int in CAPS:
		_bits[kind] = []
		_next[kind] = 0
	_meshes[FLASH] = [_flash_mesh(false, 1), _flash_mesh(false, 2), _flash_mesh(false, 3)]
	_meshes[FLASH + 100] = [_flash_mesh(true, 4), _flash_mesh(true, 5)]       # seen end-on: round
	_meshes[SHELL] = [_shell_mesh()]
	_meshes[PUFF] = [_blob_mesh(11, 0.7, DUST, 0.16, 6), _blob_mesh(12, 0.68, DUST, 0.16, 7)]
	_meshes[CHIP] = [_blob_mesh(5, 0.85, Color(0.32, 0.27, 0.24), 0.0, 8)]
	_meshes[SPARK] = [_star_mesh(8, 0.32, Color(1.0, 0.95, 0.55), Color(1, 1, 1), 0.1)]
	_meshes[STREAK] = [_rect_mesh(Vector2(1.0, 0.16), Color(1.0, 0.86, 0.35), 0.0)]
	_meshes[SHARD] = [_shard_mesh(9), _shard_mesh(10), _shard_mesh(11)]
	_meshes[DROP] = [_blob_mesh(8, 0.8, BLOOD, 0.22, 12), _blob_mesh(7, 0.75, BLOOD, 0.22, 13)]
	_meshes[BURST] = [_star_mesh(7, 0.42, BLOOD_LIGHT, Color(0.95, 0.25, 0.3), 0.12)]
	_meshes[MARK] = [_mark_mesh(14, false), _mark_mesh(15, false), _mark_mesh(16, false)]
	_meshes[MARK + 100] = [_mark_mesh(17, true), _mark_mesh(18, true)]          # on metal: a dent
	_meshes[PIECE] = [_shard_mesh(9)]          # each piece gets a mesh of its own shape
	_meshes[TRACER] = [_tracer_mesh()]
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.36)
	_light.omni_range = 4.5
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)


# ---------------------------------------------------------------- shapes

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _end(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat)
	return mesh


## A filled shape round (0, 0), in layer z (nearer the eye for a bigger z), from the middle out.
func _fan(st: SurfaceTool, ring: PackedVector2Array, color: Color, z: float, at := Vector2.ZERO) -> void:
	st.set_color(color)
	for i in ring.size():
		st.add_vertex(Vector3(at.x, at.y, z))
		st.add_vertex(Vector3(ring[i].x, ring[i].y, z))
		st.add_vertex(Vector3(ring[(i + 1) % ring.size()].x, ring[(i + 1) % ring.size()].y, z))


## The same ring pushed out by w all round: its ink.
func _grow(ring: PackedVector2Array, w: float, from := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in ring:
		out.append(p + (p - from).normalized() * w)
	return out


func _flash_mesh(is_round: bool, salt: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var n := 10 if is_round else 11
	var ring := PackedVector2Array()
	var core := PackedVector2Array()
	for i in n * 2:
		var a := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(n * 2)
		var out := i % 2 == 0
		var r := rng.randf_range(0.8, 1.0) if out else rng.randf_range(0.38, 0.5)
		if not is_round:          # side-on: long spikes forward (x), short ones back
			var fwd := maxf(cos(a), 0.0)
			r *= 0.42 + 0.58 * pow(fwd, 1.4) if out else 0.5 + 0.3 * fwd
		var p := Vector2(cos(a), sin(a)) * r
		if not is_round:
			p.y *= 0.62
			p.x += 0.34            # its back is at the muzzle
		ring.append(p)
		core.append(Vector2(cos(a), sin(a)) * r * 0.5 * (Vector2(1.0, 0.62) if not is_round else Vector2.ONE) + (Vector2(0.24, 0.0) if not is_round else Vector2.ZERO))
	var mid := Vector2(0.34, 0.0) if not is_round else Vector2.ZERO
	var st := _begin()
	_fan(st, _grow(ring, 0.07, mid), INK, 0.0, mid)
	_fan(st, ring, FIRE, 0.004, mid)
	_fan(st, core, FIRE_CORE, 0.008, mid * 0.7)
	return _end(st)


func _star_mesh(n: int, inner: float, fill: Color, core: Color, ink: float) -> ArrayMesh:
	var ring := PackedVector2Array()
	for i in n * 2:
		var a := TAU * float(i) / float(n * 2)
		ring.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else inner))
	var st := _begin()
	if ink > 0.0:
		_fan(st, _grow(ring, ink), INK, 0.0)
	_fan(st, ring, fill, 0.004)
	var small := PackedVector2Array()
	for p: Vector2 in ring:
		small.append(p * 0.45)
	_fan(st, small, core, 0.008)
	return _end(st)


func _blob_mesh(n: int, inner: float, fill: Color, ink: float, salt: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var ring := PackedVector2Array()
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(n)
		ring.append(Vector2(cos(a), sin(a)) * rng.randf_range(inner, 1.0))
	var st := _begin()
	if ink > 0.0:
		_fan(st, _grow(ring, ink), INK, 0.0)
	_fan(st, ring, fill, 0.004)
	return _end(st)


func _rect_mesh(size: Vector2, fill: Color, ink: float) -> ArrayMesh:
	var h := size * 0.5
	var ring := PackedVector2Array([Vector2(h.x, h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y), Vector2(h.x, -h.y)])
	var st := _begin()
	if ink > 0.0:
		_fan(st, _grow(ring, ink), INK, 0.0)
	_fan(st, ring, fill, 0.004)
	return _end(st)


## A spent case seen from the side: a short brass tube, its open end darker. 1 long.
func _shell_mesh() -> ArrayMesh:
	var ring := PackedVector2Array()
	for i in 16:            # a rounded box, 1 by 0.42
		var a := TAU * float(i) / 16.0
		var c := Vector2(cos(a), sin(a))
		ring.append(Vector2(signf(c.x) * pow(absf(c.x), 0.35) * 0.5, signf(c.y) * pow(absf(c.y), 0.35) * 0.21))
	var st := _begin()
	_fan(st, _grow(ring, 0.1), INK, 0.0)
	_fan(st, ring, BRASS, 0.004)
	var mouth := PackedVector2Array([Vector2(0.5, 0.2), Vector2(0.3, 0.2), Vector2(0.3, -0.2), Vector2(0.5, -0.2)])
	_fan(st, mouth, BRASS_DARK, 0.008, Vector2(0.4, 0.0))
	var shine := PackedVector2Array([Vector2(0.2, 0.12), Vector2(-0.38, 0.12), Vector2(-0.38, 0.05), Vector2(0.2, 0.05)])
	_fan(st, shine, Color(1.0, 0.88, 0.55), 0.012, Vector2(-0.09, 0.085))
	return _end(st)


func _shard_mesh(salt: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var ring := PackedVector2Array()
	for i in 3:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 3.0
		ring.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.6, 1.0))
	var mid := (ring[0] + ring[1] + ring[2]) / 3.0
	var st := _begin()
	_fan(st, _grow(ring, 0.22, mid), INK, 0.0, mid)
	_fan(st, ring, SHARD_LOOK, 0.004, mid)
	return _end(st)


## A bullet hole: a dark hole in a pale chipped ring (on metal: a grey dent). Lies on its +z face.
func _mark_mesh(salt: int, metal: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var hole := PackedVector2Array()
	var chip := PackedVector2Array()
	for i in 9:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 9.0
		hole.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.75, 1.0))
	for i in 11:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 11.0
		chip.append(Vector2(cos(a), sin(a)) * rng.randf_range(1.45, 2.1) * (0.8 if metal else 1.0))
	var st := _begin()
	_fan(st, chip, Color(0.56, 0.58, 0.62) if metal else Color(0.86, 0.82, 0.74), 0.0)
	_fan(st, _grow(hole, 0.22), INK, 0.002)
	_fan(st, hole, Color(0.2, 0.2, 0.23) if metal else Color(0.06, 0.04, 0.05), 0.004)
	return _end(st)


## The pool under someone who is down: a dark red lake with a lighter middle, inked round. 1 across.
func _pool_mesh(salt: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var n := 26
	var ring := PackedVector2Array()
	var phase := rng.randf() * TAU
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := 0.8 + 0.12 * sin(a * 3.0 + phase) + 0.07 * sin(a * 5.0 + phase * 2.0) + rng.randf_range(-0.04, 0.04)
		ring.append(Vector2(cos(a), sin(a)) * r)
	var light := PackedVector2Array()
	for p: Vector2 in ring:
		light.append(p * 0.55 + Vector2(-0.08, 0.06))
	var st := _begin()
	_fan(st, _grow(ring, 0.035), INK, 0.0)
	_fan(st, ring, POOL, 0.002)
	_fan(st, light, POOL_LIGHT, 0.004, Vector2(-0.08, 0.06))
	return _end(st)


## A tracer, 1 long along x (from the muzzle at 0 to where the round ended at 1) and 1 either side at its head:
## a hot edge round a yellow streak round a white core, thin at the tail and blunt at the head, a layer apart.
func _tracer_mesh() -> ArrayMesh:
	var xs := [0.0, 0.12, 0.35, 0.6, 0.8, 0.93, 0.985, 1.0]
	var ws := [0.0, 0.22, 0.38, 0.55, 0.75, 0.95, 0.85, 0.35]
	var st := _begin()
	for layer: Array in [[FIRE_EDGE, 1.0, 0.0], [FIRE, 0.68, 0.002], [FIRE_CORE, 0.32, 0.004]]:
		st.set_color(layer[0])
		var k: float = layer[1]
		var z: float = layer[2]
		for i in xs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var w0: float = ws[i] * k
			var w1: float = ws[i + 1] * k
			for v: Vector3 in [Vector3(x0, -w0, z), Vector3(x1, -w1, z), Vector3(x1, w1, z), Vector3(x0, -w0, z), Vector3(x1, w1, z), Vector3(x0, w0, z)]:
				st.add_vertex(v)
	return _end(st)


## A piece of a pane as it came away (`poly`, about its middle, in metres): pale glass in a fat ink line, on
## both faces (it turns over as it falls).
func _piece_mesh(poly: PackedVector2Array, size: float) -> ArrayMesh:
	var w := clampf(0.004 + 0.03 * size, 0.005, 0.011)
	var ink := poly
	var best := 0.0
	for grown: PackedVector2Array in Geometry2D.offset_polygon(poly, w, Geometry2D.JOIN_MITER):
		var a := absf(_area2(grown))
		if a > best:
			best = a
			ink = grown
	var st := _begin()
	_flat(st, ink, INK, 0.0)
	_flat(st, poly, SHARD_LOOK, 0.0015)
	_flat(st, poly, SHARD_LOOK, -0.0015)
	return _end(st)


## A filled outline (any shape) in layer z.
func _flat(st: SurfaceTool, poly: PackedVector2Array, color: Color, z: float) -> void:
	st.set_color(color)
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		var mid := Vector2.ZERO
		for p: Vector2 in poly:
			mid += p
		_fan(st, poly, color, z, mid / float(maxi(poly.size(), 1)))
		return
	for i in tris:
		st.add_vertex(Vector3(poly[i].x, poly[i].y, z))


static func _area2(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a


# ---------------------------------------------------------------- the pool of bits

func _take(kind: int, parent: Node3D) -> Bit:
	var list: Array = _bits[kind]
	var bit: Bit
	for b: Bit in list:
		if not b.alive:
			bit = b
			break
	if bit == null and list.size() < int(CAPS[kind]):
		bit = Bit.new()
		bit.kind = kind
		bit.node = MeshInstance3D.new()
		bit.node.set_meta("combat_fx", true)
		bit.node.top_level = kind != MARK
		bit.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		list.append(bit)
	if bit == null:                 # all in use: the oldest goes
		bit = list[int(_next[kind]) % list.size()]
		_next[kind] = (int(_next[kind]) + 1) % list.size()
	var meshes: Array = _meshes[kind]
	bit.node.mesh = meshes[_rng.randi() % meshes.size()]
	if bit.node.get_parent() != parent:
		if bit.node.get_parent():
			bit.node.get_parent().remove_child(bit.node)
		parent.add_child(bit.node)
	bit.alive = true
	bit.resting = false
	bit.t = 0.0
	bit.tips = 0
	bit.pane_n = Vector3.ZERO
	bit.node.visible = true
	return bit


## Pointed away from us the gun is out of sight in front of him (paper_actor.gd HOLDS "elbows"), so the flash is
## this many times the size: its points show round his outline, which is all that says he fired.
const AWAY_FLASH := 2.3


## The flash at the muzzle. `gun` is paper_actor.gd's gun_points(); `length` how long the flash is, metres.
func flash(gun: Dictionary, length: float, parent: Node3D) -> void:
	if camera == null or gun.is_empty():
		return
	var bit := _take(FLASH, parent)
	var art: String = gun.get("art", "")
	var eye := camera.global_transform.basis
	var at: Vector3 = gun["muzzle"]
	var to_eye := (camera.global_position - at).normalized()
	if art == "":
		at += to_eye * 0.08               # in front of the gun's drawing
		var d: Vector3 = gun["dir"]
		bit.ang = atan2(d.dot(eye.y), d.dot(eye.x))
		bit.stretch = 1.0
	else:
		bit.node.mesh = (_meshes[FLASH + 100] as Array)[_rng.randi() % 2]
		bit.ang = _rng.randf() * TAU
		length *= 1.0 if art == "toward" else AWAY_FLASH
		# Pointed at the camera it is in front of everything; pointed away, behind him: a glow round his outline.
		at += to_eye * (0.1 if art == "toward" else -0.22)
	bit.pos = at
	bit.size = length
	bit.life = 0.05
	_place_billboard(bit, eye, Vector2(1.0, 1.0) * length)
	_light.global_position = gun["muzzle"] - (gun["dir"] as Vector3) * 0.1 + Vector3(0, 0.05, 0)
	_light.visible = true
	_light.light_energy = 2.6
	_light_t = 0.0


## A spent case leaves the port at `at`, thrown `vel`; it lands on the floor at height `ground`.
func shell(at: Vector3, vel: Vector3, ground: float, size: float, parent: Node3D) -> void:
	var bit := _take(SHELL, parent)
	bit.pos = at
	bit.vel = vel
	bit.ang = _rng.randf() * TAU
	bit.spin = _rng.randf_range(16.0, 26.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	bit.size = size
	bit.ground = ground
	bit.life = 99999.0
	_show(bit)


## A shot hits something solid at `at`, facing `normal`: a mark on it, a puff, chips; on metal a spark.
func impact(at: Vector3, normal: Vector3, on: MeshInstance3D, metal: bool, parent: Node3D, ground: float) -> void:
	if on != null and is_instance_valid(on):
		var mark := _take(MARK, on)
		mark.node.mesh = (_meshes[MARK + 100 if metal else MARK] as Array)[_rng.randi() % (2 if metal else 3)]
		var z := normal.normalized()
		var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized().rotated(z, _rng.randf() * TAU)
		var s := 0.018 if metal else 0.022
		mark.node.global_transform = Transform3D(Basis(x * s, z.cross(x) * s, z), at + z * 0.003)     # its layers stay mm apart
		mark.life = 99999.0
		mark.resting = true
	var eye := camera.global_transform.basis if camera else Basis.IDENTITY
	if metal:
		var spark := _take(SPARK, parent)
		spark.pos = at + normal * 0.03
		spark.size = 0.11
		spark.life = 0.06
		spark.ang = _rng.randf() * TAU
		_show(spark)
		for i in 5:
			var streak := _take(STREAK, parent)
			streak.pos = at + normal * 0.02
			streak.vel = (normal + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1.2), _rng.randf_range(-1, 1)) * 0.8).normalized() * _rng.randf_range(2.5, 4.5)
			streak.size = 0.08
			streak.life = _rng.randf_range(0.12, 0.2)
			streak.ground = ground
			_show(streak)
	else:
		var puff := _take(PUFF, parent)
		puff.pos = at + normal * 0.04
		puff.vel = normal * 0.25 + Vector3(0, 0.25, 0)
		puff.size = _rng.randf_range(0.11, 0.15)
		puff.life = 0.34
		puff.ang = _rng.randf() * TAU
		_place_billboard(puff, eye, Vector2.ONE * puff.size * 0.3)
		for i in 3:
			var chip := _take(CHIP, parent)
			chip.pos = at + normal * 0.02
			chip.vel = (normal + Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(0.0, 0.9), _rng.randf_range(-0.7, 0.7))).normalized() * _rng.randf_range(1.0, 2.2)
			chip.size = _rng.randf_range(0.02, 0.032)
			chip.life = 0.7
			chip.ground = ground
			chip.spin = _rng.randf_range(-14.0, 14.0)
			_show(chip)


## Glass flies from a hole at `center` (facing `normal`, about `radius` across) the way the shot went (`dir`).
## `window`: what combat_glass.gd's shatter() said of the pane (they do not stay on its sill).
func shards(center: Vector3, normal: Vector3, dir: Vector3, radius: float, count: int, ground: float, parent: Node3D, window := {}) -> void:
	var x := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := normal.cross(x)
	var through := normal * signf(normal.dot(dir) if normal.dot(dir) != 0.0 else 1.0)
	for i in count:
		var bit := _take(SHARD, parent)
		var a := _rng.randf() * TAU
		bit.pos = center + (x * cos(a) + y * sin(a)) * radius * sqrt(_rng.randf()) * 0.9
		var way := through if _rng.randf() < 0.72 else -through
		bit.vel = way * _rng.randf_range(0.6, 2.4) + (x * cos(a) + y * sin(a)) * _rng.randf_range(0.2, 1.0) + Vector3(0, _rng.randf_range(0.0, 1.3), 0)
		bit.size = _rng.randf_range(0.035, 0.075)
		bit.ground = ground
		bit.spin = _rng.randf_range(-12.0, 12.0)
		bit.tumble = _rng.randf() * TAU
		bit.ang = _rng.randf() * TAU
		bit.life = 99999.0
		_from_window(bit, window)
		_show(bit)


## Glass from a pane does not stay on the window (its frame, its sill): it remembers where the pane was.
func _from_window(bit: Bit, window: Dictionary) -> void:
	if window.has("middle"):
		bit.pane = window["middle"]
		bit.pane_n = window["normal"]
		bit.pane_low = float(window["low"]) - OFF_WINDOW.y


## A tracer: a bright streak from `from` (the muzzle) to `to` (where the round ended), whole for a frame or two,
## then its tail running in to the far end; gone in TRACER_LIFE. Drawn flat towards the camera, so it shows
## whichever way he faces.
func tracer(from: Vector3, to: Vector3, parent: Node3D) -> void:
	if camera == null or from.distance_to(to) < 0.3:
		return
	var bit := _take(TRACER, parent)
	bit.from = from
	bit.to = to
	bit.size = TRACER_WIDTH
	bit.life = TRACER_LIFE
	_show(bit)


## The pieces of a pane that came away (combat_glass.gd's shatter() result `broke`) fall from where they were:
## those by the hit thrown the way the round went (a few back towards the gun), big ones mostly dropping, all
## turning over; they lie where they land. Lower than `ground` (nothing caught them) they are taken up.
func pieces(broke: Dictionary, dir: Vector3, ground: float, parent: Node3D) -> void:
	var basis: Basis = broke["basis"]
	var normal: Vector3 = broke["normal"]
	var center: Vector3 = broke["center"]
	var e := float(broke.get("power", 1.0))
	var through := normal * (1.0 if normal.dot(dir) >= 0.0 else -1.0)
	for f: Dictionary in broke["fallen"]:
		var bit := _take(PIECE, parent)
		var size := float(f["size"])
		bit.node.mesh = _piece_mesh(f["poly"], size)
		bit.turn = basis
		bit.pos = f["at"]
		bit.size = size
		var out: Vector3 = bit.pos - center
		out -= normal * out.dot(normal)
		out = out.normalized() if out.length() > 1e-4 else basis.x
		var push := sqrt(e) / (1.0 + float(f["near"]) / 0.12)      # the nearer the hit, the harder it goes
		var back := size < 0.08 and _rng.randf() < 0.18
		var way := -through if back else through
		if size > 0.12:
			bit.vel = way * _rng.randf_range(0.3, 0.75) + out * _rng.randf_range(0.0, 0.25)
		else:
			bit.vel = way * (_rng.randf_range(0.45, 1.0) + _rng.randf_range(1.0, 2.4) * push) * (0.55 if back else 1.0) \
					+ out * _rng.randf_range(0.15, 0.7) * push + Vector3.UP * _rng.randf_range(0.0, 0.6) * push
		var ax := basis.x * _rng.randf_range(-1.0, 1.0) + basis.y * _rng.randf_range(-1.0, 1.0) + basis.z * _rng.randf_range(-0.3, 0.3)
		bit.axis = ax.normalized() if ax.length() > 0.05 else basis.x
		bit.spin = _rng.randf_range(4.0, 15.0) / (1.0 + size * 14.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		bit.lift = _rng.randf_range(0.003, 0.007)
		bit.ground = ground
		bit.life = 99999.0
		_from_window(bit, broke)
		_show(bit)


## Someone hit at `at` by a shot going `dir`: a red burst and drops thrown on.
func blood(at: Vector3, dir: Vector3, ground: float, parent: Node3D) -> void:
	var burst := _take(BURST, parent)
	burst.pos = at
	burst.size = 0.12
	burst.life = 0.08
	burst.ang = _rng.randf() * TAU
	_show(burst)
	for i in 7:
		var drop := _take(DROP, parent)
		drop.pos = at
		drop.vel = (dir * _rng.randf_range(0.6, 1.6) + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.0, 1.2), _rng.randf_range(-0.6, 0.6)))
		drop.size = _rng.randf_range(0.03, 0.05)
		drop.ground = ground
		drop.life = 1.0
		_show(drop)


## A pool of blood under someone down, at `at` on the floor; it spreads to `radius` over `seconds`
## (0: there at once, for someone who was down when he came back).
func pool(at: Vector3, radius: float, seconds: float, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.set_meta("combat_fx", true)
	node.mesh = _pool_mesh(_rng.randi() % 1000)
	node.top_level = true
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var b := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP).rotated(Vector3.UP, _rng.randf() * TAU)
	node.global_transform = Transform3D(b, at)
	_pools.append({"node": node, "t": 0.0 if seconds > 0.0 else 1.0, "seconds": maxf(seconds, 0.001), "radius": radius, "basis": b})
	_size_pool(_pools[-1])
	return node


func _size_pool(p: Dictionary) -> void:
	var k: float = clampf(float(p["t"]), 0.0, 1.0)
	var r: float = float(p["radius"]) * lerpf(0.12, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
	var node: MeshInstance3D = p["node"]
	var b: Basis = p["basis"]
	node.global_transform = Transform3D(Basis(b.x * r, b.y * r, b.z), node.global_position)


## Take a pool up (the one who lay in it is up again).
func lift_pool(node: MeshInstance3D) -> void:
	for i in range(_pools.size() - 1, -1, -1):
		if _pools[i]["node"] == node:
			_pools.remove_at(i)
	if is_instance_valid(node):
		node.queue_free()


## He has gone somewhere else: cases and glass still in the air come down at once where they would have landed
## (they are there when he comes back); the rest of what was in the air is gone. What lies about stays.
func drop_moving() -> void:
	var eye := camera.global_transform.basis if camera else Basis.IDENTITY
	for kind: int in _bits:
		for bit: Bit in _bits[kind]:
			if not bit.alive or bit.resting or kind == MARK:
				continue
			if world != null and (kind == SHELL or kind == SHARD or kind == PIECE):
				var steps := 0
				while bit.alive and not bit.resting and steps < 300:
					_fall(bit, 1.0 / 60.0)
					steps += 1
				if bit.alive and bit.resting:
					_place_falling(bit, eye)
					continue
			_kill(bit)
	_light.visible = false
	_light_t = -1.0


## Turn what is drawn facing the camera to face it as it is now (a picture from another eye, nothing moving).
func face_camera() -> void:
	if camera == null:
		return
	var eye := camera.global_transform.basis
	for kind: int in [SHELL, SHARD, CHIP, DROP, STREAK, TRACER]:
		for bit: Bit in _bits[kind]:
			if bit.alive:
				_place_falling(bit, eye)


## A new day: every case, shard and mark is gone.
func clear() -> void:
	for kind: int in _bits:
		for bit: Bit in _bits[kind]:
			if bit.alive:
				_kill(bit)
	_light.visible = false


## Put a new bit where it starts at once (a picture can be taken before it has moved).
func _show(bit: Bit) -> void:
	if camera:
		_tick_bit(bit, 0.0, camera.global_transform.basis)


func _kill(bit: Bit) -> void:
	bit.alive = false
	bit.resting = false
	bit.node.visible = false


func count(kind: int, resting_only := false) -> int:
	var n := 0
	for bit: Bit in _bits[kind]:
		if bit.alive and (bit.resting or not resting_only):
			n += 1
	return n


## Where each of a kind lies (for the checks).
func lying(kind: int) -> Array:
	var out: Array = []
	for bit: Bit in _bits[kind]:
		if bit.alive and bit.resting:
			out.append(bit.pos)
	return out


# ---------------------------------------------------------------- each frame

func tick(delta: float) -> void:
	if frozen or camera == null:
		return
	var eye := camera.global_transform.basis
	if _light_t >= 0.0:
		_light_t += delta
		_light.light_energy = 2.6 * maxf(1.0 - _light_t / 0.07, 0.0)
		if _light_t > 0.07:
			_light.visible = false
			_light_t = -1.0
	for p: Dictionary in _pools:
		if float(p["t"]) < 1.0:
			p["t"] = float(p["t"]) + delta / float(p["seconds"])
			_size_pool(p)
	for kind: int in _bits:
		if kind == MARK:
			continue
		for bit: Bit in _bits[kind]:
			if bit.alive:
				_tick_bit(bit, delta, eye)


func _tick_bit(bit: Bit, delta: float, eye: Basis) -> void:
	bit.t += delta
	if bit.t > bit.life:
		_kill(bit)
		return
	match bit.kind:
		FLASH:
			var k := 1.0 if bit.t < 0.026 else 0.66
			_place_billboard(bit, eye, Vector2(1.0, 1.0) * bit.size * k)
		SPARK, BURST:
			_place_billboard(bit, eye, Vector2.ONE * bit.size * (1.0 if bit.t < bit.life * 0.5 else 0.6))
		PUFF:
			bit.pos += bit.vel * delta
			var k := bit.t / bit.life
			var s := lerpf(0.3, 1.0, minf(k / 0.18, 1.0)) * (1.0 if k < 0.45 else maxf(1.0 - (k - 0.45) / 0.55, 0.0))
			_place_billboard(bit, eye, Vector2.ONE * bit.size * s)
		SHELL, SHARD, CHIP, DROP, STREAK:
			if not bit.resting:
				_fall(bit, delta)
			if bit.alive:
				_place_falling(bit, eye)
		PIECE:
			if not bit.resting or bit.t == 0.0:
				_fall(bit, delta)
				if bit.alive:
					_place_falling(bit, eye)
		TRACER:
			_place_falling(bit, eye)


## How far above what it lies on a bit's middle is.
func _lie(bit: Bit) -> float:
	match bit.kind:
		SHELL:
			return bit.size * 0.21 + 0.004
		PIECE:
			return bit.lift
	return bit.size * 0.35


func _fall(bit: Bit, delta: float) -> void:
	if delta <= 0.0:
		return
	bit.vel.y -= GRAVITY * delta
	if bit.kind == PIECE:
		var drag := 1.0 - minf(0.8 * delta, 0.5)             # flat glass sails a little
		bit.vel.x *= drag
		bit.vel.z *= drag
		bit.turn = bit.turn.rotated(bit.axis, bit.spin * delta).orthonormalized()
	else:
		bit.ang += bit.spin * delta
		bit.tumble += absf(bit.spin) * 0.7 * delta
	var foot := Vector3(0.0, _lie(bit), 0.0)
	var step := bit.vel * delta
	if world != null:
		var hit: Dictionary = world.fall_hit(bit.pos - foot, bit.pos - foot + step)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			var at: Vector3 = hit["pos"]
			if n.y > 0.55:                                    # something to lie on
				bit.pos = at + foot
				_land(bit, at, n)
			else:                                             # a wall, the side of something: off it
				bit.pos = at + foot + n * 0.003
				bit.vel = (bit.vel - 2.0 * bit.vel.dot(n) * n) * 0.35
				bit.spin *= 0.6
			return
	bit.pos += step
	if bit.pos.y - foot.y > bit.ground or bit.vel.y > 0.0:
		return
	if bit.kind == PIECE:                                     # under everything: nothing caught it
		_kill(bit)
		return
	bit.pos.y = bit.ground + foot.y
	_land(bit, Vector3(bit.pos.x, bit.ground, bit.pos.z), Vector3.UP)


## It comes down at `at` on something facing `n`: it stops (or bounces, or is gone) there.
func _land(bit: Bit, at: Vector3, n: Vector3) -> void:
	if bit.pane_n != Vector3.ZERO and bit.tips < 4:           # on the window it came from: off it
		var off := (at - bit.pane).dot(bit.pane_n)
		if absf(off) < OFF_WINDOW.x and at.y > bit.pane_low:
			var going := bit.vel.dot(bit.pane_n)
			var side := signf(off) if absf(off) > 0.005 else (signf(going) if absf(going) > 0.01 else 1.0)
			bit.tips += 1
			bit.vel = bit.pane_n * side * _rng.randf_range(0.7, 1.2) + Vector3.UP * 0.35
			bit.pos += bit.pane_n * side * 0.02 + n * 0.01
			return
	match bit.kind:
		DROP, CHIP, STREAK:
			_kill(bit)
			return
		SHELL:
			if absf(bit.vel.y) > 0.9:        # it bounces
				bit.vel = Vector3(bit.vel.x * 0.55, -bit.vel.y * 0.38, bit.vel.z * 0.55)
				bit.spin *= 0.55
				return
			bit.vel = Vector3.ZERO
			bit.resting = true
			bit.ang = (0.0 if cos(bit.ang) >= 0.0 else PI) + _rng.randf_range(-0.12, 0.12)       # on its side
		SHARD:
			bit.vel = Vector3.ZERO
			bit.resting = true
			bit.tumble = PI * 0.5 * _rng.randf_range(0.6, 1.0)      # lying, seen nearly edge on
		PIECE:
			var off := _overhang(bit, at)
			if off != Vector3.ZERO and bit.tips < 3:        # most of it over an edge (a sill, a step): it tips off
				bit.tips += 1
				bit.vel = off * _rng.randf_range(0.5, 0.8) + Vector3.DOWN * 0.2
				bit.pos += off * bit.size * 0.25 + n * 0.01
				return
			bit.vel = Vector3.ZERO
			bit.resting = true
			var x := bit.turn.x - n * bit.turn.x.dot(n)
			if x.length() < 0.1:
				x = n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT)
			x = x.normalized()
			bit.turn = Basis(x, n.cross(x), n)
			bit.pos = at + n * bit.lift
	if node_for.is_valid():                  # it belongs to the room it lies in now
		var into: Variant = node_for.call(bit.pos)
		if into is Node3D and is_instance_valid(into) and into != bit.node.get_parent():
			bit.node.reparent(into)


## A piece come down at `at`: which way it would tip off if most of it is over nothing (ZERO if it lies flat).
## Small pieces lie anywhere.
func _overhang(bit: Bit, at: Vector3) -> Vector3:
	if world == null or bit.size < 0.06:
		return Vector3.ZERO
	var r := bit.size * 0.45
	var free: Array = []
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var p := at + d * r
		if world.fall_hit(p + Vector3(0.0, 0.04, 0.0), p - Vector3(0.0, 0.06, 0.0)).is_empty():
			free.append(d)
	if free.size() < 2:
		return Vector3.ZERO
	var going := Vector3(bit.vel.x, 0.0, bit.vel.z)
	var best: Vector3 = free[0]
	for d: Vector3 in free:                  # off the side it was going
		if d.dot(going) > best.dot(going):
			best = d
	return best


## A tracer from bit.from to bit.to, its tail running in towards the far end as it goes.
func _place_tracer(bit: Bit) -> void:
	var k := bit.t / bit.life
	var a := bit.from.lerp(bit.to, smoothstep(0.3, 1.0, k) * 0.92)
	var along := bit.to - a
	var to_eye := camera.global_position - (a + bit.to) * 0.5 if camera else Vector3.BACK
	var side := along.cross(to_eye)
	if side.length_squared() < 1e-10:
		side = along.cross(Vector3.UP)
	side = side.normalized()
	var face := along.cross(side).normalized()
	if face.dot(to_eye) < 0.0:
		face = -face
		side = -side
	var wide := bit.size                     # wider further off, so it reads about as wide on screen
	if camera:
		var eye := camera.global_position
		wide = clampf(eye.distance_to(Geometry3D.get_closest_point_to_segment(eye, a, bit.to)) * TRACER_SPREAD, bit.size, TRACER_WIDEST)
	bit.node.global_transform = Transform3D(Basis(along, side * wide, face), a)


func _place_falling(bit: Bit, eye: Basis) -> void:
	match bit.kind:
		PIECE:
			bit.node.global_transform = Transform3D(bit.turn, bit.pos)
		TRACER:
			_place_tracer(bit)
		SHELL:
			_place_billboard(bit, eye, Vector2(bit.size, bit.size))
		SHARD:
			_place_billboard(bit, eye, Vector2(bit.size * (0.3 + 0.7 * absf(cos(bit.tumble))), bit.size))
		CHIP, DROP:
			_place_billboard(bit, eye, Vector2.ONE * bit.size)
		STREAK:
			var v := bit.vel
			bit.ang = atan2(v.dot(eye.y), v.dot(eye.x))
			_place_billboard(bit, eye, Vector2(bit.size * (1.0 - bit.t / bit.life * 0.6), bit.size))


## Face the camera, turned `ang` in its own plane, `sizes` big (x along that turn, y across).
func _place_billboard(bit: Bit, eye: Basis, sizes: Vector2) -> void:
	var c := cos(bit.ang)
	var s := sin(bit.ang)
	var x := eye.x * c + eye.y * s
	var y := -eye.x * s + eye.y * c
	bit.node.global_transform = Transform3D(Basis(x * sizes.x, y * sizes.y, eye.z * maxf(sizes.x, sizes.y)), bit.pos)
