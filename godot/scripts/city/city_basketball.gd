extends Node3D
## Optional court activity. Static balls cost no physics ticks; only throws move.
## The level owns input/modal priority and calls tick from its gameplay loop.
const BALL_RADIUS := 0.12
const PICKUP_DISTANCE := 2.3
const ACTIVE_DISTANCE := 65.0
const MAX_ACTIVE := 3
const MAX_FLIGHT_SECONDS := 18.0
const CHARGE_SECONDS := 1.1
const GRAVITY := 9.8
const WORLD_MASK := 1 | 2

var balls: Array[Dictionary] = []
var baskets := 0
var shots := 0
var _level: Node3D
var _player: Node3D
var _held := -1
var _charging := false
var _charge := 0.0
var _mesh: ArrayMesh
var _shape: SphereShape3D
var _notice := ""
var _notice_time := 0.0

func setup(level: Node3D, courts: Node3D) -> Dictionary:
	name = "CourtBasketballs"
	_level = level
	_player = level.player
	if _player.has_method("set_court_activity"):
		_player.set_court_activity(self)
	_mesh = _make_ball_mesh()
	_shape = SphereShape3D.new()
	_shape.radius = BALL_RADIUS
	for court in courts.records:
		var body := CharacterBody3D.new()
		body.name = "Basketball_%s" % str(court.id)
		# Balls collide with terrain/backboards, never strike residents or player.
		body.collision_layer = 0
		body.collision_mask = WORLD_MASK
		body.safe_margin = 0.002
		var collider := CollisionShape3D.new()
		collider.shape = _shape
		body.add_child(collider)
		var visual := MeshInstance3D.new()
		visual.mesh = _mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)
		add_child(body)
		var home: Vector3 = court.position + Vector3.UP * (BALL_RADIUS + 0.04)
		body.global_position = home
		balls.append({"body": body, "visual": visual, "home": home,
			"court_id": str(court.id), "hoops": court.hoops, "active": false,
			"age": 0.0, "scored": false, "radius": float(court.get("length_m", 28.0)) * 0.5 + 12.0})
	set_presence(_player.global_position)
	return get_status()

func _playable() -> bool:
	if not is_instance_valid(_player) or not is_instance_valid(_level):
		return false
	if not _player.enabled or _level.paused or not _level.ready_to_play or get_tree().paused:
		return false
	if _player.has_method("is_seated") and _player.is_seated():
		return false
	var impact = _player.get("impact_recovery")
	if (impact is float or impact is int) and float(impact) > 0.0:
		return false
	var combat = _player.get("combat")
	if is_instance_valid(combat) and combat.has_method("blocks_movement") and combat.blocks_movement():
		return false
	var phone = _player.get("phone")
	return phone == null or not bool(phone.get("active"))

func tick(delta: float) -> void:
	if not _playable():
		cancel_charge()
		return
	_notice_time = maxf(0.0, _notice_time - delta)
	if _held >= 0:
		var held: Dictionary = balls[_held]
		if _player.global_position.distance_to(held.home) > ACTIVE_DISTANCE:
			return_ball(_held)
			_notice = "Ball returned to its court."
			_notice_time = 3.0
		else:
			held.body.global_position = _hold_position()
			if _charging:
				_charge = minf(1.0, _charge + delta / CHARGE_SECONDS)
	for i in balls.size():
		var ball: Dictionary = balls[i]
		if not ball.active:
			continue
		var body: CharacterBody3D = ball.body
		ball.age += delta
		if not body.global_position.is_finite() or body.global_position.y < ball.home.y - 5.0 or ball.age > MAX_FLIGHT_SECONDS or body.global_position.distance_to(ball.home) > ball.radius or body.global_position.distance_to(_player.global_position) > ACTIVE_DISTANCE:
			return_ball(i)
			continue
		var before := body.global_position
		body.velocity.y -= GRAVITY * delta
		var collision := body.move_and_collide(body.velocity * delta)
		if collision != null:
			var normal := collision.get_normal()
			# Only real, energetic contacts sound; resting/rolling balls stay quiet.
			if absf(body.velocity.dot(normal)) >= 1.0:
				var ambience := _level.get_node_or_null("NeighborhoodAudio")
				if ambience != null:
					ambience.play_activity("court_bounce", collision.get_position())
			body.velocity = body.velocity.bounce(normal) * 0.68
			if normal.y > 0.65 and absf(body.velocity.y) < 0.75:
				body.velocity.y = 0.0
				body.velocity.x *= 0.75
				body.velocity.z *= 0.75
				if body.velocity.length() < 0.4:
					ball.active = false
					body.velocity = Vector3.ZERO
		if not ball.scored:
			for hoop in ball.hoops:
				if crosses_rim(before, body.global_position, hoop.rim_position):
					ball.scored = true
					baskets += 1
					_notice = "Basket! %d made" % baskets
					_notice_time = 3.0
					break
		ball.visual.rotate_x(body.velocity.z * delta / BALL_RADIUS)
		ball.visual.rotate_z(-body.velocity.x * delta / BALL_RADIUS)
	set_presence(_player.global_position)

## Pass E here before the ordinary conversation/check-in interaction.
func interact() -> bool:
	if not _playable():
		return false
	if _held >= 0:
		_make_room_for_throw()
		var dropped: Dictionary = balls[_held]
		dropped.active = true
		dropped.age = 0.0
		dropped.body.velocity = Vector3.ZERO
		_held = -1
		cancel_charge()
		return true
	var nearest := _nearest_ball()
	if nearest < 0:
		return false
	_held = nearest
	balls[_held].active = false
	balls[_held].body.velocity = Vector3.ZERO
	balls[_held].body.global_position = _hold_position()
	cancel_charge()
	return true

## Context-only mouse input: an empty hand never consumes LMB.
func handle_input(event: InputEvent) -> bool:
	if not _playable() or _held < 0:
		cancel_charge()
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_charging = true
			_charge = 0.0
		elif _charging:
			shoot()
		return true
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_R or event.keycode == KEY_R):
		return_ball(_held)
		return true
	return false

func cancel_charge() -> void:
	_charging = false
	_charge = 0.0

func suspend(return_held := false) -> void:
	cancel_charge()
	if return_held and _held >= 0:
		return_ball(_held)

func shoot() -> bool:
	if _held < 0 or not _playable():
		cancel_charge()
		return false
	_make_room_for_throw()
	var ball: Dictionary = balls[_held]
	ball.body.global_position = _hold_position()
	ball.body.velocity = shot_velocity(_aim_direction(), _charge)
	ball.active = true
	ball.age = 0.0
	ball.scored = false
	shots += 1
	_held = -1
	cancel_charge()
	return true

func _make_room_for_throw() -> void:
	# A fixed cap includes other balls left bouncing on adjacent courts.
	var active := 0
	for ball in balls:
		active += int(ball.active)
	if active >= MAX_ACTIVE:
		for i in balls.size():
			if balls[i].active:
				return_ball(i)
				break

static func shot_velocity(aim: Vector3, charge: float) -> Vector3:
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	if flat.length_squared() < 0.1:
		flat = Vector3.FORWARD
	# Camera normally looks slightly down from the walking boom. Give throws an
	# upward arc while still allowing deliberate higher/lower camera aiming.
	var elevation := clampf(aim.y + 0.65, 0.38, 0.88)
	return (flat * sqrt(1.0 - elevation * elevation) + Vector3.UP * elevation) * lerpf(6.5, 13.5, clampf(charge, 0.0, 1.0))

static func crosses_rim(before: Vector3, after: Vector3, rim: Vector3) -> bool:
	if before.y <= rim.y or after.y > rim.y or before.y <= after.y:
		return false
	var at := before.lerp(after, (before.y - rim.y) / (before.y - after.y))
	# Actual visual rim radius .225m; the whole .12m ball must fit inside it.
	return Vector2(at.x - rim.x, at.z - rim.z).length() <= 0.225 - BALL_RADIUS

func return_ball(index: int) -> void:
	if index < 0 or index >= balls.size():
		return
	if _held == index:
		_held = -1
		cancel_charge()
	var ball: Dictionary = balls[index]
	ball.active = false
	ball.age = 0.0
	ball.scored = false
	ball.body.velocity = Vector3.ZERO
	ball.body.global_position = ball.home

func _aim_direction() -> Vector3:
	var camera: Camera3D = _player.get("camera")
	if is_instance_valid(camera):
		return -camera.global_basis.z
	return -_player.global_basis.z

## Final upper-body layer after the ordinary walk/jump pose. The lower body
## and free arm retain locomotion; charging brings up the supporting hand.
func apply_player_pose(delta: float) -> void:
	if _held < 0 or not _playable():
		return
	var combat = _player.get("combat")
	if is_instance_valid(combat) and (bool(combat.get("aiming")) or float(combat.get("reloading")) > 0.0):
		return
	var puppet: Puppet = _player.get("puppet")
	if puppet == null or puppet.arms.size() < 2:
		return
	# Settle into the view only while standing. A running player's torso keeps
	# its movement heading, and the ball follows that body rather than orbiting it.
	if float(_player.get("current_speed")) < 0.1 and not bool(_player.get("_jump_active")):
		_player.yaw = rotate_toward(float(_player.get("yaw")), float(_player.get("camera_yaw")), delta * 4.0)
		puppet.g.rotation.y = float(_player.yaw)
	var lift := smoothstep(0.0, 1.0, _charge) if _charging else 0.0
	var sway := sin(puppet.phase) * 0.035 * clampf(float(_player.get("current_speed")) / 3.8, 0.0, 1.0)
	puppet.arms[0].rotation = Vector3(lerpf(-1.05, -1.95, lift) + sway, 0.0, 0.22)
	if _charging:
		puppet.arms[1].rotation.x = lerpf(-0.65, -1.75, lift)
		puppet.arms[1].rotation.z = -0.45
	# Player physics can run after the level's activity tick: attach after the
	# final pose too, so the palm and ball never separate by a frame of walking.
	balls[_held].body.global_position = _hold_position()

func _hold_position() -> Vector3:
	var puppet: Puppet = _player.get("puppet")
	var forward := -_player.global_basis.z
	if puppet != null:
		forward = puppet.g.global_basis.z.normalized()
	var origin := _player.global_position + Vector3.UP * 1.25
	var target := origin + forward * 0.45 + forward.cross(Vector3.UP) * 0.20
	if puppet != null and not puppet.hands.is_empty():
		target = puppet.hand_pos(0) + forward * BALL_RADIUS + Vector3.UP * (BALL_RADIUS * 0.45)
	# Prevent carrying/launching the ball through a wall at arm's length.
	var ray := PhysicsRayQueryParameters3D.create(origin, target + forward * BALL_RADIUS, WORLD_MASK)
	if _player is CollisionObject3D:
		ray.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit.position + hit.normal * (BALL_RADIUS + 0.02)
	return target

func _nearest_ball() -> int:
	var nearest := -1
	var distance := PICKUP_DISTANCE * PICKUP_DISTANCE
	var origin := _player.global_position + Vector3.UP
	for i in balls.size():
		var ball: Dictionary = balls[i]
		var at: Vector3 = ball.body.global_position
		var squared := origin.distance_squared_to(at)
		if squared >= distance:
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, at, WORLD_MASK)
		if _player is CollisionObject3D:
			ray.exclude = [_player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		distance = squared
		nearest = i
	return nearest

func interaction_prompt() -> String:
	if not _playable():
		return ""
	if _held >= 0:
		if _charging:
			return "Shot power %d%% • release LMB to shoot • E drop • R return" % roundi(_charge * 100.0)
		return "Aim with mouse • hold LMB to charge, release to shoot • E drop • R return"
	if _nearest_ball() >= 0:
		return "E · Pick up basketball"
	if _notice_time > 0.0:
		return _notice
	return ""

func set_presence(center: Vector3, _near_radius := 55.0, _far_radius := 180.0) -> void:
	for i in balls.size():
		balls[i].visual.visible = i == _held or center.distance_squared_to(balls[i].body.global_position) < ACTIVE_DISTANCE * ACTIVE_DISTANCE

func get_status() -> Dictionary:
	var active := 0
	var visible := 0
	for ball in balls:
		active += int(ball.active)
		visible += int(ball.visual.visible)
	return {"enabled": not balls.is_empty(), "balls": balls.size(), "active": active,
		"visible": visible, "held": _held >= 0, "charging": _charging, "charge": _charge,
		"shots": shots, "baskets": baskets, "max_active": MAX_ACTIVE}

func _make_ball_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	const SLICES := 32
	const RINGS := 16
	for ring in RINGS:
		for segment in SLICES:
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var latitude := PI * float(ring + corner.y) / RINGS
				var longitude := TAU * float(segment + corner.x) / SLICES
				var normal := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
				vertices.append(normal * BALL_RADIUS)
				normals.append(normal)
				var seam := absf(normal.y) < 0.025 or absf(normal.x) < 0.025 or absf(normal.z) < 0.025
				colors.append(Color(0.10, 0.045, 0.016) if seam else Color(0.88, 0.30, 0.055))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh
