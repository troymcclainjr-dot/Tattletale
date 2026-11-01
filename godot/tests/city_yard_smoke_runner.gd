extends Node
## Imported-ground placement, solid-bin clearance and one-surface cell residency.
var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[city_yard] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node3D = get_tree().current_scene as Node3D
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene as Node3D
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes")
		_finish()
		return
	level.pause_exploring()
	if level.get("streaming") != null:
		level.streaming.set_process(false)
	await frames(2)
	var yards: Node3D = level.get("yard_details")
	check(yards != null, "yard provider registered before population")
	if yards == null:
		_finish()
		return
	for i in 1200:
		if int(yards.get_status().near_cells_missing) == 0:
			break
		await frames(1)
	var status: Dictionary = yards.get_status()
	check(int(status.cache_errors) == 0 and int(status.near_cells_missing) == 0, "cached nearby meshes finish loading without errors")
	var audit: Dictionary = status.get("audit", {})
	check(int(status.records) == 5414 and int(audit.get("litter", 0)) == 4619, "seeded full-map record and litter totals")
	check(int(audit.get("litter_cells", 0)) >= 150 and float(audit.get("litter_span_x_m", 0)) > 700 and float(audit.get("litter_span_z_m", 0)) > 500, "litter reaches the whole mapped neighborhood")
	check(int(audit.get("counts", {}).get("can", 0)) == 469 and int(audit.get("counts", {}).get("dumpster", 0)) == 51, "49 percent more household cans and service dumpsters survive metadata load")
	check(int(audit.get("hedge_rows", 0)) == 275 and float(audit.get("hedge_length_m", 0)) > 740 and float(audit.get("hedge_reserved_overlap_m2", 1)) == 0, "continuous porch-front hedges preserve every reserved path")
	var garden: Dictionary = level.level_data.get("construction_audit", {}).get("front_gardens", {})
	check(int(garden.get("homes_with_beds", 0)) >= 600 and float(garden.get("lawn_beds_m2", 0)) > 9000, "front beds cover residential blocks")
	check(float(garden.get("bed_path_overlap_m2", 1)) == 0.0 and float(garden.get("uncovered_approach_m2", 1)) == 0.0, "beds preserve complete paved stair approaches")
	var grounded := true
	var approach_clear := true
	var solid_count := 0
	var grounding_failures: Array[Dictionary] = []
	var sample_bin := Vector3.ZERO
	var space := yards.get_world_3d().direct_space_state
	for record in yards.records:
		var at: Vector3 = record.position
		# Cast locally to the ground; a porch roof overhead is not the support face.
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.06, at - Vector3.UP * 0.15, 1)
		var hit: Dictionary = space.intersect_ray(ray)
		grounded = grounded and not hit.is_empty()
		if not hit.is_empty():
			grounded = grounded and absf(float(hit.position.y) - at.y) < 0.02
		if hit.is_empty() or absf(float(hit.position.y) - at.y) >= 0.02:
			grounding_failures.append({"kind":record.kind,"building_id":record.building_id,"position":at,
				"hit_position":hit.get("position",Vector3.INF),"collider":str(hit.get("collider", "none"))})
		if float(record.radius) <= 0.0:
			continue
		solid_count += 1
		sample_bin = at
		for stair in level.level_data.get("porch_stairs", []):
			var a: Vector3 = level.vector(stair.landing)
			var b: Vector3 = level.vector(stair.approach)
			var nearest := Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			approach_clear = approach_clear and nearest.distance_to(Vector2(at.x, at.z)) > float(record.radius) + 0.78
	if not grounding_failures.is_empty():
		print("[city_yard] grounding_failures=", grounding_failures.size(), " first_records=", grounding_failures.slice(0, 16))
	check(grounded, "all 5414 anchors sit on imported ground within 2 cm")
	check(approach_clear and solid_count == 520, "solid bins leave every porch stair corridor open")
	check(not yards.is_clear(sample_bin, 0.3), "metadata reserves bins for population even before cells load")
	var one_surface := true
	var bins_only := true
	var total_bodies := 0
	for cell in yards._cells.values():
		if not is_instance_valid(cell.node):
			continue
		var meshes := 0
		var expected_bodies := 0
		for index in cell.indices:
			expected_bodies += int(float(yards.records[index].radius) > 0.0)
		for child in cell.node.get_children():
			if child is MeshInstance3D:
				meshes += 1
				one_surface = one_surface and child.mesh.get_surface_count() == 1
			elif child is PhysicsBody3D:
				bins_only = bins_only and child.get_meta("yard_bin", false) and child.collision_layer == 2
		one_surface = one_surface and meshes == 1
		bins_only = bins_only and cell.bodies.size() == expected_bodies
		total_bodies += cell.bodies.size()
	check(one_surface and int(status.active_batches) > 0, "one shared-material draw surface per resident cell")
	var geometry_verified := false
	for cell in yards._cells.values():
		if is_instance_valid(cell.instance):
			geometry_verified = _cached_geometry_matches(yards, cell)
			break
	check(geometry_verified, "serialized indexed cell preserves every authored position, normal and color")
	check(bins_only and total_bodies == int(status.active_bin_colliders) and int(status.litter_colliders) == 0, "only bins create physics; loose litter never creates a collider")
	var center: Vector3 = level.player.global_position
	var original_batches: int = status.active_batches
	var original_bodies: int = status.active_bin_colliders
	var builds_before: int = status.cell_builds
	yards.set_presence(center, 55, 180)
	check(int(yards.get_status().active_batches) == original_batches, "unchanged presence creates no duplicate cell batches")
	yards.set_presence(Vector3(100000, 0, 100000), 55, 180)
	await frames(2)
	status = yards.get_status()
	check(int(status.active_batches) == 0 and int(status.active_bin_colliders) == 0 and yards.get_child_count() == 0 and int(status.cached_cells) == 0, "far movement releases all resident geometry and bin physics")
	check(not yards.is_clear(sample_bin, 0.3), "unloaded bins remain reserved by immutable records")
	var reload_began := Time.get_ticks_usec()
	yards.set_presence(center, 55, 180)
	var reload_ms := float(Time.get_ticks_usec() - reload_began) / 1000.0
	for i in 1200:
		if int(yards.get_status().near_cells_missing) == 0:
			break
		await frames(1)
	var settle_ms := float(Time.get_ticks_usec() - reload_began) / 1000.0
	status = yards.get_status()
	check(int(status.cell_builds) == builds_before and int(status.async_loads) > 0, "travel reload uses background IO with zero geometry rebuilds")
	check(int(status.active_batches) == original_batches and int(status.active_bin_colliders) == original_bodies, "returning rebuilds exactly the original cells and colliders")
	print("[city_yard] reload_ms=", reload_ms, " async_settle_ms=", settle_ms, " max_activation_ms=", status.max_activation_ms, " max_attach_ms=", status.max_attach_ms, " startup_max_cell_build_ms=", status.max_cell_build_ms, " setup_ms=", status.setup_ms, " cells=", status.cells, " active_batches=", status.active_batches)
	if "--capture-yards" in OS.get_cmdline_user_args():
		await _capture_yards(level, yards)
	_finish()

func _cached_geometry_matches(yards: Node3D, cell: Dictionary) -> bool:
	var combined: ArrayMesh = cell.mesh
	var arrays := combined.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		return false
	var offset := 0
	for index in cell.indices:
		var record: Dictionary = yards.records[index]
		var source: ArrayMesh = yards._meshes[record.kind]
		var original := source.surface_get_arrays(0)
		var source_positions: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
		var source_colors: PackedColorArray = original[Mesh.ARRAY_COLOR]
		var pose := Transform3D(record.basis, record.position - cell.origin)
		var normal_basis := pose.basis.inverse().transposed()
		for i in source_positions.size():
			if offset >= indices.size():
				return false
			var mapped := indices[offset]
			if positions[mapped].distance_to(pose * source_positions[i]) > 0.0003:
				return false
			if normals[mapped].dot((normal_basis * source_normals[i]).normalized()) < 0.999:
				return false
			var color := colors[mapped]
			var source_color := source_colors[i]
			if absf(color.r - source_color.r) + absf(color.g - source_color.g) + absf(color.b - source_color.b) > 0.012:
				return false
			offset += 1
	return offset == indices.size()

func _capture_yards(level: Node3D, yards: Node3D) -> void:
	if not level.offscreen_validation or DisplayServer.get_name() == "headless":
		check(false, "yard captures require rendered --offscreen-validation mode")
		return
	var output := "res://../.work/content-pass/yard-captures"
	var args := OS.get_cmdline_user_args()
	var out_index := args.find("--outdir")
	if out_index >= 0 and out_index + 1 < args.size():
		output = args[out_index + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	level._ui.hide()
	level.player.first_person = true
	level.player.camera.fov = 58.0
	level.streaming.set_process(true)
	var stairs := {}
	for stair in level.level_data.get("porch_stairs", []):
		stairs[str(stair.building_id)] = stair
	var spawn: Vector3 = level.vector(level.level_data.spawn.position)
	var selected: Array[Vector3] = []
	for shot in 3:
		var best: Dictionary = {}
		var score := INF
		for record in yards.records:
			if not str(record.kind).begins_with("hedge") or not stairs.has(str(record.building_id)):
				continue
			var at: Vector3 = record.position
			var separated := true
			for previous in selected:
				separated = separated and at.distance_to(previous) > 70.0
			if separated and at.distance_squared_to(spawn) < score:
				best = record
				score = at.distance_squared_to(spawn)
		if best.is_empty():
			continue
		var at: Vector3 = best.position
		selected.append(at)
		var stair: Dictionary = stairs[str(best.building_id)]
		var normal: Vector3 = level.vector(stair.normal)
		var across := Vector3(-normal.z, 0, normal.x)
		var target: Vector3 = (at + level.vector(stair.approach)) * 0.5
		await _capture_view(level, target + normal * 7.5 + across * 2.0 + Vector3.UP * 3.0, target + Vector3.UP * 1.0, output, "garden-%d" % shot)
	for kind in ["can", "dumpster"]:
		var best: Dictionary = {}
		var score := INF
		for record in yards.records:
			if record.kind == kind and record.position.distance_squared_to(spawn) < score:
				best = record
				score = record.position.distance_squared_to(spawn)
		if best.is_empty():
			continue
		var at: Vector3 = best.position
		var normal := Vector3(sin(float(best.yaw)), 0, cos(float(best.yaw)))
		var across := Vector3(-normal.z, 0, normal.x)
		await _capture_view(level, at + normal * 4.5 + across * 2.0 + Vector3.UP * 2.4, at + Vector3.UP * 0.5, output, str(kind) + "-alley")

func _capture_view(level: Node3D, eye: Vector3, target: Vector3, output: String, filename: String) -> void:
	level._place_player(target, 0)
	level.capture_view(eye, target)
	level.streaming.refresh_now()
	for i in 600:
		await frames(1)
		if int(level.streaming.get_status().near_cells_missing) == 0 and int(level.yard_details.get_status().near_cells_missing) == 0:
			break
	await frames(30)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename + ".png"))
	check(error == OK, "offscreen yard capture " + filename)

func _finish() -> void:
	print("[city_yard] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
