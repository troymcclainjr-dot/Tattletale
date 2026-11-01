extends Node
## Real swept-body/contact/recovery regressions on an isolated flat street.
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Explorer := preload("res://scripts/city/city_player.gd")

class StreetFixture:
	extends Node3D
	var level: Node3D
	func on_road(_point: Vector3, _margin := 0.12) -> bool:
		return true
	func control_distance(_car: Node3D, _dt: float) -> float:
		return INF
	func release_reservation(_car: Node3D) -> void:
		pass

class LevelFixture:
	extends Node3D
	var player: CharacterBody3D

var world: Node3D
var level: Node3D
var traffic: Node3D
var player: CharacterBody3D
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_vehicle_impact] %s %s" % ["PASS" if ok else "FAIL", label])

func box(label: String, at: Vector3, size_: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size_
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func reset_player(at := Vector3.ZERO) -> void:
	player.enabled = false
	player.impact_recovery = 0.0
	player.impact_cooldown = 0.0
	player.global_position = at + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.enabled = true
	# Disabled controllers intentionally freeze instead of settling on the street.
	await frames(3)

func make_car(style: String, at_z := -14.0, target_speed := 10.0, police := false) -> Node3D:
	var car := Vehicle.new()
	# Body registration precedes route setup. Give it the intended transform
	# first, so the physics server never sees a new collider at the player origin.
	car.position = traffic.to_local(Vector3(0, 0, at_z))
	traffic.add_child(car)
	var route: Array[Vector3] = [Vector3(0, 0, at_z), Vector3(0, 0, 30)]
	check(car.setup(traffic, route, "impact_fixture", target_speed, 0, police), "controlled vehicle has road support and clear initial body")
	car.driver_style = style
	# Physics fixture runs faster than the audio device; do not leave a honk
	# playing when its short-lived test scene exits. Audio is tested separately.
	car.honk_cooldown = 1000.0
	return car

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box("Ground", Vector3(0, -0.5, 0), Vector3(100, 1, 200), 1)
	level = LevelFixture.new()
	world.add_child(level)
	player = Explorer.new()
	level.add_child(player)
	level.player = player
	traffic = StreetFixture.new()
	world.add_child(traffic)
	traffic.level = level
	await frames(4)
	var profiles_ok := true
	var aggressive := 0
	for i in 90:
		var police: bool = i in [5, 24, 43, 62]
		var profile: Dictionary = Vehicle.driver_profile(i, police)
		profiles_ok = profiles_ok and profile == Vehicle.driver_profile(i, police)
		if profile.style == "aggressive":
			aggressive += 1
			profiles_ok = profiles_ok and not police and float(profile.speed) >= 12 and float(profile.speed) <= 15
		else:
			profiles_ok = profiles_ok and float(profile.speed) >= 8 and float(profile.speed) <= 10.5
	check(profiles_ok and aggressive >= 12 and aggressive <= 18, "reproducible minority aggressive profiles, normal urban speeds, cautious patrols")
	await reset_player()
	var hits_before: int = player.vehicle_hits
	var car := make_car("cautious")
	check(is_finite(car._player_contact_fraction(Vector3(0, 0, 20))), "nearby swept interval finds player ahead")
	player.global_position.x = 3.0
	check(is_inf(car._player_contact_fraction(Vector3(0, 0, 20))), "player outside the vehicle corridor does not obstruct traffic")
	player.global_position = Vector3(0, 6, 0)
	check(is_inf(car._player_contact_fraction(Vector3(0, 0, 20))), "vertically separated player does not create a road impact")
	player.global_position = car.global_position + Vector3(0, 1.10, 2.10)
	check(is_inf(car._player_contact_fraction(Vector3.ZERO)), "player above the hood is outside the tapered cabin impact envelope")
	for gap in [0.05, 0.10, 0.20]:
		# These diagonal positions lie inside the expanded face planes but
		# outside the capsule's rounded bumper-corner contact envelope.
		var offset := (0.30 + float(gap)) / sqrt(2.0)
		await reset_player(car.global_position + Vector3(1.025 + offset, 0, 2.35 + offset))
		check(is_inf(car._player_contact_fraction(Vector3(0, 0, 0.02))),
			"exact capsule sweep rejects bumper-corner miss with %.2fm gap" % gap)
	player.set_physics_process(false)
	player.global_position = car.global_position
	await frames(2)
	check(is_zero_approx(car._player_contact_fraction(Vector3.ZERO)), "exact capsule confirmation includes initial overlap")
	player.set_physics_process(true)
	await reset_player()
	for i in 360:
		car.tick(1.0 / 60.0)
		await frames(1)
	print("[city_vehicle_impact] cautious snapshot ", car.get_status(), " player=", player.global_position, " hits=", player.vehicle_hits)
	check(player.vehicle_hits == hits_before and car.global_position.z < -3.0 and car.speed < 0.1,
		"cautious driver brakes with clearance for an explorer in the lane")
	check(absf(player.global_position.x) < 0.01 and absf(player.global_position.z) < 0.01, "cautious braking leaves the player's solid capsule undisturbed")
	car.free()
	await frames(2)
	await reset_player()
	car = make_car("aggressive", -10.0, 15.0)
	car.speed = 15.0
	for i in 12:
		car.tick(0.1)
		print("[city_vehicle_impact] aggressive step=", i, " car=", car.global_position, " speed=", car.speed, " stop=", car.blocked_reason, " hits=", player.vehicle_hits)
		if player.vehicle_hits > hits_before:
			break
		await frames(1)
	check(player.vehicle_hits == hits_before + 1 and car.player_hits == 1 and player.impact_recovery > 0,
		"aggressive driver reaches physical swept contact and triggers one stumble")
	check(car.global_position.z + Vehicle.BODY_SIZE.z * 0.5 < player.global_position.z,
		"impact stops the car before the solid player capsule")
	car.speed = 15.0
	for i in 8:
		car._hit_player(Vector3(0, 0, 1))
	check(player.vehicle_hits == hits_before + 1, "sustained contact cannot spam impacts during cooldown")
	car.free()
	var before := player.global_position
	await frames(90)
	check(player.global_position.z > before.z + 0.5 and player.impact_recovery <= 0.0 and player.impact_cooldown <= 0.0,
		"stumble glides forward and both recovery and cooldown expire")
	check(player.collision_layer == 4 and not player._capsule.disabled, "player collider stays enabled throughout recovery")
	player.camera_yaw = 0.0
	player.yaw = 0.0
	before = player.global_position
	Input.action_press("move_forward")
	await frames(24)
	Input.action_release("move_forward")
	check(player.global_position.z > before.z + 0.5, "movement controls resume after the short recovery")
	await reset_player()
	hits_before = player.vehicle_hits
	car = make_car("aggressive", -8.0, 70.0)
	car.speed = 70.0
	car.tick(0.1)
	check(player.vehicle_hits == hits_before + 1 and car.global_position.z < -2.6,
		"seven-meter frame sweep hits instead of tunneling through the capsule")
	car.free()
	await frames(2)
	await reset_player()
	for layer in [2, 8, 16]:
		var obstacle := box("Solid_%d" % layer, Vector3(0, 1.2, -3.8), Vector3(4, 2.4, 0.3), layer)
		await frames(2)
		car = make_car("aggressive", -7.0, 15.0)
		car.speed = 15.0
		# Force an intervening actual movement sweep rather than lookahead alone.
		car._obstacle_clock = 1.0
		hits_before = player.vehicle_hits
		car.tick(0.1)
		check(car.global_position.z <= -7.0 and car.speed == 0.0 and player.vehicle_hits == hits_before,
			"aggressive movement respects solid layer%d and cannot hit a shielded player" % layer)
		car.free()
		obstacle.free()
		await frames(2)
	car = make_car("aggressive", -14.0, 10.5, true)
	check((car._lookahead_query(Vector3(0, 0, 10)).collision_mask & 4) != 0, "police always inspect the player in braking lookahead")
	car.free()
	await reset_player()
	var wall := box("RecoveryWall", Vector3(0, 1.2, 1.5), Vector3(8, 2.4, 0.3), 2)
	await frames(2)
	check(player.receive_vehicle_impact(Vector3(0, 0, 1), 15.0, "wall_fixture"), "player can receive another impact after recovery")
	await frames(90)
	check(player.global_position.z < 1.07 and player.impact_recovery == 0.0, "knockback stops against a structure and still recovers")
	wall.free()
	await reset_player()
	player.enabled = false
	hits_before = player.vehicle_hits
	check(not player.receive_vehicle_impact(Vector3(0, 0, 1), 15.0) and player.vehicle_hits == hits_before,
		"paused exploration rejects new vehicle effects")
	player.enabled = true
	player.receive_vehicle_impact(Vector3(0, 0, 1), 15.0)
	player.enabled = false
	before = player.global_position
	var recovery_before: float = player.impact_recovery
	await frames(12)
	check(player.global_position.is_equal_approx(before) and player.impact_recovery == recovery_before,
		"existing recovery freezes while exploration is paused")
	player.enabled = true
	await frames(90)
	check(player.impact_recovery == 0.0 and player.impact_cooldown == 0.0, "resuming finishes recovery with no permanent immunity")
	get_tree().paused = true
	check(not player.receive_vehicle_impact(Vector3(0, 0, 1), 15.0), "tree pause also rejects impact effects")
	get_tree().paused = false
	print("[city_vehicle_impact] failures=", failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(0 if failures == 0 else 1)
