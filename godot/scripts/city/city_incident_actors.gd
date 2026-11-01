extends RefCounted
## Performer bodies for city_incidents.gd. A performer is a real neighbor the
## incident service moves for a while: a crowd resident gets one full stand-in
## (the same representation change combat and custody use: the shared render
## slot and collider are relinquished, one body replaces them at the same spot),
## a named or daily actor is held with the flags schedules already respect.
## Nothing is ever teleported: stand-ins appear where the slot stood and hand the
## slot back where the body ends up. Combat (a bicycle knockdown, a fight) or
## custody may take a performer at any time; the service then simply forgets it.

const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const PopulationAppearance := preload("res://scripts/city/city_population_appearance.gd")
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")

const CROWD_CASTS := ["liner_2", "ricky", "mailman", "granny"]
const MAX_PERFORMERS := 4
const META := "incident_performer"

var level: Node
var holder: Node
## id -> {id, actor, incident, proxy, crowd_index, target, has_target, manual, revision}
var performers: Dictionary = {}
var borrowed := 0
var released := 0
var lost := 0
var tactics := Tactics.new()

func setup(owner_level: Node, owner_holder: Node) -> void:
	level = owner_level
	holder = owner_holder

func owns(id: String) -> bool:
	return performers.has(id)

func actor_of(id: String):
	var entry: Dictionary = performers.get(id, {})
	var actor = entry.get("actor")
	return actor if is_instance_valid(actor) else null

## Takes physical control of `id` for `incident_id`. Returns the body or null
## when the person is unavailable (dead, in custody, fighting, police, budget).
func borrow(id: String, incident_id: String) -> Node3D:
	if performers.has(id):
		return actor_of(id)
	if performers.size() >= MAX_PERFORMERS or _dead(id):
		return null
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var index := int(id.substr(6))
		var proxy := _stand_in(index)
		if proxy == null:
			return null
		proxy.set_meta("crowd_proxy_index", index)
		proxy.set_meta(META, incident_id)
		proxy.combat_override = true
		performers[id] = {"id": id, "actor": proxy, "incident": incident_id, "proxy": true, "crowd_index": index}
		borrowed += 1
		return proxy
	var actor = named_actor(id)
	if not _free(actor):
		return null
	performers[id] = {"id": id, "actor": actor, "incident": incident_id, "proxy": false, "crowd_index": -1,
		"target": actor.target, "has_target": actor.has_target, "manual": actor.manual_target, "revision": actor.target_revision}
	actor.combat_override = true
	actor.set_meta("combat_controlled", true)
	actor.set_meta(META, incident_id)
	actor.has_target = false
	actor.velocity = Vector3.ZERO
	borrowed += 1
	return actor

## Still ours to move: alive, enabled, and neither combat nor custody took it.
func still_ours(id: String) -> bool:
	var actor = actor_of(id)
	if actor == null or actor.get("dead") == true or actor.get("enabled") != true:
		return false
	if actor.get("combat_override") != true or actor.has_meta("police_custody"):
		return false
	var combat = level.get("combat") if level != null else null
	if combat != null and combat.has_method("actor_mode") and str(combat.actor_mode(actor)) != "unknown":
		return false
	return str(actor.get_meta(META, "")) == str(performers[id].incident)

## Someone else owns the body now: drop the record, clear only our own marks.
func forget(id: String) -> void:
	var entry: Dictionary = performers.get(id, {})
	if entry.is_empty():
		return
	performers.erase(id)
	lost += 1
	var actor = entry.get("actor")
	if is_instance_valid(actor) and actor.has_meta(META):
		actor.remove_meta(META)

## Hands the person back to normal life where they stand. A crowd stand-in
## returns its slot at its current position; a named actor resumes its routine.
func release(id: String) -> bool:
	if not performers.has(id):
		return false
	if not still_ours(id):
		forget(id)
		return false
	var entry: Dictionary = performers[id]
	performers.erase(id)
	released += 1
	var actor = entry.actor
	actor.remove_meta(META)
	actor.velocity = Vector3.ZERO
	if bool(entry.proxy):
		var crowd = _crowd()
		actor.collision_layer = 0
		if crowd != null:
			crowd.end_combat(int(entry.crowd_index), actor.global_position, float(actor.yaw), actor.capsule)
		actor.queue_free()
		return true
	if actor.has_meta("combat_controlled"):
		actor.remove_meta("combat_controlled")
	actor.combat_override = false
	actor.blocked = false
	actor.blocked_seconds = 0.0
	if actor.puppet != null:
		actor.puppet.pose({"walk": 0.0})
	var residents = level.get("residents") if level != null else null
	if residents != null and residents.get("actors") is Dictionary and residents.actors.get(id) == actor and residents.has_method("resume_after_combat"):
		residents.resume_after_combat(actor)
	elif not actor.patrol_points.is_empty():
		actor.has_target = false
		actor.manual_target = false
	elif actor.target_revision == int(entry.revision):
		actor.target = entry.target
		actor.has_target = bool(entry.has_target)
		actor.manual_target = bool(entry.manual)
	return true

func release_all() -> void:
	for id in performers.keys().duplicate():
		release(str(id))

## One forward-only, collision-swept step (police tactics' walker).
func walk(id: String, destination: Vector3, delta: float, speed: float) -> int:
	var actor = actor_of(id)
	if actor == null:
		return Tactics.MOVE_BLOCKED
	Tactics.tick_body(actor, delta)
	var result := Tactics.walk(actor, destination, delta, speed)
	if actor.puppet != null:
		actor.puppet.pose({"walk": (0.7 if speed > 2.2 else 0.42) if actor.moving else 0.0})
	return result

## Holds still facing `point` with a named pose (the act itself, or idling).
func hold(id: String, point: Vector3, delta: float, pose: String, phase := 0.0) -> void:
	var actor = actor_of(id)
	if actor == null:
		return
	Tactics.tick_body(actor, delta)
	if point.is_finite():
		Tactics.face(actor, Tactics.heading_to(actor.global_position, point, float(actor.yaw)), delta, 0.05)
	if actor.puppet == null:
		return
	var wave := sin(phase * 7.0)
	match pose:
		"bend":
			actor.puppet.pose({"walk": 0.0, "lean": 0.32, "armR": [-0.95 + 0.12 * wave, 0.1], "armL": [-0.95 - 0.12 * wave, 0.1], "nod": 0.3})
		"drop":
			actor.puppet.pose({"walk": 0.0, "lean": 0.45, "armR": [-0.55, 0.05], "armL": [-0.2, 0.15], "nod": 0.35})
		"snatch":
			actor.puppet.pose({"walk": 0.0, "lean": 0.15, "armR": [-1.45, 0.0], "armL": [-0.4, 0.2]})
		"carry":
			actor.puppet.pose({"walk": 0.0, "armR": [-0.35, 0.05], "armL": [-0.2, 0.15]})
		"stopped":
			actor.puppet.pose({"walk": 0.0, "armR": [-0.25, 0.25], "armL": [-0.25, 0.25], "nod": 0.12})
		_:
			actor.puppet.pose({"walk": 0.0, "look": 0.25 * sin(phase * 0.7)})

func get_status() -> Dictionary:
	var list: Array = []
	for id in performers:
		list.append({"id": str(id), "incident": str(performers[id].incident), "proxy": bool(performers[id].proxy)})
	return {"performers": list, "count": performers.size(), "max": MAX_PERFORMERS, "borrowed": borrowed,
		"released": released, "lost": lost}

# --------------------------------------------------------------- lookups

func named_actor(id: String):
	if level == null:
		return null
	for provider_name in ["npcs", "residents"]:
		var provider = level.get(provider_name)
		var actors = provider.get("actors") if provider != null else null
		if actors is Dictionary and (actors as Dictionary).has(id) and is_instance_valid(actors[id]):
			return actors[id]
	return null

func _free(actor) -> bool:
	if not is_instance_valid(actor) or not actor is Actor or actor.dead or not actor.enabled or actor.combat_override:
		return false
	if actor == level.get("player"):
		return false
	var id := str(actor.actor_id)
	if str(actor.cast_id).begins_with("cop_") or id == "officer" or id.begins_with("patrol_officer_"):
		return false
	for key in ["police_custody", "police_assist", "law_responder", "police_crew", "case_locked", META]:
		if actor.has_meta(key):
			return false
	return true

func _dead(id: String) -> bool:
	var combat = level.get("combat") if level != null else null
	if combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id)):
		return true
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		return crowd != null and crowd.has_method("is_dead") and bool(crowd.is_dead(int(id.substr(6))))
	return false

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

## The same stand-in custody builds: the slot's birth-ID appearance on one rig.
func _stand_in(index: int) -> Node3D:
	var crowd = _crowd()
	if crowd == null or holder == null or not crowd.has_method("begin_combat"):
		return null
	if index < 0 or index >= crowd.residents.size():
		return null
	var record: Dictionary = crowd.residents[index]
	if record.get("panic", false) or record.get("police_custody", false):
		return null
	var info: Dictionary = crowd.begin_combat(index)
	if info.is_empty():
		return null
	var actor := Actor.new()
	holder.add_child(actor)
	actor.build(level, "crowd_%d" % index, CROWD_CASTS[index % CROWD_CASTS.size()], "Neighbor")
	var appearance := PopulationAppearance.profile("crowd_%d" % index)
	var roster: Array = ModularPeople.roster()
	var slot := int(appearance.get("roster_index", 0))
	if slot >= 0 and slot < roster.size():
		var look: Dictionary = roster[slot]
		actor.puppet.g.free()
		actor.puppet = Puppet.new()
		actor.puppet.id = actor.actor_id
		actor.puppet.H = float(look.height)
		actor.capsule.shape.height = maxf(0.8, actor.puppet.H - 0.10)
		actor.capsule.position.y = actor.capsule.shape.height * 0.5 + 0.08
		actor.puppet.g = ModularPeople.rig(actor.actor_id, slot, actor.puppet.H)
		actor.add_child(actor.puppet.g)
		actor.puppet.bind()
		actor._speech_label.position.y = actor.puppet.H + 0.78
		actor.set_meta("population_appearance", appearance)
	actor.global_position = info.position
	actor.yaw = float(info.yaw)
	actor.puppet.g.rotation.y = actor.yaw
	return actor
