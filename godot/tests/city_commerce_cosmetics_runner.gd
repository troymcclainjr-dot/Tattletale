extends Node3D
const Fixture := preload("res://tests/city_commerce_smoke.gd")
const Progression := preload("res://scripts/city/city_progression.gd")
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const Cosmetics := preload("res://scripts/city/city_player_cosmetics.gd")
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[commerce_cosmetics] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func color_of(material: Material) -> Color:
	if material is StandardMaterial3D:
		return material.albedo_color
	if material is ShaderMaterial and material.get_shader_parameter("albedo") is Color:
		return material.get_shader_parameter("albedo")
	return Color.MAGENTA

func materials_snapshot(model: Node, bandanas_only := false, exclude_bandanas := false) -> Dictionary:
	var result := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var authored := mesh.mesh.surface_get_material(surface)
			# Independent export contract: Head_Mesh owns a single bandana
			# material; fallback gives each accessory its own named mesh.
			var bandana := str(mesh.name).begins_with("Bandana") or (str(mesh.name) == "Head_Mesh" and authored != null and authored.resource_name == "clay_c4162a_r85")
			if (bandanas_only and not bandana) or (exclude_bandanas and bandana):
				continue
			var material := mesh.get_active_material(surface)
			result[str(model.get_path_to(mesh)) + ":%d" % surface] = {"id": material.get_instance_id() if material != null else 0, "color": color_of(material)}
	return result

func bandana_matches(model: Node, color: Color) -> bool:
	var state := materials_snapshot(model, true)
	if state.is_empty():
		return false
	for item in state.values():
		if not Color(item.color).is_equal_approx(color):
			return false
	return true

func apply_selection(p: Node, walking: Node, bike: Node) -> void:
	Cosmetics.bandana(walking, p.equipped_shop_color("bandana_color"))
	bike.apply_shop_cosmetics(p.equipped_shop_color("bike_color"), p.equipped_shop_color("bandana_color"))

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var placeholders_before := Assets.used_placeholder.size()
	var walking := Cast.person("two_pack", self)
	var neighbor := Cast.person("two_pack", self)
	var bike := Bicycle.new()
	add_child(bike)
	bike.set_process(false)
	bike.set_physics_process(false)
	bike._build_model()
	check(Assets.has_glb("characters/two_pack") and Assets.used_placeholder.size() == placeholders_before, "walking, neighbor and bike rider use actual exported Cast model")
	var walking_original := materials_snapshot(walking.g)
	var walking_other := materials_snapshot(walking.g, false, true)
	var rider_original := materials_snapshot(bike._rider.g)
	var rider_other := materials_snapshot(bike._rider.g, false, true)
	var neighbor_original := materials_snapshot(neighbor.g)
	check(materials_snapshot(walking.g, true).size() == 1, "actual export has one isolated bandana surface in Head_Mesh")
	var world := Fixture.CommerceWorld.new()
	add_child(world)
	world.combat = Fixture.CommerceHealth.new()
	world.law = Fixture.CommerceGate.new()
	world.driving = Fixture.CommerceGate.new()
	world.shops = Fixture.CommerceGate.new()
	world.progression = Progression.new()
	for node in [world.combat, world.law, world.driving, world.shops, world.progression]:
		world.add_child(node)
	var p: Node = world.progression
	p.setup(world)
	p.changed.connect(apply_selection.bind(p, walking.g, bike))
	check(p.purchase("bandana_ocean").ok and p.purchase("bike_teal").ok, "paid appearance changes emit real progression change hooks")
	check(bandana_matches(walking.g, Color("467dba")) and bandana_matches(bike._rider.g, Color("467dba")), "walking and mounted-rider active clay materials both show ocean blue")
	check(bike._paint.albedo_color.is_equal_approx(Color("238f91")), "bicycle frame uses purchased teal")
	check(materials_snapshot(walking.g, false, true) == walking_other and materials_snapshot(bike._rider.g, false, true) == rider_other, "all skin, tattoos, sash, jeans and other materials remain unchanged")
	check(materials_snapshot(neighbor.g) == neighbor_original, "another instance sharing imported materials is untouched")
	var saved: Dictionary = p.snapshot_state()
	var bandana_before_repeat := materials_snapshot(walking.g, true)
	apply_selection(p, walking.g, bike)
	check(materials_snapshot(walking.g, true) == bandana_before_repeat, "unrelated progression refresh does not allocate duplicate materials")
	check(p.purchase("bandana_clay").ok and p.purchase("bike_sunshine").ok, "alternate owned choices apply")
	check(bandana_matches(walking.g, Color("b96548")) and bandana_matches(bike._rider.g, Color("b96548")) and bike._paint.albedo_color.is_equal_approx(Color("e6b949")), "alternate clothing and frame visibly change together")
	check(p.restore_state(saved) and p.money == int(saved.money), "restore uses saved ownership and wallet without charging")
	check(bandana_matches(walking.g, Color("467dba")) and bandana_matches(bike._rider.g, Color("467dba")) and bike._paint.albedo_color.is_equal_approx(Color("238f91")), "restore signal reapplies both visible appearance selections")
	for phase in [0.0, PI * 0.5, PI]:
		walking.phase = phase
		walking.pose({"walk": 0.7})
		bike._phase = phase
		bike._rider.g.visible = true
		bike._animate(0.1, 0.4)
	check(bandana_matches(walking.g, Color("467dba")) and bandana_matches(bike._rider.g, Color("467dba")), "walking and actual pedaling pose changes preserve chosen bandanas")
	check(materials_snapshot(walking.g, false, true) == walking_other and materials_snapshot(bike._rider.g, false, true) == rider_other, "walking and riding leave non-clothing materials isolated")
	var render := "--render-commerce-cosmetics" in OS.get_cmdline_user_args()
	if render:
		_setup_render(walking.g, neighbor.g, bike)
		await _capture("cosmetics-owned.png")
	p.begin_new_game(true)
	check(materials_snapshot(walking.g) == walking_original and materials_snapshot(bike._rider.g) == rider_original and bike._paint.albedo_color.is_equal_approx(Color("2db6a4")), "new game restores exact original exported materials and default bike paint")
	if render:
		await _capture("cosmetics-default.png")
	_test_fallback()
	world.free()
	bike.free()
	walking.g.free()
	neighbor.g.free()
	print("[commerce_cosmetics] failures=%d" % failures)
	get_tree().quit(1 if failures else 0)

func _test_fallback() -> void:
	var fallback := Cast._build("two_pack", Cast.LOOKS.two_pack)
	add_child(fallback)
	var original := materials_snapshot(fallback)
	var other := materials_snapshot(fallback, false, true)
	var bandanas := fallback.find_children("Bandana*", "MeshInstance3D", true, false)
	var names: Array[String] = []
	for mesh in bandanas:
		names.append(str(mesh.name))
	names.sort()
	check(names == ["BandanaBand", "BandanaKnot", "BandanaTail-1", "BandanaTail1"], "procedural fallback names band, knot and both tails: " + str(names))
	Cosmetics.bandana(fallback, "b96548")
	check(bandana_matches(fallback, Color("b96548")), "fallback material_override actually shows chosen color")
	check(materials_snapshot(fallback, false, true) == other, "fallback recolor leaves skin and red waist rings unchanged")
	Cosmetics.bandana(fallback, "")
	check(materials_snapshot(fallback) == original, "fallback default restores exact original overall overrides")
	fallback.free()

func _setup_render(walking: Node3D, neighbor: Node3D, bike: Node3D) -> void:
	walking.position = Vector3(-1.4, 0, 0)
	neighbor.position = Vector3(-3.3, 0, 0)
	bike.position = Vector3(1.0, 0, 0)
	bike.rotation.y = -0.35
	for entry in [[neighbor, "Shared-model neighbor"], [walking, "Walking player"], [bike, "Bicycle rider"]]:
		var label := Label3D.new()
		label.text = str(entry[1])
		label.font_size = 30
		label.pixel_size = 0.003
		label.position = entry[0].position + Vector3(0, 2.1, 0)
		add_child(label)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(2.1, 2.7, 7.5)
	camera.look_at(Vector3(-0.7, 1.0, 0))
	camera.fov = 48.0
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.3
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("49545c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e1e0d7")
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)

func _capture(filename: String) -> void:
	var folder := "res://../artifacts/next-five-20261101"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(filename)) == OK, filename)
