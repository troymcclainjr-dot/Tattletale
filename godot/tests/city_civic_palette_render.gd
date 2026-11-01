extends SceneTree
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
func _initialize() -> void:
	_run.call_deferred()
func make_view(palette: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(5, 3, 9)
	camera.look_at(Vector3(0, 1.3, 0))
	camera.current = true
	camera.fov = 45
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("243542")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bcc7d0")
	environment.environment.ambient_light_energy = .35
	viewport.add_child(environment)
	var kit := Kit.new("PaletteComparison")
	kit.material("brick_a", Color("ad684b"), 1, .87)
	kit.material("brick_b", Color("68453c"), 1, .93)
	kit.material("white", Color("d2c7a7"), 6, .72)
	kit.material("green", Color("395b49"), 6, .94)
	kit.box(Vector3(-1.3, 1.5, 0), Vector3(2.5, 3, 1), "brick_a")
	kit.box(Vector3(1.3, 1.5, 0), Vector3(2.5, 3, 1), "brick_b")
	kit.box(Vector3(0, 3.05, .1), Vector3(5.4, .22, 1.3), "white")
	for x in [-1.3, 1.3]:
		kit.box(Vector3(x, 1.4, .57), Vector3(1.05, 1.8, .13), "green")
		kit.box(Vector3(x, 2.4, .6), Vector3(1.25, .17, .2), "white")
		kit.box(Vector3(x, .45, .6), Vector3(1.25, .17, .2), "white")
	viewport.add_child(kit.finish(palette))
	return viewport
func _run() -> void:
	var original := make_view(false)
	var merged := make_view(true)
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var a := original.get_texture().get_image()
	var b := merged.get_texture().get_image()
	var output := "res://../artifacts/render-tightening"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	a.save_png(output.path_join("civic-before.png"))
	b.save_png(output.path_join("civic-after.png"))
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var aa := a.get_data()
	var bb := b.get_data()
	var total := 0
	var large := 0
	for index in aa.size():
		var difference := absi(int(aa[index])-int(bb[index]))
		total += difference
		large += int(difference > 3)
	var mean := float(total)/aa.size()
	var ratio := float(large)/aa.size()
	print("[civic_palette_render] mean_byte_difference=%f changed_channel_ratio=%f" % [mean, ratio])
	quit(0 if mean < .1 and ratio < .001 else 1)
