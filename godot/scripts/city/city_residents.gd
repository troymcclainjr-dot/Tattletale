extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
## Forty authored adults, separate from mission contacts and the primitive crowd.
## Real street polylines provide a small local sidewalk network for each resident.
## Each edge is grounded and swept once; moving actors still collide every step.

const Actor := preload("res://scripts/city/city_resident_actor.gd")
const DATA_PATH := "res://assets/data/pen_lucy_residents.json"
const STATE_VERSION := 1
# Exact launch roster accepted by schema-1 checkpoints after append-only expansion.
const LEGACY_RESIDENT_IDS := [
	"daily_nadine_brooks",
	"daily_calvin_reed",
	"daily_ines_morales",
	"daily_walter_price",
	"daily_aisha_bell",
	"daily_ernest_cole",
	"daily_june_harris",
	"daily_marcus_webb",
	"daily_pearl_sutton",
	"daily_andre_foster",
	"daily_luz_santos",
	"daily_theo_washington",
	"daily_ruth_daniels",
	"daily_devon_clarke",
	"daily_celia_grant",
	"daily_oscar_bennett",
	"daily_miriam_owens",
	"daily_leon_turner",
	"daily_estelle_ross",
	"daily_samir_haddad",
]
const ACTIVE_RADIUS := 100.0
const INACTIVE_RADIUS := 120.0
const FAR_INTERVAL := 0.5
var level: Node3D
var actors: Dictionary = {}
var definitions: Array = []
var routes: Dictionary = {}
var placements: Dictionary = {}
var placement_failures: Array[String] = []
var route_failures: Array[String] = []
var routines_enabled := true
var _build_queue: Array[String] = []
var _shape: CapsuleShape3D
var _far_accumulator := 0.0
var _schedule_accumulator := 0.0
var _last_slots: Dictionary = {}
var _near_updates := 0
var _far_updates := 0
var _path_builds := 0
var _last_tick_usec := 0
var _max_tick_usec := 0
var _route_exclude: Array[RID] = []
var _activation_waits := 0
var _logical_waits := 0

func setup(owner_level: Node3D) -> void:
	if not actors.is_empty():
		return
	level = owner_level
	name = "DailyResidents"
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.30
	_shape.height = 1.90
	# Traffic vehicles can leave/rejoin a lane; parked-car provider bodies are
	# permanent obstacles and remain included in the layer-16 route sweep.
	if level.get("traffic") != null:
		for car in level.traffic.vehicles:
			_route_exclude.append(car.get_rid())
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != STATE_VERSION:
		push_error("Daily resident data is missing or has an unsupported version")
		return
	definitions = parsed.get("residents", [])
	for definition in definitions:
		_spawn(definition)

func _spawn(definition: Dictionary) -> void:
	var id := str(definition.id)
	var selected: Dictionary = {}
	var roads: Array = level.level_data.get("roads", [])
	# Prefer the authored street, then another actual street if its frontage is
	# occupied. Never put a body into an unchecked fallback coordinate.
	var candidates: Array = []
	for road in roads:
		if str(road.get("name", "")) == str(definition.street):
			candidates.append(road)
	for road in roads:
		if not candidates.has(road):
			candidates.append(road)
	for road in candidates:
		var length := _road_length(road)
		if length < 35.0:
			continue
		for fraction in [float(definition.get("fraction", 0.5)), 0.35, 0.65]:
			var station: float = length * fraction
			for side in [float(definition.get("side", 1.0)), -float(definition.get("side", 1.0))]:
				var desired := _lane_point(road, station, side, 0.0)
				var found: Dictionary = level.npcs._safe_candidate(desired, 0.30)
				if found.is_empty() or not _separated(found.position):
					continue
				# Reject isolated clear spots before creating a visible resident.
				# This small probe bounds the minimum useful daily walking corridor.
				if not _has_frontage(road, station, side, found.position):
					continue
				selected = {"position": found.position, "road": road, "station": station, "side": side}
				break
			if not selected.is_empty():
				break
		if not selected.is_empty():
			break
	if selected.is_empty():
		placement_failures.append(id)
		return
	var actor := Actor.new()
	add_child(actor)
	actor.build_resident(level, definition)
	actor.set_meta("population_appearance", Appearance.profile(id))
	actor.global_position = selected.position
	actor.physical = _is_near(actor.global_position)
	actor.set_distance_fade(_player_distance(actor.global_position))
	actor.set_enabled(actor.physical)
	actors[id] = actor
	placements[id] = selected
	_build_queue.append(id)
	level.register_conversation(id, {"start": "hello", "nodes": {
		"hello": {"speaker": str(definition.name), "lines": definition.dialogue,
			"choices": [{"text": "What keeps you busy?", "next": "routine"}, {"text": "See you around."}]},
		"routine": {"speaker": str(definition.name), "lines": [str(definition.about)],
			"choices": [{"text": "Have a good day."}]}}})

func _separated(point: Vector3) -> bool:
	if CivicClearance.blocked(level, point, 0.35):
		return false
	for actor in actors.values():
		if actor.global_position.distance_to(point) < 2.0:
			return false
	return true

func _has_frontage(road: Dictionary, station: float, side: float, start: Vector3) -> bool:
	var clear_steps := 0
	var length := _road_length(road)
	for direction in [-1.0, 1.0]:
		var previous := start
		for step in range(1, 17):
			var along: float = station + step * direction
			if along < 0.0 or along > length:
				break
			var found: Dictionary = {}
			for offset in [0.0, -0.35, 0.35, -0.60, 0.60, -0.8, 0.8]:
				found = _clear_edge(previous, _lane_point(road, along, side, offset))
				if not found.is_empty():
					break
			if found.is_empty():
				break
			previous = found.position
			clear_steps += 1
			if clear_steps >= 15:
				return true
	return false

func _road_length(road: Dictionary) -> float:
	var result := 0.0
	var points: Array = road.get("points", [])
	for i in range(1, points.size()):
		result += level.vector(points[i - 1]).distance_to(level.vector(points[i]))
	return result

func _lane_point(road: Dictionary, station: float, side: float, offset: float) -> Vector3:
	var points: Array = road.get("points", [])
	for i in range(1, points.size()):
		var a: Vector3 = level.vector(points[i - 1])
		var b: Vector3 = level.vector(points[i])
		var length := a.distance_to(b)
		if station <= length or i == points.size() - 1:
			var tangent := (b - a).normalized()
			var across := Vector3(-tangent.z, 0, tangent.x).normalized()
			return a.lerp(b, clampf(station / maxf(length, 0.001), 0.0, 1.0)) + across * side * (float(road.get("width", 9.5)) * 0.5 + 1.15 + offset)
		station -= length
	return Vector3.ZERO

func _build_route(id: String) -> void:
	_path_builds += 1
	var placement: Dictionary = placements[id]
	var actor = actors[id]
	var road_length := _road_length(placement.road)
	var branches: Array = []
	for direction in [-1.0, 1.0]:
		var points: Array[Vector3] = []
		var previous: Vector3 = placement.position
		for step in range(1, 81):
			var station: float = float(placement.station) + step * direction
			if station < 0.0 or station > road_length:
				break
			var found: Dictionary = {}
			for offset in [0.0, -0.35, 0.35, -0.60, 0.60, -0.8, 0.8]:
				var wanted := _lane_point(placement.road, station, float(placement.side), offset)
				if not _home_frontage_clear(previous, wanted, id):
					continue
				found = _clear_edge(previous, wanted)
				if not found.is_empty():
					break
			if found.is_empty():
				break
			points.append(found.position)
			previous = found.position
		branches.append(points)
	var corridor: Array[Vector3] = []
	branches[0].reverse()
	corridor.append_array(branches[0])
	var home_index := corridor.size()
	corridor.append(placement.position)
	corridor.append_array(branches[1])
	var work_index := corridor.size() - 1 if branches[1].size() >= branches[0].size() else 0
	var leisure_index := 0 if work_index > 0 else corridor.size() - 1
	# Prefer three distinct destinations, even on a one-sided accessible frontage.
	if leisure_index == home_index:
		leisure_index = int((home_index + work_index) / 2)
	routes[id] = {"points": corridor, "anchors": {"home": home_index, "sleep": home_index, "work": work_index, "leisure": leisure_index}}
	if corridor.size() < 16:
		route_failures.append(id + ": short accessible frontage (%dm)" % corridor.size())
	_update_schedule(actor, true)

func _clear_edge(start: Vector3, wanted: Vector3) -> Dictionary:
	if CivicClearance.segment_blocked(level, start, wanted, 0.35):
		return {}
	# Validate the entire capsule corridor, not just an endpoint ray. Static
	# scenery is cached; people and vehicles are handled by the physical actor.
	var hit: Dictionary = level.ground_at(wanted)
	if hit.is_empty() or hit.normal.y < cos(deg_to_rad(40.0)):
		return {}
	wanted.y = hit.position.y + 0.012
	if absf(wanted.y - start.y) > 0.20:
		return {}
	if not level.npcs.stair_approach_clear(wanted, 0.85):
		return {}
	if level.vegetation != null and not level.vegetation.is_trunk_clear(wanted, 0.42):
		return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * 1.03)
	query.collision_mask = 2 | 16
	query.exclude = _route_exclude
	query.margin = 0.025
	query.motion = wanted - start
	var space := get_world_3d().direct_space_state
	var sweep := space.cast_motion(query)
	if sweep.size() < 2 or sweep[0] < 0.999:
		return {}
	query.transform.origin = wanted + Vector3.UP * 1.03
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": wanted}

func _home_frontage_clear(start: Vector3, point: Vector3, owner_id: String) -> bool:
	for id in placements:
		var home_point: Vector3 = placements[id].position
		var flat := Vector2(home_point.x, home_point.z)
		var nearest := Geometry2D.get_closest_point_to_segment(flat, Vector2(start.x, start.z), Vector2(point.x, point.z))
		if id != owner_id and nearest.distance_to(flat) < 0.72:
			return false
	return true

static func schedule_slot(schedule: Array, minute: float) -> int:
	var result := 0
	for i in schedule.size():
		if float(schedule[i].minute) <= fposmod(minute, 1440.0):
			result = i
	return result

func _update_schedule(actor, force := false) -> void:
	if not routines_enabled or actor.dead or actor.has_meta("combat_controlled") or not routes.has(actor.actor_id):
		return
	if actor.needs_replan and not force:
		return
	var minute: float = level.world_time.minute_of_day if level.get("world_time") != null else 540.0
	var schedule: Array = actor.routine.schedule
	var slot := schedule_slot(schedule, minute)
	if not force and int(_last_slots.get(actor.actor_id, -1)) == slot:
		return
	_last_slots[actor.actor_id] = slot
	var entry: Dictionary = schedule[slot]
	var route: Dictionary = routes[actor.actor_id]
	var corridor: Array[Vector3] = route.points
	var nearest := 0
	var distance := INF
	for i in corridor.size():
		var candidate: float = actor.global_position.distance_squared_to(corridor[i])
		if candidate < distance:
			nearest = i
			distance = candidate
	var destination: int = route.anchors[str(entry.activity)]
	var path: Array[Vector3] = []
	var direction := 1 if destination >= nearest else -1
	for i in range(nearest, destination + direction, direction):
		path.append(corridor[i])
	actor.assign_route(path, str(entry.activity), str(entry.label))

func tick(delta: float) -> void:
	var started := Time.get_ticks_usec()
	# One bounded local corridor per physics frame; no all-city navigation bake.
	if not _build_queue.is_empty():
		_build_route(_build_queue.pop_front())
	_far_accumulator += delta
	_schedule_accumulator += delta
	var update_schedule := _schedule_accumulator >= 1.0
	if update_schedule:
		_schedule_accumulator = 0.0
	var far_delta := _far_accumulator if _far_accumulator >= FAR_INTERVAL else 0.0
	if far_delta > 0.0:
		_far_accumulator = 0.0
	for actor in actors.values():
		# The timetable never revives, relocates or re-enables a dead identity.
		if actor.dead or actor.has_meta("combat_controlled"):
			continue
		if update_schedule:
			_update_schedule(actor)
		var distance := _player_distance(actor.global_position)
		var near := distance < (INACTIVE_RADIUS if actor.physical else ACTIVE_RADIUS)
		if near and not actor.physical:
			if _activation_clear(actor):
				actor.physical = true
				actor.set_enabled(true)
				actor.arrival_fade = 1.0
			else:
				_activation_waits += 1
		elif not near and actor.physical:
			actor.physical = false
			actor.set_enabled(false)
		actor.routine_enabled = routines_enabled
		if actor.physical:
			actor.set_distance_fade(distance)
			_near_updates += 1
			actor.tick(delta)
			if routines_enabled and actor.recovery_retry <= 0.0:
				if actor.needs_replan:
					resume_after_combat(actor)
				elif actor.blocked_seconds >= 1.25:
					try_recovery(actor)
		elif far_delta > 0.0 and routines_enabled:
			_far_updates += 1
			actor.recovery_retry = maxf(0.0, actor.recovery_retry - far_delta)
			if actor.needs_replan:
				if actor.recovery_retry <= 0.0:
					resume_after_combat(actor)
			else:
				_advance_far(actor, far_delta)
	_last_tick_usec = Time.get_ticks_usec() - started
	_max_tick_usec = maxi(_max_tick_usec, _last_tick_usec)

func _is_near(point: Vector3) -> bool:
	return level.player == null or point.distance_squared_to(level.player.global_position) < ACTIVE_RADIUS * ACTIVE_RADIUS

func _player_distance(point: Vector3) -> float:
	return 0.0 if level.player == null else point.distance_to(level.player.global_position)

func _activation_clear(actor) -> bool:
	if not _logical_clear(actor.global_position, actor):
		return false
	if level.player != null:
		var offset: Vector3 = actor.global_position - level.player.global_position
		if Vector2(offset.x, offset.z).length() < 0.66 and absf(offset.y) < 1.9:
			return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP * 1.03)
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = [actor.get_rid()]
	query.margin = 0.03
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _advance_far(actor, delta: float) -> void:
	var remaining: float = actor.speed * delta
	while remaining > 0.0 and (not actor.recovery_points.is_empty() or actor.route_cursor < actor.route_points.size()):
		var recovering: bool = not actor.recovery_points.is_empty()
		var goal: Vector3 = actor.recovery_points[actor.recovery_cursor] if recovering else actor.route_points[actor.route_cursor]
		var offset: Vector3 = goal - actor.global_position
		var distance := offset.length()
		if distance < 0.02:
			if recovering:
				actor.recovery_cursor += 1
				if actor.recovery_cursor >= actor.recovery_points.size():
					actor.recovery_points.clear()
			else:
				actor.route_cursor += 1
			continue
		var travelled := minf(remaining, distance)
		var next: Vector3 = actor.global_position + offset * (travelled / distance)
		if not _logical_clear(next, actor):
			_logical_waits += 1
			actor.blocked_seconds += delta
			if actor.recovery_retry <= 0.0:
				try_recovery(actor)
			break
		actor.global_position = next
		actor.blocked_seconds = 0.0
		actor.yaw = atan2(offset.x, offset.z)
		actor.puppet.g.rotation.y = actor.yaw
		actor.distance_walked += travelled
		remaining -= travelled
		actor.has_target = false
	actor.route_completed = actor.recovery_points.is_empty() and actor.route_cursor >= actor.route_points.size()

func _logical_clear(point: Vector3, subject) -> bool:
	if CivicClearance.blocked(level, point, 0.35):
		return false
	for other in actors.values():
		if other != subject and not other.dead and point.distance_to(other.global_position) < 0.66:
			return false
	return true

func _on_sidewalk(point: Vector3) -> bool:
	var street: Dictionary = level.npcs._street_info(point)
	var half := float(street.get("width", 9.5)) * 0.5
	var distance := float(street.get("distance", INF))
	return distance >= half + 0.30 and distance <= half + float(street.get("sidewalk", 2.4)) - 0.30

func _motion_clear(actor, start: Vector3, finish: Vector3, sidewalk_only := true) -> Dictionary:
	# Validate every intermediate footfall as well as the continuous body sweep.
	var grounded := finish
	var previous := start
	var steps := maxi(1, ceili(start.distance_to(finish) / 0.4))
	for step in range(1, steps + 1):
		var sample := start.lerp(finish, float(step) / steps)
		if sidewalk_only and not _on_sidewalk(sample):
			return {}
		var ground: Dictionary = level.ground_at(sample)
		if ground.is_empty() or ground.normal.y < cos(deg_to_rad(40.0)):
			return {}
		sample.y = ground.position.y + 0.012
		if absf(sample.y - previous.y) > 0.20 or not _logical_clear(sample, actor):
			return {}
		if not level.npcs.stair_approach_clear(sample, 0.55):
			return {}
		previous = sample
		grounded = sample
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.capsule.shape
	query.transform = Transform3D(Basis.IDENTITY, start + actor.capsule.position)
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = [actor.get_rid()]
	query.margin = 0.005
	query.motion = grounded - start
	var space := get_world_3d().direct_space_state
	var sweep := space.cast_motion(query)
	if sweep.size() < 2 or sweep[0] < 0.999:
		return {}
	query.motion = Vector3.ZERO
	query.transform.origin = grounded + actor.capsule.position
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": grounded}

func try_recovery(actor) -> bool:
	actor.recovery_retry = 1.25
	if actor.route_cursor >= actor.route_points.size():
		return false
	# The lower identity yields first. A crowd walker or stationary contact has
	# priority; a second resident waits long enough for the first to step aside.
	for other in actors.values():
		if other == actor or other.dead or other.global_position.distance_to(actor.global_position) > 1.6:
			continue
		if str(actor.actor_id) > str(other.actor_id) and actor.blocked_seconds < 3.5:
			return false
	var heading: Vector3 = actor.route_points[actor.route_cursor] - actor.global_position
	heading.y = 0.0
	if heading.length() < 0.01:
		return false
	heading = heading.normalized()
	var across := Vector3(-heading.z, 0.0, heading.x)
	var join_index: int = actor.route_points.size() - 1
	for i in range(actor.route_cursor, actor.route_points.size()):
		if actor.global_position.distance_to(actor.route_points[i]) >= 2.4:
			join_index = i
			break
	var join: Vector3 = actor.route_points[join_index]
	for side in [0.75, -0.75, 1.0, -1.0]:
		var plan: Array[Vector3] = []
		var previous: Vector3 = actor.global_position
		for wanted in [previous + across * side, join + across * side, join]:
			var found := _motion_clear(actor, previous, wanted)
			if found.is_empty():
				plan.clear()
				break
			plan.append(found.position)
			previous = found.position
		if not plan.is_empty():
			actor.begin_recovery(plan, join_index)
			return true
	# If there is no passing space here, turn and retreat to let the other body
	# through. Backward *travel* is never used: the actor turns before stepping.
	for metres in [1.2, 2.0, 3.0]:
		var found := _motion_clear(actor, actor.global_position, actor.global_position - heading * metres)
		if not found.is_empty():
			var backstep: Array[Vector3] = [found.position]
			actor.begin_recovery(backstep, actor.route_cursor, 2.0)
			return true
	return false

func resume_after_combat(actor) -> bool:
	if actor.dead:
		return false
	actor.has_target = false
	actor.recovery_retry = 2.0
	if not routes.has(actor.actor_id):
		return false
	var corridor: Array[Vector3] = routes[actor.actor_id].points
	var indices: Array[int] = []
	for i in corridor.size():
		indices.append(i)
	indices.sort_custom(func(a, b): return actor.global_position.distance_squared_to(corridor[a]) < actor.global_position.distance_squared_to(corridor[b]))
	for index in indices.slice(0, mini(8, indices.size())):
		var target: Vector3 = corridor[index]
		var connector: Array[Vector3] = []
		if actor.global_position.distance_to(target) < 0.16:
			connector.append(target)
		elif not _motion_clear(actor, actor.global_position, target, false).is_empty():
			connector.append(target)
		else:
			var heading: Vector3 = (target - actor.global_position).normalized()
			var across := Vector3(-heading.z, 0.0, heading.x)
			for lateral in [0.8, -0.8, 1.6, -1.6]:
				var bend: Vector3 = actor.global_position + across * lateral
				var first := _motion_clear(actor, actor.global_position, bend, false)
				if not first.is_empty() and not _motion_clear(actor, first.position, target, false).is_empty():
					connector.assign([first.position, target])
					break
		if connector.is_empty():
			continue
		_update_schedule(actor, true)
		# The schedule's nearest point can differ from the reachable connector.
		# Continue along the validated corridor from the selected join point.
		var minute: float = level.world_time.minute_of_day
		var slot := schedule_slot(actor.routine.schedule, minute)
		var destination: int = routes[actor.actor_id].anchors[str(actor.routine.schedule[slot].activity)]
		var direction := 1 if destination >= index else -1
		for i in range(index + direction, destination + direction, direction):
			connector.append(corridor[i])
		actor.assign_route(connector, actor.activity, actor.destination_label)
		return true
	# Return may be obstructed by a person or parked vehicle. Preserve the body
	# at its real position and retry; never restore a stale straight-line target.
	actor.needs_replan = true
	return false

func set_routines_enabled(value: bool) -> void:
	routines_enabled = value
	for actor in actors.values():
		actor.routine_enabled = value
		if not value:
			actor.has_target = false
		else:
			_update_schedule(actor, true)

func get_actor(id: String) -> Node3D:
	return actors.get(id)

func snapshot_state() -> Dictionary:
	var residents: Dictionary = {}
	for id in actors:
		var actor = actors[id]
		residents[id] = {"position": [actor.global_position.x, actor.global_position.y, actor.global_position.z],
			"activity": actor.activity, "route_cursor": actor.route_cursor, "slot": _last_slots.get(id, -1), "yaw": actor.yaw}
	return {"version": STATE_VERSION, "day_index": level.world_time.day_index if level.get("world_time") != null else 0,
		"total_minutes": level.world_time.total_minutes if level.get("world_time") != null else 540.0, "residents": residents}

## Call after corridors have been prepared and the shared clock restored.
## Route cursors are regenerated from physical progress: old route arrays must
## never become straight-line targets through changed scenery.
func restore_state(state: Dictionary) -> Dictionary:
	var restored := 0
	var fallback := 0
	# Version 1 remains append-compatible: restore only saved IDs; new residents
	# retain their safely spawned homes and current schedule. No ordinal migration.
	for id in state.get("residents", {}):
		if not actors.has(id) or not routes.has(id) or actors[id].dead:
			continue
		var actor = actors[id]
		var saved: Dictionary = state.residents[id]
		var point := Vector3(float(saved.position[0]), float(saved.position[1]), float(saved.position[2]))
		var ground: Dictionary = level.ground_at(point)
		var old: Vector3 = actor.global_position
		if not CivicClearance.blocked(level, point, 0.35) and not ground.is_empty() and ground.normal.y >= cos(deg_to_rad(40.0)) and absf(point.y - ground.position.y) < 0.5:
			point.y = ground.position.y + 0.012
			actor.global_position = point
			if not _activation_clear(actor):
				actor.global_position = old
		if actor.global_position.distance_to(point) > 0.1:
			fallback += 1
		else:
			restored += 1
		actor.velocity = Vector3.ZERO
		actor.yaw = float(saved.get("yaw", 0.0))
		actor.puppet.g.rotation.y = actor.yaw
		actor.has_target = false
		actor.recovery_points.clear()
		actor.needs_replan = true
		resume_after_combat(actor)
		actor.physical = _is_near(actor.global_position)
		actor.set_enabled(actor.physical)
		actor.set_distance_fade(_player_distance(actor.global_position))
	return {"restored": restored, "fallback": fallback}

func save_state(path := "user://pen_lucy_residents_v1.json") -> Error:
	# Explicit caller-owned checkpoint; startup never blocks on disk persistence.
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot_state()))
	return OK

func get_status() -> Dictionary:
	var near := 0
	var detail: Dictionary = {}
	for id in actors:
		if actors[id].physical:
			near += 1
		detail[id] = actors[id].get_status()
	return {"count": actors.size(), "expected": definitions.size(), "near": near, "far": actors.size() - near,
		"routines_enabled": routines_enabled, "path_builds": _path_builds, "pending_routes": _build_queue.size(),
		"near_updates": _near_updates, "far_updates": _far_updates, "last_tick_usec": _last_tick_usec,
		"max_tick_usec": _max_tick_usec, "placement_failures": placement_failures.duplicate(),
		"activation_waits": _activation_waits, "logical_waits": _logical_waits,
		"route_failures": route_failures.duplicate(), "actors": detail}
