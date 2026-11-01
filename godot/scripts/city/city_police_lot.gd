extends RefCounted
## Two parking banks around a clear aisle; fence follows the actual paving grade.
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")

static func build(site: Dictionary) -> Node3D:
	var kit := Kit.new("PrecinctLotFence")
	kit.material("steel", Color("454c4b"), 0)
	# East vehicle entrance stays open; north pedestrian gate links the precinct.
	for ends in [[Vector2(-36.7, -69.7), Vector2(-36.7, -52.3)],
		[Vector2(-36.7, -52.3), Vector2(-9.4, -52.3)],
		[Vector2(-36.7, -69.7), Vector2(-29.9, -69.7)],
		[Vector2(-28.3, -69.7), Vector2(-9.4, -69.7)],
		[Vector2(-9.4, -69.7), Vector2(-9.4, -64.2)],
		[Vector2(-9.4, -57.8), Vector2(-9.4, -52.3)]]:
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var count := ceili(a.distance_to(b) / 2.4)
		for index in count:
			var start := a.lerp(b, float(index) / count)
			var end := a.lerp(b, float(index + 1) / count)
			var middle := (start + end) * 0.5
			var y := _height(site, middle)
			var length := start.distance_to(end)
			var yaw := atan2(end.x - start.x, end.y - start.y)
			for rail_y in [0.35, 1.45]:
				kit.box(Vector3(middle.x, y + rail_y, middle.y), Vector3(0.055, 0.055, length), "steel", yaw)
			kit.solid_box(Vector3(middle.x, y + 0.82, middle.y), Vector3(0.09, 1.64, length), yaw)
			var bars := ceili(length / 0.28)
			for bar in bars + 1:
				var at := start.lerp(end, float(bar) / bars)
				kit.box(Vector3(at.x, _height(site, at) + 0.85, at.y), Vector3(0.035, 1.7, 0.035), "steel")
		for endpoint in [a, b]:
			kit.box(Vector3(endpoint.x, _height(site, endpoint) + 0.9, endpoint.y), Vector3(0.095, 1.8, 0.095), "steel")
	return kit.finish()

static func _height(site: Dictionary, point: Vector2) -> float:
	var best := -INF
	for tri in site.get("parking_triangles", []):
		var a := Vector2(float(tri[0][0]), float(tri[0][2]))
		var b := Vector2(float(tri[1][0]), float(tri[1][2]))
		var c := Vector2(float(tri[2][0]), float(tri[2][2]))
		var denom := (b - a).cross(c - a)
		if absf(denom) < 0.000001:
			continue
		var u := (point - a).cross(c - a) / denom
		var v := (b - a).cross(point - a) / denom
		if u < -0.00001 or v < -0.00001 or u + v > 1.00001:
			continue
		best = maxf(best, float(tri[0][1]) * (1 - u - v) + float(tri[1][1]) * u + float(tri[2][1]) * v)
	if is_finite(best):
		return best
	var plane: Array = site.parking_height_audit.plane_ax_bz_c
	return float(plane[0]) * point.x + float(plane[1]) * point.y + float(plane[2]) + 0.025
