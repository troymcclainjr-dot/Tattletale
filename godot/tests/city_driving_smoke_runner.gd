extends Node
## Standalone driving regressions on the production explorer, CharacterBody3D
## vehicles, traffic manager and driving manager over real static collision:
## starter placement, entry authority, AI ownership, handling, collision sweeps,
## tire damage, safe dismount, render LOD and pause gating.
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
	driving.set_control_override(throttle, brake, steer, handbrake)
	for i in count:
		traffic.tick(DT)
		driving.tick(DT)
		await get_tree().physics_frame
	driving.clear_control_override()

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
	await _handling_section()
	await _collision_section()
	await _damage_section()
	await _exit_section()
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
	check(driving.get_map_pois().size() == 1 and str(status.starter.street) == "Fixture Avenue" and bool(status.starter.visible_from_spawn),
		"starter exposes a map point and was chosen in view of the spawn")
	check(starter.get_node_or_null("StarterCarLabel") is Label3D, "starter carries a YOUR CAR / F label")
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
	await stand(Vector3(20, 0.0, 10))
	driving.tick(0.1)
	check(level.notices.size() == 1 and "press F" in level.notices[0], "approaching the starter announces the F prompt once")
	check(driving.get_status().prompt == "" and not driving.handle_input(key(KEY_F)) and not driving.active,
		"away from cars F is not consumed and nothing is boarded")
	await stand(door_point(starter, 1.0))
	driving.tick(0.1)
	var status: Dictionary = driving.get_status()
	check(status.prompt == "F  Drive your car" and status.candidate_id == "player_starter", "at the starter's door the HUD prompt offers F (%s)" % status.prompt)
	level.paused = true
	check(not driving.handle_input(key(KEY_F)) and not driving.active, "a paused level ignores F")
	level.paused = false
	combat.downed = 1.0
	check(driving.handle_input(key(KEY_F)) and not driving.active and "breath" in driving.get_status().prompt, "a downed explorer is refused with a reason")
	combat.downed = 0.0
	player.impact_recovery = 0.4
	check(not driving.enter_vehicle(starter) and not driving.active, "a stumbling explorer cannot board")
	player.impact_recovery = 0.0
	driving._message_time = 0.0
	var cancels := combat.cancels
	check(driving.handle_input(key(KEY_F)) and driving.active and driving.vehicle == starter, "F at the door boards the starter car")
	check(starter.player_controlled and starter.force_detailed and starter.state == "player", "the occupied car leaves AI control and forces detailed LOD")
	check(player.is_seated() and player.collision_layer == 0 and player.collision_mask == 0 and not player.puppet.g.visible,
		"the seated explorer has no collider and a hidden puppet")
	check(player.global_position.distance_to(starter.global_position) < 0.01, "the explorer rides at the car origin for streaming and presence")
	check(not player.request_jump() and not player.receive_vehicle_impact(Vector3(0, 0, 1), 12.0) and not player.is_standing_on_vehicle(starter),
		"a seated explorer cannot jump, stumble or ride a roof")
	check(combat.cancels == cancels + 1, "boarding cancels held combat actions")
	check(not driving.enter_vehicle(starter) and driving.vehicle == starter, "only one car can be occupied at a time")
	driving.tick(DT)
	check(driving.get_status().prompt == "F  Get out" and bool(driving.get_status().exit_available), "stopped in the open, the prompt offers F to get out")
	if renderer != null:
		renderer.refresh(starter.global_position + Vector3(0, 0, 150))
		check(not starter._render_lod_active and starter.model.visible, "the occupied car keeps its exact model at far viewer distance")
		renderer.refresh(starter.global_position + Vector3(0, 0, 900))
		check(starter.model.visible, "even beyond the visual cutoff (inspector or overview camera)")

func yaw_rate(car: Node3D, speed: float, steer: float) -> float:
	place(car, OPEN, 0.0, speed)
	car.drive_steer = steer
	var before: float = car.yaw
	car.player_step(DT, 0.0, 0.0, steer, false)
	return angle_difference(before, car.yaw) / DT

func turn_sample(car: Node3D, handbrake: bool) -> Dictionary:
	place(car, OPEN, 0.0, 12.0)
	car.drive_steer = 1.0
	var before: float = car.yaw
	var slip := 0.0
	for i in 30:
		car.player_step(DT, 0.0, 0.0, 1.0, handbrake)
		var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
		slip = maxf(slip, absf(car.drive_velocity.dot(Vector3(forward.z, 0.0, -forward.x))))
	return {"yaw": angle_difference(before, car.yaw), "slip": slip, "speed": car.speed}

func _handling_section() -> void:
	var car: Node3D = driving.vehicle
	place(car, OPEN, 0.0)
	await frames(2)
	await drive(120, 1.0)
	check(car.speed > 10.0 and car.speed < Vehicle.DRIVE_MAX_SPEED, "W accelerates smoothly from rest (%.1f m/s after 2s)" % car.speed)
	check(car.global_position.z > OPEN.z + 8.0 and absf(car.global_position.x - OPEN.x) < 0.3, "straight throttle drives along the heading")
	check(player.global_position.distance_to(car.global_position) < 0.01, "the seat follows every driven step")
	var behind: Vector3 = player.camera.global_position - car.global_position
	check(behind.dot(Vector3(sin(car.yaw), 0.0, cos(car.yaw))) < -3.0 and behind.y > 1.0, "the chase camera sits behind and above the car")
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
	check(driving.handle_input(motion) and player.vehicle_orbit_yaw < orbit_before - 0.5, "mouse motion orbits the chase camera")
	place(car, OPEN, 0.0, 10.0)
	await drive(150, 0.6)
	check(absf(player.vehicle_orbit_yaw) < 0.2, "a released orbit recenters behind the moving car")

func _collision_section() -> void:
	var car: Node3D = driving.vehicle
	var half := half_size(car).z
	var wall_z := OPEN.z + 14.0
	box("HeadOnWall", Vector3(OPEN.x, 1.5, wall_z), Vector3(10, 3, 0.2), 2)
	await frames(2)
	place(car, OPEN, 0.0, 20.0)
	var impacts: int = driving.impacts
	var deepest := -INF
	var clear := true
	for i in 90:
		await drive(1, 1.0)
		deepest = maxf(deepest, car.global_position.z + half)
		clear = clear and hull_clear(car)
	check(clear and deepest < wall_z - 0.1 + 0.02, "a 20 m/s head-on sweep stops at the wall face (front %.3f, face %.3f)" % [deepest, wall_z - 0.1])
	check(absf(car.speed) < 0.6 and driving.impacts == impacts + 1 and driving.last_impact.kind == "structure" and float(driving.last_impact.speed) > 15.0,
		"the crash is reported once with its closing speed (%s)" % str(driving.last_impact))
	clear_obstacles()
	var thin_z := OPEN.z + 6.0
	box("ThinWall", Vector3(OPEN.x, 1.5, thin_z), Vector3(10, 3, 0.1), 2)
	await frames(2)
	place(car, OPEN, 0.0, 24.0)
	deepest = -INF
	driving.set_control_override(1.0, 0.0, 0.0, false)
	for i in 6:
		driving.tick(0.1)
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
	check(driving.last_impact.kind == "person", "pedestrian contact is classified for root/law hooks")
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
	check(driving.last_impact.kind == "vehicle", "vehicle contact is classified")
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
		car.player_step(DT, 1.0, 0.0, clampf(car.yaw * 3.0, -1.0, 1.0), false)
		best = maxf(best, car.speed)
	return best

func braking_distance(car: Node3D, speed: float) -> float:
	place(car, LONG_START, 0.0, speed)
	var start: Vector3 = car.global_position
	for i in 300:
		car.player_step(DT, 0.0, 1.0, clampf(car.yaw * 3.0, -1.0, 1.0), false)
		if car.speed <= 0.0:
			break
	return car.global_position.distance_to(start)

func pull_drift(car: Node3D) -> float:
	place(car, LONG_START, 0.0, 10.0)
	var before: float = car.yaw
	for i in 60:
		car.drive_velocity = Vector3(sin(car.yaw), 0.0, cos(car.yaw)) * 10.0
		car.player_step(DT, 0.0, 0.0, 0.0, false)
	return angle_difference(before, car.yaw)

func _damage_section() -> void:
	var car: Node3D = driving.vehicle
	var healthy_top := top_speed(car, 480)
	var healthy_stop := braking_distance(car, 12.0)
	var healthy_rate := absf(yaw_rate(car, 15.0, 1.0))
	check(is_zero_approx(pull_drift(car)), "a healthy car tracks straight with centred steering")
	place(car, LONG_START, 0.0)
	car.receive_gunshot({"tire_index": 0}, car.global_position + Vector3.LEFT * 3.0)
	check(car.flat_tires.size() == 1 and car.flat_tires[0] == 0 and car.force_detailed and car.model.visible and not car._render_lod_active,
		"a shot tire on the occupied car keeps its exact damaged model")
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
	var car: Node3D = driving.vehicle
	clear_obstacles()
	place(car, OPEN, 0.0, 5.0)
	await frames(2)
	var refused: int = driving.refused_exits
	check(not driving.exit_vehicle(false) and driving.active and driving.refused_exits == refused + 1 and "Stop" in driving.get_status().prompt,
		"a moving car refuses a normal exit")
	place(car, OPEN, 0.0, 0.0)
	await frames(2)
	driving._message_time = 0.0
	driving._exit_clock = 0.0
	driving.tick(DT)
	check(driving.get_status().prompt == "F  Get out", "a stopped car in the open offers F to get out")
	check(driving.handle_input(key(KEY_F)) and not driving.active and driving.last_exit.door == "driver", "F exits through the driver's door")
	var local: Vector3 = car.global_transform.affine_inverse() * player.global_position
	check(local.x > 0.9 and absf(local.z) < 1.0, "the explorer stands beside the driver's (+X) door (%s)" % local)
	check(not player.is_seated() and player.collision_layer == 4 and player.collision_mask == (1 | 2 | 8 | 16) and player.puppet.g.visible,
		"exit restores the solid explorer and its puppet")
	check(not car.player_controlled and car.player_released and car.state == "parked" and car.speed == 0.0 and not car.force_detailed,
		"the car is left parked and returns to normal LOD")
	await frames(2)
	check(capsule_clear(), "the explorer's capsule overlaps nothing after the exit")
	if renderer != null:
		renderer.refresh(car.global_position + Vector3(0, 0, 150))
		check(car._render_lod_active, "after exit the parked car rejoins the far batch")
		renderer.refresh(player.camera.global_position)
	var before: Vector3 = player.global_position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(before) > 0.5, "walking controls resume immediately after exit")
	# A wall at the driver's door: the kerb-side door is used instead.
	check(await board(car), "re-boarding for the blocked-door case")
	place(car, OPEN, 0.0, 0.0)
	var side_x: float = half_size(car).x
	box("DriverWall", car.global_position + Vector3(side_x + 0.25, 1.2, 0.0), Vector3(0.2, 2.4, 8.0), 2)
	await frames(2)
	check(driving.exit_vehicle(false) and driving.last_exit.door == "passenger" and (car.global_transform.affine_inverse() * player.global_position).x < -0.9,
		"a wall at the driver's door sends the explorer out the kerb side")
	check(capsule_clear(), "the kerb-side exit is clear of the wall and the car")
	clear_obstacles()
	# A thin fence beside the door: the spot beyond it is free, the path is not.
	check(await board(car), "re-boarding for the fence case")
	place(car, OPEN, 0.0, 0.0)
	box("Fence", car.global_position + Vector3(side_x + 0.115, 1.0, 0.0), Vector3(0.05, 2.0, 8.0), 2)
	await frames(2)
	check(driving.exit_vehicle(false) and driving.last_exit.door == "passenger", "no exit is placed through a fence the body cannot pass")
	clear_obstacles()
	# Boxed in on all sides: normal exit refused, forced exit still places the explorer.
	check(await board(car), "re-boarding for the boxed-in case")
	place(car, OPEN, 0.0, 0.0)
	var length_half: float = half_size(car).z
	box("LeftBox", car.global_position + Vector3(side_x + 0.2, 1.2, 0.0), Vector3(0.2, 2.4, 6.0), 2)
	box("RightBox", car.global_position + Vector3(-side_x - 0.2, 1.2, 0.0), Vector3(0.2, 2.4, 6.0), 2)
	box("FrontBox", car.global_position + Vector3(0.0, 1.2, length_half + 0.2), Vector3(3.0, 2.4, 0.2), 2)
	box("RearBox", car.global_position + Vector3(0.0, 1.2, -length_half - 0.2), Vector3(3.0, 2.4, 0.2), 2)
	await frames(2)
	refused = driving.refused_exits
	check(not driving.exit_vehicle(false) and driving.active and driving.refused_exits == refused + 1, "a boxed-in car refuses a normal exit")
	driving._message_time = 0.0
	driving.tick(DT)
	check("No room" in driving.get_status().prompt, "the prompt explains that there is no room to get out")
	check(not driving.recovery_exit_at(car.global_position + Vector3(side_x + 0.2, 0.05, 0.0), car.yaw) and driving.active,
		"a recovery destination inside a wall is refused and the explorer stays seated")
	check(driving.exit_vehicle(true) and not driving.active and bool(driving.last_exit.forced), "a forced exit (arrest, defeat) widens the search past boxed-in doors")
	await frames(2)
	check(capsule_clear(2), "the forced exit never places the explorer inside a wall")
	clear_obstacles()
	# Recovery detaches at a separately validated destination (facility).
	check(await board(car), "re-boarding for the recovery destination case")
	var release := Vector3(car.global_position.x + 6.0, ground_y(car.global_position + Vector3(6.0, 0.0, 0.0)) + 0.05, car.global_position.z)
	check(driving.recovery_exit_at(release, 0.0) and not driving.active and driving.last_exit.door == "recovery" and player.global_position.is_equal_approx(release),
		"recovery_exit_at places the explorer at a clear validated destination")
	await frames(2)
	check(capsule_clear() and car.state == "parked" and not car.player_controlled, "the recovery exit leaves the car parked and the explorer solid")
	# A root teleport while seated (respawn, checkpoint) releases the car in place.
	check(await board(car), "re-boarding for the relocation case")
	var car_at: Vector3 = car.global_position
	player.global_position = Vector3(40, 0.05, 40)
	driving.tick(DT)
	check(not driving.active and driving.last_exit.door == "relocated" and player.global_position.distance_to(Vector3(40, 0.05, 40)) < 0.01 and car.global_position.is_equal_approx(car_at),
		"a teleport while seated releases the car where it stopped and keeps the new spot")
	await frames(2)

func _ownership_section() -> void:
	var ai := make_ai_car(AI_SPOT, 0.0, "fixture_taxi", 0.0)
	traffic.reservations["fixture_junction"] = ai
	ai.reservation_id = "fixture_junction"
	var follower := make_ai_car(AI_SPOT - Vector3(0.0, 0.0, 14.0), 0.0, "fixture_follower")
	follower.state = "parked"
	var moving := make_ai_car(AI_SPOT + Vector3(9.0, 0.0, 0.0), 0.0, "fixture_moving")
	moving.state = "parked"
	moving.speed = 8.0
	var patrol := make_ai_car(AI_SPOT + Vector3(-9.0, 0.0, 0.0), 0.0, "fixture_patrol", 9.0, true)
	patrol.state = "parked"
	await frames(2)
	await stand(door_point(moving, 1.0))
	driving.tick(0.1)
	check(driving.get_status().candidate_id != "fixture_moving" and not driving.enter_vehicle(moving), "a moving traffic car cannot be boarded")
	remove_ai_car(moving)
	await stand(door_point(patrol, 1.0))
	driving.tick(0.1)
	check(driving.get_status().candidate_id != "fixture_patrol" and not driving.enter_vehicle(patrol), "patrol cars are not civilian cars to take")
	await stand(door_point(ai, 1.0))
	driving._message_time = 0.0
	driving.tick(0.1)
	check(driving.get_status().prompt == "F  Drive this car", "a stopped civilian car offers F")
	check(driving.handle_input(key(KEY_F)) and driving.vehicle == ai, "F boards the stopped traffic car")
	check(not traffic.reservations.has("fixture_junction") and ai.reservation_id == "", "boarding releases the car's junction reservation")
	var pose: Transform3D = ai.global_transform
	for i in 60:
		traffic.tick(DT)
		ai.tick(DT)
	check(ai.global_transform.is_equal_approx(pose), "neither traffic.tick nor a direct AI tick moves the occupied car")
	check(not ai.try_recycle() and ai.recycled == 0 and not ai.can_tick_damage_coarsely(), "the occupied car is never recycled or coarse-ticked")
	traffic._update_leaders()
	check(is_finite(follower.leader_distance) and follower.leader_distance < 9.0, "AI followers queue behind the player's car (%.1fm)" % follower.leader_distance)
	place(ai, AI_SPOT, PI * 0.5)
	traffic._update_leaders()
	check(is_finite(follower.leader_distance), "a player car turned across the lane still blocks it")
	var status: Dictionary = traffic.get_status()
	check(int(status.player_controlled) == 1 and int(status.total) == traffic.vehicles.size(), "traffic status counts the occupied car without changing fleet totals")
	place(ai, AI_SPOT, 0.0)
	await frames(2)
	check(driving.exit_vehicle(false) and ai.player_released and ai.state == "parked" and not ai.player_controlled, "exit leaves the traffic car parked and released")
	var parked: Transform3D = ai.global_transform
	for i in 30:
		traffic.tick(DT)
	check(ai.global_transform.is_equal_approx(parked) and not ai.try_recycle(), "a released car stays parked near the explorer instead of being recycled")
	traffic._update_leaders()
	check(is_finite(follower.leader_distance), "a released car still blocks its lane")
	remove_ai_car(ai)
	remove_ai_car(follower)
	remove_ai_car(patrol)
	await frames(2)

func _pause_section() -> void:
	var car: Node3D = driving.starter
	check(await board(car), "boarding the starter for pause checks")
	place(car, OPEN, 0.0, 0.0)
	await drive(60, 1.0)
	var speed: float = car.speed
	var pose: Transform3D = car.global_transform
	var seat: Vector3 = player.global_position
	var eye: Vector3 = player.camera.global_position
	var ticks: int = driving.paused_ticks
	driving.set_control_override(1.0, 0.0, 0.0, false)
	level.paused = true
	player.enabled = false
	for i in 30:
		driving.tick(DT)
		await get_tree().physics_frame
	check(car.global_transform.is_equal_approx(pose) and player.global_position.is_equal_approx(seat) and driving.paused_ticks == ticks + 30,
		"a paused level (menu, map, inspector) freezes the car and seat despite held throttle")
	check(is_equal_approx(car.speed, speed) and player.camera.global_position.is_equal_approx(eye), "the paused car keeps its speed and the chase view does not drift")
	check(not driving.handle_input(key(KEY_F)) and driving.active, "F is ignored while paused")
	level.paused = false
	get_tree().paused = true
	driving.tick(DT)
	check(car.global_transform.is_equal_approx(pose), "a paused scene tree also freezes driving")
	get_tree().paused = false
	player.enabled = true
	for i in 10:
		driving.tick(DT)
		await get_tree().physics_frame
	driving.clear_control_override()
	check(car.global_position.distance_to(pose.origin) > 0.5, "driving resumes when the pause ends")
	place(car, car.global_position, car.yaw, 0.0)
	await frames(2)
	check(driving.exit_vehicle(true) and not driving.active, "cleanup exit")
