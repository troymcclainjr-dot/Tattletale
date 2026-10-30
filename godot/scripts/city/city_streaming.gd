extends Node
## Keep terrain/collision authoritative while detailed building render resources
## stream independently. Distance hysteresis protects camera turns and cell edges.
const CACHE_VERSION := 1
const CACHE_ROOT := "user://city_stream_cache"
const SOURCE_PATH := "res://assets/models/city/pen_lucy.glb"
var level: Node3D
var optimizer: Node
var records: Array[Dictionary] = []
var providers: Array[Node] = []
var quality := "balanced"
var load_distance := 240.0
var unload_distance := 330.0
var _elapsed := 0.0
var _directory := ""
var _pending := ""
var _pending_index := -1
var _proxy_root: Node3D
var _released_sources := 0
var _loads := 0
var _unloads := 0
var _ready_stream := false

func _exit_tree() -> void:
	# Consume an outstanding request when the level closes. Normal play never waits
	# on unfinished IO; teardown must release the loader's pending resource handle.
	if not _pending.is_empty():
		ResourceLoader.load_threaded_get(_pending)
		_pending = ""

func setup(owner_level: Node3D, render_optimizer: Node, detail_providers: Array[Node] = []) -> void:
	level = owner_level
	optimizer = render_optimizer
	providers = detail_providers
	name = "NeighborhoodStreaming"
	if optimizer == null or not optimizer.enabled or optimizer.batch_root == null:
		return
	var stats: Dictionary = optimizer.get_stats()
	var signature: String = optimizer._cache_signature(int(stats.building_surfaces), int(stats.building_triangles)) + "|stream:" + str(CACHE_VERSION)
	for material_source in ["res://scripts/city/city_weathering.gd", "res://scripts/city/city_windows.gd", "res://assets/materials/city_surface.gdshader", "res://assets/materials/city_glass.gdshader"]:
		signature += "|" + str(FileAccess.get_modified_time(material_source))
	_directory = CACHE_ROOT.path_join(signature.sha256_text().substr(0, 24))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) != OK:
		push_warning("City streaming cache unavailable; retaining all detailed geometry")
		return
	_proxy_root = Node3D.new()
	_proxy_root.name = "DistantBuildingSilhouettes"
	level.add_child(_proxy_root)
	var sources: Array = optimizer._sources
	for child in optimizer.batch_root.get_children():
		if not child is MeshInstance3D or child.mesh == null:
			continue
		var instance: MeshInstance3D = child
		var path := _directory.path_join(str(instance.name) + ".scn")
		# The cache includes the city-specific material overrides applied before setup.
		if not FileAccess.file_exists(path):
			var scene := PackedScene.new()
			if scene.pack(instance) != OK or ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS) != OK:
				push_warning("Could not cache city cell " + str(instance.name))
				continue
		var world_bounds: AABB = instance.global_transform * instance.mesh.get_aabb()
		var proxy := _make_proxy(instance, sources)
		_proxy_root.add_child(proxy)
		proxy.hide()
		records.append({"path": path, "node": instance, "proxy": proxy, "bounds": world_bounds,
			"triangles": optimizer._triangle_count(instance.mesh), "failed": false})
	if records.is_empty():
		return
	# Collision children own their triangle shapes. Clearing hidden visual resources
	# releases the second full-detail copy after windows/frontages have been measured.
	for source in sources:
		if is_instance_valid(source) and source.layers == 0:
			source.mesh = null
			_released_sources += 1
	_ready_stream = true
	set_quality(optimizer.quality)
	_refresh(true)

func _make_proxy(chunk: MeshInstance3D, sources: Array) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chunk_cell := Vector2i(floori(chunk.position.x / optimizer.CHUNK_SIZE), floori(chunk.position.z / optimizer.CHUNK_SIZE))
	for source in sources:
		if source.mesh == null:
			continue
		var bounds: AABB = source.global_transform * source.mesh.get_aabb()
		var center := bounds.get_center()
		var local_center: Vector3 = optimizer.city.global_transform.affine_inverse() * center
		var cell := Vector2i(floori(local_center.x / optimizer.CHUNK_SIZE), floori(local_center.z / optimizer.CHUNK_SIZE))
		if cell != chunk_cell:
			continue
		var box := BoxMesh.new()
		box.size = bounds.size
		# A single neutral brick-colored envelope replaces many facade surfaces only
		# outside the detailed cell's streaming radius; no collision comes from it.
		surface.append_from(box, 0, Transform3D(Basis.IDENTITY, center))
	var proxy := MeshInstance3D.new()
	proxy.name = "Far_" + str(chunk.name)
	proxy.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("746c61")
	material.roughness = 1.0
	material.metallic_specular = 0.05
	proxy.material_override = material
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return proxy

func set_quality(preset: String) -> void:
	quality = preset if preset in ["low", "balanced", "high"] else "balanced"
	load_distance = {"low": 175.0, "balanced": 240.0, "high": 320.0}[quality]
	unload_distance = load_distance + 90.0
	for record in records:
		if is_instance_valid(record.node):
			_apply_quality(record.node)

func _apply_quality(instance: MeshInstance3D) -> void:
	instance.lod_bias = {"low": 0.65, "balanced": 1.0, "high": 1.5}[quality]
	instance.visibility_range_end = 0.0

func _process(delta: float) -> void:
	# Detail presence must still run when building batching/cache is unavailable.
	if level == null:
		return
	_poll_load()
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		_refresh(false)

func _distance_to_bounds(point: Vector3, bounds: AABB) -> float:
	var closest := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.z, bounds.position.z, bounds.end.z))
	return Vector2(point.x, point.z).distance_to(closest)

func _refresh(initial: bool) -> void:
	if level.player == null:
		return
	var point: Vector3 = level.player.global_position
	# Automated captures and the overview camera request detail around their view,
	# without ever changing the physical player's collision neighborhood.
	var render_point := point
	if not level.player.camera_override.is_empty():
		render_point = level.player.camera_override.get("target", point)
	var desired := -1
	var priority := INF
	for i in records.size():
		var record: Dictionary = records[i]
		var distance := _distance_to_bounds(render_point, record.bounds)
		if is_instance_valid(record.node):
			if distance > unload_distance:
				record.node.queue_free()
				record.node = null
				record.proxy.show()
				_unloads += 1
		elif distance < load_distance and not record.failed:
			# Closest cells first; one threaded request avoids flooding storage/GPU.
			if distance < priority:
				priority = distance
				desired = i
	if desired >= 0 and _pending.is_empty() and not initial:
		var path: String = records[desired].path
		var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_IGNORE)
		if error == OK:
			_pending = path
			_pending_index = desired
		else:
			records[desired].failed = true
			push_warning("City cell load request failed: " + path)
	for provider in providers:
		if is_instance_valid(provider) and provider.has_method("set_presence"):
			provider.set_presence(point, 55.0, 180.0 if quality != "low" else 135.0)

func _poll_load() -> void:
	if _pending.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_pending)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var scene = ResourceLoader.load_threaded_get(_pending)
		if scene is PackedScene:
			var instance: MeshInstance3D = scene.instantiate()
			optimizer.batch_root.add_child(instance)
			_apply_quality(instance)
			records[_pending_index].node = instance
			records[_pending_index].proxy.hide()
			_loads += 1
		else:
			records[_pending_index].failed = true
		_pending = ""
		_pending_index = -1
		_refresh(false)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		records[_pending_index].failed = true
		push_warning("City cell background load failed: " + _pending)
		_pending = ""
		_pending_index = -1

func refresh_now() -> void:
	if level != null:
		_refresh(false)

func get_status() -> Dictionary:
	var active := 0
	var triangles := 0
	var total_triangles := 0
	var failures := 0
	var missing_near := 0
	var focus: Vector3 = level.player.global_position if level != null and level.player != null else Vector3.ZERO
	if level != null and level.player != null and not level.player.camera_override.is_empty():
		focus = level.player.camera_override.get("target", focus)
	for record in records:
		total_triangles += int(record.triangles)
		if is_instance_valid(record.node):
			active += 1
			triangles += int(record.triangles)
		if record.failed:
			failures += 1
		if not is_instance_valid(record.node) and _distance_to_bounds(focus, record.bounds) < load_distance:
			missing_near += 1
	return {"enabled": _ready_stream, "cells": records.size(), "loaded_cells": active,
		"proxy_cells": records.size() - active, "loaded_detail_triangles": triangles,
		"total_detail_triangles": total_triangles, "released_original_meshes": _released_sources,
		"background_loads": _loads, "unloads": _unloads, "pending": not _pending.is_empty(),
		"failures": failures, "near_cells_missing": missing_near, "load_radius": load_distance, "unload_radius": unload_distance,
		"quality": quality, "collision_streaming": false}
