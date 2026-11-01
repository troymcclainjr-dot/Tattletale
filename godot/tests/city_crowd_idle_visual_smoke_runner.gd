extends "res://tests/city_priorities_session_fixture.gd"
## Reuse only window-safety evidence; never boot the inherited full city.
const People := preload("res://scripts/city/city_modular_people.gd")
var views: Array[SubViewport] = []
var batches: Array[MultiMeshInstance3D] = []
var captures: Array[Dictionary] = []

func _ready() -> void:
	_place_window_off_desktop()
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	_run.call_deferred()
	_visual_watchdog()

func _visual_watchdog() -> void:
	await get_tree().create_timer(60.0, true, false, true).timeout
	if not finished:
		check(false, "visual fixture watchdog")
		_finish()

func _run() -> void:
	phase_name = "crowd_idle_visual"
	output_dir = ProjectSettings.globalize_path("res://../.work/bike-city-polish/crowd-idle-visual")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var private_root := ProjectSettings.globalize_path("res://../.work").replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var profile := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	check(profile.begins_with(private_root), "fixture uses an isolated project .work user profile")
	check(DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--offscreen-validation"), "rendered fixture requires explicit offscreen validation")
	if failures:
		_finish()
		return
	result_details.input_backend = await _settle_window_safety()
	check(_window_off_desktop() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "unfocusable off-desktop render surface keeps cursor visible")
	if failures:
		_finish()
		return
	# Synthetic presentation phase drives the production shader. Pacing physics
	# is separately tested by city_crowd_idle_life_smoke, not asserted here.
	var close_view := _make_view(8, Vector2i(1600, 620), 3.0, false)
	var roster_view := _make_view(20, Vector2i(3840, 720), 3.0, true)
	var mesh := People.crowd_mesh(false)
	check(mesh.get_surface_count() == 1 and batches.size() == 2 and batches[0].multimesh.mesh == batches[1].multimesh.mesh,
		"two independent presentation views each use one shared standing MultiMesh surface")
	check(batches[0].multimesh.instance_count == 8 and batches[1].multimesh.instance_count == 20, "closeup modes and all twenty production palettes are represented")
	var images: Array[Image] = []
	for sample in [{"name": "rest", "time": 0.0}, {"name": "lifting", "time": 1.8}, {"name": "gesture", "time": 3.2}, {"name": "lowered", "time": 6.5}]:
		People.material().set_shader_parameter("crowd_clock", float(sample.time))
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := close_view.get_texture().get_image()
		images.append(image)
		_capture(image, "closeup-" + str(sample.name), float(sample.time), close_view)
		if sample.name == "gesture":
			_capture(roster_view.get_texture().get_image(), "all20-gesture", float(sample.time), roster_view)
	var different := false
	if images.size() == 4 and not images[0].is_empty() and not images[2].is_empty():
		different = images[0].get_data() != images[2].get_data()
	check(different, "production vertex animation changes rendered pixels between rest and raised gesture")
	check(_window_off_desktop() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "capture completed without changing desktop pointer ownership")
	result_details.geometry = People.budget()
	result_details.captures = captures
	result_details.phase_control = "Synthetic shared shader clock; custom phase zero. Closeup columns: idle, smoking, bagged bottle, pacing; repeat at quarter turn. All20 lineup repeats these modes."
	_finish()

func _make_view(count: int, size: Vector2i, height: float, roster: bool) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	view.mesh_lod_threshold = 0.0
	get_tree().root.add_child(view)
	views.append(view)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position = Vector3(0, 1.65, 8)
	camera.look_at(Vector3(0, .92, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = height
	camera.current = true
	var sun := DirectionalLight3D.new()
	view.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.15
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("253340")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d6dbe3")
	world.environment.ambient_light_energy = .65
	view.add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 8)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("515d60")
	ground.material_override = ground_material
	ground.position.y = -.015
	view.add_child(ground)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = People.crowd_mesh(false)
	multi.instance_count = count
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multi
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(batch)
	batches.append(batch)
	var spacing := .74 if not roster else .77
	for index in count:
		var yaw := -.6 if not roster and index >= 4 else 0.0
		multi.set_instance_transform(index, Transform3D(Basis(Vector3.UP, yaw), Vector3((float(index) - float(count - 1) * .5) * spacing, 0, 0)))
		multi.set_instance_custom_data(index, Color(float(index if roster else [0,4,16,18,2,8,17,19][index]), float(index % 4 + 1), 0, 0))
	return view

func _capture(image: Image, name: String, time: float, view: SubViewport) -> void:
	check(not image.is_empty() and image.get_width() == view.size.x and image.get_height() == view.size.y, name + " has rendered viewport pixels")
	if image.is_empty():
		return
	var file_name := name + ".png"
	check(image.save_png(output_dir.path_join(file_name)) == OK, name + " viewport PNG saved")
	var draw_calls := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var objects := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
	check(objects == 2 and draw_calls > 0 and draw_calls <= 4, name + " has only ground and one crowd batch (at most depth/color passes)")
	captures.append({"file": file_name, "shader_time": time, "size": [image.get_width(), image.get_height()],
		"draw_calls": draw_calls, "objects": objects})

func _finish() -> void:
	if finished:
		return
	finished = true
	var file := FileAccess.open(output_dir.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passes": passes, "failures": failures, "checks": checks, "details": result_details}, "\t"))
	print("[crowd_idle_visual] passes=", passes, " failures=", failures, " output=", output_dir)
	get_tree().quit(1 if failures else 0)
