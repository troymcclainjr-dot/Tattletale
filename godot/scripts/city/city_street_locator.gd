extends RefCounted
## Exact original nearest-segment semantics, with a cached 2D segment BVH.
## setup() owns a snapshot; call again when road data changes. Equal-distance
## results use original road/segment order regardless of BVH visitation order.
const FALLBACK := "Pen Lucy · Baltimore"
const LEAF_SIZE := 12
var _starts := PackedVector2Array()
var _ends := PackedVector2Array()
var _names := PackedStringArray()
var _nodes: Array[Dictionary] = []
var queries := 0
var tested_segments := 0
var last_tested_segments := 0
var last_visited_nodes := 0

func setup(roads: Array) -> void:
	_starts.clear()
	_ends.clear()
	_names.clear()
	_nodes.clear()
	queries = 0
	tested_segments = 0
	last_tested_segments = 0
	last_visited_nodes = 0
	var ids: Array[int] = []
	for road in roads:
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var start := _point(points[i - 1])
			var finish := _point(points[i])
			# Such a segment cannot win the original finite-distance comparison.
			if not start.is_finite() or not finish.is_finite():
				continue
			ids.append(_starts.size())
			_starts.append(start)
			_ends.append(finish)
			_names.append(str(road.get("name", "Pen Lucy")))
	if not ids.is_empty():
		_build(ids)

static func _point(value) -> Vector2:
	# Match pen_lucy_level.vector exactly, including malformed/short point fallback.
	if value is Vector3:
		return Vector2(value.x, value.z)
	if value is Array and value.size() >= 3:
		return Vector2(float(value[0]), float(value[2]))
	return Vector2.ZERO

func _build(ids: Array[int]) -> int:
	var low := _starts[ids[0]]
	var high := low
	for id in ids:
		low = low.min(_starts[id]).min(_ends[id])
		high = high.max(_starts[id]).max(_ends[id])
	# Conservative outward padding covers float32 projection roundoff. It can
	# admit extra exact tests; it never selects a street or approximates distance.
	var magnitude := maxf(maxf(absf(low.x), absf(low.y)), maxf(absf(high.x), absf(high.y)))
	var padding := Vector2.ONE * (0.001 + magnitude * 0.000001)
	var index := _nodes.size()
	_nodes.append({"low": low - padding, "high": high + padding, "left": -1, "right": -1, "ids": PackedInt32Array()})
	if ids.size() <= LEAF_SIZE:
		_nodes[index].ids = PackedInt32Array(ids)
		return index
	var axis := 0 if high.x - low.x >= high.y - low.y else 1
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ca: float = _starts[a][axis] * 0.5 + _ends[a][axis] * 0.5
		var cb: float = _starts[b][axis] * 0.5 + _ends[b][axis] * 0.5
		return ca < cb or (ca == cb and a < b))
	var middle := ids.size() >> 1
	_nodes[index].left = _build(ids.slice(0, middle))
	_nodes[index].right = _build(ids.slice(middle))
	return index

static func _bound(point: Vector2, node: Dictionary) -> float:
	var low: Vector2 = node.low
	var high: Vector2 = node.high
	return point.distance_squared_to(Vector2(clampf(point.x, low.x, high.x), clampf(point.y, low.y, high.y)))

func nearest(at: Vector3) -> String:
	queries += 1
	last_tested_segments = 0
	last_visited_nodes = 0
	var point := Vector2(at.x, at.z)
	if _nodes.is_empty() or not point.is_finite():
		return FALLBACK
	var closest := INF
	var best := -1
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var node: Dictionary = _nodes[stack.pop_back()]
		last_visited_nodes += 1
		# Strict > is essential: equality must still visit earlier-order ties.
		if _bound(point, node) > closest:
			continue
		if int(node.left) < 0:
			for id in node.ids:
				var near := Geometry2D.get_closest_point_to_segment(point, _starts[id], _ends[id])
				var distance := near.distance_squared_to(point)
				last_tested_segments += 1
				if distance < closest or (best >= 0 and distance == closest and id < best):
					closest = distance
					best = id
		else:
			var left := int(node.left)
			var right := int(node.right)
			if _bound(point, _nodes[left]) <= _bound(point, _nodes[right]):
				stack.append(right)
				stack.append(left)
			else:
				stack.append(left)
				stack.append(right)
	tested_segments += last_tested_segments
	return _names[best] if best >= 0 else FALLBACK

func get_status() -> Dictionary:
	return {"segments": _starts.size(), "nodes": _nodes.size(), "queries": queries,
		"tested_segments": tested_segments, "last_tested_segments": last_tested_segments, "last_visited_nodes": last_visited_nodes}
