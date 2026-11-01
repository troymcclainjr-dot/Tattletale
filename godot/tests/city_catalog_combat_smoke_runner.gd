extends "res://tests/city_combat_reactions_smoke_runner.gd"
const Catalog = preload("res://scripts/city/city_car_catalog.gd")
const Fleet = preload("res://scripts/city/city_traffic.gd")
const Vehicle = preload("res://scripts/city/city_vehicle.gd")
class Street:
	extends Node3D
	var level: Node3D
	func on_road(_point: Vector3,_margin := .12) -> bool:
		return true
	func control_distance(_car: Node3D,_dt: float) -> float:
		return INF
	func release_reservation(_car: Node3D) -> void:
		pass

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0,-.5,0),Vector3(240,1,240),1)
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	npcs = PeopleFixture.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	residents = Residents.new()
	arena.add_child(residents)
	residents.level = arena
	arena.residents = residents
	var fleet := Fleet.new()
	arena.add_child(fleet)
	fleet.level = arena
	arena.traffic = fleet
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	reset_player()
	combat.equip("pistol")
	await frames(2)
	for index in Catalog.KINDS.size():
		var kind: String = Catalog.KINDS[index]
		var street := Street.new()
		street.level = arena
		arena.add_child(street)
		var car := Vehicle.new()
		var x := float(index)*12.0-30.0
		car.position = Vector3(x,0,10)
		street.add_child(car)
		var path: Array[Vector3] = [Vector3(x,0,10),Vector3(x,0,90)]
		var paint: int = Catalog.TRAFFIC_ROTATION.find(kind)
		check(car.setup(street,path,"catalog_fire_"+kind,8.0,paint),"production catalog shot target "+kind)
		fleet.vehicles.append(car)
		player.global_position = car.global_position+Vector3(4,0,0)
		car.set_presence(player.global_position)
		await frames(2)
		for wheel in 4:
			var center: Vector3 = car.global_transform*car._wheel_positions[wheel]
			var side := signf(car._wheel_positions[wheel].x)
			player.global_position = Vector3(center.x+side*3.0,car.global_position.y,center.z)
			player.camera.global_position = center+Vector3.RIGHT*side*3.0
			player.camera.look_at(center)
			combat._muzzle.global_position = center+Vector3.RIGHT*side*2.0
			combat.ammo = 12
			combat._shot_cooldown = 0.0
			var fired: bool = combat._fire()
			check(fired and combat.last_shot.get("tire",false) and combat.last_shot.get("vehicle",false)
				and wheel in car.flat_tires,"production _fire punctures perpendicular %s tire%d"%[kind,wheel])
		fleet.vehicles.erase(car)
		car.queue_free()
		await frames(2)
	arena.queue_free()
	await frames(2)
	print("[catalog_combat] %d passed; %d failed"%[passes,failures])
	get_tree().quit(0 if failures==0 else 1)
