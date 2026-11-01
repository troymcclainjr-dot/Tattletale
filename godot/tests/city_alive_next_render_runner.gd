extends "res://tests/city_living_world_render_runner.gd"
## Exact four user viewpoints plus rear-service and existing-conifer inspection.

func _run() -> void:
	OUTPUT = "res://../artifacts/alive-next/visual"
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires private offscreen renderer")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateAliveNextCapture"
	viewport.size = Vector2i(1600, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var scene = load("res://scenes/city/pen_lucy.tscn")
	if not scene is PackedScene:
		check(false, "Pen Lucy scene loads")
		get_tree().quit(1)
		return
	level = scene.instantiate()
	viewport.add_child(level)
	for i in 2400:
		await frames(1)
		if level.get("level_ready") == true:
			break
	check(level.get("level_ready") == true, "updated world initializes")
	if level.get("level_ready") != true:
		get_tree().quit(1)
		return
	level.resume_exploring()
	level.world_time.set_time(600)
	level.day_night.tick(1.0)
	level.inspector.enter()
	level.player.camera.fov = 68.0
	var details := level.find_child("CityAliveWorld", true, false)
	check(details != null, "world repairs integrated")
	check(level.npcs.crowd.residents.size() == 1200, "canonical crowd count preserved")
	var views: Array = [
		["ss1-east41st-lawns", Vector3(131.93, 8.21, -267.60), 174.88, -22.07],
		["ss2-frisby-side-fence", Vector3(106.73, 8.27, -265.18), 30.09, -28.67],
		["ss3-dumbarton-fronts", Vector3(369.07, -.03, -91.80), 357.91, -7.87],
		["ss4-firehouse-side-lawns", Vector3(-12.42, 14.65, 116.93), 183.28, -51.82],
		["row170-rear-lane-west", Vector3(349, -5.094, -125), 102.1, -3.0],
		["row170-rear-lane-east", Vector3(392, -6.067, -125), 260.0, -1.5],
		# The end unit faces the opposite way: its actual rear door/bin are
		# south of the row and cannot appear through the houses in a lane shot.
		["row170-end-unit-rear", Vector3(398, -5.772, -103), 292.6, -3.0]]
	var pine_views: Dictionary = {}
	for plants in level.vegetation._cells.values():
		for plant in plants:
			var kind := str(plant.kind)
			if not kind in ["tree4", "tree5"]:
				continue
			if not pine_views.has(kind) or plant.position.length_squared() < pine_views[kind].position.length_squared():
				pine_views[kind] = plant
	for kind in pine_views:
		var plant: Dictionary = pine_views[kind]
		var target: Vector3 = plant.position + Vector3.UP * float(plant.height) * .55
		for offset in [Vector3(-16, 5, 18), Vector3(16, 5, 18), Vector3(-16, 5, -18), Vector3(16, 5, -18)]:
			var eye: Vector3 = plant.position + offset
			var query := PhysicsRayQueryParameters3D.create(target, eye, 2)
			if not level.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
			var direction := target - eye
			views.append(["conifer-" + str(kind), eye, rad_to_deg(atan2(direction.x, -direction.z)), rad_to_deg(atan2(direction.y, Vector2(direction.x, direction.z).length()))])
			break
	var view_report: Array[Dictionary] = []
	for view in views:
		level.inspector.eye = view[1]
		level.inspector.yaw = deg_to_rad(view[2])
		level.inspector.pitch = deg_to_rad(view[3])
		level.inspector._apply_view()
		level.inspector._refresh_info()
		await settle_streaming()
		level.inspector._canvas.hide()
		await capture(view[0])
		view_report.append({"name": view[0], "eye": [view[1].x, view[1].y, view[1].z], "heading_deg": view[2], "pitch_deg": view[3]})
	level.inspector.leave()
	check(not level.paused and level.player.enabled, "inspection returns to normal play")
	var report := {"failures": failures, "captures": captures, "views": view_report,
		"world_repairs": details.get_status() if details != null else {}, "vegetation": level.vegetation.get_stats()}
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	if file == null:
		check(false, "capture report writable")
	else:
		file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
