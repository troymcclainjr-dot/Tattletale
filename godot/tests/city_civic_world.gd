extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, text: String) -> void:
	failures += int(not ok)
	print("[civic_world] %s %s" % ["PASS" if ok else "FAIL", text])
func _run() -> void:
	var level = load("res://scenes/city/pen_lucy.tscn").instantiate()
	root.add_child(level)
	for i in 6000:
		await process_frame
		if level.level_ready:
			break
	check(level.level_ready, "level initialized")
	if not level.level_ready:
		quit(1)
		return
	level.pause_exploring()
	var district = level.civic_district
	check(district != null, "district integrated")
	check(district.map_pois.size() == 12, "four civic buildings and eight businesses on map")
	check(district._buildings.size() == 12, "all twelve new buildings constructed")
	# Survey the actual graded entrances, including the model setback inside its site.
	for site in district.sites:
		var path := "res://scripts/city/city_civic_%s.gd" % site.id
		if not FileAccess.file_exists(path):
			continue
		var model_script = load(path)
		var footprint: Vector2 = model_script.footprint()
		var start: Vector3 = level.vector(site.approach_center)
		var end: Vector3 = level.vector(site.position) + Vector3(sin(float(site.yaw)), 0, cos(float(site.yaw))) * minf(footprint.y, float(site.depth_m)) * 0.5
		var supported := true
		for sample in 25:
			var at := start.lerp(end, float(sample) / 24.0)
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at - Vector3.UP * 0.4, 1 | 2)
			if level.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				supported = false
				print("[civic_world] unsupported entrance sample %s at %s" % [site.id, at])
		check(supported, str(site.id) + " entrance has continuous ground support")
	# Both off-centre fire entrances must avoid the old abrupt foundation ledges.
	for x in [-17.25, -28.3]:
		var supported := true
		var previous := NAN
		var largest_step := 0.0
		for sample in 27:
			var z := 116.0 + float(sample) * 0.5
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, -1, z), Vector3(x, -4, z), 1 | 2)
			var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				supported = false
				continue
			var y: float = hit.position.y
			if not is_nan(previous):
				largest_step = maxf(largest_step, absf(y - previous))
			previous = y
		check(supported and largest_step <= 0.16, "fire full-width apron continuous at x=%s (max half-metre rise %.3fm)" % [x, largest_step])
	var city: Node3D = level.get_node("NeighborhoodGeometry")
	for name in district.removed_meshes:
		check(city.find_child(name, true, false) == null, "demolished geometry and original collision absent " + str(name))
	for name in ["Row_143", "Row_173", "Row_186"]:
		check(city.find_child(name, true, false) != null, "Argonne row preserved " + name)
	for key in ["porch_stairs", "rear_doors", "facade_details", "businesses"]:
		var dangling := 0
		for entry in level.level_data.get(key, []):
			if str(entry.get("source_mesh", "")) in district.removed_meshes:
				dangling += 1
		check(dangling == 0, "no stale " + key)
	for record in level.yard_details.records:
		if district.is_cleared(record.position):
			check(false, "yard item remains in clear site")
	var hospital: Dictionary = district.sites.filter(func(s): return s.id == "hospital")[0]
	var preserved := 0
	for item in district.map_buildings:
		if str(item.get("id", "")) in hospital.preserve_ids:
			preserved += 1
	check(preserved == 22, "all twenty-two preserved Argonne homes remain on map")
	for home in hospital.preserve_buildings:
		check(not district.is_cleared(level.vector(home.centroid)), "protected home excluded from clearing " + str(home.id))
	level.toggle_map()
	await process_frame
	check(level._map_overlay.visible, "M map opens")
	check(level._map_overlay.map.full_map, "default full geography map")
	print("[civic_world] STATUS " + JSON.stringify(district.get_status()))
	print("[civic_world] failures=%d" % failures)
	quit(0 if failures == 0 else 1)
