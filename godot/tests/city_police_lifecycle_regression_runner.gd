extends Node3D
## Targeted regressions; the separate assistance smoke exercises full response.
const Assistance := preload("res://scripts/city/city_police_assistance.gd")
const Custody := preload("res://scripts/city/city_police_custody.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Crowd := preload("res://scripts/city/city_crowd.gd")

class People extends Node3D:
	var actors: Dictionary = {}
	var crowd: Node3D

class CombatFixture extends Node3D:
	var states: Dictionary = {}
	var dead: Dictionary = {}
	func fighter_snapshot() -> Array:
		return states.values()
	func is_actor_dead(id: String) -> bool:
		return dead.has(id)
	func actor_mode(actor) -> String:
		if not is_instance_valid(actor):
			return "gone"
		if actor.dead:
			return "dead"
		if states.has(actor.actor_id):
			return str(states[actor.actor_id].mode)
		return "unknown" if actor.combat_override else ""
	func disengage_actor(actor) -> void:
		states.erase(actor.actor_id)
		actor.combat_override = false
		actor.remove_meta("combat_controlled")

class Arena extends Node3D:
	var player: Node3D
	var npcs: Node3D
	var residents: Node3D
	var combat: Node3D
	var law: Node
	var inspector: Node
	var paused := false

var failures := 0
var arena: Arena
var service: Node3D
var combat: CombatFixture
var officer: CharacterBody3D
var suspect: CharacterBody3D

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	failures += int(not ok)
	print("[police_lifecycle] %s %s" % ["PASS" if ok else "FAIL", message])

func person(id: String, at: Vector3, cop := false) -> CharacterBody3D:
	var actor := Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, "cop_dan" if cop else "mama", id)
	actor.position = at
	arena.npcs.actors[id] = actor
	return actor

func incident(at: Vector3) -> Dictionary:
	service._open(at, "phone", "")
	return service.incidents[-1]

func reset() -> void:
	combat.states.clear()
	service.reset_state()
	officer.position = Vector3(0.0, 0.012, 0.0)
	officer.yaw = 0.0
	suspect.position = Vector3(0.0, 0.012, 8.0)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	arena.player = Node3D.new()
	arena.add_child(arena.player)
	arena.player.position = Vector3(40.0, 0.012, 40.0)
	arena.npcs = People.new()
	arena.add_child(arena.npcs)
	arena.residents = People.new()
	arena.add_child(arena.residents)
	combat = CombatFixture.new()
	arena.add_child(combat)
	arena.combat = combat
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	arena.add_child(floor_body)
	officer = person("patrol_officer_regression", Vector3(0.0, 0.012, 0.0), true)
	suspect = person("suspect_regression", Vector3(0.0, 0.012, 8.0))
	service = Assistance.new()
	arena.add_child(service)
	service.level = arena
	service.custody.setup(arena)
	service.tactics.space = get_world_3d().direct_space_state
	await get_tree().physics_frame
	_arrival_regressions()
	_alerted_dispatch_regression()
	await _cuff_range_regression()
	_threat_regressions()
	_custody_release_regression()
	await _custody_persistence_regressions()
	_station_completion_regression()
	print("POLICE_LIFECYCLE_REGRESSION failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arrival_regressions() -> void:
	var call := incident(Vector3(30.0, 0.012, 0.0))
	var o: Dictionary = service._adopt(officer, call, "foot")
	service._apply_path(o, [], call.at, 3.1, "respond")
	o.deadline = -1.0
	service._decide(o, call)
	check(not is_finite(float(call.arrived)), "exhausted/expired remote route cannot claim scene arrival")
	o.goal = call.at
	service._arrive_scene(o, call)
	check(not is_finite(float(call.arrived)), "direct arrival helper checks actual proximity")
	reset()
	call = incident(suspect.global_position)
	var s: Dictionary = service._add_suspect(call, suspect.actor_id, suspect, false, suspect.global_position)
	o = service._adopt(officer, call, "foot")
	o.target = s.id
	service._engage(o, call)
	check(is_finite(float(call.arrived)) and bool(s.warned), "visible physical encounter marks arrival even before call waypoint")
	reset()

func _threat_regressions() -> void:
	var call := incident(suspect.global_position)
	var s: Dictionary = service._add_suspect(call, suspect.actor_id, suspect, true, suspect.global_position)
	combat.states[suspect.actor_id] = {"id": suspect.actor_id, "actor": suspect, "mode": "gun", "aim": 0.3, "shots": 0}
	service.report_violence({"suspect_id": suspect.actor_id, "at": suspect.global_position, "kind": "shooting", "active": true, "armed": true, "dispatch": false})
	check(service._imminent(s), "active armed shooting authorizes proportionate response")
	var o: Dictionary = service._adopt(officer, call, "foot")
	o.target = s.id
	o.aim = 0.5
	service.report_violence({"suspect_id": suspect.actor_id, "at": suspect.global_position, "kind": "armed_threat", "active": false, "armed": false, "dispatch": false})
	check(not service._imminent(s) and float(o.aim) < 0.0, "same-tick disarm report immediately revokes queued lethal force")
	service._discover(call, suspect.global_position)
	check(not service._imminent(s), "rediscovery cannot reauthorize an older shooting report")
	reset()

func _cuff_range_regression() -> void:
	suspect.position = Vector3(0.0, 0.012, 4.0)
	var call := incident(suspect.global_position)
	var s: Dictionary = service._add_suspect(call, suspect.actor_id, suspect, false, suspect.global_position)
	service.custody.take(suspect, suspect.actor_id, service, service._clock)
	s.state = "held"
	var o: Dictionary = service._adopt(officer, call, "foot")
	o.target = s.id
	for i in 180:
		await get_tree().physics_frame
		service._engage(o, call)
		if str(o.state) == "cuff":
			break
		service._move_officer(o, 1.0 / 60.0)
	check(str(o.state) == "cuff" and officer.global_position.distance_to(suspect.global_position) <= Assistance.CUFF_RANGE + 0.2,
		"precise final approach reaches cuff range instead of stopping at street waypoint tolerance")
	o.timer = Assistance.CUFF_SECONDS
	service._decide(o, call)
	check(str(s.state) == "escort", "physically adjacent compliant suspect proceeds to arrest and escort")
	reset()

func _custody_release_regression() -> void:
	var call := incident(suspect.global_position)
	var s: Dictionary = service._add_suspect(call, suspect.actor_id, suspect, false, suspect.global_position)
	var held = service.custody.take(suspect, suspect.actor_id, service, service._clock)
	check(held == suspect, "fixture can take compliant suspect into temporary custody")
	s.state = "held"
	service._close(call, "unavailable", "No replacement officer could arrive.")
	check(not service.custody.records.has(suspect.actor_id) and not suspect.combat_override and not suspect.has_meta("combat_controlled"), "abandoned incident releases unfinished custody and routine ownership")
	reset()

func _alerted_dispatch_regression() -> void:
	var call := incident(suspect.global_position)
	officer.combat_override = true
	officer.set_meta("combat_controlled", true)
	combat.states[officer.actor_id] = {"id": officer.actor_id, "actor": officer, "mode": "panic:alert"}
	check(service._free_officer(officer) and officer.combat_override and combat.states.has(officer.actor_id), "candidate query accepts alerted police without stealing ownership")
	check(service._send_foot(call, officer, suspect.global_position) and not combat.states.has(officer.actor_id) and officer.has_meta("police_assist"), "successful dispatch releases alert ownership before enlisting patrol")
	reset()
	officer.combat_override = true
	combat.states[officer.actor_id] = {"id": officer.actor_id, "actor": officer, "mode": "gun"}
	check(not service._free_officer(officer), "dispatch cannot steal an officer actively fighting")
	officer.combat_override = false
	reset()

func _station_completion_regression() -> void:
	var detainee := person("station_detainee", officer.global_position + Vector3(0.0, 0.0, 1.5))
	var call := incident(detainee.global_position)
	var s: Dictionary = service._add_suspect(call, detainee.actor_id, detainee, false, detainee.global_position)
	service.custody.take(detainee, detainee.actor_id, service, service._clock)
	service.custody.set_state(detainee.actor_id, "escort")
	s.state = "escort"
	var o: Dictionary = service._adopt(officer, call, "foot")
	o.state = "escort"
	o.escort = detainee.actor_id
	service._station = officer.global_position
	o.goal = service._station
	arena.player.position = officer.global_position + Vector3(5.0, 0.0, 0.0)
	check(not service._unseen(officer) and not service._unseen(detainee), "station fixture keeps caller watching the handoff")
	service._escort(o, call)
	check(service.custody.ids_in_custody().has(detainee.actor_id) and str(s.state) == "in_custody",
		"actual station arrival completes custody while caller remains nearby")

func _custody_persistence_regressions() -> void:
	var custody: RefCounted = service.custody
	for i in 13:
		var actor := person("completed_%d" % i, Vector3(50.0 + float(i), 0.012, 0.0))
		check(custody.take(actor, actor.actor_id, service, 0.0) == actor, "completed arrests do not exhaust active capacity %d" % i)
		custody.take_in(actor.actor_id)
	check(custody.records.is_empty() and custody.ids_in_custody().size() == 13, "completed registry is separate from active physical records")
	var actor: CharacterBody3D = arena.npcs.actors["completed_0"]
	actor.set_enabled(true)
	check(not actor.enabled and not actor.visible and actor.collision_layer == 0, "later mission/schedule activation cannot resurrect completed custody")
	var snapshot: Dictionary = service.snapshot_state()
	check(service.validate_state(snapshot).is_empty(), "completed custody snapshot validates")
	check(not service.validate_state({"version": 1, "custody_ids": ["player"]}).is_empty(), "caller cannot be restored as a detainee")
	check(not service.validate_state({"version": 1, "custody_ids": [officer.actor_id]}).is_empty(), "police cannot be restored as detainees")
	check(not service.validate_state({"version": 1, "custody_ids": ["completed_0", "completed_0"]}).is_empty(), "duplicate custody IDs are rejected before mutation")
	check(not service.validate_state({"version": 1, "custody_ids": ["missing_identity"]}).is_empty(), "unknown custody identities are rejected")
	var restored: Dictionary = service.restore_state({"version": 1, "custody_ids": []})
	check(restored.ok and custody.ids_in_custody().size() == 13, "older empty checkpoint cannot undo completed arrests")
	combat.dead["completed_0"] = true
	restored = service.restore_state(snapshot)
	check(restored.ok and restored.skipped_dead.has("completed_0") and not custody.ids_in_custody().has("completed_0"), "death registry takes precedence over saved custody")
	var newly_restored := person("restore_only", Vector3(45.0, 0.012, 5.0))
	restored = service.restore_state({"version": 1, "custody_ids": ["restore_only"]})
	check(restored.ok and not newly_restored.enabled and newly_restored.has_meta("combat_controlled"), "restoring a completed ID hides a currently live scheduled actor")
	await _crowd_streaming_regression(custody)

func _crowd_streaming_regression(custody: RefCounted) -> void:
	var crowd := Crowd.new()
	arena.npcs.add_child(crowd)
	arena.npcs.crowd = crowd
	var body := StaticBody3D.new()
	body.collision_layer = 8
	crowd.add_child(body)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.instance_count = 1
	var batch_node := MultiMeshInstance3D.new()
	batch_node.multimesh = multi
	crowd.add_child(batch_node)
	crowd.residents.append({"position": Vector3.ZERO, "yaw": 0.0, "body": body, "batch": "test", "slot": 0, "cell": Vector2i.ZERO})
	crowd._batches["test"] = {"multimesh": multi, "node": batch_node, "origin": Vector3.ZERO}
	crowd._cells[Vector2i.ZERO] = {"cell": Vector2i.ZERO, "center": Vector3.ZERO, "resident_indices": [0], "nodes": [batch_node], "bodies": [body]}
	var result: Dictionary = custody.restore_state({"version": 1, "custody_ids": ["crowd_0"]})
	check(result.ok and body.collision_layer == 0 and crowd.residents[0].get("police_custody", false), "crowd custody hides exact identity and collider")
	var hidden_transform := multi.get_instance_transform(0)
	crowd.set_presence(Vector3(1000.0, 0.0, 1000.0))
	await get_tree().process_frame
	crowd.set_presence(Vector3.ZERO)
	check(crowd.residents[0].body == null and crowd._cells[Vector2i.ZERO].bodies.is_empty()
		and crowd.residents[0].get("police_custody", false), "crowd streaming does not respawn a completed detainee")
	if not RenderingServer.get_video_adapter_name().is_empty():
		check(is_zero_approx(hidden_transform.basis.determinant()) and is_zero_approx(multi.get_instance_transform(0).basis.determinant()),
			"rendered crowd custody keeps its instance hidden across streaming")
	else:
		print("[police_lifecycle] SKIP render readback: dummy backend; rendered fixture must check hidden transform")
	crowd.end_combat(0)
	check(crowd.residents[0].get("combat_controlled", false), "late combat release cannot resurrect completed crowd custody")
