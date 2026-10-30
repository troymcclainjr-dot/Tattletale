extends Node3D
## Shared curbside vehicles distributed across the exported road network.
## Placement is validated once while terrain/city collision meshes are present.
## Presence changes only activate/deactivate retained data; never resample terrain.

const Models := preload("res://scripts/city/city_car_models.gd")
const MAX_CARS := 96
const PARKING_SIZE := Vector3(2.12, 2.05, 4.70)
const CENTER := Vector3(0, 1.05, 0)
var level: Node3D
var traffic: Node3D
var records: Array[Dictionary] = []
var _batches: Dictionary = {}
var _counts: Dictionary = {}
var _rejects: Dictionary = {}
var _spinner_batch: MultiMeshInstance3D
var _spinner_records: Array[int] = []
var _spinner_time := 0.0
var _spinner_tick := 0.0
var _presence_center := Vector3.ZERO
var _near_distance := 55.0
var _far_distance := 180.0
var _active_near := 0
var _active_far := 0
var _attempts := 0

func setup(owner_level: Node3D, owner_traffic: Node3D) -> void:
	level = owner_level
	traffic = owner_traffic
	name = "ParkedNeighborhoodCars"
	var pools: Dictionary = {}
	var road_ordinal := 0
	for road in level.level_data.get("roads", []):
		var street := str(road.get("name", ""))
		var points: Array = road.get("points", [])
		if points.size() < 2 or street.is_empty() or float(road.get("width", 0.0)) < 8.0:
			continue
		# The existing two moving Old York lanes need their entire clearance width.
		# Other streets supply parking rather than squeezing cars into those lanes.
		if street == "Old York Road":
			continue
		if not pools.has(street):
			pools[street] = []
		var distance := 0.0
		var target := 18.0 + float(road_ordinal % 3) * 5.0
		var ordinal := 0
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			while target <= distance + length:
				var center := a.lerp(b, (target - distance) / maxf(length, 0.001))
				var forward := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var side := 1.0 if (ordinal + road_ordinal) % 2 == 0 else -1.0
				var right := forward.cross(Vector3.UP)
				var at := center + right * side * (float(road.width) * 0.5 - PARKING_SIZE.x * 0.5 - 0.22)
				# Park facing the legal direction for its curb (US right-hand traffic).
				pools[street].append({"at": at, "forward": forward * side, "curb": right * side,
					"center": center, "width": float(road.width), "street": street})
				target += 26.0
				ordinal += 1
			distance += length
		road_ordinal += 1
	# Round robin keeps the cap from filling on the first two long roads.
	var streets: Array = pools.keys()
	streets.sort()
	var round_index := 0
	var pending := true
	while pending and records.size() < MAX_CARS:
		pending = false
		for street in streets:
			if round_index >= pools[street].size():
				continue
			pending = true
			_attempts += 1
			var candidate: Dictionary = pools[street][round_index]
			var validated := _validate(candidate)
			if validated.is_empty():
				continue
			var index := records.size()
			var kind := str(Models.KINDS[index % Models.KINDS.size()])
			var body := StaticBody3D.new()
			body.name = "ParkedCar_%03d" % index
			body.collision_layer = 0
			body.collision_mask = 0
			var collider := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = PARKING_SIZE
			collider.shape = box
			collider.position = CENTER
			body.add_child(collider)
			add_child(body)
			body.global_transform = validated.pose
			body.set_meta("parked_vehicle", true)
			records.append({"pose": validated.pose, "kind": kind, "paint": index % Models.PALETTE.size(),
				"street": street, "body": body, "presence": -1, "curb_checked": true})
			_counts[street] = int(_counts.get(street, 0)) + 1
			if records.size() >= MAX_CARS:
				break
		round_index += 1
	_build_batches()
	set_presence(level.player.global_position if is_instance_valid(level.player) else Vector3.ZERO, 55, 180)

func _reject(reason: String) -> Dictionary:
	_rejects[reason] = int(_rejects.get(reason, 0)) + 1
	return {}

func _ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP * 2.5, 1)
	ray.hit_back_faces = false
	return level.get_world_3d().direct_space_state.intersect_ray(ray)

func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var flat := Vector2(point.x, point.z)
	return Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(flat)

func _validate(candidate: Dictionary) -> Dictionary:
	var at: Vector3 = candidate.at
	var forward: Vector3 = candidate.forward
	var right := Vector3(forward.z, 0, -forward.x)
	var vegetation = level.get("vegetation")
	if is_instance_valid(vegetation) and vegetation.has_method("is_trunk_clear"):
		if not vegetation.is_trunk_clear(at, 2.7):
			return _reject("tree_trunk")
	# Keep clear sight/turning space wherever another exported road approaches,
	# including branches that join in the middle of a long polyline.
	for road in level.level_data.get("roads", []):
		if str(road.get("name", "")) == str(candidate.street):
			continue
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			if _segment_distance(at, level.vector(points[i - 1]), level.vector(points[i])) < float(road.width) * 0.5 + 7.5:
				return _reject("junction")
	var route: Array = level.level_data.get("route", {}).get("points", [])
	for i in range(1, route.size()):
		if _segment_distance(at, level.vector(route[i - 1]), level.vector(route[i])) < 3.5:
			return _reject("walk_route")
	for record in records:
		var existing: Transform3D = record.pose
		if Vector2(at.x - existing.origin.x, at.z - existing.origin.z).length() < 7.0:
			return _reject("other_parked_car")
	var heights: Array[float] = []
	for offset in [Vector3.ZERO, forward * 1.4, -forward * 1.4, right * 0.78, -right * 0.78]:
		var hit := _ground(at + offset)
		if hit.is_empty() or hit.normal.y < 0.90:
			return _reject("ground")
		heights.append(float(hit.position.y))
	# Reject curb cuts/gaps rather than guessing which facade is a driveway.
	# Both ends need a continuous raised sidewalk outside the asphalt edge.
	for offset in [-1.8, 0.0, 1.8]:
		var cross_section: Vector3 = candidate.center + forward * float(offset)
		var curb: Vector3 = candidate.curb
		var inside := _ground(cross_section + curb * (float(candidate.width) * 0.5 - 0.32))
		var outside := _ground(cross_section + curb * (float(candidate.width) * 0.5 + 0.32))
		if inside.is_empty() or outside.is_empty():
			return _reject("curb_gap")
		var rise: float = outside.position.y - inside.position.y
		if rise < 0.055 or rise > 0.32:
			return _reject("driveway_or_curb_cut")
	forward.y = (heights[1] - heights[2]) / 2.8
	right = Vector3(forward.z, 0, -forward.x)
	right.y = (heights[3] - heights[4]) / 1.56
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	at.y = (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025
	var pose := Transform3D(Basis(right, up, forward), at)
	var shape := BoxShape3D.new()
	shape.size = PARKING_SIZE + Vector3(0.20, 0, 0.20)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose * Transform3D(Basis.IDENTITY, CENTER)
	query.collision_mask = 2 | 4 | 8 | 16
	if not level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return _reject("occupied")
	return {"pose": pose}

func _build_batches() -> void:
	for kind in Models.KINDS:
		var matching: Array[int] = []
		for i in records.size():
			if str(records[i].kind) == kind:
				matching.append(i)
		if matching.is_empty():
			continue
		var data := Models.prototype(kind)
		for detail in ["near", "far"]:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = data.parked if detail == "near" else data.far_parked
			multi.instance_count = matching.size()
			multi.visible_instance_count = 0
			var node := MultiMeshInstance3D.new()
			node.name = kind + "_" + detail
			node.multimesh = multi
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if detail == "near" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_batches[kind + "_" + detail] = node
			for slot in matching.size():
				var record: Dictionary = records[matching[slot]]
				record["slot"] = slot
				multi.set_instance_color(slot, Models.paint_color(int(record.paint)))
	var spinner_data := Models.prototype("box_sedan")
	var spinners := MultiMesh.new()
	spinners.transform_format = MultiMesh.TRANSFORM_3D
	spinners.mesh = spinner_data.spinner
	spinners.instance_count = 24 # Six nearby parked cars, four hubs each.
	spinners.visible_instance_count = 0
	_spinner_batch = MultiMeshInstance3D.new()
	_spinner_batch.name = "NearbyFreeSpinningHubs"
	_spinner_batch.multimesh = spinners
	_spinner_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spinner_batch)

func set_presence(center: Vector3, near_distance := 55.0, far_distance := 180.0) -> void:
	_presence_center = center
	_near_distance = near_distance
	_far_distance = far_distance
	_active_near = 0
	_active_far = 0
	_spinner_records.clear()
	var spinner_candidates: Array[int] = []
	var visible_counts: Dictionary = {}
	for i in records.size():
		var record: Dictionary = records[i]
		var pose: Transform3D = record.pose
		var distance := pose.origin.distance_to(center)
		var presence := 2 if distance <= near_distance else (1 if distance <= far_distance else 0)
		if presence == 2:
			_active_near += 1
		elif presence == 1:
			_active_far += 1
		if int(record.presence) != presence:
			var body: StaticBody3D = record.body
			body.collision_layer = 2 if presence == 2 else 0
			record.presence = presence
		if presence > 0:
			# Compact active transforms into the drawn prefix. Distant data remains
			# in records, but does not submit zero-scale cars or spend vertex work.
			var key := str(record.kind) + ("_near" if presence == 2 else "_far")
			var slot: int = int(visible_counts.get(key, 0))
			var batch: MultiMeshInstance3D = _batches[key]
			batch.multimesh.set_instance_transform(slot, pose)
			batch.multimesh.set_instance_color(slot, Models.paint_color(int(record.paint)))
			visible_counts[key] = slot + 1
		if str(record.kind) == "box_sedan" and distance < 40.0:
			spinner_candidates.append(i)
	for key in _batches:
		var batch: MultiMeshInstance3D = _batches[key]
		batch.multimesh.visible_instance_count = int(visible_counts.get(key, 0))
	spinner_candidates.sort_custom(func(a: int, b: int) -> bool:
		var pose_a: Transform3D = records[a].pose
		var pose_b: Transform3D = records[b].pose
		return pose_a.origin.distance_squared_to(center) < pose_b.origin.distance_squared_to(center))
	for i in mini(6, spinner_candidates.size()):
		_spinner_records.append(spinner_candidates[i])
	if _spinner_batch:
		_spinner_batch.multimesh.visible_instance_count = _spinner_records.size() * 4
		_update_spinners()

func tick(dt: float) -> void:
	_spinner_time += maxf(dt, 0)
	_spinner_tick += maxf(dt, 0)
	if _spinner_tick < 0.05:
		return
	_spinner_tick = 0
	_update_spinners()

func _update_spinners() -> void:
	if _spinner_batch == null:
		return
	var data := Models.prototype("box_sedan")
	for i in _spinner_records.size():
		var record: Dictionary = records[_spinner_records[i]]
		var car_pose: Transform3D = record.pose
		for wheel in 4:
			var pose: Transform3D = data.wheel_poses[wheel]
			pose.origin.x += signf(pose.origin.x) * 0.12
			pose.basis = Basis(Vector3.RIGHT, fposmod(_spinner_time * 2.7 + float(_spinner_records[i]) * 0.4, TAU))
			_spinner_batch.multimesh.set_instance_transform(i * 4 + wheel, car_pose * pose)

func get_status() -> Dictionary:
	return {"total": records.size(), "streets": _counts.duplicate(), "street_count": _counts.size(),
		"attempts": _attempts, "rejected": _rejects.duplicate(), "draw_batches": _batches.size() + 1,
		"near": _active_near, "far": _active_far, "hidden": records.size() - _active_near - _active_far,
		"active_colliders": _active_near, "animated_spinner_cars": _spinner_records.size(),
		"presence_radius": _near_distance, "far_radius": _far_distance}
