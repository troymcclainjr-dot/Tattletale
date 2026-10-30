extends Node
## Measures wall-clock frame delivery while real input moves the explorer on the route.
## Leaves NPCs, traffic, HUD, collisions and the normal chase camera running.
const WARMUP_FRAMES := 120
var sample_seconds := 7.0
var render_size := Vector2i(1280, 720)
var output := "res://../.work/city/life_benchmark"
var level: Node3D
var _walking := false
var _route: Array[Vector3] = []
var _waypoint := 1
var _progress_elapsed := 0.0
var _progress_position := Vector3.ZERO
var _stalled_seconds := 0.0
var _stalled_windows := 0
var start_route_index := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	index = args.find("--start-route-index")
	if index >= 0:
		if index + 1 >= args.size() or not args[index + 1].is_valid_int():
			_fail("--start-route-index requires a nonnegative integer")
			return
		start_route_index = int(args[index + 1])
	for option in ["--render-width", "--render-height", "--sample-seconds"]:
		index = args.find(option)
		if index < 0:
			continue
		if index + 1 >= args.size() or not args[index + 1].is_valid_int():
			_fail(option + " requires an integer value")
			return
		var value := int(args[index + 1])
		if option == "--sample-seconds":
			if value < 5 or value > 30:
				_fail("--sample-seconds must be between 5 and 30")
				return
			sample_seconds = float(value)
		else:
			var minimum := 640 if option == "--render-width" else 360
			var maximum := 3840 if option == "--render-width" else 2160
			if value < minimum or value > maximum:
				_fail("%s must be between %d and %d" % [option, minimum, maximum])
				return
			if option == "--render-width":
				render_size.x = value
			else:
				render_size.y = value
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	if not _walking or level == null or _route.is_empty():
		return
	var here: Vector3 = level.player.global_position
	_progress_elapsed += delta
	if _progress_elapsed >= 0.5:
		var moved := Vector2(here.x - _progress_position.x, here.z - _progress_position.z).length()
		# A half-second window below 20 cm/s is effectively stopped, even if
		# collision jitter increments the player's total distance counter.
		if moved < 0.2 * _progress_elapsed:
			_stalled_seconds += _progress_elapsed
			_stalled_windows += 1
		_progress_position = here
		_progress_elapsed = 0.0
	while _waypoint < _route.size() - 1 and Vector2(here.x - _route[_waypoint].x, here.z - _route[_waypoint].z).length() < 0.35:
		_waypoint += 1
	var toward: Vector3 = _route[_waypoint] - here
	level.player.look(Vector2(-angle_difference(level.player.camera_yaw, atan2(toward.x, toward.z)) / level.player.mouse_sensitivity, 0.0))

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _fail(message: String) -> void:
	Input.action_release("move_forward")
	_walking = false
	push_error("[city_life_benchmark] " + message)
	get_tree().quit(1)

func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var count := sorted.size()
	return {"median": sorted[int(count / 2)], "p95": sorted[mini(count - 1, ceili(count * 0.95) - 1)], "min": sorted[0], "max": sorted[count - 1]}

func _save_image(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
	if error != OK:
		push_error("[city_life_benchmark] Could not write " + filename)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Run graphically: headless timings do not measure rendered play")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var started := Time.get_ticks_msec()
	if get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn") != OK:
		_fail("Neighborhood scene could not load")
		return
	await frames(5)
	level = get_tree().current_scene
	if level == null or level.get("level_ready") == null:
		_fail("Neighborhood initialization failed")
		return
	for i in 600:
		if level.level_ready:
			break
		await frames(1)
	if not level.level_ready:
		_fail("Neighborhood did not initialize within 600 rendered frames")
		return
	var startup_ms := Time.get_ticks_msec() - started
	var args := OS.get_cmdline_user_args()
	var quality := "balanced"
	var quality_index := args.find("--render-quality")
	if quality_index >= 0 and quality_index + 1 < args.size():
		quality = args[quality_index + 1]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var window := get_tree().root
	# Fix the render target itself, not just the OS window. The project's default
	# 1600x900 canvas stretch and display scaling can make these sizes differ.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = render_size
	window.content_scale_factor = 1.0
	window.size = render_size
	window.scaling_3d_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if level.render_optimizer != null:
		level.render_optimizer.set_quality(quality)
	level.spawn_player()
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Startup shader compilation is outside the sample; the world remains active.
	await frames(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	var verified_render_size := get_viewport().get_texture().get_image().get_size()
	if verified_render_size != render_size or not is_equal_approx(window.scaling_3d_scale, 1.0):
		_fail("Render target mismatch: requested %s, actual image %s, window %s, 3D scale %s" % [render_size, verified_render_size, window.size, window.scaling_3d_scale])
		return
	for point in level.level_data.get("route", {}).get("points", []):
		_route.append(level.vector(point))
	if _route.size() < 2:
		_fail("A walk route is required")
		return
	if start_route_index < 0 or start_route_index >= _route.size() - 1:
		_fail("Start route index is outside the walking route")
		return
	if start_route_index > 0:
		var toward: Vector3 = _route[start_route_index + 1] - _route[start_route_index]
		level._place_player(_route[start_route_index], atan2(toward.x, toward.z))
		_waypoint = start_route_index + 1
		level.streaming.refresh_now()
		for i in 900:
			if level.streaming.get_status().near_cells_missing == 0:
				break
			await frames(1)
		await frames(WARMUP_FRAMES)
	await _save_image("walk_start.png")
	var before: Vector3 = level.player.global_position
	var distance_before: float = level.player.distance_walked
	var npc_before: float = level.npcs._elapsed
	var car_distance_before := 0.0
	for car in level.traffic.vehicles:
		car_distance_before += car.distance_travelled
	var timings: Array[float] = []
	var draw_calls: Array[float] = []
	var physics_cost: Array[float] = []
	var process_cost: Array[float] = []
	var physics_start := Engine.get_physics_frames()
	var began := Time.get_ticks_usec()
	var previous := began
	var any_paused := false
	_progress_position = before
	_progress_elapsed = 0.0
	_stalled_seconds = 0.0
	_stalled_windows = 0
	_walking = true
	Input.action_press("move_forward")
	while Time.get_ticks_usec() - began < int(sample_seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		timings.append(float(now - previous) / 1000.0)
		previous = now
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		physics_cost.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_cost.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		any_paused = any_paused or bool(level.paused)
	Input.action_release("move_forward")
	_walking = false
	var duration := float(previous - began) / 1000000.0
	var physics_frames := Engine.get_physics_frames() - physics_start
	var distance: float = level.player.distance_walked - distance_before
	var frame_ms := _distribution(timings)
	var car_distance := -car_distance_before
	for car in level.traffic.vehicles:
		car_distance += car.distance_travelled
	var npc_status: Dictionary = level.npcs.get_status()
	var valid: bool = not any_paused and distance >= sample_seconds * 1.5 and level.npcs._elapsed - npc_before > sample_seconds * 0.8 and car_distance > 1.0 and _stalled_seconds <= 1.0
	var window_size := DisplayServer.window_get_size()
	var texture_size := get_viewport().get_texture().get_size()
	var image_size := get_viewport().get_texture().get_image().get_size()
	var viewport_size := get_viewport().get_visible_rect().size
	valid = valid and image_size == render_size and is_equal_approx(window.scaling_3d_scale, 1.0)
	var report := {
		"valid_active_play": valid, "startup_ms": startup_ms, "quality": quality,
		"requested_resolution": [render_size.x, render_size.y], "resolution": [image_size.x, image_size.y],
		"texture_size": [texture_size.x, texture_size.y], "render_scale": window.scaling_3d_scale,
		"content_scale_mode": window.content_scale_mode, "content_scale_factor": window.content_scale_factor,
		"window_size": [window_size.x, window_size.y], "viewport_size": [viewport_size.x, viewport_size.y],
		"vsync": false, "fps_cap": 0, "warmup_frames": WARMUP_FRAMES,
		"sample_seconds": duration, "rendered_frames": timings.size(), "physics_frames": physics_frames,
		"delivered_fps": timings.size() / maxf(duration, 0.001), "physics_fps": physics_frames / maxf(duration, 0.001),
		"frame_ms": frame_ms, "median_fps": 1000.0 / maxf(float(frame_ms.median), 0.001),
		"p95_frame_equivalent_fps": 1000.0 / maxf(float(frame_ms.p95), 0.001),
		"worst_frame_equivalent_fps": 1000.0 / maxf(float(frame_ms.max), 0.001),
		"draw_calls": _distribution(draw_calls), "physics_cpu_ms": _distribution(physics_cost), "process_cpu_ms": _distribution(process_cost),
		"player_distance_m": distance, "player_start": [before.x, before.y, before.z],
		"elapsed_stalled_seconds": _stalled_seconds, "stalled_half_second_windows": _stalled_windows,
		"minimum_distance_m": sample_seconds * 1.5, "maximum_allowed_stall_seconds": 1.0,
		"player_end": [level.player.global_position.x, level.player.global_position.y, level.player.global_position.z],
		"route_waypoint_start": start_route_index, "route_waypoint_reached": _waypoint, "paused_during_sample": any_paused,
		"npc_simulated_seconds": level.npcs._elapsed - npc_before, "npc_count": npc_status.count,
		"streaming": level.streaming.get_status() if level.streaming != null else {},
		"neighborhood_details": level.neighborhood_details.get_status() if level.neighborhood_details != null else {},
		"vegetation": level.vegetation.get_stats() if level.vegetation != null else {},
		"parked_cars": level.traffic.parked.get_status() if level.traffic.parked != null else {},
		"crowd": npc_status.crowd, "cars": level.traffic.vehicles.size(), "traffic_distance_m": car_distance,
		"optimization_disabled": args.has("--no-city-optimization"),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"notes": "Wall-clock frames during actual forward input; active collision, normal chase camera, HUD, NPCs and traffic. Half-second movement windows detect stalls; more than one cumulative stalled second invalidates play. CPU monitor samples are renderer-frame observations. Screenshot writes excluded from timing."
	}
	var file := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write metrics.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	await _save_image("walk_end.png")
	print("[city_life_benchmark] " + JSON.stringify(report))
	get_tree().quit(0 if valid else 1)
