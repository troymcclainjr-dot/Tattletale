extends Node
## Police cruisers in the real exported Pen Lucy world: the production level,
## its traffic fleet and lane network, residents, combat, law and save rules.
## Crew registration, save validation and lane routes are checked first; with
## the vehicle owner's external authority API, a real witness report then sends
## a real police car along the real lanes (continuously checked: on the
## carriageway, no hull overlap with buildings, cars or the player, at most two
## claims, one body per officer), its crew sees the player and gets out into a
## clear slot, and actual G input arrests the player, releasing every claim.
## Reset and an escape (walk back, re-enter, drive off, release) follow.
## The game's own loop runs; only the player and one temporary witness are
## placed. Headless runs never write the user's checkpoint.
## Run: python godot/tools/godot_run.py --timeout 600 -- --headless --script res://tests/city_police_world_smoke.gd
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const CREW := ["patrol_officer_cruiser_1", "patrol_officer_cruiser_2"]

var level: Node3D
var player: CharacterBody3D
var law: Node
var cruisers
var passes := 0
var failures := 0
var finished := false
var violations: Dictionary = {}
var watching := false
var witness: CharacterBody3D

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(600.0, true, false, true).timeout
	if not finished:
		check(false, "police world fixture completes within 600 s (including cold world boot)")
		_finish()

func check(ok: bool, label: String) -> bool:
	print("[police_world] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)
	return ok

func note(text: String) -> void:
	print("[police_world] NOTE " + text)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame
		if watching and Engine.get_physics_frames() % 6 == 0:
			_watch()

func until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await frames(1)
	return bool(condition.call())

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame

func space() -> PhysicsDirectSpaceState3D:
	return level.get_world_3d().direct_space_state

func owned(car) -> bool:
	var owner = car.get("external_owner") if is_instance_valid(car) else null
	return owner != null and not str(owner).is_empty()

func crew_entry(id: String) -> Dictionary:
	for entry in cruisers.crew:
		if str(entry.id) == id:
			return entry
	return {}

func first_unit() -> Dictionary:
	for unit in cruisers.units.values():
		return unit
	return {}

func _watch() -> void:
	var claimed := 0
	for car in level.traffic.vehicles:
		if not owned(car):
			continue
		claimed += 1
		if not level.traffic.network.on_road(car.global_position, 0.0):
			violations["off_road"] = "%s at %s" % [car.vehicle_id, car.global_position]
		var query := PhysicsShapeQueryParameters3D.new()
		query.collision_mask = 2 | 4 | 16
		query.margin = 0.0
		query.exclude = [car.get_rid()]
		for part in car.collision_parts:
			query.shape = part.shape
			query.transform = car.global_transform
			if not space().intersect_shape(query, 1).is_empty():
				violations["overlap"] = "%s overlaps a building, the player or a car at %s" % [car.vehicle_id, car.global_position]
				break
	if claimed > Cruisers.MAX_CRUISERS:
		violations["claims"] = "%d police cars claimed" % claimed
	for id in CREW:
		var actor = level.npcs.actors.get(id)
		var entry := crew_entry(id)
		if not is_instance_valid(actor) or entry.is_empty():
			violations["crew_missing"] = id
			continue
		var state := str(entry.state)
		if state in ["seated", "station"] and (actor.enabled or actor.visible or actor.collision_layer != 0):
			violations["crew_double"] = "%s is %s with a visible or physical body" % [id, state]
		if state == "foot" and not actor.enabled:
			violations["crew_ghost"] = id
		if state == "dead" and actor.enabled:
			violations["crew_resurrected"] = id

func section_clean(label: String) -> void:
	check(violations.is_empty(), "%s: claims, officer bodies, carriageway and hulls stay valid %s" % [label, str(violations)])
	violations.clear()

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	for index in 900:
		level = get_tree().current_scene as Node3D
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
	if level == null or level.get("level_ready") != true:
		check(false, "real exported level boots")
		_finish()
		return
	law = level.get("law")
	cruisers = law.get("cruisers") if law != null else null
	if not check(cruisers != null, "law composes its cruiser manager in the real level"):
		_finish()
		return
	level.resume_exploring()
	for index in 300:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	player = level.player
	check(not level.world_save.enabled, "headless validation never writes the player's checkpoint")
	_registry_section()
	_routes_section()
	var status: Dictionary = law.get_status().cruisers
	if not check(bool(status.available), "cruisers are available in the real world (%s)" % str(status.reason)):
		note("vehicle authority API or police fleet missing; behaviour sections skipped")
		_finish()
		return
	# Production timing scaled down for the fixture; the logic is unchanged.
	law.report_delay_min = 0.6
	law.report_delay_max = 1.0
	law.lost_sight_seconds = 1.5
	law.search_seconds = [3.0, 4.0, 4.0, 4.0]
	law.cooldown_seconds = [0.0, 3.0, 3.0, 3.0]
	law.stage_seconds = {"down": 0.5, "hands_up": 0.5, "fade_out": 0.4, "fade_in": 0.4}
	law.use_level_notices = false
	watching = true
	await _sighting_and_arrest_section()
	await _reset_section()
	await _escape_section()
	watching = false
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	_drop_witness()
	print("[police_world] %d passed; %d failed" % [passes, failures])
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

# --------------------------------------------------------------- static checks

func _registry_section() -> void:
	var actors: Dictionary = level.npcs.actors
	for id in CREW:
		var actor = actors.get(id)
		check(is_instance_valid(actor) and actor is Actor and not actor.enabled and not actor.visible and actor.collision_layer == 0,
			"%s is a registered, seated (hidden, collider-free) officer identity" % id)
	# The persistence rule: a recorded death must name a registered identity.
	var verdict := str(level.world_save._validate_deaths({"version": 1, "dead": [CREW[0], CREW[1]]}))
	check(verdict.is_empty(), "a checkpoint recording dead cruiser officers validates (%s)" % verdict)
	var status: Dictionary = law.get_status()
	check(status.has("cruisers") and int(status.responder_count) <= law.MAX_RESPONDERS and not bool(status.busy),
		"law status carries a cruisers section and stays idle at boot")
	check(int(status.cruisers.get("police_cars", 0)) >= 2, "the real fleet provides police cars (%d)" % int(status.cruisers.get("police_cars", 0)))

func _routes_section() -> void:
	var router = cruisers.lanes
	var network = level.traffic.network
	var enabled := int(network.get_status().enabled_lanes)
	check(router.lane_count() == enabled and enabled >= 60, "the cruiser router covers every enabled real lane (%d)" % enabled)
	var planned := 0
	var off_road := 0
	var longest := 0.0
	for car in cruisers._police_cars():
		var lane := int(car.lane_id)
		if not router.has_lane(lane):
			continue
		for goal in [player.global_position, level.traffic.road_points[0], level.traffic.road_points[-1]]:
			var plan: Dictionary = router.plan(car.global_position, Cruisers.forward_of(car), goal, lane, -1.0)
			if not bool(plan.ok):
				continue
			planned += 1
			longest = maxf(longest, float(plan.length))
			for point in plan.points:
				off_road += int(not network.on_road(point, 0.3))
	check(planned >= 3, "real police cars get lane routes to the spawn and both Old York ends (%d plans, longest %.0f m)" % [planned, longest])
	check(off_road == 0, "every routed sample lies on the real carriageway (%d off)" % off_road)

# --------------------------------------------------------------- behaviour

## A sidewalk spot about `ahead` metres along the car's lane, clear for the
## player's capsule and off the carriageway.
func _spot_ahead_of(car: Node3D, ahead: float) -> Vector3:
	var router = cruisers.lanes
	var lane := int(car.lane_id)
	if not router.has_lane(lane):
		return Vector3.INF
	var points: Array[Vector3] = level.traffic.network.lanes[lane].points
	var along := minf(float(router.project(lane, car.global_position).along) + ahead, router.lane_length(lane) - 4.0)
	var base: Vector3 = level.traffic.network.point_at(points, along)
	var tangent: Vector3 = (level.traffic.network.point_at(points, along + 1.0) - base)
	tangent.y = 0.0
	tangent = tangent.normalized()
	var side := Vector3(tangent.z, 0.0, -tangent.x)
	var skip: Array[RID] = [player.get_rid()]
	for lateral in [6.5, -6.5, 8.0, -8.0, 10.0, -10.0]:
		var at: Vector3 = base + side * float(lateral)
		if level.traffic.network.on_road(at, -0.6):
			continue
		var standing := Facilities.standing_at(space(), at, skip)
		if not standing.is_empty():
			return standing.position
	return Vector3.INF

func _place_player(at: Vector3, facing: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = atan2(facing.x, facing.z)
	if player.has_method("reset_physics_interpolation"):
		player.reset_physics_interpolation()
	level.set("_safe_position", at)

func _spawn_witness(at: Vector3, toward: Vector3) -> void:
	_drop_witness()
	witness = Actor.new()
	level.npcs.add_child(witness)
	witness.build(level, "fixture_police_witness", "mama", "Neighbor")
	witness.global_position = at
	witness.yaw = atan2(toward.x - at.x, toward.z - at.z)
	witness.puppet.g.rotation.y = witness.yaw
	level.npcs.actors["fixture_police_witness"] = witness

func _drop_witness() -> void:
	if is_instance_valid(witness):
		level.npcs.actors.erase("fixture_police_witness")
		witness.queue_free()
	witness = null

## A witness's call about a visible offender: a real police car is claimed,
## drives the real lanes, its crew sees the player, an officer gets out into a
## clear slot, and actual G input arrests the player, releasing every claim.
func _sighting_and_arrest_section() -> void:
	law.reset_state()
	level.combat.recover_player()
	var car: Node3D = null
	var best := INF
	for candidate in cruisers._police_cars():
		if cruisers._eligible(candidate) and int(candidate.lane_id) >= 0:
			var distance: float = candidate.global_position.distance_to(player.global_position)
			if distance < best:
				best = distance
				car = candidate
	if not check(car != null, "an eligible real police car is in traffic"):
		return
	var spot := _spot_ahead_of(car, 45.0)
	if not check(spot.is_finite(), "a clear sidewalk spot lies ahead of %s" % str(car.vehicle_id)):
		return
	_place_player(spot, car.global_position - spot)
	await frames(3)
	_spawn_witness(spot + (car.global_position - spot).normalized().rotated(Vector3.UP, 1.2) * 3.0, spot)
	await frames(3)
	law.on_offense("assault", spot + Vector3.UP * 0.5, "")
	var wanted: bool = await until(func(): return law.wanted > 0, 4.0)
	check(wanted, "the witness's call files and identifies the offender")
	_drop_witness()
	var claimed: bool = await until(func(): return cruisers.claimed_count() > 0, 4.0)
	if not check(claimed, "a real police car is claimed under external authority"):
		return
	var unit := first_unit()
	var cruiser: Node3D = unit.car
	var start: Vector3 = cruiser.global_position
	check(bool(cruiser.get_meta("police_emergency", false)) and str(cruiser.get("external_owner")).begins_with(Cruisers.OWNER_PREFIX),
		"the claimed car carries the police unit and emergency state")
	var out: bool = await until(func(): return str(first_unit().get("mode", "")) == "dismounted", 40.0)
	check(cruiser.global_position.distance_to(start) > 5.0, "the cruiser actually drove (%.1f m)" % cruiser.global_position.distance_to(start))
	check(int(cruisers.counters.sightings) >= 1, "its crew saw the player with its own ray")
	if not check(out, "the officer gets out near the player"):
		return
	var crew: CharacterBody3D = level.npcs.actors[CREW[int(first_unit().crew)]]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = crew.capsule.shape
	query.transform = crew.global_transform * crew.capsule.transform
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = [crew.get_rid()]
	check(crew.enabled and crew.visible and space().intersect_shape(query, 1).is_empty() and crew.global_position.distance_to(cruiser.global_position) < 3.8,
		"the officer stands beside the car in a clear capsule-checked spot")
	var ready: bool = await until(func(): return bool(law.get_status().surrender_available), 10.0)
	if not check(ready, "an officer on foot can take the surrender"):
		return
	var arrests: int = law.arrests
	await key(KEY_G)
	check(law.recovering, "actual G input starts the arrest")
	var done: bool = await until(func(): return not law.recovering, 8.0)
	await frames(10)
	var free := true
	for vehicle in level.traffic.vehicles:
		free = free and not owned(vehicle)
	check(done and law.arrests == arrests + 1, "the arrest completes once")
	check(free and cruisers.claimed_count() == 0 and not crew.enabled and not cruiser.has_meta("police_emergency"),
		"after relocation every police claim is released and the officer is seated again")
	section_clean("sighting and arrest")

## Reset ends a live response at once: no claims, every officer seated.
func _reset_section() -> void:
	law.reset_state()
	level.combat.recover_player()
	var car: Node3D = null
	for candidate in cruisers._police_cars():
		if cruisers._eligible(candidate) and int(candidate.lane_id) >= 0:
			car = candidate
			break
	if car == null:
		note("no eligible police car for the reset check")
		return
	var spot := _spot_ahead_of(car, 40.0)
	if not spot.is_finite():
		note("no sidewalk spot for the reset check")
		return
	_place_player(spot, car.global_position - spot)
	await frames(3)
	_spawn_witness(spot + Vector3(2.5, 0, 2.5), spot)
	await frames(3)
	law.on_offense("assault", spot + Vector3.UP * 0.5, "")
	await until(func(): return cruisers.claimed_count() > 0, 6.0)
	_drop_witness()
	await frames(60)
	law.reset_state()
	await frames(2)
	var seated := true
	for id in CREW:
		var entry := crew_entry(id)
		seated = seated and (str(entry.state) in ["station", "dead"] or level.npcs.actors[id].get("combat_override") == true)
	check(cruisers.claimed_count() == 0 and seated and law.wanted == 0, "reset releases every claim and re-seats every officer at once")
	section_clean("reset")

## An escape: the player leaves for somewhere no officer can see. The cruiser
## searches the last known spot only, the incident cools down, its officer
## walks back and gets in, and the car drives off before it is released.
func _escape_section() -> void:
	law.reset_state()
	level.combat.recover_player()
	var car: Node3D = null
	for candidate in cruisers._police_cars():
		if cruisers._eligible(candidate) and int(candidate.lane_id) >= 0:
			car = candidate
			break
	if car == null:
		note("no eligible police car for the escape check")
		return
	var spot := _spot_ahead_of(car, 50.0)
	var refuge := _far_refuge(spot)
	if not spot.is_finite() or not refuge.is_finite():
		note("no spot/refuge pair for the escape check")
		return
	_place_player(spot, car.global_position - spot)
	await frames(3)
	_spawn_witness(spot + Vector3(-2.5, 0, 2.5), spot)
	await frames(3)
	law.on_offense("assault", spot + Vector3.UP * 0.5, "")
	await until(func(): return law.wanted > 0, 4.0)
	_drop_witness()
	_place_player(refuge, Vector3.FORWARD)
	var known: Vector3 = law.last_known_position
	var leaks := {"value": false}
	var cooled := func() -> bool:
		var unit := first_unit()
		if not unit.is_empty() and Vector3(unit.goal).distance_to(refuge) < 10.0:
			leaks.value = true
		return law.wanted == 0
	var escaped: bool = await until(cooled, 90.0)
	check(Vector3(known).distance_to(spot) < 3.0 and not bool(leaks.value), "the response used only the reported position, never the refuge")
	check(escaped, "with nobody seeing the player the incident cools down")
	var released: bool = await until(func(): return cruisers.claimed_count() == 0, 60.0)
	check(released and int(cruisers.counters.releases) >= 1, "the cruiser drives off and is released after its officer gets back in")
	section_clean("escape")

## A standing spot far (120 m+, over twice any sight range) from the scene and
## from every police officer and police car.
func _far_refuge(from: Vector3) -> Vector3:
	var watchers: Array[Vector3] = []
	for actor in level.npcs.actors.values():
		if is_instance_valid(actor) and law._is_police(actor):
			watchers.append(actor.global_position)
	for car in cruisers._police_cars():
		watchers.append(car.global_position)
	var skip: Array[RID] = [player.get_rid()]
	for road in level.level_data.get("roads", []):
		for value in road.get("points", []):
			var point: Vector3 = level.vector(value)
			if from.is_finite() and point.distance_to(from) < 120.0:
				continue
			var clear := true
			for watcher in watchers:
				clear = clear and watcher.distance_to(point) > 120.0
			if not clear:
				continue
			for lateral in [7.0, -7.0, 9.0, -9.0]:
				var standing := Facilities.standing_at(space(), point + Vector3(lateral, 0, 0), skip)
				if not standing.is_empty():
					return standing.position
	return Vector3.INF
