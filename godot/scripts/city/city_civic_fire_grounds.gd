extends RefCounted
## Full-width graded apron and demolition-ground repair in world coordinates.
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")
const DATA := "res://assets/data/pen_lucy_fire_grounds.json"


static func build(site: Dictionary) -> Node3D:
	var k := Kit.new("FirehouseGrounds")
	k.body.collision_layer = 1
	k.material("walk", Color("9a968c"), 2)
	k.material("repair", Color("535653"), 3)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not parsed is Dictionary:
		push_error("Firehouse grounds data unavailable")
		return k.root
	var data: Dictionary = parsed
	var actual: Array = site.get("position", data.source_position)
	if _point(actual).distance_to(_point(data.source_position)) > 0.01 or absf(float(site.get("yaw", data.source_yaw)) - float(data.source_yaw)) > 0.001:
		push_error("Firehouse grounds must be regenerated after moving or rotating site")
		return k.root
	var faces := PackedVector3Array()
	for finish in data.triangles:
		for tri in data.triangles[finish]:
			var a := _point(tri[0])
			var b := _point(tri[1])
			var c := _point(tri[2])
			if (c - a).cross(b - a).y < 0:
				var swap := b
				b = c
				c = swap
			k.triangle(a, b, c, str(finish))
			faces.append_array(PackedVector3Array([a, b, c]))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	k.body.add_child(collision)
	var root: Node3D = k.finish()
	root.set_meta("civic_type", "fire_grounds")
	root.set_meta("supersedes_fire_terrain_patches", true)
	root.set_meta("grounds_audit", data.audit)
	return root


static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
