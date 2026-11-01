extends Node
const Crowd := preload("res://scripts/city/city_crowd.gd")
# Headless's dummy renderer does not provide useful MultiMesh readback. Record
# the exact same production upload calls without relying on GPU storage.
class RecordingTransforms extends RefCounted:
	var transforms: Array[Transform3D] = []
	var writes: Array[int] = []
	var custom: Dictionary = {}
	func _init(count: int) -> void:
		transforms.resize(count)
		transforms.fill(Transform3D.IDENTITY)
		writes.resize(count)
		writes.fill(0)
	func set_instance_transform(index: int, pose: Transform3D) -> void:
		transforms[index] = pose
		writes[index] += 1
	func get_instance_transform(index: int) -> Transform3D:
		return transforms[index]
	func set_instance_custom_data(index: int, value: Color) -> void:
		custom[index] = value
class RecordingBatch extends Node3D:
	var multimesh: RecordingTransforms
class IdleLevel extends Node3D:
	var player: Node3D
var failures := 0
var _finished := false
var _original_mode := true
var _original_profile := false
var _original_totals: Dictionary = {}
func _ready() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await get_tree().create_timer(45.0, true, false, true).timeout
	if not _finished:
		check(false, "idle fixture watchdog")
		_finish()
func check(ok: bool, label: String) -> void:
	print("[crowd_idle] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func make_crowd(count: int) -> Node3D:
	var fixture := IdleLevel.new()
	add_child(fixture)
	fixture.player = Node3D.new()
	fixture.add_child(fixture.player)
	var crowd := Crowd.new()
	fixture.add_child(crowd)
	crowd.level = fixture
	var multi := RecordingTransforms.new(count)
	var visual := RecordingBatch.new()
	visual.multimesh = multi
	crowd.add_child(visual)
	crowd._batches["fixture"] = {"node": visual, "multimesh": multi, "origin": Vector3.ZERO}
	crowd._batches["culled"] = {"node": null, "origin": Vector3.ZERO}
	for index in count:
		crowd.residents.append({"stable_id": "crowd_%d" % index, "activity": "social", "position": Vector3.ZERO, "yaw": 0.0, "slot": index, "batch": "fixture"})
		multi.set_instance_transform(index, Transform3D.IDENTITY)
	return crowd
func advance(crowd: Node3D, delta: float) -> void:
	# Exercise exactly the production idle scheduler without unrelated walker IO.
	crowd._clock += delta
	crowd._tick_idle(delta)
func _run() -> void:
	_original_mode = Crowd.use_staggered_idle
	_original_profile = Crowd.profile_idle
	_original_totals = Crowd.profile_totals.duplicate()
	Crowd.use_staggered_idle = true
	Crowd.profile_idle = true
	Crowd.profile_totals.clear()
	var crowd := make_crowd(150)
	var multi: RecordingTransforms = crowd._batches.fixture.multimesh
	var counts := PackedInt32Array()
	counts.resize(150)
	var phase_correct := true
	var clock_correct := true
	var largest_scan := 0
	for frame in 60:
		var before: Array[int] = multi.writes.duplicate()
		var scanned_before := int(Crowd.profile_totals.get("idle_scanned", 0))
		advance(crowd, 1.0 / 60.0)
		largest_scan = maxi(largest_scan, int(Crowd.profile_totals.idle_scanned) - scanned_before)
		for index in 150:
			var pose := multi.get_instance_transform(index)
			if before[index] != multi.writes[index]:
				counts[index] += multi.writes[index] - before[index]
				phase_correct = phase_correct and index % Crowd.IDLE_GROUPS == frame % Crowd.IDLE_GROUPS
				var yaw: float = sin(crowd._clock * 0.65 + float(index)) * 0.045
				clock_correct = clock_correct and pose.basis.is_equal_approx(Basis(Vector3.UP, yaw))
	if not phase_correct or counts.count(4) != 150:
		var bad_counts: Array[String] = []
		for index in counts.size():
			if counts[index] != 4 and bad_counts.size() < 16:
				bad_counts.append("%d:%d" % [index, counts[index]])
		print("[crowd_idle] cadence diagnostic phases=", phase_correct, " non-four counts=", bad_counts)
	check(phase_correct and counts.count(4) == 150, "all fixed cohorts receive exactly four updates per person at 60Hz")
	check(largest_scan == 10 and int(Crowd.profile_totals.idle_scanned) == 600 and int(Crowd.profile_totals.idle_calls) == 60, "normal tick scans only its cohort, not the full population")
	check(clock_correct, "animation retains absolute elapsed clock rather than cohort-local time")
	var varied := {}
	for value in multi.custom.values():
		varied[int(value.g)] = true
	check(varied.has(1) and varied.has(2) and varied.has(3), "idle cohorts upload all three deterministic shared-mesh activities")
	crowd.get_parent().free()
	crowd = make_crowd(150)
	multi = crowd._batches.fixture.multimesh
	crowd.residents[0].dead = true
	crowd.residents[1].combat_controlled = true
	crowd.residents[2].panic = true
	crowd.residents[3].activity = "walking"
	crowd.residents[4].identity_unplaced = true
	crowd.residents[5].position = Vector3(100, 0, 0)
	crowd.residents[6].batch = "culled"
	Crowd.profile_totals.clear()
	for frame in 60:
		advance(crowd, 1.0 / 60.0)
	var skipped := true
	for index in 7:
		skipped = skipped and multi.get_instance_transform(index) == Transform3D.IDENTITY
	check(skipped and int(Crowd.profile_totals.idle_updated) == 143 * 4, "dead, combat, panic, walker, unplaced, far and culled slots stay untouched")
	check(crowd.residents.size() == 150 and crowd.residents[0].stable_id == "crowd_0" and crowd._batches.size() == 2, "scheduler changes no identities, population or batches")
	crowd.residents[8].police_custody = true
	crowd.residents[9].bicycle_rejoin = Vector3.ONE
	crowd.residents[10].bicycle_avoiding = true
	var before_owned: Array[int] = multi.writes.duplicate()
	for frame in 60:
		advance(crowd, 1.0 / 60.0)
	var ownership_preserved := true
	for index in [8, 9, 10]:
		ownership_preserved = ownership_preserved and multi.writes[index] == before_owned[index] and multi.custom[index].g == 0.0
	check(ownership_preserved, "custody and bicycle ownership clear gestures without overwriting transforms")
	crowd.get_parent().free()
	crowd = make_crowd(1200)
	Crowd.profile_totals.clear()
	advance(crowd, 4.0)
	check(int(Crowd.profile_totals.idle_calls) == Crowd.IDLE_MAX_CATCHUP and int(Crowd.profile_totals.idle_scanned) == 320 and crowd._idle_skipped_steps > 0, "long stall catches up at most four cohorts / 320 of 1200 slots")
	check(crowd._near_updates == 320 and int(Crowd.profile_totals.idle_updated) == 320, "current-tick update count sums all catch-up cohorts without profile double-counting")
	var calls_before := int(Crowd.profile_totals.idle_calls)
	advance(crowd, 1.0 / 60.0)
	check(int(Crowd.profile_totals.idle_calls) == calls_before + 1, "long stall leaves no repeated catch-up backlog")
	crowd.get_parent().free()
	crowd = make_crowd(150)
	multi = crowd._batches.fixture.multimesh
	Crowd.profile_totals.clear()
	var slow_fair := true
	var slow_bounded := true
	var slow_totals := true
	for window in 4:
		var before_window: Array[int] = multi.writes.duplicate()
		for frame in 4:
			var before_calls := int(Crowd.profile_totals.get("idle_calls", 0))
			var before_updates := int(Crowd.profile_totals.get("idle_updated", 0))
			advance(crowd, 0.25)
			slow_bounded = slow_bounded and int(Crowd.profile_totals.idle_calls) - before_calls == Crowd.IDLE_MAX_CATCHUP
			slow_totals = slow_totals and crowd._near_updates == 40 and int(Crowd.profile_totals.idle_updated) - before_updates == 40
		for index in 150:
			slow_fair = slow_fair and multi.writes[index] > before_window[index]
	check(slow_fair, "sustained 250ms ticks service all fifteen cohorts within each four-call window")
	check(slow_bounded and slow_totals, "sustained slow ticks stay bounded at four cohorts and sum current-tick/profile updates exactly")
	advance(crowd, 0.0)
	check(crowd._near_updates == 0, "tick without due work clears the current-tick near-update counter")
	crowd.get_parent().free()
	crowd = make_crowd(150)
	Crowd.profile_totals.clear()
	for frame in 30:
		advance(crowd, 1.0 / 30.0)
	check(int(Crowd.profile_totals.idle_updated) == 600 and crowd._idle_skipped_steps == 0, "30Hz tick still services every scheduled cohort at 4Hz per person")
	crowd.get_parent().free()
	crowd = make_crowd(150)
	Crowd.use_staggered_idle = false
	Crowd.profile_totals.clear()
	for frame in 4:
		advance(crowd, 0.25)
	check(int(Crowd.profile_totals.idle_calls) == 4 and int(Crowd.profile_totals.idle_scanned) == 600, "counterfactual flag retains one whole-population quarter-second pass")
	Crowd.profile_idle = false
	var totals := Crowd.profile_totals.duplicate()
	advance(crowd, 0.25)
	check(Crowd.profile_totals == totals, "profiling disabled leaves all timing/counters untouched")
	crowd.get_parent().free()
	_finish()
func _finish() -> void:
	if _finished:
		return
	_finished = true
	Crowd.use_staggered_idle = _original_mode
	Crowd.profile_idle = _original_profile
	Crowd.profile_totals = _original_totals
	get_tree().quit(1 if failures else 0)
