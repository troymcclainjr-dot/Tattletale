extends "res://tests/city_priorities_session_runner.gd"
## The clock is never accelerated. Wall duration excludes boot and the complete
## integration flow. Every cycle traverses active world/UI/checkpoint phases.
var completed_cycles := 0
var soak_started_usec := 0
var soak_baseline: Dictionary = {}
var soak_duration := 0.0
var stop_cycles := false
var deferred_supply_cycles := 0
var income_runs_before := 0
var cycles_done := false

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	await session_flow()
	if failures > 0:
		_finish()
		return
	begin_phase("soak-warmup")
	var saves_before: int = provider.save_count
	await get_tree().create_timer(35.0, true, false, true).timeout
	check(provider.save_count > saves_before and provider.path == fixture,
		"normal periodic autosave commits to the isolated test checkpoint")
	if failures > 0:
		_finish()
		return
	soak_duration = clampf(float(option("--session-seconds", "120")), 30.0, 14400.0)
	soak_started_usec = Time.get_ticks_usec()
	income_runs_before = int(level.progression.snapshot_state().errands.runs)
	await _settled_world_sample("baseline")
	soak_baseline = samples.back().duplicate(true)
	sampling = true
	_sample_loop()
	_cycles()
	# This deadline is independent of cycle coroutines; stalled phases cannot
	# extend an advertised 15-minute session indefinitely or fake completion.
	while float(Time.get_ticks_usec() - soak_started_usec) / 1000000.0 < soak_duration and failures == 0:
		await get_tree().create_timer(1.0, true, false, true).timeout
	stop_cycles = true
	var aborted := failures > 0
	# A failure is a reason to stop new cycles, never a completed coroutine.
	# Wait in real time so slow render frames cannot silently extend this bound.
	var settle_deadline := Time.get_ticks_usec() + 30000000
	while not cycles_done and Time.get_ticks_usec() < settle_deadline:
		await frames(1)
	var cycle_settled := cycles_done
	begin_phase("soak-budgets")
	await frames(2)
	_sample("final", cycle_settled)
	check(cycle_settled, "last in-flight phase reached a safe cycle boundary within 30 seconds")
	check(completed_cycles >= 1, "at least one complete mixed cycle finished")
	var periodic_count := 0
	for sample in samples:
		if sample.sample_kind == "periodic":
			periodic_count += 1
	if not aborted:
		check(float(Time.get_ticks_usec() - soak_started_usec) / 1000000.0 >= soak_duration,
			"requested real wall-clock duration completed")
		check(periodic_count >= int(soak_duration / 5.0) - 1, "periodic metric sampling stayed live")
	_assert_population_and_authority()
	var last: Dictionary = samples.back()
	if not aborted:
		check(float(last.clock_seconds) > float(soak_baseline.clock_seconds) + soak_duration * .40,
			"normal game clock advanced during active mixed simulation")
	check(float(last.traffic_distance) > float(soak_baseline.traffic_distance) + 50.0,
		"normal traffic covered distance during soak")
	check(level.is_physics_processing() and player.is_physics_processing() and not level.paused,
		"normal world/player processing restored at cycle boundary")
	var peak_memory := 0.0
	var peak_objects := 0.0
	var peak_nodes := 0.0
	var peak_orphans := 0.0
	var peak_draw := 0.0
	var peak_world_draw := 0.0
	var peak_live_orphans := 0.0
	var peak_settled_orphans := 0.0
	var context_draw_peaks: Dictionary = {}
	for sample in samples:
		peak_memory = maxf(peak_memory, float(sample.memory_static))
		peak_objects = maxf(peak_objects, float(sample.objects))
		peak_nodes = maxf(peak_nodes, float(sample.nodes))
		peak_orphans = maxf(peak_orphans, float(sample.orphans))
		peak_draw = maxf(peak_draw, float(sample.draw_calls))
		peak_live_orphans = maxf(peak_live_orphans, float(sample.orphan_inventory.unexplained))
		if sample.sample_kind in ["baseline", "boundary", "final"]:
			peak_settled_orphans = maxf(peak_settled_orphans, float(sample.orphans))
		if sample.render_context_stable:
			var context: String = sample.render_context
			context_draw_peaks[context] = maxf(float(context_draw_peaks.get(context, 0.0)), float(sample.draw_calls))
			if context == "world":
				peak_world_draw = maxf(peak_world_draw, float(sample.draw_calls))
	# Explicit transient budgets, after the initial complete story/scene reload.
	# The JSONL also permits inspecting gradual growth independent of these caps.
	check(peak_memory <= float(soak_baseline.memory_static) * 1.25 + 64.0 * 1024.0 * 1024.0,
		"static memory peak within baseline +25% +64MiB")
	check(peak_objects <= float(soak_baseline.objects) + 6000.0, "object peak within 6000 transient objects of warm baseline")
	check(peak_nodes <= float(soak_baseline.nodes) + 1500.0, "node peak within 1500 transient nodes of warm baseline")
	check(peak_live_orphans <= float(soak_baseline.orphans) + 64.0,
		"unexplained orphan peak within 64 nodes of warm baseline; queued deletion independently identified")
	check(peak_settled_orphans <= float(soak_baseline.orphans) + 64.0,
		"settled cycle boundaries retain no orphan growth beyond original 64-node budget")
	if DisplayServer.get_name() == "headless":
		print("[priorities_session] draw-call budget unavailable: headless dummy renderer")
	else:
		check(peak_world_draw > 0.0 and peak_world_draw <= maxf(2600.0, float(soak_baseline.draw_calls) * 2.0),
			"rendered active-world draw calls remain under original bounded peak")
	result_details.merge({"requested_soak_seconds": soak_duration, "completed_cycles": completed_cycles,
		"aborted_after_primary_failure": aborted, "cycles_settled": cycle_settled, "periodic_samples": periodic_count,
		"draw_peaks_by_context": context_draw_peaks,
		"modal_draw_budget": "reported separately; no absolute modal rendering budget established",
		"lawful_income_runs": int(level.progression.snapshot_state().errands.runs) - income_runs_before,
		"measured_soak_seconds": float(Time.get_ticks_usec() - soak_started_usec) / 1000000.0,
		"baseline": soak_baseline, "peaks": {"memory_static": peak_memory, "objects": peak_objects,
			"nodes": peak_nodes, "orphans": peak_orphans, "unexplained_orphans": peak_live_orphans,
			"settled_orphans": peak_settled_orphans, "world_draw_calls": peak_world_draw,
			"draw_calls": peak_draw if DisplayServer.get_name() != "headless" else null}}, true)
	_finish()

func _settled_world_sample(kind: String) -> void:
	_set_scenario_position(startup_position)
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.camera_pitch = .24
	player.update_camera()
	await frames(3)
	_sample(kind, _metric_context() == "world")

func _cycles() -> void:
	while not stop_cycles and failures == 0:
		begin_phase("soak-walk")
		_set_scenario_position(startup_position)
		level.resume_exploring()
		var walked_before: float = player.distance_walked
		await held_key(KEY_W, true)
		await frames(60)
		await held_key(KEY_W, false)
		check(player.distance_walked > walked_before + .1, "real W input advances walking with normal simulation")
		if stop_cycles or failures > 0:
			break
		begin_phase("soak-drive")
		await _starter_pulse()
		if stop_cycles or failures > 0:
			break
		begin_phase("soak-modals")
		await key(KEY_M)
		check(level.paused and level._map_overlay.visible, "real M opens map")
		await frames(12)
		_sample("modal-open", true)
		await key(KEY_ESCAPE)
		await key(KEY_F6)
		check(level.inspector.active, "real F6 opens inspection")
		await frames(12)
		_sample("modal-open", true)
		await key(KEY_F6)
		check(not level.inspector.active and not level.paused, "map/inspection return to live world")
		await _browse_shop()
		await _browse_story()
		if stop_cycles or failures > 0:
			break
		if completed_cycles % 3 == 2:
			begin_phase("soak-supplies")
			var supplied := await replenish_supplies()
			deferred_supply_cycles = 0 if supplied else deferred_supply_cycles + 1
			check(deferred_supply_cycles < 10, "normal job cooldown cannot stall supplies for ten police cycles")
			if supplied:
				begin_phase("soak-police")
				await police_flow()
		if stop_cycles or failures > 0:
			break
		begin_phase("soak-checkpoint")
		_set_scenario_position(startup_position)
		check(await _wait_checkpoint(), "mixed cycle returns to a safe checkpoint")
		if not provider.can_checkpoint():
			break
		level.pause_exploring()
		var before: Variant = canonical(level.progression.snapshot_state())
		var count: int = level.traffic.player_fleet.size()
		check(provider.save_state() == OK, "normal provider writes test-profile checkpoint")
		var restored: Dictionary = provider.load_state()
		await frames(3)
		check(restored.get("ok", false) and canonical(level.progression.snapshot_state()) == before
			and level.traffic.player_fleet.size() == count, "cycle reload preserves durable wallet and vehicle uniqueness")
		level.resume_exploring()
		_assert_population_and_authority()
		completed_cycles += 1
		begin_phase("soak-cycle-boundary")
		await _settled_world_sample("boundary")
		await get_tree().create_timer(2.0, true, false, true).timeout
	# Release keys even when the deadline arrives halfway through a phase.
	await held_key(KEY_W, false)
	await held_key(KEY_SPACE, false)
	if level._dialogue.state.active:
		await key(KEY_ESCAPE)
	if level.shops.is_open():
		await key(KEY_ESCAPE)
	level.resume_exploring()
	begin_phase("soak-cycle-boundary")
	await _settled_world_sample("boundary")
	cycles_done = true

func _starter_pulse() -> void:
	var car: Node3D = level.driving.starter
	if not is_instance_valid(car):
		check(false, "starter remains present during mixed soak")
		return
	var size: Vector3 = level.driving._car_size(car)
	var door: Dictionary = {}
	for side in [-1.0, 1.0]:
		door = level.driving._exit_spot(car, side * (size.x * .5 + .65), .25, true)
		if not door.is_empty():
			break
	check(not door.is_empty(), "starter retains a supported clear door")
	if door.is_empty():
		return
	_set_scenario_position(door.position)
	await frames(8)
	await key(KEY_F)
	check(level.driving.active and level.driving.vehicle == car, "real F enters starter during soak")
	if not level.driving.active:
		return
	await held_key(KEY_W, true)
	await frames(20)
	await held_key(KEY_W, false)
	await held_key(KEY_SPACE, true)
	for step in 180:
		await frames(1)
		if absf(float(car.speed)) <= .1:
			break
	await held_key(KEY_SPACE, false)
	await key(KEY_F)
	check(not level.driving.active and player.seated_vehicle == null, "real brake/F exits without forcing collision clearance")

func _browse_shop() -> void:
	for definition in level.shops.definitions:
		var model: Node3D = level.shops.models[str(definition.id)]
		var at: Vector3 = model.to_global(model.get_meta("counter_local"))
		var spot := Facilities.standing_at(level.get_world_3d().direct_space_state, at, [player.get_rid()])
		if spot.is_empty():
			continue
		_set_scenario_position(spot.position)
		await frames(4)
		await key(KEY_E)
		check(level.shops.is_open(), "real E opens a shop in mixed cycle")
		await frames(3)
		_sample("modal-open", true)
		await key(KEY_ESCAPE)
		check(not level.shops.is_open() and not level.paused, "shop closes and normal simulation resumes")
		return
	check(false, "supported shop counter remains reachable")

func _browse_story() -> void:
	var before: Variant = canonical(level.missions.snapshot_state())
	for offer in level.missions.get_status().get("offers", []):
		if not await stand_near(offer.position, 1.8, true):
			continue
		await key(KEY_E)
		check(level._dialogue.state.active, "real E opens available mission contact dialogue")
		await frames(3)
		_sample("modal-open", true)
		await key(KEY_ESCAPE)
		check(canonical(level.missions.snapshot_state()) == before and not level.paused,
			"leaving dialogue neither grants rewards nor advances story")
		return
	check(false, "at least one authored mission contact remains available")
