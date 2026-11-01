extends Node
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Resident := preload("res://scripts/city/city_resident_actor.gd")
class FixtureWorld extends Node3D:
	var player: Node3D
var actors: Array[Node3D] = []
var failures := 0
var finished := false
func _ready() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await get_tree().create_timer(75.0, true, false, true).timeout
	if not finished:
		print("[npc_lod_visual] FAIL watchdog")
		get_tree().quit(1)
func check(ok: bool, label: String) -> void:
	print("[npc_lod_visual] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func make_view() -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(1400, 450)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	get_tree().root.add_child(view)
	var world := FixtureWorld.new()
	view.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position = Vector3(0, 2.2, 13)
	camera.look_at(Vector3(0, 1.1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.1
	camera.current = true
	var light := DirectionalLight3D.new()
	view.add_child(light)
	light.rotation_degrees = Vector3(-40, -25, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("243542")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bcc7d0")
	env.environment.ambient_light_energy = 0.5
	view.add_child(env)
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	for i in 8:
		var actor: Node3D
		if i < 4:
			actor = Actor.new()
			world.add_child(actor)
			actor.build(world, "visual_%d" % i, ["mama", "ricky", "cop_dan", "granny"][i], "Fixture")
		else:
			actor = Resident.new()
			world.add_child(actor)
			actor.build_resident(world, definitions.residents[(i - 4) * 5])
		actor.position.x = (i - 3.5) * 1.35
		actors.append(actor)
	return view
func _run() -> void:
	var near_view := make_view()
	var far_view := make_view()
	await get_tree().process_frame
	var okay := true
	for i in actors.size():
		var detail: Node = actors[i].render_detail
		okay = okay and detail != null and detail.supported and detail.proxies.size() == 5
		if detail != null:
			detail.set_process(false)
			detail.refresh(actors[i].global_position + Vector3(0, 0, 40 if i >= 8 else 0))
	for frame in 15:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://../artifacts/render-tightening"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var near_image := near_view.get_texture().get_image()
	var far_image := far_view.get_texture().get_image()
	near_image.save_png(output.path_join("npc-near.png"))
	far_image.save_png(output.path_join("npc-far.png"))
	check(okay, "near/far eight-character captures have complete rigs")
	var measurements: Array[Dictionary] = []
	var camera := near_view.get_camera_3d()
	for index in 8:
		var actor: Node3D = actors[index]
		var center := camera.unproject_position(actor.global_position)
		var left := camera.unproject_position(actor.global_position + Vector3(-0.64, 0, 0))
		var right := camera.unproject_position(actor.global_position + Vector3(0.64, 0, 0))
		var head := camera.unproject_position(actor.global_position + Vector3(0, actor.puppet.H * 1.12, 0))
		var bounds := Rect2i(int(left.x), int(head.y), int(right.x - left.x), int(center.y - head.y) + 4)
		var row_results: Array[Dictionary] = []
		for row in [["head", 0.78, 1.12], ["torso", 0.40, 0.78], ["legs", 0.0, 0.40]]:
			var top := camera.unproject_position(actor.global_position + Vector3(0, actor.puppet.H * float(row[2]), 0))
			var bottom := camera.unproject_position(actor.global_position + Vector3(0, actor.puppet.H * float(row[1]), 0))
			var area := Rect2i(bounds.position.x, int(top.y), bounds.size.x, maxi(1, int(bottom.y - top.y)))
			var result := measure(near_image, far_image, area)
			result["row"] = str(row[0])
			row_results.append(result)
			check(int(result.pixels) >= 100 and float(result.mean_abs_byte_difference) < 5.0 and float(result.max_mean_channel_delta) < 5.0,
				"%s %s foreground palette parity %s" % [actor.actor_id, row[0], JSON.stringify(result)])
		var whole := measure(near_image, far_image, bounds)
		whole["id"] = str(actor.actor_id)
		whole["kind"] = "authored" if index < 4 else "modular_daily"
		whole["rows"] = row_results
		measurements.append(whole)
	var file := FileAccess.open(output.path_join("npc-palette-parity.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "failures": failures, "actors": measurements}, "\t"))
	file.close()
	finished = true
	get_tree().quit(0 if failures == 0 else 1)

func measure(near_image: Image, far_image: Image, area: Rect2i) -> Dictionary:
	# Exclude the background and one-pixel silhouette edges in BOTH images.
	# Large empty image margins cannot conceal a systematic skin/shirt shift.
	var near_background := near_image.get_pixel(0, 0)
	var far_background := far_image.get_pixel(0, 0)
	var near_sum := Vector3.ZERO
	var far_sum := Vector3.ZERO
	var absolute_sum := 0.0
	var count := 0
	area = area.intersection(Rect2i(1, 1, near_image.get_width() - 2, near_image.get_height() - 2))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var foreground := true
			for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if color_distance(near_image.get_pixel(x + offset.x, y + offset.y), near_background) < 0.04 or color_distance(far_image.get_pixel(x + offset.x, y + offset.y), far_background) < 0.04:
					foreground = false
					break
			if not foreground:
				continue
			var a := near_image.get_pixel(x, y)
			var b := far_image.get_pixel(x, y)
			near_sum += Vector3(a.r, a.g, a.b)
			far_sum += Vector3(b.r, b.g, b.b)
			absolute_sum += color_distance(a, b)
			count += 1
	var divisor := float(maxi(1, count))
	var near_mean := near_sum * (255.0 / divisor)
	var far_mean := far_sum * (255.0 / divisor)
	var delta := (near_mean - far_mean).abs()
	return {"pixels": count, "mean_abs_byte_difference": absolute_sum * 255.0 / (divisor * 3.0),
		"max_mean_channel_delta": maxf(delta.x, maxf(delta.y, delta.z)),
		"near_mean_rgb": [near_mean.x, near_mean.y, near_mean.z], "far_mean_rgb": [far_mean.x, far_mean.y, far_mean.z]}

func color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
