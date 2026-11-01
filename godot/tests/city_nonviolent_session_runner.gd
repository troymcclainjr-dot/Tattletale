extends "res://tests/city_priorities_session_fixture.gd"
## Full population, real input route. Teleports arrange scenarios only; synthetic
## compatibility/API checks are explicitly labeled and never replace input checks.
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
var _gallery_directory := ""

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	if OS.get_cmdline_user_args().has("--basketball-pose-only"):
		result_details["scope"] = "Real-world basketball input and held/charging pose review only."
		await _basketball_input()
		_finish()
		return
	begin_phase("nonviolent-startup")
	for service in ["bicycle", "bicycle_reactions", "basketball", "police_assistance"]:
		check(level.get(service) != null, "full world starts service " + service)
	check(not PlayMode.player_combat_enabled() and not PlayMode.player_driving_enabled() and not PlayMode.alignment_enabled(), "nonviolent feature policy active")
	if failures > 0:
		_finish()
		return
	await _compatibility_and_attack_gates()
	await _bicycle_input()
	if level.bicycle.active:
		# Failed ordinary dismount is a failure, not masked by synthetic recovery.
		_finish()
		return
	await _basketball_input()
	await _phone_and_modal_input()
	await _custody_checkpoint_roundtrip()
	begin_phase("stable-view")
	_set_scenario_position(startup_position)
	await frames(30)
	_sample("bounded-nonviolent-view", true)
	result_details["performance_scope"] = "Single settled view diagnostic; not a benchmark or soak. Concurrent rendering/video workloads may affect FPS."
	check(int(level.npcs.crowd.get_status().total) == 1200 and int(level.residents.get_status().count) == 40 and level.traffic.vehicles.size() == 90, "population remains 1200 / 40 / 90 after interaction phases")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "desktop cursor remains visible and validation stays offscreen")
	_cleanup_gallery()
	_finish()

func _mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func _compatibility_and_attack_gates() -> void:
	begin_phase("synthetic-legacy-compatibility")
	var original: Dictionary = level.progression.snapshot_state()
	var legacy := original.duplicate(true)
	legacy.money = 350
	for track in legacy.reputation:
		legacy.reputation[track] = int(level.progression.config.tracks[track].max)
	check(level.progression.restore_state(legacy), "synthetic legacy progression with nonneutral alignment restores")
	var stored_tracks: Dictionary = level.progression.snapshot_state().reputation
	check(stored_tracks == legacy.reputation, "legacy stored alignment values are preserved")
	check(level.progression.credit(25, "fixture_income") == 25 and level.progression.debit(10, "fixture_fee") == 10 and level.progression.money == 365, "synthetic currency credit/debit still works")
	level.progression.on_offense("assault", player.global_position, "fixture")
	check(level.progression.snapshot_state().reputation == stored_tracks and level.progression.money == 365, "disabled alignment offense cannot change legacy tracks or wallet")
	var inventory: Dictionary = level.combat.equipment_snapshot()
	var armed := inventory.duplicate(true)
	armed.weapons.pistol = {"owned": true, "ammo": 7, "reserve": 31}
	armed.equipped = "pistol"
	check(level.combat.restore_equipment(armed), "synthetic legacy armed inventory restores")
	var retained: Dictionary = level.combat.equipment_snapshot()
	check(retained.equipped == "fists" and retained.weapons.pistol.ammo == 7 and retained.weapons.pistol.reserve == 31 and retained.weapons.pistol.owned, "legacy weapon is holstered while ownership and ammunition survive")
	begin_phase("ordinary-attack-input")
	var shots_before: int = level.combat.shots_fired
	var punches_before: int = level.combat.punches_thrown
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_R]:
		await key(code)
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		await _mouse(button, true)
		await frames(8)
		await _mouse(button, false)
	await frames(20)
	check(level.combat.shots_fired == shots_before and level.combat.punches_thrown == punches_before and level.combat.weapon == "fists" and not level.combat.aiming and level.combat.reloading <= 0.0, "ordinary equip/reload/LMB/RMB input never equips or attacks")
	check(not level.combat.request_attack() and not level.combat.request_reload(), "synthetic attack/reload API probes are also blocked")
	begin_phase("closed-gun-shops-and-cars")
	var gun_count := 0
	for entry in level.shops.definitions:
		if str(entry.kind) == "gun":
			gun_count += 1
			check(not level.shops.open_shop(str(entry.id)), "closed gun shop refuses open API: " + str(entry.id))
			check(bool(level.shops.models[str(entry.id)].get_meta("closed", false)), "real gun shop model carries closed shutter state: " + str(entry.id))
			var advertised := false
			for poi in level.shops.get_map_pois():
				advertised = advertised or str(poi.get("id", "")) == str(entry.id)
			check(not advertised, "closed gun shop omitted from shop map advertisements")
	check(gun_count > 0 and level.progression.catalog("gun").is_empty(), "authored gun shops remain present but advertise no purchasable stock")
	var money_before: int = level.progression.money
	for id in level.progression.config.items:
		if str(level.progression.config.items[id].kind) in ["weapon", "ammo"]:
			check(not bool(level.progression.purchase(str(id)).ok), "synthetic weapon/ammo purchase blocked: " + str(id))
	check(level.progression.money == money_before, "blocked shop purchases do not debit wallet")
	var car: Node3D = level.traffic.vehicles[0]
	for candidate in level.traffic.vehicles:
		if candidate.global_position.distance_to(level.bicycle.global_position) > 12.0:
			car = candidate
			break
	check(not level.driving.enter_vehicle(car), "synthetic direct legacy car boarding API blocked")
	var arranged := await stand_near(car.global_position, 2.4)
	check(arranged, "arrange player beside a real traffic car for ordinary F input")
	if arranged:
		await key(KEY_F)
		check(not level.driving.active and not player.is_seated(), "ordinary F beside car cannot enter legacy driving")
	check(level.combat.restore_equipment(inventory) and level.progression.restore_state(original), "synthetic compatibility probes restore original durable state")

func _bicycle_input() -> void:
	begin_phase("ordinary-bicycle-input")
	var bike: CharacterBody3D = level.bicycle
	check(bike.spawned, "bicycle has a clear real-world spawn")
	if not bike.spawned:
		return
	var arranged := await stand_near(bike.global_position, 1.5)
	check(arranged, "arrange player beside bicycle on real safe ground")
	if not arranged:
		return
	if OS.get_cmdline_user_args().has("--capture-nonviolent") and DisplayServer.get_name() != "headless":
		level.capture_view(bike.global_position + Vector3(4, 2.0, 4), bike.global_position + Vector3.UP * .8)
		await _capture_review("bicycle-world")
		level.release_capture_view()
	await key(KEY_F)
	check(bike.active and player.is_seated(), "ordinary F mounts bicycle")
	if not bike.active:
		return
	await key(KEY_P)
	check(not player.phone.active and not player.phone.open(), "ordinary P and direct phone open both reject seated rider")
	var before := bike.global_position
	player.camera_yaw = bike.yaw
	await held_key(KEY_W, true)
	await frames(40)
	check(not provider.can_checkpoint() and str(provider.checkpoint_blocker()).contains("bicycle"), "checkpoint refuses a moving bicycle rider")
	await held_key(KEY_W, false)
	var moved := flat_distance(before, bike.global_position)
	check(moved > .05 and bike.input_override.is_empty(), "ordinary W pedals bicycle through normal physics without control override")
	await held_key(KEY_S, true)
	for step in 40:
		await frames(1)
		if absf(bike.speed) <= bike.EXIT_SPEED:
			break
	await held_key(KEY_S, false)
	check(absf(bike.speed) <= bike.EXIT_SPEED, "ordinary S brakes below dismount speed")
	await key(KEY_F)
	check(not bike.active and not player.is_seated(), "ordinary F dismounts onto clear ground")
	if not bike.active:
		await frames(12)
		check(provider.can_checkpoint(), "checkpoint becomes safe again after dismount")

func _basketball_input() -> void:
	begin_phase("ordinary-basketball-input")
	var balls: Node3D = level.basketball
	check(not balls.balls.is_empty(), "real court records supply basketballs")
	if balls.balls.is_empty():
		return
	var arranged := await stand_near(balls.balls[0].home, 1.2)
	check(arranged, "arrange player beside a real court ball")
	if not arranged:
		return
	await key(KEY_E)
	check(bool(balls.get_status().held), "ordinary E picks up basketball")
	if not bool(balls.get_status().held):
		return
	await frames(3)
	check(player.court_activity == balls and player.puppet.arms[0].rotation.x < -0.7,
		"held basketball applies carrying arm pose through normal player physics")
	var held_body: Node3D = balls.balls[int(balls._held)].body
	check(held_body.global_position.distance_to(player.puppet.hand_pos(0)) < 0.30,
		"held basketball stays attached to the carrying hand")
	var count: int = balls.shots
	await _mouse(MOUSE_BUTTON_LEFT, true)
	await frames(18)
	check(bool(balls.get_status().charging) and float(balls.get_status().charge) > 0.0, "ordinary held LMB charges shot")
	check(player.puppet.arms[0].rotation.x < -1.05 and player.puppet.arms[1].rotation.x < -0.65,
		"charging shot raises throwing and supporting arms")
	check(held_body.global_position.distance_to(player.puppet.hand_pos(0)) < 0.30,
		"charging basketball remains supported by the throwing hand")
	# Capture before map interruption or release. After release the arms return
	# to idle and the airborne ball is no longer a held-pose review.
	await _capture_review("basketball-court")
	await key(KEY_M)
	check(level._map_overlay.visible and not bool(balls.get_status().charging), "map interrupts held shot charge")
	await _mouse(MOUSE_BUTTON_LEFT, false)
	check(balls.shots == count, "mouse release over map does not shoot basketball")
	await key(KEY_M)
	await _mouse(MOUSE_BUTTON_LEFT, true)
	await frames(18)
	await _mouse(MOUSE_BUTTON_LEFT, false)
	check(balls.shots == count + 1 and not bool(balls.get_status().held), "ordinary LMB release throws exactly one basketball")
	check(int(balls.get_status().active) <= int(balls.get_status().max_active), "basketball simulation remains bounded")

func _phone_and_modal_input() -> void:
	begin_phase("ordinary-phone-and-gui-input")
	var phone: Node3D = player.phone
	_gallery_directory = "user://phone_gallery_test_session_%s" % run_id
	phone.storage_directory = _gallery_directory
	await key(KEY_P)
	check(phone.active and phone.page == "home", "ordinary P opens phone home")
	await _capture_review("phone-home")
	var contacts: Button = _phone_button("Contacts")
	check(contacts != null, "Contacts has a real GUI button")
	if contacts != null:
		await click(contacts)
		check(phone.page == "contacts", "GUI mouse click routes through level into phone Contacts")
	for spec in [[KEY_1, "contacts"], [KEY_2, "camera"], [KEY_3, "photos"], [KEY_4, "cases"], [KEY_5, "police"]]:
		await key(int(spec[0]))
		check(phone.page == str(spec[1]), "ordinary app shortcut opens " + str(spec[1]))
	check(not phone.police_requested.get_connections().is_empty(), "phone police signal connected in full world")
	var previous_call: int = phone._last_police_call
	await key(KEY_ENTER)
	check(phone._last_police_call > previous_call and phone.get_status().report_status != "Calling neighborhood officers…", "ordinary police call receives dedicated service response")
	await key(KEY_2)
	if DisplayServer.get_name() != "headless":
		var before: int = phone.photos_taken
		await key(KEY_ENTER)
		for step in 180:
			if not phone.capturing:
				break
			await frames(1)
		check(phone.photos_taken == before + 1 and phone.last_error.is_empty(), "rendered ordinary camera input saves a real full-world photo internally")
		await key(KEY_3)
		check(phone.gallery.entries.size() > 0, "phone gallery contains rendered world photo")
		await _capture_review("phone-gallery")
	else:
		result_details["rendered_gallery"] = "not exercised on headless backend"
	var at := player.global_position
	await held_key(KEY_W, true)
	await frames(8)
	await held_key(KEY_W, false)
	check(flat_distance(at, player.global_position) < .02, "held movement cannot leak through phone")
	await key(KEY_P)
	check(not phone.active, "ordinary P puts phone away")
	await key(KEY_ESCAPE)
	check(level.paused, "ordinary Escape opens pause menu")
	at = player.global_position
	await held_key(KEY_W, true)
	await _mouse(MOUSE_BUTTON_LEFT, true)
	await _mouse(MOUSE_BUTTON_LEFT, false)
	await key(KEY_P)
	await frames(8)
	await held_key(KEY_W, false)
	check(level.paused and not phone.active and flat_distance(at, player.global_position) < .02, "pause owns movement and phone input")
	await key(KEY_ESCAPE)
	check(not level.paused, "ordinary Escape resumes exploration")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "phone apps and camera never capture validation cursor")

func _phone_button(text: String) -> Button:
	for child in player.phone._content.get_children():
		if child is Button and child.text == text:
			return child
	return null

func _custody_checkpoint_roundtrip() -> void:
	begin_phase("synthetic-custody-real-checkpoint-roundtrip")
	# Earlier phone input can leave a real response in progress. Clear only its
	# transient response via the production reset API before touching checkpoints.
	var assistance: Node = level.police_assistance
	result_details["custody_before_reset"] = _checkpoint_diagnostics()
	assistance.reset_state()
	result_details["custody_after_assistance_reset"] = _checkpoint_diagnostics()
	# Assistance cancellation sends cars home normally; their claims still make
	# law busy while departing. This synthetic persistence setup also invokes the
	# existing fixture/debug law reset, which releases those transport claims now.
	level.law.reset_state()
	_set_scenario_position(startup_position)
	for step in 180:
		await frames(1)
		if int(level.residents.get_status().pending_routes) == 0 and provider.can_checkpoint():
			break
	result_details["custody_checkpoint_ready"] = _checkpoint_diagnostics()
	print("[nonviolent_checkpoint] " + JSON.stringify(result_details.custody_checkpoint_ready))
	check(not assistance.is_busy() and provider.can_checkpoint(), "response reset and stable starting ground permit isolated checkpoint")
	check(provider.path == fixture and not str(provider.path).begins_with("user://"), "custody roundtrip uses the existing project-isolated provider")
	if not provider.can_checkpoint() or provider.path != fixture:
		return
	var crowd: Node3D = level.npcs.crowd
	var index := -1
	for candidate in crowd.residents.size():
		var resident: Dictionary = crowd.residents[candidate]
		if is_instance_valid(resident.get("body")) and not bool(resident.get("dead", false)) and not bool(resident.get("panic", false)) and not bool(resident.get("combat_controlled", false)) and not bool(resident.get("police_custody", false)):
			index = candidate
			break
	check(index >= 0, "living nonmission crowd identity available for synthetic custody setup")
	if index < 0:
		return
	var id := "crowd_%d" % index
	var setup_result: Dictionary = assistance.custody.restore_state({"version": 1, "custody_ids": [id]})
	check(bool(setup_result.get("ok", false)) and _custody_hidden(index), "synthetic custody restore hides identity/collider; rendered backend also verifies mesh")
	var wallet: int = level.progression.money
	check(provider.save_state() == OK, "actual isolated world save succeeds with completed custody")
	var read: Dictionary = provider.read_snapshot()
	check(bool(read.get("ok", false)), "actual isolated checkpoint reads back")
	if not bool(read.get("ok", false)):
		return
	var saved: Dictionary = read.state
	check(saved.has("police_assistance") and saved.police_assistance.version == 1 and id in saved.police_assistance.custody_ids and int(saved.progression.money) == wallet, "serialized checkpoint contains custody identity and exact wallet")
	# Synthetic fresh-session arrangement: remove only this fixture identity's
	# in-memory completion and reveal it, so a successful load must re-hide it.
	assistance.custody._completed.erase(id)
	crowd.residents[index].erase("police_custody")
	crowd.end_combat(index)
	check(not _custody_hidden(index), "synthetic in-memory reset requires disk restore to reapply custody")
	if wallet > 0:
		level.progression.debit(1, "fixture_roundtrip_change")
	else:
		level.progression.credit(1, "fixture_roundtrip_change")
	var loaded: Dictionary = provider.load_state()
	check(bool(loaded.get("ok", false)) and _custody_hidden(index) and level.progression.money == wallet, "actual load restores hidden custody and saved wallet together")
	for step in 180:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	var invalid := [
		{"version": 1, "custody_ids": ["crowd_999999"]},
		{"version": 1, "custody_ids": ["player"]},
		{"version": 2, "custody_ids": [id]},
	]
	for number in invalid.size():
		var bad: Dictionary = saved.duplicate(true)
		bad.police_assistance = invalid[number]
		bad.progression.money = wallet + 7 if wallet + 7 <= level.progression.money_cap else 0
		var bad_path := output_dir.path_join("invalid-custody-%d.json" % number)
		var file := FileAccess.open(bad_path, FileAccess.WRITE)
		check(file != null, "isolated malformed custody fixture writable %d" % number)
		if file == null:
			continue
		file.store_string(JSON.stringify(bad))
		file.close()
		var rejected := Save.new()
		level.add_child(rejected)
		rejected.setup(level, bad_path)
		check(not rejected.validate_snapshot(bad).is_empty(), "invalid custody schema rejected %d" % number)
		var refusal: Dictionary = rejected.load_state()
		check(not bool(refusal.get("ok", false)) and level.progression.money == wallet and _custody_hidden(index), "invalid custody load refuses before wallet/custody mutation %d" % number)
		rejected.queue_free()
	var older: Dictionary = saved.duplicate(true)
	older.erase("police_assistance")
	var older_provider := Save.new()
	level.add_child(older_provider)
	older_provider.setup(level, output_dir.path_join("legacy-without-custody.json"))
	check(older_provider.validate_snapshot(older).is_empty(), "older checkpoint missing optional custody section remains valid")
	var wrote: bool = older_provider.write_snapshot(older) == OK
	check(wrote, "older checkpoint writes only to isolated fixture path")
	if wrote:
		var older_result: Dictionary = older_provider.load_state()
		check(bool(older_result.get("ok", false)) and level.progression.money == wallet and _custody_hidden(index), "older checkpoint loads without erasing additive custody or changing wallet")
	older_provider.queue_free()
	result_details["custody_roundtrip"] = {"identity": id, "wallet": wallet, "checkpoint": fixture,
		"setup": "synthetic completion and in-memory reset; real disk save/load and invalid-load refusal"}

func _checkpoint_diagnostics() -> Dictionary:
	var law_state: Dictionary = level.law.get_status()
	var cruisers: Dictionary = law_state.get("cruisers", {})
	var assistance: Node = level.police_assistance
	var combat_state: Dictionary = level.combat.get_status()
	return {"blocker": provider.checkpoint_blocker(), "pending_routes": level.residents.get_status().pending_routes,
		"assistance_busy": assistance.is_busy(), "incidents": assistance.incidents.size(),
		"assistance_officers": assistance._officers.size(), "custody_records": assistance.custody.records.size(),
		"law_busy": law_state.get("busy", false), "wanted": law_state.get("wanted", 0),
		"cruisers_claimed": cruisers.get("claimed", 0), "cruisers_active": cruisers.get("active", 0),
		"combat_active": combat_state.get("active_count", 0), "combat_knocked": combat_state.get("knocked_count", 0),
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"stable_ground": not provider.safe_player_position(player.global_position).is_empty()}

func _custody_hidden(index: int) -> bool:
	var crowd: Node3D = level.npcs.crowd
	var resident: Dictionary = crowd.residents[index]
	var body = resident.get("body")
	var state_hidden: bool = level.police_assistance.custody.has("crowd_%d" % index) and bool(resident.get("police_custody", false)) and bool(resident.get("combat_controlled", false)) and (not is_instance_valid(body) or body.collision_layer == 0)
	if DisplayServer.get_name() == "headless":
		# Dummy RenderingServer does not retain MultiMesh transform writes.
		# Rendered runs below must still prove the visible mesh is zero-scaled.
		return state_hidden
	var batch: Dictionary = crowd._batches[resident.batch]
	var transform: Transform3D = batch.multimesh.get_instance_transform(int(resident.slot))
	return state_hidden and absf(transform.basis.determinant()) < .00001

func _capture_review(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-nonviolent") or DisplayServer.get_name() == "headless":
		return
	if not _window_off_desktop() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		check(false, "refuse review capture without offscreen/visible-pointer safety")
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://../artifacts/nonviolent-direction/review")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	check(error == OK and image != null and not image.is_empty(), "review viewport image available: " + label)
	if error == OK and image != null and not image.is_empty():
		check(image.save_png(directory.path_join(run_id + "-" + label + ".png")) == OK, "saved optional fixture review capture: " + label)

func _cleanup_gallery() -> void:
	if _gallery_directory.is_empty():
		return
	var gallery = player.phone.gallery
	gallery.directory = _gallery_directory
	gallery.reload()
	for entry in gallery.entries.duplicate():
		gallery.remove(str(entry.id))
	DirAccess.remove_absolute(_gallery_directory)
