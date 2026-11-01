extends Node3D
## Ground-authored private-lot details. No per-frame work; static batched meshes.
const DATA := "res://assets/data/pen_lucy_alive_world.json"
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")
const Backlots = preload("res://scripts/city/city_backlot_details.gd")
const CELL := 48.0
var _chunks: Array[Node3D] = []
var _centers: Array[Vector3] = []
var _status: Dictionary = {}


func setup(level: Node3D) -> Dictionary:
	name = "CityAliveWorld"
	set_process(false)
	if not _status.is_empty():
		return get_status()
	if not FileAccess.file_exists(DATA):
		return {"enabled": false, "reason": "world repair manifest unavailable"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "invalid world repair manifest"}
	var kits: Dictionary = {}
	for fence in data.fences:
		var points: Array = fence.posts
		var center := _point(points[floori(points.size() * .5)])
		var cell := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
		if not kits.has(cell):
			var new_kit := Kit.new("PrivateFenceCell_%s_%s" % [cell.x, cell.y])
			new_kit.material("wood", Color("655e4c"), 0)
			kits[cell] = new_kit
		var kit: Kit = kits[cell]
		var height := float(fence.height)
		for p in points:
			var at := _point(p)
			kit.box(at + Vector3.UP * height * .5, Vector3(.11, height, .11), "wood")
		for i in points.size() - 1:
			var a := _point(points[i])
			var b := _point(points[i + 1])
			var direction := b - a
			var length := Vector2(direction.x, direction.z).length()
			var yaw := atan2(direction.x, direction.z)
			# Slats follow terrain individually; horizontal rails are stepped
			# across short panels so their underside never floats off the grade.
			for rail_height in [.28, .83]:
				kit.box((a + b) * .5 + Vector3.UP * rail_height, Vector3(.08, .09, length), "wood", yaw)
			var slats := maxi(3, ceili(length / .16))
			for j in slats:
				var at := a.lerp(b, (float(j) + .5) / float(slats))
				kit.box(at + Vector3.UP * .48, Vector3(.075, .94, .055), "wood", yaw)
			# Thin private-side boundary only, with authored door/path gaps.
			kit.solid_box((a + b) * .5 + Vector3.UP * height * .5, Vector3(.14, height + absf(direction.y), length + .1), yaw)
	for cell in kits:
		var root: Node3D = kits[cell].finish()
		add_child(root)
		_register(root, Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL))
	var grass := Kit.new("FirehouseSideLawns")
	grass.material("grass", Color("526945"), 5)
	for tri in data.fire_grass_triangles:
		var a := _point(tri[0])
		var b := _point(tri[1])
		var c := _point(tri[2])
		if (c - a).cross(b - a).y < 0:
			var swap := b
			b = c
			c = swap
		grass.triangle(a, b, c, "grass")
	var grass_root: Node3D = grass.finish()
	add_child(grass_root)
	_register(grass_root, Vector3(-24, 0, 137))
	var terrain_kits: Dictionary = {}
	for finish in ["lawn", "paving"]:
		var triangles: Array = data.get("lawn_triangles" if finish == "lawn" else "paving_triangles", [])
		for tri in triangles:
			var a := _point(tri[0])
			var b := _point(tri[1])
			var c := _point(tri[2])
			var center := (a + b + c) / 3.0
			var cell := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
			if not terrain_kits.has(cell):
				var terrain_kit := Kit.new("FrontLawnCell_%s_%s" % [cell.x, cell.y])
				terrain_kit.material("lawn", Color("617c46"), 5)
				terrain_kit.material("paving", Color("9a968c"), 2)
				terrain_kits[cell] = terrain_kit
			if (c - a).cross(b - a).y < 0:
				var swap := b
				b = c
				c = swap
			terrain_kits[cell].triangle(a, b, c, finish)
	for cell in terrain_kits:
		var root: Node3D = terrain_kits[cell].finish()
		add_child(root)
		_register(root, Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL))
	var lawn_collision := _build_lawn_collision(data.get("lawn_collision_triangles", []))
	var yards: Node = level.get("yard_details")
	var templates: Dictionary = yards.get("_meshes") if is_instance_valid(yards) else {}
	var dumpster_mesh: Mesh = templates.get("dumpster")
	var rejected: Array[Dictionary] = []
	var accepted := 0
	var batches: Dictionary = {}
	for entry in data.dumpsters:
		var record: Dictionary = entry
		var grounded: Dictionary = Backlots._dumpster_pose(level, record)
		if dumpster_mesh == null or grounded.is_empty():
			rejected.append({"id": record.id, "reason": "ground or template"})
			continue
		var pose: Transform3D = grounded.pose
		var parts: Array[Dictionary] = Backlots._dumpster_parts()
		if not Backlots._clear(level, pose, parts):
			rejected.append({"id": record.id, "reason": "occupied"})
			continue
		var body := StaticBody3D.new()
		body.name = str(record.id)
		body.transform = pose
		body.collision_layer = 2 | 16
		body.collision_mask = 0
		for part in parts:
			var collision := CollisionShape3D.new()
			collision.shape = part.shape
			collision.position = part.offset
			body.add_child(collision)
		add_child(body)
		var cell := Vector2i(floori(pose.origin.x / CELL), floori(pose.origin.z / CELL))
		if not batches.has(cell):
			batches[cell] = []
		batches[cell].append(pose)
		accepted += 1
	for cell in batches:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = dumpster_mesh
		multimesh.instance_count = batches[cell].size()
		for i in multimesh.instance_count:
			multimesh.set_instance_transform(i, batches[cell][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "DumbartonRearBins"
		instance.multimesh = multimesh
		add_child(instance)
		_register(instance, Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL))
	_status = {"enabled": true, "fences": data.fences.size(), "dumpsters": accepted,
		"dumpster_rejected": rejected, "fire_grass_triangles": data.fire_grass_triangles.size(),
		"lawn_collision": lawn_collision,
		"chunks": _chunks.size(), "source_audit": data.audit}
	return get_status()


func _build_lawn_collision(triangles: Array) -> Dictionary:
	# Offline simplification includes only lawn extensions more than 4cm above
	# the old paving. Existing imported Ground supports all remaining lawns.
	var cells: Dictionary = {}
	for triangle in triangles:
		var a := _point(triangle[0])
		var b := _point(triangle[1])
		var c := _point(triangle[2])
		var center := (a + b + c) / 3.0
		var cell := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
		if not cells.has(cell):
			cells[cell] = PackedVector3Array()
		if (c - a).cross(b - a).y < 0:
			var swap := b
			b = c
			c = swap
		var faces: PackedVector3Array = cells[cell]
		faces.append_array(PackedVector3Array([a, b, c]))
		cells[cell] = faces
	for cell in cells:
		var support := StaticBody3D.new()
		support.name = "LawnSupport_%s_%s" % [cell.x, cell.y]
		support.collision_layer = 1
		support.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(cells[cell])
		var collision := CollisionShape3D.new()
		collision.shape = shape
		support.add_child(collision)
		add_child(support)
	return {"cells": cells.size(), "triangles": triangles.size()}


func _register(root: Node3D, center: Vector3) -> void:
	_chunks.append(root)
	_centers.append(center)
	if root is GeometryInstance3D:
		root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_presence(focus: Vector3, _near_radius: float, far_radius: float) -> void:
	var radius := minf(far_radius + CELL, 240.0)
	for i in _chunks.size():
		_chunks[i].visible = Vector2(_centers[i].x - focus.x, _centers[i].z - focus.z).length_squared() <= radius * radius


func get_status() -> Dictionary:
	return _status.duplicate(true)


static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
