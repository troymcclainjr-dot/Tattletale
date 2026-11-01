extends Node
## Fast regressions for the exact leader broadphase and physics-tier boundaries.
## Run with --headless --path godot --script res://tests/city_traffic_optimization_smoke.gd.

const Traffic := preload("res://scripts/city/city_traffic.gd")
const Vehicle := preload("res://scripts/city/city_vehicle.gd")

class PresenceProbe:
	extends "res://scripts/city/city_vehicle.gd"
	var clearance := true
	func _pose_clear(_pose: Transform3D) -> bool:
		return clearance
	func _tick_motion(_dt: float) -> void:
		for sample in 20:
			_query(Transform3D.IDENTITY)

class RiderProbe:
	extends CharacterBody3D
	var supported := false
	var checks := 0
	func is_standing_on_vehicle(_vehicle: CollisionObject3D) -> bool:
		checks += 1
		return supported

class LevelProbe:
	extends Node3D
	var player: CharacterBody3D

class ManagerProbe:
	extends Node3D
	var level: Node3D

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_traffic_optimization] %s %s" % ["PASS" if ok else "FAIL", label])

func _reference_leaders(fleet: Array[Node3D]) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for car in fleet:
		var nearest := INF
		var forward := Vector3(sin(car.yaw), 0, cos(car.yaw))
		for other in fleet:
			if other == car:
				continue
			var delta: Vector3 = other.global_position - car.global_position
			delta.y = 0
			var along := delta.dot(forward)
			if along <= 0 or along > 45.0:
				continue
			var other_forward := Vector3(sin(other.yaw), 0, cos(other.yaw))
			if forward.dot(other_forward) < 0.60 or absf(delta.dot(forward.cross(Vector3.UP))) > 1.85:
				continue
			nearest = minf(nearest, maxf(0, along - Vehicle.BODY_SIZE.z - 1.8))
		result.append(nearest)
	return result

func _leaders_match(traffic: Node3D) -> bool:
	var reference := _reference_leaders(traffic.vehicles)
	traffic._update_leaders()
	for i in traffic.vehicles.size():
		var actual: float = traffic.vehicles[i].leader_distance
		if is_inf(reference[i]) and is_inf(actual):
			continue
		if not is_equal_approx(reference[i], actual):
			return false
	return true

func _run() -> void:
	var traffic := Traffic.new()
	add_child(traffic)
	for i in 90:
		var car := Vehicle.new()
		traffic.add_child(car)
		traffic.vehicles.append(car)
	var rng := RandomNumberGenerator.new()
	rng.seed = 320684
	var exact := true
	for snapshot in 80:
		for i in traffic.vehicles.size():
			var car: Node3D = traffic.vehicles[i]
			# Mix dense queues, opposing cars, arbitrary turns and negative cells.
			car.position = Vector3(rng.randf_range(-180, 180), rng.randf_range(-8, 8), rng.randf_range(-180, 180))
			car.yaw = rng.randf_range(-PI, PI)
			if i > 0 and i % 3 != 0:
				var previous: Node3D = traffic.vehicles[i - 1]
				car.yaw = previous.yaw + rng.randf_range(-0.3, 0.3)
				var forward := Vector3(sin(previous.yaw), 0, cos(previous.yaw))
				car.position = previous.position + forward * rng.randf_range(4, 46) + forward.cross(Vector3.UP) * rng.randf_range(-2, 2)
		exact = exact and _leaders_match(traffic)
	check(exact, "grid matches original all-pairs search across 80 mixed 90-car snapshots")
	# The extreme accepted corridor corner has radius >45m. Test both signs of
	# cell boundaries and perpendicular headings, including the lateral threshold.
	var boundary_exact := true
	for heading in [0.0, PI * 0.5, PI, -PI * 0.5, PI * 0.25]:
		for coordinate in [-96.01, -48.01, -0.01, 47.99, 95.99]:
			for i in traffic.vehicles.size():
				traffic.vehicles[i].position = Vector3(10000 + i * 100, 0, 10000)
			var first: Node3D = traffic.vehicles[0]
			var second: Node3D = traffic.vehicles[1]
			first.position = Vector3(coordinate, 0, coordinate)
			first.yaw = heading
			second.yaw = heading
			var forward := Vector3(sin(heading), 0, cos(heading))
			second.position = first.position + forward * 44.999 + forward.cross(Vector3.UP) * 1.849
			boundary_exact = boundary_exact and _leaders_match(traffic) and is_finite(first.leader_distance)
	check(boundary_exact, "far corridor corners survive positive and negative grid boundaries")
	for i in traffic.vehicles.size():
		traffic.vehicles[i].position = Vector3(i % 9 * 100, 0, i / 9 * 100)
	traffic._update_leaders()
	check(traffic.leader_candidate_checks < traffic.leader_full_pair_checks / 4,
		"spread fleet prunes over three quarters of full-pair candidates (%d/%d)" % [traffic.leader_candidate_checks, traffic.leader_full_pair_checks])
	var probe := PresenceProbe.new()
	add_child(probe)
	probe.near_physics = true
	probe.set_presence(Vector3(64, 0, 0))
	check(probe.near_physics and probe.collision_layer == 16, "active physics retained inside65m exit boundary")
	probe.set_presence(Vector3(66, 0, 0))
	check(not probe.near_physics and probe.collision_layer == 0, "physics disables outside65m")
	probe.set_presence(Vector3(60, 0, 0))
	check(not probe.near_physics, "inactive physics stays disabled in hysteresis band")
	probe.clearance = false
	probe.set_presence(Vector3(54, 0, 0))
	check(not probe.near_physics and probe._presence_blocked, "occupied activation waits with collider disabled")
	probe.clearance = true
	probe.set_presence(Vector3(54, 0, 0))
	check(probe.near_physics and not probe._presence_blocked and probe.collision_layer == 16,
		"clear activation enables physics inside55m")
	probe.body_shape = BoxShape3D.new()
	var first_query: PhysicsShapeQueryParameters3D = probe._query(Transform3D.IDENTITY, Vector3.RIGHT, 0.0)
	first_query.collision_mask = 16
	var second_query: PhysicsShapeQueryParameters3D = probe._query(Transform3D(Basis.IDENTITY, Vector3(3, 0, 4)))
	check(first_query == second_query and second_query.collision_mask == Vehicle.OBSTACLES
		and second_query.motion == Vector3.ZERO and is_equal_approx(second_query.margin, Vehicle.QUERY_MARGIN)
		and second_query.transform.origin == Vector3(3, 0, 4), "cached shape query resets mask, motion, margin and transform")
	var manager := ManagerProbe.new()
	add_child(manager)
	manager.level = LevelProbe.new()
	manager.add_child(manager.level)
	var rider := RiderProbe.new()
	manager.level.add_child(rider)
	manager.level.player = rider
	probe.traffic = manager
	probe.tick(1.0 / 60.0)
	check(rider.checks == 1, "twenty synchronous collision samples share one confirmed-floor check")
	rider.supported = true
	var riding_query: PhysicsShapeQueryParameters3D = probe._query(Transform3D.IDENTITY)
	check(riding_query.exclude.has(rider.get_rid()), "boarding outside a tick immediately refreshes rider exclusion")
	rider.supported = false
	probe.tick(1.0 / 60.0)
	check(rider.checks == 3 and not riding_query.exclude.has(rider.get_rid()),
		"next tick removes stale rider exclusion after jumping off")
	traffic.free()
	probe.free()
	manager.free()
	print("[city_traffic_optimization] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
