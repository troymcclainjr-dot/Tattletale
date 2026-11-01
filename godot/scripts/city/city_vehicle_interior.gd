extends RefCounted
## Occupied-car-only window openings. Never mutate the shared fleet prototype.
## Subtract each glass triangle from nearby parallel paint triangles; convex
## half-plane partitioning avoids the holes returned by polygon boolean APIs.
const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
static var _cache: Dictionary = {}

static func seat_local_point(kind: String) -> Vector3:
	var size := Models.dimensions(kind)
	var front := 0.43
	if Catalog.has_kind(kind):
		var stations: Array = Catalog.config(kind).greenhouse
		front = float(stations[stations.size() - 2][0])
	elif kind == "compact":
		front = 0.48
	elif kind == "minivan":
		front = 0.75
	# Hip location, +X is the driver's side. Head stays below the roof.
	return Vector3(size.x * 0.23, size.y - 1.11, front - 0.10)

static func cabin_bounds(kind: String) -> AABB:
	var size := Models.dimensions(kind)
	var rear := -1.32
	var front := 1.10
	if Catalog.has_kind(kind):
		var stations: Array = Catalog.config(kind).greenhouse
		rear = float(stations[0][0])
		front = float(stations[-1][0])
	elif kind == "compact":
		rear = -1.43
		front = 1.25
	elif kind == "minivan":
		rear = -2.10
		front = 1.82
	return AABB(Vector3(-size.x * 0.40, 0.45, rear + 0.13), Vector3(size.x * 0.80, size.y - 0.65, front - rear - 0.29))

static func deck_height(kind: String, z: float) -> float:
	if Catalog.has_kind(kind):
		return Catalog.upper(kind, z)
	return 0.80 if kind == "compact" else (0.94 if kind == "minivan" else 0.88)

static func open_windows(source: Mesh, kind: String) -> ArrayMesh:
	var key := source.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var panes: Array = []
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		if material != null and material.resource_name == "city_vehicle_glass":
			panes.append_array(_triangles(source.surface_get_arrays(surface)))
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		if material == null or material.resource_name != "city_vehicle_paint":
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
			mesh.surface_set_material(surface, material)
			continue
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material)
		for triangle in _triangles(source.surface_get_arrays(surface)):
			var origin: Vector3 = triangle[0].p
			var normal: Vector3 = (triangle[1].p - origin).cross(triangle[2].p - origin).normalized()
			var remaining: Array = [triangle]
			var bounds := cabin_bounds(kind)
			# Fleet models are closed solids: both lower-body deck and the
			# greenhouse underside span the cabin at sill height. Open only
			# these near-horizontal caps, inside the greenhouse footprint.
			# Hood/trunk, roof, vertical doors and original underfloor survive.
			var cap := absf(normal.y) > 0.75
			for vertex in triangle:
				cap = cap and vertex.p.y > bounds.position.y and vertex.p.y < bounds.end.y
			if cap:
				var opening: Array[Vector3] = []
				for corner in [Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.position.x, bounds.end.z),
					Vector2(bounds.end.x, bounds.end.z), Vector2(bounds.end.x, bounds.position.z)]:
					var y: float = origin.y - (normal.x * (corner.x - origin.x) + normal.z * (corner.y - origin.z)) / normal.y
					opening.append(Vector3(corner.x, y, corner.y))
				if normal.y < 0.0:
					opening.reverse()
				remaining = _subtract(triangle, opening, normal)
			for pane in panes:
				var pn: Vector3 = (pane[1].p - pane[0].p).cross(pane[2].p - pane[0].p).normalized()
				# Curved sill outlines produce a few almost-collinear glass
				# triangles. Their normal is unstable despite lying <1cm off
				# the side panel. Permit only those slivers a tighter 2cm
				# projection, retaining the normal guard for ordinary panes.
				var sliver := is_sliver(pane)
				if absf(normal.dot(pn)) < 0.96 and not sliver:
					continue
				var near := true
				for vertex in pane:
					if absf(normal.dot(vertex.p - origin)) > (0.02 if sliver else 0.075):
						near = false
				if not near:
					continue
				var cutter: Array[Vector3] = []
				for vertex in pane:
					cutter.append(vertex.p - normal * normal.dot(vertex.p - origin))
				if (cutter[1] - cutter[0]).cross(cutter[2] - cutter[0]).length_squared() < 1e-14:
					continue
				if normal.dot(pn) < 0.0:
					cutter.reverse()
				var next: Array = []
				for polygon in remaining:
					next.append_array(_subtract(polygon, cutter, normal))
				remaining = next
				if remaining.is_empty():
					break
			for polygon in remaining:
				for index in range(1, polygon.size() - 1):
					for vertex in [polygon[0], polygon[index], polygon[index + 1]]:
						builder.set_normal(vertex.n)
						builder.set_color(vertex.c)
						builder.add_vertex(vertex.p)
		builder.index()
		builder.commit(mesh)
	# At most the nine civilian body prototypes, bounded across world reloads.
	if _cache.size() >= 9:
		_cache.clear()
	_cache[key] = mesh
	return mesh

static func is_sliver(triangle: Array) -> bool:
	var ab: Vector3 = triangle[1].p - triangle[0].p
	var ac: Vector3 = triangle[2].p - triangle[0].p
	var bc: Vector3 = triangle[2].p - triangle[1].p
	var edge_sq := maxf(ab.length_squared(), maxf(ac.length_squared(), bc.length_squared()))
	return ab.cross(ac).length() < edge_sq * 0.001

static func _triangles(arrays: Array) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var result: Array = []
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for start in range(0, count, 3):
		var triangle: Array = []
		for offset in 3:
			var index := indices[start + offset] if not indices.is_empty() else start + offset
			triangle.append({"p": vertices[index], "n": normals[index], "c": colors[index] if not colors.is_empty() else Color.WHITE})
		result.append(triangle)
	return result

static func _subtract(polygon: Array, cutter: Array[Vector3], normal: Vector3) -> Array:
	var outside: Array = []
	var inside := polygon
	for edge in cutter.size():
		var a := cutter[edge]
		var b := cutter[(edge + 1) % cutter.size()]
		var inward := normal.cross(b - a).normalized()
		var piece := _clip(inside, a, -inward)
		if piece.size() >= 3:
			outside.append(piece)
		inside = _clip(inside, a, inward)
		if inside.size() < 3:
			break
	return outside

static func _clip(polygon: Array, origin: Vector3, inward: Vector3) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Dictionary = polygon[-1]
	var pd := inward.dot(previous.p - origin)
	for vertex in polygon:
		var d := inward.dot(vertex.p - origin)
		if (d >= 0.0) != (pd >= 0.0):
			var t := pd / (pd - d)
			result.append({"p": previous.p.lerp(vertex.p, t), "n": previous.n.lerp(vertex.n, t).normalized(), "c": previous.c.lerp(vertex.c, t)})
		if d >= 0.0:
			result.append(vertex)
		previous = vertex
		pd = d
	return result
