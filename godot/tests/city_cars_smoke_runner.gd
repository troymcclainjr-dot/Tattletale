extends Node

const Models := preload("res://scripts/city/city_car_models.gd")
var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_cars] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	for kind in Models.KINDS:
		var prototype := Models.prototype(kind)
		var bounds: AABB = prototype.parked.get_aabb()
		check(bounds.size.x <= 2.13 and bounds.size.y <= 2.30 and bounds.size.z <= 4.72, "prototype fits traffic clearance: " + kind)
		check(absf(bounds.position.y) < 0.02, "tires meet ground: " + kind)
		check(int(prototype.triangles) < 4500, "modest triangle budget: " + kind)
		var far_triangles := 0
		for surface in prototype.far_parked.get_surface_count():
			far_triangles += prototype.far_parked.surface_get_array_index_len(surface) / 3
		check(far_triangles < int(prototype.triangles), "far mesh reduces wheel detail: " + kind)
		check(Models.prototype(kind).parked == prototype.parked, "prototype meshes are cached: " + kind)
		# Inspect referenced paint vertices, not only the mesh AABB: an indexed
		# bumper can leave unreferenced shell vertices in the AABB while drawing
		# no hood, doors or roof. This guards the rendered shell itself.
		var paint_arrays: Array = prototype.body.surface_get_arrays(0)
		var paint_vertices: PackedVector3Array = paint_arrays[Mesh.ARRAY_VERTEX]
		var paint_indices: PackedInt32Array = paint_arrays[Mesh.ARRAY_INDEX]
		var paint_roof := -INF
		for vertex_index in paint_indices:
			paint_roof = maxf(paint_roof, paint_vertices[vertex_index].y)
		check(paint_indices.size() / 3 >= 250 and paint_roof >= Models.dimensions(kind).y - 0.02,
			"paint draw indices retain the complete body and roof: " + kind)
	var sedan := Models.make("box_sedan", 0)
	add_child(sedan)
	var wheel: Node3D = sedan.get_node("WheelFL")
	var spinner: Node3D = sedan.get_node("Spinner_0")
	var wheel_before := wheel.transform
	var spinner_before := spinner.transform
	Models.animate_spinners(sedan, 0.8)
	check(wheel.transform == wheel_before and spinner.transform != spinner_before, "spinner hubs rotate independently of stationary wheels")
	sedan.queue_free()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 900:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes with shared cars")
		_finish()
		return
	level.pause_exploring()
	var parking: Node3D = level.traffic.parked
	check(parking != null, "parking provider initializes")
	if parking == null:
		_finish()
		return
	var status: Dictionary = parking.get_status()
	check(int(status.total) >= 36, "parked cars populate the neighborhood")
	check(int(status.street_count) >= 8, "parking covers many real streets")
	check(int(status.draw_batches) <= 7, "parked fleet shares bounded near/far/spinner batches")
	var spacing_clear := true
	var supported := true
	var extent := AABB()
	for i in parking.records.size():
		var record: Dictionary = parking.records[i]
		var pose: Transform3D = record.pose
		if i == 0:
			extent.position = pose.origin
		extent = extent.expand(pose.origin)
		var ground: Dictionary = level.ground_at(pose.origin)
		supported = supported and not ground.is_empty()
		if not ground.is_empty():
			supported = supported and absf(float(ground.position.y) - pose.origin.y) < 0.30
		for j in i:
			var other: Transform3D = parking.records[j].pose
			spacing_clear = spacing_clear and Vector2(pose.origin.x - other.origin.x, pose.origin.z - other.origin.z).length() >= 6.99
	check(spacing_clear, "parked vehicle clearance does not overlap")
	check(supported, "parked tires stay on surveyed terrain")
	check(maxf(extent.size.x, extent.size.z) > 400.0, "parking extends across the level")
	if not parking.records.is_empty():
		var first: Dictionary = {}
		for record in parking.records:
			if str(record.kind) == "box_sedan":
				first = record
				break
		check(not first.is_empty(), "parked spinner prototype exists")
		if first.is_empty():
			_finish()
			return
		var pose: Transform3D = first.pose
		parking.set_presence(pose.origin, 55, 180)
		var active: StaticBody3D = first.body
		check(active.collision_layer == 2, "near parked cars retain physical collision regardless of view")
		if DisplayServer.get_name() != "headless":
			var submitted_instances := 0
			for batch in parking._batches.values():
				submitted_instances += int(batch.multimesh.visible_instance_count)
			var active_status: Dictionary = parking.get_status()
			check(submitted_instances == int(active_status.near) + int(active_status.far), "only nearby and mid-distance cars occupy visible GPU instance prefixes")
		var count_before: int = parking.records.size()
		check(not parking._spinner_records.is_empty(), "nearby spinner hubs enter the update set")
		if DisplayServer.get_name() == "headless":
			print("[city_cars] SKIP GPU spinner readback: headless dummy renderer returns identity; rerun graphically for this check")
		elif not parking._spinner_records.is_empty():
			var hub_before: Transform3D = parking._spinner_batch.multimesh.get_instance_transform(0)
			parking.tick(0.25)
			var hub_after: Transform3D = parking._spinner_batch.multimesh.get_instance_transform(0)
			check(hub_before.basis != hub_after.basis and hub_before.origin.is_equal_approx(hub_after.origin) and parking._spinner_records.size() <= 6, "near parked spinners animate with bounded updates")
		parking.set_presence(Vector3(2000, 0, 2000), 55, 180)
		status = parking.get_status()
		check(int(status.active_colliders) == 0 and int(status.hidden) == count_before, "distant parked fleet deactivates geometry and colliders")
		if DisplayServer.get_name() != "headless":
			var empty_buffers := true
			for batch in parking._batches.values():
				empty_buffers = empty_buffers and int(batch.multimesh.visible_instance_count) == 0
			check(empty_buffers, "far parking submits zero GPU vehicle instances")
		check(parking.records.size() == count_before, "unloaded parking keeps exact placement data")
		parking.set_presence(level.player.global_position, 55, 180)
	print("[city_cars] parking ", parking.get_status())
	_finish()

func _finish() -> void:
	print("[city_cars] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
