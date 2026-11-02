extends "res://tests/city_priorities_session_fixture.gd"
## Incident aftermath in the actual imported city: full 1200/40/90 population,
## normal root ticks, the real Cator–Elkader Hospital and the real traffic lane
## network. Arranged through APIs only: where the explorer stands, one witnessed
## incident naming a free crowd neighbor, the injury combat would have reported
## (note_injury) and the explorer's phone report. Everything after that is
## production behavior: police dispatch, the ambulance leaving its home, driving
## the lanes, stopping, the paramedics' walk and treatment beside the person, the
## crew boarding, the street clearing and the return. A second response is then
## interrupted by a private checkpoint save and load (never a personal slot).
## Failures stay failures; the honest outcome text is recorded either way.
## Root runs it (the aftermath worker runs no engine):
##   godot --headless --path godot --script res://tests/city_emergency_city_session.gd -- --session-run-id=<id>
##   (rendered: add --offscreen-validation)
## Output: .work/next-five-20261101/aftermath-city-<id>/result.json
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const EmergencyStatus := preload("res://scripts/city/city_emergency_status.gd")
const PoliceStatus := preload("res://scripts/city/city_police_status.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
## Road distances from the hospital at which a scene is looked for, in order.
const SCENE_ROUTE := [180.0, 260.0, 120.0, 360.0]
const LIFECYCLE_SECONDS := 330.0
const SECOND_RESPONSE_SECONDS := 90.0
var incidents: Node3D
var ems: Node3D
var violations: Dictionary = {}
var max_frame_step := 0.0
var off_road_samples: Array = []
var overlap_samples: Array = []
var lane_samples := 0
var first_patient := ""
var crew_trace: Array = []
var _crew_probe_clock := -INF
var _crew_probe_tag := ""
var return_trace: Array = []
var _return_probe_keys: Dictionary = {}

func _watchdog() -> void:
	await get_tree().create_timer(1800.0, true, false, true).timeout
	if not finished:
		check(false, "aftermath city session completes within 1800 s")
		_finish()

func violation(kind: String, detail: String) -> void:
	if not violations.has(kind):
		violations[kind] = detail
		print("[aftermath_city] VIOLATION %s: %s" % [kind, detail])

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/next-five-20261101/aftermath-city-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	result_details.scope = "Actual city, full population and traffic, normal root ticks. API-arranged: explorer position, one witnessed incident naming a free crowd neighbor, its injury and the explorer's phone report; the rest is production behavior. Private fixture checkpoint only."
	player.phone.close()
	level.basketball.suspend(true)
	level.resume_exploring()
	incidents = level.get("incidents")
	ems = incidents.get("emergency") if incidents != null else null
	begin_phase("hospital-base")
	if not await _base_checks():
		_finish()
		return
	begin_phase("route-probes")
	_route_probes()
	begin_phase("treated-lifecycle")
	await _lifecycle()
	if OS.get_cmdline_user_args().has("--ems-crew-probe-only") or OS.get_cmdline_user_args().has("--ems-return-probe-only") or OS.get_cmdline_user_args().has("--ems-hull-probe-only"):
		_finish()
		return
	begin_phase("checkpoint-interruption")
	await _interruption()
	begin_phase("population")
	result_details.violations = violations
	check(violations.is_empty(), "no lifecycle invariant was violated: %s" % str(violations))
	check(int(level.npcs.crowd.get_status().total) == 1200 and int(level.residents.get_status().count) == 40 and level.traffic.vehicles.size() == 90,
		"full 1200 ambient / 40 daily / 90 traffic population retained")
	check(level.is_physics_processing() and player.is_physics_processing(), "normal world and player processing retained")
	_finish()

# --------------------------------------------------------------- base

func _base_checks() -> bool:
	check(ems != null and ems.get_parent() == incidents, "the incident service created the emergency service")
	if ems == null:
		return false
	var status: Dictionary = ems.get_status()
	result_details.base = status.get("base", {})
	result_details.base_reason = str(ems.reason)
	check(bool(ems.available), "the hospital's ambulance is available (%s; %s)" % [str(ems.reason), str((status.get("base", {}) as Dictionary).get("report", []))])
	if not bool(ems.available):
		return false
	var hospital: Node3D = Facilities.model(level, "hospital")
	var home: Dictionary = ems.base.home
	var at: Vector3 = ems.ambulance.global_position
	result_details.home = {"kind": str(home.kind), "position": [at.x, at.y, at.z],
		"standby": not (ems.base.get("curb", {}) as Dictionary).is_empty()}
	check(hospital != null and flat_distance(at, hospital.global_position) < 45.0,
		"the ambulance starts at Cator–Elkader Hospital (%s home, %.1f m from its centre)" % [str(home.kind), flat_distance(at, hospital.global_position) if hospital != null else INF])
	check(ems.ambulance.visible and ems.ambulance.collision_layer == 16 and str(ems.unit.mode) == "parked", "it stands parked, visible and solid")
	check(not level.traffic.emergency_vehicles.has(ems.ambulance), "parked at home it is not a traffic obstacle")
	for id in Emergency.CREW_IDS:
		var actor = level.npcs.actors.get(id)
		check(is_instance_valid(actor) and not actor.enabled and not actor.visible and actor.collision_layer == 0,
			"%s is a registered identity, seated" % id)
	check(str(level.world_save.checkpoint_blocker()).is_empty(), "the medical service never blocks a checkpoint")
	# Stand nearby so parked cars and civic vehicles there have live colliders,
	# then sweep the chosen home geometry independently of setup's own check.
	var space := level.get_world_3d().direct_space_state
	var near := _standing_near(at, [12.0, 16.0, 20.0, 26.0])
	if not near.is_empty():
		_set_scenario_position(near.position)
		await frames(45)
	check(ems.driver.pose_clear(ems.ambulance.global_transform), "its parked hull overlaps nothing: buildings, props, people or cars")
	if str(home.kind) == "bay":
		var lead: PackedVector3Array = (home.exit as Dictionary).lead
		var bad := _sweep(lead, false)
		result_details.exit_lead = {"length": float(home.exit.lead_length), "points": lead.size(), "blocked": bad}
		check(bad.is_empty(), "the canopy approach to the street is grounded and clear every metre (%s)" % str(bad))
	var curb: Dictionary = ems.base.get("curb", {})
	if not curb.is_empty():
		var pull_in: PackedVector3Array = curb.pull_in
		var bad_curb := _sweep(pull_in, true)
		result_details.standby = {"shift": float(curb.shift), "blocked": bad_curb}
		check(bad_curb.is_empty(), "the curbside standby pull-in stays on the carriageway and clear (%s)" % str(bad_curb))
	return true

## Static re-validation of a stretch: support every metre, hull clear of
## buildings, props and cars (live colliders), whole hull on the carriageway.
func _sweep(points: PackedVector3Array, require_road: bool) -> Array:
	var bad: Array = []
	var sums := Lanes.cumulative(points)
	var reference := points[0].y + 1.2 if not points.is_empty() else 0.0
	ems.driver.reset_ground()
	for i in points.size():
		var direction := Driver.direction_at(points, sums, sums[i])
		if direction == Vector3.ZERO:
			continue
		var heading := atan2(direction.x, direction.z)
		var ground: Dictionary = ems.driver.ground_pose(points[i], heading, reference, false)
		if ground.is_empty():
			bad.append("no support at %d" % i)
		else:
			var pose: Transform3D = ground.transform
			reference = pose.origin.y
			if not ems.driver.pose_clear(pose, 2 | 16):
				bad.append("hull touches a structure or car at %d (%s)" % [i, str(pose.origin)])
			if require_road:
				for corner in [Vector3(-1.06, 0, -2.35), Vector3(-1.06, 0, 2.35), Vector3(1.06, 0, -2.35), Vector3(1.06, 0, 2.35)]:
					if not level.traffic.on_road(pose * corner):
						bad.append("off the carriageway at %d" % i)
						break
		if bad.size() >= 5:
			break
	return bad

func _standing_near(center: Vector3, radii: Array) -> Dictionary:
	var space := level.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	for radius in radii:
		for turn in 12:
			var angle := float(turn) * TAU / 12.0
			var spot := Facilities.standing_at(space, center + Vector3(sin(angle), 0.0, cos(angle)) * float(radius), exclude)
			if not spot.is_empty():
				return spot
	return {}

# --------------------------------------------------------------- routes

func _route_probes() -> void:
	var goals: Array[Vector3] = [startup_position]
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		if points.size() >= 2:
			goals.append(point(points[int(points.size() * 0.5)]))
		if goals.size() >= 9:
			break
	var probes: Array = []
	var ok := 0
	for goal in goals:
		var plan: Dictionary = ems._plan_route(goal)
		ok += int(bool(plan.get("ok", false)))
		probes.append({"goal": [goal.x, goal.y, goal.z], "ok": bool(plan.get("ok", false)),
			"length": float(plan.get("length", 0.0)), "reason": str(plan.get("reason", ""))})
	result_details.route_probes = probes
	check(ok >= ceili(goals.size() * 0.75), "road routes plan from the hospital to most of the neighborhood (%d/%d)" % [ok, goals.size()])
	var home: Dictionary = ems._plan_home()
	result_details.home_route = {"ok": bool(home.get("ok", false)), "length": float(home.get("length", 0.0)), "reason": str(home.get("reason", ""))}
	check(bool(home.get("ok", false)), "a way back to the hospital plans from its own home (%s)" % str(home.get("reason", "")))

# --------------------------------------------------------------- lifecycle

## A free crowd neighbor beside a lane some road distance from the hospital,
## with the explorer standing nearby so that cell is live.
func _find_patient(exclude_id := "") -> Dictionary:
	var home: Dictionary = ems.base.home
	var lane := -1
	var along := 0.0
	if str(home.kind) == "bay":
		lane = int(home.exit.lane)
		along = float(home.exit.along)
	else:
		lane = int(home.curb.lane)
		along = float(home.curb.along)
	var tried: Array = []
	for distance in SCENE_ROUTE:
		var plan: Dictionary = ems.lanes.continuation(lane, along, Vector3.ZERO, float(distance))
		if not bool(plan.get("ok", false)):
			tried.append({"distance": distance, "reason": str(plan.get("reason", ""))})
			continue
		var points: PackedVector3Array = plan.points
		var end: Vector3 = points[points.size() - 1]
		var spot := _standing_near(end, [6.0, 8.0, 10.0, 12.0])
		if spot.is_empty():
			tried.append({"distance": distance, "reason": "no standing spot near the lane end"})
			continue
		_set_scenario_position(spot.position)
		await frames(60)
		var found := _free_resident_near(player.global_position, 45.0, exclude_id)
		tried.append({"distance": distance, "end": [end.x, end.y, end.z], "found": not found.is_empty()})
		if not found.is_empty():
			result_details["patient_search_" + ("second" if not exclude_id.is_empty() else "first")] = tried
			return found
	result_details["patient_search_" + ("second" if not exclude_id.is_empty() else "first")] = tried
	return {}

func _free_resident_near(center: Vector3, radius: float, exclude_id := "") -> Dictionary:
	var crowd = level.npcs.crowd
	var best: Dictionary = {}
	var other := ""
	for index in crowd.residents.size():
		var resident: Dictionary = crowd.residents[index]
		var at: Vector3 = resident.position
		if flat_distance(at, center) > radius or "crowd_%d" % index == exclude_id or not incidents._crowd_free(resident):
			continue
		if ems.lanes.nearest(at, Vector3.ZERO, 25.0, -2.0, 1).is_empty():
			continue
		if best.is_empty() or flat_distance(at, center) < flat_distance(Vector3(best.position), center):
			if not best.is_empty():
				other = str(best.id)
			best = {"id": "crowd_%d" % index, "index": index, "position": at}
		elif other.is_empty():
			other = "crowd_%d" % index
	if best.is_empty():
		return {}
	best.offender = other if not other.is_empty() else "crowd_%d" % ((int(best.index) + 600) % crowd.residents.size())
	return best

func _lifecycle() -> void:
	var scene: Dictionary = await _find_patient()
	check(not scene.is_empty(), "a free crowd neighbor beside a reachable street is found near a test scene")
	if scene.is_empty():
		return
	first_patient = str(scene.id)
	var patient := first_patient
	var crowd = level.npcs.crowd
	var opened: Dictionary = incidents.open_incident({"template": "street_fight", "at": scene.position, "offender_id": str(scene.offender),
		"victim_id": patient, "source": "external:aftermath-city-fixture"})
	var id := str(opened.get("incident_id", ""))
	check(bool(opened.get("ok", false)), "a witnessed incident naming the neighbor opens (%s)" % id)
	if id.is_empty():
		return
	incidents.note_observation(id, "player", {})
	check(incidents.note_injury(id, patient, "knocked_down"), "the injury names the neighbor as the record's patient")
	var notices: Array = []
	var listener := func(status: Dictionary) -> void:
		if str(status.get("incident_id", "")) == id and str(status.get("status", "")) == "medical":
			notices.append({"text": str(status.get("text", "")), "phone": bool(status.get("phone", false)), "stage": str(status.get("medical_stage", ""))})
	incidents.report_status_changed.connect(listener)
	var reply: Dictionary = incidents.report_incident(id, "player", {"channel": "phone", "phone": true})
	check(bool(reply.get("ok", false)), "the explorer's phone report is accepted (%s)" % str(reply.get("message", "")))
	var start_odometer := float(ems.driver.odometer)
	var stages: Array = []
	var trace: Array = []
	var arrival: Dictionary = {}
	var closed_at := -1.0
	var returned := false
	var frames_run := 0
	var limit := int(LIFECYCLE_SECONDS * 60.0)
	for frame in limit:
		var before: Vector3 = ems.ambulance.global_position
		await frames(1)
		frames_run += 1
		var now: Vector3 = ems.ambulance.global_position
		var moved := flat_distance(before, now)
		max_frame_step = maxf(max_frame_step, moved)
		if moved > 1.0:
			violation("teleport", "%.2f m in one frame near %s" % [moved, str(now)])
		var call: Dictionary = ems.call_for(id)
		var stage := str(call.get("stage", ""))
		if not stage.is_empty() and (stages.is_empty() or str(stages[stages.size() - 1].stage) != stage):
			stages.append({"stage": stage, "outcome": str(call.get("outcome", "")), "text": str(call.get("text", "")),
				"clock": float(level.world_time.elapsed_seconds), "odometer": float(ems.driver.odometer) - start_odometer,
				"at": [now.x, now.y, now.z], "speed": float(ems.driver.speed), "route_left": ems.driver.remaining()})
			if stage == "on_scene" and arrival.is_empty():
				arrival = {"leg_empty": (ems.driver.leg as Dictionary).is_empty(), "distance": flat_distance(now, Vector3(call.get("at", now))),
					"on_road": level.traffic.on_road(now), "spot": str(ems.unit.spot.get("kind", ""))}
		if stage == "treating" and not result_details.has("treatment_capture"):
			result_details.treatment_capture = true
			await _capture_treatment(Vector3(call.at))
		_invariants(id)
		if frame % 15 == 0:
			_sample_drive()
			_probe_return()
		if (OS.get_cmdline_user_args().has("--ems-return-probe-only") or OS.get_cmdline_user_args().has("--ems-hull-probe-only")) and not return_trace.is_empty():
			break # Capture the first physical blockage; normal acceptance still fails.
		if frame % 120 == 0:
			trace.append({"clock": float(level.world_time.elapsed_seconds), "at": [now.x, now.y, now.z], "mode": str(ems.unit.mode),
				"stage": stage, "driver": str(ems.driver.wait_reason), "speed": float(ems.driver.speed)})
		if closed_at < 0.0 and stage in ["resolved", "failed", "cancelled"]:
			closed_at = float(level.world_time.elapsed_seconds)
		if OS.get_cmdline_user_args().has("--ems-crew-probe-only") and stage in ["failed", "cancelled"]:
			break # Diagnostic run still records failed acceptance checks below.
		if closed_at >= 0.0 and str(ems.unit.mode) == "parked" and ems.calls.is_empty() and _crew_aboard():
			returned = true
			break
	incidents.report_status_changed.disconnect(listener)
	var final: Dictionary = ems.call_for(id)
	var medical: Dictionary = incidents.medical_for(id)
	result_details.lifecycle = {"incident": id, "patient": patient, "scene": [Vector3(scene.position).x, Vector3(scene.position).y, Vector3(scene.position).z],
		"stages": stages, "arrival": arrival, "outcome": str(final.get("outcome", "")), "text": str(final.get("text", "")),
		"medical": medical, "notices": notices, "frames": frames_run, "max_frame_step": max_frame_step, "lane_samples": lane_samples,
		"off_road": off_road_samples, "overlap": overlap_samples, "trace": trace, "driver": ems.driver.get_status(),
		"counters": ems.counters.duplicate()}
	var names: Array = []
	for entry in stages:
		names.append(str(entry.stage))
	check(names.find("dispatched") >= 0 and names.find("en_route") > names.find("dispatched"),
		"dispatched, then on the way only after it moved: %s" % str(names))
	var en_route_odometer := -1.0
	for entry in stages:
		if str(entry.stage) == "en_route":
			en_route_odometer = float(entry.odometer)
	check(en_route_odometer >= Emergency.EN_ROUTE_EVIDENCE, "\"on the way\" came after %.1f m of real driving" % en_route_odometer)
	check(not arrival.is_empty() and bool(arrival.leg_empty) and bool(arrival.on_road),
		"\"at the scene\" only once it stopped at the end of its route on the street (%s)" % str(arrival))
	check(str(final.get("outcome", "")) == "treated" and names.find("treating") > names.find("on_scene"),
		"paramedics reached and treated the neighbor (outcome %s: %s)" % [str(final.get("outcome", "")), str(final.get("text", ""))])
	check(str(medical.get("stage", "")) == str(final.get("stage", "")) and str(medical.get("outcome", "")) == str(final.get("outcome", "")),
		"the durable record carries the same medical result")
	var index := int(scene.index)
	check(not ems.people.owns(patient) and not bool(crowd.residents[index].get("combat_controlled", false)) and not bool(crowd.residents[index].get("dead", false)),
		"the neighbor is back in ordinary life, alive")
	check(str(medical.get("clearance", "")) == "cleared", "the ambulance drove off and the street is clear")
	check(returned and not level.traffic.emergency_vehicles.has(ems.ambulance), "it returned home with both paramedics aboard within %d s" % int(LIFECYCLE_SECONDS))
	check(notices.any(func(n): return bool(n.phone) and str(n.text).contains("Dispatch sent the ambulance")), "the phone heard the dispatch: %s" % str(notices))
	check(lane_samples > 0 and off_road_samples.is_empty(), "every sampled lane position kept the whole hull on the carriageway (%d samples): %s" % [lane_samples, str(off_road_samples)])
	check(overlap_samples.is_empty(), "no sampled pose overlapped a building or prop: %s" % str(overlap_samples))
	var card: Dictionary = {}
	for value in PoliceStatus.cards(level.police_assistance.dispatch_view(), incidents.reports_for("player", 8), 8):
		if str(value.get("key", "")) == "incident:" + id:
			card = value
	result_details.card = card
	check(not card.is_empty() and card.has("medical"), "the Police page card shows the medical response: %s" % str(card.get("incident", "")))

## Invariants against the live call each frame (bounded: one call, two crew).
func _invariants(id: String) -> void:
	_probe_crew(id)
	for call in ems.calls:
		if not id in ems._call_refs(call):
			continue
		var stage := str(call.stage)
		if stage in EmergencyStatus.PRE_ARRIVAL and float(call.get("treat_time", 0.0)) > 0.0:
			violation("timed_before_arrival", "%.2f s of care before arrival" % float(call.treat_time))
		if stage in ["on_scene", "treating"] and str(ems.unit.call) == str(call.id) and not (ems.driver.leg as Dictionary).is_empty():
			violation("arrived_while_moving", "%s with a route still being driven" % stage)
		if stage == "treating":
			var near := false
			for entry in ems.crew:
				if str(entry.state) == "with_patient" and is_instance_valid(entry.actor) \
						and flat_distance((entry.actor as Node3D).global_position, Vector3(call.at)) <= Emergency.TREAT_RANGE + 0.6:
					near = true
			if not near:
				violation("treating_without_contact", "treating with no paramedic beside the person")
	for entry in ems.crew:
		if str(entry.state) == "seated" and is_instance_valid(entry.actor) and (entry.actor.enabled or entry.actor.visible):
			violation("seated_crew_present", "%s seated but present" % str(entry.id))

## Bounded read-only scene snapshots: preserve the failure state before recall
## resets path/stuck/ownership fields. No motion, clearance or timeout changes.
func _probe_crew(id: String) -> void:
	if crew_trace.size() >= 80 or str(ems.unit.mode) != "on_scene":
		return
	var tag := ""
	for entry in ems.crew:
		tag += "%s:%s:%d:%d:%d;" % [entry.id, entry.state, entry.index, entry.reroutes, entry.unstick]
	if tag == _crew_probe_tag and float(ems._clock) - _crew_probe_clock < 1.0:
		return
	_crew_probe_tag = tag
	_crew_probe_clock = float(ems._clock)
	var call: Dictionary = ems.call_for(id)
	var snapshot := {"clock": _crew_probe_clock, "call": call.get("id", ""), "stage": call.get("stage", ""),
		"patient": call.get("at", Vector3.INF), "ambulance": ems.ambulance.global_position, "crew": []}
	for entry in ems.crew:
		var actor = entry.actor
		if not is_instance_valid(actor):
			continue
		var at: Vector3 = actor.global_position
		var detail := {"id": entry.id, "state": entry.state, "enabled": actor.enabled, "position": at, "door": entry.door,
			"path": entry.path.duplicate(), "index": entry.index, "goal": entry.goal, "stuck": entry.stuck,
			"reroutes": entry.reroutes, "unstick": entry.unstick, "gave_up": entry.gave_up, "exit_tries": entry.exit_tries,
			"contact": ems._treatment_contact(actor, call)}
		if actor.enabled:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = actor.capsule.shape
			query.transform = actor.capsule.global_transform
			query.collision_mask = 1 | 2 | 4 | 8 | 16
			query.exclude = [actor.get_rid()]
			detail.overlaps = []
			for hit in level.get_world_3d().direct_space_state.intersect_shape(query, 8):
				detail.overlaps.append(str(hit.collider.get_path()))
			var goal: Vector3 = entry.goal
			if goal.is_finite():
				detail.direct_link = ems._tactics.link_clear(at, goal)
				var offset := Vector3(goal.x - at.x, 0, goal.z - at.z).normalized() * Emergency.WALK_SPEED / 60.0
				if int(entry.index) < entry.path.size():
					var target: Vector3 = entry.path[int(entry.index)]
					offset = Vector3(target.x - at.x, 0, target.z - at.z).normalized() * Emergency.WALK_SPEED / 60.0
				var ground: Dictionary = actor.walking_ground_at(at + offset)
				detail.ground = {} if ground.is_empty() else {"at": ground.position, "normal": ground.normal, "collider": str(ground.collider.get_path()), "rise": Vector3(ground.position).y + 0.012 - at.y}
				if not ground.is_empty():
					var motion := offset + Vector3.UP * (Vector3(ground.position).y + 0.012 - at.y)
					var collision := KinematicCollision3D.new()
					if actor.test_move(actor.global_transform, motion, collision):
						detail.step_collision = {"collider": str(collision.get_collider().get_path()), "normal": collision.get_normal(), "position": collision.get_position()}
				if entry.path.is_empty() and level.law.routes != null:
					detail.route_retry = level.law.routes.route(at, goal, Emergency.FOOT_ROUTE_LIMIT)
		snapshot.crew.append(detail)
	crew_trace.append(snapshot)
	result_details.crew_trace = crew_trace
	print("EMS_CITY_CREW ", JSON.stringify(snapshot))

## While driving a lane leg: the whole hull on the carriageway and clear of buildings.
func _sample_drive() -> void:
	var kind: String = ems.driver.kind()
	if not kind in ["respond", "return"] or float(ems.driver.s) <= maxf(0.0, float(ems.unit.get("lead_length", 0.0))) + 1.0:
		return
	if ems.driver.remaining() <= Emergency.SHIFT_LENGTH + 1.0:
		return # A curb pull-over is validated when planned; its corners hug the curb.
	lane_samples += 1
	var pose: Transform3D = ems.ambulance.global_transform
	for corner in [Vector3(-1.06, 0, -2.35), Vector3(-1.06, 0, 2.35), Vector3(1.06, 0, -2.35), Vector3(1.06, 0, 2.35)]:
		if not level.traffic.on_road(pose * corner, 0.0):
			if off_road_samples.size() < 5:
				off_road_samples.append(str(pose.origin))
			break
	if not ems.driver.pose_clear(pose, 2) and overlap_samples.size() < 5:
		overlap_samples.append(str(pose.origin))

func _crew_aboard() -> bool:
	for entry in ems.crew:
		if str(entry.state) == "dead":
			continue
		if str(entry.state) != "seated" or not is_instance_valid(entry.actor) or entry.actor.enabled or entry.actor.visible:
			return false
	return true

func _probe_return() -> void:
	if return_trace.size() >= 8 or not str(ems.unit.mode) in ["responding", "returning"] or str(ems.driver.wait_reason) != "hull" or float(ems.driver.wait_time) < 2.0:
		return
	var driver = ems.driver
	var at: Vector3 = ems.ambulance.global_position
	if OS.get_cmdline_user_args().has("--ems-return-probe-only") \
			and flat_distance(at, Vector3(264.8756, -3.7878, -94.6132)) > 8.0:
		return # Target the proven Wilsby/Dumbarton stall, not transient scene traffic.
	var key := "%d:%d" % [roundi(at.x * 10), roundi(at.z * 10)]
	if _return_probe_keys.has(key):
		return
	_return_probe_keys[key] = true
	var next_s: float = minf(float(driver.leg.length), float(driver.s) + 2.6 / 3600.0)
	var point := Driver.point_at(driver.leg.points, driver.leg.sums, next_s, driver.cursor)
	var direction := Driver.direction_at(driver.leg.points, driver.leg.sums, next_s, driver.cursor)
	var ground: Dictionary = driver.ground_pose(point, atan2(direction.x, direction.z) + (PI if driver.leg.reverse else 0.0))
	var snapshot := {"clock": ems._clock, "position": at, "pose": ems.ambulance.global_transform, "driver": driver.get_status(),
		"cursor": driver.cursor, "near_points": [], "next": point, "ground": ground, "current_hits": _ambulance_hits(ems.ambulance.global_transform),
		"near_cars": [], "reservations": {}, "segments": driver.leg.get("segments", []), "junctions": driver.leg.get("junctions", [])}
	for node in level.traffic.reservations:
		var holder = level.traffic.reservations[node]
		snapshot.reservations[node] = str(holder.get_path()) if is_instance_valid(holder) else "invalid"
	for i in range(maxi(0, int(driver.cursor) - 3), mini(driver.leg.points.size(), int(driver.cursor) + 6)):
		snapshot.near_points.append(driver.leg.points[i])
	if not ground.is_empty():
		snapshot.next_hits = _ambulance_hits(ground.transform)
	for car in level.traffic.vehicles:
		if is_instance_valid(car) and flat_distance(car.global_position, at) < 12.0:
			snapshot.near_cars.append({"path": str(car.get_path()), "at": car.global_position, "speed": car.speed, "yaw": car.yaw,
				"lane": car.lane_id, "next_lane": car.next_lane_id, "reservation": car.reservation_id, "control": car.control_reason,
				"route_index": car.route_index, "connector_end": car.connector_end_index, "leader_distance": car.leader_distance})
	return_trace.append(snapshot)
	result_details.return_trace = return_trace
	print("EMS_RETURN_PROBE ", JSON.stringify(snapshot))

func _ambulance_hits(pose: Transform3D) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.transform = pose
	query.margin = 0.02
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = [ems.ambulance.get_rid()]
	var hits: Array = []
	for part in ems.driver.parts:
		query.shape = part.shape
		for hit in level.get_world_3d().direct_space_state.intersect_shape(query, 8):
			hits.append({"part": part.get("name", ""), "collider": str(hit.collider.get_path()), "shape": hit.shape,
				"layer": hit.collider.collision_layer, "at": hit.collider.global_position})
	return hits

# --------------------------------------------------------------- interruption

func _interruption() -> void:
	var unblocked := false
	for frame in 60 * 150:
		if str(level.world_save.checkpoint_blocker()).is_empty():
			unblocked = true
			break
		await frames(1)
	check(unblocked, "the first incident's police call ends, so a checkpoint may be taken (%s)" % str(level.world_save.checkpoint_blocker()))
	if not unblocked:
		return
	var scene := _free_resident_near(player.global_position, 60.0, first_patient)
	if scene.is_empty():
		scene = await _find_patient(first_patient)
	check(not scene.is_empty(), "a second free neighbor is found for an interrupted response")
	if scene.is_empty():
		return
	var patient := str(scene.id)
	var opened: Dictionary = incidents.open_incident({"template": "street_fight", "at": scene.position, "offender_id": str(scene.offender),
		"victim_id": patient, "source": "external:aftermath-city-fixture"})
	var id := str(opened.get("incident_id", ""))
	incidents.note_observation(id, "player", {})
	incidents.note_injury(id, patient, "hurt")
	# No police report: a direct medical request keeps the checkpoint unblocked.
	var reply: Dictionary = ems.request({"ref": id, "patient": patient, "injury": "hurt", "at": scene.position, "by": "fixture"})
	check(bool(reply.get("ok", false)), "a second response starts (%s)" % str(reply.get("message", "")))
	var moving := false
	for frame in int(SECOND_RESPONSE_SECONDS * 60.0):
		if str(ems.call_for(id).get("stage", "")) == "en_route":
			moving = true
			break
		await frames(1)
	check(moving, "the ambulance is on its way to the second neighbor")
	check(str(level.world_save.checkpoint_blocker()).is_empty(), "a live medical response never blocks saving")
	var snapshot: Dictionary = provider.snapshot_state()
	var saved_stage := ""
	if not snapshot.is_empty():
		for entry in (snapshot.get("incidents", {}) as Dictionary).get("incidents", []):
			if str(entry.get("id", "")) == id:
				saved_stage = str((entry.get("medical", {}) as Dictionary).get("stage", ""))
	check(not snapshot.is_empty() and provider.validate_snapshot(snapshot).is_empty() and saved_stage == "en_route",
		"the checkpoint validates and carries the medical summary (%s)" % saved_stage)
	if snapshot.is_empty():
		return
	check(provider.write_snapshot(snapshot) == OK, "it is written to the private fixture checkpoint")
	var loaded: Dictionary = provider.load_state()
	check(bool(loaded.get("ok", false)), "the checkpoint loads (%s)" % str(loaded.get("reason", "")))
	await frames(3)
	var index := int(scene.index)
	check(ems.calls.is_empty() and ems.people.holds.is_empty() and str(ems.unit.mode) == "parked" and _crew_aboard(),
		"the load stands the live response down; the ambulance is home with its crew")
	check(not bool(level.npcs.crowd.residents[index].get("combat_controlled", false)), "the held neighbor is back in ordinary life")
	await frames(90)
	var medical: Dictionary = incidents.medical_for(id)
	result_details.interrupted = medical
	check(str(medical.get("stage", "")) == "cancelled" and str(medical.get("outcome", "")) == "interrupted",
		"after the load the record says the response stopped and its result is unknown (%s)" % str(medical.get("text", "")))

## Renderer-only visual acceptance; no desktop input or world/player relocation.
func _capture_treatment(patient_at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	check(_window_off_desktop(), "treatment capture stays off-desktop")
	var center: Vector3 = patient_at.lerp(ems.ambulance.global_position, 0.35)
	var toward: Vector3 = (patient_at - ems.ambulance.global_position).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	player.camera_override = {"eye": center - toward * 6.0 + side * 7.0 + Vector3.UP * 5.0,
		"target": center + Vector3.UP * 0.8}
	player.update_camera()
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/next-five-20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	var capture := get_viewport().get_texture().get_image()
	check(capture.save_png(folder.path_join("ambulance-city-treatment.png")) == OK, "actual city treatment capture saved")
	player.camera_override = {}
	player.update_camera()
