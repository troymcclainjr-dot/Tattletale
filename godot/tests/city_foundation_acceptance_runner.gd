extends "res://tests/city_priorities_session_fixture.gd"
## Production world, real keyboard/mouse events, private checkpoint and gallery.
## Only player placement is arranged; no completion/evidence/witness flags seeded.
var _case_hooks: Array[Dictionary] = []
var _case_signal_counts := {"evidence": 0, "report": 0, "resolved": 0}
var _parcel_evidence: Array[Dictionary] = []
var _phone_report_events: Array[Dictionary] = []

func _run() -> void:
	begin_phase("boot")
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/pacifist-foundation/acceptance/" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.setup(level, fixture)
	result_details["profile"] = OS.get_user_data_dir()
	await _capture_foundation("world")
	await _phone_and_map()
	await _pacifist_and_bicycle()
	await _parcel_case()
	await _checkpoint_roundtrip()
	await _incident_reporting()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "acceptance never captures the desktop pointer or foreground")
	_finish()

func _capture_foundation(id: String) -> void:
	if not _window_off_desktop() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		check(false, "capture requires off-desktop unfocused window and visible pointer")
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), id + " viewport contains rendered image")
	if image != null:
		check(image.save_png(output_dir.path_join(id + ".png")) == OK, id + " screenshot saved")

func _phone_and_map() -> void:
	begin_phase("phone_map")
	var phone: Node = player.get("phone")
	check(phone != null and phone.has_method("get_status"), "production phone is installed")
	if phone == null:
		return
	await key(KEY_P)
	check(phone.get_status().active and phone.get_status().page == "home", "P opens phone home")
	await _capture_foundation("phone-home")
	var time_before: float = level.world_time.elapsed_seconds
	await frames(8)
	check(float(level.world_time.elapsed_seconds) > time_before and not level.paused, "phone leaves the actual world clock running")
	for app in [[KEY_1, "contacts"], [KEY_2, "camera"], [KEY_3, "photos"], [KEY_4, "cases"], [KEY_5, "police"]]:
		await key(int(app[0]))
		check(phone.get_status().active and str(phone.get_status().page) == str(app[1]), "phone input opens " + str(app[1]))
	await key(KEY_2)
	var before: Dictionary = phone.get_status()
	await key(KEY_ENTER)
	for i in 120:
		await frames(1)
		if not bool(phone.get_status().capturing):
			break
	var after: Dictionary = phone.get_status()
	check(int(after.gallery_count) == int(before.gallery_count) + 1 and int(after.captures_emitted) == int(before.captures_emitted) + 1,
		"real shutter stores one private photo and emits one trusted capture")
	await key(KEY_BACKSPACE)
	check(str(phone.get_status().page) == "home", "Backspace returns camera to phone home")
	await key(KEY_M)
	await frames(3)
	check(not bool(phone.get_status().active) and level._map_overlay.visible, "M suspends phone and opens map through level input")
	var map: Control = level._map_overlay.map
	check(map.has_method("poi_entries"), "map exposes real POI registry")
	if map.has_method("poi_entries"):
		var entries: Array = map.poi_entries()
		var categories: Dictionary = {}
		for entry in entries:
			categories[str(entry.get("category", ""))] = true
		check(entries.size() > 5 and categories.size() >= 4, "map contains categorized civic/business symbols")
		var stats: Dictionary = map.get("last_draw_stats")
		check(int(stats.get("icons", 0)) > 0 and int(stats.get("captions", 99)) <= 1, "map draws icon symbols without a blanket of POI captions")
		check(level._map_overlay.key.get_child_count() >= 10, "map legend explains the icon vocabulary")
		result_details["map"] = {"entries": entries.size(), "categories": categories.keys(), "draw": stats}
	await _capture_foundation("map")
	await key(KEY_M)
	check(not level._map_overlay.visible, "M closes the map")
	await key(KEY_P)
	await key(KEY_P)
	check(not bool(phone.get_status().active), "P toggles phone closed without invoking combat")

func _pacifist_and_bicycle() -> void:
	begin_phase("pacifist_bicycle")
	var combat: Node = level.combat
	check(combat.has_method("player_offense_enabled") and not combat.player_offense_enabled(), "player combat policy is disabled")
	var inventory: Variant = canonical(combat.equipment_snapshot())
	var punches: int = combat.get("punches_thrown")
	var wanted: int = level.law.get_status().wanted
	for code in [KEY_2, KEY_3, KEY_4]:
		await key(code)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)
	check(canonical(combat.equipment_snapshot()) == inventory and int(combat.get("punches_thrown")) == punches,
		"real weapon keys and attack input do not equip/fire/punch")
	check(int(level.law.get_status().wanted) == wanted, "disabled player attack does not create a crime")
	var bicycle: Node3D = level.get("bicycle")
	check(bicycle != null and bicycle.has_method("get_status"), "production bicycle is installed")
	if bicycle == null:
		return
	check(await stand_near(bicycle.global_position, 1.1), "player can stand beside existing bicycle")
	await key(KEY_P)
	await key(KEY_F)
	check(not bool(bicycle.get_status().active), "phone-open input cannot mount a bicycle")
	await key(KEY_P)
	await key(KEY_F)
	check(bool(bicycle.get_status().active), "F mounts the nearby bicycle")
	if not bool(bicycle.get_status().active):
		return
	await key(KEY_P)
	check(not bool(player.phone.get_status().active), "riding cannot open the phone")
	var heading: float = bicycle.get("yaw")
	player.camera_yaw += PI * 0.5
	await held_key(KEY_W, true)
	await frames(12)
	check(not provider.can_checkpoint() and provider.checkpoint_blocker() == "stop the bicycle before saving", "moving bicycle blocks checkpoint until stopped")
	await held_key(KEY_W, false)
	check(absf(float(bicycle.get_status().speed)) > 0.05, "W pedals with camera looking sideways")
	check(absf(angle_difference(heading, float(bicycle.get("yaw")))) < 0.15, "camera orbit does not steer the bicycle")
	await held_key(KEY_S, true)
	for i in 90:
		await frames(1)
		if absf(float(bicycle.get_status().speed)) < 0.12:
			break
	await held_key(KEY_S, false)
	await key(KEY_F)
	check(not bool(bicycle.get_status().active), "braking then F returns to walking")
	result_details["bicycle"] = bicycle.get_status()

func _choose_case_reply(id: String, offer := false) -> bool:
	for line in 14:
		if not level._dialogue.state.active:
			return false
		var choices: Array = level._dialogue.state.choices()
		if choices.is_empty():
			await key(KEY_ENTER)
			continue
		for index in choices.size():
			var hook: Dictionary = choices[index].get("hook", {})
			var kind := str(hook.get("kind", ""))
			if str(hook.get("id", "")) != id:
				continue
			if (offer and kind != "start_case") or (not offer and kind not in ["case_step", "case_interview", "case_report"]):
				continue
			var already_selected := false
			for previous in _case_hooks:
				already_selected = already_selected or previous == hook
			if already_selected:
				continue
			var buttons: Array = level._dialogue.replies.get_children()
			if index >= buttons.size() or not buttons[index] is Button:
				return false
			_case_hooks.append(hook.duplicate(true))
			await click(buttons[index])
			await frames(2)
			return true
		return false
	return false

func _accept_case(id: String) -> bool:
	if str(level.missions.active_id) == id:
		return true
	var contact: Vector3 = level.npcs.actor_position("resident")
	if not contact.is_finite() or not await stand_near(contact, 1.8, true):
		return false
	await key(KEY_E)
	var accepted := await _choose_case_reply(id, true)
	if level._dialogue.state.active:
		await key(KEY_ESCAPE)
	return accepted and str(level.missions.active_id) == id

func _complete_case(id: String) -> bool:
	for i in 24:
		if id in level.missions.snapshot_state().completed_ids:
			return true
		if str(level.missions.active_id) != id:
			return false
		var status: Dictionary = level.missions.get_status()
		var target: Vector3 = status.target_position
		if not target.is_finite() or not await stand_near(target, 1.8, true):
			return false
		await key(KEY_E)
		var chosen := await _choose_case_reply(id)
		if level._dialogue.state.active:
			await key(KEY_ESCAPE)
		if not chosen:
			return false
	return false

func _parcel_case() -> void:
	begin_phase("data_case")
	var missions: Node = level.missions
	var ready := missions.has_method("case_detail") and missions.has_method("evidence_list") and FileAccess.file_exists("res://assets/data/cases/parcel_report.json")
	check(ready, "migrated parcel data and evidence API are installed; legacy fallback is not accepted as the data test")
	if not ready:
		return
	check(await _accept_case("lost_satchel") and await _complete_case("lost_satchel"), "prerequisite satchel completed through dialogue and clue interactions")
	if not "lost_satchel" in missions.snapshot_state().completed_ids:
		return
	if missions.has_signal("evidence_recorded"):
		missions.evidence_recorded.connect(func(case_id: String, evidence: Dictionary):
			_case_signal_counts.evidence += 1
			if case_id == "parcel_report":
				_parcel_evidence.append(evidence.duplicate(true)))
	if missions.has_signal("report_filed"):
		missions.report_filed.connect(func(_id: String, _report: Dictionary): _case_signal_counts.report += 1)
	if missions.has_signal("case_resolved"):
		missions.case_resolved.connect(func(_id: String, _outcome: Dictionary): _case_signal_counts.resolved += 1)
	var money: int = level.progression.money
	var score: int = missions.score
	check(await _accept_case("parcel_report"), "resident dialogue accepts migrated opened-parcel case")
	check(await _complete_case("parcel_report"), "real examine/interview/report replies resolve parcel case")
	var state: Dictionary = missions.snapshot_state()
	var engine: Dictionary = state.get("case_engine", {})
	check(engine.get("records", {}).has("parcel_report"), "resolution recorded by data engine, not legacy fallback")
	# Closed records may retain evidence IDs rather than full active payloads.
	# Observe trusted production signals while playing instead of seeding data.
	var evidence: Array = _parcel_evidence.duplicate(true)
	var unique_evidence: Dictionary = {}
	for entry in evidence:
		unique_evidence[str(entry.get("id", ""))] = true
	check(unique_evidence.size() >= 2 and not unique_evidence.has(""), "parcel inspection and witness interview produce distinct actual evidence")
	check(int(_case_signal_counts.report) == 1 and int(_case_signal_counts.resolved) == 1, "one report and one resolution emitted")
	check(int(missions.score) == score + 150 and int(level.progression.money) == money + int(level.progression.case_money("parcel_report", 150)), "parcel reward paid once at existing configured rate")
	var paid: Variant = canonical(level.progression.snapshot_state())
	check(not level.progression.reward_case("parcel_report", 150) and canonical(level.progression.snapshot_state()) == paid, "duplicate reward request cannot pay twice")
	result_details["parcel"] = {"hooks": _case_hooks, "signals": _case_signal_counts, "evidence": evidence, "engine": engine}

func _checkpoint_roundtrip() -> void:
	begin_phase("durable_reload")
	_set_scenario_position(startup_position)
	for i in 900:
		if provider.can_checkpoint():
			break
		await frames(1)
	check(provider.can_checkpoint(), "real world reaches checkpoint-safe state")
	if not provider.can_checkpoint():
		result_details["checkpoint_blocker"] = provider.checkpoint_blocker()
		return
	level.pause_exploring()
	var expected := {"missions": canonical(level.missions.snapshot_state()), "progression": canonical(level.progression.snapshot_state())}
	var snapshot: Dictionary = provider.snapshot_state()
	check(not snapshot.is_empty() and provider.validate_snapshot(snapshot).is_empty(), "complete foundation checkpoint validates")
	if snapshot.is_empty():
		return
	check(provider.write_snapshot(snapshot) == OK, "checkpoint written to private fixture path")
	var old_id := level.get_instance_id()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	for i in 1800:
		await frames(1)
		level = get_tree().current_scene as Node3D
		if level != null and level.get_instance_id() != old_id and level.get("level_ready") == true:
			break
	check(level != null and level.get_instance_id() != old_id and level.get("level_ready") == true, "fresh complete world boots for durable restore")
	if level == null or level.get("level_ready") != true:
		return
	player = level.player
	check(not level.world_save.enabled, "fresh scene cannot access production save slot")
	provider = Save.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	level.world_save = provider
	for attempt in 2:
		var result: Dictionary = provider.load_state()
		check(bool(result.get("ok", false)), "full checkpoint restore succeeds, attempt %d" % (attempt + 1))
		for section in ["missions", "progression"]:
			check(canonical(level.get(section).snapshot_state()) == expected[section], "reload preserves exact " + section + " without replaying rewards")
	level.resume_exploring()
	_place_window_off_desktop()
	await _settle_window_safety()
	await _capture_foundation("world-reloaded")

func _incident_reporting() -> void:
	begin_phase("truthful_incidents")
	var incidents: Node = level.get("incidents")
	check(incidents != null, "incident service is integrated into real level")
	if incidents == null:
		return
	for method in ["spawn_template_now", "performer_actor", "report_incident", "reportable_for", "get_incident", "set_spawning_enabled"]:
		if not incidents.has_method(method):
			check(false, "incident service missing contract method " + method)
			return
	incidents.set_spawning_enabled(false)
	var unknown: Dictionary = incidents.report_incident("inc_acceptance_missing", "player", {"channel": "phone"})
	check(not bool(unknown.get("ok", true)) and str(unknown.get("reason", "")) == "unknown_incident", "unknown incident is rejected without inventing a report")
	# Let the normal planner select a free neighbor and a real mid-block road
	# crossing. Do not pin a synthetic route or convert an ended external record
	# into something the player supposedly saw happening.
	var opened: Dictionary = {}
	var spawn_attempts: Array = []
	for anchor_id in ["", "lookout", "resident", "caretaker", "gardener", "organizer"]:
		var anchor: Vector3 = startup_position if anchor_id.is_empty() else level.npcs.actor_position(anchor_id)
		if not anchor.is_finite() or not await stand_near(anchor, 2.0):
			continue
		# Allow normal neighborhood body residency to settle before planning.
		await frames(60)
		opened = incidents.spawn_template_now("jaywalking")
		spawn_attempts.append({"anchor": anchor_id, "result": opened.duplicate(true)})
		if bool(opened.get("ok", false)):
			break
	result_details["incident_spawn_attempts"] = spawn_attempts
	check(bool(opened.get("ok", false)), "production planner starts a live neighbor crossing an actual road")
	if not bool(opened.get("ok", false)):
		result_details["incident_open"] = opened
		return
	var id := str(opened.incident_id)
	var offender := ""
	for participant in incidents.get_incident(id).get("participants", []):
		if str(participant.get("role", "")) == "offender":
			offender = str(participant.get("id", ""))
	var performer: Node3D = incidents.performer_actor(offender) as Node3D
	check(is_instance_valid(performer), "spawn owns a real physical performer")
	if not is_instance_valid(performer):
		return
	var first_position := performer.global_position
	# This happens before the next simulation frame, so the initial spawn
	# cannot accidentally become witnessed while we arrange the far position.
	var placed_far := await stand_near(first_position, 55.0)
	var outside_sight: bool = placed_far and flat_distance(player.global_position, performer.global_position) > 40.0
	check(outside_sight,
		"unwitnessed scenario places player outside actual 40 m sight range")
	if not outside_sight:
		return
	var unseen: Dictionary = incidents.report_incident(id, "player", {"channel": "phone"})
	check(not bool(unseen.get("ok", true)) and str(unseen.get("reason", "")) == "not_witnessed", "unwitnessed report rejected rather than fabricated")
	check(await stand_near(performer.global_position, 4.0), "player approaches actual live performer")
	var observed := false
	for i in 240:
		if not is_instance_valid(performer):
			break
		var toward := performer.global_position - player.global_position
		player.camera_yaw = atan2(toward.x, toward.z)
		player.camera_pitch = 0.05
		player.update_camera()
		await frames(1)
		for entry in incidents.reportable_for("player"):
			if str(entry.get("id", entry.get("incident_id", ""))) == id:
				observed = true
		if observed and flat_distance(first_position, performer.global_position) > 0.05:
			break
	var witnessed_by_sight := false
	for witness in incidents.get_incident(id).get("witnesses", []):
		witnessed_by_sight = witnessed_by_sight or (str(witness.get("id", "")) == "player" and str(witness.get("via", "")) == "sight")
	check(is_instance_valid(performer) and flat_distance(first_position, performer.global_position) > 0.05,
		"performer actually moves along the production crossing")
	check(witnessed_by_sight, "player witness provenance is the production sight observer")
	check(observed, "production sight/LOS polling records player witness; no witness/evidence flag injected")
	if not observed:
		result_details["unobserved_incident"] = incidents.get_incident(id)
		return
	if incidents.has_signal("report_status_changed"):
		incidents.report_status_changed.connect(func(status: Dictionary): _phone_report_events.append(status.duplicate(true)))
	await key(KEY_P)
	await key(KEY_5)
	await key(KEY_ENTER)
	await frames(6)
	var reported: Dictionary = incidents.get_incident(id)
	var report: Dictionary = reported.get("report", {})
	var phone_routed := str(report.get("by", "")) == "player" and str(report.get("channel", "")) == "phone"
	for event in _phone_report_events:
		phone_routed = phone_routed or (str(event.get("incident_id", "")) == id and bool(event.get("phone", false)) and str(event.get("status", "")) not in ["rejected", "unavailable"])
	check(phone_routed and not report.is_empty(), "actual phone Police/Enter route files or corroborates witnessed report")
	var duplicate: Dictionary = incidents.report_incident(id, "player", {"channel": "phone"})
	check(bool(duplicate.get("duplicate", false)), "repeat report does not dispatch a second incident")
	check(str(incidents.get_incident(id).get("report", {}).get("police_incident_id", "")) == str(report.get("police_incident_id", "")), "duplicate report retains original dispatch identity")
	result_details["incident"] = {"unknown": unknown, "unseen": unseen, "reported": reported, "duplicate": duplicate}
	await _capture_foundation("phone-report")
	await key(KEY_P)
