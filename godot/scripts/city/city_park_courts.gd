extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
## Public courts across usable greens, source-fitted ramps and batched paint/hoops.
## Floor collision stays authoritative like city terrain; one render mesh per court.
const DATA := "res://assets/data/pen_lucy_courts.json"
var records: Array[Dictionary] = []
var _audit: Dictionary = {}
var _material: StandardMaterial3D

func setup(level: Node3D) -> Dictionary:
	name = "ParkBasketballCourts"
	if not FileAccess.file_exists(DATA):
		return {"enabled": false, "reason": "court metadata absent"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return {"enabled": false, "reason": "invalid court metadata"}
	_audit = data.audit.duplicate(true)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = .92
	_material.metallic_specular = .15
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var civic_removed := 0
	for entry in data.courts:
		if CivicClearance.record_removed(level, entry):
			civic_removed += 1
			continue
		var record: Dictionary = entry.duplicate(true)
		record.position = level.vector(entry.position)
		var polygon := PackedVector2Array()
		for point in entry.footprint:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		record.polygon = polygon
		var holder := Node3D.new()
		holder.name = str(entry.id)
		holder.position = record.position
		add_child(holder)
		var arrays := _arrays(entry.mesh)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		var instance := MeshInstance3D.new()
		instance.name = "CourtPaintAndHoops"
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(instance)
		record.instance = instance
		# Only slab/apron triangles create floor collision. Hoop boards and arms
		# get matching overhead boxes; paint and nets remain decorative.
		var floor_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].slice(0, int(entry.floor_triangles) * 3)
		var floor_shape := ConcavePolygonShape3D.new()
		floor_shape.set_faces(floor_vertices)
		var floor_body := StaticBody3D.new()
		floor_body.name = "CourtSupport"
		floor_body.collision_layer = 1
		floor_body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = floor_shape
		floor_body.add_child(collision)
		holder.add_child(floor_body)
		var retaining_count := int(entry.get("retaining_triangles", 0))
		if retaining_count > 0:
			var retaining_shape := ConcavePolygonShape3D.new()
			retaining_shape.backface_collision = true
			retaining_shape.set_faces(arrays[Mesh.ARRAY_VERTEX].slice(int(entry.floor_triangles) * 3, (int(entry.floor_triangles) + retaining_count) * 3))
			var retaining_body := StaticBody3D.new()
			retaining_body.name = "SolidCourtRetainingEdge"
			retaining_body.collision_layer = 2
			retaining_body.collision_mask = 0
			var retaining_collision := CollisionShape3D.new()
			retaining_collision.shape = retaining_shape
			retaining_body.add_child(retaining_collision)
			holder.add_child(retaining_body)
		var hoops: Array[Dictionary] = []
		for hoop_entry in entry.hoops:
			var hoop: Dictionary = hoop_entry.duplicate()
			hoop.position = level.vector(hoop_entry.position)
			hoop.rim_position = level.vector(hoop_entry.rim_position)
			# Match park_courts.mesh_for: board is .375m behind the rim and
			# .40m higher; arm joins the pole to the board at pole-ground+3.48m.
			var inward: Vector3 = hoop.rim_position - hoop.position
			inward.y = 0.0
			inward = inward.normalized()
			hoop.board_position = hoop.rim_position - inward * .375 + Vector3.UP * .40
			var arm_end: Vector3 = hoop.board_position
			arm_end.y = hoop.position.y
			hoop.arm_position = (hoop.position + arm_end) * .5 + Vector3.UP * 3.48
			var arm_length: float = hoop.position.distance_to(arm_end)
			var hoop_yaw := atan2(inward.x, inward.z)
			_solid_box(holder, "SolidHoopBackboard_%d" % hoops.size(), hoop.board_position - record.position, Vector3(1.80, 1.05, .06), hoop_yaw)
			_solid_box(holder, "SolidHoopArm_%d" % hoops.size(), hoop.arm_position - record.position, Vector3(.12, .14, arm_length), hoop_yaw)
			hoops.append(hoop)
			var body := StaticBody3D.new()
			body.name = "SolidHoopPole"
			body.position = hoop.position - record.position
			body.collision_layer = 2
			body.collision_mask = 0
			var shape := CylinderShape3D.new()
			shape.radius = .16
			shape.height = 3.75
			var pole := CollisionShape3D.new()
			pole.shape = shape
			pole.position.y = 1.875
			body.add_child(pole)
			holder.add_child(body)
		record.hoops = hoops
		records.append(record)
	_audit.civic_removed = civic_removed
	return get_status()

func _solid_box(holder: Node3D, label: String, at: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.rotation.y = yaw
	body.collision_layer = 2
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	holder.add_child(body)

func _arrays(data: Dictionary) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(0, data.vertices.size(), 3):
		vertices.append(Vector3(data.vertices[i], data.vertices[i + 1], data.vertices[i + 2]))
		normals.append(Vector3(data.normals[i], data.normals[i + 1], data.normals[i + 2]))
	for i in range(0, data.colors.size(), 4):
		colors.append(Color(data.colors[i], data.colors[i + 1], data.colors[i + 2], data.colors[i + 3]))
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_COLOR] = colors
	return result

func set_presence(center: Vector3, _near_radius := 55.0, _far_radius := 180.0) -> void:
	for record in records:
		record.instance.visible = Vector2(center.x - record.position.x, center.z - record.position.z).length() < 300.0

func is_clear(point: Vector3, radius: float) -> bool:
	for record in records:
		for hoop in record.hoops:
			var at: Vector3 = hoop.position
			if Vector2(point.x - at.x, point.z - at.z).length() < radius + float(hoop.radius):
				return false
	return true

func is_court(point: Vector3, margin := 0.0) -> bool:
	var flat := Vector2(point.x, point.z)
	for record in records:
		var polygon: PackedVector2Array = record.polygon
		if Geometry2D.is_point_in_polygon(flat, polygon):
			return true
		if margin > 0:
			for i in range(1, polygon.size()):
				if Geometry2D.get_closest_point_to_segment(flat, polygon[i - 1], polygon[i]).distance_to(flat) < margin:
					return true
	return false

func get_status() -> Dictionary:
	var visible := 0
	var hoops := 0
	for record in records:
		visible += int(record.instance.visible)
		hoops += record.hoops.size()
	return {"enabled": not records.is_empty(), "courts": records.size(), "hoops": hoops,
		"draw_batches": visible, "floor_colliders": records.size(), "pole_colliders": hoops,
		"backboard_colliders": hoops, "arm_colliders": hoops, "audit": _audit}
