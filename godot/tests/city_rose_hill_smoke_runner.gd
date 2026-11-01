extends Node
var passed := 0
var failed := 0
var level: Node3D

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[rose_hill] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(5)
	level = get_tree().current_scene
	for i in 1800:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
	if level == null or level.get("level_ready") != true:
		check(false, "world initializes")
		get_tree().quit(1)
		return
	level.pause_exploring()
	var bays: Array = level.level_data.get("facade_details", [])
	check(bays.size() >= 16, "Rose Hill has a substantial run of upper bays")
	var variants := {}
	var rows := {}
	for bay in bays:
		variants[bay.variant] = true
		rows[bay.source_mesh] = true
		var center: Vector3 = level.vector(bay.position)
		var normal: Vector3 = level.vector(bay.normal)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center + normal * 1.5, center - normal * 0.3, 2))
		check(not hit.is_empty() and hit.position.distance_to(center) < 0.25, str(bay.building_id) + " projecting bay has real imported collision")
		check(float(bay.porch_clearance_m) >= 0.03 and float(bay.depth_m) <= 0.73, str(bay.building_id) + " bay sits above porch with shallow projection")
		check(float(bay.top_y) - float(bay.base_y) < float(bay.storey_height_m), str(bay.building_id) + " bay stays within second storey")
	check(variants.size() == 3 and rows.size() >= 2, "three bay styles span multiple Rose Hill rows")
	var stats: Dictionary = level.render_optimizer.get_stats()
	check(stats.enabled and stats.batch_meshes == 21 and stats.batch_surfaces <= 685, "bay windows remain in existing building batches without new draw surfaces")
	check(stats.collision_shapes_after == stats.collision_shapes_before, "building collision remains intact after batching")
	print("[rose_hill] bays=%d rows=%d triangles=%d surfaces=%d" % [bays.size(), rows.size(), stats.building_triangles, stats.batch_surfaces])
	if "--capture-rose-hill" in OS.get_cmdline_user_args() and not bays.is_empty():
		check(level.offscreen_validation and DisplayServer.get_name() != "headless", "captures use isolated offscreen GPU mode")
		if level.offscreen_validation and DisplayServer.get_name() != "headless":
			var selected: Dictionary = bays[0]
			for bay in bays:
				if absf(float(bay.position[0]) + 55.0) < absf(float(selected.position[0]) + 55.0):
					selected = bay
			await capture(selected, "rose-hill-row", false)
			await capture(selected, "rose-hill-bay", true)
			for bay in bays:
				if bay.source_mesh != selected.source_mesh:
					await capture(bay, "rose-hill-second-row", false)
					break
	print("[rose_hill] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func capture(bay: Dictionary, file_name: String, close: bool) -> void:
	var output := "res://../artifacts/rose-hill"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var center: Vector3 = level.vector(bay.position)
	var normal: Vector3 = level.vector(bay.normal)
	var across := normal.cross(Vector3.UP)
	level._place_player(center + normal * 10.0, 0.0)
	level._ui.hide()
	level.player.first_person = true
	var eye := center + normal * (7.0 if close else 18.0) + across * (2.0 if close else 7.0) - Vector3.UP * (0.2 if close else 1.7)
	level.capture_view(eye, center - Vector3.UP * (0.4 if close else 1.3))
	level.streaming.refresh_now()
	await frames(120)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(file_name + ".png")) == OK, "save " + file_name)
	level.player.camera_override.clear()
	level.player.first_person = false
	level._ui.show()
