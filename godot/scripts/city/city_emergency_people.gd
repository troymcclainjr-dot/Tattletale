extends RefCounted
## Injured people waiting for paramedics (city_emergency_response.gd). A crowd
## neighbor is held by one stand-in body: the representation change combat,
## custody and incidents already use (the shared slot and its collider are
## relinquished and one full body appears exactly where the slot stood). The
## person then stays hunched over where they are; nobody is moved anywhere.
## Named contacts and daily residents are never held, only tracked by identity.
## Combat, custody or police may take the body at any time: the hold is then
## forgotten. A body that died is never released or revived; combat keeps it.

const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const PopulationAppearance := preload("res://scripts/city/city_population_appearance.gd")
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")

const CROWD_CASTS := ["liner_2", "ricky", "mailman", "granny"]
const MAX_HOLDS := 2
## On the held body (combat: never a fight target; a bicycle bump only stumbles).
const META := "ems_patient"

var level: Node
var holder: Node
## id -> {id, actor, call, crowd_index}
var holds: Dictionary = {}
var borrowed := 0
var released := 0
var lost := 0

func setup(owner_level: Node, owner_holder: Node) -> void:
	level = owner_level
	holder = owner_holder

func owns(id: String) -> bool:
	return holds.has(id)

func body_of(id: String):
	var entry: Dictionary = holds.get(id, {})
	var actor = entry.get("actor")
	return actor if is_instance_valid(actor) else null

## "" when `id` could be held right now, otherwise why not. Only free, placed,
## living crowd neighbors qualify; nobody busy with combat, panic or custody.
func hold_blocker(id: String) -> String:
	if holds.has(id):
		return ""
	if holds.size() >= MAX_HOLDS:
		return "hold_budget"
	if not id.begins_with("crowd_") or not id.substr(6).is_valid_int():
		return "not_crowd"
	var crowd = _crowd()
	var index := int(id.substr(6))
	if crowd == null or index < 0 or index >= crowd.residents.size():
		return "unknown"
	var resident: Dictionary = crowd.residents[index]
	if bool(resident.get("dead", false)):
		return "dead"
	if bool(resident.get("police_custody", false)) or bool(resident.get("police_custody_completed", false)):
		return "custody"
	if bool(resident.get("combat_controlled", false)) or bool(resident.get("panic", false)):
		return "busy"
	if bool(resident.get("identity_unplaced", false)) or not is_instance_valid(resident.get("body")):
		return "not_placed"
	return ""

## Takes physical charge of a waiting crowd patient for `call_id`. The body
## appears where the slot stands. Null when the person cannot be held now.
func hold(id: String, call_id: String) -> Node3D:
	if holds.has(id):
		return body_of(id)
	if not hold_blocker(id).is_empty():
		return null
	var index := int(id.substr(6))
	var actor := _stand_in(index)
	if actor == null:
		return null
	actor.set_meta("crowd_proxy_index", index)
	actor.set_meta(META, call_id)
	actor.combat_override = true
	actor.velocity = Vector3.ZERO
	holds[id] = {"id": id, "actor": actor, "call": call_id, "crowd_index": index}
	borrowed += 1
	return actor

## Still ours to pose: alive, enabled, and neither combat nor custody took it.
func still_ours(id: String) -> bool:
	var actor = body_of(id)
	if actor == null or actor.get("dead") == true or bool(actor.get_meta("city_dead", false)) or actor.get("enabled") != true:
		return false
	if actor.get("combat_override") != true or actor.has_meta("police_custody"):
		return false
	var combat = level.get("combat") if level != null else null
	if combat != null and combat.has_method("actor_mode") and str(combat.actor_mode(actor)) != "unknown":
		return false
	return str(actor.get_meta(META, "")) == str(holds[id].call)

## Hunched over, a hand to the head, where they are; facing `face` when given.
## `attended`: a paramedic is with them, so they look up.
func pose(id: String, delta: float, face: Vector3, attended := false) -> void:
	var actor = body_of(id)
	if actor == null:
		return
	Tactics.tick_body(actor, delta)
	if face.is_finite() and Tactics.flat(actor.global_position, face) > 0.3:
		Tactics.face(actor, Tactics.heading_to(actor.global_position, face, float(actor.yaw)), delta, 0.05)
	if actor.puppet == null:
		return
	if attended:
		actor.puppet.pose({"walk": 0.0, "lean": 0.3, "bob": -0.22, "armR": [-1.7, 0.2], "armL": [-0.55, 0.25], "nod": 0.05})
	else:
		actor.puppet.pose({"walk": 0.0, "lean": 0.5, "bob": -0.26, "armR": [-2.3, 0.25], "armL": [-0.6, 0.3], "nod": 0.4})
	for leg in actor.puppet.legs:
		leg.rotation.x = -0.5

## Hands the person back to ordinary life where they stand (the slot returns at
## the body's current position). A body someone else owns is only forgotten.
func release(id: String) -> bool:
	if not holds.has(id):
		return false
	if not still_ours(id):
		forget(id)
		return false
	var entry: Dictionary = holds[id]
	holds.erase(id)
	released += 1
	var actor = entry.actor
	actor.remove_meta(META)
	actor.velocity = Vector3.ZERO
	if actor.puppet != null:
		actor.puppet.pose({"walk": 0.0})
	actor.collision_layer = 0
	var crowd = _crowd()
	if crowd != null:
		# Held people never move, so a body already out of the tree (teardown)
		# simply hands the slot back where it stood.
		var at: Vector3 = actor.global_position if actor.is_inside_tree() else Vector3.INF
		crowd.end_combat(int(entry.crowd_index), at, float(actor.yaw), actor.capsule)
	actor.queue_free()
	return true

## Someone else owns the body now (combat, custody, death): drop the record and
## only our own mark. A corpse stays exactly as combat left it.
func forget(id: String) -> void:
	var entry: Dictionary = holds.get(id, {})
	if entry.is_empty():
		return
	holds.erase(id)
	lost += 1
	var actor = entry.get("actor")
	if is_instance_valid(actor) and actor.has_meta(META):
		actor.remove_meta(META)

func release_all() -> void:
	for id in holds.keys().duplicate():
		release(str(id))

func get_status() -> Dictionary:
	var list: Array = []
	for id in holds:
		list.append({"id": str(id), "call": str(holds[id].call)})
	return {"holds": list, "count": holds.size(), "max": MAX_HOLDS, "borrowed": borrowed, "released": released, "lost": lost}

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

## The same stand-in incidents and custody build: the slot's birth-ID look on
## one full rig, standing exactly where the slot stood.
func _stand_in(index: int) -> Node3D:
	var crowd = _crowd()
	if crowd == null or holder == null or not crowd.has_method("begin_combat"):
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
