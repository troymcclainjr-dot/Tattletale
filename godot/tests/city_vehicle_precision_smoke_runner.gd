extends Node
## Real-physics collision fits and production connector movement, at both tiers.
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")

class RedSignals:
	extends Node3D
	func phase(_axis: String) -> String:
		return "Red"

class LevelFixture:
	extends Node3D
	var player: Node3D

class StreetFixture:
	extends Node3D
	var level: Node3D
	func on_road(_point: Vector3, _margin := 0.12) -> bool:
		return true
	func control_distance(_car: Node3D, _dt: float) -> float:
		return INF
	func release_reservation(_car: Node3D) -> void:
		pass

var failures := 0
var world: Node3D
var level: Node3D
var traffic: Node3D

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_vehicle_precision] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 16))

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var box := BoxShape3D.new()
	box.size = Vector3(150, 1, 150)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	level = LevelFixture.new()
	world.add_child(level)
	level.player = Node3D.new()
	level.add_child(level.player)
	level.player.position = Vector3(1000, 0, 1000)
	traffic = StreetFixture.new()
	traffic.level = level
	world.add_child(traffic)
	await frames(3)
	for kind in ["box_sedan", "compact", "minivan", "police"]:
		var body := StaticBody3D.new()
		body.collision_layer = 16
		Collision.attach(body, kind)
		world.add_child(body)
		await frames(2)
		var roof_z := 0.30 if kind == "police" else 0.0
		var roof := ray(Vector3(0, 4, roof_z), Vector3(0, 0, roof_z))
		var expected := 1.872 if kind == "police" else Models.dimensions(kind).y
		check(not roof.is_empty() and absf(float(roof.position.y) - expected) < 0.04, kind + " roof collider follows visible roof")
		var hood := ray(Vector3(0, 4, 2.0), Vector3(0, 0, 2.0))
		var belt := 1.20 if kind == "police" else (0.80 if kind == "compact" else (0.94 if kind == "minivan" else 0.88))
		check(not hood.is_empty() and absf(float(hood.position.y) - belt) < 0.02, kind + " hood has no full-height invisible box")
		var width := 1.98 if kind == "police" else Models.dimensions(kind).x
		var shoulder := ray(Vector3(width * 0.48, expected - 0.05, -4), Vector3(width * 0.48, expected - 0.05, 4))
		check(shoulder.is_empty(), kind + " space outside tapered cabin is clear")
		check(body.get_child_count() == (3 if kind == "police" else 2), kind + " uses bounded shared convex shapes")
		body.free()
	await frames(2)
	var network := Network.new()
	network.level = level
	network._index_road(Vector3(-40, 0, 0), Vector3(40, 0, 0), 100)
	var incoming: Array[Vector3] = [Vector3(0, 0, -16), Vector3(0, 0, -6)]
	var outgoing: Array[Vector3] = [Vector3(6, 0, 0), Vector3(16, 0, 0)]
	network.lanes = [{"points": incoming}, {"points": outgoing}]
	var connector: Array[Vector3] = network.connector(0, 1)
	check(not connector.is_empty(), "production right-turn connector has real ground support")
	if connector.is_empty():
		get_tree().quit(1)
		return
	var path: Array[Vector3] = incoming.duplicate()
	path.append_array(connector.slice(1))
	path.append(outgoing[-1])
	for mode in ["near", "far", "far_to_near", "large_dt"]:
		await _check_turn(path, mode)
	await _check_braking("red", 1.0 / 60.0)
	await _check_braking("stop", 0.1)
	_check_small_step_heading()
	print("[city_vehicle_precision] failures=", failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(0 if failures == 0 else 1)

func _check_small_step_heading() -> void:
	var car := Vehicle.new()
	world.add_child(car)
	for origin in [Vector3.ZERO, Vector3(439.28, -6.85, -75.71), Vector3(-439.28, 0, 275.71)]:
		car.global_position = origin
		var tangent := Vector3(0.38, 0, -0.925).normalized()
		car.route = [origin, origin + tangent * 10.0]
		car.route_index = 1
		var worst_error := 0.0
		for step in [0.1, 0.001, 0.0001, 0.00001, 0.000002]:
			var advance: Dictionary = car._advance_route(step)
			worst_error = maxf(worst_error, (advance.direction as Vector3).angle_to(tangent))
		check(worst_error < 0.001, "crawl heading remains lane-aligned at " + str(origin))
	car.free()

func _check_turn(path: Array[Vector3], mode: String) -> void:
	var car := Vehicle.new()
	car.position = path[0]
	traffic.add_child(car)
	check(car.setup(traffic, path.duplicate(), "turn_" + mode, 4.2), mode + " car setup")
	car.speed = 4.2
	car.honk_cooldown = 1000
	if mode != "near":
		car.set_presence(Vector3(1000, 0, 1000))
	var dt := 0.1 if mode == "large_dt" else 1.0 / 60.0
	var min_step := INF
	var max_yaw_step := 0.0
	var min_alignment := 1.0
	var stopped := 0
	var activated := false
	for i in ceili(8.0 / dt):
		if mode == "far_to_near" and not activated and car.global_position.z > -5:
			var before := car.global_transform
			car.set_presence(car.global_position + Vector3(10, 0, 0))
			activated = true
			check(car.near_physics and car.global_transform.is_equal_approx(before), "far-to-near activation keeps the exact turn pose")
		var before := car.global_position
		var heading: float = car.yaw
		car.tick(dt)
		var motion := car.global_position - before
		motion.y = 0
		if car.route_index >= path.size():
			break
		min_step = minf(min_step, motion.length())
		max_yaw_step = maxf(max_yaw_step, absf(angle_difference(heading, car.yaw)))
		if motion.length_squared() > 0.000001:
			min_alignment = minf(min_alignment, motion.normalized().dot(Vector3(sin(car.yaw), 0, cos(car.yaw))))
		stopped += int(car.state == "blocked" or car.speed < 4.19)
		if car.near_physics:
			await frames()
	check(stopped == 0 and min_step > 4.2 * dt * 0.98, mode + " retains full travel budget through samples without braking jitter")
	check(max_yaw_step < deg_to_rad(12 if mode == "large_dt" else 4), mode + " heading changes smoothly through connector entry, turn and exit")
	check(min_alignment > 0.99999, mode + " faces actual travel with no lateral slide")
	check(car.global_position.x > 14 and (mode != "far_to_near" or activated), mode + " completes turn and continues down outgoing lane")
	print("[city_vehicle_precision] ", mode, " min_step=", min_step, " max_yaw_degrees=", rad_to_deg(max_yaw_step), " blocked=", car.blocked_reason)
	car.free()
	await frames(2)

func _check_braking(control: String, dt: float) -> void:
	var manager := Traffic.new()
	manager.level = level
	world.add_child(manager)
	var network := Network.new()
	network.level = level
	network._index_road(Vector3(-40, 0, 0), Vector3(40, 0, 0), 100)
	var path: Array[Vector3] = [Vector3(20, 0, -40), Vector3(20, 0, 0)]
	network.lanes = [{"id": 0, "to": "stop_line", "axis": "ns", "stop": control == "stop", "points": path}]
	network.nodes = {"stop_line": {"signal": control == "red", "out": []}}
	manager.network = network
	manager.signals = RedSignals.new()
	manager.add_child(manager.signals)
	var car := Vehicle.new()
	car.position = path[0]
	manager.add_child(car)
	check(car.setup(manager, path, "braking_" + control, 15.0), control + " aggressive-speed approach setup")
	car.lane_id = 0
	car.driver_style = "aggressive"
	car.speed = 15.0
	car.honk_cooldown = 1000
	var maximum_drop := 0.0
	var early_braking := false
	for i in ceili(6.0 / dt):
		var before: float = car.speed
		var remaining: float = car.remaining_route_distance()
		car.tick(dt)
		maximum_drop = maxf(maximum_drop, before - car.speed)
		early_braking = early_braking or (remaining > 22 and car.speed < before)
		await frames()
		if car.speed < 0.05 and car.remaining_route_distance() < 0.12:
			break
	check(early_braking, control + " approach begins braking beyond the old 22m horizon")
	check(maximum_drop <= Vehicle.BRAKING * dt + 0.002, control + " approach has no instantaneous speed loss at the line")
	check(car.speed < 0.05 and car.remaining_route_distance() < 0.12 and car.global_position.z < 0,
		control + " aggressive driver stops smoothly before the controlled line")
	print("[city_vehicle_precision] ", control, " dt=", dt, " maximum_speed_drop=", maximum_drop,
		" remaining=", car.remaining_route_distance(), " speed=", car.speed)
	manager.free()
	await frames(2)
