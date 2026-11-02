extends Node
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Shared templates merge into one material surface per resident spatial cell.
## The level's streamer calls set_presence; no per-tree processing or physics ticks.
const DATA_PATH := "res://assets/data/pen_lucy_vegetation.json"
const SHRUB_GROWTH := "res://assets/data/pen_lucy_shrub_growth.json"
const POINTED_SHRUBS := "res://assets/data/pen_lucy_pointed_shrubs.json"
const ALIVE_WORLD := "res://assets/data/pen_lucy_alive_world.json"
const WIND_SHADER := preload("res://assets/materials/city_vegetation_wind.gdshader")
const CELL := 48.0
const RAW_VERTEX_BYTES := 56
const HISTORY_BYTE_BUDGET := 32 * 1024 * 1024
const MAX_NEW_MESHES_PER_REFRESH := 1
## Paced (ordinary streaming cadence) presence retires at most this many horizon
## cells per call; their nodes are destroyed at frame end. set_presence stays complete.
const PACED_HORIZON_UNLOADS := 16
## Loading-screen preparation may run several one-build passes in one frame.
const PREPARE_FRAME_BUDGET_USEC := 12000
var _cells := {}
var _active := {}
var _meshes := {}
var _template_normals := {}
var _template_vertices := {}
var _template_colors := {}
var _template_wind_weights := {}
var _template_wind_counts := {}
# Per template: [vertices, normals, colors, one-column FORMAT_RF sway weights].
var _templates := {}
var _cell_meshes := {}
var _mesh_history := {}
var _mesh_history_order: Array[Vector3i] = []
# Cell -> number of historical variants, so distant cells skip four history probes.
var _history_cells := {}
var _history_vertices := 0
var _history_byte_budget := HISTORY_BYTE_BUDGET
var _legacy_cache := false
var _history_evictions := 0
var _cell_mesh_builds := 0
var _cell_mesh_cache_hits := 0
var _pending_visual_cells := 0
var _deferred_horizon_unloads := 0
var _last_refresh_mesh_builds := 0
var _max_refresh_mesh_builds := 0
var _counts := {}
var _material: Material
var _wind_enabled := true
var _wind_shader := true
var _wind_time := 0.0
# Opt-in phase attribution, enabled by the streamer's profiler. Microseconds spent
# in the latest presence call; nested inside the streamer's provider timing.
# "unload" excludes node destruction, which the engine defers to frame end.
var profile_presence := false
var presence_profile: Dictionary = {}

func setup(_level: Node3D, city: Node3D) -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {"enabled": false, "reason": "vegetation metadata absent"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "invalid vegetation metadata"}
	name = "CityVegetation"
	_legacy_cache = "--legacy-vegetation-cache" in OS.get_cmdline_args() or "--legacy-vegetation-cache" in OS.get_cmdline_user_args()
	_wind_shader = not ("--no-city-wind-shader" in OS.get_cmdline_args() or "--no-city-wind-shader" in OS.get_cmdline_user_args())
	_wind_enabled = _wind_shader and not ("--no-city-wind" in OS.get_cmdline_args() or "--no-city-wind" in OS.get_cmdline_user_args())
	if _wind_shader:
		var wind_material := ShaderMaterial.new()
		wind_material.shader = WIND_SHADER
		wind_material.set_shader_parameter("wind_strength", 1.0 if _wind_enabled else 0.0)
		wind_material.set_shader_parameter("wind_time", _wind_time)
		_material = wind_material
	else:
		var standard := StandardMaterial3D.new()
		standard.vertex_color_use_as_albedo = true
		standard.vertex_color_is_srgb = true
		standard.roughness = 0.88
		standard.metallic_specular = 0.21
		_material = standard
	if FileAccess.file_exists(POINTED_SHRUBS):
		var pointed = JSON.parse_string(FileAccess.get_file_as_string(POINTED_SHRUBS))
		if pointed is Dictionary and int(pointed.get("version", 0)) == 1:
			if not data.templates.has("bush_spire"):
				data.templates["bush_spire"] = {"near": {}, "far": {}}
			data.plants.append_array(pointed.get("plants", []))
	if FileAccess.file_exists(ALIVE_WORLD):
		var alive = JSON.parse_string(FileAccess.get_file_as_string(ALIVE_WORLD))
		if alive is Dictionary and int(alive.get("version", 0)) == 1:
			data.plants.append_array(alive.get("plants", []))
	for kind in data.templates:
		for lod in ["near", "far"]:
			var key: String = str(kind) + "_" + str(lod)
			# One authored library supplies the same crowns to near and far batches.
			# Keep the spire fallback for older metadata without its template.
			var template: Dictionary = data.templates[kind][lod]
			var arrays := _template_arrays(template) if template.has("vertices") else _pointed_shrub_arrays(lod == "near")
			_meshes[key] = _mesh_from_arrays(arrays)
			# Retain the source arrays: reading them back from the ArrayMesh is a
			# renderer readback, which merging previously repeated for every plant.
			_template_normals[key] = arrays[Mesh.ARRAY_NORMAL]
			_template_vertices[key] = arrays[Mesh.ARRAY_VERTEX]
			_template_colors[key] = arrays[Mesh.ARRAY_COLOR]
			var vertices: PackedVector3Array = _template_vertices[key]
			var weights := PackedFloat32Array()
			weights.resize(vertices.size())
			var moving_count := 0
			if str(kind).begins_with("tree"):
				for i in vertices.size():
					var upper := clampf((vertices[i].y - 0.25) / 0.65, 0.0, 1.0)
					weights[i] = upper * upper * (0.5 if lod == "far" else 1.0)
					moving_count += int(weights[i] > 0.0)
			_template_wind_weights[key] = weights
			_template_wind_counts[key] = moving_count
	var growth: Dictionary = {}
	if FileAccess.file_exists(SHRUB_GROWTH):
		var authored = JSON.parse_string(FileAccess.get_file_as_string(SHRUB_GROWTH))
		if authored is Dictionary and str(authored.get("source_sha256", "")) == FileAccess.get_sha256(DATA_PATH):
			for shrub in authored.get("plants", []):
				growth[int(shrub.index)] = shrub
	var civic_removed := 0
	var source_index := -1
	for source_record in data.plants:
		source_index += 1
		var record: Dictionary = source_record.duplicate()
		if str(record.kind) in ["tree4", "tree5"]:
			# Survey tree centers lie on a regular grid: use high hash bits so
			# the two conifer silhouettes do not collapse to the same parity.
			var conifer_seed := (roundi(float(record.position[0]) * 10.0) * 73856093) ^ (roundi(-float(record.position[2]) * 10.0) * 19349663)
			record.kind = "tree%d" % (4 + ((conifer_seed >> 8) & 1))
		if str(record.kind).begins_with("bush") and str(record.kind) != "bush_spire" and not bool(record.get("authored_size", false)):
			record.height = clampf(float(record.height) * 1.8, 1.25, 1.85)
			if growth.has(source_index):
				record.radius = float(growth[source_index].radius)
				record.height = float(growth[source_index].height)
		if CivicClearance.record_removed(_level, record, float(record.get("radius", 0.5))):
			civic_removed += 1
			continue
		var coordinates: Array = record.position
		var point := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
		if not _cells.has(cell):
			_cells[cell] = []
		var plant: Dictionary = record.duplicate()
		plant.position = point
		_cells[cell].append(plant)
	_counts = data.counts.duplicate()
	_counts.civic_removed = civic_removed
	_counts.trees = 0
	_counts.bushes = 0
	_counts.pointed_shrubs = 0
	for cell_plants in _cells.values():
		for plant in cell_plants:
			_counts.trees += int(str(plant.kind).begins_with("tree"))
			_counts.bushes += int(str(plant.kind).begins_with("bush"))
			_counts.pointed_shrubs += int(str(plant.kind) == "bush_spire")
	_counts.enabled = true
	_counts.shared_meshes = _meshes.size()
	_counts.spatial_cells = _cells.size()
	# Replace the old monolithic crowns and their expensive triangle collision.
	# Root may also skip Trees while creating imported city collision shapes.
	for source in city.find_children("Trees", "MeshInstance3D", true, false):
		source.free()
	return get_stats()

func clear_playground_shrubs(playgrounds: Array[Dictionary]) -> int:
	# Furniture chooses its final terrain-supported footprint after vegetation
	# loads. Remove only decorative crowns touching those pads, once at setup.
	var removed := 0
	var pointed_removed := 0
	for cell in _cells:
		var retained: Array = []
		for plant in _cells[cell]:
			var overlaps := false
			if str(plant.kind).begins_with("bush"):
				var point := Vector2(plant.position.x, plant.position.z)
				for playground in playgrounds:
					var center := Vector2(playground.position.x, playground.position.z)
					var half_size: Vector2 = playground.size * 0.5
					var closest := point.clamp(center - half_size, center + half_size)
					# Procedural crowns stay inside their authored radius; the
					# extra margin also keeps their wind motion clear of equipment.
					if point.distance_to(closest) < float(plant.radius) + 0.4:
						overlaps = true
						break
			if overlaps:
				removed += 1
				pointed_removed += int(str(plant.kind) == "bush_spire")
			else:
				retained.append(plant)
		if retained.size() == _cells[cell].size():
			continue
		_cells[cell] = retained
		_release_cell_meshes(cell)
		# Update visible geometry without replacing tree bodies. Empty/pending
		# cells will build normally on their next streaming refresh.
		var active: Dictionary = _active.get(cell, {})
		if not active.is_empty() and str(active.lod) in ["near", "far"]:
			_set_cell_geometry(active.node, _cell_mesh(cell, active.lod, active.bushes), active.lod)
	_counts.bushes = int(_counts.get("bushes", 0)) - removed
	_counts.pointed_shrubs = int(_counts.get("pointed_shrubs", 0)) - pointed_removed
	_counts.playground_removed = int(_counts.get("playground_removed", 0)) + removed
	return removed

func set_wind_time(seconds: float) -> void:
	# The level's simulation clock supplies this value. Holding it freezes wind
	# during menu pause; TIME would continue while SceneTree is paused.
	_wind_time = seconds
	if _material is ShaderMaterial and _wind_enabled:
		(_material as ShaderMaterial).set_shader_parameter("wind_time", _wind_time)

func set_wind_enabled(enabled: bool) -> void:
	_wind_enabled = enabled and _wind_shader
	if _material is ShaderMaterial:
		var wind_material := _material as ShaderMaterial
		wind_material.set_shader_parameter("wind_strength", 1.0 if _wind_enabled else 0.0)
		if _wind_enabled:
			wind_material.set_shader_parameter("wind_time", _wind_time)

func _template_arrays(data: Dictionary) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var positions: Array = data.vertices
	var directions: Array = data.normals
	var rgba: Array = data.colors
	for i in range(0, positions.size(), 3):
		vertices.append(Vector3(float(positions[i]), float(positions[i + 1]), float(positions[i + 2])))
		normals.append(Vector3(float(directions[i]), float(directions[i + 1]), float(directions[i + 2])))
	for i in range(0, rgba.size(), 4):
		colors.append(Color(float(rgba[i]), float(rgba[i + 1]), float(rgba[i + 2]), float(rgba[i + 3])))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays

func _build_mesh(data: Dictionary) -> ArrayMesh:
	return _mesh_from_arrays(_template_arrays(data))

func _mesh_from_arrays(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh

func set_capture_presence(center: Vector3, render_center: Vector3, near_radius := 55.0, far_radius := 180.0) -> void:
	set_presence(center, near_radius, far_radius, render_center)

func set_presence(center: Vector3, near_radius: float, far_radius: float, render_center := Vector3.INF) -> void:
	_update_presence(center, near_radius, far_radius, render_center, -1)

func set_paced_presence(center: Vector3, near_radius: float, far_radius: float, render_center := Vector3.INF) -> void:
	# Ordinary streaming cadence: identical residency and collision decisions, but
	# a relocation's horizon exits are retired over several calls.
	_update_presence(center, near_radius, far_radius, render_center, PACED_HORIZON_UNLOADS)

func _update_presence(center: Vector3, near_radius: float, far_radius: float, render_center: Vector3, unload_budget: int) -> void:
	# Large tree silhouettes remain on the horizon. Short bushes need only the
	# street-level vicinity; cylinder physics is ready before a walker reaches it.
	var profiling := profile_presence
	if profiling:
		presence_profile = {"scan": 0, "unload": 0, "mesh_arrays": 0, "mesh_upload": 0, "physics": 0}
	var scan_began := Time.get_ticks_usec() if profiling else 0
	var horizon := maxf(far_radius, 400.0)
	var physics_limit := maxf(near_radius, 90.0)
	var camera := render_center.is_finite()
	var focus := Vector2(center.x, center.z)
	var eye := Vector2(render_center.x, render_center.z) if camera else focus
	# Parallel arrays: the full-city scan allocates nothing per unchanged cell.
	var candidate_cells: Array[Vector2i] = []
	var candidate_distances := PackedFloat64Array()
	var candidate_flags := PackedByteArray()
	_deferred_horizon_unloads = 0
	for cell: Vector2i in _cells:
		var x0 := float(cell.x) * CELL
		var z0 := float(cell.y) * CELL
		var distance := Vector2(clampf(focus.x, x0, x0 + CELL), clampf(focus.y, z0, z0 + CELL)).distance_to(focus)
		var physics_distance := distance
		if camera:
			distance = minf(distance, Vector2(clampf(eye.x, x0, x0 + CELL), clampf(eye.y, z0, z0 + CELL)).distance_to(eye))
		var previous = _active.get(cell)
		var resident: bool = previous != null
		# Different enter/leave thresholds prevent reallocating batches and shapes
		# when the player jogs back and forth across a cell's distance boundary.
		if distance > horizon + (20.0 if resident else 0.0):
			if resident:
				if unload_budget == 0:
					# Still beyond the horizon next call; keep it whole until then.
					_deferred_horizon_unloads += 1
					continue
				unload_budget -= 1
				var unload_began := Time.get_ticks_usec() if profiling else 0
				previous.node.queue_free()
				_active.erase(cell)
				# Historical variants are useful only while their cell is resident.
				_release_cell_meshes(cell)
				if profiling:
					presence_profile.unload += Time.get_ticks_usec() - unload_began
			elif _cell_meshes.has(cell) or _history_cells.has(cell):
				_release_cell_meshes(cell)
			continue
		var near := distance <= near_radius + (10.0 if resident and previous.lod == "near" else 0.0)
		var physics := physics_distance <= physics_limit + (10.0 if resident and previous.physics else 0.0)
		var bushes := distance <= 125.0 + (10.0 if resident and previous.bushes else 0.0)
		# Pending cells carry lod "", so they always remain candidates.
		if resident and previous.lod == ("near" if near else "far") and previous.physics == physics and previous.bushes == bushes:
			continue
		candidate_cells.append(cell)
		candidate_distances.append(distance)
		candidate_flags.append(int(near) | (int(physics) << 1) | (int(bushes) << 2))
	if profiling:
		presence_profile.scan = Time.get_ticks_usec() - scan_began - int(presence_profile.unload)
	var builds_before := _cell_mesh_builds
	_pending_visual_cells = 0
	var count := candidate_cells.size()
	var handled := PackedByteArray()
	handled.resize(count)
	handled.fill(0)
	# Ready variants never spend the construction budget. Apply them first so a
	# later build's history eviction cannot discard a variant this pass reuses.
	for i in count:
		var flags := candidate_flags[i]
		if _variant_ready(candidate_cells[i], "near" if flags & 1 else "far", bool(flags & 4)):
			_apply_cell(candidate_cells[i], flags)
			handled[i] = 1
	# Then construct uncached variants nearest-first within the per-call budget.
	for _build in MAX_NEW_MESHES_PER_REFRESH:
		var nearest := -1
		for i in count:
			if handled[i] == 0 and (nearest < 0 or candidate_distances[i] < candidate_distances[nearest]):
				nearest = i
		if nearest < 0:
			break
		_apply_cell(candidate_cells[nearest], candidate_flags[nearest])
		handled[nearest] = 1
	for i in count:
		if handled[i] == 1:
			continue
		_pending_visual_cells += 1
		# Keep the old visual until its replacement is ready, but never defer
		# nearby collision merely because a far/near mesh needs construction.
		var cell := candidate_cells[i]
		var physics := bool(candidate_flags[i] & 2)
		var previous = _active.get(cell)
		if previous == null:
			if physics:
				var waiting := _new_cell_root(cell, "pending")
				_set_cell_physics(waiting, cell, true)
				_active[cell] = {"node": waiting, "signature": "", "lod": "", "physics": true, "bushes": false}
		elif bool(previous.physics) != physics:
			_set_cell_physics(previous.node, cell, physics)
			previous.physics = physics
			previous.signature = "%s_%s_%s" % [previous.lod, previous.physics, previous.bushes]
	_last_refresh_mesh_builds = _cell_mesh_builds - builds_before
	_max_refresh_mesh_builds = maxi(_max_refresh_mesh_builds, _last_refresh_mesh_builds)

func _variant_ready(cell: Vector2i, lod: String, bushes: bool) -> bool:
	var visual_signature := "%s_%s" % [lod, bushes]
	return str(_cell_meshes.get(cell, {}).get("signature", "")) == visual_signature or _mesh_history.has(_history_key(cell, visual_signature))

func _apply_cell(cell: Vector2i, flags: int) -> void:
	var lod := "near" if flags & 1 else "far"
	var physics := bool(flags & 2)
	var bushes := bool(flags & 4)
	var previous = _active.get(cell)
	var cell_node: Node3D = previous.node if previous != null else _new_cell_root(cell, lod)
	cell_node.name = "Plants_%d_%d_%s" % [cell.x, cell.y, lod]
	_set_cell_geometry(cell_node, _cell_mesh(cell, lod, bushes), lod)
	if previous == null or bool(previous.physics) != physics:
		_set_cell_physics(cell_node, cell, physics)
	_active[cell] = {"node": cell_node, "signature": "%s_%s_%s" % [lod, physics, bushes], "lod": lod,
		"physics": physics, "bushes": bushes}

func prepare_presence(center: Vector3, near_radius: float, far_radius: float) -> void:
	# Await under the loading screen so the first playable frame has its horizon.
	# Every presence pass keeps the one-mesh construction budget; several bounded
	# passes may share one loading frame.
	set_presence(center, near_radius, far_radius)
	while _pending_visual_cells > 0:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var frame_began := Time.get_ticks_usec()
		set_presence(center, near_radius, far_radius)
		while _pending_visual_cells > 0 and Time.get_ticks_usec() - frame_began < PREPARE_FRAME_BUDGET_USEC:
			set_presence(center, near_radius, far_radius)

func is_trunk_clear(point: Vector3, radius: float) -> bool:
	# Placement uses surveyed plant records, including unloaded distant cells.
	# The largest generated trunk is 0.42m; leave room for that plus a margin.
	var reach := radius + 0.5
	for x in range(floori((point.x - reach) / CELL), floori((point.x + reach) / CELL) + 1):
		for z in range(floori((point.z - reach) / CELL), floori((point.z + reach) / CELL) + 1):
			for plant in _cells.get(Vector2i(x, z), []):
				var trunk_radius: float = plant.trunk_radius
				if trunk_radius <= 0.0:
					continue
				var at: Vector3 = plant.position
				var height: float = plant.height
				if point.y + radius < at.y - height * 0.015 or point.y - radius > at.y + height * 0.575:
					continue
				if Vector2(point.x - at.x, point.z - at.z).length() < radius + trunk_radius + 0.05:
					return false
	return true

func _template(key: String) -> Array:
	if _templates.has(key):
		return _templates[key]
	# Setup supplies CPU arrays. Fixtures that inject only shared meshes read the
	# missing arrays back once per template here, never once per plant.
	var arrays: Array = []
	if not (_template_vertices.has(key) and _template_normals.has(key) and _template_colors.has(key)):
		var shared: ArrayMesh = _meshes[key]
		arrays = shared.surface_get_arrays(0)
	var vertices: PackedVector3Array = _template_vertices[key] if _template_vertices.has(key) else arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = _template_normals[key] if _template_normals.has(key) else arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = _template_colors[key] if _template_colors.has(key) else arrays[Mesh.ARRAY_COLOR]
	var weights: PackedFloat32Array = _template_wind_weights[key]
	var column: Image = null
	if not weights.is_empty():
		column = Image.create_from_data(1, weights.size(), false, Image.FORMAT_RF, weights.to_byte_array())
	var template := [vertices, normals, colors, column]
	_templates[key] = template
	return template

func _cell_mesh(cell: Vector2i, lod: String, bushes: bool) -> Dictionary:
	var signature := "%s_%s" % [lod, bushes]
	var cached: Dictionary = _cell_meshes.get(cell, {})
	if str(cached.get("signature", "")) == signature:
		_cell_mesh_cache_hits += 1
		return cached
	var history_key := _history_key(cell, signature)
	if _mesh_history.has(history_key):
		var restored: Dictionary = _mesh_history[history_key]
		_erase_history(history_key)
		_remember_mesh(cell, cached)
		_cell_meshes[cell] = restored
		_cell_mesh_cache_hits += 1
		return restored
	var began := Time.get_ticks_usec() if profile_presence else 0
	var vertex_count := 0
	for plant in _cells[cell]:
		var kind: String = plant.kind
		if kind.begins_with("tree") or bushes:
			var template_vertices: PackedVector3Array = _template(kind + "_" + lod)[0]
			vertex_count += template_vertices.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# One row of four floats per vertex: anchor x, anchor z, normal ratio, sway
	# weight. FORMAT_RF rows have exactly the CUSTOM0 RGBA_FLOAT byte layout, and
	# native fills/copies replace four GDScript writes per merged vertex.
	var wind_rows: Image = Image.create_empty(4, vertex_count, false, Image.FORMAT_RF) if vertex_count > 0 else null
	var vertex_offset := 0
	var origin := Vector3(float(cell.x) * CELL, 0, float(cell.y) * CELL)
	var plant_count := 0
	var wind_vertices := 0
	for plant in _cells[cell]:
		var kind: String = plant.kind
		if not kind.begins_with("tree") and not bushes:
			continue
		var radius: float = plant.radius
		var height: float = plant.height
		var key := kind + "_" + lod
		var template := _template(key)
		var source_vertices: PackedVector3Array = template[0]
		var source_normals: PackedVector3Array = template[1]
		var source_colors: PackedColorArray = template[2]
		var pose := Transform3D(Basis(Vector3.UP, float(plant.yaw)).scaled(Vector3(radius, height, radius)), plant.position - origin)
		vertices.append_array(pose * source_vertices)
		# Like the former SurfaceTool merge, apply the forward basis without
		# normalizing. Yaw commutes with (r,h,r), so multiplying its normal's XZ by
		# (h/r)^2 restores inverse-transpose direction in the shader. StandardMaterial
		# keeps the CPU correction; octahedral vertex encoding normalizes either form.
		var normal_basis := pose.basis if _wind_shader else pose.basis.inverse().transposed()
		normals.append_array(Transform3D(normal_basis, Vector3.ZERO) * source_normals)
		colors.append_array(source_colors)
		var count := source_vertices.size()
		if count > 0:
			var anchor: Vector3 = plant.position - origin
			var normal_ratio := (height / radius) * (height / radius) if _wind_shader else 1.0
			wind_rows.fill_rect(Rect2i(0, vertex_offset, 1, count), Color(anchor.x, 0.0, 0.0))
			wind_rows.fill_rect(Rect2i(1, vertex_offset, 1, count), Color(anchor.z, 0.0, 0.0))
			wind_rows.fill_rect(Rect2i(2, vertex_offset, 1, count), Color(normal_ratio, 0.0, 0.0))
			wind_rows.blit_rect(template[3], Rect2i(0, 0, 1, count), Vector2i(3, vertex_offset))
		wind_vertices += int(_template_wind_counts[key])
		vertex_offset += count
		plant_count += 1
	var upload_began := Time.get_ticks_usec() if profile_presence else 0
	var mesh: ArrayMesh
	if plant_count > 0 and vertex_count > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = wind_rows.get_data().to_float32_array()
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, _material)
	if profile_presence:
		presence_profile.mesh_arrays = int(presence_profile.get("mesh_arrays", 0)) + upload_began - began
		presence_profile.mesh_upload = int(presence_profile.get("mesh_upload", 0)) + Time.get_ticks_usec() - upload_began
	# Keep the active variant plus a bounded LRU of previously used signatures.
	# Returning across a LOD/bush threshold reuses immutable merged triangles.
	_remember_mesh(cell, cached)
	cached = {"signature": signature, "mesh": mesh, "plants": plant_count, "vertices": vertex_count, "wind_vertices": wind_vertices}
	_cell_meshes[cell] = cached
	_cell_mesh_builds += 1
	return cached

func _history_key(cell: Vector2i, signature: String) -> Vector3i:
	var variant := (2 if signature.begins_with("far_") else 0) + (1 if signature.ends_with("true") else 0)
	return Vector3i(cell.x, cell.y, variant)

func _release_cell_meshes(cell: Vector2i) -> void:
	_cell_meshes.erase(cell)
	if _history_cells.has(cell):
		for variant in 4:
			_erase_history(Vector3i(cell.x, cell.y, variant))

func _erase_history(key: Vector3i) -> void:
	if not _mesh_history.has(key):
		return
	_history_vertices -= int(_mesh_history[key].vertices)
	_mesh_history.erase(key)
	_mesh_history_order.erase(key)
	var cell := Vector2i(key.x, key.y)
	var remaining := int(_history_cells.get(cell, 0)) - 1
	if remaining > 0:
		_history_cells[cell] = remaining
	else:
		_history_cells.erase(cell)

func _remember_mesh(cell: Vector2i, geometry: Dictionary) -> void:
	if _legacy_cache or geometry.is_empty():
		return
	var vertices: int = geometry.vertices
	# A single unusually dense cell must not displace the whole cache.
	if vertices * RAW_VERTEX_BYTES > _history_byte_budget:
		return
	var key := _history_key(cell, str(geometry.signature))
	_erase_history(key)
	while (_history_vertices + vertices) * RAW_VERTEX_BYTES > _history_byte_budget and not _mesh_history_order.is_empty():
		_erase_history(_mesh_history_order[0])
		_history_evictions += 1
	_mesh_history[key] = geometry
	_mesh_history_order.append(key)
	_history_vertices += vertices
	_history_cells[cell] = int(_history_cells.get(cell, 0)) + 1

func _build_cell(cell: Vector2i, lod: String, physics: bool, bushes: bool) -> Node3D:
	var root := _new_cell_root(cell, lod)
	_set_cell_physics(root, cell, physics)
	_set_cell_geometry(root, _cell_mesh(cell, lod, bushes), lod)
	return root

func _new_cell_root(cell: Vector2i, lod: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Plants_%d_%d_%s" % [cell.x, cell.y, lod]
	root.position = Vector3(float(cell.x) * CELL, 0, float(cell.y) * CELL)
	add_child(root)
	return root

func _set_cell_physics(root: Node3D, cell: Vector2i, physics: bool) -> void:
	if bool(root.get_meta("physics", false)) == physics:
		return
	var began := Time.get_ticks_usec() if profile_presence else 0
	for child in root.get_children():
		if child is StaticBody3D:
			child.collision_layer = 0
			root.remove_child(child)
			child.queue_free()
	var trunk_count := 0
	for plant in _cells[cell]:
		var kind: String = plant.kind
		var is_tree := kind.begins_with("tree")
		var height: float = plant.height
		if physics and is_tree:
			var body := StaticBody3D.new()
			body.name = "TreeTrunk_%d" % trunk_count
			body.collision_layer = 2
			body.collision_mask = 0
			body.position = plant.position - root.position + Vector3.UP * height * 0.28
			var shape := CylinderShape3D.new()
			shape.radius = float(plant.trunk_radius)
			shape.height = height * 0.59
			var collider := CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			root.add_child(body)
			trunk_count += 1
	root.set_meta("trunks", trunk_count)
	root.set_meta("physics", physics)
	if profile_presence:
		presence_profile.physics = int(presence_profile.get("physics", 0)) + Time.get_ticks_usec() - began

func _set_cell_geometry(root: Node3D, geometry: Dictionary, lod: String) -> void:
	var batch: MeshInstance3D
	for child in root.get_children():
		if child is MeshInstance3D:
			batch = child
			break
	if geometry.mesh != null:
		if batch == null:
			batch = MeshInstance3D.new()
			root.add_child(batch)
		batch.name = "Vegetation_" + lod
		batch.mesh = geometry.mesh
		batch.extra_cull_margin = 0.1
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == "near" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif batch != null:
		root.remove_child(batch)
		batch.queue_free()
	root.set_meta("plants", int(geometry.plants))
	root.set_meta("batches", 1 if geometry.mesh != null else 0)

func get_stats() -> Dictionary:
	var result := _counts.duplicate()
	result.loaded_cells = _active.size()
	result.loaded_plants = 0
	result.trunk_colliders = 0
	result.draw_batches = 0
	result.cached_cell_meshes = _cell_meshes.size()
	result.cached_mesh_variants = _cell_meshes.size() + _mesh_history.size()
	result.historical_mesh_variants = _mesh_history.size()
	result.historical_raw_mesh_bytes = _history_vertices * RAW_VERTEX_BYTES
	result.history_byte_budget = _history_byte_budget
	result.history_evictions = _history_evictions
	result.legacy_vegetation_cache = _legacy_cache
	result.cached_vertices = 0
	result.wind_vertices = 0
	result.active_vertices = 0
	result.active_wind_vertices = 0
	result.wind_enabled = _wind_enabled
	result.wind_shader = _wind_shader
	result.wind_time = _wind_time
	result.cell_mesh_builds = _cell_mesh_builds
	result.cell_mesh_cache_hits = _cell_mesh_cache_hits
	result.pending_visual_cells = _pending_visual_cells
	result.deferred_horizon_unloads = _deferred_horizon_unloads
	result.last_refresh_mesh_builds = _last_refresh_mesh_builds
	result.max_refresh_mesh_builds = _max_refresh_mesh_builds
	result.presence_profile = presence_profile.duplicate() if profile_presence else {}
	for geometry in _cell_meshes.values():
		result.cached_vertices += int(geometry.vertices)
		result.wind_vertices += int(geometry.wind_vertices)
		result.active_vertices += int(geometry.vertices)
		result.active_wind_vertices += int(geometry.wind_vertices)
	for geometry in _mesh_history.values():
		result.cached_vertices += int(geometry.vertices)
		result.wind_vertices += int(geometry.wind_vertices)
	# Uncompressed position+normal+color+custom0 arrays; excludes engine/GPU overhead.
	result.estimated_raw_mesh_bytes = int(result.cached_vertices) * RAW_VERTEX_BYTES
	for entry in _active.values():
		result.loaded_plants += int(entry.node.get_meta("plants", 0))
		result.trunk_colliders += int(entry.node.get_meta("trunks", 0))
		result.draw_batches += int(entry.node.get_meta("batches", 0))
	return result

func _pointed_shrub_mesh(near: bool) -> ArrayMesh:
	return _mesh_from_arrays(_pointed_shrub_arrays(near))

func _pointed_shrub_arrays(near: bool) -> Array:
	# A narrow evergreen crown with overlapping irregular tiers and a pointed
	# leader. Shared by every lawn, merged into the existing vegetation cells.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 12 if near else 7
	var profile: Array[Vector2] = [Vector2(-0.04, 0.64), Vector2(0.14, 0.83), Vector2(0.31, 0.94), Vector2(0.42, 0.77), Vector2(0.56, 0.72), Vector2(0.69, 0.48), Vector2(0.81, 0.35), Vector2(0.91, 0.17), Vector2(1.0, 0.0)]
	if not near:
		profile = [profile[0], profile[2], profile[4], profile[6], profile[8]]
	for tier in range(profile.size() - 1):
		for segment in segments:
			var corners: Array[Vector3] = []
			for sample in [Vector2i(tier, segment), Vector2i(tier, segment + 1), Vector2i(tier + 1, segment + 1), Vector2i(tier + 1, segment)]:
				var ring := profile[sample.x]
				var angle := TAU * float(sample.y % segments) / float(segments)
				var radius := ring.y * (0.94 + 0.04 * sin(angle * 3.0 + ring.x * 9.0))
				corners.append(Vector3(cos(angle) * radius, ring.x, sin(angle) * radius))
			var shade := 0.90 + 0.11 * sin(float(segment * 3 + tier)) + profile[tier].x * 0.12
			var color := Color("345339") * Color(shade, shade, shade, 1.0)
			for tri in [[0, 2, 1], [0, 3, 2]]:
				var normal := (corners[tri[1]] - corners[tri[0]]).cross(corners[tri[2]] - corners[tri[0]])
				if normal.length_squared() < 0.0000001:
					continue
				normal = normal.normalized()
				# Godot's outward faces use clockwise winding; retain the
				# outward analytic normal while reversing the cross-product order.
				for index in [tri[0], tri[2], tri[1]]:
					surface.set_normal(normal)
					surface.set_color(color)
					surface.add_vertex(corners[index])
	return surface.commit_to_arrays()
