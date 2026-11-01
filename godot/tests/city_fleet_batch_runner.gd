extends Node
const Fleet := preload("res://scripts/city/city_civic_parking_fleet.gd")
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("[fleet_batch] %s %s" % ["PASS" if ok else "FAIL", message])
	failures += int(not ok)

func _run() -> void:
	var fleet := Node3D.new()
	for spec in Fleet.default_specs():
		var body := StaticBody3D.new()
		body.name = spec.id
		body.position = spec.position
		body.rotation = Vector3(0.025, float(spec.yaw), -0.015)
		body.set_meta("civic_vehicle", true)
		body.set_meta("precise_vehicle_hulls", true)
		var kind: String = spec.kind
		Fleet.Collision.attach(body, "minivan" if kind == "ambulance" else kind)
		var model: Node3D
		if kind == "police":
			model = Assets.model("cop_car")
			model.rotation.y = -PI / 2.0
		else:
			model = Fleet.Models.make("minivan" if kind == "ambulance" else kind, int(spec.get("paint", 1)))
		if kind == "ambulance":
			Fleet._ambulance_livery(model, body)
		body.add_child(model)
		fleet.add_child(body)
	var before: Dictionary = {}
	_snapshot(fleet, Transform3D.IDENTITY, before)
	var status := Fleet._batch_visuals(fleet)
	var after: Dictionary = {}
	_snapshot(fleet, Transform3D.IDENTITY, after)
	check(fleet.get_child_count() == 16, "all sixteen named static vehicle bodies remain direct children")
	var hulls := 0
	for body in fleet.get_children():
		for child in body.get_children():
			if child is CollisionShape3D:
				hulls += 1
	check(hulls == 42, "all42 original compound collision hulls remain")
	check(int(status.labels) == 2, "both ambulance side labels remain in their original hierarchy")
	check(int(status.unbatched_surfaces) == 0, "all static mesh surfaces support batching")
	check(int(status.batch_meshes) == 2, "precinct and hospital each use one spatial visual bucket")
	check(int(status.batch_surfaces) < int(status.source_surfaces) * 0.3, "material-preserving batches remove more than70percent of source surfaces")
	var matched := before.size() == after.size()
	var bounds_error := 0.0
	var mean_position_error := 0.0
	for key in before:
		if not after.has(key):
			matched = false
			continue
		var a: Dictionary = before[key]
		var b: Dictionary = after[key]
		matched = matched and int(a.vertices) == int(b.vertices)
		bounds_error = maxf(bounds_error, a.bounds.position.distance_to(b.bounds.position))
		bounds_error = maxf(bounds_error, a.bounds.end.distance_to(b.bounds.end))
		for axis in 3:
			mean_position_error = maxf(mean_position_error, absf(float(a.sum[axis]) - float(b.sum[axis])) / float(a.vertices))
	check(matched, "each exact material retains all original full-detail triangle vertices")
	check(bounds_error < 0.001 and mean_position_error < 0.0001, "nested local wheel/body transforms preserve world geometry within submillimeter tolerance")
	print("[fleet_batch] status ", JSON.stringify(status), " bounds_error=", bounds_error, " mean_error=", mean_position_error)
	var file := FileAccess.open("res://../.work/neighborhood-pass/fleet-batch-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":status,"failures":failures,"world_bounds_error_m":bounds_error,"mean_world_position_error_m":mean_position_error}, "\t"))
	file.close()
	fleet.free()
	print("[fleet_batch] failures=", failures)
	get_tree().quit(1 if failures else 0)

func _snapshot(node: Node3D, pose: Transform3D, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			var key := material.get_instance_id() if material != null else 0
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if not result.has(key):
				result[key] = {"vertices":0,"bounds":AABB(pose*points[0],Vector3.ZERO),"sum":[0.0,0.0,0.0]}
			var entry: Dictionary = result[key]
			var count := indices.size() if not indices.is_empty() else points.size()
			for i in count:
				var index := indices[i] if not indices.is_empty() else i
				var point := pose * points[index]
				entry.bounds = entry.bounds.expand(point)
				entry.sum[0] += float(point.x)
				entry.sum[1] += float(point.y)
				entry.sum[2] += float(point.z)
			entry.vertices += count
	for child in node.get_children():
		if child is Node3D:
			_snapshot(child, pose * child.transform, result)
