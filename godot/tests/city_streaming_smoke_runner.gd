extends Node
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("[city_streaming] %s %s" % ["PASS" if value else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(5)
	var level: Node = get_tree().current_scene
	for i in 1200:
		if level.level_ready:
			break
		await frames(1)
	check(level.level_ready, "neighborhood initializes")
	if not level.level_ready:
		get_tree().quit(1)
		return
	var manager: Node = level.streaming
	await frames(5)
	var status: Dictionary = manager.get_status()
	print("[city_streaming] start ", status)
	check(status.enabled and status.cells > 5, "detailed city has streamable cells")
	check(status.released_original_meshes > 300, "hidden duplicate building geometry released")
	check(status.loaded_cells > 0 and status.loaded_cells < status.cells, "near detail loaded and far detail actually absent")
	check(status.proxy_cells > 0, "unloaded blocks keep distant silhouettes")
	check(status.loaded_detail_triangles < status.total_detail_triangles, "resident full-detail triangle allocation is reduced")
	var city: Node = level.get_node("NeighborhoodGeometry")
	var collider_count := city.find_children("*", "CollisionShape3D", true, false).size()
	var unloaded := -1
	for i in manager.records.size():
		if not is_instance_valid(manager.records[i].node):
			unloaded = i
			break
	check(unloaded >= 0, "an unloaded geographic cell is available")
	if unloaded >= 0:
		var record: Dictionary = manager.records[unloaded]
		var point: Vector3 = record.bounds.get_center()
		level._place_player(point, 0.0)
		level.pause_exploring()
		manager.refresh_now()
		for i in 1800:
			if is_instance_valid(record.node):
				break
			await frames(1)
		check(is_instance_valid(record.node), "moving near a distant cell restores its real detail asynchronously")
		check(not record.proxy.visible, "proxy disappears only once detailed scene is ready")
		if is_instance_valid(record.node):
			check(level.render_optimizer._triangle_count(record.node.mesh) == record.triangles, "reloaded full-detail geometry matches its saved source")
			var weathered := false
			for surface in record.node.mesh.get_surface_count():
				weathered = weathered or record.node.get_active_material(surface) is ShaderMaterial
			check(weathered, "streamed scene retains weathered shader overrides")
		# A few metres around a load threshold may not unload an active cell.
		var boundary: Vector3 = record.bounds.end + Vector3(manager.load_distance + 8, 0, 0)
		boundary.z = record.bounds.get_center().z
		level.player.position = boundary
		manager.refresh_now()
		await frames(3)
		check(is_instance_valid(record.node), "distance hysteresis retains detail near the loading boundary")
		level.player.position = record.bounds.end + Vector3(manager.unload_distance + 100, 0, manager.unload_distance + 100)
		manager.refresh_now()
		await frames(3)
		check(not is_instance_valid(record.node) and record.proxy.visible, "leaving the region frees detailed scene and restores proxy")
	check(city.find_children("*", "CollisionShape3D", true, false).size() == collider_count, "building/terrain collision stays authoritative while graphics stream")
	manager.set_quality("low")
	check(manager.load_distance < 240.0, "low quality reduces streaming radius")
	manager.set_quality("high")
	check(manager.load_distance > 240.0, "high quality increases streaming radius")
	manager.set_quality("balanced")
	check(manager.get_status().failures == 0, "no background load failures")
	if level.vegetation != null:
		manager.set_process(false)
		var fallback = load("res://scripts/city/city_streaming.gd").new()
		level.add_child(fallback)
		var fallback_providers: Array[Node] = [level.vegetation]
		fallback.setup(level, null, fallback_providers)
		level.player.position = Vector3(2500, 0, 2500)
		fallback.refresh_now()
		await frames(3)
		check(level.vegetation.get_stats().loaded_cells == 0, "provider unloading works even without building optimizer/cache")
		level.spawn_player()
		fallback.refresh_now()
		await frames(3)
		check(level.vegetation.get_stats().loaded_cells > 0 and level.vegetation.get_stats().trunk_colliders > 0, "provider visuals and physical trees reload in fallback mode")
		fallback.queue_free()
		manager.set_process(true)
	print("[city_streaming] end ", manager.get_status())
	print("[city_streaming] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
