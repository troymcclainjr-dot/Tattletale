extends RefCounted
## Shared low-poly collision shells in the traffic model's native +Z frame.
## Wheels/handles stay inside the lower shell; the tapered cabin leaves hood,
## trunk and shoulder space clear. Resources are built once per prototype.
const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
static var _cache: Dictionary = {}
static var _envelopes: Dictionary = {}

static func parts(kind: String) -> Array[Dictionary]:
	if Catalog.has_kind(kind):
		return Catalog.collision_parts(kind)
	if _cache.has(kind):
		return _cache[kind]
	var police := kind == "police"
	var size := Vector3(1.98, 1.872, 4.40) if police else Models.dimensions(kind)
	var belt := 1.20 if police else (0.80 if kind == "compact" else (0.94 if kind == "minivan" else 0.88))
	var half := size.x * 0.5
	var length := size.z * 0.5
	var lower := PackedVector3Array()
	# Upper shoulder follows the shell; only the low wheel band needs the extra
	# tire width. The shape does not extend a wheel-width box above the doors.
	for y in [0.08, 0.60, belt]:
		var width: float = half + (0.045 if y < belt else -0.045)
		for z in [-length - 0.03, length + 0.03]:
			for side in [-1.0, 1.0]:
				lower.append(Vector3(side * width, y, z))
	var result: Array[Dictionary] = [_part("LowerBody", lower)]
	var roof_front := 0.62 if police else (0.75 if kind == "minivan" else (0.48 if kind == "compact" else 0.43))
	var roof_rear := -1.08 if police else (-1.87 if kind == "minivan" else -0.79)
	var base_front := 1.15 if police else (1.82 if kind == "minivan" else (1.25 if kind == "compact" else 1.10))
	var base_rear := -1.52 if police else (-2.10 if kind == "minivan" else (-1.43 if kind == "compact" else -1.32))
	var base_width := 0.85 if police else half * 0.91
	var roof_width := 0.77 if police else half * 0.79
	var cabin := PackedVector3Array()
	for station in [[base_rear, belt + 0.015, base_width], [roof_rear, size.y - 0.035, roof_width],
		[roof_front, size.y, roof_width], [base_front, belt + 0.015, base_width]]:
		var z := float(station[0])
		var top := float(station[1])
		var width := float(station[2])
		for side in [-1.0, 1.0]:
			cabin.append(Vector3(side * base_width, belt - 0.015, z))
			cabin.append(Vector3(side * width, top - 0.035, z))
			cabin.append(Vector3(side * width * 0.95, top, z))
	result.append(_part("Cabin", cabin))
	if police:
		var bar := PackedVector3Array()
		for x in [-0.49, 0.49]:
			for y in [1.86, 2.06]:
				for z in [-0.43, 0.03]:
					bar.append(Vector3(x, y, z))
		result.append(_part("LightBar", bar))
	_cache[kind] = result
	return result

static func envelope(kind: String) -> Dictionary:
	if _envelopes.has(kind):
		return _envelopes[kind]
	var hulls := parts(kind)
	var bounds := AABB(hulls[0].shape.points[0], Vector3.ZERO)
	for hull in hulls:
		for point in hull.shape.points:
			bounds = bounds.expand(point)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var result := {"shape": shape, "center": bounds.get_center()}
	_envelopes[kind] = result
	return result

static func _part(label: String, points: PackedVector3Array) -> Dictionary:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var radius := 0.0
	for point in points:
		radius = maxf(radius, point.length())
	# Cache supporting planes for the swept player-capsule fallback. This keeps
	# roof contacts out of the old oversized rectangular impact envelope too.
	var planes: Array[Plane] = []
	for a in points.size():
		for b in range(a + 1, points.size()):
			for c in range(b + 1, points.size()):
				var normal := (points[b] - points[a]).cross(points[c] - points[a])
				if normal.length_squared() < 0.0000001:
					continue
				normal = normal.normalized()
				var plane := Plane(normal, normal.dot(points[a]))
				var positive := false
				var negative := false
				for point in points:
					var distance := plane.distance_to(point)
					positive = positive or distance > 0.0001
					negative = negative or distance < -0.0001
				if positive and negative:
					continue
				if positive:
					plane = Plane(-plane.normal, -plane.d)
				var duplicate := false
				for existing in planes:
					if existing.normal.dot(plane.normal) > 0.9999 and absf(existing.d - plane.d) < 0.001:
						duplicate = true
						break
				if not duplicate:
					planes.append(plane)
	return {"name": label, "shape": shape, "planes": planes, "radius": radius}

static func attach(body: CollisionObject3D, kind: String) -> void:
	for part in parts(kind):
		var collider := CollisionShape3D.new()
		collider.name = part.name
		collider.shape = part.shape
		body.add_child(collider)
## Project the full collision envelope, including pitched/rolled height, onto
## the ground plane. Distant parked bodies may have their physics layer off.
static func footprint(pose: Transform3D, kind: String) -> PackedVector2Array:
	var envelope := envelope(kind)
	var half: Vector3 = (envelope.shape as BoxShape3D).size * 0.5
	var points := PackedVector2Array()
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var world: Vector3 = pose * (Vector3(envelope.center) + Vector3(half.x * x, half.y * y, half.z * z))
				points.append(Vector2(world.x, world.z))
	return Geometry2D.convex_hull(points)

## Separating axes of both convex footprints; a 20 cm gap is still required.
## This rejects genuine hull overlap without a circular five-metre exclusion
## that also blocked clear travel alongside every curb-parked car.
static func footprints_overlap(a: PackedVector2Array, b: PackedVector2Array, clearance := 0.20) -> bool:
	for polygon in [a, b]:
		for i in range(1, polygon.size()):
			var edge: Vector2 = polygon[i] - polygon[i - 1]
			if edge.length_squared() < 0.000001:
				continue
			var axis := Vector2(-edge.y, edge.x).normalized()
			var a_min := INF
			var a_max := -INF
			var b_min := INF
			var b_max := -INF
			for point in a:
				var value := point.dot(axis)
				a_min = minf(a_min, value)
				a_max = maxf(a_max, value)
			for point in b:
				var value := point.dot(axis)
				b_min = minf(b_min, value)
				b_max = maxf(b_max, value)
			if a_max + clearance < b_min or b_max + clearance < a_min:
				return false
	return true
