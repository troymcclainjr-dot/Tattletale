extends "res://tests/city_living_world_render_runner.gd"
var photo: Camera3D
func _run() -> void:
	OUTPUT = "res://../artifacts/civic-build/visual"
	if not "--offscreen-validation" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
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
	check(level.level_ready, "civic level initialized")
	if not level.level_ready:
		get_tree().quit(1)
		return
	level.pause_exploring()
	level.world_time.frozen = true
	level.world_time.set_time(600)
	level._ui.hide()
	level.player.first_person = true
	photo = Camera3D.new()
	photo.fov = 60.0
	photo.far = 1100.0
	viewport.add_child(photo)
	photo.make_current()
	for site in level.civic_district.sites:
		if not FileAccess.file_exists("res://scripts/city/city_civic_%s.gd" % site.id):
			check(false, "building not yet available " + str(site.id))
			continue
		var center: Vector3 = level.vector(site.position)
		var front := Vector3(sin(float(site.yaw)), 0, cos(float(site.yaw)))
		var right := Vector3(front.z, 0, -front.x)
		level._place_player(level.vector(site.approach_center), float(site.yaw))
		await settle_streaming()
		photo.global_position = center + front * (float(site.depth_m) * 0.5 + 27) + right * 16 + Vector3.UP * 10
		if site.id == "police":
			photo.global_position = center + front * 26 + right * 8 + Vector3.UP * 8
		photo.look_at(center + Vector3.UP * 5)
		photo.reset_physics_interpolation()
		await capture(str(site.id))
		if site.id == "hospital":
			photo.global_position = center + Vector3(-72, 76, 60)
			photo.look_at(center + Vector3(25, 0, 5))
			photo.reset_physics_interpolation()
			await capture("hospital-campus-and-preserved-rows")
	for index in [0, 1, 4]:
		var entry: Dictionary = level.civic_district.businesses[index]
		var center: Vector3 = level.vector(entry.position)
		var front := Vector3(sin(float(entry.yaw)), 0, cos(float(entry.yaw)))
		level._place_player(center + front * (float(entry.depth) * 0.5 + 3), float(entry.yaw))
		await settle_streaming()
		photo.global_position = center + front * (float(entry.depth) * 0.5 + 15) + Vector3(front.z, 0, -front.x) * 5 + Vector3.UP * 5
		photo.look_at(center + Vector3.UP * 2.5)
		photo.reset_physics_interpolation()
		await capture(str(entry.id))
	level._ui.show()
	level.toggle_map()
	await frames(2)
	await capture("default-neighborhood-map")
	var report := {"captures": captures, "failures": failures, "district": level.civic_district.get_status()}
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
