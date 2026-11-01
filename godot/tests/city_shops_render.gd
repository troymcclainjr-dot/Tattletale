extends SceneTree
const Building := preload("res://scripts/city/city_shop_building.gd")
var finished := false
func _initialize() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await create_timer(75.0, true, false, true).timeout
	if not finished:
		print("[shops_render] FAIL watchdog")
		quit(1)
func make_view(entry: Dictionary, interior: bool) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(960, 640)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	root.add_child(view)
	var model := Building.build(entry)
	view.add_child(model)
	view.add_child(Building.approach(entry))
	var camera := Camera3D.new()
	view.add_child(camera)
	var front := float(entry.depth) * 0.5
	camera.position = model.to_global(Vector3(0, 1.65, front - 0.75) if interior else Vector3(float(entry.width) * 0.9, 5.0, front + 11))
	camera.look_at(model.to_global(Vector3(0, 1.55, -float(entry.depth) * 0.22) if interior else Vector3(0, 1.5, front)))
	camera.fov = 73.0 if interior else 55.0
	camera.current = true
	var light := DirectionalLight3D.new()
	view.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.shadow_enabled = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("415563")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d7d0be")
	environment.environment.ambient_light_energy = 0.65
	view.add_child(environment)
	return view
func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_shops.json"))
	var output := "res://../artifacts/sandbox-foundations/shops"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var captured := 0
	for entry in data.shops:
		for inside in [false, true]:
			var view := make_view(entry, inside)
			for frame in 16:
				await process_frame
			await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			var path := output.path_join(str(entry.id) + ("-interior.png" if inside else "-exterior.png"))
			if image.save_png(path) == OK:
				captured += 1
			view.queue_free()
			await process_frame
	finished = true
	print("[shops_render] %s %d/10 exterior/interior views" % ["PASS" if captured == 10 else "FAIL", captured])
	quit(0 if captured == 10 else 1)
