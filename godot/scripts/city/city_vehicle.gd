extends CharacterBody3D
## Forward-only sedan. Terrain is sampled on layer 1; the complete body is swept
## against buildings/props, explorer, pedestrians and other cars before any move.

const OBSTACLES := 2 | 4 | 8 | 16
const BODY_SIZE := Vector3(2.12, 2.30, 4.70)
const BODY_CENTER := Vector3(0.0, 1.20, 0.0)
const Models := preload("res://scripts/city/city_car_models.gd")
var traffic: Node3D
var route: Array[Vector3] = []
var route_index := 1
var vehicle_id := ""
var state := "parked"
var blocked_reason := ""
var yaw := 0.0
var speed := 0.0
var cruise_speed := 9.0
var lane_id := -1
var next_lane_id := -1
var route_sequence := 0
var reservation_id := ""
var connector_end_index := -1
var stop_dwell := 0.0
var control_reason := "Waiting at traffic signal"
var leader_distance := INF
var near_physics := true
var is_police := false
var _obstacle_distance := INF
var _obstacle_clock := 0.0
var _presence_blocked := false
var distance_travelled := 0.0
var honks := 0
var recycled := 0
var stopped_time := 0.0
var honk_cooldown := 0.0
var body_shape: BoxShape3D
var model: Node3D
var paint_color := ""
var prototype_kind := ""
var _spinners: Array[Node3D] = []
var _spinner_phase := 0.0
var _wheels: Array[Node3D] = []
var _wheel_bases: Array[Basis] = []
var _wheel_spin := 0.0

func setup(manager: Node3D, path: Array[Vector3], id: String, requested_speed: float, paint_index: int = 0, police: bool = false) -> bool:
	traffic = manager
	route = path
	vehicle_id = id
	cruise_speed = requested_speed
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8 | 16
	if route.size() < 2:
		return false
	body_shape = BoxShape3D.new()
	body_shape.size = BODY_SIZE
	var collision := CollisionShape3D.new()
	collision.shape = body_shape
	collision.position = BODY_CENTER
	add_child(collision)
	var delta := route[1] - route[0]
	yaw = atan2(delta.x, delta.z)
	var pose := _ground_pose(route[0], yaw)
	if pose.is_empty():
		return false
	global_transform = pose.transform
	if not _pose_clear(global_transform):
		return false
	is_police = police
	prototype_kind = "police" if police else str(Models.KINDS[posmod(paint_index, Models.KINDS.size())])
	if police:
		model = Assets.model("cop_car")
		# Original patrol car faces +X; all traffic routes use native +Z.
		model.rotation.y = -PI / 2
	else:
		model = Models.make(prototype_kind, paint_index)
	add_child(model)
	paint_color = Models.paint_color(paint_index).to_html(false)
	for child in model.get_children():
		if str(child.name).begins_with("Spinner_"):
			_spinners.append(child)
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var wheel := Assets.find(model, wheel_name)
		if wheel:
			_wheels.append(wheel)
			_wheel_bases.append(wheel.basis)
	state = "waiting"
	set_meta("traffic_vehicle", true)
	return true

func _animate_spinners(dt: float) -> void:
	if _spinners.is_empty() or not is_instance_valid(traffic.level.player):
		return
	# A free-spinning hub coasts independently even while the wheel is stopped.
	# Only nearby hubs update; distant cars retain their last cheap static pose.
	if global_position.distance_squared_to(traffic.level.player.global_position) > 55.0 * 55.0:
		return
	_spinner_phase = fposmod(_spinner_phase + dt * 2.7, TAU)
	for spinner in _spinners:
		spinner.rotation.x = _spinner_phase

func _query(pose: Transform3D, motion := Vector3.ZERO, margin := 0.06) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape
	query.transform = pose * Transform3D(Basis.IDENTITY, BODY_CENTER)
	query.motion = motion
	query.margin = margin
	query.collision_mask = OBSTACLES
	query.exclude = [get_rid()]
	return query

func _pose_clear(pose: Transform3D) -> bool:
	for x in [-BODY_SIZE.x * 0.5, BODY_SIZE.x * 0.5]:
		for z in [-BODY_SIZE.z * 0.5, BODY_SIZE.z * 0.5]:
			if not traffic.on_road(pose * Vector3(x, 0.0, z)):
				return false
	return get_world_3d().direct_space_state.intersect_shape(_query(pose), 8).is_empty()

func _ground_pose(at: Vector3, heading: float) -> Dictionary:
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var sample_positions: Array[Vector3] = [at, at + forward * 1.35, at - forward * 1.35, at + right * 0.80, at - right * 0.80]
	var heights: Array[float] = []
	for p in sample_positions:
		if not traffic.on_road(p):
			return {}
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p - Vector3.UP * 5.0, 1)
		ray.hit_back_faces = false
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.82:
			return {}
		heights.append(float(hit.position.y))
	forward.y = (heights[1] - heights[2]) / 2.70
	right.y = (heights[3] - heights[4]) / 1.60
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	at.y = (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025
	return {"transform": Transform3D(Basis(right, up, forward), at)}

func _stop(reason: String, dt: float, audible := true) -> void:
	state = "blocked"
	blocked_reason = reason
	speed = 0.0
	velocity = Vector3.ZERO
	stopped_time += dt
	if audible and stopped_time > 1.0 and honk_cooldown <= 0.0:
		var explorer = traffic.level.player
		if is_instance_valid(explorer) and global_position.distance_to(explorer.global_position) < 55.0:
			Audio.sfx("honk")
			honks += 1
			honk_cooldown = 5.0

func set_manual_route(path: Array[Vector3]) -> void:
	traffic.release_reservation(self)
	lane_id = -1
	next_lane_id = -1
	route = path
	route_index = 1
	leader_distance = INF
	_obstacle_distance = INF
	_obstacle_clock = 0

func set_presence(center: Vector3) -> void:
	var distance := global_position.distance_squared_to(center)
	var active := distance < 85.0 * 85.0
	_presence_blocked = false
	# Activation does not teleport or enable a collider inside an approaching
	# player. The next clear tick enables it while keeping the car stationary.
	if active and not near_physics and not _pose_clear(global_transform):
		active = false
		_presence_blocked = true
	near_physics = active
	collision_layer = 16 if active else 0
	if model:
		model.visible = distance < 220.0 * 220.0

func remaining_route_distance() -> float:
	if route_index >= route.size():
		return 0.0
	var length := Vector2(route[route_index].x - global_position.x, route[route_index].z - global_position.z).length()
	for i in range(route_index + 1, route.size()):
		length += Vector2(route[i].x - route[i - 1].x, route[i].z - route[i - 1].z).length()
	return length

func tick(dt: float) -> void:
	_animate_spinners(dt)
	if state == "parked" or dt <= 0.0:
		return
	dt = minf(dt, 0.1)
	if _presence_blocked:
		_stop("Waiting for nearby clearance", dt, false)
		return
	honk_cooldown = maxf(0.0, honk_cooldown - dt)
	var limit: float = traffic.control_distance(self, dt)
	if route_index >= route.size():
		if lane_id < 0:
			state = "parked"
			speed = 0.0
		else:
			_stop(control_reason, dt, false)
		return
	# Consume reached samples in this same update. A harmless curve or waypoint
	# must not force a stop-and-rotate animation.
	while route_index < route.size() - 1 and Vector2(route[route_index].x - global_position.x, route[route_index].z - global_position.z).length() < 0.06:
		route_index += 1
	var target := route[route_index]
	var delta := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var remaining := delta.length()
	if remaining < 0.025:
		if lane_id < 0:
			route_index += 1
		_stop(control_reason, dt, false)
		return
	var direction := delta / remaining
	var wanted := atan2(direction.x, direction.z)
	var bend := absf(angle_difference(yaw, wanted))
	var desired := cruise_speed
	if reservation_id != "":
		desired = minf(desired, 4.2)
	if bend > 0.12:
		desired = minf(desired, 3.5)
	var clearance := minf(limit, leader_distance)
	var audible := false
	var reason := control_reason if limit <= leader_distance else "Following traffic"
	_obstacle_clock -= dt
	if near_physics:
		var space := get_world_3d().direct_space_state
		if not _pose_clear(global_transform):
			_stop("Occupied vehicle clearance", dt)
			return
		if _obstacle_clock <= 0.0:
			var reach := maxf(3.0, speed * speed / 8.0 + 3.0)
			var fractions := space.cast_motion(_query(global_transform, direction * reach))
			_obstacle_distance = maxf(0.0, reach * float(fractions[0]) - 1.5) if fractions.size() >= 2 and fractions[0] < 0.999 else INF
			_obstacle_clock = 0.1
		if _obstacle_distance < clearance:
			clearance = _obstacle_distance
			reason = "Waiting for the lane to clear"
			audible = true
	if clearance <= 0.06:
		_stop(reason, dt, audible)
		return
	if is_finite(clearance):
		desired = minf(desired, sqrt(maxf(0, 8.0 * clearance)))
	speed = move_toward(speed, desired, dt * (4.0 if desired < speed else 2.4))
	var step := minf(minf(remaining, speed * dt), clearance)
	var at := global_position + direction * step
	# Cached lane heights make remote simulation independent of streamed props.
	var previous := route[maxi(0, route_index - 1)]
	var segment := Vector2(target.x - previous.x, target.z - previous.z)
	var progress := clampf(Vector2(at.x - previous.x, at.z - previous.z).dot(segment) / maxf(segment.length_squared(), 0.001), 0, 1)
	at.y = lerpf(previous.y, target.y, progress)
	var next_pose := Transform3D(Basis(Vector3.UP, wanted), at)
	if near_physics:
		var ground := _ground_pose(at, wanted)
		if ground.is_empty():
			_stop("Road support unavailable", dt, false)
			return
		next_pose = ground.transform
		var movement := get_world_3d().direct_space_state.cast_motion(_query(global_transform, next_pose.origin - global_position))
		if movement.size() < 2 or movement[0] < 0.999 or not _pose_clear(next_pose):
			_stop("Obstacle ahead", dt)
			return
		if bend > 0.01:
			# Translation sweeps alone do not enclose the rotating outer corners.
			# Angular/linear spacing stays inside the query's .06m safety margin.
			var samples := maxi(ceili(bend / deg_to_rad(1.0)), ceili(global_position.distance_to(next_pose.origin) / 0.07))
			for sample in range(1, samples):
				var swept_pose := global_transform.interpolate_with(next_pose, float(sample) / samples)
				if not _pose_clear(swept_pose):
					_stop("Turning clearance occupied", dt)
					return
	var motion := next_pose.origin - global_position
	global_transform = next_pose
	yaw = wanted
	velocity = motion / dt
	distance_travelled += step
	_obstacle_distance = maxf(0, _obstacle_distance - step)
	leader_distance = maxf(0, leader_distance - step)
	if model.visible:
		_wheel_spin += step / (0.36 if is_police else Models.wheel_radius(prototype_kind))
		for i in _wheels.size():
			_wheels[i].basis = _wheel_bases[i] * Basis(Vector3.FORWARD if is_police else Vector3.RIGHT, _wheel_spin)
	state = "driving"
	blocked_reason = ""
	stopped_time = 0.0

func get_status() -> Dictionary:
	return {"id": vehicle_id, "state": state, "position": global_position, "yaw": yaw,
		"speed": speed, "distance_travelled": distance_travelled, "route_index": route_index,
		"route_points": route.size(), "blocked_reason": blocked_reason, "stopped_time": stopped_time,
		"honks": honks, "recycled": recycled, "paint_color": paint_color, "prototype": prototype_kind,
		"spinners": _spinners.size(), "spinner_phase": _spinner_phase, "police": is_police,
		"lane_id": lane_id, "near_physics": near_physics, "reservation": reservation_id, "transfers": route_sequence}

func _outside_view(point: Vector3, camera: Camera3D) -> bool:
	# A bounding sphere must lie fully beyond a frustum plane. Determine each
	# plane's inside sign from a known point down the camera's optical axis.
	var depth := (camera.near + minf(camera.far, camera.near + 20.0)) * 0.5
	var inside := camera.global_position - camera.global_basis.z * depth
	var center := point + Vector3.UP * BODY_CENTER.y
	for plane in camera.get_frustum():
		var side := signf(plane.distance_to(inside))
		if side != 0.0 and plane.distance_to(center) * side < -3.3:
			return true
	return false

func try_recycle() -> bool:
	# This is also the test hook: it never bypasses visibility or collision guards.
	if state != "parked" or route.size() < 2:
		return false
	var explorer = traffic.level.player
	if not is_instance_valid(explorer) or not is_instance_valid(explorer.camera):
		return false
	var camera: Camera3D = explorer.camera
	var start := route[0]
	if global_position.distance_to(explorer.global_position) <= 80.0 or start.distance_to(explorer.global_position) <= 80.0:
		return false
	if not _outside_view(global_position, camera) or not _outside_view(start, camera):
		return false
	var direction := route[1] - route[0]
	var initial_yaw := atan2(direction.x, direction.z)
	var ground := _ground_pose(start, initial_yaw)
	if ground.is_empty():
		return false
	var pose: Transform3D = ground.transform
	if not _outside_view(pose.origin, camera) or not _pose_clear(pose):
		return false
	global_transform = pose
	yaw = initial_yaw
	route_index = 1
	speed = 0.0
	velocity = Vector3.ZERO
	stopped_time = 0.0
	blocked_reason = ""
	state = "waiting"
	recycled += 1
	return true
