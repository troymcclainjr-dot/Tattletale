extends SceneTree
## Graphical private-world parity: identical geometry/camera/light, changing
## only StandardMaterial source_color versus moving MultiMesh instance tint.
const Models := preload("res://scripts/city/city_car_models.gd")
const Renderer := preload("res://scripts/city/city_vehicle_render_lod.gd")
const OUTPUT := "res://../artifacts/render-tightening/vehicle-tint"
var failures := 0
var finished := false
var report: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await create_timer(75.0, true, false, true).timeout
	if not finished:
		print("[vehicle_tint_render] FAIL watchdog")
		quit(1)

func check(ok: bool, label: String) -> void:
	print("[vehicle_tint_render] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func make_view(kind: String, paint: int, mode: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(6, 3.8, 7)
	camera.look_at(Vector3(0, 0.85, 0))
	camera.current = true
	camera.fov = 40
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("243542")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bcc7d0")
	environment.environment.ambient_light_energy = 0.35
	viewport.add_child(environment)
	var mesh: ArrayMesh = Models.prototype(kind).far_parked
	if mode == "full_near":
		viewport.add_child(Models.make(kind, paint))
	elif mode == "material":
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.set_surface_override_material(0, Models._paint(paint))
		viewport.add_child(visual)
	else:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = 1
		multi.set_instance_transform(0, Transform3D.IDENTITY)
		var tint := Models.paint_color(paint)
		if mode == "batch":
			tint = Renderer.paint_tint(tint)
		multi.set_instance_color(0, tint)
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multi
		viewport.add_child(visual)
	return viewport

func compare(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var aa := a.get_data()
	var bb := b.get_data()
	var total := 0
	var large := 0
	var foreground := 0
	for index in aa.size():
		var difference := absi(int(aa[index]) - int(bb[index]))
		total += difference
		large += int(difference > 3)
	for index in range(0, aa.size(), 3):
		if absi(int(aa[index]) - int(aa[0])) + absi(int(aa[index + 1]) - int(aa[1])) + absi(int(aa[index + 2]) - int(aa[2])) > 10:
			foreground += 1
	return {"mean_byte_difference": float(total) / aa.size(), "changed_channel_ratio": float(large) / aa.size(), "foreground_pixels": foreground}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var cases := [["compact", 0], ["long_sedan", 1], ["pickup", 3], ["compact_suv", 2]]
	for entry in cases:
		var kind: String = str(entry[0])
		var paint: int = int(entry[1])
		var material := make_view(kind, paint, "material")
		var batch := make_view(kind, paint, "batch")
		var full := make_view(kind, paint, "full_near")
		var wrong: SubViewport = make_view(kind, paint, "encoded_control") if kind == "compact" else null
		for frame in 16:
			await process_frame
		await RenderingServer.frame_post_draw
		var reference := material.get_texture().get_image()
		var actual := batch.get_texture().get_image()
		var prefix := "%s_paint%d" % [kind, paint]
		reference.save_png(OUTPUT.path_join(prefix + "_same_mesh_material.png"))
		actual.save_png(OUTPUT.path_join(prefix + "_far_batch.png"))
		full.get_texture().get_image().save_png(OUTPUT.path_join(prefix + "_full_near.png"))
		var result := compare(reference, actual)
		result["kind"] = kind
		result["paint"] = paint
		report.append(result)
		check(int(result.foreground_pixels) > 5000, prefix + " actually renders vehicle geometry")
		check(float(result.mean_byte_difference) < 0.1 and float(result.changed_channel_ratio) < 0.001, prefix + " identical-geometry paint parity: " + JSON.stringify(result))
		if kind != "compact":
			var colors: PackedColorArray = Models.prototype(kind).far_parked.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var shades: Dictionary = {}
			for color in colors:
				shades[color.to_html()] = true
			check(shades.size() >= 3, prefix + " covers catalog vertex shade multipliers")
		if wrong != null:
			var negative := compare(reference, wrong.get_texture().get_image())
			if RenderingServer.get_current_rendering_method() != "gl_compatibility":
				check(float(negative.mean_byte_difference) > 0.5, "negative control detects unconverted sRGB instance tint: " + JSON.stringify(negative))
			wrong.queue_free()
		material.queue_free()
		batch.queue_free()
		full.queue_free()
		await process_frame
	var file := FileAccess.open(OUTPUT.path_join("parity.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "failures": failures, "comparisons": report}, "\t"))
	file.close()
	finished = true
	print("[vehicle_tint_render] failures=", failures)
	quit(1 if failures else 0)
