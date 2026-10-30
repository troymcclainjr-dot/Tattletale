extends Node
## Production fleet acceptance: sustained full-scene near physics, followed by
## accelerated distant simulation and isolated reservation regressions.

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[city_traffic_network] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 900:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "world initialized")
		_finish()
		return
	level.pause_exploring()
	await frames(2)
	var traffic: Node3D = level.traffic
	var initial: Dictionary = traffic.get_status()
	check(int(initial.total) >= 68 and int(initial.total) <= 76, "roughly72 moving cars initialized")
	check(int(initial.streets) >= 10, "cars distributed across at least ten streets")
	check(int(initial.spawn_streets.get("Old York Road", 0)) >= 8, "OldYork retains at least eight cars")
	var lane_counts: Dictionary = {}
	var initial_spacing := INF
	for car in traffic.vehicles:
		lane_counts[car.lane_id] = int(lane_counts.get(car.lane_id, 0)) + 1
		for other in traffic.vehicles:
			if car != other:
				initial_spacing = minf(initial_spacing, car.global_position.distance_to(other.global_position))
	check(initial_spacing >= 17.9, "initial cars have at least18m separation")
	var filled_long_lane := false
	for count in lane_counts.values():
		filled_long_lane = filled_long_lane or int(count) > 1
	check(filled_long_lane, "long lanes support more than one moving car")
	check(int(initial.police) >= 3, "original patrol car asset reused by at least three moving police")
	check(int(initial.network.lanes) >= 60, "directed lanes cover the real road network")
	var speeds_ok := true
	var distant := 0
	for car in traffic.vehicles:
		speeds_ok = speeds_ok and car.cruise_speed >= 8.0 and car.cruise_speed <= 11.0
		if car.global_position.distance_to(level.player.global_position) > 100:
			distant += int(not car.near_physics and car.collision_layer == 0)
	check(speeds_ok, "urban cruise targets are 8–11 meters per second")
	check(distant >= 10, "distant cars retain simulation without active body colliders")
	await _check_near_flow(level, traffic)
	# Accelerate simulation using the same production methods, deliberately using
	# its distant tier. No scene physics query is meaningful between physics ticks.
	for car in traffic.vehicles:
		car.set_presence(Vector3(100000, 0, 100000))
	var before: Dictionary = {}
	var late_before: Dictionary = {}
	var late_transfers := 0
	for car in traffic.vehicles:
		before[car.vehicle_id] = car.distance_travelled
	for frame in 3600:
		if frame == 2700:
			late_transfers = traffic.junction_transfers
			for car in traffic.vehicles:
				late_before[car.vehicle_id] = car.distance_travelled
		traffic.signals.tick(1.0 / 60.0)
		if frame % 6 == 0:
			traffic._update_leaders()
		for car in traffic.vehicles:
			car.tick(1.0 / 60.0)
	var progressed_streets: Dictionary = {}
	var progressed := 0
	var late_progressed := 0
	var finite_queues := 0
	var max_route_points := 0
	var overlaps := 0
	for car in traffic.vehicles:
		late_progressed += int(car.distance_travelled - float(late_before[car.vehicle_id]) > 5.0)
		if car.distance_travelled - float(before[car.vehicle_id]) > 25.0:
			progressed += 1
			progressed_streets[traffic.network.lanes[car.lane_id].street] = true
		finite_queues += int(car.state == "parked")
		max_route_points = maxi(max_route_points, car.route.size())
		for other in traffic.vehicles:
			if other == car:
				continue
			var relative: Vector3 = car.global_transform.affine_inverse() * other.global_position
			var alignment: float = car.global_basis.z.dot(other.global_basis.z)
			if alignment > 0.90 and absf(relative.x) < 2.1 and absf(relative.z) < 4.65:
				overlaps += 1
	check(progressed >= int(traffic.vehicles.size() * 0.75), "at least three quarters of cars travel over25m in60s")
	check(progressed_streets.size() >= 10, "continuous movement remains spread across neighborhood")
	check(traffic.junction_transfers >= 20, "cars transfer through junctions onto subsequent streets")
	check(late_progressed >= traffic.vehicles.size() / 2 and traffic.junction_transfers - late_transfers >= 4, "movement and junction transfers continue during final15seconds")
	check(finite_queues == 0, "no car parks at the end of a finite route")
	check(max_route_points < 220, "completed route prefixes are discarded")
	check(overlaps == 0, "same-direction cars maintain body separation in distant simulation")
	var reasons: Dictionary = {}
	for car in traffic.vehicles:
		if car.blocked_reason != "":
			reasons[car.blocked_reason] = int(reasons.get(car.blocked_reason, 0)) + 1
	print("[city_traffic_network] flow progressed=", progressed, " late=", late_progressed,
		" late_transfers=", traffic.junction_transfers - late_transfers, " overlaps=", overlaps, " stops=", reasons)
	# Preserve the real fleet snapshot before the isolated controller experiment.
	var flow_status: Dictionary = traffic.get_status()
	var report_dir := ProjectSettings.globalize_path("res://../artifacts/pen-lucy-dense/traffic")
	DirAccess.make_dir_recursive_absolute(report_dir)
	var report := FileAccess.open(report_dir.path_join("network-smoke.json"), FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(flow_status, "\t"))
	var compact_status: Dictionary = flow_status.duplicate()
	compact_status.erase("vehicles")
	compact_status.erase("street_details")
	compact_status.erase("parked_cars")
	print("[city_traffic_network] status ", compact_status)
	# Isolate two real incoming lanes at a shared uncontrolled junction. One car
	# gets the zone; the second must yield until the first clears its exit.
	var pair: Array[int] = []
	for a in traffic.network.lanes:
		if not bool(a.enabled) or bool(traffic.network.nodes[a.to].signal) or bool(a.stop):
			continue
		for b in traffic.network.lanes:
			if not bool(b.enabled) or a.id == b.id or a.to != b.to or bool(b.stop):
				continue
			if traffic.network.choices(int(a.id), 1).size() >= 2:
				pair = [int(a.id), int(b.id)]
				break
		if not pair.is_empty():
			break
	check(pair.size() == 2, "shared uncontrolled intersection available for reservation test")
	if pair.size() == 2:
		var all_cars: Array[Node3D] = traffic.vehicles.duplicate()
		var isolated: Array[Node3D] = [all_cars[0], all_cars[1]]
		traffic.vehicles = isolated
		traffic.reservations.clear()
		for i in 2:
			var car: Node3D = traffic.vehicles[i]
			var path: Array[Vector3] = traffic.network.lanes[pair[i]].points
			var approach: Array[Vector3] = [path[-2], path[-1]]
			car.route = approach
			car.route_index = 1
			car.lane_id = pair[i]
			car.next_lane_id = -1
			car.reservation_id = ""
			car.connector_end_index = -1
			car.global_position = path[-1]
			var direction := (path[-1] - path[-2]).normalized()
			car.yaw = atan2(direction.x, direction.z)
			car.rotation.y = car.yaw
			car.speed = 0.0
			car.state = "waiting"
			car.leader_distance = INF
			car.route_sequence = 1
		var first: Node3D = traffic.vehicles[0]
		var second: Node3D = traffic.vehicles[1]
		var zone: String = str(traffic.network.lanes[pair[0]].to)
		var first_pose := first.global_transform
		var second_pose := second.global_transform
		var second_yaw: float = second.yaw
		# Recreate the failed queue with actual positions: the rear car is called
		# first in iteration order, but must not reserve ahead of the front car.
		second.global_transform = first.global_transform
		second.yaw = first.yaw
		first.global_position -= Vector3(sin(first.yaw), 0, cos(first.yaw)) * 6.6
		traffic._update_leaders()
		traffic.control_distance(first, 0.1)
		check(not traffic.reservations.has(zone), "a follower cannot reserve from behind a waiting leader")
		first.global_transform = first_pose
		second.global_transform = second_pose
		second.yaw = second_yaw
		first.leader_distance = INF
		second.leader_distance = INF
		traffic.control_distance(first, 0.1)
		check(traffic.reservations.get(zone) == first and first.route.size() > 2, "first approach reserves and receives connected route")
		var wait_distance: float = traffic.control_distance(second, 0.1)
		check(wait_distance < 0.1 and second.reservation_id == "", "conflicting approach cannot enter occupied junction")
		for frame in 900:
			first.tick(1.0 / 60.0)
			if not traffic.reservations.has(zone):
				break
		check(not traffic.reservations.has(zone), "reservation releases only after vehicle clears exit")
		traffic.control_distance(second, 0.1)
		check(traffic.reservations.get(zone) == second, "waiting approach proceeds after clearance")
		traffic.vehicles = all_cars
	_finish()

func _check_near_flow(level: Node, traffic: Node3D) -> void:
	# Leave the entire fleet, parked cars, residents, walkers and fixtures active.
	# Only normal gameplay updates move cars or change their presence tiers.
	level.spawn_player()
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var near_distance: Dictionary = {}
	var late_distance: Dictionary = {}
	var previous_distance: Dictionary = {}
	var previous_near: Dictionary = {}
	var observed: Dictionary = {}
	var collisions: Dictionary = {}
	var max_active := 0
	var steps := Engine.physics_ticks_per_second * 45
	for car in traffic.vehicles:
		previous_distance[car.vehicle_id] = float(car.distance_travelled)
		previous_near[car.vehicle_id] = bool(car.near_physics)
	for step in steps:
		await frames(1)
		var active := 0
		for car in traffic.vehicles:
			var id: String = str(car.vehicle_id)
			var physical: bool = car.near_physics and car.collision_layer == 16
			if physical:
				active += 1
				observed[id] = true
			if physical and bool(previous_near[id]):
				var moved := maxf(0, float(car.distance_travelled) - float(previous_distance[id]))
				near_distance[id] = float(near_distance.get(id, 0)) + moved
				if step >= steps * 2 / 3:
					late_distance[id] = float(late_distance.get(id, 0)) + moved
			previous_distance[id] = float(car.distance_travelled)
			previous_near[id] = physical
			if physical and step % 6 == 0:
				# Query the actual registered boxes, including their pitch/roll,
				# rather than assuming proximity means physical penetration.
				var query: PhysicsShapeQueryParameters3D = car._query(car.global_transform, Vector3.ZERO, 0.0)
				query.collision_mask = 16
				for hit in car.get_world_3d().direct_space_state.intersect_shape(query, 8):
					var other: Node3D = hit.collider as Node3D
					if other and other.get_meta("traffic_vehicle", false) and car.global_basis.z.dot(other.global_basis.z) > 0.90:
						collisions[id + ":" + str(other.vehicle_id)] = true
		max_active = maxi(max_active, active)
	level.pause_exploring()
	await frames(2)
	var progressed := 0
	var late_progressed := 0
	for distance in near_distance.values():
		progressed += int(float(distance) > 8.0)
	for distance in late_distance.values():
		late_progressed += int(float(distance) > 3.0)
	check(observed.size() >= 3 and max_active >= 3, "several nearby cars retain physical colliders in normal play")
	check(progressed >= 3, "at least three cars travel over8m while near physics is active")
	check(late_progressed >= 2, "nearby fleet keeps moving in final15seconds of full-scene run")
	check(collisions.is_empty(), "nearby full-scene cars have no same-direction physical box overlaps")
	var report: Dictionary = traffic.get_status()
	report["near_test"] = {"simulated_seconds": 45, "observed_near_cars": observed.size(),
		"maximum_active_colliders": max_active, "progressed_near_cars": progressed,
		"late_progressed_near_cars": late_progressed, "overlap_pairs": collisions.keys(),
		"near_distances": near_distance, "late_near_distances": late_distance}
	var report_dir := ProjectSettings.globalize_path("res://../artifacts/pen-lucy-dense/traffic")
	DirAccess.make_dir_recursive_absolute(report_dir)
	var file := FileAccess.open(report_dir.path_join("network-near-smoke.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("[city_traffic_network] near45s observed=", observed.size(), " max_active=", max_active,
		" progressed=", progressed, " late_progressed=", late_progressed, " overlaps=", collisions.size(),
		" active_at_end=", report.physics_cars)

func _finish() -> void:
	print("[city_traffic_network] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
