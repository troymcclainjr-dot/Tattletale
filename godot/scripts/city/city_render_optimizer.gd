extends Node
## Static render batching only: original meshes and their physics children remain.
## Call after collision creation, before neighborhood-specific material overrides.

const CACHE_VERSION := 6
const CHUNK_SIZE := 150.0
const MODEL_PATH := "res://assets/models/city/pen_lucy.glb"
const CACHE_DIR := "user://city_render_cache"
const CACHE_PATH := CACHE_DIR + "/pen_lucy_batches.scn"
const STAMP_PATH := CACHE_DIR + "/pen_lucy_batches.json"
var level: Node3D
var city: Node3D
var batch_root: Node3D
var quality := "balanced"
var enabled := true
var _sources: Array[MeshInstance3D] = []
var _all_meshes: Array[MeshInstance3D] = []
var _stats: Dictionary = {}

func setup(owner_level: Node3D, city_root: Node3D) -> void:
	level = owner_level
	city = city_root
	name = "CityRenderOptimizer"
	var began := Time.get_ticks_msec()
	var collision_shapes := city.find_children("*", "CollisionShape3D", true, false).size()
	enabled = not OS.get_cmdline_user_args().has("--no-city-optimization")
	_collect(city)
	_sources.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D): return str(a.get_path()) < str(b.get_path()))
	var surfaces := 0
	var source_surfaces := 0
	var source_triangles := 0
	var material_ids: Dictionary = {}
	for mesh_node in _all_meshes:
		surfaces += mesh_node.mesh.get_surface_count()
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface)
			if material:
				material_ids[material.get_instance_id()] = true
	for mesh_node in _sources:
		source_surfaces += mesh_node.mesh.get_surface_count()
		source_triangles += _triangle_count(mesh_node.mesh)
	_stats = {"enabled": enabled, "quality": quality, "source_meshes": _all_meshes.size(),
		"source_surfaces": surfaces, "shared_materials": material_ids.size(),
		"building_meshes": _sources.size(), "building_surfaces": source_surfaces,
		"building_triangles": source_triangles, "batch_meshes": 0, "batch_surfaces": 0,
		"batch_triangles": 0, "cache_hit": false, "cache_saved": false, "setup_ms": 0,
		"visible_surface_budget": surfaces, "collision_shapes_before": collision_shapes,
		"collision_shapes_after": collision_shapes, "collision_nodes_preserved": true}
	if not enabled or _sources.is_empty():
		_stats.setup_ms = Time.get_ticks_msec() - began
		return
	var signature := _cache_signature(source_surfaces, source_triangles)
	if not OS.get_cmdline_user_args().has("--rebuild-city-render-cache"):
		_load_cache(signature)
	if batch_root == null:
		_build_batches()
		if batch_root and int(batch_root.get_meta("triangle_count", -1)) == source_triangles:
			_save_cache(signature)
	if batch_root == null or int(batch_root.get_meta("triangle_count", -1)) != source_triangles:
		push_warning("City render batching failed its geometry check; preserving original visuals")
		if batch_root:
			batch_root.queue_free()
		batch_root = null
		enabled = false
		_stats.enabled = false
		_stats.setup_ms = Time.get_ticks_msec() - began
		return
	city.add_child(batch_root)
	# Layers affect rendering only; collision children stay registered and active.
	for source in _sources:
		source.set_meta("city_original_render_layers", source.layers)
		source.layers = 0
	_stats.batch_meshes = batch_root.get_child_count()
	_stats.batch_surfaces = int(batch_root.get_meta("surface_count", 0))
	_stats.batch_triangles = int(batch_root.get_meta("triangle_count", 0))
	_stats.visible_surface_budget = surfaces - source_surfaces + int(_stats.batch_surfaces)
	_stats.collision_shapes_after = city.find_children("*", "CollisionShape3D", true, false).size()
	_stats.collision_nodes_preserved = int(_stats.collision_shapes_after) == collision_shapes
	set_quality(quality)
	_stats.setup_ms = Time.get_ticks_msec() - began
	print("[city_render] " + JSON.stringify(_stats))

func _collect(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_node: MeshInstance3D = node
		_all_meshes.append(mesh_node)
		var label := str(node.name)
		if label.begins_with("Row_") or label.begins_with("Bldg_"):
			var compatible := mesh_node.mesh is ArrayMesh and mesh_node.skin == null and mesh_node.material_overlay == null
			if compatible:
				compatible = (mesh_node.mesh as ArrayMesh).get_blend_shape_count() == 0
			for surface in mesh_node.mesh.get_surface_count():
				if mesh_node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
					compatible = false
			if compatible:
				_sources.append(mesh_node)
	for child in node.get_children():
		if not child is CollisionObject3D:
			_collect(child)

func _triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh:
			var array_mesh := mesh as ArrayMesh
			var indices := array_mesh.surface_get_array_index_len(surface)
			count += (indices if indices > 0 else array_mesh.surface_get_array_len(surface)) / 3
	return count

func _cache_signature(surfaces: int, triangles: int) -> String:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	var bytes := file.get_length() if file else 0
	return "%s|%s|%s|%s|%s|%s|%s" % [CACHE_VERSION, Engine.get_version_info().string,
		FileAccess.get_modified_time(MODEL_PATH), FileAccess.get_modified_time(MODEL_PATH + ".import"),
		bytes, surfaces, triangles]

func _load_cache(signature: String) -> void:
	if not FileAccess.file_exists(STAMP_PATH) or not ResourceLoader.exists(CACHE_PATH):
		return
	var stamp = JSON.parse_string(FileAccess.get_file_as_string(STAMP_PATH))
	if not stamp is Dictionary or str(stamp.get("signature", "")) != signature:
		return
	var packed = ResourceLoader.load(CACHE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed is PackedScene:
		batch_root = packed.instantiate()
		_stats.cache_hit = true

func _save_cache(signature: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var packed := PackedScene.new()
	if packed.pack(batch_root) != OK:
		return
	if ResourceSaver.save(packed, CACHE_PATH, ResourceSaver.FLAG_COMPRESS) != OK:
		return
	var stamp := FileAccess.open(STAMP_PATH, FileAccess.WRITE)
	if stamp:
		stamp.store_string(JSON.stringify({"signature": signature}))
		_stats.cache_saved = true

func _build_batches() -> void:
	var chunks: Dictionary = {}
	var inverse := city.global_transform.affine_inverse()
	for source in _sources:
		var local := inverse * source.global_transform
		var center: Vector3 = local * source.mesh.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / CHUNK_SIZE), floori(center.z / CHUNK_SIZE))
		var key := "%d_%d_%d_%d" % [cell.x, cell.y, source.layers, source.cast_shadow]
		if not chunks.has(key):
			chunks[key] = {"origin": Vector3(cell.x * CHUNK_SIZE, 0.0, cell.y * CHUNK_SIZE),
				"layers": source.layers, "shadow": source.cast_shadow, "groups": {}}
		var chunk: Dictionary = chunks[key]
		var relative := local
		relative.origin -= chunk.origin
		for surface in source.mesh.get_surface_count():
			var material := source.get_active_material(surface)
			var material_id := material.get_instance_id() if material else 0
			# Do not coalesce surfaces with different vertex layouts or render layers.
			var format := (source.mesh as ArrayMesh).surface_get_format(surface)
			var group_key := "%d_%d_%d_%d" % [material_id, format, source.layers, source.cast_shadow]
			if not chunk.groups.has(group_key):
				chunk.groups[group_key] = {"material": material, "entries": [], "layers": source.layers, "shadow": source.cast_shadow}
			chunk.groups[group_key].entries.append({"mesh": source.mesh, "surface": surface, "transform": relative})
	batch_root = Node3D.new()
	batch_root.name = "CityRenderBatches"
	var total_triangles := 0
	var total_surfaces := 0
	var keys: Array = chunks.keys()
	keys.sort()
	for key in keys:
		var chunk: Dictionary = chunks[key]
		var importer := ImporterMesh.new()
		var groups: Array = chunk.groups.keys()
		groups.sort()
		for group_key in groups:
			var group: Dictionary = chunk.groups[group_key]
			var surface_tool := SurfaceTool.new()
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for entry in group.entries:
				surface_tool.append_from(entry.mesh, int(entry.surface), entry.transform)
			var arrays := surface_tool.commit_to_arrays()
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, group.material)
		# Native meshoptimizer LODs retain the full-detail surface and reduce distant
		# triangle cost. Normals, tangents, UVs and vertex colors were copied above.
		importer.generate_lods(60.0, 0.0, [])
		var mesh: ArrayMesh = importer.get_mesh()
		if mesh == null:
			continue
		mesh.shadow_mesh = _shadow_mesh(importer)
		var instance := MeshInstance3D.new()
		instance.name = "BuildingChunk_" + str(key)
		instance.mesh = mesh
		instance.position = chunk.origin
		instance.layers = int(chunk.layers)
		instance.cast_shadow = int(chunk.shadow)
		instance.set_meta("city_surface_kind", "building")
		instance.extra_cull_margin = 2.0
		batch_root.add_child(instance)
		instance.owner = batch_root
		total_triangles += _triangle_count(mesh)
		total_surfaces += mesh.get_surface_count()
	batch_root.set_meta("triangle_count", total_triangles)
	batch_root.set_meta("surface_count", total_surfaces)
	batch_root.set_meta("cache_version", CACHE_VERSION)

func _shadow_mesh(source: ImporterMesh) -> ArrayMesh:
	# All city building materials are opaque and leave vertex positions intact.
	# Preserve the exact surface slots, vertex positions and LOD index tables:
	# the renderer indexes the shadow mesh using the main mesh's surface index.
	# Position-only arrays reduce shadow vertex traffic without merging slots.
	var shadow := ImporterMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.get_surface_arrays(surface).duplicate()
		for index in Mesh.ARRAY_MAX:
			if index != Mesh.ARRAY_VERTEX and index != Mesh.ARRAY_INDEX:
				arrays[index] = null
		var lods: Dictionary = {}
		for lod in source.get_surface_lod_count(surface):
			lods[source.get_surface_lod_size(surface, lod)] = source.get_surface_lod_indices(surface, lod)
		shadow.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return shadow.get_mesh()

func set_quality(preset: String) -> void:
	quality = preset if preset in ["low", "balanced", "high"] else "balanced"
	_stats.quality = quality
	if not enabled or city == null:
		return
	var bias: float = {"low": 0.7, "balanced": 1.0, "high": 1.5}[quality]
	var shadow_distance: float = {"low": 55.0, "balanced": 90.0, "high": 120.0}[quality]
	if batch_root:
		for child in batch_root.get_children():
			if child is GeometryInstance3D:
				child.lod_bias = bias
				# Balanced keeps the entire neighborhood in normal street-level views.
				child.visibility_range_end = 520.0 if quality == "low" else 0.0
	for mesh_node in _all_meshes:
		if mesh_node.layers == 0:
			continue
		mesh_node.lod_bias = bias
		if str(mesh_node.name).begins_with("Context_Buildings"):
			mesh_node.visibility_range_end = 850.0 if quality == "low" else 0.0
	for node in level.find_children("*", "DirectionalLight3D", true, false):
		if node.shadow_enabled:
			node.directional_shadow_max_distance = shadow_distance
			node.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for node in level.find_children("*", "WorldEnvironment", true, false):
		if node.environment:
			node.environment.ssao_enabled = quality != "low"
	_stats.shadow_distance = shadow_distance
	_stats.lod_bias = bias
	if is_instance_valid(level.get("streaming")):
		level.streaming.set_quality(quality)

func get_stats() -> Dictionary:
	return _stats.duplicate(true)
