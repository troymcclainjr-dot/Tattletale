extends "res://tests/city_sandbox_world_smoke_runner.gd"
## Shared full-world fixtures. Inherit only established geometry/input helpers.
## Scene arrangement may reposition the player; every interaction uses real input.
## Normal world clock/NPC/traffic/player processing stays enabled throughout.
var run_id := "manual"
var output_dir := ""
var phase_name := "boot"
var checks: Array[Dictionary] = []
var boot_usec := 0
var sampling := false
var samples: Array[Dictionary] = []
var initial_population: Dictionary = {}
var observed_phases: Dictionary = {}
var result_details: Dictionary = {}
var _native_focus_checked := false
var _native_focus_verified := false
var _native_focus_evidence: Dictionary = {}

func _ready() -> void:
	# Apply before the inherited runner schedules boot or dispatches any input.
	# Main-window visibility is owned by the launch harness. Keep its render
	# surface alive, unfocusable and outside every monitor instead of hiding it.
	_place_window_off_desktop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	super._ready()

func _place_window_off_desktop() -> void:
	var window := get_tree().root
	window.unfocusable = true
	var at := Vector2i(-10000, -10000)
	if DisplayServer.get_name() != "headless":
		for screen in DisplayServer.get_screen_count():
			at.x = mini(at.x, DisplayServer.screen_get_position(screen).x - window.size.x - 256)
	window.position = at

func _window_off_desktop() -> bool:
	if DisplayServer.get_name() == "headless":
		return true # Dummy display owns no OS window or desktop focus.
	var evidence := _window_safety_evidence()
	var unfocused: bool = (not bool(evidence.window_has_focus) and not bool(evidence.display_has_focus)) or _native_focus_verified
	return bool(evidence.geometry_off_desktop) and bool(evidence.unfocusable) and bool(evidence.get("display_no_focus", true)) and unfocused

func _window_safety_evidence() -> Dictionary:
	var window := get_tree().root
	var evidence := {"display": DisplayServer.get_name(), "mouse_mode": Input.mouse_mode,
		"captured_mouse": Input.mouse_mode != Input.MOUSE_MODE_VISIBLE, "unfocusable": window.unfocusable,
		"window_position": [window.position.x, window.position.y], "window_size": [window.size.x, window.size.y],
		"geometry_off_desktop": true, "window_has_focus": false, "display_has_focus": false, "monitors": []}
	if DisplayServer.get_name() == "headless":
		return evidence
	var window_id := window.get_window_id()
	evidence.window_has_focus = window.has_focus()
	evidence.display_has_focus = DisplayServer.window_is_focused(window_id)
	evidence.display_no_focus = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, window_id)
	var actual_position := DisplayServer.window_get_position(window_id)
	var actual_size := DisplayServer.window_get_size(window_id)
	evidence.display_position = [actual_position.x, actual_position.y]
	evidence.display_size = [actual_size.x, actual_size.y]
	# Include a generous frame/decorations border in the intersection check.
	var bounds := Rect2i(actual_position, actual_size).grow(64)
	for screen in DisplayServer.get_screen_count():
		var monitor := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
		evidence.monitors.append([monitor.position.x, monitor.position.y, monitor.size.x, monitor.size.y])
		if bounds.intersects(monitor):
			evidence.geometry_off_desktop = false
	return evidence

func _settle_window_safety() -> Dictionary:
	var history: Array[Dictionary] = [_window_safety_evidence()]
	# Native focus/position notifications arrive at process boundaries. Wait at
	# least two, at most six, before accepting or refusing the existing checks.
	for frame in 6:
		await get_tree().process_frame
		history.append(_window_safety_evidence())
		if frame >= 1 and _window_off_desktop():
			break
	var evidence := _window_safety_evidence()
	# A hidden launch may never deliver a native focus-loss event. Both Godot
	# getters read the same cached Windows flag; resolve a persistent mismatch
	# once with read-only Win32 evidence, never with per-shot subprocess polling.
	if bool(evidence.geometry_off_desktop) and bool(evidence.unfocusable) and bool(evidence.get("display_no_focus", false)) \
		and (bool(evidence.window_has_focus) or bool(evidence.display_has_focus)) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
		and not _native_focus_checked and OS.get_name() == "Windows":
		_native_focus_checked = true
		_native_focus_evidence = _read_native_window_focus()
		_native_focus_verified = int(_native_focus_evidence.get("engine_pid", -1)) == OS.get_process_id() \
			and int(_native_focus_evidence.get("foreground_pid", 0)) > 0 \
			and _native_focus_evidence.get("engine_is_foreground") == false \
			and _native_focus_evidence.get("gui_query_ok") == true \
			and int(_native_focus_evidence.get("thread_capture_hwnd", 0)) == 0
	evidence["settle_samples"] = history
	evidence["native_focus_checked"] = _native_focus_checked
	evidence["native_focus_verified"] = _native_focus_verified
	evidence["native_focus"] = _native_focus_evidence.duplicate(true)
	return evidence

func _read_native_window_focus() -> Dictionary:
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_tree().root.get_window_id())
	var script := ProjectSettings.globalize_path("res://../.work/priorities-five/window_native_focus_probe.py")
	var output: Array = []
	# open_console=false: this helper only reads foreground/thread state.
	var status := OS.execute("python", PackedStringArray([script, str(OS.get_process_id()), str(handle)]), output, true, false)
	if status != 0 or output.is_empty():
		return {"error": "native focus probe failed", "exit_code": status, "output": str(output)}
	var parsed = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary or int(parsed.get("engine_hwnd", -1)) != handle:
		return {"error": "native focus probe returned invalid window evidence"}
	return parsed

func option(key_name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key_name + "="):
			return arg.substr(key_name.length() + 1)
	return fallback

func check(ok: bool, label: String) -> void:
	print("[priorities_session] %s %s: %s" % ["PASS" if ok else "FAIL", phase_name, label])
	passes += int(ok)
	failures += int(not ok)
	checks.append({"ok": ok, "phase": phase_name, "label": label})

func _watchdog() -> void:
	var duration := clampf(float(option("--session-seconds", "0")), 0.0, 14400.0)
	await get_tree().create_timer(duration + 600.0, true, false, true).timeout
	if not finished:
		check(false, "session watchdog expired")
		_finish()

func boot_world() -> bool:
	# Refuse before creating a world: graphical fixtures must explicitly opt into
	# validation so the production provider never reads or writes a real slot.
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--offscreen-validation"):
		check(false, "requires --headless or --offscreen-validation before scene creation")
		return false
	run_id = option("--session-run-id", "manual")
	if run_id.is_empty() or run_id.length() > 80:
		check(false, "invalid fixture run id")
		return false
	for character in run_id:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			check(false, "fixture run id contains path characters")
			return false
	output_dir = ProjectSettings.globalize_path("res://../.work/priorities-five/session-validation/" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	_cleanup()
	for file_name in ["result.json", "samples.jsonl"]:
		var previous: String = output_dir.path_join(file_name)
		if FileAccess.file_exists(previous):
			DirAccess.remove_absolute(previous)
	boot_usec = Time.get_ticks_usec()
	# Real LMB events use the explicit offscreen route in the level and combat;
	# no native mouse capture is needed, even on a rendered Windows backend.
	var window_evidence := await _settle_window_safety()
	var pointer_safe := Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and (DisplayServer.get_name() == "headless"
		or (_window_off_desktop() and get_tree().root.unfocusable))
	result_details["input_backend"] = window_evidence
	check(pointer_safe, "real LMB validation keeps desktop mouse visible and render window off-desktop/unfocused")
	if not pointer_safe:
		return false
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	for index in 1800:
		await frames(1)
		level = get_tree().current_scene as Node3D
		if level != null and level.get("level_ready") == true:
			break
	if level == null or level.get("level_ready") != true:
		check(false, "real exported world boots within bounded wait")
		return false
	# Level startup also places its window; reapply the all-monitor bound.
	_place_window_off_desktop()
	var world_window := await _settle_window_safety()
	result_details["world_window"] = world_window
	if not _window_off_desktop():
		check(false, "world startup retains off-desktop and unfocused render window")
		return false
	for manager in ["player", "shops", "progression", "driving", "law", "combat", "world_save", "traffic", "missions", "npcs", "residents"]:
		if level.get(manager) == null:
			check(false, "missing world manager " + manager)
			return false
	player = level.player
	check(level.get("offscreen_validation") == true, "explicit offscreen validation input route enabled")
	if level.get("offscreen_validation") != true:
		return false
	check(not level.world_save.enabled, "production user checkpoint provider disabled")
	if level.world_save.enabled:
		return false
	provider = Save.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	check(provider.enabled and provider.path == fixture, "isolated project test checkpoint enabled")
	# Root's normal 30-second autosave tick now reaches only this fixture path.
	# The original user-slot provider remains disabled and is never invoked.
	level.world_save = provider
	level.resume_exploring()
	for index in 600:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	check(int(level.residents.get_status().pending_routes) == 0, "daily resident routes finish")
	startup_position = player.global_position
	initial_population = {"ambient": int(level.npcs.crowd.get_status().total), "daily": int(level.residents.get_status().count), "traffic": level.traffic.vehicles.size()}
	check(initial_population.ambient == 1200 and initial_population.daily == 40 and initial_population.traffic == 90,
		"full 1200 ambient / 40 daily / 90 traffic population retained")
	check(level.is_physics_processing() and player.is_physics_processing(), "normal world and player processing enabled")
	return failures == 0

func held_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func _drive_steps(count: int) -> void:
	await frames(count)

func _law_steps(count: int) -> void:
	await frames(count)

func _walk_to(destination: Vector3) -> bool:
	player.set_orbiting(false)
	player._clear_basis_offset()
	Input.action_press("move_forward")
	Input.action_press("run")
	var reached := false
	var stalled := 0
	for step in 420:
		if flat_distance(player.global_position, destination) <= .22:
			reached = true
			break
		var before := player.global_position
		var toward := destination - before
		player.camera_yaw = atan2(toward.x, toward.z)
		await frames(1)
		stalled = stalled + 1 if flat_distance(before, player.global_position) < .001 else 0
		if stalled > 45 or absf(player.global_position.y - destination.y) > 4.0:
			break
	Input.action_release("move_forward")
	Input.action_release("run")
	return reached

func stand_near(target: Vector3, radius := 1.7, require_interaction := false, angle_offset := 0) -> bool:
	for turn in 16:
		var angle := float((turn + angle_offset) % 16) * TAU / 16.0
		var desired := target + Vector3(sin(angle), 0, cos(angle)) * radius
		var spot := Facilities.standing_at(level.get_world_3d().direct_space_state, desired, [player.get_rid()])
		if spot.is_empty():
			continue
		_set_scenario_position(spot.position)
		await frames(3)
		if not require_interaction or level.missions._can_interact(target):
			return true
	return false

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func begin_phase(label: String) -> void:
	phase_name = label
	observed_phases[label] = int(observed_phases.get(label, 0)) + 1
	print("[priorities_session] PHASE " + label)

func _sample_loop() -> void:
	var next_sample_usec := Time.get_ticks_usec() + 5000000
	while sampling and not finished:
		var delay := maxf(.001, float(next_sample_usec - Time.get_ticks_usec()) / 1000000.0)
		await get_tree().create_timer(delay, true, false, true).timeout
		var context := _metric_context()
		await frames(2)
		if sampling and not finished:
			_sample("periodic", context == _metric_context())
		next_sample_usec += 5000000

func _metric_context() -> String:
	if level._map_overlay.visible:
		return "map"
	if level.inspector.active:
		return "inspection"
	if level.shops.is_open():
		return "shop"
	if level._dialogue.state.active:
		return "dialogue"
	return "paused" if level.paused else "world"

func _orphan_inventory(raw_count: int) -> Dictionary:
	# Removed UI trees remain ObjectDB orphans until queue_free runs. Count only
	# nodes whose own/ancestor deletion flag proves that pending cleanup.
	var queued := 0
	var live_ids: Array[int] = []
	if raw_count > 0 and OS.is_debug_build():
		for id in Node.get_orphan_node_ids():
			var orphan := instance_from_id(id) as Node
			var cursor := orphan
			var pending := false
			while is_instance_valid(cursor):
				if cursor.is_queued_for_deletion():
					pending = true
					break
				cursor = cursor.get_parent()
			if pending:
				queued += 1
			else:
				live_ids.append(id)
	# Missing debug inventory never turns an unexplained orphan into a pass.
	return {"queued": queued, "unexplained": maxi(0, raw_count - queued), "live_ids": live_ids}

func _sample(kind := "periodic", render_context_stable := false) -> void:
	if not is_instance_valid(level) or level.get("level_ready") != true:
		return
	var traffic_status: Dictionary = level.traffic.get_status()
	var law_status: Dictionary = level.law.get_status()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var orphan_inventory := _orphan_inventory(orphan_count)
	var sample := {"wall_seconds": float(Time.get_ticks_usec() - boot_usec) / 1000000.0,
		"phase": phase_name, "clock_seconds": float(level.world_time.elapsed_seconds),
		"sample_kind": kind, "render_context": _metric_context(), "render_context_stable": render_context_stable,
		"render_frame": Engine.get_frames_drawn(),
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"camera_yaw": player.camera_yaw, "camera_pitch": player.camera_pitch,
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": orphan_count, "orphan_inventory": orphan_inventory,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"ambient": int(level.npcs.crowd.get_status().total), "daily": int(level.residents.get_status().count),
		"traffic": level.traffic.vehicles.size(), "traffic_distance": float(traffic_status.distance_travelled),
		"player_fleet": int(traffic_status.player_fleet), "wanted": int(law_status.wanted),
		"cruisers": law_status.get("cruisers", {}), "rendered": DisplayServer.get_name() != "headless"}
	samples.append(sample)
	var stream := FileAccess.open(output_dir.path_join("samples.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(output_dir.path_join("samples.jsonl")) else FileAccess.WRITE)
	if stream != null:
		stream.seek_end()
		stream.store_line(JSON.stringify(sample))
		stream.flush()

func _finish() -> void:
	if finished:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished = true
	sampling = false
	for action in ["move_forward", "move_back", "move_left", "move_right", "run"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = false
		Input.parse_input_event(event)
	if not output_dir.is_empty():
		var output := FileAccess.open(output_dir.path_join("result.json"), FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify({"complete": true, "passed": failures == 0, "passes": passes, "failures": failures,
				"checks": checks, "phases": observed_phases, "samples": samples.size(), "checkpoint": fixture,
				"details": result_details,
				"wall_seconds": float(Time.get_ticks_usec() - boot_usec) / 1000000.0}, "\t"))
			output.flush()
	print("[priorities_session] COMPLETE %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
