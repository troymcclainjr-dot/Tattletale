extends Node
## Production CharacterBody/compound sweeps on actual static ground + side wall.
const Vehicle = preload("res://scripts/city/city_vehicle.gd")
const Handling = preload("res://scripts/city/city_tire_handling.gd")
class LevelFixture:
	extends Node3D
	var player: CharacterBody3D
class StreetFixture:
	extends Node3D
	var level: Node3D
	var center_x := 0.0
	var half_width := 4.5
	var stop_line := INF
	func on_road(point: Vector3, margin := .12) -> bool:
		return absf(point.x - center_x) < half_width - margin
	func control_distance(car: Node3D, _dt: float) -> float:
		return maxf(0.0, stop_line - car.route_position().z) if is_finite(stop_line) else INF
	func release_reservation(_car: Node3D) -> void:
		pass
var world: Node3D
var level: Node3D
var failures := 0

func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[tire_handling] %s %s" % ["PASS" if ok else "FAIL", label])
func box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body
func car_at(x: float, id: String, cruise := 9.0) -> Node3D:
	var street := StreetFixture.new()
	street.center_x = x
	street.level = level
	world.add_child(street)
	var car := Vehicle.new()
	car.position = Vector3(x, 0, 0)
	street.add_child(car)
	var path: Array[Vector3] = [Vector3(x,0,0),Vector3(x,0,90)]
	check(car.setup(street,path,id,cruise,0), id + " has valid supported production body")
	car.honk_cooldown = 1000.0
	return car
func puncture(car: Node3D, tire: int) -> void:
	car.receive_gunshot({"tire_index": tire}, car.global_position + Vector3.LEFT * 4)

func _run() -> void:
	_check_profile_cache()
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box(Vector3(0,-.5,30),Vector3(120,1,160),1)
	level = LevelFixture.new()
	world.add_child(level)
	level.player = CharacterBody3D.new()
	level.add_child(level.player)
	level.player.position = Vector3(50,0,-20)
	await get_tree().physics_frame
	var left := car_at(-12,"left_flat")
	var right := car_at(0,"right_flat")
	puncture(left,0)
	puncture(right,1)
	left.speed = 8.0
	right.speed = 8.0
	var max_left := 0.0
	var max_right := 0.0
	var max_yaw := 0.0
	for i in 240:
		left.tick(1.0/60.0)
		right.tick(1.0/60.0)
		max_left = maxf(max_left,-(left.global_position.x+12.0))
		max_right = maxf(max_right,right.global_position.x)
		max_yaw = maxf(max_yaw,absf(left.yaw))
	check(max_left > .20 and max_right > .20, "opposite punctured sides cause opposite actual lane departures")
	check(max_yaw > .025, "damage changes actual body yaw, not only speed or wheel appearance")
	check(max_left <= Handling.MAX_OFFSET+.001 and max_right <= Handling.MAX_OFFSET+.001, "lane departures remain bounded")
	check(left.tire_handling.recoveries > 0 and right.tire_handling.recoveries > 0, "drivers countersteer after substantial lateral loss")
	var stop_at: Vector3 = left.global_position
	left.traffic.stop_line = left.route_position().z
	left.tick(1.0/60.0)
	check(left.speed == 0 and left.global_position.is_equal_approx(stop_at), "punctured car still obeys an authoritative stop line")
	left.set_presence(Vector3(1000,0,1000))
	check(left.near_physics and left.collision_layer == 16, "damaged motion retains collision presence beyond ordinary culling radius")
	var controlled_stop: float = left.route_position().z + 10.0
	left.traffic.stop_line = controlled_stop
	left.speed = 8.0
	var crossed := false
	for i in 300:
		left.tick(1.0/60.0)
		crossed = crossed or left.route_position().z > controlled_stop + .001
	check(not crossed and left.speed < .01 and controlled_stop-left.route_position().z < .12,
		"reduced-grip braking approaches but never crosses its stop line despite lateral offset")
	left.queue_free()
	right.queue_free()
	await get_tree().physics_frame
	var healthy := car_at(-12,"healthy_braking",0.0)
	var flat := car_at(0,"flat_braking",0.0)
	puncture(flat,0)
	healthy.speed = 8.0
	flat.speed = 8.0
	for i in 400:
		healthy.tick(1.0/60.0)
		flat.tick(1.0/60.0)
	check(healthy.speed < .01 and flat.speed < .01, "both cars stop under normal requested braking")
	check(flat.global_position.z > healthy.global_position.z * 1.25, "one flat materially lengthens measured braking distance")
	check(flat.effective_braking() < healthy.effective_braking(), "braking planner uses reduced tire adhesion")
	var one: Array[int] = [0]
	var three: Array[int] = [0,1,2]
	check(float(Handling.profile(three).grip) < float(Handling.profile(one).grip), "multiple flats reduce steering and lateral grip further")
	# Actual wall occupies the outside of a still-valid road. A full proposed
	# swerve would hit it; recovery must choose a clear path and keep progressing.
	var curb_car := car_at(15,"collision_recovery")
	box(Vector3(13.30,.55,30),Vector3(.20,1.1,50),2)
	await get_tree().physics_frame
	puncture(curb_car,0)
	curb_car.speed = 8.0
	var clear := true
	for i in 420:
		curb_car.tick(1.0/60.0)
		clear = clear and curb_car._pose_clear(curb_car.global_transform)
	check(clear, "every committed drifting and recovering hull remains clear of actual wall")
	check(curb_car.damage_clearance_recoveries > 0, "unsafe lateral proposals trigger collision-aware countersteering")
	check(curb_car.global_position.z > 30.0, "recovery continues down the road instead of becoming trapped at curb")
	print("[tire_handling] measured ",JSON.stringify({"left_departure":max_left,"right_departure":max_right,"yaw":max_yaw,
		"healthy_stop_m":healthy.global_position.z,"flat_stop_m":flat.global_position.z,"recovery":curb_car.get_status()}))
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures==0 else 1)

func _check_profile_cache() -> void:
	var probe := Vehicle.new()
	check(probe.effective_braking()==Vehicle.BRAKING and probe._cached_tire_profile.is_empty(),
		"healthy braking preserves constant without allocating a tire profile")
	probe._wheel_sides = [-1.0,1.0,-1.0,1.0]
	probe.flat_tires = [0]
	var first: Dictionary = probe._tire_profile()
	check(is_same(first,probe._tire_profile()) and is_equal_approx(probe.effective_braking(),Vehicle.BRAKING*.72),
		"unchanged damaged state reuses its profile and preserves braking")
	probe.flat_tires[0] = 1
	var changed: Dictionary = probe._tire_profile()
	check(float(first.pull)<0 and float(changed.pull)>0 and not is_same(first,changed),
		"same-count direct tire mutation invalidates cached steering side")
	probe.flat_tires.append(0)
	check(is_equal_approx(probe.effective_braking(),Vehicle.BRAKING*.50),
		"direct tire append immediately updates braking authority")
	probe.flat_tires = [0]
	probe._wheel_sides[0] = 1.0
	check(float(probe._tire_profile().pull)>0,"direct wheel-side mutation also refreshes cached profile")
	probe.flat_tires.clear()
	check(probe.effective_braking()==Vehicle.BRAKING,"direct tire repair restores healthy braking immediately")
	probe.free()
