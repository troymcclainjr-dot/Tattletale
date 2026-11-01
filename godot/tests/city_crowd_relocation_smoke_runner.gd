extends Node
## Focused bookkeeping regression: movement endpoints are placed explicitly so
## collision/pathfinding cannot hide a cell-index or batch-presence failure.
const Crowd := preload("res://scripts/city/city_crowd.gd")

class FixtureLevel extends Node3D:
	var player: Node3D

class FixtureNPCs extends Node3D:
	func _route_distance(_at: Vector3) -> float:
		return 150.0

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[city_crowd_relocation] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count := 2) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var level := FixtureLevel.new()
	add_child(level)
	level.player = Node3D.new()
	level.add_child(level.player)
	var npcs := FixtureNPCs.new()
	level.add_child(npcs)
	var crowd := Crowd.new()
	level.add_child(crowd)
	crowd.level = level
	crowd.npcs = npcs
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = 0.24
	crowd._shape.height = 1.65
	crowd._meshes = [crowd._person_mesh(false), crowd._person_mesh(true)]
	crowd._add_resident(Vector3(1, 0, 1), 0.0, "social", false)
	crowd._add_resident(Vector3(4, 0, 3), 0.0, "social", false)
	crowd._add_resident(Vector3(5, 0, 45), 0.0, "social", false)
	crowd._build_batches()
	await frames()
	var resident: Dictionary = crowd.residents[0]
	var original_cell: Vector2i = resident.cell
	var batch: Dictionary = crowd._batches[resident.batch]
	# Repeated 8m escapes accumulate well beyond any fixed 12m padding.
	for step in 30:
		var previous: Vector3 = resident.position
		var next := previous + Vector3(8, 0, 0)
		crowd._relocate(0, previous, next)
		resident.body.position = next
		crowd._apply_transform(0, "stand")
	var at: Vector3 = resident.position
	check(at.x > 240 and resident.cell == original_cell, "repeated displacement crosses cells while retaining shared batch ownership")
	var from := at + Vector3(-1, 1.1, 0)
	var to := at + Vector3(1, 1.1, 0)
	var direct: Array[int] = crowd.react_to_threat(at, 2.0, from, to)
	check(direct == [0] and crowd._panic.has(0), "settled resident reacts exactly once to nearby shot beyond original cell padding")
	check(crowd._panic[0].threat == from, "direct near miss uses shooter as threat origin")
	crowd._finish_panic(0, true)
	crowd.set_presence(at, 20.0, 90.0)
	check(is_instance_valid(resident.body) and resident.body.collision_layer == 8,
		"near displaced resident keeps physical presence despite distant original cell")
	check(is_instance_valid(batch.node) and batch.node.visibility_range_end == 0,
		"retained displaced batch bypasses incorrect original-origin distance culling")
	crowd.set_presence(Vector3(2000, 0, 2000), 20.0, 90.0)
	await frames()
	check(not is_instance_valid(resident.body) and not is_instance_valid(batch.node),
		"settled displaced resident still unloads when player leaves actual location")
	crowd.set_presence(at, 20.0, 90.0)
	check(is_instance_valid(resident.body) and resident.body.global_position.is_equal_approx(at)
		and is_instance_valid(batch.node) and batch.node.visibility_range_end == 0,
		"returning to actual location recreates body and visible batch without origin visit")
	check(crowd.kill_resident(0, from, false), "displaced identity can die after reload")
	crowd.set_presence(Vector3(2000, 0, 2000), 20.0, 90.0)
	await frames()
	crowd.set_presence(at, 20.0, 90.0)
	check(crowd.is_dead(0) and (not is_instance_valid(resident.body) or resident.body.collision_layer == 0),
		"displaced dead identity never regains a collider after culling")
	# A live panic can cross cells before a settled relocation is committed.
	crowd.set_presence(Vector3.ZERO, 20.0, 90.0)
	var moving: Dictionary = crowd.residents[1]
	check(crowd.panic_resident(1, Vector3.ZERO), "active-panic fixture begins from an enabled resident")
	moving.position = Vector3(400, 0, 3)
	moving.body.position = moving.position
	crowd._apply_transform(1, "run")
	var moving_at: Vector3 = moving.position
	var moving_from := moving_at + Vector3(-1, 1.1, 0)
	var moving_to := moving_at + Vector3(1, 1.1, 0)
	direct = crowd.react_to_threat(moving_at, 2.0, moving_from, moving_to)
	check(direct == [1], "active mover reacts at actual position before relocation bookkeeping")
	crowd.set_presence(moving_at, 20.0, 90.0)
	check(is_instance_valid(moving.body) and batch.node.visibility_range_end == 0,
		"active mover remains renderable outside original batch visibility range")
	crowd._finish_panic(1, false)
	# A 90m shot passes a neighbor 45m from the shooter and endpoint: outside
	# both existing hearing/impact radii, but within the near-miss corridor.
	crowd.set_presence(Vector3(5, 0, 45), 20.0, 90.0)
	var shot_start := Vector3(5, 1.1, 0)
	var shot_end := Vector3(5, 1.1, 90)
	direct = crowd.react_to_threat(shot_start, 30.0, shot_start, shot_end)
	check(direct == [2] and crowd._panic.has(2), "middle of long shot alerts near-miss resident beyond hearing and endpoint radii")
	check(crowd._panic[2].threat == shot_start, "middle-of-shot victim flees from shooter")
	direct = crowd.react_to_threat(shot_end, 10.0, shot_start, shot_end)
	check(direct == [2] and crowd._panic[2].threat == shot_start,
		"cell and panic candidates deduplicate; endpoint event retains shooter threat origin")
	level.queue_free()
	await frames()
	print("[city_crowd_relocation] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
