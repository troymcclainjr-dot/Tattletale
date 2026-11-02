extends SceneTree
## Streaming-polish scheduler fixture: periodic provider passes spread over frames,
## explicit/capture refreshes stay synchronous, relocations start promptly without
## starving providers, and building retirement/teardown stay bounded. _process is
## driven manually. Provider costs are busy-waits, so contention can only lengthen
## them; every timing-dependent assertion relies on costs being lower bounds.
var passes := 0
var fails := 0

class TestPlayer extends Node3D:
	var camera_override: Dictionary = {}

class TestLevel extends Node3D:
	var player: Node3D
	var inspector: Node = null

class CostProvider extends Node:
	var cost_usec := 0
	var calls := 0
	var capture_calls := 0
	var focus := Vector3.INF
	var journal: Array = []
	func set_presence(center: Vector3, _near_radius: float, _far_radius: float) -> void:
		calls += 1
		focus = center
		journal.append(str(name))
		var until := Time.get_ticks_usec() + cost_usec
		while Time.get_ticks_usec() < until:
			pass
	func set_capture_presence(center: Vector3, _eye: Vector3, near_radius: float, far_radius: float) -> void:
		capture_calls += 1
		set_presence(center, near_radius, far_radius)

class PacedProvider extends CostProvider:
	var paced_calls := 0
	var profile_presence := false
	var presence_profile: Dictionary = {}
	func set_paced_presence(center: Vector3, near_radius: float, far_radius: float) -> void:
		paced_calls += 1
		presence_profile = {"scan": 7, "physics": 3} if profile_presence else {}
		set_presence(center, near_radius, far_radius)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[streaming_polish_schedule] %s %s" % ["PASS" if ok else "FAIL", label])

func _world() -> TestLevel:
	var world := TestLevel.new()
	root.add_child(world)
	world.player = TestPlayer.new()
	world.add_child(world.player)
	return world

func _streaming(world: TestLevel, list: Array[Node]) -> Node:
	var streaming = load("res://scripts/city/city_streaming.gd").new()
	world.add_child(streaming)
	streaming.set_process(false)
	streaming.level = world
	streaming.providers.assign(list)
	return streaming

func _providers(world: TestLevel, journal: Array, count: int, cost: int) -> Array[Node]:
	var list: Array[Node] = []
	for i in count:
		var provider := CostProvider.new()
		provider.name = "Cost%d" % i
		provider.cost_usec = cost
		provider.journal = journal
		world.add_child(provider)
		list.append(provider)
	return list

func _drain(streaming: Node, limit := 32) -> int:
	# Frames needed to finish the current pass, excluding the frame that began it.
	var frames := 0
	while not streaming._detail_queue.is_empty() and frames < limit:
		streaming._process(0.001)
		frames += 1
	return frames

func _run() -> void:
	var world := _world()
	var journal: Array = []
	var list := _providers(world, journal, 4, 1500)
	var streaming := _streaming(world, list)
	streaming.detail_frame_budget_usec = 2500
	streaming.refresh_now()
	check(journal == ["Cost0", "Cost1", "Cost2", "Cost3"], "explicit refresh calls every provider once, synchronously and in order")
	check(streaming._detail_queue.is_empty() and int(streaming._provider_cost.size()) == 4, "explicit refresh learns each provider's cost")
	journal.clear()
	streaming._process(0.25)
	check(journal == ["Cost0"], "cadence starts a pass; learned 1.5 ms costs leave one provider in a 2.5 ms slice")
	var frames := _drain(streaming)
	check(journal == ["Cost0", "Cost1", "Cost2", "Cost3"] and frames == 3, "the pass reaches every provider exactly once, in order, over four frames")
	var status: Dictionary = streaming.get_status()
	check(int(status.detail_passes) == 1 and int(status.detail_slices) == 4 and int(status.detail_queue) == 0, "pass/slice counters describe the spread pass")
	journal.clear()
	streaming._process(0.001)
	check(journal.is_empty(), "no provider runs again before the next cadence deadline")

	# One provider costing more than the budget runs alone; the overrun is reported.
	list[2].cost_usec = 4000
	var overruns_before := int(streaming.get_status().detail_budget_overruns)
	streaming._process(0.25)
	_drain(streaming)
	journal.clear()
	streaming._process(0.25)
	var slice_sizes := [journal.size()]
	while not streaming._detail_queue.is_empty():
		var before := journal.size()
		streaming._process(0.001)
		slice_sizes.append(journal.size() - before)
	check(slice_sizes == [1, 1, 1, 1] and journal == ["Cost0", "Cost1", "Cost2", "Cost3"], "an indivisible over-budget provider occupies its own frame")
	check(int(streaming.get_status().detail_budget_overruns) - overruns_before >= 2, "slices that exceed the soft budget are counted, not hidden")
	list[2].cost_usec = 1500

	# Cheap providers share one frame when they fit.
	for provider in list:
		provider.cost_usec = 0
	streaming.detail_frame_budget_usec = 1000000
	streaming.refresh_now()
	journal.clear()
	streaming._process(0.25)
	check(journal.size() == 4 and streaming._detail_queue.is_empty(), "providers that fit the budget complete in a single frame")
	for provider in list:
		provider.cost_usec = 1500
	streaming.detail_frame_budget_usec = 2500
	streaming.refresh_now()

	# refresh_now supersedes a pass that is still spread over frames.
	journal.clear()
	streaming._process(0.25)
	check(journal == ["Cost0"] and streaming._detail_queue.size() == 3, "a periodic pass is in progress")
	streaming.refresh_now()
	check(journal == ["Cost0", "Cost0", "Cost1", "Cost2", "Cost3"] and streaming._detail_queue.is_empty(), "refresh_now refreshes everyone at once and cancels the remaining pass")
	streaming._process(0.001)
	check(journal.size() == 5, "a superseded pass never resumes")

	# Captures keep the original synchronous periodic refresh through set_capture_presence.
	world.player.camera_override = {"eye": Vector3(300, 4, 0), "target": Vector3(900, 4, 0)}
	journal.clear()
	streaming._process(0.25)
	var capture_calls := 0
	for provider in list:
		capture_calls += provider.capture_calls
	check(journal.size() == 4 and capture_calls == 4 and streaming._detail_queue.is_empty(), "capture mode refreshes every provider in one frame with camera presence")
	check(bool(streaming.get_status().capture_details), "capture bookkeeping remains enabled during captures")
	world.player.camera_override = {}
	streaming.refresh_now()

	# Relocation starts a pass promptly; repeated jumps never restart it.
	journal.clear()
	streaming._process(0.001)
	check(journal.is_empty(), "ordinary travel between deadlines does not dispatch providers")
	world.player.position = Vector3(400, 0, 0)
	streaming._process(0.001)
	check(journal == ["Cost0"] and list[0].focus == Vector3(400, 0, 0) and int(streaming.get_status().relocation_refreshes) == 1,
		"a relocation starts presence at the new place without waiting for the cadence")
	for jump in 3:
		world.player.position += Vector3(200, 0, 0)
		streaming._process(0.001)
	check(journal == ["Cost0", "Cost1", "Cost2", "Cost3"], "jumping every frame continues the pass instead of starving later providers")
	check(list[3].focus == world.player.position, "each slice uses the latest focus")
	streaming._process(0.001)
	check(journal.size() == 5 and journal[4] == "Cost0" and not streaming._detail_due, "the jumps queue exactly one follow-up pass, which starts next frame")
	_drain(streaming)
	streaming.refresh_now()

	# Optional paced presence and opt-in phase attribution.
	var paced := PacedProvider.new()
	paced.name = "Paced"
	paced.journal = journal
	world.add_child(paced)
	streaming.providers.append(paced)
	streaming.refresh_now()
	check(paced.calls == 1 and paced.paced_calls == 0, "explicit refresh uses complete set_presence")
	streaming.profile_streaming = true
	journal.clear()
	streaming._process(0.25)
	_drain(streaming)
	check(paced.paced_calls == 1 and paced.calls == 2 and paced.profile_presence, "periodic passes prefer set_paced_presence and enable provider attribution")
	var stages: Dictionary = streaming.get_status().profile_stages
	check(stages.has("detail_frame_slice") and stages.has("detail_pass_cpu") and stages.has("detail:Paced") and stages.has("detail:Cost0"), "slice, pass and provider stages are recorded")
	check(int(stages.get("detail:Paced/scan", {}).get("max_usec", -1)) == 7 and int(stages.get("detail:Paced/physics", {}).get("max_usec", -1)) == 3,
		"provider-reported phases are recorded as nested stages")
	check(not stages.has("refresh_with_details"), "periodic passes do not masquerade as synchronous full refreshes")
	var schedule: Dictionary = streaming.get_status().profile_detail_schedule
	check(int(schedule.passes) == 1 and int(schedule.slices) == int(stages.detail_frame_slice.calls) and int(schedule.max_slices_per_pass) >= 2,
		"schedule summary matches the recorded slices")
	streaming.refresh_now()
	check(streaming.get_status().profile_stages.has("refresh_with_details"), "explicit refresh still records refresh_with_details")
	streaming.profile_streaming = false

	# A provider freed mid-pass is skipped without engine errors.
	journal.clear()
	streaming._process(0.25)
	var doomed: Node = streaming._detail_queue[0]
	doomed.free()
	_drain(streaming)
	check(not journal.has("Cost1") and journal.has("Cost3") and journal.has("Paced"), "freed providers are skipped and the pass completes")

	# Building retirement: periodic refreshes retire one far cell per call.
	var far_world := _world()
	var no_providers: Array[Node] = []
	var builder := _streaming(far_world, no_providers)
	for i in 4:
		var node := MeshInstance3D.new()
		far_world.add_child(node)
		var proxy := MeshInstance3D.new()
		far_world.add_child(proxy)
		proxy.hide()
		builder.records.append({"path": "res://missing_polish_cell_%d.scn" % i, "node": node, "proxy": proxy,
			"bounds": AABB(Vector3(1000 + 100 * i, 0, 0), Vector3(10, 10, 10)), "triangles": 10, "failed": false})
	check(int(builder.get_status().unloads_deferred) == 4, "four loaded cells lie beyond the unload radius")
	builder._process(0.25)
	check(builder.records[3].node == null and builder.records[3].proxy.visible and builder.records[0].node != null and int(builder.get_status().unloads) == 1,
		"a periodic refresh retires only the farthest cell and restores its silhouette")
	check(int(builder.get_status().unloads_deferred) == 3, "remaining retirements are reported")
	builder._process(0.25)
	check(builder.records[2].node == null and int(builder.get_status().unloads) == 2, "the next refresh retires the next farthest cell")
	builder.refresh_now()
	check(builder.records[0].node == null and builder.records[1].node == null and int(builder.get_status().unloads_deferred) == 0 and int(builder.get_status().unloads) == 4,
		"explicit refresh still retires every out-of-range cell at once")

	# Teardown consumes an outstanding threaded load and drops queued providers.
	var directory := ProjectSettings.globalize_path("res://../.work/polish-five/streaming-polish")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated fixture directory exists")
	var source := MeshInstance3D.new()
	source.mesh = BoxMesh.new()
	var packed := PackedScene.new()
	var path := directory.path_join("polish_cell.scn")
	check(packed.pack(source) == OK and ResourceSaver.save(packed, path) == OK, "real cell scene saved")
	source.free()
	builder.providers.assign(_providers(far_world, [], 3, 1500))
	builder.refresh_now()
	builder._process(0.25)
	var near_proxy := MeshInstance3D.new()
	far_world.add_child(near_proxy)
	builder.records.append({"path": path, "node": null, "proxy": near_proxy, "bounds": AABB(Vector3(2, 0, 2), Vector3(4, 4, 4)), "triangles": 12, "failed": false})
	# Request through the periodic building path without polling, so completion
	# timing on the loader thread cannot race the assertion.
	builder._refresh(false, false, true)
	check(not builder._pending.is_empty() and not builder._detail_queue.is_empty(), "a threaded load and a spread pass are both outstanding")
	far_world.remove_child(builder)
	check(builder._pending.is_empty() and builder._detail_queue.is_empty(), "leaving the tree consumes the load and clears the pass")
	builder.free()
	DirAccess.remove_absolute(path)
	print("[streaming_polish_schedule] %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
