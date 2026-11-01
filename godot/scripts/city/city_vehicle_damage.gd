extends RefCounted
## Shot-only narrowphase. Cylinders follow the visible wheels, without adding
## collision bodies or per-frame fleet work. Cylinder axis is vehicle-local X.

static func ray_tire(from: Vector3, to: Vector3, pose: Transform3D, radius: float, half_width := 0.115) -> Dictionary:
	var inverse := pose.affine_inverse()
	var start := inverse * from
	var motion := inverse * to - start
	var first := 0.0
	var last := 1.0
	if absf(motion.x) < 0.000001:
		if absf(start.x) > half_width:
			return {}
	else:
		var a := (-half_width - start.x) / motion.x
		var b := (half_width - start.x) / motion.x
		first = maxf(first, minf(a, b))
		last = minf(last, maxf(a, b))
	var radial_start := Vector2(start.y, start.z)
	var radial_motion := Vector2(motion.y, motion.z)
	var aa := radial_motion.length_squared()
	var cc := radial_start.length_squared() - radius * radius
	if aa < 0.000001:
		if cc > 0.0:
			return {}
	else:
		var bb := 2.0 * radial_start.dot(radial_motion)
		var discriminant := bb * bb - 4.0 * aa * cc
		if discriminant < 0.0:
			return {}
		var root := sqrt(discriminant)
		first = maxf(first, (-bb - root) / (2.0 * aa))
		last = minf(last, (-bb + root) / (2.0 * aa))
	if first > last or last < 0.0 or first > 1.0:
		return {}
	var local := start + motion * first
	var normal := Vector3(signf(local.x), 0, 0) if absf(absf(local.x) - half_width) < 0.001 else Vector3(0, local.y, local.z).normalized()
	var position := from.lerp(to, first)
	return {"position": position, "normal": (pose.basis.inverse().transposed() * normal).normalized(),
		"distance": from.distance_to(position), "vehicle_hit": true}

static func flat_basis(base: Basis, spin_axis: Vector3, spin: float, flat: bool) -> Basis:
	var squash := Basis.from_scale(Vector3(1.08, 0.55, 1.10)) if flat else Basis.IDENTITY
	return squash * base * Basis(spin_axis, spin)

static func ray_hull(from: Vector3, to: Vector3, pose: Transform3D, parts: Array[Dictionary]) -> Dictionary:
	# Clip the finite segment against the same convex face planes as physical
	# collision. This also supplies occlusion for cars outside physics presence.
	var inverse := pose.affine_inverse()
	var start := inverse * from
	var motion := inverse * to - start
	var nearest: Dictionary = {}
	for part in parts:
		var first := 0.0
		var last := 1.0
		var normal := -motion.normalized()
		for plane in part.planes:
			var distance: float = plane.distance_to(start)
			var rate: float = plane.normal.dot(motion)
			if absf(rate) < 0.000001:
				if distance > 0.0:
					last = -1.0
					break
				continue
			var crossing := -distance / rate
			if rate < 0.0:
				if crossing > first:
					first = crossing
					normal = plane.normal
			else:
				last = minf(last, crossing)
			if first > last:
				break
		if first > last or last < 0.0 or first > 1.0:
			continue
		var position := from.lerp(to, first)
		var distance := from.distance_to(position)
		if nearest.is_empty() or distance < float(nearest.distance):
			nearest = {"position": position, "normal": (pose.basis.inverse().transposed() * normal).normalized(),
				"distance": distance, "vehicle_hit": true}
	return nearest

static func speed_factor(flats: int) -> float:
	return [1.0, 0.70, 0.48, 0.32, 0.20][clampi(flats, 0, 4)]
