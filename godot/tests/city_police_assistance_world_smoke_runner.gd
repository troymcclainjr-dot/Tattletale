extends "res://tests/city_priorities_session_fixture.gd"
## Actual phone -> incident -> real traffic cruiser -> physical crew arrival.
## Only the caller is arranged before dispatch. No responder/car is teleported,
## no route/state is forced, and the production world loop runs every frame.
const CruiserScript := preload("res://scripts/city/city_police_cruisers.gd")
const RESPONSE_SECONDS := 90.0
const MAX_CANDIDATES := 180
const MAX_PLAN_CHECKS := 32
var assistance: Node3D
var cruisers: RefCounted
var call_at := Vector3.INF
var incident_id := ""
var trace: FileAccess
var tracked_cars: Dictionary = {}
var tracked_officers: Dictionary = {}
var violations: Dictionary = {}
var physical_arrival := false
var arrival_officer := ""
var arrival_frame := -1
var response_frame := 0

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	begin_phase("select-real-distant-phone-call")
	assistance = level.get("police_assistance")
	cruisers = level.law.get("cruisers")
	check(assistance != null and cruisers != null and bool(cruisers.get("available")), "real assistance service and traffic cruisers are available")
	if assistance == null or cruisers == null or not bool(cruisers.get("available")):
		_finish()
		return
	check(not assistance.is_busy() and int(level.law.wanted) == 0, "quiet initial world has no player warrant or existing response")
	var scenario := _choose_distant_call()
	check(not scenario.is_empty(), "surveyed sidewalk call beyond foot-dispatch preference has a bounded real lane route")
	if scenario.is_empty():
		result_details["selection_failure"] = {"cruisers": cruisers.get_status(), "patrols": assistance._patrols.size()}
		_finish()
		return
	call_at = scenario.position
	result_details["selected_scenario"] = scenario
	_set_scenario_position(call_at)
	level.resume_exploring()
	await frames(3)
	var health_before := float(level.combat.health)
	var requests_before := int(assistance.counters.requests)
	var dispatches_before := int(assistance.counters.cruiser_dispatches)
	for car in cruisers._police_cars():
		tracked_cars[str(car.vehicle_id)] = {"body": car, "origin": car.global_position,
			"previous": car.global_position, "claimed": false, "distance": 0.0,
			"max_step": 0.0, "max_odometer": 0.0, "path_samples": 0, "dismounted": false}
	trace = FileAccess.open(output_dir.path_join("assistance-trace.jsonl"), FileAccess.WRITE)
	check(trace != null, "project-local response trace opened")
	begin_phase("real-phone-dispatch")
	await key(KEY_P)
	check(player.phone.active, "P opens the real phone")
	await key(KEY_5)
	check(str(player.phone.page) == "police", "5 selects the actual police-call page")
	await key(KEY_ENTER)
	check(int(assistance.counters.requests) == requests_before + 1, "Enter sends exactly one real phone request through the level signal")
	for incident in assistance.incidents:
		if str(incident.source) == "phone" and _flat(incident.at, call_at) < 1.0:
			incident_id = str(incident.id)
			check(incident.suspects.is_empty(), "quiet caller is not fabricated into a suspect")
	check(not incident_id.is_empty() and int(assistance.counters.cruiser_dispatches) > dispatches_before, "distant phone request claims a real cruiser rather than accepting a foot-only substitute")
	# Leave the caller standing still; keep the phone open without changing time.
	# Physical evidence is captured every normal world physics frame.
	begin_phase("real-cruiser-and-officer-arrival")
	var start_frame := Engine.get_physics_frames()
	var budget := ceili(RESPONSE_SECONDS * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() - start_frame < budget:
		await frames(1)
		response_frame = Engine.get_physics_frames() - start_frame
		_observe()
		if response_frame % Engine.physics_ticks_per_second == 0:
			_write_trace()
		if physical_arrival:
			break
	_write_trace()
	check(physical_arrival, "real cruiser crew walks within 3 m of the call and service records arrival within 90 simulated seconds")
	var driven := false
	var dismounted := false
	for id in tracked_cars:
		var row: Dictionary = tracked_cars[id]
		if not bool(row.claimed):
			continue
		driven = driven or (float(row.distance) > 12.0 and float(row.max_odometer) > 8.0 and int(row.path_samples) >= 2)
		dismounted = dismounted or bool(row.dismounted)
	check(driven, "a claimed fleet cruiser physically traverses its surveyed lane route, with real odometer progress")
	check(dismounted and int(cruisers.assist_counters.dismounts) > 0, "a real cruiser crew dismounts through the production checked-door path")
	check(violations.is_empty(), "continuous response has no teleport, off-road excursion, caller target, or budget violation: %s" % str(violations))
	check(int(level.law.wanted) == 0 and float(level.combat.health) >= health_before - 0.01 and int(assistance.counters.rounds) == 0,
		"a quiet phone call never criminalizes, shoots, arrests, or hurts the caller")
	check(level.traffic.vehicles.size() == 90 and level.is_physics_processing() and player.is_physics_processing(), "full traffic population and normal world/player processing remain enabled")
	var car_evidence := {}
	for id in tracked_cars:
		var row: Dictionary = tracked_cars[id].duplicate()
		row.erase("body")
		car_evidence[id] = row
	result_details["real_assistance"] = {"simulated_seconds": float(response_frame) / Engine.physics_ticks_per_second,
		"call": call_at, "incident": incident_id, "arrival_officer": arrival_officer, "arrival_frame": arrival_frame,
		"cars": car_evidence, "officers": tracked_officers, "violations": violations,
		"assistance": assistance.get_status(), "cruisers": cruisers.get_status(), "trace": output_dir.path_join("assistance-trace.jsonl")}
	if trace != null:
		trace.flush()
		trace = null
	_finish()

## Read-only selection on current road geometry and current real patrol/car
## positions. Match the dispatcher's mobile-first nearest-car preference.
func _choose_distant_call() -> Dictionary:
	var network = level.traffic.network
	var router = cruisers.lanes
	var best := {}
	var best_length := INF
	var checked := 0
	var planned := 0
	var enabled_lanes: Array = []
	for lane in network.lanes:
		if bool(lane.get("enabled", false)) and router.has_lane(int(lane.id)):
			enabled_lanes.append(lane)
	# Spread the bounded geometry probes over the entire directed network.
	var lane_samples := mini(enabled_lanes.size(), floori(float(MAX_CANDIDATES) / 12.0))
	for sample_index in lane_samples:
		var lane: Dictionary = enabled_lanes[floori(float(sample_index) * enabled_lanes.size() / lane_samples)]
		var length := float(router.lane_length(int(lane.id)))
		for fraction in [0.25, 0.5, 0.75]:
			var along := clampf(length * float(fraction), 4.0, maxf(4.0, length - 4.0))
			var base: Vector3 = network.point_at(lane.points, along)
			var heading: Vector3 = network.point_at(lane.points, minf(length, along + 1.0)) - base
			heading.y = 0.0
			if heading.length_squared() < 0.01:
				continue
			heading = heading.normalized()
			var side := Vector3(heading.z, 0.0, -heading.x)
			for lateral in [6.5, -6.5, 8.0, -8.0]:
				checked += 1
				if checked > MAX_CANDIDATES or planned >= MAX_PLAN_CHECKS:
					return best
				var wanted := base + side * float(lateral)
				if network.on_road(wanted, -0.6):
					continue
				var foot: Array = assistance._foot_candidates(wanted)
				var foot_distance := float(foot[0].distance) if not foot.is_empty() else 999.0
				if foot_distance < float(assistance.CRUISER_PREFERRED_DISTANCE) + 15.0:
					continue
				var standing := Facilities.standing_at(level.get_world_3d().direct_space_state, wanted, [player.get_rid()])
				if standing.is_empty():
					continue
				var car = _expected_dispatch_car(standing.position)
				if car == null or _flat(car.global_position, standing.position) < 30.0:
					continue
				planned += 1
				var plan: Dictionary = router.plan(car.global_position, CruiserScript.forward_of(car), standing.position, int(car.lane_id), -1.0)
				if not bool(plan.ok) or float(plan.length) < 30.0 or float(plan.length) > 240.0 or float(plan.length) >= best_length:
					continue
				var road_ok := true
				for point in plan.points:
					if not network.on_road(point, 0.4):
						road_ok = false
						break
				if not road_ok:
					continue
				best_length = float(plan.length)
				best = {"position": standing.position, "nearest_free_foot_metres": foot_distance,
					"expected_car": str(car.vehicle_id), "car_start": car.global_position,
					"plan_length": plan.length, "route_samples": plan.points.size(), "goal_lane": plan.goal_lane,
					"candidates_checked": checked, "plans_checked": planned}
	return best

func _expected_dispatch_car(goal: Vector3):
	var best = null
	var best_distance := float(cruisers.DISPATCH_RADIUS)
	var best_mobile := false
	for car in cruisers._police_cars():
		if not cruisers._eligible(car):
			continue
		var distance := _flat(car.global_position, goal)
		if distance >= float(cruisers.DISPATCH_RADIUS):
			continue
		var mobile: bool = cruisers._dispatch_mobile(car)
		if best == null or (mobile and not best_mobile) or (mobile == best_mobile and distance < best_distance):
			best = car
			best_mobile = mobile
			best_distance = distance
	return best

func _observe() -> void:
	if int(level.law.wanted) > 0 or bool(level.law.recovering):
		violations.caller_criminalized = response_frame
	if cruisers.units.size() > int(cruisers.MAX_CRUISERS) or assistance._officers.size() > int(assistance.MAX_OFFICERS):
		violations.budget = response_frame
	for unit in cruisers.units.values():
		if not str(unit.get("assist", "")).begins_with(incident_id + ":"):
			continue
		var id := str(unit.vehicle_id)
		if not tracked_cars.has(id):
			violations.not_original_fleet = id
			continue
		var row: Dictionary = tracked_cars[id]
		var car: Node3D = unit.car
		var step := _flat(row.previous, car.global_position)
		if bool(row.claimed):
			row.max_step = maxf(float(row.max_step), step)
			row.distance += step
			if step > 3.0:
				violations.car_teleport = {"id": id, "metres": step}
		row.previous = car.global_position
		row.claimed = true
		row.max_odometer = maxf(float(row.max_odometer), float(unit.odometer))
		row.path_samples = maxi(int(row.path_samples), unit.path.size())
		row.dismounted = bool(row.dismounted) or str(unit.mode) == "dismounted"
		if not level.traffic.network.on_road(car.global_position, 0.4):
			violations.car_off_road = {"id": id, "position": car.global_position}
	for officer in assistance._officers.values():
		if str(officer.incident) != incident_id:
			continue
		if str(officer.target) in ["player", "two_pack"]:
			violations.targeted_caller = str(officer.id)
		if str(officer.kind) != "crew":
			continue
		var actor: Node3D = officer.actor
		var id := str(officer.id)
		if not tracked_officers.has(id):
			tracked_officers[id] = {"first_position": actor.global_position, "previous": actor.global_position,
				"walked": 0.0, "max_step": 0.0, "minimum_call_distance": INF}
		var row: Dictionary = tracked_officers[id]
		var step := _flat(row.previous, actor.global_position)
		row.previous = actor.global_position
		row.walked += step
		row.max_step = maxf(float(row.max_step), step)
		row.minimum_call_distance = minf(float(row.minimum_call_distance), _flat(actor.global_position, call_at))
		if step > 0.65:
			violations.officer_teleport = {"id": id, "metres": step}
		if not actor.get("enabled") or not actor.visible or int(actor.get("collision_layer")) == 0:
			violations.invisible_officer = id
		if float(row.minimum_call_distance) <= 3.0 and float(row.walked) > 0.5 and int(assistance.counters.arrivals) > 0:
			physical_arrival = true
			arrival_officer = id
			arrival_frame = response_frame

func _write_trace() -> void:
	if trace != null:
		trace.store_line(JSON.stringify({"frame": response_frame, "seconds": float(response_frame) / Engine.physics_ticks_per_second,
			"assistance": assistance.get_status(), "cruisers": cruisers.get_status(), "violations": violations}))
		trace.flush()

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
