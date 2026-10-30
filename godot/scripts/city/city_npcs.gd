extends Node3D
## Neighborhood residents are independent of the original block's G simulation.
## Call setup after terrain physics is registered; tick only during unpaused physics.

const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Crowd := preload("res://scripts/city/city_crowd.gd")
var crowd: Node3D
var level: Node3D
var actors: Dictionary = {}
var placement_failures: Array[String] = []
var _route: Array[Vector3] = []
var _elapsed := 0.0
var _street_grid: Dictionary = {}
var _street_segments: Array[Dictionary] = []
var _candidate_shapes: Dictionary = {}
var _stair_grid: Dictionary = {}

func setup(owner_level: Node3D) -> void:
	if not actors.is_empty():
		return
	level = owner_level
	name = "NeighborhoodPeople"
	_index_streets()
	var route: Dictionary = level.level_data.get("route", {})
	for point in route.get("points", []):
		_route.append(level.vector(point))
	var first := _landmark("old_york_wyanoke", _route_point(18.0))
	var witness := _landmark("old_york_dumbarton", _route_point(100.0))
	_spawn("resident", "mama", "Ms. Lena · Resident", first, false)
	_spawn("lookout", "ricky", "Malik · Witness", witness, false)
	_spawn("officer", "cop_dan", "Officer Dan", first + Vector3(0, 0, 16), false)
	_spawn("ambient_mailman", "mailman", "Mail carrier", _route_point(52.0), true)
	_spawn("ambient_granny", "granny", "Neighbor", _route_point(135.0), true)
	_spawn("ambient_neighbor", "liner_2", "Neighbor", _route_point(178.0), true)
	_spawn("gardener", "granny", "Community gardener", _route_point(70.0), false)
	_spawn("organizer", "liner_2", "Block organizer", _route_point(123.0), false)
	_spawn("caretaker", "mailman", "Porch caretaker", _route_point(192.0), false)
	var patrol_count := 0
	var patrol_streets: Dictionary = {}
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		var street: String = str(road.get("name", ""))
		if points.size() < 8 or patrol_streets.has(street):
			continue
		var middle := points.size() / 2
		var point: Vector3 = level.vector(points[middle])
		var heading: Vector3 = (level.vector(points[middle + 1]) - level.vector(points[middle - 1])).normalized()
		var across := Vector3(-heading.z, 0, heading.x)
		var id := "patrol_officer_%d" % patrol_count
		_spawn(id, "cop_dan" if patrol_count % 2 == 0 else "cop_steve", "Patrol officer", point + across * (float(road.get("width", 9.5)) * 0.5 + 1.2), true)
		if actors.has(id):
			# A clear standing spot alone is not a patrol. Try the next street if
			# this block's stairs/contacts leave no safe walking corridor.
			if actors[id].patrol_points.size() < 2:
				actors[id].queue_free()
				actors.erase(id)
				placement_failures.erase(id + ":patrol")
				continue
			patrol_streets[street] = true
			patrol_count += 1
		if patrol_count >= 6:
			break
	crowd = Crowd.new()
	add_child(crowd)
	crowd.setup(level, self)

func tick(delta: float) -> void:
	_elapsed += delta
	for actor in actors.values():
		actor.tick(delta)
	if crowd != null:
		crowd.tick(delta)

func get_actor(id: String) -> Node3D:
	return actors.get(id)

func get_actor_position(id: String) -> Vector3:
	var actor: Node3D = get_actor(id)
	return actor.global_position if actor != null else Vector3.INF

func actor_position(id: String) -> Vector3:
	return get_actor_position(id)

func actor_rid(id: String) -> RID:
	var actor = get_actor(id)
	return actor.get_rid() if actor != null else RID()

func set_actor_enabled(id: String, enabled: bool) -> void:
	var actor = get_actor(id)
	if actor != null:
		actor.set_enabled(enabled)

func set_actor_target(id: String, target: Vector3) -> bool:
	var actor = get_actor(id)
	if actor == null:
		return false
	actor.set_target(target)
	return true

func speak(id: String, text: String, duration := 4.0) -> void:
	var actor = get_actor(id)
	if actor != null:
		actor.speak(text, duration)

func get_status() -> Dictionary:
	var details: Dictionary = {}
	var moving_count := 0
	for id in actors:
		details[id] = actors[id].get_status()
		if actors[id].moving:
			moving_count += 1
	var crowd_status: Dictionary = crowd.get_status() if crowd != null else {}
	var patrolling := 0
	for id in actors:
		if str(id).begins_with("patrol_officer_") and actors[id].patrol_points.size() >= 2:
			patrolling += 1
	return {"count": actors.size() + int(crowd_status.get("total", 0)), "physical_actors": actors.size(), "foot_patrols": patrolling, "crowd": crowd_status, "moving": moving_count, "elapsed": _elapsed, "actors": details, "placement_failures": placement_failures.duplicate()}

func _spawn(id: String, character: String, label: String, desired: Vector3, walking: bool) -> void:
	var found := find_safe_position(desired, 0.28)
	if not found.ok and walking:
		# Some northern porch fronts fill the entire spare sidewalk strip.
		# Use another surveyed stretch instead of weakening physical clearance.
		for metres in [75.0, 24.0, 205.0, 110.0]:
			found = find_safe_position(_route_point(float(metres)), 0.28)
			if found.ok:
				break
	if not found.ok:
		placement_failures.append(id)
		push_warning("No clear sidewalk position for neighborhood actor: " + id)
		return
	var actor := Actor.new()
	add_child(actor)
	actor.build(level, id, character, label)
	actor.global_position = found.position
	actor.yaw = PI * 0.5
	actor.puppet.g.rotation.y = actor.yaw
	actors[id] = actor
	if walking:
		var tangent: Vector3 = _street_info(actor.global_position).get("tangent", Vector3.FORWARD)
		var patrol: Array[Vector3] = []
		for sign_ in [-1.0, 1.0]:
			var distance := 9.0 if id.begins_with("patrol_officer_") else 4.5
			var end: Vector3 = actor.global_position + tangent * float(sign_) * distance
			if _clear_patrol(actor, actor.global_position, end):
				var hit: Dictionary = level.ground_at(end)
				patrol.append(Vector3(end.x, hit.position.y + 0.012, end.z))
		if patrol.size() == 1:
			patrol.append(actor.global_position)
		if patrol.size() >= 2:
			actor.set_patrol(patrol)
		else:
			placement_failures.append(id + ":patrol")

func find_safe_position(desired: Vector3, radius := 0.45) -> Dictionary:
	if level == null:
		return {"ok": false, "position": desired}
	var tangent: Vector3 = _street_info(desired).get("tangent", Vector3.FORWARD)
	var across := Vector3(-tangent.z, 0, tangent.x)
	for along in [0.0, 3.0, -3.0, 6.0, -6.0, 10.0, -10.0, 16.0, -16.0, 24.0, -24.0]:
		for side in [0.0, 1.0, -1.0, 1.8, -1.8, 3.0, -3.0]:
			var point: Vector3 = desired + tangent * float(along) + across * float(side)
			var grounded := _safe_candidate(point, radius)
			if not grounded.is_empty():
				return {"ok": true, "position": grounded.position}
	return {"ok": false, "position": desired}

func _safe_candidate(point: Vector3, radius: float, exclude: Array[RID] = []) -> Dictionary:
	if not stair_approach_clear(point, radius + 0.65):
		return {}
	if level.vegetation != null and level.vegetation.has_method("is_trunk_clear") and not level.vegetation.is_trunk_clear(point, radius + 0.1):
		return {}
	var street := _street_info(point)
	var distance: float = street.get("distance", INF)
	var half_width: float = float(street.get("width", 9.5)) * 0.5
	var sidewalk: float = street.get("sidewalk", 2.4)
	if distance < half_width + radius + 0.12 or distance > half_width + sidewalk - radius:
		return {}
	if _route_distance(point) < radius + 0.55:
		return {}
	var spawn: Vector3 = level.vector(level.level_data.get("spawn", {}).get("position", [0, 0, 0]))
	if Vector2(point.x - spawn.x, point.z - spawn.z).length() < 5.0:
		return {}
	for actor in actors.values():
		if actor.get_rid() in exclude:
			continue
		if Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z).length() < radius + 1.0:
			return {}
		for i in range(1, actor.patrol_points.size()):
			var a: Vector3 = actor.patrol_points[i - 1]
			var b: Vector3 = actor.patrol_points[i]
			if Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(Vector2(point.x, point.z)) < radius + 0.65:
				return {}
	for mark in level.landmarks:
		var position_: Vector3 = level.vector(mark.get("position"))
		if Vector2(point.x - position_.x, point.z - position_.z).length() < 2.1:
			return {}
	var ground: Dictionary = level.ground_at(point)
	if ground.is_empty() or ground.normal.y < cos(deg_to_rad(42.0)):
		return {}
	point.y = ground.position.y + 0.012
	if not _candidate_shapes.has(radius):
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(1.85, radius * 2.0)
		_candidate_shapes[radius] = capsule
	var shape: CapsuleShape3D = _candidate_shapes[radius]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (shape.height * 0.5 + 0.08))
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = exclude
	query.margin = 0.08
	if not get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty():
		return {}
	return {"position": point}

func _clear_patrol(actor, start: Vector3, finish: Vector3) -> bool:
	var samples := ceili(start.distance_to(finish) / 0.5)
	for i in range(1, samples + 1):
		var point := start.lerp(finish, float(i) / samples)
		if _safe_candidate(point, 0.28, [actor.get_rid()]).is_empty():
			return false
	return true

func _landmark(id: String, fallback: Vector3) -> Vector3:
	for mark in level.level_data.get("landmarks", []):
		if str(mark.get("id", "")) == id:
			return level.vector(mark.get("position"))
	return fallback

func _route_point(metres: float) -> Vector3:
	for i in range(1, _route.size()):
		var length := _route[i - 1].distance_to(_route[i])
		if metres <= length:
			return _route[i - 1].lerp(_route[i], metres / maxf(length, 0.001))
		metres -= length
	return _route.back() if not _route.is_empty() else Vector3.ZERO

func _route_distance(point: Vector3) -> float:
	var result := INF
	for i in range(1, _route.size()):
		var a := Vector2(_route[i - 1].x, _route[i - 1].z)
		var b := Vector2(_route[i].x, _route[i].z)
		result = minf(result, Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), a, b).distance_to(Vector2(point.x, point.z)))
	return result

func _street_info(point: Vector3) -> Dictionary:
	var best := INF
	var info: Dictionary = {}
	var flat := Vector2(point.x, point.z)
	var key := Vector2i(floori(point.x / 32.0), floori(point.z / 32.0))
	var candidates: Array = _street_grid.get(key, _street_segments)
	for segment in candidates:
		var nearest := Geometry2D.get_closest_point_to_segment(flat, segment.a, segment.b)
		var distance := nearest.distance_to(flat)
		if distance < best:
			best = distance
			info = {"distance": distance, "width": segment.width, "sidewalk": segment.sidewalk, "tangent": segment.tangent}
	return info

func _index_streets() -> void:
	for stair in level.level_data.get("porch_stairs", []):
		var a: Vector3 = level.vector(stair.approach)
		var b: Vector3 = level.vector(stair.landing) - level.vector(stair.normal) * 0.45
		var corridor := {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z)}
		var area := Rect2(corridor.a, Vector2.ZERO).expand(corridor.b).grow(2.0)
		for x in range(floori(area.position.x / 16.0), floori(area.end.x / 16.0) + 1):
			for z in range(floori(area.position.y / 16.0), floori(area.end.y / 16.0) + 1):
				var key := Vector2i(x, z)
				if not _stair_grid.has(key):
					_stair_grid[key] = []
				_stair_grid[key].append(corridor)
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var segment := {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "width": float(road.get("width", 9.5)), "sidewalk": float(road.get("sidewalk_width", 2.4)), "tangent": Vector3(b.x - a.x, 0, b.z - a.z).normalized()}
			_street_segments.append(segment)
			var bounds := Rect2(segment.a, Vector2.ZERO).expand(segment.b).grow(32.0)
			for x in range(floori(bounds.position.x / 32.0), floori(bounds.end.x / 32.0) + 1):
				for z in range(floori(bounds.position.y / 32.0), floori(bounds.end.y / 32.0) + 1):
					var key := Vector2i(x, z)
					if not _street_grid.has(key):
						_street_grid[key] = []
					_street_grid[key].append(segment)

func stair_approach_clear(point: Vector3, radius := 0.9) -> bool:
	var flat := Vector2(point.x, point.z)
	var key := Vector2i(floori(point.x / 16.0), floori(point.z / 16.0))
	for corridor in _stair_grid.get(key, []):
		if Geometry2D.get_closest_point_to_segment(flat, corridor.a, corridor.b).distance_to(flat) < radius:
			return false
	return true
