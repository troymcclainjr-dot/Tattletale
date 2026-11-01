extends "res://tests/city_tire_handling_smoke_runner.gd"
const Manager = preload("res://scripts/city/city_traffic.gd")
const Explorer = preload("res://scripts/city/city_player.gd")
class BudgetCar:
	extends Node3D
	var far_damage_elapsed := 0.0
	var state := "driving"
	var far := true
	var calls := 0
	var coarse_calls := 0
	var elapsed := 0.0
	func can_tick_damage_coarsely() -> bool:
		return far
	func tick(dt: float,coarse := false) -> void:
		calls += 1
		coarse_calls += int(coarse)
		elapsed += dt
	func try_recycle() -> bool:
		return false

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box(Vector3(0,-.5,0),Vector3(120,1,500),1)
	level = LevelFixture.new()
	world.add_child(level)
	level.player = Explorer.new()
	level.add_child(level.player)
	level.player.set_physics_process(false)
	level.player.enabled = true
	level.player.camera_yaw = 0.0
	level.player.update_camera()
	var manager := Manager.new()
	world.add_child(manager)
	manager.level = level
	# Isolate scheduler from network/presence timers; production car solver is
	# exercised separately below with a real wall and ground.
	manager._control_clock = -100.0
	manager._presence_clock = -100.0
	for i in 90:
		var car := BudgetCar.new()
		manager.add_child(car)
		manager.vehicles.append(car)
	var nearby := BudgetCar.new()
	nearby.far = false
	manager.add_child(nearby)
	manager.vehicles.append(nearby)
	var bounded := true
	for frame in 240:
		manager.tick(1.0/60.0)
		bounded = bounded and manager.far_damage_updates<=Manager.MAX_FAR_DAMAGE_UPDATES
	var fair := true
	var time_preserved := true
	for i in 90:
		fair = fair and manager.vehicles[i].coarse_calls>0
		time_preserved = time_preserved and manager.vehicles[i].elapsed>3.6 and manager.vehicles[i].elapsed<=4.001
	check(bounded and manager.far_damage_peak_updates<=8,"all90 damaged far cars stay within8 coarse updates per frame")
	check(fair and time_preserved,"round robin updates every far car without dropping elapsed simulation time")
	check(nearby.calls==240 and nearby.coarse_calls==0,"nearby or visible traffic retains full-rate updates")
	manager.queue_free()
	await get_tree().physics_frame
	level.player.position = Vector3(50,0,0)
	var car := car_at(15,"coarse_sweep")
	box(Vector3(13.3,.55,30),Vector3(.2,1.1,50),2)
	await get_tree().physics_frame
	puncture(car,0)
	car.speed = 8.0
	var clear := true
	for i in 35:
		car.tick(.2,true)
		clear = clear and car._pose_clear(car.global_transform)
	check(clear,"coarse rotation-expanded sweeps never commit a hull inside actual wall")
	check(car.global_position.z>20,"coarse damaged solver still makes road progress")
	car.queue_free()
	await get_tree().physics_frame
	level.player.position = Vector3.ZERO
	level.player.camera_yaw = 0.0
	level.player.update_camera()
	var street := StreetFixture.new()
	street.level = level
	world.add_child(street)
	var jam := Vehicle.new()
	jam.position = Vector3(0,0,-110)
	street.add_child(jam)
	var route: Array[Vector3] = [Vector3(0,0,-110),Vector3(0,0,-210)]
	check(jam.setup(street,route,"offscreen_jam",9.0),"jam fixture has a valid offscreen restart")
	jam.global_position = Vector3(0,.025,-150)
	puncture(jam,0)
	check(not jam.flat_tires.is_empty() and jam.near_physics,"punctured offscreen jam initially retains safe collision")
	jam.state = "blocked"
	jam.stopped_time = 21.0
	await get_tree().physics_frame
	check(jam.try_recycle() and jam.recycled==1 and absf(jam.global_position.z+110)<.01,"long offscreen unreserved jam safely restarts at clear route origin")
	check(jam.flat_tires.is_empty() and jam.collision_layer==0 and not jam.near_physics,
		"fresh offscreen arrival clears flats and releases distant physics presence")
	check(jam._wheels[0].position.is_equal_approx(jam._wheel_positions[0]) and jam._wheels[0].basis.is_equal_approx(jam._wheel_bases[0]),
		"fresh arrival restores unsquashed wheel position and shape")
	jam.global_position = Vector3(0,.025,-150)
	jam.state = "blocked"
	jam.stopped_time = 21.0
	jam.reservation_id = "owned_junction"
	check(not jam.try_recycle(),"junction reservation holder cannot be recycled out of its control contract")
	jam.reservation_id = ""
	level.player.camera_yaw = PI
	level.player.update_camera()
	check(not jam.try_recycle(),"visible jam is never teleported")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures==0 else 1)
