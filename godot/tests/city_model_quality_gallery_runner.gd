extends Node
## Root-owned rendered asset review, fixed scale/light/cameras and private outputs.
const OUT := "res://../.work/model-quality-20261101"
const BASE := OUT + "/baseline/"
var root: Window
var baseline := false
var group := "all"
var revision := "after-r1"
var report: Array[Dictionary] = []
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var finished := false

func _ready() -> void:
	root = get_tree().root
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		if arg.begins_with("--group="): group = arg.trim_prefix("--group=")
		if arg.begins_with("--revision="): revision = arg.trim_prefix("--revision=")
	_run.call_deferred()

func _setup() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root.mode = Window.MODE_WINDOWED
	root.position = Vector2i(-10000, -10000)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("27343c")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d5dde3")
	env.environment.ambient_light_energy = 0.5
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -28, 0)
	light.light_energy = 1.05
	viewport.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 155, 0)
	fill.light_energy = 0.35
	viewport.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("576267")
	mat.roughness = 1.0
	floor_mesh.material_override = mat
	floor_mesh.position.y = -0.015
	viewport.add_child(floor_mesh)

func _glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(error == OK, path)
	var model := document.generate_scene(state) as Node3D
	ClayLib.apply(model)
	return model

func _metrics(model: Node3D) -> Dictionary:
	var meshes := 0
	var surfaces := 0
	var tris := 0
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
			meshes += 1
			var box: AABB = model.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			surfaces += node.mesh.get_surface_count()
			for s in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(s)
				tris += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return {"meshes": meshes, "surfaces": surfaces, "triangles": tris, "mesh_bounds": {"position": [bounds.position.x,bounds.position.y,bounds.position.z], "size": [bounds.size.x,bounds.size.y,bounds.size.z]}}

func _capture(id: String, family: String, model: Node3D, height: float = 1.8) -> void:
	stage.add_child(model)
	var details := _metrics(model)
	var sheet := Image.create(1920, 800, false, Image.FORMAT_RGB8)
	for view in 3:
		if family == "vehicles":
			camera.size = 6.5
			camera.position = [Vector3(7,3.5,8), Vector3(-8,2,0), Vector3(-7,3.5,-8)][view]
			camera.look_at(Vector3(0,0.8,0))
		else:
			camera.size = 2.5 if view < 2 else 0.74
			camera.position = [Vector3(0,1.14,5),Vector3(3,1.6,-5),Vector3(0,height-0.15,3)][view]
			camera.look_at(Vector3(0,1.14,0) if view < 2 else Vector3(0,height-0.15,0))
		for frame in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not root.has_focus(), "No desktop input takeover")
		var img := viewport.get_texture().get_image()
		assert(img != null and not img.is_empty())
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(view*640,0))
	var folder := OUT.path_join(revision).path_join(family)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	assert(sheet.save_png(folder.path_join(id + ".png")) == OK)
	details.merge({"id":id,"family":family,"height_contract":height,"image":ProjectSettings.globalize_path(folder.path_join(id+".png")),"baseline":baseline})
	report.append(details)
	print("[model_quality] captured ", family, "/", id, " ", details.triangles, " triangles")
	model.free()
	await get_tree().process_frame

func _run() -> void:
	assert(OS.get_cmdline_user_args().has("--offscreen-validation"))
	_setup()
	if group in ["all", "cast", "player"]:
		for id in Cast.LOOKS:
			if group == "player" and id != "two_pack": continue
			var model: Node3D
			var h := float(Cast.LOOKS[id].get("h",1.8))
			if baseline:
				model = _glb(BASE+"characters/"+id+".glb")
				var p := Puppet.new()
				p.id=id; p.H=h; p.g=model; p.bind(); Cast._extras(p)
			else:
				var holder := Node3D.new()
				var p := Cast.person(id, holder)
				model=p.g
				holder.remove_child(model)
				holder.free()
			await _capture(id,"cast",model,h)
	if group in ["all", "npcs"]:
		var people: Script = load(BASE+"city_modular_people.gd" if baseline else "res://scripts/city/city_modular_people.gd")
		var roster: Array = people.roster()
		for index in roster.size():
			var look: Dictionary=roster[index]
			await _capture(str(look.id),"npcs",people.rig(str(look.id),index,float(look.height)),float(look.height))
	if group in ["all", "vehicles"]:
		var models: Script=load(BASE+"city_car_models.gd" if baseline else "res://scripts/city/city_car_models.gd")
		for kind in models.ALL_KINDS:
			await _capture(kind,"vehicles",models.make(kind,1))
		# Match the hospital's real transport-van composition without requiring
		# parking-ground physics. The livery helper adds its original lightbar
		# collider to this holder; only meshes enter the gallery metrics.
		var fleet: Script = load(BASE+"city_civic_parking_fleet.gd" if baseline else "res://scripts/city/city_civic_parking_fleet.gd")
		var ambulance := StaticBody3D.new()
		ambulance.name = "AmbulanceGallery"
		ambulance.collision_layer = 0
		ambulance.collision_mask = 0
		var van: Node3D = models.make("minivan", 1)
		fleet._ambulance_livery(van, ambulance)
		ambulance.add_child(van)
		await _capture("ambulance", "vehicles", ambulance)
		for id in ["cop_car","sedan"]:
			var model := _glb(BASE+id+".glb") if baseline else Assets.model(id)
			model.rotation.y=-PI/2.0
			await _capture(id,"vehicles",model)
	var file := FileAccess.open(OUT.path_join(revision).path_join(group+"-metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"baseline":baseline,"models":report,"passed":true},"\t"))
	file.close()
	finished=true
	print("[model_quality] COMPLETE ",report.size()," models; pointer and focus guards passed")
	get_tree().quit(0)
