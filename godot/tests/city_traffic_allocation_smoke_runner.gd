extends Node
## Exit-clearance reference preserves the pre-optimization algorithm verbatim.
## No full city, timers, collision-query substitution, or reduced simulation.
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
var failures := 0
var comparisons := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[traffic_allocation] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	_check_exits()
	print("[traffic_allocation] comparisons=%d failures=%d" % [comparisons, failures])
	get_tree().quit(1 if failures else 0)

func _check_exits() -> void:
	var traffic := Traffic.new()
	add_child(traffic)
	traffic.network = Network.new()
	var self_car := Node3D.new()
	traffic.add_child(self_car)
	var pool: Array[Node3D] = []
	for index in 91:
		var other := Node3D.new()
		traffic.add_child(other)
		pool.append(other)
	var rng := RandomNumberGenerator.new()
	rng.seed = 45602026
	var match_all := true
	for sample in 350:
		var origin := Vector3(rng.randf_range(-600, 600), rng.randf_range(-15, 15), rng.randf_range(-600, 600))
		var heading := rng.randf_range(-PI, PI)
		var direction := Vector3(sin(heading), rng.randf_range(-0.15, 0.15), cos(heading)).normalized()
		var points: Array[Vector3] = [origin, origin + direction * 12.0]
		traffic.network.lanes.assign([{"points": points}])
		traffic.vehicles.clear()
		traffic.player_fleet.clear()
		traffic.vehicles.append(self_car)
		traffic.player_fleet.append(self_car)
		self_car.global_position = origin
		for index in pool.size():
			pool[index].global_position = origin + Vector3(rng.randf_range(-30, 30), rng.randf_range(-5, 5), rng.randf_range(-30, 30))
			if index < sample % 91:
				traffic.vehicles.append(pool[index])
			if index % 17 == sample % 17:
				# Retain duplicates/overlap between the two fleets, including self.
				traffic.player_fleet.append(pool[index])
		traffic.vehicles.append(null)
		traffic.player_fleet.append(null)
		comparisons += 1
		match_all = match_all and traffic._exit_clear(self_car, 0) == _legacy_exit_clear(traffic, self_car, 0)
	check(match_all, "exit result matches original across arbitrary headings, grades, live positions, self and overlapping fleets")
	var axis: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 10)]
	traffic.network.lanes.assign([{"points": axis}])
	traffic.vehicles.assign([self_car, null])
	traffic.player_fleet.assign([self_car, pool[0], pool[0], null])
	var edges_ok := true
	for point in [Vector3(0, 0, -5), Vector3(0, 0, 13), Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, -4.999), Vector3(0, 0, 12.999), Vector3(1.999, 0, 0), Vector3(-1.999, 0, 0)]:
		pool[0].global_position = point
		comparisons += 1
		edges_ok = edges_ok and traffic._exit_clear(self_car, 0) == _legacy_exit_clear(traffic, self_car, 0)
	check(edges_ok, "strict exit boundaries and player-fleet-only blockers match original")
	pool[0].global_position = Vector3(20, 0, 0)
	check(traffic._exit_clear(self_car, 0), "self in both fleets is ignored and moved blocker is observed live")
	var freed := Node3D.new()
	traffic.vehicles.append(freed)
	traffic.player_fleet.append(freed)
	freed.free()
	check(traffic._exit_clear(self_car, 0) == _legacy_exit_clear(traffic, self_car, 0), "freed fleet entries retain original skip semantics")
	traffic.vehicles.clear()
	traffic.player_fleet.clear()
	traffic.free()

func _legacy_exit_clear(traffic, car: Node3D, outgoing: int) -> bool:
	var points: Array[Vector3] = traffic.network.lanes[outgoing].points
	var direction := (points[1] - points[0]).normalized()
	for other in traffic.vehicles + traffic.player_fleet:
		if other == car or not is_instance_valid(other):
			continue
		var delta: Vector3 = other.global_position - points[0]
		var along := delta.dot(direction)
		if along > -5 and along < 13 and absf(delta.dot(direction.cross(Vector3.UP))) < 2.0:
			return false
	return true
