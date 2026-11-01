extends SceneTree
## Run with a rendering backend; all captures are from production prop builders.
const OUT := "res://../.work/pacifist-foundation/"
var failures: Array[String] = []
var metrics: Dictionary = {}
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D

class FlatGround extends Node3D:
	func ground_at(point: Vector3) -> Dictionary:
		return {"position": Vector3(point.x, 0, point.z), "normal": Vector3.UP}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _inspect(id: String, mesh: Mesh, expected_triangles: int = -1) -> void:
	_check(mesh != null, id + " mesh missing")
	if mesh == null:
		return
	var triangles := 0
	var invalid := 0
	for index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(index)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		triangles += (indices.size() if not indices.is_empty() else points.size()) / 3
		_check(points.size() == normals.size(), id + " missing normals")
		for p in points:
			if not p.is_finite():
				invalid += 1
		for n in normals:
			if not n.is_finite() or n.length_squared() < 0.8:
				invalid += 1
	_check(invalid == 0, id + " invalid vertices/normals")
	_check(triangles > 0, id + " has no triangles")
	if expected_triangles >= 0:
		_check(triangles == expected_triangles, "%s triangle budget: %d != %d" % [id, triangles, expected_triangles])
	metrics[id] = {"triangles": triangles, "surfaces": mesh.get_surface_count(), "bounds": str(mesh.get_aabb()), "invalid": invalid}

func _show(id: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = id
	instance.mesh = mesh
	instance.position = at
	stage.add_child(instance)
	return instance

func _capture(name: String, position: Vector3, target: Vector3, size: float) -> void:
	camera.position = position
	camera.look_at(target)
	camera.size = size
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), name + " capture empty")
	if image != null:
		_check(image.save_png(ProjectSettings.globalize_path(OUT + name + ".png")) == OK, name + " capture could not save")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Prop showcase requires the isolated offscreen renderer")
		quit(1)
		return
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bacbd4")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e4eaf1")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	stage.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 70)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("777f6b")
	plane.material = ground_material
	_show("StudioGround", plane, Vector3(0, -0.015, 0))

	var yards: Node3D = load("res://scripts/city/city_yard_details.gd").new()
	stage.add_child(yards)
	yards.set("_material", StandardMaterial3D.new())
	var yard_material: StandardMaterial3D = yards.get("_material")
	yard_material.vertex_color_use_as_albedo = true
	yard_material.vertex_color_is_srgb = true
	yard_material.roughness = 0.91
	yards.call("_build_templates")
	var templates: Dictionary = yards.get("_meshes")
	_inspect("dumpster", templates.dumpster, 228)
	_check(templates.dumpster.get_surface_count() == 1, "Dumpster must retain one shared surface")
	_show("Dumpster", templates.dumpster, Vector3(0, 0, 1))
	for kind in ["paper", "wrapper", "cardboard", "loose_can", "cup"]:
		_inspect(kind, templates[kind])
	_check(yards.get_child_count() == 0, "Template build must create no per-prop nodes or colliders")
	var backlots: Script = load("res://scripts/city/city_backlot_details.gd")
	var dumpster_parts: Array = backlots._dumpster_parts()
	_check(dumpster_parts.size() == 8, "Dumpster collision parts changed")
	_check(dumpster_parts[0].shape.size == Vector3(1.8, 1.05, 1.05), "Dumpster body collider changed")

	var neighborhood: Node3D = load("res://scripts/city/city_neighborhood_details.gd").new()
	stage.add_child(neighborhood)
	var mailbox: Mesh = neighborhood.call("_mail_mesh", false)
	_inspect("mailbox", mailbox, 116)
	_check(mailbox.get_surface_count() == 1, "Mailbox must retain one shared surface")
	_check(mailbox.get_aabb().size.y <= 1.28, "Mailbox exceeds existing collider height")
	_show("Mailbox", mailbox, Vector3(-4, 0, 1))
	_inspect("postal_drop_fallback", neighborhood.call("_mail_mesh", true), 72)
	neighborhood.call("_load_utility_meshes")
	var utilities: Dictionary = neighborhood.get("_meshes")
	for spec in [["postal_drop", Vector3(-2.7, 0, 1)], ["hydrant", Vector3(-1.5, 0, 1)]]:
		var utility: Mesh = utilities.get(spec[0])
		_inspect(spec[0], utility)
		if utility != null:
			_show(spec[0], utility, spec[1])

	var parks: Node3D = load("res://scripts/city/city_park_furniture.gd").new()
	stage.add_child(parks)
	var ground := FlatGround.new()
	stage.add_child(ground)
	parks.set("level", ground)
	parks.call("_build_bench", Vector3(3, 0, 1), 0.0, "Studio")
	var bench: Node3D = parks.get_child(0)
	_inspect("park_bench", bench.get_node("BatchedArchitecture").mesh, 204)
	_check(bench.get_node("SolidArchitecture").get_child_count() == 2, "Bench collider count changed")
	_check(parks.get("bench_slots").size() == 2, "Bench seating slots changed")
	parks.call("_build_playground", Vector3(6, 0, -6), "Studio", 1.0, Vector2(9, 8))
	var playground: Node3D = parks.get_child(1)
	_inspect("playground", playground.get_node("BatchedArchitecture").mesh)
	_check(playground.get_node("SolidArchitecture").get_child_count() == 6, "Playground collider count changed")
	_check(parks.get("_visuals").size() == 2, "Park furniture must stay one render mesh per assembly")

	var grid: Node3D = load("res://scripts/city/city_power_grid.gd").new()
	stage.add_child(grid)
	for transformer in [false, true]:
		for terminal in [false, true]:
			var pole: Mesh = grid.call("_make_pole", transformer, terminal)
			_inspect("pole_%s_%s" % [transformer, terminal], pole)
			_check(pole.get_surface_count() == 1, "Pole variants must retain one surface")
			if not terminal:
				_show("Pole", pole, Vector3(0 if transformer else -3, 0, -7))
	_check(grid.get_child_count() == 0, "Pole template build must not add colliders or nodes")
	var dressing: Script = load("res://scripts/city/city_dressing.gd")
	var lamp: Mesh = dressing.source_lamp_mesh()
	_inspect("source_streetlamp", lamp)
	if lamp != null:
		_show("Lamp", lamp, Vector3(-7, 0, -4))
	_inspect("stop_sign", dressing._stop_sign_mesh())
	var stop := Node3D.new()
	stage.add_child(stop)
	stop.position = Vector3(-5.3, 0, -4)
	dressing._stop_sign(stop)

	await _capture("props-close", Vector3(7, 4.5, 12), Vector3(-0.5, 0.8, 1), 10.8)
	await _capture("props-civic", Vector3(17, 13, 23), Vector3(0, 3.0, -3), 24.0)
	await _capture("props-playground", Vector3(13, 8, 6), Vector3(6, 0.8, -6), 12.0)

	var courts: Node3D = load("res://scripts/city/city_park_courts.gd").new()
	stage.add_child(courts)
	var court_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_courts.json"))
	_check(not court_data.courts.is_empty(), "No authored courts")
	if not court_data.courts.is_empty():
		var court_mesh := ArrayMesh.new()
		court_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, courts.call("_arrays", court_data.courts[0].mesh))
		court_mesh.surface_set_material(0, yard_material)
		_inspect("basketball_court", court_mesh)
		var court: MeshInstance3D = _show("Court", court_mesh, Vector3(-22, 0, -16))
		var center: Vector3 = court.position + court_mesh.get_aabb().get_center()
		await _capture("props-court", center + Vector3(23, 27, 23), center, 36.0)

	var report := {"suite": "world_prop_quality", "metrics": metrics, "failures": failures}
	var file := FileAccess.open(OUT + "props-metrics.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
