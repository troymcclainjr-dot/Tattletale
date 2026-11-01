extends "res://tests/city_tire_handling_smoke_runner.gd"
const Catalog = preload("res://scripts/city/city_car_catalog.gd")
const Models = preload("res://scripts/city/city_car_models.gd")
const Collision = preload("res://scripts/city/city_car_collision.gd")
const Parked = preload("res://scripts/city/city_parked_cars.gd")

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box(Vector3(0,-.5,30),Vector3(140,1,160),1)
	level = LevelFixture.new()
	world.add_child(level)
	level.player = CharacterBody3D.new()
	level.add_child(level.player)
	level.player.position = Vector3(0,0,-40)
	await get_tree().physics_frame
	var seen: Dictionary = {}
	for index in Catalog.TRAFFIC_ROTATION.size():
		var x := -48.0 + float(index)*8.0
		var street := StreetFixture.new()
		street.center_x = x
		street.level = level
		world.add_child(street)
		var car := Vehicle.new()
		car.position.x = x
		street.add_child(car)
		var route: Array[Vector3] = [Vector3(x,0,0),Vector3(x,0,90)]
		check(car.setup(street,route,"catalog_%d"%index,8.0,index),"catalog traffic placement %d"%index)
		seen[car.prototype_kind] = true
		check(car.prototype_kind==Catalog.traffic_kind(index),"traffic uses authored catalog rotation %d"%index)
		if not Catalog.has_kind(car.prototype_kind):
			continue
		var kind: String = car.prototype_kind
		check(Collision.parts(kind)[0].shape==Catalog.collision_parts(kind)[0].shape,"shared exact catalog hull for "+kind)
		var centers := Catalog.wheel_poses(kind)
		var mapping := [0,2,1,3] # prototype order versus moving canonical FL FR RL RR
		var aligned := car._wheels.size()==4
		var hittable := true
		for wheel in 4:
			var expected: Vector3 = centers[mapping[wheel]].origin
			aligned = aligned and car._wheel_positions[wheel].is_equal_approx(expected)
			var center: Vector3 = car.global_transform*expected
			var outside: Vector3 = car.global_basis.x*signf(expected.x)*2.0
			var hit: Dictionary = car.raycast_tires(center+outside,center)
			hittable = hittable and int(hit.get("tire_index",-1))==wheel
		check(aligned,"four physical wheel centers align with "+kind)
		check(hittable,"all four tires exposed to real side gunshot ray on "+kind)
	check(seen.size()==Models.ALL_KINDS.size(),"traffic rotation includes all nine vehicle kinds")
	var parked := Parked.new()
	world.add_child(parked)
	parked.level = level
	for index in Catalog.KINDS.size():
		var kind: String = Catalog.KINDS[index]
		var pose := Transform3D(Basis.IDENTITY,Vector3(float(index)*8.0-20.0,.025,30))
		var body := StaticBody3D.new()
		Collision.attach(body,kind)
		parked.add_child(body)
		body.global_transform = pose
		body.set_meta("parked_index",index)
		parked.records.append({"pose":pose,"kind":kind,"paint":index,"body":body,"presence":-1,"flat_tires":[]})
	parked._build_batches()
	parked.set_presence(Vector3(0,0,30),55,180)
	for index in Catalog.KINDS.size():
		var kind: String = Catalog.KINDS[index]
		var record: Dictionary = parked.records[index]
		check(parked._batches.has(kind+"_near") and parked._batches.has(kind+"_far")
			and parked._batches[kind+"_near"].multimesh.visible_instance_count==1,"parked near/far batches render "+kind)
		var hittable := true
		var poses := Catalog.wheel_poses(kind)
		for wheel in 4:
			var center: Vector3 = record.pose*poses[wheel].origin
			var outside := Vector3.RIGHT*signf(poses[wheel].origin.x)*2.0
			var hit: Dictionary = parked.raycast_tires(center+outside,center)
			hittable = hittable and hit.get("collider")==record.body and int(hit.get("tire_index",-1))==wheel
		check(hittable,"parked tire rays preserve correct wheel indices on "+kind)
		var result: Dictionary = parked.receive_gunshot({"collider":record.body,"tire_index":2},Vector3.ZERO)
		check(result.punctured and record.damage_model.get_meta("vehicle_prototype")==kind
			and parked._batches[kind+"_near"].multimesh.visible_instance_count==0,"damaged parked car preserves catalog model "+kind)
	check(parked.get_status().kinds.size()==6,"parked kind telemetry reports all new variants")
	world.queue_free()
	await get_tree().process_frame
	print("[catalog_integration] failures=%d"%failures)
	get_tree().quit(0 if failures==0 else 1)
