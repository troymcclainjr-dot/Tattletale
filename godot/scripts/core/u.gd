class_name U
## Small shared helpers (engine.js). Static, so call them as U.rand(0, 1) etc.

const TAU_ := TAU


static func rand(a: float, b: float) -> float:
	return a + randf() * (b - a)


## Shortest signed angle from a to b, in (-PI, PI].
static func ang_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d < -PI:
		d += TAU
	return d


## Turn cur toward tgt by at most max_step radians.
static func turn_toward(cur: float, tgt: float, max_step: float) -> float:
	return cur + clampf(ang_diff(cur, tgt), -max_step, max_step)


## Seconds -> "m:ss" (rounds up, never negative), like the JS fmt().
static func fmt(s: float) -> String:
	var t := maxi(0, ceili(s))
	return "%d:%02d" % [t / 60, t % 60]


## Heading for a direction (dx, dz): yaw 0 faces +z, forward = (sin(yaw), cos(yaw)).
static func yaw_to(dx: float, dz: float) -> float:
	return atan2(dx, dz)
