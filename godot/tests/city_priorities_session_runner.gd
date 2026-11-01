extends "res://tests/city_priorities_session_fixture.gd"
## Combined acceptance through the actual world input and save boundary.
const SessionCarModels := preload("res://scripts/city/city_car_models.gd")
# Authored amends paths: report case $90; protect action $40; negotiated case
# $60; intimidation +$120 followed by the full -$120 repayment. This gate
# explicitly checks those outcomes; repeatable earned income is tested below.
const STORY_AMENDS_NET_CASH := {"report": 90, "protect": 40, "negotiate": 60, "intimidate": 0}
var remembered_car: Node3D
var remembered_source := ""
var remembered_record := -1
var expected_durable: Dictionary = {}
var collision_events: Array[Dictionary] = []

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	await session_flow()
	_finish()

func session_flow() -> void:
	for method in ["snapshot_state", "validate_state", "preflight_state", "restore_state", "reset_persistent_state"]:
		check(level.driving.has_method(method), "driving persistence API available: " + method)
	check(level.traffic.has_method("external_vehicles") and level.traffic.parked.has_method("source_index"),
		"vehicle external authority and stable parked-source APIs available")
	if failures > 0:
		return
	begin_phase("supplies")
	await shop_visit()
	if failures > 0:
		return
	begin_phase("stopped-civilian-input")
	await stopped_traffic_input()
	if failures > 0:
		return
	begin_phase("parked-promotion-drive-impact")
	await parked_drive()
	if failures > 0:
		return
	begin_phase("gunfire-cruiser-pursuit-loss-surrender")
	await police_flow()
	if failures > 0:
		return
	begin_phase("shop-after-recovery")
	await shop_visit(false)
	begin_phase("branching-story")
	await story_flow()
	if failures > 0:
		return
	begin_phase("save-scene-reload")
	await durable_reload()

func shop_visit(purchase := true) -> void:
	var selected: Dictionary = {}
	for definition in level.shops.definitions:
		if str(definition.kind) == "gun":
			selected = definition
			break
	check(not selected.is_empty(), "real gun shop exists")
	if selected.is_empty():
		return
	var model: Node3D = level.shops.models[str(selected.id)]
	_set_scenario_position(point(selected.approach_start) + Vector3.UP * .03)
	level.resume_exploring()
	await frames(15)
	var entered := await _walk_to(point(selected.entry_world))
	entered = (await _walk_to(model.to_global(model.get_meta("counter_local")))) and entered
	check(entered and level.shops.counter_at(player.global_position) == str(selected.id), "real input walks through supported doorway to counter")
	if not entered:
		return
	if purchase:
		check(await _purchase_and_modal(str(selected.id)), "counter GUI debits purchase exactly once")
	else:
		var cash: int = level.progression.money
		await key(KEY_E)
		check(level.shops.is_open() and level.paused, "shop remains accessible after recovery with actual remaining wallet")
		await key(KEY_ESCAPE)
		check(not level.shops.is_open() and not level.paused and int(level.progression.money) == cash,
			"browsing after fees neither manufactures nor loses cash")
	var exited := await _walk_to(point(selected.entry_world))
	exited = (await _walk_to(point(selected.approach_start))) and exited
	check(exited, "real input walks back out through doorway")

func _input_shot(target: Vector3) -> bool:
	await key(KEY_2)
	if level.combat.ammo == 0 and level.combat.reserve > 0:
		await key(KEY_R)
		for step in 240:
			await frames(1)
			if level.combat.reloading <= 0.0:
				break
	await frames(35)
	var before: int = level.combat.shots_fired
	var eye := player.global_position + Vector3.UP * 1.55
	level.capture_view(eye, target)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(2)
	var shot_evidence := {"mouse_mode": Input.mouse_mode, "weapon": level.combat.weapon,
		"ammo_before": level.combat.ammo, "shots_before": before, "accepts_input": level.combat.accepts_player_input(),
		"player_enabled": player.enabled, "paused": level.paused, "reloading": level.combat.reloading,
		"health": level.combat.health, "downed": level.combat.downed,
		"eye": [eye.x, eye.y, eye.z], "target": [target.x, target.y, target.z]}
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or level.get("offscreen_validation") != true or not _window_off_desktop():
		level.release_capture_view()
		shot_evidence["refusal"] = "safe offscreen input route unavailable"
		result_details["last_input_shot"] = shot_evidence
		check(false, "actual LMB phase requires visible mouse and explicit offscreen route; no direct combat-call substitute")
		return false
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	level.release_capture_view()
	await frames(3)
	shot_evidence["ammo_after"] = level.combat.ammo
	shot_evidence["shots_after"] = level.combat.shots_fired
	result_details["last_input_shot"] = shot_evidence
	print("[priorities_session] INPUT_SHOT " + JSON.stringify(shot_evidence))
	return level.combat.shots_fired == before + 1

func stopped_traffic_input() -> void:
	var selected: Node3D
	for candidate in level.traffic.vehicles:
		if candidate.is_police or absf(float(candidate.speed)) > .1 or candidate.disabled \
			or candidate.player_controlled or not str(candidate.external_owner).is_empty():
			continue
		var size: Vector3 = level.driving._car_size(candidate)
		for side in [-1.0, 1.0]:
			var spot: Dictionary = level.driving._exit_spot(candidate, float(side) * (size.x * .5 + .65), .25, true)
			if spot.is_empty():
				continue
			_set_scenario_position(spot.position)
			await frames(8)
			if str(level.driving.get_status().candidate_id) != str(candidate.vehicle_id):
				continue
			await key(KEY_F)
			if level.driving.active and level.driving.vehicle == candidate:
				selected = candidate
				break
		if selected != null:
			break
	check(selected != null, "real F input takes an actual stopped civilian AI traffic car")
	if selected == null:
		return
	check(selected.player_controlled and str(selected.reservation_id).is_empty()
		and selected in level.traffic.vehicles and selected not in level.traffic.player_fleet,
		"stopped traffic claim transfers sole authority without changing fleet ownership")
	await held_key(KEY_W, true)
	await frames(20)
	await held_key(KEY_W, false)
	await held_key(KEY_SPACE, true)
	for step in 180:
		await frames(1)
		if absf(float(selected.speed)) <= .1:
			break
	await held_key(KEY_SPACE, false)
	await key(KEY_F)
	check(not level.driving.active and selected.player_released and not selected.player_controlled,
		"actual Space/F safely relinquishes traffic car and leaves it parked")
	_assert_population_and_authority()

func _police_witness_position(radius := 18.0) -> Node3D:
	for actor in level.law._police():
		if not str(actor.actor_id).begins_with("patrol_officer_") or actor.get_meta("city_dead", false):
			continue
		if not await stand_near(actor.global_position, radius):
			continue
		if level.law._clear_sight(level.get_world_3d().direct_space_state,
			actor.global_position + Vector3.UP * level.law.EYE_HEIGHT,
			player.global_position + Vector3.UP * level.law.CHEST_HEIGHT, actor.get_rid()):
			return actor
	return null

func _assert_population_and_authority() -> void:
	check(int(level.npcs.crowd.get_status().total) == 1200 and int(level.residents.get_status().count) == 40
		and level.traffic.vehicles.size() == 90, "population and traffic counts remain intact")
	var ids: Dictionary = {}
	var unique := true
	var controlled := 0
	var external := 0
	for car in level.traffic.vehicles + level.traffic.player_fleet:
		if not is_instance_valid(car):
			unique = false
			continue
		var id := str(car.vehicle_id)
		unique = unique and not ids.has(id)
		ids[id] = true
		controlled += int(car.player_controlled)
		var owner := str(car.get("external_owner"))
		if not owner.is_empty():
			external += 1
			unique = unique and not car.player_controlled and car not in level.traffic.player_fleet \
				and bool(car.is_police) and owner.begins_with("law_cruiser_")
	check(unique and controlled <= 1 and external <= 2, "unique live vehicle IDs with exclusive player/police authority and at most two cruisers")
	check(level.traffic.player_fleet.size() <= 9, "remembered vehicle fleet stays bounded, including starter")
	var durable_vehicles: Dictionary = level.driving.snapshot_state()
	check(durable_vehicles.vehicles.size() <= 8 and level.driving.validate_state(durable_vehicles).is_empty(),
		"durable remembered registry is valid and bounded at eight including starter")
	var cruiser_status: Dictionary = level.law.get_status().get("cruisers", {})
	if not cruiser_status.is_empty():
		check(int(cruiser_status.max) == 2 and int(cruiser_status.claimed) <= 2,
			"published cruiser status retains two-unit cap")
		var crew_unique := true
		var crew_ids: Dictionary = {}
		for crew in cruiser_status.get("crew", []):
			var id := str(crew.id)
			crew_unique = crew_unique and not crew_ids.has(id) and level.npcs.actors.has(id)
			crew_ids[id] = true
			var actor: Node3D = level.npcs.actors.get(id)
			if actor != null and not actor.enabled and not actor.get_meta("city_dead", false):
				crew_unique = crew_unique and not actor.visible and actor.collision_layer == 0
		check(crew_unique and crew_ids.size() == 2, "both cruiser crew IDs are registered once and seated actors have no second visible/collision body")

func _choose_hook(kind: String, field := "", value := "") -> bool:
	for step in 12:
		if not level._dialogue.state.active:
			return false
		var choices: Array = level._dialogue.state.choices()
		if choices.is_empty():
			await key(KEY_ENTER)
			continue
		for index in choices.size():
			var hook: Dictionary = choices[index].get("hook", {})
			if str(hook.get("kind", "")) != kind or (not field.is_empty() and str(hook.get(field, "")) != value):
				continue
			var buttons: Array = level._dialogue.replies.get_children()
			if index >= buttons.size() or not buttons[index] is Button:
				return false
			await click(buttons[index])
			await frames(2)
			return true
		return false
	return false

func _wait_checkpoint() -> bool:
	level.combat.cancel_player_actions()
	await key(KEY_1)
	for step in 900:
		if provider.can_checkpoint():
			return true
		await frames(1)
	return false

func durable_reload() -> void:
	_set_scenario_position(startup_position)
	check(await _wait_checkpoint(), "normal world reaches stable checkpoint after story/recovery")
	if not provider.can_checkpoint():
		return
	level.pause_exploring()
	expected_durable = {"progression": canonical(level.progression.snapshot_state()),
		"missions": canonical(level.missions.snapshot_state()), "vehicles": canonical(level.driving.snapshot_state()),
		"inventory": canonical(level.combat.equipment_snapshot())}
	var snapshot: Dictionary = provider.snapshot_state()
	check(not snapshot.is_empty() and int(snapshot.get("version", 0)) == 4
		and canonical(snapshot.get("vehicles", {})) == expected_durable.vehicles
		and provider.validate_snapshot(snapshot).is_empty(), "schema4 includes exact durable vehicle section and validates in full world")
	if snapshot.is_empty():
		return
	check(provider.write_snapshot(snapshot) == OK, "atomic test checkpoint written")
	var old_scene_id := level.get_instance_id()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	for step in 1800:
		await frames(1)
		level = get_tree().current_scene as Node3D
		if level != null and level.get_instance_id() != old_scene_id and level.get("level_ready") == true:
			break
	check(level != null and level.get_instance_id() != old_scene_id and level.get("level_ready") == true,
		"old complete scene destroyed and new exported world boots")
	if level == null or level.get("level_ready") != true:
		return
	player = level.player
	check(not level.world_save.enabled, "new scene still cannot access production player slot")
	provider = Save.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	level.world_save = provider
	var restored: Dictionary = provider.load_state()
	check(restored.get("ok", false), "fresh scene loads the isolated durable checkpoint")
	if not restored.get("ok", false):
		return
	check(int(restored.get("version", 0)) == 4 and int(restored.get("vehicle_fallbacks", -1)) == 0,
		"unchanged full-world geometry restores schema4 vehicles without fallback")
	for section in ["progression", "missions", "inventory"]:
		var actual: Variant = level.combat.equipment_snapshot() if section == "inventory" else level.get(section).snapshot_state()
		check(canonical(actual) == expected_durable[section], "fresh scene preserves exact " + section)
	check(canonical(level.driving.snapshot_state()) == expected_durable.vehicles, "fresh scene preserves exact durable vehicle records")
	_assert_population_and_authority()
	_assert_parked_hidden()
	var first_count: int = level.traffic.player_fleet.size()
	var second: Dictionary = provider.load_state()
	await frames(3)
	check(second.get("ok", false) and level.traffic.player_fleet.size() == first_count,
		"repeated load neither duplicates live remembered vehicles nor pays rewards")
	check(canonical(level.progression.snapshot_state()) == expected_durable.progression,
		"wallet, story choices and relationships unchanged by repeated restore")
	_assert_population_and_authority()
	level.resume_exploring()

func parked_drive() -> void:
	var parked: Node3D = level.traffic.parked
	check(parked != null and not parked.records.is_empty() and level.driving.has_method("snapshot_state")
		and level.driving.has_signal("vehicle_collision"), "parked promotion/persistence/collision contract available")
	if parked == null or parked.records.is_empty() or not level.driving.has_method("snapshot_state") or not level.driving.has_signal("vehicle_collision"):
		return
	level.driving.connect("vehicle_collision", func(contact: Dictionary): collision_events.append(contact.duplicate()))
	# Select an existing parked car facing a real solid obstruction 4–14m away.
	# This makes the contact deterministic without manufacturing a wall/NPC,
	# relocating the car or bypassing swept world collision.
	var candidates := 0
	for index in parked.records.size():
		if candidates >= 100:
			break
		var record: Dictionary = parked.records[index]
		var pose: Transform3D = record.pose
		var nose := pose.origin + pose.basis.z * 2.5 + Vector3.UP * .8
		var survey_spot := Facilities.standing_at(level.get_world_3d().direct_space_state,
			pose.origin + pose.basis.x * 2.0, [player.get_rid()])
		if survey_spot.is_empty():
			continue
		_set_scenario_position(survey_spot.position)
		await frames(2)
		var ray := PhysicsRayQueryParameters3D.create(nose, nose + pose.basis.z * 14.0, 2 | 16,
			[player.get_rid(), record.body.get_rid()])
		var obstacle: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
		if obstacle.is_empty() or nose.distance_to(obstacle.position) < 4.0 or not obstacle.collider is StaticBody3D:
			continue
		candidates += 1
		for side in [-1.0, 1.0]:
			var desired: Vector3 = pose.origin + pose.basis.x * float(side) * 1.7 + pose.basis.z * .25
			var door := Facilities.standing_at(level.get_world_3d().direct_space_state, desired, [player.get_rid()])
			if door.is_empty():
				continue
			_set_scenario_position(door.position)
			await frames(8)
			await key(KEY_F)
			if not level.driving.active:
				continue
			var car: Node3D = level.driving.vehicle
			if car == level.driving.starter or car.global_position.distance_to(pose.origin) > .5:
				await key(KEY_F)
				continue
			remembered_car = car
			remembered_record = index
			remembered_source = str(record.source_id)
			check(str(car.vehicle_id) == remembered_source and str(record.promoted) == remembered_source,
				"promoted source, registry and live vehicle share one stable identity")
			check(str(car.prototype_kind) == str(record.kind), "F promotion preserves exact parked prototype")
			var expected_tires: Array[int] = []
			for tire in record.flat_tires:
				expected_tires.append([0, 2, 1, 3][int(tire)])
			expected_tires.sort()
			var actual_tires: Array = car.flat_tires.duplicate()
			actual_tires.sort()
			check(Color(str(car.paint_color)).is_equal_approx(SessionCarModels.paint_color(int(record.paint)))
				and canonical(actual_tires) == canonical(expected_tires) and is_equal_approx(float(car.health), float(record.health)),
				"F promotion preserves paint, health and tire state with correct wheel-order conversion")
			break
		if is_instance_valid(remembered_car):
			break
	check(is_instance_valid(remembered_car), "real F promotes an ordinary parked car beside a checked door")
	if not is_instance_valid(remembered_car):
		return
	_assert_parked_hidden()
	var original_pose: Transform3D = remembered_car.global_transform
	var offenses_before_impact: int = level.law.offenses_received
	await held_key(KEY_W, true)
	for step in 240:
		await frames(1)
		if not collision_events.is_empty() or not level.driving.active:
			break
	if level.driving.active and not collision_events.is_empty():
		await frames(45) # Keep pushing briefly: one contact episode must not flood crimes.
	await held_key(KEY_W, false)
	await held_key(KEY_SPACE, true)
	for step in 180:
		await frames(1)
		if absf(float(remembered_car.speed)) <= .1:
			break
	await held_key(KEY_SPACE, false)
	check(remembered_car.global_position.distance_to(original_pose.origin) > .5, "real W accelerates promoted car in world")
	check(not collision_events.is_empty() and collision_events.size() <= 8, "actual swept impact emits bounded consequential contacts")
	var event_ids: Dictionary = {}
	var contacts_valid := true
	var consequential_vehicle_contact := false
	for contact in collision_events:
		contacts_valid = contacts_valid and str(contact.get("driver", "")) == "player" \
			and str(contact.get("vehicle_id", "")) == remembered_source \
			and float(contact.get("relative_speed", 0.0)) >= 1.0 and contact.has("id") and not event_ids.has(contact.get("id"))
		event_ids[contact.get("id")] = true
		consequential_vehicle_contact = consequential_vehicle_contact or (str(contact.get("kind", "")) == "vehicle"
			and float(contact.get("other_damage", 0.0)) > 0.0 and float(contact.get("relative_speed", 0.0)) >= 4.0)
	check(contacts_valid, "collision bridge receives unique IDs, player authority and real closing speed")
	if consequential_vehicle_contact:
		check(level.law.offenses_received > offenses_before_impact, "consequential vehicle impact reaches actual law perception bridge")
	check(level.driving.active and not provider.can_checkpoint(), "occupied promoted car continues to block checkpoints")
	var occupied_inventory: Variant = canonical(level.combat.equipment_snapshot())
	var refused_load: Dictionary = provider.load_state()
	check(not refused_load.get("ok", true) and not refused_load.get("partial", true)
		and level.driving.active and level.driving.vehicle == remembered_car
		and canonical(level.combat.equipment_snapshot()) == occupied_inventory,
		"checkpoint load while occupied refuses atomically without detaching or mutating inventory")
	await key(KEY_F)
	check(not level.driving.active and not remembered_car.player_controlled and player.seated_vehicle == null,
		"real brake/F returns player authority through a clear door")
	if level.driving.active:
		return
	var before_damage: Variant = canonical(level.driving.snapshot_state())
	var health_before: float = remembered_car.health
	var shot := await _input_shot(remembered_car.global_position + Vector3.UP * .65)
	check(shot and float(remembered_car.health) < health_before and canonical(level.driving.snapshot_state()) != before_damage,
		"actual pistol input hits promoted body and changes durable damage state")
	# Re-entry must reuse exactly the same instance and source ownership.
	var size: Vector3 = level.driving._car_size(remembered_car)
	var door: Dictionary = {}
	for side in [-1.0, 1.0]:
		door = level.driving._exit_spot(remembered_car, side * (size.x * .5 + .65), .25, true)
		if not door.is_empty():
			break
	check(not door.is_empty(), "damaged promoted car retains a clear door")
	if not door.is_empty():
		_set_scenario_position(door.position)
		await frames(8)
		await key(KEY_F)
		check(level.driving.active and level.driving.vehicle == remembered_car, "re-entry uses the original promoted live body")
		await key(KEY_F)
	_assert_parked_hidden()
	_assert_population_and_authority()

func _assert_parked_hidden() -> void:
	if remembered_record < 0:
		check(false, "parked source record selected")
		return
	var parked: Node3D = level.traffic.parked
	remembered_record = parked.source_index(remembered_source)
	check(remembered_record >= 0, "stable parked source survives scene reload")
	if remembered_record < 0:
		return
	var record: Dictionary = parked.records[remembered_record]
	var pose: Transform3D = record.pose
	parked.set_presence(pose.origin)
	var visible := false
	for batch in parked._batches.values():
		for index in maxi(0, batch.multimesh.visible_instance_count):
			var instance_pose: Transform3D = batch.multimesh.get_instance_transform(index)
			visible = visible or instance_pose.is_equal_approx(pose)
	if record.has("damage_model") and is_instance_valid(record.damage_model):
		visible = visible or record.damage_model.visible
	check(str(record.promoted) == remembered_source and record.body.collision_layer == 0 and not visible,
		"promoted original has neither active collider nor near/far batch duplicate")
	parked.set_presence(player.global_position)

func police_flow() -> void:
	var law: Node = level.law
	check(law.get("cruisers") != null, "police cruiser manager exists in actual law manager")
	if law.get("cruisers") == null:
		return
	law.reset_state()
	level.combat.recover_player()
	level.resume_exploring()
	var officer: Node3D = await _police_witness_position()
	check(officer != null, "real foot patrol has an independently clear supported witness position")
	if officer == null:
		return
	# Start before the offense: a cruiser retained near this location by an
	# earlier cycle can arrive while shots/occlusion setup are still awaiting.
	var start_positions: Dictionary = {}
	for car in level.traffic.vehicles:
		if bool(car.is_police):
			start_positions[str(car.vehicle_id)] = car.global_position
	var dispatches_before := int(law.cruisers.counters.dispatches)
	var claims_before := int(law.cruisers.counters.claims)
	var dismounts_before := int(law.cruisers.counters.dismounts)
	var offenses: int = law.offenses_received
	check(await _input_shot(player.global_position + Vector3(2, 40, 0)), "actual pistol input fires a witnessed sky shot")
	check(await _input_shot(player.global_position + Vector3(2, 40, 0)), "second actual shot reaches cruiser dispatch tier")
	await frames(20)
	check(law.offenses_received == offenses + 2 and law.wanted > 0, "root firearm events establish identified wanted status")
	check(int(law.last_scan.get("rays", 0)) <= law.MAX_WITNESS_CHECKS,
		"world perception retains its configured ray budget")
	var hidden: Vector3 = await _unseen_location()
	check(hidden.is_finite(), "full-world geometry supplies a verified location occluded from every witness candidate")
	if not hidden.is_finite():
		return
	var claimed := false
	var observed_search := false
	var hidden_target_leaked := false
	var cruiser_moved := false
	var nearby_arrival := false
	var foot_response := false
	var foot_start_positions: Dictionary = {}
	var foot_evidence: Dictionary = {}
	var response_evidence: Dictionary = {}
	var wait_extension: Dictionary = {}
	var observed_frames := 0
	# Seven seconds covers ordinary dispatch. A documented queue can legitimately
	# need the production 12 s give-up bound plus its 6 s reverse recovery.
	var ordinary_frames := 420
	var maximum_frames := ceili((float(law.cruisers.BLOCK_GIVE_UP) + float(law.cruisers.REVERSE_SECONDS)
		+ float(law.cruisers.SENSE_INTERVAL)) * 60.0)
	var known: Vector3 = law.last_known_position
	for step in maximum_frames:
		await frames(1)
		observed_frames = step + 1
		var external := 0
		for car in level.traffic.vehicles:
			if str(car.get("external_owner")).is_empty():
				continue
			external += 1
			claimed = true
		for unit in law.cruisers.units.values():
			var car: Node3D = unit.car
			var id := str(car.get("vehicle_id"))
			if not start_positions.has(id) or str(car.get("external_owner")) != str(unit.owner):
				continue
			var displacement := car.global_position.distance_to(start_positions[id])
			var driven := float(unit.odometer) # Only movement under external authority.
			cruiser_moved = cruiser_moved or (displacement > .25 and driven > .25)
			var goal: Vector3 = unit.goal
			var start_gap := Vector2(start_positions[id].x - goal.x, start_positions[id].z - goal.z).length()
			var end_gap := Vector2(car.global_position.x - goal.x, car.global_position.z - goal.z).length()
			var entry: Dictionary = law.cruisers.crew[int(unit.crew)]
			if str(unit.get("response_fallback", "")) == "foot" and str(entry.state) == "foot":
				var actor: Node3D = entry.actor
				var crew_id := str(entry.id)
				if not foot_start_positions.has(crew_id):
					foot_start_positions[crew_id] = actor.global_position
				var foot_start: Vector3 = foot_start_positions[crew_id]
				var first_gap := Vector2(foot_start.x - goal.x, foot_start.z - goal.z).length()
				var current_gap := Vector2(actor.global_position.x - goal.x, actor.global_position.z - goal.z).length()
				foot_evidence[crew_id] = {"displacement": actor.global_position.distance_to(foot_start),
					"start_goal_gap": first_gap, "end_goal_gap": current_gap, "enlisted": law._responders.has(crew_id)}
				foot_response = foot_response or (actor.global_position.distance_to(foot_start) > .25
					and current_gap < first_gap - .25 and bool(actor.get("enabled")) and not bool(actor.get("dead"))
					and law._responders.has(crew_id))
			# Already close at dispatch: require a real completed crew exit at the
			# reported goal, not merely a claim, stationary car, or distant fallback.
			var arrived: bool = str(unit.mode) == "dismounted" and str(entry.state) == "foot" \
				and str(unit.hold_reason) in ["search", "engage"] \
				and start_gap <= float(law.cruisers.DISMOUNT_RANGE) and end_gap <= float(law.cruisers.DISMOUNT_RANGE) \
				and float(unit.remaining) <= float(law.cruisers.ARRIVE_DISTANCE) + .01 \
				and int(law.cruisers.counters.dismounts) > dismounts_before
			nearby_arrival = nearby_arrival or arrived
			response_evidence[id] = {"displacement": displacement, "externally_driven": driven,
				"start_goal_gap": start_gap, "end_goal_gap": end_gap, "mode": str(unit.mode),
				"remaining": float(unit.remaining), "completed_nearby_arrival": arrived,
				"obstacle": float(unit.obstacle), "obstacle_kind": str(unit.obstacle_kind),
				"obstacle_speed": float(unit.obstacle_speed), "blocked_time": float(unit.blocked_time),
				"yielding": bool(unit.yielding), "yield_time": float(unit.yield_time),
				"reverse_left": float(unit.reverse_left), "unsticks": int(unit.unstick),
				"last_blocked": str(unit.get("last_blocked", ""))}
		if external > 2:
			check(false, "more than two police-owned cruisers")
			break
		observed_search = observed_search or str(law.phase) in ["search", "cooldown"]
		if not law.seen and law.last_known_position.distance_to(hidden) < 1.0 and known.distance_to(hidden) > 10.0:
			hidden_target_leaked = true
		if observed_frames >= ordinary_frames:
			if cruiser_moved or nearby_arrival or foot_response:
				break
			if observed_frames == ordinary_frames:
				for unit in law.cruisers.units.values():
					var vehicle_wait: bool = str(unit.obstacle_kind) == "vehicle" \
						and absf(float(unit.obstacle_speed)) < .5 and float(unit.obstacle) <= float(law.cruisers.PASS_START_GAP) + 2.5 \
						and float(unit.blocked_time) > 0.0
					var yielding_wait: bool = bool(unit.yielding) and float(unit.yield_time) > 0.0
					var reversing_wait: bool = float(unit.reverse_left) > 0.0 and int(unit.unstick) > 0
					if absf(float(unit.car.speed)) < .5 and (vehicle_wait or yielding_wait or reversing_wait) \
						and int(law.cruisers.counters.dispatches) > dispatches_before \
						and int(law.cruisers.counters.claims) > claims_before:
						wait_extension[str(unit.vehicle_id)] = response_evidence.get(str(unit.vehicle_id), {}).duplicate(true)
				if wait_extension.is_empty():
					break # No actual queue/recovery evidence: keep the original deadline.
	var dispatch_delta := int(law.cruisers.counters.dispatches) - dispatches_before
	var claim_delta := int(law.cruisers.counters.claims) - claims_before
	print("[priorities_session] POLICE_RESPONSE " + JSON.stringify({"dispatches": dispatch_delta,
		"claims": claim_delta, "moved": cruiser_moved, "nearby_arrival": nearby_arrival, "cars": response_evidence,
		"active_foot_response": foot_response, "foot_evidence": foot_evidence,
		"blocked_dispatch": law.cruisers.last_blocked_dispatch,
		"observation_frames": observed_frames, "maximum_frames": maximum_frames, "wait_extension": wait_extension}))
	check(claimed and dispatch_delta > 0 and claim_delta > 0 and (cruiser_moved or nearby_arrival or foot_response),
		"new dispatch obtains authority and makes vehicle progress, nearby arrival or active foot fallback progress")
	check(observed_search and not hidden_target_leaked and not law.seen,
		"loss of actual line of sight enters bounded search without tracking hidden live position")
	_assert_population_and_authority()
	# Bring only the player back into a visible, supported arrest interaction.
	# No officer, vehicle or responder is teleported into this encounter.
	officer = await _police_witness_position(3.0)
	check(officer != null, "live patrol remains available for real surrender input")
	if officer == null:
		return
	for step in 60:
		await frames(1)
		if law.seen:
			break
	var cash: int = level.progression.money
	var fee := mini(cash, int(law.ARREST_FINES[clampi(int(law.wanted), 1, law.MAX_WANTED)]))
	var arrests: int = law.arrests
	await key(KEY_G)
	check(law.recovering, "actual G starts visible patrol surrender")
	for step in 480:
		if not law.recovering:
			break
		await frames(1)
	_assert_release("arrest", fee, cash)
	await frames(20)
	check(law.arrests == arrests + 1 and int(level.progression.money) == cash - fee,
		"arrest recovery and fee occur exactly once")
	var external_after := 0
	for car in level.traffic.vehicles:
		external_after += int(not str(car.get("external_owner")).is_empty())
	check(external_after == 0, "arrest releases every police vehicle authority claim")
	_assert_population_and_authority()

func story_flow() -> void:
	var branch := option("--session-branch", "report")
	check(branch in ["report", "protect", "negotiate", "intimidate"], "requested authored branch is valid")
	var before: Dictionary = level.progression.snapshot_state()
	check(int(before.get("version", 0)) == 2 and before.has("relationships") and before.has("choices")
		and before.has("errands"), "published progression v2 story/relationship/income payload available")
	if failures > 0:
		return
	var parts := ["petals_word", "petals_" + branch, "petals_end_" + branch]
	var outcomes: Array[Dictionary] = []
	for part in parts:
		check(await _accept_narrative_offer(str(part), "story_start"), "actual contact dialogue accepts " + str(part))
		if str(level.missions.active_id) != str(part):
			return
		var description: Dictionary = level.missions.get_status()
		outcomes.append({"id": part, "objective": str(description.objective)})
		var stepped := await _complete_narrative_case(str(part), branch)
		var marked: bool = str(part) in level.missions.snapshot_state().completed_ids
		check(stepped and marked, "real E and GUI choices complete " + str(part))
		if not marked:
			return
		if str(part) == "petals_word":
			check(str(level.progression.snapshot_state().choices.get("petals_call", "")) == branch,
				"first choice durably selects the later branch-specific opportunity")
	var after: Dictionary = level.progression.snapshot_state()
	check(str(after.choices.get("petals_call", "")) == branch
		and str(after.choices.get("petals_final", "")) == branch + "_amends",
		"both authored decisions preserve selected branch and final ending")
	check(after.relationships != before.relationships and after.reputation != before.reputation,
		"chain changes durable relationships and alignment")
	check(int(after.money) - int(before.money) == int(STORY_AMENDS_NET_CASH[branch]),
		"authored %s amends path has exact net cash change $%d" % [branch, int(STORY_AMENDS_NET_CASH[branch])])
	var completed: Array = level.missions.snapshot_state().completed_ids
	var exclusive := true
	for other in ["report", "protect", "negotiate", "intimidate"]:
		if other != branch:
			exclusive = exclusive and ("petals_" + other not in completed) and ("petals_end_" + other not in completed)
	check(exclusive, "unselected story branches are not silently completed or rewarded")
	result_details["story"] = {"branch": branch, "parts": outcomes, "choices": after.choices,
		"relationships_before": before.relationships, "relationships_after": after.relationships}
	await lawful_job_cycle()

func _accept_narrative_offer(id: String, kind: String) -> bool:
	if str(level.missions.active_id) == id:
		return true
	if not str(level.missions.active_id).is_empty():
		return false
	# Known authored contacts first, then existing registries for a death-aware
	# replacement. Only the player is arranged; no NPC is enabled/relocated.
	var contacts: Array = ["daily_ines_morales", "ambient_mailman", "officer", "lookout", "organizer",
		"caretaker", "gardener", "ambient_neighbor", "ambient_granny", "daily_aisha_bell"]
	for actor_id in level.npcs.actors.keys() + level.residents.actors.keys():
		if actor_id not in contacts:
			contacts.append(actor_id)
	for actor_id in contacts:
		var at: Vector3 = level.npcs.actor_position(str(actor_id))
		if not at.is_finite():
			continue
		for angle in [0, 4, 8, 12]:
			if not await stand_near(at, 1.8, true, int(angle)):
				continue
			var preview: Dictionary = level.missions.conversation_preview()
			var offered := false
			for node in preview.get("nodes", {}).values():
				for choice in node.get("choices", []):
					var hook: Dictionary = choice.get("hook", {})
					offered = offered or (str(hook.get("kind", "")) == kind and str(hook.get("id", "")) == id)
			if not offered:
				continue
			await key(KEY_E)
			var accepted := await _choose_hook(kind, "id", id)
			if level._dialogue.state.active:
				await key(KEY_ESCAPE)
			return accepted and str(level.missions.active_id) == id
	return false

func _complete_narrative_case(id: String, branch := "") -> bool:
	for step in 16:
		# Part 1's committed final choice immediately starts part 2. Completion
		# is established by its durable ledger, regardless of the new active ID.
		if id in level.missions.snapshot_state().completed_ids:
			return true
		if str(level.missions.active_id).is_empty():
			return true
		if str(level.missions.active_id) != id:
			return false
		var status: Dictionary = level.missions.get_status()
		var target: Vector3 = status.target_position
		if not target.is_finite() or not await stand_near(target, 1.8, true):
			return false
		var old_stage: int = level.missions.stage
		await key(KEY_E)
		if not level._dialogue.state.active:
			return false
		var selected := false
		for line_index in 12:
			var choices: Array = level._dialogue.state.choices()
			if choices.is_empty():
				await key(KEY_ENTER)
				if not level._dialogue.state.active:
					break
				continue
			for choice_index in choices.size():
				var hook: Dictionary = choices[choice_index].get("hook", {})
				if str(hook.get("kind", "")) != "case_step" or str(hook.get("id", "")) != id \
					or int(hook.get("stage", -1)) != old_stage:
					continue
				if hook.has("choice"):
					var option_value := str(hook.choice)
					if id == "petals_word" and option_value != branch:
						continue
					if id.begins_with("petals_end_") and option_value not in [branch + "_amends", "amends"]:
						continue
				var buttons: Array = level._dialogue.replies.get_children()
				if choice_index >= buttons.size() or not buttons[choice_index] is Button:
					break
				await click(buttons[choice_index])
				selected = true
				break
			break
		if level._dialogue.state.active:
			await key(KEY_ESCAPE)
		if not selected or (str(level.missions.active_id) == id and int(level.missions.stage) == old_stage):
			return false
	return false

func lawful_job_cycle() -> bool:
	var before: Dictionary = level.progression.snapshot_state()
	var accepted := await _accept_narrative_offer("errand_delivery", "errand_start")
	check(accepted, "actual contact dialogue accepts always-available lawful delivery income")
	if not accepted:
		return false
	check(await _complete_narrative_case("errand_delivery"), "actual input completes lawful delivery steps")
	var after: Dictionary = level.progression.snapshot_state()
	var paid := int(after.errands.runs) == int(before.errands.runs) + 1 \
		and int(after.errands.earned) > int(before.errands.earned) and int(after.money) > int(before.money)
	check(paid and "errand_delivery" not in level.missions.snapshot_state().completed_ids,
		"lawful job pays exactly one durable run and remains repeatable")
	check(int(after.errands.ready_at) > int(level.world_time.elapsed_seconds), "job records a durable future cooldown")
	return paid

func replenish_supplies() -> bool:
	var inventory: Dictionary = level.combat.equipment_snapshot()
	if int(inventory.weapons.pistol.ammo) + int(inventory.weapons.pistol.reserve) >= 6:
		return true
	var ammunition: Dictionary = _stock_item("ammo_pistol")
	if ammunition.is_empty():
		check(false, "pistol ammunition remains in actual shop catalog")
		return false
	if int(level.progression.money) < int(ammunition.price):
		var economy: Dictionary = level.progression.snapshot_state()
		if float(economy.errands.ready_at) > float(level.world_time.elapsed_seconds):
			return false # Normal cycles keep advancing time; never bypass cooldown.
		if not await lawful_job_cycle():
			return false
	check(int(level.progression.money) >= int(ammunition.price), "one lawful income run can fund standard ammunition")
	if int(level.progression.money) < int(ammunition.price):
		return false
	await shop_visit()
	return failures == 0
