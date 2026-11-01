extends SceneTree
## Imported-model regression only: no full level, population or save setup.
const Weathering := preload("res://scripts/city/city_weathering.gd")
var failures: Array[String] = []
var samples: Array[Dictionary] = [
	{"id": "requested_wilsby_strip", "xz": Vector2(275.63, -162.80), "y": -4.895282, "hex": "3a3a40", "kind": 3},
	{"id": "wilsby_passage", "xz": Vector2(282.0, -167.0), "y": -5.040990, "hex": "3a3a40", "kind": 3},
	{"id": "east_public_sidewalk", "xz": Vector2(268.0, -164.0), "y": -4.708150, "hex": "a8a49a", "kind": 2},
	{"id": "west_public_sidewalk", "xz": Vector2(256.0, -164.0), "y": -4.479347, "hex": "a8a49a", "kind": 2},
	{"id": "protected_front_pad", "xz": Vector2(274.929667, -181.378), "y": -4.702771, "hex": "8a8a90", "kind": 2},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed = load("res://assets/models/city/pen_lucy.glb")
	if not packed is PackedScene:
		failures.append("Imported neighborhood model missing")
		_finish()
		return
	var city: Node3D = packed.instantiate()
	root.add_child(city)
	var ground := city.find_child("Ground", true, false) as MeshInstance3D
	if ground == null or ground.mesh == null:
		failures.append("Imported Ground mesh missing")
		city.free()
		_finish()
		return
	for surface in ground.mesh.get_surface_count():
		var material: Material = ground.mesh.surface_get_material(surface)
		var material_name: String = material.resource_name if material != null else ""
		var arrays: Array = ground.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in vertices.size():
				indices[index] = index
		for sample in samples:
			var point: Vector2 = sample.xz
			for offset in range(0, indices.size(), 3):
				var a: Vector3 = ground.global_transform * vertices[indices[offset]]
				var b: Vector3 = ground.global_transform * vertices[indices[offset + 1]]
				var c: Vector3 = ground.global_transform * vertices[indices[offset + 2]]
				if point.x < minf(a.x, minf(b.x, c.x)) - .00001 or point.x > maxf(a.x, maxf(b.x, c.x)) + .00001:
					continue
				if point.y < minf(a.z, minf(b.z, c.z)) - .00001 or point.y > maxf(a.z, maxf(b.z, c.z)) + .00001:
					continue
				var hit = Geometry3D.ray_intersects_triangle(Vector3(point.x, 50.0, point.y), Vector3.DOWN, a, b, c)
				if hit == null:
					continue
				sample["hit"] = true
				sample["actual_material"] = material_name
				sample["actual_y"] = hit.y
				if not material_name.begins_with("clay_" + str(sample.hex) + "_"):
					failures.append(str(sample.id) + " has wrong finish: " + material_name)
				if absf(hit.y - float(sample.y)) > .002:
					failures.append(str(sample.id) + " terrain height changed")
				if Weathering.classify(material_name) != int(sample.kind):
					failures.append(str(sample.id) + " has wrong weathered shader kind")
				break
	for sample in samples:
		if not bool(sample.get("hit", false)):
			failures.append(str(sample.id) + " has no ground support")
	city.free()
	_finish()

func _finish() -> void:
	print("ALLEY_SURFACE_SMOKE " + JSON.stringify({"failures": failures, "samples": samples}))
	quit(0 if failures.is_empty() else 1)
