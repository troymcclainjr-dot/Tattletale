extends Node
## Differential control/leader probe against an immutable pre-change script.
## --traffic-baseline <absolute city_traffic.gd> enables paired AB/BA timings.
## No timing threshold: this is a CPU microbenchmark, not an FPS assertion.
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Signals := preload("res://scripts/city/city_street_signals.gd")
var failures := 0
var comparisons := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[traffic_dispatch] %s %s" % ["PASS" if ok else "FAIL", label])

func _make_manager(script: Script) -> Node3D:
	var manager: Node3D = script.new()
	add_child(manager)
	manager.network = Network.new()
	manager.signals = Signals.new()
	manager.add_child(manager.signals)
	var incoming: Array[Vector3] = [Vector3(0, 0, -100), Vector3.ZERO]
	var outgoing: Array[Vector3] = [Vector3(0, 0, 10), Vector3(0, 0, 14), Vector3(0, 0, 100)]
	manager.network.lanes.assign([
		{"points": incoming, "to": "junction", "axis": "old_york", "stop": false, "enabled": true},
		{"points": outgoing, "to": "exit", "axis": "old_york", "stop": false, "enabled": true}])
	manager.network.nodes = {"junction": {"signal": false, "out": [1]}, "exit": {"signal": false, "out": []}}
	var bridge: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 5), Vector3(0, 0, 10)]
	manager.network._connector_cache["0_1"] = bridge
	for index in 90:
		var car := Vehicle.new()
		manager.add_child(car)
		car.traffic = manager
		car.vehicle_id = str(index)
		manager.vehicles.append(car)
	return manager

func _arrange(manager: Node3D, scenario: int, seed_value: int) -> void:
	manager.reservations.clear()
	manager.junction_transfers = 0
	manager.network.nodes.junction.signal = scenario == 1
	manager.network.nodes.junction.out = [] if scenario == 6 else [1]
	manager.network.lanes[0].stop = scenario == 2
	manager.signals.elapsed = 24.0 if scenario == 1 else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in manager.vehicles.size():
		var car: Vehicle = manager.vehicles[index]
		car.route = manager.network.lanes[0].points.duplicate()
		car.route_index = 1
		car.lane_id = 0
		car.next_lane_id = -1
		car.reservation_id = ""
		car.connector_end_index = -1
		car.route_sequence = 1
		car.stop_dwell = 0.0
		car.control_reason = "initial"
		car.leader_distance = INF
		car.flat_tires.clear()
		car.player_controlled = false
		car.player_released = false
		car.external_owner = ""
		car.external_released = false
		car.disabled = false
		car.position = Vector3(rng.randf_range(-500, 500), 0, rng.randf_range(-500, 500))
		car.yaw = rng.randf_range(-PI, PI)
		car.speed = 0.0
	var first: Vehicle = manager.vehicles[0]
	first.position = Vector3(0, 0, -60 if scenario == 0 else (-0.05 if scenario == 2 else -3))
	if scenario == 3:
		first.leader_distance = 1.0
	elif scenario == 4:
		manager.reservations.junction = manager.vehicles[1]
	elif scenario == 5:
		manager.vehicles[1].position = Vector3(0, 0, 15)
	elif scenario == 8:
		first.reservation_id = "junction"
		first.connector_end_index = 2
		manager.reservations.junction = first
	elif scenario == 9:
		first.reservation_id = "junction"
		first.connector_end_index = 0
		manager.reservations.junction = first

func _state(manager: Node3D) -> Dictionary:
	var car: Vehicle = manager.vehicles[0]
	var reserved := ""
	if manager.reservations.has("junction"):
		reserved = str(manager.reservations.junction.vehicle_id)
	return {"route": car.route.duplicate(), "index": car.route_index, "lane": car.lane_id,
		"next": car.next_lane_id, "reservation": car.reservation_id, "reserved": reserved,
		"connector_end": car.connector_end_index, "sequence": car.route_sequence,
		"dwell": car.stop_dwell, "reason": car.control_reason, "transfers": manager.junction_transfers}

func _timed_control(manager: Node3D, iterations: int) -> int:
	var car: Vehicle = manager.vehicles[0]
	var began := Time.get_ticks_usec()
	for index in iterations:
		manager.control_distance(car, 1.0 / 60.0)
	return Time.get_ticks_usec() - began

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var path := ""
	var args := OS.get_cmdline_user_args()
	for index in args.size() - 1:
		if args[index] == "--traffic-baseline":
			path = args[index + 1]
	if path.is_empty():
		check(false, "requires --traffic-baseline immutable pre-change script")
		get_tree().quit(1)
		return
	var baseline_script := load(path) as Script
	if baseline_script == null or not baseline_script.can_instantiate():
		check(false, "baseline script loads")
		get_tree().quit(1)
		return
	var baseline := _make_manager(baseline_script)
	var candidate := _make_manager(Traffic)
	var exact := true
	for scenario in 10:
		for trial in 20:
			_arrange(baseline, scenario, 20261101 + trial)
			_arrange(candidate, scenario, 20261101 + trial)
			for tick in 60:
				var before: float = baseline.control_distance(baseline.vehicles[0], 1.0 / 60.0)
				var after: float = candidate.control_distance(candidate.vehicles[0], 1.0 / 60.0)
				comparisons += 1
				exact = exact and before == after and _state(baseline) == _state(candidate)
	check(exact, "12000 control results and live route/queue/reservation states match frozen original")
	var leader_exact := true
	for trial in 80:
		_arrange(baseline, 0, trial)
		_arrange(candidate, 0, trial)
		for manager in [baseline, candidate]:
			for index in manager.vehicles.size():
				var car: Vehicle = manager.vehicles[index]
				if index % 4 == 0:
					car.flat_tires.assign([0])
					car._route_heading = car.yaw + 0.3
				car.player_released = index % 7 == 0
				car.external_owner = "police" if index % 11 == 0 else ""
			manager._update_leaders()
		for index in candidate.vehicles.size():
			leader_exact = leader_exact and baseline.vehicles[index].leader_distance == candidate.vehicles[index].leader_distance
	check(leader_exact, "7200 mixed damaged/released/external leader distances match frozen original")
	var timings: Array = []
	for scenario in [0, 1, 2, 3, 4, 5, 6, 8]:
		_arrange(baseline, scenario, 20261101)
		_arrange(candidate, scenario, 20261101)
		if scenario == 2:
			# Keep this timed gate on the approaching-stop branch; the stateful
			# .8-second dwell/transfer is covered by the differential checks.
			baseline.vehicles[0].position.z = -3.0
			candidate.vehicles[0].position.z = -3.0
		_timed_control(baseline, 1000)
		_timed_control(candidate, 1000)
		for pair in 6:
			var before := 0
			var after := 0
			if pair % 2 == 0:
				before = _timed_control(baseline, 20000)
				after = _timed_control(candidate, 20000)
			else:
				after = _timed_control(candidate, 20000)
				before = _timed_control(baseline, 20000)
			timings.append({"scenario": scenario, "pair": pair, "calls": 20000, "baseline_usec": before, "candidate_usec": after})
	print("[traffic_dispatch] TIMINGS " + JSON.stringify(timings))
	baseline.free()
	candidate.free()
	print("[traffic_dispatch] comparisons=%d failures=%d" % [comparisons, failures])
	get_tree().quit(1 if failures else 0)
