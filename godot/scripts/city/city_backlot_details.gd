extends Node3D
## Source-authored paved side/rear spaces. Initialize after yards and permanent
## terrain/building colliders; no per-frame work or procedural roadside guessing.
const DATA := "res://assets/data/pen_lucy_backlots.json"
const Fleet = preload("res://scripts/city/city_civic_parking_fleet.gd")
const CELL := 48.0
var records: Array[Dictionary] = []
var _status: Dictionary = {}


func setup(level: Node3D) -> Dictionary:
	name = "CityBacklotDetails"
	set_process(false)
	if not _status.is_empty():
		return get_status()
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		_status = {"enabled": false, "reason": "backlot manifest missing"}
		return get_status()
	var yards: Node = level.get("yard_details")
	var templates: Dictionary = yards.get("_meshes") if is_instance_valid(yards) else {}
	var dumpster: Mesh = templates.get("dumpster")
	if dumpster == null:
		_status = {"enabled": false, "reason": "initialize after yard dumpster template"}
		return get_status()
	var rejected: Array[Dictionary] = []
	var specs: Array[Dictionary] = []
	var batches: Dictionary = {}
	for entry in data.records:
		var record: Dictionary = entry.duplicate(true)
		if str(record.kind) != "dumpster":
			specs.append(record)
			continue
		var grounded := _dumpster_pose(level, record)
		if grounded.is_empty():
			rejected.append({"id": record.id, "reason": "ground"})
			continue
		var pose: Transform3D = grounded.pose
		var parts := _dumpster_parts()
		if not _clear(level, pose, parts):
			rejected.append({"id": record.id, "reason": "occupied"})
			continue
		var body := StaticBody3D.new()
		body.name = str(record.id)
		body.transform = pose
		body.collision_layer = 2 | 16
		body.collision_mask = 0
		body.set_meta("backlot_dumpster", true)
		body.set_meta("ground_checked", true)
		body.set_meta("building_id", str(record.building_id))
		for part in parts:
			var collider := CollisionShape3D.new()
			collider.shape = part.shape
			collider.position = part.offset
			body.add_child(collider)
		add_child(body)
		var cell := Vector2i(floori(pose.origin.x / CELL), floori(pose.origin.z / CELL))
		if not batches.has(cell):
			batches[cell] = []
		batches[cell].append(pose)
		record["pose"] = pose
		records.append(record)
	for cell in batches:
		var origin := Vector3(cell.x * CELL, 0, cell.y * CELL)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = dumpster
		multimesh.instance_count = batches[cell].size()
		for i in multimesh.instance_count:
			var pose: Transform3D = batches[cell][i]
			pose.origin -= origin
			multimesh.set_instance_transform(i, pose)
		var instance := MultiMeshInstance3D.new()
		instance.name = "DumpsterCell_%s_%s" % [cell.x, cell.y]
		instance.position = origin
		instance.multimesh = multimesh
		instance.visibility_range_end = 190.0
		instance.visibility_range_end_margin = 15.0
		add_child(instance)
	var fleet_status: Dictionary = {"requested": 0, "total": 0, "rejected": []}
	if not specs.is_empty():
		var fleet := Fleet.build(level, specs)
		fleet.name = "BacklotParkingFleet"
		add_child(fleet)
		fleet_status = fleet.get_meta("fleet_status")
		for spec in specs:
			var vehicle := fleet.get_node_or_null(NodePath(str(spec.id))) as Node3D
			if vehicle != null:
				spec["pose"] = vehicle.transform
				records.append(spec)
		for rejection in fleet_status.rejected:
			rejected.append(rejection)
	var mandatory: Dictionary = {}
	for entry in data.records:
		if bool(entry.get("mandatory", false)):
			mandatory[str(entry.id)] = false
	for record in records:
		if bool(record.get("mandatory", false)):
			mandatory[str(record.id)] = true
	_status = {"enabled": true, "requested": data.records.size(), "total": records.size(),
		"dumpsters": records.size() - int(fleet_status.total), "cars": int(fleet_status.total),
		"dumpster_batches": batches.size(), "rejected": rejected, "mandatory": mandatory,
		"fleet": fleet_status, "source_audit": data.audit}
	return get_status()


func get_status() -> Dictionary:
	return _status.duplicate(true)


static func _dumpster_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	# Match the existing yard prototype's body, lid, handles and four feet.
	for box in [[Vector3(1.8, 1.05, 1.05), Vector3(0, .65, 0)],
		[Vector3(1.92, .15, 1.18), Vector3(0, 1.235, 0)]]:
		var shape := BoxShape3D.new()
		shape.size = box[0]
		parts.append({"shape": shape, "offset": box[1]})
	for x in [-.5, .5]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(.32, .12, .1)
		parts.append({"shape": shape, "offset": Vector3(x, 1.30, .35)})
	for x in [-.67, .67]:
		for z in [-.36, .36]:
			var shape := BoxShape3D.new()
			shape.size = Vector3(.23, .22, .25)
			parts.append({"shape": shape, "offset": Vector3(x, .11, z)})
	return parts


static func _clear(level: Node3D, pose: Transform3D, parts: Array[Dictionary]) -> bool:
	for part in parts:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = part.shape
		query.transform = pose * Transform3D(Basis.IDENTITY, part.offset)
		query.collision_mask = 2 | 16
		query.margin = .015
		if not level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


static func _dumpster_pose(level: Node3D, record: Dictionary) -> Dictionary:
	var at := Vector3(record.position[0], record.position[1], record.position[2])
	var forward := Vector3(sin(float(record.yaw)), 0, cos(float(record.yaw)))
	var right := Vector3(forward.z, 0, -forward.x)
	var heights: Array[float] = []
	for offset in [forward * .45, -forward * .45, right * .8, -right * .8]:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3(offset) + Vector3.UP, at + Vector3(offset) - Vector3.UP * 2, 1)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or float(hit.normal.y) < .94:
			return {}
		heights.append(float(hit.position.y))
	forward.y = (heights[0] - heights[1]) / .9
	right.y = (heights[2] - heights[3]) / 1.6
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	at.y = (heights[0] + heights[1] + heights[2] + heights[3]) * .25 + .018
	return {"pose": Transform3D(Basis(right, up, forward), at)}
