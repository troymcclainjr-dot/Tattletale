extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Fictional utility poles on source-checked curb strips. Decoration has no
## collision, per-pole nodes, lights, physics queries, or per-frame processing.
const DATA := "res://assets/data/pen_lucy_power.json"
const CONNECTIONS := "res://assets/data/pen_lucy_power_connections.json"
const CELL := 72.0
const WIRE_HEIGHT := 9.2
const SAG := 0.65
var records: Array = []
var spans: Array = []
var _cells: Dictionary = {}
var _audit: Dictionary = {}
var _pole_mesh: ArrayMesh
var _pole_variants: Dictionary = {}
var _transformer_count := 0
var _wire_material: StandardMaterial3D
var _setup_ms := 0
var _visible_cells := 0
var _vertex_count := 0

func setup(_level: Node3D) -> Dictionary:
	name = "CityPowerGrid"
	set_process(false)
	var began := Time.get_ticks_msec()
	if not FileAccess.file_exists(DATA):
		return {"enabled": false, "reason": "Power metadata absent"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "Power metadata invalid"}
	var remap: Dictionary = {}
	for index in data.poles.size():
		var pole: Dictionary = data.poles[index]
		if CivicClearance.record_removed(_level, pole, 0.35):
			continue
		remap[index] = records.size()
		records.append(pole)
	var source_spans: Array = data.spans.duplicate(true)
	if FileAccess.file_exists(CONNECTIONS):
		var connections = JSON.parse_string(FileAccess.get_file_as_string(CONNECTIONS))
		if connections is Dictionary and str(connections.get("source_sha256", "")) == FileAccess.get_sha256(DATA):
			source_spans.append_array(connections.get("spans", []))
	var seen_edges: Dictionary = {}
	for source_span in source_spans:
		var edge := Vector2i(mini(int(source_span.a), int(source_span.b)), maxi(int(source_span.a), int(source_span.b)))
		if edge.x == edge.y or seen_edges.has(edge) or float(source_span.get("min_clearance_m", 0.0)) < 7.2:
			continue
		seen_edges[edge] = true
		if not remap.has(int(source_span.a)) or not remap.has(int(source_span.b)):
			continue
		var a := _point(data.poles[int(source_span.a)].position)
		var b := _point(data.poles[int(source_span.b)].position)
		if CivicClearance.segment_blocked(_level, a, b, 1.0):
			continue
		var span: Dictionary = source_span.duplicate()
		span.a = remap[int(source_span.a)]
		span.b = remap[int(source_span.b)]
		spans.append(span)
	_prune_and_equip()
	_audit = data.audit.duplicate(true)
	_audit.civic_removed_poles = data.poles.size() - records.size()
	_audit.source_spans = source_spans.size()
	_audit.filtered_spans = source_spans.size() - spans.size()
	_audit.isolated_poles = 0
	_audit.transformers = _transformer_count
	for transformer in [false, true]:
		for terminal in [false, true]:
			_pole_variants["%s_%s" % [transformer, terminal]] = _make_pole(transformer, terminal)
	_pole_mesh = _pole_variants["false_false"]
	_wire_material = StandardMaterial3D.new()
	_wire_material.albedo_color = Color("353634")
	_wire_material.roughness = 0.95
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in records.size():
		var at := _point(records[index].position)
		_cell(at).poles.append(index)
	for span in spans:
		var a := _point(records[int(span.a)].position)
		var b := _point(records[int(span.b)].position)
		_cell((a + b) * 0.5).spans.append(span)
	for cell in _cells.values():
		_build_cell(cell)
	_setup_ms = Time.get_ticks_msec() - began
	return get_status()

func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _cell(at: Vector3) -> Dictionary:
	var key := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _cells.has(key):
		_cells[key] = {"origin": Vector3((key.x + 0.5) * CELL, 0, (key.y + 0.5) * CELL), "poles": [], "spans": [], "node": null}
	return _cells[key]

func _make_pole(transformer := false, terminal := false) -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.96
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.bottom_radius = 0.17
	pole.top_radius = 0.105
	pole.height = 9.6
	pole.radial_segments = 7
	pole.rings = 1
	_append_primitive(surface, pole, Vector3(0, 4.8, 0), Color("765e45"))
	var arm := BoxMesh.new()
	arm.size = Vector3(2.0, 0.16, 0.16)
	_append_primitive(surface, arm, Vector3(0, 8.93, 0), Color("645744"))
	for offset in [-0.77, 0.0, 0.77]:
		var insulator := CylinderMesh.new()
		insulator.top_radius = 0.09
		insulator.bottom_radius = 0.1
		insulator.height = 0.22
		insulator.radial_segments = 6
		insulator.rings = 1
		_append_primitive(surface, insulator, Vector3(offset, 9.12, 0), Color("96aaa4"))
		# Two porcelain skirts give the insulator a readable electrical profile.
		var skirt := CylinderMesh.new()
		skirt.top_radius = 0.075
		skirt.bottom_radius = 0.12
		skirt.height = 0.035
		skirt.radial_segments = 6
		skirt.rings = 1
		for y in [9.07, 9.17]:
			_append_primitive(surface, skirt, Vector3(offset, y, 0), Color("b0bdb2"))
	if terminal:
		var conduit := CylinderMesh.new()
		conduit.bottom_radius = 0.075
		conduit.top_radius = 0.075
		conduit.height = 8.7
		conduit.radial_segments = 6
		_append_primitive(surface, conduit, Vector3(0, 4.35, 0.20), Color("56615e"))
		# Separate insulated entries into a termination box; the three primary
		# phases must not appear to short together at a single exposed junction.
		var termination := BoxMesh.new()
		termination.size = Vector3(0.34, 0.24, 0.25)
		_append_primitive(surface, termination, Vector3(0, 8.7, 0.20), Color("596561"))
		surface.set_color(Color("353634"))
		for x in [-0.77, 0.0, 0.77]:
			_tube(surface, Vector3(x, WIRE_HEIGHT, 0), Vector3(float(x) * 0.15, 8.82, 0.20))
	if transformer:
		var can := CylinderMesh.new()
		can.bottom_radius = 0.28
		can.top_radius = 0.28
		can.height = 0.88
		can.radial_segments = 12
		can.rings = 1
		_append_primitive(surface, can, Vector3(0, 7.25, 0.40), Color("8b9691"))
		var band := BoxMesh.new()
		band.size = Vector3(0.55, 0.085, 0.58)
		for y in [6.92, 7.54]:
			_append_primitive(surface, band, Vector3(0, y, 0.17), Color("535e5a"))
		var bushing := CylinderMesh.new()
		bushing.bottom_radius = 0.07
		bushing.top_radius = 0.055
		bushing.height = 0.19
		bushing.radial_segments = 6
		bushing.rings = 1
		_append_primitive(surface, bushing, Vector3(0, 7.78, 0.40), Color("b8b3a1"))
		surface.set_color(Color("353634"))
		_tube(surface, Vector3(0, WIRE_HEIGHT, 0), Vector3(0.20, 8.45, 0.40))
		_tube(surface, Vector3(0.20, 8.45, 0.40), Vector3(0, 7.88, 0.40))
		var secondary := CylinderMesh.new()
		secondary.bottom_radius = 0.025
		secondary.top_radius = 0.025
		secondary.height = 6.85
		secondary.radial_segments = 5
		secondary.rings = 1
		_append_primitive(surface, secondary, Vector3(0.18, 3.425, 0.19), Color("444c49"))
		_tube(surface, Vector3(0.18, 6.85, 0.19), Vector3(0.18, 7.0, 0.40))
	surface.set_material(material)
	return surface.commit()

func _append_primitive(surface: SurfaceTool, primitive: PrimitiveMesh, offset: Vector3, color: Color) -> void:
	var arrays := primitive.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(color)
		surface.set_normal(normals[index])
		surface.add_vertex(vertices[index] + offset)

func _build_cell(cell: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "UtilityCell_%d_%d" % [cell.origin.x, cell.origin.z]
	node.position = cell.origin
	add_child(node)
	cell.node = node
	cell.pole_node = Node3D.new()
	node.add_child(cell.pole_node)
	cell.wires = null
	var groups: Dictionary = {}
	for index in cell.poles:
		var record: Dictionary = records[index]
		var key := "%s_%s" % [record.transformer, record.terminal]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(record)
	for key in groups:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = _pole_variants[key]
		batch.instance_count = groups[key].size()
		for i in groups[key].size():
			var record: Dictionary = groups[key][i]
			batch.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(record.yaw)), _point(record.position) - cell.origin))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cell.pole_node.add_child(instance)
	if not cell.spans.is_empty():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for span in cell.spans:
			var first: Dictionary = records[int(span.a)]
			var last: Dictionary = records[int(span.b)]
			var first_right := Basis(Vector3.UP, float(first.yaw)) * Vector3.RIGHT
			var last_right := Basis(Vector3.UP, float(last.yaw)) * Vector3.RIGHT
			var polarity := 1.0 if first_right.dot(last_right) >= 0.0 else -1.0
			for conductor in [-0.77, 0.0, 0.77]:
				var a: Vector3 = _point(first.position) - cell.origin + Vector3.UP * WIRE_HEIGHT + Basis(Vector3.UP, float(first.yaw)) * Vector3(conductor, 0, 0)
				var b: Vector3 = _point(last.position) - cell.origin + Vector3.UP * WIRE_HEIGHT + Basis(Vector3.UP, float(last.yaw)) * Vector3(float(conductor) * polarity, 0, 0)
				for segment in 8:
					var t := float(segment) / 8.0
					var u := float(segment + 1) / 8.0
					_tube(surface, a.lerp(b, t) - Vector3.UP * SAG * 4 * t * (1 - t), a.lerp(b, u) - Vector3.UP * SAG * 4 * u * (1 - u))
		surface.set_material(_wire_material)
		var instance := MeshInstance3D.new()
		instance.mesh = surface.commit()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
		cell.wires = instance
	cell.pole_node.visible = false
	if cell.wires != null:
		cell.wires.visible = false

func _tube(surface: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var direction := (b - a).normalized()
	var right := direction.cross(Vector3.UP).normalized() * 0.024
	var up := right.normalized().cross(direction) * 0.024
	var offsets := [right, up, -right, -up]
	for side in 4:
		var p: Vector3 = offsets[side]
		var q: Vector3 = offsets[(side + 1) % 4]
		surface.set_normal((p + q).normalized())
		for vertex in [a + p, b + p, b + q, a + p, b + q, a + q]:
			surface.add_vertex(vertex)
			_vertex_count += 1

func set_presence(focus: Vector3, _near_radius := 55.0, far_radius := 230.0) -> void:
	_visible_cells = 0
	var radius := far_radius + CELL * 0.71 + 30.0
	var visible_spans: Array = []
	for cell in _cells.values():
		var offset: Vector3 = cell.origin - focus
		var visible := Vector2(offset.x, offset.z).length_squared() <= radius * radius
		cell.pole_node.visible = visible
		if cell.wires != null:
			cell.wires.visible = visible
		if visible:
			visible_spans.append_array(cell.spans)
	# Only the supports inherit span visibility: revealing a pole cell must not
	# recursively reveal that cell's other wires across the entire network.
	for span in visible_spans:
		_cell(_point(records[int(span.a)].position)).pole_node.visible = true
		_cell(_point(records[int(span.b)].position)).pole_node.visible = true
	for cell in _cells.values():
		_visible_cells += int(cell.pole_node.visible or (cell.wires != null and cell.wires.visible))

func get_status() -> Dictionary:
	return {"enabled": not records.is_empty(), "poles": records.size(), "spans": spans.size(), "cells": _cells.size(), "visible_cells": _visible_cells, "wire_vertices": _vertex_count, "setup_ms": _setup_ms, "collision_bodies": 0, "shadow_casters": 0, "per_frame_processing": false, "audit": _audit}

func _prune_and_equip() -> void:
	var degree: Dictionary = {}
	for span in spans:
		degree[int(span.a)] = int(degree.get(int(span.a), 0)) + 1
		degree[int(span.b)] = int(degree.get(int(span.b), 0)) + 1
	var retained: Array = []
	var remap: Dictionary = {}
	var transformers: Array[Vector3] = []
	for i in records.size():
		if not degree.has(i):
			continue
		var record: Dictionary = records[i].duplicate()
		record.terminal = int(degree[i]) == 1
		record.transformer = false
		var at := _point(record.position)
		var separated := true
		for previous in transformers:
			if Vector2(at.x - previous.x, at.z - previous.z).length() < 110.0:
				separated = false
				break
		if separated and int(degree[i]) >= 2:
			record.transformer = true
			transformers.append(at)
		remap[i] = retained.size()
		retained.append(record)
	for span in spans:
		span.a = remap[int(span.a)]
		span.b = remap[int(span.b)]
	records = retained
	_transformer_count = transformers.size()
