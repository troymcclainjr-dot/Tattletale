extends "res://tests/city_priorities_session_fixture.gd"
## Frozen full-city render A/B, not a gameplay CPU benchmark. No population cuts.
## The only sampled mutation is production cloud quality: 0 / 1 / 2 / 0.
const WARM_FRAMES := 90
const SAMPLE_FRAMES := 180
const FIXED_MINUTE := 960.0
var viewport: SubViewport
var results: Array[Dictionary] = []
var frozen_modes: Array[Dictionary] = []
var captured_images: Array[String] = []
var window_evidence: Dictionary = {}

func _ready() -> void:
	_place_window_off_desktop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	_run.call_deferred()
	_sky_watchdog()

func _sky_watchdog() -> void:
	await get_tree().create_timer(600.0, true, false, true).timeout
	if not finished:
		check(false, "full-city sky benchmark watchdog expired")
		_finish()

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"count": sorted.size(), "median": sorted[sorted.size() / 2],
		"p95": sorted[floori(float(sorted.size() - 1) * .95)], "mean": total / sorted.size(),
		"min": sorted[0], "max": sorted[-1]}

func _freeze_world() -> void:
	frozen_modes.clear()
	var pending: Array[Node] = [level]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		frozen_modes.append({"node": node, "mode": node.process_mode})
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is RigidBody3D:
			node.freeze = true
		for child in node.get_children():
			pending.append(child)

func _thaw_streaming() -> void:
	# World remains explicitly paused. Restore node processing only so streamed
	# resource requests/providers can settle at the next fixed camera location.
	for entry in frozen_modes:
		if is_instance_valid(entry.node):
			entry.node.process_mode = entry.mode
	frozen_modes.clear()

func _world_signature() -> Dictionary:
	var transforms := PackedStringArray()
	for node in level.find_children("*", "Node3D", true, false):
		transforms.append(str(node.get_path()) + ":" + str(node.transform) + ":" + str(node.visible))
	return {"clock": level.world_time.get_status(), "transforms_sha256": "|".join(transforms).sha256_text(),
		"nodes": transforms.size(), "ambient": int(level.npcs.crowd.get_status().total),
		"daily": int(level.residents.get_status().count), "traffic": level.traffic.vehicles.size(),
		"vegetation": level.vegetation.get_stats(), "streaming": level.streaming.get_status()}

func _prepare_view(view: Dictionary) -> bool:
	_thaw_streaming()
	level.pause_exploring()
	level._ui.hide()
	level._place_player(view.foot, 0.0)
	level.capture_view(view.eye, view.target)
	player.camera.fov = 75.0
	player.camera.reset_physics_interpolation()
	level.world_time.frozen = true
	level.world_time.set_time(FIXED_MINUTE)
	level.day_night.tick(1.0)
	level.streaming.refresh_now()
	_place_window_off_desktop()
	window_evidence = await _settle_window_safety()
	if not _window_off_desktop() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		check(false, "capture warmup window safety: " + JSON.stringify(window_evidence))
		return false
	var stable_frames := 0
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		level.streaming.refresh_now()
		await get_tree().process_frame
		var stream: Dictionary = level.streaming.get_status()
		var plants: Dictionary = level.vegetation.get_stats()
		if int(stream.near_cells_missing) == 0 and not bool(stream.pending) and int(plants.pending_visual_cells) == 0 and int(stream.get("detail_missing", 0)) == 0 and int(stream.get("detail_pending", 0)) == 0:
			stable_frames += 1
		else:
			stable_frames = 0
		if stable_frames >= 90:
			break
	check(stable_frames >= 90, str(view.id) + " residency settles before freezing")
	if stable_frames < 90:
		print("[foundation_sky_residency_failure] " + JSON.stringify({"player": player.global_position, "override": player.camera_override, "streaming": level.streaming.get_status(), "vegetation": level.vegetation.get_stats(), "yards": level.yard_details.get_status()}))
	_freeze_world()
	for i in 12:
		await get_tree().process_frame
	return stable_frames >= 90

func _variant(view: Dictionary, quality: int, bracket: int) -> void:
	begin_phase(str(view.id) + "-q%d-b%d" % [quality, bracket])
	level.day_night.set_cloud_quality(quality)
	var material: ShaderMaterial = level.day_night.sky_visual
	check(material != null and int(material.get_shader_parameter("cloud_quality")) == quality, "production cloud uniform matches requested variant")
	for i in WARM_FRAMES:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var before := _world_signature()
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var wall: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	var objects: Array[float] = []
	var raw: Array[Dictionary] = []
	var invalid := 0
	var last_stamp := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var stamp := Time.get_ticks_usec()
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		var draw_count := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var primitive_count := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		var object_count := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		var wall_ms := float(stamp - last_stamp) / 1000.0
		last_stamp = stamp
		var valid := is_finite(gpu_ms) and gpu_ms > 0.0 and is_finite(cpu_ms) and cpu_ms > 0.0 and draw_count > 0
		invalid += int(not valid)
		gpu.append(gpu_ms)
		cpu.append(cpu_ms)
		wall.append(wall_ms)
		draws.append(float(draw_count))
		primitives.append(float(primitive_count))
		objects.append(float(object_count))
		raw.append({"frame": Engine.get_frames_drawn(), "gpu_ms": gpu_ms, "render_cpu_ms": cpu_ms,
			"wall_frame_ms": wall_ms, "draw_calls": draw_count, "primitives": primitive_count, "objects": object_count, "valid": valid})
	var after := _world_signature()
	check(invalid == 0, "all measured GPU/CPU frames and draw counts are valid")
	check(before == after, "world transforms, clock, populations and streaming remain fixed")
	check(draws.min() == draws.max(), "draw-call workload stays constant within variant")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "no pointer capture or foreground window: " + JSON.stringify(_window_safety_evidence()))
	var image_path := output_dir.path_join(phase_name + ".png")
	var picture := viewport.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1080), "captured framebuffer is actually 1920x1080")
	check(not picture.is_empty() and picture.save_png(image_path) == OK, "1080p variant screenshot saved")
	captured_images.append(image_path)
	var row := {"view": view.id, "quality": quality, "bracket": bracket, "gpu_ms": _stats(gpu),
		"render_cpu_ms": _stats(cpu), "wall_frame_ms": _stats(wall), "draw_calls": _stats(draws),
		"primitives": _stats(primitives), "objects": _stats(objects), "invalid_samples": invalid,
		"world_before": before, "world_after": after, "eye": view.eye, "target": view.target,
		"sky": level.day_night.get_status(), "image": image_path, "samples": raw}
	results.append(row)
	print("[foundation_sky] " + JSON.stringify({"view": view.id, "quality": quality, "gpu_ms": row.gpu_ms, "render_cpu_ms": row.render_cpu_ms, "draw_calls": row.draw_calls}))
	_write_report(false)

func _run() -> void:
	output_dir = ProjectSettings.globalize_path("res://../.work/pacifist-foundation/fullcity-sky")
	DirAccess.make_dir_recursive_absolute(output_dir)
	window_evidence = await _settle_window_safety()
	check(_window_off_desktop() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "private offscreen window safety verified")
	if failures:
		_finish()
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport = SubViewport.new()
	viewport.name = "PrivateFullCitySkyBenchmark"
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.scaling_3d_scale = 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var scene := load("res://scenes/city/pen_lucy.tscn") as PackedScene
	check(scene != null, "production city scene loads dynamically after private-profile guard")
	if scene == null:
		_finish()
		return
	level = scene.instantiate()
	viewport.add_child(level)
	for i in 3600:
		await get_tree().process_frame
		if level.get("level_ready") == true:
			break
	check(level.get("level_ready") == true, "full production city booted")
	if level.get("level_ready") != true:
		_finish()
		return
	player = level.player
	check(not level.world_save.enabled, "validation provider never opens a live checkpoint")
	check(level.npcs.crowd.get_status().total == 1200 and level.residents.get_status().count == 40 and level.traffic.vehicles.size() == 90, "canonical full-city populations retained")
	var views: Array[Dictionary] = [
		{"id": "old-york-wyanoke", "foot": Vector3(-6.7, .3, 10), "eye": Vector3(-6.7, 2.2, 10), "target": Vector3(-7, 8, -85)},
		{"id": "argonne-hospital", "foot": Vector3(423.43, -6.4, -112.21), "eye": Vector3(423.43, -3.8, -112.21), "target": Vector3(459, 5, -158)}]
	for view in views:
		if not await _prepare_view(view):
			continue
		for index in 4:
			await _variant(view, [0, 1, 2, 0][index], index)
	_finish()

func _write_report(complete: bool) -> void:
	var brackets: Array[Dictionary] = []
	for start in range(0, results.size() - 3, 4):
		var a: Dictionary = results[start]
		var cheap: Dictionary = results[start + 1]
		var volume: Dictionary = results[start + 2]
		var b: Dictionary = results[start + 3]
		brackets.append({"view": a.view, "off_gpu_drift_ms": b.gpu_ms.median - a.gpu_ms.median,
			"cheap_vs_off_before_ms": cheap.gpu_ms.median - a.gpu_ms.median, "cheap_vs_off_after_ms": cheap.gpu_ms.median - b.gpu_ms.median,
			"volume_vs_off_before_ms": volume.gpu_ms.median - a.gpu_ms.median, "volume_vs_off_after_ms": volume.gpu_ms.median - b.gpu_ms.median,
			"same_draw_workload": a.draw_calls.median == b.draw_calls.median and a.draw_calls.median == cheap.draw_calls.median and a.draw_calls.median == volume.draw_calls.median})
	var report := {"complete": complete, "passed": complete and failures == 0, "checks": checks,
		"failures": failures, "suite": "fullcity_frozen_sky_ab", "resolution": [viewport.size.x, viewport.size.y] if viewport != null else [],
		"profile": OS.get_user_data_dir(), "window": window_evidence,
		"adapter": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "warmup_frames": WARM_FRAMES, "sample_frames": SAMPLE_FRAMES,
		"clock_minutes": FIXED_MINUTE, "quality_sequence": [0, 1, 2, 0], "results": results, "brackets": brackets,
		"scope": "Frozen production city renderer and sky cost; excludes live gameplay simulation CPU cost.",
		"settings": {"max_fps": Engine.max_fps, "viewport_msaa": viewport.msaa_3d if viewport != null else -1,
			"render_scale": viewport.scaling_3d_scale if viewport != null else 0, "vsync": DisplayServer.window_get_vsync_mode()}}
	var file := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()

func _finish() -> void:
	if finished:
		return
	finished = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_write_report(true)
	print("[foundation_sky] COMPLETE %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
