extends Node
## One real neighborhood instance; no engine launch or project setting changes here.
const SETTINGS_PATH := "user://pen_lucy_settings.cfg"
var passes := 0
var fails := 0
var skips := 0
var level: Node
var _finished := false
var _isolated := false
var _had_settings := false
var _settings_bytes := PackedByteArray()
var _saved_values: Dictionary = {}
var _original_max_fps := 0
var _original_vsync := DisplayServer.VSYNC_ENABLED
var _original_scale := 1.0
var _audio: Dictionary = {}
var _original_music := true
var _wall: StaticBody3D

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(180.0, true, false, true).timeout
	if not _finished:
		check(false, "test watchdog timeout")
		_finish()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_ui] %s %s" % ["PASS" if ok else "FAIL", label])

func skip(label: String) -> void:
	skips += 1
	print("[city_ui] SKIP " + label)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func key(code: int) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.physical_keycode = code
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await frames(1)
	var released := InputEventKey.new()
	released.keycode = code
	released.physical_keycode = code
	Input.parse_input_event(released)
	await frames(2)

func capture_state(expected: int, label: String) -> void:
	if level != null and level.offscreen_validation:
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, label + ": offscreen validation leaves host pointer visible")
		return
	if DisplayServer.get_name() == "headless":
		skip(label + ": headless backend cannot establish OS capture (Input.mouse_mode=%d)" % Input.mouse_mode)
	else:
		check(Input.mouse_mode == expected, label)

func _run() -> void:
	var project := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().replace("\\", "/")
	var profile := OS.get_user_data_dir().replace("\\", "/")
	_isolated = profile.to_lower().begins_with((project + "/.work/test-profile/").to_lower())
	check(_isolated, "profile is isolated under workspace/.work/test-profile: " + profile)
	if not _isolated:
		_finish()
		return
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_settings_bytes = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_original_max_fps = Engine.max_fps
	_original_vsync = DisplayServer.window_get_vsync_mode()
	_original_scale = get_viewport().scaling_3d_scale
	_original_music = G.S.music_on
	for bus in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus)
		_audio[bus] = {"volume": AudioServer.get_bus_volume_db(index), "muted": AudioServer.is_bus_mute(index)}
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	for i in 1200:
		await frames(1)
		level = get_tree().current_scene
		if level != null and level.get("level_ready") == true:
			break
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes within bounded frame count")
		_finish()
		return
	var phone_help := false
	for label in level._settings.find_children("*", "Label", true, false):
		phone_help = phone_help or ("O  Open photo folder" in str(label.text) and "F5  Save progress" in str(label.text))
	check(phone_help, "Controls documents phone folder and checkpoint keys")
	_saved_values = level._settings.values.duplicate(true)
	check(true, "one neighborhood instance initialized")
	level.resume_exploring()
	await frames(3)
	await _map_and_pause()
	_layout()
	await _settings_checks()
	await _offers()
	_finish()

func _map_and_pause() -> void:
	check(not level.paused and not level._menu.visible, "play has no onboarding/case menu")
	capture_state(Input.MOUSE_MODE_CAPTURED, "active play captures mouse")
	await key(KEY_M)
	check(level.paused and level._map_overlay.visible and not level._menu.visible, "M opens map and pauses play")
	capture_state(Input.MOUSE_MODE_VISIBLE, "map releases mouse")
	var positions: Dictionary = {}
	for actor in level.npcs.actors.values():
		positions[actor] = actor.global_position
	for car in level.traffic.vehicles:
		positions[car] = car.global_position
	await frames(24)
	var stable := true
	for actor in positions:
		stable = stable and actor.global_position.distance_to(positions[actor]) < 0.001
	check(stable, "map pause freezes neighbors and traffic")
	check(not level.interact(), "map pause prevents E interactions")
	var canvas: Control = level._map_overlay.map
	var zoom: float = canvas.zoom
	await key(KEY_EQUAL)
	check(canvas.zoom > zoom, "map + key increases zoom")
	canvas.fit_neighborhood()
	var player_map: Vector2 = canvas._map(level.player.position)
	var north_map: Vector2 = canvas._map(level.player.position + Vector3(0, 0, -10))
	check(north_map.y < player_map.y, "north-up map preserves geographic orientation")
	var all_inside := true
	for item in level.level_data.site_boundary:
		all_inside = all_inside and Rect2(Vector2.ZERO, canvas.size).has_point(canvas._map(level.vector(item)))
	check(all_inside, "whole-neighborhood view fits surveyed boundary")
	await key(KEY_M)
	check(not level.paused and not level._map_overlay.visible, "M closes map and resumes")
	capture_state(Input.MOUSE_MODE_CAPTURED, "closing map recaptures mouse")
	await key(KEY_ESCAPE)
	check(level.paused and level._menu.visible and not level._map_overlay.visible, "Esc opens settings")
	capture_state(Input.MOUSE_MODE_VISIBLE, "settings releases mouse")
	var tabs: Array[Node] = level._settings.find_children("*", "TabContainer", true, false)
	check(tabs.size() == 1, "settings has one tab container")
	if tabs.size() == 1:
		var names: Array[String] = []
		for index in tabs[0].get_tab_count():
			names.append(tabs[0].get_tab_title(index))
		check(names == ["Video", "Audio", "Controls"], "Esc offers standard Video Audio Controls tabs")
	var has_case_board := false
	for control in level._settings.find_children("*", "Control", true, false):
		if control is Label or control is Button:
			var content := str(control.text).to_lower()
			has_case_board = has_case_board or "case board" in content or "take selected case" in content
	check(not has_case_board, "Esc contains no case selector")
	await key(KEY_ESCAPE)
	if level.offscreen_validation:
		level._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		check(not level.paused, "offscreen validation ignores OS focus without capturing host input")
	else:
		level._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		await frames(2)
		check(level.paused and level._menu.visible, "focus loss opens paused settings")
		level._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
		await frames(2)
		check(level.paused, "focus return waits for explicit resume")
		await key(KEY_ESCAPE)
		check(not level.paused, "explicit resume closes focus-loss pause")

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	check(level._fps.global_position.x < 40 and level._fps.global_position.y < 40, "FPS is top-left")
	check(level._location.get_parent() == level._objective.get_parent() and level._location.global_position.x > size.x * 0.5, "street name belongs to right ledger")
	check(level._location.get_index() == 0, "street name is first in ledger")
	check(level._prompt.get_parent() == level._objective.get_parent(), "context prompt belongs to right ledger")
	var left_labels: Array[String] = []
	var bottom_help := false
	for label in level._ui.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree() or str(label.text).is_empty():
			continue
		var position_: Vector2 = label.global_position
		if position_.x < size.x * 0.4 and position_.y < size.y * 0.4:
			left_labels.append(str(label.name))
		if position_.x < size.x * 0.4 and position_.y > size.y * 0.6 and str(label.name) != "RadarAttribution":
			bottom_help = true
	check(left_labels.size() == 1 and left_labels[0] == "FrameRate", "top-left contains only FPS")
	check(not bottom_help, "bottom-left help clutter is absent")
	check(level._radar.is_visible_in_tree() and level._radar.clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "minimap is visible and circularly masked")
	var radar_rect: Rect2 = level._radar.get_global_rect()
	check(radar_rect.position.x >= 0 and radar_rect.position.y > size.y * 0.5 and radar_rect.end.y <= size.y and radar_rect.end.x < size.x * 0.4, "radar fits inside lower-left viewport")
	var radar: Control = level._radar.map
	check(radar._map(level.player.position).distance_to(radar.size * 0.5) < 0.01, "radar keeps player centered")
	var ahead: Vector3 = level.player.position + Vector3(sin(level.player.camera_yaw), 0, cos(level.player.camera_yaw)) * 10
	var mapped: Vector2 = radar._map(ahead) - radar.size * 0.5
	check(absf(mapped.x) < 0.01 and mapped.y < 0, "radar rotates camera direction to top")
	var old_heading: float = level.player.camera_yaw
	var redraws: int = radar.redraw_count
	var geographic_builds: int = radar.geography.build_count
	var aligned := true
	for i in 8:
		level.player.camera_yaw += 0.04
		radar._process(0.001)
		var world_point := Vector2(ahead.x, ahead.z)
		aligned = aligned and (radar.geography.transform * world_point).distance_to(radar._map(ahead)) < 0.01
	check(radar.redraw_count == redraws + 8, "radar redraws every turn sample without the old 80ms delay")
	check(aligned, "cached geography stays aligned with live markers through camera turns")
	check(radar.geography.build_count == geographic_builds, "camera turns do not rebuild static map drawing")
	level.player.camera_yaw = old_heading
	check(radar._roads.size() == level.level_data.roads.size(), "map caches all real street geometry")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	level._input(right)
	check(level.player.orbiting, "right mouse press enables free orbit through level input")
	right.pressed = false
	level._input(right)
	check(not level.player.orbiting, "right mouse release ends orbit")
	right.pressed = true
	level._input(right)
	level.pause_exploring()
	check(not level.player.orbiting and not level._radar.visible, "pause clears orbit and hides radar")
	level.resume_exploring()

func _settings_checks() -> void:
	level.pause_exploring()
	var settings: Control = level._settings
	check(settings.get_node("SettingsBackground").color == Color.BLACK, "settings uses a black background")
	var tabs: TabContainer = settings.find_children("*", "TabContainer", true, false)[0]
	for index in tabs.get_tab_count():
		tabs.current_tab = index
		await frames(2)
		for slider in tabs.get_current_tab_control().find_children("*", "HSlider", true, false):
			check(absf(slider.size.x - slider.get_parent().size.x * 0.5) <= 1.0 and slider.custom_minimum_size.x == 120.0, "settings slider occupies half its responsive track: " + str(slider.name))
			check(slider.get_theme_stylebox("slider").get_minimum_size().y >= 6.0 and slider.get_theme_stylebox("grabber_area").get_minimum_size().y >= 6.0, "settings slider has a visible six-pixel rail: " + str(slider.name))
			var value: Label = slider.get_parent().get_node("SliderValue")
			check(absf(value.position.x - slider.get_rect().end.x - 12.0) <= 1.0, "settings value sits beside the shortened rail: " + str(slider.name))
	tabs.current_tab = 0
	settings._change("sensitivity", 1.75)
	settings._change("invert_y", true)
	check(is_equal_approx(level.player.mouse_sensitivity, 0.0042) and level.player.invert_y, "sensitivity and inversion apply to real player")
	level.player.camera_pitch = 0.24
	level.player.look(Vector2(0, 10))
	check(level.player.camera_pitch < 0.24, "inverted look changes actual camera direction")
	settings._change("render_scale", 0.75)
	check(is_equal_approx(get_viewport().scaling_3d_scale, 0.75), "render scale applies to viewport")
	settings._change("fps_cap", 90)
	check(Engine.max_fps == 90, "FPS limit applies to engine")
	settings._change("vsync", false)
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "VSync toggle applies to display")
	else:
		skip("VSync cannot be exercised by headless display")
	settings._change("quality", "Low")
	check(level.render_optimizer == null or level.render_optimizer.get_stats().get("quality") == "low", "quality selection reaches render optimizer")
	settings._change("master", 42.0)
	settings._change("music", 0.0)
	settings._change("sfx", 35.0)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))), 0.42), "master slider changes audio bus")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "zero music volume mutes music")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.35 * 0.7), "SFX slider respects mix gain")
	var saved := ConfigFile.new()
	check(saved.load(SETTINGS_PATH) == OK and saved.get_value("settings", "fps_cap", -1) == 90, "settings are persisted in isolated profile")
	var reload = load("res://scripts/city/city_settings.gd").new()
	level._ui.add_child(reload)
	reload.setup(level)
	check(reload.values == settings.values, "fresh settings control reloads all saved values without reloading world")
	reload.queue_free()
	await frames(2)
	settings.values = _saved_values.duplicate(true)
	settings.apply_settings(true)
	level.resume_exploring()

func _offers() -> void:
	level.missions.cancel_case()
	level.spawn_player()
	await frames(3)
	check(level.missions.nearby_offer().is_empty(), "spawn does not auto-start or reach an offer")
	await key(KEY_E)
	check(str(level.missions.active_id).is_empty(), "far E cannot start a case")
	var resident: Node3D = level.npcs.get_actor("resident")
	if resident == null:
		check(false, "resident exists for natural discovery test")
		return
	var target: Vector3 = resident.global_position
	# Choose a clear approach using the same live LOS the mission uses.
	var approach := Vector3.ZERO
	var found := false
	for direction in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		level._place_player(target + direction * 1.8, atan2(-direction.x, -direction.z))
		await frames(3)
		if not level.missions.nearby_offer().is_empty():
			approach = (level.player.global_position - target).normalized()
			found = true
			break
	check(found, "resident offers a case from an accessible nearby position")
	if not found:
		return
	var between: Vector3 = level.player.global_position.lerp(target, 0.5)
	_wall = StaticBody3D.new()
	_wall.collision_layer = 2
	_wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.12)
	collision.shape = box
	_wall.add_child(collision)
	_wall.position = between + Vector3.UP * 1.3
	_wall.rotation.y = atan2(approach.x, approach.z)
	level.add_child(_wall)
	await frames(3)
	await key(KEY_E)
	check(str(level.missions.active_id).is_empty() and level.missions.nearby_offer().is_empty(), "wall blocks idle offer and E case discovery")
	_wall.queue_free()
	_wall = null
	await frames(3)
	await key(KEY_E)
	check(level._dialogue.state.active and level.missions.active_id.is_empty() and level.missions.stage == 0, "nearby E opens text without starting/advancing case")
	check(level.paused and not level.player.enabled, "conversation captures movement")
	var offer_score: int = level.missions.score
	await key(KEY_M)
	check(level._dialogue.state.active and not level._map_overlay.visible, "dialogue captures M before map")
	await key(KEY_ESCAPE)
	check(not level._dialogue.state.active and not level.paused and not level._menu.visible, "Esc closes conversation before settings")
	check(level.missions.active_id.is_empty() and level.missions.score == offer_score, "closing offer changes no progress or reward")
	await key(KEY_E)
	var decline: Button = level._dialogue.replies.get_child(1)
	decline.pressed.emit()
	await frames(1)
	check(not level._dialogue.state.active and level.missions.active_id.is_empty(), "mouse reply callback can decline without starting case")
	await key(KEY_E)
	await key(KEY_ENTER)
	check(level.missions.active_id == "lost_satchel" and level.missions.stage == 0, "explicit offer choice starts case without advancing it")
	check(level.mission_navigation.active_id == "lost_satchel" and not level.mission_navigation.route.is_empty(), "accepted case sets shared mission route and destination")
	await key(KEY_E)
	check(level._dialogue.state.active and level.missions.stage == 0, "E previews current case line without progress")
	var exact: String = level.missions._steps[0].dialogue
	check(level._dialogue.state.current().text == exact, "conversation preserves authored case line verbatim")
	var jumps_before: int = level.player.jumps_started
	await key(KEY_SPACE)
	check(not level._dialogue.state.active and level.missions.stage == 1, "Space confirms one case step and resumes")
	check(level.player.jumps_started == jumps_before, "Space confirmation is consumed by dialogue and never triggers a jump")
	check(level.mission_navigation.stage == 1 and level.mission_navigation.target.distance_to(level.missions._target_position()) < 0.01, "case stage updates shared map destination")
	check(not level.missions.commit_dialogue_action({"kind": "case_step", "id": "lost_satchel", "stage": 0}), "stale step callback rejected")
	check(level.missions.stage == 1 and level.missions.score == offer_score, "replayed callback changes no progress/reward")
	check(not level._menu.visible and not level.paused, "conversation completion resumes without settings")
	level.missions.cancel_case()
	check(level.mission_navigation.route.is_empty() and level.mission_navigation.active_id.is_empty(), "cancel clears shared full-map and minimap guidance")

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(_wall):
		_wall.queue_free()
	if is_instance_valid(level) and not _saved_values.is_empty():
		level._settings.values = _saved_values.duplicate(true)
		level._settings.apply_settings(true)
	Engine.max_fps = _original_max_fps
	get_viewport().scaling_3d_scale = _original_scale
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(_original_vsync)
	for bus in _audio:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, _audio[bus].volume)
		AudioServer.set_bus_mute(index, _audio[bus].muted)
	G.S.music_on = _original_music
	if _isolated:
		if _had_settings:
			var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if file:
				file.store_buffer(_settings_bytes)
				file.close()
			check(FileAccess.get_file_as_bytes(SETTINGS_PATH) == _settings_bytes, "original settings bytes restored")
		else:
			if FileAccess.file_exists(SETTINGS_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
			check(not FileAccess.file_exists(SETTINGS_PATH), "temporary settings removed")
	print("[city_ui] %d passed, %d failed, %d backend skips" % [passes, fails, skips])
	get_tree().quit(0 if fails == 0 else 1)
