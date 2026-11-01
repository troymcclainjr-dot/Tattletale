extends Node
## Police incident response in a small physics arena with real combat: a call
## with no violence is investigated (a real patrol walks there and back, never
## teleported), an unarmed attacker is warned and arrested without a shot, an
## armed shooter is fired on only with a clear line (a bystander in the line
## holds fire) and firing stops once they are neutralized. Bounds, the law
## enlist guard and the cruiser assist contract are checked without traffic.
const Assistance := preload("res://scripts/city/city_police_assistance.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Law := preload("res://scripts/city/city_law.gd")
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

class PhoneFixture:
	extends Node3D
	var active := false
	var statuses: Array[String] = []
	func set_report_status(message: String) -> void:
		statuses.append(message)
	func suspend() -> void:
		pass

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	var combat: Node3D
	var law: Node
	var paused := false

var arena: Arena
var player: CharacterBody3D
var phone: PhoneFixture
var combat: Node3D
var law: Node
var assistance: Node3D
var officer: CharacterBody3D
var far_officer: CharacterBody3D
var failures := 0
var max_step := 0.0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[police_assistance] %s %s" % ["PASS" if ok else "FAIL", label])

func step(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await tick_once()

func tick_once() -> void:
	var before := officer.global_position
	# The caller's health is not under test; a downed player would pause combat.
	combat.health = maxf(combat.health, 60.0)
	combat.tick(1.0 / 60.0)
	assistance.tick(1.0 / 60.0)
	max_step = maxf(max_step, Vector2(officer.global_position.x - before.x, officer.global_position.z - before.z).length())
	await get_tree().physics_frame

func advance_until(condition: Callable, limit: float) -> bool:
	for i in ceili(limit * 60.0):
		if condition.call():
			return true
		await tick_once()
	return bool(condition.call())

func box(at: Vector3, size_: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = size_
	shape.shape = form
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

## A standing person who does not react: the static body a crowd resident uses.
func bystander(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func person(id: String, cast: String, label: String, at: Vector3, yaw: float) -> CharacterBody3D:
	var actor := Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, cast, label)
	arena.npcs.actors[id] = actor
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	return actor

func id_with(armed: bool, prefix: String) -> String:
	for i in 200:
		var id := "%s_%d" % [prefix, i]
		if Combat.is_armed_id(id) == armed:
			return id
	return prefix

func place_officer(at: Vector3, yaw: float) -> void:
	# Fixture placement between scenarios, never during a response.
	officer.global_position = at
	officer.yaw = yaw
	officer.puppet.g.rotation.y = yaw
	max_step = 0.0

func calm() -> void:
	assistance.reset_state()
	combat.recover_player()
	combat.health = 100.0
	await step(0.2)

func status() -> Dictionary:
	return assistance.get_status()

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(240, 1, 240))
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.012, 0)
	player.enabled = true
	phone = PhoneFixture.new()
	arena.add_child(phone)
	player.phone = phone
	arena.player = player
	arena.npcs = PeopleFixture.new()
	arena.add_child(arena.npcs)
	arena.residents = PeopleFixture.new()
	arena.add_child(arena.residents)
	officer = person("patrol_officer_0", "cop_dan", "Patrol officer", Vector3(16, 0.012, 2), -PI * 0.5)
	var beat: Array[Vector3] = [Vector3(16, 0.012, 2), Vector3(16, 0.012, 8)]
	officer.set_patrol(beat)
	far_officer = person("patrol_officer_1", "cop_steve", "Patrol officer", Vector3(-80, 0.012, 0), 0.0)
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	arena.combat = combat
	# Law is composed but never set up or ticked: its responder registry and
	# enlist guard are what assistance relies on.
	law = Law.new()
	arena.law = law
	assistance = Assistance.new()
	arena.add_child(assistance)
	assistance.setup(arena)
	assistance.search_seconds = 3.0
	assistance.secure_seconds = 1.0
	await step(0.1)
	check(bool(status().available), "service is available with real foot patrols")

	# ---- 1. A call with no violence: investigate the call location.
	var reply: Dictionary = assistance.request_help(player.global_position)
	check(bool(reply.ok) and int(reply.dispatched) == 1 and str(reply.threat) == "none" and int(reply.suspects) == 0,
		"a call with nobody violent nearby names no suspect and sends one officer")
	check(str(reply.message).contains("on foot"), "the reply says honestly who is coming: %s" % reply.message)
	check(officer.combat_override and officer.has_meta("police_assist") and not far_officer.has_meta("police_assist"),
		"the nearest free patrol is taken; an unreachable one is not")
	check(law._enlist(officer, "wanted").is_empty() and not law._responders.has(officer.actor_id),
		"law cannot enlist an officer answering a neighbor's call")
	var start := officer.global_position
	var arrived: bool = await advance_until(func(): return Vector2(officer.global_position.x, officer.global_position.z).length() <= 4.0, 12.0)
	check(arrived and start.distance_to(officer.global_position) > 10.0, "the officer physically walked to the call")
	check(max_step <= Assistance.JOG_SPEED / 60.0 + 0.01, "no frame moved the officer more than one jogging step (%.3f m)" % max_step)
	var closed: bool = await advance_until(func(): return not officer.has_meta("police_assist"), 30.0)
	var history: Array = status().history
	check(closed and not history.is_empty() and str(history[-1].outcome) == "no_threat", "the call closes as checked with nobody in danger")
	check(phone.statuses.any(func(text): return text.contains("Nobody there needed help")), "the phone receives the completion status")
	check(not officer.combat_override and not officer.has_meta("law_responder") and int(status().counters.rounds) == 0,
		"the officer is back on their beat and nobody was shot at")
	check(Vector2(officer.global_position.x - start.x, officer.global_position.z - start.z).length() < 3.0,
		"the officer walked back the way they came")

	# ---- 2. An unarmed attacker: approach, warn, detain, arrest. Never fire.
	await calm()
	place_officer(Vector3(16, 0.012, 2), -PI * 0.5)
	var brawler_id := id_with(false, "brawler")
	var brawler := person(brawler_id, "ricky", "Neighbor", Vector3(3, 0.012, 3), PI)
	check(combat.engage_actor(brawler, false) and combat.actor_mode(brawler) == "aggro", "fixture: an unarmed neighbor attacks")
	reply = assistance.request_help(player.global_position)
	check(str(reply.threat) == "violent" and int(reply.suspects) == 1, "the call identifies the one person actually fighting")
	var detained: bool = await advance_until(func(): return assistance.custody.has(brawler_id), 15.0)
	check(detained and combat.actor_mode(brawler) == "unknown" and int(status().counters.warnings) >= 1,
		"after a spoken warning combat lets go and police hold the attacker")
	var arrested: bool = await advance_until(func(): return int(status().counters.arrests) == 1, 15.0)
	check(arrested and int(status().counters.rounds) == 0 and not brawler.dead, "the unarmed attacker is arrested without a shot")
	check(phone.statuses.any(func(text): return text.contains("arrested")), "the phone hears about the arrest")
	await calm()
	check(not brawler.combat_override and not brawler.has_meta("police_custody") and not officer.has_meta("police_assist"),
		"reset hands both people back to normal life")
	brawler.set_enabled(false) # Out of the next scenario's way.

	# ---- 3. An armed shooter: lethal force only with a clear line.
	await calm()
	place_officer(Vector3(8, 0.012, -12), 0.0)
	var shooter_id := id_with(true, "shooter")
	var shooter := person(shooter_id, "liner_2", "Neighbor", Vector3(8, 0.012, 8), PI + 0.79)
	var blocker := bystander(Vector3(8, 0.0, -2))
	check(combat.engage_actor(shooter, true) and combat.actor_mode(shooter) == "gun", "fixture: an armed neighbor draws")
	var fired: bool = await advance_until(func(): return int(combat.get_status().actors.get(shooter_id, {}).get("shots", 0)) > 0, 6.0)
	check(fired, "fixture: the armed neighbor actually opens fire")
	reply = assistance.request_help(player.global_position)
	check(str(reply.threat) == "armed", "the call reports an armed suspect")
	var held: bool = await advance_until(func(): return int(status().hold_reasons.get("person_in_line", 0)) > 0, 12.0)
	check(held and int(status().counters.rounds) == 0 and not shooter.dead, "a bystander in the line of fire holds every round")
	blocker.global_position = Vector3(30, 0.0, -2)
	var stopped: bool = await advance_until(func(): return shooter.dead or assistance.custody.has(shooter_id), 30.0)
	var counts: Dictionary = status().counters
	check(stopped and int(counts.rounds) >= 1 and int(counts.hits) == int(counts.damage_applied),
		"with the line clear police fire at the imminent threat; only the suspect takes damage")
	check(str(status().hooks.damage) in ["public", "internal_fallback"], "damage goes through combat (%s)" % status().hooks.damage)
	check(not shooter.dead or combat.is_actor_dead(shooter_id), "a killed suspect is recorded in combat's death registry")
	var rounds_then := int(counts.rounds)
	await step(4.0)
	check(int(status().counters.rounds) == rounds_then, "firing stops once the suspect is neutralized")
	check(not officer.dead and combat.actor_mode(officer) in ["unknown", ""], "the officer was never taken over by combat")

	# ---- 4. Bounds, honesty and no random targets.
	await calm()
	place_officer(Vector3(16, 0.012, 2), -PI * 0.5)
	var spots := [Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0)]
	var accepted := 0
	for at in spots:
		accepted += int(bool(assistance.request_help(at).ok))
	var overflow: Dictionary = assistance.request_help(Vector3(0, 0, 90))
	check(accepted == 3 and not bool(overflow.ok) and str(overflow.message).contains("already on calls"),
		"at most three open incidents; the fourth call is refused honestly")
	var named := 0
	for incident in status().incidents:
		named += (incident.suspects as Array).size()
	check(named == 0, "no call names a suspect when nobody is violent (the caller included)")
	var as_police: Dictionary = assistance.report_violence({"suspect_id": "patrol_officer_1", "kind": "shooting"})
	var unknown: Dictionary = assistance.report_violence({"suspect_id": "nobody_here", "kind": "assault"})
	check(not bool(as_police.ok) and not bool(unknown.ok), "reports naming an officer or no real person are rejected")
	check(int(status().officer_count) <= Assistance.MAX_OFFICERS, "officer budget holds")
	await calm()

	# ---- 5. Cruiser assist contract (no traffic in this arena).
	var cruisers := Cruisers.new()
	var refused: Dictionary = cruisers.request_assist(Vector3.ZERO, "incident_x:1")
	check(not bool(refused.ok) and not str(refused.reason).is_empty(), "unavailable cruisers refuse an assist with a reason")
	var unit := {"assist": "incident_x:1", "mode": "respond", "slot": 1, "seen": false, "had_sight": false,
		"goal": Vector3(1, 0, 1), "frozen": false}
	cruisers.units[1] = unit
	cruisers.request(Vector3(50, 0, 50), 1)
	cruisers.radio(Vector3(60, 0, 60))
	check(Vector3(unit.goal) == Vector3(1, 0, 1), "law reports and radio never redirect an assist car")
	unit.seen = true
	cruisers._unit_perceive(unit)
	check(not bool(unit.seen), "an assist car never looks for the player")
	check(int(cruisers.summary().active) == 0, "assist cars do not hold the player's response phase open")
	cruisers._begin_hold(unit, "search")
	check(str(unit.mode) == "hold" and str(unit.hold_reason) == "assist", "every on-foot exit hands the crew to the incident")
	cruisers.stand_down(false)
	check(str(unit.mode) == "hold", "the player's incident ending does not recall a neighbor's call")
	cruisers.units.clear()

	print("[police_assistance] rays=%d shape_queries=%d" % [int(status().rays), int(status().shape_queries)])
	law.free()
	arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
