extends Node
## End-to-end road fixture, signal behavior and traffic spacing checks.

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_street] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes")
		_finish()
		return
	level.pause_exploring()
	await frames(2)
	var traffic: Node3D = level.traffic
	var details: Dictionary = traffic.street_details
	check(traffic.vehicles.size() >= 6, "at least six physical sedans spawn")
	check(int(details.get("street_lamps", 0)) >= 10, "streetlamps extend along actual road polylines")
	check(int(details.get("fixture_batches", 0)) == 1, "repeated original streetlights share a MultiMesh batch")
	check(int(details.get("stop_signs", 0)) == 2, "two side streets receive stop controls")
	var mesh := CityDressing.source_lamp_mesh()
	check(mesh != null and mesh.get_aabb().size.x < 0.6 and mesh.get_aabb().size.y > 4.5, "extracted original lamp contains exactly one standing fixture")
	check(traffic.signals.heads.size() >= 2, "original signal heads survive ground and route-clearance validation")
	var paints: Dictionary = {}
	var trim_preserved := true
	var paint_shared := true
	for car in traffic.vehicles:
		check(car._pose_clear(car.global_transform), "physical car begins inside clear roadway: " + str(car.name))
		var body := Assets.find(car.model, "Body") as MeshInstance3D
		if body:
			for surface in body.mesh.get_surface_count():
				var paint_override := body.get_surface_override_material(surface)
				if paint_override == null:
					continue
				trim_preserved = trim_preserved and body.mesh.surface_get_material(surface).resource_name == "city_vehicle_paint"
				var color: String = car.paint_color
				if paints.has(color):
					paint_shared = paint_shared and paints[color] == paint_override.get_instance_id()
				paints[color] = paint_override.get_instance_id()
	check(paints.size() >= 4 and paint_shared, "traffic paint palette reuses shared materials")
	check(trim_preserved, "car paint overrides preserve original glass and trim surfaces")
	var signals: Node3D = traffic.signals
	var exclusive := true
	for second in 360:
		signals.elapsed = second / 10.0
		exclusive = exclusive and not (signals.phase("old_york") != "Red" and signals.phase("wyanoke") != "Red")
	check(exclusive, "opposing road axes never receive conflicting green or amber")
	signals.elapsed = 20.0
	check(signals.phase("old_york") == "Red" and signals.phase("wyanoke") == "Red", "all-red clearance phase separates road axes")
	signals.elapsed = 0.0
	check(is_finite(signals.stopping_distance(Vector3(20, 0, 0), Vector3.LEFT, 2.35)), "cross-street cars also observe their red signal")
	signals.elapsed = 22.0
	check(not is_finite(signals.stopping_distance(Vector3(20, 0, 0), Vector3.LEFT, 2.35)), "cross-street green releases its approach")
	var car = traffic.vehicles[0]
	# Other frozen vehicles are not participants in this isolated signal test.
	for other in traffic.vehicles:
		if other != car:
			other.collision_layer = 0
	# Independent northbound route crosses the physical signal's stop line.
	car.set_manual_route(traffic._lane_path(traffic.road_length * 0.42, traffic.road_length * 0.59))
	car.near_physics = true
	var direction: Vector3 = (car.route[1] - car.route[0]).normalized()
	car.yaw = atan2(direction.x, direction.z)
	var ground: Dictionary = car._ground_pose(car.route[0], car.yaw)
	check(not ground.is_empty(), "signal test lane is grounded")
	if not ground.is_empty():
		car.global_transform = ground.transform
		car.state = "waiting"
		car.speed = 0.0
		signals.elapsed = 22.0
		signals.update_lenses()
		for i in 480:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.state == "blocked" and car.blocked_reason == "Waiting at traffic signal", "sedan stops at a red signal")
		check(car.global_position.z - car.BODY_SIZE.z * 0.5 >= signals.junction.z + signals.STOP_LINE - 0.12, "front bumper stays behind stop line")
		var stopped: Vector3 = car.global_position
		for i in 30:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.global_position.distance_to(stopped) < 0.01 and car.honks == 0, "red-light wait is stationary and silent")
		signals.elapsed = 0.0
		signals.update_lenses()
		for i in 180:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.global_position.distance_to(stopped) > 3.0, "green signal releases waiting traffic")
		check(not car.try_recycle(), "active vehicle cannot visibly recycle")
	print("[city_street] details ", details, " signals ", signals.get_status())
	_finish()

func _finish() -> void:
	print("[city_street] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
