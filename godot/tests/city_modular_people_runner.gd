extends Node
const People := preload("res://scripts/city/city_modular_people.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const Crowd := preload("res://scripts/city/city_crowd.gd")
const DailyActor := preload("res://scripts/city/city_resident_actor.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
var failures := 0
var report: Dictionary = {}
var hardware_readback := false

class Routes extends Node3D:
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

class Neighborhood extends Node3D:
	var npcs: Node3D

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("[modular_people] %s %s" % ["PASS" if ok else "FAIL", message])
	failures += int(not ok)

func _run() -> void:
	hardware_readback = DisplayServer.get_name() != "headless"
	var groups := {"Black": 0, "Hispanic": 0, "White": 0}
	var unique: Dictionary = {}
	for look in People.roster():
		groups[look.identity_group] += 1
		unique[JSON.stringify(look)] = true
	check(groups == {"Black": 32, "Hispanic": 4, "White": 4} and unique.size() == 40, "forty distinct authored appearances:32Black,4Hispanic,4White")
	var original_ids := ["b01","b02","b03","b04","b05","b06","b07","b08","b09","b10","b11","b12","b13","b14","b15","b16","h01","h02","w01","w02"]
	var migration_ok := true
	for index in original_ids.size():
		migration_ok = migration_ok and People.roster()[index].id == original_ids[index]
		migration_ok = migration_ok and Appearance.modular_index("legacy_fixture", {"roster_index": index}) == index
		migration_ok = migration_ok and Appearance.modular_index("legacy_fixture", {"roster_id": original_ids[index], "roster_index": 39}) == index
	check(migration_ok, "original twenty stable style IDs/order and legacy index-only appearances remain compatible")
	var numeric_palette: Variant = People.material().get_shader_parameter("skin_palette")
	var palette_ok: bool = numeric_palette is PackedVector4Array and numeric_palette.size() == 40
	if palette_ok:
		for index in People.roster().size():
			var expected := Color(str(People.roster()[index].skin))
			if RenderingServer.get_current_rendering_method() != "gl_compatibility":
				expected = expected.srgb_to_linear()
			var actual: Vector4 = numeric_palette[index]
			palette_ok = palette_ok and Vector3(actual.x,actual.y,actual.z).distance_to(Vector3(expected.r,expected.g,expected.b)) < .000001
	check(palette_ok, "all40 skin palettes use numeric vectors with exactly one renderer-appropriate gamma conversion")
	var profiles: Dictionary = {}
	var black := 0
	var used: Dictionary = {}
	for i in 1200:
		var id := "crowd_%d" % i
		var profile := Appearance.profile(id)
		profiles[id] = profile
		black += int(profile.identity_group == "Black")
		used[profile.roster_index] = true
	check(black == 964 and used.size() == 40, "all1200 ambient IDs map deterministically across all40looks;964Black identities preserved")
	var stable := true
	for i in range(1199, -1, -1):
		var id := "crowd_%d" % i
		var simulated_save := {"id": id, "dead": i % 3 == 0, "position": [i, 99, -i], "activity": "park"}
		stable = stable and Appearance.profile(simulated_save.id) == profiles[id]
	check(stable, "birth identity and appearance survive reversed ordering, saved deaths and relocation")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Appearance.DATA_PATH))
	var daily_groups := {"Black": 0, "Hispanic": 0, "White": 0}
	var named_preserved := true
	for profile in data.identities:
		black += int(profile.identity_group == "Black")
		if str(profile.id).begins_with("daily_"):
			daily_groups[profile.identity_group] += 1
		elif profile.source == "authored_cast_appearance_preserved":
			named_preserved = named_preserved and profile.skin == Cast.LOOKS[profile.cast].skin and not profile.apply_skin
	check(daily_groups == groups and black == 1004 and named_preserved, "daily roster32/4/4, original named heroes unchanged;1004of1255Black neighborhood identities")
	var budget := People.budget()
	var geometry_ok := true
	for pose in 3:
		var info: Dictionary = budget.poses[str(pose)]
		geometry_ok = geometry_ok and info.surfaces == 1 and info.triangles < 4500 and info.lod_triangles[1] < 900 and info.lod_triangles[1] < info.triangles / 3.0
		var mesh := People.crowd_mesh(pose != 0, pose != 2)
		var arrays: Array = mesh.surface_get_arrays(0)
		geometry_ok = geometry_ok and arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_NORMAL].size()
		for index in arrays[Mesh.ARRAY_INDEX]:
			geometry_ok = geometry_ok and index >= 0 and index < arrays[Mesh.ARRAY_VERTEX].size()
	check(geometry_ok, "allthree shared poses:one surface,under4500high/900far triangles, valid geometry and explicit LODs")
	var seated_volume := true
	for include_chair in [true,false]:
		var arrays: Array = People.crowd_mesh(true,include_chair).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var lows := {25: INF,28: INF}
		var highs := {25: -INF,28: -INF}
		var shirt_bottom := INF
		for index in vertices.size():
			var component := roundi(uv2[index].x)
			if component in [25,28]:
				lows[component] = minf(float(lows[component]),vertices[index].y)
				highs[component] = maxf(float(highs[component]),vertices[index].y)
			if component == 0 and roundi(uv[index].x) == 1 and uv2[index].y < -.5 and uv2[index].y > -1.5:
				shirt_bottom = minf(shirt_bottom,vertices[index].y)
		seated_volume = seated_volume and float(highs[25])-float(lows[25]) > .20 and float(highs[28])-float(lows[28]) > .18 and shirt_bottom >= .61
	check(seated_volume, "production chair/bench clothing keeps vertical knee/side drape and seated shirt hems above thighs")

	var crowd := Crowd.new()
	add_child(crowd)
	var routes := Routes.new()
	add_child(routes)
	crowd.npcs = routes
	crowd._meshes = [crowd._person_mesh(false), crowd._person_mesh(true), crowd._person_mesh(true, false)]
	var expected_batches: Dictionary = {}
	for i in range(1199, -1, -1):
		var at := Vector3((i % 40) * 3.0, 0, floori(i / 40.0) * 3.0)
		var cell := Vector2i(floori(at.x / crowd.CELL), floori(at.z / crowd.CELL))
		if not crowd._cells.has(cell):
			crowd._cells[cell] = {"nodes": []}
		expected_batches["%d_%d_%d" % [cell.x, cell.y, i % 3]] = true
		crowd.residents.append({"stable_id": "crowd_%d" % i, "position": at, "birth_position": at, "birth_activity": "park", "activity": "park", "birth_pose": i % 3, "dead": i % 7 == 0, "yaw": 0.0, "pose": i % 3, "cell": cell})
	crowd._build_batches()
	var uploads_ok := true
	var gpu_uploads_ok := true
	var upload_mismatches: Array = []
	for resident in crowd.residents:
		var multi: MultiMesh = crowd._batches[resident.batch].multimesh
		var profile: Dictionary = profiles[resident.stable_id]
		uploads_ok = uploads_ok and resident.appearance == profile and resident.birth_position == resident.position and resident.birth_activity == "park"
		if hardware_readback:
			var actual := multi.get_instance_custom_data(resident.slot)
			if roundi(actual.r) != int(profile.roster_index) and upload_mismatches.size() < 8:
				upload_mismatches.append({"id": resident.stable_id, "expected": profile.roster_index, "actual": [actual.r, actual.g, actual.b, actual.a], "slot": resident.slot})
			gpu_uploads_ok = gpu_uploads_ok and roundi(actual.r) == int(profile.roster_index)
	print("[modular_people] upload evidence: ", JSON.stringify({"mismatches": upload_mismatches, "actual_batches": crowd._batches.size(), "expected_batches": expected_batches.size(), "mesh_count": crowd._meshes.size()}))
	check(uploads_ok and crowd._batches.size() == expected_batches.size() and crowd._meshes.size() == 3, "1200 canonical CPU appearance records preserve birth records and original cell/pose draw budget")
	if hardware_readback:
		check(gpu_uploads_ok, "all1200 GPU custom-data slots match canonical roster indices")
	else:
		print("[modular_people] SKIP GPU custom-data readback: requires real renderer; headless dummy returns identity colors")
	_combat_appearance(crowd, routes)
	var rigs_ok := true
	var daily: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	var source_daily_surfaces := 0
	for definition in daily.residents:
		var profile := Appearance.profile(str(definition.id))
		var rig := People.rig(str(definition.id), int(profile.roster_index), float(definition.appearance.h))
		var puppet := Puppet.new()
		puppet.id = str(definition.id)
		puppet.H = float(definition.appearance.h)
		puppet.g = rig
		add_child(rig)
		puppet.bind()
		puppet.phase = .5
		puppet.pose({"walk": .4, "look": .2, "mouth": .3})
		rigs_ok = rigs_ok and puppet.legs.size() == 2 and puppet.arms.size() == 2 and puppet.hands.size() == 2 and _mesh_count(rig) == 9
		rigs_ok = rigs_ok and is_equal_approx(rig.scale.y * 1.7, float(definition.appearance.h))
		rig.free()
		var old := Cast._build(str(definition.id), definition.appearance)
		source_daily_surfaces += _mesh_count(old)
		old.free()
	check(rigs_ok, "all40daily puppets bind and animate existing rig contract; authored heights preserved,nine shared-mesh surfaces each")
	report = {"gpu_readback": "verified" if hardware_readback and gpu_uploads_ok else ("failed" if hardware_readback else "not_run_requires_real_renderer"), "budget": budget, "baseline_crowd_triangles": {"standing": 108, "chair_seated": 204, "bench_seated": 132}, "baseline_daily_surfaces": source_daily_surfaces, "new_daily_surfaces": 360, "old_fixture_batches": expected_batches.size(), "new_fixture_batches": crowd._batches.size(), "black": black, "population": 1255}
	crowd.free()
	routes.free()
	if "--roster-visual" in OS.get_cmdline_user_args() or "--appearance-visual" in OS.get_cmdline_user_args():
		await _visual()
	report.failures = failures
	var folder := ProjectSettings.globalize_path("res://../.work/alive-next")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("npc-modular-test.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if failures == 0 else 1)

func _combat_appearance(crowd: Node3D, routes: Node3D) -> void:
	# Restore canonical array order after the upload-order test. Exercise the real
	# crowd/combat transition methods; only the outer neighborhood host is minimal.
	crowd.residents.reverse()
	var host := Neighborhood.new()
	add_child(host)
	host.npcs = routes
	routes.crowd = crowd
	var combat := Combat.new()
	add_child(combat)
	combat.level = host
	var checked: Dictionary = {}
	var transitions_ok := true
	var gpu_transitions_ok := true
	var transition_mismatches: Array = []
	var last_index := -1
	for index in crowd.residents.size():
		var resident: Dictionary = crowd.residents[index]
		var look: int = resident.appearance.roster_index
		if resident.dead or checked.has(look):
			continue
		var body := StaticBody3D.new()
		crowd.add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		body.add_child(shape)
		body.global_position = resident.position
		resident.body = body
		var profile: Dictionary = resident.appearance.duplicate()
		var actor = combat._promote_crowd(index)
		if actor == null:
			transitions_ok = false
			continue
		var visible_indices: Array[int] = []
		_roster_indices(actor.puppet.g, visible_indices)
		transitions_ok = transitions_ok and actor.actor_id == resident.stable_id and actor.get_meta("population_appearance") == profile
		transitions_ok = transitions_ok and visible_indices.size() == 9 and visible_indices.all(func(value): return value == look)
		var expected_height := maxf(.8,float(People.roster()[look].height)-.10)
		transitions_ok = transitions_ok and is_equal_approx(actor.capsule.shape.height,expected_height)
		transitions_ok = transitions_ok and is_equal_approx(actor.capsule.position.y,expected_height*.5+.08)
		var state: Dictionary = combat._new_state(actor, index)
		combat._active[actor.get_instance_id()] = state
		actor.puppet.pose({"walk": .4, "armR": [-1.1,.1], "lean": -.1})
		combat._release(state)
		transitions_ok = transitions_ok and is_equal_approx(resident.body_shape.height,expected_height)
		transitions_ok = transitions_ok and is_equal_approx(resident.body_shape_offset.y,expected_height*.5+.08)
		var multi: MultiMesh = crowd._batches[resident.batch].multimesh
		transitions_ok = transitions_ok and not resident.combat_controlled and not resident.dead and resident.appearance == profile
		if hardware_readback:
			var restored_index := roundi(multi.get_instance_custom_data(resident.slot).r)
			if restored_index != look and transition_mismatches.size() < 8:
				transition_mismatches.append({"id": resident.stable_id, "expected": look, "rig_indices": visible_indices, "demoted_index": restored_index})
			gpu_transitions_ok = gpu_transitions_ok and restored_index == look
		checked[look] = true
		last_index = index
		if checked.size() == 40:
			break
	print("[modular_people] transition evidence: ", JSON.stringify({"styles_checked": checked.size(), "mismatches": transition_mismatches}))
	check(transitions_ok and checked.size() == 40, "all40looks survive real combat promotion/animation/demotion with original IDs, collider dimensions and nine-surface limit")
	if hardware_readback:
		check(gpu_transitions_ok, "all40 demoted GPU slots retain their appearance indices")
	else:
		print("[modular_people] SKIP demoted GPU slot readback: requires real renderer")
	var corpse = combat._promote_crowd(last_index)
	var original_rig: Node3D = corpse.puppet.g
	var death_state: Dictionary = combat._new_state(corpse, last_index)
	combat._active[corpse.get_instance_id()] = death_state
	var id: String = corpse.actor_id
	combat._kill(id, corpse, last_index, death_state, corpse.global_position + Vector3.FORWARD)
	var saved: Dictionary = combat.death_snapshot()
	check(corpse.dead and corpse.puppet.g == original_rig and crowd.is_dead(last_index) and saved.dead == [id] and combat._promote_crowd(last_index) == null, "promoted corpse keeps same appearance; permanent canonical death prevents re-promotion")
	combat.free()
	host.free()

func _roster_indices(node: Node, indices: Array[int]) -> void:
	if node is MeshInstance3D:
		indices.append(int(node.get_instance_shader_parameter("roster_override")))
	for child in node.get_children():
		_roster_indices(child, indices)

func _mesh_count(node: Node) -> int:
	var result := int(node is MeshInstance3D)
	for child in node.get_children():
		result += _mesh_count(child)
	return result

func _visual() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2400, 2200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("26313b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = .7
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-25,0)
	light.light_energy = .8
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.2
	camera.position = Vector3(5.85,-1.5,15)
	viewport.add_child(camera)
	camera.look_at(Vector3(5.85,-1.5,0))
	# Actual crowd MultiMesh shader: four rows of ten, mixed standing/seated below.
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = People.crowd_mesh(false)
	multi.instance_count = 40
	for i in 40:
		var x := float(i % 10) * 1.30
		var y := 1.4 - floorf(float(i) / 10.0) * 2.55
		multi.set_instance_custom_data(i, Color(float(i),0,0,0))
		multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP,.10),Vector3(x,y,0)))
		var label := Label3D.new()
		label.text = "%02d %s" % [i + 1, str(People.roster()[i].id)]
		label.font_size = 28
		label.pixel_size = .0025
		label.position = Vector3(x,y-.16,.2)
		label.no_depth_test = true
		viewport.add_child(label)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.lod_bias = 1000.0
	viewport.add_child(instance)
	for _frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and not image.is_empty(), "private viewport rendered all40actual crowd appearances")
	if image != null and not image.is_empty():
		var folder := ProjectSettings.globalize_path("res://../.work/alive-next")
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png(folder.path_join("npc-roster.png"))
		report.visual = folder.path_join("npc-roster.png")
		instance.hide()
		for child in viewport.get_children():
			if child is Label3D:
				child.hide()
		var daily: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
		var actors: Array[Node3D] = []
		for i in daily.residents.size():
			var actor := DailyActor.new()
			viewport.add_child(actor)
			actor.build_resident(null, daily.residents[i])
			actor.position = Vector3(float(i % 10) * 1.3, 1.4 - floorf(float(i) / 10.0) * 2.55, 0)
			actor.puppet.phase = float(i) * .8
			actor.puppet.pose({"walk": .35, "look": .15, "mouth": .2})
			actors.append(actor)
		for _frame in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(folder.path_join("npc-daily-roster.png"))
		report.daily_visual = folder.path_join("npc-daily-roster.png")
		for actor in actors:
			actor.free()
		for row in 4:
			var seated := MultiMesh.new()
			seated.transform_format = MultiMesh.TRANSFORM_3D
			seated.use_custom_data = true
			seated.mesh = People.crowd_mesh(true, row % 2 == 0)
			seated.instance_count = 10
			for i in 10:
				seated.set_instance_custom_data(i, Color(float(i + row * 10),0,0,0))
				seated.set_instance_transform(i, Transform3D(Basis(Vector3.UP,.38), Vector3(float(i)*1.3, 1.4 - float(row) * 2.55,0)))
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = seated
			visual.lod_bias = 1000.0
			viewport.add_child(visual)
		for _frame in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(folder.path_join("npc-seated-roster.png"))
		report.seated_visual = folder.path_join("npc-seated-roster.png")
	viewport.queue_free()

