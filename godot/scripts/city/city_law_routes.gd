extends RefCounted
## Bounded foot routes for responding officers along the surveyed street centre
## lines. Roads share exact vertices at intersections, so one keyed point per
## vertex joins the network. Built once; a route only obstacle-checks its two end
## links (and one shortcut), so planning never sweeps whole blocks.
const CELL := 48.0
const ATTACH_RADIUS := 48.0
const MAX_ATTACH_CHECKS := 8
const DIRECT_LIMIT := 36.0
var graph := AStar3D.new()
var clear_link: Callable
var routes_built := 0
var link_checks := 0
var _keys: Dictionary = {}
var _cells: Dictionary = {}

static func vec(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

func setup(roads: Array, obstacle_clear: Callable = Callable()) -> void:
	graph.clear()
	_keys.clear()
	_cells.clear()
	clear_link = obstacle_clear
	for road in roads:
		if not road is Dictionary:
			continue
		var previous := -1
		for value in road.get("points", []):
			var at := vec(value)
			if not at.is_finite():
				continue
			var id := _point(at)
			if previous >= 0 and previous != id and not graph.are_points_connected(previous, id):
				graph.connect_points(previous, id)
			previous = id

func point_count() -> int:
	return graph.get_point_count()

func _point(at: Vector3) -> int:
	var key := Vector2i(roundi(at.x * 10.0), roundi(at.z * 10.0))
	if _keys.has(key):
		return int(_keys[key])
	var id := graph.get_available_point_id()
	graph.add_point(id, at)
	_keys[key] = id
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(id)
	return id

func _clear(a: Vector3, b: Vector3) -> bool:
	link_checks += 1
	return not clear_link.is_valid() or bool(clear_link.call(a, b))

func _nearby(at: Vector3) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			for id in _cells.get(Vector2i(x, z), []):
				var point := graph.get_point_position(int(id))
				var distance := Vector2(point.x - at.x, point.z - at.z).length()
				if distance <= ATTACH_RADIUS:
					found.append({"id": int(id), "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return found

## Nearest street vertex with a clear walking link, or -1.
func _attach(at: Vector3) -> int:
	var checks := 0
	for entry in _nearby(at):
		if checks >= MAX_ATTACH_CHECKS:
			break
		checks += 1
		if _clear(at, graph.get_point_position(int(entry.id))):
			return int(entry.id)
	return -1

## Returns {"points": PackedVector3Array (excluding `from`), "length": float,
## "complete": bool}. Empty points means no route. An incomplete route ends on
## the street nearest an unreachable destination (a yard behind a fence).
func route(from: Vector3, to: Vector3, max_length := 380.0) -> Dictionary:
	routes_built += 1
	var points := PackedVector3Array()
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	if flat <= DIRECT_LIMIT and _clear(from, to):
		points.append(to)
		return {"points": points, "length": from.distance_to(to), "complete": true}
	if graph.get_point_count() == 0:
		return {"points": points, "length": 0.0, "complete": false}
	var start := _attach(from)
	if start < 0:
		return {"points": points, "length": 0.0, "complete": false}
	var finish := _attach(to)
	var complete := finish >= 0
	if not complete:
		var near := _nearby(to)
		if near.is_empty():
			return {"points": points, "length": 0.0, "complete": false}
		finish = int(near[0].id)
	var path := graph.get_point_path(start, finish)
	if path.is_empty():
		return {"points": points, "length": 0.0, "complete": false}
	# Skip a first vertex behind the officer when the next one is directly reachable.
	var first := 0
	if path.size() >= 2 and _clear(from, path[1]):
		first = 1
	var length := 0.0
	var previous := from
	for index in range(first, path.size()):
		length += previous.distance_to(path[index])
		previous = path[index]
		points.append(path[index])
	if complete:
		length += previous.distance_to(to)
		points.append(to)
	if length > max_length:
		return {"points": PackedVector3Array(), "length": length, "complete": false}
	return {"points": points, "length": length, "complete": complete}
