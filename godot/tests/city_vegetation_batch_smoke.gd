extends SceneTree
## Focused merge/normal/cache checks without loading neighborhood physics.
const Vegetation := preload("res://scripts/city/city_vegetation.gd")
var passes := 0
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[vegetation_batch] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var city := Node3D.new()
	root.add_child(city)
	var vegetation := Vegetation.new()
	city.add_child(vegetation)
	var stats: Dictionary = vegetation.setup(city, city)
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Vegetation.DATA_PATH))
	var expected_kinds: Array = authored.templates.keys()
	if FileAccess.file_exists(Vegetation.POINTED_SHRUBS) and not "bush_spire" in expected_kinds:
		expected_kinds.append("bush_spire")
	check(int(stats.get("shared_meshes", 0)) == expected_kinds.size() * 2, "each published kind has exactly one shared near/far template pair")
	for kind in expected_kinds:
		var near_template: ArrayMesh = vegetation._meshes[str(kind) + "_near"]
		var far_template: ArrayMesh = vegetation._meshes[str(kind) + "_far"]
		var near_vertices: PackedVector3Array = near_template.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var far_vertices: PackedVector3Array = far_template.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(near_template.get_surface_count() == 1 and far_template.get_surface_count() == 1, str(kind) + " retains one surface per LOD")
		check(near_vertices.size() <= 1800 and far_vertices.size() <= 420 and far_vertices.size() < near_vertices.size(), str(kind) + " stays within explicit near/far geometry budgets")
	var cell := Vector2i.ZERO
	var plants := [
		{"kind": "tree0", "position": Vector3(12, 2, 18), "yaw": 0.63, "radius": 1.7, "height": 7.4, "trunk_radius": 0.31},
		{"kind": "bush1", "position": Vector3(25, 3, 22), "yaw": -0.41, "radius": 0.9, "height": 1.3, "trunk_radius": 0.0},
	]
	vegetation._cells = {cell: plants}
	var geometry: Dictionary = vegetation._cell_mesh(cell, "near", true)
	var mesh: ArrayMesh = geometry.mesh
	check(mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == vegetation._material, "mixed variants merge into one surface and shared material")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var wind: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	check(wind.size() == vertices.size() * 4, "merged vertices retain one tree anchor and sway weight each")
	var offset := 0
	var positions_match := true
	var normals_match := true
	var colors_match := true
	var anchors_match := true
	var bases_fixed := true
	var crowns_move := false
	var expected_normals := PackedVector3Array()
	var forward_normals_match := true
	var ratios_match := true
	var weights_match := true
	for plant in plants:
		var source: ArrayMesh = vegetation._meshes[str(plant.kind) + "_near"]
		var source_arrays := source.surface_get_arrays(0)
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]
		var source_colors: PackedColorArray = source_arrays[Mesh.ARRAY_COLOR]
		var pose := Transform3D(Basis(Vector3.UP, float(plant.yaw)).scaled(Vector3(float(plant.radius), float(plant.height), float(plant.radius))), plant.position)
		var normal_basis := pose.basis.inverse().transposed()
		for i in source_vertices.size():
			positions_match = positions_match and vertices[offset + i].distance_to(pose * source_vertices[i]) < 0.0001
			var expected := (normal_basis * source_normals[i]).normalized()
			expected_normals.append(expected)
			var lit_normal := normals[offset + i]
			var ratio: float = wind[(offset + i) * 4 + 2]
			if vegetation._wind_shader:
				forward_normals_match = forward_normals_match and lit_normal.dot((pose.basis * source_normals[i]).normalized()) > 0.99999
				ratios_match = ratios_match and absf(ratio - pow(float(plant.height) / float(plant.radius), 2.0)) < 0.00001
				lit_normal = (lit_normal * Vector3(ratio, 1.0, ratio)).normalized()
			normals_match = normals_match and lit_normal.dot(expected) > 0.99999
			colors_match = colors_match and colors[offset + i].is_equal_approx(source_colors[i])
			anchors_match = anchors_match and is_equal_approx(wind[(offset + i) * 4], plant.position.x) and is_equal_approx(wind[(offset + i) * 4 + 1], plant.position.z)
			var weight: float = wind[(offset + i) * 4 + 3]
			var upper := clampf((source_vertices[i].y - 0.25) / 0.65, 0.0, 1.0)
			var expected_weight := upper * upper if str(plant.kind).begins_with("tree") else 0.0
			weights_match = weights_match and absf(weight - expected_weight) < 0.000001
			if not str(plant.kind).begins_with("tree") or source_vertices[i].y <= 0.25:
				bases_fixed = bases_fixed and is_zero_approx(weight)
			elif source_vertices[i].y >= 0.9:
				crowns_move = crowns_move or weight > 0.9
		offset += source_vertices.size()
	check(offset == vertices.size() and positions_match, "every transformed plant triangle preserves its placement")
	check(normals_match, "nonuniform plant scaling preserves inverse-transpose lighting normals")
	check(forward_normals_match and ratios_match, "native forward normals and per-plant ratio support the exact shader correction")
	check(weights_match, "precomputed template wind weights preserve the authored height mask")
	check(colors_match, "all authored foliage and trunk vertex colors survive merging")
	check(anchors_match and bases_fixed and crowns_move, "tree crowns carry per-tree phase while trunks and bushes stay fixed")
	if vegetation._wind_shader:
		vegetation.set_wind_time(3.5)
		check(is_equal_approx(float(vegetation._material.get_shader_parameter("wind_time")), 3.5), "one shared wind clock controls all cells")
		vegetation.set_wind_enabled(false)
		check(is_zero_approx(float(vegetation._material.get_shader_parameter("wind_strength"))), "wind toggle leaves merged geometry and material in place")
		vegetation.set_wind_enabled(true)
	else:
		check(vegetation._material is StandardMaterial3D, "no-shader baseline uses the original StandardMaterial")
	var fallback := Vegetation.new()
	city.add_child(fallback)
	fallback._wind_shader = false
	fallback._material = StandardMaterial3D.new()
	fallback._cells = {cell: plants}
	fallback._meshes = vegetation._meshes
	fallback._template_normals = vegetation._template_normals
	fallback._template_wind_weights = vegetation._template_wind_weights
	fallback._template_wind_counts = vegetation._template_wind_counts
	var fallback_geometry: Dictionary = fallback._cell_mesh(cell, "near", true)
	var fallback_normals: PackedVector3Array = fallback_geometry.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var fallback_matches := fallback_normals.size() == expected_normals.size()
	for i in fallback_normals.size():
		fallback_matches = fallback_matches and fallback_normals[i].dot(expected_normals[i]) > 0.99999
	check(fallback_matches, "StandardMaterial fallback retains CPU inverse-transpose normals")
	var analytic_match := true
	for aspect in [0.2, 1.0, 4.0, 9.0]:
		for yaw in [-2.5, 0.0, 0.63, 2.2]:
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1.7, 1.7 * aspect, 1.7))
			for direction in [Vector3(1, 2, 3).normalized(), Vector3(-3, 0.01, 1).normalized(), Vector3.UP]:
				var forward: Vector3 = (basis * direction).normalized()
				var corrected := (forward * Vector3(aspect * aspect, 1.0, aspect * aspect)).normalized()
				var inverse: Vector3 = (basis.inverse().transposed() * direction).normalized()
				analytic_match = analytic_match and corrected.distance_to(inverse) < 0.000001
	check(analytic_match, "GPU correction agrees with inverse-transpose across yaw and squat/tall aspect ratios")
	vegetation.set_presence(Vector3(145, 0, 0), 55, 400)
	var far_mesh: ArrayMesh = vegetation._cell_meshes[cell].mesh
	var builds_before: int = vegetation.get_stats().cell_mesh_builds
	check(not bool(vegetation._active[cell].physics), "far cell begins without trunk physics")
	vegetation.set_presence(Vector3(130, 0, 0), 55, 400)
	stats = vegetation.get_stats()
	check(vegetation._cell_meshes[cell].mesh == far_mesh and int(stats.cell_mesh_builds) == builds_before, "physics-only presence transition reuses merged geometry")
	check(int(stats.trunk_colliders) == 1 and int(stats.draw_batches) == 1, "one cell draw preserves nearby tree collision")
	var node: Node3D = vegetation._active[cell].node
	check(node.get_node("Vegetation_far").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "far geometry keeps shadow-free LOD")
	var physical_cell := node
	var trunk_rid: RID = (node.get_node("TreeTrunk_0") as StaticBody3D).get_rid()
	var visual_node := node.get_node("Vegetation_far")
	vegetation.set_presence(Vector3.ZERO, 55, 400)
	node = vegetation._active[cell].node
	check(node.get_node("Vegetation_near").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "near geometry retains tree shadows")
	check(node == physical_cell and (node.get_node("TreeTrunk_0") as StaticBody3D).get_rid() == trunk_rid,
		"visual-only LOD change preserves the cell and live collision RID")
	check(node.get_node("Vegetation_near") == visual_node,
		"visual-only LOD change swaps the resource on the existing draw instance")
	check(vegetation._cell_meshes[cell].mesh == mesh, "returning to near LOD restores the original merged resource")
	builds_before = int(vegetation.get_stats().cell_mesh_builds)
	for repeat in 3:
		vegetation.set_presence(Vector3(145, 0, 0), 55, 400)
		vegetation.set_presence(Vector3.ZERO, 55, 400)
	check(int(vegetation.get_stats().cell_mesh_builds) == builds_before,
		"repeated near/far threshold crossings do not rebuild cached triangles")
	check((vegetation._active[cell].node.get_node("TreeTrunk_0") as StaticBody3D).get_rid() == trunk_rid,
		"repeated visual threshold crossings preserve collision registration")
	vegetation.set_presence(Vector3(180, 0, 0), 55, 400)
	check(int(vegetation.get_stats().trunk_colliders) == 0, "physics range exit still removes trunk bodies")
	vegetation.set_presence(Vector3.ZERO, 55, 400)
	check(int(vegetation.get_stats().trunk_colliders) == 1, "physics range reentry still restores trunk bodies")
	var without_bushes: Dictionary = vegetation._cell_mesh(cell, "far", false)
	check(int(without_bushes.plants) == 1, "tree-only signature excludes the bush")
	vegetation._cell_mesh(cell, "far", true)
	check(vegetation._cell_mesh(cell, "far", false).mesh == without_bushes.mesh,
		"bush visibility variants retain independent reusable resources")
	stats = vegetation.get_stats()
	var expected_vertices := 0
	for active_mesh in vegetation._cell_meshes.values():
		expected_vertices += int(active_mesh.vertices)
	for historical_mesh in vegetation._mesh_history.values():
		expected_vertices += int(historical_mesh.vertices)
	check(int(stats.cached_vertices) == expected_vertices and int(stats.estimated_raw_mesh_bytes) == expected_vertices * Vegetation.RAW_VERTEX_BYTES,
		"memory accounting includes active and historical resources once")
	vegetation.set_presence(Vector3(2000, 0, 2000), 55, 400)
	stats = vegetation.get_stats()
	check(int(stats.loaded_cells) == 0 and int(stats.cached_mesh_variants) == 0 and int(stats.historical_raw_mesh_bytes) == 0,
		"horizon unloading releases nodes and all historical LOD variants")
	vegetation._history_byte_budget = int(geometry.vertices) * Vegetation.RAW_VERTEX_BYTES
	vegetation._cell_mesh(cell, "near", true)
	vegetation._cell_mesh(cell, "far", true)
	vegetation._cell_mesh(cell, "far", false)
	stats = vegetation.get_stats()
	check(int(stats.history_evictions) > 0 and int(stats.historical_raw_mesh_bytes) <= int(stats.history_byte_budget),
		"historical LRU evicts old variants within its byte budget")
	check(vegetation._cell_meshes[cell].mesh != null, "history eviction never discards the current mesh")
	vegetation.set_presence(Vector3(2000, 0, 2000), 55, 400)
	vegetation._legacy_cache = true
	vegetation._cell_mesh(cell, "near", true)
	vegetation._cell_mesh(cell, "far", true)
	builds_before = int(vegetation.get_stats().cell_mesh_builds)
	vegetation._cell_mesh(cell, "near", true)
	check(int(vegetation.get_stats().cell_mesh_builds) == builds_before + 1 and vegetation._mesh_history.is_empty(),
		"legacy cache baseline retains single-variant rebuilding")
	vegetation.set_presence(Vector3(2000, 0, 2000), 55, 400)
	vegetation._legacy_cache = false
	vegetation._history_byte_budget = Vegetation.HISTORY_BYTE_BUDGET
	vegetation._cells.clear()
	for x in 3:
		var planted: Dictionary = plants[0].duplicate()
		planted.position = Vector3(float(x) * Vegetation.CELL + 12.0, 2, 18)
		vegetation._cells[Vector2i(x, 0)] = [planted]
		vegetation._cell_mesh(Vector2i(x, 0), "far", false)
	vegetation.set_presence(Vector3(300, 0, 0), 55, 400)
	var old_visual: MeshInstance3D = vegetation._active[Vector2i(2, 0)].node.get_node("Vegetation_far")
	builds_before = int(vegetation.get_stats().cell_mesh_builds)
	vegetation.set_presence(Vector3.ZERO, 200, 400)
	stats = vegetation.get_stats()
	check(int(stats.cell_mesh_builds) == builds_before + 1 and int(stats.pending_visual_cells) == 2,
		"one refresh constructs at most one uncached visual variant")
	check(str(vegetation._active[Vector2i.ZERO].lod) == "near", "the nearest pending cell receives the construction budget first")
	check(old_visual == vegetation._active[Vector2i(2, 0)].node.get_node("Vegetation_far") and old_visual.mesh != null,
		"deferred replacement retains its old draw instance and geometry")
	check(int(stats.trunk_colliders) == 3, "nearby trunk collision is not deferred with visual construction")
	await vegetation.prepare_presence(Vector3.ZERO, 200, 400)
	stats = vegetation.get_stats()
	check(int(stats.pending_visual_cells) == 0 and int(stats.max_refresh_mesh_builds) <= 1,
		"loading preparation drains pending visuals without exceeding the refresh budget")
	builds_before = int(stats.cell_mesh_builds)
	vegetation.set_presence(Vector3(300, 0, 0), 55, 400)
	check(int(vegetation.get_stats().cell_mesh_builds) == builds_before and int(vegetation.get_stats().pending_visual_cells) == 0,
		"cached transitions bypass the construction budget for every ready cell")
	print("[vegetation_batch] %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
