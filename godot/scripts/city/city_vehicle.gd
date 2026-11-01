extends CharacterBody3D
## Forward-only sedan. Terrain is sampled on layer 1; the complete body is swept
## against buildings/props, explorer, pedestrians and other cars before any move.

const OBSTACLES := 2 | 4 | 8 | 16
# Fleet envelope for road/leader broadphases only. Physical shapes come from
# each prototype's low body and tapered cabin in Collision.
const BODY_SIZE := Vector3(2.12, 2.30, 4.70)
const BODY_CENTER := Vector3(0.0, 1.0, 0.0)
const Collision := preload("res://scripts/city/city_car_collision.gd")
const QUERY_MARGIN := 0.01
const STOP_CLEARANCE := 0.06
const BRAKING := 4.0
const ROAD_CORNERS: Array[Vector3] = [Vector3(-1.06, 0, -2.35), Vector3(-1.06, 0, 2.35),
	Vector3(1.06, 0, -2.35), Vector3(1.06, 0, 2.35)]
# Presence refreshes every .25s; the 10m hysteresis avoids repeatedly enabling
# colliders at the boundary, well outside the player's interaction range.
const PHYSICS_ENTER_DISTANCE := 55.0
const PHYSICS_EXIT_DISTANCE := 65.0
const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const Damage := preload("res://scripts/city/city_vehicle_damage.gd")
const TireHandling := preload("res://scripts/city/city_tire_handling.gd")
const WorldAudio := preload("res://scripts/city/city_world_audio.gd")
const RenderLOD := preload("res://scripts/city/city_vehicle_render_lod.gd")
# Benchmark-only aggregation. Root enables/resets these between sample windows.
# ground/pose/cast costs are disjoint. tick and motion include their child
# timers; control includes remaining_route. Do not sum inclusive totals.
# Counts are wrapper calls, not individual hull casts.
static var use_route_distance_cache := true
static var profile_queries := false
static var profile_totals: Dictionary = {}
var traffic: Node3D
var _render_lod: Node3D
var _render_lod_active := false
var _render_lod_slot := -1
var _render_lod_key := ""
var route: Array[Vector3] = []:
	set(value):
		route = value
		invalidate_route_distance_cache()
var _route_distance_suffix := PackedFloat64Array()
var _route_distance_cache_size := -1
var _route_distance_cache_builds := 0
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
var driver_style := "cautious"
var player_hits := 0
var _impact_cooldown := 0.0
var _obstacle_distance := INF
var _obstacle_clock := 0.0
var _presence_blocked := false
var distance_travelled := 0.0
var honks := 0
var recycled := 0
var stopped_time := 0.0
var honk_cooldown := 0.0
var body_shape: Shape3D
var collision_parts: Array[Dictionary] = []
var _collision_radius := 0.0
var _clearance_shape: BoxShape3D
var _clearance_center := Vector3.ZERO
var _shape_query: PhysicsShapeQueryParameters3D
var _query_rider := RID()
var _in_tick := false
var _rider_checked := false
var _rider_result := false
var _ground_ray: PhysicsRayQueryParameters3D
var model: Node3D
var paint_color := ""
var prototype_kind := ""
var _spinners: Array[Node3D] = []
var _spinner_phase := 0.0
var _wheels: Array[Node3D] = []
var _wheel_bases: Array[Basis] = []
var _wheel_spin := 0.0
var _wheel_positions: Array[Vector3] = []
var flat_tires: Array[int] = []
var panic_time := 0.0
var gunshot_reactions := 0
var tire_handling := TireHandling.new()
var _cached_tire_profile: Dictionary = {}
var _cached_profile_tires: Array[int] = []
var _cached_profile_sides: Array[float] = []
var _wheel_sides: Array[float] = []
var _route_position := Vector3.INF
var _route_heading := 0.0
var damage_clearance_recoveries := 0
var far_damage_elapsed := 0.0
var coarse_damage_motion := false
# Player control (city_driving.gd). An occupied car has no lane/route track,
# reservation, AI tick or recycling, and always renders its exact model.
# Bodies are swept continuously against props/buildings, people and vehicles;
# terrain is followed with support rays and a bounded step, never swept.
const DRIVE_MASK := 2 | 8 | 16
const DRIVE_MAX_SPEED := 24.0
const DRIVE_MAX_REVERSE := 7.0
const DRIVE_ENGINE := 7.0
const DRIVE_REVERSE_ACCEL := 4.0
const DRIVE_BRAKE := 11.0
const DRIVE_HANDBRAKE := 6.5
const DRIVE_COAST := 1.1
const DRIVE_DRAG := 0.0022
const DRIVE_WHEELBASE := 2.7
const DRIVE_PIVOT := 1.30
# Steering lock narrows with speed: a tight turn while parking, a stable lane
# change at speed. Grip then caps the lateral acceleration actually achieved.
const DRIVE_STEER_LOW := 0.62
const DRIVE_STEER_HIGH := 0.15
const DRIVE_STEER_FADE := 22.0
const DRIVE_STEER_RATE := 3.4
const DRIVE_STEER_RETURN := 5.0
const DRIVE_LATERAL_ACCEL := 9.5
const DRIVE_LATERAL_GRIP := 9.0
const DRIVE_HANDBRAKE_GRIP := 0.18
const DRIVE_PULL := 0.30
const DRIVE_STEP_UP := 0.30
# Lifted hull bottom ~0.29m above its ground plane: curbs pass under it.
const DRIVE_TERRAIN_LIFT := 0.18
const DRIVE_MAX_SLOPE := 0.70
const DRIVE_GRAVITY := 22.0
const DRIVE_SKIN := 0.004
const HEALTHY_TIRES := {"count": 0, "grip": 1.0, "braking": 1.0, "pull": 0.0}
var player_controlled := false
# Left parked by the player: an obstacle from any heading until recycled.
var player_released := false
var force_detailed := false
var home_lane := -1
var drive_velocity := Vector3.ZERO
var drive_steer := 0.0
var wheel_steer := 0.0
var drive_vertical_speed := 0.0
var drive_airborne := false
var drive_contacts := 0
var last_drive_contact: Dictionary = {}
var _drive_heights := PackedFloat32Array()
var _drive_exclude: Array[RID] = []
var _drive_params: PhysicsShapeQueryParameters3D
var _drive_ray: PhysicsRayQueryParameters3D
# External authority (police). The same swept drive model without player
# ownership: no AI tick or recycling, exact model, and the on-foot explorer is
# an obstacle. Traffic grants/revokes it (claim/release_external_vehicle).
var external_owner := ""
var external_released := false
# Bounded body damage. Health 0 disables the engine until a fleet car recycles
# or persistence resets it; brakes and steering keep working.
const MAX_HEALTH := 100.0
const SHOT_BODY_DAMAGE := 2.5
const CRASH_DAMAGE_FLOOR := 3.0
const CRASH_DAMAGE_SCALE := 1.0
const CRASH_DAMAGE_CAP := 25.0
var health := MAX_HEALTH
var disabled := false
var last_damage_origin := Vector3.INF
var damage_events := 0
# One event per contact episode per collider: suppressed while touching and
# for CONTACT_SEPARATION after, unless a clearly harder hit follows.
const CONTACT_MIN_SPEED := 1.0
const CONTACT_SEPARATION := 0.6
const CONTACT_REHIT_GAIN := 4.0
const CONTACT_REHIT_DELAY := 0.25
const CONTACT_MAX_EVENTS := 4
const CONTACT_MAX_KEYS := 24
const PERSON_IMPACT_SPEED := 2.0
static var _contact_serial := 0
var contact_events := 0
var _contact_clock := 0.0
var _contact_memory: Dictionary = {}
var _step_events: Array[Dictionary] = []
var _drive_input: Dictionary = {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}
# Remembered-vehicle registry (city_driving.gd); empty for ordinary traffic.
var paint_index := 0
var registry_id := ""
var source_id := ""
var source_key: Dictionary = {}
var last_used := 0

func effective_braking() -> float:
	if flat_tires.is_empty():
		return BRAKING
	return BRAKING * float(_tire_profile().braking)

func _tire_profile() -> Dictionary:
	# Public flat_tires is also mutated directly by fixtures/save restoration.
	# Compare its bounded contents, not only count or receive_gunshot events.
	# Sides normally stay fixed after setup, but preserve direct-edit semantics.
	if _cached_tire_profile.is_empty() or _cached_profile_tires != flat_tires or _cached_profile_sides != _wheel_sides:
		_cached_profile_tires = flat_tires.duplicate()
		_cached_profile_sides = _wheel_sides.duplicate()
		_cached_tire_profile = TireHandling.profile(flat_tires,_wheel_sides)
	return _cached_tire_profile

func route_position() -> Vector3:
	return _route_position if _route_position.is_finite() and not flat_tires.is_empty() else global_position

func react_to_gunfire(_origin: Vector3) -> void:
	panic_time = 12.0
	gunshot_reactions += 1
	# Refresh braking immediately, including for previously reckless drivers.
	_obstacle_clock = 0.0

func raycast_tires(from: Vector3, to: Vector3) -> Dictionary:
	# Include the enclosing body, even while its physics presence is culled.
	# Combat receives a body result (no tire_index) if it occludes the tire.
	var nearest := Damage.ray_hull(from, to, global_transform, collision_parts)
	if not nearest.is_empty():
		nearest["collider"] = self
	for i in _wheels.size():
		# Imported patrol meshes can wrap wheel pivots below another Node3D.
		var wheel_parent := _wheels[i].get_parent() as Node3D
		var center := wheel_parent.global_transform * _wheel_positions[i]
		var pose := Transform3D(global_basis, center)
		var radius := 0.36 if is_police else Models.wheel_radius(prototype_kind)
		if i in flat_tires:
			pose.origin -= global_basis.y * radius * 0.45
			pose.basis = pose.basis.scaled_local(Vector3(1.08, 0.55, 1.10))
		var half_width := 0.14 if is_police else (float(Catalog.config(prototype_kind).tire_half_width) if Catalog.has_kind(prototype_kind) else 0.115)
		var hit := Damage.ray_tire(from, to, pose, radius, half_width)
		if not hit.is_empty() and (nearest.is_empty() or float(hit.distance) < float(nearest.distance)):
			hit["collider"] = self
			hit["tire_index"] = i
			nearest = hit
	return nearest

func receive_gunshot(hit: Dictionary, origin: Vector3) -> Dictionary:
	react_to_gunfire(origin)
	var tire := int(hit.get("tire_index", -1))
	var punctured := tire >= 0 and tire < _wheels.size() and not tire in flat_tires
	if punctured:
		if flat_tires.is_empty():
			_route_position = global_position
			_route_heading = yaw
		flat_tires.append(tire)
		tire_handling.puncture()
		# Shot range exceeds ordinary physics presence. Damaged cars retain
		# collision-aware motion even after the explorer walks away.
		if is_instance_valid(traffic.level.player):
			set_presence(traffic.level.player.global_position)
		_update_wheels()
		if is_instance_valid(_render_lod):
			_render_lod.refresh_vehicle(self)
	# A body round (no tire) dents the car; root may pass its own body_damage.
	var dealt := 0.0
	if tire < 0:
		var before := health
		var amount = hit.get("body_damage", SHOT_BODY_DAMAGE)
		if (amount is float or amount is int) and apply_body_damage(float(amount), origin):
			dealt = before - health
	return {"vehicle_hit": true, "tire_index": tire, "punctured": punctured, "panic": true,
		"body_damage": dealt, "health": health, "disabled": disabled}

func _update_wheels() -> void:
	if not profile_queries:
		_update_wheels_impl()
		return
	var began := Time.get_ticks_usec()
	_update_wheels_impl()
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["wheels_calls"] = int(profile_totals.get("wheels_calls",0))+1
	profile_totals["wheels_usec"] = int(profile_totals.get("wheels_usec",0))+elapsed

func _update_wheels_impl() -> void:
	var radius := 0.36 if is_police else Models.wheel_radius(prototype_kind)
	for i in _wheels.size():
		var flat := i in flat_tires
		var wheel_basis := Damage.flat_basis(_wheel_bases[i], Vector3.FORWARD if is_police else Vector3.RIGHT, _wheel_spin, flat)
		# WheelFL/WheelFR show the driver's steering; traffic keeps them straight.
		if i < 2 and wheel_steer != 0.0:
			wheel_basis = Basis(Vector3.UP, wheel_steer) * wheel_basis
		_wheels[i].basis = wheel_basis
		_wheels[i].position = _wheel_positions[i] - Vector3.UP * (radius * 0.45 if flat else 0.0)
	# Decorative hub meshes must not float over a collapsed tire.
	for spinner in _spinners:
		spinner.visible = true
		for i in flat_tires:
			if spinner.position.distance_to(_wheel_positions[i]) < 0.25:
				spinner.visible = false

static func driver_profile(number: int, police := false) -> Dictionary:
	# Stable across launches, with variety spread through the whole spawn order.
	# Patrols always retain the cautious civilian braking policy.
	var aggressive := not police and posmod(number * 7 + 3, 10) < 2
	return {"style": "aggressive" if aggressive else "cautious",
		"speed": 12.0 + float(posmod(number, 4)) if aggressive else 8.0 + float(posmod(number, 6)) * 0.5}

func _player_near_motion(motion: Vector3) -> bool:
	var explorer = traffic.level.player
	if not is_instance_valid(explorer):
		return false
	# A seated explorer has no collider; their car is swept on the vehicle layer.
	if explorer.get("seated_vehicle") != null:
		return false
	if _player_is_riding():
		return false
	# Broadphase only: the compound swept hull decides contact, including height.
	var reach := motion.length() + BODY_SIZE.z * 0.5 + 1.0
	return global_position.distance_squared_to(explorer.global_position) <= reach * reach

func _player_is_riding() -> bool:
	# A car tick is synchronous: the player's floor solver cannot change its
	# contacts between the compound hull/sweep samples. Outside ticks, recheck.
	if _in_tick and _rider_checked:
		return _rider_result
	var result := false
	if is_instance_valid(traffic) and is_instance_valid(traffic.level.player):
		var explorer = traffic.level.player
		result = explorer.has_method("is_standing_on_vehicle") and explorer.is_standing_on_vehicle(self)
	if _in_tick:
		_rider_checked = true
		_rider_result = result
	return result

func _lookahead_mask() -> int:
	return OBSTACLES & ~4 if driver_style == "aggressive" and not is_police and panic_time <= 0.0 else OBSTACLES

func _lookahead_query(motion: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := _query(global_transform, motion)
	# Reckless planning ignores the player; actual moves always include them.
	query.collision_mask = _lookahead_mask()
	return query

func _player_contact_fraction(motion: Vector3) -> float:
	if not _player_near_motion(motion):
		return INF
	var explorer = traffic.level.player
	var collider = explorer.get("_capsule")
	if not is_instance_valid(collider) or not collider.shape is CapsuleShape3D:
		return INF
	var capsule: CapsuleShape3D = collider.shape
	var capsule_pose: Transform3D = collider.global_transform
	var inverse := global_transform.affine_inverse()
	var capsule_axis := inverse.basis * capsule_pose.basis.y
	var half_segment := maxf(0.0, capsule.height * 0.5 - capsule.radius)
	var radius := capsule.radius * maxf(capsule_pose.basis.x.length(), capsule_pose.basis.z.length())
	var start := inverse * capsule_pose.origin
	var relative_motion := -(inverse.basis * motion)
	var earliest := INF
	for part in collision_parts:
		var first := 0.0
		var last := 1.0
		for plane in part.planes:
			var normal: Vector3 = plane.normal
			var support := radius + QUERY_MARGIN + absf(normal.dot(capsule_axis)) * half_segment
			var distance: float = plane.distance_to(start) - support
			var rate := normal.dot(relative_motion)
			if absf(rate) < 0.000001:
				if distance > 0.0:
					last = -1.0
					break
				continue
			var crossing := -distance / rate
			if rate < 0.0:
				first = maxf(first, crossing)
			else:
				last = minf(last, crossing)
			if first > last:
				break
		if first <= last:
			earliest = minf(earliest, first)
	return _exact_player_contact_fraction(motion, earliest) if is_finite(earliest) else INF

func _exact_player_contact_fraction(motion: Vector3, broad_start: float) -> float:
	# Expanded face planes are only a broadphase: their corners are square,
	# whereas the capsule's contact envelope is rounded. Confirm with the same
	# convex/capsule physics used for actual movement before creating an impact.
	var space := get_world_3d().direct_space_state
	var earliest := INF
	for part_index in collision_parts.size():
		var query := _query(global_transform, Vector3.ZERO, QUERY_MARGIN, part_index)
		query.collision_mask = 4
		if not space.intersect_shape(query, 1).is_empty():
			return 0.0
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions.size() >= 2 and fractions[0] < 1.0:
			earliest = minf(earliest, fractions[0])
			continue
		# Some backends can miss very short casts ending in capsule contact. An
		# exact endpoint overlap, then bisection, retains that safeguard without
		# accepting the broadphase's phantom bumper-corner contacts.
		query.motion = Vector3.ZERO
		query.transform.origin = global_position + motion
		if space.intersect_shape(query, 1).is_empty():
			continue
		var low := broad_start
		var high := 1.0
		for iteration in 14:
			var middle := (low + high) * 0.5
			query.transform.origin = global_position + motion * middle
			if space.intersect_shape(query, 1).is_empty():
				low = middle
			else:
				high = middle
		earliest = minf(earliest, low)
	return earliest

func _hit_player(direction: Vector3) -> void:
	var explorer = traffic.level.player
	if _impact_cooldown > 0.0 or not is_instance_valid(explorer) or not explorer.has_method("receive_vehicle_impact"):
		return
	if explorer.receive_vehicle_impact(direction, speed, vehicle_id):
		player_hits += 1
		_impact_cooldown = 1.25

func setup(manager: Node3D, path: Array[Vector3], id: String, requested_speed: float, paint: int = 0, police: bool = false) -> bool:
	traffic = manager
	route = path
	vehicle_id = id
	cruise_speed = requested_speed
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8 | 16
	if route.size() < 2:
		return false
	is_police = police
	_attach_hull("police" if police else Catalog.traffic_kind(paint))
	var delta := route[1] - route[0]
	yaw = atan2(delta.x, delta.z)
	var pose := _ground_pose(route[0], yaw)
	if pose.is_empty():
		return false
	global_transform = pose.transform
	if not _pose_clear(global_transform):
		return false
	_attach_model(paint)
	state = "waiting"
	set_meta("traffic_vehicle", true)
	_render_lod = RenderLOD.ensure(traffic)
	_render_lod.register_vehicle(self)
	return true

## Driving-owned parked car (the starter car, or a promoted/restored parked
## record of `kind`): the same prototype hull, model, wheels and LOD
## registration as traffic, at a pose the caller validated off any lane. It has
## no route to follow and is never AI-ticked or recycled. require_clear=false
## when the caller already proved the pose with its own (explorer-free) checks.
func setup_parked(manager: Node3D, pose: Transform3D, id: String, paint: int = 0, kind := "", require_clear := true) -> bool:
	traffic = manager
	vehicle_id = id
	cruise_speed = 0.0
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8 | 16
	is_police = false
	_attach_hull(kind if Models.has_kind(kind) else Catalog.traffic_kind(paint))
	global_transform = pose
	yaw = atan2(pose.basis.z.x, pose.basis.z.z)
	if require_clear and not _hull_clear(global_transform):
		return false
	var parked_route: Array[Vector3] = [pose.origin, pose.origin + Vector3(sin(yaw), 0.0, cos(yaw)) * 5.0]
	route = parked_route
	route_index = route.size()
	_route_position = pose.origin
	_route_heading = yaw
	_attach_model(paint)
	state = "parked"
	set_meta("traffic_vehicle", true)
	set_meta("player_vehicle", true)
	_render_lod = RenderLOD.ensure(traffic)
	_render_lod.register_vehicle(self)
	return true

func _attach_hull(kind: String) -> void:
	prototype_kind = kind
	collision_parts = Collision.parts(prototype_kind)
	var envelope := Collision.envelope(prototype_kind)
	_clearance_shape = envelope.shape
	_clearance_center = envelope.center
	for part in collision_parts:
		_collision_radius = maxf(_collision_radius, float(part.radius))
	body_shape = collision_parts[0].shape
	Collision.attach(self, prototype_kind)

func _attach_model(paint: int) -> void:
	paint_index = posmod(paint, Models.PALETTE.size())
	if is_police:
		model = Assets.model("cop_car")
		# Original patrol car faces +X; all traffic routes use native +Z.
		model.rotation.y = -PI / 2
	else:
		model = Models.make(prototype_kind, paint)
	add_child(model)
	paint_color = Models.paint_color(paint).to_html(false)
	for child in model.get_children():
		if str(child.name).begins_with("Spinner_"):
			_spinners.append(child)
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var wheel := Assets.find(model, wheel_name)
		if wheel:
			_wheels.append(wheel)
			_wheel_bases.append(wheel.basis)
			_wheel_positions.append(wheel.position)
			_wheel_sides.append(signf((global_transform.affine_inverse() * wheel.global_position).x))

func _animate_spinners(dt: float) -> void:
	if not profile_queries:
		_animate_spinners_impl(dt)
		return
	var began := Time.get_ticks_usec()
	_animate_spinners_impl(dt)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["spinners_calls"] = int(profile_totals.get("spinners_calls",0))+1
	profile_totals["spinners_usec"] = int(profile_totals.get("spinners_usec",0))+elapsed

func _animate_spinners_impl(dt: float) -> void:
	if _spinners.is_empty() or not is_instance_valid(traffic.level.player):
		return
	# A free-spinning hub coasts independently even while the wheel is stopped.
	# Only nearby hubs update; distant cars retain their last cheap static pose.
	if global_position.distance_squared_to(traffic.level.player.global_position) > 55.0 * 55.0:
		return
	_spinner_phase = fposmod(_spinner_phase + dt * 2.7, TAU)
	for spinner in _spinners:
		spinner.rotation.x = _spinner_phase

func _query(pose: Transform3D, motion := Vector3.ZERO, margin := QUERY_MARGIN, part_index := 0) -> PhysicsShapeQueryParameters3D:
	if _shape_query == null:
		_shape_query = PhysicsShapeQueryParameters3D.new()
		_shape_query.exclude = [get_rid()]
	_shape_query.shape = _clearance_shape if part_index < 0 else (collision_parts[part_index].shape if not collision_parts.is_empty() else body_shape)
	_shape_query.transform = pose * Transform3D(Basis.IDENTITY, _clearance_center) if part_index < 0 else pose
	_shape_query.motion = motion
	_shape_query.margin = margin
	# Callers may temporarily inspect a different layer; reset it every use.
	_shape_query.collision_mask = OBSTACLES
	var rider: RID = traffic.level.player.get_rid() if _player_is_riding() else RID()
	if rider != _query_rider:
		_shape_query.exclude = [get_rid(), rider] if rider.is_valid() else [get_rid()]
		_query_rider = rider
	return _shape_query

func _pose_clear(pose: Transform3D) -> bool:
	if not profile_queries:
		return _pose_clear_impl(pose)
	var began := Time.get_ticks_usec()
	var result: bool = _pose_clear_impl(pose)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["pose_calls"] = int(profile_totals.get("pose_calls",0))+1
	profile_totals["pose_usec"] = int(profile_totals.get("pose_usec",0))+elapsed
	return result

func _pose_clear_impl(pose: Transform3D) -> bool:
	for corner in ROAD_CORNERS:
		if not traffic.on_road(pose * corner):
			return false
	return _hull_clear(pose)

func _hull_clear(pose: Transform3D, margin := QUERY_MARGIN) -> bool:
	var space := get_world_3d().direct_space_state
	# Empty enclosing box proves every convex part clear. Only occupied boxes
	# need the exact compound tests, retaining tight hood/cabin clearance.
	if _clearance_shape != null and space.intersect_shape(_query(pose, Vector3.ZERO, margin, -1), 1).is_empty():
		return true
	for part_index in collision_parts.size():
		if not space.intersect_shape(_query(pose, Vector3.ZERO, margin, part_index), 1).is_empty():
			return false
	return true

func _cast_fraction(pose: Transform3D, motion: Vector3, mask := OBSTACLES, margin := QUERY_MARGIN) -> float:
	if not profile_queries:
		return _cast_fraction_impl(pose, motion, mask, margin)
	var began := Time.get_ticks_usec()
	var result: float = _cast_fraction_impl(pose, motion, mask, margin)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["cast_calls"] = int(profile_totals.get("cast_calls",0))+1
	profile_totals["cast_usec"] = int(profile_totals.get("cast_usec",0))+elapsed
	return result

func _cast_fraction_impl(pose: Transform3D, motion: Vector3, mask := OBSTACLES, margin := QUERY_MARGIN) -> float:
	var safe := 1.0
	var space := get_world_3d().direct_space_state
	for part_index in collision_parts.size():
		var query := _query(pose, motion, margin, part_index)
		query.collision_mask = mask
		var fractions := space.cast_motion(query)
		if fractions.size() < 2:
			return 0.0
		safe = minf(safe, fractions[0])
	return safe

func _ground_pose(at: Vector3, heading: float) -> Dictionary:
	if not profile_queries:
		return _ground_pose_impl(at, heading)
	var began := Time.get_ticks_usec()
	var result: Dictionary = _ground_pose_impl(at, heading)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["ground_calls"] = int(profile_totals.get("ground_calls",0))+1
	profile_totals["ground_usec"] = int(profile_totals.get("ground_usec",0))+elapsed
	return result

func _ground_pose_impl(at: Vector3, heading: float) -> Dictionary:
	if _ground_ray == null:
		_ground_ray = PhysicsRayQueryParameters3D.new()
		_ground_ray.collision_mask = 1
		_ground_ray.hit_back_faces = false
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var sample_positions: Array[Vector3] = [at, at + forward * 1.35, at - forward * 1.35, at + right * 0.80, at - right * 0.80]
	var heights: Array[float] = []
	for p in sample_positions:
		if not traffic.on_road(p):
			return {}
		_ground_ray.from = p + Vector3.UP * 4.0
		_ground_ray.to = p - Vector3.UP * 5.0
		var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
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
			WorldAudio.ensure(traffic.level).honk(global_position + Vector3.UP * .8)
			honks += 1
			honk_cooldown = 5.0

func _damage_path_clear(pose: Transform3D) -> bool:
	if not _pose_clear(pose):
		return false
	var angle := global_basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())
	if coarse_damage_motion:
		# A sphere expansion by the maximum rotating-corner travel encloses
		# every intermediate orientation. This conservative sweep replaces the
		# expensive series of exact rotating-pose overlaps for offscreen steps.
		var margin := QUERY_MARGIN + angle * _collision_radius
		for index in collision_parts.size():
			if not get_world_3d().direct_space_state.intersect_shape(_query(global_transform,Vector3.ZERO,margin,index),1).is_empty():
				return false
		if _cast_fraction(global_transform,pose.origin-global_position,OBSTACLES,margin)<.999:
			return false
		for fraction in [.25,.5,.75]:
			if profile_queries:
				profile_totals["rotation_samples"] = int(profile_totals.get("rotation_samples",0))+1
				profile_totals["coarse_rotation_samples"] = int(profile_totals.get("coarse_rotation_samples",0))+1
			var middle := global_transform.interpolate_with(pose,float(fraction))
			for corner in ROAD_CORNERS:
				if not traffic.on_road(middle*corner,.12+angle*_collision_radius):
					return false
		return true
	if _cast_fraction(global_transform,pose.origin-global_position)<.999:
		return false
	var travel := global_position.distance_to(pose.origin) + angle * _collision_radius
	if angle * _collision_radius > QUERY_MARGIN:
		var samples := maxi(2, ceili(travel / (QUERY_MARGIN * 2.0)))
		for sample in range(1, samples):
			if profile_queries:
				profile_totals["rotation_samples"] = int(profile_totals.get("rotation_samples",0))+1
				profile_totals["damage_rotation_samples"] = int(profile_totals.get("damage_rotation_samples",0))+1
			if not _pose_clear(global_transform.interpolate_with(pose, float(sample) / samples)):
				return false
	return true

func _safe_damage_pose(proposal: Dictionary, anchor: Vector3, heading: float, previous_offset: float, dt: float) -> Dictionary:
	if not proposal.is_empty() and _damage_path_clear(proposal.transform):
		proposal["heading"] = heading + tire_handling.yaw_error
		return proposal
	# A rejected swerve is not committed. Countersteer toward the route from the
	# actual displaced pose, using the same swept compound hull and road checks.
	# Retrying forward recovery avoids cars becoming permanently stuck at a curb.
	tire_handling.request_recovery()
	var recovered := move_toward(previous_offset, 0.0, maxf(.002, speed * dt * .35))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	# An expanded rotating hull can overlap a nearby wall even when both real
	# poses are clear. First countersteer normally; retaining the current yaw
	# gives a bounded translation-only escape toward the lane before turning.
	for recovery_heading in [rotate_toward(yaw, heading, dt * .65), yaw]:
		for candidate_offset in [recovered, previous_offset]:
			var ground := _ground_pose(anchor + right * float(candidate_offset), float(recovery_heading))
			if ground.is_empty() or not _damage_path_clear(ground.transform):
				continue
			damage_clearance_recoveries += 1
			tire_handling.offset = float(candidate_offset)
			tire_handling.lateral_speed = (float(candidate_offset) - previous_offset) / maxf(dt, .001)
			tire_handling.yaw_error = angle_difference(heading, float(recovery_heading))
			ground["heading"] = float(recovery_heading)
			return ground
	return {}

func set_manual_route(path: Array[Vector3]) -> void:
	traffic.release_reservation(self)
	lane_id = -1
	next_lane_id = -1
	route = path
	route_index = 1
	leader_distance = INF
	_obstacle_distance = INF
	_obstacle_clock = 0
	_route_position = global_position
	_route_heading = yaw
	tire_handling.reset_motion()

func set_presence(center: Vector3) -> void:
	var distance := global_position.distance_squared_to(center)
	var radius := PHYSICS_EXIT_DISTANCE if near_physics else PHYSICS_ENTER_DISTANCE
	var driven := player_controlled or not external_owner.is_empty()
	var active := distance < radius * radius or not flat_tires.is_empty() or driven
	_presence_blocked = false
	# Activation does not teleport or enable a collider inside an approaching
	# player. The next clear tick enables it while keeping the car stationary.
	if active and not near_physics and not driven and not _activation_clear():
		active = false
		_presence_blocked = true
	near_physics = active
	collision_layer = 16 if active else 0
	if model and not is_instance_valid(_render_lod):
		model.visible = distance < 220.0 * 220.0 or force_detailed

func _activation_clear() -> bool:
	# Player-placed cars (the starter, or one left at a curb, lot or sidewalk)
	# need only body clearance; traffic's lane-corner test would keep them
	# collider-less forever once the explorer had walked away and returned.
	# Zero margin: a car left flush against another (sweeps stop 4mm short)
	# must still regain its collider; any real overlap keeps it off.
	if player_released or external_released or has_meta("player_vehicle"):
		return _hull_clear(global_transform, 0.0)
	return _pose_clear(global_transform)

func remaining_route_distance() -> float:
	if not profile_queries:
		return remaining_route_distance_impl()
	var began := Time.get_ticks_usec()
	var result: float = remaining_route_distance_impl()
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["remaining_route_calls"] = int(profile_totals.get("remaining_route_calls",0))+1
	profile_totals["remaining_route_usec"] = int(profile_totals.get("remaining_route_usec",0))+elapsed
	return result

func invalidate_route_distance_cache() -> void:
	# Assignment uses the setter; append/remove through a shared Array alias is
	# detected by size. Call this after in-place edits that preserve Array size.
	_route_distance_cache_size = -1

func _rebuild_route_distance_cache() -> void:
	var count := route.size()
	_route_distance_suffix.resize(count)
	if count > 0:
		_route_distance_suffix[count-1] = 0.0
		for i in range(count-2,-1,-1):
			var segment := Vector2(route[i+1].x-route[i].x,route[i+1].z-route[i].z).length()
			_route_distance_suffix[i] = segment+_route_distance_suffix[i+1]
	_route_distance_cache_size = count
	_route_distance_cache_builds += 1

func remaining_route_distance_impl() -> float:
	if route_index >= route.size():
		return 0.0
	var reference := route_position()
	var length := Vector2(route[route_index].x - reference.x, route[route_index].z - reference.z).length()
	if use_route_distance_cache and route_index >= 0:
		if _route_distance_cache_size != route.size():
			_rebuild_route_distance_cache()
		return length+_route_distance_suffix[route_index]
	# Benchmark counterfactual and legacy negative-index semantics. The normal
	# hot path above only computes the current partial segment and one lookup.
	for i in range(route_index + 1, route.size()):
		length += Vector2(route[i].x - route[i - 1].x, route[i].z - route[i - 1].z).length()
	return length

func _advance_route(distance: float) -> Dictionary:
	if not profile_queries:
		return _advance_route_impl(distance)
	var began := Time.get_ticks_usec()
	var result: Dictionary = _advance_route_impl(distance)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["advance_route_calls"] = int(profile_totals.get("advance_route_calls",0))+1
	profile_totals["advance_route_usec"] = int(profile_totals.get("advance_route_usec",0))+elapsed
	return result

func _advance_route_impl(distance: float) -> Dictionary:
	# Consume the whole travel budget, even across several curve samples. Only
	# commit the returned index after all collision/ground checks have passed.
	var at := route_position()
	var index := route_index
	var travelled := 0.0
	var travel_vector := Vector3.ZERO
	while index < route.size() and distance > 0.000001:
		var target := route[index]
		var delta := Vector3(target.x - at.x, 0, target.z - at.z)
		var length := delta.length()
		if length < 0.000001:
			index += 1
			continue
		var step := minf(length, distance)
		var previous := route[maxi(0, index - 1)]
		var local_step := delta * (step / length)
		travel_vector += local_step
		at += local_step
		var segment := Vector2(target.x - previous.x, target.z - previous.z)
		var fraction := clampf(Vector2(at.x - previous.x, at.z - previous.z).dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
		at.y = lerpf(previous.y, target.y, fraction)
		distance -= step
		travelled += step
		if step >= length - 0.000001:
			index += 1
	return {"position": at, "index": index, "distance": travelled, "direction": travel_vector.normalized()}

func can_tick_damage_coarsely() -> bool:
	if player_controlled or not external_owner.is_empty() or disabled or flat_tires.is_empty() or reservation_id != "" or remaining_route_distance() < 10.0:
		return false
	var explorer: Node3D = traffic.level.player
	if not is_instance_valid(explorer) or global_position.distance_squared_to(explorer.global_position)<=80.0*80.0:
		return false
	var view := explorer.get("camera") as Camera3D
	return view != null and _outside_view(global_position,view)

func tick(dt: float, coarse := false) -> void:
	if not profile_queries:
		tick_impl(dt, coarse)
		return
	var began := Time.get_ticks_usec()
	tick_impl(dt, coarse)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["tick_calls"] = int(profile_totals.get("tick_calls",0))+1
	profile_totals["tick_usec"] = int(profile_totals.get("tick_usec",0))+elapsed

func tick_impl(dt: float, coarse := false) -> void:
	if player_controlled or not external_owner.is_empty():
		return # Driving/police own this body: no route, lane or reservation motion.
	_in_tick = true
	_rider_checked = false
	coarse_damage_motion = coarse
	_tick_motion(dt)
	coarse_damage_motion = false
	_in_tick = false
	if _render_lod_active and is_instance_valid(_render_lod):
		_render_lod.update_vehicle(self)

func _tick_motion(dt: float) -> void:
	if not profile_queries:
		_tick_motion_impl(dt)
		return
	var began := Time.get_ticks_usec()
	_tick_motion_impl(dt)
	var elapsed := Time.get_ticks_usec()-began
	profile_totals["motion_calls"] = int(profile_totals.get("motion_calls",0))+1
	profile_totals["motion_usec"] = int(profile_totals.get("motion_usec",0))+elapsed

func _tick_motion_impl(dt: float) -> void:
	if state == "parked" or dt <= 0.0:
		return
	if disabled:
		# A dead engine: no creeping, honking or lane progress until recycled.
		state = "disabled"
		blocked_reason = "Vehicle disabled"
		speed = 0.0
		velocity = Vector3.ZERO
		stopped_time += dt
		return
	if not flat_tires.is_empty() and not _route_position.is_finite():
		_route_position = global_position
		_route_heading = yaw
	dt = minf(dt, 0.25 if coarse_damage_motion else 0.1)
	panic_time = maxf(0.0, panic_time - dt)
	_impact_cooldown = maxf(0.0, _impact_cooldown - dt)
	_animate_spinners(dt)
	if _presence_blocked:
		_stop("Waiting for nearby clearance", dt, false)
		return
	honk_cooldown = maxf(0.0, honk_cooldown - dt)
	var limit: float = traffic.control_distance(self, dt)
	if route_index >= route.size():
		if lane_id < 0:
			state = "parked"
			speed = 0.0
			velocity = Vector3.ZERO
		else:
			_stop(control_reason, dt, false)
		return
	# Consume reached samples in this same update. A harmless curve or waypoint
	# must not force a stop-and-rotate animation.
	var reference := route_position()
	while route_index < route.size() - 1 and Vector2(route[route_index].x - reference.x, route[route_index].z - reference.z).length() < 0.000001:
		route_index += 1
	var target := route[route_index]
	var delta := Vector3(target.x - reference.x, 0.0, target.z - reference.z)
	var remaining := delta.length()
	if remaining < 0.000001:
		if lane_id < 0:
			route_index += 1
		_stop(control_reason, dt, false)
		return
	var direction := delta / remaining
	var wanted := atan2(direction.x, direction.z)
	var desired := cruise_speed * (1.40 if panic_time > 0.0 else 1.0) * Damage.speed_factor(flat_tires.size())
	if not flat_tires.is_empty():
		var bend := clampf(absf(angle_difference(_route_heading, wanted)) / 0.25, 0.0, 1.0)
		desired *= lerpf(1.0, 0.50, bend)
		if tire_handling.recovery > 0.0:
			desired = minf(desired, 6.5 if flat_tires.size() == 1 else 4.0)
	if reservation_id != "":
		desired = minf(desired, 4.2)
	var clearance := minf(limit, leader_distance)
	var audible := false
	var reason := control_reason if limit <= leader_distance else "Following traffic"
	var braking := effective_braking()
	_obstacle_clock -= dt
	if near_physics:
		if not _pose_clear(global_transform):
			_stop("Occupied vehicle clearance", dt)
			return
		if _obstacle_clock <= 0.0:
			var reach := maxf(3.0, speed * speed / (2.0 * braking) + 3.0)
			var fraction := _cast_fraction(global_transform, direction * reach, _lookahead_mask())
			var obstacle_fraction := fraction if fraction < 0.999 else INF
			if driver_style != "aggressive" or is_police or panic_time > 0.0:
				obstacle_fraction = minf(obstacle_fraction, _player_contact_fraction(direction * reach))
			_obstacle_distance = maxf(0.0, reach * obstacle_fraction - 1.5) if is_finite(obstacle_fraction) else INF
			_obstacle_clock = 0.1
		if _obstacle_distance < clearance:
			clearance = _obstacle_distance
			reason = "Waiting for the lane to clear"
			audible = true
	if clearance <= STOP_CLEARANCE:
		_stop(reason, dt, audible)
		return
	if is_finite(clearance):
		# The next step must leave its own braking distance before the stop
		# buffer. Solving v*dt + v²/(2a) <= distance avoids a final speed snap.
		var brake_step := braking * dt
		desired = minf(desired, sqrt(brake_step * brake_step + 2.0 * braking * maxf(0.0, clearance - STOP_CLEARANCE)) - brake_step)
	speed = move_toward(speed, desired, dt * (braking if desired < speed else ((4.5 if panic_time > 0.0 else 2.4) * Damage.speed_factor(flat_tires.size()))))
	var advance := _advance_route(minf(speed * dt, clearance))
	var step: float = advance.distance
	var at: Vector3 = advance.position
	# The body faces the actual travel chord; smoothing orientation separately
	# would introduce sideways sliding. Fine curve samples keep heading continuous.
	# Do not subtract two float32 world positions for heading: at a slow crawl
	# hundreds of metres from the origin this quantizes a diagonal into an axis,
	# rotating a stopped car across its lane. Accumulate the local travel chord
	# before adding it to world coordinates, including crossed curve samples.
	direction = advance.direction
	if direction.length_squared() < 0.5:
		return
	wanted = atan2(direction.x, direction.z)
	var route_heading := wanted
	var previous_offset: float = tire_handling.offset
	if not flat_tires.is_empty():
		var info := _tire_profile()
		# Junctions tighten lateral wandering; stop-line progress still follows
		# the logical lane anchor rather than the displaced physical center.
		var lateral_limit := .28 if reservation_id != "" or clearance < 6.0 else TireHandling.MAX_OFFSET
		tire_handling.step(info, speed, angle_difference(_route_heading, route_heading), dt, maxf(lateral_limit, absf(previous_offset)))
		var right := Vector3(cos(route_heading), 0, -sin(route_heading))
		at += right * tire_handling.offset
		wanted += tire_handling.yaw_error
	var next_pose := Transform3D(Basis(Vector3.UP, wanted), at)
	if near_physics:
		var ground := _ground_pose(at, wanted)
		if not flat_tires.is_empty():
			ground = _safe_damage_pose(ground, advance.position, route_heading, previous_offset, dt)
			if not ground.is_empty():
				wanted = float(ground.heading)
		if ground.is_empty():
			if not flat_tires.is_empty():
				tire_handling.offset = previous_offset
				tire_handling.lateral_speed = 0.0
				tire_handling.request_recovery()
			_stop("Road support unavailable", dt, false)
			return
		next_pose = ground.transform
		var intended_motion := next_pose.origin - global_position
		var movement := _cast_fraction(global_transform, intended_motion)
		var player_fraction := _player_contact_fraction(intended_motion)
		var player_first := false
		if player_fraction <= 1.0:
			var solids := _cast_fraction(global_transform, intended_motion, OBSTACLES & ~4)
			# A wall/NPC/car reached first shields a player behind it. All normal
			# movement and turning checks retain their complete collision masks.
			player_first = player_fraction <= solids
		if player_first:
			# Move only to the last safe pose, never into/through the capsule. The
			# player's own collision solver handles the following stumble/glide.
			var safe_fraction := maxf(0.0, player_fraction - 0.001)
			var contact_pose := global_transform
			contact_pose.origin += intended_motion * safe_fraction
			if _pose_clear(contact_pose):
				global_transform = contact_pose
				distance_travelled += step * safe_fraction
			_hit_player(direction)
			_stop("Player impact", dt, false)
			return
		if movement < 0.999 or not _pose_clear(next_pose):
			_stop("Obstacle ahead", dt)
			return
		var angular_travel := global_basis.get_rotation_quaternion().angle_to(next_pose.basis.get_rotation_quaternion()) * _collision_radius
		if angular_travel > QUERY_MARGIN and flat_tires.is_empty():
			# Translation sweeps alone do not enclose the rotating outer corners.
			# Bound their combined travel (including road pitch/roll), so every
			# intermediate pose is within one query margin of a checked sample.
			var corner_travel := global_position.distance_to(next_pose.origin) + angular_travel
			var samples := maxi(2, ceili(corner_travel / (QUERY_MARGIN * 2.0)))
			for sample in range(1, samples):
				if profile_queries:
					profile_totals["rotation_samples"] = int(profile_totals.get("rotation_samples",0))+1
					profile_totals["healthy_rotation_samples"] = int(profile_totals.get("healthy_rotation_samples",0))+1
				var swept_pose := global_transform.interpolate_with(next_pose, float(sample) / samples)
				if not _pose_clear(swept_pose):
					_stop("Turning clearance occupied", dt)
					return
	var motion := next_pose.origin - global_position
	global_transform = next_pose
	if not flat_tires.is_empty():
		_route_position = advance.position
		_route_heading = route_heading
	route_index = int(advance.index)
	yaw = wanted
	velocity = motion / dt
	distance_travelled += step
	_obstacle_distance = maxf(0, _obstacle_distance - step)
	leader_distance = maxf(0, leader_distance - step)
	if model.visible:
		_wheel_spin += step / (0.36 if is_police else Models.wheel_radius(prototype_kind))
		_update_wheels()
	state = "driving"
	blocked_reason = ""
	stopped_time = 0.0

func get_status() -> Dictionary:
	return {"id": vehicle_id, "state": state, "position": global_position, "yaw": yaw,
		"speed": speed, "distance_travelled": distance_travelled, "route_index": route_index,
		"route_points": route.size(), "blocked_reason": blocked_reason, "stopped_time": stopped_time,
		"honks": honks, "recycled": recycled, "paint_color": paint_color, "prototype": prototype_kind,
		"spinners": _spinners.size(), "spinner_phase": _spinner_phase, "police": is_police,
		"render_lod": "batched_far" if _render_lod_active else ("full" if model.visible else "hidden"),
		"driver_style": driver_style, "cruise_speed": cruise_speed, "player_hits": player_hits,
		"flat_tires": flat_tires.duplicate(), "tire_speed_factor": Damage.speed_factor(flat_tires.size()),
		"tire_handling": tire_handling.snapshot(), "effective_braking": effective_braking(),
		"damage_clearance_recoveries": damage_clearance_recoveries,
		"panicking": panic_time > 0.0, "panic_time": panic_time, "gunshot_reactions": gunshot_reactions,
		"lane_id": lane_id, "near_physics": near_physics, "reservation": reservation_id, "transfers": route_sequence,
		"player_controlled": player_controlled, "player_released": player_released, "force_detailed": force_detailed,
		"drive_contacts": drive_contacts, "health": health, "disabled": disabled, "damage_stage": damage_stage(),
		"external_owner": external_owner, "external_released": external_released,
		"registry_id": registry_id, "source_id": source_id, "contact_events": contact_events}

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
	# An occupied car is never recycled; a released one only once it is away
	# from the player and out of view, like any other parked arrival. Driving's
	# own bodies (starter, remembered parked cars) are never recycled.
	if player_controlled or not external_owner.is_empty() or has_meta("player_vehicle"):
		return false
	var abandoned_jam := state == "blocked" and stopped_time >= 20.0 and reservation_id.is_empty()
	if (state != "parked" and state != "disabled" and not abandoned_jam) or route.size() < 2:
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
	_route_position = pose.origin
	_route_heading = initial_yaw
	tire_handling.reset_motion()
	yaw = initial_yaw
	route_index = 1
	speed = 0.0
	velocity = Vector3.ZERO
	stopped_time = 0.0
	blocked_reason = ""
	_obstacle_distance = INF
	_obstacle_clock = 0.0
	leader_distance = INF
	far_damage_elapsed = 0.0
	# Recycling represents a fresh offscreen arrival, not a permanent damaged
	# body accumulating outside the presence radius.
	flat_tires.clear()
	_cached_tire_profile.clear()
	_cached_profile_tires.clear()
	_cached_profile_sides.clear()
	tire_handling.shock = 0.0
	panic_time = 0.0
	_wheel_spin = 0.0
	_update_wheels()
	# Body damage resets with the tires: a fresh arrival, not the old wreck.
	health = MAX_HEALTH
	disabled = false
	_contact_memory.clear()
	set_presence(explorer.global_position)
	if is_instance_valid(_render_lod):
		_render_lod.refresh_vehicle(self)
	state = "waiting"
	player_released = false
	external_released = false
	recycled += 1
	return true

# --- Player control --------------------------------------------------------

## Driving takes this body over (traffic.claim_vehicle releases its junction
## reservation first). The current speed carries over; the route is not used.
func begin_player_control() -> void:
	player_controlled = true
	player_released = false
	_begin_drive_control("player")

## Police (or another external owner) drives this fleet body through
## external_step(); traffic.claim_external_vehicle releases its reservation.
func begin_external_control(owner_id: String) -> void:
	external_owner = owner_id
	external_released = false
	_begin_drive_control("external")

func _begin_drive_control(mode: String) -> void:
	force_detailed = true
	state = mode
	blocked_reason = ""
	stopped_time = 0.0
	reservation_id = ""
	connector_end_index = -1
	next_lane_id = -1
	stop_dwell = 0.0
	panic_time = 0.0
	tire_handling.reset_motion()
	_route_position = global_position
	_route_heading = yaw
	drive_velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * speed
	drive_steer = 0.0
	wheel_steer = 0.0
	drive_vertical_speed = 0.0
	drive_airborne = false
	_drive_heights = PackedFloat32Array()
	var ground := _drive_ground(global_position, yaw)
	if ground.has("heights"):
		_drive_heights = ground.heights
	_presence_blocked = false
	near_physics = true
	collision_layer = 16
	if is_instance_valid(_render_lod):
		_render_lod.refresh_vehicle(self)
	elif model != null:
		model.visible = true

## The driver got out: the car settles where it stopped and is parked. Traffic
## restores a home lane for released fleet cars so recycling can reuse them.
func end_player_control() -> void:
	_settle_drive()
	player_controlled = false
	player_released = true
	_end_drive_control()

## The external owner let go: parked exactly where it stopped, never moved.
## Like a player-released car it blocks lanes until recycled out of view.
func end_external_control() -> void:
	_settle_drive()
	external_owner = ""
	external_released = true
	_end_drive_control()

func _settle_drive() -> void:
	_drive_exclude = [get_rid()]
	if drive_airborne:
		var ground := _drive_ground(global_position, yaw)
		if ground.has("transform") and _drive_pose_clear(ground.transform):
			global_transform = ground.transform

func _end_drive_control() -> void:
	force_detailed = false
	state = "parked"
	speed = 0.0
	velocity = Vector3.ZERO
	drive_velocity = Vector3.ZERO
	drive_steer = 0.0
	wheel_steer = 0.0
	drive_vertical_speed = 0.0
	drive_airborne = false
	stopped_time = 0.0
	blocked_reason = ""
	leader_distance = INF
	_obstacle_distance = INF
	_obstacle_clock = 0.0
	_route_position = global_position
	_route_heading = yaw
	tire_handling.reset_motion()
	if model != null and model.visible:
		_update_wheels()
	if is_instance_valid(_render_lod):
		_render_lod.refresh_vehicle(self)

## One player-driven update of at most 0.1s, split into <=1/60s substeps.
## throttle/brake are 0..1, steer -1 (left) .. 1 (right). Returns the travelled
## distance, the strongest contact {kind, speed, position, normal, collider},
## the last blocking reason ("turn", "terrain", "clearance" or "") and the
## deduplicated contact events of this update (see _note_contact).
func player_step(dt: float, throttle: float, brake: float, steer: float, handbrake: bool) -> Dictionary:
	if not player_controlled or dt <= 0.0 or not is_finite(dt) or not is_inside_tree():
		return {"moved": 0.0, "contact": {}, "blocked": "", "events": []}
	return _drive_step(dt, throttle, brake, steer, handbrake)

## External (police) update: identical swept physics to player_step, with the
## on-foot explorer as an obstacle. Never claims player_controlled; refused
## (ok=false, no motion) unless traffic granted this body to an owner.
func external_step(dt: float, throttle: float, brake: float, steer: float, handbrake: bool) -> Dictionary:
	var report := {"ok": false, "moved": 0.0, "contact": {}, "blocked": "", "events": []}
	if not external_owner.is_empty() and not player_controlled and dt > 0.0 and is_finite(dt) and is_inside_tree():
		report = _drive_step(dt, throttle, brake, steer, handbrake)
		report["ok"] = true
		if is_instance_valid(traffic) and traffic.has_signal("external_collision"):
			for event in report.events:
				traffic.emit_signal("external_collision", event)
	report["speed"] = speed
	report["yaw"] = yaw
	report["position"] = global_position
	report["health"] = health
	report["disabled"] = disabled
	return report

func _drive_step(dt: float, throttle: float, brake: float, steer: float, handbrake: bool) -> Dictionary:
	var report := {"moved": 0.0, "contact": {}, "blocked": "", "events": []}
	dt = minf(dt, 0.1)
	throttle = clampf(throttle, 0.0, 1.0) if is_finite(throttle) else 0.0
	brake = clampf(brake, 0.0, 1.0) if is_finite(brake) else 0.0
	steer = clampf(steer, -1.0, 1.0) if is_finite(steer) else 0.0
	_drive_input = {"throttle": throttle, "brake": brake, "steer": steer, "handbrake": handbrake}
	_step_events.clear()
	var steps := maxi(1, ceili(dt * 60.0 - 0.001))
	var h := dt / steps
	var before := global_position
	var rolled := 0.0
	for step in steps:
		_contact_clock += h
		var result := _player_substep(h, throttle, brake, steer, handbrake)
		report.moved = float(report.moved) + float(result.moved)
		rolled += float(result.moved) * signf(speed)
		var contact: Dictionary = result.contact
		if not contact.is_empty() and (report.contact.is_empty() or float(contact.speed) > float(report.contact.speed)):
			report.contact = contact
		if not str(result.blocked).is_empty():
			report.blocked = result.blocked
	velocity = (global_position - before) / dt
	distance_travelled += float(report.moved)
	_route_position = global_position
	_route_heading = yaw
	stopped_time = stopped_time + dt if absf(speed) < 0.1 else 0.0
	panic_time = maxf(0.0, panic_time - dt)
	_impact_cooldown = maxf(0.0, _impact_cooldown - dt)
	_animate_spinners(dt)
	if model != null and model.visible:
		_wheel_spin += rolled / (0.36 if is_police else Models.wheel_radius(prototype_kind))
		_update_wheels()
	report.events = _step_events.duplicate()
	return report

func _player_substep(h: float, throttle: float, brake: float, steer: float, handbrake: bool) -> Dictionary:
	var result := {"moved": 0.0, "contact": {}, "blocked": ""}
	var tires: Dictionary = HEALTHY_TIRES if flat_tires.is_empty() else _tire_profile()
	var grip := float(tires.grip)
	var factor := Damage.speed_factor(flat_tires.size())
	var top := DRIVE_MAX_SPEED * factor
	if disabled:
		throttle = 0.0 # A dead engine neither accelerates nor reverses.
	# Bodies already overlapping (a collider re-enabled around a parked car) may
	# be driven out of, never further into; nothing new is ever entered. An
	# explorer riding an externally driven roof is carried, not swept against.
	_drive_exclude = [get_rid()]
	if not external_owner.is_empty() and _player_is_riding():
		_drive_exclude.append(traffic.level.player.get_rid())
	_drive_exclude.append_array(_drive_overlaps(global_transform))
	var centring := absf(steer) < absf(drive_steer) or signf(steer) != signf(drive_steer)
	drive_steer = move_toward(drive_steer, steer, (DRIVE_STEER_RETURN if centring else DRIVE_STEER_RATE) * h)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var v_f := drive_velocity.dot(forward)
	# Positive steer is right (-X when facing +Z), i.e. decreasing yaw.
	wheel_steer = -drive_steer * lerpf(DRIVE_STEER_LOW, DRIVE_STEER_HIGH, clampf(absf(v_f) / DRIVE_STEER_FADE, 0.0, 1.0))
	if not drive_airborne:
		var yaw_rate := v_f * tan(wheel_steer) / DRIVE_WHEELBASE
		var limit := DRIVE_LATERAL_ACCEL * grip / maxf(absf(v_f), 1.0)
		if handbrake and absf(v_f) > 3.0:
			# Locked rear wheels let the tail step out.
			yaw_rate *= 1.35
			limit *= 1.7
		yaw_rate = clampf(yaw_rate, -limit, limit)
		# A flat tire drags its side: the existing profile's pull, toward that side.
		yaw_rate += float(tires.pull) * DRIVE_PULL * clampf(absf(v_f) / 8.0, 0.0, 1.0) * signf(v_f)
		var turn := yaw_rate * h
		if absf(turn) > 0.000001:
			var turned := _turned_pose(turn) if _drive_rotation_clear(turn) else _drive_rotation_nudge(turn)
			if turned.is_finite():
				global_transform = turned
				yaw = wrapf(yaw + turn, -PI, PI)
			else:
				result.blocked = "turn"
	forward = Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(forward.z, 0.0, -forward.x)
	v_f = drive_velocity.dot(forward)
	var v_s := drive_velocity.dot(side)
	if not drive_airborne:
		var braking := DRIVE_BRAKE * float(tires.braking)
		if handbrake:
			v_f = move_toward(v_f, 0.0, DRIVE_HANDBRAKE * h)
		elif throttle > 0.01 and v_f > -0.3:
			v_f += DRIVE_ENGINE * throttle * (1.0 - pow(clampf(v_f / top, 0.0, 1.0), 2.0)) * h
		elif throttle > 0.01:
			v_f = move_toward(v_f, 0.0, braking * throttle * h)
		elif brake > 0.01 and (v_f > 0.3 or disabled):
			v_f = move_toward(v_f, 0.0, braking * brake * h)
		elif brake > 0.01:
			v_f = move_toward(v_f, -DRIVE_MAX_REVERSE * factor, DRIVE_REVERSE_ACCEL * brake * h)
		else:
			v_f = move_toward(v_f, 0.0, (DRIVE_COAST + DRIVE_DRAG * v_f * v_f) * h)
		if v_f > top:
			v_f = move_toward(v_f, top, 4.0 * h)
		var adhesion := DRIVE_LATERAL_GRIP * grip * (DRIVE_HANDBRAKE_GRIP if handbrake and absf(v_f) > 2.0 else 1.0)
		v_s *= exp(-adhesion * h)
		if absf(v_s) < 0.005:
			v_s = 0.0
	drive_velocity = forward * v_f + side * v_s
	var motion := drive_velocity * h
	if motion.length_squared() > 0.0000001 or drive_airborne:
		result.moved = _drive_translate(motion, h, result)
	speed = drive_velocity.dot(forward)
	return result

func _drive_translate(motion: Vector3, h: float, result: Dictionary, slides_left := 1) -> float:
	var start := global_position
	var flat_motion := Vector3(motion.x, 0.0, motion.z)
	var ground := _drive_ground(start + flat_motion, yaw)
	if ground.is_empty():
		# No support, a slope steeper than tires climb, or a riser above a curb.
		_drive_block(-flat_motion.normalized(), "terrain", {}, result)
		return 0.0
	var pose: Transform3D = ground.transform
	if not _external_road_clear(pose):
		# This is a controller boundary, not a physical collision. Stop before
		# committing it without inventing crash damage or witness events.
		drive_velocity = Vector3.ZERO
		result.blocked = "road"
		return 0.0
	var support := pose.origin.y
	# Follow slopes and curbs down while rolling; larger drops fall with gravity.
	var settle := 0.06 + flat_motion.length() * DRIVE_MAX_SLOPE
	if drive_airborne or support < start.y - settle:
		drive_vertical_speed -= DRIVE_GRAVITY * h
		pose.origin.y = maxf(support, start.y + drive_vertical_speed * h)
		drive_airborne = pose.origin.y > support + 0.005
	else:
		drive_airborne = false
	if not drive_airborne:
		drive_vertical_speed = 0.0
	var sweep := pose.origin - start
	var cast := _drive_cast(global_transform, sweep)
	var probe_pose := global_transform
	var probe_mask := _drive_mask()
	# Terrain taller than a curb is a wall: sweep the hull lifted by about a
	# step against it, so the bumper stops at a riser instead of entering it.
	# Skipped if the lifted hull already touches terrain (a single trimesh).
	var lifted := global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * DRIVE_TERRAIN_LIFT)
	if _drive_pose_clear(lifted, 1):
		var riser := _drive_cast(lifted, sweep, 1)
		if float(riser.safe) < float(cast.safe):
			cast = riser
			probe_pose = lifted
			probe_mask = 1
	if float(cast.safe) >= 1.0:
		if _drive_pose_clear(pose):
			_drive_commit(pose, ground.heights)
			return Vector2(sweep.x, sweep.z).length()
		# Tilting onto the new support would enter something low beside it.
		var level_pose := Transform3D(global_basis, pose.origin)
		if _drive_pose_clear(level_pose):
			_drive_commit(level_pose, ground.heights)
			return Vector2(sweep.x, sweep.z).length()
		_drive_block(-flat_motion.normalized(), "clearance", {}, result)
		return 0.0
	# Contact: stop just short of it and keep only the motion along the surface.
	# The swept hull never passes the first touching fraction, so thin posts and
	# walls cannot be tunnelled through even at the largest substep.
	var contact := _drive_contact(probe_pose, sweep, float(cast.unsafe), probe_mask)
	var normal: Vector3 = contact.get("normal", -flat_motion.normalized())
	normal.y = 0.0
	normal = normal.normalized() if normal.length_squared() > 0.0001 else -flat_motion.normalized()
	var fraction := maxf(0.0, float(cast.safe) - DRIVE_SKIN / maxf(sweep.length(), 0.001))
	var moved := 0.0
	if fraction > 0.0:
		var reached := Transform3D(global_basis, start + sweep * fraction)
		if _drive_pose_clear(reached):
			_drive_commit(reached, PackedFloat32Array())
			moved = Vector2(sweep.x, sweep.z).length() * fraction
	_drive_block(normal, "terrain" if probe_mask == 1 else str(contact.get("kind", "structure")), contact, result)
	# Spend the remaining grounded substep along the contact surface. Merely
	# projecting velocity leaves the car stuck at the first touching fraction:
	# tire adhesion adds an inward component again before the next update.
	# One retry is sufficient for a glancing wall; a second obstacle stops it.
	# The retry uses the same terrain, compound sweeps and final-pose checks.
	if slides_left > 0 and not drive_airborne:
		var remaining := h * (1.0 - fraction)
		var slide := drive_velocity * remaining
		if slide.length_squared() > 0.0000001:
			moved += _drive_translate(slide, remaining, result, slides_left - 1)
	return moved

func _drive_block(normal: Vector3, kind: String, contact: Dictionary, result: Dictionary) -> void:
	# Closing speed against a moving body (car, person) uses both velocities;
	# the physical response below still removes only this car's inward part.
	var collider = contact.get("collider")
	var closing := drive_velocity
	if collider is CharacterBody3D and collider != self:
		closing -= Vector3((collider as CharacterBody3D).velocity.x, 0.0, (collider as CharacterBody3D).velocity.z)
	var relative := maxf(0.0, -closing.dot(normal))
	var car_speed := Vector2(drive_velocity.x, drive_velocity.z).length()
	var into := drive_velocity.dot(normal)
	var impact := maxf(0.0, -into)
	if into < 0.0:
		drive_velocity -= normal * into
		# A real hit also costs speed along the surface; sustained sliding
		# (sub-1 m/s closing speed each update) only loses its normal part.
		drive_velocity *= 1.0 - clampf((impact - 1.0) * 0.035, 0.0, 0.6)
	drive_vertical_speed = minf(drive_vertical_speed, 0.0)
	drive_contacts += 1
	last_drive_contact = {"kind": kind, "speed": impact, "normal": normal,
		"position": contact.get("point", global_position), "collider": collider}
	if result.contact.is_empty() or impact > float(result.contact.speed):
		result.contact = last_drive_contact
	if kind in ["terrain", "clearance"]:
		result.blocked = kind
	_note_contact(kind, normal, last_drive_contact.position, collider, relative, car_speed)

func _drive_commit(pose: Transform3D, heights: PackedFloat32Array) -> void:
	global_transform = pose
	if heights.size() == 5:
		_drive_heights = heights

func _drive_ground(at: Vector3, heading: float) -> Dictionary:
	if _drive_ray == null:
		_drive_ray = PhysicsRayQueryParameters3D.new()
		_drive_ray.collision_mask = 1
		_drive_ray.hit_back_faces = false
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var top := maxf(global_position.y, at.y) + DRIVE_STEP_UP + 0.6
	var heights := PackedFloat32Array()
	var space := get_world_3d().direct_space_state
	for offset in [Vector3.ZERO, forward * 1.35, -forward * 1.35, right * 0.80, -right * 0.80]:
		var point: Vector3 = at + offset
		_drive_ray.from = Vector3(point.x, top, point.z)
		_drive_ray.to = Vector3(point.x, top - 45.0, point.z)
		var hit := space.intersect_ray(_drive_ray)
		if hit.is_empty():
			return {}
		heights.append(float(hit.position.y))
	# Rays sit on curb edges at times, so judge the surface by sampled heights:
	# a riser taller than a curb between updates is a wall for the tires.
	if _drive_heights.size() == heights.size():
		for i in heights.size():
			if heights[i] - _drive_heights[i] > DRIVE_STEP_UP:
				return {}
	var pitch := (heights[1] - heights[2]) / 2.70
	var roll := (heights[3] - heights[4]) / 1.60
	if absf(pitch) > DRIVE_MAX_SLOPE or absf(roll) > DRIVE_MAX_SLOPE:
		return {}
	forward.y = pitch
	right.y = roll
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	var origin := Vector3(at.x, (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025, at.z)
	return {"transform": Transform3D(Basis(right, up, forward), origin), "heights": heights}

## Swept obstacles for a driven body. A seated explorer has no collider (their
## car is layer 16); an external car must also stop for the explorer on foot.
func _drive_mask() -> int:
	return DRIVE_MASK if external_owner.is_empty() else DRIVE_MASK | 4

func _drive_query(pose: Transform3D, motion: Vector3, part_index: int, mask := -1) -> PhysicsShapeQueryParameters3D:
	# Separate from the traffic query cache, whose rider/mask state it must not touch.
	if mask < 0:
		mask = _drive_mask()
	if _drive_params == null:
		_drive_params = PhysicsShapeQueryParameters3D.new()
	_drive_params.shape = _clearance_shape if part_index < 0 else collision_parts[part_index].shape
	_drive_params.transform = pose * Transform3D(Basis.IDENTITY, _clearance_center) if part_index < 0 else pose
	_drive_params.motion = motion
	_drive_params.margin = 0.0
	_drive_params.collision_mask = mask
	if _drive_exclude.is_empty():
		_drive_exclude = [get_rid()]
	_drive_params.exclude = _drive_exclude
	return _drive_params

func _drive_overlaps(pose: Transform3D) -> Array[RID]:
	var found: Array[RID] = []
	var space := get_world_3d().direct_space_state
	if _clearance_shape != null and space.intersect_shape(_drive_query(pose, Vector3.ZERO, -1), 1).is_empty():
		return found
	for part_index in collision_parts.size():
		for hit in space.intersect_shape(_drive_query(pose, Vector3.ZERO, part_index), 8):
			var rid: RID = hit.rid
			if not found.has(rid):
				found.append(rid)
	return found

func _drive_pose_clear(pose: Transform3D, mask := -1) -> bool:
	# Scripted emergency drivers must keep the complete hull on the road.
	# Test before any commit (including rotation/reverse), while player-driven
	# vehicles retain their existing freedom to leave the carriageway.
	if not _external_road_clear(pose):
		return false
	var space := get_world_3d().direct_space_state
	if _clearance_shape != null and space.intersect_shape(_drive_query(pose, Vector3.ZERO, -1, mask), 1).is_empty():
		return true
	for part_index in collision_parts.size():
		if not space.intersect_shape(_drive_query(pose, Vector3.ZERO, part_index, mask), 1).is_empty():
			return false
	return true

func _external_road_clear(pose: Transform3D) -> bool:
	if not external_owner.is_empty():
		for corner in ROAD_CORNERS:
			if not traffic.on_road(pose * corner):
				return false
	return true

## Yaw about the rear axle, as the steered bicycle model turns: the tail does
## not slide out sideways at parking speeds.
func _turned_pose(turn: float) -> Transform3D:
	var pose := global_transform
	var spin := Basis(Vector3.UP, turn)
	var pivot := pose.origin - Vector3(sin(yaw), 0.0, cos(yaw)) * DRIVE_PIVOT
	pose.basis = spin * pose.basis
	pose.origin = pivot + spin * (pose.origin - pivot)
	return pose

func _drive_rotation_clear(turn: float) -> bool:
	# Sample the rotating corners at most two query margins apart (as traffic
	# does); translation sweeps alone never enclose a turning body.
	var samples := maxi(1, ceili(absf(turn) * (_collision_radius + DRIVE_PIVOT) / (QUERY_MARGIN * 2.0)))
	for sample in range(1, samples + 1):
		if not _drive_pose_clear(_turned_pose(turn * float(sample) / samples)):
			return false
	return true

## A body touching a wall must still be able to steer away from it, although
## its far corner swings a few millimetres toward the wall. Accept the turn
## when separating along the actual contact by at most the corner travel
## leaves the whole hull clear. Returns a non-finite transform when refused.
func _drive_rotation_nudge(turn: float) -> Transform3D:
	var refused := Transform3D(Basis.IDENTITY, Vector3.INF)
	var pose := _turned_pose(turn)
	var limit := maxf(0.02, absf(turn) * (_collision_radius + DRIVE_PIVOT) * 1.5)
	var space := get_world_3d().direct_space_state
	var push := Vector3.ZERO
	for part_index in collision_parts.size():
		var points := space.collide_shape(_drive_query(pose, Vector3.ZERO, part_index), 8)
		for i in range(0, points.size() - 1, 2):
			# Pairs are (point on this hull, point on the other body).
			var separation: Vector3 = points[i + 1] - points[i]
			separation.y = 0.0
			if separation.length_squared() > push.length_squared():
				push = separation
	if push.length_squared() < 0.00000001 or push.length() > limit:
		return refused
	pose.origin += push + push.normalized() * DRIVE_SKIN
	return pose if _drive_pose_clear(pose) else refused

func _drive_cast(pose: Transform3D, motion: Vector3, mask := -1) -> Dictionary:
	var best := {"safe": 1.0, "unsafe": 1.0}
	if motion.length_squared() < 0.00000001:
		return best
	var space := get_world_3d().direct_space_state
	for part_index in collision_parts.size():
		var fractions := space.cast_motion(_drive_query(pose, motion, part_index, mask))
		if fractions.size() < 2:
			return {"safe": 0.0, "unsafe": 0.0}
		if fractions[0] < float(best.safe):
			best = {"safe": fractions[0], "unsafe": fractions[1]}
	return best

func _drive_contact(pose: Transform3D, motion: Vector3, unsafe: float, mask := -1) -> Dictionary:
	var probe := pose
	probe.origin += motion * clampf(unsafe + 0.01 / maxf(motion.length(), 0.001), 0.0, 1.0)
	var space := get_world_3d().direct_space_state
	for part_index in collision_parts.size():
		var query := _drive_query(probe, Vector3.ZERO, part_index, mask)
		query.margin = 0.03
		var info := space.get_rest_info(query)
		if info.is_empty():
			continue
		var collider := instance_from_id(int(info.collider_id))
		return {"normal": info.normal, "point": info.point, "collider": collider, "kind": _contact_kind(collider)}
	return {}

static func _contact_kind(collider: Object) -> String:
	if collider is CollisionObject3D:
		var body := collider as CollisionObject3D
		if body.has_meta("traffic_vehicle") or body.has_meta("parked_vehicle") or (body.collision_layer & 16) != 0:
			return "vehicle"
		if (body.collision_layer & 8) != 0:
			return "person"
		# Only external (police) sweeps include the on-foot explorer's layer.
		if (body.collision_layer & 4) != 0:
			return "player"
	return "structure"

# --- Contacts, damage and telemetry ----------------------------------------

static func crash_damage(relative_speed: float) -> float:
	return snappedf(clampf((relative_speed - CRASH_DAMAGE_FLOOR) * CRASH_DAMAGE_SCALE, 0.0, CRASH_DAMAGE_CAP), 0.1)

static func contact_severity(relative_speed: float) -> String:
	return "crash" if relative_speed >= 9.0 else ("bump" if relative_speed >= 4.0 else "scrape")

## Turns raw swept contacts into bounded episodes. A key stays "in contact"
## while touched again within CONTACT_SEPARATION; only a first touch, a touch
## after separating, or a clearly harder re-hit creates an event (and damage).
func _note_contact(kind: String, normal: Vector3, at: Vector3, collider: Object, relative: float, car_speed: float) -> void:
	var key := _contact_key(kind, collider)
	var memory: Dictionary = _contact_memory.get(key, {})
	var separated := memory.is_empty() or _contact_clock - float(memory.touch) >= CONTACT_SEPARATION
	var harder := not memory.is_empty() and relative >= float(memory.speed) + CONTACT_REHIT_GAIN \
		and _contact_clock - float(memory.time) >= CONTACT_REHIT_DELAY
	if memory.is_empty():
		memory = {"touch": _contact_clock, "time": -INF, "speed": 0.0}
		_contact_memory[key] = memory
	memory.touch = _contact_clock
	if relative < CONTACT_MIN_SPEED or not (separated or harder) or _step_events.size() >= CONTACT_MAX_EVENTS:
		_prune_contacts()
		return
	memory.time = _contact_clock
	memory.speed = relative
	_prune_contacts()
	_step_events.append(_contact_event(kind, normal, at, collider, relative, car_speed))

func _contact_key(kind: String, collider: Object) -> String:
	if is_instance_valid(collider):
		return str(collider.get_instance_id())
	return kind

func _prune_contacts() -> void:
	if _contact_memory.size() <= CONTACT_MAX_KEYS:
		return
	var oldest := ""
	var oldest_touch := INF
	for key in _contact_memory:
		var touch := float(_contact_memory[key].touch)
		if touch < oldest_touch:
			oldest_touch = touch
			oldest = str(key)
	_contact_memory.erase(oldest)

func _contact_event(kind: String, normal: Vector3, at: Vector3, collider: Object, relative: float, car_speed: float) -> Dictionary:
	var valid := is_instance_valid(collider)
	var other_id := ""
	var other_police := false
	var other_owner := ""
	var actor_id := ""
	var own_damage := 0.0
	var other_damage := 0.0
	if kind in ["structure", "terrain", "clearance", "vehicle"]:
		own_damage = crash_damage(relative)
	if valid and kind == "vehicle":
		if collider.has_method("apply_body_damage"):
			other_id = str(collider.get("vehicle_id"))
			other_police = collider.get("is_police") == true
			other_owner = str(collider.get("external_owner")) if collider.get("external_owner") != null else ""
			var before := float(collider.get("health"))
			if collider.apply_body_damage(crash_damage(relative), at):
				other_damage = before - float(collider.get("health"))
		elif collider.has_meta("parked_index"):
			var parked = traffic.get("parked") if is_instance_valid(traffic) else null
			var index := int(collider.get_meta("parked_index"))
			if parked != null and parked.has_method("apply_body_damage") and index >= 0 and index < parked.records.size():
				other_id = str(parked.records[index].get("source_id", "parked_%03d" % index))
				var before := float(parked.records[index].get("health", MAX_HEALTH))
				if parked.apply_body_damage(index, crash_damage(relative), at):
					other_damage = before - float(parked.records[index].get("health", MAX_HEALTH))
	elif valid and kind == "person":
		# Same identities as combat: an actor's actor_id, else crowd_<index>.
		var named = collider.get("actor_id")
		if named is String and not (named as String).is_empty():
			actor_id = named
		elif collider.has_meta("city_crowd_index"):
			actor_id = "crowd_%d" % int(collider.get_meta("city_crowd_index"))
	elif valid and kind == "player" and relative >= PERSON_IMPACT_SPEED and collider.has_method("receive_vehicle_impact"):
		# The explorer stumbles away from an external car (normal points to the car).
		collider.receive_vehicle_impact(-normal, relative, vehicle_id)
	var before_health := health
	if own_damage > 0.0:
		apply_body_damage(own_damage, at)
	_contact_serial += 1
	contact_events += 1
	return {"id": _contact_serial, "vehicle_id": vehicle_id, "registry_id": registry_id,
		"driver": "player" if player_controlled else "external", "external_owner": external_owner,
		"kind": kind, "collider": collider if valid else null, "actor_id": actor_id,
		"other_vehicle_id": other_id, "other_police": other_police, "other_external_owner": other_owner,
		"relative_speed": relative, "car_speed": car_speed, "point": at, "normal": normal,
		"severity": contact_severity(relative), "body_damage": before_health - health,
		"other_damage": other_damage, "health": health, "disabled": disabled, "time_msec": Time.get_ticks_msec()}

## Bounded body damage. Returns true only if health actually changed.
## Reaching zero disables the engine (sticky until recycle/reset).
func apply_body_damage(amount: float, origin: Vector3 = Vector3.INF) -> bool:
	if not is_finite(amount) or amount <= 0.0 or disabled:
		return false
	var before := health
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	if origin.is_finite():
		last_damage_origin = origin
	damage_events += 1
	if health <= 0.0:
		_disable()
	return health != before

func _disable() -> void:
	health = 0.0
	disabled = true
	stopped_time = 0.0
	# A wreck must not hold a junction hostage; followers queue behind it.
	if not player_controlled and external_owner.is_empty() and is_instance_valid(traffic) and traffic.has_method("release_reservation"):
		traffic.release_reservation(self)

func is_disabled() -> bool:
	return disabled

func damage_stage() -> String:
	if disabled:
		return "disabled"
	if health <= 35.0:
		return "smoking"
	return "damaged" if health < MAX_HEALTH else "intact"

func get_damage_status() -> Dictionary:
	return {"health": health, "max_health": MAX_HEALTH, "disabled": disabled, "stage": damage_stage(),
		"flat_tires": flat_tires.duplicate(), "external_owner": external_owner,
		"seat": "player" if player_controlled else ("external" if not external_owner.is_empty() else "empty")}

## Persistence/promotion: exact health and flat tires (vehicle wheel order).
func set_damage_state(value: float, tires: Array) -> void:
	health = clampf(value, 0.0, MAX_HEALTH) if is_finite(value) else MAX_HEALTH
	disabled = health <= 0.0
	var valid_tires: Array[int] = []
	for tire in tires:
		var index := int(tire)
		if index >= 0 and index < maxi(_wheels.size(), 4) and not valid_tires.has(index):
			valid_tires.append(index)
	valid_tires.sort()
	flat_tires = valid_tires
	_cached_tire_profile.clear()
	if not flat_tires.is_empty():
		_route_position = global_position
		_route_heading = yaw
	if model != null:
		_update_wheels()
	if is_instance_valid(_render_lod):
		_render_lod.refresh_vehicle(self)

## Exact parked placement for driving's own bodies (restore/reset). The caller
## validated support and clearance; the car stays stationary and unrouted.
func place_parked(pose: Transform3D, heading: float) -> void:
	global_transform = pose
	yaw = heading
	speed = 0.0
	velocity = Vector3.ZERO
	drive_velocity = Vector3.ZERO
	drive_steer = 0.0
	wheel_steer = 0.0
	drive_airborne = false
	drive_vertical_speed = 0.0
	_drive_heights = PackedFloat32Array()
	var parked_route: Array[Vector3] = [pose.origin, pose.origin + Vector3(sin(heading), 0.0, cos(heading)) * 5.0]
	route = parked_route
	route_index = route.size()
	_route_position = pose.origin
	_route_heading = heading
	state = "parked"
	stopped_time = 0.0
	blocked_reason = ""
	_contact_memory.clear()
	if model != null and model.visible:
		_update_wheels()
	if is_instance_valid(_render_lod):
		_render_lod.refresh_vehicle(self)

## Read-only state for engine/skid audio and seat presentation.
func get_drive_telemetry() -> Dictionary:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(forward.z, 0.0, -forward.x)
	var driven := player_controlled or not external_owner.is_empty()
	var throttle := float(_drive_input.throttle) if driven else 0.0
	var forward_speed := drive_velocity.dot(forward) if driven else speed
	return {"speed": absf(forward_speed), "forward_speed": forward_speed,
		"lateral_slip": drive_velocity.dot(side) if driven else 0.0, "throttle": throttle,
		"brake": float(_drive_input.brake) if driven else 0.0, "steer": drive_steer,
		"handbrake": bool(_drive_input.handbrake) if driven else false, "airborne": drive_airborne,
		"engine_load": 0.0 if disabled else clampf(throttle * 0.7 + absf(forward_speed) / DRIVE_MAX_SPEED * 0.3, 0.0, 1.0),
		"disabled": disabled, "health": health, "wheel_steer": wheel_steer}

## Approximate driver hip point on the +X (driver) side, facing forward.
func driver_seat_transform() -> Transform3D:
	var size := Models.dimensions(prototype_kind) if Models.has_kind(prototype_kind) else BODY_SIZE
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(size.x * 0.21, clampf(size.y * 0.36, 0.48, 0.78), -0.08))

func _exit_tree() -> void:
	if is_instance_valid(_render_lod) and _render_lod.is_inside_tree():
		_render_lod.unregister_vehicle(self)
