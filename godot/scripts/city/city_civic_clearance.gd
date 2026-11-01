extends RefCounted
## Shared reservation check for authored civic construction and provider records.
## The district owns the polygons; providers retain their existing lifetime/cache.

static func district(level: Node):
	return level.get("civic_district") if is_instance_valid(level) else null

static func blocked(level: Node, at: Vector3, radius := 0.0) -> bool:
	var civic = district(level)
	if civic == null or not civic.has_method("is_cleared"):
		return false
	if civic.is_cleared(at):
		return true
	if radius > 0.0:
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			if civic.is_cleared(at + direction * radius):
				return true
	return false

static func segment_blocked(level: Node, start: Vector3, finish: Vector3, radius := 0.0) -> bool:
	if district(level) == null:
		return false
	var steps := maxi(1, ceili(Vector2(finish.x - start.x, finish.z - start.z).length() / 1.5))
	for index in range(steps + 1):
		if blocked(level, start.lerp(finish, float(index) / steps), radius):
			return true
	return false

static func removed_home(level: Node, building_id := "", source_mesh := "") -> bool:
	var civic = district(level)
	if civic == null:
		return false
	var ids = civic.get("removed_building_ids")
	var meshes = civic.get("removed_meshes")
	return (not building_id.is_empty() and ids != null and ids.has(building_id)) or (not source_mesh.is_empty() and meshes != null and meshes.has(source_mesh))

static func record_removed(level: Node, record: Dictionary, radius := 0.0) -> bool:
	if removed_home(level, str(record.get("building_id", "")), str(record.get("source_mesh", record.get("source", "")))):
		return true
	var value = record.get("position", record.get("door_position", null))
	if value is Vector3:
		return blocked(level, value, radius)
	if value is Array and value.size() >= 3:
		return blocked(level, Vector3(float(value[0]), float(value[1]), float(value[2])), radius)
	return false

static func sidewalk_relocation(level: Node3D, npcs: Node3D, desired: Vector3, radius := 0.30, reserved: Array[Vector3] = []) -> Dictionary:
	# Rare setup/restore fallback. Existing identity/index is retained by caller.
	# All returned points pass the same terrain/capsule/street validation as NPCs.
	var candidates: Array[Dictionary] = []
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			if tangent.is_zero_approx():
				continue
			var closest := Geometry2D.get_closest_point_to_segment(Vector2(desired.x, desired.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var center := Vector3(closest.x, a.y, closest.y)
			var across := Vector3(-tangent.z, 0, tangent.x)
			for side in [-1.0, 1.0]:
				var wanted: Vector3 = center + across * side * (float(road.get("width", 9.5)) * 0.5 + 1.2)
				if not blocked(level, wanted, radius):
					candidates.append({"point": wanted, "distance": wanted.distance_squared_to(desired)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for candidate in candidates:
		var occupied := false
		var wanted: Vector3 = candidate.point
		for anchor in reserved:
			if Vector2(wanted.x - anchor.x, wanted.z - anchor.z).length_squared() < 1.0:
				occupied = true
				break
		if occupied:
			continue
		var found: Dictionary = npcs._safe_candidate(candidate.point, radius)
		if not found.is_empty():
			return found
	return {}
