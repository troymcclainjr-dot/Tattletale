extends RefCounted
## Small deterministic tire/driver model layered over the traffic route. It
## proposes motion only: Vehicle owns road support, sweeps and right-of-way.
const MAX_OFFSET := 1.05
const MAX_YAW := 0.19
var offset := 0.0
var lateral_speed := 0.0
var yaw_error := 0.0
var phase := 0.0
var shock := 0.0
var recovery := 0.0
var recoveries := 0
var max_departure := 0.0

static func profile(flats: Array[int], sides: Array[float] = []) -> Dictionary:
	var count := clampi(flats.size(), 0, 4)
	var pull := 0.0
	for tire in flats:
		var side := sides[tire] if tire >= 0 and tire < sides.size() else (-1.0 if tire % 2 == 0 else 1.0)
		pull += side * (1.0 if tire < 2 else .65)
	return {"count": count, "grip": [1.0, .74, .53, .37, .27][count],
		"braking": [1.0, .72, .50, .36, .25][count], "pull": clampf(pull, -1.65, 1.65)}

func puncture() -> void:
	shock = 1.7

func reset_motion() -> void:
	offset = 0.0
	lateral_speed = 0.0
	yaw_error = 0.0
	recovery = 0.0

func request_recovery() -> void:
	if recovery <= 0.0:
		recoveries += 1
	recovery = 1.3

func step(info: Dictionary, speed: float, bend: float, dt: float, limit := MAX_OFFSET) -> Dictionary:
	if int(info.count) == 0:
		reset_motion()
		return snapshot()
	dt = clampf(dt, 0.0, .25)
	limit = clampf(limit, .12, MAX_OFFSET)
	phase = fposmod(phase + dt * (2.3 + speed * .55), TAU)
	shock = maxf(0.0, shock - dt)
	recovery = maxf(0.0, recovery - dt)
	var grip := float(info.grip)
	var moving := clampf(speed / 4.0, 0.0, 1.0)
	var wobble := sin(phase) * .026 * (1.0 - grip) * moving
	var pull := float(info.pull) * (.065 + .07 * shock / 1.7) * moving
	var countersteer := -offset * .095 - lateral_speed * .045
	var desired_yaw := clampf(pull + wobble + countersteer, -MAX_YAW, MAX_YAW)
	if absf(offset) > limit * .58 and offset * lateral_speed > 0.0:
		request_recovery()
	if recovery > 0.0:
		desired_yaw = clampf(-offset * .23 - lateral_speed * .12, -MAX_YAW, MAX_YAW)
	# Damaged wheels follow steering corrections more slowly and retain lateral
	# motion on bends. A flat rear wheel therefore differs from a healthy rail.
	yaw_error = move_toward(yaw_error, desired_yaw, dt * (.16 + grip * .27))
	var target_slip := sin(yaw_error) * speed - bend * speed * (1.0 - grip) * .45
	lateral_speed = move_toward(lateral_speed, target_slip, dt * (.65 + grip * 2.1))
	if speed < .1:
		lateral_speed = move_toward(lateral_speed, 0.0, dt * 3.0)
	var next := offset + lateral_speed * dt
	if absf(next) >= limit:
		next = clampf(next, -limit, limit)
		lateral_speed = 0.0
		request_recovery()
	offset = next
	max_departure = maxf(max_departure, absf(offset))
	return snapshot()

func snapshot() -> Dictionary:
	return {"offset": offset, "lateral_speed": lateral_speed, "yaw_error": yaw_error,
		"recovery": recovery, "recoveries": recoveries, "max_departure": max_departure}
