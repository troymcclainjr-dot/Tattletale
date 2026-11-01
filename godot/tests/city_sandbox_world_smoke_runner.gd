extends Node
## Full exported-world integration. No mock progression, shop, car or law managers.
## All files are isolated project fixtures; no actual user checkpoint is touched.
const Save := preload("res://scripts/city/city_world_save.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
var level: Node3D
var player: CharacterBody3D
var provider: Node
var passes := 0
var failures := 0
var finished := false
var fixture := ""
var startup_position := Vector3.ZERO
var purchased_id := ""
var purchase_inventory: Dictionary = {}
var purchase_progression: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(300.0, true, false, true).timeout
	if not finished:
		check(false, "full-world fixture completes within 300 seconds (including cold world boot)")
		_finish()

func check(ok: bool, label: String) -> void:
	print("[sandbox_world] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame

func click(button: Button) -> void:
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(button)
	await get_tree().process_frame
	var at: Vector2 = button.get_global_transform_with_canvas() * (button.size * .5)
	var viewport := button.get_viewport()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().process_frame

func point(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	for script_path in ["res://scripts/city/city_progression.gd", "res://scripts/city/city_driving.gd", "res://scripts/city/city_law.gd"]:
		if not ResourceLoader.exists(script_path):
			check(false, "required manager source exists: " + script_path)
			_finish()
			return
	fixture = ProjectSettings.globalize_path("res://../.work/sandbox-foundations/world-integration/world.json")
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	_cleanup()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	for index in 800:
		level = get_tree().current_scene as Node3D
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
	if level == null or level.get("level_ready") != true:
		check(false, "real exported level boots")
		_finish()
		return
	var ready := true
	for manager in ["player", "shops", "progression", "driving", "law", "combat", "world_save"]:
		ready = ready and level.get(manager) != null
	check(ready, "actual level boots with all sandbox managers")
	if not ready:
		_finish()
		return
	level.resume_exploring()
	for index in 300:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	check(int(level.residents.get_status().pending_routes) == 0, "resident routes finish before deterministic scenarios")
	player = level.player
	var starter: Dictionary = level.combat.equipment_snapshot()
	check(starter.equipped == "fists" and starter.weapons.fists.owned and not starter.weapons.pistol.owned, "fresh headless world honors configured fists-only starting ownership")
	startup_position = player.global_position
	# Freeze NPC/traffic scheduling, not collision. Only production methods for
	# the controlled scenario advance below, with fixed 1/60-second steps.
	level.set_physics_process(false)
	player.set_physics_process(false)
	provider = Save.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	check(provider.enabled and provider.path == fixture and not level.world_save.enabled, "checkpoint writes are isolated from the actual player slot")
	await _shops_and_modal()
	await _save_roundtrip()
	_facility_geometry()
	await _inspector_cancellation()
	await _driving_and_law()
	_finish()

func _walk_to(destination: Vector3) -> bool:
	var direction := destination - player.global_position
	player.camera_yaw = atan2(direction.x, direction.z)
	player.yaw = player.camera_yaw
	player.set_orbiting(false)
	player._clear_basis_offset()
	Input.action_press("move_forward")
	Input.action_press("run")
	var stalled := 0
	var reached := false
	for step in 420:
		if flat_distance(player.global_position, destination) <= .20:
			reached = true
			break
		var before := player.global_position
		var toward := destination - before
		player.camera_yaw = atan2(toward.x, toward.z)
		await get_tree().physics_frame
		player._physics_process(1.0 / 60.0)
		await get_tree().process_frame
		stalled = stalled + 1 if flat_distance(before, player.global_position) < .001 else 0
		if stalled > 45 or absf(player.global_position.y - destination.y) > 4.0:
			break
	Input.action_release("move_forward")
	Input.action_release("run")
	player.current_speed = 0.0
	player.velocity = Vector3.ZERO
	if not reached:
		print("[sandbox_world] walk blocked from ", player.global_position, " to ", destination)
		for contact in player.get_slide_collision_count():
			print("[sandbox_world] contact ", player.get_slide_collision(contact).get_collider())
	return reached

func _shops_and_modal() -> void:
	var shops: Node3D = level.shops
	check(not shops.definitions.is_empty() and shops.models.size() == shops.definitions.size(), "every authored shop has exactly one real building")
	var purchased := false
	for entry in shops.definitions:
		var model: Node3D = shops.models[str(entry.id)]
		check(level.find_child(str(entry.source_mesh), true, false) == null and str(entry.source_mesh) in level.civic_district.removed_meshes,
			str(entry.id) + " original building mesh/collider removed before world collision import")
		var front := float(entry.depth) * .5
		var space := level.get_world_3d().direct_space_state
		var opening := PhysicsRayQueryParameters3D.create(model.to_global(Vector3(0, 1.1, front + .5)), model.to_global(Vector3(0, 1.1, front - 1.0)), 2 | 16)
		var wall := PhysicsRayQueryParameters3D.create(model.to_global(Vector3(float(entry.width) * .5 - .4, 1.1, 0)), model.to_global(Vector3(float(entry.width) * .5 + .4, 1.1, 0)), 2)
		check(space.intersect_ray(opening).is_empty() and not space.intersect_ray(wall).is_empty(), str(entry.id) + " full-world entrance is open while side wall stays solid")
		var start := point(entry.approach_start)
		var door := point(entry.entry_world)
		var counter: Vector3 = model.to_global(model.get_meta("counter_local"))
		player.global_position = start + Vector3.UP * .03
		player.reset_jump()
		player.velocity = Vector3.ZERO
		level.resume_exploring()
		await frames(20)
		var entered := await _walk_to(door)
		entered = (await _walk_to(counter)) and entered
		check(entered and shops.counter_at(player.global_position) == str(entry.id), str(entry.id) + " real player runs up ramp, through doorway and to counter")
		if entered and not purchased and str(entry.kind) == "gun":
			purchased = await _purchase_and_modal(str(entry.id))
		var exited := await _walk_to(door)
		exited = (await _walk_to(start)) and exited
		check(exited and shops.counter_at(player.global_position).is_empty(), str(entry.id) + " real player exits without teleporting across building collision")
	check(purchased, "at least one real shop UI purchase succeeds")

func _purchase_and_modal(identity: String) -> bool:
	var shops: Node3D = level.shops
	var economy: Node = level.progression
	var before_equipment: Dictionary = level.combat.equipment_snapshot()
	var desired: String = "ammo_pistol" if before_equipment.weapons.pistol.owned else "pistol"
	var item := _stock_item(desired)
	if item.is_empty() or int(item.price) > int(economy.money):
		check(false, "starter wallet can afford the actual starter firearm/ammunition")
		return false
	var modal_weapon: String = level.combat.weapon
	var before_cash: int = economy.money
	var spent := 0
	await key(KEY_E)
	check(shops.is_open() and shops.active_id == identity and level.paused and not player.enabled, "E opens real counter modal and root suspends world/player input")
	if not shops.is_open():
		return false
	var before_punches: int = level.combat.punches_thrown
	var before_shots: int = level.combat.shots_fired
	var before_position := player.global_position
	await key(KEY_4)
	await key(KEY_P)
	await key(KEY_F)
	Input.action_press("move_forward")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var attack := InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	attack.pressed = true
	attack.position = Vector2(4, 4)
	get_viewport().push_input(attack, true)
	attack.pressed = false
	get_viewport().push_input(attack, true)
	await frames(1)
	check(level.combat.weapon == modal_weapon and level.combat.punches_thrown == before_punches and level.combat.shots_fired == before_shots and not player.phone.active and not level.driving.active and player.global_position.is_equal_approx(before_position), "shop modal suppresses root weapon/phone/driving/attack/movement inputs")
	var button := shops.stock_rows.get_node_or_null("Buy_" + str(item.id)) as Button
	check(button != null and not button.disabled, "actual catalog exposes an affordable enabled purchase button")
	if button == null or button.disabled:
		shops.close()
		return false
	await click(button)
	spent += int(item.price)
	purchased_id = str(item.id)
	if desired == "pistol":
		check(level.combat.equipment_snapshot().weapons.pistol.owned and int(economy.money) == before_cash - spent,
			"fists-only new game buys its first pistol through the real counter button")
		var ammunition := _stock_item("ammo_pistol")
		var ammo_button := shops.stock_rows.get_node_or_null("Buy_ammo_pistol") as Button
		check(not ammunition.is_empty() and ammo_button != null and not ammo_button.disabled,
			"newly owned pistol permits affordable ammunition purchase")
		if not ammunition.is_empty() and ammo_button != null and not ammo_button.disabled:
			await click(ammo_button)
			spent += int(ammunition.price)
			purchased_id = "pistol+ammo_pistol"
	purchase_inventory = level.combat.equipment_snapshot()
	purchase_progression = economy.snapshot_state()
	check(int(economy.money) == before_cash - spent and purchase_inventory != before_equipment and int(purchase_inventory.weapons.pistol.reserve) > int(before_equipment.weapons.pistol.reserve),
		"real weapon/ammunition GUI purchases debit exact prices and grant combat inventory once")
	var inside: Dictionary = provider.snapshot_state()
	check(not inside.is_empty() and shops.counter_at(player.global_position) == identity,
		"raised shop interior floor supports a checkpoint immediately after purchase")
	if not inside.is_empty():
		var written: int = provider.write_snapshot(inside)
		var read: Dictionary = provider.read_snapshot()
		var disk_state: Dictionary = read.get("state", {})
		# JSON turns integer Variants into floats and typed arrays into ordinary
		# arrays. Compare the complete payload in its serialized value domain;
		# read_snapshot still enforces the production schema before this check.
		var expected_inventory: Variant = JSON.parse_string(JSON.stringify(purchase_inventory))
		var expected_progression: Variant = JSON.parse_string(JSON.stringify(purchase_progression))
		var inventory_matches: bool = disk_state.get("inventory", {}) == expected_inventory
		var progression_matches: bool = disk_state.get("progression", {}) == expected_progression
		print("[sandbox_world] interior disk write=%d read_ok=%s reason=%s source=%s inventory=%s progression=%s" % [written,
			read.get("ok", false), read.get("reason", ""), read.get("source", ""), inventory_matches, progression_matches])
		if not inventory_matches or not progression_matches:
			print("[sandbox_world] expected purchase=" + JSON.stringify({"inventory": expected_inventory, "progression": expected_progression}))
			print("[sandbox_world] disk purchase=" + JSON.stringify({"inventory": disk_state.get("inventory", {}), "progression": disk_state.get("progression", {})}))
		check(written == OK and read.get("ok", false) and inventory_matches and progression_matches,
			"purchase persists to disk while player remains at the interior counter")
	await key(KEY_ESCAPE)
	check(not shops.is_open() and not level.paused and player.enabled, "Escape closes shop and root restores exploration")
	return int(economy.money) == before_cash - spent and purchase_inventory != before_equipment

func _stock_item(id: String) -> Dictionary:
	for candidate in level.progression.catalog("gun"):
		if str(candidate.id) == id:
			return candidate
	return {}

func _save_roundtrip() -> void:
	player.global_position = startup_position
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	level.combat.cancel_player_actions()
	level.combat.combo = 0
	level.pause_exploring()
	await frames(2)
	var economy: Node = level.progression
	var before_alignment: Dictionary = economy.snapshot_state()
	economy.apply_action("dialogue_own_it", {"key": "integration_snitch", "source": "dialogue"})
	economy.apply_action("dialogue_vouch_street", {"key": "integration_street", "source": "dialogue"})
	var expected_progression: Dictionary = economy.snapshot_state()
	var expected_inventory: Dictionary = level.combat.equipment_snapshot()
	check(int(expected_progression.reputation.snitch) > int(before_alignment.reputation.snitch) and int(expected_progression.reputation.gangsta) > int(before_alignment.reputation.gangsta), "configured dialogue actions change both independent alignment tracks before save")
	var snapshot: Dictionary = provider.snapshot_state()
	check(not snapshot.is_empty() and int(snapshot.get("version", 0)) == Save.VERSION, "real stable-ground world produces current-schema checkpoint")
	if snapshot.is_empty():
		return
	check(snapshot.inventory == expected_inventory and snapshot.progression == expected_progression and provider.validate_snapshot(snapshot).is_empty(), "world checkpoint includes purchased ammo, actual wallet and both alignment tracks")
	check(provider.write_snapshot(snapshot) == OK, "complete sandbox checkpoint writes atomically to isolated fixture")
	economy.debit(1, "integration mutation")
	level.combat.add_ammo("pistol", 3)
	var loaded: Dictionary = provider.load_state()
	check(loaded.get("ok", false) and economy.snapshot_state() == expected_progression and level.combat.equipment_snapshot() == expected_inventory,
		"schema3 disk roundtrip restores exact purchase inventory, money and alignment")
	# A real old v2 save has no progression/inventory, but did already award its
	# completed mission score. Migration must mark payment without paying again.
	var authored: Dictionary = level.missions.save_schema()
	var case_id := str(authored.keys()[0])
	var reward := int(authored[case_id].reward)
	# Earliest v1 slots had no equipment field. Restore from a rich, wounded
	# session to prove the migration supplies defaults rather than preserving it.
	var earliest: Dictionary = snapshot.duplicate(true)
	earliest.version = 1
	for field in ["equipment", "inventory", "progression", "deaths"]:
		earliest.erase(field)
	level.combat.grant_weapon("ak47")
	level.combat.add_ammo("ak47", 100)
	level.combat.equip("ak47")
	level.combat.health = 21.0
	economy.credit(5000, "integration future wealth")
	check(provider.validate_snapshot(earliest).is_empty() and provider.write_snapshot(earliest) == OK,
		"equipmentless early v1 checkpoint remains valid")
	var earliest_result: Dictionary = provider.load_state()
	var earliest_inventory: Dictionary = level.combat.equipment_snapshot()
	check(earliest_result.get("ok", false) and level.combat.health == 100.0 and earliest_inventory.equipped == "fists"
		and earliest_inventory.weapons.pistol.owned and earliest_inventory.weapons.pistol.ammo == 12 and earliest_inventory.weapons.pistol.reserve == 72
		and not earliest_inventory.weapons.ak47.owned and not earliest_inventory.weapons.uzi.owned
		and level.combat.ammo == 0 and level.combat.reserve == 0 and int(economy.money) == int(economy.config.money.starting),
		"equipmentless v1 replaces future guns, wealth and wounds with deterministic historical defaults")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.version = 2
	legacy.erase("inventory")
	legacy.erase("progression")
	legacy.equipment = {"health": 100.0, "weapon": "fists", "ammo": 3, "reserve": 19}
	legacy.missions = {"active_id": "", "stage": 0, "completed_ids": [case_id], "score": reward}
	var legacy_cash: int = economy.config.money.starting
	level.combat.grant_weapon("ak47")
	level.combat.add_ammo("ak47", 100)
	check(provider.validate_snapshot(legacy).is_empty() and provider.write_snapshot(legacy) == OK, "genuine v2 completed-case checkpoint remains valid")
	var migrated: Dictionary = provider.load_state()
	check(level.combat.weapon == "fists" and level.combat.ammo == 0 and level.combat.reserve == 0, "v2 fists restore keeps current fists inventory empty")
	level.combat.equip("pistol")
	check(level.combat.ammo == 3 and level.combat.reserve == 19, "v2 fists legacy shared ammo migrates to pistol without refill or loss")
	check(not level.combat.equipment_snapshot().weapons.ak47.owned and int(economy.money) == legacy_cash, "loading v2 discards unsaved future guns and wealth before applying legacy migration")
	var first_reward: bool = economy.reward_case(case_id, reward)
	var repeat: Dictionary = provider.load_state()
	var second_reward: bool = economy.reward_case(case_id, reward)
	check(migrated.get("ok", false) and repeat.get("ok", false) and not first_reward and not second_reward and int(economy.money) == legacy_cash,
		"v2 completed-case migration and repeated load never replay cash rewards")
	check(level.missions.snapshot_state().completed_ids.has(case_id),
		"legacy mission completion remains recorded after wallet migration")
	check(provider.write_snapshot(snapshot) == OK and provider.load_state().get("ok", false), "new-format checkpoint remains restorable after legacy migration exercise")
	level.resume_exploring()

func _facility_geometry() -> void:
	for site in ["hospital", "police"]:
		var release: Dictionary = Facilities.release_point(level, site, player)
		check(release.get("ok", false) and not release.get("fallback", true) and int(release.checks) <= Facilities.MAX_CANDIDATES,
			site + " actual civic frontage has a bounded nonfallback release point")
		if not release.get("ok", false):
			continue
		var at: Vector3 = release.position
		var support := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .20, at - Vector3.UP * .20, 1 | 2, [player.get_rid()])
		var space := level.get_world_3d().direct_space_state
		var ground: Dictionary = space.intersect_ray(support)
		var capsule := PhysicsShapeQueryParameters3D.new()
		capsule.shape = player._capsule.shape
		capsule.transform = Transform3D(Basis.IDENTITY, at + player._capsule.position)
		capsule.collision_mask = 2 | 8 | 16
		capsule.exclude = [player.get_rid()]
		capsule.margin = .01
		check(not ground.is_empty() and float(ground.normal.y) > .8 and space.intersect_shape(capsule, 1).is_empty(),
			site + " release point independently supports the actual player capsule without overlap")

func _inspector_cancellation() -> void:
	level.resume_exploring()
	level.combat.grant_weapon("uzi")
	level.combat.equip("uzi")
	level.combat._trigger_held = true
	var shots: int = level.combat.shots_fired
	await key(KEY_F6)
	check(level.inspector.active and not level.combat._trigger_held, "F6 inspector entry cancels an already held Uzi trigger")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await key(KEY_F6)
	level.combat.tick(.1)
	check(not level.inspector.active and not level.combat._trigger_held and level.combat.shots_fired == shots, "releasing in inspector and returning never fires a stale automatic round")
	level.combat.equip("fists")
	level.resume_exploring()

func _driving_and_law() -> void:
	await _driving_scenario()
	await _law_scenario()

func _drive_steps(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		level.driving.tick(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
		await get_tree().process_frame

func _driving_scenario() -> void:
	var driving: Node3D = level.driving
	var car: Node3D = driving.starter
	check(is_instance_valid(car) and driving.get_status().starter_spawned, "actual exported neighborhood supplies a reachable starter car")
	if not is_instance_valid(car):
		return
	level.resume_exploring()
	var size: Vector3 = driving._car_size(car)
	var spot: Dictionary = {}
	for side in [1.0, -1.0]:
		spot = driving._exit_spot(car, side * (size.x * .5 + .65), .25, true)
		if not spot.is_empty():
			break
	check(not spot.is_empty(), "starter car has an actual clear supported door approach")
	if spot.is_empty():
		return
	player.global_position = spot.position
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.reset_jump()
	level.traffic._update_presence()
	await frames(20)
	for index in 8:
		await get_tree().physics_frame
		player._physics_process(1.0 / 60.0)
		await get_tree().process_frame
	driving.tick(.11)
	check(player.is_on_floor() and driving.get_status().candidate_id == str(car.vehicle_id) and str(driving.get_status().prompt).contains("F"), "standing at starter door exposes the real F driving prompt")
	await key(KEY_F)
	check(driving.active and driving.vehicle == car and car.player_controlled and player.seated_vehicle == car,
		"actual root F input transfers starter authority and seats the player")
	if not driving.active:
		return
	check(car.force_detailed and not car._render_lod_active and str(car.reservation_id).is_empty() and not level.combat.accepts_player_input() and not provider.can_checkpoint(),
		"occupied car keeps full model, no junction reservation, and blocks combat/checkpoints")
	var start_pose: Transform3D = car.global_transform
	car.tick(.1)
	check(car.global_transform.is_equal_approx(start_pose), "ordinary AI vehicle tick cannot move the occupied car")
	var weapon: String = level.combat.weapon
	await key(KEY_2)
	await key(KEY_P)
	check(level.combat.weapon == weapon and not player.phone.active, "root driving mode suppresses firearm and phone hotkeys")
	# A small low-speed movement tests the real solver in the actual curb lane.
	driving.set_control_override(1.0, 0.0, 0.0, false)
	await _drive_steps(25)
	check(flat_distance(car.global_position, start_pose.origin) > .08 and absf(float(car.speed)) > .1,
		"actual starter accelerates and moves through production swept driving physics")
	await key(KEY_ESCAPE)
	var paused_pose: Transform3D = car.global_transform
	var paused_seat := player.global_position
	var paused_speed: float = car.speed
	await _drive_steps(12)
	check(level.paused and driving.active and car.global_transform.is_equal_approx(paused_pose) and player.global_position.is_equal_approx(paused_seat) and is_equal_approx(float(car.speed), paused_speed),
		"root pause freezes both occupied vehicle and seated body despite held throttle")
	await key(KEY_ESCAPE)
	driving.set_control_override(0.0, 1.0, 0.0, true)
	for step in 60:
		await _drive_steps(1)
		if absf(float(car.speed)) <= .1:
			break
	# Brake also becomes reverse after stopping; release as soon as stopped.
	driving.set_control_override(0.0, 0.0, 0.0, true)
	await _drive_steps(30)
	check(absf(float(car.speed)) <= driving.EXIT_MAX_SPEED, "handbrake brings the actual car to an exit-safe speed")
	driving.clear_control_override()
	await key(KEY_F)
	check(not driving.active and not car.player_controlled and player.seated_vehicle == null and player.collision_layer == 4,
		"actual F exit restores explorer collision and relinquishes player authority")
	if driving.active:
		driving.exit_vehicle(true)
		return
	var exit_pose: Transform3D = car.global_transform
	car.tick(.1)
	check(car.global_transform.is_equal_approx(exit_pose) and car.player_released, "released starter remains parked instead of resuming an old AI route")
	var capsule := PhysicsShapeQueryParameters3D.new()
	capsule.shape = player._capsule.shape
	capsule.transform = Transform3D(Basis.IDENTITY, player.global_position + player._capsule.position)
	capsule.exclude = [player.get_rid()]
	capsule.collision_mask = 2 | 8 | 16
	capsule.margin = .005
	check(level.get_world_3d().direct_space_state.intersect_shape(capsule, 1).is_empty(), "actual dismount clears car, buildings, street props and people")

func _law_steps(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		level.law.tick(1.0 / 60.0)
		level.progression.tick(1.0 / 60.0)
		await get_tree().process_frame

func _set_scenario_position(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.reset_jump()
	player.update_camera()
	level.npcs.crowd.set_presence(at)
	level.traffic._update_presence()

func _no_visible_witness(at: Vector3) -> bool:
	# Stronger precondition than the bounded production scan: check every
	# current candidate, including candidates beyond its ten-ray budget.
	var law: Node = level.law
	var space := level.get_world_3d().direct_space_state
	for candidate in law._witness_candidates(at, law.HEARING_RADIUS + 2.0, []):
		if law._clear_sight(space, Vector3(candidate.position) + Vector3.UP * law.EYE_HEIGHT,
			at + Vector3.UP * law.CHEST_HEIGHT, candidate.rid):
			return false
	return true

func _unseen_location() -> Vector3:
	var candidates: Array[Vector3] = []
	# Enclosed actual shop floors are useful occlusion cases. If an open
	# doorway gives a witness sight, try supported surveyed road vertices.
	for model in level.shops.models.values():
		candidates.append(model.to_global(model.get_meta("counter_local")))
	for road in level.level_data.get("roads", []):
		for value in road.get("points", []):
			if candidates.size() >= 100:
				break
			candidates.append(point(value))
		if candidates.size() >= 100:
			break
	var exclude: Array[RID] = [player.get_rid()]
	for at in candidates:
		var standing := Facilities.standing_at(level.get_world_3d().direct_space_state, at, exclude)
		if standing.is_empty():
			continue
		_set_scenario_position(standing.position)
		await frames(2) # Newly present crowd collisions must reach the server.
		if _no_visible_witness(player.global_position):
			return player.global_position
	return Vector3.INF

func _shoot_up() -> bool:
	level.combat.cancel_player_actions()
	level.combat.equip("pistol")
	# Real firearm/muzzle/raycast/event chain, aimed away from every bystander.
	# Only scene arrangement is synthetic; no offense signal is emitted here.
	level.combat._shot_cooldown = 0.0
	player.camera.global_position = player.global_position + Vector3.UP * 1.55
	player.camera.look_at(player.camera.global_position + Vector3(.1, 1, 0), Vector3.BACK)
	return level.combat._fire()

func _assert_release(kind: String, expected_fee: int, cash_before: int) -> void:
	var law: Node = level.law
	var status: Dictionary = law.get_status()
	check(not law.recovering and status.last_recovery.get("kind", "") == kind and status.last_recovery.get("relocated", false),
		kind + " completes at the real civic facility")
	check(law.wanted == 0 and law.heat == 0 and level.combat.health == 100.0 and level.combat.downed == 0.0 and player.enabled,
		kind + " clears incident and restores healthy exploration")
	check(int(status.last_fee) == expected_fee and int(level.progression.money) == cash_before - expected_fee,
		kind + " charges the exact affordable fee once")
	var release: Dictionary = status.last_release
	check(release.get("ok", false) and not release.get("fallback", true) and player.global_position.distance_to(Vector3(release.get("position", Vector3.INF))) < .12,
		kind + " uses a checked nonfallback facility release point")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._capsule.shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + player._capsule.position)
	query.exclude = [player.get_rid()]
	query.collision_mask = 2 | 8 | 16
	query.margin = .005
	check(level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(),
		kind + " release capsule clears the actual world")

func _law_scenario() -> void:
	var law: Node = level.law
	level.resume_exploring()
	law.reset_state()
	level.combat.recover_player()
	var unseen: Vector3 = await _unseen_location()
	check(unseen.is_finite(), "actual supported world has a checked location with no visible witnesses")
	if unseen.is_finite():
		var reputation: Dictionary = level.progression.snapshot_state().reputation.duplicate()
		var offenses: int = law.offenses_received
		check(_shoot_up(), "unseen scenario fires an actual owned pistol round")
		await _law_steps(18)
		check(law.offenses_received == offenses + 1 and law.last_scan.get("observed", []).is_empty(),
			"actual unseen shot reaches bounded law perception exactly once")
		check(level.progression.snapshot_state().reputation == reputation and law.wanted == 0,
			"unseen shot causes no reputation gain or identified wanted level")
	law.reset_state()
	level.combat.recover_player()
	# Find a real patrol and supported position with direct sight; never
	# manufacture a witness or move an NPC into the scenario.
	var officer: CharacterBody3D = null
	var found := Vector3.INF
	var exclude: Array[RID] = [player.get_rid()]
	for actor in law._police():
		if not str(actor.actor_id).begins_with("patrol_officer_"):
			continue
		for angle in [0.0, PI * .5, PI, PI * 1.5]:
			var desired: Vector3 = actor.global_position + Vector3(sin(angle), 0, cos(angle)) * 3.0
			var standing := Facilities.standing_at(level.get_world_3d().direct_space_state, desired, exclude)
			if standing.is_empty():
				continue
			if law._clear_sight(level.get_world_3d().direct_space_state, actor.global_position + Vector3.UP * law.EYE_HEIGHT,
				Vector3(standing.position) + Vector3.UP * law.CHEST_HEIGHT, actor.get_rid()):
				officer = actor
				found = standing.position
				break
		if officer != null:
			break
	check(officer != null, "existing foot patrol has a clear supported nearby witness position")
	if officer != null:
		_set_scenario_position(found)
		await frames(2)
		var reputation_before: int = level.progression.snapshot_state().reputation.gangsta
		var offenses_before: int = law.offenses_received
		check(_shoot_up(), "patrol scenario fires an actual owned pistol round")
		await _law_steps(18)
		check(law.offenses_received == offenses_before + 1 and law.last_scan.get("observed", []).has(str(officer.actor_id)) and law.wanted > 0,
			"nearby real patrol observes one shot and establishes wanted status")
		check(int(level.progression.snapshot_state().reputation.gangsta) > reputation_before,
			"root witnessed-offense signal awards configured reputation")
		check(int(law.get_status().responder_count) <= law.MAX_RESPONDERS and int(law.last_scan.get("rays", 0)) <= law.MAX_WITNESS_CHECKS,
			"real incident retains responder and perception budgets")
		var cash: int = level.progression.money
		var fee := mini(cash, int(law.ARREST_FINES[clampi(int(law.wanted), 1, law.MAX_WANTED)]))
		var arrests: int = law.arrests
		await key(KEY_G)
		check(law.recovering and law.get_status().recovery.get("kind", "") == "arrest", "actual root G input begins surrender to the visible patrol")
		for step in 420:
			if not law.recovering:
				break
			await _law_steps(1)
		_assert_release("arrest", fee, cash)
		await _law_steps(20)
		check(law.arrests == arrests + 1 and int(level.progression.money) == cash - fee, "completed arrest cannot repeat its fine")
	# A real fatal hit while seated exercises law -> driving forced exit,
	# hospital relocation, combat healing and exploration ownership together.
	law.reset_state()
	level.combat.recover_player()
	var driving: Node3D = level.driving
	var car: Node3D = driving.starter
	var size: Vector3 = driving._car_size(car)
	var door: Dictionary = {}
	for side in [1.0, -1.0]:
		door = driving._exit_spot(car, side * (size.x * .5 + .65), .25, true)
		if not door.is_empty():
			break
	check(not door.is_empty(), "released starter retains a supported door for recovery handoff")
	if door.is_empty():
		return
	_set_scenario_position(door.position)
	await _drive_steps(8)
	driving.tick(.11)
	await key(KEY_F)
	check(driving.active, "actual F boards the parked starter before the defeat scenario")
	if not driving.active:
		return
	var cash: int = level.progression.money
	var visits: int = law.hospital_visits
	var fee := mini(cash, int(law.HOSPITAL_FEE))
	level.combat._invulnerable = 0.0
	check(level.combat._hurt_player(1000.0) and law.recovering, "actual combat defeat signal starts hospital recovery while seated")
	for step in 480:
		if not law.recovering:
			break
		await _law_steps(1)
	_assert_release("hospital", fee, cash)
	check(not driving.active and player.seated_vehicle == null and not car.player_controlled and player.collision_layer == 4,
		"hospital recovery exits the real car and restores explorer ownership/collision")
	await _law_steps(20)
	check(law.hospital_visits == visits + 1 and int(level.progression.money) == cash - fee, "completed hospital recovery cannot repeat its bill")

func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = fixture + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _finish() -> void:
	if finished:
		return
	finished = true
	Input.action_release("move_forward")
	Input.action_release("run")
	print("[sandbox_world] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
