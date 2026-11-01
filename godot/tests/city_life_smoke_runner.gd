extends Node
## End-to-end checks for neighborhood actors, paused simulation and ordered cases.

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_life] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "living neighborhood initializes")
		_finish()
		return
	check(level.npcs != null and level.traffic != null and level.missions != null, "all three neighborhood systems initialize")
	check(level.npcs.actors.size() >= 6, "mission contacts and ambient neighbors exist")
	for id in ["resident", "lookout", "officer", "gardener", "organizer", "caretaker"]:
		check(level.npcs.get_actor(id) != null, "mission contact " + id)
	check(int(level.npcs.get_status().foot_patrols) == 6, "all six foot patrols placed")
	check(level.traffic.vehicles.size() >= 80, "neighborhood traffic bootstrap populates at least80 vehicles")
	check((level.player.collision_mask & 24) == 24, "player collides with neighbors and cars")
	check(int(level.weathering_report.get("shared_finishes", 0)) > 5, "city has shared weathered surface finishes")
	var eligible: int = level.weathering_report.get("eligible_house_windows", 0)
	var barred: int = level.weathering_report.get("barred_windows", 0)
	check(eligible > 100 and float(barred) / eligible > 0.74 and float(barred) / eligible < 0.86, "roughly eighty percent of measured house windows have bars")
	var consistent_homes := true
	for home in level.weathering_report.get("window_homes", {}).values():
		consistent_homes = consistent_homes and int(home.barred) == (int(home.windows) if home.selected else 0)
	check(consistent_homes, "each house uses one treatment for all measured windows")
	check(int(level.weathering_report.get("window_bar_triangles", -1)) == barred * 2, "window grilles cost only two triangles each")
	check(int(level.weathering_report.get("rough_glass_surfaces", 0)) > 0, "shiny glass is replaced with shared dusty glass")
	check(int(level.weathering_report.get("litter", 0)) >= 30, "decorative roadside litter populates neighborhood walk")
	_check_litter_provider(level)
	check(int(level.weathering_report.get("draw_batches", 0)) < int(level.weathering_report.get("litter", 0)), "litter shares draw batches")
	print("[city_life] weathering ", level.weathering_report)
	var rendering: Dictionary = level.render_optimizer.get_stats()
	check(rendering.get("collision_nodes_preserved", false), "render batching preserves city collision shapes")
	check(int(rendering.get("batch_triangles", 0)) == int(rendering.get("building_triangles", -1)), "render batching preserves full-detail building geometry")
	level.pause_exploring()
	var positions := {}
	for actor in level.npcs.actors.values():
		positions[actor] = actor.global_position
	for car in level.traffic.vehicles:
		positions[car] = car.global_position
	await frames(30)
	var still := true
	for actor in positions:
		still = still and actor.global_position.distance_to(positions[actor]) < 0.001
	check(still, "settings menu freezes neighbors and traffic")
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(240)
	var npc_movement := 0.0
	var car_movement := 0.0
	for actor in level.npcs.actors.values():
		npc_movement = maxf(npc_movement, actor.global_position.distance_to(positions[actor]))
	for car in level.traffic.vehicles:
		car_movement = maxf(car_movement, car.global_position.distance_to(positions[car]))
	check(npc_movement > 0.5, "ambient neighbors actually walk")
	check(car_movement > 2.0, "traffic actually drives")
	print("[city_life] NPC status ", level.npcs.get_status())
	print("[city_life] traffic status ", level.traffic.get_status())
	for actor in positions:
		check(actor.global_position.is_finite() and not level.ground_at(actor.global_position).is_empty(), "actor stays on surveyed terrain: " + str(actor.name))
	level.pause_exploring()
	for actor in positions:
		positions[actor] = actor.global_position
	await frames(30)
	still = true
	for actor in positions:
		still = still and actor.global_position.distance_to(positions[actor]) < 0.001
	check(still, "pause freezes the living neighborhood")
	check(not level.interact(), "pause prevents interactions")
	var status: Dictionary = level.missions.get_status()
	check(status.get("cases", []).size() == 6, "six discoverable cases offered")
	check(str(status.get("active_id", "")).is_empty(), "sightseeing does not auto-start a case")
	await exercise_collisions(level)
	await exercise_cases(level)
	# Returning to the original block must release all actors and case state.
	G.open_original_block()
	await frames(10)
	check(G.built and G.S.mode == "title", "original game remains available after neighborhood cases")
	check(get_tree().current_scene.find_children("StreetTraffic", "", true, false).is_empty(), "traffic does not leak into original scene")
	_finish()

func _check_litter_provider(level: Node) -> void:
	var provider: Node3D = level.get("yard_details")
	check(provider != null, "streamed yard/litter provider exists")
	if provider == null:
		return
	var status: Dictionary = provider.get_status()
	var loose_kinds := ["paper", "wrapper", "cardboard", "loose_can", "cup"]
	var loose_count := 0
	var loose_without_collision := true
	for record in provider.records:
		if str(record.kind) in loose_kinds:
			loose_count += 1
			loose_without_collision = loose_without_collision and is_zero_approx(float(record.radius))
	check(loose_count >= 30 and loose_count == int(status.get("audit", {}).get("litter", -1)) and loose_count == int(level.weathering_report.get("litter", -1)), "actual loose records match yard audit and weathering report")
	check(loose_without_collision and int(status.get("audit", {}).get("loose_litter_colliders", -1)) == 0 and int(status.get("litter_colliders", -1)) == 0, "every loose litter record has zero collision radius")
	var expected_bins: Array[Vector3] = []
	var only_bins_request_collision := true
	for cell in provider._cells.values():
		if not is_instance_valid(cell.node):
			continue
		for index in cell.indices:
			var record: Dictionary = provider.records[index]
			if float(record.radius) > 0.0:
				only_bins_request_collision = only_bins_request_collision and str(record.kind) in ["can", "dumpster"]
				expected_bins.append(record.position)
	check(only_bins_request_collision, "only rigid cans and dumpsters request live yard colliders")
	var colliders := provider.find_children("*", "CollisionObject3D", true, false)
	var actual_bins_only := true
	for body in colliders:
		var matches_bin := false
		for at in expected_bins:
			if body.global_position.distance_to(at) < 0.001:
				matches_bin = true
		actual_bins_only = actual_bins_only and matches_bin and body.get_meta("yard_bin", false) == true and body.collision_layer == 2 and not body.find_children("*", "CollisionShape3D", true, false).is_empty()
	check(not expected_bins.is_empty() and colliders.size() == expected_bins.size() and colliders.size() == int(status.get("active_bin_colliders", -1)), "loaded solid-bin records match actual physics bodies")
	check(actual_bins_only, "all live yard physics bodies belong to solid bins; loose trash has no body")
	check(str(level.weathering_report.get("provider", "")) == "CityYardDetails" and level.get_node_or_null("RoadsideLitter") == null, "litter uses single streamed provider without duplicate legacy nodes")

func exercise_collisions(level: Node) -> void:
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var resident: Node3D = level.npcs.get_actor("resident")
	level._place_player(resident.global_position + Vector3(0, 0, 2.0), PI)
	await frames(4)
	Input.action_press("move_forward")
	await frames(70)
	Input.action_release("move_forward")
	var gap: float = Vector2(level.player.position.x - resident.position.x, level.player.position.z - resident.position.z).length()
	check(gap >= 0.52 and gap < 1.2, "player physically stops at a neighbor")
	var walker: Node3D = level.npcs.get_actor("ambient_mailman")
	var before: Vector3 = walker.global_position
	var destination := before + Vector3(sin(walker.yaw + PI), 0, cos(walker.yaw + PI)) * 2.0
	level.npcs.set_actor_target("ambient_mailman", destination)
	await frames(1)
	check(walker.global_position.distance_to(before) < 0.01, "neighbor turns before walking in a new direction")
	# A real player capsule in the lane must stop the complete sedan, then release it.
	# The first network car may already be turning through a junction. Select a
	# clear straight corridor so the player is on the car's actual future path.
	level.pause_exploring()
	var car: Node3D = _straight_traffic_fixture(level)
	check(car != null, "player-blocking fixture has a clear straight driving corridor")
	if car == null:
		level.spawn_player()
		return
	var forward := Vector3(sin(car.yaw), 0, cos(car.yaw))
	level._place_player(car.global_position + forward * 8.0, car.yaw + PI)
	level.traffic._update_presence()
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(240)
	print("[city_life] player-blocking car ", car.get_status())
	check(car.state == "blocked" and car.speed == 0.0, "car stops for player in its lane")
	gap = Vector2(level.player.position.x - car.position.x, level.player.position.z - car.position.z).length()
	check(gap > 2.8, "car preserves bumper clearance from player")
	check(car.honks > 0, "blocked traffic honks")
	before = car.global_position
	await frames(30)
	check(car.global_position.distance_to(before) < 0.01, "blocked car cannot creep through player")
	level.spawn_player()
	await frames(120)
	check(car.global_position.distance_to(before) > 1.0, "car resumes when lane clears")
	check(not car.try_recycle(), "moving or nearby car cannot be recycled")
	level.pause_exploring()
	# A dense fleet can occupy the old entrance after the blocking test. Choose
	# an actually clear finite lane for the reuse guard, preserving all colliders.
	var recycle_route: Array[Vector3] = _clear_recycle_route(level, car)
	check(not recycle_route.is_empty(), "recycle fixture has grounded clear entrance and endpoint")
	var end_pose: Dictionary = {}
	if not recycle_route.is_empty():
		car.set_manual_route(recycle_route)
		var end_direction: Vector3 = recycle_route[-1] - recycle_route[-2]
		car.yaw = atan2(end_direction.x, end_direction.z)
		end_pose = car._ground_pose(car.route.back(), car.yaw)
	if not end_pose.is_empty():
		car.global_transform = end_pose.transform
		car.state = "parked"
		car.speed = 0.0
		var start: Vector3 = car.route[0]
		var away: Vector3 = (car.route[-1] - start).normalized().cross(Vector3.UP).normalized()
		var observer: Vector3 = (start + car.route[-1]) * 0.5 + away * 120.0
		level._place_player(observer, 0.0)
		level.capture_view(start + Vector3(0, 12, 20), start)
		await frames(2)
		check(not car.try_recycle(), "visible route entrance prevents vehicle recycling")
		level.capture_view(observer + Vector3.UP * 20, observer + Vector3.UP * 20 + away * 80)
		await frames(2)
		check(car.try_recycle() and car.recycled > 0, "distant offscreen car safely reuses its lane route")
		level.release_capture_view()
	else:
		check(false, "traffic route has a grounded endpoint")
	level.spawn_player()

func _straight_traffic_fixture(level: Node) -> Node3D:
	for car in level.traffic.vehicles:
		if car.reservation_id != "" or car.route_index >= car.route.size():
			continue
		var forward := Vector3(sin(car.yaw), 0, cos(car.yaw))
		var path: Array[Vector3] = [car.global_position]
		var length := 0.0
		for i in range(car.route_index, car.route.size()):
			var segment: Vector3 = car.route[i] - path[-1]
			segment.y = 0
			if segment.length() < 0.05:
				continue
			if segment.normalized().dot(forward) < 0.995:
				break
			length += segment.length()
			path.append(car.route[i])
			if length >= 30.0:
				break
		if length < 30.0:
			continue
		var occupied := false
		for other in level.traffic.vehicles:
			if other == car:
				continue
			var delta: Vector3 = other.global_position - car.global_position
			var along := delta.dot(forward)
			if along > -5 and along < 35 and absf(delta.dot(forward.cross(Vector3.UP))) < 2.2:
				occupied = true
		if occupied:
			continue
		var ground: Dictionary = car._ground_pose(path[0], car.yaw)
		if ground.is_empty() or not car._pose_clear(ground.transform):
			continue
		car.set_manual_route(path)
		car.global_transform = ground.transform
		car.speed = 0.0
		car.velocity = Vector3.ZERO
		car.state = "waiting"
		car.stopped_time = 0.0
		car.honks = 0
		car.honk_cooldown = 0.0
		return car
	return null

func _clear_recycle_route(level: Node, car: Node3D) -> Array[Vector3]:
	for lane in level.traffic.network.lanes:
		if not bool(lane.enabled) or float(lane.length) < 35.0:
			continue
		var path: Array[Vector3] = lane.points
		var occupied := false
		for other in level.traffic.vehicles:
			if other != car and (other.global_position.distance_to(path[0]) < 8.0 or other.global_position.distance_to(path[-1]) < 8.0):
				occupied = true
		if occupied:
			continue
		var start_direction := path[1] - path[0]
		var end_direction := path[-1] - path[-2]
		var start_pose: Dictionary = car._ground_pose(path[0], atan2(start_direction.x, start_direction.z))
		var end_pose: Dictionary = car._ground_pose(path[-1], atan2(end_direction.x, end_direction.z))
		if not start_pose.is_empty() and not end_pose.is_empty() and car._pose_clear(start_pose.transform) and car._pose_clear(end_pose.transform):
			return path.duplicate()
	return []

func exercise_cases(level: Node) -> void:
	var cases: Array = level.missions.get_status().get("cases", []).duplicate(true)
	if cases.is_empty():
		return
	check(not level.missions.start_case("unknown_case"), "unknown case is rejected")
	check(level.start_neighborhood_case(str(cases[0].id)), "case entry starts a case and resumes play")
	var status: Dictionary = level.missions.get_status()
	var target: Vector3 = level.vector(status.get("target_position"))
	level._place_player(target + Vector3(0, 0, 1.7), PI)
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.12)
	shape.shape = box
	wall.add_child(shape)
	wall.position = target + Vector3(0, 1.5, 0.8)
	level.add_child(wall)
	await frames(3)
	check(not level.interact(), "nearby case target cannot be used through a wall")
	wall.queue_free()
	await frames(2)
	level._place_player(target + Vector3(35, 0, 35), 0.0)
	check(not level.interact(), "cannot advance a case from far away")
	level.missions.cancel_case()
	check(str(level.missions.get_status().get("active_id", "")).is_empty(), "case can be left for sightseeing")
	var prior_score := 0
	for item in cases:
		var id := str(item.id)
		if id == "lost_satchel":
			level.spawn_player()
			await frames(4)
		check(level.start_neighborhood_case(id), "start " + id)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var steps := 0
		var progressed := true
		while steps < 10:
			status = level.missions.get_status()
			if str(status.get("active_id", "")).is_empty():
				break
			target = level.vector(status.get("target_position"))
			_check_case_guidance(level, status)
			# Stand next to the physical target rather than inside a clue or NPC.
			if id == "lost_satchel":
				if not await walk_to_target(level, target):
					progressed = false
					break
			else:
				var standing := target + Vector3(0, 0, 1.7)
				level._place_player(standing, PI)
			await frames(4)
			var before_stage: int = level.missions.stage
			var opened: bool = level.interact()
			var advanced := false
			if opened and level._dialogue.state.active:
				check(level.missions.stage == before_stage, "opening case dialogue does not advance " + id)
				# Explicitly accept the displayed step, as the player's E/Enter action does.
				level._dialogue.state.choose(0)
				advanced = not level._dialogue.state.active and (level.missions.completed_ids.has(id) or level.missions.stage == before_stage + 1)
			if not advanced:
				print("[city_life] interaction refused ", status, " player=", level.player.position)
				progressed = false
				break
			steps += 1
			await frames(4)
		status = level.missions.get_status()
		check(progressed and steps > 0 and level.missions.completed_ids.has(id) and str(status.get("active_id", "")).is_empty(), "complete ordered case " + id)
		var score := int(status.get("score", 0))
		check(score > prior_score, "case rewards points once: " + id)
		check(not level.missions.start_case(id), "completed case cannot reward twice: " + id)
		check(level.mission_navigation.active_id.is_empty() and level.mission_navigation.route.is_empty(), "completed case clears both maps' navigation: " + id)
		prior_score = score
	check(int(level.missions.get_status().get("completed", 0)) == cases.size(), "all neighborhood cases resolved")

func _check_case_guidance(level: Node, status: Dictionary) -> void:
	# Exercise the production UI refresh rather than bypassing it with a forced
	# test-only navigation rebuild. This runs before each legitimate walk/approach.
	level._update_ui()
	var navigation: RefCounted = level.mission_navigation
	var label := "%s stage %d" % [str(status.active_id), int(status.stage)]
	var destination: Vector3 = level.vector(status.target_position)
	check(navigation.active_id == str(status.active_id) and navigation.stage == int(status.stage) and navigation.target.distance_to(destination) < 0.01, "current-stage destination matches mission: " + label)
	var path: PackedVector3Array = navigation.route
	var route_exists := path.size() >= 2
	check(route_exists, "current mission stage has a reachable street/walk route: " + label)
	if route_exists:
		# A mobile mail-carrier target can move up to the route cache's 2m
		# refresh threshold; fixed contacts/clues must retain exact endpoints.
		var action: Dictionary = level.missions._steps[int(status.stage)]
		var moving := str(action.target) == "ambient_mailman"
		check(path[-1].distance_to(destination) <= (2.1 if moving else 0.02), "route ends at current destination within moving-target cache tolerance: " + label)
		var finite := true
		var clear := true
		for i in path.size():
			finite = finite and path[i].is_finite()
			if i > 0:
				clear = clear and level._navigation_clear_link(path[i - 1], path[i])
		check(finite and clear, "all guidance segments are finite and avoid solid world geometry: " + label)
	var full_map: Control = level._map_overlay.map
	var radar: Control = level._radar.map
	var full_point: Vector2 = full_map._map(navigation.target)
	var radar_point: Vector2 = radar._marker(radar._map(navigation.target), true)
	var radar_radius: float = minf(radar.size.x, radar.size.y) * 0.5 - 15.0
	check(full_point.is_finite() and radar_point.is_finite() and radar_point.distance_to(radar.size * 0.5) <= radar_radius + 0.01, "both map destination projections are valid and radar stays on its rim: " + label)

func walk_to_target(level: Node, target: Vector3) -> bool:
	var points: Array = level.level_data.route.points
	var from_index := 0
	var to_index := 0
	var from_distance := INF
	var to_distance := INF
	for i in points.size():
		var p: Vector3 = level.vector(points[i])
		var distance := Vector2(p.x - level.player.position.x, p.z - level.player.position.z).length()
		if distance < from_distance:
			from_index = i
			from_distance = distance
		distance = Vector2(p.x - target.x, p.z - target.z).length()
		if distance < to_distance:
			to_index = i
			to_distance = distance
	var direction := 1 if to_index >= from_index else -1
	var deadzone := 0.0
	for action in ["move_left", "move_right", "move_back", "move_forward"]:
		deadzone += InputMap.action_get_deadzone(action) * 0.25
	Input.action_release("run")
	for i in range(from_index, to_index + direction, direction):
		var waypoint: Vector3 = level.vector(points[i])
		var arrived := false
		for frame in 480:
			var offset: Vector3 = waypoint - level.player.position
			var remaining_distance := Vector2(offset.x, offset.z).length()
			if remaining_distance < 0.10:
				arrived = true
				break
			level.player.look(Vector2(-angle_difference(level.player.camera_yaw, atan2(offset.x, offset.z)) / level.player.mouse_sensitivity, 0.0))
			# This driver follows a narrow clearance-checked polyline. Brake before
			# its vertices and make tight turns at low speed instead of sprinting
			# past them and circling into neighboring actors. Only drive real input.
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
		if not arrived:
			Input.action_release("run")
			print("[city_life] walking blocked at ", waypoint, " player=", level.player.position, " reason=", level.player.debug_step_reason)
			var capsule: CollisionShape3D = level.player.get("_capsule")
			var probe := PhysicsShapeQueryParameters3D.new()
			probe.shape = capsule.shape
			probe.transform = level.player.global_transform * capsule.transform
			var heading := Vector3(sin(level.player.yaw), 0, cos(level.player.yaw))
			probe.transform.origin += heading * 0.15
			probe.collision_mask = 2 | 8 | 16
			probe.exclude = [level.player.get_rid()]
			for hit in level.get_world_3d().direct_space_state.intersect_shape(probe, 4):
				print("[city_life] forward obstacle=", hit.collider.get_path())
			check(false, "walk to case target with real physics")
			return false
	Input.action_release("run")
	check(Vector2(level.player.position.x - target.x, level.player.position.z - target.z).length() <= 2.4, "walk to case target with real physics")
	return true

func _finish() -> void:
	print("[city_life] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
