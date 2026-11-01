extends Node

const Crowd := preload("res://scripts/city/city_crowd.gd")
const FRAME := 1.0 / 60.0

class FixtureLevel extends Node3D:
	var player: Node3D

class FixtureNPCs extends Node3D:
	func _route_distance(_at: Vector3) -> float:
		return 150.0

var crowd: Node3D
var level: FixtureLevel
var passed := 0
var failed := 0
var phase_ok := true

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[city_crowd_cadence] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func advance(count: int, counts: Array[int], check_phase := false) -> void:
	for frame in count:
		var before: Array[float] = []
		for resident in crowd.residents:
			before.append(resident.walk_progress)
		crowd.tick(FRAME)
		var changed := 0
		for index in crowd.residents.size():
			if not is_equal_approx(float(crowd.residents[index].walk_progress), before[index]):
				counts[index] += 1
				changed += 1
				if check_phase:
					phase_ok = phase_ok and index == frame % 3
		if check_phase:
			phase_ok = phase_ok and changed == 1
		await frames(1)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	level = FixtureLevel.new()
	add_child(level)
	level.player = Node3D.new()
	level.player.position = Vector3(20, 0, 0)
	level.add_child(level.player)
	var npcs := FixtureNPCs.new()
	level.add_child(npcs)
	crowd = Crowd.new()
	level.add_child(crowd)
	crowd.level = level
	crowd.npcs = npcs
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.65
	crowd._shape = capsule
	var meshes: Array[ArrayMesh] = [crowd._person_mesh(false), crowd._person_mesh(true)]
	crowd._meshes = meshes
	for index in 3:
		var x := float(index) * 3.0
		crowd._add_resident(Vector3(x, 0, 1.5), 0.0, "walking", false)
		var resident: Dictionary = crowd.residents[index]
		var path: Array[Vector3] = []
		for step in 13:
			path.append(Vector3(x, 0, float(step) * 0.5))
		resident.walk_a = path[0]
		resident.walk_b = path[-1]
		resident.walk_path = path
		resident.walk_progress = 0.25
		resident.walk_direction = 1.0
		resident.walk_speed = 1.2
		crowd._walkers.append(index)
	crowd._build_batches()
	await frames(3)
	var initial_activations: int = crowd.get_status().cell_activations
	var initial_batch: Dictionary = crowd._batches[crowd.residents[0].batch]
	initial_batch.node.visibility_range_end = 123.0
	crowd.set_presence(Vector3.ZERO, 32.0, 160.0)
	check(is_equal_approx(initial_batch.node.visibility_range_end, 123.0) and crowd.get_status().cell_activations == initial_activations,
		"unchanged presence radius leaves existing node range and activation count alone")
	crowd.set_presence(Vector3.ZERO, 20.0, 90.0)
	check(is_equal_approx(initial_batch.node.visibility_range_end, 90.0) and crowd.get_status().cell_activations == initial_activations,
		"changed presence radius updates the existing batch without activating a cell")
	var counts: Array[int] = [0, 0, 0]
	await advance(60, counts, true)
	check(phase_ok, "one walker advances in each physics frame, in three staggered phases")
	check(counts == [20, 20, 20], "each staggered walker receives 20 steps in one simulated second")
	var travel_ok := true
	for resident in crowd.residents:
		travel_ok = travel_ok and absf(float(resident.walk_progress) - 0.45) < 0.0001
	check(travel_ok, "each walker advances the expected 1.2 m aggregate distance")
	var promoted_position: Vector3 = crowd.residents[1].position
	var promotion: Dictionary = crowd.begin_combat(1)
	check(not promotion.is_empty() and crowd.residents[1].body.collision_layer == 0, "promotion transfers the walking resident's collider")
	check(crowd.begin_combat(1).is_empty(), "a promoted resident cannot be promoted twice")
	var post_promotion: Array[int] = [0, 0, 0]
	await advance(30, post_promotion)
	check(post_promotion == [10, 0, 10] and crowd.residents[1].position == promoted_position, "promotion skips only its walker phase")
	crowd.end_combat(1, Vector3(3, 0, 1.7), 0.0)
	check(crowd.residents[1].activity == "social" and not crowd._walkers.has(1) and crowd.residents[1].body.collision_layer == 8, "displaced demotion removes the old route and restores the collider")
	var post_demotion: Array[int] = [0, 0, 0]
	await advance(30, post_demotion)
	check(post_demotion == [10, 0, 10] and crowd.residents[1].position == Vector3(3, 0, 1.7), "remaining walker phases keep cadence after route removal")
	var old_body_rid: RID = crowd.residents[0].body.get_rid()
	crowd.set_presence(Vector3(1000, 0, 1000), 20.0, 90.0)
	await frames(3)
	var before_cull: float = crowd.residents[0].walk_progress
	var culled_counts: Array[int] = [0, 0, 0]
	await advance(60, culled_counts)
	check(crowd.residents[0].body == null and is_equal_approx(float(crowd.residents[0].walk_progress), before_cull), "culled walkers do not advance without a batch or body")
	crowd.set_presence(Vector3.ZERO, 20.0, 90.0)
	await frames(3)
	check(crowd.get_status().cell_activations == initial_activations + 1,
		"restoring a culled cell increments the monotonic activation counter once")
	var restored_counts: Array[int] = [0, 0, 0]
	await advance(60, restored_counts)
	check(crowd.residents[0].body.get_rid() != old_body_rid and restored_counts == [20, 0, 20], "restored walkers use replacement bodies and resume their phases")
	print("[city_crowd_cadence] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
