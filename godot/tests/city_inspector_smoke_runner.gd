extends "res://tests/city_living_world_render_runner.gd"

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _run() -> void:
	var graphics := DisplayServer.get_name() != "headless"
	if graphics and not "--offscreen-validation" in OS.get_cmdline_user_args():
		get_tree().quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	level = load("res://scenes/city/pen_lucy.tscn").instantiate()
	viewport.add_child(level)
	for i in 2400:
		await frames(1)
		if level.level_ready:
			break
	check(level.level_ready and level.inspector != null, "inspector initialized with level")
	if not level.level_ready or level.inspector == null:
		get_tree().quit(1)
		return
	await frames(12)
	var player_at: Vector3 = level.player.global_position
	var old_view: bool = level.player.first_person
	var old_yaw: float = level.player.camera_yaw
	var walked: float = level.player.distance_walked
	level._input(key(KEY_F6))
	var fly = level.inspector
	check(fly.active and level.paused and not level.player.enabled, "F6 freezes simulation and detaches camera")
	check(not level._ui.visible and fly._canvas.visible, "inspection overlay replaces gameplay HUD")
	check(not level.player.request_jump(), "jump cannot reach physical player while inspecting")
	var clock: float = level.world_time.total_minutes
	await frames(12)
	check(level.world_time.total_minutes == clock and level.player.global_position == player_at, "world time and physical player remain frozen")
	fly.yaw = 0
	fly.pitch = 0
	fly.eye = Vector3.ZERO
	fly.move_camera(Vector2(0, 1), 0, 0.1)
	check(fly.eye.is_equal_approx(Vector3(0, 0, -3.5)), "W flies north at 35m/s")
	fly.eye = Vector3.ZERO
	fly.move_camera(Vector2.ONE, 1, 0.1)
	check(is_equal_approx(fly.eye.length(), 3.5), "three-axis diagonal movement is normalized")
	fly.eye = Vector3.ZERO
	fly.move_camera(Vector2(0, 1), 0, 0.1, true)
	check(is_equal_approx(fly.eye.length(), 14.0), "Shift gives four-times boost")
	fly.eye = Vector3.ZERO
	fly.move_camera(Vector2(0, 1), 0, 0.1, false, true)
	check(is_equal_approx(fly.eye.length(), 0.7), "Ctrl gives precise slow movement")
	fly.yaw = PI * 0.5
	fly.pitch = 0.0
	check(fly.forward().is_equal_approx(Vector3.RIGHT), "heading 90 is east")
	fly.look(Vector2(0, -100000))
	check(fly.pitch <= deg_to_rad(89) and fly.forward().is_finite(), "vertical look clamps before singularity")
	fly.adjust_speed(100)
	check(fly.speed == 200, "wheel speed upper bound")
	fly.adjust_speed(-100)
	check(fly.speed == 5, "wheel speed lower bound")
	fly.speed = 35
	level._input(key(KEY_ESCAPE))
	check(not fly.has_control and fly.active and not level._menu.visible, "Esc frees cursor without opening hidden settings")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var ammo: int = level.combat.ammo
	level._input(click)
	check(fly.has_control and level.combat.ammo == ammo, "click recaptures flight without firing")
	level._input(key(KEY_M))
	check(fly.active and fly.map_open and fly._inspection_map.visible and not fly.has_control, "M opens inspection map and releases flight mouse")
	check(level.paused and not level.player.enabled and not level._ui.visible, "inspection map keeps simulation paused and normal HUD hidden")
	fly._inspection_map.map.center_player()
	check(fly._inspection_map.map.map_center.is_equal_approx(Vector2(fly.eye.x, fly.eye.z)), "Find me centers the detached camera")
	level._input(key(KEY_ESCAPE))
	check(not fly.map_open and fly.has_control and fly.active and level.paused, "Esc closes map back to flight without resuming gameplay")
	level._input(key(KEY_M))
	fly.close_map()
	check(not fly.map_open and fly.active and level.paused, "map close button callback returns to paused flight")
	fly.eye = Vector3(365, 25, -170)
	var direction: Vector3 = (Vector3(420, 0, -158) - fly.eye).normalized()
	fly.yaw = atan2(direction.x, -direction.z)
	fly.pitch = asin(direction.y)
	fly._apply_view()
	fly._refresh_info()
	await settle_streaming()
	var info: Dictionary = fly.snapshot()
	check(info.has("target") and str(info.target.object_path).contains("Hospital"), "crosshair identifies hospital and exact hit location")
	check(fly.streaming_focus().distance_to(level.player.global_position) > 250, "streaming follows remote camera rather than frozen player")
	check(absf(fly.streaming_focus().y) < 30, "streaming focus projects to ground below flying camera")
	check(info.camera_position == [365.0, 25.0, -170.0] and info.has("forward") and info.has("heading_degrees"), "shareable snapshot contains reproducible camera pose")
	check(not level.player.puppet.g.visible, "player model hidden during detached flight")
	# Test near a real remote lamp, rather than assuming every hospital frontage
	# has a fixture inside the bounded light-pool radius.
	var photo_eye: Vector3 = fly.eye
	var farthest := 0.0
	for anchor in level.day_night._anchors:
		var at: Vector3 = anchor.position
		if at.distance_squared_to(player_at) > farthest:
			farthest = at.distance_squared_to(player_at)
			fly.eye = at + Vector3.UP * 15
	fly._apply_view()
	fly._refresh_info()
	level.world_time.set_time(23 * 60)
	level.day_night.tick(1.0)
	var lamps_follow_camera: bool = not level.day_night._selected.is_empty()
	for index in level.day_night._selected:
		var at: Vector3 = level.day_night._anchors[index].position
		var focus: Vector3 = fly.streaming_focus()
		lamps_follow_camera = lamps_follow_camera and Vector2(at.x - focus.x, at.z - focus.z).length() <= level.day_night.LAMP_REACH
	check(lamps_follow_camera, "night light pool follows inspection camera")
	print("[inspector] night pool: " + JSON.stringify(level.day_night.get_status()))
	level.world_time.total_minutes = clock
	fly.eye = photo_eye
	fly._apply_view()
	fly._refresh_info()
	level.day_night.tick(1.0)
	var image_path := ""
	if graphics:
		fly.output_directory = "res://../artifacts/inspector"
		level._input(key(KEY_F8))
		for i in 180:
			await frames(1)
			if not fly.capture_busy:
				break
		image_path = fly.last_capture
		check(not image_path.is_empty() and FileAccess.file_exists(image_path), "F8 writes screenshot")
		if not image_path.is_empty():
			var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(image_path.get_basename() + ".json"))
			check(saved.camera_position == info.camera_position and saved.target.object_path == info.target.object_path, "PNG sidecar matches the captured view")
			var pixels := Image.load_from_file(image_path)
			check(pixels.get_size() == Vector2i(1600, 900), "screenshot captures correct private viewport")
			pixels.save_png("res://../artifacts/inspector/inspection-mode.png")
	level._input(key(KEY_F6))
	check(not fly.active and not level.paused and level.player.enabled, "F6 restores normal gameplay")
	check(level.player.global_position == player_at and level.player.distance_walked == walked, "inspection never teleports player or advances walking progress")
	check(level.player.first_person == old_view and level.player.camera_yaw == old_yaw and level.player.camera_override.is_empty(), "original camera mode and bearing restored")
	check(level._ui.visible and not fly._canvas.visible, "normal HUD restored")
	level.player.toggle_view()
	level._input(key(KEY_F6))
	level._input(key(KEY_F6))
	check(level.player.first_person and not level.player.puppet.g.visible, "first-person view survives an inspection round trip")
	level.player.toggle_view()
	level.pause_exploring()
	check(not fly.enter(), "inspection cannot steal focus from settings or dialogue")
	var report := {"failures": failures, "snapshot": info, "capture": image_path, "graphics": graphics}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/inspector"))
	var file := FileAccess.open("res://../artifacts/inspector/validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)
