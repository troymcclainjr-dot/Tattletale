extends Node3D
## What shots look like, drawn like everything else here: flat colours inside a fat ink line, no fading
## see-through stuff (a thing that goes, shrinks away). Everything is a flat shape built once and reused:
## a muzzle flash (a paper star for a frame or two, with a quick warm light), spent cases thrown from the
## port that bounce and lie on the floor, a puff and a mark where a shot hits a wall, a spark on metal,
## shards of glass, drops of blood and the pool that spreads under someone who is down.
##
## Capped: at most SHELLS cases, MARKS marks and SHARDS shards lie about; past that the oldest is taken
## up and used again. Nothing is made while shooting but the marks' first round.

const SHELLS := 40
const MARKS := 60
const SHARDS := 90
const GRAVITY := 9.8

enum {FLASH, SHELL, PUFF, CHIP, SPARK, STREAK, SHARD, DROP, BURST, MARK}
const CAPS := {FLASH: 8, SHELL: SHELLS, PUFF: 10, CHIP: 24, SPARK: 6, STREAK: 30, SHARD: SHARDS, DROP: 40, BURST: 6, MARK: MARKS}

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


var camera: Camera3D
var frozen := false             # a picture: nothing moves
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
func shards(center: Vector3, normal: Vector3, dir: Vector3, radius: float, count: int, ground: float, parent: Node3D) -> void:
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


## He has gone somewhere else: what was in the air is gone. What lies about stays where it is.
func drop_moving() -> void:
	for kind: int in _bits:
		for bit: Bit in _bits[kind]:
			if bit.alive and not bit.resting and kind != MARK:
				_kill(bit)
	_light.visible = false
	_light_t = -1.0


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


func _fall(bit: Bit, delta: float) -> void:
	bit.vel.y -= GRAVITY * delta
	bit.pos += bit.vel * delta
	bit.ang += bit.spin * delta
	bit.tumble += absf(bit.spin) * 0.7 * delta
	var lie := bit.ground + (bit.size * 0.21 + 0.004 if bit.kind == SHELL else bit.size * 0.35)
	if bit.pos.y > lie or bit.vel.y > 0.0:
		return
	bit.pos.y = lie
	match bit.kind:
		DROP, CHIP, STREAK:
			_kill(bit)
		SHELL:
			if absf(bit.vel.y) > 0.9:        # it bounces
				bit.vel = Vector3(bit.vel.x * 0.55, -bit.vel.y * 0.38, bit.vel.z * 0.55)
				bit.spin *= 0.55
			else:
				bit.vel = Vector3.ZERO
				bit.resting = true
				bit.ang = (0.0 if cos(bit.ang) >= 0.0 else PI) + _rng.randf_range(-0.12, 0.12)       # on its side
		SHARD:
			bit.vel = Vector3.ZERO
			bit.resting = true
			bit.tumble = PI * 0.5 * _rng.randf_range(0.6, 1.0)      # lying, seen nearly edge on


func _place_falling(bit: Bit, eye: Basis) -> void:
	match bit.kind:
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
