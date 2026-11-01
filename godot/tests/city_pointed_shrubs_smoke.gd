extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	print("[pointed_shrubs] %s %s" % ["PASS" if ok else "FAIL", message])
	failures += int(not ok)
func _initialize() -> void:
	var vegetation = load("res://scripts/city/city_vegetation.gd").new()
	vegetation._material = StandardMaterial3D.new()
	var counts: Array[int] = []
	for near in [true, false]:
		var mesh: ArrayMesh = vegetation._pointed_shrub_mesh(near)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var outward := true
		var clockwise := true
		for i in range(0, vertices.size(), 3):
			var normal := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
			clockwise = clockwise and normal.dot(normals[i]) < -0.99
			var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
			outward = outward and Vector2(center.x, center.z).dot(Vector2(normals[i].x, normals[i].z)) > 0.0
		check(clockwise and outward, "pointed crown faces outward with Godot winding at LOD " + str(near))
		check(mesh.get_aabb().position.y < 0.0 and is_equal_approx(mesh.get_aabb().end.y, 1.0), "crown base seats below ground and reaches pointed tip")
		counts.append(vertices.size())
	check(counts[1] < counts[0] / 2, "far crown uses less than half the geometry")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(vegetation.POINTED_SHRUBS))
	check(data.audit.target_placed and data.audit.spatial_cells >= 50, "target lawn and mapwide coverage authored")
	check(data.plants.all(func(p: Dictionary): return p.trunk_radius == 0.0 and p.height >= 1.9 and p.height <= 2.6), "shrubs stay decorative and taller than hedges")
	vegetation.free()
	quit(0 if failures == 0 else 1)
