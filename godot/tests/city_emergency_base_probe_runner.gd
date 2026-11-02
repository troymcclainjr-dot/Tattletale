extends "res://tests/city_priorities_session_fixture.gd"
## Read-only bounded geometry diagnosis; never installs a route or moves the unit.
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const AmbulanceDriver := preload("res://scripts/city/city_ambulance_driver.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Clearance := preload("res://scripts/city/city_civic_clearance.gd")
var ems: Node3D
var diagnoses: Array = []
var reason_counts: Dictionary = {}

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/next-five-20261101/ems-base-probe-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	ems = level.incidents.emergency
	result_details.before = ems.get_status()
	result_details.parked = ems._parked_cache.duplicate(true)
	begin_phase("base-geometry")
	var blocked_parking: Array = []
	for record in level.traffic.parked.records:
		if Clearance.parking_blocked(level, (record.pose as Transform3D).origin, 2.5):
			blocked_parking.append({"id": record.source_id, "position": (record.pose as Transform3D).origin})
	result_details.illegal_parking = blocked_parking
	check(blocked_parking.is_empty(), "generated parked cars leave the authored emergency driveway and existing civic clearances open")
	check(level.traffic.parked.records.size() > 100, "parking elsewhere in the district remains populated")
	var spec: Dictionary = ems._hospital_spec()
	for pose in spec.get("bays", []):
		_probe_bay(pose)
	_probe_curbs((spec.bays[0] as Transform3D).origin)
	result_details.candidates = diagnoses
	result_details.reasons = reason_counts
	result_details.scope = "Actual city support and collision; bounded read-only diagnosis, no installed route, collider changes, or clearance relaxation."
	print("EMS_BASE_PROBE reasons=", JSON.stringify(reason_counts))
	check(not diagnoses.is_empty(), "hospital candidate diagnostic produced actual geometry evidence")
	_finish()

func _record(entry: Dictionary) -> void:
	diagnoses.append(entry)
	var why := str(entry.get("reason", "valid"))
	reason_counts[why] = int(reason_counts.get(why, 0)) + 1
	if not why in ["curvature", "endpoint", "direction", "disabled"]:
		print("EMS_BASE_PROBE ", JSON.stringify(entry))

func _probe_bay(pose: Transform3D) -> void:
	var grounded: Dictionary = ems._ground_bay(pose)
	if grounded.is_empty():
		_record({"kind": "bay", "bay": pose.origin, "reason": "bay support/hull", "support": _support(pose.origin, atan2(pose.basis.z.x, pose.basis.z.z), pose.origin.y + 1.2), "hits": _hits(pose, AmbulanceDriver.HULL_MASK)})
		return
	var bay: Transform3D = grounded.transform
	var front := Vector3(bay.basis.z.x, 0, bay.basis.z.z).normalized()
	# Experimental shorter leads are diagnostic only: the real canopy may allow
	# an earlier smooth turn into a gap between curb-parked vehicles.
	var straight_candidates: Array = Emergency.EXIT_STRAIGHTS.duplicate()
	straight_candidates.append_array([2.0, 4.0, 6.0])
	for straight in straight_candidates:
		var exit_point: Vector3 = bay.origin + front * float(straight)
		var options: Array[Dictionary] = []
		for candidate in ems.lanes.nearest(exit_point, Vector3.ZERO, 30.0, -2.0, 6):
			var lane := int(candidate.lane)
			var points := PackedVector3Array(ems.lanes.lane_points(lane))
			var sums := Lanes.cumulative(points)
			var total: float = sums[sums.size() - 1]
			for ahead in Emergency.JOIN_AHEAD:
				var entry := {"kind": "exit", "bay": bay.origin, "straight": straight, "lane": lane, "ahead": ahead}
				if ems.lanes.graph.is_point_disabled(lane):
					entry.reason = "disabled"
					_record(entry)
					continue
				var along: float = float(candidate.along) + float(ahead)
				if along < 3.0 or along > total - 3.0:
					entry.reason = "endpoint"
					_record(entry)
					continue
				var join := Driver.point_at(points, sums, along)
				var direction := Driver.direction_at(points, sums, along)
				entry.join = join
				entry.endpoint_road = ems._hull_on_road(level.traffic, join, atan2(direction.x, direction.z))
				if direction == Vector3.ZERO or direction.dot(front) < -0.35:
					entry.reason = "direction"
					_record(entry)
					continue
				var lead: PackedVector3Array = ems._exit_curve(bay.origin, exit_point, front, join, direction)
				var lead_sums := Lanes.cumulative(lead)
				entry.length = lead_sums[lead_sums.size() - 1]
				entry.points = lead
				options.append(entry)
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.length) < float(b.length))
		var physics_checks := 0
		for entry in options:
			var lead: PackedVector3Array = entry.points
			entry.erase("points")
			if not Emergency._smooth(lead):
				entry.reason = "curvature"
				_record(entry)
				continue
			if physics_checks >= 12:
				entry.reason = "probe budget"
				_record(entry)
				continue
			physics_checks += 1
			entry.merge(_path_detail(lead, false), true)
			_record(entry)

func _probe_curbs(anchor: Vector3) -> void:
	for candidate in ems.lanes.nearest(anchor, Vector3.ZERO, 45.0, -2.0, 6):
		var lane := int(candidate.lane)
		var total: float = ems.lanes.lane_length(lane)
		var shift: float = ems._lane_shift(lane)
		for offset in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0]:
			var along: float = float(candidate.along) + offset
			var entry := {"kind": "curb", "lane": lane, "along": along, "shift": shift}
			if ems.lanes.graph.is_point_disabled(lane):
				entry.reason = "disabled"
			elif along < Emergency.SHIFT_LENGTH + 4.0 or along > total - Emergency.SHIFT_LENGTH - 4.0:
				entry.reason = "endpoint"
			elif shift < Emergency.STANDBY_SHIFT:
				entry.reason = "curb width"
			else:
				var pull_in: PackedVector3Array = ems._shift_path(lane, along - Emergency.SHIFT_LENGTH, along, 0.0, shift)
				entry.merge(_path_detail(pull_in, true), true)
				if entry.reason == "valid":
					var pull_out: PackedVector3Array = ems._shift_path(lane, along, along + Emergency.SHIFT_LENGTH, shift, 0.0)
					entry.merge(_path_detail(pull_out, true), true)
			_record(entry)

func _path_detail(points: PackedVector3Array, require_road: bool) -> Dictionary:
	if not Emergency._smooth(points):
		return {"reason": "curvature"}
	var sums := Lanes.cumulative(points)
	var previous := PackedFloat32Array()
	var reference_y := points[0].y + 1.2
	for i in points.size():
		var direction := Driver.direction_at(points, sums, sums[i])
		if direction == Vector3.ZERO:
			continue
		var heading := atan2(direction.x, direction.z)
		var detail := {"point": points[i], "index": i, "heading": heading}
		if require_road and not ems._hull_on_road(level.traffic, points[i], heading):
			detail.reason = "off carriageway"
			return detail
		var ground: Dictionary = ems.driver.ground_pose(points[i], heading, reference_y, false)
		if ground.is_empty():
			detail.reason = "support"
			detail.support = _support(points[i], heading, reference_y)
			return detail
		var heights: PackedFloat32Array = ground.heights
		if previous.size() == heights.size():
			for k in heights.size():
				if absf(heights[k] - previous[k]) > AmbulanceDriver.STEP_UP:
					detail.reason = "step"
					detail.heights = heights
					detail.previous = previous
					detail.support = _support(points[i], heading, reference_y)
					return detail
		previous = heights
		var pose: Transform3D = ground.transform
		reference_y = pose.origin.y
		if i % 2 == 0 or i == points.size() - 1:
			if not ems.driver.pose_clear(pose, 2):
				detail.reason = "structure"
				detail.hits = _hits(pose, 2)
				return detail
			if ems._parked_conflict(pose):
				detail.reason = "parked car"
				detail.nearby = []
				for parked in ems._parked_cache:
					if Lanes.flat(parked.origin, pose.origin) < 6.0:
						detail.nearby.append(parked.origin)
				return detail
	return {"reason": "valid", "points": points}

func _hits(pose: Transform3D, mask: int) -> Array:
	var result: Array = []
	var query := PhysicsShapeQueryParameters3D.new()
	query.transform = pose
	query.margin = 0.02
	query.collision_mask = mask
	query.exclude = [ems.ambulance.get_rid()]
	for part in ems.driver.parts:
		query.shape = part.shape
		for hit in level.get_world_3d().direct_space_state.intersect_shape(query, 8):
			result.append({"collider": str(hit.collider.get_path()), "shape": hit.shape, "layer": hit.collider.collision_layer})
	return result

func _support(at: Vector3, heading: float, reference_y: float) -> Array:
	var result: Array = []
	var forward := Vector3(sin(heading), 0, cos(heading))
	var right := Vector3(forward.z, 0, -forward.x)
	var top := reference_y + AmbulanceDriver.STEP_UP + 0.6
	for offset in [Vector3.ZERO, forward * 1.35, -forward * 1.35, right * 0.8, -right * 0.8]:
		var point: Vector3 = at + offset
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, top, point.z), Vector3(point.x, top - 6.0, point.z), AmbulanceDriver.GROUND_MASK)
		query.exclude = [ems.ambulance.get_rid()]
		var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
		result.append({"point": point, "hit": hit.position, "normal": hit.normal, "collider": str(hit.collider.get_path()), "layer": hit.collider.collision_layer} if not hit.is_empty() else {"point": point, "empty": true, "top": top})
	return result
