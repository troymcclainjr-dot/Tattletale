extends "res://tests/city_priorities_session_fixture.gd"
## Full imported city and normal player physics. Arrange only a street-side
## starting point, then walk and use E/GUI through production interaction paths.
## Failures remain failures even when later checks arrange a diagnostic pose.
const Catalog := preload("res://scripts/city/city_shop_catalog.gd")
const CosmeticAudit := preload("res://tests/city_commerce_cosmetics_runner.gd")

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/next-five-20261101/commerce-city-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	_cleanup()
	result_details.scope = "Actual city: street-to-window walk, real E and purchase buttons, exported cosmetics, settled counter footing, private checkpoint save/load. No removed colliders or reduced population."
	check(level.offscreen_validation and provider.path != Save.DEFAULT_PATH, "validation uses a private project checkpoint only")
	var shops: Node3D = level.shops
	check(shops.models.has(Catalog.SHOP_ID), "pantry service window registered in real city")
	if not shops.models.has(Catalog.SHOP_ID):
		_finish()
		return
	var window: Node3D = shops.models[Catalog.SHOP_ID]
	var local: Vector3 = window.get_meta("counter_local")
	var target := window.to_global(local)
	result_details.counter = [target.x, target.y, target.z]
	player.phone.close()
	level.basketball.suspend(true)
	level.resume_exploring()
	begin_phase("physical-access")
	var approach := Facilities.standing_at(level.get_world_3d().direct_space_state, window.to_global(local + Vector3(0, 0, 2.0)), [player.get_rid()])
	check(not approach.is_empty(), "street-side approach has real collision-clear support")
	if approach.is_empty():
		_finish()
		return
	_set_scenario_position(approach.position)
	await frames(20)
	check(not shops.open_shop(Catalog.SHOP_ID), "counter cannot open beyond its frontage interaction region")
	var reached := await _walk_to(target)
	check(reached, "normal walking physically reaches pantry counter from outside")
	result_details.walk_reached = reached
	if not reached:
		# Preserve the failed access assertion; isolate purchasing/footing next.
		_set_scenario_position(target + Vector3.UP * 0.15)
		result_details.diagnostic_counter_arrangement = true
	await frames(40)
	result_details.settled_feet = [player.global_position.x, player.global_position.y, player.global_position.z]
	check(player.is_on_floor() and absf(player.global_position.y - target.y) < 0.12, "actual player feet settle on the authored counter apron")
	check(shops.counter_at(player.global_position) == Catalog.SHOP_ID, "settled feet are within pantry interaction region")
	check(shops.counter_at(window.to_global(Vector3(local.x, local.y, 0))).is_empty(), "wrong side of solid storefront cannot activate counter")
	await _capture_city("pantry-city-frontage.png", window, local)
	begin_phase("purchase-and-appearance")
	var audit := CosmeticAudit.new()
	var skin_before: Dictionary = audit.materials_snapshot(player.puppet.g, false, true)
	var rider_before: Dictionary = audit.materials_snapshot(level.bicycle._rider.g, false, true)
	var balance := int(level.progression.money)
	await key(KEY_E)
	check(shops.is_open() and shops.active_id == Catalog.SHOP_ID, "real E input opens physical pantry counter")
	if not shops.is_open():
		audit.free()
		_finish()
		return
	await click(shops.stock_rows.get_node("Buy_bike_teal"))
	await click(shops.stock_rows.get_node("Buy_bandana_ocean"))
	check(level.progression.money == balance - 75 and level.progression.equipped_shop_item("bandana_color") == "bandana_ocean", "real purchase buttons debit exact total and equip owned goods")
	check(audit.bandana_matches(player.puppet.g, Color("467dba")) and audit.bandana_matches(level.bicycle._rider.g, Color("467dba")), "root change hook recolors actual walking and bicycle-rider bandanas")
	check(level.bicycle._paint.albedo_color.is_equal_approx(Color("238f91")), "root change hook applies real bicycle paint")
	check(audit.materials_snapshot(player.puppet.g, false, true) == skin_before and audit.materials_snapshot(level.bicycle._rider.g, false, true) == rider_before, "fullcity purchase leaves skin and all unrelated materials unchanged")
	await _capture_city("pantry-city-purchase.png", window, local)
	await key(KEY_ESCAPE)
	await frames(25)
	begin_phase("counter-checkpoint")
	var support_query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, player.global_position + Vector3.DOWN * 2.0, 1 | 2, [player.get_rid()])
	var support: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(support_query)
	result_details.support = {"collider": str(support.collider.get_path()), "height": support.position.y} if not support.is_empty() else {}
	var terrain: Dictionary = level.ground_at(player.global_position)
	result_details.terrain_height = terrain.position.y if not terrain.is_empty() else null
	var apron: Dictionary = shops.exterior_floor_at(player.global_position)
	check(not apron.is_empty() and apron.get("collider") == support.get("collider"), "checkpoint apron helper verifies exact physical civic support")
	check(shops.exterior_floor_at(window.to_global(Vector3(local.x, local.y, 0))).is_empty(), "apron support cannot authorize a point inside the solid building")
	check(shops.exterior_floor_at(target + Vector3.UP).is_empty() and shops.exterior_floor_at(target + Vector3.UP * 7.5).is_empty(), "counter-height and roof points cannot use apron support")
	check(shops.exterior_floor_at(window.to_global(local + Vector3(0, 0, 4))).is_empty(), "apron support is bounded to the customer frontage")
	result_details.checkpoint_blocker = provider.checkpoint_blocker()
	result_details.checkpoint_clearance = _checkpoint_clearance_probe(window)
	print("[commerce_clearance] ", JSON.stringify(result_details.checkpoint_clearance))
	check(player.is_on_floor() and shops.counter_at(player.global_position) == Catalog.SHOP_ID, "closing shop retains grounded counter position")
	var live_before_save := player.global_position
	var save_result: Error = provider.save_state()
	result_details.save_result = save_result
	result_details.save_reason = provider.last_result
	check(save_result == OK and FileAccess.file_exists(fixture), "save succeeds at actual settled pantry feet: " + str(provider.last_result))
	check(player.global_position.is_equal_approx(live_before_save), "checkpoint clearance correction never moves the live player")
	if save_result == OK:
		var saved_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
		var saved_feet := point(saved_file.player.position)
		var shift := saved_feet - live_before_save
		var horizontal_shift := Vector3(shift.x, 0.0, shift.z)
		var outward := window.global_basis.z.normalized()
		check(not provider._validated_player_position(saved_feet).is_empty(), "saved corrected feet independently pass exact full-capsule validation")
		check(horizontal_shift.length() <= 0.041 and horizontal_shift.dot(outward) >= -0.001 and horizontal_shift.cross(outward).length() < 0.001, "checkpoint adjustment stays within four centimetres straight outward on same apron")
		result_details.saved_feet = [saved_feet.x, saved_feet.y, saved_feet.z]
		result_details.saved_shift = [shift.x, shift.y, shift.z]
		var saved_money := int(level.progression.money)
		await key(KEY_E)
		if shops.is_open():
			await click(shops.stock_rows.get_node("Buy_bandana_clay"))
			await key(KEY_ESCAPE)
		await frames(5)
		var restored: Dictionary = provider.load_state()
		check(bool(restored.get("ok", false)) and level.progression.money == saved_money, "private checkpoint restores saved wallet without replaying purchases")
		check(level.progression.equipped_shop_item("bandana_color") == "bandana_ocean" and audit.bandana_matches(player.puppet.g, Color("467dba")) and audit.bandana_matches(level.bicycle._rider.g, Color("467dba")), "full checkpoint restores owned choice and both actual bandanas")
		await frames(10)
		check(player.is_on_floor() and shops.counter_at(player.global_position) == Catalog.SHOP_ID, "loaded counter position remains physically grounded and usable")
		check(not provider._validated_player_position(player.global_position).is_empty(), "restored settled feet retain exact checkpoint clearance")
	audit.free()
	player.camera_override = {}
	_finish()

func _capture_city(filename: String, window: Node3D, local: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.camera_override = {"eye": window.to_global(local + Vector3(4.5, 2.7, 5.0)), "target": window.to_global(local + Vector3(0, 1.1, -0.6))}
	player.update_camera()
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := "res://../artifacts/next-five-20261101"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(filename)) == OK, filename)

## Match production checkpoint predicates exactly; bounded diagnostic queries
## never move the player, omit a collider, or change a shape/margin.
func _checkpoint_clearance_probe(window: Node3D) -> Dictionary:
	var at := player.global_position
	var result := {"in_bounds": provider._in_bounds(at), "closed_shop": provider._inside_closed_shop(at),
		"actual_local": window.to_local(at), "capsule_radius": player._capsule.shape.radius,
		"capsule_height": player._capsule.shape.height, "nearby_residents": [], "candidates": []}
	var apron: Dictionary = level.shops.exterior_floor_at(at)
	if apron.is_empty():
		result.no_apron = true
		return result
	var snapped := Vector3(at.x, float(apron.position.y) + 0.02, at.z)
	result.snapped = snapped
	result.support_normal = apron.normal
	for actor in level.residents.actors.values():
		if actor.get_meta("city_dead", false):
			continue
		var offset: Vector3 = snapped - actor.global_position
		if Vector2(offset.x, offset.z).length() < 0.66 and absf(offset.y) < 1.9:
			result.nearby_residents.append({"path": str(actor.get_path()), "offset": offset})
			if result.nearby_residents.size() >= 8:
				break
	for distance in [0.0, 0.01, 0.02, 0.04, 0.08]:
		var candidate := snapped + window.global_basis.z.normalized() * float(distance)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player._capsule.shape
		query.transform = Transform3D(Basis.IDENTITY, candidate + player._capsule.position)
		query.collision_mask = 2 | 8 | 16
		query.exclude = [player.get_rid()]
		query.margin = 0.005
		var collisions: Array = []
		for hit in level.get_world_3d().direct_space_state.intersect_shape(query, 8):
			var body := hit.collider as CollisionObject3D
			var owner_id := body.shape_find_owner(int(hit.shape))
			var shape_node: Node = body.shape_owner_get_owner(owner_id)
			collisions.append({"body": str(body.get_path()), "shape_index": hit.shape,
				"shape_node": str(shape_node.get_path()) if is_instance_valid(shape_node) else "",
				"shape_position": shape_node.global_position if shape_node is Node3D else null})
		result.candidates.append({"outward_metres": distance, "position": candidate, "collisions": collisions,
			"exact_position": provider._validated_player_position(candidate)})
	return result
