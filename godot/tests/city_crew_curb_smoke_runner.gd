extends Node
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const DT := 1.0 / 60.0
var world: Node3D
var failures := 0
var passes := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	passes += int(ok)
	print("[crew_curb] ", "PASS " if ok else "FAIL ", label)

func _box(label: String, at: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	body.global_position = at

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	_box("Street", Vector3(1, -0.5, 10), Vector3(20, 1, 50), 1)
	for case_index in 5:
		await _case(case_index)
	await _diagonal()
	print("[crew_curb] COMPLETE ", passes, " passed; ", failures, " failed")
	get_tree().quit(1 if failures else 0)

func _case(case_index: int) -> void:
	var z := float(case_index) * 5.0
	var name_: String = ["curb", "tall_step", "wall", "ceiling", "person"][case_index]
	var height := 0.35 if case_index == 1 else 0.15
	_box(name_ + "_ledge", Vector3(2.75, height * 0.5, z), Vector3(3.5, height, 3), 1)
	var actor := Actor.new()
	world.add_child(actor)
	actor.build(world, "crew_" + name_, "mailman", "Paramedic")
	actor.global_position = Vector3(0, 0.012, z)
	actor.yaw = PI * 0.5
	actor.puppet.g.rotation.y = actor.yaw
	if case_index in [2, 4]:
		_box(name_ + "_blocker", Vector3(1.3, 1.5, z), Vector3(0.3, 3, 2), 2 if case_index == 2 else 8)
	if case_index == 3:
		var capsule: CapsuleShape3D = actor.capsule.shape
		var head_top: float = actor.global_position.y + actor.capsule.position.y + capsule.height * 0.5
		_box("LowCeiling", Vector3(2.25, head_top + 0.14, z), Vector3(3.5, 0.2, 3), 2)
	await get_tree().physics_frame
	var max_rise := 0.0
	var max_horizontal := 0.0
	var original_mask: int = actor.collision_mask
	for frame in 180:
		var before: Vector3 = actor.global_position
		Tactics.tick_body(actor, DT)
		Tactics.walk(actor, Vector3(3, height + 0.012, z), DT, 1.9)
		max_rise = maxf(max_rise, actor.global_position.y - before.y)
		max_horizontal = maxf(max_horizontal, Tactics.flat(before, actor.global_position))
		await get_tree().physics_frame
	if case_index == 0:
		check(actor.global_position.x > 2.7 and absf(actor.global_position.y - 0.162) < 0.02,
			"15 cm curb is crossed by actual capsule walking: " + str(actor.global_position))
	else:
		check(actor.global_position.x < 1.15, name_ + " remains physically blocking: " + str(actor.global_position))
	check(max_rise <= 0.231 and max_horizontal <= 1.9 * DT + 0.005,
		name_ + " respects 23 cm rise and one horizontal walking step")
	check(actor.collision_mask == original_mask and actor.collision_layer == Actor.ACTOR_LAYER,
		name_ + " retains original full collision masks")
	if case_index == 0:
		var max_drop := 0.0
		max_horizontal = 0.0
		for frame in 180:
			var before: Vector3 = actor.global_position
			Tactics.tick_body(actor, DT)
			Tactics.walk(actor, Vector3(0, 0.012, z), DT, 1.9)
			max_drop = maxf(max_drop, before.y - actor.global_position.y)
			max_horizontal = maxf(max_horizontal, Tactics.flat(before, actor.global_position))
			await get_tree().physics_frame
		check(actor.global_position.x < 0.3 and absf(actor.global_position.y - 0.012) < 0.02,
			"15 cm curb is descended with actual trailing capsule clearance: " + str(actor.global_position))
		check(max_drop <= 0.231 and max_horizontal <= 1.9 * DT + 0.005,
			"descending curb respects drop and horizontal step bounds")
	actor.queue_free()
	await get_tree().physics_frame

func _diagonal() -> void:
	_box("DiagonalLedge", Vector3(2.75, 0.075, 30), Vector3(3.5, 0.15, 8), 1)
	var actor := Actor.new()
	world.add_child(actor)
	actor.build(world, "crew_diagonal", "mailman", "Paramedic")
	actor.global_position = Vector3(0, 0.012, 28.5)
	await get_tree().physics_frame
	var max_horizontal := 0.0
	var max_vertical := 0.0
	for goal in [Vector3(3, 0.162, 31.5), Vector3(0, 0.012, 28.5)]:
		for frame in 240:
			var before: Vector3 = actor.global_position
			Tactics.tick_body(actor, DT)
			Tactics.walk(actor, goal, DT, 1.9)
			max_horizontal = maxf(max_horizontal, Tactics.flat(before, actor.global_position))
			max_vertical = maxf(max_vertical, absf(actor.global_position.y - before.y))
			await get_tree().physics_frame
		check(Tactics.flat(actor.global_position, goal) < 0.25 and absf(actor.global_position.y - goal.y) < 0.02,
			"diagonal curb traversal reaches physical destination " + str(goal) + ": " + str(actor.global_position))
	check(max_vertical <= 0.231 and max_horizontal <= 1.9 * DT + 0.005,
		"diagonal ascent/descent retains vertical and horizontal movement bounds")
	actor.queue_free()
	await get_tree().physics_frame
