extends Node
## Full Pen Lucy integration through root's real wiring: the starter car near
## spawn, the walk-up HUD prompt, F/WASD through Input, no car/traffic/clock
## motion behind the settings menu, map or inspector, exact LOD for the
## occupied car, and taking a stopped civilian car from live traffic.
## Run: python godot/tools/godot_run.py --timeout 480 -- --headless --script res://tests/city_driving_level_smoke.gd -- --offscreen-validation
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
var level: Node
var driving: Node3D
var traffic: Node3D
var passes := 0
var failures := 0
var _finished := false

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(420.0, true, false, true).timeout
	if not _finished:
		check(false, "driving level fixture exceeded its watchdog")
		_finish()

func check(ok: bool, label: String) -> bool:
	passes += int(ok)
	failures += int(not ok)
	print("[city_driving_level] %s %s" % ["PASS" if ok else "FAIL", label])
	return ok

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func door_point(car: Node3D, along := 0.25) -> Vector3:
	var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
	var left := Vector3(forward.z, 0.0, -forward.x)
	return car.global_position + left * (Models.dimensions(str(car.prototype_kind)).x * 0.5 + 0.45) + forward * along

func room(car: Node3D, direction: float) -> float:
	var own: Array[RID] = [car.get_rid()]
	car._drive_exclude = own
	var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw)) * direction
	return float(car._drive_cast(car.global_transform, forward * 20.0, Vehicle.DRIVE_MASK).safe) * 20.0

func snapshot(car: Node3D) -> Dictionary:
	var poses: Dictionary = {}
	for other in traffic.vehicles:
		poses[other.vehicle_id] = other.global_transform
	return {"car": car.global_transform, "seat": level.player.global_position, "poses": poses,
		"clock": float(level.world_time.elapsed_seconds)}

func unchanged(state: Dictionary, car: Node3D) -> bool:
	if not car.global_transform.is_equal_approx(state.car) or not level.player.global_position.is_equal_approx(state.seat):
		return false
	for other in traffic.vehicles:
		if not other.global_transform.is_equal_approx(state.poses[other.vehicle_id]):
			return false
	return is_equal_approx(float(level.world_time.elapsed_seconds), float(state.clock))

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	level = get_tree().current_scene
	for i in 2400:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if not check(level != null and level.get("level_ready") == true, "complete world initialized"):
		_finish()
		return
	driving = level.get("driving")
	traffic = level.get("traffic")
	if not check(driving != null and driving.has_method("exit_vehicle") and traffic != null, "level wires the driving manager after traffic"):
		_finish()
		return
	var status: Dictionary = driving.get_status()
	print("[city_driving_level] starter ", status.starter)
	if not check(bool(status.starter_spawned) and is_instance_valid(driving.starter), "a starter car is placed for the new player"):
		_finish()
		return
	var starter: Node3D = driving.starter
	var spawn: Vector3 = level.vector(level.level_data.spawn.position)
	var spawn_distance := Vector2(starter.global_position.x - spawn.x, starter.global_position.z - spawn.z).length()
	check(spawn_distance <= 75.0 and spawn_distance >= 6.0, "the starter is %.1fm from spawn on %s" % [spawn_distance, str(status.starter.get("street", "?"))])
	check(int(traffic.get_status().total) == 90 and not traffic.vehicles.has(starter) and traffic.player_fleet.has(starter),
		"the starter leaves the 90-car AI fleet untouched")
	check(starter._hull_clear(starter.global_transform) and starter.state == "parked", "the starter is parked with a clear physical hull")
	await _walk_up_and_drive(starter)
	await _menus_freeze(starter)
	await _get_out(starter)
	await _take_traffic_car()
	check(int(traffic.get_status().total) == 90 and int(traffic.get_status().player_controlled) == 0, "the AI fleet still has 90 cars and none is player-controlled")
	_finish()

func _walk_up_and_drive(starter: Node3D) -> void:
	level.pause_exploring()
	await frames(2)
	level._place_player(door_point(starter), starter.yaw)
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(12)
	check(driving.get_status().prompt == "F  Drive your car", "walking up to the starter shows the F prompt (%s)" % driving.get_status().prompt)
	var hud = level.get("_sandbox_label")
	if hud is Label:
		check("F  Drive your car" in (hud as Label).text, "root's HUD line shows the driving prompt")
	await key(KEY_F)
	check(driving.active and driving.vehicle == starter and level.player.is_seated() and level.player.collision_layer == 0,
		"F through the level's input path boards the starter")
	check(not level.combat.accepts_player_input(), "combat input is blocked while driving")
	var ahead := room(starter, 1.0)
	var behind := room(starter, -1.0)
	var direction := 1.0 if ahead >= behind else -1.0
	print("[city_driving_level] free room ahead %.1fm, behind %.1fm" % [ahead, behind])
	var start: Vector3 = starter.global_position
	var action := "move_forward" if direction > 0.0 else "move_back"
	Input.action_press(action)
	await frames(45)
	Input.action_release(action)
	var travel: Vector3 = starter.global_position - start
	var forward := Vector3(sin(starter.yaw), 0.0, cos(starter.yaw))
	check(travel.dot(forward) * direction > 0.4, "%s drives the car through the real input actions (%.2fm)" % ["W" if direction > 0.0 else "S", travel.length()])
	check(level.player.global_position.distance_to(starter.global_position) < 0.01, "the explorer's seat follows the car in the level tick")
	driving.set_control_override(0.0, 0.0, 0.0, true)
	for i in 120:
		await frames(1)
		if absf(float(starter.speed)) < 0.05:
			break
	driving.clear_control_override()
	check(absf(float(starter.speed)) < 0.05, "the handbrake brings the car to a stop")

func _menus_freeze(starter: Node3D) -> void:
	var direction := 1.0 if room(starter, 1.0) >= room(starter, -1.0) else -1.0
	# Gentle held input in the roomier direction; the car must be moving.
	driving.set_control_override(0.6 if direction > 0.0 else 0.0, 0.0 if direction > 0.0 else 1.0, 0.0, false)
	await frames(20)
	check(absf(float(starter.speed)) > 0.5, "the held input has the car rolling before the menus open")
	var state := snapshot(starter)
	level.pause_exploring()
	await frames(30)
	check(unchanged(state, starter) and driving.active, "the settings menu freezes the held-throttle car, all AI cars and the clock")
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(8)
	check(starter.global_transform.origin.distance_to(state.car.origin) > 0.03, "driving resumes after the menu")
	state = snapshot(starter)
	level.toggle_map()
	await frames(30)
	check(unchanged(state, starter), "the map freezes the car, traffic and clock")
	level.toggle_map()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(4)
	state = snapshot(starter)
	var inspector: Node = level.get("inspector")
	if inspector != null and inspector.enter():
		# Fly the inspection camera far away: other cars batch, the occupied car does not.
		inspector.eye = starter.global_position + Vector3(0.0, 90.0, 320.0)
		inspector._apply_view()
		await frames(30)
		check(unchanged(state, starter), "the inspector freezes the car, traffic and clock")
		check(starter.model.visible and not starter._render_lod_active, "the occupied car keeps its exact model under a distant inspector camera")
		inspector.leave()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await frames(4)
	else:
		check(false, "the inspector could be entered while driving")
	driving.set_control_override(0.0, 0.0, 0.0, true)
	for i in 120:
		await frames(1)
		if absf(float(starter.speed)) < 0.05:
			break
	driving.clear_control_override()

func _get_out(starter: Node3D) -> void:
	await frames(16)
	if not driving.get_status().exit_available:
		print("[city_driving_level] exit blocked here: ", driving.get_status().prompt)
	await key(KEY_F)
	if driving.active:
		check(driving.exit_vehicle(true), "forced exit succeeds where the doors are blocked")
	else:
		check(driving.last_exit.door in ["driver", "passenger", "driver_rear", "passenger_rear", "rear", "front"], "F gets out through a checked door (%s)" % driving.last_exit.door)
	check(not level.player.is_seated() and level.player.collision_layer == 4 and level.player.puppet.g.visible, "the explorer is solid and visible again")
	check(starter.state == "parked" and not starter.player_controlled and traffic.player_fleet.has(starter), "the starter stays parked as the player's car")
	await frames(10)
	check(level.player.is_on_floor(), "the explorer stands on walkable ground after getting out")

func _take_traffic_car() -> void:
	# Wait for a civilian car to stop (signals, stop signs, queues) near the
	# explorer with a clear driver door, then board it through the input path.
	var taken: Node3D = null
	for attempt in 1800:
		for car in traffic.vehicles:
			if car.is_police or not car.near_physics or absf(float(car.speed)) > 0.05:
				continue
			if car.global_position.distance_to(level.player.global_position) > 60.0:
				continue
			var lateral: float = Models.dimensions(str(car.prototype_kind)).x * 0.5 + 0.50
			if driving._exit_spot(car, lateral, 0.25, true).is_empty():
				continue
			taken = car
			break
		if taken != null:
			break
		await frames(1)
	if taken == null:
		print("[city_driving_level] SKIP no stopped civilian car with a clear door appeared within 30s")
		return
	level.pause_exploring()
	await frames(2)
	level._place_player(door_point(taken), taken.yaw)
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await key(KEY_F)
	if not check(driving.active and driving.vehicle == taken, "F boards a stopped civilian car from live traffic (%s)" % taken.vehicle_id):
		return
	check(not traffic.reservations.values().has(taken) and taken.reservation_id == "", "the taken car holds no junction reservation")
	# Settle any residual roll on the handbrake, then only AI could move it.
	driving.set_control_override(0.0, 0.0, 0.0, true)
	await frames(10)
	var pose: Transform3D = taken.global_transform
	await frames(60)
	driving.clear_control_override()
	check(taken.global_transform.is_equal_approx(pose) and taken.player_controlled, "live traffic ticks never move the occupied car")
	check(not taken.try_recycle(), "the occupied car is never recycled")
	check(int(traffic.get_status().player_controlled) == 1 and int(traffic.get_status().total) == 90, "traffic counts one player car within its 90")
	if not driving.exit_vehicle(false):
		print("[city_driving_level] normal exit refused here: ", driving.get_status().prompt)
		check(driving.exit_vehicle(true), "forced exit succeeds from the taken car")
	check(not driving.active and taken.player_released and taken.state == "parked", "the taken car is left parked and released to traffic")

func _finish() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release("move_forward")
	Input.action_release("move_back")
	print("[city_driving_level] %d passed, %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
