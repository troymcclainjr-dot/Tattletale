extends CharacterBody3D
## Local exploration controller. The original game's simulation is deliberately unused.

var puppet: Puppet
var camera: Camera3D
var yaw := 0.0
var camera_yaw := 0.0
var camera_pitch := 0.24
var first_person := false
var enabled := false
var distance_walked := 0.0
var walk_speed := 3.8
var run_speed := 7.2
var mouse_sensitivity := 0.0024
var invert_y := false
var camera_fov := 68.0
var current_speed := 0.0
var stepped_this_frame := false
var camera_override: Dictionary = {}
var orbiting := false
# Keep held movement stable through orbit/release and automatic camera following.
# A fresh movement gesture adopts the camera's new bearing.
var _orbit_movement_yaw := 0.0
var _orbit_basis_latched := false
const STEP_HEIGHT := 0.28
const STEP_SURFACES := 1 | 2
const CAMERA_LOOK_GRACE := 0.85
var _capsule: CollisionShape3D
var debug_step_reason := "not attempted"
var _pose_speed := 0.0
var _camera_anchor_y := 0.0
var _camera_anchor_valid := false
var _camera_last_player_position := Vector3.ZERO
var _camera_look_grace := 0.0
var _camera_moving_time := 0.0
var _camera_boom_length := 0.0
var _camera_collision_shape: SphereShape3D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 16
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.72
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.87
	add_child(shape)
	_capsule = shape
	puppet = Cast.person("two_pack", self)
	camera = Camera3D.new()
	camera.name = "ExplorationCamera"
	camera.fov = 68.0
	camera.near = 0.09
	camera.far = 1500.0
	add_child(camera)
	camera.top_level = true
	camera.current = true
	_camera_collision_shape = SphereShape3D.new()
	_camera_collision_shape.radius = 0.18
	update_camera()

func look(relative: Vector2) -> void:
	if relative.length_squared() > 0.0001:
		_camera_look_grace = CAMERA_LOOK_GRACE
	var yaw_change := -relative.x * mouse_sensitivity
	camera_yaw += yaw_change
	if _orbit_basis_latched and not orbiting:
		_orbit_movement_yaw += yaw_change
	var vertical := relative.y * mouse_sensitivity * (0.0022 / 0.0024)
	camera_pitch = clampf(camera_pitch + vertical * (-1.0 if invert_y else 1.0), -0.35, 1.05)

func set_orbiting(active: bool) -> void:
	if active == orbiting:
		return
	if active and not _orbit_basis_latched:
		_orbit_movement_yaw = camera_yaw
		_orbit_basis_latched = true
	orbiting = active
	_camera_look_grace = CAMERA_LOOK_GRACE

func toggle_view() -> void:
	first_person = not first_person
	puppet.g.visible = not first_person
	update_camera()

func _physics_process(delta: float) -> void:
	var before := global_position
	var was_grounded := is_on_floor()
	var requested_motion := Vector3.ZERO
	var move := Vector2.ZERO
	stepped_this_frame = false
	_camera_look_grace = maxf(0.0, _camera_look_grace - delta)
	if enabled:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		var keyboard_turn := (Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")) * delta * 1.7
		camera_yaw += keyboard_turn
		if absf(keyboard_turn) > 0.0001:
			_camera_look_grace = CAMERA_LOOK_GRACE
		if _orbit_basis_latched and not orbiting:
			_orbit_movement_yaw += keyboard_turn
	if not orbiting and (move.length() <= 0.01 or not enabled):
		_orbit_basis_latched = false
	velocity.x = 0.0
	velocity.z = 0.0
	var target_speed := 0.0
	if move.length() > 0.01:
		var movement_yaw := _orbit_movement_yaw if _orbit_basis_latched else camera_yaw
		var direction := Vector3(sin(movement_yaw) * move.y - cos(movement_yaw) * move.x, 0.0, cos(movement_yaw) * move.y + sin(movement_yaw) * move.x).normalized()
		var wanted := atan2(direction.x, direction.z)
		var turn_error := absf(angle_difference(yaw, wanted))
		var turn_rate := 4.0 + minf(6.0, turn_error * 4.0)
		yaw = rotate_toward(yaw, wanted, delta * turn_rate)
		target_speed = (run_speed if Input.is_action_pressed("run") else walk_speed) * move.length()
		# Steer travel and body together. Ordinary corners retain speed; a tight
		# reversal eases down into a forward arc instead of stopping or backpedaling.
		var reversal := clampf((turn_error - PI * 0.5) / (PI * 0.5), 0.0, 1.0)
		target_speed *= lerpf(1.0, 0.45, reversal)
	if not enabled:
		current_speed = 0.0
	else:
		current_speed = move_toward(current_speed, target_speed, (18.0 if target_speed > current_speed else 24.0) * delta)
	if current_speed > 0.001 and enabled:
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		requested_motion = forward * current_speed * delta
		var curb_top := _walkable_step_top(requested_motion) if was_grounded else {}
		if was_grounded and (not curb_top.is_empty() or _curb_ahead(requested_motion)):
			stepped_this_frame = _try_step(requested_motion, curb_top)
		if not stepped_this_frame:
			# Let the full capsule's collision solver remove the into-wall component
			# while retaining tangential movement. A preflight all-or-nothing test
			# caused hard stops on every diagonal facade or porch-post contact.
			velocity.x = forward.x * current_speed
			velocity.z = forward.z * current_speed
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = -0.5
	if not stepped_this_frame:
		move_and_slide()
	# A triangle seam can report the same valid floor contact repeatedly and consume
	# every slide iteration. Project onto the intended direction so diagonal curb
	# sliding cannot be mistaken for forward progress.
	var displacement := global_position - before
	displacement.y = 0.0
	var horizontal_progress := maxf(0.0, displacement.dot(requested_motion.normalized())) if requested_motion.length() > 0.001 else 0.0
	if not stepped_this_frame and (was_grounded or is_on_floor()) and requested_motion.length() > 0.001 and horizontal_progress < requested_motion.length() * 0.85:
		var remaining := requested_motion.normalized() * maxf(0.0, requested_motion.length() - horizontal_progress)
		stepped_this_frame = _try_step(remaining)
	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if requested_motion.length() > 0.001 and travelled < requested_motion.length() * 0.05:
		current_speed = 0.0
	distance_walked += travelled
	var visual_yaw := atan2(displacement.x, displacement.z) if is_on_wall() and travelled > 0.001 else yaw
	puppet.g.rotation.y = rotate_toward(puppet.g.rotation.y, visual_yaw, delta * 12.0)
	var actual_speed := travelled / maxf(delta, 0.0001)
	_pose_speed = move_toward(_pose_speed, minf(actual_speed, run_speed), delta * 24.0)
	var run_blend := clampf((_pose_speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var moving_blend := clampf(_pose_speed / walk_speed, 0.0, 1.0)
	puppet.phase += travelled * lerpf(3.5, 2.8, run_blend)
	var swing := sin(puppet.phase) * lerpf(0.42, 0.78, run_blend) * moving_blend
	puppet.pose({"walk": lerpf(0.48, 0.72, run_blend) * moving_blend,
		"armR": [-swing - 0.12 * run_blend, 0.08], "armL": [swing - 0.12 * run_blend, 0.08],
		"lean": lerpf(0.025, 0.12, run_blend) * moving_blend,
		"bob": absf(sin(puppet.phase)) * lerpf(0.015, 0.028, run_blend) * moving_blend})
	_update_camera_follow(delta, move, actual_speed, visual_yaw)
	update_camera(delta)

func _update_camera_follow(delta: float, move: Vector2, actual_speed: float, travel_yaw: float) -> void:
	if not enabled or move.length() < 0.01 or actual_speed < 0.5:
		_camera_moving_time = 0.0
		return
	_camera_moving_time += delta
	if first_person or orbiting or not camera_override.is_empty() or _camera_look_grace > 0.0 or _camera_moving_time < 0.75:
		return
	var error := angle_difference(camera_yaw, travel_yaw)
	if absf(error) < deg_to_rad(4.0):
		return
	# Input inactivity gets a grace period; idle views never recenter. Preserve
	# the held input's world bearing so camera assistance cannot steer the player.
	if not _orbit_basis_latched:
		_orbit_movement_yaw = camera_yaw
		_orbit_basis_latched = true
	var rate := minf(0.85, absf(error) * 1.8)
	camera_yaw = rotate_toward(camera_yaw, travel_yaw, delta * rate)

func _obstacle_motion_clear(from: Transform3D, motion: Vector3, mask: int = 8 | 16) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule.shape
	query.transform = from * _capsule.transform
	query.motion = motion
	query.collision_mask = collision_mask & mask
	query.exclude = [get_rid()]
	query.margin = safe_margin
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		return false
	query.transform.origin += motion
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 4).is_empty()

func _curb_ahead(motion: Vector3) -> bool:
	var forward := motion.normalized()
	var right := Vector3(-forward.z, 0, forward.x)
	var foot_y := global_position.y + 0.01
	var ahead := minf(0.42, 0.30 + motion.length())
	for side in [-0.18, 0.0, 0.18]:
		var point: Vector3 = global_position + forward * ahead + right * float(side)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, foot_y + STEP_HEIGHT + 0.04, point.z), Vector3(point.x, foot_y - floor_snap_length, point.z), STEP_SURFACES)
		ray.hit_back_faces = false
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.normal.y >= cos(floor_max_angle):
			var difference: float = hit.position.y - foot_y
			if absf(difference) > 0.045 and difference <= STEP_HEIGHT and difference >= -floor_snap_length:
				return true
	return false

func _walkable_step_top(motion: Vector3) -> Dictionary:
	# A rounded capsule may touch a curb's convex edge before its center is above
	# the pavement. Verify the actual top and the approached riser, not that edge's
	# blended contact normal. Sampling from terrain height also avoids lift/drop
	# oscillation while the capsule center is still on the lower side of the curb.
	var space := get_world_3d().direct_space_state
	var ground_ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.08, global_position - Vector3.UP * (floor_snap_length + 0.1), STEP_SURFACES)
	ground_ray.hit_back_faces = false
	var ground := space.intersect_ray(ground_ray)
	if ground.is_empty() or ground.normal.y < cos(floor_max_angle):
		return {}
	var base_y: float = ground.position.y
	if global_position.y - base_y > STEP_HEIGHT + 0.03:
		return {}
	var forward := motion.normalized()
	var right := Vector3(-forward.z, 0, forward.x)
	var ahead := minf(0.42, 0.30 + motion.length())
	for side in [0.0, -0.18, 0.18]:
		var point: Vector3 = global_position + forward * ahead + right * float(side)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, base_y + STEP_HEIGHT + 0.035, point.z), Vector3(point.x, base_y - 0.08, point.z), STEP_SURFACES)
		ray.hit_back_faces = false
		var top := space.intersect_ray(ray)
		if top.is_empty() or top.normal.y < cos(floor_max_angle):
			continue
		var rise: float = top.position.y - base_y
		if rise < 0.045 or rise > STEP_HEIGHT:
			continue
		# On an uphill road the curb's base can already be above our feet. A
		# single low ray then hits the road instead of the curb and falsely rejects
		# a walkable step. Sample within the verified rise, still requiring a
		# near-vertical terrain riser facing this approach; a steep ramp is not one.
		for fraction in [0.25, 0.5, 0.75]:
			var riser_y: float = base_y + rise * float(fraction)
			var low_ray := PhysicsRayQueryParameters3D.create(Vector3(global_position.x, riser_y, global_position.z), Vector3(point.x, riser_y, point.z), STEP_SURFACES)
			low_ray.hit_back_faces = false
			var riser := space.intersect_ray(low_ray)
			if riser.is_empty() or absf(riser.normal.y) > 0.5:
				continue
			var outward: Vector3 = riser.normal
			outward.y = 0.0
			if -forward.dot(outward.normalized()) <= 0.08:
				continue
			return {"height": top.position.y, "normal": top.normal}
	return {}

func _try_step(motion: Vector3, curb_top: Dictionary = {}) -> bool:
	# Sweep the complete capsule along all three legs of a small step. A tall wall,
	# overhang, missing landing, or steep landing rejects the move without teleporting.
	if not _obstacle_motion_clear(global_transform, motion):
		debug_step_reason = "solid obstacle blocks step"
		return false
	if curb_top.is_empty():
		curb_top = _walkable_step_top(motion)
	var ascent := KinematicCollision3D.new()
	if test_move(global_transform, Vector3.UP * STEP_HEIGHT, ascent, safe_margin, false, 8):
		# At a downhill curb, the capsule can retain a zero-travel contact with
		# the higher sidewalk despite moving away from its walkable normal.
		# Only static tread/terrain contact is eligible; actors and ceilings fail.
		for i in ascent.get_collision_count():
			var obstacle = ascent.get_collider(i)
			if not obstacle is CollisionObject3D or (obstacle.collision_layer & STEP_SURFACES) == 0:
				debug_step_reason = "ascent obstacle=%s normal=%s" % [_obstacle_path(obstacle), ascent.get_normal(i)]
				return false
			var separating_curb := not curb_top.is_empty() and ascent.get_normal(i).y >= -0.01
			if ascent.get_normal(i).y < cos(floor_max_angle) and not separating_curb:
				debug_step_reason = "ascent steep normal=%s obstacle=%s" % [ascent.get_normal(i), _obstacle_path(obstacle)]
				return false
	var raised := global_transform
	raised.origin.y += STEP_HEIGHT
	# The raised pose must actually be empty, even if an earlier floor contact
	# masked another surface in the ascent sweep.
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = _capsule.shape
	clearance.transform = raised * _capsule.transform
	clearance.collision_mask = collision_mask
	clearance.exclude = [get_rid()]
	clearance.margin = safe_margin
	var overlaps := get_world_3d().direct_space_state.intersect_shape(clearance, 8)
	if not overlaps.is_empty():
		debug_step_reason = "raised overlap=%s raised=%s count=%d" % [_obstacle_path(overlaps[0].collider), raised.origin, overlaps.size()]
		return false
	var forward_contact := KinematicCollision3D.new()
	if test_move(raised, motion, forward_contact):
		debug_step_reason = "forward obstacle=%s normal=%s travel=%s" % [_obstacle_path(forward_contact.get_collider()), forward_contact.get_normal(), forward_contact.get_travel()]
		return false
	raised.origin += motion
	var support_motion := Vector3.DOWN * (STEP_HEIGHT + floor_snap_length)
	clearance.transform = raised * _capsule.transform
	clearance.motion = support_motion
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(clearance)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		debug_step_reason = "support shape cast absent from=%s depth=%.3f fractions=%s" % [raised.origin, support_motion.length(), fractions]
		return false
	var landing := raised.origin + support_motion * fractions[0]
	if not curb_top.is_empty():
		var foot_offset := _capsule.position.y - (_capsule.shape as CapsuleShape3D).height * 0.5
		var top_landing := raised.origin
		top_landing.y = float(curb_top.height) - foot_offset + 0.012
		# Only descend within the already swept clear interval. A final complete
		# capsule occupancy check protects the side edges of diagonal approaches.
		if top_landing.y >= landing.y and top_landing.y <= raised.origin.y and top_landing.y - global_position.y <= STEP_HEIGHT + 0.001:
			clearance.transform = Transform3D(global_transform.basis, top_landing) * _capsule.transform
			clearance.motion = Vector3.ZERO
			if space.intersect_shape(clearance, 8).is_empty():
				global_position = top_landing
				velocity.y = 0.0
				debug_step_reason = "stepped to verified curb top=%s safe_landing=%s" % [top_landing, landing]
				return true
	# Inspect the actual supporting surface just beyond the unsafe contact fraction.
	clearance.transform = raised * _capsule.transform
	clearance.transform.origin += support_motion * minf(1.0, fractions[1] + 0.02 / support_motion.length())
	clearance.motion = Vector3.ZERO
	var support := space.get_rest_info(clearance)
	var support_normal := Vector3.ZERO
	if support.is_empty():
		# The capsule sweep still supplies the safe landing. At a thin triangle
		# edge, a front-face terrain ray can supply its missing contact normal,
		# but only when its height agrees with the capsule's physical landing.
		var foot_y := landing.y + _capsule.position.y - (_capsule.shape as CapsuleShape3D).height * 0.5
		var ray := PhysicsRayQueryParameters3D.create(Vector3(landing.x, foot_y + 0.22, landing.z), Vector3(landing.x, foot_y - 0.22, landing.z), STEP_SURFACES)
		ray.hit_back_faces = false
		var terrain := space.intersect_ray(ray)
		if terrain.is_empty() or absf(terrain.position.y - foot_y) > 0.20:
			debug_step_reason = "support rest and agreeing terrain absent fractions=%s pose=%s" % [fractions, clearance.transform.origin]
			return false
		support_normal = terrain.normal
	else:
		support_normal = support.normal
	if support_normal.y < cos(floor_max_angle):
		debug_step_reason = "support steep normal=%s fractions=%s" % [support_normal, fractions]
		return false
	global_position = landing + Vector3.UP * 0.003
	velocity.y = 0.0
	debug_step_reason = "stepped to=%s fractions=%s normal=%s" % [global_position, fractions, support_normal]
	return true

func _obstacle_path(obstacle) -> String:
	return str(obstacle.get_path()) if obstacle is Node else str(obstacle)

func update_camera(delta := 0.0) -> void:
	if camera == null:
		return
	camera.fov = clampf(camera_fov, 45.0, 95.0)
	if delta <= 0.0 or not _camera_anchor_valid or global_position.distance_to(_camera_last_player_position) > 3.0:
		_camera_anchor_y = global_position.y
		_camera_anchor_valid = true
	else:
		_camera_anchor_y = lerpf(_camera_anchor_y, global_position.y, 1.0 - exp(-delta * 14.0))
	_camera_last_player_position = global_position
	if not camera_override.is_empty():
		puppet.g.visible = not first_person
		camera.global_position = camera_override.eye
		camera.look_at(camera_override.target, Vector3.UP)
		return
	var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
	var camera_anchor := Vector3(global_position.x, _camera_anchor_y, global_position.z)
	var target := camera_anchor + Vector3.UP * 1.50
	if first_person:
		puppet.g.hide()
		camera.global_position = camera_anchor + Vector3.UP * 1.64
		camera.look_at(camera.global_position + forward * cos(camera_pitch) - Vector3.UP * sin(camera_pitch), Vector3.UP)
	else:
		var boom := -forward * cos(camera_pitch) * 5.2 + Vector3.UP * (sin(camera_pitch) * 5.2 + 0.65)
		var sweep := PhysicsShapeQueryParameters3D.new()
		sweep.shape = _camera_collision_shape
		sweep.transform.origin = target
		sweep.motion = boom
		sweep.collision_mask = 1 | 2 | 16
		sweep.exclude = [get_rid()]
		var fractions := get_world_3d().direct_space_state.cast_motion(sweep)
		var safe_length := boom.length()
		if fractions.size() >= 2 and fractions[0] < 1.0:
			safe_length = maxf(0.05, safe_length * fractions[0] - 0.04)
		# Contract immediately to stay outside walls, then ease the boom back out
		# after an obstruction clears. A swept volume protects the near plane.
		if delta <= 0.0 or _camera_boom_length <= 0.0 or safe_length < _camera_boom_length:
			_camera_boom_length = safe_length
		else:
			_camera_boom_length = lerpf(_camera_boom_length, safe_length, 1.0 - exp(-delta * 6.0))
		var desired := target + boom.normalized() * _camera_boom_length
		# A wall or porch can push the chase camera inside the character's head.
		# Hide the local mesh only while compressed; looking away restores it.
		puppet.g.visible = desired.distance_to(target) >= 1.65
		camera.global_position = desired
		camera.look_at(target, Vector3.UP)
