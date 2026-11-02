extends RefCounted
## One park court as a playing frame: painted bounds, the hoop in play, the
## three-point arc, the check spot and the floor plane. Built once from a court
## record and free of scene queries, so rules, the opponent and tests share it.
## Dimensions follow park_courts.py: rims 1.575 m inside the baseline and an arc
## of min(6.75, width/2 - .75) joined to corner lines width/2 - .90 out.

const RIM_INSET := 1.575
const RIM_HEIGHT := 3.05
const ARC_LIMIT := 6.75
const FREE_THROW := 4.225

var id := ""
var kind := "full"
var center := Vector3.ZERO
var across := Vector3.RIGHT
var along := Vector3.BACK
var width := 15.0
var length := 28.0
var rims: Array[Vector3] = []
var hoop := 0
var _slope := 0.0
var _across_slope := 0.0
var _floor_offset := 0.0

func setup(record: Dictionary) -> RefCounted:
	id = str(record.get("id", ""))
	center = _vector(record.get("position", Vector3.ZERO))
	width = maxf(4.0, float(record.get("width_m", 15.0)))
	length = maxf(6.0, float(record.get("length_m", 28.0)))
	rims.clear()
	for entry in record.get("hoops", []):
		if entry is Dictionary and entry.has("rim_position"):
			rims.append(_vector(entry.rim_position))
	kind = str(record.get("kind", "full" if rims.size() >= 2 else "half"))
	var axis := _flat(_vector(record.get("along", Vector3.ZERO)))
	if axis.length_squared() < 0.01 and rims.size() >= 2:
		axis = _flat(rims[1] - rims[0])
	elif axis.length_squared() < 0.01 and rims.size() == 1:
		axis = _flat(center - rims[0])
	along = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.BACK
	var side := _flat(_vector(record.get("across", Vector3.ZERO)))
	across = side.normalized() if side.length_squared() > 0.01 else Vector3(-along.z, 0.0, along.x)
	# Courts are graded planes: the record origin is floor height at the centre
	# and every rim stands 3.05 m over the floor beneath it.
	_slope = 0.0
	_across_slope = 0.0
	_floor_offset = 0.0
	var reach := 0.5
	for rim_at in rims:
		var v := (rim_at - center).dot(along)
		if absf(v) > reach:
			reach = absf(v)
			_slope = (rim_at.y - RIM_HEIGHT - center.y) / v
	_read_floor_plane(record)
	hoop = 0
	return self

## The painted slab is a plane, but its apron follows surrounding terrain.
## Read one nondegenerate triangle wholly inside the paint from the same floor
## prefix used by city_park_courts collision. Sparse fixtures retain rim fallback.
func _read_floor_plane(record: Dictionary) -> void:
	var mesh_data: Dictionary = record.get("mesh", {})
	var vertices: Array = mesh_data.get("vertices", [])
	var count := mini(int(record.get("floor_triangles", 0)), vertices.size() / 9)
	for i in count:
		var triangle: Array[Vector3] = []
		for j in 3:
			var offset := i * 9 + j * 3
			var point := Vector3(float(vertices[offset]), float(vertices[offset + 1]), float(vertices[offset + 2]))
			if not point.is_finite() or absf(point.dot(across)) > width * 0.5 - 0.05 or absf(point.dot(along)) > length * 0.5 - 0.05:
				break
			triangle.append(point)
		if triangle.size() != 3:
			continue
		var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
		if normal.length_squared() < 0.000001:
			continue
		normal = normal.normalized()
		if absf(normal.y) < 0.8:
			continue
		_slope = -normal.dot(along) / normal.y
		_across_slope = -normal.dot(across) / normal.y
		_floor_offset = normal.dot(triangle[0]) / normal.y
		return

func playable() -> bool:
	return not rims.is_empty()

func full() -> bool:
	return rims.size() >= 2 and not kind.ends_with("half")

func local(point: Vector3) -> Vector2:
	var offset := point - center
	return Vector2(offset.dot(across), offset.dot(along))

func world(u: float, v: float) -> Vector3:
	var point := center + across * u + along * v
	point.y = center.y + _floor_offset + v * _slope + u * _across_slope
	return point

func floor_y(point: Vector3) -> float:
	var at := local(point)
	return center.y + _floor_offset + at.y * _slope + at.x * _across_slope

func on_floor(point: Vector3) -> Vector3:
	return Vector3(point.x, floor_y(point), point.z)

## Painted rectangle of the whole record, any hoop.
func contains(point: Vector3, margin := 0.0) -> bool:
	var at := local(point)
	return absf(at.x) <= width * 0.5 + margin and absf(at.y) <= length * 0.5 + margin

func nearest_hoop(point: Vector3) -> int:
	var best := INF
	var nearest := 0
	for i in rims.size():
		var distance := Vector2(point.x - rims[i].x, point.z - rims[i].z).length_squared()
		if distance < best:
			best = distance
			nearest = i
	return nearest

func select_hoop(point: Vector3) -> int:
	hoop = nearest_hoop(point)
	return hoop

func rim(index := -1) -> Vector3:
	var chosen := hoop if index < 0 else index
	if rims.is_empty():
		return center + Vector3.UP * RIM_HEIGHT
	return rims[clampi(chosen, 0, rims.size() - 1)]

## Horizontal unit from a rim toward the floor it defends.
func inward(index := -1) -> Vector3:
	return along * (-1.0 if (rim(index) - center).dot(along) > 0.0 else 1.0)

## (lateral, depth) from a rim; depth grows toward the top of the key.
func hoop_local(point: Vector3, index := -1) -> Vector2:
	var offset := point - rim(index)
	var inner := inward(index)
	return Vector2(offset.dot(Vector3(-inner.z, 0.0, inner.x)), offset.dot(inner))

func arc_radius() -> float:
	return minf(ARC_LIMIT, width * 0.5 - 0.75)

func corner_x() -> float:
	return width * 0.5 - 0.90

func beyond_arc(point: Vector3, index := -1) -> bool:
	var at := hoop_local(point, index)
	var radius := arc_radius()
	var corner := minf(corner_x(), radius * 0.999)
	# The straight corner lines run from the baseline to where they meet the arc.
	if at.y <= sqrt(maxf(radius * radius - corner * corner, 0.0)):
		return absf(at.x) > corner
	return at.length() > radius

func shot_value(point: Vector3, index := -1) -> int:
	return 2 if beyond_arc(point, index) else 1

## Court-local along-axis extent of the half in play: baseline to the centre
## line on a full court, the whole slab on a half court.
func play_range(index := -1) -> Vector2:
	var baseline := length * 0.5 * (1.0 if (rim(index) - center).dot(along) > 0.0 else -1.0)
	var far := 0.0 if full() else -baseline
	return Vector2(minf(baseline, far), maxf(baseline, far))

## Metres a point lies outside the half in play, 0 inside. `centre_slack` widens
## only a full court's centre-line edge (holders drifting over half court).
func outside_distance(point: Vector3, centre_slack := 0.0) -> float:
	var at := local(point)
	var span := play_range()
	if full():
		if (rim() - center).dot(along) > 0.0:
			span.x -= centre_slack
		else:
			span.y += centre_slack
	var du := maxf(0.0, absf(at.x) - width * 0.5)
	var dv := maxf(0.0, maxf(span.x - at.y, at.y - span.y))
	return sqrt(du * du + dv * dv)

func clamp_in_play(point: Vector3, margin := 0.4, index := -1) -> Vector3:
	var at := local(point)
	var span := play_range(index)
	var half_width := maxf(0.0, width * 0.5 - margin)
	return world(clampf(at.x, -half_width, half_width), clampf(at.y, span.x + margin, maxf(span.x + margin, span.y - margin)))

## Floor point `distance` from the rim, `angle` radians off the line to the top.
func spot(distance: float, angle: float, index := -1) -> Vector3:
	var inner := inward(index)
	var lateral := Vector3(-inner.z, 0.0, inner.x)
	return on_floor(rim(index) + (inner * cos(angle) + lateral * sin(angle)) * distance)

func check_spot() -> Vector3:
	return clamp_in_play(spot(arc_radius() + 0.75, 0.0), 0.6)

func free_throw_spot(index := -1) -> Vector3:
	return clamp_in_play(spot(FREE_THROW, 0.0, index), 0.5, index)

## Nearest place beyond the arc for a ball handler who must clear it.
func clear_spot(from: Vector3) -> Vector3:
	var at := hoop_local(from)
	var angle := clampf(atan2(at.x, maxf(at.y, 0.05)), -1.2, 1.2)
	var candidate := clamp_in_play(spot(arc_radius() + 0.7, angle), 0.45)
	return candidate if beyond_arc(candidate) else check_spot()

## Between an attacker and the basket, `gap` metres off the attacker.
func guard_spot(attacker: Vector3, gap: float) -> Vector3:
	var basket := on_floor(rim())
	var line := Vector3(basket.x - attacker.x, 0.0, basket.z - attacker.z)
	var distance := line.length()
	if distance < 0.05:
		return clamp_in_play(basket + inward() * 0.8, 0.4)
	return clamp_in_play(attacker + line / distance * minf(gap, distance * 0.6), 0.4)

## Walk-on places beside the half in play, away from `avoid`, then inside it.
func spawn_points(avoid: Vector3) -> Array[Vector3]:
	var span := play_range()
	var middle := (span.x + span.y) * 0.5
	var side := -1.0 if local(avoid).x > 0.0 else 1.0
	var outside := width * 0.5 + 1.3
	var points: Array[Vector3] = [world(side * outside, middle), world(-side * outside, middle), free_throw_spot(), check_spot()]
	return points

func exit_point(from: Vector3) -> Vector3:
	var at := local(from)
	var span := play_range()
	return world((1.0 if at.x >= 0.0 else -1.0) * (width * 0.5 + 3.0), clampf(at.y, span.x, span.y))

## Launch speed for `angle` that carries a ball `distance` metres across and
## `rise` metres up. Matches the balls' semi-implicit steps (gravity is applied
## before each move), which lower a step-`step` path by g*step*t/2. 0 if out of reach.
static func launch_speed(distance: float, rise: float, angle: float, gravity: float, step: float) -> float:
	var c := cos(angle)
	var reach := distance * tan(angle) - rise
	if distance < 0.01 or c < 0.01 or reach <= 0.0:
		return 0.0
	var a := gravity * distance * distance / (2.0 * c * c)
	var b := gravity * step * distance / (2.0 * c)
	var w := (-b + sqrt(b * b + 4.0 * a * reach)) / (2.0 * a)
	return 1.0 / w if w > 0.000001 else 0.0

## Angle of descent (radians below horizontal) where that arc meets its target.
static func entry_angle(distance: float, rise: float, angle: float) -> float:
	if distance < 0.01:
		return 0.0
	return atan(tan(angle) - 2.0 * rise / distance)

static func _vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

static func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
