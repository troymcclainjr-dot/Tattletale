extends "res://tests/city_living_world_render_runner.gd"

func _run() -> void:
	OUTPUT = "res://../artifacts/courts-lots-pass/visual"
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
	check(level.level_ready, "updated world initializes")
	if not level.level_ready:
		get_tree().quit(1)
		return
	level.resume_exploring()
	level.world_time.set_time(600)
	level.day_night.tick(1.0)
	level.inspector.enter()
	var court_13: Dictionary = {}
	var court_17 := false
	for court in level.park_courts.records:
		if court.id == "park_court_13":
			court_13 = court
		court_17 = court_17 or court.id == "park_court_17"
	check(not court_13.is_empty() and court_13.get("hoops", []).size() == 2, "Wyanoke court has opposing hoops")
	check(not court_17, "requested Argonne court removed")
	check(int(level.vegetation.get_stats().get("pointed_shrubs", 0)) >= 50, "tall pointed shrubs distributed across residential lawns")
	check(level.backlot_details != null, "backlot dressing integrated")
	check(level.npcs.crowd.residents.size() == 1200, "ambient identity count preserved")
	var report := {"courts": level.park_courts.get_status(), "vegetation": level.vegetation.get_stats(),
		"crowd": level.npcs.crowd.get_status(), "backlots": level.backlot_details.get_status() if level.backlot_details != null else {}}
	var views := [
		["wyanoke-court", Vector3(225.87,8.53,-38.40), 180.80, -43.25],
		["removed-argonne-court", Vector3(255.37,9.37,40.97), 141.33, -24.96],
		["wyanoke-dumpster", Vector3(206.27,6.10,-43.07), 61.58, -35.55],
		["cator-pointed-shrub", Vector3(153.14,5.88,-188.80), 172.69, -33.96],
		["cator-dumpster-driveway", Vector3(189.59,1.62,-202.60), 306.89, -14.23]]
	if not court_13.is_empty():
		views.append(["wyanoke-full-court", court_13.position + Vector3(-18,25,16), 48.37, -46.0])
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
	level.inspector.leave()
	check(not level.paused and level.player.enabled, "inspection returns to normal play")
	report.failures = failures
	report.captures = captures
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
