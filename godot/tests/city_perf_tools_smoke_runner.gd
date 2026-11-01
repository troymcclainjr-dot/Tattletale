extends Node
## Benchmark tooling behavior without a scene: summary statistics, per-cycle
## phase attribution from synthetic timestamp sequences, and the opt-in
## production counters. Expected values are derived by hand from the inputs.

const Stats := preload("res://tools/city_perf_stats.gd")
const Timeline := preload("res://tools/city_perf_timeline.gd")
const PerfCounters := preload("res://scripts/city/city_perf_counters.gd")

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[perf_tools] %s %s" % ["PASS" if ok else "FAIL", label])

func near(a: float, b: float, tolerance := 0.000001) -> bool:
	return absf(a - b) <= tolerance

func _run() -> void:
	_stats()
	_timeline_render_only()
	_timeline_two_ticks()
	_timeline_missing_and_disordered()
	_timeline_recording_window()
	_counters()
	print("[perf_tools] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

func _stats() -> void:
	check(Stats.distribution([]).is_empty(), "an empty sample has no distribution rather than zeros")
	var single := Stats.distribution([5.0])
	check(near(single.median, 5) and near(single.p99, 5) and near(single.min, 5) and near(single.max, 5) and int(single.count) == 1, "a single value is every statistic")
	var hundred: Array[float] = []
	for i in range(100, 0, -1):
		hundred.append(float(i))
	var summary := Stats.distribution(hundred)
	check(near(summary.median, 51) and near(summary.p95, 95) and near(summary.p99, 99), "1..100 unsorted: upper median 51, nearest-rank p95 95 and p99 99")
	check(near(summary.mean, 50.5) and near(summary.sum, 5050) and near(summary.min, 1) and near(summary.max, 100), "mean, sum and extremes of 1..100")
	var mixed := Stats.distribution(PackedInt32Array([3, 1, 2]))
	check(near(mixed.median, 2) and near(mixed.mean, 2), "integer packed input is summarized as numbers")
	var original := PackedFloat64Array([3.0, 1.0, 2.0])
	Stats.distribution(original)
	check(original[0] == 3.0 and original[1] == 1.0, "summaries never reorder the caller's samples")
	check(near(Stats.per_second([10.0, 20.0, 30.0], 2.0), 30.0), "60ms of work in 2s is a 30ms/s budget")
	check(near(Stats.per_second([10.0], 0.0), 0.0), "a zero-length window has no budget instead of dividing by zero")
	# Four 1ms frames and one 6ms frame: half the wall time is in the long frame.
	var frames := [1.0, 1.0, 1.0, 1.0, 6.0]
	check(near(Stats.distribution(frames).median, 1.0) and near(Stats.time_weighted_percentile(frames, 0.5), 6.0), "time-weighted median exposes the frame holding half the elapsed time")
	check(near(Stats.time_weighted_percentile(frames, 0.3), 1.0) and near(Stats.time_weighted_percentile([], 0.5), 0.0), "time-weighted low percentile and empty input")
	check(Stats.count_over([1.0, 5.0, 10.0], 5.0) == 1, "hitch counting is strictly above the threshold")
	var columns := Stats.summarize_columns({"a": [1.0, 3.0], "empty": []}, 4.0)
	check(columns.has("a") and not columns.has("empty") and near(columns.a.per_second, 1.0), "column summaries skip empty columns and add a per-second budget")

func _row(timeline: Timeline, index: int) -> Dictionary:
	var result := {}
	var values := timeline.row(index)
	for i in Timeline.COLUMNS.size():
		result[Timeline.COLUMNS[i]] = values[i]
	return result

func _phase_sum(row: Dictionary) -> float:
	var sum := 0.0
	for key in ["driver_ms", "process_pre_ms", "process_scripts_ms", "process_post_ms", "render_ms", "tail_ms", "physics_pre_ms", "physics_scripts_ms", "physics_engine_ms", "unattributed_ms"]:
		sum += float(row[key])
	return sum

func _timeline_render_only() -> void:
	var timeline := Timeline.new()
	timeline.start(0)
	timeline.driver_done(10)
	timeline.process_begin(30)
	timeline.process_end(130)
	timeline.draw_begin(150)
	timeline.draw_end(1150)
	check(timeline.process_frame(1200), "a recorded cycle closes at the next process_frame")
	var row := _row(timeline, 0)
	check(near(row.cycle_ms, 1.2) and near(row.driver_ms, 0.01) and near(row.process_pre_ms, 0.02) and near(row.process_scripts_ms, 0.1), "render-only cycle: driver, pre-process and script phases")
	check(near(row.process_post_ms, 0.02) and near(row.render_ms, 1.0) and near(row.tail_ms, 0.05) and near(row.physics_ticks, 0) and near(row.unattributed_ms, 0), "render-only cycle: post-process, render, tail and no physics")

func _timeline_two_ticks() -> void:
	var timeline := Timeline.new()
	timeline.start(0)
	timeline.driver_done(5)
	timeline.process_begin(10)
	timeline.process_end(20)
	timeline.draw_begin(25)
	timeline.draw_end(100)
	timeline.physics_frame(110)
	timeline.physics_begin(112)
	timeline.physics_end(150)
	timeline.physics_frame(170)
	timeline.physics_begin(171)
	timeline.physics_end(200)
	timeline.process_frame(260)
	var row := _row(timeline, 0)
	check(near(row.physics_ticks, 2) and near(row.tail_ms, 0.01), "two catch-up ticks; tail ends at the first physics_frame")
	check(near(row.physics_pre_ms, 0.003) and near(row.physics_scripts_ms, 0.067) and near(row.physics_engine_ms, 0.08), "tick pre 2+1us, scripts 38+29us, engine 20+60us")
	check(near(_phase_sum(row), row.cycle_ms) and near(row.unattributed_ms, 0), "ordered phases add up to the whole cycle")
	check(timeline.tick_scripts_ms.size() == 2 and near(timeline.tick_engine_ms[1], 0.06) and timeline.tick_cycle[0] == 0 and timeline.tick_cycle[1] == 0, "per-tick trace keeps both ticks in cycle 0")
	# The next cycle's tick carries the next cycle index.
	timeline.process_begin(270)
	timeline.process_end(280)
	timeline.physics_frame(300)
	timeline.physics_begin(301)
	timeline.physics_end(311)
	timeline.process_frame(330)
	check(timeline.cycles() == 2 and timeline.tick_cycle[2] == 1, "ticks are attributed to the cycle they ran in")
	check(near(_row(timeline, 1).render_ms, 0.0) and near(_row(timeline, 1).tail_ms, 0.02), "a cycle without a draw has zero render time; its tail starts after the scripts")

func _timeline_missing_and_disordered() -> void:
	var timeline := Timeline.new()
	timeline.start(0)
	timeline.process_begin(10)
	timeline.process_end(20)
	timeline.draw_begin(150)
	timeline.draw_end(140)
	timeline.process_frame(200)
	var row := _row(timeline, 0)
	check(timeline.anomalies == 1 and near(row.render_ms, 0.0) and near(_phase_sum(row), row.cycle_ms), "a draw end before its begin is an anomaly; phases still cover the cycle")
	# A tick whose last mark never ran: its span stays inside the cycle.
	timeline.physics_frame(220)
	timeline.physics_begin(221)
	timeline.physics_frame(260)
	timeline.physics_begin(262)
	timeline.physics_end(280)
	timeline.process_frame(300)
	row = _row(timeline, 1)
	check(timeline.anomalies == 2 and near(row.physics_ticks, 1) and near(_phase_sum(row), row.cycle_ms), "an unfinished tick is counted as an anomaly without losing time")

func _timeline_recording_window() -> void:
	var timeline := Timeline.new()
	check(not timeline.process_frame(10), "nothing is recorded before start")
	timeline.physics_frame(20)
	timeline.physics_begin(21)
	timeline.physics_end(30)
	timeline.start(40)
	timeline.process_frame(100)
	check(timeline.cycles() == 1 and near(_row(timeline, 0).physics_ticks, 0) and timeline.tick_scripts_ms.is_empty(), "physics before start is excluded from the first cycle")
	timeline.stop()
	timeline.process_begin(110)
	check(not timeline.process_frame(200) and timeline.cycles() == 1, "events after stop are ignored")
	timeline.start(300)
	check(timeline.cycles() == 0 and timeline.anomalies == 0, "a restart discards the previous recording")

func _counters() -> void:
	check(not PerfCounters.enabled, "counters are inert by default in a fresh process")
	check(PerfCounters.NAMES.size() == PerfCounters.COUNT, "one name per counter slot")
	var ids := {}
	var consistent := true
	var constants: Dictionary = (PerfCounters as Script).get_script_constant_map()
	for key in constants:
		var value: Variant = constants[key]
		if key == "COUNT" or not value is int:
			continue
		var id: int = value
		consistent = consistent and id >= 0 and id < PerfCounters.COUNT and not ids.has(id) and PerfCounters.NAMES[id] == str(key).to_lower()
		ids[id] = true
	check(consistent and ids.size() == PerfCounters.COUNT, "every ID constant is unique, in range and named after itself")
	PerfCounters.reset()
	check(PerfCounters.snapshot().is_empty(), "a reset snapshot reports nothing")
	PerfCounters.add(PerfCounters.TRAFFIC_ON_ROAD)
	PerfCounters.add(PerfCounters.TRAFFIC_ON_ROAD, 4)
	var counted: Dictionary = PerfCounters.snapshot()
	check(int(counted.traffic_on_road.count) == 5 and int(counted.traffic_on_road.usec) == 0 and counted.size() == 1, "pure counts accumulate without time")
	var began := PerfCounters.begin()
	OS.delay_usec(1500)
	PerfCounters.end(PerfCounters.VEHICLE_POSE_CLEAR, began)
	PerfCounters.end(PerfCounters.VEHICLE_POSE_CLEAR, PerfCounters.begin())
	var timed: Dictionary = PerfCounters.snapshot().vehicle_pose_clear
	check(int(timed.count) == 2 and int(timed.usec) >= 1500 and int(timed.max_usec) >= 1500 and int(timed.max_usec) <= int(timed.usec), "timed regions count calls, total time and the worst call")
	PerfCounters.add_named("rare_event", 2)
	PerfCounters.end_named("rare_event", PerfCounters.begin())
	var named: Dictionary = PerfCounters.snapshot()
	check(int(named["named:rare_event"].count) == 3, "named counters merge counts and timed calls")
	named["named:rare_event"]["count"] = 99
	named.traffic_on_road.count = 99
	check(int(PerfCounters.snapshot()["named:rare_event"].count) == 3 and int(PerfCounters.snapshot().traffic_on_road.count) == 5, "snapshots are copies")
	PerfCounters.reset()
	# The documented production hook pattern does nothing while disabled.
	PerfCounters.enabled = false
	for i in 10:
		if PerfCounters.enabled:
			PerfCounters.add(PerfCounters.LAW_LOS_RAY)
	check(PerfCounters.snapshot().is_empty(), "guarded hooks record nothing while disabled")
