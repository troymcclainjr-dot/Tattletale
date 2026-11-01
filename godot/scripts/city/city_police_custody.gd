extends RefCounted
## Police custody for city_police_assistance.gd. A suspect is held only after
## combat has let go (combat.disengage_actor): the same body for named actors,
## or a fresh physical stand-in for a crowd resident, because combat frees its
## own crowd proxy on release. Holding sets the flags schedules and combat
## already respect (combat_override, combat_controlled, law_responder), so no
## routine walks the suspect away and ambient gunfire hearing does not steal
## them. Completed custody uses a separate bounded identity registry; saving
## and restoring it never serializes transient holds or resurrects dead people.

const Actor := preload("res://scripts/city/city_npc_actor.gd")
const PopulationAppearance := preload("res://scripts/city/city_population_appearance.gd")
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")

const MAX_RECORDS := 12
const MAX_COMPLETED := 4096
const PERSIST_VERSION := 1
const CROWD_CASTS := ["liner_2", "ricky", "mailman", "granny"]

var level: Node
## id -> {id, actor, crowd_index, proxy, state: held|cuffed|escort|in_custody|lost, since}
var records: Dictionary = {}
var _completed: Dictionary = {}
var taken_in := 0
var lost := 0

func setup(owner_level: Node) -> void:
	level = owner_level

func has(id: String) -> bool:
	return records.has(id) or _completed.has(id)

func record(id: String) -> Dictionary:
	if _completed.has(id):
		return {"id": id, "state": "in_custody", "actor": null, "proxy": id.begins_with("crowd_")}
	return records.get(id, {})

func body_of(id: String):
	var entry: Dictionary = records.get(id, {})
	var actor = entry.get("actor")
	return actor if is_instance_valid(actor) else null

func ids_in_custody() -> Array[String]:
	var ids: Array[String] = []
	for id in _completed:
		if not _dead(str(id)):
			ids.append(str(id))
	ids.sort()
	return ids

## Takes physical control of a compliant suspect. `holder` parents a crowd
## stand-in. Returns the held body, or null when someone else still owns it.
func take(actor, id: String, holder: Node, clock: float) -> Node3D:
	if _completed.has(id) or _dead(id):
		return null
	if records.has(id):
		return body_of(id)
	if records.size() >= MAX_RECORDS or _completed.size() + records.size() >= MAX_COMPLETED:
		return null
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var proxy := _stand_in(int(id.substr(6)), holder)
		if proxy == null:
			return null
		_hold(proxy)
		records[id] = {"id": id, "actor": proxy, "crowd_index": int(id.substr(6)), "proxy": true, "state": "held", "since": clock}
		return proxy
	if not is_instance_valid(actor) or actor.get("dead") == true or actor.get("enabled") != true:
		return null
	if actor.get("combat_override") == true:
		return null # Combat (or another owner) still holds this body.
	_hold(actor)
	records[id] = {"id": id, "actor": actor, "crowd_index": -1, "proxy": false, "state": "held", "since": clock}
	return actor

func set_state(id: String, state: String) -> void:
	if records.has(id):
		records[id].state = state

## Whether the held body is still ours (combat can take it back, e.g. if hit).
func still_held(id: String, combat) -> bool:
	var actor = body_of(id)
	if actor == null or actor.get("dead") == true:
		return false
	if actor.get("combat_override") != true:
		return false
	if combat != null and combat.has_method("actor_mode"):
		return str(combat.actor_mode(actor)) == "unknown"
	return true

## The suspect is placed in a cruiser or walked out of view: off the street.
func take_in(id: String) -> void:
	var entry: Dictionary = records.get(id, {})
	if entry.is_empty():
		return
	if _dead(id):
		drop(id)
		return
	_completed[id] = true
	records.erase(id)
	taken_in += 1
	var actor = entry.get("actor")
	_hide_completed(id)
	if bool(entry.proxy):
		if is_instance_valid(actor):
			actor.collision_layer = 0
			actor.queue_free()

## Lost control (combat took the body, it died or was freed): forget the hold.
func drop(id: String) -> void:
	var entry: Dictionary = records.get(id, {})
	if entry.is_empty():
		return
	records.erase(id)
	lost += 1
	var actor = entry.get("actor")
	if is_instance_valid(actor):
		_clear_flags(actor, false)

## Return a held (not yet taken-in) suspect to normal life where they stand
## (reset). Taken-in suspects stay off the street.
func release(id: String) -> void:
	var entry: Dictionary = records.get(id, {})
	if entry.is_empty() or str(entry.state) == "in_custody":
		return
	records.erase(id)
	var actor = entry.get("actor")
	if not is_instance_valid(actor) or actor.get("dead") == true:
		return
	if bool(entry.proxy):
		var crowd = _crowd()
		actor.collision_layer = 0
		if crowd != null:
			crowd.end_combat(int(entry.crowd_index), actor.global_position, float(actor.yaw), actor.capsule)
		actor.queue_free()
		return
	_clear_flags(actor, true)

func release_all() -> void:
	for id in records.keys().duplicate():
		release(str(id))

func snapshot_state() -> Dictionary:
	return {"version": PERSIST_VERSION, "custody_ids": ids_in_custody()}

## Validate without mutating or materializing actors. Dead identities are valid
## input but are ignored at restore, so combat's persisted deaths take priority.
func validate_state(value) -> String:
	if not value is Dictionary:
		return "police custody state must be an object"
	var state: Dictionary = value
	if state.size() != 2 or not state.has("version") or not state.has("custody_ids"):
		return "invalid police custody fields"
	if not (state.version is int or state.version is float) or float(state.version) != float(PERSIST_VERSION):
		return "unsupported police custody version"
	if not state.custody_ids is Array or state.custody_ids.size() > MAX_COMPLETED:
		return "invalid police custody ID list"
	var seen: Dictionary = {}
	var merged := _completed.duplicate()
	for value_id in state.custody_ids:
		if not value_id is String:
			return "police custody ID must be text"
		var id: String = value_id
		if seen.has(id):
			return "duplicate police custody ID"
		if not _known_id(id):
			return "unknown or protected police custody ID: " + id
		seen[id] = true
		merged[id] = true
	if merged.size() > MAX_COMPLETED:
		return "police custody registry capacity exceeded"
	return ""

## Additive like the death registry: an older checkpoint cannot free a person
## already taken in. Call after resident restore and combat death restoration.
func restore_state(value) -> Dictionary:
	var reason := validate_state(value)
	if not reason.is_empty():
		return {"ok": false, "restored": 0, "skipped_dead": [], "reason": reason}
	if not records.is_empty():
		return {"ok": false, "restored": 0, "skipped_dead": [], "reason": "active police custody"}
	var skipped: Array[String] = []
	for id in value.custody_ids:
		if _dead(str(id)):
			skipped.append(str(id))
		else:
			_completed[str(id)] = true
	for id in _completed.keys():
		if _dead(str(id)):
			_completed.erase(id)
			if not skipped.has(str(id)):
				skipped.append(str(id))
		else:
			_hide_completed(str(id))
	return {"ok": true, "restored": _completed.size(), "skipped_dead": skipped, "reason": ""}

func _known_id(id: String) -> bool:
	if id.is_empty() or id.length() > 128 or id in ["player", "two_pack"]:
		return false
	if id.begins_with("crowd_"):
		var suffix := id.substr(6)
		if not suffix.is_valid_int() or "crowd_%d" % int(suffix) != id:
			return false
		var crowd = _crowd()
		return crowd != null and int(suffix) >= 0 and int(suffix) < crowd.residents.size()
	var actor = _named_actor(id)
	if not is_instance_valid(actor) or actor == level.get("player"):
		return false
	return not str(actor.get("cast_id")).begins_with("cop_") and id != "officer" and not id.begins_with("patrol_officer_")

func _named_actor(id: String):
	if level == null:
		return null
	for provider_name in ["npcs", "residents"]:
		var provider = level.get(provider_name)
		var actors = provider.get("actors") if provider != null else null
		if actors is Dictionary and actors.has(id) and is_instance_valid(actors[id]):
			return actors[id]
	return null

func _dead(id: String) -> bool:
	var combat = level.get("combat") if level != null else null
	if combat != null and combat.has_method("is_actor_dead") and combat.is_actor_dead(id):
		return true
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		return crowd != null and crowd.has_method("is_dead") and crowd.is_dead(int(id.substr(6)))
	var actor = _named_actor(id)
	return is_instance_valid(actor) and actor.get("dead") == true

func _hide_completed(id: String) -> void:
	if _dead(id):
		return
	if id.begins_with("crowd_"):
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd == null or index < 0 or index >= crowd.residents.size():
			return
		var resident: Dictionary = crowd.residents[index]
		var panic = crowd.get("_panic")
		if panic is Dictionary and panic.has(index):
			crowd._finish_panic(index, false)
		resident.police_custody = true
		resident.combat_controlled = true
		if is_instance_valid(resident.get("body")):
			resident.body.collision_layer = 0
			resident.body.collision_mask = 0
		crowd._apply_transform(index, "hidden")
		return
	var actor = _named_actor(id)
	if is_instance_valid(actor):
		_hold(actor)
		actor.set_meta("police_custody_completed", true)
		actor.set_enabled(false)
		actor.visible = false
		actor.velocity = Vector3.ZERO

func _hold(actor) -> void:
	actor.combat_override = true
	actor.set_meta("combat_controlled", true)
	actor.set_meta("law_responder", true)
	actor.set_meta("police_custody", true)
	actor.has_target = false
	actor.velocity = Vector3.ZERO

## Only our own flags; combat_controlled/combat_override are cleared only when
## custody still owns the body (a drop leaves combat's ownership intact).
func _clear_flags(actor, restore_routine: bool) -> void:
	for key in ["police_custody", "law_responder"]:
		if actor.has_meta(key):
			actor.remove_meta(key)
	if actor.get("dead") == true or not restore_routine:
		return
	if actor.has_meta("combat_controlled"):
		actor.remove_meta("combat_controlled")
	if actor.get("combat_override") == true:
		actor.combat_override = false
		actor.blocked = false
		actor.blocked_seconds = 0.0
		var residents = level.get("residents") if level != null else null
		if residents != null and residents.get("actors") is Dictionary and residents.actors.get(actor.actor_id) == actor and residents.has_method("resume_after_combat"):
			residents.resume_after_combat(actor)
		elif not actor.patrol_points.is_empty():
			actor.has_target = false
			actor.manual_target = false

## Same representation change combat uses for a struck crowd resident: the
## shared render slot and collider are relinquished, one full body replaces them.
func _stand_in(index: int, holder: Node) -> Node3D:
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

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

func get_status() -> Dictionary:
	var list: Array = []
	for id in records:
		var entry: Dictionary = records[id]
		list.append({"id": str(id), "state": str(entry.state), "proxy": bool(entry.proxy)})
	return {"records": list, "completed": _completed.size(), "completed_ids": ids_in_custody(),
		"taken_in": taken_in, "lost": lost, "max": MAX_RECORDS, "max_completed": MAX_COMPLETED}
