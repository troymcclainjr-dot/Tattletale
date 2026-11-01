extends RefCounted
## Only the occupied car needs triangle-accurate window tests. Cache its single
## body mesh; shots remain world-physics rays everywhere else. This does not
## replace the solid vehicle hull used for movement and collisions.
var _mesh: Mesh
var _solid: Array[Vector3] = []
var _glass: Array[Vector3] = []

func clear() -> void:
	_mesh = null
	_solid.clear()
	_glass.clear()

func window_path(body: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(body) or body.mesh == null:
		return false
	if body.mesh != _mesh:
		_cache(body.mesh)
	var start := body.to_local(from)
	var finish := body.to_local(to)
	var distance := start.distance_to(finish)
	if distance < 0.001:
		return false
	var direction := (finish - start) / distance
	# Crossing glass is necessary: no shots through a closed roof or door.
	if not _intersects(_glass, start, direction, distance):
		return false
	return not _intersects(_solid, start, direction, distance)

func _cache(mesh: Mesh) -> void:
	clear()
	_mesh = mesh
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var material := mesh.surface_get_material(surface)
		var glass := material != null and material.resource_name == "city_vehicle_glass"
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var target: Array[Vector3] = _glass if glass else _solid
		if indices.is_empty():
			for vertex in vertices:
				target.append(vertex)
		else:
			for index in indices:
				target.append(vertices[index])

func _intersects(triangles: Array[Vector3], from: Vector3, direction: Vector3, distance: float) -> bool:
	for index in range(0, triangles.size() - 2, 3):
		var hit = Geometry3D.ray_intersects_triangle(from, direction, triangles[index], triangles[index + 1], triangles[index + 2])
		if hit != null and from.distance_to(hit) < distance - 0.005:
			return true
	return false

static func sphere_hit(from: Vector3, to: Vector3, center: Vector3, radius: float) -> Vector3:
	var length := from.distance_to(to)
	if length <= 0.0001 or radius <= 0.0:
		return Vector3.INF
	var direction := (to - from) / length
	var offset := from - center
	var projection := offset.dot(direction)
	var determinant := projection * projection - (offset.length_squared() - radius * radius)
	if determinant < 0.0:
		return Vector3.INF
	var distance := maxf(0.0, -projection - sqrt(determinant))
	return from + direction * distance if distance <= length and -projection + sqrt(determinant) >= 0.0 else Vector3.INF
