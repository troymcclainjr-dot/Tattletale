extends "res://tests/city_priorities_session_fixture.gd"
## Bounded real-renderer workload. Only phase setup relocates the player/time;
## ordinary clock, traffic, residents, physics, rendering and autosaves stay live.
const Stats := preload("res://tools/city_perf_stats.gd")
const Timeline := preload("res://tools/city_perf_timeline.gd")
class PhysicsMark extends Node:
	var timeline
	var last := false
	func _physics_process(_delta: float) -> void:
		if last:
			timeline.physics_end(Time.get_ticks_usec())
		else:
			timeline.physics_begin(Time.get_ticks_usec())
class ProcessMark extends Node:
	var timeline
	var last := false
	func _process(_delta: float) -> void:
		if last:
			timeline.process_end(Time.get_ticks_usec())
		else:
			timeline.process_begin(Time.get_ticks_usec())
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
var profile_transitions := false
var relocation_samples: Array[Dictionary] = []
var pipeline_monitors: Array[int] = []
var _profile_process_start := 0
var _profile_draw_start := 0
var _profile_draw_end := 0
var _profile_process_to_draw_ms := 0.0
var _profile_draw_ms := 0.0
var _profile_between_frames_ms := 0.0
var _timeline: Timeline
var _profile_player_cursor := 0

static func _sweep_pixels(elapsed_usec: int) -> float:
	# Preserve the old 0.3-pixel step at nominal 60 Hz, not at renderer FPS.
	return maxf(0.0, float(elapsed_usec)) * 0.000018

func _watchdog() -> void:
	# Includes startup; outer launcher independently kills/reaps a stalled engine.
	var deadline := clampf(float(option("--sustained-seconds", "180")), 0.0, 900.0) + 360.0
	await get_tree().create_timer(deadline, true, false, true).timeout
	if not finished:
		check(false, "duration plus startup-headroom fixture watchdog")
		_finish()

func _process(_delta: float) -> void:
	if not collecting:
		return
	var now := Time.get_ticks_usec()
	var row: Array = [float(now - sample_started) / 1000000.0, phase_name,
		float(now - previous_frame) / 1000.0,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		Engine.get_process_frames(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 if profile_transitions else 0.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0 if profile_transitions else 0.0]
	for monitor in pipeline_monitors:
		row.append(Performance.get_monitor(monitor) if monitor >= 0 else -1.0)
	row.append(RenderingServer.get_frame_setup_time_cpu() if profile_transitions else 0.0)
	row.append(_profile_process_to_draw_ms)
	row.append(_profile_draw_ms)
	row.append(_profile_between_frames_ms)
	var player_cost := 0.0
	if profile_transitions:
		for index in range(_profile_player_cursor, player.profile_samples.size()):
			player_cost += float(player.profile_samples[index])
		_profile_player_cursor = player.profile_samples.size()
	row.append(player_cost)
	if _timeline != null and _timeline.cycles() > 0:
		row.append_array(Array(_timeline.row(_timeline.cycles() - 1)))
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
	profile_transitions = OS.get_cmdline_user_args().has("--profile-transitions")
	var transition_probe := OS.get_cmdline_user_args().has("--transition-probe")
	duration = clampf(float(option("--sustained-seconds", "180")), 32.0 if transition_probe else 180.0, 120.0 if transition_probe else 900.0)
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
	var render_resolution := Vector2i(int(option("--render-width", "1280")), int(option("--render-height", "720")))
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = render_resolution
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.size = render_resolution
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
	_begin_transition_profile()
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
			var initial_direction := route[start + 1] - route[start]
			player.camera_yaw = atan2(initial_direction.x, initial_direction.z)
			_set_scenario_position(route[start])
			waypoint = start + 1
			walking = true
			Input.action_press("move_forward")
		else:
			# The stationary view must not inherit the previous phase's sweep.
			player.camera_yaw = 0.0
			_set_scenario_position(level.vector(level.level_data.landmarks[4].position))
			walking = false
			Input.action_release("move_forward")
		var phase_start := Time.get_ticks_usec()
		var start_position: Vector3 = player.global_position
		var start_walked: float = player.distance_walked
		var phase_deadline := sample_started + int(duration * float(phase + 1) / 8.0 * 1000000.0)
		var phone_at := phase_deadline - (1000000 if transition_probe else 6000000)
		var phone_opened := false
		var sweep_started := 0
		var sweep_initial_yaw := 0.0
		var phase_initial_yaw: float = player.camera_yaw
		while Time.get_ticks_usec() < phase_deadline and not finished:
			if not phone_opened and Time.get_ticks_usec() >= phone_at:
				walking = false
				Input.action_release("move_forward")
				await key(KEY_P)
				await key(KEY_2)
				phone_opened = true
				check(player.phone.get_status().active and player.phone.get_status().page == "camera", "real P/2 opens phone camera without pausing")
			if not walking:
				var now := Time.get_ticks_usec()
				if sweep_started == 0:
					sweep_started = now
					sweep_initial_yaw = player.camera_yaw
				var target_yaw: float = sweep_initial_yaw - _sweep_pixels(now - sweep_started) * player.mouse_sensitivity
				player.look(Vector2((player.camera_yaw - target_yaw) / player.mouse_sensitivity, 0.0))
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
			"clock": level.world_time.get_status(), "player_position": player.global_position,
			"camera_initial_yaw": phase_initial_yaw, "camera_final_yaw": player.camera_yaw})
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
		"camera_sweep": {"schema": 2, "pixels_per_second": 18.0, "clock": "elapsed_wall_usec", "phase_heading": "route_tangent_or_zero"},
		"render_resolution": [render_resolution.x, render_resolution.y],
		"diagnostic_only": transition_probe,
		"unix_start": unix_start, "unix_end": Time.get_unix_time_from_system(),
		"frame_metrics": distributions, "phase_frame_ms": by_phase, "phases": phase_results,
		"physics_components_ms": Stats.summarize_columns(level.physics_samples, seconds),
		"walked_m": player.distance_walked - walked_before,
		"frame_trace_columns": ["seconds", "phase", "frame_ms", "gpu_ms", "render_cpu_ms", "draw_calls", "process_frame", "process_cpu_ms", "physics_cpu_ms", "pipeline_canvas", "pipeline_mesh", "pipeline_surface", "pipeline_draw", "pipeline_specialization", "render_setup_cpu_ms", "process_to_predraw_ms", "predraw_to_postdraw_ms", "postdraw_to_process_ms", "player_physics_cpu_ms"] + (Array(Timeline.COLUMNS) if profile_transitions else []),
		"transition_profiling": profile_transitions, "relocations": relocation_samples,
		"player_stages": player.get("profile_stages"), "player_slow_stages": player.get("profile_slow_stages"),
		"timeline_columns_after_player_cpu": Timeline.COLUMNS, "timeline_anomalies": _timeline.anomalies if _timeline != null else 0,
		"notes": "Explicit render_resolution, balanced, scale 1, FOV 68, uncapped, real renderer. Phase setup relocates player and sets daylight; normal clock rate remains unchanged. Greenmount is a stationary intersection camera sweep. Phone camera preview uses real P/2 input; no photo readback during timed samples. GPU timestamps may lag. The traffic CPU bucket includes bicycle/reactions, basketball, police assistance, incidents, driving and vehicle presentation. Memory trend includes retained fixture measurement arrays; process telemetry is external."}
	var trace := FileAccess.open(output_dir.path_join("frames.json"), FileAccess.WRITE)
	if trace != null:
		trace.store_string(JSON.stringify(frame_rows))
		trace.close()
	_finish()

func _begin_transition_profile() -> void:
	pipeline_monitors.clear()
	for monitor in ["PIPELINE_COMPILATIONS_CANVAS", "PIPELINE_COMPILATIONS_MESH", "PIPELINE_COMPILATIONS_SURFACE", "PIPELINE_COMPILATIONS_DRAW", "PIPELINE_COMPILATIONS_SPECIALIZATION"]:
		pipeline_monitors.append(ClassDB.class_get_integer_constant("Performance", monitor) if profile_transitions and ClassDB.class_has_integer_constant("Performance", monitor) else -1)
	if profile_transitions:
		_timeline = Timeline.new()
		_timeline.start(Time.get_ticks_usec())
		_timeline.driver_done(Time.get_ticks_usec())
		for last in [false, true]:
			var physics_mark := PhysicsMark.new()
			physics_mark.timeline = _timeline
			physics_mark.last = last
			physics_mark.process_physics_priority = 2000000000 if last else -2000000000
			add_child(physics_mark)
			var process_mark := ProcessMark.new()
			process_mark.timeline = _timeline
			process_mark.last = last
			process_mark.process_priority = 2000000000 if last else -2000000000
			add_child(process_mark)
		player.profile_costs = true
		player.profile_samples.clear()
		if player.get("profile_stages") != null:
			player.profile_stages.clear()
			player.profile_slow_stages.clear()
		get_tree().physics_frame.connect(_profile_physics_signal)
		get_tree().process_frame.connect(_profile_process_begin)
		RenderingServer.frame_pre_draw.connect(_profile_predraw)
		RenderingServer.frame_post_draw.connect(_profile_postdraw)
	if profile_transitions and is_instance_valid(level.streaming) and level.streaming.get("profile_streaming") != null:
		level.streaming.profile_stages.clear()
		level.streaming.profile_slow_stages.clear()
		level.streaming.profile_unload_batches = {"max_cells": 0, "max_frame": 0}
		level.streaming.profile_streaming = true

func _profile_process_begin() -> void:
	_profile_process_start = Time.get_ticks_usec()
	if _timeline != null:
		_timeline.process_frame(_profile_process_start)
		_timeline.driver_done(Time.get_ticks_usec())
	if _profile_draw_end > 0:
		_profile_between_frames_ms = float(_profile_process_start - _profile_draw_end) / 1000.0

func _profile_predraw() -> void:
	_profile_draw_start = Time.get_ticks_usec()
	if _timeline != null:
		_timeline.draw_begin(_profile_draw_start)
	if _profile_process_start > 0:
		_profile_process_to_draw_ms = float(_profile_draw_start - _profile_process_start) / 1000.0

func _profile_postdraw() -> void:
	_profile_draw_end = Time.get_ticks_usec()
	if _timeline != null:
		_timeline.draw_end(_profile_draw_end)
	if _profile_draw_start > 0:
		_profile_draw_ms = float(_profile_draw_end - _profile_draw_start) / 1000.0

func _profile_physics_signal() -> void:
	if _timeline != null:
		_timeline.physics_frame(Time.get_ticks_usec())

func _set_scenario_position(at: Vector3) -> void:
	if not profile_transitions:
		super._set_scenario_position(at)
		return
	# Same synchronous relocation as city_sandbox_world_smoke_runner, split only
	# for attribution. Collision presence is still ready before returning.
	var began := Time.get_ticks_usec()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.reset_jump()
	player.update_camera()
	var player_done := Time.get_ticks_usec()
	level.npcs.crowd.set_presence(at)
	var crowd_done := Time.get_ticks_usec()
	level.traffic._update_presence()
	var ended := Time.get_ticks_usec()
	var overlaps: Array[String] = []
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._capsule.shape
	query.transform = player._capsule.global_transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, 32):
		overlaps.append(str(hit.collider.get_path()))
	var ground_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 3.0, 1 | 2, [player.get_rid()])
	var ground := player.get_world_3d().direct_space_state.intersect_ray(ground_query)
	relocation_samples.append({"phase": phase_name, "process_frame": Engine.get_process_frames(),
		"player_usec": player_done - began, "crowd_usec": crowd_done - player_done,
		"traffic_presence_usec": ended - crowd_done, "total_usec": ended - began,
		"spawn_position": str(at), "spawn_overlaps": overlaps,
		"support_position": str(ground.position) if not ground.is_empty() else "none",
		"support_collider": str(ground.collider.get_path()) if not ground.is_empty() else "none"})

func _finish() -> void:
	if finishing or finished:
		return
	finishing = true
	collecting = false
	if _timeline != null:
		_timeline.stop()
	if is_instance_valid(player):
		player.profile_costs = false
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
