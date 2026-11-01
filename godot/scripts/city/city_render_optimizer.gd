extends Node
## Static render batching only: original meshes and their physics children remain.
## Call after collision creation, before neighborhood-specific material overrides.

const CACHE_VERSION := 6
const CHUNK_SIZE := 150.0
const MODEL_PATH := "res://assets/models/city/pen_lucy.glb"
const CACHE_DIR := "user://city_render_cache"
const CACHE_PATH := CACHE_DIR + "/pen_lucy_batches.scn"
const STAMP_PATH := CACHE_DIR + "/pen_lucy_batches.json"
const PALETTE_VERSION := 1
const PALETTE_SHADER := "res://assets/materials/city_surface.gdshader"
const PALETTE_CACHE_DIR := "user://city_palette_cache"
var level: Node3D
var city: Node3D
var batch_root: Node3D
var quality := "balanced"
var enabled := true
var _sources: Array[MeshInstance3D] = []
var _all_meshes: Array[MeshInstance3D] = []
var _stats: Dictionary = {}
var _palette_materials: Dictionary = {}
var _palette_applied := false
var _palette_cache_digest := ""
var _canonical_materials: Dictionary = {}

func rebind_shared_materials(instance: MeshInstance3D) -> void:
	if instance.mesh == null:
		return
	if _canonical_materials.is_empty():
		# Prefer current authored/override resources to serialized copies, including
		# the glass material shared with non-streamed city geometry.
		for source in _all_meshes:
			if is_instance_valid(source) and source.mesh != null:
				for surface in source.mesh.get_surface_count():
					var material := source.get_active_material(surface)
					if material != null:
						_canonical_materials[_material_fingerprint(material)] = material
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_active_material(surface)
		if material == null:
			continue
		var key := _material_fingerprint(material)
		if not _canonical_materials.has(key):
			_canonical_materials[key] = material
		var shared: Material = _canonical_materials[key]
		if instance.get_surface_override_material(surface) != null:
			instance.set_surface_override_material(surface, shared)
		elif instance.material_override == null:
			instance.mesh.surface_set_material(surface, shared)

func apply_chunk_quality(instance: GeometryInstance3D) -> void:
	instance.lod_bias = {"low": 0.7, "balanced": 1.0, "high": 1.5}[quality]
	instance.visibility_range_end = 520.0 if quality == "low" else 0.0

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
	var redevelopment := ""
	for path in ["res://assets/data/pen_lucy_civic_build.json", "res://assets/data/pen_lucy_new_businesses.json"]:
		if FileAccess.file_exists(path):
			redevelopment += FileAccess.get_sha256(path)
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [CACHE_VERSION, Engine.get_version_info().string,
		FileAccess.get_modified_time(MODEL_PATH), FileAccess.get_modified_time(MODEL_PATH + ".import"),
		bytes, surfaces, triangles, redevelopment]

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

func palette_cache_signature() -> String:
	var digest := _palette_cache_digest
	if digest.is_empty() and batch_root != null:
		# Baseline material/calibration flags also need distinct streaming caches.
		var fingerprint := ""
		for child in batch_root.get_children():
			if child is MeshInstance3D and child.mesh != null:
				for surface in child.mesh.get_surface_count():
					fingerprint += _material_fingerprint(child.get_active_material(surface))
		digest = fingerprint.sha256_text()
	return "palette:%d:%s:%s" % [PALETTE_VERSION, _palette_applied, digest]

func consolidate_material_palette(persist_cache: bool = true) -> Dictionary:
	# Call after weathering/window overrides and before streaming serializes cells.
	# Only the explicit city_surface contract permits moving uniforms to vertices.
	var report := {"enabled": false, "surfaces_before": 0, "surfaces_after": 0,
		"merged_surfaces": 0, "palette_materials": 0, "cache_hits": 0, "cache_builds": 0}
	if not enabled or batch_root == null or _palette_applied:
		return report
	if "--no-city-material-palette" in OS.get_cmdline_args() or "--no-city-material-palette" in OS.get_cmdline_user_args():
		_stats.material_palette = report
		return report
	var began := Time.get_ticks_msec()
	var cache_available := persist_cache and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PALETTE_CACHE_DIR)) == OK
	var source_signature := _cache_signature(int(_stats.get("building_surfaces", 0)), int(_stats.get("building_triangles", 0)))
	var content_fingerprints: Array[String] = []
	for child in batch_root.get_children():
		if not child is MeshInstance3D or not child.mesh is ArrayMesh:
			continue
		var instance := child as MeshInstance3D
		var original := instance.mesh as ArrayMesh
		if instance.material_override != null or instance.material_overlay != null or original.get_blend_shape_count() > 0:
			var unchanged_fingerprint := str(instance.name) + _material_fingerprint(instance.material_overlay)
			for surface in original.get_surface_count():
				unchanged_fingerprint += _material_fingerprint(instance.get_active_material(surface))
			content_fingerprints.append(unchanged_fingerprint.sha256_text())
			report.surfaces_before += original.get_surface_count()
			report.surfaces_after += original.get_surface_count()
			continue
		var groups: Dictionary = {}
		var fingerprint := ""
		for surface in original.get_surface_count():
			var material := instance.get_active_material(surface)
			var descriptor := _palette_descriptor(material, original.surface_get_format(surface))
			var key := str(descriptor.get("key", "surface:%d" % surface))
			if not groups.has(key):
				groups[key] = {"surfaces": [], "descriptor": descriptor, "material": material, "paints": {}}
			groups[key].surfaces.append(surface)
			groups[key].paints[surface] = descriptor
			fingerprint += "|%d:%s" % [surface, _material_fingerprint(material)]
		content_fingerprints.append((str(instance.name) + fingerprint).sha256_text())
		report.surfaces_before += original.get_surface_count()
		if groups.size() == original.get_surface_count():
			report.surfaces_after += original.get_surface_count()
			continue
		var cache_key := (source_signature + "|palette:" + str(PALETTE_VERSION) + "|" + str(instance.name) + fingerprint).sha256_text()
		var cache_path := PALETTE_CACHE_DIR.path_join(cache_key + ".res")
		var replacement: ArrayMesh
		if cache_available and ResourceLoader.exists(cache_path):
			replacement = ResourceLoader.load(cache_path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
			if replacement != null and (_triangle_count(replacement) != _triangle_count(original) or replacement.get_surface_count() != groups.size()):
				replacement = null
			if replacement != null:
				report.cache_hits += 1
		if replacement == null:
			replacement = _consolidate_palette_mesh(original, groups)
			if replacement != null and cache_available:
				ResourceSaver.save(replacement, cache_path, ResourceSaver.FLAG_COMPRESS)
			report.cache_builds += 1
		if replacement == null or _triangle_count(replacement) != _triangle_count(original):
			report.surfaces_after += original.get_surface_count()
			continue
		for surface in replacement.get_surface_count():
			var cached_material := replacement.surface_get_material(surface)
			if cached_material == null or not cached_material.has_meta("city_palette_key"):
				continue
			var material_key: String = cached_material.get_meta("city_palette_key")
			if not _palette_materials.has(material_key):
				_palette_materials[material_key] = cached_material
			else:
				replacement.surface_set_material(surface, _palette_materials[material_key])
		# Overrides refer to the OLD surface slots. Remove before changing their
		# count/order; every new slot carries its exact effective material itself.
		for surface in original.get_surface_count():
			instance.set_surface_override_material(surface, null)
		instance.mesh = replacement
		report.surfaces_after += replacement.get_surface_count()
		_palette_applied = true
		report.enabled = true
	# Source collision meshes, chunk bounds, layers and culling remain untouched.
	report.merged_surfaces = int(report.surfaces_before) - int(report.surfaces_after)
	report.palette_materials = _palette_materials.size()
	report.setup_ms = Time.get_ticks_msec() - began
	_palette_cache_digest = "|".join(content_fingerprints).sha256_text()
	_stats.material_palette = report
	if _palette_applied:
		_stats.batch_surfaces = int(report.surfaces_after)
		_stats.visible_surface_budget = int(_stats.source_surfaces) - int(_stats.building_surfaces) + int(report.surfaces_after)
		batch_root.set_meta("surface_count", int(report.surfaces_after))
	print("[city_palette] " + JSON.stringify(report))
	return report

func _material_fingerprint(material: Material) -> String:
	if material == null:
		return "null"
	if not material is ShaderMaterial:
		# These surfaces are never merged; resource identity/path still separates
		# incompatible persisted chunks when the imported material changes.
		var stored: Dictionary = {}
		for property in material.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				stored[str(property.name)] = material.get(property.name)
		return var_to_str(stored)
	var shader_material := material as ShaderMaterial
	if shader_material.shader == null:
		return "shader:null"
	var names: Array[String] = []
	for uniform in shader_material.shader.get_shader_uniform_list():
		names.append(str(uniform.name))
	names.sort()
	var result := shader_material.shader.code.sha256_text() + ":" + str(material.render_priority)
	if material.next_pass != null:
		result += "|next=" + _material_fingerprint(material.next_pass)
	for uniform in names:
		result += "|" + uniform + "=" + var_to_str(_effective_shader_parameter(shader_material, uniform))
	return result

func _effective_shader_parameter(material: ShaderMaterial, parameter: String) -> Variant:
	# get_shader_parameter returns null for an unset uniform. Resource duplication
	# and saving enumerate properties, which populate those same entries with
	# shader defaults. Hash the effective value so that harmless mutation cannot
	# change cache identity or prevent canonical material sharing.
	var value = material.get_shader_parameter(parameter)
	if value == null and material.shader != null:
		return RenderingServer.shader_get_parameter_default(material.shader.get_rid(), parameter)
	return value

func _palette_descriptor(material: Material, format: int) -> Dictionary:
	if not material is ShaderMaterial or material.next_pass != null:
		return {}
	var shader_material := material as ShaderMaterial
	if shader_material.shader == null or shader_material.shader.resource_path != PALETTE_SHADER:
		return {}
	# Existing custom data belongs to another contract and must remain intact.
	if format & Mesh.ARRAY_FORMAT_CUSTOM0:
		return {}
	var names: Array[String] = []
	for uniform in shader_material.shader.get_shader_uniform_list():
		names.append(str(uniform.name))
	if not "use_vertex_palette" in names or shader_material.get_shader_parameter("use_vertex_palette") == true:
		return {}
	var color = shader_material.get_shader_parameter("albedo")
	var roughness = shader_material.get_shader_parameter("roughness")
	if not color is Color or not (roughness is float or roughness is int):
		return {}
	names.sort()
	var key := "%s:%s:%s" % [shader_material.shader.code.sha256_text(), material.render_priority, format & ~Mesh.ARRAY_FORMAT_INDEX]
	for uniform in names:
		if uniform not in ["albedo", "roughness", "use_vertex_palette"]:
			key += "|" + uniform + "=" + var_to_str(_effective_shader_parameter(shader_material, uniform))
	return {"key": key, "color": color, "roughness": float(roughness), "format": format}

## Authored civic meshes use the same explicit shader contract as city chunks.
## No spatial merging: each building/prop keeps its own bounds and collisions.
func consolidate_authored_mesh(original: ArrayMesh) -> ArrayMesh:
	if original == null or original.get_blend_shape_count() > 0:
		return original
	var groups: Dictionary = {}
	for surface in original.get_surface_count():
		if original.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return original
		var material := original.surface_get_material(surface)
		var descriptor := _palette_descriptor(material, original.surface_get_format(surface))
		var key := str(descriptor.get("key", "surface:%d" % surface))
		if not groups.has(key):
			groups[key] = {"surfaces": [], "descriptor": descriptor, "material": material, "paints": {}}
		groups[key].surfaces.append(surface)
		groups[key].paints[surface] = descriptor
	if groups.size() == original.get_surface_count():
		return original
	var result := _consolidate_palette_mesh(original, groups)
	if result == null or _triangle_count(result) != _triangle_count(original):
		return original
	return result

func _consolidate_palette_mesh(original: ArrayMesh, groups: Dictionary) -> ArrayMesh:
	var importer := ImporterMesh.new()
	var original_colors: Dictionary = {}
	for key in groups:
		var group: Dictionary = groups[key]
		var descriptor: Dictionary = group.descriptor
		var material: Material = group.material
		if descriptor.is_empty():
			var surface: int = group.surfaces[0]
			importer.add_surface(original.surface_get_primitive_type(surface), original.surface_get_arrays(surface), [], {}, material, "", original.surface_get_format(surface))
			continue
		var combined: Array = []
		combined.resize(Mesh.ARRAY_MAX)
		var indices := PackedInt32Array()
		var lod_colors := PackedColorArray()
		var offset := 0
		for surface in group.surfaces:
			var arrays := original.surface_get_arrays(int(surface))
			# The descriptor must be taken from the effective surface override.
			var paint: Dictionary = group.get("paints", {}).get(surface, {})
			if paint.is_empty():
				paint = descriptor
			var color: Color = paint.color
			var roughness: float = paint.roughness
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var palette := PackedFloat32Array()
			palette.resize(vertices.size() * 4)
			for vertex in vertices.size():
				palette[vertex * 4] = color.r
				palette[vertex * 4 + 1] = color.g
				palette[vertex * 4 + 2] = color.b
				palette[vertex * 4 + 3] = roughness
				lod_colors.append(Color(color.r, color.g, color.b, roughness))
			arrays[Mesh.ARRAY_CUSTOM0] = palette
			for slot in Mesh.ARRAY_MAX:
				if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
					continue
				if combined[slot] == null:
					combined[slot] = arrays[slot]
				else:
					var destination = combined[slot]
					destination.append_array(arrays[slot])
					combined[slot] = destination
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if source_indices.is_empty():
				for vertex in vertices.size():
					indices.append(offset + vertex)
			else:
				for index in source_indices:
					indices.append(offset + index)
			offset += vertices.size()
		combined[Mesh.ARRAY_INDEX] = indices
		# Native LOD welding compares COLOR, not CUSTOM0. Protect coincident
		# material seams during simplification without changing stored colors.
		original_colors[importer.get_surface_count()] = combined[Mesh.ARRAY_COLOR]
		combined[Mesh.ARRAY_COLOR] = lod_colors
		if not _palette_materials.has(key):
			var shared := material.duplicate() as ShaderMaterial
			shared.resource_name = "CityPalette_" + str(_palette_materials.size())
			shared.set_shader_parameter("use_vertex_palette", true)
			shared.set_meta("city_palette_key", key)
			_palette_materials[key] = shared
		var flags: int = int(descriptor.format) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, combined, [], {}, _palette_materials[key], "", flags)
	importer.generate_lods(60.0, 0.0, [])
	var final_mesh := ImporterMesh.new()
	for surface in importer.get_surface_count():
		var arrays: Array = importer.get_surface_arrays(surface).duplicate()
		if original_colors.has(surface):
			arrays[Mesh.ARRAY_COLOR] = original_colors[surface]
		var lods: Dictionary = {}
		for lod in importer.get_surface_lod_count(surface):
			lods[importer.get_surface_lod_size(surface, lod)] = importer.get_surface_lod_indices(surface, lod)
		final_mesh.add_surface(importer.get_surface_primitive_type(surface), arrays, [], lods,
			importer.get_surface_material(surface), "", importer.get_surface_format(surface))
	var result := final_mesh.get_mesh()
	if result != null:
		result.shadow_mesh = _shadow_mesh(final_mesh)
	return result

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
				apply_chunk_quality(child)
	for mesh_node in _all_meshes:
		if mesh_node.layers == 0:
			continue
		mesh_node.lod_bias = bias
		if str(mesh_node.name).begins_with("Context_Buildings"):
			mesh_node.visibility_range_end = 850.0 if quality == "low" else 0.0
	for node in level.find_children("*", "DirectionalLight3D", true, false):
		# Night temporarily disables the sun's shadows, not its chosen preset.
		if node.shadow_enabled or node.name == "LateAfternoonSun":
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
