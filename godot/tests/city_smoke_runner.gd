extends Node

var passes := 0
var fails := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_test] %s %s" % ["PASS" if ok else "FAIL", label])

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await frames(5)
	check(G.built and G.S.mode == "title", "original block boots")
	var button: Button = null
	for node in Hud.find_children("*", "Button", true, false):
		if "PEN LUCY" in node.text.to_upper():
			button = node
	check(button != null, "title offers Explore Pen Lucy")
	if button:
		button.pressed.emit()
	else:
		G.open_neighborhood()
	await frames(6)
	var level: Node = get_tree().current_scene
	for i in 240:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	check(level != null and level.scene_file_path.ends_with("pen_lucy.tscn"), "menu loads Baltimore scene")
	if level == null or level.get("player") == null:
		check(false, "neighborhood player initialized")
		_finish()
		return
	check(level.get("level_ready") == true, "city initialization completes")
	check(not G.built and G.LATER.is_empty(), "legacy simulation and timers stop")
	var player: CharacterBody3D = level.player
	await frames(45)
	check(player.is_on_floor(), "spawn rests on real terrain")
	check(player.global_position.is_finite(), "player coordinates remain finite")
	check(level.landmarks.size() >= 3, "route has at least three named destinations")
	check(player.enabled and not level.paused, "neighborhood opens directly into play")
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(not level.check_in(), "cannot check in from outside destination radius")
	player.toggle_view()
	check(player.first_person and not player.puppet.g.visible, "first-person view hides player mesh")
	player.toggle_view()
	check(not player.first_person and player.puppet.g.visible, "third-person view restores player mesh")
	level.pause_exploring()
	var paused_position: Vector3 = player.global_position
	Input.action_press("move_forward")
	await frames(8)
	Input.action_release("move_forward")
	check(Vector2(player.position.x - paused_position.x, player.position.z - paused_position.z).length() < 0.01, "pause disables walking")
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var turning_position: Vector3 = player.global_position
	Input.action_press("move_back")
	await frames(1)
	Input.action_release("move_back")
	var turn_travel := Vector2(player.position.x - turning_position.x, player.position.z - turning_position.z)
	check(turn_travel.dot(Vector2(sin(player.yaw), cos(player.yaw))) >= -0.001, "direction changes travel with facing rather than sliding backward")
	level.spawn_player()
	await frames(10)
	await walk_route(level)
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for landmark in level.landmarks:
		var p: Vector3 = level.vector(landmark.position)
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p - Vector3.UP * 4.0, 1)
		var hit := space.intersect_ray(query)
		check(not hit.is_empty(), "terrain under " + str(landmark.label))
		level.teleport_to_landmark(str(landmark.id))
		await frames(24)
		check(player.is_on_floor(), "can stand at " + str(landmark.label))
	# Sweep the actual player capsule into a known nearby building wall.
	var obstacle_hit := false
	for node in level.find_children("*", "MeshInstance3D", true, false):
		if not (str(node.name).begins_with("Row_") or str(node.name).begins_with("Bldg_")):
			continue
		var box: AABB = node.get_aabb()
		# Streaming deliberately releases hidden render meshes. Use retained
		# authoritative collision geometry to locate the facade under test.
		if node.mesh == null:
			var shapes := node.find_children("*", "CollisionShape3D", true, false)
			if shapes.is_empty() or not shapes[0].shape is ConcavePolygonShape3D:
				continue
			var faces: PackedVector3Array = shapes[0].shape.get_faces()
			if faces.is_empty():
				continue
			box = AABB(faces[0], Vector3.ZERO)
			for vertex in faces:
				box = box.expand(vertex)
		var center: Vector3 = node.global_transform * box.get_center()
		var query := PhysicsRayQueryParameters3D.create(center + Vector3(0, 1, 30), center + Vector3(0, 1, -30), 2)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			if absf(normal.y) < 0.2:
				var pose := Transform3D(Basis.IDENTITY, hit.position + normal * 0.8 - Vector3.UP * 0.85)
				obstacle_hit = player.test_move(pose, -normal * 1.6)
				if obstacle_hit:
					break
	check(obstacle_hit, "player capsule is blocked by a building facade")
	level.spawn_player()
	await frames(20)
	var initial: Vector3 = player.global_position
	player.enabled = true
	Input.action_press("move_forward")
	await frames(45)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(initial) > 0.5, "walking input moves through neighborhood")
	check(player.is_on_floor(), "walking maintains terrain contact")
	level.spawn_player()
	await frames(15)
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(5, 3, 0.25)
	wall_shape.shape = box_shape
	wall.add_child(wall_shape)
	wall.position = player.position + Vector3(0, 1.5, -2.0)
	level.add_child(wall)
	await frames(3)
	var wall_start: Vector3 = player.global_position
	player.yaw = PI
	player.camera_yaw = PI
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	check(player.global_position.z > wall_start.z - 1.8 and player.global_position.z < wall_start.z - 0.4, "actual movement stops at tall walls without stepping through")
	wall.queue_free()
	G.open_original_block()
	await frames(8)
	check(G.built and G.S.mode == "title", "return rebuilds original title and cast")
	check(G.W.has("dan") and G.W.has("mama"), "old world references restored")
	G.start_game()
	G.manual = true
	G.tick(1.0 / 60.0)
	check(G.S.mode == "play" and G.C.gary.active, "old game starts after visiting Baltimore")
	Hud.show_pause(true)
	Hud.card("Old stage card", "Must be cleared", 300)
	Hud.puzzle_show("keypad", G.C.gary)
	Hud.say("GARY", "Old subtitle", 300)
	G.open_neighborhood()
	await frames(8)
	level = get_tree().current_scene
	for i in 240:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	check(level != null and level.get("level_ready") == true and not G.built, "Baltimore can be entered again")
	check(not Hud._screens.pause.visible and not Hud._screens.stagecard.visible and not Hud._puzzle.visible and Hud._puzzle.focus == null, "transitions clear old overlays and puzzle references")
	_finish()

func walk_route(level: Node) -> void:
	var points: Array = level.level_data.get("route", {}).get("points", [])
	check(points.size() > 3, "continuous sidewalk route is exported")
	var reached := true
	var last_index := 0
	var deadzone := 0.0
	for action in ["move_left", "move_right", "move_back", "move_forward"]:
		deadzone += InputMap.action_get_deadzone(action) * 0.25
	Input.action_release("run")
	for index in points.size():
		last_index = index
		var target: Vector3 = level.vector(points[index])
		var arrived := false
		for step_ in 480:
			var offset: Vector3 = target - level.player.global_position
			# Stay within the route's clearance envelope instead of cutting corners.
			var remaining_distance := Vector2(offset.x, offset.z).length()
			if remaining_distance < 0.10:
				arrived = true
				break
			level.player.look(Vector2(-angle_difference(level.player.camera_yaw, atan2(offset.x, offset.z)) / level.player.mouse_sensitivity, 0.0))
			# Approach each vertex under braking, then steer a small forward arc.
			# Full-speed pursuit overshoots tight vertices even on a clear route.
			var heading_error := absf(angle_difference(level.player.yaw, level.player.camera_yaw))
			var running := remaining_distance > 2.0 and heading_error < 0.12
			if running:
				Input.action_press("run")
			else:
				Input.action_release("run")
			var maximum_speed: float = level.player.run_speed if running else level.player.walk_speed
			var approach_speed := minf(maximum_speed, sqrt(24.0 * maxf(remaining_distance - 0.045, 0.0)))
			if heading_error > 0.12:
				approach_speed = minf(approach_speed, 0.40)
			var strength := deadzone + (1.0 - deadzone) * clampf(approach_speed / maximum_speed, 0.0, 1.0)
			Input.action_press("move_forward", strength)
			await frames(1)
		Input.action_release("move_forward")
		level.check_in()
		if not arrived:
			print("[city_test] blocked at route point %d target=%s player=%s" % [index, target, level.player.global_position])
			print("[city_test] step reason: ", level.player.debug_step_reason)
			var probe_at: Vector3 = level.player.global_position
			var terrain_ray := PhysicsRayQueryParameters3D.create(probe_at + Vector3.UP * 3, probe_at - Vector3.UP * 3, 1)
			terrain_ray.hit_back_faces = false
			print("[city_test] front-face downward ray: ", level.get_world_3d().direct_space_state.intersect_ray(terrain_ray))
			terrain_ray.from = probe_at - Vector3.UP * 3
			terrain_ray.to = probe_at + Vector3.UP * 3
			print("[city_test] front-face upward ray: ", level.get_world_3d().direct_space_state.intersect_ray(terrain_ray))
			var contact := KinematicCollision3D.new()
			var motion: Vector3 = target - level.player.global_position
			motion.y = 0
			if level.player.test_move(level.player.global_transform, motion.normalized() * 0.5, contact):
				print("[city_test] obstacle=%s normal=%s position=%s" % [contact.get_collider().get_path(), contact.get_normal(), contact.get_position()])
			print("[city_test] velocity=%s yaw=%s camera_yaw=%s floor=%s enabled=%s" % [level.player.velocity, level.player.yaw, level.player.camera_yaw, level.player.is_on_floor(), level.player.enabled])
			for slide_index in level.player.get_slide_collision_count():
				var slide: KinematicCollision3D = level.player.get_slide_collision(slide_index)
				print("[city_test] slide=%s normal=%s position=%s" % [slide.get_collider().get_path(), slide.get_normal(), slide.get_position()])
			var rise := KinematicCollision3D.new()
			var up_hit: bool = level.player.test_move(level.player.global_transform, Vector3.UP * 0.28, rise)
			print("[city_test] step up hit=%s normal=%s travel=%s" % [up_hit, rise.get_normal() if up_hit else Vector3.ZERO, rise.get_travel() if up_hit else Vector3.ZERO])
			var raised: Transform3D = level.player.global_transform
			raised.origin.y += 0.28
			var ahead := KinematicCollision3D.new()
			var forward: Vector3 = motion.normalized() * 0.12
			var forward_hit: bool = level.player.test_move(raised, forward, ahead)
			print("[city_test] step forward hit=%s normal=%s travel=%s" % [forward_hit, ahead.get_normal() if forward_hit else Vector3.ZERO, ahead.get_travel() if forward_hit else Vector3.ZERO])
			raised.origin += forward
			var down := KinematicCollision3D.new()
			var down_hit: bool = level.player.test_move(raised, Vector3.DOWN * 0.36, down)
			print("[city_test] step down hit=%s normal=%s travel=%s" % [down_hit, down.get_normal() if down_hit else Vector3.ZERO, down.get_travel() if down_hit else Vector3.ZERO])
			reached = false
			break
	Input.action_release("run")
	check(reached, "walk complete route with real physics (%d/%d points)" % [last_index + 1, points.size()])
	check(level.get_progress().finished, "all route stops checked in through walking")

func _finish() -> void:
	Input.action_release("move_forward")
	print("[city_test] %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
