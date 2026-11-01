extends Node
const Crowd := preload("res://scripts/city/city_crowd.gd")
const STEP := 0.05

class FixtureLevel extends Node3D:
	var player: Node3D

class FixtureNPCs extends Node3D:
	func _route_distance(_at: Vector3) -> float:
		return 150.0

var level: FixtureLevel
var crowd: Node3D
var passed := 0
var failed := 0

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[city_crowd_motion] %s %s" % ["PASS" if ok else "FAIL", label])

func advance() -> void:
	crowd._clock += STEP
	crowd._tick_walkers(STEP)
	await frames(1)

func reset_walker() -> void:
	var resident: Dictionary = crowd.residents[0]
	resident.position = Vector3(0, 0, 3)
	resident.body.position = resident.position
	resident.walk_progress = .5
	resident.walk_direction = 1.0
	resident.yaw = 0.0
	var batch: Dictionary = crowd._batches[resident.batch]
	batch.multimesh.set_instance_transform(resident.slot, Transform3D(Basis.IDENTITY, resident.position - batch.origin))
	await frames(2)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	level = FixtureLevel.new()
	add_child(level)
	level.player = Node3D.new()
	level.player.position = Vector3(20, 0, 3)
	level.add_child(level.player)
	var npcs := FixtureNPCs.new()
	level.add_child(npcs)
	crowd = Crowd.new()
	level.add_child(crowd)
	crowd.level = level
	crowd.npcs = npcs
	var capsule := CapsuleShape3D.new()
	capsule.radius = .24
	capsule.height = 1.65
	crowd._shape = capsule
	var meshes: Array[ArrayMesh] = [crowd._person_mesh(false), crowd._person_mesh(true)]
	crowd._meshes = meshes
	crowd._add_resident(Vector3(0, 0, 3), 0.0, "walking", false)
	var resident: Dictionary = crowd.residents[0]
	var path: Array[Vector3] = []
	for i in 13:
		path.append(Vector3(0, 0, float(i) * .5))
	resident.walk_a = path[0]
	resident.walk_b = path[-1]
	resident.walk_path = path
	resident.walk_progress = .5
	resident.walk_direction = 1.0
	resident.walk_speed = 1.25
	crowd._walkers.append(0)
	crowd._build_batches()
	await frames(3)
	var batch: Dictionary = crowd._batches[resident.batch]
	var mesh: MultiMeshInstance3D = batch.node
	var original_id := mesh.get_instance_id()
	crowd.set_presence(Vector3.ZERO, 20.0, 90.0)
	check(is_equal_approx(mesh.visibility_range_end, 90.0), "existing crowd batch immediately follows lower quality range")
	crowd.set_presence(Vector3.ZERO, 40.0, 220.0)
	check(mesh.get_instance_id() == original_id and is_equal_approx(mesh.visibility_range_end, 220.0), "existing batch follows larger range without unload or recreation")
	var min_z := 3.0
	var max_z := 3.0
	var minimum_facing_dot := 1.0
	var stationary_turns := 0
	var endpoint_visits := 0
	var last_direction := 1.0
	var smooth_turns := true
	var feet_fixed := true
	var rendered_feet_fixed := true
	# Godot's dummy renderer ignores MultiMesh writes and returns identity on
	# readback. Real instance readback is asserted by this same fixture on GPU.
	var rendered_readback := DisplayServer.get_name() != "headless"
	var max_body_error := 0.0
	var max_render_error := 0.0
	for i in 480:
		var before: Vector3 = resident.position
		var old_yaw: float = resident.yaw
		await advance()
		var motion: Vector3 = resident.position - before
		motion.y = 0.0
		var turn: float = absf(wrapf(float(resident.yaw) - old_yaw, -PI, PI))
		smooth_turns = smooth_turns and turn <= Crowd.WALK_TURN_RATE * STEP + .00001
		if motion.length() > .00001:
			var forward := Vector3(sin(float(resident.yaw)), 0, cos(float(resident.yaw)))
			minimum_facing_dot = minf(minimum_facing_dot, motion.normalized().dot(forward))
		elif turn > .001:
			stationary_turns += 1
			var body_error: float = before.distance_to(resident.body.position)
			max_body_error = maxf(max_body_error, body_error)
			feet_fixed = feet_fixed and body_error < .00001
			if rendered_readback:
				var rendered: Transform3D = mesh.multimesh.get_instance_transform(0)
				var render_error: float = (rendered.origin + batch.origin).distance_to(before)
				max_render_error = maxf(max_render_error, render_error)
				rendered_feet_fixed = rendered_feet_fixed and render_error < .00001
		if float(resident.walk_direction) != last_direction:
			endpoint_visits += 1
			last_direction = resident.walk_direction
		min_z = minf(min_z, resident.position.z)
		max_z = maxf(max_z, resident.position.z)
	check(minimum_facing_dot > .99, "all walking displacement faces forward, including both endpoint reversals")
	print("[city_crowd_motion] turn samples=%d max_body_error=%.6f max_render_error=%.6f" % [stationary_turns, max_body_error, max_render_error])
	check(stationary_turns >= 30 and feet_fixed, "endpoint turns rotate in place with physical feet fixed")
	if rendered_readback:
		check(rendered_feet_fixed, "GPU MultiMesh readback confirms rendered feet stay fixed during turns")
	else:
		print("[city_crowd_motion] SKIP rendered feet readback: headless dummy renderer returns identity; run this fixture offscreen with a GPU renderer")
	check(smooth_turns, "yaw changes stay within the smooth turn speed limit")
	check(min_z < .0001 and max_z > 5.9999 and endpoint_visits >= 3, "walker reaches both exact endpoints repeatedly without getting stuck")
	check(crowd.residents.size() == 1 and crowd._walkers.size() == 1, "turning and quality changes preserve the resident allocation")
	await reset_walker()
	level.player.position = Vector3(0, 0, 3.5)
	for i in 20:
		await advance()
	check(resident.position.distance_to(Vector3(0, 0, 3)) < .00001 and is_equal_approx(resident.walk_progress, .5), "walker yields to the player without advancing its path")
	level.player.position = Vector3(20, 0, 3)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	blocker.position = Vector3(0, .9, 3.5)
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1.8, .4)
	var collision := CollisionShape3D.new()
	collision.shape = box
	blocker.add_child(collision)
	level.add_child(blocker)
	await frames(2)
	for i in 30:
		await advance()
	check(resident.position.z < 3.15, "capsule sweep still stops for a patrol entering the walking corridor")
	blocker.queue_free()
	await frames(2)
	for i in 80:
		await advance()
	check(resident.position.z > 5.0, "walker resumes after the patrol obstruction clears")
	print("[city_crowd_motion] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
