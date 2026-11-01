extends Node
## Shared standalone world for the vehicle contract fixtures: the production
## explorer, CityVehicle bodies, traffic manager, a real curbside parked batch
## (city_parked_cars.setup on a 9.5m curb) and the driving manager, over static
## collision. Runners extend this, set `tag` and implement run_sections().
## Loaded by a SceneTree wrapper so the G/Hud autoloads exist first.
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Explorer := preload("res://scripts/city/city_player.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Driving := preload("res://scripts/city/city_driving.gd")
const ParkedCars := preload("res://scripts/city/city_parked_cars.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const DT := 1.0 / 60.0
const SPAWN := Vector3(5.0, 0.15, 10.0)
const OPEN := Vector3(-80.0, 0.0, -150.0)
const LANE_X := 200.0

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
	func vector(value) -> Vector3:
		if value is Vector3:
			return value
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

class CombatStub:
	extends Node3D
	var downed := 0.0
	var cancels := 0
	func blocks_movement() -> bool:
		return downed > 0.0
	func cancel_player_actions() -> void:
		cancels += 1

## A resident-like body: layer 8 with the actor_id property combat reads.
class PersonStub:
	extends CharacterBody3D
	var actor_id := ""

var tag := "vehicle_contract"
var world: Node3D
var level: LevelFixture
var player: CharacterBody3D
var traffic: Node3D
var parked: Node3D
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
	print("[%s] %s %s" % [tag, "PASS" if ok else "FAIL", label])
	return ok

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	await build_world()
	var prepared := check(is_instance_valid(driving.starter), "fixture starter car spawned (%s)" % str(driving.starter_report))
	prepared = check(parked.records.size() >= 16, "fixture curb holds a real parked batch (%d records)" % parked.records.size()) and prepared
	if prepared:
		await run_sections()
	await finish()

## Overridden by each runner.
func run_sections() -> void:
	pass

func finish() -> void:
	driving.clear_control_override()
	print("[%s] %d passed, %d failed" % [tag, passes, failures])
	world.queue_free()
	await frames(2)
	get_tree().quit(0 if failures == 0 else 1)

func build_world() -> void:
	world = Node3D.new()
	add_child(world)
	box("Ground", Vector3(100, -0.5, 0), Vector3(900, 1, 900), 1)
	# Starter Street is 7.5m: wide enough for the starter, too narrow to park.
	box("StarterEast", Vector3(5.0, 0.075, 0), Vector3(2.5, 0.15, 120), 1)
	box("StarterWest", Vector3(-5.0, 0.075, 0), Vector3(2.5, 0.15, 120), 1)
	# Parked Lane is 9.5m with continuous 15cm curbs: single-side curb parking.
	box("LaneEast", Vector3(LANE_X + 6.0, 0.075, 0), Vector3(2.5, 0.15, 200), 1)
	box("LaneWest", Vector3(LANE_X - 6.0, 0.075, 0), Vector3(2.5, 0.15, 200), 1)
	obstacles.clear()
	level = LevelFixture.new()
	level.name = "VehicleContractLevel"
	world.add_child(level)
	level.level_data = {"roads": [
		{"name": "Starter Street", "width": 7.5, "points": [[0.0, 0.0, 60.0], [0.0, 0.0, -60.0]]},
		{"name": "Parked Lane", "width": 9.5, "points": [[LANE_X, 0.0, 100.0], [LANE_X, 0.0, -100.0]]}],
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
	var strip: Array[Vector3] = [Vector3(0, 0, -400), Vector3(0, 0, 400)]
	traffic.road_points = strip
	traffic.road_width = 800.0
	level.traffic = traffic
	await frames(4)
	parked = ParkedCars.new()
	traffic.add_child(parked)
	traffic.parked = parked
	parked.setup(level, traffic)
	await frames(2)
	driving = Driving.new()
	level.add_child(driving)
	driving.setup(level)
	renderer = traffic.get_node_or_null("MovingVehicleRenderLOD")
	if renderer != null:
		renderer.set_process(false)
	await frames(2)

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

func person(at: Vector3, actor_id := "", crowd_index := -1) -> CharacterBody3D:
	var body := PersonStub.new()
	body.name = "Person_" + (actor_id if not actor_id.is_empty() else str(crowd_index))
	body.actor_id = actor_id
	if crowd_index >= 0:
		body.set_meta("city_crowd_index", crowd_index)
	body.collision_layer = 8
	body.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85
	body.add_child(shape)
	world.add_child(body)
	body.global_position = at
	obstacles.append(body)
	return body

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

func stand(at: Vector3, facing := INF) -> void:
	player.enabled = false
	player.global_position = Vector3(at.x, ground_y(at) + 0.05, at.z)
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.impact_recovery = 0.0
	player.impact_cooldown = 0.0
	if is_finite(facing):
		player.yaw = facing
		player.camera_yaw = facing
	player.enabled = true
	await frames(3)
	if is_instance_valid(parked):
		parked.set_presence(player.global_position)

## Stand far from `target` and face directly away from it.
func look_away(at: Vector3, target: Vector3) -> void:
	var away := Vector3(at.x - target.x, 0.0, at.z - target.z).normalized()
	await stand(at, atan2(away.x, away.z))
	player.update_camera()

func half_size(car: Node3D) -> Vector3:
	return Models.dimensions(str(car.prototype_kind)) * 0.5

## Beside a live car's door: side 1 is the driver's (+X) side, -1 the kerb side.
func door_point(car: Node3D, side := 1.0, along := 0.25) -> Vector3:
	var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
	var left := Vector3(forward.z, 0.0, -forward.x)
	return car.global_position + left * side * (half_size(car).x + 0.45) + forward * along

## Beside a parked record on its sidewalk (kerb, local -X) side.
func record_door(index: int, gap := 0.95) -> Vector3:
	var record: Dictionary = parked.records[index]
	var pose: Transform3D = record.pose
	var size := Models.dimensions(str(record.kind))
	var side := pose.basis.x.normalized()
	return pose.origin - side * (size.x * 0.5 + gap) + pose.basis.z.normalized() * 0.25

func board(car: Node3D) -> bool:
	if driving.active:
		return driving.vehicle == car
	for side in [1.0, -1.0]:
		await stand(door_point(car, side))
		driving.tick(0.1)
		if driving.handle_input(key(KEY_F)) and driving.active:
			return true
	return false

## Stand at a parked record's kerb door and press F (real promotion path).
func board_record(index: int) -> bool:
	if driving.active:
		return false
	await stand(record_door(index))
	driving.tick(0.1)
	return driving.handle_input(key(KEY_F)) and driving.active

func leave() -> bool:
	if not driving.active:
		return true
	var car: Node3D = driving.vehicle
	place(car, car.global_position, car.yaw, 0.0)
	await frames(2)
	driving._message_time = 0.0
	return driving.exit_vehicle(false) or driving.exit_vehicle(true)

## Teleport a body; the explorer's seat follows a controlled car.
func place(car: Node3D, at: Vector3, heading: float, speed := 0.0) -> void:
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
	var own: Array[RID] = [car.get_rid()]
	car._drive_exclude = own
	return car._drive_pose_clear(car.global_transform, 2 | 8 | 16)

## Batch instances drawn at `pose`. Needs a real renderer: the headless dummy
## RenderingServer returns zero transforms (city_vehicle_batch_render_gate.gd).
func batch_instances_at(pose: Transform3D) -> int:
	var found := 0
	for batch in parked._batches.values():
		for index in maxi(0, batch.multimesh.visible_instance_count):
			var instance: Transform3D = batch.multimesh.get_instance_transform(index)
			if instance.origin.distance_to(pose.origin) < 0.01:
				found += 1
	return found

## Instances of `kind` the parked batches currently submit (near + far). The
## headless dummy renderer does not retain per-instance transforms, so tests
## compare these counts at one presence center instead of reading poses back.
func batch_total(kind: String) -> int:
	var total := 0
	for detail in ["_near", "_far"]:
		var batch: MultiMeshInstance3D = parked._batches.get(kind + detail)
		if batch != null:
			total += batch.multimesh.visible_instance_count
	return total

func fleet_count(id: String) -> int:
	var found := 0
	for car in traffic.vehicles + traffic.player_fleet:
		if is_instance_valid(car) and car.is_inside_tree() and str(car.vehicle_id) == id:
			found += 1
	return found

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))
