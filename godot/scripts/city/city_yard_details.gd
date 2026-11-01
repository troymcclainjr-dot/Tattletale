extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Source-clipped gardens, original port cans, service bins and non-blocking litter.
## One vertex-color surface per resident cell. No per-piece draw nodes or ticks.
const DATA := "res://assets/data/pen_lucy_yards.json"
const CELL := 48.0
const CACHE_VERSION := 1
const CACHE_ROOT := "user://city_yard_cache"
var records: Array[Dictionary] = []
var _cells: Dictionary = {}
var _meshes: Dictionary = {}
var _template_normals: Dictionary = {}
var _audit: Dictionary = {}
var _material: StandardMaterial3D
var _setup_ms := 0
var _max_cell_build_ms := 0.0
var _cell_builds := 0
var _cache_directory := ""
var _cache_hits := 0
var _cache_errors := 0
var _pending := ""
var _pending_cell: Dictionary = {}
var _async_loads := 0
var _civic_signature := ""
var _max_activation_ms := 0.0
var _max_attach_ms := 0.0

func setup(level: Node3D) -> Dictionary:
	name = "CityYardDetails"
	var began := Time.get_ticks_msec()
	if not FileAccess.file_exists(DATA):
		return {"enabled": false, "reason": "yard metadata absent"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "missing yard metadata"}
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.91
	_material.metallic_specular = 0.18
	for key in data.templates:
		_meshes[key] = _decode_mesh(data.templates[key])
	_build_templates()
	for key in _meshes:
		_template_normals[key] = _meshes[key].surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	_audit = data.audit.duplicate(true)
	var source_index := -1
	var civic_removed := 0
	for entry in data.records:
		source_index += 1
		var clearance_radius := float(entry.get("radius", 0.4))
		if str(entry.kind).begins_with("hedge"):
			clearance_radius = Vector2(float(entry.scale[0]), float(entry.scale[2])).length() * 0.5
		if CivicClearance.record_removed(level, entry, clearance_radius):
			_civic_signature += str(source_index) + ","
			civic_removed += 1
			continue
		var record: Dictionary = entry.duplicate()
		record.position = level.vector(entry.position)
		record.scale = level.vector(entry.scale)
		var up: Vector3 = level.vector(entry.get("normal", [0, 1, 0]))
		var forward := Vector3(sin(float(entry.yaw)), 0, cos(float(entry.yaw))).slide(up).normalized()
		# Scale along the hedge's own frontage axes, not the world's X/Z axes.
		record.basis = Basis(up.cross(forward).normalized() * record.scale.x, up * record.scale.y, forward * record.scale.z)
		var cell := Vector2i(floori(record.position.x / CELL), floori(record.position.z / CELL))
		if not _cells.has(cell):
			_cells[cell] = {"origin": Vector3(cell.x * CELL, 0, cell.y * CELL), "indices": [], "node": null, "bodies": [], "mesh": null, "instance": null, "prefetch": false, "distance": INF, "path": "", "failed": false}
		_cells[cell].indices.append(records.size())
		records.append(record)
	_audit.civic_removed = civic_removed
	_audit.litter = records.filter(func(r: Dictionary): return r.kind in ["paper", "wrapper", "cardboard", "loose_can", "cup"]).size()
	_prepare_cache()
	set_process(false)
	_setup_ms = Time.get_ticks_msec() - began
	return get_status()

func _decode_mesh(data: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(0, data.vertices.size(), 3):
		vertices.append(Vector3(data.vertices[i], data.vertices[i + 1], data.vertices[i + 2]))
		normals.append(Vector3(data.normals[i], data.normals[i + 1], data.normals[i + 2]))
	for i in range(0, data.colors.size(), 4):
		colors.append(Color(data.colors[i], data.colors[i + 1], data.colors[i + 2], data.colors[i + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh

func _parts_mesh(parts: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var primitive: PrimitiveMesh = part[0]
		var arrays := primitive.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			surface.set_color(part[2])
			surface.set_normal(normals[index])
			surface.add_vertex(vertices[index] + part[1])
	surface.set_material(_material)
	return surface.commit()

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _build_templates() -> void:
	# No dumpster model exists in the port; palette and lid details match its cans.
	var dumpster_parts := [
		[_box(Vector3(1.8, 1.05, 1.05)), Vector3(0, 0.65, 0), Color("42604c")],
		[_box(Vector3(1.92, 0.12, 1.18)), Vector3(0, 1.22, 0), Color("303936")],
		[_box(Vector3(0.045, 0.03, 1.18)), Vector3(0, 1.295, 0), Color("1e2924")],
		[_box(Vector3(0.32, 0.12, 0.1)), Vector3(-0.50, 1.30, 0.35), Color("2e3d33")],
		[_box(Vector3(0.32, 0.12, 0.1)), Vector3(0.50, 1.30, 0.35), Color("2e3d33")],
		[_box(Vector3(0.23, 0.22, 0.25)), Vector3(-0.67, 0.11, 0.36), Color("292b29")],
		[_box(Vector3(0.23, 0.22, 0.25)), Vector3(0.67, 0.11, 0.36), Color("292b29")],
		[_box(Vector3(0.23, 0.22, 0.25)), Vector3(-0.67, 0.11, -0.36), Color("292b29")],
		[_box(Vector3(0.23, 0.22, 0.25)), Vector3(0.67, 0.11, -0.36), Color("292b29")],
		[_box(Vector3(0.45, 0.22, 0.015)), Vector3(0.35, 0.82, 0.533), Color("a2a28a")]]
	# Folded steel rim, pressed ribs and lid hinges read at walking distance.
	# Detail stays beneath the existing lid envelope; all cells share this mesh.
	dumpster_parts.append([_box(Vector3(1.84, 0.065, 1.09)), Vector3(0, 1.13, 0), Color("526d55")])
	for z in [-0.532, 0.532]:
		for x in [-0.68, -0.22, 0.68]:
			dumpster_parts.append([_box(Vector3(0.045, 0.72, 0.025)), Vector3(x, 0.67, z), Color("4a6752")])
	for x in [-0.57, 0.57]:
		dumpster_parts.append([_box(Vector3(0.18, 0.055, 0.075)), Vector3(x, 1.265, -0.54), Color("677167")])
	_meshes.dumpster = _parts_mesh(dumpster_parts)
	for part in [["paper", Vector3(0.25, 0.009, 0.18), Color("b8ad92")], ["wrapper", Vector3(0.15, 0.014, 0.1), Color("a99453")], ["cardboard", Vector3(0.39, 0.02, 0.30), Color("785438")]]:
		_meshes[part[0]] = _parts_mesh([[_box(part[1]), Vector3(0, part[1].y * 0.5, 0), part[2]]])
	for kind in ["loose_can", "cup"]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.035 if kind == "loose_can" else 0.045
		cylinder.bottom_radius = 0.035
		cylinder.height = 0.10
		cylinder.radial_segments = 7
		cylinder.rings = 1
		_meshes[kind] = _parts_mesh([[cylinder, Vector3(0, 0.05, 0), Color("506477") if kind == "loose_can" else Color("b1aa91")]])

func _prepare_cache() -> void:
	# Expensive assembly occurs only during setup, before gameplay. Cache keys
	# cover authored placement/template bytes and all mesh-building code.
	var signature := str(CACHE_VERSION) + "|" + FileAccess.get_sha256(DATA) + "|" + FileAccess.get_sha256(get_script().resource_path) + "|civic:" + _civic_signature
	_cache_directory = CACHE_ROOT.path_join(signature.sha256_text().substr(0, 24))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_cache_directory)) != OK:
		_cache_errors += 1
		push_error("Yard mesh cache directory unavailable")
		return
	for key in _cells:
		var cell: Dictionary = _cells[key]
		cell.path = _cache_directory.path_join("yard_%d_%d.res" % [key.x, key.y])
		if FileAccess.file_exists(cell.path):
			_cache_hits += 1
			continue
		var mesh := _make_cell_mesh(cell)
		if ResourceSaver.save(mesh, cell.path, ResourceSaver.FLAG_COMPRESS) != OK:
			cell.failed = true
			_cache_errors += 1
			push_error("Could not save yard cell: " + str(cell.path))
		# Only the serialized file remains. Far geometry is not retained in RAM.

func _make_cell_mesh(cell: Dictionary) -> ArrayMesh:
	var began := Time.get_ticks_usec()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corrected_normals := PackedVector3Array()
	for index in cell.indices:
		var record: Dictionary = records[index]
		var mesh: ArrayMesh = _meshes[record.kind]
		var pose := Transform3D(record.basis, record.position - cell.origin)
		surface.append_from(mesh, 0, pose)
		var normal_basis := pose.basis.inverse().transposed()
		for normal in _template_normals[record.kind]:
			corrected_normals.append((normal_basis * normal).normalized())
	var arrays := surface.commit_to_arrays()
	arrays[Mesh.ARRAY_NORMAL] = corrected_normals
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	combined.surface_set_material(0, _material)
	# Weld identical position/normal/color tuples offline. This preserves all
	# authored faces and lighting while reducing disk IO and GPU vertex uploads.
	var indexed := SurfaceTool.new()
	indexed.create_from(combined, 0)
	indexed.index()
	var result := indexed.commit()
	_cell_builds += 1
	_max_cell_build_ms = maxf(_max_cell_build_ms, float(Time.get_ticks_usec() - began) / 1000.0)
	return result

func _load_cell(cell: Dictionary) -> void:
	var began := Time.get_ticks_usec()
	var holder := Node3D.new()
	holder.name = "YardCell"
	holder.position = cell.origin
	add_child(holder)
	cell.node = holder
	# Collider readiness never waits for disk or visual uploads.
	for index in cell.indices:
		var record: Dictionary = records[index]
		if float(record.radius) <= 0.0:
			continue
		var body := StaticBody3D.new()
		body.name = "SolidYardBin"
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = record.position - cell.origin
		body.basis = record.basis
		body.set_meta("yard_bin", true)
		var collision := CollisionShape3D.new()
		if record.kind == "can":
			var shape := CylinderShape3D.new()
			shape.radius = 0.35
			shape.height = 1.14
			collision.shape = shape
			collision.position.y = 0.57
		else:
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.96, 1.38, 1.22)
			collision.shape = shape
			collision.position.y = 0.69
		body.add_child(collision)
		holder.add_child(body)
		cell.bodies.append(body)
	_attach_mesh(cell)
	_max_activation_ms = maxf(_max_activation_ms, float(Time.get_ticks_usec() - began) / 1000.0)

func _attach_mesh(cell: Dictionary) -> void:
	if cell.mesh == null or not is_instance_valid(cell.node) or is_instance_valid(cell.instance):
		return
	var began := Time.get_ticks_usec()
	var instance := MeshInstance3D.new()
	instance.mesh = cell.mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cell.node.add_child(instance)
	cell.instance = instance
	_max_attach_ms = maxf(_max_attach_ms, float(Time.get_ticks_usec() - began) / 1000.0)

func set_capture_presence(center: Vector3, render_center: Vector3, near_radius := 55.0, far_radius := 180.0) -> void:
	# Camera-only captures add detail residency without evicting player colliders.
	set_presence(center, near_radius, far_radius, render_center)

func set_presence(center: Vector3, _near_radius := 55.0, _far_radius := 180.0, render_center := Vector3.INF) -> void:
	for cell in _cells.values():
		var origin: Vector3 = cell.origin
		var nearest := Vector2(clampf(center.x, origin.x, origin.x + CELL), clampf(center.z, origin.z, origin.z + CELL))
		var distance := nearest.distance_to(Vector2(center.x, center.z))
		if render_center.is_finite():
			var camera_nearest := Vector2(clampf(render_center.x, origin.x, origin.x + CELL), clampf(render_center.z, origin.z, origin.z + CELL))
			distance = minf(distance, camera_nearest.distance_to(Vector2(render_center.x, render_center.z)))
		cell.distance = distance
		# Prefetch 45 m before the visible threshold. A 20 m margin avoids IO
		# churn; outside that bounded ring both visual and prefetched meshes go.
		cell.prefetch = distance < 150.0 or (cell.mesh != null and distance < 170.0)
		if distance < 105.0 and not is_instance_valid(cell.node):
			_load_cell(cell)
		elif distance > 130.0 and is_instance_valid(cell.node):
			for body in cell.bodies:
				body.collision_layer = 0
			cell.bodies.clear()
			cell.node.queue_free()
			cell.node = null
			cell.instance = null
		if not cell.prefetch:
			cell.mesh = null
	_request_next()
	set_process(not _pending.is_empty())

func _request_next() -> void:
	if not _pending.is_empty():
		return
	var selected: Dictionary = {}
	var nearest := INF
	for cell in _cells.values():
		if cell.prefetch and cell.mesh == null and not cell.failed and not str(cell.path).is_empty() and float(cell.distance) < nearest:
			selected = cell
			nearest = float(cell.distance)
	if selected.is_empty():
		return
	var error := ResourceLoader.load_threaded_request(selected.path, "ArrayMesh", false, ResourceLoader.CACHE_MODE_IGNORE)
	if error == OK:
		_pending = selected.path
		_pending_cell = selected
	else:
		selected.failed = true
		_cache_errors += 1
		push_error("Yard cell asynchronous request failed: " + str(selected.path))

func _process(_delta: float) -> void:
	if not _pending.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_pending)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var mesh = ResourceLoader.load_threaded_get(_pending)
			if mesh is ArrayMesh and _pending_cell.prefetch:
				_pending_cell.mesh = mesh
				_attach_mesh(_pending_cell)
				_async_loads += 1
			elif not mesh is ArrayMesh:
				_pending_cell.failed = true
				_cache_errors += 1
				push_error("Cached yard resource is not an ArrayMesh: " + _pending)
			_pending = ""
			_pending_cell = {}
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending_cell.failed = true
			_cache_errors += 1
			push_error("Yard cell asynchronous load failed: " + _pending)
			_pending = ""
			_pending_cell = {}
	_request_next()
	if _pending.is_empty():
		set_process(false)

func _exit_tree() -> void:
	# Teardown alone may wait; normal travel never consumes an unfinished load.
	if not _pending.is_empty():
		ResourceLoader.load_threaded_get(_pending)
		_pending = ""

func is_clear(point: Vector3, radius: float) -> bool:
	# Records remain available for NPC reservations even when their cell is unloaded.
	var reach := radius + 1.5
	for x in range(floori((point.x - reach) / CELL), floori((point.x + reach) / CELL) + 1):
		for z in range(floori((point.z - reach) / CELL), floori((point.z + reach) / CELL) + 1):
			var cell: Dictionary = _cells.get(Vector2i(x, z), {})
			for index in cell.get("indices", []):
				var record: Dictionary = records[index]
				if float(record.radius) <= 0.0:
					continue
				if Vector2(point.x - record.position.x, point.z - record.position.z).length() < radius + float(record.radius):
					return false
	return true

func get_status() -> Dictionary:
	var active := 0
	var bodies := 0
	var visuals := 0
	var cached := 0
	for cell in _cells.values():
		if is_instance_valid(cell.node):
			active += 1
			bodies += cell.bodies.size()
			visuals += int(is_instance_valid(cell.instance))
		cached += int(cell.mesh != null)
	return {"enabled": not records.is_empty(), "records": records.size(), "cells": _cells.size(), "active_batches": visuals, "active_cells": active, "near_cells_missing": active - visuals, "cached_cells": cached,
		"active_bin_colliders": bodies, "litter_colliders": 0, "shared_meshes": _meshes.size(),
		"setup_ms": _setup_ms, "cache_hits": _cache_hits, "cache_errors": _cache_errors, "async_loads": _async_loads, "pending_loads": int(not _pending.is_empty()), "max_activation_ms": _max_activation_ms, "max_attach_ms": _max_attach_ms, "max_cell_build_ms": _max_cell_build_ms, "cell_builds": _cell_builds, "audit": _audit}
