extends Node
## Pacifist policy plus dormant vehicle-physics regressions on the explorer, CharacterBody3D
## vehicles, traffic manager and driving manager over real static collision:
## starter placement, entry authority, AI ownership, handling, collision sweeps,
## tire damage, safe placement, external ownership, render LOD and pause gating.
## Physics use legitimate external ownership; player driving is never enabled.
## Run: python godot/tools/godot_run.py --timeout 240 -- --headless --script res://tests/city_driving_smoke.gd
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Explorer := preload("res://scripts/city/city_player.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Driving := preload("res://scripts/city/city_driving.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const DT := 1.0 / 60.0
const SPAWN := Vector3(6.2, 0.15, 10.0)
const OPEN := Vector3(-60.0, 0.0, -120.0)
const LONG_START := Vector3(-150.0, 0.0, -250.0)
const AI_SPOT := Vector3(60.0, 0.0, -120.0)

class LevelFixture:
	extends Node3D
	var player: CharacterBody3D
	var traffic: Node3D
	var combat: Node3D
	var paused := false
	var offscreen_validation := true
	var level_data: Dictionary = {}
	var notices: Array[String] = []
	func show_notice(message: String) -> void:
		notices.append(message)

class CombatStub:
	extends Node3D
	var downed := 0.0
	var cancels := 0
	func blocks_movement() -> bool:
		return downed > 0.0
	func cancel_player_actions() -> void:
		cancels += 1

var world: Node3D
var level: LevelFixture
var player: CharacterBody3D
var traffic: Node3D
var driving: Node3D
var combat: CombatStub
var renderer: Node3D
var physics_car: Node3D
var physics_impacts := 0
var physics_contact: Dictionary = {}
var passes := 0
var failures := 0
var obstacles: Array[Node] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	passes += int(ok)
	failures += int(not ok)
	print("[city_driving] %s %s" % ["PASS" if ok else "FAIL", label])
	return ok

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func box(label: String, at: Vector3, size: Vector3, layer: int, heading := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, heading), at)
	obstacles.append(body)
	return body

func clear_obstacles() -> void:
	for body in obstacles:
		if is_instance_valid(body):
			body.free()
	obstacles.clear()

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func ground_y(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 3.0, 1 | 2)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else at.y

func stand(at: Vector3) -> void:
	player.enabled = false
	player.global_position = Vector3(at.x, ground_y(at) + 0.05, at.z)
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.impact_recovery = 0.0
	player.impact_cooldown = 0.0
	player.enabled = true
	await frames(3)

func half_size(car: Node3D) -> Vector3:
	return Models.dimensions(str(car.prototype_kind)) * 0.5

## A point beside a door: side 1 is the driver's (+X) side, -1 the kerb side.
func door_point(car: Node3D, side := 1.0, along := 0.25) -> Vector3:
	var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
	var left := Vector3(forward.z, 0.0, -forward.x)
	return car.global_position + left * side * (half_size(car).x + 0.45) + forward * along

func board(car: Node3D) -> bool:
	if driving.active:
		return driving.vehicle == car
	for side in [1.0, -1.0]:
		await stand(door_point(car, side))
		driving.tick(0.1)
		if driving.handle_input(key(KEY_F)) and driving.active:
			return true
	return false

## Teleport a body; the explorer's seat follows a controlled car.
func place(car: Node3D, at: Vector3, heading: float, speed := 0.0) -> void:
	# Each placement starts an independent movement fixture. Earlier wall/curb
	# crashes now damage the body; do not carry a wreck into tire/exit tests.
	# Dedicated vehicle consequence tests cover sticky disable and repair rules.
	car.health = Vehicle.MAX_HEALTH
	car.disabled = false
	car._contact_memory.clear()
	car.global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(at.x, ground_y(at) + 0.025, at.z))
	car.yaw = heading
	car.speed = speed
	car.drive_velocity = Vector3(sin(heading), 0.0, cos(heading)) * speed
	car.drive_steer = 0.0
	car.drive_airborne = false
	car.drive_vertical_speed = 0.0
	car._drive_heights = PackedFloat32Array()
	if car.player_controlled and driving.vehicle == car:
		player.follow_vehicle()
		driving._last_seat = player.global_position

func drive(count: int, throttle := 0.0, brake := 0.0, steer := 0.0, handbrake := false) -> void:
	for i in count:
		step_physics(DT, throttle, brake, steer, handbrake)
		await get_tree().physics_frame

func step_physics(delta: float, throttle: float, brake: float, steer: float, handbrake: bool) -> void:
	var result: Dictionary = physics_car.external_step(delta, throttle, brake, steer, handbrake)
	var contact: Dictionary = result.get("contact", {})
	if not contact.is_empty() and float(contact.get("speed", 0.0)) >= Driving.IMPACT_REPORT_SPEED:
		physics_impacts += 1
		physics_contact = contact

func make_ai_car(at: Vector3, heading: float, id: String, cruise := 9.0, police := false) -> Node3D:
	var car := Vehicle.new()
	car.name = id
	car.position = traffic.to_local(at)
	traffic.add_child(car)
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var route: Array[Vector3] = [at, at + forward * 60.0]
	check(car.setup(traffic, route, id, cruise, 4, police), id + " fixture traffic car has a clear supported body")
	car.honk_cooldown = 1000.0
	traffic.vehicles.append(car)
	return car

func remove_ai_car(car: Node3D) -> void:
	traffic.vehicles.erase(car)
	if is_instance_valid(car):
		car.free()

func hull_clear(car: Node3D) -> bool:
	# Exclude only the car itself, never bodies the last substep overlapped.
	var own: Array[RID] = [car.get_rid()]
	car._drive_exclude = own
	return car._drive_pose_clear(car.global_transform)

func capsule_clear(mask := 2 | 8 | 16) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._capsule.shape
	query.transform = player.global_transform * player._capsule.transform
	query.collision_mask = mask
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box("Ground", Vector3(0, -0.5, 0), Vector3(600, 1, 600), 1)
	# A 9.5m street with 15cm curbs and sidewalks, as in the exported city.
	box("EastSidewalk", Vector3(6.0, 0.075, 0), Vector3(2.5, 0.15, 120), 1)
	box("WestSidewalk", Vector3(-6.0, 0.075, 0), Vector3(2.5, 0.15, 120), 1)
	obstacles.clear()
	level = LevelFixture.new()
	level.name = "DrivingFixtureLevel"
	world.add_child(level)
	level.level_data = {"roads": [{"name": "Fixture Avenue", "width": 9.5, "points": [[0.0, 0.0, 60.0], [0.0, 0.0, -60.0]]}],
		"spawn": {"position": [SPAWN.x, SPAWN.y, SPAWN.z], "yaw": PI}}
	player = Explorer.new()
	player.name = "Explorer"
	level.add_child(player)
	level.player = player
	player.global_position = SPAWN + Vector3.UP * 0.05
	player.yaw = PI
	player.camera_yaw = PI
	player.enabled = true
	combat = CombatStub.new()
	level.add_child(combat)
	level.combat = combat
	traffic = Traffic.new()
	traffic.name = "StreetTraffic"
	level.add_child(traffic)
	traffic.level = level
	# Without a lane network, on_road() falls back to this wide strip.
	var strip: Array[Vector3] = [Vector3(0, 0, -300), Vector3(0, 0, 300)]
	traffic.road_points = strip
	traffic.road_width = 600.0
	level.traffic = traffic
	await frames(4)
	driving = Driving.new()
	level.add_child(driving)
	driving.setup(level)
	renderer = traffic.get_node_or_null("MovingVehicleRenderLOD")
	if renderer != null:
		renderer.set_process(false)
	await frames(2)
	_starter_section()
	if not is_instance_valid(driving.starter):
		_finish()
		return
	await _presence_section()
	await _entry_section()
	physics_car = make_ai_car(OPEN, 0.0, "fixture_physics_car", 0.0)
	check(traffic.claim_external_vehicle(physics_car, "physics_fixture"), "external physics fixture owns the body without enabling player driving")
	await _handling_section()
	await _collision_section()
	await _damage_section()
	traffic.release_external_vehicle(physics_car, "physics_fixture")
	await _exit_section()
	remove_ai_car(physics_car)
	await _ownership_section()
	await _pause_section()
	_finish()

func _finish() -> void:
	print("[city_driving] %d passed, %d failed" % [passes, failures])
	world.queue_free()
	await frames(2)
	get_tree().quit(0 if failures == 0 else 1)

func _starter_section() -> void:
	var status: Dictionary = driving.get_status()
	var starter: Node3D = driving.starter
	if not check(bool(status.starter_spawned) and is_instance_valid(starter) and starter.vehicle_id == "player_starter",
		"starter car spawns from road data near the spawn point (%s)" % str(status.starter)):
		return
	check(traffic.player_fleet.has(starter) and not traffic.vehicles.has(starter) and int(traffic.get_status().total) == traffic.vehicles.size(),
		"starter joins player_fleet, never the AI fleet or its totals")
	var at: Vector3 = starter.global_position
	check(absf(absf(at.x) - 3.63) < 0.06 and absf(at.y - 0.025) < 0.02, "starter sits against the curb, clear of both moving lanes (%s)" % at)
	var offset := Vector3(at.x - SPAWN.x, 0.0, at.z - SPAWN.z)
	check(offset.length() >= 6.0 and offset.length() <= 12.0 and offset.normalized().dot(Vector3(0, 0, -1)) > 0.5,
		"starter is the nearest legal spot ahead of the spawn view (%.1fm)" % offset.length())
	var heading := Vector3(sin(starter.yaw), 0.0, cos(starter.yaw))
	check(heading.dot(Vector3(0, 0, -1) if at.x > 0.0 else Vector3(0, 0, 1)) > 0.999, "starter faces the legal direction for its curb")
	check(starter.state == "parked" and not starter.player_controlled and starter.collision_layer == 16 and starter._hull_clear(starter.global_transform),
		"starter is a parked physical car with a clear hull")
	check(driving.get_map_pois().is_empty() and str(status.starter.street) == "Fixture Avenue" and bool(status.starter.visible_from_spawn),
		"retired starter has no player map point but keeps safe placement")
	check(starter.get_node_or_null("StarterCarLabel") == null, "retired starter carries no player-driving label")
	var pose: Transform3D = starter.global_transform
	for i in 30:
		traffic.tick(DT)
	check(starter.global_transform.is_equal_approx(pose) and starter.state == "parked", "traffic ticks never move or recycle the starter")
	if renderer != null:
		renderer.refresh(starter.global_position + Vector3(0, 0, 150))
		check(starter._render_lod_active and not starter.model.visible, "a parked starter joins the far batch like traffic")
		renderer.refresh(player.camera.global_position)
		check(not starter._render_lod_active and starter.model.visible, "and returns to its exact model nearby")

## Presence drops colliders beyond 65m. At a real curb the parked car's corners
## lie off the lane surface that traffic's activation test requires; a narrow
## fixture road reproduces that for the explorer's return trip.
func _presence_section() -> void:
	var starter: Node3D = driving.starter
	var width: float = traffic.road_width
	traffic.road_width = 4.0
	starter.set_presence(starter.global_position + Vector3(0, 0, 200))
	var dropped: bool = starter.collision_layer == 0 and not starter.near_physics
	await stand(starter.global_position)
	starter.set_presence(player.global_position)
	check(dropped and starter.collision_layer == 0 and bool(starter._presence_blocked),
		"far away the starter drops its collider, which never re-enables around the explorer")
	await stand(SPAWN)
	var lane_test: bool = starter._pose_clear(starter.global_transform)
	starter.set_presence(player.global_position)
	check(not lane_test and starter.collision_layer == 16 and starter.near_physics and not starter._presence_blocked,
		"a curbside starter off the lane surface regains its collider when the explorer returns")
	traffic.road_width = width

func _entry_section() -> void:
	var starter: Node3D = driving.starter
	await stand(door_point(starter))
	driving.tick(0.1)
	check(not driving.get_status().player_driving_enabled and driving.get_status().prompt.is_empty(), "player driving is disabled with no misleading prompt")
	check(not driving.handle_input(key(KEY_F)) and not driving.enter_vehicle(starter), "both F and direct entry refuse player driving")
	check(not driving.active and not player.is_seated() and not starter.player_controlled and combat.cancels == 0, "refused entry leaves player, combat and vehicle ownership untouched")
	level.paused = true
	check(not driving.handle_input(key(KEY_F)), "paused input cannot enter retired driving")
	level.paused = false
	await stand(SPAWN)

func yaw_rate(car: Node3D, speed: float, steer: float) -> float:
	place(car, OPEN, 0.0, speed)
	car.drive_steer = steer
	var before: float = car.yaw
	car.external_step(DT, 0.0, 0.0, steer, false)
	return angle_difference(before, car.yaw) / DT

func turn_sample(car: Node3D, handbrake: bool) -> Dictionary:
	place(car, OPEN, 0.0, 12.0)
	car.drive_steer = 1.0
	var before: float = car.yaw
	var slip := 0.0
	for i in 30:
		car.external_step(DT, 0.0, 0.0, 1.0, handbrake)
		var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
		slip = maxf(slip, absf(car.drive_velocity.dot(Vector3(forward.z, 0.0, -forward.x))))
	return {"yaw": angle_difference(before, car.yaw), "slip": slip, "speed": car.speed}

func _handling_section() -> void:
	var car: Node3D = physics_car
	place(car, OPEN, 0.0)
	await frames(2)
	await drive(120, 1.0)
	check(car.speed > 10.0 and car.speed < Vehicle.DRIVE_MAX_SPEED, "W accelerates smoothly from rest (%.1f m/s after 2s)" % car.speed)
	check(car.global_position.z > OPEN.z + 8.0 and absf(car.global_position.x - OPEN.x) < 0.3, "straight throttle drives along the heading")
	check(not player.is_seated() and not car.player_controlled, "external motion never takes the player seat")
	var behind: Vector3 = player.camera.global_position - car.global_position
	check(behind.is_finite() and not driving.active, "the on-foot camera remains independent of external vehicle motion")
	place(car, OPEN, 0.0, 15.0)
	var start: Vector3 = car.global_position
	var stop_distance := INF
	for i in 200:
		await drive(1, 0.0, 1.0)
		if car.speed <= 0.0 and not is_finite(stop_distance):
			stop_distance = car.global_position.distance_to(start)
	check(stop_distance > 8.0 and stop_distance < 12.0, "S brakes 15 m/s to a stop in %.1fm" % stop_distance)
	check(car.speed < -4.0 and car.speed >= -Vehicle.DRIVE_MAX_REVERSE - 0.01, "holding S after stopping reverses at a bounded speed (%.1f m/s)" % car.speed)
	var slow := yaw_rate(car, 5.0, 1.0)
	var fast := yaw_rate(car, 15.0, 1.0)
	check(slow < 0.0 and fast < 0.0 and yaw_rate(car, 5.0, -1.0) > 0.0, "D steers right and A steers left")
	check(15.0 / absf(fast) > (5.0 / absf(slow)) * 2.0, "steering narrows with speed (radius %.1fm at 5 m/s, %.1fm at 15 m/s)" % [5.0 / absf(slow), 15.0 / absf(fast)])
	check(absf(fast) * 15.0 <= Vehicle.DRIVE_LATERAL_ACCEL + 0.05, "tire grip caps lateral acceleration at speed")
	check(is_zero_approx(yaw_rate(car, 0.0, 1.0)), "a stationary car cannot spin in place")
	var normal := turn_sample(car, false)
	var drift := turn_sample(car, true)
	check(absf(float(drift.yaw)) > absf(float(normal.yaw)) * 1.15 and float(drift.slip) > float(normal.slip) + 0.5,
		"Space handbrake swings the tail: more yaw (%.2f vs %.2f rad) and a sideways slide" % [drift.yaw, normal.yaw])
	check(float(drift.speed) < float(normal.speed) - 1.0, "the handbrake also scrubs speed")
	place(car, OPEN, 0.0, 0.0)
	var parked_at: Vector3 = car.global_position
	await drive(30, 1.0, 0.0, 0.0, true)
	check(absf(car.speed) < 0.01 and car.global_position.distance_to(parked_at) < 0.01, "a held handbrake keeps a stopped car in place under throttle")
	var orbit_before: float = player.vehicle_orbit_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(300, 0)
	motion.screen_relative = Vector2(300, 0)
	check(not driving.handle_input(motion) and is_equal_approx(player.vehicle_orbit_yaw, orbit_before), "retired driving does not steal mouse look")
	place(car, OPEN, 0.0, 10.0)
	await drive(150, 0.6)
	check(is_equal_approx(player.vehicle_orbit_yaw, orbit_before), "external movement leaves player orbit unchanged")

func _collision_section() -> void:
	var car: Node3D = physics_car
	var half := half_size(car).z
	var wall_z := OPEN.z + 14.0
	box("HeadOnWall", Vector3(OPEN.x, 1.5, wall_z), Vector3(10, 3, 0.2), 2)
	await frames(2)
	place(car, OPEN, 0.0, 20.0)
	var impacts: int = physics_impacts
	var deepest := -INF
	var clear := true
	for i in 90:
		await drive(1, 1.0)
		deepest = maxf(deepest, car.global_position.z + half)
		clear = clear and hull_clear(car)
	check(clear and deepest < wall_z - 0.1 + 0.02, "a 20 m/s head-on sweep stops at the wall face (front %.3f, face %.3f)" % [deepest, wall_z - 0.1])
	check(absf(car.speed) < 0.6 and physics_impacts == impacts + 1 and physics_contact.kind == "structure" and float(physics_contact.speed) > 15.0,
		"the crash is reported once with its closing speed (%s)" % str(physics_contact))
	clear_obstacles()
	var thin_z := OPEN.z + 6.0
	box("ThinWall", Vector3(OPEN.x, 1.5, thin_z), Vector3(10, 3, 0.1), 2)
	await frames(2)
	place(car, OPEN, 0.0, 24.0)
	deepest = -INF
	for i in 6:
		step_physics(0.1, 1.0, 0.0, 0.0, false)
		deepest = maxf(deepest, car.global_position.z + half)
		await get_tree().physics_frame
	driving.clear_control_override()
	check(deepest < thin_z - 0.05 + 0.02 and hull_clear(car), "0.1s frames at 24 m/s cannot tunnel through a 10cm wall")
	clear_obstacles()
	# A long wall 20 degrees off the heading: the corner meets it, then slides.
	box("GlancingWall", OPEN + Vector3(2.5, 1.5, 14.0), Vector3(0.3, 3, 40), 2, deg_to_rad(20.0))
	await frames(2)
	place(car, OPEN, 0.0, 15.0)
	var contacts: int = car.drive_contacts
	clear = true
	for i in 60:
		await drive(1, 1.0)
		clear = clear and hull_clear(car)
	check(car.drive_contacts > contacts and clear and car.speed > 3.0 and car.global_position.z > OPEN.z + 8.0 and car.global_position.x > OPEN.x + 0.5,
		"a glancing wall contact slides along the surface without entering it (%.1f m/s, at %s, contacts %d, hull clear %s)" % [car.speed, car.global_position, car.drive_contacts - contacts, clear])
	clear_obstacles()
	var person := CharacterBody3D.new()
	person.name = "Pedestrian"
	person.collision_layer = 8
	person.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var person_shape := CollisionShape3D.new()
	person_shape.shape = capsule
	person_shape.position.y = 0.85
	person.add_child(person_shape)
	world.add_child(person)
	person.global_position = OPEN + Vector3(0.0, 0.0, 12.0)
	obstacles.append(person)
	await frames(2)
	var person_at := person.global_position
	place(car, OPEN, 0.0, 12.0)
	for i in 120:
		await drive(1, 0.6)
	check(car.global_position.z + half < person_at.z - 0.3 + 0.02 and person.global_position.is_equal_approx(person_at) and hull_clear(car),
		"a pedestrian body stops the car before it; nobody is pushed or entered")
	check(physics_contact.kind == "person", "pedestrian contact is classified for root/law hooks")
	clear_obstacles()
	place(car, OPEN, 0.0, 0.0)
	await frames(2)
	var other := make_ai_car(OPEN + Vector3(0.0, 0.0, 14.0), 0.0, "fixture_obstacle_car")
	other.state = "parked"
	await frames(2)
	var other_pose: Transform3D = other.global_transform
	place(car, OPEN, 0.0, 12.0)
	for i in 120:
		await drive(1, 0.6)
	check(car.global_position.z + half < other.global_position.z - half_size(other).z + 0.02 and other.global_transform.is_equal_approx(other_pose) and hull_clear(car),
		"a traffic car stops the driven car without being displaced")
	check(physics_contact.kind == "vehicle", "vehicle contact is classified")
	remove_ai_car(other)
	# A 15cm curb is mounted at an angle; a 60cm riser is a wall. Use a wide
	# platform so the first front sample cannot leave its far edge in the same
	# update that the rear sample mounts it (the street sidewalks are 2.5m).
	var curb_start := OPEN + Vector3(0.0, 0.0, -40.0)
	box("CurbPlatform", curb_start + Vector3(7.75, 0.075, 0.0), Vector3(6.0, 0.15, 30.0), 1)
	await frames(2)
	place(car, curb_start + Vector3(2.0, 0.0, 0.0), deg_to_rad(60.0), 6.0)
	for i in 120:
		await drive(1, 0.4)
		if car.global_position.x >= curb_start.x + 6.0:
			break
	check(car.global_position.x >= curb_start.x + 6.0 and absf(car.global_position.y - 0.175) < 0.03 and hull_clear(car), "a 15cm curb is mounted at an angle (%s)" % car.global_position)
	clear_obstacles()
	var riser_face := OPEN.z + 8.0
	box("TallRiser", OPEN + Vector3(0.0, 0.3, 10.0), Vector3(10, 0.6, 4), 1)
	await frames(2)
	place(car, OPEN, 0.0, 8.0)
	for i in 90:
		await drive(1, 0.8)
	check(car.global_position.y < 0.1 and car.global_position.z + half < riser_face + 0.02 and car.last_drive_contact.kind == "terrain",
		"a 60cm terrain riser stops the bumper at its face like a wall")
	clear_obstacles()

func top_speed(car: Node3D, count: int) -> float:
	place(car, LONG_START, 0.0, 0.0)
	var best := 0.0
	for i in count:
		# Hold the heading; a flat tire pulls otherwise.
		car.external_step(DT, 1.0, 0.0, clampf(car.yaw * 3.0, -1.0, 1.0), false)
		best = maxf(best, car.speed)
	return best

func braking_distance(car: Node3D, speed: float) -> float:
	place(car, LONG_START, 0.0, speed)
	var start: Vector3 = car.global_position
	for i in 300:
		car.external_step(DT, 0.0, 1.0, clampf(car.yaw * 3.0, -1.0, 1.0), false)
		if car.speed <= 0.0:
			break
	return car.global_position.distance_to(start)

func pull_drift(car: Node3D) -> float:
	place(car, LONG_START, 0.0, 10.0)
	var before: float = car.yaw
	for i in 60:
		car.drive_velocity = Vector3(sin(car.yaw), 0.0, cos(car.yaw)) * 10.0
		car.external_step(DT, 0.0, 0.0, 0.0, false)
	return angle_difference(before, car.yaw)

func _damage_section() -> void:
	var car: Node3D = physics_car
	var healthy_top := top_speed(car, 480)
	var healthy_stop := braking_distance(car, 12.0)
	var healthy_rate := absf(yaw_rate(car, 15.0, 1.0))
	check(is_zero_approx(pull_drift(car)), "a healthy car tracks straight with centred steering")
	place(car, LONG_START, 0.0)
	car.receive_gunshot({"tire_index": 0}, car.global_position + Vector3.LEFT * 3.0)
	check(car.flat_tires.size() == 1 and car.flat_tires[0] == 0 and car.force_detailed and car.model.visible and not car._render_lod_active,
		"tire damage on an externally controlled car keeps its exact model")
	var flat_top := top_speed(car, 480)
	check(healthy_top > 20.0 and flat_top <= Vehicle.DRIVE_MAX_SPEED * 0.70 + 0.05 and flat_top > 12.0,
		"one flat caps top speed by the existing tire speed factor (%.1f -> %.1f m/s)" % [healthy_top, flat_top])
	var flat_stop := braking_distance(car, 12.0)
	check(flat_stop > healthy_stop * 1.25, "one flat lengthens measured braking distance (%.1fm -> %.1fm)" % [healthy_stop, flat_stop])
	var pull_minus := pull_drift(car)
	var kerb_side: Array[int] = [1]
	car.flat_tires = kerb_side
	var pull_plus := pull_drift(car)
	check(pull_minus < -0.05 and pull_plus > 0.05, "a flat pulls toward its own side (-X %.2f rad, +X %.2f rad)" % [pull_minus, pull_plus])
	# Front flats on both sides cancel their pull, isolating the grip loss.
	var both_front: Array[int] = [0, 1]
	car.flat_tires = both_front
	check(absf(pull_drift(car)) < 0.01 and absf(yaw_rate(car, 15.0, 1.0)) < healthy_rate * 0.9,
		"reduced tire grip lowers the achievable cornering rate (%.2f vs %.2f rad/s)" % [absf(yaw_rate(car, 15.0, 1.0)), healthy_rate])
	car.flat_tires.clear()
	car._update_wheels()
	await frames(1)

func _exit_section() -> void:
	var car: Node3D = physics_car
	clear_obstacles()
	place(car, OPEN, 0.0)
	await frames(2)
	var lateral := half_size(car).x + 0.50
	check(not driving._exit_spot(car, lateral, 0.25, true).is_empty(), "legacy safe-placement helper finds a clear door")
	box("DriverWall", car.global_position + Vector3(half_size(car).x + 0.25, 1.2, 0), Vector3(0.2, 2.4, 8), 2)
	await frames(2)
	check(driving._exit_spot(car, lateral, 0.25, true).is_empty() and not driving._exit_spot(car, -lateral, 0.25, true).is_empty(), "safe placement refuses a wall and accepts the opposite clear side")
	clear_obstacles()
	box("Fence", car.global_position + Vector3(half_size(car).x + 0.115, 1, 0), Vector3(0.05, 2, 8), 2)
	await frames(2)
	check(driving._exit_spot(car, lateral, 0.25, true).is_empty(), "safe-placement sweep refuses a thin fence")
	clear_obstacles()
	box("LeftBox", car.global_position + Vector3(lateral - 0.3, 1.2, 0), Vector3(0.2, 2.4, 6), 2)
	box("RightBox", car.global_position + Vector3(-lateral + 0.3, 1.2, 0), Vector3(0.2, 2.4, 6), 2)
	await frames(2)
	check(driving._exit_spot(car, lateral, 0.25, true).is_empty() and driving._exit_spot(car, -lateral, 0.25, true).is_empty(), "boxed-in legacy door placements are both refused")
	check(not driving.active and not player.is_seated() and capsule_clear(), "placement probes never seat or teleport the player")
	clear_obstacles()
	var before: Vector3 = player.global_position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(before) > 0.5, "walking stays available after refused driving and placement probes")

func _ownership_section() -> void:
	var ai := make_ai_car(AI_SPOT, 0.0, "fixture_taxi", 0.0)
	traffic.reservations["fixture_junction"] = ai
	ai.reservation_id = "fixture_junction"
	var follower := make_ai_car(AI_SPOT - Vector3(0, 0, 14), 0.0, "fixture_follower")
	follower.state = "parked"
	var moving := make_ai_car(AI_SPOT + Vector3(9, 0, 0), 0.0, "fixture_moving")
	moving.speed = 8.0
	var patrol := make_ai_car(AI_SPOT + Vector3(-9, 0, 0), 0.0, "fixture_patrol", 9.0, true)
	for car in [ai, moving, patrol]:
		check(not driving.enter_vehicle(car) and not car.player_controlled, "policy refuses civilian, moving and patrol entry: " + str(car.vehicle_id))
	check(traffic.reservations.has("fixture_junction") and ai.reservation_id == "fixture_junction", "refused player entry does not steal AI reservations")
	check(traffic.claim_external_vehicle(ai, "fixture_dispatch"), "legitimate external ownership remains available")
	check(not traffic.reservations.has("fixture_junction"), "external ownership releases the junction reservation")
	var pose: Transform3D = ai.global_transform
	for i in 30:
		ai.tick(DT)
	check(ai.global_transform.is_equal_approx(pose) and not ai.try_recycle() and not ai.can_tick_damage_coarsely(), "AI cannot move, recycle or coarse-tick an externally owned car")
	traffic._update_leaders()
	check(is_finite(follower.leader_distance), "traffic queues behind an externally owned car")
	check(traffic.release_external_vehicle(ai, "fixture_dispatch") and ai.state == "parked" and not ai.player_controlled, "external release leaves a parked non-player car")
	check(not driving.active and not player.is_seated(), "ownership tests never enable a player vehicle")
	for car in [ai, follower, moving, patrol]:
		remove_ai_car(car)
	await frames(2)

func _pause_section() -> void:
	var car: Node3D = driving.starter
	place(car, OPEN, 0.0)
	var pose: Transform3D = car.global_transform
	var ticks: int = driving.paused_ticks
	driving.set_control_override(1.0, 0.0, 1.0, false)
	level.paused = true
	for i in 30:
		driving.tick(DT)
	check(car.global_transform.is_equal_approx(pose) and driving.paused_ticks == ticks + 30, "pause gates the manager despite a control override")
	check(not driving.handle_input(key(KEY_F)) and not driving.active, "pause cannot activate driving")
	level.paused = false
	get_tree().paused = true
	driving.tick(DT)
	check(car.global_transform.is_equal_approx(pose), "tree pause also gates the manager")
	get_tree().paused = false
	for i in 30:
		driving.tick(DT)
	driving.clear_control_override()
	check(car.global_transform.is_equal_approx(pose) and not driving.active, "unpausing does not bypass disabled player-driving policy")
