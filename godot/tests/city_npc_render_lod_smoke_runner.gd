extends Node
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Resident := preload("res://scripts/city/city_resident_actor.gd")
const Detail := preload("res://scripts/city/city_npc_render_lod.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const People := preload("res://scripts/city/city_modular_people.gd")
class LODWorld extends Node3D:
	var player: Node3D
var failures := 0
var finished := false

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(45.0, true, false, true).timeout
	if not finished:
		check(false, "watchdog")
		_finish()

func check(ok: bool, label: String) -> void:
	print("[npc_render_lod] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	var world := LODWorld.new()
	add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var actors: Array[Node3D] = []
	var cast_names := ["mama", "ricky", "cop_dan", "mailman", "granny", "liner_2", "granny", "liner_2", "mailman"]
	for index in 15:
		var character: String = str(cast_names[index]) if index < 9 else ("cop_dan" if index % 2 else "cop_steve")
		var actor := Actor.new()
		world.add_child(actor)
		actor.build(world, "fixture_contact_%d" % index if index < 9 else "patrol_officer_%d" % (index - 9), character, "Fixture")
		if index >= 9:
			Appearance.apply_patrol_skin(actor.puppet.g, Color(str(Cast.LOOKS[character].skin)), Color("482b20"))
		actors.append(actor)
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	for definition in definitions.residents:
		var actor := Resident.new()
		world.add_child(actor)
		actor.build_resident(world, definition)
		actors.append(actor)
	await get_tree().process_frame
	var before := 0
	var after := 0
	var all_supported := true
	var all_five := true
	var selected_skin := false
	for actor in actors:
		var detail: Node = actor.render_detail
		all_supported = all_supported and detail != null and detail.supported
		if detail == null or not detail.supported:
			print("[npc_render_lod] Unsupported fixture cast: ", actor.cast_id)
			continue
		for source in detail.originals:
			before += source.mesh.get_surface_count()
		for proxy in detail.proxies:
			after += proxy.mesh.get_surface_count()
			if str(actor.actor_id).begins_with("patrol_"):
				var colors: PackedColorArray = proxy.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				for color in colors:
					selected_skin = selected_skin or color.is_equal_approx(Color("482b20"))
		all_five = all_five and detail.proxies.size() == 5
	check(actors.size() == 55 and all_supported, "all15 authored/patrol and40 daily rigs support original-appearance proxies")
	check(all_five and after == 275 and before > after, "five surfaces each reduce distant draw submission: %d -> %d" % [before, after])
	check(selected_skin, "patrol replacement skin survives the baked proxy")
	var actor: Node3D = actors[0]
	var detail: Node = actor.render_detail
	var capsule: RID = actor.capsule.shape.get_rid()
	var identity: String = actor.actor_id
	var layer: int = actor.collision_layer
	var target := Vector3(10, 0, 0)
	actor.set_target(target)
	detail.refresh(Vector3(0, 0, 40))
	check(detail.far and _layers(detail.originals, false) and _layers(detail.proxies, true), "distant original surfaces hidden and five-part proxy enabled")
	check(actor.actor_id == identity and actor.capsule.shape.get_rid() == capsule and actor.collision_layer == layer and actor.target == target and actor.has_target, "LOD preserves identity, collision shape/layer and movement target")
	detail.refresh(Vector3(0, 0, 29))
	check(detail.far, "hysteresis keeps distant representation at 29m")
	detail.refresh(Vector3(0, 0, 20))
	check(not detail.far and _layers(detail.originals, true) and _layers(detail.proxies, false), "camera approach restores complete near rig")
	var shadows_restored := true
	for index in detail.originals.size():
		shadows_restored = shadows_restored and detail.originals[index].cast_shadow == detail.original_shadows[index]
	check(shadows_restored, "original near shadow settings restored")
	detail.refresh(Vector3(0, 0, 40))
	actor.speak("Hello", 1.0)
	check(not detail.far, "conversation restores full rig immediately")
	actor._speech_remaining = 0.0
	detail.refresh(Vector3(0, 0, 40))
	actor.combat_override = true
	check(not detail.far, "combat takeover restores full articulated rig before first combat pose")
	actor.combat_override = false
	detail.refresh(Vector3(0, 0, 40))
	actor.mark_dead()
	check(not detail.far and actor.dead and actor.collision_layer == 0, "death retains full corpse articulation and normal death collision semantics")
	var daily: Node3D = actors[15]
	var daily_detail: Node = daily.render_detail
	daily_detail.refresh(Vector3(0, 0, 80))
	daily.set_distance_fade(80.0)
	var fades_match := true
	for proxy in daily_detail.proxies:
		fades_match = fades_match and is_equal_approx(proxy.transparency, daily._fade)
	check(fades_match and daily_detail.far and _layers(daily_detail.originals, false), "resident fade also affects proxy without restoring original draw calls")
	daily_detail._animation_time = 0.0
	var poses := 0
	for tick in 60:
		if daily_detail.animation_due(1.0 / 60.0):
			poses += 1
	check(poses == 20, "far visual pose cadence is 20Hz at 60Hz physics")
	daily_detail.refresh(Vector3.ZERO)
	var every_frame := true
	for tick in 60:
		every_frame = daily_detail.animation_due(1.0 / 60.0) and every_frame
	check(every_frame, "near visual pose keeps full physics cadence")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	camera.position = Vector3(0, 0, 50)
	daily_detail._timer = 0.0
	daily_detail._process(0.1)
	var far_camera: bool = daily_detail.far
	camera.position = Vector3.ZERO
	daily_detail._process(0.1)
	check(far_camera and not daily_detail.far, "active camera controls detail independently of player position (inspector)")
	Detail.enabled = false
	daily_detail.refresh(Vector3(0, 0, 80))
	check(not daily_detail.far, "counterfactual flag restores original representation")
	Detail.enabled = true
	_check_all_modular_bakes(actors.slice(15))
	# Match CityResidents._create_actor: fade and disable happen synchronously,
	# while the render-detail bake is deferred until after the provider returns.
	var initially_hidden := Resident.new()
	world.add_child(initially_hidden)
	initially_hidden.build_resident(world, definitions.residents[0])
	initially_hidden.set_distance_fade(100.0)
	initially_hidden.set_enabled(false)
	await get_tree().process_frame
	var hidden_detail: Node = initially_hidden.render_detail
	check(hidden_detail != null and hidden_detail.supported and hidden_detail.originals.size() == 9 and hidden_detail.proxies.size() == 5,
		"provider startup fade still bakes all resident body parts")
	initially_hidden.set_enabled(true)
	initially_hidden.set_distance_fade(40.0)
	hidden_detail.refresh(Vector3(0, 0, 40))
	var proxy_visible := true
	for proxy in hidden_detail.proxies:
		proxy_visible = proxy_visible and proxy.is_visible_in_tree() and is_zero_approx(proxy.transparency)
	check(hidden_detail.far and _layers(hidden_detail.originals, false) and _layers(hidden_detail.proxies, true) and proxy_visible,
		"initially hidden resident returns with visible far proxy and hidden originals")
	hidden_detail.refresh(Vector3(0, 0, 20))
	var original_visible := true
	for source in hidden_detail.originals:
		original_visible = original_visible and source.is_visible_in_tree() and is_zero_approx(source.transparency)
	check(not hidden_detail.far and _layers(hidden_detail.originals, true) and _layers(hidden_detail.proxies, false) and original_visible,
		"initially hidden resident restores complete visible near rig")
	world.queue_free()
	_finish()

func _check_all_modular_bakes(daily_actors: Array) -> void:
	var all_components := true
	var all_bounds := true
	var all_colors := true
	var all_budgets := true
	var fitted_changed := 0
	for actor in daily_actors:
		var index := Appearance.modular_index(str(actor.actor_id))
		var look: Dictionary = People.roster()[index]
		var detail: Node = actor.render_detail
		for component in range(1,13):
			all_components = all_components and Detail._component_visible(component, look) == (component == int(look.hair_style) + 1)
		for component in range(20,29):
			all_components = all_components and Detail._component_visible(component, look) == (component == int(look.garment_style) + 20)
		all_components = all_components and Detail._component_visible(29, look) == (int(look.garment_style) in [1,3,4,6])
		if detail == null or not detail.supported or detail.proxies.size() != 5:
			all_budgets = false
			continue
		var actor_triangles := 0
		var actor_changed := false
		for proxy in detail.proxies:
			var expected_triangles := 0
			var expected_bounds := AABB()
			var raw_bounds := AABB()
			var has_bounds := false
			var expected_colors: Array[Color] = []
			var pivot: Node3D = proxy.get_parent()
			for source in detail.originals:
				var group_pivot: Node3D = actor.puppet.body
				for candidate in [actor.puppet.arms[0],actor.puppet.arms[1],actor.puppet.legs[0],actor.puppet.legs[1]]:
					if candidate.is_ancestor_of(source):
						group_pivot = candidate
				if group_pivot != pivot:
					continue
				var relative: Transform3D = pivot.global_transform.affine_inverse() * source.global_transform
				var arrays: Array = source.mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				for triangle in range(0,indices.size(),3):
					var component := roundi(uv2[indices[triangle]].x)
					# Independent authored-slot predicate catches obsolete range masks.
					if component >= 1 and component <= 12 and component != int(look.hair_style) + 1:
						continue
					if component >= 20 and component <= 28 and component != int(look.garment_style) + 20:
						continue
					if component == 29 and int(look.garment_style) not in [1,3,4,6]:
						continue
					if component == 40 and float(look.beard) <= .5:
						continue
					expected_triangles += 1
					for corner in 3:
						var vertex_index: int = indices[triangle + corner]
						var fitted := People.bake_rig_vertex(look, vertices[vertex_index], normals[vertex_index], uv2[vertex_index], str(source.get_parent().name))
						var point: Vector3 = relative * fitted.point
						var raw_point: Vector3 = relative * vertices[vertex_index]
						if not has_bounds:
							expected_bounds = AABB(point,Vector3.ZERO)
							raw_bounds = AABB(raw_point,Vector3.ZERO)
							has_bounds = true
						expected_bounds = expected_bounds.expand(point)
						raw_bounds = raw_bounds.expand(raw_point)
						var slot := roundi(uv[vertex_index].x)
						if slot == 1 and int(look.garment_style) in [6,7] and uv2[vertex_index].y < -2.5:
							slot = 8
						var color := Detail._modular_color(slot,look)
						if not expected_colors.has(color):
							expected_colors.append(color)
			var actual: Array = proxy.mesh.surface_get_arrays(0)
			var actual_indices: PackedInt32Array = actual[Mesh.ARRAY_INDEX]
			var actual_colors: PackedColorArray = actual[Mesh.ARRAY_COLOR]
			var actual_bounds: AABB = proxy.mesh.get_aabb()
			all_budgets = all_budgets and proxy.mesh.get_surface_count() == 1 and actual_indices.size() == expected_triangles * 3
			actor_triangles += actual_indices.size() / 3
			all_bounds = all_bounds and has_bounds and actual_bounds.position.distance_to(expected_bounds.position) < .0001 and actual_bounds.end.distance_to(expected_bounds.end) < .0001
			actor_changed = actor_changed or raw_bounds.position.distance_to(expected_bounds.position) > .0001 or raw_bounds.end.distance_to(expected_bounds.end) > .0001
			for expected in expected_colors:
				var found := false
				for color in actual_colors:
					found = found or (absf(color.r-expected.r) <= 1.0/255.0+.00001 and absf(color.g-expected.g) <= 1.0/255.0+.00001 and absf(color.b-expected.b) <= 1.0/255.0+.00001)
				all_colors = all_colors and found
		all_budgets = all_budgets and actor_triangles < 4500
		fitted_changed += int(actor_changed)
	check(daily_actors.size() == 40 and all_components, "all40 exact hair/garment/long-sleeve masks match authored selections")
	check(all_bounds and fitted_changed == 40, "all40 installed proxy bounds match fitted near-rig vertex contract within0.1mm; none use unfitted topology")
	check(all_colors, "all40 installed proxy palettes include expected skin/clothing/hair/shoes and varsity accents")
	check(all_budgets, "all40 proxies contain exactly selected triangles, at five surfaces each and under4500 triangles")

func _layers(meshes: Array, expected_visible: bool) -> bool:
	for mesh in meshes:
		if (mesh.layers != 0) != expected_visible:
			return false
	return not meshes.is_empty()

func _finish() -> void:
	if finished:
		return
	finished = true
	print("[npc_render_lod] failures=", failures)
	get_tree().quit(1 if failures else 0)
