extends "res://tests/city_combat_reactions_smoke_runner.gd"
## Real actor/collision and input-path regressions for the sandbox combat contract.
class LawArena extends Arena:
	var law: Node
	var driving: Node
class DrivingStub extends Node:
	var active := false
var offenses: Array[Dictionary] = []
var defeated_events := 0

func _run() -> void:
	arena = LawArena.new()
	add_child(arena)
	box(Vector3(0, -.5, 0), Vector3(240, 1, 240), 1)
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	npcs = PeopleFixture.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	residents = Residents.new()
	arena.add_child(residents)
	residents.level = arena
	arena.residents = residents
	traffic = FakeTraffic.new()
	arena.add_child(traffic)
	arena.traffic = traffic
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	combat.player_offense.connect(func(kind: String, at: Vector3, id: String): offenses.append({"kind": kind, "at": at, "id": id}))
	combat.player_defeated.connect(func(): defeated_events += 1)
	reset_player()
	await frames(3)
	await _knockdown_contract()
	await _knockdown_budget_contract()
	await _group_contract()
	await _equipment_contract()
	await _recovery_contract()
	arena.queue_free()
	await frames(3)
	print("[combat_sandbox] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _knockdown_contract() -> void:
	var victim := spawn("sandbox_victim", Vector3(0, .012, 1.25), PI)
	await frames(2)
	combat.equip("fists")
	check(combat.request_attack(), "first deliberate punch starts")
	await advance(.20)
	combat.request_attack() # Explicitly queue the cross.
	await advance(.38)
	combat.request_attack() # Explicitly queue the knockdown strike.
	await advance(.48)
	check(combat._knocked.has(victim.actor_id) and not victim.dead and not combat.is_actor_dead(victim.actor_id), "three real punch inputs knock down without registering a death")
	check(not combat._queued_punch and combat._stomp_elapsed < 0.0, "knockdown clears buffered combo and never queues a stomp")
	var landed: int = combat.hits_landed
	check(not combat._damage_target(victim, 999.0, "punch") and combat.hits_landed == landed and not victim.dead, "even excessive repeated punch damage cannot execute a downed target")
	await advance(1.0)
	check(not victim.dead and combat.get_status().stomp_available, "waiting after combo preserves victim and exposes explicit lethal stomp cue")
	var assaults := 0
	for event in offenses:
		assaults += int(event.kind == "assault")
	check(assaults == 3, "exactly one offense per landed punch, none for buffered input")
	check(combat.request_attack() and combat._stomp_elapsed == 0.0 and not victim.dead, "later explicit LMB starts a separate stomp animation")
	await advance(.30)
	check(victim.dead and combat.is_actor_dead(victim.actor_id) and not combat._knocked.has(victim.actor_id), "stomp contact kills once and removes knockdown state")
	check(absf(victim.puppet.g.rotation.x) > 1.3, "stomp corpse remains fallen instead of replaying an upright collapse")
	var stomps := 0
	for event in offenses:
		stomps += int(event.kind == "stomp")
	check(stomps == 1, "stomp emits one distinct offense")
	await advance(.5)
	await dismiss([victim])
	var spared := spawn("sandbox_spared", Vector3(0, .012, 1.25), PI)
	await frames(2)
	combat.combo = 1
	combat._damage_target(spared, 999.0, "punch")
	check(combat._knocked.has(spared.actor_id) and not spared.dead, "single excessive punch also follows nonlethal knockdown path")
	await advance(.8)
	combat.request_attack()
	player.position.x = 5.0 # Step away before contact; the cached cue is not authority.
	await advance(.7)
	check(not spared.dead and combat._knocked.has(spared.actor_id), "stomp rechecks actual range at contact")
	combat._knocked[spared.actor_id].time = Combat.KNOCKDOWN_TIME - .05
	await advance(.1)
	check(not spared.dead and not spared.combat_override and not combat._knocked.has(spared.actor_id) and is_zero_approx(spared.capsule.rotation.x), "spared victim recovers with original collider and routine ownership")
	combat._damage_target(spared, 200.0, "shot", ORIGIN)
	check(spared.dead, "gunshot damage remains lethal")
	await dismiss([spared])
	reset_player()

func _knockdown_budget_contract() -> void:
	var victims: Array = []
	for index in Combat.MAX_DOWNED + 1:
		var actor := spawn("sandbox_budget_%d" % index, Vector3(12 + index * 3, .012, 8), PI)
		victims.append(actor)
	await frames(2)
	combat.combo = 1
	for actor in victims:
		combat._damage_target(actor, 999.0, "punch")
	var all_alive := true
	for actor in victims:
		all_alive = all_alive and not actor.dead and not combat.is_actor_dead(actor.actor_id)
	check(combat._knocked.size() == Combat.MAX_DOWNED and all_alive and not victims[0].combat_override,
		"overflow knockdown recovers oldest living victim and never exceeds eight downed actors")
	for id in combat._knocked.keys():
		combat._recover_knocked(str(id))
	await dismiss(victims)

func _group_contract() -> void:
	var members: Array = []
	var melee_id := ""
	var flee_id := ""
	var gun_id := ""
	for i in 200:
		var id := "sandbox_group_%d" % i
		match Combat.default_reaction(id):
			"aggro": melee_id = id if melee_id.is_empty() else melee_id
			"flee": flee_id = id if flee_id.is_empty() else flee_id
			"gun": gun_id = id if gun_id.is_empty() else gun_id
		if not melee_id.is_empty() and not flee_id.is_empty() and not gun_id.is_empty():
			break
	var victim := spawn("sandbox_group_victim", Vector3(0, .012, 2.0), PI)
	victim.set_meta("social_group_id", "fixture_friends")
	for i in 3:
		var actor := spawn([melee_id, flee_id, gun_id][i], Vector3([-5.0, -2.5, 5.0][i], .012, 5), PI)
		actor.set_meta("social_group_id", "fixture_friends")
		members.append(actor)
	var distant := spawn("sandbox_distant_friend", Vector3(75, .012, 20), PI)
	distant.set_meta("social_group_id", "fixture_friends")
	var stranger := spawn("sandbox_stranger", Vector3(7, .012, 6), PI)
	await frames(2)
	combat._group_assault(victim.actor_id, victim, victim.position, ORIGIN)
	check(combat._active.has(members[0].get_instance_id()) and combat._active[members[0].get_instance_id()].mode == "aggro", "melee group member chooses their own melee response")
	check(combat._panic.has(members[1].get_instance_id()), "flee group member keeps their own default response")
	check(combat._active.has(members[2].get_instance_id()) and combat._active[members[2].get_instance_id()].mode == "gun", "armed group member chooses their own gun response")
	check(not combat._active.has(distant.get_instance_id()) and not combat._panic.has(distant.get_instance_id()) and not stranger.combat_override, "group event leaves distant friends and unrelated neighbors untouched")
	check(int(combat.last_group_reaction.checked) <= Combat.MAX_GROUP_REACTIONS and combat._active.size() <= Combat.MAX_ACTIVE and combat._panic.size() <= Combat.MAX_PANIC, "group scans and existing actor budgets stay bounded")
	members.append_array([victim, distant, stranger])
	await dismiss(members)
	# Same grouping index used after canonical recipe loading, independent of group center/order.
	crowd = Crowd.new()
	npcs.add_child(crowd)
	npcs.crowd = crowd
	crowd.level = arena
	crowd.npcs = npcs
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = .24
	crowd._shape.height = 1.65
	crowd._meshes.assign([crowd._person_mesh(false), crowd._person_mesh(true)])
	for i in 5:
		crowd._add_resident(Vector3(-4 + i * 2, .012, 7), PI, "circle", false)
	crowd._circle_groups.assign([{"indices": [3, 1, 2], "center": Vector3.ZERO, "street": "Fixture"}])
	crowd._index_social_groups()
	var stable: String = crowd.social_group_id(2)
	crowd._circle_groups[0].indices = [2, 3, 1]
	crowd._circle_groups[0].center = Vector3(100, 0, 100)
	crowd._index_social_groups()
	check(stable == "social_crowd_1" and crowd.social_group_id(2) == stable and crowd.social_group_members(2).size() == 3 and crowd.social_group_id(0).is_empty(), "baked crowd group identity uses stable ordinals, not current position or ordering")
	crowd._build_batches()
	await frames(2)
	combat._group_assault("crowd_2", null, crowd.residents[2].position, ORIGIN)
	check(combat.last_group_reaction.group == stable and combat.last_group_reaction.reacted.size() > 0 and combat.last_group_reaction.reacted.size() <= 2, "primitive crowd group lookup drives real bounded member reactions")
	release_all()
	await frames(2)
	combat.combo = 1
	combat._damage_target(crowd.residents[2].body, 999.0, "punch")
	check(combat._knocked.has("crowd_2") and crowd.residents[2].combat_controlled and not crowd.is_dead(2), "primitive crowd victim promotes into a living downed actor without a duplicate body")
	combat._recover_knocked("crowd_2")
	check(not crowd.is_dead(2) and not crowd.residents[2].combat_controlled and crowd.residents[2].body.collision_layer == 8 and crowd.social_group_id(2) == stable, "crowd recovery restores its physical slot and stable social identity")
	release_all()
	crowd.queue_free()
	npcs.crowd = null
	crowd = null
	await frames(2)

func _equipment_contract() -> void:
	combat.equip("fists")
	check(combat.ammo == 0 and combat.reserve == 0 and combat.get_status().ammo == combat.equipment_snapshot().weapons.fists.ammo, "fists legacy summary matches zero-ammo inventory for save consistency")
	combat.equip("uzi")
	check(combat.weapon == "fists", "unowned weapon cannot be equipped")
	check(combat.grant_weapon("uzi") and not combat.grant_weapon("uzi") and combat.grant_weapon("ak47"), "weapon grants are idempotent")
	check(combat.add_ammo("uzi", 41) == 41 and combat.add_ammo("ak47", 20) == 20 and combat.add_ammo("bad", 5) == 0, "ammo grants target a canonical weapon inventory")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_3
	combat.handle_input(key)
	check(combat.weapon == "uzi" and combat.ammo == 30 and combat.reserve == 41 and combat._weapon_models.uzi.visible and not combat._weapon_models.pistol.visible, "number key 3 selects owned Uzi and its distinct model")
	combat.ammo = 7
	combat.equip("ak47")
	combat.ammo = 3
	combat.equip("uzi")
	check(combat.ammo == 7 and combat.reserve == 41, "switching guns preserves separate magazine and reserve counts")
	check(combat.request_reload(), "Uzi reload starts")
	await advance(2.0)
	check(combat.ammo == 30 and combat.reserve == 18, "reload transfers only missing rounds for selected weapon")
	combat.equip("ak47")
	check(combat.ammo == 3 and combat.reserve == 20, "other firearm ammo is unaffected by reload")
	combat.request_reload()
	combat.equip("uzi")
	await advance(2.5)
	combat.equip("ak47")
	check(combat.ammo == 3 and combat.reserve == 20 and combat.reloading == 0, "switch cancels reload without duplicating ammo")
	var before := offenses.size()
	combat.ammo = 0
	combat._shot_cooldown = 0.0
	check(not combat.request_attack() and offenses.size() == before, "empty magazine causes no shot or offense")
	combat.equip("uzi")
	combat._shot_cooldown = 0.0
	check(combat.request_attack() and is_equal_approx(combat._shot_cooldown, .09), "Uzi fires through production collision path with distinct cadence")
	combat.equip("ak47")
	combat.ammo = 3
	combat._shot_cooldown = 0.0
	check(combat.request_attack() and is_equal_approx(combat._shot_cooldown, .14), "AK47 fires through production collision path with distinct cadence")
	check(offenses.size() == before + 2 and offenses[-1].kind == "shooting", "each discharged round emits exactly one shooting offense")
	combat.equip("uzi")
	combat._shot_cooldown = 0.0
	var auto_start: int = combat.shots_fired
	var auto_offenses := offenses.size()
	combat._trigger_held = true
	await advance(.35)
	var automatic_rounds: int = combat.shots_fired - auto_start
	check(automatic_rounds >= 3 and automatic_rounds <= 5 and offenses.size() - auto_offenses == automatic_rounds, "held automatic trigger follows bounded cadence and emits one offense per real round")
	combat.cancel_player_actions()
	var stopped: int = combat.shots_fired
	await advance(.35)
	check(combat.shots_fired == stopped and not combat._trigger_held, "modal cancellation stops held fire without an extra round")
	combat.equip("pistol")
	combat._shot_cooldown = 0.0
	var semi_start: int = combat.shots_fired
	combat.request_attack()
	combat._trigger_held = true
	await advance(.4)
	check(combat.shots_fired == semi_start + 1, "holding the pistol trigger never converts it to automatic fire")
	combat.cancel_player_actions()
	var snapshot: Dictionary = combat.equipment_snapshot()
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	check(combat.validate_equipment(encoded) and combat.restore_equipment(encoded) and combat.equipment_snapshot() == snapshot, "equipment survives JSON save/restore with separate ammo stores")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.weapons.uzi.ammo = 30000
	check(not combat.validate_equipment(invalid) and not combat.restore_equipment(invalid) and combat.equipment_snapshot() == snapshot, "invalid ammo snapshot is rejected without partial mutation")
	var malformed_version := snapshot.duplicate(true)
	malformed_version.version = {"unexpected": 1}
	check(not combat.validate_equipment(malformed_version) and not combat.restore_equipment(malformed_version) and combat.equipment_snapshot() == snapshot,
		"malformed version type is rejected without constructor errors or mutation")
	check(combat._weapon_models.pistol.get_child_count() != combat._weapon_models.uzi.get_child_count() and combat._weapon_models.ak47.get_child_count() > combat._weapon_models.uzi.get_child_count(), "three weapon silhouettes use distinct authored geometry")
	combat.equip("fists")

func _recovery_contract() -> void:
	var actual: LawArena = arena as LawArena
	actual.law = Node.new()
	actual.add_child(actual.law)
	actual.driving = DrivingStub.new()
	actual.add_child(actual.driving)
	actual.driving.active = true
	check(not combat.accepts_player_input(), "driving blocks direct combat input")
	actual.driving.active = false
	combat._invulnerable = 0.0
	check(combat._hurt_player(1000.0) and defeated_events == 1, "defeat emits exactly one recovery event")
	await advance(4.0)
	check(combat.health == 0 and combat.downed > 0 and defeated_events == 1, "law-owned defeat never auto-heals on the legacy timer")
	combat.recover_player()
	check(combat.health == 100 and combat.downed == 0 and combat._active.is_empty() and combat._panic.is_empty(), "explicit recovery restores health and clears combat pursuit")
