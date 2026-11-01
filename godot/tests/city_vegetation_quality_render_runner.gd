extends Node
## Production decoder, cell merger, inverse-transpose correction, wind and LODs.
const Vegetation := preload("res://scripts/city/city_vegetation.gd")
const Yards := preload("res://scripts/city/city_yard_details.gd")
const OUTPUT := "res://../.work/pacifist-foundation/vegetation-visual"
var failures := 0
var captures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[vegetation_quality] %s %s" % ["PASS" if ok else "FAIL", label])

func capture(viewport: SubViewport, filename: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(not picture.is_empty(), filename + " has rendered pixels")
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename + ".png"))
	check(picture.save_png(path) == OK, filename + " saved")
	captures.append(path)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires private offscreen renderer")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bccbd0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d4dfdf")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("fff5dd")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(36, .12, 24)
	ground.mesh = slab
	ground.position = Vector3(12.5, -.10, 4)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("a3ad93")
	ground_material.roughness = .92
	ground.material_override = ground_material
	world.add_child(ground)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(17, 15, 31)
	camera.look_at(Vector3(12.5, 2.5, 3.5))
	camera.fov = 62
	camera.current = true
	var original_hash := FileAccess.get_sha256(Vegetation.DATA_PATH)
	var vegetation := Vegetation.new()
	world.add_child(vegetation)
	vegetation.setup(world, world)
	var published: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Vegetation.DATA_PATH))
	var plants: Array[Dictionary] = []
	var kinds: Array = published.templates.keys()
	for i in kinds.size():
		var kind := str(kinds[i])
		var tree := kind.begins_with("tree")
		var column := i if tree else i - 6
		plants.append({"kind": kind, "position": Vector3(float(column) * 5.0 + (0.0 if tree else 3.5), 0, 0 if tree else 8),
			"yaw": .35, "radius": 2.0 if tree else .95, "height": 7.0 if tree else (2.4 if kind == "bush_spire" else 1.6), "trunk_radius": .12 if tree else 0.0})
	vegetation._cells = {Vector2i.ZERO: plants}
	vegetation.set_wind_time(3.0)
	var cell := vegetation._build_cell(Vector2i.ZERO, "near", false, true)
	var near: Dictionary = vegetation._cell_mesh(Vector2i.ZERO, "near", true)
	check(near.mesh.get_surface_count() == 1, "all ten kinds merge to one production material surface")
	check(int(near.vertices) <= 11000, "showcase stays within aggregate near vertex budget")
	var batch := cell.get_child(0) as MeshInstance3D
	check(batch != null and batch.extra_cull_margin >= .1, "wind displacement is covered by the production cull margin")
	# These are decoded production hedge templates, displayed at actual yard scale.
	var yard := Yards.new()
	world.add_child(yard)
	yard._material = StandardMaterial3D.new()
	yard._material.vertex_color_use_as_albedo = true
	yard._material.vertex_color_is_srgb = true
	yard._material.roughness = .91
	yard._material.metallic_specular = .18
	var yard_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Yards.DATA))
	for i in 3:
		var hedge := MeshInstance3D.new()
		hedge.mesh = yard._decode_mesh(yard_data.templates["hedge%d" % i])
		hedge.scale = Vector3(3.5, 1.2, .7)
		hedge.position = Vector3(4 + i * 7, 0, 12)
		world.add_child(hedge)
	await capture(viewport, "near-all-kinds-and-hedges")
	var far: Dictionary = vegetation._cell_mesh(Vector2i.ZERO, "far", true)
	check(int(far.vertices) < int(near.vertices) and int(far.vertices) <= 3000, "far LOD reduces aggregate vertices")
	vegetation._set_cell_geometry(cell, far, "far")
	await capture(viewport, "far-same-camera")
	vegetation._set_cell_geometry(cell, near, "near")
	vegetation.set_wind_time(12.0)
	await capture(viewport, "near-wind-phase-12")
	check(FileAccess.get_sha256(Vegetation.DATA_PATH) == original_hash, "showcase leaves published plant records unchanged")
	var file := FileAccess.open(OUTPUT.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"failures": failures, "captures": captures, "kinds": kinds,
			"near_vertices": near.vertices, "far_vertices": far.vertices, "source_sha256": original_hash}, "\t"))
	else:
		check(false, "report writable")
	get_tree().quit(0 if failures == 0 else 1)
