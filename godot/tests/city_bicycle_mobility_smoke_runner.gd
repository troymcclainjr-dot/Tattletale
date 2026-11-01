extends Node3D
## Root serializes engine runs. No save data, live residents or city edits.
const Bicycle := preload("res://scripts/city/city_bicycle.gd")

class Explorer extends CharacterBody3D:
	var enabled := true
	var yaw := 0.0
	var camera_yaw := 0.0
	var chase_distance := 6.2
	var phone: Node3D
	var seated_vehicle: Node3D
	func is_seated() -> bool:
		return seated_vehicle != null
	func enter_vehicle(bike: Node3D) -> void:
		seated_vehicle = bike
		follow_vehicle()
	func follow_vehicle() -> void:
		global_position = seated_vehicle.global_position
	func leave_vehicle(at: Vector3, heading: float) -> void:
		seated_vehicle = null
		global_position = at
		yaw = heading
	func vehicle_look(motion: Vector2) -> void:
		camera_yaw += motion.x * 0.003

class Fixture extends Node3D:
	var paused := false
	var player: CharacterBody3D
	var combat: Node3D

var world: Fixture
var bike: CharacterBody3D
var errors: Array[String] = []
var checks := 0
var harmless_contacts := 0
var peak := 0.0
var max_rise := 0.0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
	print("BIKE_MOBILITY ", "PASS " if ok else "FAIL ", message)

func _box(at: Vector3, size: Vector3, layer := 2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _reset(at: Vector3, heading := 0.0) -> void:
	bike.global_position = at
	bike.yaw = heading
	bike.rotation.y = heading
	bike.speed = 0.0
	# Clears recoil slip, wobble and deflection left by a previous obstacle.
	bike.reset_motion_state()
	bike.velocity = Vector3.ZERO
	bike._hop_active = false
	bike._hop_buffer = 0.0
	bike._hop_held = false
	bike._curb_grace = 0.0
	bike._steer = 0.0
	bike.set_control_override(Vector2.ZERO, true)
	world.player.follow_vehicle()
	bike._last_seat = world.player.global_position
	peak = at.y
	max_rise = 0.0
	await _frames(8)

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
		var before: float = bike.global_position.y
		bike.tick(1.0 / 60.0)
		peak = maxf(peak, bike.global_position.y)
		max_rise = maxf(max_rise, bike.global_position.y - before)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(240.0, 0.5, 240.0), 1)
	world.player = Explorer.new()
	world.add_child(world.player)
	world.player.position = Vector3(0.0, 0.05, -30.0)
	await get_tree().physics_frame
	bike = Bicycle.new()
	world.add_child(bike)
	bike.setup(world)
	_check(bike.spawned and bike.enter_bicycle(), "fixture mounts actual bicycle")
	if not bike.active:
		get_tree().quit(1)
		return
	bike.pedestrian_contact.connect(func(contact: Dictionary):
		_check(bool(contact.harmless) and is_zero_approx(float(contact.body_damage)), "impact remains harmless")
		harmless_contacts += 1
	)
	await _controls()
	await _hops()
	await _curb(-42.0, 0.18, 0.0)
	await _curb(-26.0, 0.28, 0.0)
	await _curb(-10.0, 0.18, PI / 6.0)
	await _obstacles()
	print("CITY_BICYCLE_MOBILITY_SMOKE ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)

func _controls() -> void:
	await _reset(Vector3(0.0, 0.04, -35.0))
	bike.clear_control_override()
	Input.action_press("move_forward")
	world.player.camera_yaw = PI
	await _frames(90)
	Input.action_release("move_forward")
	_check(absf(bike.yaw) < 0.001 and bike.global_position.z > -32.0, "W propels along bike heading despite opposite camera")
	var look := InputEventMouseMotion.new()
	look.screen_relative = Vector2(300.0, 0.0)
	_check(bike.handle_input(look) and absf(bike.yaw) < 0.001, "camera orbit does not steer bicycle")
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _frames(35)
	Input.action_release("move_forward")
	Input.action_release("move_right")
	_check(bike.yaw < -0.3 and bike.global_position.x < -0.15, "D steers toward rider right independently of camera")
	await _reset(Vector3(0.0, 0.04, -35.0))
	bike.set_control_override(Vector2(0.0, 1.0))
	await _frames(60)
	bike.set_control_override(Vector2(0.0, -1.0))
	await _frames(10)
	_check(bike.speed >= 0.0 and bike.speed < 2.0, "S initially brakes forward travel")
	await _frames(90)
	_check(bike.speed < -2.0 and bike.speed >= -Bicycle.REVERSE_SPEED - 0.01, "holding S enters limited reverse")
	_check(not bike.exit_vehicle(), "reverse speed also prevents unsafe dismount")
	await _reset(Vector3(0.0, 0.04, -35.0))
	bike.set_control_override(Vector2(0.0, 1.0), false, true)
	await _frames(150)
	_check(bike.speed > Bicycle.MAX_SPEED + 1.0 and bike.speed <= Bicycle.SPRINT_SPEED + 0.01, "Shift pedals harder within sprint cap")

func _hops() -> void:
	await _reset(Vector3(20.0, 0.04, -30.0))
	var before: int = bike.hops_started
	bike.set_control_override(Vector2.ZERO, false, false, true)
	await _frames(80)
	_check(peak > 0.55 and peak < 1.2, "Space creates a bounded physical hop")
	_check(bike.hops_started == before + 1 and not bike._hop_active and bike.global_position.y < 0.08, "held Space does not auto-hop after landing")
	var ceiling := _box(Vector3(20.0, 1.8, -30.0), Vector3(4.0, 0.4, 4.0))
	await _reset(Vector3(20.0, 0.04, -30.0))
	bike.set_control_override(Vector2.ZERO, false, false, true)
	await _frames(70)
	_check(peak < 0.17 and not bike._hop_active, "hop respects low ceiling and lands")
	ceiling.queue_free()
	await get_tree().physics_frame

func _curb(x: float, height: float, heading: float) -> void:
	var curb := _box(Vector3(x, height * 0.5, 5.0), Vector3(12.0, height, 10.0), 1)
	await _reset(Vector3(x, 0.04, -3.0), heading)
	var before: int = bike.steps_climbed
	bike.set_control_override(Vector2(0.0, 1.0))
	await _frames(150)
	_check(bike.global_position.z > 2.0, "crosses %.2f m curb at heading %.2f (position=%s, %s)" % [height, heading, bike.global_position, bike.debug_step_reason])
	_check(peak < height + 0.09 and max_rise <= Bicycle.STEP_HEIGHT + 0.01, "curb ascent stays within bounded step height")
	_check(bike._hull_clear(bike.global_transform, 0.015), "complete bicycle hull stays clear on curb")
	print("BIKE_CURB steps=", bike.steps_climbed - before, " peak=", peak, " position=", bike.global_position)
	# Continue off the far edge and let physical gravity/snap settle on street.
	await _frames(100)
	_check(bike.global_position.z > 11.0 and bike.global_position.y < 0.08, "curb descent returns to street without hanging")
	curb.queue_free()
	await get_tree().physics_frame

func _obstacles() -> void:
	var wall := _box(Vector3(35.0, 1.0, 1.0), Vector3(8.0, 2.0, 2.0))
	await _reset(Vector3(35.0, 0.04, -3.0))
	bike.set_control_override(Vector2(0.0, 1.0), false, true)
	await _frames(120)
	_check(bike.global_position.z < 0.0 and peak < 0.09, "holding W at tall wall cannot climb or tunnel")
	wall.queue_free()
	var curb := _box(Vector3(50.0, 0.10, 3.0), Vector3(8.0, 0.20, 6.0), 1)
	var canopy := _box(Vector3(50.0, 1.65, 0.0), Vector3(8.0, 0.2, 6.0))
	await _reset(Vector3(50.0, 0.04, -3.0))
	bike.set_control_override(Vector2(0.0, 1.0))
	await _frames(120)
	_check(bike.global_position.z < 0.0 and bike._hull_clear(bike.global_transform, 0.005), "low overhang blocks curb ascent without clipping")
	curb.queue_free()
	canopy.queue_free()
	var person := _box(Vector3(65.0, 0.9, 0.0), Vector3(0.65, 1.8, 0.65), 8)
	await _reset(Vector3(65.0, 0.04, -3.0))
	bike.set_control_override(Vector2(0.0, 1.0), false, true)
	await _frames(100)
	_check(harmless_contacts > 0 and bike.global_position.z < 0.0 and peak < 0.1, "pedestrian contact slows bike without stepping onto person")
	person.queue_free()
