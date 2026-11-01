extends RefCounted
## World-coordinate, graded hospital campus. Supersedes hospital terrain patches.
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")
const DATA := "res://assets/data/pen_lucy_hospital_grounds.json"


static func build(site: Dictionary) -> Node3D:
	var k := Kit.new("HospitalCampusGrounds")
	k.body.collision_layer = 1
	k.material("asphalt", Color("575b58"), 3)
	k.material("walk", Color("aaa79b"), 2)
	k.material("landscape", Color("67705a"), 5)
	k.material("paint", Color("dad5bc"), 0)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not parsed is Dictionary:
		push_error("Hospital campus geometry unavailable")
		return k.root
	var data: Dictionary = parsed
	var expected: Array = data.source_position
	var actual: Array = site.get("position", expected)
	if Vector3(float(actual[0]), float(actual[1]), float(actual[2])).distance_to(Vector3(float(expected[0]), float(expected[1]), float(expected[2]))) > 0.01:
		push_error("Hospital campus must be regenerated after moving its site")
		return k.root
	if absf(float(site.get("yaw", data.source_yaw)) - float(data.source_yaw)) > 0.001:
		push_error("Hospital campus must be regenerated after rotating its site")
		return k.root
	var faces := PackedVector3Array()
	for finish in data.triangles:
		var material := str(finish) if str(finish) != "repair" else "landscape"
		for tri in data.triangles[finish]:
			var a := _point(tri[0])
			var b := _point(tri[1])
			var c := _point(tri[2])
			if (c - a).cross(b - a).y < 0:
				var swap := b
				b = c
				c = swap
			k.triangle(a, b, c, material)
			if str(finish) != "paint":
				faces.append_array(PackedVector3Array([a, b, c]))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	k.body.add_child(collision)
	var root: Node3D = k.finish()
	root.set_meta("civic_type", "hospital_campus")
	root.set_meta("supersedes_hospital_terrain_patches", true)
	root.set_meta("campus_audit", data.audit)
	return root


static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
