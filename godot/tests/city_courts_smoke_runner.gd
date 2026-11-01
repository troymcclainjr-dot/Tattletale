extends Node
var passed := 0
var failed := 0
var level: Node3D

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[city_courts] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(5)
	level = get_tree().current_scene
	for i in 1800:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes")
		get_tree().quit(1)
		return
	var courts: Node3D = level.park_courts
	check(courts != null and not courts.records.is_empty(), "fitted green-space courts are integrated")
	if courts == null or courts.records.is_empty():
		get_tree().quit(1)
		return
	level.pause_exploring()
	var status: Dictionary = courts.get_status()
	var court_count: int = courts.records.size()
	check(status.floor_colliders == court_count and status.pole_colliders == status.hoops, "every playing surface and hoop pole has physical collision")
	check(status.backboard_colliders == status.hoops and status.arm_colliders == status.hoops, "every backboard and support arm has matching overhead collision")
	check(float(status.audit.max_court_grade) <= 0.0151 and float(status.audit.max_apron_slope_deg) < 4.0 and float(status.audit.max_fill_m) <= 0.8, "court planes and joining ramps respect bounded grade/fill limits")
	check(int(level.vegetation.get_stats().trees) == int(status.audit.retained_trees), "court reservations and retained neighborhood canopy match the export audit")
	var covered := {}
	var exclusions := 0
	var accounted := true
	for green in status.audit.green_coverage:
		if green.status == "covered":
			covered[green.green_id] = green.court_id
		else:
			exclusions += 1
			accounted = accounted and not str(green.reason).is_empty()
	for record in courts.records:
		accounted = accounted and covered.get(record.green_id, "") == record.id
	check(accounted and covered.size() == court_count and exclusions == int(status.audit.excluded_greens), "every inventoried green is covered or has an explicit geometric exclusion")
	var named_parks_covered := true
	for park in status.audit.green_inventory.named_parks:
		var found := false
		for green_id in park.green_ids:
			found = found or covered.has(green_id)
		named_parks_covered = named_parks_covered and found
	check(named_parks_covered, "all mapped park regions have a court in their surrounding green")
	var clear := true
	for resident in level.npcs.crowd.residents:
		if resident.activity == "park":
			clear = clear and not courts.is_court(resident.position, 0.49)
	check(clear and int(level.npcs.crowd.get_status().park) == 160, "park residents remain populated without standing in playing areas")
	var user_args := OS.get_cmdline_user_args()
	var capture_index := user_args.find("--capture-court-id")
	var capture_id := ""
	if capture_index >= 0 and capture_index + 1 < user_args.size():
		capture_id = user_args[capture_index + 1]
	for record in courts.records:
		var center: Vector3 = record.position
		var across: Vector3 = level.vector(record.across)
		var along: Vector3 = level.vector(record.along)
		var supported := true
		for u in [-0.42, 0.0, 0.42]:
			for v in [-0.42, 0.0, 0.42]:
				var at: Vector3 = center + across * float(record.width_m) * float(u) + along * float(record.length_m) * float(v)
				var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1))
				supported = supported and not hit.is_empty()
				if not hit.is_empty():
					supported = supported and hit.collider.name == "CourtSupport" and hit.normal.y > 0.9998
		check(supported, str(record.id) + " actual imported floor rays match the low-grade court surface")
		check(record.instance.mesh.get_surface_count() == 1, str(record.id) + " paint and hoops share one draw surface")
		var poles_solid := true
		var overhead_solid := true
		for hoop in record.hoops:
			var at: Vector3 = hoop.position + Vector3.UP
			var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at - Vector3.RIGHT * 0.5, at + Vector3.RIGHT * 0.5, 2))
			poles_solid = poles_solid and not hit.is_empty() and not courts.is_clear(hoop.position, 0.3)
			var board_at: Vector3 = hoop.board_position + across * .55
			var board_hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(board_at - Vector3.UP * .8, board_at + Vector3.UP * .8, 2))
			var arm_at: Vector3 = hoop.arm_position
			var arm_hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(arm_at - Vector3.UP * .3, arm_at + Vector3.UP * .3, 2))
			overhead_solid = overhead_solid and not board_hit.is_empty() and not arm_hit.is_empty()
			if not board_hit.is_empty() and not arm_hit.is_empty():
				overhead_solid = overhead_solid and str(board_hit.collider.name).begins_with("SolidHoopBackboard") and str(arm_hit.collider.name).begins_with("SolidHoopArm")
		check(poles_solid, str(record.id) + " hoop poles block collision and population reservations")
		check(overhead_solid, str(record.id) + " upward rays hit actual backboards and support arms")
		if int(record.get("retaining_triangles", 0)) > 0:
			var holder: Node = courts.get_node(str(record.id))
			check(holder.has_node("SolidCourtRetainingEdge"), str(record.id) + " raised slab has solid retaining sides")
		# Both retained slabs and ordinary aprons have opposed across-axis access.
		var crossing_length: float = float(record.width_m) + 2.0 + float(record.apron_width_m) * 2.0 - 0.6
		var start := center - across * (crossing_length * 0.5)
		level._place_player(start, atan2(across.x, across.z))
		level.resume_exploring()
		await frames(5)
		start = level.player.global_position
		Input.action_press("move_forward")
		Input.action_press("run")
		for i in 420:
			await frames(1)
			if (level.player.global_position - start).dot(across) > crossing_length - 0.4:
				break
		Input.action_release("move_forward")
		Input.action_release("run")
		var progress: float = (level.player.global_position - start).dot(across)
		check(progress > crossing_length - 0.5 and level.player.is_on_floor(), str(record.id) + " player physically traverses both access ramps and playing slab")
		level._place_player(center, 0.0)
		await frames(8)
		var ground_y: float = level.player.position.y
		level.player.request_jump()
		await frames(12)
		check(level.player.position.y > ground_y + 0.5, str(record.id) + " jump works on court collision")
		await frames(55)
		check(level.player.is_on_floor() and absf(level.player.position.y - ground_y) < 0.03, str(record.id) + " jump lands on the same slab")
		if record.id == courts.records[0].id:
			await check_backboard_jump(record)
		level.pause_exploring()
		if str(record.id) == capture_id or ("--capture-courts" in user_args and capture_id.is_empty()):
			await capture(record)
	courts.set_presence(Vector3(9000, 0, 9000))
	check(courts.get_status().draw_batches == 0 and courts.get_status().floor_colliders == court_count, "distant courts cull visuals while retaining safe ground")
	print("[city_courts] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func check_backboard_jump(record: Dictionary) -> void:
	var board: Vector3 = record.hoops[0].board_position
	# Offset along the board width to test its underside without also hitting the rim.
	var at: Vector3 = board + level.vector(record.across) * .55
	at.y = record.position.y
	level._place_player(at, 0.0)
	await frames(8)
	var start_y: float = level.player.position.y
	var max_y := start_y
	var ceiling_contact := false
	var capsule: CollisionShape3D = level.player._capsule
	var capsule_shape := capsule.shape as CapsuleShape3D
	var head_offset: float = capsule.position.y + capsule_shape.height * .5
	level.player.request_jump()
	for frame in 75:
		await frames(1)
		max_y = maxf(max_y, level.player.position.y)
		ceiling_contact = ceiling_contact or level.player.is_on_ceiling()
	check(max_y > start_y + .5 and ceiling_contact, "actual player jump contacts the underside of the backboard")
	check(max_y + head_offset <= board.y - .525 + .035, "player head stays below the solid backboard")
	check(level.player.is_on_floor() and absf(level.player.position.y - start_y) < .03, "backboard jump returns safely to the court")

func capture(record: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not level.offscreen_validation:
		check(false, "court captures require offscreen GPU validation")
		return
	var output := "res://../artifacts/vehicle-courts/courts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	level._ui.hide()
	level.player.first_person = true
	var center: Vector3 = record.position
	var across: Vector3 = level.vector(record.across)
	var along: Vector3 = level.vector(record.along)
	# Include the entire full court and both access ramps in one view.
	level.capture_view(center + along * 18.0 + across * 15.0 + Vector3.UP * 30.0, center + Vector3.UP * 0.7)
	level.streaming.refresh_now()
	await frames(100)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(str(record.id) + ".png")) == OK, "capture " + str(record.id))
	level.player.camera_override.clear()
	level.player.first_person = false
	level._ui.show()
