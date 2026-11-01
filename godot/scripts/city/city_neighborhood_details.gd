extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Fictional business fronts and street wear anchored to surveyed collision.
## Immutable records survive cell unloading; shared meshes stay small and reusable.
const CELL := 70.0
const MAIL_LIMIT := 24
const POSTAL_LIMIT := 28
const HYDRANT_LIMIT := 46
const Dressing := preload("res://scripts/city/city_dressing.gd")
const DOT_LIMIT := 1200
const POTHOLE_LIMIT := 24
const CROSSING_LIMIT := 48
const Surfaces := preload("res://scripts/city/city_street_surfaces.gd")
const ROAD_MATERIAL := preload("res://assets/materials/city_road_wear.gdshader")
var level: Node3D
var records: Array[Dictionary] = []
var _cells: Dictionary = {}
var _meshes: Dictionary = {}
var _counts: Dictionary = {}
var _business_cells: Dictionary = {}
var _mail_cells: Dictionary = {}
var _crossings: Array[Vector3] = []
var _crossing_details: Array[Dictionary] = []
var _focus := Vector3.ZERO
var _far_radius := 180.0
var _setup_ms := 0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "NeighborhoodDetails"
	var began := Time.get_ticks_msec()
	_meshes.mailbox = _mail_mesh(false)
	_meshes.postal_drop = _mail_mesh(true)
	_load_utility_meshes()
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
	_build_utilities(samples)
	for sample in samples:
		var center: Vector3 = sample.center
		if _near_crossing(center, 8.0):
			continue
		var tangent := Vector3(sample.across.z, 0, -sample.across.x)
		if int(_counts.get("road_dot", 0)) < DOT_LIMIT - 1:
			for side in [-1.0, 1.0]:
				_add_road(center + sample.across * side * 0.18, tangent, Vector2(0.18, 1.20), "road_dot", Color("e0b736"))
		if int(_counts.get("pothole", 0)) < POTHOLE_LIMIT and posmod(roundi(center.x * 13.0 + center.z * 7.0), 17) == 0:
			_add_road(center + sample.across * float(sample.half) * 0.48, tangent, Vector2(0.85, 1.25), "pothole", Color.WHITE)
	# Build only the nearby cell instances. Far records need no nodes or colliders.
	set_presence(level.player.global_position)
	_setup_ms = Time.get_ticks_msec() - began

func _add_built_business(entry: Dictionary) -> void:
	var at: Vector3 = level.vector(entry.get("sign_position", entry.get("front_position", [0, 0, 0])))
	var normal: Vector3 = level.vector(entry.get("normal", [0, 0, 1])).normalized()
	var floor_y: float = level.vector(entry.get("door_position", [0, 0, 0])).y
	var kit := str(entry.get("kit", ""))
	var title := str(entry.get("name", "Neighborhood shop"))
	var label_height := 0.0
	if not kit.is_empty():
		# The new shop fascias carry one strong, legible name, like the reference
		# markets. Fit the actual sign band instead of capping every shop at 14 cm.
		title = title.to_upper()
		var band_height := 0.70
		if kit == "mini_mart":
			band_height = 2.0 * (at.y - floor_y - 2.6) - 0.30
		elif kit == "shuttered":
			band_height = 2.0 * (at.y - floor_y - 2.6) - 0.20
		label_height = minf(0.65, maxf(0.25, band_height) * 0.72)
	else:
		title += "\n" + str(entry.get("subtitle", ""))
	_add_record({"kind": "business", "mesh": "", "position": at, "normal": normal,
		"text": title, "label_height": label_height,
		"text_color": str(entry.get("sign_text_color", "f3e6c4")),
		"street": str(entry.get("street", "")), "source": str(entry.get("source_mesh", "")),
		"shop_type": entry.get("type", "shop"), "floor_y": floor_y,
		"label_width": float(entry.get("sign_width", 3.5)), "fixture": false})

func _cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))

func _record_clear(at: Vector3, radius: float, reserve_shop_entrances := true) -> bool:
	if CivicClearance.blocked(level, at, radius):
		return false
	for crossing in _crossing_details:
		for landing in [crossing.landing_a, crossing.landing_b]:
			if Vector2(at.x - landing.x, at.z - landing.z).length() < radius + 0.65:
				return false
	for record in records:
		if record.kind in ["mailbox", "postal_drop", "hydrant"] and at.distance_to(record.position) < radius:
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
	_add_record({"kind": kind, "mesh": "road", "position": ground.position + normal * 0.013, "basis": Basis(right * size.x, normal, forward * size.y), "color": color, "style": 1.0 if kind == "road_dot" else (2.0 if kind == "pothole" else 0.0), "fixture": false})

func _build_crossings() -> void:
	var junctions: Dictionary = {}
	# Shared interior polyline vertices matter as much as endpoints: many side
	# streets join a long arterial halfway along its exported road record.
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for i in points.size():
			var at: Vector3 = level.vector(points[i])
			var key := "%d_%d" % [roundi(at.x * 10), roundi(at.z * 10)]
			if not junctions.has(key):
				junctions[key] = {"position": at, "names": {}, "approaches": [], "width": 0.0}
			var node: Dictionary = junctions[key]
			node.names[str(road.get("name", ""))] = true
			node.width = maxf(node.width, float(road.width))
			for neighbor in [i - 1, i + 1]:
				if neighbor < 0 or neighbor >= points.size():
					continue
				var other: Vector3 = level.vector(points[neighbor])
				var tangent := Vector3(other.x - at.x, 0, other.z - at.z).normalized()
				var duplicate := false
				for approach in node.approaches:
					if tangent.dot(approach.tangent) > 0.98:
						duplicate = true
						break
				if not duplicate:
					node.approaches.append({"tangent": tangent, "width": float(road.width), "street": str(road.name)})
	var keys: Array = junctions.keys()
	keys.sort()
	for key in keys:
		var node: Dictionary = junctions[key]
		if _crossings.size() >= CROSSING_LIMIT or node.names.size() < 2:
			continue
		# One supported crossing per junction spreads coverage across the map.
		# Prefer the narrower road, reducing exposed walking distance.
		node.approaches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.width) < float(b.width))
		for approach in node.approaches:
			if _try_crossing(node, approach, str(key)):
				break

func _crossing_landing(at: Vector3) -> Dictionary:
	if not Surfaces.circle_clear("sidewalk", at, 0.32):
		return {}
	var ground: Dictionary = level.ground_at(at)
	if ground.is_empty() or ground.normal.y < 0.90:
		return {}
	at.y = ground.position.y
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.85
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = at + Vector3.UP * 0.96
	query.collision_mask = 2
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": at}

func _try_crossing(node: Dictionary, approach: Dictionary, id: String) -> bool:
	var forward: Vector3 = approach.tangent
	var across := Vector3(-forward.z, 0, forward.x)
	var width: float = float(approach.width)
	for extra in [2.2, 3.7, 5.2, 6.7]:
		var center: Vector3 = node.position + forward * (float(node.width) * 0.5 + float(extra))
		if _near_crossing(center, 15.0):
			continue
		var a := _crossing_landing(center + across * (width * 0.5 + 0.70))
		var b := _crossing_landing(center - across * (width * 0.5 + 0.70))
		if a.is_empty() or b.is_empty():
			continue
		var count := maxi(4, floori((width - 1.0) / 0.9))
		var stripes: Array[Vector3] = []
		for stripe in count:
			var at := center + across * (float(stripe) - (count - 1) * 0.5) * 0.9
			if not Surfaces.rectangle_clear("road", at, across, forward, Vector2(0.215, 1.175)):
				break
			var ground: Dictionary = level.ground_at(at)
			if ground.is_empty() or ground.normal.y < 0.92:
				break
			stripes.append(at)
		if stripes.size() != count:
			continue
		_crossings.append(center)
		_crossing_details.append({"id": id, "position": center, "forward": forward, "across": across,
			"street": str(approach.street), "width": width, "landing_a": a.position, "landing_b": b.position,
			"stripes": count, "surface_checked": true})
		for at in stripes:
			_add_road(at, forward, Vector2(0.43, 2.35), "crosswalk_stripe", Color("e1dccb"))
		return true
	return false

func _near_crossing(at: Vector3, radius: float) -> bool:
	for crossing in _crossings:
		if Vector2(at.x - crossing.x, at.z - crossing.z).length() < radius:
			return true
	return false

func _add_record(record: Dictionary) -> void:
	# New authored business signs may belong to the civic build itself.
	if str(record.kind) != "business" and CivicClearance.record_removed(level, record, 0.45):
		return
	if CivicClearance.removed_home(level, "", str(record.get("source", ""))):
		return
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
		parts = [[Vector3(0.09, 0.95, 0.09), Vector3(0, 0.475, 0), Color("62584b")], [Vector3(0.34, 0.14, 0.47), Vector3(0, 0.96, 0), Color("73766c")], [Vector3(0.27, 0.21, 0.02), Vector3(0, 1.03, 0.244), Color("444e48")], [Vector3(0.04, 0.17, 0.11), Vector3(0.19, 1.17, 0), Color("923f32")]]
		parts.append([Vector3(0.37, 0.035, 0.49), Vector3(0, 0.895, 0), Color("555e55")])
		parts.append([Vector3(0.075, 0.025, 0.035), Vector3(0, 1.10, 0.268), Color("b0b3a3")])
		parts.append([Vector3(0.21, 0.025, 0.025), Vector3(0, 0.93, 0.26), Color("899080")])
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
	if not drop:
		# A rolled sheet-metal crown, sharing the one vertex-colour surface.
		for i in 8:
			var angle_a := float(i) * PI / 8.0
			var angle_b := float(i + 1) * PI / 8.0
			var p := Vector3(cos(angle_a) * 0.17, 1.03 + sin(angle_a) * 0.17, 0)
			var q := Vector3(cos(angle_b) * 0.17, 1.03 + sin(angle_b) * 0.17, 0)
			var depth := Vector3(0, 0, 0.235)
			var normal := Vector3(cos((angle_a + angle_b) * 0.5), sin((angle_a + angle_b) * 0.5), 0)
			_mail_face(surface, [p - depth, q - depth, q + depth, p + depth], normal, Color("73766c"))
			_mail_face(surface, [Vector3(0, 1.03, 0.235), p + depth, q + depth], Vector3.BACK, Color("73766c"))
			_mail_face(surface, [Vector3(0, 1.03, -0.235), q - depth, p - depth], Vector3.FORWARD, Color("73766c"))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.93
	surface.set_material(material)
	return surface.commit()

func _mail_face(surface: SurfaceTool, points: Array, normal: Vector3, color: Color) -> void:
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		# Godot front faces are clockwise; caps and crown keep outward normals.
		if (c - a).cross(b - a).dot(normal) < 0:
			var swap := b
			b = c
			c = swap
		for point in [a, b, c]:
			surface.set_color(color)
			surface.set_normal(normal)
			surface.add_vertex(point)

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
				var pixel_cap := 0.0036
				if float(record.get("label_height", 0.0)) > 0.0:
					pixel_cap = float(record.label_height) / ThemeDB.fallback_font.get_height(40)
				label.pixel_size = minf(pixel_cap, float(record.label_width) * 0.88 / widest)
			label.outline_size = 3
			label.modulate = Color(str(record.get("text_color", "f3e6c4")))
			label.position = record.position - cell.center + record.normal * 0.06
			label.basis = Basis(Vector3.UP.cross(record.normal).normalized(), Vector3.UP, record.normal)
			label.visibility_range_end = 65.0
			holder.add_child(label)
		if bool(record.fixture):
			var body := StaticBody3D.new()
			body.name = "SolidUtilityFixture"
			body.set_meta("postal_fixture", record.kind in ["mailbox", "postal_drop"])
			body.position = record.position - cell.center
			body.basis = record.get("collision_basis", record.basis)
			body.collision_layer = 2
			body.collision_mask = 0
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = record.get("solid_size", Vector3(0.66, 1.44, 0.68) if record.kind == "postal_drop" else Vector3(0.40, 1.28, 0.50))
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

func set_capture_presence(center: Vector3, render_center: Vector3, near_radius := 55.0, far_radius := 180.0) -> void:
	# Camera-only captures add detail residency without evicting player colliders.
	set_presence(center, near_radius, far_radius, render_center)

func set_presence(center: Vector3, _near_radius := 55.0, far_radius := 180.0, render_center := Vector3.INF) -> void:
	_focus = center
	_far_radius = maxf(far_radius, 90.0)
	for cell in _cells.values():
		var distance := Vector2(center.x - cell.center.x, center.z - cell.center.z).length()
		if render_center.is_finite():
			distance = minf(distance, Vector2(render_center.x - cell.center.x, render_center.z - cell.center.z).length())
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
	return {"counts": _counts.duplicate(), "records": records.size(), "crossings": _crossings.size(), "crossing_details": _crossing_details,
		"cells": _cells.size(), "business_cells": business_cells.size(), "postal_cells": postal_cells.size(), "span_x": max_at.x - min_at.x, "span_z": max_at.z - min_at.z, "active_cells": active, "active_batches": batches, "active_postal_colliders": fixtures, "shared_meshes": _meshes.size(), "setup_ms": _setup_ms, "fictional_businesses": true}

func _load_utility_meshes() -> void:
	# The original port contains detailed bolts/chains/nozzles and a curved blue
	# collection box. Extract once; each resident cell instances one shared mesh.
	var furniture := Assets.glb("furniture")
	if furniture == null:
		return
	var hydrants := Assets.find(furniture, "Hydrants") as MeshInstance3D
	var drop := Assets.find(furniture, "MailDrop") as MeshInstance3D
	if hydrants != null:
		_meshes.hydrant = _extract_fixture(hydrants, Vector3(-8.5, 0.14, -0.32), -9.5, -7.5)
	if drop != null:
		_meshes.postal_drop = _extract_fixture(drop, Vector3.ZERO)
	furniture.free()

func _extract_fixture(source: MeshInstance3D, origin: Vector3, min_x := -INF, max_x := INF) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := source.get_active_material(surface)
		var color := _fixture_color(material)
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for triangle in range(0, count, 3):
			var first := indices[triangle] if not indices.is_empty() else triangle
			if vertices[first].x < min_x or vertices[first].x > max_x:
				continue
			for corner in 3:
				var index := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				builder.set_color(color)
				builder.set_normal(normals[index])
				builder.add_vertex(vertices[index] - origin)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.77
	builder.set_material(material)
	builder.index()
	return builder.commit()

func _fixture_color(material: Material) -> Color:
	# Assets.glb replaces the imported PBR materials with ClayLib ShaderMaterials.
	# Their authored sRGB colour lives in the albedo shader parameter, not in
	# BaseMaterial3D.albedo_color. Keep it when merging finishes into vertex colour.
	if material is ShaderMaterial:
		var albedo = material.get_shader_parameter("albedo")
		if albedo is Color:
			return albedo
		if albedo is Vector4:
			return Color(albedo.x, albedo.y, albedo.z, albedo.w)
	if material is BaseMaterial3D:
		return material.albedo_color
	return Color.WHITE

func _build_utilities(samples: Array[Dictionary]) -> void:
	var ordered: Array[Dictionary] = samples.duplicate()
	# Stable spatial ordering avoids filling the quota along the first arterial.
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac := _cell(a.center)
		var bc := _cell(b.center)
		var ah := posmod(ac.x * 73856093 ^ ac.y * 19349663, 104729)
		var bh := posmod(bc.x * 73856093 ^ bc.y * 19349663, 104729)
		return ah < bh)
	var existing_hydrants: Array[Vector3] = []
	for anchor in level.level_data.get("dressing", []):
		if str(anchor.get("kind", "")) == "hydrant":
			existing_hydrants.append(level.vector(anchor.position))
	for kind in ["hydrant", "postal_drop", "mailbox"]:
		if not _meshes.has(kind):
			continue
		var limit: int = HYDRANT_LIMIT if kind == "hydrant" else (POSTAL_LIMIT if kind == "postal_drop" else MAIL_LIMIT)
		var spacing: float = 65.0 if kind == "hydrant" else (85.0 if kind == "postal_drop" else 95.0)
		var used: Dictionary = {}
		for sample in ordered:
			if int(_counts.get(kind, 0)) >= limit:
				break
			var center: Vector3 = sample.center
			var cell := _cell(center)
			if used.has(cell) or not _utility_spacing(center, kind, spacing, existing_hydrants):
				continue
			var placed := false
			for side in [1.0, -1.0]:
				for inset in [0.65, 0.95, 1.25]:
					var at: Vector3 = center + sample.across * float(side) * (float(sample.half) + float(inset))
					if not _record_clear(at, 2.0) or not _utility_spacing(at, kind, spacing, existing_hydrants):
						continue
					var radius := 0.50 if kind == "postal_drop" else (0.35 if kind == "hydrant" else 0.30)
					var found := Dressing.fixture_position(level, at, radius, 1.0 if kind == "hydrant" else 1.5)
					if found.is_empty():
						continue
					var yaw := atan2(-float(sample.across.x) * float(side), -float(sample.across.z) * float(side))
					if kind == "hydrant":
						_add_record({"kind": kind, "mesh": kind, "position": found.position,
							"basis": Basis(Vector3.UP, yaw), "color": Color.WHITE, "fixture": true,
							"solid_size": Vector3(0.48, 0.88, 0.45), "sidewalk_checked": true})
					else:
						_add_mail(found.position, yaw, kind == "postal_drop")
					used[cell] = true
					placed = true
					break
				if placed:
					break

func _utility_spacing(at: Vector3, kind: String, distance: float, existing_hydrants: Array[Vector3]) -> bool:
	for record in records:
		if str(record.kind) == kind and Vector2(at.x - record.position.x, at.z - record.position.z).length() < distance:
			return false
	if kind == "hydrant":
		for previous in existing_hydrants:
			if Vector2(at.x - previous.x, at.z - previous.z).length() < distance:
				return false
	return true
