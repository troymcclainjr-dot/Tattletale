extends Node
const Explorer := preload("res://scripts/city/city_player.gd")
var world: Node3D
var player: CharacterBody3D
var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[city_jump] %s %s" % ["PASS" if ok else "FAIL", label])

func box(at: Vector3, size_: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size_
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func reset(at := Vector3(0, 0.04, 0)) -> void:
	Input.action_release("move_forward")
	Input.action_release("run")
	player.enabled = false
	player.reset_jump()
	player.position = at
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.enabled = true
	# Disabled exploration now freezes passive falls too. Settle through real
	# enabled physics before measuring jump height and the first launch frame.
	await frames(12)

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	player = Explorer.new()
	world.add_child(player)
	await frames(4)
	await reset()
	check(player.is_on_floor(), "fixture starts on physical ground")
	var initial: Vector3 = player.position
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	check(player.velocity.y > 0 and player.position.y > initial.y + 0.1, "Space starts a physical jump")
	var peak := player.position.y
	var count: int = player.jumps_started
	player.request_jump()
	for i in 70:
		await frames(1)
		peak = maxf(peak, player.position.y)
	check(peak - initial.y > 2.25 and peak - initial.y < 2.50, "jump reaches a controlled 2.25–2.50 metre apex for vehicle roofs")
	check(player.jumps_started == count, "early midair press cannot double jump or queue a late bounce")
	check(player.is_on_floor() and absf(player.position.y - initial.y) < 0.03, "capsule lands back on the actual ground")
	check(Vector2(player.position.x, player.position.z).length() < 0.01, "standing jump has no horizontal drift")
	await reset()
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(30)
	initial = player.position
	player.request_jump()
	await frames(70)
	check(player.position.z > initial.z + 4.0 and player.current_speed > 6.5, "running jump preserves forward momentum through landing")
	await reset()
	var ceiling := box(Vector3(0, 2.0, 0), Vector3(5, 0.15, 5))
	await frames(3)
	player.request_jump()
	peak = player.position.y
	for i in 45:
		await frames(1)
		peak = maxf(peak, player.position.y)
	check(peak < 0.23 and player.is_on_floor(), "low ceiling blocks the full capsule and permits recovery")
	ceiling.queue_free()
	await frames(2)
	await reset()
	player.request_jump()
	await frames(8)
	player.enabled = false
	initial = player.position
	var vertical: float = player.velocity.y
	check(not player.request_jump(), "menus reject new jump requests")
	await frames(20)
	check(player.position.is_equal_approx(initial) and is_equal_approx(player.velocity.y, vertical), "pausing freezes a jump instead of falling behind a menu")
	player.enabled = true
	await frames(60)
	check(player.is_on_floor(), "resuming completes the same jump")
	# A real elevated ledge supplies coyote-time support, not a spoofed flag.
	await reset(Vector3(8, 0.04, 0))
	var ledge := box(Vector3(8, 0.65, 0), Vector3(3, 1.3, 3))
	player.position.y = 1.34
	await frames(12)
	Input.action_press("move_forward")
	var left_ledge := false
	for i in 90:
		await frames(1)
		if not player.is_on_floor():
			left_ledge = true
			break
	count = player.jumps_started
	player.request_jump()
	await frames(2)
	check(left_ledge and player.jumps_started == count + 1 and player.velocity.y > 0, "brief coyote time allows a jump just after leaving a real ledge")
	Input.action_release("move_forward")
	await frames(80)
	ledge.queue_free()
	await frames(2)
	await reset()
	player.request_jump()
	count = player.jumps_started
	var buffered := false
	for i in 80:
		await frames(1)
		if not buffered and player.velocity.y < -3.0 and player.position.y < 0.20:
			player.request_jump()
			buffered = true
		if player.jumps_started >= count + 2:
			break
	check(buffered and player.jumps_started == count + 2, "a fresh press just before landing buffers exactly one next jump")
	await frames(65)
	check(player.is_on_floor() and player.jumps_started == count + 2, "buffered jump cannot repeat without another press")
	player.impact_recovery = 0.5
	check(not player.request_jump(), "vehicle recovery cannot be bypassed by jumping")
	player.impact_recovery = 0.0
	world.queue_free()
	await frames(2)
	print("[city_jump] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
