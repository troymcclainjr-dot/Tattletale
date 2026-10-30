extends Node3D
## Neutral, UI-free three-quarter previews of the actual shared game meshes.

var output := "res://../artifacts/pen-lucy-world/cars"
var camera: Camera3D
var failures := 0

func _ready() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	G.built = false
	Hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _save(label: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	if error != OK:
		failures += 1
	print("[car_style] " + label + ": " + error_string(error))

func _run() -> void:
	var models = load("res://scripts/city/city_car_models.gd")
	if models == null or not models.can_instantiate():
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("b6c0c2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c5d0d3")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -35, 0)
	key.light_color = Color("fff0d6")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 25
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_color = Color("d0ddeb")
	fill.light_energy = 0.40
	add_child(fill)
	var plane := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(200, 200)
	plane.mesh = ground
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("888b85")
	ground_material.roughness = 0.95
	plane.material_override = ground_material
	add_child(plane)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 39
	camera.near = 0.05
	add_child(camera)
	var names := ["01-box-sedan-spinners", "02-compact-sedan", "03-neighborhood-minivan"]
	for i in models.KINDS.size():
		var kind: String = models.KINDS[i]
		var car: Node3D = models.make(kind, [1, 0, 3][i])
		add_child(car)
		camera.position = Vector3(5.0, 2.7, 6.0)
		camera.look_at(Vector3(0, 0.73, 0))
		await _save(names[i])
		var prototype: Dictionary = models.prototype(kind)
		print("[car_style] prototype ", kind, " triangles=", prototype.triangles, " dimensions=", prototype.dimensions, " reference=", prototype.reference)
		if kind == "box_sedan":
			camera.fov = 34
			camera.position = Vector3(2.10, 0.66, 2.05)
			camera.look_at(Vector3(1.02, 0.36, 1.40))
			models.animate_spinners(car, 0.12)
			await _save("04-spinner-detail")
			models.animate_spinners(car, 0.67)
			await _save("05-spinner-independent-rotation")
			camera.fov = 39
		car.queue_free()
		await frames(2)
	# A real rendered comparison frame, with identical lighting/materials and no
	# compositing: all three factory prototypes stand together on the same ground.
	for i in models.KINDS.size():
		var car: Node3D = models.make(str(models.KINDS[i]), [1, 0, 3][i])
		car.position.x = float(i - 1) * 5.0
		add_child(car)
	camera.fov = 47
	camera.position = Vector3(8, 5.3, 12)
	camera.look_at(Vector3(0, 0.8, 0))
	await _save("00-three-car-style-lineup")
	get_tree().quit(0 if failures == 0 else 1)
