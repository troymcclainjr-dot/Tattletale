extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Shared curbside vehicles distributed across the exported road network.
## Placement is validated once while terrain/city collision meshes are present.
## Presence changes only activate/deactivate retained data; never resample terrain.

const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Damage := preload("res://scripts/city/city_vehicle_damage.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const BASELINE_CARS := 144
const MAX_CARS := 216
const CANDIDATE_SPACING := 8.0
const PARKING_SIZE := Vector3(2.12, 2.05, 4.70)
const CENTER := Vector3(0, 1.05, 0)
# Batch records name wheels in prototype order; city_vehicle bodies use
# [FL, FR, RL, RR]. Promotion and persistence convert by wheel name.
const PARKED_WHEELS := ["WheelFL", "WheelRL", "WheelFR", "WheelRR"]
const VEHICLE_WHEELS := ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
const MAX_HEALTH := 100.0
const SHOT_BODY_DAMAGE := 2.5
const SOURCE_MATCH_DISTANCE := 0.75
const MAX_DAMAGE_RECORDS := 64
var level: Node3D
var traffic: Node3D
var records: Array[Dictionary] = []
var _batches: Dictionary = {}
var _counts: Dictionary = {}
var _rejects: Dictionary = {}
var _spinner_batch: MultiMeshInstance3D
var _spinner_records: Array[int] = []
var _presence_center := Vector3.ZERO
var _near_distance := 55.0
var _far_distance := 180.0
var _active_near := 0
var _active_far := 0
var _attempts := 0
var _external_points := PackedVector3Array()
var _external_radius := 40.0

func setup(owner_level: Node3D, owner_traffic: Node3D) -> void:
	level = owner_level
	traffic = owner_traffic
	name = "ParkedNeighborhoodCars"
	var pools: Dictionary = {}
	var road_ordinal := 0
	for road in level.level_data.get("roads", []):
		var street := str(road.get("name", ""))
		var points: Array = road.get("points", [])
		var mode := Network.parking_mode(float(road.get("width", 0.0)), street)
		if points.size() < 2 or street.is_empty() or mode == "none":
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
				# A consistent curb for the whole narrow road, shared with lane offsets.
				var side := 1.0 if mode == "single" or (ordinal + road_ordinal) % 2 == 0 else -1.0
				var right := forward.cross(Vector3.UP)
				var at := center + right * side * (float(road.width) * 0.5 - PARKING_SIZE.x * 0.5 - 0.22)
				# Park facing the legal direction for its curb (US right-hand traffic).
				pools[street].append({"at": at, "forward": forward * side, "curb": right * side,
					"center": center, "width": float(road.width), "street": street,
					"parking_mode": mode, "parking_side": side, "road_index": road_ordinal})
				# Eight metres leaves at least 3.3m bumper space on a single curb.
				# All intersection, curb-cut, ground and overlap checks still apply.
				target += CANDIDATE_SPACING
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
			var kind := Catalog.parked_kind(index)
			var body := StaticBody3D.new()
			body.name = "ParkedCar_%03d" % index
			body.collision_layer = 0
			body.collision_mask = 0
			Collision.attach(body, kind)
			add_child(body)
			body.global_transform = validated.pose
			body.set_meta("parked_vehicle", true)
			body.set_meta("parked_index", index)
			var origin: Vector3 = validated.pose.origin
			# Stable identity for promotion/persistence: same level data, same id;
			# the fingerprint detects geometry changes that reorder records.
			records.append({"pose": validated.pose, "kind": kind, "paint": index % Models.PALETTE.size(),
				"street": street, "body": body, "presence": -1, "curb_checked": true, "flat_tires": [],
				"parking_mode": candidate.parking_mode, "parking_side": candidate.parking_side,
				"road_index": candidate.road_index, "road_width": candidate.width,
				"source_id": "parked_%03d" % index, "health": MAX_HEALTH, "promoted": "",
				"source_key": {"street": street, "kind": kind,
					"origin": [snappedf(origin.x, 0.001), snappedf(origin.y, 0.001), snappedf(origin.z, 0.001)]}})
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
	if CivicClearance.parking_blocked(level, at, 2.5):
		return _reject("civic_approach")
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
	# Curved lane centerlines must retain the same clearance as straight roads.
	# Keep both 2.12m vehicle envelopes plus a 0.20m lateral gap unoccupied.
	if is_instance_valid(traffic) and traffic.get("network") != null:
		for lane in traffic.network.lanes:
			if not bool(lane.enabled) or str(lane.street) != str(candidate.street):
				continue
			var path: Array[Vector3] = lane.points
			for i in range(1, path.size()):
				if _segment_distance(at, path[i - 1], path[i]) < 2.32:
					return _reject("moving_lane_clearance")
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
	for kind in Models.ALL_KINDS:
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
	_spinner_batch.name = "NearbyStationaryHubs"
	_spinner_batch.multimesh = spinners
	_spinner_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spinner_batch)

func set_capture_presence(center: Vector3, render_center: Vector3, near_radius := 55.0, far_radius := 180.0) -> void:
	# Camera-only captures add detail residency without evicting player colliders.
	set_presence(center, near_radius, far_radius, render_center)

func set_presence(center: Vector3, near_distance := 55.0, far_distance := 180.0, render_center := Vector3.INF) -> void:
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
		if render_center.is_finite():
			distance = minf(distance, pose.origin.distance_to(render_center))
		var presence := 2 if distance <= near_distance else (1 if distance <= far_distance else 0)
		if presence == 2:
			_active_near += 1
		elif presence == 1:
			_active_far += 1
		record.presence = presence
		# Retain static-obstacle queries while exposing the vehicle hit layer.
		# A promoted record's live body replaces both its collider and visuals;
		# a returned original stays hidden until its curb spot is clear.
		var hidden := _is_promoted(record) or _settling(record)
		_apply_collider(record)
		if record.has("damage_model"):
			record.damage_model.visible = presence > 0 and not hidden
		if hidden:
			continue
		if presence > 0 and not record.has("damage_model"):
			# Compact active transforms into the drawn prefix. Distant data remains
			# in records, but does not submit zero-scale cars or spend vertex work.
			var key := str(record.kind) + ("_near" if presence == 2 else "_far")
			var slot: int = int(visible_counts.get(key, 0))
			var batch: MultiMeshInstance3D = _batches[key]
			batch.multimesh.set_instance_transform(slot, pose)
			batch.multimesh.set_instance_color(slot, Models.paint_color(int(record.paint)))
			visible_counts[key] = slot + 1
		if str(record.kind) == "box_sedan" and presence == 2 and distance < 40.0 and not record.has("damage_model"):
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
		_place_stationary_hubs()

func _place_stationary_hubs() -> void:
	if _spinner_batch == null:
		return
	var data := Models.prototype("box_sedan")
	for i in _spinner_records.size():
		var record: Dictionary = records[_spinner_records[i]]
		var car_pose: Transform3D = record.pose
		for wheel in 4:
			var pose: Transform3D = data.wheel_poses[wheel]
			pose.origin.x += signf(pose.origin.x) * 0.12
			# A stable per-car angle survives presence refreshes and cell changes.
			# Parked tires and their decorative hubs never receive animation ticks.
			pose.basis = Basis(Vector3.RIGHT, float(_spinner_records[i]) * 0.4)
			_spinner_batch.multimesh.set_instance_transform(i * 4 + wheel, car_pose * pose)

func get_status() -> Dictionary:
	var kinds: Dictionary = {}
	var damaged := 0
	var punctures := 0
	var promoted := 0
	var dented := 0
	var colliders := 0
	var settling := 0
	for record in records:
		kinds[str(record.kind)] = int(kinds.get(str(record.kind),0)) + 1
		punctures += record.flat_tires.size()
		damaged += int(not record.flat_tires.is_empty())
		promoted += int(_is_promoted(record))
		settling += int(record.get("settling", false))
		dented += int(float(record.get("health", MAX_HEALTH)) < MAX_HEALTH)
		colliders += int(is_instance_valid(record.body) and (record.body as StaticBody3D).collision_layer != 0)
	return {"total": records.size(), "target": MAX_CARS, "baseline": BASELINE_CARS,
		"increase_percent": 100.0 * (float(records.size()) / BASELINE_CARS - 1.0),
		"streets": _counts.duplicate(), "street_count": _counts.size(), "kinds": kinds,
		"benchmark_legacy_catalog": Catalog.benchmark_legacy_catalog,
		"damaged_cars": damaged, "flat_tires": punctures,
		"attempts": _attempts, "rejected": _rejects.duplicate(), "draw_batches": _batches.size() + 1,
		"near": _active_near, "far": _active_far, "hidden": records.size() - _active_near - _active_far,
		"active_colliders": colliders, "animated_spinner_cars": 0, "visible_spinner_cars": _spinner_records.size(),
		"presence_radius": _near_distance, "far_radius": _far_distance, "promoted": promoted,
		"damaged_health": dented, "external_centers": _external_points.size(), "settling": settling}

func raycast_tires(from: Vector3, to: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	for index in records.size():
		var record: Dictionary = records[index]
		var car_pose: Transform3D = record.pose
		if Geometry3D.get_closest_point_to_segment(car_pose.origin, from, to).distance_squared_to(car_pose.origin) > 9.0:
			continue
		if _is_promoted(record) or record.get("settling", false):
			continue # A live body answers instead, or the original is not back yet.
		var hull := Damage.ray_hull(from, to, car_pose, Collision.parts(str(record.kind)))
		if not hull.is_empty() and (nearest.is_empty() or float(hull.distance) < float(nearest.distance)):
			hull["collider"] = record.body
			nearest = hull
		var data := Models.prototype(str(record.kind))
		for wheel in data.wheel_poses.size():
			var wheel_pose: Transform3D = data.wheel_poses[wheel]
			var radius := Models.wheel_radius(str(record.kind))
			if wheel in record.flat_tires:
				wheel_pose.origin.y -= radius * 0.45
				wheel_pose.basis = Basis.from_scale(Vector3(1.08, 0.55, 1.10))
			var half_width := float(Catalog.config(str(record.kind)).tire_half_width) if Catalog.has_kind(str(record.kind)) else 0.115
			var hit := Damage.ray_tire(from, to, car_pose * wheel_pose, radius, half_width)
			if not hit.is_empty() and (nearest.is_empty() or float(hit.distance) < float(nearest.distance)):
				hit["collider"] = record.body
				hit["tire_index"] = wheel
				nearest = hit
	return nearest

func receive_gunshot(hit: Dictionary, origin: Vector3) -> Dictionary:
	var body = hit.get("collider")
	if not is_instance_valid(body) or not body.has_meta("parked_index"):
		return {}
	var index := int(body.get_meta("parked_index"))
	if index < 0 or index >= records.size() or records[index].body != body or _is_promoted(records[index]) or records[index].get("settling", false):
		return {}
	var record: Dictionary = records[index]
	var wheel := int(hit.get("tire_index", -1))
	if wheel < 0:
		# A body round dents the record; promotion carries it to the live car.
		var before := float(record.get("health", MAX_HEALTH))
		var amount = hit.get("body_damage", SHOT_BODY_DAMAGE)
		var dealt := 0.0
		if (amount is float or amount is int) and apply_body_damage(index, float(amount), origin):
			dealt = before - float(record.health)
		return {"vehicle_hit": true, "tire_index": wheel, "punctured": false, "body_damage": dealt,
			"health": float(record.get("health", MAX_HEALTH))}
	if wheel >= 4 or wheel in record.flat_tires:
		return {"vehicle_hit": true, "tire_index": wheel, "punctured": false}
	record.flat_tires.append(wheel)
	# Only shot parked cars leave the shared batch. Persistent damage survives
	# every presence change, without rebuilding meshes or the whole fleet.
	if not record.has("damage_model"):
		var visual := Models.make(str(record.kind), int(record.paint))
		body.add_child(visual)
		record["damage_model"] = visual
	_flatten_wheel(record.damage_model, str(record.kind), wheel)
	set_presence(_presence_center, _near_distance, _far_distance)
	return {"vehicle_hit": true, "tire_index": wheel, "punctured": true}

func _flatten_wheel(model: Node3D, kind: String, wheel: int) -> void:
	var tire: Node3D = model.get_node(PARKED_WHEELS[wheel])
	tire.basis = Damage.flat_basis(Basis.IDENTITY, Vector3.RIGHT, 0.0, true)
	tire.position.y -= Models.wheel_radius(kind) * 0.45
	var spinner := model.get_node_or_null("Spinner_%d" % wheel)
	if spinner:
		spinner.hide()

# --- Promotion, damage and persistence support ------------------------------

static func to_vehicle_wheel(parked_wheel: int) -> int:
	return VEHICLE_WHEELS.find(PARKED_WHEELS[parked_wheel]) if parked_wheel >= 0 and parked_wheel < 4 else -1

static func to_parked_wheel(vehicle_wheel: int) -> int:
	return PARKED_WHEELS.find(VEHICLE_WHEELS[vehicle_wheel]) if vehicle_wheel >= 0 and vehicle_wheel < 4 else -1

func _is_promoted(record: Dictionary) -> bool:
	return record.get("promoted", "") != ""

## A returned original (its live body was removed) waits hidden and non-solid
## until nobody (explorer, person or car) stands in its curb spot, so it never
## becomes solid inside anyone. Only settling records pay for this query.
func _settling(record: Dictionary) -> bool:
	if not record.get("settling", false):
		return false
	if _spot_clear(record):
		record.erase("settling")
		return false
	return true

func _spot_clear(record: Dictionary) -> bool:
	if not is_inside_tree():
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 4 | 8 | 16
	query.margin = 0.0
	query.transform = record.pose
	query.exclude = [(record.body as CollisionObject3D).get_rid()]
	var space := get_world_3d().direct_space_state
	for part in Collision.parts(str(record.kind)):
		query.shape = part.shape
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true

func _apply_collider(record: Dictionary) -> void:
	var body: StaticBody3D = record.body
	var layer := 0
	if not _is_promoted(record) and not record.get("settling", false):
		var pose: Transform3D = record.pose
		if int(record.presence) == 2 or _near_external(pose.origin):
			layer = 2 | 16
	if body.collision_layer != layer:
		body.collision_layer = layer

func _near_external(at: Vector3) -> bool:
	for point in _external_points:
		if point.distance_squared_to(at) <= _external_radius * _external_radius:
			return true
	return false

## Traffic: colliders stay physical around externally driven (police) cars
## even beyond the explorer's presence radius. Visual batches are unchanged.
func set_external_centers(points: PackedVector3Array, radius := 40.0) -> void:
	_external_points = points
	_external_radius = radius
	for record in records:
		_apply_collider(record)

## Unpromoted records whose active collider lies within `radius` of `at`.
func records_near(at: Vector3, radius: float) -> Array[int]:
	var found: Array[int] = []
	for index in records.size():
		var record: Dictionary = records[index]
		var pose: Transform3D = record.pose
		if int(record.presence) == 2 and not _is_promoted(record) and not record.get("settling", false) \
			and pose.origin.distance_squared_to(at) <= radius * radius:
			found.append(index)
	return found

## Index of the record that `source_id` named, if its fingerprint still holds
## (same street, kind and origin within 0.75m); otherwise any fingerprint match.
func source_index(source_id: String, key: Dictionary = {}) -> int:
	var suffix := source_id.trim_prefix("parked_")
	if source_id.begins_with("parked_") and suffix.is_valid_int():
		var index := int(suffix)
		if index >= 0 and index < records.size() and str(records[index].get("source_id", "parked_%03d" % index)) == source_id and _key_matches(records[index], key):
			return index
	if key.is_empty():
		return -1
	for index in records.size():
		if _key_matches(records[index], key):
			return index
	return -1

func _key_matches(record: Dictionary, key: Dictionary) -> bool:
	if key.is_empty():
		return true
	var origin = key.get("origin")
	if str(record.get("street", "")) != str(key.get("street", "")) or str(record.kind) != str(key.get("kind", "")):
		return false
	if not origin is Array or origin.size() != 3:
		return false
	var pose: Transform3D = record.pose
	return pose.origin.distance_to(Vector3(float(origin[0]), float(origin[1]), float(origin[2]))) <= SOURCE_MATCH_DISTANCE

## Driving promoted this record into a live body owned by `owner_id`: hide its
## exact batch instance, damage model and collider. Idempotent per owner.
func hide_record(index: int, owner_id: String) -> bool:
	if index < 0 or index >= records.size() or owner_id.is_empty():
		return false
	var record: Dictionary = records[index]
	if _is_promoted(record):
		return str(record.promoted) == owner_id
	record["promoted"] = owner_id
	record.erase("settling")
	set_presence(_presence_center, _near_distance, _far_distance)
	return true

## The record hidden for `owner_id`, else -1 (exact ownership, no fingerprint).
func promoted_index(owner_id: String) -> int:
	if owner_id.is_empty():
		return -1
	for index in records.size():
		if str(records[index].get("promoted", "")) == owner_id:
			return index
	return -1

## The live body is gone: the original returns at its validated curb pose,
## settling (hidden, non-solid) until that spot is clear of everyone.
func restore_record(index: int) -> bool:
	if index < 0 or index >= records.size() or not _is_promoted(records[index]):
		return false
	records[index]["promoted"] = ""
	records[index]["settling"] = true
	set_presence(_presence_center, _near_distance, _far_distance)
	return true

func apply_body_damage(index: int, amount: float, _origin := Vector3.INF) -> bool:
	if index < 0 or index >= records.size() or not is_finite(amount) or amount <= 0.0:
		return false
	var record: Dictionary = records[index]
	var before := float(record.get("health", MAX_HEALTH))
	if _is_promoted(record) or before <= 0.0:
		return false
	record["health"] = clampf(before - amount, 0.0, MAX_HEALTH)
	return float(record.health) != before

## Health and flat tires in vehicle wheel order (FL, FR, RL, RR).
func record_damage(index: int) -> Dictionary:
	var record: Dictionary = records[index]
	var tires: Array[int] = []
	for wheel in record.flat_tires:
		tires.append(to_vehicle_wheel(int(wheel)))
	tires.sort()
	return {"health": float(record.get("health", MAX_HEALTH)), "flat_tires": tires}

func set_record_damage(index: int, value: float, vehicle_tires: Array) -> void:
	if index < 0 or index >= records.size():
		return
	var record: Dictionary = records[index]
	record["health"] = clampf(value, 0.0, MAX_HEALTH) if is_finite(value) else MAX_HEALTH
	var tires: Array = []
	for tire in vehicle_tires:
		var wheel := to_parked_wheel(int(tire))
		if wheel >= 0 and not tires.has(wheel):
			tires.append(wheel)
	record.flat_tires = tires
	if record.has("damage_model"):
		var old: Node3D = record.damage_model
		record.erase("damage_model")
		if is_instance_valid(old):
			old.visible = false
			old.queue_free()
	if not tires.is_empty():
		var visual := Models.make(str(record.kind), int(record.paint))
		(record.body as Node3D).add_child(visual)
		record["damage_model"] = visual
		for wheel in tires:
			_flatten_wheel(visual, str(record.kind), int(wheel))
	set_presence(_presence_center, _near_distance, _far_distance)

func clear_damage() -> void:
	for index in records.size():
		var record: Dictionary = records[index]
		if float(record.get("health", MAX_HEALTH)) < MAX_HEALTH or not record.flat_tires.is_empty():
			set_record_damage(index, MAX_HEALTH, [])

## Damaged, unpromoted records for persistence (bounded, index order).
func damage_snapshot() -> Array:
	var found: Array = []
	for index in records.size():
		var record: Dictionary = records[index]
		if _is_promoted(record):
			continue
		var damage := record_damage(index)
		# Judge the persisted (quantized) value so a round trip is exact.
		var stored := snappedf(float(damage.health), 0.01)
		if stored >= MAX_HEALTH and damage.flat_tires.is_empty():
			continue
		if found.size() >= MAX_DAMAGE_RECORDS:
			break
		found.append({"source_id": str(record.get("source_id", "parked_%03d" % index)),
			"source_key": record.get("source_key", {}).duplicate(true),
			"health": stored, "flat_tires": damage.flat_tires})
	return found
