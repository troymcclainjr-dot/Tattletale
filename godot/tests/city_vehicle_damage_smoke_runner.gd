extends Node

const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Parked := preload("res://scripts/city/city_parked_cars.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Damage := preload("res://scripts/city/city_vehicle_damage.gd")

class LevelFixture:
	extends Node3D
	var player: CharacterBody3D

class StreetFixture:
	extends Node3D
	var level: Node3D
	var stop_distance := INF
	func on_road(_point: Vector3, _margin := 0.12) -> bool:
		return true
	func control_distance(_car: Node3D, _dt: float) -> float:
		return stop_distance
	func release_reservation(_car: Node3D) -> void:
		pass

var failures := 0

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_vehicle_damage] %s %s" % ["PASS" if ok else "FAIL", label])

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var world := Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(100, 1, 200)
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = ground_shape
	ground_collision.position.y = -0.5
	ground.add_child(ground_collision)
	world.add_child(ground)
	var level := LevelFixture.new()
	world.add_child(level)
	level.player = CharacterBody3D.new()
	level.add_child(level.player)
	level.player.position = Vector3(20, 0, 0)
	var street := StreetFixture.new()
	street.level = level
	world.add_child(street)
	await get_tree().physics_frame
	var car := Vehicle.new()
	street.add_child(car)
	var path: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 90)]
	check(car.setup(street, path, "damage_test", 9.0), "production vehicle setup")
	car.driver_style = "aggressive"
	var dispatcher := Traffic.new()
	world.add_child(dispatcher)
	dispatcher.vehicles.append(car)
	var wheel_center: Vector3 = car._wheels[0].global_position
	var from := wheel_center + Vector3(-4, 0, 0)
	await get_tree().physics_frame
	var hit: Dictionary = dispatcher.raycast_tires(from, wheel_center)
	check(not hit.is_empty() and int(hit.get("tire_index", -1)) == 0, "side shot resolves individual visible tire")
	var body_query := PhysicsRayQueryParameters3D.create(from, wheel_center, 16)
	var body_hit := world.get_world_3d().direct_space_state.intersect_ray(body_query)
	check(not body_hit.is_empty() and not hit.is_empty() and body_hit.collider == car
		and float(hit.distance) <= from.distance_to(body_hit.position) + 0.001,
		"visible sidewall wins nearest-hit comparison against vehicle body hull")
	var front_origin := Vector3(wheel_center.x, wheel_center.y, 6.0)
	var hidden_tire: Dictionary = dispatcher.raycast_tires(front_origin, wheel_center)
	var front_query := PhysicsRayQueryParameters3D.create(front_origin, wheel_center, 16)
	var front_body := world.get_world_3d().direct_space_state.intersect_ray(front_query)
	check(not hidden_tire.is_empty() and not front_body.is_empty()
		and not hidden_tire.has("tire_index")
		and absf(front_origin.distance_to(front_body.position) - float(hidden_tire.distance)) < 0.01,
		"body wins over tire behind bumper; same-collider hit cannot bypass occlusion")
	var other_side := wheel_center + Vector3(4, 0, 0)
	var far_side: Dictionary = dispatcher.raycast_tires(other_side, wheel_center)
	check(not far_side.is_empty() and int(far_side.tire_index) == 1,
		"cross-car ray selects near-side tire instead of intended far-side tire")
	if not hit.is_empty():
		var response: Dictionary = dispatcher.receive_gunshot(hit, from)
		check(bool(response.punctured) and car.flat_tires == [0], "one tire punctures without damaging other wheels")
		check(car._wheels[0].basis.y.length() < 0.60 and car._wheels[1].basis.y.length() > 0.95,
			"puncture visibly collapses only the selected tire")
		check(not bool(dispatcher.receive_gunshot(hit, from).punctured) and car.flat_tires.size() == 1,
			"repeat hit is idempotent")
	check(car.panic_time > 0 and car._lookahead_mask() == Vehicle.OBSTACLES,
		"shot driver panics with full player collision planning")
	check(Damage.ray_tire(Vector3(-3, 0.5, 0), Vector3(3, 0.5, 0), Transform3D.IDENTITY, 0.34).is_empty(),
		"narrowphase rejects rays above the visible tire")
	check(dispatcher.notify_gunshot(Vector3(0, 1, -5), Vector3(0, 1, 5)) == 1,
		"near miss alerts driver")
	check(dispatcher.notify_gunshot(Vector3(50, 1, -5), Vector3(50, 1, 5)) == 0,
		"distant shot does not alert driver")
	car.speed = 0
	for i in 180:
		car.tick(1.0 / 60.0)
	check(car.speed > 4.5 and car.speed <= 9.0 * 1.4 * 0.70 + 0.01,
		"panicked escape accelerates but flat tire caps speed")
	street.stop_distance = 0
	var stopped_at := car.global_position
	car.tick(1.0 / 60.0)
	check(car.speed == 0 and car.global_position.is_equal_approx(stopped_at),
		"panic obeys traffic stop and collision safety limits")
	# The 90m weapon range exceeds the 55m collider radius. Test every model,
	# including imported police pivots, with physical presence deliberately off.
	for number in 4:
		var distant := Vehicle.new()
		street.add_child(distant)
		var distant_path: Array[Vector3] = [Vector3(-10, 0, 0), Vector3(-10, 0, 90)]
		check(distant.setup(street, distant_path, "distant_%d" % number, 9.0, number, number == 3),
			"distant model %d setup" % number)
		dispatcher.vehicles.append(distant)
		distant.set_presence(Vector3(0, 0, 100))
		check(not distant.near_physics and distant.collision_layer == 0, "distant model %d has no active physics body" % number)
		var center: Vector3 = distant._wheels[0].global_position
		var side := signf(center.x - distant.global_position.x)
		var ray_start := center + Vector3(side * 70, 0, 0)
		var distant_hit: Dictionary = dispatcher.raycast_tires(ray_start, center)
		check(not distant_hit.is_empty() and distant_hit.collider == distant and int(distant_hit.get("tire_index", -1)) == 0,
			"distant model %d exposed tire remains shootable at 70m" % number)
		var frontal := Vector3(center.x, center.y, 70)
		var distant_body: Dictionary = dispatcher.raycast_tires(frontal, center)
		check(not distant_body.is_empty() and distant_body.collider == distant and not distant_body.has("tire_index"),
			"distant model %d hull shields tire behind body without physics collider" % number)
		dispatcher.vehicles.erase(distant)
		distant.free()
	# A real parked batch entry must leave its batch on damage and retain that
	# damage through culling; use the same production promotion and presence code.
	var parked := Parked.new()
	world.add_child(parked)
	var body := StaticBody3D.new()
	body.collision_layer = 16
	body.set_meta("parked_vehicle", true)
	body.set_meta("parked_index", 0)
	Collision.attach(body, "box_sedan")
	parked.add_child(body)
	body.position = Vector3(10, 0.025, 0)
	parked.records.append({"pose": body.global_transform, "kind": "box_sedan", "paint": 0,
		"street": "fixture", "body": body, "presence": -1, "curb_checked": true, "flat_tires": []})
	parked._build_batches()
	parked.set_presence(Vector3.ZERO)
	dispatcher.parked = parked
	var data := Models.prototype("box_sedan")
	var parked_wheel: Vector3 = body.global_transform * data.wheel_poses[0].origin
	var parked_hit: Dictionary = parked.raycast_tires(parked_wheel - Vector3(4, 0, 0), parked_wheel)
	check(not parked_hit.is_empty(), "parked tire supports exact ray hit")
	if not parked_hit.is_empty():
		var result: Dictionary = dispatcher.receive_gunshot(parked_hit, parked_wheel - Vector3(4, 0, 0))
		check(bool(result.punctured) and parked.records[0].has("damage_model"), "parked puncture promotes only damaged car")
		check(parked._batches["box_sedan_near"].multimesh.visible_instance_count == 0,
			"damaged parked car has no duplicate undamaged batched wheels")
		parked.set_presence(Vector3(500, 0, 0))
		check(not parked.records[0].damage_model.visible and body.collision_layer == 0, "damaged car culls normally")
		var far_from := Vector3(parked_wheel.x, parked_wheel.y, 70)
		var far_parked: Dictionary = parked.raycast_tires(far_from, parked_wheel)
		check(not far_parked.is_empty() and far_parked.collider == body and not far_parked.has("tire_index"),
			"culled parked body still shields far-side tire during shot-only query")
		parked.set_presence(Vector3.ZERO)
		check(parked.records[0].damage_model.visible and body.collision_layer == (2 | 16)
			and parked.records[0].flat_tires == [0], "parked tire damage survives presence refresh")
	world.queue_free()
	await get_tree().process_frame
	print("[city_vehicle_damage] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
