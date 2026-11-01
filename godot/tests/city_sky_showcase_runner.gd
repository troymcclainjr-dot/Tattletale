extends Node
## Offscreen 1080p A/B sky timing. Use a real rendering backend, not --headless.
const DayNight := preload("res://scripts/city/city_day_night.gd")
const SkyVisual := preload("res://scripts/city/city_sky.gd")
const OUT := "res://../.work/pacifist-foundation/"
const WARMUP := 45
const SAMPLES := 180
var failures: Array[String] = []
var results: Array[Dictionary] = []
var viewport: SubViewport
var camera: Camera3D
var controller: Node
var level: TestLevel

class TestClock extends Node:
	var minute_of_day := 720.0

class TestLevel extends Node3D:
	var world_time: Node
	var dressing_report: Dictionary = {}
	var traffic: Node = null
	var player: Node3D
	var inspector: Node = null

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _stats(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median": values[values.size() / 2], "p95": values[floori(float(values.size() - 1) * 0.95)], "min": values[0], "max": values[-1]}

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), name + " image is empty")
	if image != null:
		_check(image.save_png(ProjectSettings.globalize_path(OUT + name + ".png")) == OK, name + " could not save")

func _variant(quality: int, minute: float) -> void:
	level.world_time.set("minute_of_day", minute)
	if quality == -1:
		var legacy := ProceduralSkyMaterial.new()
		controller.set("atmosphere", legacy)
		controller.set("sky_visual", null)
		controller.sky.sky_material = legacy
	else:
		var material := SkyVisual.create_material(quality)
		controller.set("atmosphere", null)
		controller.set("sky_visual", material)
		controller.set("cloud_quality", quality)
		controller.sky.sky_material = material
	controller.set("_last_sky_minute", -1.0)
	controller.set("_last_sample_minute", -1.0)
	controller.call("_apply_lighting", true)
	var direction: Vector3 = controller.sun.global_basis.z.normalized()
	# Point toward the real sun while keeping low-angle horizon in frame.
	var aim := Vector3(direction.x, maxf(direction.y, 0.12), direction.z).normalized()
	camera.look_at(camera.global_position + aim)
	if quality >= 0:
		var uniform: Vector3 = controller.sky_visual.get_shader_parameter("sun_direction")
		_check(uniform.dot(direction) > 0.99999, "Visible sun is not opposite emitted -Z rays")
		if minute >= 420 and minute <= 1020:
			_check(uniform.y > 0.0, "Daytime sun must be above the horizon")
		var expected: Dictionary = DayNight.sample(minute)
		_check(is_equal_approx(controller.sun.light_energy, float(expected.sun_energy)), "Sky changed physical sun energy")
		_check(is_equal_approx(controller.environment.ambient_light_energy, float(expected.ambient_energy)), "Sky changed ambient preset")
		_check(is_equal_approx(controller.fill.light_energy, float(expected.fill_energy)), "Sky changed fill preset")
		_check(controller._pool.size() == 8, "Sky altered nearby streetlight budget")
	var before: int = controller.get_status().sky_updates
	controller.call("tick", 1.0)
	_check(int(controller.get_status().sky_updates) == before, "Frozen world clock rewrote sky")
	for i in WARMUP:
		await get_tree().process_frame
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var starting_updates: int = controller.get_status().sky_updates
	for i in SAMPLES:
		# Exercise 2Hz uniform/radiance refresh rather than timing a frozen sky.
		level.world_time.set("minute_of_day", minute + float(i) * 0.02)
		controller.call("tick", 1.0 / 60.0)
		await get_tree().process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
	var updates: int = int(controller.get_status().sky_updates) - starting_updates
	_check(updates <= ceili(float(SAMPLES) / 30.0), "Sky update cadence exceeded 2Hz")
	var row := {"quality": quality, "minute": minute, "gpu_ms": _stats(gpu), "render_cpu_ms": _stats(cpu), "sky_updates": updates}
	results.append(row)
	print("[sky_ab] " + JSON.stringify(row))
	await _capture("sky-%04d-q%d" % [int(minute), quality])

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Sky showcase requires the isolated offscreen renderer")
		get_tree().quit(2)
		return
	get_tree().root.unfocusable = true
	get_tree().root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.max_fps = 0
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	level = TestLevel.new()
	viewport.add_child(level)
	level.world_time = TestClock.new()
	level.add_child(level.world_time)
	level.player = Node3D.new()
	level.add_child(level.player)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c8d5dd")
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	level.add_child(world)
	for name in ["LateAfternoonSun", "SkyFill"]:
		var light := DirectionalLight3D.new()
		light.name = name
		level.add_child(light)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.7, 0)
	camera.fov = 75
	level.add_child(camera)
	camera.make_current()
	controller = DayNight.new()
	level.add_child(controller)
	controller.call("setup", level)
	_check(controller.sky.radiance_size == Sky.RADIANCE_SIZE_128, "Radiance budget changed")
	_check(controller.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL, "Sky regeneration is not incremental")
	for minute in [450.0, 720.0, 1100.0, 1380.0]:
		# Bracket volume with cheap/off measurements to expose clock/power drift.
		for quality in [-1, 0, 2, 1, 0]:
			await _variant(quality, minute)
	var max_delta := 0.0
	var max_tail_delta := 0.0
	var valid := true
	for minute in [450.0, 720.0, 1100.0, 1380.0]:
		var off: Array[Dictionary] = []
		var volume: Dictionary = {}
		for row in results:
			if is_equal_approx(float(row.minute), minute):
				if int(row.quality) == 0:
					off.append(row)
				if int(row.quality) == 2:
					volume = row
		for row in off:
			valid = valid and float(row.gpu_ms.median) > 0.0
			max_delta = maxf(max_delta, float(volume.gpu_ms.median) - float(row.gpu_ms.median))
			max_tail_delta = maxf(max_tail_delta, float(volume.gpu_ms.p95) - float(row.gpu_ms.p95))
		valid = valid and not volume.is_empty()
	_check(valid, "GPU timings unavailable; cannot approve volumetric default")
	var report := {"suite": "city_sky_ab", "resolution": [1920, 1080], "adapter": RenderingServer.get_video_adapter_name(),
		"samples_per_variant": SAMPLES, "warmup_frames": WARMUP, "results": results, "gpu_timings_valid": valid,
		"max_volume_delta_ms": max_delta, "max_volume_p95_delta_ms": max_tail_delta,
		"volume_budget_pass": valid and max_delta <= 1.0 and max_tail_delta <= 1.5,
		"recommendation": "Inspect captures and confirm full-city performance before selecting default quality 2.", "failures": failures}
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT + "sky-metrics.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("[sky_ab_result] " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
