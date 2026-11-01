extends RefCounted
## Pure steering and speed math for police cruisers, in the input convention of
## city_vehicle.gd's swept driving model: throttle/brake 0..1, steer -1 (left)
## .. +1 (right, decreasing yaw), handbrake holds; brake while stopped reverses.
## Handling figures default to the vehicle's own constants and are refreshed from
## its script when available, so the planner never assumes grip the car lacks.

static var wheelbase := 2.7
static var pivot := 1.30
static var steer_low := 0.62
static var steer_high := 0.15
static var steer_fade := 22.0
static var engine := 7.0
static var braking := 11.0
static var coast := 1.1
static var drag := 0.0022
static var top_speed := 24.0

static func configure(car: Object) -> void:
	if car == null or car.get_script() == null:
		return
	var constants: Dictionary = (car.get_script() as Script).get_script_constant_map()
	wheelbase = float(constants.get("DRIVE_WHEELBASE", wheelbase))
	pivot = float(constants.get("DRIVE_PIVOT", pivot))
	steer_low = float(constants.get("DRIVE_STEER_LOW", steer_low))
	steer_high = float(constants.get("DRIVE_STEER_HIGH", steer_high))
	steer_fade = float(constants.get("DRIVE_STEER_FADE", steer_fade))
	engine = float(constants.get("DRIVE_ENGINE", engine))
	braking = float(constants.get("DRIVE_BRAKE", braking))
	coast = float(constants.get("DRIVE_COAST", coast))
	drag = float(constants.get("DRIVE_DRAG", drag))
	top_speed = float(constants.get("DRIVE_MAX_SPEED", top_speed))

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func steering_lock(speed: float) -> float:
	return lerpf(steer_low, steer_high, clampf(absf(speed) / maxf(steer_fade, 0.1), 0.0, 1.0))

## Pure pursuit from the rear axle (the model turns about it) toward `aim`.
static func steer_toward(position: Vector3, yaw: float, speed: float, aim: Vector3) -> float:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var rear := position - forward * pivot
	var offset := Vector3(aim.x - rear.x, 0.0, aim.z - rear.z)
	var distance := offset.length()
	if distance < 0.05:
		return 0.0
	# Positive alpha: the aim lies to the left, so yaw must increase.
	var alpha := angle_difference(yaw, atan2(offset.x, offset.z))
	var curvature := 2.0 * sin(alpha) / distance
	var wheel := atan(curvature * wheelbase)
	return clampf(-wheel / steering_lock(speed), -1.0, 1.0)

## Pure pursuit while reversing toward `aim` behind the car. Viewed from the
## leading rear axle, a target to that view's left is the car's right: the
## wheels turn right (positive steer) to swing the tail that way.
static func reverse_steer_toward(position: Vector3, yaw: float, speed: float, aim: Vector3) -> float:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var rear := position - forward * pivot
	var offset := Vector3(aim.x - rear.x, 0.0, aim.z - rear.z)
	var distance := offset.length()
	if distance < 0.05:
		return 0.0
	var alpha := angle_difference(yaw + PI, atan2(offset.x, offset.z))
	var curvature := 2.0 * sin(alpha) / distance
	return clampf(atan(curvature * wheelbase) / steering_lock(speed), -1.0, 1.0)

## Pedals that approach `target` (m/s, forward) without ever reversing by
## accident: a stopped car holds on the handbrake instead of braking.
static func pedals(speed: float, target: float, planned_decel := 0.0) -> Dictionary:
	var result := {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}
	if speed < -0.3:
		# Rolling backward: throttle brakes a reversing car toward rest.
		result.throttle = 0.7
		return result
	# A stopping/curvature envelope assumes this deceleration immediately when
	# exceeded. A proportional speed controller alone lags behind that moving
	# envelope until it has consumed the intended clearance.
	if planned_decel > 0.0 and speed > maxf(target + 0.05, 0.8):
		result.brake = clampf(maxf(planned_decel / maxf(braking, 0.1), (speed - target) * 0.2), 0.0, 1.0)
		return result
	if target <= 0.15:
		if speed <= 0.8:
			result.handbrake = true
		else:
			result.brake = clampf(speed * 0.18, 0.25, 1.0)
		return result
	var error := target - speed
	var lift := maxf(engine * (1.0 - pow(clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0), 2.0)), 0.5)
	var feed := (coast + drag * speed * speed) / lift
	if error >= -0.4:
		result.throttle = clampf(feed + error * 0.45, 0.0, 1.0)
	elif error < -1.2:
		if speed > 0.4:
			result.brake = clampf(-error * 0.2, 0.12, 1.0)
		else:
			result.handbrake = true
	return result

## Backs away slowly (about 2.5 m/s); a car still rolling forward stops first.
static func reverse_pedals(speed: float) -> Dictionary:
	if speed > 0.3:
		return {"throttle": 0.0, "brake": 1.0, "steer": 0.0, "handbrake": false}
	return {"throttle": 0.0, "brake": 0.7 if speed > -2.5 else 0.0, "steer": 0.0, "handbrake": false}

static func stop_speed(distance: float, decel: float) -> float:
	return sqrt(2.0 * decel * maxf(0.0, distance))

## Per-point speed cap from path curvature (heading change over +-2 samples).
static func curve_limits(points: PackedVector3Array, lateral: float, cap: float) -> PackedFloat32Array:
	var limits := PackedFloat32Array()
	limits.resize(points.size())
	for i in points.size():
		var a := points[maxi(0, i - 2)]
		var b := points[i]
		var c := points[mini(points.size() - 1, i + 2)]
		var before := flat(a, b)
		var after := flat(b, c)
		if before < 0.05 or after < 0.05:
			limits[i] = cap
			continue
		var turn := absf(angle_difference(atan2(b.x - a.x, b.z - a.z), atan2(c.x - b.x, c.z - b.z)))
		var curvature := turn / ((before + after) * 0.5)
		limits[i] = minf(cap, sqrt(lateral / maxf(curvature, 0.0001)))
	return limits

## The highest speed now that can still slow to every cap within `horizon`.
static func allowed_speed(limits: PackedFloat32Array, sums: PackedFloat64Array, from_index: int, s: float, horizon: float, decel: float) -> float:
	var best := INF
	var i := clampi(from_index, 0, maxi(0, limits.size() - 1))
	while i < limits.size() and sums[i] <= s + horizon:
		var cap := float(limits[i])
		best = minf(best, sqrt(cap * cap + 2.0 * decel * maxf(0.0, sums[i] - s)))
		i += 1
	return best

## Closest point of the path near `cursor`: {cursor, s, lateral}.
static func track(points: PackedVector3Array, sums: PackedFloat64Array, cursor: int, at: Vector3, window := 30) -> Dictionary:
	if points.size() < 2:
		return {"cursor": 0, "s": 0.0, "lateral": flat(points[0], at) if points.size() == 1 else INF}
	var best_distance := INF
	var best_index := clampi(cursor, 0, points.size() - 2)
	var best_t := 0.0
	var first := clampi(cursor - 2, 0, points.size() - 2)
	var last := mini(points.size() - 2, maxi(cursor, 0) + window)
	for i in range(first, last + 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length_squared := ab.length_squared()
		var t := 0.0 if length_squared < 0.000001 else clampf(Vector2(at.x - a.x, at.z - a.z).dot(ab) / length_squared, 0.0, 1.0)
		var distance := (Vector2(a.x, a.z) + ab * t).distance_to(Vector2(at.x, at.z))
		if distance < best_distance - 0.0001:
			best_distance = distance
			best_index = i
			best_t = t
	return {"cursor": best_index, "s": sums[best_index] + (sums[best_index + 1] - sums[best_index]) * best_t, "lateral": best_distance}

static func point_at(points: PackedVector3Array, sums: PackedFloat64Array, s: float, hint := 0) -> Vector3:
	if points.is_empty():
		return Vector3.INF
	if s <= 0.0 or points.size() == 1:
		return points[0]
	var i := clampi(hint, 0, points.size() - 2)
	while i > 0 and sums[i] > s:
		i -= 1
	while i < points.size() - 2 and sums[i + 1] < s:
		i += 1
	var length := sums[i + 1] - sums[i]
	if s >= sums[-1]:
		return points[-1]
	return points[i].lerp(points[i + 1], clampf((s - sums[i]) / maxf(length, 0.000001), 0.0, 1.0))

static func direction_at(points: PackedVector3Array, sums: PackedFloat64Array, s: float, hint := 0) -> Vector3:
	var a := point_at(points, sums, s - 1.0, hint)
	var b := point_at(points, sums, s + 1.0, hint)
	var offset := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return offset.normalized() if offset.length_squared() > 0.0001 else Vector3.ZERO
