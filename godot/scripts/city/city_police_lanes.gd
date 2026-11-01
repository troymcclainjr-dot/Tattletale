extends RefCounted
## Cruiser routes over the traffic network's directed lanes. Lanes and junction
## connectors are the same grounded paths traffic drives (the network checks the
## whole car footprint stays on the carriageway), so a cruiser that tracks its
## path keeps its wheels off the curbs. A lane-level AStar3D is built once;
## connectors are validated lazily along a chosen route and cached by the
## network, so a plan never sweeps the whole map. Paths come back resampled at a
## uniform 1 m spacing with lane/junction metadata in path distance.

const CELL := 32.0
const SAMPLE_SPACING := 4.0
const SPACING := 1.0
const MAX_GOAL_LANES := 2
const MAX_OPTIONS := 3
const MAX_REPAIRS := 4
const GOAL_RADIUS := 64.0
const START_RADIUS := 14.0
const BLOCK_SECONDS := 45.0

var network
var graph := AStar3D.new()
var plans := 0
var failures := 0
var connector_checks := 0
var bad_links := 0
var last_reason := ""
var _cells: Dictionary = {}
var _sums: Dictionary = {}
var _blocked: Dictionary = {}

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func setup(source) -> void:
	network = source
	graph.clear()
	_cells.clear()
	_sums.clear()
	_blocked.clear()
	if source == null or not source.get("lanes") is Array:
		return
	for lane in source.lanes:
		if not bool(lane.get("enabled", false)) or (lane.points as Array).size() < 2:
			continue
		var id := int(lane.id)
		var points: Array = lane.points
		var sums := PackedFloat64Array()
		sums.resize(points.size())
		var total := 0.0
		for i in range(1, points.size()):
			total += flat(points[i - 1], points[i])
			sums[i] = total
		_sums[id] = sums
		graph.add_point(id, _at(points, sums, total * 0.5))
		var along := 0.0
		while along < total:
			_index(id, _at(points, sums, along))
			along += SAMPLE_SPACING
		_index(id, points[-1])
	for lane in source.lanes:
		var id := int(lane.id)
		if not graph.has_point(id):
			continue
		var junction = source.nodes.get(lane.to)
		if not junction is Dictionary:
			continue
		for value in junction.get("out", []):
			var next := int(value)
			if next != id and graph.has_point(next) and not graph.are_points_connected(id, next, false):
				var outgoing: Dictionary = source.lanes[next]
				# Traffic can animate a terminal hairpin whose radius is smaller
				# than a physically steered cruiser can drive. Use another street
				# (or the bounded no-route fallback), never that same-street U-turn.
				if lane.has("from") and outgoing.get("to") == lane.get("from") and outgoing.get("street") == lane.get("street"):
					continue
				graph.connect_points(id, next, false)

func lane_count() -> int:
	return graph.get_point_count()

func has_lane(id: int) -> bool:
	return id >= 0 and graph.has_point(id)

func lane_points(id: int) -> Array:
	return network.lanes[id].points

func lane_length(id: int) -> float:
	var sums: PackedFloat64Array = _sums.get(id, PackedFloat64Array())
	return sums[-1] if not sums.is_empty() else 0.0

func on_road(point: Vector3, margin := 0.12) -> bool:
	return network != null and network.has_method("on_road") and bool(network.on_road(point, margin))

## A street blocked by geometry (a cruiser stuck on it) is avoided for a while.
func block(id: int, clock: float) -> void:
	if not graph.has_point(id):
		return
	_blocked[id] = clock + BLOCK_SECONDS
	graph.set_point_disabled(id, true)

func is_blocked(id: int) -> bool:
	return _blocked.has(id)

func _expire(clock: float) -> void:
	for id in _blocked.keys():
		if clock >= float(_blocked[id]):
			_blocked.erase(id)
			if graph.has_point(int(id)):
				graph.set_point_disabled(int(id), false)

func _index(id: int, at: Vector3) -> void:
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _cells.has(cell):
		_cells[cell] = []
	var bucket: Array = _cells[cell]
	if not bucket.has(id):
		bucket.append(id)

static func _at(points: Array, sums: PackedFloat64Array, along: float) -> Vector3:
	if along <= 0.0:
		return points[0]
	for i in range(1, points.size()):
		if sums[i] >= along:
			var length := sums[i] - sums[i - 1]
			var t := 0.0 if length < 0.000001 else (along - sums[i - 1]) / length
			return (points[i - 1] as Vector3).lerp(points[i], clampf(t, 0.0, 1.0))
	return points[-1]

## Closest point of one lane: {along, point, distance, tangent}.
func project(id: int, at: Vector3) -> Dictionary:
	var points: Array = network.lanes[id].points
	var sums: PackedFloat64Array = _sums[id]
	var best := {"along": 0.0, "point": points[0], "distance": INF, "tangent": Vector3.FORWARD}
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length_squared := ab.length_squared()
		var t := 0.0 if length_squared < 0.000001 else clampf(Vector2(at.x - a.x, at.z - a.z).dot(ab) / length_squared, 0.0, 1.0)
		var point := a.lerp(b, t)
		var distance := flat(point, at)
		if distance < float(best.distance):
			var tangent := Vector3(ab.x, 0.0, ab.y)
			best = {"along": sums[i - 1] + (sums[i] - sums[i - 1]) * t, "point": point, "distance": distance,
				"tangent": tangent.normalized() if tangent.length_squared() > 0.0 else Vector3.FORWARD}
	return best

## Nearby lanes, nearest first, whose direction agrees with `heading` (dot >= min_dot).
func nearest(at: Vector3, heading := Vector3.ZERO, radius := START_RADIUS, min_dot := -2.0, limit := 4) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if network == null or not at.is_finite():
		return found
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	var reach := maxi(1, ceili(radius / CELL))
	var seen: Dictionary = {}
	var flat_heading := Vector3(heading.x, 0.0, heading.z)
	var directed := flat_heading.length_squared() > 0.0001
	if directed:
		flat_heading = flat_heading.normalized()
	for x in range(cell.x - reach, cell.x + reach + 1):
		for z in range(cell.y - reach, cell.y + reach + 1):
			for value in _cells.get(Vector2i(x, z), []):
				var id := int(value)
				if seen.has(id):
					continue
				seen[id] = true
				var hit := project(id, at)
				if float(hit.distance) > radius:
					continue
				if directed and (hit.tangent as Vector3).dot(flat_heading) < min_dot:
					continue
				hit["lane"] = id
				found.append(hit)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	if found.size() > limit:
		found.resize(limit)
	return found

func _successors(id: int) -> Array[int]:
	var result: Array[int] = []
	var junction = network.nodes.get(network.lanes[id].to)
	if not junction is Dictionary:
		return result
	for value in junction.get("out", []):
		var next := int(value)
		if next != id and graph.has_point(next) and not graph.is_point_disabled(next) and graph.are_points_connected(id, next, false):
			result.append(next)
	return result

func _path_cost(ids: PackedInt64Array) -> float:
	var cost := 0.0
	for i in range(1, ids.size()):
		cost += graph.get_point_position(ids[i - 1]).distance_to(graph.get_point_position(ids[i]))
	return cost

## Plans from the car's pose to the lane point nearest `goal`.
## start_lane/start_along place the car on a lane (start_lane < 0 searches
## lanes aligned with `heading`); `lead` is a short drivable prefix (the rest of
## a junction connector the car is already on) that ends where start_lane
## begins at start_along. Returns {ok, reason, points, length, segments,
## junctions, goal_lane, goal_point, end_gap}. Segments and junctions carry path
## distance (s) so a replan can resume on the lane the car is driving.
func plan(from: Vector3, heading: Vector3, goal: Vector3, start_lane := -1, start_along := -1.0,
		lead := PackedVector3Array(), max_length := 1000.0, clock := 0.0) -> Dictionary:
	plans += 1
	_expire(clock)
	var empty := {"ok": false, "reason": "", "points": PackedVector3Array(), "length": 0.0, "segments": [], "junctions": [],
		"goal_lane": -1, "goal_point": Vector3.INF, "end_gap": INF}
	if network == null or graph.get_point_count() == 0:
		return _fail(empty, "no lane network")
	if not goal.is_finite() or not from.is_finite():
		return _fail(empty, "invalid endpoints")
	if not has_lane(start_lane):
		# The nearest lane the car is already pointing along, never a blocked one.
		start_lane = -1
		for candidate in nearest(from, heading, START_RADIUS, 0.45, 4):
			if not graph.is_point_disabled(int(candidate.lane)):
				start_lane = int(candidate.lane)
				start_along = float(candidate.along)
				break
		if start_lane < 0:
			return _fail(empty, "car is off the lane network")
	elif start_along < 0.0:
		start_along = float(project(start_lane, from).along)
	var goals := nearest(goal, Vector3.ZERO, GOAL_RADIUS, -2.0, MAX_GOAL_LANES * 2)
	if goals.is_empty():
		return _fail(empty, "no street near the goal")
	for attempt in MAX_REPAIRS:
		var best: Dictionary = {}
		var used := 0
		for candidate in goals:
			if used >= MAX_GOAL_LANES:
				break
			var target := int(candidate.lane)
			if graph.is_point_disabled(target) and target != start_lane:
				continue
			used += 1
			var along_goal := float(candidate.along)
			if target == start_lane and along_goal >= start_along + 0.5:
				var direct := along_goal - start_along
				if best.is_empty() or direct < float(best.cost):
					best = {"cost": direct, "lanes": [start_lane], "final": along_goal, "goal": candidate}
				continue
			var options := 0
			for next in _successors(start_lane):
				if options >= MAX_OPTIONS:
					break
				options += 1
				var ids := PackedInt64Array()
				if next == target:
					ids.append(next)
				else:
					ids = graph.get_id_path(next, target)
				if ids.is_empty():
					continue
				var cost := lane_length(start_lane) - start_along + _path_cost(ids) + along_goal
				if best.is_empty() or cost < float(best.cost):
					var sequence: Array = [start_lane]
					for value in ids:
						sequence.append(int(value))
					best = {"cost": cost, "lanes": sequence, "final": along_goal, "goal": candidate}
		if best.is_empty():
			return _fail(empty, "no lane route to the goal")
		var built := assemble(best.lanes, start_along, float(best.final), lead)
		if not bool(built.ok):
			# A turn traffic never validated: forget that link and look again.
			var a := int(built.get("bad_from", -1))
			var b := int(built.get("bad_to", -1))
			if a >= 0 and b >= 0 and graph.are_points_connected(a, b, false):
				graph.disconnect_points(a, b, false)
				bad_links += 1
				continue
			return _fail(empty, str(built.get("reason", "route assembly failed")))
		if float(built.length) > max_length:
			return _fail(empty, "route too long")
		built["goal_lane"] = int((best.goal as Dictionary).lane)
		built["goal_point"] = (best.goal as Dictionary).point
		built["end_gap"] = float((best.goal as Dictionary).distance)
		built["reason"] = ""
		last_reason = ""
		return built
	return _fail(empty, "no valid turn sequence")

func _fail(result: Dictionary, reason: String) -> Dictionary:
	failures += 1
	last_reason = reason
	result.reason = reason
	return result

## Keeps driving from a lane position for about `distance` metres, preferring at
## each junction the exit that best continues `heading` (a search or departure).
func continuation(start_lane: int, start_along: float, heading: Vector3, distance: float, lead := PackedVector3Array()) -> Dictionary:
	if not has_lane(start_lane):
		return {"ok": false, "reason": "no lane", "points": PackedVector3Array(), "length": 0.0, "segments": [], "junctions": []}
	var sequence: Array = [start_lane]
	var total := lane_length(start_lane) - start_along
	var current := start_lane
	var flat_heading := Vector3(heading.x, 0.0, heading.z)
	flat_heading = flat_heading.normalized() if flat_heading.length_squared() > 0.0001 else Vector3.ZERO
	var guard := 0
	while total < distance and guard < 6:
		guard += 1
		var best := -1
		var score := -INF
		for next in _successors(current):
			if network.connector(current, next).is_empty():
				continue
			connector_checks += 1
			var points: Array = network.lanes[next].points
			var direction := Vector3(points[1].x - points[0].x, 0.0, points[1].z - points[0].z).normalized()
			var value := direction.dot(flat_heading) if flat_heading != Vector3.ZERO else 0.0
			if value > score:
				score = value
				best = next
		if best < 0:
			break
		sequence.append(best)
		total += lane_length(best)
		current = best
		var exit_points: Array = network.lanes[best].points
		flat_heading = Vector3(exit_points[-1].x - exit_points[-2].x, 0.0, exit_points[-1].z - exit_points[-2].z).normalized()
	var final_along := lane_length(int(sequence[-1]))
	if sequence.size() == 1:
		final_along = minf(lane_length(start_lane), start_along + distance)
	return assemble(sequence, start_along, final_along, lead)

## Lane sequence -> resampled path. The first lane starts at start_along (after
## `lead`), the last stops at final_along; consecutive lanes are joined by the
## network's validated connector. A missing connector reports its link.
func assemble(sequence: Array, start_along: float, final_along: float, lead := PackedVector3Array()) -> Dictionary:
	var raw := PackedVector3Array()
	var marks: Array[Dictionary] = []
	for point in lead:
		_append(raw, point)
	for index in sequence.size():
		var id := int(sequence[index])
		if index > 0:
			var previous := int(sequence[index - 1])
			connector_checks += 1
			var joint: Array = network.connector(previous, id)
			if joint.is_empty():
				return {"ok": false, "reason": "unsupported turn", "bad_from": previous, "bad_to": id}
			var lane: Dictionary = network.lanes[previous]
			var junction = network.nodes.get(lane.to, {})
			var entry_length := _length(raw)
			marks.append({"kind": "junction", "raw_s": entry_length, "node": str(lane.to), "lane": previous, "next": id,
				"signal": bool(junction.get("signal", false)), "stop": bool(lane.get("stop", false)), "axis": str(lane.get("axis", "")),
				"center": _center(junction, joint), "radius": float(junction.get("width", 7.0)) * 0.5 + 4.0})
			for i in range(1, joint.size()):
				_append(raw, joint[i])
			marks.append({"kind": "junction_exit", "raw_s": _length(raw)})
		var begin := start_along if index == 0 else 0.0
		var finish := final_along if index == sequence.size() - 1 else lane_length(id)
		marks.append({"kind": "lane", "raw_s": _length(raw), "lane": id, "along": begin})
		_append_lane(raw, id, begin, finish)
	if raw.is_empty():
		return {"ok": false, "reason": "empty route"}
	var points := resample(raw, SPACING)
	var sums := cumulative(points)
	var length := sums[-1]
	var segments: Array = []
	var junctions: Array = []
	for mark in marks:
		var s := clampf(float(mark.raw_s), 0.0, length)
		match str(mark.kind):
			"lane":
				segments.append({"kind": "lane", "s": s, "lane": int(mark.lane), "along": float(mark.along)})
			"junction":
				var entry := mark.duplicate()
				entry.erase("raw_s")
				entry.erase("kind")
				entry["s"] = s
				junctions.append(entry)
				segments.append({"kind": "connector", "s": s, "lane": int(mark.next), "along": 0.0})
			"junction_exit":
				if not junctions.is_empty():
					(junctions[-1] as Dictionary)["exit_s"] = s
	if not lead.is_empty():
		segments.push_front({"kind": "lead", "s": 0.0, "lane": int(sequence[0]), "along": start_along})
	return {"ok": true, "points": points, "sums": sums, "length": length, "segments": segments, "junctions": junctions}

## Flat cumulative distance of each point from the first.
static func cumulative(points: PackedVector3Array) -> PackedFloat64Array:
	var sums := PackedFloat64Array()
	sums.resize(points.size())
	for i in range(1, points.size()):
		sums[i] = sums[i - 1] + flat(points[i - 1], points[i])
	return sums

static func _center(junction, joint: Array) -> Vector3:
	var points: Array = junction.get("points", []) if junction is Dictionary else []
	if points.is_empty():
		return (joint[0] as Vector3).lerp(joint[-1], 0.5)
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())

func _append_lane(raw: PackedVector3Array, id: int, begin: float, finish: float) -> void:
	var points: Array = network.lanes[id].points
	var sums: PackedFloat64Array = _sums[id]
	if finish < begin:
		finish = begin
	_append(raw, _at(points, sums, begin))
	for i in points.size():
		if sums[i] > begin + 0.001 and sums[i] < finish - 0.001:
			_append(raw, points[i])
	_append(raw, _at(points, sums, finish))

static func _append(raw: PackedVector3Array, point: Vector3) -> void:
	if raw.is_empty() or flat(raw[-1], point) > 0.02:
		raw.append(point)

static func _length(raw: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, raw.size()):
		length += flat(raw[i - 1], raw[i])
	return length

## Uniform arc-length samples (flat distance), keeping the original heights.
static func resample(raw: PackedVector3Array, spacing := SPACING) -> PackedVector3Array:
	var result := PackedVector3Array()
	if raw.is_empty():
		return result
	result.append(raw[0])
	var carried := 0.0
	for i in range(1, raw.size()):
		var a := raw[i - 1]
		var b := raw[i]
		var length := flat(a, b)
		if length < 0.000001:
			continue
		var along := spacing - carried
		while along <= length + 0.000001:
			result.append(a.lerp(b, along / length))
			along += spacing
		carried = length - (along - spacing)
	if flat(result[-1], raw[-1]) > 0.05:
		result.append(raw[-1])
	return result
