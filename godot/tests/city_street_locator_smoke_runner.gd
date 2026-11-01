extends Node
## Differential oracle is the original level scan, retaining its conversions,
## segment primitive, strict-less update and source-order tie behavior.
const Locator := preload("res://scripts/city/city_street_locator.gd")
const DATA := "res://assets/data/pen_lucy_level.json"
var failures := 0
var comparisons := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[street_locator] %s %s" % ["PASS" if ok else "FAIL", label])

static func vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

static func original(roads: Array, at: Vector3) -> String:
	var closest := INF
	var street := "Pen Lucy · Baltimore"
	var point := Vector2(at.x, at.z)
	for road in roads:
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var p := vector(points[i - 1])
			var q := vector(points[i])
			var near := Geometry2D.get_closest_point_to_segment(point, Vector2(p.x, p.z), Vector2(q.x, q.z))
			var distance := near.distance_squared_to(point)
			if distance < closest:
				closest = distance
				street = str(road.get("name", "Pen Lucy"))
	return street

func compare(locator, roads: Array, points: Array[Vector3], label: String) -> void:
	var bad := 0
	for point in points:
		var expected := original(roads, point)
		var actual: String = locator.nearest(point)
		comparisons += 1
		if expected != actual:
			if bad < 4:
				print("[street_locator] mismatch %s at %s: expected '%s', got '%s'" % [label, point, expected, actual])
			bad += 1
	check(bad == 0, "%s: %d exact original comparisons" % [label, points.size()])

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	check(parsed is Dictionary and parsed.get("roads") is Array, "actual map road data loaded")
	if not parsed is Dictionary or not parsed.get("roads") is Array:
		get_tree().quit(1)
		return
	var roads: Array = parsed.roads
	var locator := Locator.new()
	var setup_start := Time.get_ticks_usec()
	locator.setup(roads)
	var setup_usec := Time.get_ticks_usec() - setup_start
	var points: Array[Vector3] = []
	var low := Vector3(INF, 0, INF)
	var high := Vector3(-INF, 0, -INF)
	for road in roads:
		for raw in road.get("points", []):
			var point := vector(raw)
			points.append(point)
			low.x = minf(low.x, point.x)
			low.z = minf(low.z, point.z)
			high.x = maxf(high.x, point.x)
			high.z = maxf(high.z, point.z)
	compare(locator, roads, points, "every actual road point")
	var grid: Array[Vector3] = []
	for x in range(-4, 37):
		for z in range(-4, 37):
			grid.append(Vector3(lerpf(low.x, high.x, float(x) / 32.0), 99.0, lerpf(low.z, high.z, float(z) / 32.0)))
	compare(locator, roads, grid, "full-map grid including outside edges")
	var mids: Array[Vector3] = []
	for road in roads:
		var vertices: Array = road.get("points", [])
		for i in range(1, vertices.size()):
			var middle := vector(vertices[i - 1]).lerp(vector(vertices[i]), 0.5)
			mids.append(middle)
			mids.append(middle + Vector3(0.0001, 1000, -0.0001))
			mids.append(middle + Vector3(-0.0001, -1000, 0.0001))
	compare(locator, roads, mids, "every segment midpoint and near-boundary offsets")
	var far: Array[Vector3] = [Vector3.ZERO, Vector3(1e7, 0, 1e7), Vector3(-1e7, 0, 1e7),
		Vector3(1e7, 0, -1e7), Vector3(-1e7, 0, -1e7), Vector3(0, INF, 0), Vector3(INF, 0, 0), Vector3(NAN, 0, 0)]
	compare(locator, roads, far, "far off-map/nonfinite and ignored-height semantics")
	_check_degenerate()
	_benchmark(locator, roads, grid, setup_usec)
	print("[street_locator] %d differential comparisons; %d failures" % [comparisons, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_degenerate() -> void:
	var locator := Locator.new()
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(0, 100, 4), Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(10000, 0, -10000)]
	locator.setup([])
	compare(locator, [], positions, "empty roads fallback")
	var roads: Array = [{"name": "Empty", "points": []}, {"name": "Single", "points": [[999, 0, 999]]},
		{"name": "Earlier tie", "points": [[-1, 0, -10], [-1, 0, 10]]},
		{"name": "Later tie", "points": [[1, 0, -10], [1, 0, 10]]},
		{"name": "Zero segment", "points": [[0, 0, 0], [0, 50, 0]]},
		{"points": [[100, 0, 100], [100, 0, 101]]},
		{"name": "", "points": [Vector3(-100, 0, -100), Vector3(-101, 0, -100)]},
		{"name": "Malformed point defaults", "points": [[], null, Vector3(0, 3, -5)]}]
	# Force multiple BVH leaves and source-order ties across reordered partitions.
	for i in 40:
		roads.append({"name": "Far filler %d" % i, "points": [[1000 + i, 0, 1000], [1000 + i, 0, 1010]]})
	positions.append_array([Vector3(0, 0, 8), Vector3(100, 0, 100.5), Vector3(-100, 0, -100), Vector3(0.000001, 0, 8), Vector3(-0.000001, 0, 8)])
	locator.setup(roads)
	compare(locator, roads, positions, "degenerate/missing-name/empty-name/source-order ties")
	check(locator.nearest(Vector3(0, 0, 8)) == "Earlier tie", "equidistant segments retain original first street")
	var split_ties: Array = [{"name": "Earlier right", "points": [[1, 0, -10], [1, 0, 10]]},
		{"name": "Later left", "points": [[-1, 0, -10], [-1, 0, 10]]}]
	for i in range(1, 21):
		for sign_ in [-1, 1]:
			split_ties.append({"name": "Filler", "points": [[sign_ * i * 50, 0, -10], [sign_ * i * 50, 0, 10]]})
	locator.setup(split_ties)
	compare(locator, split_ties, [Vector3.ZERO], "symmetric tree tie with earlier source in right partition")
	check(locator.nearest(Vector3.ZERO) == "Earlier right", "later-visited equal-distance candidate can replace later source name")
	var ties: Array = []
	for i in 40:
		ties.append({"name": "Tie %d" % i, "points": [[-10, 0, 0], [10, 0, 0]]})
	locator.setup(ties)
	check(locator.nearest(Vector3(0, 0, 2)) == "Tie 0", "identical segment ties retain first source name")
	ties[0].name = "Changed source"
	check(locator.nearest(Vector3(0, 0, 2)) == "Tie 0", "setup snapshots names and geometry")
	locator.setup(ties)
	check(locator.nearest(Vector3(0, 0, 2)) == "Changed source", "setup invalidation rebuilds changed source")
	locator.setup([])
	check(locator.nearest(Vector3.ZERO) == Locator.FALLBACK and locator.get_status().segments == 0, "empty rebuild clears prior index")

func _benchmark(locator, roads: Array, grid: Array[Vector3], setup_usec: int) -> void:
	var sample: Array[Vector3] = []
	for i in range(0, grid.size(), 7):
		sample.append(grid[i])
	for point in sample.slice(0, 20):
		original(roads, point)
		locator.nearest(point)
	var original_times: Array[int] = []
	var indexed_times: Array[int] = []
	var before_queries: int = locator.queries
	var before_segments: int = locator.tested_segments
	var guard := 0
	for round_index in 5:
		# Alternate order to reduce warm-up/frequency drift bias in one process.
		for mode in ([0, 1] if round_index % 2 == 0 else [1, 0]):
			var start := Time.get_ticks_usec()
			for point in sample:
				guard += (original(roads, point) if mode == 0 else locator.nearest(point)).length()
			var elapsed := Time.get_ticks_usec() - start
			if mode == 0:
				original_times.append(elapsed)
			else:
				indexed_times.append(elapsed)
	var indexed_queries: int = locator.queries - before_queries
	var exact_tests: int = locator.tested_segments - before_segments
	var segment_count: int = locator.get_status().segments
	check(indexed_queries == sample.size() * 5 and exact_tests < indexed_queries * segment_count, "benchmark actually prunes exact segment queries")
	var sorted_original := original_times.duplicate()
	var sorted_indexed := indexed_times.duplicate()
	sorted_original.sort()
	sorted_indexed.sort()
	print("[street_locator] BENCHMARK " + JSON.stringify({"scope": "same-process lookup microbenchmark; no global FPS claim", "setup_usec": setup_usec,
		"queries_per_round": sample.size(), "rounds": 5, "segments": segment_count, "indexed_queries": indexed_queries,
		"original_segment_tests": indexed_queries * segment_count, "indexed_segment_tests": exact_tests,
		"original_round_usec": original_times, "indexed_round_usec": indexed_times,
		"original_median_usec": sorted_original[2], "indexed_median_usec": sorted_indexed[2], "result_guard": guard}))
