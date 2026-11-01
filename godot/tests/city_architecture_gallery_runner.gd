extends Node
## Six isolated source-geometry views using the real shared city finishes.
const MaterialLib := preload("res://scripts/core/clay_lib.gd")
const Weathering := preload("res://scripts/city/city_weathering.gd")
const SOURCE := "res://../.work/pacifist-foundation/architecture-gallery.json"
const OUTPUT := "res://../artifacts/pacifist-foundation/architecture"
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var models: Array[MeshInstance3D] = []
var captures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await get_tree().physics_frame


func _point(values: Array, index: int) -> Vector3:
	# Blender east/north/up -> Godot east/up/south, preserving orientation.
	return Vector3(float(values[index * 3]), float(values[index * 3 + 2]), -float(values[index * 3 + 1]))


func _mesh(record: Dictionary, palette: Dictionary) -> ArrayMesh:
	var source: Array = record.verts
	var faces: Array = record.faces
	var face_materials: Array = record.mats
	var material_names: Array = record.matnames
	var smooth_faces: Array = record.get("smooth_faces", [])
	var positions := PackedVector3Array()
	positions.resize(source.size() / 3)
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	var face_normals := PackedVector3Array()
	face_normals.resize(face_materials.size())
	for i in positions.size():
		positions[i] = _point(source, i)
	for f in face_materials.size():
		var a := int(faces[f * 3])
		var b := int(faces[f * 3 + 1])
		var c := int(faces[f * 3 + 2])
		var normal := (positions[b] - positions[a]).cross(positions[c] - positions[a]).normalized()
		face_normals[f] = normal
		var smooth: bool = bool(smooth_faces[f]) if not smooth_faces.is_empty() else bool(record.get("smooth", false))
		if smooth:
			for vertex in [a, b, c]:
				normals[vertex] += normal
	var mesh := ArrayMesh.new()
	for mat_index in material_names.size():
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		for f in face_materials.size():
			if int(face_materials[f]) != mat_index:
				continue
			var smooth: bool = bool(smooth_faces[f]) if not smooth_faces.is_empty() else bool(record.get("smooth", false))
			# Godot expects clockwise triangles; outward normals stay unchanged.
			for corner in [0, 2, 1]:
				var vertex := int(faces[f * 3 + corner])
				verts.append(positions[vertex])
				norms.append(normals[vertex].normalized() if smooth else face_normals[f])
		if verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var definition: Array = palette[str(material_names[mat_index])]
		var material_name := "%s_%s_r%d" % [str(definition[0]), str(definition[1]).trim_prefix("#"), roundi(float(definition[2]) * 100.0)]
		mesh.surface_set_material(mesh.get_surface_count() - 1, MaterialLib.material(material_name))
	return mesh


func _stage() -> void:
	viewport = SubViewport.new()
	viewport.name = "PrivateArchitectureGallery"
	viewport.size = Vector2i(1280, 960)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#8fb4dc")
	sky_material.sky_horizon_color = Color("#b9d0e4")
	sky_material.ground_horizon_color = Color("#b9d0e4")
	sky_material.ground_bottom_color = Color("#77766e")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ssao_enabled = true
	environment.ssao_radius = .6
	environment.ssao_intensity = 1.2
	var sky_node := WorldEnvironment.new()
	sky_node.environment = environment
	world.add_child(sky_node)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff0df")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.
	sun.light_angular_distance = 1.5
	world.add_child(sun)
	sun.look_at_from_position(Vector3(-20, 30, -20), Vector3.ZERO)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 80)
	ground.mesh = plane
	ground.material_override = MaterialLib.clay("#7d7a70", .95)
	ground.position = Vector3(20, -.01, 0)
	world.add_child(ground)
	camera = Camera3D.new()
	camera.far = 300.
	camera.fov = 52.
	world.add_child(camera)
	camera.current = true


func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Architecture gallery requires private offscreen rendering, not dummy headless rendering")
		get_tree().quit(1)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not parsed is Dictionary or parsed.get("objects", []).size() != 6:
		push_error("Generate architecture-gallery.json before rendering six fixture views")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_stage()
	for record in parsed.objects:
		var model := MeshInstance3D.new()
		model.name = str(record.name)
		model.mesh = _mesh(record, parsed.materials)
		world.add_child(model)
		model.hide()
		models.append(model)
	var finishes := Weathering.apply_materials(world)
	await _frames(12)
	for i in models.size():
		var model := models[i]
		var label: Dictionary = parsed.labels[i]
		var x := float(label.x)
		var garage := str(label.name) == "Garage"
		model.show()
		camera.look_at_from_position(Vector3(x - (6. if garage else 8.), 4.5 if garage else 6.5, -19.), Vector3(x, 1.8 if garage else 4.1, -3.7))
		await _frames(8)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Architecture fixture returned no image: " + str(label.name))
			get_tree().quit(1)
			return
		var path := ProjectSettings.globalize_path(OUTPUT.path_join(str(label.name) + ".png"))
		if image.save_png(path) != OK:
			push_error("Cannot save architecture fixture " + path)
			get_tree().quit(1)
			return
		captures.append(path)
		model.hide()
	var receipt := FileAccess.open(OUTPUT.path_join("gallery-report.json"), FileAccess.WRITE)
	if receipt == null:
		get_tree().quit(1)
		return
	receipt.store_string(JSON.stringify({"captures": captures, "fixtures": parsed.labels, "finishes": finishes,
		"source": SOURCE, "note": "Synthetic silhouette fixtures; real-map import and clearance QA remain separate."}, "\t"))
	print("[architecture_gallery] captured %d isolated source fixtures" % captures.size())
	get_tree().quit(0)
