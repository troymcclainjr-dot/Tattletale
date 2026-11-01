extends Node
## Real lateral jumps onto production shells, followed by a moving roof ride.
const Explorer := preload("res://scripts/city/city_player.gd")
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Models := preload("res://scripts/city/city_car_models.gd")

class LevelFixture:
	extends Node3D
	var player: CharacterBody3D

class StreetFixture:
	extends Node3D
	var level: Node3D
	var active_car: CharacterBody3D
	var run_car := false
	func _physics_process(dt: float) -> void:
		if run_car and is_instance_valid(active_car):
			active_car.tick(dt)
	func on_road(_point: Vector3, _margin := 0.12) -> bool:
		return true
	func control_distance(_car: Node3D, _dt: float) -> float:
		return INF
	func release_reservation(_car: Node3D) -> void:
		pass

var world: Node3D
var level: Node3D
var traffic: Node3D
var player: CharacterBody3D
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func frames(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_vehicle_jump] %s %s" % ["PASS" if ok else "FAIL", label])

func reset_player(at: Vector3) -> void:
	Input.action_release("move_forward")
	Input.action_release("run")
	player.enabled = false
	player.reset_jump()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.current_speed = 0
	player.impact_recovery = 0
	player.impact_cooldown = 0
	player.yaw = PI * 0.5
	player.camera_yaw = player.yaw
	player._orbit_basis_latched = false
	player.enabled = true
	# Floor contact must settle with exploration enabled; pause freezes gravity.
	await frames(12)

func foot_height() -> float:
	return player.global_position.y + player._capsule.position.y - player._capsule.shape.height * 0.5

func lateral_jump(body: CollisionObject3D, label: String, roof: float, z := 0.0) -> bool:
	await reset_player(body.global_position + Vector3(-2.2, 0.04, z))
	check(player.is_on_floor(), label + " jump starts on physical street")
	var count: int = player.jumps_started
	Input.action_press("move_forward")
	check(player.request_jump(), label + " accepts lateral jump")
	var peak := foot_height()
	var landed := false
	for i in 100:
		await frames()
		peak = maxf(peak, foot_height())
		if player.global_position.x > body.global_position.x - 0.2:
			Input.action_release("move_forward")
		if player.is_standing_on_vehicle(body):
			landed = true
			break
	Input.action_release("move_forward")
	await frames(20)
	check(landed and player.is_standing_on_vehicle(body), label + " lateral jump lands and remains on the real vehicle collider")
	check(absf(foot_height() - (body.global_position.y + roof)) < 0.07,
		label + " feet settle on visible roof height")
	check(peak > body.global_position.y + 2.25 and peak < body.global_position.y + 2.50
		and player.jumps_started == count + 1, label + " jump clears cabin without invisible ceiling or double jump")
	print("[city_vehicle_jump] ", label, " position=", player.global_position, " roof=", roof, " peak=", peak,
		" floor=", player.is_on_floor(), " vehicle_floor=", player.is_standing_on_vehicle(body))
	return landed and player.is_standing_on_vehicle(body)

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(100, 1, 140)
	var collider := CollisionShape3D.new()
	collider.shape = ground_shape
	collider.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	level = LevelFixture.new()
	world.add_child(level)
	player = Explorer.new()
	level.add_child(player)
	level.player = player
	traffic = StreetFixture.new()
	traffic.level = level
	# Mirror the level's traffic-first physics order; player's solver sees the
	# updated platform pose in this same tick, as in actual city play.
	traffic.process_physics_priority = -1
	world.add_child(traffic)
	await frames(4)
	for kind in ["box_sedan", "compact", "minivan", "police"]:
		await reset_player(Vector3(-8, 0.04, 0))
		var parked := StaticBody3D.new()
		parked.collision_layer = 2
		parked.collision_mask = 0
		parked.set_meta("parked_vehicle", true)
		Collision.attach(parked, kind)
		var visual: Node3D
		if kind == "police":
			visual = Assets.model("cop_car")
			visual.rotation.y = -PI * 0.5
		else:
			visual = Models.make(kind)
		parked.add_child(visual)
		world.add_child(parked)
		await frames(3)
		var roof := 2.06 if kind == "police" else Models.dimensions(kind).y
		await lateral_jump(parked, "parked " + kind, roof, -0.20 if kind == "police" else 0.0)
		await reset_player(Vector3(-8, 0.04, 0))
		parked.free()
		await frames(2)
	# A production CharacterBody car, stopped while boarding, then driven by its
	# real tick method. No test-side translations or fake platform velocities.
	var car := Vehicle.new()
	traffic.add_child(car)
	var route: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 40)]
	check(car.setup(traffic, route, "roof_ride", 4.2), "moving sedan setup uses actual collision and ground support")
	car.honk_cooldown = 1000
	traffic.active_car = car
	await frames(3)
	var boarded := await lateral_jump(car, "moving sedan boarding", Models.dimensions("box_sedan").y)
	if boarded:
		var local_before := car.global_transform.affine_inverse() * player.global_position
		var car_before := car.global_position
		var player_before := player.global_position
		var hits_before: int = player.vehicle_hits
		var walked_before: float = player.distance_walked
		var phase_before: float = player.puppet.phase
		traffic.run_car = true
		var supported_frames := 0
		for i in 150:
			await frames()
			supported_frames += int(player.is_standing_on_vehicle(car))
		traffic.run_car = false
		var local_after := car.global_transform.affine_inverse() * player.global_position
		check(car.global_position.z - car_before.z > 5.0, "confirmed roof rider does not block or brake the moving car")
		check(player.global_position.z - player_before.z > 5.0 and local_after.distance_to(local_before) < 0.15,
			"moving CharacterBody roof carries the idle player without slipping off")
		check(supported_frames >= 145 and player.is_standing_on_vehicle(car), "moving roof keeps actual upward floor contact")
		check(player.vehicle_hits == hits_before and player.impact_recovery == 0,
			"confirmed roof support never produces a road-impact stumble")
		check(player._pose_speed < 0.12 and player.distance_walked - walked_before < 0.15
			and absf(player.puppet.phase - phase_before) < 0.55,
			"idle roof ride keeps idle animation and excludes support travel from walked distance")
		print("[city_vehicle_jump] ride car_motion=", car.global_position - car_before,
			" player_motion=", player.global_position - player_before, " relative_drift=", local_after.distance_to(local_before),
			" supported_frames=", supported_frames, " platform_velocity=", player.get_platform_velocity(), " stop=", car.blocked_reason)
		check(player.request_jump(), "player can jump off moving vehicle support")
		await frames(3)
		check(not player.is_standing_on_vehicle(car) and player.velocity.y > 0,
			"jumping releases confirmed vehicle-rider exemption")
	else:
		check(false, "moving-roof checks require successful physical boarding")
	traffic.run_car = false
	Input.action_release("move_forward")
	Input.action_release("run")
	world.queue_free()
	await frames(2)
	print("[city_vehicle_jump] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
