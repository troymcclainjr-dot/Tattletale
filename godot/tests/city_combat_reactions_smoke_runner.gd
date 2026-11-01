extends Node
## Gunfire reactions in a real physics arena: armed identities, flee vs return
## fire, NPC telegraph/LOS/cooldown, tire occlusion, permanent death across
## culling and reload, cheap overflow, and bounded per-shot/per-frame work.
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Crowd := preload("res://scripts/city/city_crowd.gd")
const Residents := preload("res://scripts/city/city_residents.gd")
const Resident := preload("res://scripts/city/city_resident_actor.gd")

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

## Implements the agreed traffic contract with one analytic tire.
class FakeTraffic:
	extends Node3D
	var tire_at := Vector3.INF
	var received: Array[Dictionary] = []
	var notified: Array = []
	func raycast_tires(from: Vector3, to: Vector3) -> Dictionary:
		if not tire_at.is_finite():
			return {}
		var closest := Geometry3D.get_closest_point_to_segment(tire_at, from, to)
		if closest.distance_to(tire_at) > 0.4:
			return {}
		return {"position": closest, "normal": Vector3.UP, "distance": from.distance_to(closest), "collider": self, "tire_index": 2, "vehicle_hit": true}
	func receive_gunshot(hit: Dictionary, _origin: Vector3) -> Dictionary:
		received.append(hit)
		return {"vehicle_hit": true, "tire_index": int(hit.get("tire_index", -1))}
	func notify_gunshot(from: Vector3, to: Vector3) -> int:
		notified.append([from, to])
		return 0

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	var traffic: Node3D
	func ground_at(at: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP * 2.0, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)

var arena: Arena
var player: CharacterBody3D
var npcs: PeopleFixture
var residents: Node3D
var traffic: FakeTraffic
var combat: Node3D
var crowd: Node3D
var failures := 0
var passes := 0
const ORIGIN := Vector3(0, 1.3, 0)

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	passes += int(ok)
	print("[combat_reactions] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func advance(seconds: float, with_crowd := false) -> void:
	for i in ceili(seconds * 60.0):
		combat.tick(1.0 / 60.0)
		if with_crowd and crowd != null:
			crowd.tick(1.0 / 60.0)
		await frames(1)

func box(at: Vector3, size_: Vector3, layer := 2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size_
	shape.shape = mesh
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func ids_with(armed: bool, prefix: String, count := 1) -> Array[String]:
	var result: Array[String] = []
	for i in 2000:
		var id := "%s_%d" % [prefix, i]
		if Combat.is_armed_id(id) == armed:
			result.append(id)
			if result.size() >= count:
				break
	return result

func spawn(id: String, at: Vector3, yaw := 0.0) -> CharacterBody3D:
	var actor := Actor.new()
	npcs.add_child(actor)
	actor.build(arena, id, "mama", "Neighbor")
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	npcs.actors[id] = actor
	return actor

func make_resident(id: String, at: Vector3) -> CharacterBody3D:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Residents.DATA_PATH))
	var definition: Dictionary = data.residents[0].duplicate(true)
	definition.id = id
	var actor := Resident.new()
	residents.add_child(actor)
	actor.build_resident(arena, definition)
	actor.global_position = at
	residents.actors[id] = actor
	return actor

func release_all() -> void:
	for state in combat._active.values().duplicate():
		combat._release(state)
	for state in combat._panic.values().duplicate():
		combat._release(state)

func dismiss(actors: Array) -> void:
	release_all()
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		if npcs.actors.get(actor.actor_id) == actor:
			npcs.actors.erase(actor.actor_id)
		if residents.actors.get(actor.actor_id) == actor:
			residents.actors.erase(actor.actor_id)
		actor.queue_free()
	await frames(2)

func reset_player() -> void:
	player.position = Vector3(0, 0.012, 0)
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.enabled = true
	combat.downed = 0.0
	combat.health = 100.0
	combat._invulnerable = 0.0
	combat._shot_cooldown = 0.0

func _run() -> void:
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(240, 1, 240), 1)
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
	residents._shape = CapsuleShape3D.new()
	residents._shape.radius = 0.30
	residents._shape.height = 1.90
	arena.residents = residents
	traffic = FakeTraffic.new()
	arena.add_child(traffic)
	arena.traffic = traffic
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	reset_player()
	await frames(3)
	_armed_identities()
	await _vehicle_occlusion()
	await _flee_versus_return_fire()
	await _return_fire_rules()
	await _death_registry()
	await _panic_budget()
	await _crowd_reactions()
	await frames(2)
	arena.queue_free()
	await frames(2)
	var audio_deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < audio_deadline:
		await get_tree().process_frame
	print("[combat_reactions] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _armed_identities() -> void:
	check(Combat.stable_hash("") == 2166136261 and Combat.stable_hash("a") == 0xE40C292C and Combat.stable_hash("foobar") == 0xBF9CF968, "identity hash is standard FNV-1a (launch and platform stable)")
	var armed := 0
	for i in 1200:
		armed += int(Combat.is_armed_id("crowd_%d" % i))
	var fraction := float(armed) / 1200.0
	check(fraction > 0.28 and fraction < 0.39, "roughly one third of crowd identities are armed (%.3f)" % fraction)
	var again := 0
	for i in 1200:
		again += int(Combat.is_armed_id("crowd_%d" % i))
	check(again == armed, "armed identities are deterministic across queries")
	check(Combat.is_armed_id(ids_with(false, "civ")[0], true), "police are always armed")

func _vehicle_occlusion() -> void:
	reset_player()
	traffic.tire_at = Vector3(0, 0.4, 6)
	var chest := Vector3(0, 1.2, 0)
	var muzzle := Vector3(0, 1.3, 0.5)
	var rid: Array[RID] = [player.get_rid()]
	var open: Dictionary = combat._trace_bullet(chest, muzzle, Vector3(0, 0.0, 12), rid)
	check(open.tire and open.endpoint.distance_to(traffic.tire_at) < 0.45, "unobstructed tire nearer than the world hit is chosen")
	var wall := box(Vector3(0, 1.0, 3), Vector3(3, 2, 0.2), 2)
	await frames(2)
	var covered: Dictionary = combat._trace_bullet(chest, muzzle, Vector3(0, 0.0, 12), rid)
	check(not covered.tire and covered.hit.get("collider") == wall, "a nearer wall wins: tires are never shot through cover")
	wall.free()
	await frames(2)
	var received := traffic.received.size()
	check(combat._vehicle_shot(open.hit, muzzle) and traffic.received.size() == received + 1 and int(traffic.received[-1].tire_index) == 2, "tire hit dispatches receive_gunshot with its wheel index")
	var hull := box(Vector3(6, 0.8, 6), Vector3(2, 1.6, 4), 16)
	await frames(2)
	var body_trace: Dictionary = combat._trace_bullet(Vector3(6, 1.2, 0), Vector3(6, 1.2, 0.5), Vector3(6, 1.0, 12), rid)
	check(body_trace.hit.get("collider") == hull and combat._vehicle_shot(body_trace.hit, Vector3(6, 1.2, 0.5)) and traffic.received[-1].collider == hull, "layer-16 vehicle body hit is dispatched to traffic")
	hull.free()
	await frames(2)
	# Integrated player shot aimed at the tire.
	var notified := traffic.notified.size()
	received = traffic.received.size()
	combat.equip("pistol")
	combat.ammo = 12
	combat.aiming = true
	combat.apply_player_pose(0.1)
	player.camera.global_position = Vector3(0, 1.3, -2)
	player.camera.look_at(traffic.tire_at, Vector3.UP)
	await frames(2)
	combat._shot_cooldown = 0.0
	combat.request_attack()
	check(traffic.notified.size() == notified + 1, "each player shot notifies traffic exactly once")
	check(traffic.notified[-1][1].distance_to(combat.last_shot.to) < 0.001, "traffic notification uses the occluded endpoint")
	check(combat.last_shot.get("tire", false) and traffic.received.size() == received + 1, "camera-aimed shot punctures the unobstructed tire")
	combat.equip("fists")
	traffic.tire_at = Vector3.INF
	await dismiss([])

func _flee_versus_return_fire() -> void:
	reset_player()
	var unarmed := spawn(ids_with(false, "bystander")[0], Vector3(0, 0.012, 10))
	var armed := spawn(ids_with(true, "neighbor")[0], Vector3(6, 0.012, 12))
	var start: Vector3 = unarmed.global_position
	await frames(2)
	var u_key: int = unarmed.get_instance_id()
	var a_key: int = armed.get_instance_id()
	# Shot into the ground well away from both: only the noise reaches them.
	combat._gunshot_event(ORIGIN, ORIGIN, Vector3(-9, 0.0, 14), true, null)
	check(combat._panic.has(u_key) and combat._panic[u_key].mode == "flee", "gunfire sound makes an unarmed bystander flee")
	check(combat._panic.has(a_key) and not combat._active.has(a_key), "an armed bystander who only hears gunfire flees instead of attacking")
	check(unarmed.combat_override and unarmed.has_meta("combat_controlled"), "fleeing actor pauses schedule/interaction ownership")
	await advance(2.0)
	var moved: Vector3 = unarmed.global_position - start
	check(moved.z > 2.0 and absf(moved.x) < moved.z, "bystander runs away from the actual shooter location (%.2f m)" % moved.z)
	var chest: Vector3 = armed.global_position + Vector3.UP * 1.2
	combat._gunshot_event(ORIGIN, ORIGIN, ORIGIN + (chest + Vector3(0.5, 0, 0) - ORIGIN) * 1.5, true, null)
	check(combat._active.has(a_key) and combat._active[a_key].mode == "gun", "armed neighbor near-missed by the player returns fire")
	check(combat._active.has(a_key) and is_instance_valid(combat._active[a_key].gun), "returning fire puts a pistol in the NPC's hand")
	check(combat._panic.has(u_key) and combat._panic[u_key].mode != "gun", "the unarmed bystander keeps fleeing on the near miss")
	await dismiss([unarmed, armed])
	# Boxed in: every flee direction is blocked, so the bystander takes cover.
	var trapped := spawn(ids_with(false, "trapped")[0], Vector3(12, 0.012, 10))
	var walls := [box(Vector3(12, 1.1, 11.0), Vector3(2.4, 2.2, 0.2)), box(Vector3(11.0, 1.1, 9.5), Vector3(0.2, 2.2, 3.4)), box(Vector3(13.0, 1.1, 9.5), Vector3(0.2, 2.2, 3.4))]
	await frames(2)
	var trapped_at: Vector3 = trapped.global_position
	combat._gunshot_event(Vector3(12, 1.3, 0), Vector3(12, 1.3, 0), Vector3(12, 0, 3), true, null)
	var t_key: int = trapped.get_instance_id()
	check(combat._panic.has(t_key) and combat._panic[t_key].mode == "cower", "boxed-in bystander cowers instead of running into walls")
	await advance(1.0)
	check(trapped.global_position.distance_to(trapped_at) < 0.3, "cowering bystander does not grind into scenery")
	for wall in walls:
		wall.free()
	await dismiss([trapped])
	# Survivors resume their day after a quiet cooldown, retracing the flee trail.
	var calm := spawn(ids_with(false, "calm")[0], Vector3(-5, 0.012, 8))
	var home: Vector3 = calm.global_position
	await frames(2)
	combat._gunshot_event(ORIGIN, ORIGIN, Vector3(-5, 0, 3), true, null)
	var c_key: int = calm.get_instance_id()
	await advance(3.0)
	check(calm.global_position.distance_to(home) > 2.0, "panicked neighbor physically leaves the danger area")
	await advance(Combat.SAFE_COOLDOWN + 12.0)
	check(not combat._panic.has(c_key) and not calm.combat_override and not calm.has_meta("combat_controlled"), "after a safe cooldown the survivor's normal control is restored")
	check(calm.global_position.distance_to(home) < 1.0, "survivor walks the checked flee trail back home (%.2f m)" % calm.global_position.distance_to(home))
	check(not combat._wounds.has(calm.actor_id) and not calm.dead, "an unhurt survivor leaves no wound or death record")
	await dismiss([calm])

func _return_fire_rules() -> void:
	reset_player()
	var shooter := spawn(ids_with(true, "shooter")[0], Vector3(0, 0.012, 8), 0.0)
	await frames(2)
	var key: int = shooter.get_instance_id()
	var shots: int = combat.npc_shots
	var telegraphs: int = combat.telegraphs
	var notified := traffic.notified.size()
	check(combat._engage(shooter, "gun"), "armed NPC enters return fire within the fight budget")
	await advance(0.5)
	check(combat.npc_shots == shots and combat.health == 100.0, "armed NPC turns in place before any shot")
	await advance(0.9)
	check(combat.telegraphs > telegraphs, "a raised-pistol telegraph precedes the first shot")
	await advance(1.6)
	var fired: int = combat.npc_shots - shots
	check(fired >= 1 and fired <= 2, "return fire respects its cooldown (%d shots in 3 s)" % fired)
	check(traffic.notified.size() - notified == fired and combat.last_threat.get("by_player", true) == false, "each NPC bullet notifies traffic once, flagged as NPC fire")
	check(combat.npc_hits <= combat.npc_shots and combat.get_status().aggro_count >= 1, "NPC hits are bounded by shots; the shooter counts as hostile")
	await dismiss([shooter])
	# Cover between shooter and player: no sight, no telegraph, no damage.
	reset_player()
	var blocked := spawn(ids_with(true, "covered")[0], Vector3(0, 0.012, 8), PI)
	var wall := box(Vector3(0, 1.15, 4), Vector3(3, 2.3, 0.2))
	await frames(2)
	shots = combat.npc_shots
	telegraphs = combat.telegraphs
	combat._engage(blocked, "gun")
	await advance(3.0)
	check(combat.npc_shots == shots and combat.telegraphs == telegraphs and combat.health == 100.0, "an NPC never aims or fires through a wall")
	var excluded: Array[RID] = [blocked.get_rid()]
	var through: Dictionary = combat._trace_bullet(Vector3(0, 1.25, 8.0), Vector3(0, 1.25, 7.6), Vector3(0, 1.1, -1), excluded)
	check(through.hit.get("collider") == wall, "an NPC bullet trace stops at cover")
	await advance(3.5)
	check(not combat._active.has(blocked.get_instance_id()) or combat._active[blocked.get_instance_id()].mode == "return", "losing sight eventually ends return fire")
	wall.free()
	await dismiss([blocked])

func _death_registry() -> void:
	reset_player()
	var victim_id: String = ids_with(false, "victim")[0]
	var victim := spawn(victim_id, Vector3(-10, 0.012, 6))
	await frames(2)
	var died: Array[String] = []
	combat.actor_died.connect(func(id: String): died.append(id))
	var key: int = victim.get_instance_id()
	combat._damage_target(victim, 46.0, "shot", ORIGIN)
	check(not victim.dead and combat._panic.has(key), "first bullet wounds an unarmed victim, who flees")
	combat._damage_target(victim, 46.0, "shot", ORIGIN)
	check(victim.dead and combat.is_actor_dead(victim_id) and died.size() == 1 and died[0] == victim_id, "zero health kills: registry and actor_died signal agree")
	check(not victim.enabled and victim.collision_layer == 0 and not combat._panic.has(key) and not combat._active.has(key), "dead actor loses collision and every control budget")
	victim.set_enabled(true)
	check(not victim.enabled, "set_enabled(true) cannot resurrect a dead identity")
	await advance(0.8)
	check(victim.visible and victim.puppet.g.rotation.x < -1.0 and combat._corpses.size() >= 1, "a non-gory corpse lies down and stays briefly")
	var daily_id: String = ids_with(false, "daily")[0]
	var daily := make_resident(daily_id, Vector3(-14, 0.012, 6))
	await frames(2)
	combat._damage_target(daily, 200.0, "shot", ORIGIN)
	var spot: Vector3 = daily.global_position
	for i in 10:
		residents.tick(0.5)
	check(daily.dead and not daily.enabled and daily.global_position == spot and not residents.resume_after_combat(daily), "daily timetable never re-enables, moves or reschedules a dead resident")
	player.position = Vector3(0, 0.012, -90)
	await advance(2.0)
	check(not victim.visible and combat._corpses.is_empty() and combat.is_actor_dead(victim_id), "far corpses fade out while the death registry remains")
	reset_player()
	# Reload: fresh registry and fresh bodies for the same stable identities.
	var snapshot: Dictionary = combat.death_snapshot()
	check(int(snapshot.version) == Combat.DEATH_VERSION and snapshot.dead.has(victim_id) and snapshot.dead.has(daily_id), "death snapshot lists both stable identities")
	var reborn := spawn(victim_id, Vector3(-10, 0.012, 6))
	var reloaded := Combat.new()
	arena.add_child(reloaded)
	reloaded.setup(arena)
	await frames(2)
	check(not reloaded.is_actor_dead(victim_id) and reborn.enabled, "a fresh world has no deaths until its registry is restored")
	check(reloaded.restore_deaths(JSON.parse_string(JSON.stringify(snapshot))), "a JSON round-tripped registry restores")
	check(reborn.dead and not reborn.enabled and not reborn.visible and reloaded.is_actor_dead(daily_id), "restored deaths stay dead after reload")
	var size_before: int = reloaded.dead_ids().size()
	check(not reloaded.restore_deaths({"version": 99, "dead": []}), "unknown registry version is rejected")
	check(not reloaded.restore_deaths({"version": 1, "dead": [7]}) and not reloaded.restore_deaths({"version": 1, "dead": "victim"}) and not reloaded.restore_deaths({"version": 1, "dead": ["bad id!"]}), "malformed registries are rejected")
	var huge: Array = []
	for i in Combat.MAX_DEATHS + 1:
		huge.append("crowd_%d" % i)
	check(not reloaded.restore_deaths({"version": 1, "dead": huge}) and reloaded.dead_ids().size() == size_before, "an oversized registry is rejected without partial application")
	player.combat = combat
	reloaded._gun.queue_free()
	reloaded.queue_free()
	await dismiss([victim, reborn, daily])

func _panic_budget() -> void:
	reset_player()
	var ring: Array = []
	var ids := ids_with(false, "ring", 20)
	for i in ids.size():
		var angle := TAU * float(i) / ids.size()
		ring.append(spawn(ids[i], Vector3(sin(angle) * 9.0, 0.012, cos(angle) * 9.0), angle))
	await frames(2)
	combat._gunshot_event(ORIGIN, ORIGIN, ORIGIN + Vector3(0, -1.3, 0.5), true, null)
	check(combat._panic.size() == Combat.MAX_PANIC, "full-actor panic stays within its bounded budget (%d)" % combat._panic.size())
	check(combat.threat_scanned == ids.size(), "one gunshot scans each nearby actor once (%d)" % combat.threat_scanned)
	await advance(0.1)
	var status: Dictionary = combat.get_status()
	check(int(status.panic_ticks) <= Combat.MAX_PANIC and status.has("max_threat_usec") and status.has("crowd_panic"), "per-frame panic updates are bounded and reported")
	await dismiss(ring)

func _crowd_reactions() -> void:
	reset_player()
	crowd = Crowd.new()
	npcs.add_child(crowd)
	npcs.crowd = crowd
	crowd.level = arena
	crowd.npcs = npcs
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = 0.24
	crowd._shape.height = 1.65
	crowd._meshes.assign([crowd._person_mesh(false), crowd._person_mesh(true)])
	var near: Array[int] = []
	for i in 6:
		near.append(crowd.residents.size())
		crowd._add_resident(Vector3(-3.75 + i * 1.5, 0.012, 14), 0.0, "social", false)
	var porch: int = crowd.residents.size()
	crowd._add_resident(Vector3(8, 0.012, 14), PI, "porch", true)
	var enclosed: int = crowd.residents.size()
	crowd._add_resident(Vector3(20, 0.012, 14), 0.0, "social", false)
	var far: Array[int] = []
	for i in 20:
		far.append(crowd.residents.size())
		crowd._add_resident(Vector3(400 + i * 1.5, 0.012, 400), 0.0, "social", false)
	var fighters: Array[int] = []
	for i in 9:
		fighters.append(crowd.residents.size())
		crowd._add_resident(Vector3(-40 + i * 1.4, 0.012, -40), 0.0, "social", false)
	crowd._build_batches()
	var walls := [box(Vector3(20, 1.1, 15), Vector3(2.2, 2.2, 0.2)), box(Vector3(20, 1.1, 13), Vector3(2.2, 2.2, 0.2)),
		box(Vector3(19, 1.1, 14), Vector3(0.2, 2.2, 2.2)), box(Vector3(21, 1.1, 14), Vector3(0.2, 2.2, 2.2))]
	await frames(2)
	var starts: Dictionary = {}
	for index in near:
		starts[index] = crowd.residents[index].position
	var scanned_before: int = crowd._threat_scanned
	combat._gunshot_event(ORIGIN, ORIGIN, Vector3(-12, 0.0, 6), true, null)
	check(crowd._panic.size() == 8, "gunfire panics every primitive resident in earshot (%d)" % crowd._panic.size())
	check(crowd._threat_scanned - scanned_before == 8, "the shot scans only nearby residents, not the whole crowd (%d)" % (crowd._threat_scanned - scanned_before))
	var untouched := true
	for index in far + fighters:
		untouched = untouched and not crowd.residents[index].get("panic", false)
	check(untouched, "distant crowd cells are not disturbed")
	check(crowd._panic[porch].mode == "cower", "seated porch resident ducks in place")
	await advance(3.5, true)
	var fled := true
	for index in near:
		fled = fled and crowd.residents[index].position.distance_to(ORIGIN) > starts[index].distance_to(ORIGIN) + 2.0
	check(fled, "primitive residents run away from the shooter")
	check(crowd._panic[enclosed].mode == "cower" and crowd.residents[enclosed].position.distance_to(Vector3(20, 0.012, 14)) < 0.05, "boxed-in primitive resident cowers instead of pushing into walls")
	var panic_status: Dictionary = crowd.get_panic_status()
	check(int(panic_status.panic_movers) <= Crowd.PANIC_MOVERS and int(panic_status.panic_updates) <= Crowd.PANIC_MOVERS, "crowd flee updates stay within the mover budget")
	await advance(Crowd.PANIC_SAFE + 10.0, true)
	var home := true
	for index in near:
		home = home and crowd.residents[index].position.distance_to(starts[index]) < 0.1
	check(crowd._panic.is_empty() and not crowd.residents[porch].get("panic", false), "every crowd survivor is released after the safe cooldown")
	check(home, "primitive survivors walk back to their original spots")
	for wall in walls:
		wall.free()
	# Cheap crowd death; culling and promotion never resurrect it.
	var victim: int = far[0]
	var neighbor: int = far[1]
	check(combat._damage_target(crowd.residents[victim].body, 200.0, "shot", Vector3(400, 1.3, 395)), "a primitive resident can be shot")
	check(crowd.is_dead(victim) and combat.is_actor_dead("crowd_%d" % victim) and crowd.residents[victim].body.collision_layer == 0, "zero health kills the primitive resident and drops its collider")
	crowd.set_presence(Vector3(-3000, 0, -3000), 40.0, 160.0)
	await frames(2)
	crowd.set_presence(Vector3(400, 0, 400), 40.0, 160.0)
	await frames(2)
	check(crowd.residents[victim].body == null and is_instance_valid(crowd.residents[neighbor].body) and crowd.residents[neighbor].body.collision_layer == 8, "cell unload/reload rebuilds neighbors but never the dead")
	check(crowd.begin_combat(victim).is_empty() and combat._promote_crowd(victim) == null, "a dead crowd identity cannot be promoted back into a fighter")
	crowd.set_presence(Vector3.ZERO, 40.0, 160.0)
	await frames(2)
	# Overflow: the ninth punch has no fight slot but still lands.
	var overflow_before: int = combat.overflow_hits
	for i in 8:
		combat._damage_target(crowd.residents[fighters[i]].body, 1.0, "punch")
	check(combat._active.size() == Combat.MAX_ACTIVE, "fight budget fills at its limit")
	var spare: int = fighters[8]
	check(combat._damage_target(crowd.residents[spare].body, 30.0, "punch"), "a hit beyond the fight budget is still accepted")
	check(combat._active.size() == Combat.MAX_ACTIVE and combat.overflow_hits == overflow_before + 1, "overflow hit counted without exceeding the budget")
	check(combat._wounds.has("crowd_%d" % spare) and crowd.residents[spare].get("panic", false), "overflow damage is stored and the resident flees cheaply")
	combat._damage_target(crowd.residents[spare].body, 70.0, "shot")
	check(combat.is_actor_dead("crowd_%d" % spare) and crowd.is_dead(spare), "accumulated overflow damage kills without a full actor")
	release_all()
	check(not crowd.is_dead(fighters[0]) and is_instance_valid(crowd.residents[fighters[0]].body) and crowd.residents[fighters[0]].body.collision_layer == 8, "released survivors return to the shared crowd")
	var snapshot: Dictionary = combat.death_snapshot()
	check(snapshot.dead.has("crowd_%d" % victim) and snapshot.dead.has("crowd_%d" % spare), "crowd deaths enter the persisted registry")
