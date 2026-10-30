extends Node
## Small shared meshes; only nearby spatial batches and trunk shapes are resident.
## The level's streamer calls set_presence; no per-tree processing or physics ticks.
const DATA_PATH := "res://assets/data/pen_lucy_vegetation.json"
const CELL := 48.0
var _cells := {}
var _active := {}
var _meshes := {}
var _counts := {}
var _material: StandardMaterial3D

func setup(_level: Node3D, city: Node3D) -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {"enabled": false, "reason": "vegetation metadata absent"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "invalid vegetation metadata"}
	name = "CityVegetation"
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.97
	_material.metallic_specular = 0.15
	for kind in data.templates:
		for lod in ["near", "far"]:
			_meshes[str(kind) + "_" + lod] = _build_mesh(data.templates[kind][lod])
	for record in data.plants:
		var coordinates: Array = record.position
		var point := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
		if not _cells.has(cell):
			_cells[cell] = []
		var plant: Dictionary = record.duplicate()
		plant.position = point
		_cells[cell].append(plant)
	_counts = data.counts.duplicate()
	_counts.enabled = true
	_counts.shared_meshes = _meshes.size()
	_counts.spatial_cells = _cells.size()
	# Replace the old monolithic crowns and their expensive triangle collision.
	# Root may also skip Trees while creating imported city collision shapes.
	for source in city.find_children("Trees", "MeshInstance3D", true, false):
		source.free()
	return get_stats()

func _build_mesh(data: Dictionary) -> ArrayMesh:
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
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh

func set_presence(center: Vector3, near_radius: float, far_radius: float) -> void:
	# Large tree silhouettes remain on the horizon. Short bushes need only the
	# street-level vicinity; cylinder physics is ready before a walker reaches it.
	var horizon := maxf(far_radius, 400.0)
	for cell in _cells:
		var previous: Dictionary = _active.get(cell, {})
		var closest := Vector2(clampf(center.x, float(cell.x) * CELL, (float(cell.x) + 1.0) * CELL), clampf(center.z, float(cell.y) * CELL, (float(cell.y) + 1.0) * CELL))
		var distance := closest.distance_to(Vector2(center.x, center.z))
		# Different enter/leave thresholds prevent reallocating batches and shapes
		# when the player jogs back and forth across a cell's distance boundary.
		if distance > horizon + (20.0 if not previous.is_empty() else 0.0):
			if _active.has(cell):
				_active[cell].node.queue_free()
				_active.erase(cell)
			continue
		var near_limit := near_radius + (10.0 if str(previous.get("lod", "")) == "near" else 0.0)
		var lod := "near" if distance <= near_limit else "far"
		var physics := distance <= maxf(near_radius, 90.0) + (10.0 if bool(previous.get("physics", false)) else 0.0)
		var bushes := distance <= 125.0 + (10.0 if bool(previous.get("bushes", false)) else 0.0)
		var signature := "%s_%s_%s" % [lod, physics, bushes]
		if _active.has(cell) and _active[cell].signature == signature:
			continue
		if _active.has(cell):
			_active[cell].node.queue_free()
		_active[cell] = {"node": _build_cell(cell, lod, physics, bushes), "signature": signature, "lod": lod, "physics": physics, "bushes": bushes}

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

func _build_cell(cell: Vector2i, lod: String, physics: bool, bushes: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Plants_%d_%d_%s" % [cell.x, cell.y, lod]
	root.position = Vector3(float(cell.x) * CELL, 0, float(cell.y) * CELL)
	add_child(root)
	var groups := {}
	var trunk_count := 0
	var plant_count := 0
	for plant in _cells[cell]:
		var kind: String = plant.kind
		var is_tree := kind.begins_with("tree")
		if not is_tree and not bushes:
			continue
		if not groups.has(kind):
			groups[kind] = []
		var radius: float = plant.radius
		var height: float = plant.height
		var pose := Transform3D(Basis(Vector3.UP, float(plant.yaw)).scaled(Vector3(radius, height, radius)), plant.position - root.position)
		groups[kind].append(pose)
		plant_count += 1
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
	for kind in groups:
		var poses: Array = groups[kind]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _meshes[str(kind) + "_" + lod]
		multi.instance_count = poses.size()
		for i in poses.size():
			multi.set_instance_transform(i, poses[i])
		var batch := MultiMeshInstance3D.new()
		batch.name = str(kind) + "_" + lod
		batch.multimesh = multi
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == "near" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
	root.set_meta("trunks", trunk_count)
	root.set_meta("plants", plant_count)
	root.set_meta("batches", groups.size())
	return root

func get_stats() -> Dictionary:
	var result := _counts.duplicate()
	result.loaded_cells = _active.size()
	result.loaded_plants = 0
	result.trunk_colliders = 0
	result.draw_batches = 0
	for entry in _active.values():
		result.loaded_plants += int(entry.node.get_meta("plants", 0))
		result.trunk_colliders += int(entry.node.get_meta("trunks", 0))
		result.draw_batches += int(entry.node.get_meta("batches", 0))
	return result
