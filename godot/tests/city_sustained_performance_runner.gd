extends "res://tests/city_priorities_session_fixture.gd"
## Bounded real-renderer workload. Only phase setup relocates the player/time;
## ordinary clock, traffic, residents, physics, rendering and autosaves stay live.
const Stats := preload("res://tools/city_perf_stats.gd")
var collecting := false
var duration := 180.0
var sample_started := 0
var previous_frame := 0
var frame_rows: Array[Array] = []
var columns := {"frame_ms": [], "gpu_ms": [], "render_cpu_ms": [], "draw_calls": []}
var phase_frames: Dictionary = {}
var phase_results: Array[Dictionary] = []
var route: Array[Vector3] = []
var waypoint := 1
var walking := false
var any_paused := false
var walked_before := 0.0
var stream_failures := 0
var finishing := false

func _watchdog() -> void:
	# Includes startup; outer launcher independently kills/reaps a stalled engine.
	await get_tree().create_timer(480.0, true, false, true).timeout
	if not finished:
		check(false, "480-second hard fixture watchdog")
		_finish()

func _process(_delta: float) -> void:
	if not collecting:
		return
	var now := Time.get_ticks_usec()
	var row: Array = [float(now - sample_started) / 1000000.0, phase_name,
		float(now - previous_frame) / 1000.0,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
	previous_frame = now
	frame_rows.append(row)
	for index in columns.size():
		columns[columns.keys()[index]].append(float(row[index + 2]))
	if not phase_frames.has(phase_name):
		phase_frames[phase_name] = []
	phase_frames[phase_name].append(float(row[2]))
	any_paused = any_paused or bool(level.paused) or get_tree().paused

func _physics_process(_delta: float) -> void:
	if not walking or route.is_empty():
		return
	var here: Vector3 = player.global_position
	while waypoint < route.size() - 1 and flat_distance(here, route[waypoint]) < .4:
		waypoint += 1
	if flat_distance(here, route[waypoint]) < .4:
		Input.action_release("move_forward")
		walking = false
		return
	var toward := route[waypoint] - here
	player.look(Vector2(-angle_difference(player.camera_yaw, atan2(toward.x, toward.z)) / player.mouse_sensitivity, 0.0))

func _run() -> void:
	duration = clampf(float(option("--sustained-seconds", "180")), 180.0, 300.0)
	if DisplayServer.get_name() == "headless":
		check(false, "requires a real renderer")
		_finish()
		return
	if not await boot_world():
		_finish()
		return
	for point in level.level_data.route.points:
		route.append(level.vector(point))
	check(route.size() > 105, "authored sidewalk traversal route available")
	if failures > 0:
		_finish()
		return
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.size = Vector2i(1280, 720)
	window.scaling_3d_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	player.camera.fov = 68.0
	level.render_optimizer.set_quality("balanced")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().create_timer(5.0, true, false, true).timeout
	begin_phase("warm_baseline")
	_sample("baseline", true)
	walked_before = player.distance_walked
	for values in level.physics_samples.values():
		values.clear()
	level.process_samples.clear()
	level.profile_physics = true
	sample_started = Time.get_ticks_usec()
	previous_frame = sample_started
	collecting = true
	sampling = true
	_sample_loop()
	var unix_start := Time.get_unix_time_from_system()
	print("[sustained_performance] SAMPLE_BEGIN unix=%.3f" % unix_start)
	# Each district is revisited under matching daylight/night conditions.
	for phase in 8:
		if failures > 0 or finished:
			break
		var district := phase % 4
		var names := ["wyanoke", "dumbarton", "rose_hill_cator", "greenmount"]
		begin_phase(str(names[district]) + ("_day" if phase < 4 else "_night"))
		level.world_time.set_time(600.0 if phase < 4 else 1260.0)
		if district < 3:
			var starts := [0, 63, 103]
			var start: int = starts[district]
			_set_scenario_position(route[start])
			waypoint = start + 1
			walking = true
			Input.action_press("move_forward")
		else:
			_set_scenario_position(level.vector(level.level_data.landmarks[4].position))
			walking = false
			Input.action_release("move_forward")
		var phase_start := Time.get_ticks_usec()
		var start_position: Vector3 = player.global_position
		var start_walked: float = player.distance_walked
		var phase_deadline := sample_started + int(duration * float(phase + 1) / 8.0 * 1000000.0)
		var phone_at := phase_deadline - 6000000
		var phone_opened := false
		while Time.get_ticks_usec() < phase_deadline and not finished:
			if not phone_opened and Time.get_ticks_usec() >= phone_at:
				walking = false
				Input.action_release("move_forward")
				await key(KEY_P)
				await key(KEY_2)
				phone_opened = true
				check(player.phone.get_status().active and player.phone.get_status().page == "camera", "real P/2 opens phone camera without pausing")
			if not walking:
				player.look(Vector2(.3, 0.0))
			await get_tree().process_frame
		if phone_opened:
			await key(KEY_P)
			check(not player.phone.get_status().active, "real P closes phone")
		walking = false
		Input.action_release("move_forward")
		var moved: float = player.distance_walked - start_walked
		if district < 3:
			check(moved > 2.0 and flat_distance(start_position, player.global_position) > 1.0, "normal collision-aware player input traversed district")
		var stream: Dictionary = level.streaming.get_status()
		stream_failures += int(stream.get("failed_cells", stream.get("failures", 0)))
		phase_results.append({"phase": phase_name, "wall_seconds": float(Time.get_ticks_usec() - phase_start) / 1000000.0,
			"walked_m": moved, "streaming": stream, "traffic": level.traffic.get_status(),
			"clock": level.world_time.get_status(), "player_position": player.global_position})
		_sample("phase_boundary", true)
	collecting = false
	sampling = false
	level.profile_physics = false
	var seconds := float(Time.get_ticks_usec() - sample_started) / 1000000.0
	print("[sustained_performance] SAMPLE_END unix=%.3f" % Time.get_unix_time_from_system())
	check(seconds >= duration and seconds < duration + 10.0, "requested real duration completed within bounded overrun")
	check(not any_paused and not level.world_time.frozen, "world never paused or clock frozen during sample")
	check(phase_results.size() == 8 and stream_failures == 0, "all eight district/light phases completed without stream failures")
	check(float(level.world_time.elapsed_seconds) - float(samples.front().clock_seconds) > duration * .4, "normal simulation clock advanced")
	check(float(samples.back().traffic_distance) - float(samples.front().traffic_distance) > 50.0, "live traffic covered distance")
	check(float(Stats.distribution(columns.draw_calls).get("min", 0)) > 0.0, "renderer submitted draw calls throughout sample")
	for sample in samples:
		if int(sample.ambient) != 1200 or int(sample.daily) != 40 or int(sample.traffic) != 90:
			check(false, "population changed during sustained sample")
	var distributions := {}
	for column in columns:
		distributions[column] = Stats.distribution(columns[column])
	var by_phase := {}
	for label in phase_frames:
		by_phase[label] = Stats.distribution(phase_frames[label])
	result_details["sustained"] = {"schema": 3, "requested_seconds": duration, "measured_seconds": seconds,
		"unix_start": unix_start, "unix_end": Time.get_unix_time_from_system(),
		"frame_metrics": distributions, "phase_frame_ms": by_phase, "phases": phase_results,
		"physics_components_ms": Stats.summarize_columns(level.physics_samples, seconds),
		"walked_m": player.distance_walked - walked_before,
		"frame_trace_columns": ["seconds", "phase", "frame_ms", "gpu_ms", "render_cpu_ms", "draw_calls"],
		"notes": "1280x720 balanced, scale 1, FOV 68, uncapped, real renderer. Phase setup relocates player and sets daylight; normal clock rate remains unchanged. Greenmount is a stationary intersection camera sweep. Phone camera preview uses real P/2 input; no photo readback during timed samples. GPU timestamps may lag. The traffic CPU bucket includes bicycle/reactions, basketball, police assistance, incidents, driving and vehicle presentation. Memory trend includes retained fixture measurement arrays; process telemetry is external."}
	var trace := FileAccess.open(output_dir.path_join("frames.json"), FileAccess.WRITE)
	if trace != null:
		trace.store_string(JSON.stringify(frame_rows))
		trace.close()
	_finish()

func _finish() -> void:
	if finishing or finished:
		return
	finishing = true
	collecting = false
	sampling = false
	walking = false
	for action in ["move_forward", "move_back", "move_left", "move_right", "run"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	if is_instance_valid(level):
		level.profile_physics = false
	if is_instance_valid(player) and player.get("phone") != null:
		player.phone.suspend()
	# All measurement has ended. Let the renderer remove visible geometry/light
	# pairings before destroying the world; don't leave its first teardown to
	# SceneTree destruction after quit. The external runner still bounds hangs.
	if is_instance_valid(level):
		level.process_mode = Node.PROCESS_MODE_DISABLED
		level.hide()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		result_details["teardown"] = {"version": 3, "world_released": not is_instance_valid(level)}
		check(not is_instance_valid(level), "world released before engine shutdown")
	# stop() schedules mixer-side release. Drain before quitting, outside every
	# measurement interval; autoload _exit_tree runs too late for this guarantee.
	var stopped := 0
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for audio_player in get_tree().root.find_children("*", kind, true, false):
			audio_player.stop()
			stopped += 1
	await get_tree().create_timer(0.1, true, false, true).timeout
	result_details["audio_drain"] = {"version": 3, "players_stopped": stopped, "minimum_seconds": 0.1}
	super._finish()

func _metric_context() -> String:
	# The inherited periodic coroutine may wake while graceful teardown awaits
	# a frame. It must not read a freed world even though sampling is stopped.
	if finishing or not is_instance_valid(level):
		return "teardown"
	return super._metric_context()
