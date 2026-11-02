extends CharacterBody3D
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
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
var combat: Node3D
var phone: Node3D
var court_activity: Node3D
# Release of free look while moving swings the view back behind the held travel.
# When false, travel instead eases toward the view the player left it at.
var free_look_recenters_view := true
# Movement is camera-relative: the movement frame is camera_yaw + _basis_offset.
# Ordinary look keeps the offset, so the mouse steers. Free look and camera
# assistance turn only the view and accumulate an offset that preserves the held
# input's world bearing. A new key combination, or idling outside free look, clears it.
var _basis_offset := 0.0
var _basis_input := Vector2.ZERO
var _held_move := Vector2.ZERO
var _view_returning := false
# Compatibility for callers that clear the held frame after placing the player.
var _orbit_basis_latched: bool:
	get:
		return orbiting or not is_zero_approx(_basis_offset)
	set(value):
		if not value:
			_clear_basis_offset()
const STEP_HEIGHT := 0.28
const GRAVITY := 22.0
# About 2.37m of foot clearance at 60Hz: reaches every civilian roof and
# patrol-car lightbar without increasing the curb/stair step allowance.
const JUMP_SPEED := 10.4
const JUMP_BUFFER := 0.12
const COYOTE_TIME := 0.10
var _jump_buffer := 0.0
var _coyote_time := 0.0
var _jump_active := false
var _landing_pose := 0.0
var jumps_started := 0
const STEP_SURFACES := 1 | 2
const CAMERA_LOOK_GRACE := 0.85
# Keyboard combinations differ by 45 degrees; analog drift below this keeps the frame.
const INPUT_REBASE_ANGLE := 0.35
const FREE_LOOK_RETURN_GAIN := 7.0
const FREE_LOOK_RETURN_MIN_RATE := 1.2
const FREE_LOOK_RETURN_MAX_RATE := 6.0
# 100 degrees: running toward the camera never swings the view around.
const CAMERA_ASSIST_MAX_ERROR := 1.745
var _capsule: CollisionShape3D
var _physics_last_position := Vector3.INF
var _collision_bounds_refresh_ticks := 0
var debug_step_reason := "not attempted"
var _pose_speed := 0.0
var _camera_anchor_y := 0.0
var _camera_anchor_valid := false
var _camera_last_player_position := Vector3.ZERO
var _camera_look_grace := 0.0
var _camera_moving_time := 0.0
var _camera_boom_length := 0.0
var _camera_aim_blend := 0.0
var _camera_collision_shape: SphereShape3D
# A seat change (mounting, getting off, standing up after a crash) moves the
# camera's subject up to a few metres at once. The look-at point glides over
# from the old subject instead of cutting, and the boom keeps its length and
# eases to the new one. Teleports (respawn, checkpoint) still cut. The glide
# only ever shrinks; a swept sphere keeps it out of walls and cars.
const CAMERA_GLIDE_RATE := 7.0
const CAMERA_CUT_DISTANCE := 3.0
var _camera_glide := Vector3.ZERO
var _camera_last_target := Vector3.INF
var _camera_boom_carry := false
# Thin bodies the camera never treats as obstacles, because their collision is a
# coarse proxy: the explorer's bicycle keeps an upright hull even lying fallen,
# so a boom swept against it would jump in front of a few tubes.
var camera_ignore: Array[RID] = []

signal vehicle_impact(speed: float, source: String)
var vehicle_hits := 0
var impact_recovery := 0.0
var impact_cooldown := 0.0
var _impact_velocity := Vector3.ZERO
var _impact_duration := 0.0

# Seated in a car (city_driving.gd owns entry/exit). The body rides at the car
# origin with no collision layer/mask: no walking physics, jumps, floor riding
# or vehicle impacts. Position-based systems (streaming, presence, radar,
# missions) keep following it. The chase camera orbits the car instead.
const CHASE_DISTANCE := 6.2
const CHASE_PITCH := 0.24
const CHASE_TARGET_HEIGHT := 1.45
const CHASE_RECENTER_DELAY := 1.3
var seated_vehicle: Node3D
var _seated := false
var vehicle_orbit_yaw := 0.0
var vehicle_orbit_pitch := CHASE_PITCH
var chase_distance := CHASE_DISTANCE
var _vehicle_view_yaw := 0.0
var _vehicle_look_idle := 0.0
var _vehicle_shake := 0.0
var _vehicle_shake_phase := 0.0
var _seat_layer := 4
var _seat_mask := 1 | 2 | 8 | 16

func receive_vehicle_impact(direction: Vector3, hit_speed: float, source := "") -> bool:
	if not enabled or _seated or get_tree().paused or impact_cooldown > 0.0 or hit_speed < 2.0:
		return false
	var away := Vector3(direction.x, 0.0, direction.z).normalized()
	if away.length_squared() < 0.5:
		return false
	# A short non-gory stumble. The full capsule stays solid throughout recovery;
	# move_and_slide resolves walls, curbs, people and cars on each physics frame.
	_impact_duration = clampf(0.52 + hit_speed * 0.018, 0.58, 0.82)
	impact_recovery = _impact_duration
	impact_cooldown = _impact_duration + 0.65
	_impact_velocity = away * clampf(hit_speed * 0.48, 2.0, 7.0)
	_jump_buffer = 0.0
	_coyote_time = 0.0
	_jump_active = false
	yaw = atan2(away.x, away.z)
	current_speed = 0.0
	_pose_speed = 0.0
	_clear_basis_offset()
	vehicle_hits += 1
	vehicle_impact.emit(hit_speed, source)
	return true

func _tick_vehicle_impact(delta: float) -> void:
	impact_recovery = maxf(0.0, impact_recovery - delta)
	velocity.x = _impact_velocity.x
	velocity.z = _impact_velocity.z
	velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
	var before := global_position
	move_and_slide()
	# Use the solver's surviving horizontal direction, so a wall absorbs the
	# impulse instead of accumulating force or pushing the capsule through it.
	_impact_velocity = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, delta * 10.0)
	var displacement := global_position - before
	displacement.y = 0.0
	if displacement.length_squared() > 0.000001:
		yaw = atan2(displacement.x, displacement.z)
	puppet.g.rotation.y = rotate_toward(puppet.g.rotation.y, yaw, delta * 16.0)
	var stumble := sin(PI * clampf(impact_recovery / maxf(_impact_duration, 0.001), 0.0, 1.0))
	puppet.pose({"walk": 0.0, "armR": [-0.6 * stumble, 0.20], "armL": [-0.6 * stumble, -0.20],
		"lean": -0.30 * stumble, "bob": -0.08 * stumble})
	if impact_recovery <= 0.0:
		_impact_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
	update_camera(delta)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 16
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	# Even a shallow tangential component must slide around a round post. The
	# default 15-degree wall dead zone pins the capsule between a pole and curb.
	wall_min_slide_angle = 0.0
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
	if _seated:
		vehicle_look(relative)
		return
	if relative.length_squared() > 0.0001:
		_camera_look_grace = CAMERA_LOOK_GRACE
		if _view_returning and not orbiting:
			_clear_basis_offset()
	_turn_view(-relative.x * mouse_sensitivity)
	var vertical := relative.y * mouse_sensitivity * (0.0022 / 0.0024)
	var photographing: bool = phone != null and bool(phone.active)
	camera_pitch = clampf(camera_pitch + vertical * (-1.0 if invert_y else 1.0), -1.35 if photographing else -0.35, 1.35 if photographing else 1.05)

## Ordinary look turns the movement frame with the view, so the mouse steers held
## input. Free look turns only the view and preserves the frame's world bearing.
func _turn_view(amount: float) -> void:
	if absf(amount) > 0.000001 and _view_returning and not orbiting:
		_clear_basis_offset()
	camera_yaw += amount
	if orbiting:
		_basis_offset = wrapf(_basis_offset - amount, -PI, PI)

func set_orbiting(active: bool) -> void:
	if active == orbiting:
		return
	orbiting = active
	_camera_look_grace = CAMERA_LOOK_GRACE
	if active:
		_view_returning = false
	elif not enabled or _held_move.length() <= 0.01:
		# Idle: the chosen view becomes the frame for the next movement.
		_clear_basis_offset()
	else:
		_view_returning = not is_zero_approx(_basis_offset)

func _clear_basis_offset() -> void:
	_basis_offset = 0.0
	_view_returning = false

func _update_movement_basis(move: Vector2, delta: float) -> void:
	var held := enabled and move.length() > 0.01
	if not held:
		_basis_input = Vector2.ZERO
		if not orbiting:
			_clear_basis_offset()
	elif orbiting:
		# Track keys without rebasing while deliberately looking away.
		_basis_input = move
	elif _basis_input.length() <= 0.01 or absf(_basis_input.angle_to(move)) > INPUT_REBASE_ANGLE:
		# A new key combination is read against the view on screen now, dropping
		# any bearing camera assistance had preserved for the previous one.
		_clear_basis_offset()
		_basis_input = move
		_camera_moving_time = 0.0
	_held_move = move if held else Vector2.ZERO
	if _view_returning and held:
		var rate := clampf(absf(_basis_offset) * FREE_LOOK_RETURN_GAIN, FREE_LOOK_RETURN_MIN_RATE, FREE_LOOK_RETURN_MAX_RATE)
		var step := clampf(_basis_offset, -rate * delta, rate * delta)
		if free_look_recenters_view:
			camera_yaw += step
		_basis_offset -= step
		if is_zero_approx(_basis_offset):
			_clear_basis_offset()

func toggle_view() -> void:
	if _seated:
		return # The car has no cabin view; the walking mode is kept for exit.
	first_person = not first_person
	puppet.g.visible = not first_person
	update_camera()

func request_jump() -> bool:
	if not enabled or _seated or get_tree().paused or impact_recovery > 0.0 or (phone != null and phone.active) or (combat != null and combat.blocks_movement()):
		return false
	_jump_buffer = JUMP_BUFFER
	return true

func is_standing_on_vehicle(vehicle: CollisionObject3D) -> bool:
	# Seated: floor contacts are stale from before boarding, never a roof ride.
	if _seated or not is_on_floor() or velocity.y > 0.1:
		return false
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		if contact.get_collider() == vehicle and contact.get_normal().dot(up_direction) > cos(floor_max_angle):
			return true
	return false

func _floor_motion_velocity() -> Vector3:
	if not is_on_floor():
		return Vector3.ZERO
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		var body := contact.get_collider()
		if contact.get_normal().dot(up_direction) > cos(floor_max_angle) and body is CharacterBody3D:
			# Traffic ticks before us, whereas get_platform_velocity() still holds
			# last frame's speed while the car is accelerating or braking.
			return body.velocity
	return get_platform_velocity()

func reset_jump() -> void:
	_jump_buffer = 0.0
	_coyote_time = 0.0
	_jump_active = false
	_landing_pose = 0.0

func _unhandled_input(event: InputEvent) -> void:
	# Dialogue consumes Space before unhandled input; menus disable exploration.
	if Bindings.matches(event, "city_jump"):
		if request_jump():
			get_viewport().set_input_as_handled()

var profile_costs := false
var profile_samples: Array[float] = []
var profile_stages: Dictionary = {}
var profile_slow_stages: Array[Dictionary] = []

func _profile_stage(stage: String, began: int) -> int:
	if not profile_costs:
		return 0
	var ended := Time.get_ticks_usec()
	var elapsed := ended - began
	var entry: Dictionary = profile_stages.get(stage, {"count": 0, "total_usec": 0, "max_usec": 0, "max_frame": 0})
	entry.count += 1
	entry.total_usec += elapsed
	if elapsed > entry.max_usec:
		entry.max_usec = elapsed
		entry.max_frame = Engine.get_process_frames()
	profile_stages[stage] = entry
	if elapsed >= 2000 and profile_slow_stages.size() < 256:
		var event := {"stage": stage, "usec": elapsed, "frame": Engine.get_process_frames(), "position": [global_position.x, global_position.y, global_position.z]}
		if stage == "move_and_slide":
			event["contacts"] = []
			for index in get_slide_collision_count():
				var contact := get_slide_collision(index)
				event.contacts.append({"collider": _obstacle_path(contact.get_collider()), "normal": str(contact.get_normal()), "depth": contact.get_depth(), "position": str(contact.get_position())})
		profile_slow_stages.append(event)
	return Time.get_ticks_usec()

func set_court_activity(activity: Node3D) -> void:
	court_activity = activity

func _physics_process(delta: float) -> void:
	var began := Time.get_ticks_usec() if profile_costs else 0
	_refresh_teleport_collision_bounds()
	_physics_step(delta)
	if profile_costs:
		profile_samples.append(float(Time.get_ticks_usec() - began) / 1000.0)

func _refresh_teleport_collision_bounds() -> void:
	if not _physics_last_position.is_finite() or global_position.distance_squared_to(_physics_last_position) > CAMERA_CUT_DISTANCE * CAMERA_CUT_DISTANCE:
		_collision_bounds_refresh_ticks = 2
	# Remember the start, including seat-follow/other placements made inside the
	# previous callback. Ordinary walking/driving never crosses this cut distance.
	_physics_last_position = global_position
	if _collision_bounds_refresh_ticks <= 0 or not is_instance_valid(_capsule):
		return
	_collision_bounds_refresh_ticks -= 1
	# Godot Physics caches the kinematic sweep's bounds through the following
	# tick. A teleport otherwise makes move_and_slide cull a city-sized box.
	# Re-submit the same owned capsule transform on both sides of integration;
	# its geometry, enabled state, layers and all collision tests stay intact.
	for owner_id in get_shape_owners():
		if shape_owner_get_owner(owner_id) == _capsule:
			shape_owner_set_transform(owner_id, _capsule.transform)
			break

func _physics_step(delta: float) -> void:
	var stage_began := Time.get_ticks_usec() if profile_costs else 0
	if _seated:
		_tick_seated(delta)
		return
	if enabled and combat != null and combat.blocks_movement():
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
		move_and_slide()
		_jump_buffer = 0.0
		_jump_active = false
		current_speed = 0.0
		puppet.pose({"walk": 0.0})
		combat.apply_player_pose(delta)
		update_camera(delta)
		return
	if not enabled:
		_jump_buffer = 0.0
		_coyote_time = 0.0
		# Freeze passive falls as well as jumps behind menus and dialogue.
		update_camera(delta)
		return
	if enabled:
		impact_cooldown = maxf(0.0, impact_cooldown - delta)
	if impact_recovery > 0.0:
		if enabled:
			_tick_vehicle_impact(delta)
		else:
			update_camera(delta)
		return
	var before := global_position
	var was_grounded := is_on_floor()
	# CharacterBody carries us with the floor before applying our own velocity.
	# Capture that support velocity before the solver can switch floor contacts.
	var support_velocity := _floor_motion_velocity()
	stage_began = _profile_stage("support", stage_began) if profile_costs else 0
	if enabled and was_grounded and not _jump_active:
		_coyote_time = COYOTE_TIME
	else:
		_coyote_time = maxf(0.0, _coyote_time - delta)
	var jumped := enabled and _jump_buffer > 0.0 and _coyote_time > 0.0 and not _jump_active
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if jumped:
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote_time = 0.0
		_jump_active = true
		jumps_started += 1
	var requested_motion := Vector3.ZERO
	var move := Vector2.ZERO
	stepped_this_frame = false
	_camera_look_grace = maxf(0.0, _camera_look_grace - delta)
	if enabled and (phone == null or not phone.active):
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		var keyboard_turn := (Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")) * delta * 1.7
		_turn_view(keyboard_turn)
		if absf(keyboard_turn) > 0.0001:
			_camera_look_grace = CAMERA_LOOK_GRACE
	_update_movement_basis(move, delta)
	velocity.x = 0.0
	velocity.z = 0.0
	var target_speed := 0.0
	if move.length() > 0.01:
		var movement_yaw := camera_yaw + _basis_offset
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
	stage_began = _profile_stage("input", stage_began) if profile_costs else 0
	if current_speed > 0.001 and enabled:
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		requested_motion = forward * current_speed * delta
		var curb_top := _walkable_step_top(requested_motion) if was_grounded and not _jump_active else {}
		if was_grounded and not _jump_active and (not curb_top.is_empty() or _curb_ahead(requested_motion)):
			stepped_this_frame = _try_step(requested_motion, curb_top)
		if not stepped_this_frame:
			# Let the full capsule's collision solver remove the into-wall component
			# while retaining tangential movement. A preflight all-or-nothing test
			# caused hard stops on every diagonal facade or porch-post contact.
			velocity.x = forward.x * current_speed
			velocity.z = forward.z * current_speed
	stage_began = _profile_stage("step_preflight", stage_began) if profile_costs else 0
	if jumped or not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if not stepped_this_frame:
		move_and_slide()
	stage_began = _profile_stage("move_and_slide", stage_began) if profile_costs else 0
	# A triangle seam can report the same valid floor contact repeatedly and consume
	# every slide iteration. Project onto the intended direction so diagonal curb
	# sliding cannot be mistaken for forward progress.
	var support_motion := support_velocity * delta if was_grounded and not jumped and not stepped_this_frame else Vector3.ZERO
	var displacement := global_position - before - support_motion
	displacement.y = 0.0
	var horizontal_progress := maxf(0.0, displacement.dot(requested_motion.normalized())) if requested_motion.length() > 0.001 else 0.0
	if not _jump_active and not stepped_this_frame and (was_grounded or is_on_floor()) and requested_motion.length() > 0.001 and horizontal_progress < requested_motion.length() * 0.85:
		var remaining := requested_motion.normalized() * maxf(0.0, requested_motion.length() - horizontal_progress)
		stepped_this_frame = _try_step(remaining)
	stage_began = _profile_stage("step_retry", stage_began) if profile_costs else 0
	displacement = global_position - before - support_motion
	displacement.y = 0.0
	var travelled := displacement.length()
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
	if _jump_active:
		if is_on_floor() and not jumped:
			_jump_active = false
			_landing_pose = 0.13
		else:
			puppet.pose({"walk": 0.0, "armR": [-0.35, 0.23], "armL": [-0.35, 0.23], "lean": 0.045})
			puppet.legs[0].rotation.x = -0.22
			puppet.legs[1].rotation.x = -0.12
	if _landing_pose > 0.0:
		_landing_pose = maxf(0.0, _landing_pose - delta)
		puppet.body.position.y -= sin(PI * _landing_pose / 0.13) * 0.055
	# Follow the body's heading, not a wall slide's displacement: grazing a facade
	# or pole must not swing the view.
	stage_began = _profile_stage("pose", stage_began) if profile_costs else 0
	if combat != null:
		combat.apply_player_pose(delta)
	if is_instance_valid(court_activity):
		court_activity.apply_player_pose(delta)
	_update_camera_follow(delta, move, actual_speed, yaw)
	stage_began = _profile_stage("activities", stage_began) if profile_costs else 0
	update_camera(delta)
	if profile_costs:
		_profile_stage("camera", stage_began)

func _update_camera_follow(delta: float, move: Vector2, actual_speed: float, travel_yaw: float) -> void:
	if not enabled or move.length() < 0.01 or actual_speed < 0.5:
		_camera_moving_time = 0.0
		return
	_camera_moving_time += delta
	if first_person or orbiting or (combat != null and combat.aiming) or _view_returning or not camera_override.is_empty() or _camera_look_grace > 0.0 or _camera_moving_time < 0.75:
		return
	var error := angle_difference(camera_yaw, travel_yaw)
	if absf(error) < deg_to_rad(4.0) or absf(error) > CAMERA_ASSIST_MAX_ERROR:
		return
	# Input inactivity gets a grace period; idle views never recenter. Only the
	# view turns: the offset preserves the held input's world bearing, so the
	# assist converges on the travel direction instead of steering or spiralling.
	var rate := minf(0.85, absf(error) * 1.8)
	var turn := rotate_toward(camera_yaw, travel_yaw, delta * rate) - camera_yaw
	camera_yaw += turn
	_basis_offset = wrapf(_basis_offset - turn, -PI, PI)

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
	var aim_target := 1.0 if combat != null and combat.aiming else 0.0
	_camera_aim_blend = aim_target if delta <= 0.0 else lerpf(_camera_aim_blend, aim_target, 1.0 - exp(-delta * 12.0))
	if absf(_camera_aim_blend - aim_target) < 0.001:
		_camera_aim_blend = aim_target
	camera.fov = clampf(camera_fov - 10.0 * _camera_aim_blend, 45.0, 95.0)
	var jumped := global_position.distance_to(_camera_last_player_position) > CAMERA_CUT_DISTANCE
	if delta <= 0.0 or not _camera_anchor_valid or jumped:
		_camera_anchor_y = global_position.y
		_camera_anchor_valid = true
	else:
		_camera_anchor_y = lerpf(_camera_anchor_y, global_position.y, 1.0 - exp(-delta * 14.0))
	if jumped:
		# Respawns, checkpoints and relocations cut: no glide, no carried boom.
		_camera_glide = Vector3.ZERO
		_camera_boom_carry = false
	elif delta > 0.0:
		_camera_glide *= exp(-delta * CAMERA_GLIDE_RATE)
	_camera_last_player_position = global_position
	if not camera_override.is_empty():
		_camera_glide = Vector3.ZERO
		puppet.g.visible = not first_person and not _seated
		camera.global_position = camera_override.eye
		camera.look_at(camera_override.target, Vector3.UP)
		return
	if _seated and is_instance_valid(seated_vehicle):
		_update_vehicle_camera(delta)
		return
	var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
	var camera_anchor := Vector3(global_position.x, _camera_anchor_y, global_position.z)
	var target := camera_anchor + Vector3.UP * 1.50
	if phone != null and phone.active:
		_camera_glide = Vector3.ZERO
		_camera_last_target = camera_anchor + Vector3.UP * 1.64
		puppet.g.hide()
		camera.fov = phone.photo_fov
		camera.global_position = camera_anchor + Vector3.UP * 1.64
		camera.look_at(camera.global_position + forward * cos(camera_pitch) - Vector3.UP * sin(camera_pitch), Vector3.UP)
		return
	if first_person:
		_camera_glide = Vector3.ZERO
		_camera_last_target = camera_anchor + Vector3.UP * 1.64
		puppet.g.hide()
		camera.global_position = camera_anchor + Vector3.UP * 1.64
		camera.look_at(camera.global_position + forward * cos(camera_pitch) - Vector3.UP * sin(camera_pitch), Vector3.UP)
	else:
		var excluded: Array[RID] = [get_rid()]
		excluded.append_array(camera_ignore)
		target = _glided_target(target, excluded)
		_camera_last_target = target
		var boom_distance := lerpf(5.2, 3.1, _camera_aim_blend)
		# +Z is character forward, so its right hand is on local -X. Put the
		# entire shoulder offset inside the swept boom, never after collision.
		var right := Vector3(-forward.z, 0.0, forward.x)
		var boom := -forward * cos(camera_pitch) * boom_distance + Vector3.UP * (sin(camera_pitch) * boom_distance + lerpf(0.65, 0.45, _camera_aim_blend)) + right * (0.78 * _camera_aim_blend)
		var desired := target + boom.normalized() * _swept_boom(target, boom, excluded, delta, 6.0)
		# A wall or porch can push the chase camera inside the character's head.
		# Hide the local mesh only while compressed; looking away restores it.
		puppet.g.visible = desired.distance_to(target) >= 1.65
		camera.global_position = desired
		camera.look_at(target, Vector3.UP)
	if _camera_aim_blend > 0.0:
		# Smoothly leave the ordinary chase look-at. At full aim the center ray
		# follows view pitch from beside the head, with the equipped hand visible.
		var aim_direction := forward * cos(camera_pitch) - Vector3.UP * sin(camera_pitch)
		var view_direction := (-camera.global_basis.z).slerp(aim_direction, _camera_aim_blend).normalized()
		camera.look_at(camera.global_position + view_direction, Vector3.UP)

## The look-at point, still offset toward the previous subject after a seat
## change. A sphere swept from the true target clamps the offset to clear space.
func _glided_target(target: Vector3, exclude: Array[RID]) -> Vector3:
	if _camera_glide.length_squared() < 0.000004:
		_camera_glide = Vector3.ZERO
		return target
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = _camera_collision_shape
	sweep.transform.origin = target
	sweep.motion = _camera_glide
	sweep.collision_mask = 1 | 2 | 16
	sweep.exclude = exclude
	var fractions := get_world_3d().direct_space_state.cast_motion(sweep)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		_camera_glide *= fractions[0]
	return target + _camera_glide

## Boom length for this frame. A swept volume protects the near plane: contract
## immediately to stay outside walls, then ease back out after an obstruction
## clears. A length carried over from the previous seat eases to the new boom
## either way (never past what the sweep found clear) instead of snapping.
func _swept_boom(target: Vector3, boom: Vector3, exclude: Array[RID], delta: float, rate: float) -> float:
	var reach := maxf(boom.length(), _camera_boom_length) if _camera_boom_carry else boom.length()
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = _camera_collision_shape
	sweep.transform.origin = target
	sweep.motion = boom.normalized() * reach
	sweep.collision_mask = 1 | 2 | 16
	sweep.exclude = exclude
	var fractions := get_world_3d().direct_space_state.cast_motion(sweep)
	var safe_length := reach
	if fractions.size() >= 2 and fractions[0] < 1.0:
		safe_length = maxf(0.05, reach * fractions[0] - 0.04)
	var wanted := minf(boom.length(), safe_length)
	if _camera_boom_carry and _camera_boom_length > 0.0 and safe_length >= _camera_boom_length:
		if delta > 0.0:
			_camera_boom_length = lerpf(_camera_boom_length, wanted, 1.0 - exp(-delta * rate))
		_camera_boom_carry = absf(_camera_boom_length - wanted) > 0.005
	elif delta <= 0.0 or _camera_boom_length <= 0.0 or safe_length < _camera_boom_length:
		_camera_boom_carry = false
		_camera_boom_length = wanted
	else:
		_camera_boom_length = lerpf(_camera_boom_length, safe_length, 1.0 - exp(-delta * rate))
	return _camera_boom_length

## A seat change: glide the look-at point over from where the camera was looking
## and keep the boom length, unless the subject moved further than a cut.
func _begin_seat_transition(from: Vector3, to: Vector3) -> void:
	_camera_glide = Vector3.ZERO
	_camera_boom_carry = _camera_boom_length > 0.0
	if from.is_finite() and from.distance_to(to) <= CAMERA_CUT_DISTANCE:
		_camera_glide = from - to

## Seat the explorer in `car` (driving decides when). The view swings from the
## current walking view to behind the car instead of cutting.
func enter_vehicle(car: Node3D) -> void:
	if car == null or _seated:
		return
	var previous_target := _camera_last_target
	_seated = true
	seated_vehicle = car
	set_orbiting(false)
	_clear_basis_offset()
	reset_jump()
	velocity = Vector3.ZERO
	current_speed = 0.0
	_pose_speed = 0.0
	_seat_layer = collision_layer
	_seat_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	puppet.g.visible = false
	vehicle_orbit_yaw = 0.0
	# Keep the walking view's tilt instead of snapping it. Riding off eases it back
	# to the usual chase pitch (the recentering in _update_vehicle_camera).
	vehicle_orbit_pitch = clampf(camera_pitch, -0.12, 1.0)
	_vehicle_view_yaw = camera_yaw
	_vehicle_look_idle = 0.0
	_vehicle_shake = 0.0
	follow_vehicle()
	_begin_seat_transition(previous_target, car.global_position + Vector3.UP * CHASE_TARGET_HEIGHT)
	update_camera()

## Ride at the car origin; driving calls this after every car step.
func follow_vehicle() -> void:
	if not _seated or not is_instance_valid(seated_vehicle):
		return
	global_position = seated_vehicle.global_position
	velocity = seated_vehicle.velocity
	yaw = float(seated_vehicle.get("yaw"))
	current_speed = 0.0

## Stand at a spot driving verified (door, forced fallback or teleport target).
func leave_vehicle(at: Vector3, heading: float) -> void:
	if not _seated:
		return
	var previous_target := _camera_last_target
	_seated = false
	seated_vehicle = null
	collision_layer = _seat_layer
	collision_mask = _seat_mask
	global_position = at
	velocity = Vector3.ZERO
	current_speed = 0.0
	_pose_speed = 0.0
	reset_jump()
	set_orbiting(false)
	_clear_basis_offset()
	yaw = heading
	camera_yaw = _vehicle_view_yaw
	camera_pitch = clampf(vehicle_orbit_pitch, -0.35, 1.05)
	puppet.g.rotation.y = heading
	puppet.g.visible = not first_person
	_camera_anchor_valid = false
	_vehicle_shake = 0.0
	_begin_seat_transition(previous_target, at + Vector3.UP * 1.50)
	update_camera()

func is_seated() -> bool:
	return _seated

## A restored ride starts with the chase view straight behind `heading` (no
## swing from whatever the view was before the checkpoint loaded).
func reset_vehicle_view(heading: float) -> void:
	if not _seated:
		return
	vehicle_orbit_yaw = 0.0
	vehicle_orbit_pitch = CHASE_PITCH
	_vehicle_view_yaw = heading
	_vehicle_look_idle = 0.0
	camera_yaw = heading
	_camera_glide = Vector3.ZERO
	_camera_boom_carry = false
	_camera_boom_length = 0.0
	update_camera()

func vehicle_look(relative: Vector2) -> void:
	if not _seated:
		return
	vehicle_orbit_yaw = wrapf(vehicle_orbit_yaw - relative.x * mouse_sensitivity, -PI, PI)
	var vertical := relative.y * mouse_sensitivity * (0.0022 / 0.0024)
	vehicle_orbit_pitch = clampf(vehicle_orbit_pitch + vertical * (-1.0 if invert_y else 1.0), -0.12, 1.0)
	if relative.length_squared() > 0.0001:
		_vehicle_look_idle = 0.0

func vehicle_zoom(steps: int) -> void:
	chase_distance = clampf(chase_distance * pow(1.12, -steps), 4.2, 11.0)

func vehicle_shake(amount: float) -> void:
	_vehicle_shake = maxf(_vehicle_shake, clampf(amount, 0.0, 1.0))

func _tick_seated(delta: float) -> void:
	# Driving moves the car and this collider-free body together in the level
	# tick; here only the chase view follows. Paused views (menus, map, shop,
	# dialogue, inspector) redraw without advancing recentering or shake.
	if not is_instance_valid(seated_vehicle):
		leave_vehicle(global_position, yaw) # Car freed under us (teardown).
		return
	_jump_buffer = 0.0
	_coyote_time = 0.0
	stepped_this_frame = false
	update_camera(delta if enabled else 0.0)

func _update_vehicle_camera(delta: float) -> void:
	var car := seated_vehicle
	var heading := float(car.get("yaw"))
	var car_speed := absf(float(car.get("speed")))
	if delta > 0.0:
		_vehicle_look_idle += delta
		# Released orbit drifts back behind a moving car; a stopped car keeps the
		# view the player chose, like idle walking views.
		if _vehicle_look_idle > CHASE_RECENTER_DELAY and car_speed > 2.0:
			vehicle_orbit_yaw = rotate_toward(vehicle_orbit_yaw, 0.0, delta * 1.6)
			vehicle_orbit_pitch = move_toward(vehicle_orbit_pitch, CHASE_PITCH, delta * 0.5)
		_vehicle_view_yaw = lerp_angle(_vehicle_view_yaw, heading + vehicle_orbit_yaw, 1.0 - exp(-delta * 6.0))
		_vehicle_shake = maxf(0.0, _vehicle_shake - delta * 2.5)
		_vehicle_shake_phase += delta
	# Radar heading-up and the walking view after exit follow the chase view.
	camera_yaw = _vehicle_view_yaw
	yaw = heading
	puppet.g.visible = false
	camera.fov = clampf(camera_fov + 7.0 * clampf(car_speed / 24.0, 0.0, 1.0), 45.0, 100.0)
	var forward := Vector3(sin(_vehicle_view_yaw), 0.0, cos(_vehicle_view_yaw))
	var excluded: Array[RID] = [get_rid(), (car as CollisionObject3D).get_rid()]
	excluded.append_array(camera_ignore)
	var target := _glided_target(car.global_position + Vector3.UP * CHASE_TARGET_HEIGHT, excluded)
	_camera_last_target = target
	var boom := -forward * cos(vehicle_orbit_pitch) * chase_distance + Vector3.UP * (sin(vehicle_orbit_pitch) * chase_distance + 0.55)
	var eye := target + boom.normalized() * _swept_boom(target, boom, excluded, delta, 4.0)
	if _vehicle_shake > 0.0:
		var phase := _vehicle_shake_phase
		eye += Vector3(sin(phase * 47.0), sin(phase * 61.0 + 1.3), sin(phase * 53.0 + 2.1)) * 0.06 * _vehicle_shake
	camera.global_position = eye
	# Look over the car along the view, never at a degenerate/vertical target.
	var look_point := target + forward * 2.5
	var direction := look_point - eye
	if direction.length_squared() > 0.0001 and absf(direction.normalized().y) < 0.995:
		camera.look_at(look_point, Vector3.UP)
