extends Node
## Identical fixed cameras and uncapped 1280x720 output for honest comparisons.
var output := "res://../.work/city/render_benchmark"
var samples: Array = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.name) == property_name:
			return true
	return false

func _fail(message: String) -> void:
	push_error("[city_benchmark] " + message)
	get_tree().quit(1)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var start := Time.get_ticks_msec()
	var level_script = load("res://scripts/city/pen_lucy_level.gd")
	if not level_script is Script or not level_script.can_instantiate():
		_fail("Pen Lucy level script cannot instantiate; fix parser errors before benchmarking")
		return
	if get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn") != OK:
		_fail("Pen Lucy scene could not load")
		return
	await frames(5)
	var level = get_tree().current_scene
	if not is_instance_valid(level) or not _has_property(level, "level_ready"):
		_fail("Scene has no level_ready property; initialization failed")
		return
	var initialization_frames := 0
	while not level.level_ready:
		initialization_frames += 1
		if initialization_frames > 600:
			_fail("Level did not initialize within 600 rendered frames")
			return
		await frames(1)
	var startup := Time.get_ticks_msec() - start
	level.resume_exploring()
	level.paused = true
	level.player.enabled = false
	level._ui.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.scaling_3d_scale = 1.0
	get_tree().root.size = Vector2i(1280, 720)
	var preset := "balanced"
	var args := OS.get_cmdline_user_args()
	var quality_index := args.find("--render-quality")
	if quality_index >= 0 and quality_index + 1 < args.size():
		preset = args[quality_index + 1]
	if level.render_optimizer:
		level.render_optimizer.set_quality(preset)
	var views := [
		{"name": "old_york", "eye": Vector3(-3, 3.2, 18), "look": Vector3(-3, 3, -60)},
		{"name": "rowhouses", "eye": Vector3(133.82, 0.96, -91.92), "look": Vector3(140.71, 2.62, -80.14)},
		{"name": "overview", "eye": Vector3(270, 340, 300), "look": Vector3(90, -5, -70)}]
	for view in views:
		level.capture_view(view.eye, view.look)
		level.player.update_camera()
		await frames(90)
		var timings: Array[float] = []
		var draw_calls := 0.0
		var primitives := 0.0
		var previous := Time.get_ticks_usec()
		for i in 180:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			timings.append((now - previous) / 1000.0)
			previous = now
			draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var total := 0.0
		for milliseconds in timings:
			total += milliseconds
		timings.sort()
		var record := {"camera": view.name, "fps": 180000.0 / total,
			"median_frame_ms": timings[90], "p95_frame_ms": timings[171],
			"draw_calls": draw_calls / 180.0, "primitives": primitives / 180.0}
		samples.append(record)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(str(view.name) + ".png"))
		print("[city_benchmark] " + JSON.stringify(record))
	var report := {"startup_ms": startup, "quality": preset, "resolution": [1280, 720],
		"optimization_disabled": args.has("--no-city-optimization"), "cameras": samples,
		"optimizer": level.render_optimizer.get_stats() if level.render_optimizer else {},
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"render_video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}
	var file := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit()
