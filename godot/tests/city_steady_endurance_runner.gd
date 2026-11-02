extends "res://tests/city_sustained_performance_runner.gd"
## Same-neighborhood endurance. Fixed histograms replace retained frame arrays;
## per-physics timing arrays stay disabled, and five-second samples are bounded
## by the 900-second maximum. Normal NPCs, traffic, clock and saves remain live.
class Histogram:
	extends RefCounted
	const BIN_COUNT := 20001
	var bins := PackedInt64Array()
	var count := 0
	var total := 0.0
	var minimum := INF
	var maximum := 0.0
	var width := 0.1
	var overflow := 0
	func _init(bin_width := 0.1) -> void:
		width = bin_width
		bins.resize(BIN_COUNT)
	func record(value: float) -> void:
		count += 1
		total += value
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		var index := ceili(maxf(0.0, value) / width)
		if index >= BIN_COUNT:
			overflow += 1
		bins[mini(index, BIN_COUNT - 1)] += 1
	func percentile(fraction: float) -> float:
		var target := ceili(count * fraction)
		var seen := 0
		for index in bins.size():
			seen += bins[index]
			if seen >= target:
				if index == BIN_COUNT - 1 and overflow > 0:
					return maximum # Saturated tail still reports an upper bound.
				return index * width
		return maximum
	func distribution() -> Dictionary:
		return {"count": count, "min": minimum if count else 0.0, "max": maximum,
			"mean": total / maxf(count, 1), "sum": total,
			"median": percentile(.5), "p95": percentile(.95), "p99": percentile(.99),
			"percentile_bin_width": width, "overflow": overflow,
			"percentiles_are_bin_upper_bounds": true}

var histograms: Dictionary = {}
var steady_mode := "stationary"
var loop_direction := 1
var loops_completed := 0
var maximum_displacement := 0.0
var steady_origin := Vector3.ZERO
const SLOW_FRAME_THRESHOLD_MS := 50.0
const MAX_SLOW_FRAMES := 32
var slow_frames: Array[Dictionary] = []
var slow_frame_count := 0

func _process(_delta: float) -> void:
	if not collecting:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - previous_frame) / 1000.0
	histograms.frame_ms.record(frame_ms)
	previous_frame = now
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var render_cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
	var draw_calls := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	histograms.gpu_ms.record(gpu_ms)
	histograms.render_cpu_ms.record(render_cpu_ms)
	histograms.draw_calls.record(draw_calls)
	if frame_ms > SLOW_FRAME_THRESHOLD_MS:
		_record_slow_frame(now, frame_ms, render_cpu_ms, gpu_ms, draw_calls)
	maximum_displacement = maxf(maximum_displacement, flat_distance(player.global_position, steady_origin))
	any_paused = any_paused or bool(level.paused) or get_tree().paused

func _record_slow_frame(now: int, frame_ms: float, render_cpu_ms: float, gpu_ms: float, draw_calls: float) -> void:
	slow_frame_count += 1
	# Keep only the worst bounded tail, sorted descending. No log/file writes or
	# world-status scans in the measured frame; ordinary frames allocate no row.
	if slow_frames.size() >= MAX_SLOW_FRAMES and frame_ms <= float(slow_frames.back().frame_ms):
		return
	var unix_end := Time.get_unix_time_from_system()
	var row := {"unix": unix_end, "unix_interval_start": unix_end - frame_ms / 1000.0,
		"elapsed_seconds": float(now - sample_started) / 1000000.0,
		"process_frame": Engine.get_process_frames(), "frame_ms": frame_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": render_cpu_ms, "gpu_ms": gpu_ms, "draw_calls": draw_calls}
	# These public scalars update after a successful write; the saved timestamp
	# belongs to its snapshot, not the write's completion. Reads perform no I/O.
	if is_instance_valid(level.world_save):
		row.save_count = int(level.world_save.save_count)
		row.last_saved_snapshot_unix = float(level.world_save.last_saved_unix)
	if slow_frames.size() >= MAX_SLOW_FRAMES:
		slow_frames.pop_back()
	slow_frames.append(row)
	slow_frames.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.frame_ms) > float(b.frame_ms))

func _physics_process(_delta: float) -> void:
	if not collecting or steady_mode != "walk" or route.size() < 2:
		return
	if flat_distance(player.global_position, route[waypoint]) < .4:
		if waypoint == route.size() - 1:
			loop_direction = -1
		elif waypoint == 0:
			loop_direction = 1
			loops_completed += 1
		waypoint += loop_direction
	var toward := route[waypoint] - player.global_position
	player.look(Vector2(-angle_difference(player.camera_yaw, atan2(toward.x, toward.z)) / player.mouse_sensitivity, 0.0))

func _run() -> void:
	duration = clampf(float(option("--sustained-seconds", "600")), 60.0, 900.0)
	steady_mode = option("--steady-mode", "stationary")
	if DisplayServer.get_name() == "headless" or not steady_mode in ["stationary", "walk"]:
		check(false, "steady endurance requires renderer and stationary/walk mode")
		_finish()
		return
	if not await boot_world():
		_finish()
		return
	for index in range(20, 29):
		route.append(level.vector(level.level_data.route.points[index]))
	_set_scenario_position(route[0])
	steady_origin = player.global_position
	player.look(Vector2(-angle_difference(player.camera_yaw, 0.0) / player.mouse_sensitivity, 0.0))
	level.world_time.set_time(540.0)
	var resolution := Vector2i(int(option("--render-width", "1280")), int(option("--render-height", "720")))
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = resolution
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.size = resolution
	window.scaling_3d_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	player.camera.fov = 68.0
	level.render_optimizer.set_quality("balanced")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# Warm the exact same scene before measuring memory. Do not teleport again.
	await get_tree().create_timer(30.0, true, false, true).timeout
	level.profile_physics = false
	for values in level.physics_samples.values():
		values.clear()
	level.process_samples.clear()
	for column in ["frame_ms", "gpu_ms", "render_cpu_ms", "draw_calls"]:
		histograms[column] = Histogram.new(1.0 if column == "draw_calls" else .1)
	begin_phase("steady_" + steady_mode)
	_sample("baseline", true)
	walked_before = player.distance_walked
	sample_started = Time.get_ticks_usec()
	previous_frame = sample_started
	collecting = true
	sampling = true
	_sample_loop()
	var unix_start := Time.get_unix_time_from_system()
	print("[sustained_performance] SAMPLE_BEGIN unix=%.3f" % unix_start)
	if steady_mode == "walk":
		Input.action_press("move_forward")
	while Time.get_ticks_usec() - sample_started < int(duration * 1000000.0) and not finished:
		await get_tree().process_frame
	collecting = false
	sampling = false
	Input.action_release("move_forward")
	_sample("end", true)
	var seconds := float(Time.get_ticks_usec() - sample_started) / 1000000.0
	print("[sustained_performance] SAMPLE_END unix=%.3f" % Time.get_unix_time_from_system())
	check(seconds >= duration and seconds < duration + 10.0, "requested steady duration completed")
	check(not any_paused and not level.world_time.frozen, "steady world clock and simulation remained live")
	check(float(samples.back().clock_seconds) - float(samples.front().clock_seconds) > duration * .4, "normal world clock advanced throughout endurance")
	check(float(samples.back().traffic_distance) - float(samples.front().traffic_distance) > 50.0, "traffic moved during endurance")
	check(maximum_displacement < 25.0, "player remained in the same small neighborhood")
	check(steady_mode != "walk" or loops_completed >= 2, "walk mode completed repeated collision-aware sidewalk loops")
	var populations_ok := true
	var orphans_clear := true
	for sample in samples:
		populations_ok = populations_ok and int(sample.ambient) == 1200 and int(sample.daily) == 40 and int(sample.traffic) == 90
		orphans_clear = orphans_clear and int(sample.orphans) == 0
	check(populations_ok, "1200/40/90 population remained constant")
	check(orphans_clear, "no orphan nodes in endurance samples")
	var retained_physics_samples: int = level.process_samples.size()
	for values in level.physics_samples.values():
		retained_physics_samples += values.size()
	check(retained_physics_samples == 0 and frame_rows.is_empty(), "per-frame and per-physics timing arrays stayed empty")
	var distributions := {}
	for column in histograms:
		distributions[column] = histograms[column].distribution()
	check(float(distributions.draw_calls.min) > 0, "renderer submitted draws throughout endurance")
	var stream: Dictionary = level.streaming.get_status()
	check(int(stream.get("failures", 0)) == 0, "no streaming failures")
	result_details["sustained"] = {"schema": 4, "workload": "same_neighborhood_endurance",
		"requested_seconds": duration, "measured_seconds": seconds, "unix_start": unix_start,
		"unix_end": Time.get_unix_time_from_system(), "steady_mode": steady_mode,
		"render_resolution": [resolution.x, resolution.y], "warmup_seconds": 30,
		"frame_metrics": distributions, "loops_completed": loops_completed,
		"walked_m": player.distance_walked - walked_before, "max_displacement_m": maximum_displacement,
		"streaming": stream, "retained_frame_rows": frame_rows.size(),
		"retained_histogram_bytes": 4 * Histogram.BIN_COUNT * 8, "retained_metric_samples": samples.size(),
		"slow_frame_threshold_ms": SLOW_FRAME_THRESHOLD_MS, "slow_frame_count": slow_frame_count,
		"retained_slow_frame_limit": MAX_SLOW_FRAMES, "slow_frames": slow_frames,
		"slow_frame_notes": "Worst32 frames over50ms only, descending wall time. Unix marks observation end; interval start is derived. Process/physics/render counters are the latest available monitor samples, not a stack trace. Save fields are cheap public scalars; last_saved_snapshot_unix dates the successful snapshot, not write completion or duration. No per-event world-status scan. Older histogram-only runs (including the988.315ms spike) cannot be retrospectively attributed from this diagnostic.",
		"notes": "Fixed histograms (~640KB), at most182 five-second samples and worst32 slow-frame records; no full per-frame trace or per-physics arrays. Percentiles are 0.1ms upper-bin bounds (draw counts1); min/max/mean exact. Same initial scene and normal clock, no repeat relocations, balanced scale1 uncapped real renderer. User/background processes remain a contention variable."}
	_finish()
