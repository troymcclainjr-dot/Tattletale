extends Node
## Keep terrain/collision authoritative while detailed building render resources
## stream independently. Distance hysteresis protects camera turns and cell edges.
const CACHE_VERSION := 2
const CACHE_ROOT := "user://city_stream_cache"
const SOURCE_PATH := "res://assets/models/city/pen_lucy.glb"
const DETAIL_INTERVAL := 0.25
## A physics-focus jump this large between frames is a relocation, not travel.
const RELOCATION_DISTANCE := 16.0
var level: Node3D
var optimizer: Node
var records: Array[Dictionary] = []
var providers: Array[Node] = []
var quality := "balanced"
var load_distance := 240.0
var unload_distance := 330.0
## Ordinary play spreads one periodic provider pass over consecutive frames. This
## soft target is checked between provider calls: one indivisible set_presence
## call can exceed it, and each frame always advances at least one provider.
## refresh_now(), setup and camera captures still refresh every provider at once.
var detail_frame_budget_usec := 2500
var _elapsed := 0.0
var _directory := ""
var _pending := ""
var _pending_index := -1
var _proxy_root: Node3D
var _released_sources := 0
var _loads := 0
var _unloads := 0
var _ready_stream := false
var _detail_render_focus := Vector3.ZERO
var _detail_physics_focus := Vector3.ZERO
var _capture_details := false
var _detail_queue: Array[Node] = []
var _detail_due := false
var _detail_pass_usec := 0
var _detail_pass_slices := 0
var _detail_passes := 0
var _detail_slices := 0
var _detail_overruns := 0
var _relocation_refreshes := 0
# Latest measured cost per provider instance id; predicts whether it fits a slice.
var _provider_cost := {}
var _last_focus := Vector3.INF
# Opt-in CPU attribution; disabled in ordinary play. Totals are bounded and
# retain maxima/frame IDs, rather than growing a trace during long sessions.
var profile_streaming := false
var profile_stages: Dictionary = {}
var profile_unload_batches: Dictionary = {"max_cells": 0, "max_frame": 0}
var profile_slow_stages: Array[Dictionary] = []
var profile_detail_schedule: Dictionary = {"passes": 0, "slices": 0, "max_slices_per_pass": 0, "budget_overruns": 0}

func _profile_stage(stage: String, began: int) -> void:
	if not profile_streaming:
		return
	_profile_elapsed(stage, Time.get_ticks_usec() - began, began)

func _profile_elapsed(stage: String, elapsed: int, began: int, frame_event := true) -> void:
	var entry: Dictionary = profile_stages.get(stage, {"calls": 0, "total_usec": 0, "max_usec": 0, "max_frame": 0})
	entry.calls += 1
	entry.total_usec += elapsed
	if elapsed > int(entry.max_usec):
		entry.max_usec = elapsed
		entry.max_frame = Engine.get_process_frames()
	profile_stages[stage] = entry
	# Slow events are correlated with individual frames; multi-frame totals opt out.
	if frame_event and elapsed >= 20000:
		if profile_slow_stages.size() >= 128:
			profile_slow_stages.pop_front()
		profile_slow_stages.append({"stage": stage, "usec": elapsed,
			"process_frame": Engine.get_process_frames(), "at_usec": began})

func _exit_tree() -> void:
	# Consume an outstanding request when the level closes. Normal play never waits
	# on unfinished IO; teardown must release the loader's pending resource handle.
	if not _pending.is_empty():
		ResourceLoader.load_threaded_get(_pending)
		_pending = ""
	_detail_queue.clear()
	_detail_due = false
	_provider_cost.clear()

func setup(owner_level: Node3D, render_optimizer: Node, detail_providers: Array[Node] = []) -> void:
	level = owner_level
	optimizer = render_optimizer
	providers = detail_providers
	name = "NeighborhoodStreaming"
	if optimizer == null or not optimizer.enabled or optimizer.batch_root == null:
		return
	var stats: Dictionary = optimizer.get_stats()
	var signature: String = optimizer._cache_signature(int(stats.building_surfaces), int(stats.building_triangles)) + "|stream:" + str(CACHE_VERSION)
	# Consolidated CUSTOM0 palette geometry must never load from legacy cells.
	signature += "|" + optimizer.palette_cache_signature()
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
		optimizer.rebind_shared_materials(instance)
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
	if optimizer != null and optimizer.quality != quality:
		# The optimizer owns chunk LOD/culling and sun settings; this manager owns
		# only residency distances. Its callback re-enters with matching quality.
		optimizer.set_quality(quality)
	load_distance = {"low": 175.0, "balanced": 240.0, "high": 320.0}[quality]
	unload_distance = load_distance + 90.0
	for record in records:
		if is_instance_valid(record.node):
			_apply_quality(record.node)

func _apply_quality(instance: MeshInstance3D) -> void:
	if optimizer != null:
		optimizer.apply_chunk_quality(instance)

func _process(delta: float) -> void:
	# Detail presence must still run when building batching/cache is unavailable.
	if level == null:
		return
	_poll_load()
	if level.player == null:
		return
	_elapsed += delta
	var relocated := _focus_jumped()
	if relocated or _elapsed >= DETAIL_INTERVAL:
		_elapsed = 0.0
		_relocation_refreshes += int(relocated)
		if _capture_requested():
			# Automated captures keep the original fully synchronous refresh.
			_cancel_detail_pass()
			_refresh(false)
			return
		_refresh(false, false, true)
		# A pass in progress continues with the new focus; a complete pass follows.
		_detail_due = true
	if _detail_queue.is_empty():
		if not _detail_due:
			return
		_detail_due = false
		_detail_queue.assign(providers)
		if _detail_queue.is_empty():
			return
	_dispatch_detail_slice()

func _focus_jumped() -> bool:
	if level.player == null:
		return false
	var focus: Vector3 = level.player.global_position
	var inspector = level.get("inspector")
	if inspector != null and inspector.active:
		focus = inspector.streaming_focus()
	var jumped := _last_focus.is_finite() and focus.distance_squared_to(_last_focus) > RELOCATION_DISTANCE * RELOCATION_DISTANCE
	_last_focus = focus
	return jumped

func _capture_requested() -> bool:
	if level.player == null or level.player.camera_override.is_empty():
		return false
	var inspector = level.get("inspector")
	return inspector == null or not inspector.active

func _distance_to_bounds(point: Vector3, bounds: AABB) -> float:
	var closest := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.z, bounds.position.z, bounds.end.z))
	return Vector2(point.x, point.z).distance_to(closest)

func _detail_focus() -> Array:
	# Automated captures and the overview camera request detail around their view,
	# without ever changing the physical player's collision neighborhood.
	var point: Vector3 = level.player.global_position
	var render_point := point
	var detail_point := point
	var capture_details: bool = not level.player.camera_override.is_empty()
	if capture_details:
		render_point = level.player.camera_override.get("target", point)
		# Detail distance/LOD follows the actual camera, not a far look-at target.
		detail_point = level.player.camera_override.get("eye", render_point)
	var inspector = level.get("inspector")
	if inspector != null and inspector.active:
		point = inspector.streaming_focus()
		render_point = point
		detail_point = point
		capture_details = false
	_detail_render_focus = detail_point
	_detail_physics_focus = point
	_capture_details = capture_details
	return [point, render_point, detail_point, capture_details]

func _refresh(initial: bool, refresh_details := true, paced := false) -> void:
	if level.player == null:
		return
	var began := Time.get_ticks_usec() if profile_streaming else 0
	var focus := _detail_focus()
	var render_point: Vector3 = focus[1]
	var desired := -1
	var priority := INF
	var unloads_before := _unloads
	var retire := -1
	var retire_distance := -INF
	for i in records.size():
		var record: Dictionary = records[i]
		var distance := _distance_to_bounds(render_point, record.bounds)
		if is_instance_valid(record.node):
			if distance > unload_distance:
				# Periodic scheduling retires the farthest such cell per call, so a
				# relocation cannot destroy several large scenes at one frame end.
				if not paced:
					_retire(record)
				elif distance > retire_distance:
					retire = i
					retire_distance = distance
		elif distance < load_distance and not record.failed:
			# Closest cells first; one threaded request avoids flooding storage/GPU.
			if distance < priority:
				priority = distance
				desired = i
	if retire >= 0:
		_retire(records[retire])
	# queue_free only schedules work. This count distinguishes a cheap refresh
	# that causes a later frame-end destruction spike from synchronous activation.
	if profile_streaming and _unloads - unloads_before > int(profile_unload_batches.max_cells):
		profile_unload_batches.max_cells = _unloads - unloads_before
		profile_unload_batches.max_frame = Engine.get_process_frames()
	if desired >= 0 and _pending.is_empty() and not initial:
		var path: String = records[desired].path
		var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_IGNORE)
		if error == OK:
			_pending = path
			_pending_index = desired
		else:
			records[desired].failed = true
			push_warning("City cell load request failed: " + path)
	_profile_stage("building_refresh", began)
	if not refresh_details:
		return
	for provider in providers:
		if is_instance_valid(provider) and provider.has_method("set_presence"):
			_apply_presence(provider, focus, false)
	# Synchronous full refreshes only; periodic passes report detail_frame_slice.
	_profile_stage("refresh_with_details", began)

func _retire(record: Dictionary) -> void:
	record.node.queue_free()
	record.node = null
	record.proxy.show()
	_unloads += 1

func _apply_presence(provider: Node, focus: Array, paced: bool) -> void:
	var point: Vector3 = focus[0]
	var detail_point: Vector3 = focus[2]
	var capture_details: bool = focus[3]
	var far_radius := 180.0 if quality != "low" else 135.0
	if profile_streaming and "profile_presence" in provider:
		provider.profile_presence = true
	var began := Time.get_ticks_usec()
	if capture_details and provider.has_method("set_capture_presence"):
		provider.set_capture_presence(point, detail_point, 55.0, far_radius)
	elif paced and not capture_details and provider.has_method("set_paced_presence"):
		provider.set_paced_presence(point, 55.0, far_radius)
	else:
		# These providers only cull visuals; their collision stays permanent.
		provider.set_presence(detail_point if capture_details else point, 55.0, far_radius)
	var elapsed := Time.get_ticks_usec() - began
	_provider_cost[provider.get_instance_id()] = elapsed
	if not profile_streaming:
		return
	var stage := "detail:" + str(provider.name)
	_profile_elapsed(stage, elapsed, began)
	# Provider phases are nested inside its stage; never sum them with it.
	if "presence_profile" in provider:
		var phases: Dictionary = provider.presence_profile
		for phase in phases:
			_profile_elapsed(stage + "/" + str(phase), int(phases[phase]), began)

func _dispatch_detail_slice() -> void:
	var began := Time.get_ticks_usec()
	var focus := _detail_focus()
	var dispatched := 0
	while not _detail_queue.is_empty():
		var provider = _detail_queue[0]
		var usable: bool = is_instance_valid(provider) and provider.has_method("set_presence")
		if usable and dispatched > 0:
			var predicted := int(_provider_cost.get(provider.get_instance_id(), 0))
			if Time.get_ticks_usec() - began + predicted > detail_frame_budget_usec:
				break
		_detail_queue.pop_front()
		if usable:
			_apply_presence(provider, focus, true)
			dispatched += 1
	var spent := Time.get_ticks_usec() - began
	_detail_slices += 1
	_detail_pass_slices += 1
	_detail_pass_usec += spent
	_detail_overruns += int(spent > detail_frame_budget_usec)
	if profile_streaming:
		_profile_elapsed("detail_frame_slice", spent, began)
		profile_detail_schedule.slices += 1
		profile_detail_schedule.budget_overruns += int(spent > detail_frame_budget_usec)
	if not _detail_queue.is_empty():
		return
	_detail_passes += 1
	if profile_streaming:
		# CPU summed across the pass's frames; it is not a single-frame cost.
		_profile_elapsed("detail_pass_cpu", _detail_pass_usec, began, false)
		profile_detail_schedule.passes += 1
		profile_detail_schedule.max_slices_per_pass = maxi(int(profile_detail_schedule.max_slices_per_pass), _detail_pass_slices)
	_detail_pass_usec = 0
	_detail_pass_slices = 0

func _cancel_detail_pass() -> void:
	_detail_queue.clear()
	_detail_due = false
	_detail_pass_usec = 0
	_detail_pass_slices = 0

func _poll_load() -> void:
	if _pending.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_pending)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var began := Time.get_ticks_usec() if profile_streaming else 0
		var scene = ResourceLoader.load_threaded_get(_pending)
		_profile_stage("threaded_get_ready", began)
		if scene is PackedScene:
			var stage_began := Time.get_ticks_usec() if profile_streaming else 0
			var instance: MeshInstance3D = scene.instantiate()
			_profile_stage("instantiate", stage_began)
			stage_began = Time.get_ticks_usec() if profile_streaming else 0
			optimizer.rebind_shared_materials(instance)
			_profile_stage("bind_materials", stage_began)
			stage_began = Time.get_ticks_usec() if profile_streaming else 0
			optimizer.batch_root.add_child(instance)
			_profile_stage("add_child", stage_began)
			stage_began = Time.get_ticks_usec() if profile_streaming else 0
			_apply_quality(instance)
			_profile_stage("apply_quality", stage_began)
			records[_pending_index].node = instance
			records[_pending_index].proxy.hide()
			_loads += 1
		else:
			records[_pending_index].failed = true
		_pending = ""
		_pending_index = -1
		_profile_stage("activate_cell", began)
		# Advance the next building request immediately. Detail presence keeps its
		# regular cadence (or explicit refresh_now), so a completed load cannot
		# repeat provider scans or spend another vegetation mesh budget this frame.
		_refresh(false, false, true)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		records[_pending_index].failed = true
		push_warning("City cell background load failed: " + _pending)
		_pending = ""
		_pending_index = -1

func refresh_now() -> void:
	if level != null:
		# Explicit requests stay complete and synchronous; they supersede any
		# periodic pass still spread over frames.
		_cancel_detail_pass()
		_refresh(false)

func get_status() -> Dictionary:
	var active := 0
	var triangles := 0
	var total_triangles := 0
	var failures := 0
	var missing_near := 0
	var deferred_unloads := 0
	var focus: Vector3 = level.player.global_position if level != null and level.player != null else Vector3.ZERO
	if level != null and level.player != null and not level.player.camera_override.is_empty():
		focus = level.player.camera_override.get("target", focus)
	var inspector = level.get("inspector") if level != null else null
	if inspector != null and inspector.active:
		focus = inspector.streaming_focus()
	for record in records:
		total_triangles += int(record.triangles)
		if is_instance_valid(record.node):
			active += 1
			triangles += int(record.triangles)
			deferred_unloads += int(_distance_to_bounds(focus, record.bounds) > unload_distance)
		if record.failed:
			failures += 1
		if not is_instance_valid(record.node) and _distance_to_bounds(focus, record.bounds) < load_distance:
			missing_near += 1
	var detail_pending := 0
	var detail_missing := 0
	if _capture_details:
		for provider in providers:
			if not is_instance_valid(provider):
				continue
			var status: Dictionary = provider.get_stats() if provider.has_method("get_stats") else (provider.get_status() if provider.has_method("get_status") else {})
			detail_pending += int(status.get("pending_visual_cells", 0)) + int(status.get("pending_loads", 0))
			detail_missing += int(status.get("near_cells_missing", 0))
	return {"enabled": _ready_stream, "cells": records.size(),
		"profile_stages": profile_stages.duplicate(true) if profile_streaming else {},
		"profile_unload_batches": profile_unload_batches.duplicate() if profile_streaming else {},
		"profile_slow_stages": profile_slow_stages.duplicate(true) if profile_streaming else [],
		"profile_detail_schedule": profile_detail_schedule.duplicate() if profile_streaming else {},
		"capture_details": _capture_details, "detail_render_focus": _detail_render_focus, "detail_physics_focus": _detail_physics_focus,
		"detail_pending": detail_pending, "detail_missing": detail_missing, "loaded_cells": active,
		"proxy_cells": records.size() - active, "loaded_detail_triangles": triangles,
		"total_detail_triangles": total_triangles, "released_original_meshes": _released_sources,
		"background_loads": _loads, "unloads": _unloads, "unloads_deferred": deferred_unloads, "pending": not _pending.is_empty(),
		"failures": failures, "near_cells_missing": missing_near, "load_radius": load_distance, "unload_radius": unload_distance,
		"detail_frame_budget_usec": detail_frame_budget_usec, "detail_queue": _detail_queue.size(),
		"detail_passes": _detail_passes, "detail_slices": _detail_slices, "detail_budget_overruns": _detail_overruns,
		"relocation_refreshes": _relocation_refreshes,
		"quality": quality, "collision_streaming": false}
