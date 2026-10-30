extends Node3D
## Fictional business fronts and street wear anchored to surveyed collision.
## Immutable records survive cell unloading; shared meshes stay small and reusable.
const CELL := 70.0
const MAIL_LIMIT := 36
const DOT_LIMIT := 1200
const POTHOLE_LIMIT := 24
const CROSSING_LIMIT := 20
const ROAD_MATERIAL := preload("res://assets/materials/city_road_wear.gdshader")
var level: Node3D
var records: Array[Dictionary] = []
var _cells: Dictionary = {}
var _meshes: Dictionary = {}
var _counts: Dictionary = {}
var _business_cells: Dictionary = {}
var _mail_cells: Dictionary = {}
var _crossings: Array[Vector3] = []
var _focus := Vector3.ZERO
var _far_radius := 180.0
var _setup_ms := 0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "NeighborhoodDetails"
	var began := Time.get_ticks_msec()
	_meshes.mailbox = _mail_mesh(false)
	_meshes.postal_drop = _mail_mesh(true)
	var road := PlaneMesh.new()
	road.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = ROAD_MATERIAL
	road.material = material
	_meshes.road = road
	var samples: Array[Dictionary] = level.npcs.crowd._street_samples()
	_build_crossings()
	# Shop architecture is built into the city mesh. Runtime adds only the text
	# on its authored fascia; it never covers residential doors/windows.
	for business in level.level_data.get("businesses", []):
		_add_built_business(business)
	for sample in samples:
		var center: Vector3 = sample.center
		var cell := _cell(center)
		if int(_counts.get("mailbox", 0)) + int(_counts.get("postal_drop", 0)) < MAIL_LIMIT and not _mail_cells.has(cell):
			for side in [1.0, -1.0]:
				var desired: Vector3 = center + sample.across * side * (float(sample.half) + 1.6)
				var found: Dictionary = level.npcs._safe_candidate(desired, 0.34)
				if not found.is_empty() and _record_clear(found.position, 2.0):
					var drop: bool = _mail_cells.size() % 3 == 0
					_add_mail(found.position, atan2(-sample.across.x * side, -sample.across.z * side), drop)
					_mail_cells[cell] = true
					break
		if _near_crossing(center, 8.0):
			continue
		var tangent := Vector3(sample.across.z, 0, -sample.across.x)
		if int(_counts.get("road_dot", 0)) < DOT_LIMIT - 1:
			for side in [-1.0, 1.0]:
				_add_road(center + sample.across * side * 0.15, tangent, Vector2(0.13, 0.28), "road_dot", Color("c7a451"))
		if int(_counts.get("pothole", 0)) < POTHOLE_LIMIT and posmod(roundi(center.x * 13.0 + center.z * 7.0), 17) == 0:
			_add_road(center + sample.across * float(sample.half) * 0.48, tangent, Vector2(0.85, 1.25), "pothole", Color.WHITE)
	# Build only the nearby cell instances. Far records need no nodes or colliders.
	set_presence(level.player.global_position)
	_setup_ms = Time.get_ticks_msec() - began

func _add_built_business(entry: Dictionary) -> void:
	var at: Vector3 = level.vector(entry.get("sign_position", entry.get("front_position", [0, 0, 0])))
	var normal: Vector3 = level.vector(entry.get("normal", [0, 0, 1])).normalized()
	_add_record({"kind": "business", "mesh": "", "position": at, "normal": normal,
		"text": str(entry.get("name", "Neighborhood shop")) + "\n" + str(entry.get("subtitle", "")),
		"street": str(entry.get("street", "")), "source": str(entry.get("source_mesh", "")),
		"shop_type": entry.get("type", "shop"), "floor_y": level.vector(entry.get("door_position", [0, 0, 0])).y,
		"label_width": float(entry.get("sign_width", 3.5)), "fixture": false})

func _cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))

func _record_clear(at: Vector3, radius: float, reserve_shop_entrances := true) -> bool:
	for record in records:
		if record.kind in ["mailbox", "postal_drop"] and at.distance_to(record.position) < radius:
			return false
		if record.kind == "entrance_walk" and at.distance_to(record.position) < 0.8:
			return false
		if reserve_shop_entrances and record.kind == "business":
			var offset: Vector3 = at - record.position
			var normal: Vector3 = record.normal
			if offset.dot(normal) > 0.0 and offset.dot(normal) < 2.3 + radius and absf(offset.dot(Vector3.UP.cross(normal))) < 1.6 + radius:
				return false
	return true

func _add_mail(at: Vector3, yaw: float, drop: bool) -> void:
	var kind := "postal_drop" if drop else "mailbox"
	_add_record({"kind": kind, "mesh": kind, "position": at, "basis": Basis(Vector3.UP, yaw), "color": Color.WHITE, "normal": Vector3(sin(yaw), 0, cos(yaw)), "fixture": true})

func _add_road(at: Vector3, tangent: Vector3, size: Vector2, kind: String, color: Color) -> void:
	var ground: Dictionary = level.ground_at(at)
	if ground.is_empty() or ground.normal.y < 0.92:
		return
	var normal: Vector3 = ground.normal
	var forward := tangent.slide(normal).normalized()
	var right := normal.cross(forward).normalized()
	_add_record({"kind": kind, "mesh": "road", "position": ground.position + normal * 0.013, "basis": Basis(right * size.x, normal, forward * size.y), "color": color, "fixture": false})

func _build_crossings() -> void:
	var junctions: Dictionary = {}
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for endpoint in [0, points.size() - 1]:
			if points.size() < 2:
				continue
			var at: Vector3 = level.vector(points[endpoint])
			var key := "%d_%d" % [roundi(at.x), roundi(at.z)]
			if not junctions.has(key):
				junctions[key] = []
			var other: Vector3 = level.vector(points[1 if endpoint == 0 else points.size() - 2])
			junctions[key].append({"position": at, "name": str(road.get("name", "")), "tangent": Vector3(other.x - at.x, 0, other.z - at.z).normalized(), "width": float(road.get("width", 9.5))})
	for entries in junctions.values():
		if _crossings.size() >= CROSSING_LIMIT or entries.size() < 2:
			continue
		var first: Dictionary = entries[0]
		var names: Dictionary = {}
		for entry in entries:
			names[entry.name] = true
		if names.size() < 2 or _near_crossing(first.position, 18.0):
			continue
		_crossings.append(first.position)
		var forward: Vector3 = first.tangent
		var across := Vector3(-forward.z, 0, forward.x)
		var count := maxi(4, floori((float(first.width) - 1.0) / 0.9))
		for stripe in count:
			var at: Vector3 = first.position + forward * 7.5 + across * (float(stripe) - (count - 1) * 0.5) * 0.9
			_add_road(at, forward, Vector2(0.43, 2.35), "crosswalk_stripe", Color("c8c2ad"))

func _near_crossing(at: Vector3, radius: float) -> bool:
	for crossing in _crossings:
		if Vector2(at.x - crossing.x, at.z - crossing.z).length() < radius:
			return true
	return false

func _add_record(record: Dictionary) -> void:
	var cell := _cell(record.position)
	if not _cells.has(cell):
		_cells[cell] = {"cell": cell, "center": Vector3((cell.x + 0.5) * CELL, 0, (cell.y + 0.5) * CELL), "indices": [], "node": null, "nodes": [], "bodies": []}
	_cells[cell].indices.append(records.size())
	records.append(record)
	_counts[record.kind] = int(_counts.get(record.kind, 0)) + 1

func _mail_mesh(drop: bool) -> ArrayMesh:
	var parts := []
	if drop:
		parts = [[Vector3(0.58, 0.95, 0.48), Vector3(0, 0.73, 0), Color("304e6e")], [Vector3(0.64, 0.15, 0.53), Vector3(0, 1.26, 0), Color("3b5977")], [Vector3(0.41, 0.055, 0.02), Vector3(0, 1.13, 0.25), Color("161f26")], [Vector3(0.32, 0.19, 0.015), Vector3(0, 0.88, 0.251), Color("c4c8be")]]
		for x in [-0.22, 0.22]:
			parts.append([Vector3(0.08, 0.3, 0.4), Vector3(x, 0.15, 0), Color("293843")])
	else:
		parts = [[Vector3(0.09, 0.95, 0.09), Vector3(0, 0.475, 0), Color("62584b")], [Vector3(0.34, 0.30, 0.47), Vector3(0, 1.04, 0), Color("73766c")], [Vector3(0.27, 0.21, 0.02), Vector3(0, 1.03, 0.244), Color("444e48")], [Vector3(0.04, 0.17, 0.11), Vector3(0.19, 1.17, 0), Color("923f32")]]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			surface.set_color(part[2])
			surface.set_normal(normals[index])
			surface.add_vertex(vertices[index] + part[1])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.93
	surface.set_material(material)
	return surface.commit()

func _load_cell(cell: Dictionary) -> void:
	if is_instance_valid(cell.node):
		return
	var holder := Node3D.new()
	holder.name = "DetailCell_%d_%d" % [cell.cell.x, cell.cell.y]
	holder.position = cell.center
	add_child(holder)
	cell.node = holder
	cell.nodes.append(holder)
	var groups: Dictionary = {}
	for index in cell.indices:
		var record: Dictionary = records[index]
		if not str(record.mesh).is_empty():
			if not groups.has(record.mesh):
				groups[record.mesh] = []
			groups[record.mesh].append(record)
		if record.has("text"):
			var label := Label3D.new()
			label.text = record.text
			label.font_size = 40
			label.pixel_size = 0.00125 if bool(record.get("small_text", false)) else 0.0036
			if record.has("label_width"):
				var lines: PackedStringArray = str(record.text).split("\n")
				var widest := 1.0
				for line in lines:
					widest = maxf(widest, ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x)
				label.pixel_size = minf(0.0036, float(record.label_width) * 0.88 / widest)
			label.outline_size = 3
			label.modulate = Color("f3e6c4")
			label.position = record.position - cell.center + record.normal * 0.06
			label.basis = Basis(Vector3.UP.cross(record.normal).normalized(), Vector3.UP, record.normal)
			label.visibility_range_end = 65.0
			holder.add_child(label)
		if bool(record.fixture):
			var body := StaticBody3D.new()
			body.name = "SolidPostalFixture"
			body.set_meta("postal_fixture", record.kind in ["mailbox", "postal_drop"])
			body.position = record.position - cell.center
			body.basis = record.get("collision_basis", record.basis)
			body.collision_layer = 2
			body.collision_mask = 0
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = record.get("solid_size", Vector3(0.66, 1.35, 0.55) if record.kind == "postal_drop" else Vector3(0.40, 1.28, 0.50))
			collision.shape = shape
			collision.position = record.get("solid_center", Vector3(0, shape.size.y * 0.5, 0))
			body.add_child(collision)
			holder.add_child(body)
			cell.bodies.append(body)
	for key in groups:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = _meshes[key]
		multi.instance_count = groups[key].size()
		for i in groups[key].size():
			var record: Dictionary = groups[key][i]
			multi.set_instance_transform(i, Transform3D(record.basis, record.position - cell.center))
			multi.set_instance_color(i, record.color)
			multi.set_instance_custom_data(i, Color(float(record.get("style", 2.0 if record.kind == "pothole" else 0.0)), 0, 0, 1))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(instance)

func set_presence(center: Vector3, _near_radius := 55.0, far_radius := 180.0) -> void:
	_focus = center
	_far_radius = maxf(far_radius, 90.0)
	for cell in _cells.values():
		var distance := Vector2(center.x - cell.center.x, center.z - cell.center.z).length()
		if distance < _far_radius + CELL:
			_load_cell(cell)
		elif distance > _far_radius + CELL * 1.5 and is_instance_valid(cell.node):
			for body in cell.bodies:
				body.collision_layer = 0
			cell.node.queue_free()
			cell.node = null
			cell.nodes.clear()
			cell.bodies.clear()

func get_streaming_cells() -> Array:
	return _cells.values()

func get_business_fronts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		if record.kind == "business":
			result.append({"name": record.text, "position": record.position, "normal": record.normal, "street": record.street, "source": record.source, "type": record.shop_type})
	return result

func get_status() -> Dictionary:
	var active := 0
	var batches := 0
	var fixtures := 0
	var postal_cells: Dictionary = {}
	var business_cells: Dictionary = {}
	var min_at := Vector3.INF
	var max_at := -Vector3.INF
	for record in records:
		min_at = min_at.min(record.position)
		max_at = max_at.max(record.position)
		if record.kind == "business":
			business_cells[_cell(record.position)] = true
		elif record.kind in ["mailbox", "postal_drop"]:
			postal_cells[_cell(record.position)] = true
	for cell in _cells.values():
		if is_instance_valid(cell.node):
			active += 1
			for body in cell.bodies:
				fixtures += int(bool(body.get_meta("postal_fixture", false)))
			for child in cell.node.get_children():
				batches += int(child is MultiMeshInstance3D)
	return {"counts": _counts.duplicate(), "records": records.size(), "crossings": _crossings.size(), "cells": _cells.size(), "business_cells": business_cells.size(), "postal_cells": postal_cells.size(), "span_x": max_at.x - min_at.x, "span_z": max_at.z - min_at.z, "active_cells": active, "active_batches": batches, "active_postal_colliders": fixtures, "shared_meshes": _meshes.size(), "setup_ms": _setup_ms, "fictional_businesses": true}
