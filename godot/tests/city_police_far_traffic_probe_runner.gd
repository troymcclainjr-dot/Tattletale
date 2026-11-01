extends "res://tests/city_priorities_session_fixture.gd"
## Diagnostic, not gameplay acceptance or a wall-clock soak. Real full-world
## physics/traffic continue; only identified report injection and player setup
## are synthetic. --fixed-fps 60 --max-fps 0 accelerates simulated time headlessly.
const ProbeVehicle := preload("res://scripts/city/city_vehicle.gd")
var trace: FileAccess
var probe_step := 0
var probe_cycle := 0
var probe_started := 0
var seen_claims := 0
var seen_fallbacks := 0
var no_progress_samples := 0
var report_goal := Vector3(257.7985, -3.1733, -56.8558)

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	check(DisplayServer.get_name() == "headless", "accelerated traffic probe is explicitly headless")
	if failures > 0:
		_finish()
		return
	begin_phase("far-player-traffic-probe")
	var requested := clampi(int(option("--probe-seconds", "1000")), 30, 1800)
	var warmup := clampi(int(option("--probe-warmup", "60")), 0, 180)
	var mode := option("--probe-mode", "reports")
	check(mode in ["reports", "ambient"], "probe mode is reports or ambient control")
	var standing := Facilities.standing_at(level.get_world_3d().direct_space_state,
		Vector3(-128.6379, 4.5907, -253.234), [player.get_rid()])
	check(not standing.is_empty(), "far-player probe position is supported in the actual map")
	if standing.is_empty():
		_finish()
		return
	_set_scenario_position(standing.position)
	level.resume_exploring()
	level.law.reset_state()
	trace = FileAccess.open(output_dir.path_join("traffic-trace.jsonl"), FileAccess.WRITE)
	check(trace != null, "bounded project-local traffic trace opened")
	if trace == null:
		_finish()
		return
	probe_started = Time.get_ticks_usec()
	var simulation_start := Engine.get_physics_frames()
	for index in (requested + warmup) * 60:
		probe_step = index
		var active_step := index - warmup * 60
		if active_step >= 0 and mode == "reports":
			var cycle_frame := active_step % (30 * 60)
			if cycle_frame == 0:
				probe_cycle += 1
				level.law.reset_state()
				level.law._file({"identified": true, "player_at": report_goal, "at": report_goal,
					"severity": float(level.law.TIER_HEAT[2]), "kind": "shooting", "lethal": false,
					"time": float(level.law._clock), "source": "police", "seated": false})
				_snapshot("report")
			elif cycle_frame == 20 * 60:
				_snapshot("before_reset")
				level.law.reset_state()
		await frames(1)
		var claims := int(level.law.cruisers.counters.claims)
		var fallbacks := int(level.law.cruisers.counters.blocked_dispatches)
		if claims != seen_claims or fallbacks != seen_fallbacks:
			_snapshot("claim_or_fallback")
			seen_claims = claims
			seen_fallbacks = fallbacks
		elif index % 300 == 0:
			_snapshot("periodic")
		if index % 3600 == 0:
			print("[far_traffic_probe] sim_seconds=%d cycles=%d claims=%d fallbacks=%d wall_seconds=%.1f" %
				[index / 60, probe_cycle, claims, fallbacks, float(Time.get_ticks_usec() - probe_started) / 1000000.0])
	_snapshot("complete")
	trace.flush()
	trace = null
	result_details["traffic_probe"] = {"mode": mode, "simulated_physics_frames": Engine.get_physics_frames() - simulation_start,
		"requested_seconds": requested, "warmup_seconds": warmup, "cycles": probe_cycle,
		"no_progress_samples": no_progress_samples, "claims": seen_claims, "fallbacks": seen_fallbacks,
		"wall_seconds": float(Time.get_ticks_usec() - probe_started) / 1000000.0,
		"trace": output_dir.path_join("traffic-trace.jsonl"), "injected_report_goal": report_goal}
	check(level.traffic.vehicles.size() == 90, "diagnostic retains all ninety real traffic cars")
	check(mode == "ambient" or seen_claims > 0, "report probe observed actual external claims")
	print("[far_traffic_probe] diagnostic completed; queue progress requires trace review, not inferred from exit zero")
	_finish()

func _snapshot(event: String) -> void:
	var traffic: Node3D = level.traffic
	var cars: Array = []
	var fleet: Array = []
	fleet.append_array(traffic.vehicles)
	fleet.append_array(traffic.player_fleet)
	var interest := PackedVector3Array()
	for car in traffic.vehicles:
		if not str(car.external_owner).is_empty():
			interest.append(car.global_position)
	var geometry_checks := 0
	for car in fleet:
		if not is_instance_valid(car):
			continue
		var leader := ""
		var leader_gap := INF
		var heading: float = car._route_heading if not car.flat_tires.is_empty() else car.yaw
		var forward := Vector3(sin(heading), 0, cos(heading))
		for other in fleet:
			if other == car or not is_instance_valid(other):
				continue
			var delta: Vector3 = other.global_position - car.global_position
			delta.y = 0
			var along := delta.dot(forward)
			var other_heading: float = other._route_heading if not other.flat_tires.is_empty() else other.yaw
			var omni: bool = other in traffic.player_fleet or other.player_controlled or other.player_released \
				or not str(other.external_owner).is_empty() or other.external_released or other.disabled
			var corridor := 2.95 if not car.flat_tires.is_empty() or not other.flat_tires.is_empty() else 1.85
			if along <= 0 or along > 45 or absf(delta.dot(forward.cross(Vector3.UP))) > corridor \
				or (forward.dot(Vector3(sin(other_heading), 0, cos(other_heading))) < .60 and not omni):
				continue
			var gap := maxf(0, along - ProbeVehicle.BODY_SIZE.z - 1.8)
			if gap < leader_gap:
				leader_gap = gap
				leader = str(other.vehicle_id)
		var lane: Dictionary = traffic.network.lanes[car.lane_id] if car.lane_id >= 0 else {}
		var record := {"id": str(car.vehicle_id), "position": car.global_position, "yaw": float(car.yaw),
			"state": str(car.state), "speed": float(car.speed), "distance": float(car.distance_travelled),
			"stopped_time": float(car.stopped_time), "blocked_reason": str(car.blocked_reason), "control_reason": str(car.control_reason),
			"leader_id": leader, "computed_leader_gap": leader_gap, "leader_distance": float(car.leader_distance),
			"obstacle_distance": float(car._obstacle_distance), "near_physics": bool(car.near_physics),
			"presence_blocked": bool(car._presence_blocked), "collision_layer": int(car.collision_layer),
			"owner": str(car.external_owner), "external_released": bool(car.external_released),
			"player_released": bool(car.player_released), "disabled": bool(car.disabled), "flat_tires": car.flat_tires,
			"lane_id": int(car.lane_id), "street": lane.get("street", ""), "lane_to": lane.get("to", ""),
			"next_lane_id": int(car.next_lane_id), "reservation": str(car.reservation_id),
			"route_index": int(car.route_index), "route_points": car.route.size(), "remaining": car.remaining_route_distance(),
			"recycled": int(car.recycled), "player_distance": car.global_position.distance_to(player.global_position)}
		var near_cruiser := false
		for at in interest:
			near_cruiser = near_cruiser or car.global_position.distance_squared_to(at) <= 50.0 * 50.0
		if near_cruiser and absf(float(car.speed)) < .1 and geometry_checks < 12:
			geometry_checks += 1
			var road_corners: Array = []
			for corner in ProbeVehicle.ROAD_CORNERS:
				road_corners.append(traffic.on_road(car.global_transform * corner))
			var ground: Dictionary = car._ground_pose(car.global_position, float(car.yaw))
			record["geometry"] = {"pose_clear": car._pose_clear(car.global_transform),
				"hull_clear": car._hull_clear(car.global_transform), "road_corners": road_corners,
				"ground_available": not ground.is_empty(),
				"ground_pose": ground.get("transform", Transform3D.IDENTITY)}
		cars.append(record)
	var reservations := {}
	for key in traffic.reservations:
		var holder = traffic.reservations[key]
		reservations[str(key)] = str(holder.vehicle_id) if is_instance_valid(holder) else "INVALID"
	var status: Dictionary = level.law.cruisers.get_status()
	for unit in status.units:
		if float(unit.odometer) < .25 and float(unit.obstacle) < 3.0 and str(unit.obstacle_kind) == "vehicle":
			no_progress_samples += 1
	trace.store_line(JSON.stringify({"event": event, "sim_seconds": float(probe_step) / 60.0, "cycle": probe_cycle,
		"wall_seconds": float(Time.get_ticks_usec() - probe_started) / 1000000.0, "player": player.global_position,
		"traffic_distance": traffic.get_status().distance_travelled, "reservations": reservations,
		"cruisers": status, "cars": cars}))
	trace.flush()
