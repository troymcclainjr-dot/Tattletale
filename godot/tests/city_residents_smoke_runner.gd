extends Node
## Real-world placement, route sweep, identity, pause, and population parity checks.
const Residents := preload("res://scripts/city/city_residents.gd")
const People := preload("res://scripts/city/city_modular_people.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
var passes := 0
var failures := 0
var deployment: Dictionary = {}

func check(value: bool, label: String) -> void:
	print("[city_residents] %s %s" % ["PASS" if value else "FAIL", label])
	if value:
		passes += 1
	else:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Residents.DATA_PATH))
	check(data.residents.size() == 40, "exactly forty authored residents")
	var identities := {}
	var appearances := {}
	var starts := {}
	for definition in data.residents:
		identities[definition.id] = true
		appearances[JSON.stringify(definition.appearance)] = true
		starts[definition.schedule[2].minute] = true
		check(int(definition.age) >= 18 and float(definition.appearance.h) >= 1.5, str(definition.id) + " is an adult")
		check(Residents.schedule_slot(definition.schedule, 1439.0) == 5 and Residents.schedule_slot(definition.schedule, 1440.0) == 0, str(definition.id) + " crosses midnight correctly")
		for i in range(1, definition.schedule.size()):
			check(Residents.schedule_slot(definition.schedule, float(definition.schedule[i].minute)) == i, str(definition.id) + " exact boundary %d" % i)
	check(identities.size() == 40 and appearances.size() == 40 and starts.size() >= 15, "identities, appearances, and work times are distinctive")
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("residents") == null:
		check(false, "resident provider initialized")
		_finish()
		return
	await frames(55)
	var provider: Node = level.residents
	var status: Dictionary = provider.get_status()
	check(status.count == 40 and status.placement_failures.is_empty(), "forty safe grounded residents spawned")
	check(status.pending_routes == 0 and status.path_builds == 40, "bounded route preparation completes")
	check(status.route_failures.is_empty(), "all residents have substantial accessible frontages")
	print("[city_residents] route failures: ", status.route_failures)
	var safe_routes := true
	var distinct_streets := {}
	for id in provider.routes:
		var route: Dictionary = provider.routes[id]
		var actor = provider.get_actor(id)
		distinct_streets[provider.placements[id].road.name] = true
		check(level.npcs.get_actor(id) == actor and level.conversations.has(id), str(id) + " reachable by interaction API")
		check(route.anchors.work != route.anchors.home and route.anchors.leisure != route.anchors.work, str(id) + " has distinct daily destinations")
		for i in range(1, route.points.size()):
			if provider._clear_edge(route.points[i - 1], route.points[i]).is_empty():
				safe_routes = false
	check(safe_routes, "every route edge passes full capsule sweep and ground clearance")
	check(distinct_streets.size() >= 8, "residents use the neighborhood, not one repeated short patrol")
	_capture_deployment(level, provider, safe_routes)
	level.pause_exploring()
	var paused_minutes: float = level.world_time.total_minutes
	var before := {}
	for id in provider.actors:
		before[id] = provider.actors[id].global_position
	await frames(45)
	var paused := true
	for id in before:
		paused = paused and before[id].distance_to(provider.actors[id].global_position) < 0.001
	check(paused, "pause freezes resident physical and logical progress")
	check(level.world_time.total_minutes == paused_minutes, "pause freezes the shared daily clock beyond the far update interval")
	provider.set_routines_enabled(false)
	check(provider.actors.size() == 40, "routine benchmark toggle retains the same forty identities")
	var identical := true
	for id in before:
		identical = identical and before[id].distance_to(provider.actors[id].global_position) < 0.001
	check(identical, "routine benchmark toggle preserves all positions")
	var saved: Dictionary = provider.snapshot_state()
	check(saved.version == 1 and saved.residents.size() == 40 and saved.has("total_minutes"), "versioned checkpoint contains identities, schedule progress, and day clock")
	var legacy: Dictionary = saved.duplicate(true)
	var appended_positions: Dictionary = {}
	for id in saved.residents:
		if id not in Residents.LEGACY_RESIDENT_IDS:
			legacy.residents.erase(id)
			appended_positions[id] = provider.actors[id].global_position
	var legacy_restore: Dictionary = provider.restore_state(legacy)
	var appended_unchanged := appended_positions.size() == 20
	for id in appended_positions:
		appended_unchanged = appended_unchanged and provider.actors[id].global_position.distance_to(appended_positions[id]) < .001
	check(legacy.residents.size() == 20 and legacy_restore.restored == 20 and legacy_restore.fallback == 0 and appended_unchanged, "original twenty-ID checkpoint restores without moving or removing twenty appended residents")
	deployment.legacy_restore = {"restored": legacy_restore.restored, "fallback": legacy_restore.fallback, "appended_unchanged": appended_unchanged}
	provider.set_routines_enabled(true)
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(120)
	var progressed := 0
	for id in before:
		if before[id].distance_to(provider.actors[id].global_position) > 0.2:
			progressed += 1
	check(progressed > 0, "daily destination movement advances in real neighborhood")
	# Exercise the real clock across all forty schedules, including midnight.
	level.pause_exploring()
	var previous_minutes: float = level.world_time.total_minutes
	var boundaries: Array[float] = [0.0, 1439.0, 1440.0, 1440.0 + 540.0]
	for definition in data.residents:
		for entry in definition.schedule:
			boundaries.append(float(entry.minute))
	boundaries.sort()
	var all_activities := true
	var visited_activities: Dictionary = {}
	for minute in boundaries:
		level.world_time.set_time(minute)
		for actor in provider.actors.values():
			provider._update_schedule(actor)
			var slot := Residents.schedule_slot(actor.routine.schedule, minute)
			all_activities = all_activities and actor.activity == str(actor.routine.schedule[slot].activity)
			visited_activities[actor.activity] = true
	check(all_activities and visited_activities.size() == 4, "all forty live actors adopt home, work, leisure, and sleep across a full day")
	check(level.world_time.day_index == 1, "resident schedule survives the live clock's midnight rollover")
	level.world_time.total_minutes = previous_minutes
	for actor in provider.actors.values():
		provider._update_schedule(actor, true)
	# Activate a walking adult at their surveyed position and measure full body
	# motion, rather than letting far logical simulation satisfy this assertion.
	var subject = null
	for actor in provider.actors.values():
		if actor.route_points.size() - actor.route_cursor < 10:
			continue
		var toward: Vector3 = actor.route_points[-1] - actor.global_position
		toward.y = 0.0
		var visitor: Dictionary = level.npcs.find_safe_position(actor.global_position - toward.normalized() * 5.0, 0.30)
		if visitor.ok and visitor.position.distance_to(actor.global_position) > 2.0:
			level._place_player(visitor.position, 0.0)
			subject = actor
			break
	check(subject != null, "a physical resident encounter is available")
	if subject != null:
		level.resume_exploring()
		await frames(5)
		var physical_start: Vector3 = subject.global_position
		var forward_only := true
		for frame in 150:
			var old_position: Vector3 = subject.global_position
			await frames(1)
			var travel: Vector3 = subject.global_position - old_position
			travel.y = 0.0
			if travel.length() > 0.001:
				forward_only = forward_only and travel.normalized().dot(Vector3(sin(subject.yaw), 0.0, cos(subject.yaw))) > 0.99
		check(subject.physical and subject.enabled and physical_start.distance_to(subject.global_position) > 0.2, "near resident advances through full CharacterBody collision movement")
		check(forward_only, "physical daily resident turns before moving, without side sliding")
		level.pause_exploring()
		# Disable route motion so this checks only activation policy. Positions
		# may change only when the player explicitly teleports in this test.
		provider.set_routines_enabled(false)
		var stable: Vector3 = subject.global_position
		level.player.global_position = stable + Vector3(105, 0, 0)
		provider.tick(0.01)
		check(subject.physical and subject.get_status().fade > 0.99, "100–120m hysteresis retains body after appearance fades out")
		level.player.global_position = stable + Vector3(125, 0, 0)
		provider.tick(0.01)
		check(not subject.physical and not subject.visible, "fully faded resident changes to cheap far simulation")
		level.player.global_position = stable + Vector3(105, 0, 0)
		provider.tick(0.01)
		check(not subject.physical and stable.distance_to(subject.global_position) < 0.001, "hysteresis avoids repeated activation and position jumps")
		provider.set_routines_enabled(true)
	print("[city_residents] summary: count=%d near=%d far=%d progressed=%d" % [status.count, status.near, status.far, progressed])
	_finish()

func _capture_deployment(level: Node, provider: Node, safe_routes: bool) -> void:
	var daily_styles: Dictionary = {}
	var daily: Dictionary = {}
	var bound_rigs := true
	for id in provider.actors:
		var actor: Node3D = provider.actors[id]
		var profile: Dictionary = actor.get_meta("population_appearance", {})
		var style := str(profile.get("roster_id", ""))
		daily_styles[style] = int(daily_styles.get(style, 0)) + 1
		var render_indices: Array[int] = []
		_rig_indices(actor.puppet.g, render_indices)
		var expected_index := int(profile.get("roster_index", -1))
		bound_rigs = bound_rigs and render_indices.size() == 9
		for value in render_indices:
			bound_rigs = bound_rigs and value == expected_index
		var route: Dictionary = provider.routes.get(id, {})
		var at: Vector3 = actor.global_position
		daily[id] = {"style": style, "index": expected_index, "position": [at.x, at.y, at.z],
			"street": str(provider.placements[id].road.name), "route_points": route.get("points", []).size(), "anchors": route.get("anchors", {})}
	var ambient_styles: Dictionary = {}
	var ambient_ids: Dictionary = {}
	var uploads_ok := true
	var hardware_readback := DisplayServer.get_name() != "headless"
	var gpu_uploads_ok := true
	var crowd: Node = level.npcs.crowd
	for ordinal in crowd.residents.size():
		var resident: Dictionary = crowd.residents[ordinal]
		var identity := str(resident.get("stable_id", "crowd_%d" % ordinal))
		ambient_ids[identity] = true
		var profile: Dictionary = resident.get("appearance", {})
		var canonical: Dictionary = Appearance.profile(identity)
		uploads_ok = uploads_ok and profile == canonical
		if not resident.has("batch") or not crowd._batches.has(resident.batch):
			uploads_ok = false
			continue
		var multi: MultiMesh = crowd._batches[resident.batch].multimesh
		if hardware_readback:
			gpu_uploads_ok = gpu_uploads_ok and roundi(multi.get_instance_custom_data(int(resident.slot)).r) == int(canonical.roster_index)
		if not resident.get("identity_unplaced", false) and not resident.get("dead", false):
			var style := str(profile.get("roster_id", ""))
			ambient_styles[style] = int(ambient_styles.get(style, 0)) + 1
	var covered := People.roster().size() == 40 and daily_styles.size() == 40 and ambient_styles.size() == 40
	for look in People.roster():
		covered = covered and int(daily_styles.get(str(look.id), 0)) == 1 and int(ambient_styles.get(str(look.id), 0)) > 0
	check(covered and bound_rigs, "all forty style IDs deployed once as named daily rigs and represented by placed living ambient residents")
	check(crowd.residents.size() == 1200 and ambient_ids.size() == 1200 and uploads_ok, "actual1200 ambient batch slots carry canonical CPU stable-ID appearance records")
	if hardware_readback:
		check(gpu_uploads_ok, "actual1200 ambient MultiMesh GPU custom-data slots match canonical roster indices")
	else:
		print("[city_residents] SKIP GPU custom-data readback: requires real renderer; headless dummy returns identity colors")
	check(provider.routes.size() == 40 and safe_routes, "all forty deployed residents own swept safe routes")
	deployment = {"daily_count": daily.size(), "daily_styles": daily_styles, "daily": daily,
		"ambient_count": crowd.residents.size(), "ambient_styles": ambient_styles, "ambient_stable_ids": ambient_ids.size(),
		"all_styles_deployed": covered, "rigs_bound": bound_rigs, "ambient_cpu_records_valid": uploads_ok, "ambient_gpu_readback": "verified" if hardware_readback and gpu_uploads_ok else ("failed" if hardware_readback else "not_run_requires_real_renderer"),
		"safe_routes": safe_routes, "route_count": provider.routes.size(), "placement_failures": provider.placement_failures.duplicate(), "route_failures": provider.route_failures.duplicate()}

func _rig_indices(node: Node, result: Array[int]) -> void:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() > 0:
		var active: Material = node.get_active_material(0)
		if active is ShaderMaterial and active.shader == People.SHADER:
			# Deferred RenderDetail also installs five baked proxy meshes beneath
			# these pivots. They have vertex colors, not roster instance uniforms.
			var value: Variant = node.get_instance_shader_parameter("roster_override")
			result.append(int(value) if value is int or value is float else -1)
	for child in node.get_children():
		_rig_indices(child, result)

func _finish() -> void:
	deployment.passes = passes
	deployment.failures = failures
	var folder := ProjectSettings.globalize_path("res://../.work/model-quality-20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("npc-deployment-evidence.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(deployment, "\t"))
	print("[city_residents] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
