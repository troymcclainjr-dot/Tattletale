extends "res://tests/city_priorities_session_fixture.gd"
## Full imported city and real inputs/ball physics. Only the initial player
## approach and camera are arranged; ball positions, velocities, scores, rules
## and opponent state are never assigned by this fixture.
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
var activity: Node3D
var court_frame: RefCounted
var ball_index := -1

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/next-five-20261101/basketball-city-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	_cleanup()
	result_details.scope = "Actual city/court, default semantic input, normal ball physics, one opponent, charge/release and modal cancellation. No injected points or ball/rules/opponent poses."
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	Bindings.apply() # Process-local defaults only; never write the user's controls.
	get_tree().root.size = Vector2i(1280, 720)
	_place_window_off_desktop()
	activity = level.basketball
	check(activity != null and not activity.frames.is_empty(), "actual imported courts expose playable activity frames")
	if activity == null or activity.frames.is_empty():
		_finish()
		return
	# Prefer a full court so the short shot has ample physical runoff.
	var best := INF
	for index in activity.frames.size():
		var frame: RefCounted = activity.frames[index]
		if not frame.playable() or not frame.full():
			continue
		var distance: float = flat_distance(frame.center, player.global_position)
		if distance < best:
			best = distance
			ball_index = index
	if ball_index < 0:
		check(false, "full court available for physical rebound fixture")
		_finish()
		return
	court_frame = activity.frames[ball_index]
	result_details.court_id = court_frame.id
	player.phone.close()
	level.resume_exploring()
	var approach: Dictionary = Facilities.standing_at(level.get_world_3d().direct_space_state, court_frame.center + court_frame.across * 3.0, [player.get_rid()])
	check(not approach.is_empty(), "court approach has collision-clear physical support")
	if approach.is_empty():
		_finish()
		return
	_set_scenario_position(approach.position)
	await frames(30)
	begin_phase("court-pickup-and-rebound")
	check(await _walk_to(court_frame.center), "normal walking reaches actual court ball")
	await frames(12)
	await key(KEY_E)
	check(activity._held == ball_index and activity.mode == "shootaround", "real E picks up this court's physical ball")
	if activity._held != ball_index:
		result_details.failed_status = activity.get_status()
		_finish()
		return
	# Short unassisted toss along the long axis, then a genuine floor rebound.
	player.camera_yaw = atan2(court_frame.along.x, court_frame.along.z)
	player.camera_pitch = 0.24
	player.update_camera()
	var before_shots: int = activity.shots
	await _shoot_button(true)
	await frames(4)
	check(activity._charging and activity._charge > 0.0, "real left press accumulates basketball power")
	await _shoot_button(false)
	check(activity.shots == before_shots + 1 and activity._held < 0 and activity.balls[ball_index].active, "real release launches exactly one moving ball")
	var release_origin: Vector3 = activity.balls[ball_index].body.global_position
	var ground_contact := false
	var max_displacement := 0.0
	for tick in 240:
		await frames(1)
		var ball: Dictionary = activity.balls[ball_index]
		max_displacement = maxf(max_displacement, release_origin.distance_to(ball.body.global_position))
		if bool(ball.release.get("grounded", false)):
			ground_contact = true
			break
	check(ground_contact and max_displacement > 0.5, "released ball travels and physically contacts the court floor")
	result_details.rebound_displacement = max_displacement
	var recovered := await _recover_free_ball()
	check(recovered, "walk to real rebound and press E to recover it")
	if not recovered:
		result_details.failed_status = activity.get_status()
		_finish()
		return
	# Start near the top of the selected half, carrying the recovered ball.
	court_frame.select_hoop(player.global_position)
	check(await _walk_to(court_frame.check_spot()), "normal walking carries ball to the top of the key")
	await frames(15)
	begin_phase("pickup-game")
	await key(KEY_T)
	await frames(30)
	check(activity.mode == "match" and activity.rules != null, "real T starts a game at the actual court")
	check(is_instance_valid(activity.opponent) and activity.opponent.present and activity.opponent_instances == 1, "one live reusable opponent joins the court")
	if activity.mode != "match" or not is_instance_valid(activity.opponent):
		result_details.failed_status = activity.get_status()
		_finish()
		return
	var opponent_id: int = activity.opponent.get_instance_id()
	if activity._held < 0:
		check(await _walk_to(activity.court.check_spot()), "walk to checked match ball")
		await key(KEY_E)
	check(activity._held == ball_index, "player has the legal game ball through real pickup or carried possession")
	await _verify_opponent_support()
	await _capture_court("basketball-city-court.png")
	begin_phase("modal-safety")
	for modal in ["pause", "phone", "map"]:
		await _check_modal(modal)
	begin_phase("power-and-release")
	var rim: Vector3 = activity.court.rim()
	var toward := rim - player.global_position
	player.camera_yaw = atan2(toward.x, toward.z)
	player.camera_pitch = -0.12
	player.update_camera()
	before_shots = activity.shots
	await _shoot_button(true)
	await frames(20)
	check(activity._charging and activity._meter.visible and activity._charge > 0.1, "game power meter shows actual accumulated charge")
	await _capture_court("basketball-city-power.png")
	# Restore the gameplay camera before releasing; no scripted shot solution.
	player.camera_override = {}
	player.update_camera()
	await _shoot_button(false)
	check(activity.shots == before_shots + 1 and not activity._charging and activity._held < 0, "match release launches once and clears charge")
	await frames(90)
	result_details.after_shot = activity.get_status()
	check(activity.mode == "match" and activity.rules != null, "normal shot physics leaves a valid running match")
	begin_phase("quit-and-restart")
	await key(KEY_T)
	check(activity.mode == "match" and activity._quit_armed > 0.0, "first T arms quit without ending the match")
	await key(KEY_T)
	check(activity.rules == null and activity.mode == "free", "second T quits through normal challenge input")
	await key(KEY_T)
	await frames(12)
	check(activity.mode == "match" and activity.games_started == 2, "T starts another game at same court")
	check(activity.opponent_instances == 1 and activity.opponent.get_instance_id() == opponent_id, "restart reuses the same opponent instance")
	result_details.final_status = activity.get_status()
	result_details.limitations = "No forced scores; this fixture checks quit/restart, not a completed-game result/rematch. Rebound recovery is verified in shootaround before the opponent joins."
	check(level.npcs.crowd.get_status().total == 1200 and level.residents.get_status().count == 40 and level.traffic.vehicles.size() == 90, "court session retains full city population")
	check(_window_off_desktop() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "session remains off-desktop with visible uncaptured pointer")
	player.camera_override = {}
	_finish()

func _shoot_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(8, 8) # Clear of phone/menu controls.
	event.global_position = event.position
	Input.parse_input_event(event)
	await get_tree().process_frame

func _verify_opponent_support() -> void:
	# The production opponent ray-grounds move_and_collide; is_on_floor is a
	# move_and_slide cache and never describes this controller's real support.
	# Measure that support directly and retain the actual movement requirement.
	var evidence: Dictionary = {}
	var valid := false
	for tick in 180:
		await frames(1)
		var actor: CharacterBody3D = activity.opponent
		var feet := actor.global_position
		var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.35,
			feet - Vector3.UP * 0.35, 1, [actor.get_rid()])
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		var clearance := INF
		var normal_y := 0.0
		if not hit.is_empty():
			clearance = feet.y - float(hit.position.y)
			normal_y = float(hit.normal.y)
		evidence = {"ticks_waited": tick + 1, "status": actor.get_status(),
			"feet": feet, "ground_clearance": clearance, "ground_normal_y": normal_y,
			"floor_cache": actor.is_on_floor(), "support": str(hit.collider.get_path()) if not hit.is_empty() else ""}
		valid = not hit.is_empty() and normal_y >= 0.7 and clearance >= -0.005 and clearance <= 0.04 and actor.distance_moved > 0.05
		if valid:
			break
	result_details.opponent_physical_support = evidence
	check(valid, "opponent physically settles and moves on actual court geometry")

func _recover_free_ball() -> bool:
	player.set_orbiting(false)
	player._clear_basis_offset()
	for tick in 480:
		var body: CharacterBody3D = activity.balls[ball_index].body
		var toward := body.global_position - player.global_position
		player.camera_yaw = atan2(toward.x, toward.z)
		if flat_distance(player.global_position, body.global_position) > 1.1:
			Input.action_press("move_forward")
			Input.action_press("run")
		else:
			Input.action_release("move_forward")
			Input.action_release("run")
		await frames(1)
		if tick % 6 == 0 and activity._nearest_ball() == ball_index:
			await key(KEY_E)
			if activity._held == ball_index:
				Input.action_release("move_forward")
				Input.action_release("run")
				return true
	Input.action_release("move_forward")
	Input.action_release("run")
	return false

func _check_modal(modal: String) -> void:
	var shots_before: int = activity.shots
	await _shoot_button(true)
	await frames(5)
	check(activity._charging, modal + " precondition: real charge is active")
	var code := KEY_ESCAPE if modal == "pause" else (KEY_P if modal == "phone" else KEY_M)
	await key(code)
	await frames(3)
	var opened: bool = player.phone.active if modal == "phone" else (level._map_overlay.visible if modal == "map" else level.paused)
	check(opened and not activity._charging and not activity._meter.visible, modal + " opens and cancels charge immediately")
	await _shoot_button(false)
	await key(KEY_T)
	await frames(4)
	check(activity.shots == shots_before and activity._held == ball_index and activity.mode == "match" and activity._quit_armed == 0.0, modal + " consumes release/challenge without accidental shot or quit")
	await key(code)
	await frames(3)
	check(not level.paused and not player.phone.active and activity.mode == "match", modal + " closes back into same match")

func _capture_court(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	check(_window_off_desktop(), filename + " keeps rendering safely off-desktop")
	var feet := player.global_position
	var toward: Vector3 = (court_frame.rim() - feet).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	player.camera_override = {"eye": feet - toward * 5.5 + side * 5.0 + Vector3.UP * 4.0,
		"target": feet + toward * 3.0 + Vector3.UP * 1.1}
	player.update_camera()
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/next-five-20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	var image := get_viewport().get_texture().get_image()
	check(image.get_width() == 1280 and image.get_height() == 720, filename + " is native 720p")
	check(image.save_png(folder.path_join(filename)) == OK, filename)
	player.camera_override = {}
	player.update_camera()
