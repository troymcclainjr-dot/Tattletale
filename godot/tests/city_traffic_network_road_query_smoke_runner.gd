extends Node
## on_road() contract: a point is on a road when its plan-view distance to an
## indexed centerline segment is below half the road width less the margin.
## Analytic boundaries come from geometry; a seeded differential sweep compares
## every answer with the original Dictionary-per-segment query, including
## points placed exactly at the acceptance boundary. No scene or physics.

const Network := preload("res://scripts/city/city_traffic_network.gd")

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[road_query] %s %s" % ["PASS" if ok else "FAIL", label])

## The pre-optimization implementation, kept verbatim as the oracle.
func _original_on_road(network: RefCounted, point: Vector3, margin := 0.12) -> bool:
	var flat := Vector2(point.x, point.z)
	for road in network._road_cells.get(Vector2i(floori(point.x / 32), floori(point.z / 32)), []):
		if Geometry2D.get_closest_point_to_segment(flat, road.a, road.b).distance_to(flat) < float(road.half) - margin:
			return true
	return false

func _run() -> void:
	var network = Network.new()
	check(not network.on_road(Vector3.ZERO), "an empty network has no road anywhere")
	# East-west road on z=10, x 0..100, 10m wide: accepted band is 5m - margin.
	network._index_road(Vector3(0, 0, 10), Vector3(100, 0, 10), 10.0)
	check(network.on_road(Vector3(50, 3.0, 10)), "centerline is on road regardless of sample height")
	check(network.on_road(Vector3(50, 0, 14.87)), "4.87m off center is inside 5m less the default 0.12m margin")
	check(not network.on_road(Vector3(50, 0, 14.89)), "4.89m off center is outside the default margin band")
	check(not network.on_road(Vector3(50, 0, 10), 5.0), "a margin equal to the half width rejects even the centerline")
	check(not network.on_road(Vector3(50, 0, 10), 7.5), "a margin wider than the road rejects everything")
	check(network.on_road(Vector3(50, 0, 14.4), 0.5) and not network.on_road(Vector3(50, 0, 14.6), 0.5), "an explicit 0.5m margin moves the boundary to 4.5m")
	check(network.on_road(Vector3(50, 0, 15.5), -1.0), "a negative margin widens the band within the indexed corridor")
	check(network.on_road(Vector3(104.0, 0, 10)), "the end of a segment is rounded: 4m past the end is still road")
	check(not network.on_road(Vector3(103.6, 0, 13.6)), "beyond the rounded end corner is off road")
	check(network.on_road(Vector3(95, 0, 10)), "a segment spanning several 32m cells is found in its far cell")
	check(network.on_road(Vector3(31.999, 0, 10)) and network.on_road(Vector3(32.0, 0, 10)) and network.on_road(Vector3(64.0, 0, 10)), "points exactly on and beside cell boundaries")
	check(not network.on_road(Vector3(5000, 0, 5000)), "a point in a cell with no roads is off road")
	# Indexing after queries must be visible to later queries.
	check(not network.on_road(Vector3(-45, 0, -55)), "a road not yet indexed is absent")
	network._index_road(Vector3(-80, 0, -40), Vector3(-10, 0, -70), 8.0)
	check(network.on_road(Vector3(-45, 0, -55)), "negative-coordinate road is found after later indexing")
	check(not network.on_road(Vector3(-45, 0, -45)), "9.2m from that 8m road is off road")
	check(network.on_road(Vector3(-0.001, 0, -54.4)) == _original_on_road(network, Vector3(-0.001, 0, -54.4)), "negative cell just below zero matches the original")
	network._index_road(Vector3(200, 0, 200), Vector3(200, 0, 200), 6.0)
	check(network.on_road(Vector3(202, 0, 201)) and not network.on_road(Vector3(203, 0, 200)), "a zero-length segment covers a 2.88m disc")
	network._index_road(Vector3(300, 0, 0), Vector3(330, 0, 0), 4.0)
	check(not network.on_road(Vector3(315, 0, 5.5)), "5.5m from a 4m road is off road")
	network._index_road(Vector3(300, 0, 0), Vector3(330, 0, 0), 12.0)
	check(network.on_road(Vector3(315, 0, 5.5)), "an overlapping wider road accepts the same point")
	check(not network._road_cells.is_empty(), "the original cell index is still populated for other readers")
	# Seeded differential sweep against the original query.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2610
	var segments: Array[Dictionary] = []
	for i in 70:
		var a := Vector3(rng.randf_range(-400, 400), rng.randf_range(-1, 3), rng.randf_range(-400, 400))
		var direction := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var b := a + direction * rng.randf_range(0.0, 120.0)
		var width := rng.randf_range(4.0, 14.0)
		network._index_road(a, b, width)
		segments.append({"a": a, "b": b, "half": width * 0.5})
	var margins := [0.12, 1.1, 0.0, -0.5]
	var mismatches := 0
	var accepted := 0
	var total := 0
	for i in 20000:
		var point := Vector3(rng.randf_range(-450, 450), rng.randf_range(-2, 5), rng.randf_range(-450, 450))
		var margin: float = margins[i % margins.size()] if i % 5 != 4 else rng.randf_range(0.0, 2.5)
		var result: bool = network.on_road(point, margin)
		mismatches += int(result != _original_on_road(network, point, margin))
		accepted += int(result)
		total += 1
	# Points placed on each segment's exact acceptance boundary, both sides.
	var boundary_mismatches := 0
	for segment in segments:
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var along := (b - a)
		var side := Vector3(-along.z, 0, along.x).normalized() if along.length() > 0.001 else Vector3.RIGHT
		for j in 30:
			var margin: float = margins[j % margins.size()]
			var limit := float(segment.half) - margin
			var t := rng.randf()
			for offset in [limit - 1e-4, limit, limit + 1e-4, -limit, -(limit + 1e-3)]:
				var point := a.lerp(b, t) + side * float(offset)
				var result: bool = network.on_road(point, margin)
				boundary_mismatches += int(result != _original_on_road(network, point, margin))
				total += 1
	check(mismatches == 0, "%d random queries match the original exactly (%d mismatches)" % [20000, mismatches])
	check(boundary_mismatches == 0, "boundary-placed queries match the original exactly (%d mismatches)" % boundary_mismatches)
	check(accepted > 500 and accepted < 19500, "the random sweep exercises both outcomes (%d accepted)" % accepted)
	# Informational only: relative cost on this machine, not an assertion.
	var probe_points: Array[Vector3] = []
	for i in 20000:
		var segment: Dictionary = segments[i % segments.size()]
		probe_points.append((segment.a as Vector3).lerp(segment.b, rng.randf()) + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
	var began := Time.get_ticks_usec()
	for point in probe_points:
		network.on_road(point)
	var packed_usec := Time.get_ticks_usec() - began
	began = Time.get_ticks_usec()
	for point in probe_points:
		_original_on_road(network, point)
	var original_usec := Time.get_ticks_usec() - began
	print("[road_query] INFO %d near-road queries: packed %.3f us/call, original %.3f us/call (%d total comparisons)" % [probe_points.size(), packed_usec / float(probe_points.size()), original_usec / float(probe_points.size()), total])
	print("[road_query] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
