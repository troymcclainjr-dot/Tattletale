extends Node3D
## Run only through the project's serialized Godot test runner.
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const Reactions := preload("res://scripts/city/city_bicycle_reactions.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Law := preload("res://scripts/city/city_law.gd")

class Explorer extends CharacterBody3D:
	var enabled := true
	var yaw := 0.0
	var camera_yaw := 0.0
	var chase_distance := 6.2
	var phone: Node3D
	var seated_vehicle: Node3D
	func is_seated() -> bool:
		return seated_vehicle != null
	func enter_vehicle(bike: Node3D) -> void:
		seated_vehicle = bike
		follow_vehicle()
	func follow_vehicle() -> void:
		global_position = seated_vehicle.global_position
	func leave_vehicle(at: Vector3, heading: float) -> void:
		seated_vehicle = null
		global_position = at
		yaw = heading

class Fixture extends Node3D:
	var paused := false
	var player: CharacterBody3D
	var combat: Node3D
	var npcs: Node3D
	var bicycle: CharacterBody3D
	var driving: Node3D

class NpcsFixture extends Node3D:
	var crowd: Node3D

class CrowdFixture extends Node3D:
	var residents: Array[Dictionary] = []
	func _relocate(index: int, _from: Vector3, to: Vector3, keep_walk: bool) -> void:
		assert(keep_walk)
		residents[index].position = to
	func _apply_transform(_index: int, _kind: String) -> void:
		pass

var errors: Array[String] = []
var person_hits := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func _body(parent: Node3D, at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	parent.add_child(body)
	return body

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var world := Fixture.new()
	add_child(world)
	_body(world, Vector3(0.0, -0.25, 0.0), Vector3(100.0, 0.5, 100.0), 1)
	var explorer := Explorer.new()
	world.player = explorer
	world.add_child(explorer)
	explorer.position = Vector3(0.0, 0.05, 0.0)
	await get_tree().physics_frame
	var bike := Bicycle.new()
	world.add_child(bike)
	world.bicycle = bike
	bike.setup(world)
	_check(bike.spawned, "bike finds clear nearby parking")
	_check(bike.get_map_pois().size() == 1, "parked bicycle is discoverable on map")
	var mount := InputEventKey.new()
	mount.keycode = KEY_F
	mount.pressed = true
	_check(bike.handle_input(mount) and bike.active and explorer.is_seated(), "F mounts nearby bicycle")
	_check(bike._rider.g.visible, "mounted bicycle displays rider")
	bike.set_control_override(Vector2(0.0, 1.0))
	for i in 90:
		await get_tree().physics_frame
		bike.tick(1.0 / 60.0)
	_check(bike.speed > 3.0 and bike.speed <= Bicycle.MAX_SPEED, "bicycle accelerates within safe cap")
	_check(not bike.exit_vehicle(), "cannot dismount a moving bicycle")
	world.paused = true
	var stopped_at := bike.global_position
	bike.tick(1.0)
	_check(bike.global_position.is_equal_approx(stopped_at), "pause freezes bicycle")
	world.paused = false
	# Force a real physics contact. It must stop and emit only harmless data.
	var person_at := bike.global_position + Vector3(0.0, 0.9, 2.2)
	var person := _body(world, person_at, Vector3(0.6, 1.8, 0.6), 8)
	person.set_meta("city_crowd_index", 17)
	bike.pedestrian_contact.connect(func(contact: Dictionary):
		person_hits += 1
		_check(contact.harmless and float(contact.body_damage) == 0.0, "contact cannot request damage")
		_check(int(contact.crowd_index) == 17, "contact preserves pedestrian identity")
	)
	for i in 40:
		await get_tree().physics_frame
		bike.tick(1.0 / 60.0)
	_check(person_hits == 1, "person contact emits once per cooldown")
	_check(bike.global_position.z < person_at.z, "bicycle cannot pass through person")
	_check(bike.speed < 1.0, "person contact slows bicycle")
	bike.set_control_override(Vector2.ZERO, true)
	for i in 30:
		await get_tree().physics_frame
		bike.tick(1.0 / 60.0)
	_check(bike.exit_vehicle(), "stopped bicycle permits checked dismount")
	_check(not explorer.is_seated() and not bike._rider.g.visible, "dismount restores walking and hides rider")
	_check(is_equal_approx(explorer.chase_distance, 6.2), "dismount restores camera distance")
	_check(bike.get_map_pois().size() == 1, "dismounted bicycle remains parked")
	await _law_bicycle_exit(world, bike)
	await _reactions(world, bike)
	print("CITY_BICYCLE_SMOKE ", "PASS" if errors.is_empty() else "FAIL", " contacts=", person_hits)
	world.queue_free()
	get_tree().quit(0 if errors.is_empty() else 1)

func _law_bicycle_exit(world: Node3D, bike: CharacterBody3D) -> void:
	# Synthetic clear-floor arrangement; the transport and recovery exit are real.
	# No law setup/overlay or facility teleport is needed for this focused contract.
	bike.clear_control_override()
	bike.global_position = Vector3(-10.0, .05, -10.0)
	bike.yaw = 0.0
	bike.rotation.y = 0.0
	world.player.global_position = bike.global_position + Vector3(1.3, 0.0, 0.0)
	await get_tree().physics_frame
	_check(bike.enter_bicycle(), "law recovery fixture mounts actual bicycle")
	if not bike.active:
		return
	var law := Law.new()
	world.add_child(law)
	law.level = world
	_check(law._ridden_transport() == bike, "law selects ridden bicycle without legacy car manager")
	# A recovery may arrive while moving. Force bypasses speed, never clearance.
	bike.speed = 6.0
	_check(not bike.exit_vehicle(), "ordinary dismount remains blocked at recovery test speed")
	_check(law._exit_vehicle(), "actual law recovery forces safe bicycle dismount")
	_check(not bike.active and not world.player.is_seated() and law.vehicle_exits == 1, "law and bicycle agree rider authority has been released")
	var at: Vector3 = world.player.global_position
	_check(at.is_finite() and not bike._ground(at).is_empty() and bike._standing_clear(at) and absf(at.y - bike.global_position.y) < .65, "law dismount lands on finite supported clear ground")
	_check(bike.enter_bicycle(), "blocked-exit fixture remounts real bicycle")
	if bike.active:
		var seated_at: Vector3 = world.player.global_position
		var obstruction := _body(world, bike.global_position + Vector3.UP * 2.0, Vector3(9.0, 4.0, 9.0), 2)
		await get_tree().physics_frame
		_check(not law._exit_vehicle() and bike.active and world.player.is_seated(), "forced law exit refuses when every local landing is obstructed")
		_check(world.player.global_position.is_equal_approx(seated_at), "failed forced exit never invents relocation coordinates")
		obstruction.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(law._exit_vehicle() and not world.player.is_seated(), "law safely releases bicycle after real obstruction is removed")
	law.queue_free()

func _reactions(world: Node3D, bike: CharacterBody3D) -> void:
	var crowd_fixture := CrowdFixture.new()
	var npcs_fixture := NpcsFixture.new()
	world.npcs = npcs_fixture
	world.add_child(npcs_fixture)
	npcs_fixture.crowd = crowd_fixture
	npcs_fixture.add_child(crowd_fixture)
	var neighbor := Actor.new()
	world.add_child(neighbor)
	neighbor.build(world, "bicycle_test_neighbor", "mama", "Neighbor")
	neighbor.position = Vector3(20.0, 0.012, 20.0)
	neighbor.set_target(Vector3(20.0, 0.012, 25.0))
	var saved_revision: int = neighbor.target_revision
	var saved_target: Vector3 = neighbor.target
	var resident := _body(world, Vector3(24.0, 0.012, 20.0), Vector3(0.48, 1.65, 0.48), 8)
	# Crowd bodies place their shape above the foot origin.
	resident.get_child(0).position.y = 0.9
	resident.set_meta("city_crowd_index", 0)
	var resident_home := resident.global_position
	crowd_fixture.residents.append({"position": resident_home, "body": resident, "pose": 0,
		"activity": "walking", "yaw": 0.0, "body_shape": resident.get_child(0).shape,
		"body_shape_offset": Vector3.UP * 0.9})
	var reactions := Reactions.new()
	world.add_child(reactions)
	reactions.setup(world, bike)
	_check(reactions.crowd == npcs_fixture.crowd, "reaction lookup follows actual level.npcs.crowd ownership")
	bike.global_position = Vector3(20.0, 0.04, 17.5)
	await get_tree().physics_frame
	reactions._avoid_nearby(bike.global_position, Vector3(0.0, 0.0, 5.0))
	_check(neighbor.bicycle_override, "approaching bicycle starts a bounded actor sidestep")
	var scans: int = reactions.scans
	reactions._avoid_nearby(bike.global_position, Vector3(0.0, 0.0, 5.0))
	_check(reactions.scans == scans and reactions.candidates_checked <= Reactions.MAX_NEARBY, "proximity queries obey cadence and result cap")
	reactions._begin(resident, resident_home - Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, 1.0), false)
	_check(crowd_fixture.residents[0].get("bicycle_avoiding", false), "crowd sidestep claims only its temporary movement flag")
	for i in 210:
		await get_tree().physics_frame
		reactions.tick(1.0 / 60.0)
	_check(not neighbor.bicycle_override and neighbor.target == saved_target and neighbor.target_revision == saved_revision, "sidestep restores actor routine without rewriting destination")
	_check(resident.global_position.distance_to(resident_home) < 0.04 and not crowd_fixture.residents[0].get("bicycle_avoiding", false), "crowd sidestep returns to original walking point")
	reactions._on_contact({"collider": neighbor, "direction": Vector3(0.0, 0.0, 1.0)})
	_check(reactions.complaints == 1 and neighbor._speech_remaining > 0.0 and not neighbor.dead and not neighbor.combat_override, "bump produces angry speech without combat or death")
	neighbor.set_target(Vector3(21.0, 0.012, 24.0))
	reactions.tick(1.0 / 60.0)
	_check(not neighbor.bicycle_override and neighbor.target == Vector3(21.0, 0.012, 24.0), "new mission destination supersedes temporary sidestep")
	# A blocked return expires its task but preserves a safe normal-routine join.
	reactions._begin(resident, resident_home - Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, 1.0), true)
	var id := resident.get_instance_id()
	_check(reactions._tasks.has(id), "blocked-return fixture starts a new crowd sidestep")
	if reactions._tasks.has(id):
		var task: Dictionary = reactions._tasks[id]
		var displaced := resident_home + Vector3(1.0, 0.0, 0.0)
		reactions._set_position(task, displaced)
		task.deadline = reactions._clock
		reactions.tick(1.0 / 60.0)
		_check(not reactions._tasks.has(id) and resident.global_position == displaced, "timed-out return frees task capacity without teleporting")
		_check(crowd_fixture.residents[0].get("bicycle_rejoin", Vector3.INF) == resident_home and crowd_fixture.residents[0].activity == "walking", "timed-out walker keeps original route and a bounded rejoin target")
