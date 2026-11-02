extends "res://tests/city_foundation_acceptance_runner.gd"
## One continuous production city, then one explicit durable checkpoint reload.
## Only scenario starts/camera are arranged. Interactions and ball flight use
## real input/physics; no manufactured purchases, evidence, points or rewards.
const Catalog := preload("res://scripts/city/city_shop_catalog.gd")
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
var _session_world_id := 0
var _session_gallery := 0
var _session_purchase := false

func _watchdog() -> void:
	await get_tree().create_timer(600.0, true, false, true).timeout
	if not finished:
		check(false, "mixed city session completes within ten minutes including boot and reload")
		_finish()

func _run() -> void:
	begin_phase("boot")
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/polish-five/session-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.setup(level, fixture)
	_cleanup()
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	Bindings.apply() # Process-local fixture input, never saved to user controls.
	_session_world_id = level.get_instance_id()
	result_details.scope = "One full-population city through phone/photo/map, bicycle, pantry purchase, physical basketball and truthful report, followed by one durable fresh-scene reload."
	result_details.limitations = "Scenario starting poses are arranged; not an uninterrupted cross-city navigation test. No forced basket, completed pickup match, full case resolution, EMS response or performance threshold claim. Incident is requested from the real planner; witness/report provenance is actual sight and phone input."
	result_details.profile = OS.get_user_data_dir()
	await _capture_foundation("mixed-world-start")
	await _phone_and_map()
	_session_gallery = int(player.phone.get_status().gallery_count)
	_session_checkpoint_sample("after-phone")
	await _pacifist_and_bicycle()
	if bool(level.bicycle.get_status().active):
		check(false, "bicycle must dismount normally before walking activities")
		_finish()
		return
	_session_checkpoint_sample("after-bicycle")
	await _pantry_visit()
	_session_checkpoint_sample("after-pantry")
	await _court_visit()
	_session_checkpoint_sample("after-court")
	if bool(level.basketball._charging) or int(level.basketball._held) >= 0:
		check(false, "court phase must release its ball before leaving")
		_finish()
		return
	await _incident_reporting()
	_session_checkpoint_sample("after-report")
	if not await _wait_for_report_response():
		_finish()
		return
	var wallet_before: int = level.progression.money
	var purchase_before := str(level.progression.equipped_shop_item("bandana_color"))
	await _checkpoint_roundtrip()
	begin_phase("mixed-restored")
	check(level.get_instance_id() != _session_world_id, "only the explicit final reload replaces the session world")
	if level.get_instance_id() == _session_world_id:
		_finish() # A blocked save is never evidence that a reload preserved state.
		return
	check(int(level.progression.money) == wallet_before and str(level.progression.equipped_shop_item("bandana_color")) == purchase_before,
		"reload retains session wallet and equipped pantry purchase without another debit")
	check(_session_purchase and purchase_before == "bandana_ocean", "real purchased bandana survived all later activities")
	check(int(player.phone.get_status().gallery_count) >= _session_gallery and _session_gallery > 0,
		"private session photo remains in gallery after durable reload")
	check(level.basketball.mode == "free" and level.basketball._held < 0 and not level.basketball._charging,
		"reload clears transient basketball possession and charge")
	check(not level.combat.player_offense_enabled(), "pacifist policy remains active after mixed activity reload")
	check(level.npcs.crowd.get_status().total == 1200 and level.residents.get_status().count == 40 and level.traffic.vehicles.size() == 90,
		"mixed session and reload retain full 1200/40/90 population")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "mixed session never captures desktop pointer or foreground")
	await _capture_foundation("mixed-finish")
	_finish()

func _session_checkpoint_sample(label: String) -> void:
	check(level.get_instance_id() == _session_world_id, label + " retains the same live world")
	_sample(label, false)

func held_key(code: int, pressed: bool) -> void:
	await super.held_key(code, pressed)
	if code == KEY_S and pressed and is_instance_valid(level) and level.bicycle.active:
		# This session intends to stop, not back up. Observe every physics frame
		# and release the actual key as soon as the production bicycle rests;
		# rendered captures/slow frames must not stretch S into a reverse command.
		var began := Time.get_ticks_msec()
		var stopped := false
		while Time.get_ticks_msec() - began < 3000:
			await get_tree().physics_frame
			if absf(float(level.bicycle.speed)) <= 0.03:
				stopped = true
				break
		await super.held_key(KEY_S, false)
		result_details.bicycle_brake = {"stopped": stopped, "wall_ms": Time.get_ticks_msec() - began,
			"status": level.bicycle.get_status()}
		check(stopped, "real S brake reaches a stop before the key is released")
	# Observe the inherited real-input ride immediately after W is released;
	# wheels still move, and the camera/solver remain in their gameplay state.
	if code == KEY_W and not pressed and is_instance_valid(level):
		var bicycle: Node3D = level.get("bicycle")
		if bicycle != null and bicycle.active and absf(bicycle.speed) > 0.05:
			result_details.bicycle_capture = bicycle.get_status()
			await _capture_foundation("mixed-bicycle-moving")

## A filed call owns a real physical response, which correctly blocks saves.
## Observe it in the running world; never cancel units, change response clocks,
## clear flags, or relocate the reporter while waiting for it to finish.
func _wait_for_report_response() -> bool:
	begin_phase("mixed-response-settle")
	var incident_details: Dictionary = result_details.get("incident", {})
	var record: Dictionary = incident_details.get("reported", {})
	var report: Dictionary = record.get("report", {})
	var call_id := str(report.get("police_incident_id", ""))
	var record_id := str(record.get("id", ""))
	check(not call_id.is_empty(), "reported incident has a real dispatch identity to observe")
	if call_id.is_empty():
		return false
	var assistance: Node = level.police_assistance
	var began := Time.get_ticks_msec()
	var clock_before: float = level.world_time.elapsed_seconds
	var deadline := began + 180000
	var next_record := began
	var previous := ""
	var rows: Array[Dictionary] = []
	var resolved := false
	var terminal := false
	while Time.get_ticks_msec() < deadline:
		var call: Dictionary = assistance.call_status(call_id)
		var incident: Dictionary = level.incidents.get_incident(record_id)
		var blocked: bool = assistance.blocks_checkpoint() or level.incidents.blocks_checkpoint()
		var signature := JSON.stringify([call.get("stage", "unknown"), call.get("handling", ""),
			call.get("outcome", ""), call.get("units", []), blocked])
		if signature != previous or Time.get_ticks_msec() >= next_record:
			var row := {"wall_seconds": float(Time.get_ticks_msec() - began) / 1000.0,
				"simulation_seconds": float(level.world_time.elapsed_seconds) - clock_before,
				"call": call, "response_blocks_checkpoint": blocked,
				"checkpoint_blocker": provider.checkpoint_blocker(),
				"incident_state": incident.get("state", ""), "incident_resolution": incident.get("resolution", {}),
				"police": assistance.get_status()}
			rows.append(row)
			result_details.response_wait = rows
			print("[polish_response] ", JSON.stringify(row))
			var path := output_dir.path_join("response-wait.jsonl")
			var file := FileAccess.open(path, FileAccess.READ_WRITE if rows.size() > 1 else FileAccess.WRITE)
			if file != null:
				file.seek_end()
				file.store_line(JSON.stringify(row))
				file.flush()
			previous = signature
			next_record = Time.get_ticks_msec() + 10000
		terminal = str(call.get("stage", "")) in ["resolved", "failed", "cancelled", "unavailable"]
		if terminal and not blocked:
			resolved = str(call.get("stage", "")) == "resolved" and str(call.get("outcome", "")) != "timeout"
			break
		await frames(6)
	result_details.response_final = {"dispatch": assistance.call_status(call_id), "police": assistance.get_status(),
		"incident": level.incidents.get_incident(record_id), "checkpoint_blocker": provider.checkpoint_blocker(),
		"wall_seconds": float(Time.get_ticks_msec() - began) / 1000.0}
	check(terminal, "reported response reaches a terminal dispatch stage within 180 seconds")
	check(resolved, "reported response resolves naturally and releases its checkpoint barrier")
	if resolved:
		await _capture_foundation("mixed-response-resolved")
	return resolved

func _pantry_visit() -> void:
	begin_phase("mixed-pantry")
	var shops: Node3D = level.shops
	check(shops.models.has(Catalog.SHOP_ID), "actual pantry service window is present")
	if not shops.models.has(Catalog.SHOP_ID):
		return
	var window: Node3D = shops.models[Catalog.SHOP_ID]
	var local: Vector3 = window.get_meta("counter_local")
	var target := window.to_global(local)
	var approach := Facilities.standing_at(level.get_world_3d().direct_space_state,
		window.to_global(local + Vector3(0.0, 0.0, 2.0)), [player.get_rid()])
	check(not approach.is_empty(), "pantry approach has collision-clear street support")
	if approach.is_empty():
		return
	_set_scenario_position(approach.position)
	await frames(20)
	var reached := await _walk_to(target)
	check(reached, "walking from street approach physically reaches pantry window")
	if not reached:
		return # Never replace failed physical access with a counter teleport.
	await frames(30)
	check(player.is_on_floor() and shops.counter_at(player.global_position) == Catalog.SHOP_ID,
		"player settles on actual pantry apron inside interaction region")
	var wallet: int = level.progression.money
	await key(KEY_E)
	check(shops.is_open() and shops.active_id == Catalog.SHOP_ID, "E opens the pantry through production interaction")
	if not shops.is_open():
		return
	var buy := shops.stock_rows.get_node_or_null("Buy_bandana_ocean") as Button
	check(buy != null and not buy.disabled, "authored wallet can buy the displayed bandana without seeded money")
	if buy != null and not buy.disabled:
		await click(buy)
		_session_purchase = level.progression.money == wallet - 30 and level.progression.equipped_shop_item("bandana_color") == "bandana_ocean"
		check(_session_purchase, "actual pantry button debits exactly 30 and equips the bandana")
	await _capture_foundation("mixed-pantry")
	await key(KEY_ESCAPE)
	await frames(6)
	check(not shops.is_open() and not level.paused and player.enabled, "closing pantry resumes the same walking session")
	result_details.pantry = {"purchased": _session_purchase, "money_before": wallet, "money_after": level.progression.money}

func _court_visit() -> void:
	begin_phase("mixed-basketball")
	var activity: Node3D = level.basketball
	var selected := -1
	var nearest := INF
	for index in activity.frames.size():
		var candidate: RefCounted = activity.frames[index]
		if not candidate.playable() or not candidate.full():
			continue
		var distance := flat_distance(candidate.center, player.global_position)
		if distance < nearest:
			selected = index
			nearest = distance
	check(selected >= 0, "real full court is available during mixed session")
	if selected < 0:
		return
	var court: RefCounted = activity.frames[selected]
	var approach := Facilities.standing_at(level.get_world_3d().direct_space_state,
		court.center + court.across * 3.0, [player.get_rid()])
	check(not approach.is_empty(), "court approach has real collision-clear support")
	if approach.is_empty():
		return
	_set_scenario_position(approach.position)
	await frames(30)
	var reached := await _walk_to(court.center)
	check(reached, "normal walking reaches the actual court ball")
	if not reached:
		return
	await frames(12)
	await key(KEY_E)
	check(activity._held == selected and activity.mode == "shootaround", "E picks up the existing physical basketball")
	if activity._held != selected:
		return
	var before_shots: int = activity.shots
	var before_games: int = activity.games_started
	for modal in ["pause", "phone", "map"]:
		await _session_shoot(true)
		await frames(5)
		check(activity._charging and activity._charge > 0.0, modal + " starts from an actual charged ball")
		var code: int = KEY_ESCAPE if modal == "pause" else (KEY_P if modal == "phone" else KEY_M)
		await key(code)
		await frames(3)
		var opened: bool = level.paused if modal == "pause" else (player.phone.active if modal == "phone" else level._map_overlay.visible)
		check(opened and not activity._charging and not activity._meter.visible, modal + " cancels charge and hides power meter")
		await _session_shoot(false)
		await key(KEY_T)
		check(activity.shots == before_shots and activity.games_started == before_games and activity._held == selected,
			modal + " consumes shot release and challenge without losing possession")
		await key(code)
		await frames(3)
		check(not level.paused and not player.phone.active and not level._map_overlay.visible, modal + " closes back into same court session")
	player.camera_yaw = atan2(court.along.x, court.along.z)
	player.camera_pitch = 0.24
	player.update_camera()
	await _session_shoot(true)
	await frames(4)
	await _session_shoot(false)
	check(activity.shots == before_shots + 1 and activity._held < 0 and activity.balls[selected].active,
		"real release launches one physical ball after all modal interruptions")
	var origin: Vector3 = activity.balls[selected].body.global_position
	var travelled := 0.0
	var grounded := false
	for tick in 240:
		await frames(1)
		var ball: Dictionary = activity.balls[selected]
		travelled = maxf(travelled, origin.distance_to(ball.body.global_position))
		if bool(ball.release.get("grounded", false)):
			grounded = true
			break
	check(grounded and travelled > 0.5, "shot travels through real city physics and contacts court floor")
	result_details.basketball = {"court": court.id, "travelled": travelled, "ground_contact": grounded, "status": activity.get_status()}
	await _capture_foundation("mixed-court")

func _session_shoot(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(8.0, 8.0)
	event.global_position = event.position
	Input.parse_input_event(event)
	await get_tree().process_frame
