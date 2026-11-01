extends "res://tests/city_living_world_render_runner.gd"

func _run() -> void:
	OUTPUT = "res://../artifacts/neighborhood-pass/visual"
	var graphics := DisplayServer.get_name() != "headless"
	if graphics and not "--offscreen-validation" in OS.get_cmdline_user_args():
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	level = load("res://scenes/city/pen_lucy.tscn").instantiate()
	viewport.add_child(level)
	for i in 2400:
		await frames(1)
		if level.level_ready:
			break
	check(level.level_ready, "neighborhood initializes")
	if not level.level_ready:
		get_tree().quit(1)
		return
	level.resume_exploring()
	level.world_time.set_time(600)
	level.day_night.tick(1.0)
	level.inspector.enter()
	var report := {"graphics": graphics, "parking": level.traffic.parked.get_status(), "crowd": level.npcs.crowd.get_status(),
		"power": level.power_grid.get_status(), "details": level.neighborhood_details.get_status(),
		"vegetation": level.vegetation_report, "district": level.civic_district.get_status()}
	if level.park_furniture != null:
		report.parks = level.park_furniture.get_status()
	if level.civic_fleet != null:
		report.fleet = level.civic_fleet.get_meta("fleet_status")
	check(int(report.parking.total) >= 216, "street parking reaches fifty percent increase from144")
	check(int(report.crowd.total) == 1200, "crowd budget and identity count preserved")
	var views := [
		["missing-window", Vector3(439.20,-3.63,-140.46), 101.05, -10.64],
		["window-awnings", Vector3(464.84,-4.23,-145.90), 254.64, -12.70],
		["porch-clearances", Vector3(470.01,-3.66,-133.25), 284.48, -11.74],
		["police-lot", Vector3(-6.76,7.86,-46.20), 320.65, -24.37],
		["larger-shrubs", Vector3(-29.24,3.85,53.15), 222.74, -30.83],
		["edge-park-crowd", Vector3(-105.36,30.28,-250.78), 319.13, -42.38],
		["old-york-shops", Vector3(-5,13.51,-109.99), 90.73, -29.87],
		["hospital-parking", Vector3(397,20,-95), 35.0, -35.0],
		["hospital-ambulance", Vector3(384,2,-140), 92.2, -19.2]]
	if level.park_furniture != null:
		for play in level.park_furniture.playgrounds:
			var at: Vector3 = play.position
			views.append(["playground-" + str(views.size()), at + Vector3(6,3,8), 323.13, -10.0])
	for kind in ["hydrant", "postal_drop"]:
		for record in level.neighborhood_details.records:
			if str(record.kind) == kind:
				var at: Vector3 = record.position
				views.append([kind, at + Vector3(4,3,5), 321.34, -19.0])
				break
	for record in level.power_grid.records:
		if bool(record.get("transformer", false)):
			var at: Vector3 = level.vector(record.position)
			views.append(["pole-transformer", at + Vector3(10,10,12), 320.19, -12.0])
			break
	for view in views:
		level.inspector.eye = view[1]
		level.inspector.yaw = deg_to_rad(view[2])
		level.inspector.pitch = deg_to_rad(view[3])
		level.inspector._apply_view()
		level.inspector._refresh_info()
		await settle_streaming()
		level.inspector._canvas.hide()
		if graphics:
			await capture(view[0])
	level.inspector.open_map()
	check(level.inspector.map_open and level.paused, "inspection map remains paused")
	if graphics:
		await capture("inspection-map")
	level.inspector.close_map()
	level.inspector.leave()
	check(not level.paused and level.player.enabled, "inspection roundtrip restores gameplay")
	report.failures = failures
	report.captures = captures
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
