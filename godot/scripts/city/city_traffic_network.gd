extends RefCounted
## Directed lanes built from shared exported road nodes, with close junctions
## treated as one reservation zone. All lane/connector heights are cached once.

var level: Node3D
var lanes: Array[Dictionary] = []
var nodes: Dictionary = {}
var _road_cells: Dictionary = {}
# on_road() is called for every corner/support sample of each near car, many
# times per physics tick. Packed per-cell mirrors of _road_cells hold the same
# segments in the same order (endpoints interleaved a0,b0,a1,b1…, half widths
# as the same doubles), so results are identical without a default-Array
# allocation per call or three Dictionary lookups per candidate segment.
var _cell_slots: Dictionary = {}
var _cell_points: Array[PackedVector2Array] = []
var _cell_halves: Array[PackedFloat64Array] = []
var _packed_dirty := false
var _connector_cache: Dictionary = {}
var rejected_lanes := 0

## Reserve room for two moving lanes. Narrow streets retain both directions;
## only their canonical right curb is parked. The same policy places parked cars.
static func parking_mode(width: float, street: String) -> String:
	if street == "Old York Road" or width < 8.0:
		return "none"
	return "single" if width < 11.0 else "both"

static func lane_offset(width: float, street: String, reverse: bool) -> float:
	if street == "Old York Road":
		return 2.1
	if parking_mode(width, street) == "single":
		# 9.5m road: parked inner edge +2.41; moving centers +0.9/-2.3.
		# A 2.12m moving envelope retains 0.45m to the parked envelope.
		return 2.3 if reverse else 0.9
	return clampf((width - 9.5) * 0.23 + 1.20, 1.20, 2.30)

func _key(point: Vector3) -> String:
	return "%d_%d" % [roundi(point.x * 10), roundi(point.z * 10)]

func _root(key: String, parents: Dictionary) -> String:
	while str(parents[key]) != key:
		key = str(parents[key])
	return key

func setup(owner_level: Node3D) -> void:
	level = owner_level
	var owners: Dictionary = {}
	var positions: Dictionary = {}
	var roads: Array = level.level_data.get("roads", [])
	for r in roads.size():
		var road: Dictionary = roads[r]
		var points: Array = road.get("points", [])
		for i in points.size():
			var point: Vector3 = level.vector(points[i])
			var key := _key(point)
			positions[key] = point
			if not owners.has(key):
				owners[key] = []
			if not owners[key].has(r):
				owners[key].append(r)
			if i > 0:
				_index_road(level.vector(points[i - 1]), point, float(road.width))
	var raw: Array[Dictionary] = []
	var parents: Dictionary = {}
	for road in roads:
		var points: Array = road.points
		var cuts: Array[int] = []
		for i in points.size():
			var key := _key(level.vector(points[i]))
			if i == 0 or i == points.size() - 1 or owners[key].size() > 1:
				cuts.append(i)
				parents[key] = key
		for i in range(1, cuts.size()):
			var path: Array[Vector3] = []
			for p in range(cuts[i - 1], cuts[i] + 1):
				path.append(level.vector(points[p]))
			raw.append({"from": _key(path[0]), "to": _key(path[-1]), "points": path,
				"street": str(road.name), "width": float(road.width), "length": path_length(path)})
	# Tiny divided-road links and closely spaced nodes are a single junction.
	for edge in raw:
		if float(edge.length) < 26.0:
			parents[_root(str(edge.to), parents)] = _root(str(edge.from), parents)
	for key in parents:
		var id := _root(key, parents)
		if not nodes.has(id):
			nodes[id] = {"points": [], "out": [], "streets": [], "width": 7.0, "signal": false}
		nodes[id].points.append(positions[key])
		if (positions[key] as Vector3).length() < 0.5:
			nodes[id].signal = true
	for edge in raw:
		edge.from = _root(str(edge.from), parents)
		edge.to = _root(str(edge.to), parents)
		for id in [edge.from, edge.to]:
			nodes[id].width = maxf(float(nodes[id].width), float(edge.width))
			if not nodes[id].streets.has(edge.street):
				nodes[id].streets.append(edge.street)
	for edge in raw:
		if edge.from == edge.to:
			continue
		for reverse in [false, true]:
			var source: Array[Vector3] = []
			source.assign(edge.points)
			if reverse:
				source.reverse()
			var from: String = str(edge.to if reverse else edge.from)
			var to: String = str(edge.from if reverse else edge.to)
			var offset := lane_offset(float(edge.width), str(edge.street), reverse)
			var priority := "Old York Road" if nodes[to].streets.has("Old York Road") else ("Greenmount Avenue" if nodes[to].streets.has("Greenmount Avenue") else "")
			var needs_stop: bool = not bool(nodes[to].signal) and nodes[to].streets.size() > 1 and (priority.is_empty() or str(edge.street) != priority)
			var start_trim := 11.6 if bool(nodes[from].signal) else float(nodes[from].width) * 0.5 + 2.75
			var end_trim := 11.6 if bool(nodes[to].signal) else float(nodes[to].width) * 0.5 + 2.75
			var legacy_end_trim := end_trim
			if needs_stop:
				# The leading bumper waits behind a crossing band outside the
				# junction. Major-road approaches retain priority at unlit junctions.
				legacy_end_trim = maxf(end_trim, maxf(13.0, float(nodes[to].width) * 0.5 + 5.0))
				# Waiting bumpers stay behind the existing crosswalk band. Only the
				# sidewalk sign moves closer; its target is recorded for dressing.
				end_trim = legacy_end_trim
			start_trim = minf(start_trim, float(edge.length) * 0.36)
			end_trim = minf(end_trim, float(edge.length) * 0.36)
			legacy_end_trim = minf(legacy_end_trim, float(edge.length) * 0.36)
			var path := lane_path(source, start_trim, float(edge.length) - end_trim, offset)
			if not ground_path(path):
				rejected_lanes += 1
				continue
			var id := lanes.size()
			lanes.append({"id": id, "from": from, "to": to, "street": str(edge.street), "width": float(edge.width),
				"points": path, "length": path_length(path), "enabled": true, "stop": needs_stop, "offset": offset,
				"parking_mode": parking_mode(float(edge.width), str(edge.street)), "canonical_reverse": reverse,
				"junction_point": source[-1], "legacy_stop_setback": legacy_end_trim - 2.35,
				"stop_setback": maxf(float(nodes[to].width) * 0.5 + 0.4, (legacy_end_trim - 2.35) * (2.0 / 3.0)),
				"stop_line_setback": end_trim - 2.35,
				"axis": "old_york" if str(edge.street) == "Old York Road" else "wyanoke"})
			nodes[from].out.append(id)
	# Eliminate unsupported terminal chains before spawning. Every selected lane
	# must have a grounded continuation, including a valid turn at a map boundary.
	for pass_index in lanes.size():
		var changed := false
		for lane in lanes:
			if not bool(lane.enabled):
				continue
			var supported := false
			for option in choices(int(lane.id), 1):
				if not connector(int(lane.id), option).is_empty():
					supported = true
					break
			if not supported:
				lane.enabled = false
				changed = true
		if not changed:
			break

func _index_road(a: Vector3, b: Vector3, width: float) -> void:
	var margin := width * 0.5 + 1.0
	for x in range(floori((minf(a.x, b.x) - margin) / 32), floori((maxf(a.x, b.x) + margin) / 32) + 1):
		for z in range(floori((minf(a.z, b.z) - margin) / 32), floori((maxf(a.z, b.z) + margin) / 32) + 1):
			var cell := Vector2i(x, z)
			if not _road_cells.has(cell):
				_road_cells[cell] = []
			_road_cells[cell].append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "half": width * 0.5})
	_packed_dirty = true

func _pack_road_cells() -> void:
	_cell_slots.clear()
	_cell_points.clear()
	_cell_halves.clear()
	for cell in _road_cells:
		var points := PackedVector2Array()
		var halves := PackedFloat64Array()
		for road in _road_cells[cell]:
			points.append(road.a)
			points.append(road.b)
			halves.append(float(road.half))
		_cell_slots[cell] = _cell_points.size()
		_cell_points.append(points)
		_cell_halves.append(halves)
	_packed_dirty = false

func on_road(point: Vector3, margin := 0.12) -> bool:
	if _packed_dirty:
		_pack_road_cells()
	var slot: int = _cell_slots.get(Vector2i(floori(point.x / 32), floori(point.z / 32)), -1)
	if slot < 0:
		return false
	var flat := Vector2(point.x, point.z)
	var points := _cell_points[slot]
	var halves := _cell_halves[slot]
	for i in halves.size():
		if Geometry2D.get_closest_point_to_segment(flat, points[2 * i], points[2 * i + 1]).distance_to(flat) < halves[i] - margin:
			return true
	return false

func path_length(path: Array[Vector3]) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
	return length

func point_at(path: Array[Vector3], distance: float) -> Vector3:
	var travelled := 0.0
	for i in range(1, path.size()):
		var length := Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
		if travelled + length >= distance:
			return path[i - 1].lerp(path[i], clampf((distance - travelled) / maxf(length, 0.001), 0, 1))
		travelled += length
	return path[-1]

func lane_path(source: Array[Vector3], start: float, finish: float, offset: float) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var steps := maxi(2, ceili((finish - start) / 3.5))
	for i in range(steps + 1):
		var along := lerpf(start, finish, float(i) / steps)
		var at := point_at(source, along)
		var tangent := point_at(source, along + 0.5) - point_at(source, along - 0.5)
		tangent.y = 0
		path.append(at + tangent.normalized().cross(Vector3.UP) * offset)
	return rounded_path(path)

static func rounded_path(source: Array[Vector3]) -> Array[Vector3]:
	# Round the exported polyline's corners, preserving tangent continuity with
	# the straight pieces. Only bends gain samples, so long lanes stay compact.
	if source.size() < 3:
		return source.duplicate()
	var result: Array[Vector3] = [source[0]]
	for i in range(1, source.size() - 1):
		var incoming := source[i] - source[i - 1]
		var outgoing := source[i + 1] - source[i]
		var before := Vector2(incoming.x, incoming.z).length()
		var after := Vector2(outgoing.x, outgoing.z).length()
		if minf(before, after) < 0.001 or incoming.normalized().dot(outgoing.normalized()) > 0.99999:
			result.append(source[i])
			continue
		var trim := minf(2.5, minf(before, after) * 0.45)
		var a := source[i] - incoming * (trim / before)
		var b := source[i] + outgoing * (trim / after)
		result.append(a)
		var steps := maxi(4, ceili(trim * 2.0 / 0.20))
		for sample in range(1, steps + 1):
			var t := float(sample) / steps
			result.append(a * (1 - t) * (1 - t) + source[i] * 2 * (1 - t) * t + b * t * t)
	result.append(source[-1])
	return result

func ground_path(path: Array[Vector3]) -> bool:
	if path.size() < 2:
		return false
	for i in path.size():
		var p := path[i]
		if not on_road(p, 1.1):
			return false
		var forward := path[mini(path.size() - 1, i + 1)] - path[maxi(0, i - 1)]
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		# Check the full footprint once, including turns and terminal U-turns.
		# Remote cars must never traverse a curve that near physics would reject.
		for x in [-1.06, 1.06]:
			for z in [-2.35, 2.35]:
				if not on_road(p + right * x + forward * z):
					return false
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4, p - Vector3.UP * 5, 1)
		ray.hit_back_faces = false
		var ground := level.get_world_3d().direct_space_state.intersect_ray(ray)
		if ground.is_empty() or ground.normal.y < 0.82:
			return false
		p.y = float(ground.position.y) + 0.025
		path[i] = p
	return true

func connector(from_id: int, to_id: int) -> Array[Vector3]:
	var key := "%d_%d" % [from_id, to_id]
	if _connector_cache.has(key):
		return _connector_cache[key]
	var a: Array[Vector3] = lanes[from_id].points
	var b: Array[Vector3] = lanes[to_id].points
	var p0 := a[-1]
	var p3 := b[0]
	var incoming := (a[-1] - a[-2]).normalized()
	var outgoing := (b[1] - b[0]).normalized()
	var reach := clampf(p0.distance_to(p3) * 0.45, 4.5, 13.0)
	var p1 := p0 + incoming * reach
	var p2 := p3 - outgoing * reach
	var path: Array[Vector3] = []
	# Bound spacing by the control polygon, including tight terminal U-turns.
	# Coarse ~1.3m samples produced visible heading snaps at each waypoint.
	var steps := maxi(24, ceili((p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)) / 0.20))
	for i in range(steps + 1):
		var t := float(i) / steps
		var q := 1.0 - t
		path.append(p0 * q * q * q + p1 * 3 * q * q * t + p2 * 3 * q * t * t + p3 * t * t * t)
	if not ground_path(path):
		path.clear()
	_connector_cache[key] = path
	return path

func choices(lane_id: int, sequence: int) -> Array[int]:
	var lane: Dictionary = lanes[lane_id]
	var options: Array[int] = []
	for id in nodes[lane.to].out:
		if bool(lanes[int(id)].enabled):
			options.append(int(id))
	var input: Array[Vector3] = lane.points
	var forward := (input[-1] - input[-2]).normalized()
	# Prefer continuous straight streets, with deterministic occasional turns.
	options.sort_custom(func(a: int, b: int) -> bool:
		var pa: Array[Vector3] = lanes[a].points
		var pb: Array[Vector3] = lanes[b].points
		var da := forward.dot((pa[1] - pa[0]).normalized())
		var db := forward.dot((pb[1] - pb[0]).normalized())
		return da > db)
	if options.size() > 2 and sequence % 4 == 0:
		var alternate: int = options[1]
		options.remove_at(1)
		options.push_front(alternate)
	return options

func get_status() -> Dictionary:
	var streets: Dictionary = {}
	var enabled := 0
	var stop_approaches := 0
	for lane in lanes:
		if bool(lane.enabled):
			streets[lane.street] = true
			enabled += 1
			stop_approaches += int(bool(lane.stop))
	return {"lanes": lanes.size(), "junctions": nodes.size(), "streets": streets.size(), "rejected_lanes": rejected_lanes,
		"enabled_lanes": enabled, "stop_approaches": stop_approaches, "cached_connectors": _connector_cache.size()}
