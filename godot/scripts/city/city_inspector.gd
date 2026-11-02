extends Node
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
## A detached inspection camera. The physical player and world clock stay put.
const T := preload("res://scripts/ui/hud_theme.gd")
const MIN_SPEED := 5.0
const MAX_SPEED := 200.0
var level: Node3D
var active := false
var eye := Vector3.ZERO
var yaw := 0.0 # Clockwise from geographic north (-Z).
var pitch := 0.0 # Positive looks up.
var speed := 35.0
var has_control := false
var capture_busy := false
var last_capture := ""
var output_directory := "user://inspection_shots"
var _old_first_person := false
var _old_override: Dictionary = {}
var _canvas: CanvasLayer
var _label: Label
var _elapsed := 0.0
var _message := ""
var _hit: Dictionary = {}
var _focus := Vector3.ZERO
var map_open := false
var _map_canvas: CanvasLayer
var _inspection_map: Control
signal capture_saved(png_path: String, json_path: String)

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "WorldInspector"
	_canvas = CanvasLayer.new()
	_canvas.layer = 40
	add_child(_canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.07, 0.93)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.label_settings = T.ls(T.mono(), 15, T.PAPER)
	panel.add_child(_label)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.label_settings = T.ls(T.mono(true), 23, T.PAPER, [], 0.0, 3, T.INK)
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(7, 16)
	_canvas.hide()
	set_process(false)

func enter() -> bool:
	if active or not level.ready_to_play or level.paused:
		return false
	var player = level.player
	_old_first_person = player.first_person
	_old_override = player.camera_override.duplicate(true)
	eye = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z.normalized()
	yaw = atan2(forward.x, -forward.z)
	pitch = asin(clampf(forward.y, -1.0, 1.0))
	active = true
	level.paused = true
	player.enabled = false
	player.set_orbiting(false)
	player.first_person = true
	if level.combat != null:
		if level.combat.has_method("cancel_player_actions"):
			level.combat.cancel_player_actions()
		else:
			level.combat.aiming = false
	level._ui.hide()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_message = "F8 saves PNG + location JSON; F7 copies location."
	_capture_mouse()
	_apply_view()
	_refresh_info()
	_canvas.show()
	set_process(true)
	if level.streaming != null:
		level.streaming.refresh_now()
	return true

func leave() -> void:
	if not active or capture_busy:
		return
	if map_open:
		close_map()
	active = false
	set_process(false)
	_canvas.hide()
	level.player.first_person = _old_first_person
	level.player.camera_override = _old_override
	level.player.update_camera()
	level.player.camera.reset_physics_interpolation()
	level._ui.show()
	level.resume_exploring()
	if level.streaming != null:
		level.streaming.refresh_now()
	if level.day_night != null:
		level.day_night._update_pool()

func _capture_mouse() -> void:
	has_control = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if level.offscreen_validation else Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	has_control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if active:
		_refresh_info()

func handle_input(event: InputEvent) -> void:
	if capture_busy:
		return
	if Bindings.matches(event, "city_map"):
		if map_open:
			close_map()
		else:
			open_map()
		return
	if map_open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				close_map()
			elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
				_inspection_map.map.zoom_by(0.8 if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.25)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				release_mouse()
			KEY_F7:
				DisplayServer.clipboard_set(JSON.stringify(snapshot(true), "\t"))
				_message = "Location copied. Paste it alongside your screenshot."
				_refresh_info()
			KEY_F8:
				save_capture()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not has_control:
			_capture_mouse()
		elif has_control and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			adjust_speed(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	elif event is InputEventMouseMotion and has_control:
		look(event.screen_relative)

func open_map() -> void:
	if not active or capture_busy:
		return
	if _map_canvas == null:
		_map_canvas = CanvasLayer.new()
		_map_canvas.layer = 41
		add_child(_map_canvas)
		_inspection_map = preload("res://scripts/city/city_map_overlay.gd").new()
		_map_canvas.add_child(_inspection_map)
		_inspection_map.setup(level, close_map)
	map_open = true
	release_mouse()
	_canvas.hide()
	_map_canvas.show()
	_inspection_map.show()
	_inspection_map.map.fit_neighborhood()

func close_map() -> void:
	map_open = false
	if _map_canvas != null:
		_map_canvas.hide()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_canvas.show()
	_capture_mouse()
	_refresh_info()

func forward() -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

func look(relative: Vector2) -> void:
	yaw = wrapf(yaw + relative.x * level.player.mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * level.player.mouse_sensitivity * (-1.0 if level.player.invert_y else 1.0), deg_to_rad(-89), deg_to_rad(89))
	_apply_view()

func adjust_speed(steps: int) -> void:
	speed = clampf(speed * pow(1.25, steps), MIN_SPEED, MAX_SPEED)
	_refresh_info()

func move_camera(axes: Vector2, vertical: float, delta: float, boost := false, precision := false) -> void:
	var right := Vector3(cos(yaw), 0, sin(yaw))
	var motion := (right * axes.x + forward() * axes.y + Vector3.UP * vertical).limit_length(1.0)
	eye += motion * speed * (0.2 if precision else 4.0 if boost else 1.0) * clampf(delta, 0, 0.1)
	_apply_view()

func _apply_view() -> void:
	level.player.camera_override = {"eye": eye, "target": eye + forward()}
	level.player.update_camera()
	level.player.camera.reset_physics_interpolation()

func _process(delta: float) -> void:
	if not active or capture_busy:
		return
	if has_control:
		var axes := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		var up := float(Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_Q))
		move_camera(axes, up, delta, Input.is_physical_key_pressed(KEY_SHIFT), Input.is_physical_key_pressed(KEY_CTRL))
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		_refresh_info()
		# Relocate the existing bounded light pool without advancing the clock.
		if level.day_night != null:
			level.day_night._update_pool()

func streaming_focus() -> Vector3:
	return _focus

func _sample_target() -> void:
	var world: World3D = level.get_world_3d()
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + forward() * 1500, 1 | 2 | 8 | 16)
	_hit = world.direct_space_state.intersect_ray(ray)
	# Centre ground-level detail below the drone; altitude must not unload trees.
	var ground_ray := PhysicsRayQueryParameters3D.create(Vector3(eye.x, 2000, eye.z), Vector3(eye.x, -2000, eye.z), 1)
	var ground: Dictionary = world.direct_space_state.intersect_ray(ground_ray)
	_focus = ground.get("position", Vector3(eye.x, 0, eye.z))

static func _xyz(point: Vector3) -> Array:
	return [snappedf(point.x, 0.001), snappedf(point.y, 0.001), snappedf(point.z, 0.001)]

func snapshot(include_diagnostics := false) -> Dictionary:
	_sample_target()
	var compass := fposmod(rad_to_deg(yaw), 360.0)
	var result := {"version": 1, "level": "pen_lucy", "utc": Time.get_datetime_string_from_system(true) + "Z", "axes": "Godot metres: +X east, +Y up, +Z south; heading 0 north,90 east; pitch positive up", "camera_position": _xyz(eye), "forward": _xyz(forward()), "heading_degrees": snappedf(compass, 0.01), "pitch_degrees": snappedf(rad_to_deg(pitch), 0.01), "fov_degrees": level.player.camera.fov, "street": level._nearest_street(eye), "player_position": _xyz(level.player.global_position), "clock": level.world_time.get_status(), "streaming": level.streaming.get_status() if level.streaming != null else {}, "speed_metres_per_second": speed, "world_paused": true}
	if not _hit.is_empty():
		var collider: Node = _hit.collider
		result.target = {"position": _xyz(_hit.position), "distance": snappedf(eye.distance_to(_hit.position), 0.01), "object_path": str(collider.get_path())}
	result.capture_directory = ProjectSettings.globalize_path(output_directory)
	result.last_capture = last_capture
	if include_diagnostics and level.get("traffic") != null:
		# Capture-only, not the overlay refresh loop. Preserve the paused vehicle
		# state so a screenshot can explain a jam without remote desktop control.
		var nearby: Array = []
		for car in level.traffic.vehicles + level.traffic.player_fleet:
			if is_instance_valid(car) and car.global_position.distance_squared_to(eye) < 65.0 * 65.0:
				nearby.append(car)
		nearby.sort_custom(func(a, b): return a.global_position.distance_squared_to(eye) < b.global_position.distance_squared_to(eye))
		result.traffic_near_camera = []
		for car in nearby.slice(0, 12):
			var status: Dictionary = car.get_status()
			status.position = _xyz(car.global_position)
			status["route_target"] = _xyz(car.route[car.route_index]) if car.route_index < car.route.size() else []
			result.traffic_near_camera.append(status)
	return result

func _refresh_info() -> void:
	var info := snapshot()
	var headings := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var cardinal: String = headings[int(round(float(info.heading_degrees) / 45.0)) % 8]
	var lines := PackedStringArray([
		"INSPECT / WORLD PAUSED                 F6  RETURN",
		str(info.street),
		"CAM   X %8.2f   Y %8.2f   Z %8.2f" % [eye.x, eye.y, eye.z],
		"LOOK  %s  %06.2f°   PITCH %+.2f°   FOV %.0f°" % [cardinal, info.heading_degrees, info.pitch_degrees, info.fov_degrees],
		"DIR   X %+.3f   Y %+.3f   Z %+.3f" % [forward().x, forward().y, forward().z],
	])
	if info.has("target"):
		var at: Vector3 = _hit.position
		lines.append("HIT   X %8.2f   Y %8.2f   Z %8.2f" % [at.x, at.y, at.z])
		lines.append("OBJ   " + str(info.target.object_path).trim_prefix(str(level.get_path()) + "/").right(52))
		lines.append("RANGE %.1f m" % float(info.target.distance))
	else:
		lines.append("HIT   No surface under crosshair (sky / >1500 m)")
	var stream: Dictionary = info.streaming
	lines.append("%d FPS  |  BASE %.1f m/s  |  DETAIL %d/%d%s" % [Engine.get_frames_per_second(), speed, int(stream.get("loaded_cells", 0)), int(stream.get("cells", 0)), " (loading)" if int(stream.get("near_cells_missing", 0)) > 0 or bool(stream.get("pending", false)) else ""])
	lines.append("Axes: X east / Y up / Z south. Pitch + looks up.")
	lines.append("WASD fly / Mouse look / E or Space up / Q down")
	lines.append("Shift 4x / Ctrl precision / Wheel speed / Esc cursor")
	lines.append("%s map / F7 copy location / F8 save screenshot + location" % Bindings.label("city_map"))
	lines.append(_message if has_control else "MOUSE FREE / Click to fly again / F6 return")
	_label.text = "\n".join(lines)

func save_capture() -> void:
	if capture_busy or not active or DisplayServer.get_name() == "headless":
		return
	capture_busy = true
	_apply_view()
	_refresh_info()
	var info := snapshot(true)
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var directory := ProjectSettings.globalize_path(output_directory)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_") + "_" + str(Time.get_ticks_usec())
	var path := directory.path_join("pen_lucy_" + stamp)
	var pixels := get_viewport().get_texture().get_image()
	if error == OK and pixels != null and not pixels.is_empty():
		error = pixels.save_png(path + ".png")
	else:
		error = ERR_CANT_CREATE
	if error == OK:
		info.image = path + ".png"
		var file := FileAccess.open(path + ".json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(info, "\t"))
			file.close()
			last_capture = path + ".png"
			_message = "Saved PNG + JSON in inspection_shots (F7 for location)."
			capture_saved.emit(path + ".png", path + ".json")
		else:
			_message = "PNG saved, but location JSON could not be written."
	else:
		_message = "Screenshot could not be saved (error %d)." % error
	capture_busy = false
	_refresh_info()
