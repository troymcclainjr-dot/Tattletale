extends RefCounted
## Release points at the civic plan's real hospital and precinct. Candidates come
## first from the built model (hospital PublicEntrance marker, precinct approach
## metadata), then from the plan's graded entry approach, then a small ring. Each
## candidate must stand on a walkable top surface near its planned height with a
## clear player-sized capsule (buildings, people, vehicles). Nobody is moved into
## collision; with no clear candidate the caller keeps the player where they are.
const PLAYER_RADIUS := 0.30
const PLAYER_HEIGHT := 1.72
const PLAYER_CENTER := 0.87
const CLEARANCE := 0.05
const BODY_MASK := 2 | 8 | 16
const GROUND_MASK := 1 | 2
const MAX_CANDIDATES := 40
const MAX_RISE := 0.75
const NAMES := {"hospital": "the hospital", "police": "the police station"}

static func _vec(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

static func _flat_normal(value: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO

static func site(level: Node, id: String) -> Dictionary:
	var civic = level.get("civic_district") if is_instance_valid(level) else null
	if civic == null:
		return {}
	var sites = civic.get("sites")
	if not sites is Array:
		return {}
	for entry in sites:
		if entry is Dictionary and str(entry.get("id", "")) == id:
			return entry
	return {}

static func model(level: Node, id: String) -> Node3D:
	var civic = level.get("civic_district") if is_instance_valid(level) else null
	if not civic is Node:
		return null
	for child in civic.get_children():
		if child is Node3D and str(child.get_meta("civic_id", "")) == id:
			return child
	return null

## Ordered candidate points plus the facing (away from the building, to the street).
static func candidates(level: Node, id: String) -> Dictionary:
	var points: Array[Vector3] = []
	var front := Vector3.ZERO
	var plan := site(level, id)
	var built := model(level, id)
	if built != null:
		var anchor := Vector3.INF
		var direction := Vector3.ZERO
		# The hospital entrance sits under its canopy; the precinct walk is ~4 m long.
		var distances := [3.0, 5.0, 7.0, 9.0]
		if id == "hospital":
			var marker := built.get_node_or_null("PublicEntrance") as Node3D
			if marker != null:
				anchor = marker.global_position
				direction = _flat_normal(built.global_basis * Vector3(marker.get_meta("approach_local", Vector3.BACK)))
		elif built.has_meta("approach"):
			anchor = built.to_global(Vector3(built.get_meta("approach")))
			direction = _flat_normal(built.global_basis * Vector3(built.get_meta("front_normal", Vector3.BACK)))
			distances = [2.5, 4.0, 5.0]
		if anchor.is_finite() and direction != Vector3.ZERO:
			front = direction
			var across := Vector3(-direction.z, 0.0, direction.x)
			for distance in distances:
				for side in [0.0, 1.6, -1.6]:
					points.append(anchor + direction * float(distance) + across * float(side))
	if not plan.is_empty():
		var entry := _vec(plan.get("entry_world", plan.get("position", [0, 0, 0])))
		var approach := _vec(plan.get("approach_center", plan.get("entry_world", plan.get("position", [0, 0, 0]))))
		var direction := _flat_normal(_vec(plan.get("front_vector", [0, 0, 0])))
		if direction == Vector3.ZERO and entry.is_finite() and approach.is_finite():
			direction = _flat_normal(approach - entry)
		if front == Vector3.ZERO:
			front = direction
		if entry.is_finite() and approach.is_finite():
			var across := Vector3(-direction.z, 0.0, direction.x)
			for t in [1.0, 0.75, 0.5]:
				var base := entry.lerp(approach, float(t))
				for side in [0.0, 1.5, -1.5]:
					points.append(base + across * float(side))
			for distance in [1.5, 3.0]:
				points.append(approach + direction * float(distance))
			for radius in [2.5, 4.0]:
				for step in 8:
					var angle := TAU * float(step) / 8.0
					points.append(approach + Vector3(cos(angle), 0.0, sin(angle)) * float(radius))
	var label := str(plan.get("name", NAMES.get(id, id)))
	return {"points": points, "front": front if front != Vector3.ZERO else Vector3.BACK, "name": label, "planned": not plan.is_empty() or built != null}

## Ground and clearance for one standing spot, or {} when unsafe.
static func standing_at(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array[RID]) -> Dictionary:
	if space == null or not point.is_finite():
		return {}
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.2, point - Vector3.UP * 3.0, GROUND_MASK)
	ray.exclude = exclude
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or Vector3(hit.normal).y < 0.8 or absf(Vector3(hit.position).y - point.y) > MAX_RISE:
		return {}
	var foot: Vector3 = hit.position
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS + 0.04
	capsule.height = PLAYER_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * (PLAYER_CENTER + CLEARANCE + 0.01))
	query.collision_mask = BODY_MASK
	query.exclude = exclude
	query.margin = 0.02
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": foot + Vector3.UP * CLEARANCE}

## {"ok", "position", "yaw", "name", "site", "checks", "fallback"}.
static func release_point(level: Node, id: String, player: Node3D = null) -> Dictionary:
	var info := candidates(level, id)
	var points: Array = info.points
	var fallback := false
	if points.is_empty():
		# No civic district (fixture or --no-civic-district): use the walk's start.
		fallback = true
		var data = level.get("level_data") if is_instance_valid(level) else null
		var spawn := _vec(data.get("spawn", {}).get("position", null)) if data is Dictionary else Vector3.INF
		if spawn.is_finite():
			points.append(spawn)
			for step in 8:
				var angle := TAU * float(step) / 8.0
				points.append(spawn + Vector3(cos(angle), 0.0, sin(angle)) * 2.0)
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var space: PhysicsDirectSpaceState3D = null
	if level is Node3D and (level as Node3D).get_world_3d() != null:
		space = (level as Node3D).get_world_3d().direct_space_state
	var front: Vector3 = info.front
	var checks := 0
	for point in points:
		if checks >= MAX_CANDIDATES:
			break
		checks += 1
		var standing := standing_at(space, Vector3(point), exclude)
		if not standing.is_empty():
			return {"ok": true, "position": standing.position, "yaw": atan2(front.x, front.z), "name": str(info.name),
				"site": id, "checks": checks, "fallback": fallback}
	return {"ok": false, "position": Vector3.INF, "yaw": atan2(front.x, front.z), "name": str(info.name), "site": id,
		"checks": checks, "fallback": fallback}
