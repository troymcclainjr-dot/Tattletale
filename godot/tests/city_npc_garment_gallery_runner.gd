extends "res://tests/city_model_quality_gallery_runner.gd"
## Bounded real-renderer garment validation using production rig, LOD and seated builders.
const PEOPLE := preload("res://scripts/city/city_modular_people.gd")
const RESIDENT := preload("res://scripts/city/city_resident_actor.gd")
const APPEARANCE := preload("res://scripts/city/city_population_appearance.gd")
const PICKS := ["b08","b18","b19","b21","b23","b24","b27","b31","b32","h03","w03","w04"]
const POSES := ["standing_near", "walk_left_near", "walk_right_near", "walk_left_far", "chair", "bench"]
var garment_evidence: Array[Dictionary] = []

func _run() -> void:
	assert(OS.get_cmdline_user_args().has("--offscreen-validation"))
	assert(DisplayServer.get_name() != "headless", "Garment images require a real renderer")
	_setup()
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	var folder := OUT.path_join(revision).path_join("garments")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var selected_ids: Array = PICKS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			selected_ids = Array(arg.trim_prefix("--ids=").split(",",false))
			assert(not selected_ids.is_empty(), "--ids must name at least one garment style")
			for selected_id in selected_ids:
				assert(selected_id in PICKS, "Unknown garment fixture style: " + str(selected_id))
	for style_id in selected_ids:
		var selected: Dictionary = {}
		for definition in definitions.residents:
			if str(APPEARANCE.profile(str(definition.id)).get("roster_id", "")) == style_id:
				selected = definition
				break
		assert(not selected.is_empty(), style_id)
		var index := APPEARANCE.modular_index(str(selected.id))
		for pose_name in POSES:
			await _garment_capture(folder, style_id, index, selected, pose_name)
	var file := FileAccess.open(folder.path_join("garment-evidence.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"captures": garment_evidence, "palette": "production numeric uniform palettes",
		"sources": ["People.rig via Resident.build_resident", "Puppet.pose walk=.42", "CityNpcRenderLOD.refresh at actual camera distance", "People.crowd_mesh seated chair/bench"],
		"limits": ["Discrete deterministic poses, no gameplay physics or continuous cloth simulation.", "Bench support is a neutral fixture block; the seated character mesh is the production bench pose.", "Near and far use identical orthographic framing at actual5m and40m camera distances."]}, "\t"))
	file.close()
	print("[npc_garments] COMPLETE ", garment_evidence.size(), " production pose sheets")
	get_tree().quit(0)

func _garment_capture(folder: String, style_id: String, index: int, definition: Dictionary, pose_name: String) -> void:
	var model := Node3D.new()
	stage.add_child(model)
	var actor: Node3D
	var seated := pose_name in ["chair", "bench"]
	var far_pose := pose_name.ends_with("_far")
	if seated:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = PEOPLE.crowd_mesh(true, pose_name == "chair")
		multi.instance_count = 1
		multi.set_instance_custom_data(0, Color(float(index),0,0,0))
		multi.set_instance_transform(0, Transform3D.IDENTITY)
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multi
		visual.lod_bias = 1000.0
		model.add_child(visual)
		if pose_name == "bench":
			var seat := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.1,.08,.50)
			seat.mesh = box
			seat.position = Vector3(0,.38,0)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("737d82")
			seat.material_override = material
			model.add_child(seat)
	else:
		actor = RESIDENT.new()
		model.add_child(actor)
		actor.build_resident(null, definition)
		actor.puppet.phase = 3.0*PI/2.0 if pose_name == "walk_right_near" else PI/2.0
		actor.puppet.pose({"walk": 0.0 if pose_name == "standing_near" else .42})
		await get_tree().process_frame
		assert(actor.render_detail != null and actor.render_detail.supported)
	var sheet := Image.create(1920,800,false,Image.FORMAT_RGB8)
	var distance := 40.0 if far_pose else 5.0
	for view in 3:
		var focus := Vector3(0,.85 if seated else 1.0,0)
		camera.size = 2.25
		var direction: Vector3 = [Vector3(0,.025,1),Vector3(.6,.14,-1),Vector3(1,.08,.1)][view]
		camera.position = focus + direction.normalized()*distance
		camera.look_at(focus)
		if actor != null:
			actor.render_detail.refresh(camera.global_position)
			assert(actor.render_detail.far == far_pose)
		for frame in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not root.has_focus(), "No desktop input takeover")
		var picture := viewport.get_texture().get_image()
		assert(picture != null and not picture.is_empty())
		picture.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(picture,Rect2i(Vector2i.ZERO,picture.get_size()),Vector2i(view*640,0))
	var filename := style_id + "_" + pose_name + ".png"
	assert(sheet.save_png(folder.path_join(filename)) == OK)
	garment_evidence.append({"id": style_id, "resident": definition.id, "roster_index": index,
		"pose": pose_name, "walk_amplitude": 0.0 if seated or pose_name == "standing_near" else .42,
		"lod_far": far_pose, "source_surfaces": 1 if seated else (5 if far_pose else 9),
		"views": ["front", "rear_three_quarter", "side"], "image": ProjectSettings.globalize_path(folder.path_join(filename))})
	print("[npc_garments] captured ", filename)
	model.free()
	await get_tree().process_frame
