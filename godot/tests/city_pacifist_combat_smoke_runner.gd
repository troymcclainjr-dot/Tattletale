extends Node
## Bicycle knockdown and neighbor fights in a small physics arena with real
## combat: a hard bike contact lays a pedestrian down with the model-controlled
## knockdown rig (no ragdoll, no damage, no death, no offense), they get up and
## go after the rider with fists even when their identity is armed, mild bumps
## only stumble (a repeat starts the grudge), duplicates are ignored, police are
## exempt, a wall changes the fall direction, the downed set stays bounded, and
## an incident fistfight knocks the loser down without ever killing anyone.
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	var combat: Node3D
	var paused := false

var arena: Arena
var player: CharacterBody3D
var combat: Node3D
var failures := 0
var offenses := 0
var knockdown_signals := 0
var recovered_signals: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[pacifist_combat] %s %s" % ["PASS" if ok else "FAIL", label])

func tick_once() -> void:
	combat.tick(1.0 / 60.0)
	await get_tree().physics_frame

func step(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await tick_once()

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

func person(id: String, cast: String, at: Vector3, yaw: float) -> CharacterBody3D:
	var actor := Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, cast, "Neighbor")
	arena.npcs.actors[id] = actor
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	return actor

## An identity whose stable disposition matches (armed / flee / aggro).
func id_where(prefix: String, test: Callable) -> String:
	for i in 4000:
		var id := "%s_%d" % [prefix, i]
		if test.call(id):
			return id
	return prefix

func has_physics_rig(node: Node) -> bool:
	if node is RigidBody3D or node is PhysicalBone3D or node is PhysicalBoneSimulator3D:
		return true
	for child in node.get_children():
		if has_physics_rig(child):
			return true
	return false

func snapshot_entry(id: String) -> Dictionary:
	for entry in combat.fighter_snapshot():
		if str(entry.id) == id:
			return entry
	return {}

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
	arena.player = player
	arena.npcs = PeopleFixture.new()
	arena.add_child(arena.npcs)
	arena.residents = PeopleFixture.new()
	arena.add_child(arena.residents)
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	arena.combat = combat
	combat.player_offense.connect(func(_kind: String, _at: Vector3, _id: String): offenses += 1)
	combat.bicycle_knockdown.connect(func(_result: Dictionary): knockdown_signals += 1)
	combat.bicycle_recovered.connect(func(id: String): recovered_signals.append(id))
	await step(0.1)

	# ---- 1. A hard contact knocks an armed neighbor down: no harm, no offense.
	var armed_id := id_where("rider_hit", func(id: String) -> bool: return Combat.is_armed_id(id))
	var walker := person(armed_id, "ricky", Vector3(0, 0.012, 3), PI)
	var result: Dictionary = combat.knockdown_from_bicycle(walker, 4.5, Vector3(0, 0, 9.0), {"source": "bicycle"})
	check(bool(result.ok) and str(result.outcome) == "knocked_down" and str(result.id) == armed_id and float(result.down_seconds) >= 2.0,
		"a 4.5 m/s bicycle contact knocks the pedestrian down (%s)" % str(result))
	check(combat.actor_mode(walker) == "downed" and int(combat.get_status().knocked_count) == 1 and combat.is_bicycle_knockdown(armed_id),
		"the person is in the bounded downed set")
	var entry: Dictionary = combat._knocked[armed_id]
	check(bool(entry.nonlethal) and float(entry.state.health) == Combat.ACTOR_HEALTH and not walker.dead and combat.deaths == 0,
		"no damage, health unchanged, nobody dead")
	check(absf(angle_difference(float(entry.fall_yaw), Combat._fall_yaw_along(Vector3(0, 0, 1)))) < 0.01 and bool(entry.flat),
		"with open ground the body falls along the push")
	await step(0.6)
	check(walker.puppet.g.rotation.x < -1.2 and absf(walker.capsule.rotation.x + PI * 0.5) < 0.01,
		"model-controlled downed pose: rig on the ground, capsule lying flat")
	check(not has_physics_rig(walker), "no ragdoll or physical bones are created")
	check(offenses == 0 and knockdown_signals == 1, "no player offense; one knockdown signal")
	var stomp_target: String = combat._nearest_knocked()
	check(stomp_target.is_empty(), "a bicycle knockdown can never become a stomp target")

	# ---- 2. Up again: fists at the rider even though this identity is armed.
	var got_up: bool = await advance_until(func(): return combat.actor_mode(walker) != "downed", float(result.down_seconds) + 1.0)
	var fighter := snapshot_entry(armed_id)
	check(got_up and str(fighter.get("mode", "")) == "aggro" and str(fighter.get("provoked", "")) == "bicycle",
		"after recovery the person is a melee (aggro) fighter marked provoked by the bicycle")
	check(combat.is_actor_armed(walker) and combat._active[walker.get_instance_id()].get("gun") == null,
		"an armed identity uses fists after a bike crash (no drawn pistol)")
	check(absf(walker.capsule.rotation.x) < 0.01 and recovered_signals.has(armed_id), "capsule upright again; recovery signalled")
	var before_health: float = combat.health
	var punched: bool = await advance_until(func(): return combat.health < before_health, 6.0)
	check(punched and combat.get_status().aggro_count == 1, "the person walks up and punches the rider (melee aggression)")
	player.global_position = Vector3(0, 0.012, -40) # Fixture: the rider leaves.
	var cooled: bool = await advance_until(func(): return combat.actor_mode(walker) == "", 20.0)
	check(cooled and not walker.combat_override and not walker.dead, "riding away cools the grudge; they resume normal life")
	player.global_position = Vector3(0, 0.012, 0)
	combat.health = 100.0
	check(offenses == 0 and combat.deaths == 0, "still no offense and no death after the whole grudge")

	# ---- 3. Mild bumps stumble; a repeat within the window starts the grudge.
	var mild_id := id_where("mild_bump", func(id: String) -> bool: return Combat.default_reaction(id) == "flee")
	var mild := person(mild_id, "granny", Vector3(4, 0.012, 2), 0.0)
	result = combat.knockdown_from_bicycle(mild, 1.2)
	check(str(result.outcome) == "stumbled" and not bool(result.aggro) and combat.actor_mode(mild) == "" and float(mild._speech_remaining) > 0.0,
		"a slow bump only stumbles (one short line, no state change)")
	result = combat.knockdown_from_bicycle(mild, 1.2)
	check(str(result.outcome) == "ignored" and bool(result.deduped), "a duplicate contact within a second is ignored")
	await step(1.2)
	result = combat.knockdown_from_bicycle(mild, 1.2)
	check(str(result.outcome) == "stumbled" and str(result.reason) == "repeated" and bool(result.aggro) and combat.actor_mode(mild) == "aggro",
		"a second bump inside the window escalates to fists, even for a peaceful disposition")
	combat.disengage_actor(mild)
	mild.set_enabled(false)

	# ---- 4. Exemptions and invalid contacts.
	var officer := person("patrol_officer_9", "cop_dan", Vector3(-4, 0.012, 2), 0.0)
	result = combat.knockdown_from_bicycle(officer, 6.0, Vector3(1, 0, 0))
	check(str(result.outcome) == "stumbled" and str(result.reason) == "police" and combat.actor_mode(officer) == "",
		"police officers are never knocked down or turned against the rider")
	var duty := person("duty_neighbor", "liner_2", Vector3(-6, 0.012, 2), 0.0)
	duty.set_meta("police_custody", true)
	result = combat.knockdown_from_bicycle(duty, 6.0)
	check(str(result.reason) == "in_custody" and combat.actor_mode(duty) == "", "people in custody only stumble")
	duty.remove_meta("police_custody")
	duty.set_enabled(false)
	check(str(combat.knockdown_from_bicycle(walker, 0.3).reason) == "too_slow", "below 0.6 m/s nothing happens")
	var post := box(Vector3(30, 0.5, 30), Vector3(0.3, 1, 0.3), 2)
	check(str(combat.knockdown_from_bicycle(post, 5.0).reason) == "unknown_target", "a non-person collider is rejected")
	var gone := person("gone_neighbor", "mailman", Vector3(-8, 0.012, 2), 0.0)
	gone.mark_dead()
	check(str(combat.knockdown_from_bicycle(gone, 5.0).reason) == "unavailable", "a dead person cannot be knocked down")
	check(str(combat.knockdown_from_bicycle("crowd_999999", 5.0).reason) == "unavailable", "an unknown crowd slot is unavailable")

	# ---- 5. A wall behind the pedestrian changes the fall direction.
	var walled_id := id_where("walled", func(id: String) -> bool: return Combat.default_reaction(id) != "gun")
	var walled := person(walled_id, "liner_2", Vector3(10, 0.012, 0), -PI * 0.5)
	box(Vector3(10.8, 1.0, 0), Vector3(0.3, 2.0, 8.0), 1)
	# The city's building trimeshes are layer 1. Let the new wall enter the
	# physics broadphase before asking the real fall-direction solver.
	await get_tree().physics_frame
	await get_tree().physics_frame
	result = combat.knockdown_from_bicycle(walled, 5.0, Vector3(6, 0, 0))
	entry = combat._knocked.get(walled_id, {})
	var fall_dir := Vector3(-sin(float(entry.get("fall_yaw", 0.0))), 0.0, -cos(float(entry.get("fall_yaw", 0.0))))
	check(str(result.outcome) == "knocked_down" and bool(entry.get("flat", false)) and fall_dir.x < 0.2,
		"pushed toward a wall, the body falls onto clear ground instead (fall x %.2f)" % fall_dir.x)
	check(combat.recover_from_bicycle(walled_id) and combat.actor_mode(walled) == "aggro", "recover_from_bicycle stands them up into the grudge")
	combat.disengage_actor(walled)
	walled.set_enabled(false)

	# ---- 6. The downed set stays bounded (oldest stands up first).
	var crowd_ids: Array[String] = []
	for i in Combat.MAX_DOWNED + 1:
		var id := "downed_%d" % i
		var body := person(id, "granny", Vector3(-20 + i * 2.5, 0.012, 20), 0.0)
		crowd_ids.append(id)
		combat.knockdown_from_bicycle(body, 5.0, Vector3(0, 0, 1))
	check(combat._knocked.size() <= Combat.MAX_DOWNED and not combat._knocked.has(crowd_ids[0]),
		"at most %d people are down at once; the first knocked stood up" % Combat.MAX_DOWNED)
	for id in crowd_ids:
		combat.recover_from_bicycle(id)
	for id in crowd_ids:
		var body = arena.npcs.actors[id]
		combat.disengage_actor(body)
		body.set_enabled(false)
	check(combat._knocked.is_empty() and combat.get_status().knocked_count == 0, "every downed person is up again")

	# ---- 7. Incident fistfight: nonlethal, budgeted, never an offense.
	combat.recover_player()
	var brawler_id := id_where("brawler", func(id: String) -> bool: return Combat.default_reaction(id) != "flee")
	var rival_id := id_where("rival", func(id: String) -> bool: return Combat.default_reaction(id) != "flee")
	var brawler := person(brawler_id, "ricky", Vector3(-30, 0.012, -20), PI * 0.5)
	var rival := person(rival_id, "liner_2", Vector3(-27.5, 0.012, -20), -PI * 0.5)
	var fight: Dictionary = combat.start_npc_fight(brawler, rival_id, {"seconds": 30.0, "incident_id": "inc_000042", "mutual": true})
	check(bool(fight.ok) and str(snapshot_entry(brawler_id).get("foe", "")) == rival_id and str(snapshot_entry(brawler_id).get("incident_id", "")) == "inc_000042",
		"a mutual neighbor fight starts and is visible to police discovery with its foe")
	check(combat.get_status().aggro_count == 0 and int(combat.get_status().npc_fighting) == 2,
		"neighbor fighters are not counted as hostile to the explorer")
	var third := person("third_party", "mailman", Vector3(-40, 0.012, -20), 0.0)
	var fourth := person("fourth_party", "granny", Vector3(-42, 0.012, -20), 0.0)
	var fifth := person("fifth_party", "granny", Vector3(-44, 0.012, -24), 0.0)
	var sixth := person("sixth_party", "granny", Vector3(-46, 0.012, -24), 0.0)
	check(bool(combat.start_npc_fight(third, fourth, {}).ok) and str(combat.start_npc_fight(fifth, sixth, {}).reason) == "fight_budget",
		"at most %d neighbor fights at once" % Combat.MAX_NPC_FIGHTS)
	check(combat.stop_npc_fight(third), "stop_npc_fight ends the second fight")
	check(str(combat.start_npc_fight(officer, fifth, {}).reason) == "unavailable" and str(combat.start_npc_fight(fifth, fifth, {}).reason) == "invalid_people",
		"police cannot be made to brawl; nobody fights themselves")
	var someone_down: bool = await advance_until(func(): return combat._knocked.has(brawler_id) or combat._knocked.has(rival_id), 30.0)
	check(someone_down and int(combat.get_status().npc_strikes) > 0 and int(combat.get_status().npc_knockdowns) == 1,
		"strikes land until one neighbor is knocked down")
	var loser_id := brawler_id if combat._knocked.has(brawler_id) else rival_id
	var loser = arena.npcs.actors[loser_id]
	check(not loser.dead and not combat.is_actor_dead(loser_id) and float(combat._knocked[loser_id].state.health) >= 1.0 and bool(combat._knocked[loser_id].nonlethal),
		"the loser is down, alive and not stompable")
	var settled: bool = await advance_until(func(): return combat.actor_mode(loser) != "downed" and combat.get_status().npc_fighting == 0, Combat.NPC_KNOCKDOWN_TIME + 4.0)
	check(settled and combat.deaths == 0 and offenses == 0, "the fight ends, the loser gets up; no deaths, no player offense")

	# ---- 8. A one-sided fight: the victim flees through the bounded panic path.
	await step(8.0)
	var bully_id := id_where("bully", func(id: String) -> bool: return Combat.default_reaction(id) != "flee")
	var bully := person(bully_id, "ricky", Vector3(30, 0.012, -30), 0.0)
	var target := person("target_neighbor", "granny", Vector3(30, 0.012, -28.6), PI)
	check(bool(combat.start_npc_fight(bully, target, {"seconds": 12.0}).ok), "a one-sided fight starts")
	var fled: bool = await advance_until(func(): return str(combat.actor_mode(target)).begins_with("panic:") or combat._knocked.has("target_neighbor"), 8.0)
	check(fled and not target.dead, "the person hit runs (combat panic) instead of joining a brawl")
	combat.stop_npc_fight(bully)
	check(combat.get_status().npc_fighting == 0, "stop_npc_fight ends it")

	print("[pacifist_combat] knockdowns=%d stumbles=%d grudges=%d strikes=%d" % [combat.bike_knockdowns, combat.bike_stumbles, combat.bike_grudges, combat.npc_strikes])
	arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
