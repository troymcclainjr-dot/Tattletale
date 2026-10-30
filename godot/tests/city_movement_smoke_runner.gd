extends Node
## Controlled full-capsule tests, independent of the geographic map's triangle seams.
const Explorer := preload("res://scripts/city/city_player.gd")
var player: CharacterBody3D
var world: Node3D
var passed := 0
var failed := 0

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
	print("[city_movement] %s %s" % ["PASS" if value else "FAIL", label])

func box(label: String, position_: Vector3, size_: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = position_
	var shape := BoxShape3D.new()
	shape.size = size_
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func reset(position_: Vector3, heading: float) -> void:
	set_move(Vector2.ZERO)
	Input.action_release("run")
	player.set_orbiting(false)
	player.enabled = false
	player.global_position = position_
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.yaw = heading
	player.camera_yaw = heading
	player.camera_pitch = 0.24
	player.update_camera()
	await frames(12)
	player.enabled = true

func set_move(direction: Vector2) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)
	if direction.y > 0:
		Input.action_press("move_forward")
	elif direction.y < 0:
		Input.action_press("move_back")
	if direction.x > 0:
		Input.action_press("move_right")
	elif direction.x < 0:
		Input.action_press("move_left")

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	world.name = "ControlledCurbFixture"
	add_child(world)
	box("FlatGround", Vector3(0, -0.5, 0), Vector3(30, 1, 44), 1)
	# A real 18cm curb with a broad raised pavement surface, not a visual-only marker.
	box("RaisedPavement", Vector3(0, 0.09, 4), Vector3(18, 0.18, 10), 1)
	player = Explorer.new()
	world.add_child(player)
	await frames(5)
	var audio_serial: int = Audio._serial
	await reset(Vector3(0, 0.08, -10), 0.0)
	var initial := player.global_position
	Input.action_press("move_back")
	await frames(1)
	var reversal_motion := player.global_position - initial
	check(reversal_motion.length() > 0.001 and reversal_motion.dot(Vector3(sin(player.yaw), 0, cos(player.yaw))) > 0.0, "reversal steers forward without a turn-in-place pause")
	await reset(Vector3(0, 0.08, -10), 0.0)
	Input.action_press("move_forward")
	await frames(1)
	check(player.current_speed > 0.0 and player.current_speed < player.walk_speed, "walking accelerates rather than instantly jumping to speed")
	await frames(25)
	check(absf(player.current_speed - player.walk_speed) < 0.01, "acceleration reaches walking speed")
	Input.action_release("move_forward")
	await frames(4)
	check(player.current_speed > 0.0 and player.current_speed < player.walk_speed, "release brakes smoothly in the facing direction")
	await frames(15)
	check(player.current_speed < 0.001, "braking comes to a full stop")
	await direction_transitions(false)
	await direction_transitions(true)
	await orbit_controls()
	await camera_follow_controls()
	await porch_stairs(false)
	await porch_stairs(true)
	await sloped_curb(false)
	await sloped_curb(true)
	for angle in [15.0, 45.0, 70.0]:
		await diagonal_curb(float(angle), false)
		await diagonal_curb(float(angle), true)
	# An oblique facade contact should preserve tangent motion without penetration.
	box("TallWall", Vector3(0, 1.5, 14), Vector3(24, 3, 0.5), 2)
	await frames(2)
	await reset(Vector3(-2, 0.08, 11), PI * 0.25)
	initial = player.global_position
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(110)
	var delta_position := player.global_position - initial
	check(player.position.z < 13.48 and player.position.y < 0.08, "diagonal tall wall remains impassable")
	check(delta_position.x > delta_position.z + 3.0 and player.current_speed > player.walk_speed, "diagonal facade contact glides along the wall without hard stopping")
	await reset(Vector3(0, 0.08, 11), 0.0)
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(80)
	check(player.position.z < 13.48 and absf(player.position.x) < 0.02, "head-on facade remains solid without sideways drift")
	var corner := box("WallReturn", Vector3(5, 1.5, 11.75), Vector3(0.5, 3, 4.0), 2)
	await frames(2)
	await reset(Vector3(2, 0.08, 11), PI * 0.25)
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(90)
	check(player.position.x < 4.48 and player.position.z < 13.48, "wall glide stops safely at a solid inside corner")
	corner.queue_free()
	await frames(2)
	# The same step path may not use a neighbor or a vehicle as a stair.
	box("NeighborBody", Vector3(0, 0.9, -5), Vector3(0.6, 1.8, 0.6), 8)
	box("VehicleBody", Vector3(4, 0.6, -4), Vector3(2, 1.2, 3), 16)
	await frames(2)
	await reset(Vector3(0, 0.08, -8), 0.0)
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(90)
	check(player.position.z < -5.58 and player.position.y < 0.08, "neighbor blocks movement and step recovery")
	await reset(Vector3(4, 0.08, -8), 0.0)
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(90)
	check(player.position.z < -5.78 and player.position.y < 0.08, "vehicle blocks movement and step recovery")
	box("TooHighTerrainStep", Vector3(-7, 0.3, -7), Vector3(2, 0.6, 2), 1)
	await frames(2)
	await reset(Vector3(-7, 0.08, -10), 0.0)
	Input.action_press("move_forward")
	Input.action_press("run")
	await frames(90)
	check(player.position.z < -8.25 and player.position.y < 0.08, "terrain riser above maximum step height remains impassable")
	# Enough room for standing on the road, but not for stepping onto this curb.
	box("LowCeiling", Vector3(0, 1.93, -0.9), Vector3(18, 0.2, 2), 2)
	await frames(2)
	await reset(Vector3(0, 0.08, -2.7), 0.0)
	Input.action_press("move_forward")
	await frames(90)
	check(player.position.z < -1.20 and player.position.y < 0.08, "curb ascent respects head clearance")
	Input.action_release("move_forward")
	Input.action_release("run")
	player.enabled = false
	player.camera_pitch = 0.24
	player.invert_y = true
	player.look(Vector2(0, 10))
	check(player.camera_pitch < 0.24, "invert Y setting reverses vertical mouse look")
	player.camera_fov = 75.0
	player.update_camera()
	check(is_equal_approx(player.camera.fov, 75.0), "FOV setting applies to exploration camera")
	check(Audio._serial == audio_serial, "walking and running emit no step beep")
	print("[city_movement] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func direction_transitions(running: bool) -> void:
	# Exercise every ordered pair, including W -> W+D and their rotated/mirrored
	# equivalents. Measure physical travel each tick, not just the target velocity.
	var inputs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
	var speed: float = player.run_speed if running else player.walk_speed
	var continuous := true
	var corners_keep_speed := true
	var forward_only := true
	var smooth_heading := true
	var reaches_heading := true
	var normalized_speed := true
	for from_input in inputs:
		for to_input in inputs:
			if from_input == to_input:
				continue
			var from_heading := atan2(-from_input.x, from_input.y)
			var to_heading := atan2(-to_input.x, to_input.y)
			await reset(Vector3(0, 0.08, -10), from_heading)
			player.camera_yaw = 0.0
			set_move(from_input)
			if running:
				Input.action_press("run")
			# Acceleration is covered above. Seed cruise speed to isolate steering.
			player.current_speed = speed
			await frames(2)
			set_move(to_input)
			var ordinary_corner := absf(angle_difference(from_heading, to_heading)) <= PI * 0.5 + 0.001
			for tick in 32:
				var previous := player.global_position
				var previous_yaw: float = player.yaw
				await frames(1)
				var travelled := player.global_position - previous
				travelled.y = 0.0
				var facing := Vector3(sin(player.yaw), 0, cos(player.yaw))
				continuous = continuous and travelled.length() > speed / 60.0 * 0.30
				forward_only = forward_only and travelled.normalized().dot(facing) > 0.995
				smooth_heading = smooth_heading and absf(angle_difference(previous_yaw, player.yaw)) <= 10.0 / 60.0 + 0.002
				normalized_speed = normalized_speed and player.current_speed <= speed + 0.001
				if ordinary_corner:
					corners_keep_speed = corners_keep_speed and player.current_speed >= speed * 0.99
			reaches_heading = reaches_heading and absf(angle_difference(player.yaw, to_heading)) < 0.025
	var label := "all 56 directional %s transitions " % ["run" if running else "walk"]
	check(continuous, label + "keep moving every frame, including reversals")
	check(corners_keep_speed, label + "preserve cruise speed through 45/90 degree turns")
	check(forward_only, label + "travel with body facing, never sideways/backward")
	check(smooth_heading, label + "bound heading changes without snaps")
	check(reaches_heading, label + "reach each of the eight requested headings")
	check(normalized_speed, label + "avoid diagonal speed boosts")

func orbit_controls() -> void:
	await reset(Vector3(0, 0.08, -10), 0.0)
	set_move(Vector2(0, 1))
	await frames(26)
	player.set_orbiting(true)
	var before := player.global_position
	var camera_before: Vector3 = player.camera.global_position - player.global_position
	player.look(Vector2(-PI * 0.5 / player.mouse_sensitivity, 0))
	await frames(12)
	var shift := player.global_position - before
	var camera_after: Vector3 = player.camera.global_position - player.global_position
	check(absf(shift.x) < 0.01 and shift.z > 0.6 and absf(player.yaw) < 0.001, "held right orbit preserves walking direction")
	check(camera_before.distance_to(camera_after) > 5.0, "right orbit moves camera around the character")
	player.set_orbiting(false)
	before = player.global_position
	await frames(12)
	shift = player.global_position - before
	check(absf(shift.x) < 0.01 and shift.z > 0.6 and absf(player.yaw) < 0.001, "orbit release preserves held movement without a snap")
	check(absf(player.current_speed - player.walk_speed) < 0.01, "orbit and release preserve movement speed")
	# A second orbit during the same movement gesture must retain the first frame.
	player.set_orbiting(true)
	player.look(Vector2(-0.3 / player.mouse_sensitivity, 0))
	await frames(2)
	player.set_orbiting(false)
	check(absf(player.yaw) < 0.001, "repeated orbit holds preserve the original movement frame")
	player.look(Vector2(-0.2 / player.mouse_sensitivity, 0))
	await frames(8)
	check(absf(angle_difference(player.yaw, 0.2)) < 0.025, "ordinary mouse look resumes smooth steering after orbit")
	set_move(Vector2.ZERO)
	await frames(15)
	set_move(Vector2(0, 1))
	await frames(35)
	check(absf(angle_difference(player.yaw, player.camera_yaw)) < 0.025, "fresh movement adopts the orbited camera bearing")
	await reset(Vector3(0, 0.08, -10), 0.0)
	player.set_orbiting(true)
	player.look(Vector2(-1.0 / player.mouse_sensitivity, 0))
	await frames(2)
	check(absf(player.yaw) < 0.001 and player.current_speed < 0.001, "idle orbit leaves character stationary")
	player.set_orbiting(false)
	await frames(2)
	set_move(Vector2(0, 1))
	await frames(25)
	check(absf(angle_difference(player.yaw, player.camera_yaw)) < 0.025, "walking after idle orbit uses the new camera bearing")

func camera_follow_controls() -> void:
	await reset(Vector3(0, 0.08, -18), 0.0)
	player.set_orbiting(true)
	player.look(Vector2(-1.2 / player.mouse_sensitivity, 0))
	set_move(Vector2(0, 1))
	await frames(75)
	check(absf(player.camera_yaw - 1.2) < 0.001, "held orbit defeats automatic follow during sustained movement")
	player.set_orbiting(false)
	var before := player.global_position
	await frames(30)
	check(absf(player.camera_yaw - 1.2) < 0.001, "orbit release grants a look grace period before following")
	await frames(60)
	check(player.camera_yaw < 1.0 and player.camera_yaw > 0.1, "moving camera eases behind the character without snapping")
	check(absf(player.position.x - before.x) < 0.02 and absf(player.yaw) < 0.001, "automatic follow cannot redirect a held movement input")
	set_move(Vector2.ZERO)
	await frames(20)
	var idle_heading: float = player.camera_yaw
	await frames(90)
	check(absf(player.camera_yaw - idle_heading) < 0.001, "idle camera preserves the chosen view without recentering")
	player.look(Vector2(-0.3 / player.mouse_sensitivity, 0))
	var manual_heading: float = player.camera_yaw
	set_move(Vector2(0, 1))
	await frames(30)
	check(absf(player.camera_yaw - manual_heading) < 0.001, "manual mouse look immediately interrupts camera assistance")
	# A real wall compresses the boom; turning away restores distance gradually.
	await reset(Vector3(0, 0.08, -15), 0.0)
	var wall := box("CameraBoomWall", Vector3(0, 1.8, -17), Vector3(4, 3.6, 0.25), 2)
	await frames(2)
	player.update_camera()
	check(player.camera.global_position.z > -16.70, "camera swept volume keeps its near plane outside a wall")
	var compressed: float = player._camera_boom_length
	player.camera_yaw = PI
	player.update_camera(1.0 / 60.0)
	check(player._camera_boom_length > compressed and player._camera_boom_length < compressed + 0.6, "camera distance restores smoothly when an obstruction clears")
	await frames(90)
	check(player._camera_boom_length > 5.0, "camera recovers its full chase distance after clearing a wall")
	wall.queue_free()
	await frames(2)

func porch_stairs(running: bool) -> void:
	# Match the porch kit: 18cm risers, 30cm treads, a 1.25m stair opening,
	# structural layer 2 (not terrain), raised deck, terminal posts and a roof.
	var fixtures: Array[Node] = []
	for i in 4:
		var top := float(i + 1) * 0.18
		fixtures.append(box("PorchTread%d" % i, Vector3(-10, top * 0.5, -12.85 + float(i) * 0.30), Vector3(1.25, top, 0.30), 2))
	fixtures.append(box("PorchDeck", Vector3(-10, 0.45, -9.8), Vector3(3.5, 0.9, 4.0), 2))
	fixtures.append(box("PorchRoof", Vector3(-10, 3.15, -9.8), Vector3(3.8, 0.2, 4.2), 2))
	for side in [-1.0, 1.0]:
		fixtures.append(box("PorchTerminalPost", Vector3(-10 + float(side) * 0.73, 1.40, -11.68), Vector3(0.13, 1.0, 0.14), 2))
	await frames(2)
	await reset(Vector3(-10, 0.08, -14.5), 0.0)
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	var largest_rise := 0.0
	var last_y: float = player.position.y
	for tick in (48 if running else 85):
		await frames(1)
		largest_rise = maxf(largest_rise, player.position.y - last_y)
		last_y = player.position.y
	var label := "porch staircase " + ("run" if running else "walk")
	print("[city_movement] ", label, " final=", player.global_position, " step=", player.debug_step_reason)
	check(player.position.z > -11.0 and player.position.y > 0.86 and player.position.y < 1.0, label + " reaches the actual raised deck")
	check(largest_rise <= player.STEP_HEIGHT + 0.005, label + " climbs individual treads within the original step limit")
	check(absf(player.position.x + 10.0) < 0.02, label + " fits between solid terminal posts")
	await reset(Vector3(-10, 0.98, -10.2), PI)
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	await frames(48 if running else 85)
	check(player.position.z < -13.4 and player.position.y < 0.08, label + " descends back to the ground")
	# Extend over the approach so the rounded head is already under the ceiling
	# before the rounded feet reach the riser; aligned edges permit a safe partial lift.
	var ceiling := box("StairLowOverhang", Vector3(-10, 1.88, -13.0), Vector3(2, 0.15, 1.4), 2)
	await frames(2)
	await reset(Vector3(-10, 0.08, -14.5), 0.0)
	Input.action_press("move_forward")
	await frames(70)
	print("[city_movement] ", label, " low-overhang final=", player.global_position, " step=", player.debug_step_reason)
	check(player.position.z < -12.9 and player.position.y < 0.10, label + " refuses ascent without head clearance")
	set_move(Vector2.ZERO)
	Input.action_release("run")
	player.enabled = false
	ceiling.queue_free()
	for fixture in fixtures:
		fixture.queue_free()
	await frames(2)

func sloped_curb(running: bool) -> void:
	# The real Wyanoke crossing has a ~16cm curb on rising road terrain. Its
	# base is above a ray cast 3.5cm above the player's current ground height.
	var slope := atan(0.20)
	var road := box("UphillRoad", Vector3(10, -0.5 / cos(slope), -12), Vector3(4, 1, 6), 1)
	road.rotation.x = -slope
	var sidewalk_z := -11.0 + 2.0 * cos(slope) + 0.5 * sin(slope)
	var sidewalk_y := 0.18 + 0.20 * (sidewalk_z + 12.0) - 0.5 / cos(slope)
	var pavement := box("UphillRaisedPavement", Vector3(10, sidewalk_y, sidewalk_z), Vector3(4, 1, 4), 1)
	pavement.rotation.x = -slope
	await frames(2)
	await reset(Vector3(10, 0.08, -12.4), 0.0)
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	await frames(45 if running else 80)
	var label := "uphill curb " + ("run" if running else "walk")
	print("[city_movement] ", label, " final=", player.global_position, " step=", player.debug_step_reason)
	check(player.position.z > -10.2 and player.position.y > 0.5, label + " climbs a curb whose base is above the road underfoot")
	check(absf(player.position.x - 10.0) < 0.02, label + " preserves forward travel without side slipping")
	await reset(Vector3(10, 0.90, -9.2), PI)
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	await frames(45 if running else 80)
	check(player.position.z < -11.7 and player.position.y < 0.16, label + " descends onto the sloped road")
	check(absf(player.position.x - 10.0) < 0.02, label + " descends without lateral recovery")
	set_move(Vector2.ZERO)
	Input.action_release("run")
	player.enabled = false
	road.queue_free()
	pavement.queue_free()
	await frames(2)

func diagonal_curb(angle: float, running: bool) -> void:
	var heading := deg_to_rad(angle)
	var direction := Vector3(sin(heading), 0, cos(heading))
	var edge := Vector3(0, 0, -1)
	await reset(edge - direction * 2.0 + Vector3.UP * 0.08, heading)
	var initial := player.global_position
	var last_camera_y: float = player.camera.position.y
	var largest_camera_jump := 0.0
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	for i in (60 if running else 100):
		await frames(1)
		largest_camera_jump = maxf(largest_camera_jump, absf(player.camera.position.y - last_camera_y))
		last_camera_y = player.camera.position.y
	var shift := player.global_position - initial
	var progress := shift.dot(direction)
	var lateral := absf(Vector2(shift.x, shift.z).cross(Vector2(direction.x, direction.z)))
	var label := "%d degree %s" % [roundi(angle), "run" if running else "walk"]
	print("[city_movement] curb ", label, " start=", initial, " final=", player.global_position, " progress=", progress, " lateral=", lateral, " speed=", player.current_speed, " step=", player.debug_step_reason)
	check(progress > 3.5 and player.position.y > 0.13 and player.position.y < 0.25, label + " climbs physical curb")
	check(lateral < 0.18, label + " maintains facing direction over curb")
	check(largest_camera_jump < 0.11, label + " camera eases curb height")
	# Return over the same edge; this catches the formerly failing downhill seam.
	await reset(edge + direction * 2.0 + Vector3.UP * 0.28, heading + PI)
	Input.action_press("move_forward")
	if running:
		Input.action_press("run")
	await frames(60 if running else 100)
	check(player.position.y < 0.06 and player.position.z < -1.4, label + " descends physical curb")
