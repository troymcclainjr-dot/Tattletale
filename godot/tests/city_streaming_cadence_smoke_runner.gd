extends Node
## Real threaded PackedScene completion through the production streamer.
## Counting provider isolates cadence; city_capture_residency_smoke separately
## checks real vegetation/yard collider identity across camera-only captures.
var failures := 0

class TestPlayer extends Node3D:
	var camera_override: Dictionary = {}

class TestLevel extends Node3D:
	var player: Node3D
	var inspector: Node = null

class TestOptimizer extends Node:
	var batch_root: Node3D
	var rebinds := 0
	var quality_applications := 0
	func rebind_shared_materials(_instance: MeshInstance3D) -> void:
		rebinds += 1
	func apply_chunk_quality(_instance: MeshInstance3D) -> void:
		quality_applications += 1

class CountingProvider extends Node:
	var calls := 0
	var capture_calls := 0
	var physics_focus := Vector3.INF
	var render_focus := Vector3.INF
	var radii := Vector2.ZERO
	func set_presence(center: Vector3, near_radius: float, far_radius: float) -> void:
		calls += 1
		physics_focus = center
		render_focus = center
		radii = Vector2(near_radius, far_radius)
	func set_capture_presence(center: Vector3, eye: Vector3, near_radius: float, far_radius: float) -> void:
		set_presence(center, near_radius, far_radius)
		capture_calls += 1
		render_focus = eye

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[streaming_cadence] %s %s" % ["PASS" if ok else "FAIL", label])

func _wait_for_request(streaming: Node) -> bool:
	for frame in 180:
		var path: String = streaming._pending
		if path.is_empty():
			return false
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return true
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			return false
		await get_tree().process_frame
	return false

func _run() -> void:
	var world := TestLevel.new()
	add_child(world)
	world.player = TestPlayer.new()
	world.add_child(world.player)
	world.player.position = Vector3(2, 0, 2)
	var optimizer := TestOptimizer.new()
	world.add_child(optimizer)
	optimizer.batch_root = Node3D.new()
	world.add_child(optimizer.batch_root)
	var provider := CountingProvider.new()
	world.add_child(provider)
	var streaming = load("res://scripts/city/city_streaming.gd").new()
	world.add_child(streaming)
	streaming.set_process(false) # Exercise exact production _process deadlines below.
	streaming.level = world
	streaming.optimizer = optimizer
	streaming.providers.assign([provider])
	var directory := ProjectSettings.globalize_path("res://../.work/pacifist-foundation/streaming-cadence")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated fixture directory exists")
	var paths: Array[String] = []
	for index in 2:
		var source := MeshInstance3D.new()
		source.name = "CadenceCell%d" % index
		source.mesh = BoxMesh.new()
		var packed := PackedScene.new()
		var path := directory.path_join("cell_%d.scn" % index)
		var packed_ok := packed.pack(source) == OK
		check(packed_ok and ResourceSaver.save(packed, path) == OK, "real cell scene saved: %d" % index)
		source.free()
		paths.append(path)
		var proxy := MeshInstance3D.new()
		world.add_child(proxy)
		streaming.records.append({"path": path, "node": null, "proxy": proxy,
			"bounds": AABB(Vector3(5 + index * 10, 0, 0), Vector3(2, 2, 2)), "triangles": 12, "failed": false})
	streaming.refresh_now()
	check(provider.calls == 1 and streaming._pending_index == 0, "explicit refresh applies details and requests nearest building")
	var ready: bool = await _wait_for_request(streaming)
	check(ready, "first real threaded request completes")
	if not ready:
		get_tree().quit(1)
		return
	streaming._elapsed = 0.249
	streaming._process(0.002)
	check(streaming._loads == 1 and is_instance_valid(streaming.records[0].node), "production poll attaches the completed building")
	check(streaming._pending_index == 1, "completion immediately advances next building request")
	check(provider.calls == 2, "completion coincident with cadence deadline refreshes providers exactly once")
	ready = await _wait_for_request(streaming)
	check(ready, "chained real threaded request completes")
	if not ready:
		get_tree().quit(1)
		return
	streaming._process(0.01)
	check(streaming._loads == 2 and streaming._pending.is_empty(), "second building attaches without waiting for detail cadence")
	check(provider.calls == 2, "load completion before deadline does not refresh providers")
	check(optimizer.rebinds == 2 and optimizer.quality_applications == 2, "both streamed cells retain material rebinding and quality application")
	streaming._process(0.25)
	check(provider.calls == 3, "detail cadence progresses after building queue becomes empty")
	world.player.position = Vector3(4, 0, 4)
	world.player.camera_override = {"eye": Vector3(492, 3, 12), "target": Vector3(1400, 8, 12)}
	# The fixture's building queue is complete; isolate capture detail dispatch.
	streaming.records.clear()
	streaming.refresh_now()
	streaming.refresh_now()
	check(provider.calls == 5 and provider.capture_calls == 2, "explicit capture warmup calls remain immediate")
	check(provider.physics_focus == world.player.global_position and provider.render_focus == Vector3(492, 3, 12),
		"capture passes actual player collision focus and camera eye independently")
	check(provider.radii == Vector2(55, 180), "capture presence radii remain unchanged")
	world.player.camera_override.clear()
	streaming.refresh_now()
	check(provider.calls == 6 and provider.physics_focus == world.player.global_position \
		and provider.render_focus == world.player.global_position, "leaving capture immediately restores ordinary presence")
	for path in paths:
		DirAccess.remove_absolute(path)
	get_tree().quit(0 if failures == 0 else 1)
