extends Node
## Isolates production ownership decisions; perception is forced occluded and
## pose/movement are instrumented so an unseen-player leak fails deterministically.

class Officer:
	extends CharacterBody3D
	var actor_id := "patrol_officer_fixture"
	var dead := false
	var enabled := true
	var combat_override := true
	var yaw := 0.0

class CombatProbe:
	extends "res://scripts/city/city_combat.gd"
	var movement_requests := 0
	func _sight(_from: Vector3, _to: Vector3, _source: CollisionObject3D, _target_body: CollisionObject3D) -> bool:
		return false
	func _tick_body_clock(_actor, _delta: float) -> void:
		pass
	func _pose_actor(_actor: CharacterBody3D, _state: Dictionary) -> void:
		pass
	func _pose_gun(_actor, _state: Dictionary) -> void:
		pass
	func _move_actor(_actor: CharacterBody3D, _destination: Vector3, _delta: float, _speed: float) -> int:
		movement_requests += 1
		return 0

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[combat_law_ownership] %s %s" % ["PASS" if ok else "FAIL", label])
	failures += int(not ok)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var world := Node3D.new()
	add_child(world)
	var combat := CombatProbe.new()
	world.add_child(combat)
	var player := CharacterBody3D.new()
	world.add_child(player)
	player.position = Vector3(5, 0, 0)
	combat.player = player
	var officer := Officer.new()
	world.add_child(officer)
	officer.set_meta("law_responder", true)
	combat._react(officer, player.global_position, false, true)
	combat._react(officer, player.global_position, true, true)
	combat._react(officer, player.global_position, false, false)
	check(combat._active.is_empty() and combat._panic.is_empty(), "gunfire cannot steal a law-owned responder into alert or combat")
	var state := {"actor": officer, "mode": "aggro", "time": 0.0, "unseen": 0.0,
		"hurt": 0.0, "cooldown": 0.0, "attack": 0.2, "aim": 0.2, "gun_cooldown": 0.0}
	combat._tick_actor(state, 0.1)
	check(combat.movement_requests == 0 and officer.yaw == 0.0 and state.attack < 0.0 and state.unseen > 0.0, "occluded melee responder holds without following hidden player and cancels swing")
	combat._tick_gun(state, 0.1)
	check(combat.movement_requests == 0 and officer.yaw == 0.0 and state.aim < 0.0, "occluded armed responder does not rotate toward hidden player or retain telegraph")
	var key := officer.get_instance_id()
	combat._active[key] = {"mode": "aggro"}
	check(combat.actor_mode(officer) == "aggro", "public actor mode exposes combat owner")
	combat._knocked[officer.actor_id] = {}
	check(combat.actor_mode(officer) == "downed", "downed state takes precedence")
	combat._knocked.clear()
	combat._active.clear()
	combat._panic[key] = {"mode": "alert"}
	check(combat.actor_mode(officer) == "panic:alert", "public actor mode exposes alert owner")
	combat._panic.clear()
	officer.combat_override = false
	check(combat.actor_mode(officer).is_empty(), "unowned officer exposes empty mode")
	officer.dead = true
	check(combat.actor_mode(officer) == "dead" and combat.actor_mode(null) == "gone", "dead and missing actors stay unavailable")
	world.free()
	get_tree().quit(0 if failures == 0 else 1)
