extends SceneTree
## Streaming-polish vegetation fixture. Direct array merging must reproduce the
## pre-polish SurfaceTool merge, the allocation-free scan must make the pre-polish
## residency/collision decisions, and paced horizon retirement must stay bounded.
## Timing lines are informational: headless uses the dummy renderer, so the old
## per-plant template readback is far cheaper here than on a real GPU.
const Vegetation := preload("res://scripts/city/city_vegetation.gd")
var passes := 0
var fails := 0

class ReferenceVegetation extends "res://scripts/city/city_vegetation.gd":
	# Pre-polish set_presence decisions, kept verbatim for parity checks.
	func set_presence(center: Vector3, near_radius: float, far_radius: float, render_center := Vector3.INF) -> void:
		var horizon := maxf(far_radius, 400.0)
		var candidates: Array[Dictionary] = []
		for cell in _cells:
			var previous: Dictionary = _active.get(cell, {})
			var closest := Vector2(clampf(center.x, float(cell.x) * CELL, (float(cell.x) + 1.0) * CELL), clampf(center.z, float(cell.y) * CELL, (float(cell.y) + 1.0) * CELL))
			var distance := closest.distance_to(Vector2(center.x, center.z))
			var physics_distance := distance
			if render_center.is_finite():
				var camera_closest := Vector2(clampf(render_center.x, float(cell.x) * CELL, (float(cell.x) + 1.0) * CELL), clampf(render_center.z, float(cell.y) * CELL, (float(cell.y) + 1.0) * CELL))
				distance = minf(distance, camera_closest.distance_to(Vector2(render_center.x, render_center.z)))
			if distance > horizon + (20.0 if not previous.is_empty() else 0.0):
				if _active.has(cell):
					_active[cell].node.queue_free()
					_active.erase(cell)
				_cell_meshes.erase(cell)
				for variant in 4:
					_erase_history(Vector3i(cell.x, cell.y, variant))
				continue
			var near_limit := near_radius + (10.0 if str(previous.get("lod", "")) == "near" else 0.0)
			var lod := "near" if distance <= near_limit else "far"
			var physics := physics_distance <= maxf(near_radius, 90.0) + (10.0 if bool(previous.get("physics", false)) else 0.0)
			var bushes := distance <= 125.0 + (10.0 if bool(previous.get("bushes", false)) else 0.0)
			var signature := "%s_%s_%s" % [lod, physics, bushes]
			if _active.has(cell) and _active[cell].signature == signature:
				continue
			candidates.append({"cell": cell, "distance": distance, "lod": lod, "physics": physics,
				"bushes": bushes, "signature": signature})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
		var builds_before := _cell_mesh_builds
		_pending_visual_cells = 0
		for desired in candidates:
			var cell: Vector2i = desired.cell
			var previous: Dictionary = _active.get(cell, {})
			var visual_signature := "%s_%s" % [desired.lod, desired.bushes]
			var cached := str(_cell_meshes.get(cell, {}).get("signature", "")) == visual_signature or _mesh_history.has(_history_key(cell, visual_signature))
			var can_build := cached or _cell_mesh_builds - builds_before < MAX_NEW_MESHES_PER_REFRESH
			if not can_build:
				_pending_visual_cells += 1
				if previous.is_empty() and bool(desired.physics):
					var waiting := _new_cell_root(cell, "pending")
					_set_cell_physics(waiting, cell, true)
					_active[cell] = {"node": waiting, "signature": "", "lod": "", "physics": true, "bushes": false}
				elif not previous.is_empty() and bool(previous.physics) != bool(desired.physics):
					_set_cell_physics(previous.node, cell, bool(desired.physics))
					previous.physics = desired.physics
					previous.signature = "%s_%s_%s" % [previous.lod, previous.physics, previous.bushes]
				continue
			var cell_node: Node3D = previous.node if not previous.is_empty() else _new_cell_root(cell, desired.lod)
			cell_node.name = "Plants_%d_%d_%s" % [cell.x, cell.y, desired.lod]
			_set_cell_geometry(cell_node, _cell_mesh(cell, desired.lod, desired.bushes), desired.lod)
			if previous.is_empty() or bool(previous.physics) != bool(desired.physics):
				_set_cell_physics(cell_node, cell, desired.physics)
			_active[cell] = {"node": cell_node, "signature": desired.signature, "lod": desired.lod,
				"physics": desired.physics, "bushes": desired.bushes}
		_last_refresh_mesh_builds = _cell_mesh_builds - builds_before
		_max_refresh_mesh_builds = maxi(_max_refresh_mesh_builds, _last_refresh_mesh_builds)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[streaming_polish_vegetation] %s %s" % ["PASS" if ok else "FAIL", label])

func report(label: String, value) -> void:
	print("[streaming_polish_vegetation] TIMING %s %s" % [label, str(value)])

func _reference_mesh(vegetation: Node, cell: Vector2i, lod: String, bushes: bool) -> ArrayMesh:
	# The pre-polish merge: SurfaceTool.append_from per plant (a template readback
	# each time) and four scripted CUSTOM0 writes per merged vertex.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0
	for plant in vegetation._cells[cell]:
		var kind: String = plant.kind
		if kind.begins_with("tree") or bushes:
			var counted: PackedFloat32Array = vegetation._template_wind_weights[kind + "_" + lod]
			vertex_count += counted.size()
	var corrected_normals := PackedVector3Array()
	if not vegetation._wind_shader:
		corrected_normals.resize(vertex_count)
	var wind_data := PackedFloat32Array()
	wind_data.resize(vertex_count * 4)
	var vertex_offset := 0
	var origin := Vector3(float(cell.x) * Vegetation.CELL, 0, float(cell.y) * Vegetation.CELL)
	var plant_count := 0
	for plant in vegetation._cells[cell]:
		var kind: String = plant.kind
		if not kind.begins_with("tree") and not bushes:
			continue
		var radius: float = plant.radius
		var height: float = plant.height
		var pose := Transform3D(Basis(Vector3.UP, float(plant.yaw)).scaled(Vector3(radius, height, radius)), plant.position - origin)
		var key := kind + "_" + lod
		surface.append_from(vegetation._meshes[key], 0, pose)
		if not vegetation._wind_shader:
			var normal_basis := pose.basis.inverse().transposed()
			var source_normals: PackedVector3Array = vegetation._template_normals[key]
			for i in source_normals.size():
				corrected_normals[vertex_offset + i] = (normal_basis * source_normals[i]).normalized()
		var weights: PackedFloat32Array = vegetation._template_wind_weights[key]
		var anchor: Vector3 = plant.position - origin
		var normal_ratio := (height / radius) * (height / radius) if vegetation._wind_shader else 1.0
		for i in weights.size():
			var at := (vertex_offset + i) * 4
			wind_data[at] = anchor.x
			wind_data[at + 1] = anchor.z
			wind_data[at + 2] = normal_ratio
			wind_data[at + 3] = weights[i]
		vertex_offset += weights.size()
		plant_count += 1
	if plant_count == 0:
		return null
	var arrays := surface.commit_to_arrays()
	if not vegetation._wind_shader:
		arrays[Mesh.ARRAY_NORMAL] = corrected_normals
	arrays[Mesh.ARRAY_CUSTOM0] = wind_data
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, vegetation._material)
	return mesh

func _unindexed(arrays: Array) -> bool:
	var indices = arrays[Mesh.ARRAY_INDEX]
	return indices == null or indices.size() == 0

func _decoded_template_colors(vegetation: Node, cell: Vector2i, lod: String, bushes: bool) -> PackedColorArray:
	var colors := PackedColorArray()
	for plant in vegetation._cells[cell]:
		var kind: String = plant.kind
		if kind.begins_with("tree") or bushes:
			var shared: ArrayMesh = vegetation._meshes[kind + "_" + lod]
			colors.append_array(shared.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	return colors

func _compare_merge(vegetation: Node, cell: Vector2i, lod: String, bushes: bool, label: String) -> void:
	vegetation._release_cell_meshes(cell)
	var geometry: Dictionary = vegetation._cell_mesh(cell, lod, bushes)
	var expected := _reference_mesh(vegetation, cell, lod, bushes)
	var actual: ArrayMesh = geometry.mesh
	check(actual != null and expected != null, label + ": both merges produce geometry")
	if actual == null or expected == null:
		return
	var a := actual.surface_get_arrays(0)
	var e := expected.surface_get_arrays(0)
	var a_vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var e_vertices: PackedVector3Array = e[Mesh.ARRAY_VERTEX]
	var a_wind: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var e_wind: PackedFloat32Array = e[Mesh.ARRAY_CUSTOM0]
	var a_normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var e_normals: PackedVector3Array = e[Mesh.ARRAY_NORMAL]
	var a_colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
	check(actual.get_surface_count() == 1 and actual.surface_get_material(0) == vegetation._material, label + ": one surface with the shared material")
	check(actual.surface_get_format(0) == expected.surface_get_format(0) and _unindexed(a) and _unindexed(e),
		label + ": identical vertex format with no index array")
	check(a_vertices.size() == e_vertices.size() and a_vertices == e_vertices, label + ": merged positions are bit-identical")
	check(a_wind.size() == a_vertices.size() * 4 and a_wind == e_wind, label + ": CUSTOM0 anchors, ratios and sway weights are bit-identical")
	var min_dot := 1.0
	for i in mini(a_normals.size(), e_normals.size()):
		min_dot = minf(min_dot, a_normals[i].dot(e_normals[i]))
	check(a_normals.size() == e_normals.size() and min_dot > 0.99999, label + ": lighting normals match within encoding precision (min dot %.7f)" % min_dot)
	var template_colors := _decoded_template_colors(vegetation, cell, lod, bushes)
	var colors_match := a_colors.size() == template_colors.size()
	for i in mini(a_colors.size(), template_colors.size()):
		colors_match = colors_match and a_colors[i].is_equal_approx(template_colors[i])
	check(colors_match, label + ": authored vertex colors survive exactly as the shared templates store them")
	check(actual.get_aabb().is_equal_approx(expected.get_aabb()), label + ": bounds unchanged")

func _synthetic_plants(vegetation: Node, cell: Vector2i, repeats: int) -> Array:
	var kinds: Array[String] = []
	for key in vegetation._meshes:
		if str(key).ends_with("_near"):
			kinds.append(str(key).trim_suffix("_near"))
	kinds.sort()
	var origin := Vector3(float(cell.x) * Vegetation.CELL, 0, float(cell.y) * Vegetation.CELL)
	var plants: Array = []
	var index := 0
	for repeat in repeats:
		for kind in kinds:
			var tree: bool = kind.begins_with("tree")
			plants.append({"kind": kind, "position": origin + Vector3(2.0 + fmod(float(index) * 7.3, 44.0), 1.5 + 0.1 * float(index % 5), 3.0 + fmod(float(index) * 11.9, 42.0)),
				"yaw": -2.9 + 0.37 * float(index), "radius": (1.4 + 0.15 * float(repeat % 3)) if tree else (0.6 + 0.1 * float(repeat % 3)),
				"height": (6.0 + 2.5 * float(repeat % 3)) if tree else (1.2 + 0.4 * float(repeat % 3)), "trunk_radius": 0.2 if tree else 0.0})
			index += 1
	return plants

func _state(vegetation: Node) -> Dictionary:
	var state := {}
	for cell in vegetation._active:
		var entry: Dictionary = vegetation._active[cell]
		state[cell] = "%s|%s|%s|%s|%d" % [entry.lod, entry.physics, entry.bushes, entry.signature, int(entry.node.get_meta("trunks", 0))]
	return state

func _city_box(vegetation: Node) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for cell in vegetation._cells:
		low = Vector2(minf(low.x, float(cell.x)), minf(low.y, float(cell.y)))
		high = Vector2(maxf(high.x, float(cell.x) + 1.0), maxf(high.y, float(cell.y) + 1.0))
	return Rect2(low * Vegetation.CELL, (high - low) * Vegetation.CELL)

func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) if not sorted.is_empty() else 0.0

func _run() -> void:
	var city := Node3D.new()
	root.add_child(city)
	var vegetation := Vegetation.new()
	city.add_child(vegetation)
	var stats: Dictionary = vegetation.setup(city, city)
	check(bool(stats.get("enabled", false)), "production vegetation metadata loads")
	# Setup keeps CPU source arrays; positions match what the shared mesh stores.
	var retained := not vegetation._meshes.is_empty()
	for key in vegetation._meshes:
		var shared: ArrayMesh = vegetation._meshes[key]
		var decoded := shared.surface_get_arrays(0)
		var decoded_vertices: PackedVector3Array = decoded[Mesh.ARRAY_VERTEX]
		var cpu_vertices: PackedVector3Array = vegetation._template_vertices.get(key, PackedVector3Array())
		var cpu_colors: PackedColorArray = vegetation._template_colors.get(key, PackedColorArray())
		retained = retained and vegetation._template_normals.has(key) and cpu_vertices == decoded_vertices and cpu_colors.size() == decoded_vertices.size()
	check(retained, "every shared template retains CPU positions, normals and colors without readback")

	# Merge equivalence across every published kind, both LODs and both bush masks.
	var cell := Vector2i(3, -2)
	var plants := _synthetic_plants(vegetation, cell, 3)
	vegetation._cells = {cell: plants}
	for lod in ["near", "far"]:
		for bushes in [true, false]:
			_compare_merge(vegetation, cell, lod, bushes, "wind %s bushes=%s" % [lod, bushes])
	var counted: Dictionary = vegetation._cell_mesh(cell, "near", true)
	var expected_vertices := 0
	var expected_wind := 0
	for plant in plants:
		var weights: PackedFloat32Array = vegetation._template_wind_weights[str(plant.kind) + "_near"]
		expected_vertices += weights.size()
		expected_wind += int(vegetation._template_wind_counts[str(plant.kind) + "_near"])
	check(int(counted.plants) == plants.size() and int(counted.vertices) == expected_vertices and int(counted.wind_vertices) == expected_wind,
		"merged plant, vertex and moving-vertex accounting is unchanged")
	# StandardMaterial fallback: CPU inverse-transpose normals, ratio lane 1.0.
	var fallback := Vegetation.new()
	city.add_child(fallback)
	fallback._wind_shader = false
	fallback._material = StandardMaterial3D.new()
	fallback._cells = {cell: plants}
	fallback._meshes = vegetation._meshes
	fallback._template_normals = vegetation._template_normals
	fallback._template_wind_weights = vegetation._template_wind_weights
	fallback._template_wind_counts = vegetation._template_wind_counts
	for lod in ["near", "far"]:
		_compare_merge(fallback, cell, lod, true, "fallback %s" % lod)
	# Injected fixtures without CPU arrays read each template back once, not per plant.
	var used := {}
	for plant in plants:
		used[str(plant.kind) + "_near"] = true
		used[str(plant.kind) + "_far"] = true
	check(fallback._templates.size() == used.size(), "lazy template cache holds one entry per used template (%d plants, %d templates)" % [plants.size(), fallback._templates.size()])
	check(int(vegetation._cell_mesh(cell, "far", false).plants) == plants.filter(func(p): return str(p.kind).begins_with("tree")).size(),
		"tree-only variant still excludes every bush")
	# Informational: one dense near cell, old merge versus direct merge.
	var old_times := []
	var new_times := []
	for repeat in 7:
		var began := Time.get_ticks_usec()
		_reference_mesh(vegetation, cell, "near", true)
		old_times.append(Time.get_ticks_usec() - began)
		vegetation._release_cell_meshes(cell)
		began = Time.get_ticks_usec()
		vegetation._cell_mesh(cell, "near", true)
		new_times.append(Time.get_ticks_usec() - began)
	report("dense_near_cell_%d_plants_%d_vertices median_usec old/new" % [plants.size(), expected_vertices], "%d/%d" % [int(_median(old_times)), int(_median(new_times))])
	fallback.queue_free()
	vegetation.queue_free()
	await process_frame

	# Decision parity on the production cell layout: new scan versus verbatim old scan.
	var fresh := Vegetation.new()
	city.add_child(fresh)
	fresh.setup(city, city)
	var reference := ReferenceVegetation.new()
	city.add_child(reference)
	reference.setup(city, city)
	# Remove history-eviction order as a variable; eviction is covered elsewhere.
	fresh._history_byte_budget = 1 << 30
	reference._history_byte_budget = 1 << 30
	check(fresh._cells.size() == reference._cells.size() and fresh._cells.size() > 100, "both instances load the production cell layout (%d cells)" % fresh._cells.size())
	var box := _city_box(fresh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var at := box.get_center()
	var parity := true
	var first_mismatch := ""
	var steps := 0
	var builds_seen := 0
	for step in 90:
		if step % 15 == 0:
			at = Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		else:
			at += Vector2(rng.randf_range(-35.0, 35.0), rng.randf_range(-35.0, 35.0))
		var center := Vector3(at.x, 0.0, at.y)
		# Keep the camera eye out of plant cells: two distance-zero candidates
		# would make the old unstable sort's build choice arbitrary.
		var eye := Vector3.INF
		if step % 9 == 4:
			for attempt in 16:
				var trial := center + Vector3(rng.randf_range(-260.0, 260.0), 6.0, rng.randf_range(-260.0, 260.0))
				if not fresh._cells.has(Vector2i(floori(trial.x / Vegetation.CELL), floori(trial.z / Vegetation.CELL))):
					eye = trial
					break
		if eye.is_finite():
			fresh.set_capture_presence(center, eye, 55.0, 180.0)
			reference.set_capture_presence(center, eye, 55.0, 180.0)
		else:
			fresh.set_presence(center, 55.0, 180.0)
			reference.set_presence(center, 55.0, 180.0)
		steps += 1
		builds_seen += int(fresh._last_refresh_mesh_builds)
		var same: bool = _state(fresh) == _state(reference) and fresh._pending_visual_cells == reference._pending_visual_cells \
			and fresh._last_refresh_mesh_builds == reference._last_refresh_mesh_builds and fresh._cell_meshes.size() == reference._cell_meshes.size() \
			and fresh._mesh_history.size() == reference._mesh_history.size()
		if not same and parity:
			first_mismatch = "step %d at %s: pending %d/%d builds %d/%d active %d/%d" % [step, str(center), fresh._pending_visual_cells, reference._pending_visual_cells,
				fresh._last_refresh_mesh_builds, reference._last_refresh_mesh_builds, fresh._active.size(), reference._active.size()]
		parity = parity and same
		if step % 10 == 9:
			await process_frame
	check(parity, "scan rewrite makes the pre-polish LOD, bush, collision, pending and build decisions over %d moves/teleports/captures %s" % [steps, first_mismatch])
	check(builds_seen > 0 and int(fresh.get_stats().max_refresh_mesh_builds) <= 1, "parity walk exercised construction without exceeding one build per call")
	check(int(fresh.get_stats().trunk_colliders) == int(reference.get_stats().trunk_colliders) and int(fresh.get_stats().loaded_cells) == int(reference.get_stats().loaded_cells),
		"trunk collider and resident cell totals match the pre-polish scan")

	# Converge both at one corner, then compare paced versus complete horizon exits.
	var corner_a := Vector3(box.position.x + 60.0, 0.0, box.position.y + 60.0)
	var corner_b := Vector3(box.end.x - 60.0, 0.0, box.end.y - 60.0)
	var guard := 0
	fresh.set_presence(corner_a, 55.0, 180.0)
	reference.set_presence(corner_a, 55.0, 180.0)
	while (fresh._pending_visual_cells > 0 or reference._pending_visual_cells > 0) and guard < 2000:
		fresh.set_presence(corner_a, 55.0, 180.0)
		reference.set_presence(corner_a, 55.0, 180.0)
		guard += 1
	await process_frame
	check(fresh._pending_visual_cells == 0 and _state(fresh) == _state(reference), "corner horizon converges identically before the relocation")
	# Informational: pure scan cost once nothing changes (production layout).
	var old_scan := []
	var new_scan := []
	for repeat in 21:
		var began := Time.get_ticks_usec()
		reference.set_presence(corner_a, 55.0, 180.0)
		old_scan.append(Time.get_ticks_usec() - began)
		began = Time.get_ticks_usec()
		fresh.set_presence(corner_a, 55.0, 180.0)
		new_scan.append(Time.get_ticks_usec() - began)
	report("settled_scan_%d_cells median_usec old/new" % fresh._cells.size(), "%d/%d" % [int(_median(old_scan)), int(_median(new_scan))])
	var resident_at_a: Array = fresh._active.keys()
	var leaving := 0
	for resident in resident_at_a:
		var x0 := float(resident.x) * Vegetation.CELL
		var z0 := float(resident.y) * Vegetation.CELL
		var closest := Vector2(clampf(corner_b.x, x0, x0 + Vegetation.CELL), clampf(corner_b.z, z0, z0 + Vegetation.CELL))
		leaving += int(closest.distance_to(Vector2(corner_b.x, corner_b.z)) > 420.0)
	check(leaving > Vegetation.PACED_HORIZON_UNLOADS, "relocation leaves more horizon cells than one paced call retires (%d)" % leaving)
	fresh.profile_presence = true
	fresh.set_paced_presence(corner_b, 55.0, 180.0)
	reference.set_presence(corner_b, 55.0, 180.0)
	var profile: Dictionary = fresh.get_stats().presence_profile
	check(profile.has("scan") and profile.has("unload") and profile.has("mesh_arrays") and profile.has("mesh_upload") and profile.has("physics")
		and int(profile.scan) >= 0 and int(profile.unload) >= 0 and int(profile.physics) >= 0, "opt-in presence phases are reported in microseconds")
	var deferred: int = fresh.get_stats().deferred_horizon_unloads
	check(deferred == leaving - Vegetation.PACED_HORIZON_UNLOADS, "paced call retires exactly %d horizon cells and reports the rest (%d deferred)" % [Vegetation.PACED_HORIZON_UNLOADS, deferred])
	var in_range_match := true
	var reference_state := _state(reference)
	var fresh_state := _state(fresh)
	for key in reference_state:
		in_range_match = in_range_match and fresh_state.get(key, "") == reference_state[key]
	check(in_range_match and fresh._pending_visual_cells == reference._pending_visual_cells and fresh._last_refresh_mesh_builds == reference._last_refresh_mesh_builds,
		"pacing leaves every in-range LOD, collider and build decision identical")
	var still_whole := true
	for key in fresh_state:
		if reference_state.has(key):
			continue
		still_whole = still_whole and is_instance_valid(fresh._active[key].node) and fresh._cell_meshes.has(key)
	check(still_whole, "deferred horizon cells keep their node and merged mesh until retired")
	var calls := 1
	while int(fresh.get_stats().deferred_horizon_unloads) > 0 and calls < 64:
		fresh.set_paced_presence(corner_b, 55.0, 180.0)
		reference.set_presence(corner_b, 55.0, 180.0)
		calls += 1
	check(calls == ceili(float(leaving) / float(Vegetation.PACED_HORIZON_UNLOADS)) and _state(fresh) == _state(reference),
		"paced retirement converges in %d calls to the complete result" % calls)
	check(int(fresh.get_stats().cached_mesh_variants) == int(reference.get_stats().cached_mesh_variants),
		"retired cells release their current and historical meshes")
	fresh.profile_presence = false
	check(fresh.get_stats().presence_profile.is_empty(), "presence phases are absent when profiling is off")
	# Loading preparation drains with several one-build passes per frame.
	var loader := Vegetation.new()
	city.add_child(loader)
	loader.setup(city, city)
	var frame_before := Engine.get_process_frames()
	await loader.prepare_presence(corner_b, 55.0, 180.0)
	var loader_stats: Dictionary = loader.get_stats()
	check(int(loader_stats.pending_visual_cells) == 0 and int(loader_stats.max_refresh_mesh_builds) <= 1 and int(loader_stats.cell_mesh_builds) > 1,
		"prepare_presence drains %d builds without exceeding one per pass" % int(loader_stats.cell_mesh_builds))
	report("prepare_presence builds/frames", "%d/%d" % [int(loader_stats.cell_mesh_builds), Engine.get_process_frames() - frame_before])
	print("[streaming_polish_vegetation] %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
