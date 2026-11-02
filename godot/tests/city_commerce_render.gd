extends SceneTree
## Rendered fixture, not headless: real civic pantry, service window and shop UI.
const Fixture := preload("res://tests/city_commerce_smoke.gd")
const Shops := preload("res://scripts/city/city_shops.gd")
const Progression := preload("res://scripts/city/city_progression.gd")
const CivicBuilding := preload("res://scripts/city/city_civic_businesses.gd")
const Catalog := preload("res://scripts/city/city_shop_catalog.gd")
const OUTPUT := "res://../artifacts/next-five-20261101"
var finished := false
var failures := 0

func _initialize() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await create_timer(60.0, true, false, true).timeout
	if not finished:
		print("[commerce_render] FAIL watchdog")
		quit(1)

func capture(view: SubViewport, filename: String) -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image().save_png(OUTPUT.path_join(filename))
	print("[commerce_render] %s %s" % ["PASS" if result == OK else "FAIL", filename])
	if result != OK:
		failures += 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var view := SubViewport.new()
	view.size = Vector2i(1280, 900)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	root.add_child(view)
	var world := Fixture.CommerceWorld.new()
	view.add_child(world)
	world.combat = Fixture.CommerceHealth.new()
	world.law = Fixture.CommerceGate.new()
	world.driving = Fixture.CommerceGate.new()
	world.bicycle = Fixture.CommerceGate.new()
	world.player = Fixture.CommercePlayer.new()
	world.progression = Progression.new()
	world.shops = Shops.new()
	for node in [world.combat, world.law, world.driving, world.bicycle, world.player, world.progression, world.shops]:
		world.add_child(node)
	var district := Fixture.CommerceDistrict.new()
	world.add_child(district)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_new_businesses.json"))
	var entry := {}
	for candidate in data.businesses:
		if str(candidate.id) == Catalog.SHOP_ID:
			entry = candidate
	if entry.is_empty():
		quit(1)
		return
	district.businesses.append(entry)
	district.map_pois.append({"id": entry.id, "label": entry.label, "position": Vector3.ZERO, "service": entry.service})
	var model := CivicBuilding.build(entry)
	model.position = Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2]))
	model.rotation.y = float(entry.yaw)
	district.add_child(model)
	world.shops.register_corner_store(district)
	world.shops.setup(world)
	world.progression.setup(world)
	var camera := Camera3D.new()
	view.add_child(camera)
	var front := float(entry.depth) * 0.5
	camera.position = model.to_global(Vector3(7.5, 4.5, front + 12.5))
	camera.look_at(model.to_global(Vector3(0.5, 3.15, front)))
	camera.fov = 58.0
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("596b78")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d7d0be")
	environment.environment.ambient_light_energy = 0.7
	view.add_child(environment)
	await capture(view, "pantry-window.png")
	var window: Node3D = world.shops.models[Catalog.SHOP_ID]
	world.player.global_position = window.to_global(window.get_meta("counter_local"))
	world.combat.health = 75.0
	if not world.shops.open_shop(Catalog.SHOP_ID):
		print("[commerce_render] FAIL pantry did not open")
		quit(1)
		return
	world.shops.purchase("bike_teal")
	world.shops.purchase("bandana_ocean")
	await capture(view, "pantry-catalog.png")
	var scroll: ScrollContainer = world.shops.stock_rows.get_parent()
	scroll.scroll_vertical = 10000
	await capture(view, "pantry-catalog-food.png")
	world.shops.close()
	view.free()
	finished = true
	quit(1 if failures else 0)
