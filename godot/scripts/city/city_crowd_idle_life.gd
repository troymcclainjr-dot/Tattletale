extends RefCounted
## Presentation and a tiny nearby pacing budget; canonical identities never change.
const MAX_PACERS := 6
const STEP := 0.10
const MAX_MOVES_PER_TICK := 2
const PLAN_INTERVAL := 1.5
const RADIUS := 26.0
const SPEED := 0.48
const DISTANCE := 0.85
const Civic := preload("res://scripts/city/city_civic_clearance.gd")
var pacers: Dictionary = {}
var _next_plan := 1.0
var _cursor := 0
var moves := 0
var starts := 0
var blocked := 0
var queries := 0
var last_tick_moves := 0
var last_tick_queries := 0
var max_tick_queries := 0
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _ground_query := PhysicsRayQueryParameters3D.new()

static func owns_idle(resident: Dictionary) -> bool:
	return int(resident.get("pose", 0)) == 0 and str(resident.get("activity", "")) != "porch" \
		and str(resident.get("activity", "")) != "walking" and not resident.get("identity_unplaced", false) \
		and not resident.get("dead", false) and not resident.get("combat_controlled", false) \
		and not resident.get("panic", false) and not resident.get("police_custody", false) \
		and not resident.get("bicycle_avoiding", false) and not resident.has("bicycle_rejoin")

static func activity_for(index: int) -> int:
	# Stable ordinal mix; does not depend on appearance, class, location or frame.
	var bucket := posmod(index * 37 + 11, 23)
	return 2 if bucket in [2, 8, 17] else (3 if bucket in [4, 13, 21] else 1)

static func phase_for(index: int) -> float:
	return float(posmod(index * 7919 + 137, 1009)) / 1009.0

func tick(crowd: Node3D) -> void:
	last_tick_moves = 0
	last_tick_queries = 0
	if pacers.is_empty():
		return
	var keys := pacers.keys()
	for offset in keys.size():
		var index: int = keys[(_cursor + offset) % keys.size()]
		if not pacers.has(index):
			continue
		var resident: Dictionary = crowd.residents[index]
		var task: Dictionary = pacers[index]
		if not owns_idle(resident) or resident.position.distance_squared_to(crowd.level.player.global_position) > RADIUS * RADIUS or not is_instance_valid(resident.get("body")):
			_finish(crowd, index, false)
			continue
		if crowd._clock < float(task.next) or last_tick_moves >= MAX_MOVES_PER_TICK:
			continue
		task.next = crowd._clock + STEP
		last_tick_moves += 1
		if crowd._clock > float(task.deadline):
			_finish(crowd, index, false)
			continue
		var target: Vector3 = task.home if bool(task.returning) else task.goal
		if resident.position.distance_to(target) < .025:
			if bool(task.returning):
				resident.yaw = float(task.yaw)
				_finish(crowd, index, true)
			else:
				task.returning = true
				task.next = crowd._clock + 1.0 + phase_for(index)
			continue
		var heading: Vector3 = target - resident.position
		var wanted := atan2(heading.x, heading.z)
		resident.yaw = rotate_toward(float(resident.yaw), wanted, 3.2 * STEP)
		if absf(angle_difference(float(resident.yaw), wanted)) > .08:
			_upload(crowd, index, false)
			continue
		var next: Vector3 = resident.position.move_toward(target, SPEED * STEP)
		var ground := _ground(crowd, next, float(resident.position.y))
		if ground.is_empty() or not _clear(crowd, index, resident.position, ground.position):
			blocked += 1
			task.next = crowd._clock + .6
			task.returning = true
			_upload(crowd, index, false)
			continue
		var before: Vector3 = resident.position
		crowd._relocate(index, before, ground.position, true)
		resident.body.global_position = resident.position
		_upload(crowd, index, true)
		moves += 1
	_cursor += 1
	max_tick_queries = maxi(max_tick_queries, last_tick_queries)

func consider(crowd: Node3D, index: int) -> void:
	if pacers.size() >= MAX_PACERS or pacers.has(index) or crowd._clock < _next_plan or index % 11 != 5:
		return
	var resident: Dictionary = crowd.residents[index]
	if not owns_idle(resident) or not is_instance_valid(resident.get("body")) or resident.position.distance_squared_to(crowd.level.player.global_position) > RADIUS * RADIUS:
		return
	if float(resident.get("idle_pace_after", 0.0)) > crowd._clock or crowd.npcs == null or not crowd.npcs.has_method("_street_info"):
		return
	_next_plan = crowd._clock + PLAN_INTERVAL
	resident.idle_pace_after = crowd._clock + 22.0 + phase_for(index) * 18.0
	var origin: Vector3 = resident.position
	var side := Vector3(cos(float(resident.yaw)), 0.0, -sin(float(resident.yaw)))
	side *= -1.0 if index % 2 else 1.0
	var end := origin + side * DISTANCE
	var street: Dictionary = crowd.npcs._street_info(end)
	if float(street.get("distance", INF)) < float(street.get("width", 9.5)) * .5 + .55 or Civic.blocked(crowd.level, end, .3):
		return
	# Three supported samples stop short routes crossing a curb, gap or stairs.
	var previous := origin
	for fraction in [.33, .66, 1.0]:
		var ground := _ground(crowd, origin.lerp(end, float(fraction)), float(previous.y))
		if ground.is_empty():
			return
		previous = ground.position
	end = previous
	if not _clear(crowd, index, origin, end):
		blocked += 1
		return
	pacers[index] = {"home": origin, "goal": end, "yaw": resident.yaw, "returning": false,
		"next": crowd._clock + phase_for(index) * STEP, "deadline": crowd._clock + 16.0}
	resident.idle_pacing = true
	starts += 1
	max_tick_queries = maxi(max_tick_queries, last_tick_queries)

func _ground(crowd: Node3D, at: Vector3, height: float) -> Dictionary:
	_ground_query.from = Vector3(at.x, height + .35, at.z)
	_ground_query.to = Vector3(at.x, height - .35, at.z)
	_ground_query.collision_mask = 1 | 2
	queries += 1
	last_tick_queries += 1
	var hit := crowd.get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty() or hit.normal.y < .94 or absf(float(hit.position.y) + .012 - height) > .10:
		return {}
	return {"position": hit.position + Vector3.UP * .012}

func _clear(crowd: Node3D, index: int, from: Vector3, to: Vector3) -> bool:
	if to.distance_squared_to(crowd.level.player.global_position) < .9 * .9:
		return false
	var resident: Dictionary = crowd.residents[index]
	var cell := Vector2i(floori(to.x / 4.0), floori(to.z / 4.0))
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			for other in crowd._spacing_grid.get(Vector2i(x, z), []):
				if int(other) != index and crowd.residents[int(other)].position.distance_squared_to(to) < .75 * .75:
					return false
	_shape_query.shape = resident.get("body_shape", crowd._shape)
	_shape_query.transform = Transform3D(Basis.IDENTITY, from + resident.get("body_shape_offset", Vector3.UP * .9))
	_shape_query.motion = to - from
	_shape_query.collision_mask = 2 | 4 | 8 | 16
	_shape_query.margin = .02
	_shape_query.exclude = [resident.body.get_rid()]
	var space := crowd.get_world_3d().direct_space_state
	queries += 1
	last_tick_queries += 1
	var sweep := space.cast_motion(_shape_query)
	if not sweep.is_empty() and sweep[0] < .999:
		return false
	_shape_query.transform.origin = to + resident.get("body_shape_offset", Vector3.UP * .9)
	_shape_query.motion = Vector3.ZERO
	queries += 1
	last_tick_queries += 1
	return space.intersect_shape(_shape_query, 1).is_empty()

func _upload(crowd: Node3D, index: int, walking: bool) -> void:
	var resident: Dictionary = crowd.residents[index]
	var batch: Dictionary = crowd._batches[resident.batch]
	if not is_instance_valid(batch.node):
		return
	batch.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, resident.yaw), resident.position - batch.origin))
	crowd._set_idle_visual(index, 4 if walking else 1)

func _finish(crowd: Node3D, index: int, returned: bool) -> void:
	pacers.erase(index)
	var resident: Dictionary = crowd.residents[index]
	resident.erase("idle_pacing")
	# If blocked/interrupted, stop exactly at the checked current position; never
	# teleport home or retain a movement owner after combat/bike/custody takes over.
	if owns_idle(resident):
		_upload(crowd, index, false)
	elif resident.has("batch"):
		crowd._set_idle_visual(index, 0)
	if returned:
		resident.idle_pace_after = crowd._clock + 30.0 + phase_for(index) * 20.0

func status() -> Dictionary:
	return {"pacers": pacers.size(), "max_pacers": MAX_PACERS, "pace_starts": starts,
		"pace_moves": moves, "pace_blocked": blocked, "physics_queries": queries,
		"last_tick_moves": last_tick_moves, "last_tick_queries": last_tick_queries,
		"max_tick_queries": max_tick_queries, "plan_interval": PLAN_INTERVAL, "radius": RADIUS}
