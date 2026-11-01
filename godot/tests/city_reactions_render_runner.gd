extends "res://tests/city_living_world_render_runner.gd"
## Captures the real level changes without desktop input or a visible window.
func _run() -> void:
	OUTPUT = "res://../artifacts/life-reactions/visual"
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
	check(level.level_ready, "level initialized")
	if not level.level_ready:
		get_tree().quit(1)
		return
	level.world_time.frozen = true
	level.world_time.set_time(600.0)
	level.pause_exploring()
	level._ui.hide()
	level.player.first_person = true
	var lawn := Vector3(-14.1797, 0.2097, -9.6511)
	level._place_player(street_camera(lawn).foot, 0.0)
	await settle_streaming()
	level.capture_view(Vector3(-14.164, 3.010, -5.651), Vector3(-14.1797, 0.310, -9.6511))
	await capture("01-front-lawn")
	# Production sign mesh and label in an isolated fixture beside the real road.
	var sign := Node3D.new()
	level.add_child(sign)
	var origin: Vector3 = level.player.global_position + Vector3(0, 0, 4)
	sign.global_position = origin
	load("res://scripts/city/city_dressing.gd")._stop_sign(sign)
	level.capture_view(origin + Vector3(1.2, 2.5, 3), origin + Vector3(0, 2.3, 0))
	await capture("02-stop-front")
	level.capture_view(origin + Vector3(-1.2, 2.5, -3), origin + Vector3(0, 2.3, 0))
	await capture("03-stop-rear")
	sign.queue_free()
	var facade: Dictionary = level.level_data.facade_details[0]
	var bay: Vector3 = level.vector(facade.position)
	var outward: Vector3 = level.vector(facade.normal).normalized()
	level._place_player(street_camera(bay).foot, 0.0)
	await settle_streaming()
	level.capture_view(bay + outward * 11.0, bay - Vector3.UP)
	await capture("04-house-windows")
	check(level.power_grid != null, "power grid integrated")
	if level.power_grid != null and not level.power_grid.records.is_empty():
		var pole: Vector3 = level.vector(level.power_grid.records[0].position)
		level._place_player(street_camera(pole).foot, 0.0)
		await settle_streaming()
		level.capture_view(pole + Vector3(15, 5, 18), pole + Vector3.UP * 5)
		await capture("05-power-lines")
	var shot_car: Node3D
	var shot_exclusions: Array[RID] = [level.player.get_rid()]
	for candidate in level.traffic.vehicles:
		if candidate._wheels.is_empty():
			continue
		var wheel: Vector3 = candidate._wheels[0].global_position
		var side: Vector3 = -candidate.global_basis.x.normalized()
		var origin_shot := wheel + side * 3.0
		var trace: Dictionary = level.combat._trace_bullet(origin_shot, origin_shot, wheel, shot_exclusions)
		if trace.hit.get("collider") != candidate or not trace.hit.has("tire_index"):
			continue
		level._place_player(street_camera(candidate.global_position).foot, 0.0)
		await settle_streaming()
		candidate.set_presence(level.player.global_position)
		check(level.combat._vehicle_shot(trace.hit, origin_shot), "production bullet dispatch punctures a traffic tire")
		check(candidate.flat_tires.size() == 1 and candidate.panic_time > 0, "actual traffic vehicle retains flat tire and escape impulse")
		# Traffic is advanced centrally by the level; freeze only the photo.
		level.set_physics_process(false)
		wheel = candidate._wheels[0].global_position
		side = -candidate.global_basis.x.normalized()
		var photo_camera := Camera3D.new()
		viewport.add_child(photo_camera)
		photo_camera.fov = 60.0
		photo_camera.global_position = wheel + side * 5.0 + Vector3.UP * 1.4 + candidate.global_basis.z
		photo_camera.look_at(wheel + Vector3.UP * 0.5)
		photo_camera.make_current()
		candidate.reset_physics_interpolation()
		await capture("07-flat-tire")
		photo_camera.queue_free()
		level.player.camera.make_current()
		shot_car = candidate
		break
	check(shot_car != null, "unobstructed production tire shot found")
	level._ui.show()
	level.toggle_map()
	level._map_overlay.map.fit_neighborhood()
	await capture("06-civic-proposals")
	var report := {"captures": captures, "failures": failures,
		"power": level.power_grid.get_status() if level.power_grid != null else {}, "windows": level.weathering_report}
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
