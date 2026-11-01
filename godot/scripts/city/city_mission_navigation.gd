extends RefCounted
## Shared, cached map guidance along surveyed streets and the authored sidewalk walk.
## Only endpoint links need obstacle checks; a missing safe link yields a marker, never
## a guessed straight line through a building. Both maps consume this same route.
const CELL := 48.0
const REFRESH_SECONDS := 0.75
const MAX_LINK := 32.0
var graph := AStar3D.new()
var segments: Array[Dictionary] = []
var cells: Dictionary = {}
var points: Dictionary = {}
var route := PackedVector3Array()
var target := Vector3.ZERO
var active_id := ""
var stage := -1
var build_count := 0
var route_build_count := 0
var revision := 0
var clear_link: Callable
var _elapsed := 0.0
var _routed_target := Vector3.INF
var _temporary: Array[int] = []
var _attachments: Dictionary = {}

static func _vec(value) -> Vector3:
	return value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))

func _point(at: Vector3) -> int:
	var key := Vector2i(roundi(at.x * 10.0), roundi(at.z * 10.0))
	if points.has(key):
		return int(points[key])
	var id := graph.get_available_point_id()
	graph.add_point(id, at)
	points[key] = id
	return id

func _segment(a: Vector3, b: Vector3, walk := false) -> void:
	if a.distance_to(b) < 0.01:
		return
	var from := _point(a)
	var to := _point(b)
	if from == to:
		return
	if not graph.are_points_connected(from, to):
		graph.connect_points(from, to)
	var id := segments.size()
	segments.append({"a": a, "b": b, "from": from, "to": to, "walk": walk})
	var bounds := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z))
	for x in range(floori(bounds.position.x / CELL), floori(bounds.end.x / CELL) + 1):
		for z in range(floori(bounds.position.y / CELL), floori(bounds.end.y / CELL) + 1):
			var key := Vector2i(x, z)
			if not cells.has(key):
				cells[key] = []
			cells[key].append(id)

func setup(data: Dictionary, obstacle_clear: Callable = Callable()) -> void:
	graph.clear()
	segments.clear()
	cells.clear()
	points.clear()
	clear_link = obstacle_clear
	for road in data.get("roads", []):
		var vertices: Array = road.get("points", [])
		for i in range(1, vertices.size()):
			_segment(_vec(vertices[i - 1]), _vec(vertices[i]))
	var walk: Array = data.get("route", {}).get("points", [])
	for i in range(1, walk.size()):
		_segment(_vec(walk[i - 1]), _vec(walk[i]), true)
	# Join the authored sidewalk to nearby surveyed road samples at intervals.
	# A bounded short clear link crosses only the street/sidewalk approach.
	for i in range(0, walk.size(), 8):
		var at := _vec(walk[i])
		var from := _point(at)
		var nearest := -1
		var best := 12.0 * 12.0
		for candidate in _candidates(at):
			var edge: Dictionary = segments[int(candidate.id)]
			if bool(edge.walk):
				continue
			for to in [int(edge.from), int(edge.to)]:
				if to == from or graph.are_points_connected(from, to):
					continue
				var other := graph.get_point_position(to)
				var distance := at.distance_squared_to(other)
				if distance < best and _clear(at, other):
					nearest = to
					best = distance
		if nearest >= 0:
			graph.connect_points(from, nearest)
	build_count += 1
	clear()

func _clear(a: Vector3, b: Vector3) -> bool:
	return not clear_link.is_valid() or bool(clear_link.call(a, b))

func _candidates(at: Vector3) -> Array[Dictionary]:
	var found: Dictionary = {}
	var result: Array[Dictionary] = []
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			for id in cells.get(Vector2i(x, z), []):
				if found.has(id):
					continue
				found[id] = true
				var edge: Dictionary = segments[id]
				var a: Vector3 = edge.a
				var b: Vector3 = edge.b
				var flat := Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
				var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
				var t := Vector2(a.x, a.z).distance_to(flat) / maxf(length, 0.001)
				var projected := a.lerp(b, t)
				var distance := at.distance_squared_to(projected)
				if distance <= MAX_LINK * MAX_LINK:
					result.append({"id": id, "at": projected, "distance": distance})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
	return result

func _temporary_point(at: Vector3) -> int:
	var id := graph.get_available_point_id()
	graph.add_point(id, at)
	_temporary.append(id)
	return id

func _attach(at: Vector3) -> int:
	var root := _temporary_point(at)
	var count := 0
	var examined := 0
	for candidate in _candidates(at):
		examined += 1
		if examined > 20:
			break
		var projected: Vector3 = candidate.at
		if not _clear(at, projected):
			continue
		var edge: Dictionary = segments[int(candidate.id)]
		var join := _temporary_point(projected)
		graph.connect_points(root, join)
		graph.connect_points(join, int(edge.from))
		graph.connect_points(join, int(edge.to))
		for previous in _attachments.get(candidate.id, []):
			graph.connect_points(join, previous)
		if not _attachments.has(candidate.id):
			_attachments[candidate.id] = []
		_attachments[candidate.id].append(join)
		count += 1
		if count >= 4:
			break
	return root

func _rebuild(here: Vector3) -> void:
	var from := _attach(here)
	var to := _attach(target)
	route = graph.get_point_path(from, to)
	for id in _temporary:
		graph.remove_point(id)
	_temporary.clear()
	_attachments.clear()
	_routed_target = target
	_elapsed = 0.0
	route_build_count += 1
	revision += 1

func clear() -> void:
	route.clear()
	active_id = ""
	stage = -1
	_routed_target = Vector3.INF
	_elapsed = 0.0
	revision += 1

func _distance_to_route(here: Vector3) -> float:
	var closest := INF
	for i in range(1, route.size()):
		var a := Vector2(route[i - 1].x, route[i - 1].z)
		var b := Vector2(route[i].x, route[i].z)
		closest = minf(closest, Geometry2D.get_closest_point_to_segment(Vector2(here.x, here.z), a, b).distance_to(Vector2(here.x, here.z)))
	return closest

func _trim_followed_route(here: Vector3) -> void:
	var best := INF
	var best_index := -1
	var nearest := Vector3.ZERO
	for i in range(1, route.size()):
		var point := Geometry3D.get_closest_point_to_segment(here, route[i - 1], route[i])
		var distance := here.distance_squared_to(point)
		if distance < best:
			best = distance
			best_index = i - 1
			nearest = point
	if best_index < 0 or (best_index == 0 and here.distance_to(route[0]) < 4.0):
		return
	var remaining := PackedVector3Array()
	if _clear(here, nearest):
		remaining.append(here)
	remaining.append(nearest)
	remaining.append_array(route.slice(best_index + 1))
	route = remaining
	revision += 1

func update(status: Dictionary, here: Vector3, delta: float, force := false) -> void:
	_elapsed += delta
	var id := str(status.get("active_id", ""))
	if id.is_empty():
		if not active_id.is_empty() or not route.is_empty():
			clear()
		return
	var next_stage := int(status.get("stage", 0))
	var changed := id != active_id or next_stage != stage
	active_id = id
	stage = next_stage
	target = _vec(status.get("target_position", Vector3.ZERO))
	if changed or force:
		_rebuild(here)
	elif _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		if target.distance_to(_routed_target) > 2.0 or _distance_to_route(here) > 7.0:
			_rebuild(here)
		else:
			_trim_followed_route(here)
