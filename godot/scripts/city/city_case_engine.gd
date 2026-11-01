extends RefCounted
## Data-driven neighborhood cases (schema 1, res://assets/data/cases/). Owned
## by CityMissions like the narrative: the active case and stage are the
## ordinary missions.active_id/stage, so the HUD, case marker, yellow route and
## world-save stage check are unchanged. This keeps what a stage needs: per
## objective progress, the people bound to roles, evidence, outcome ledgers and
## the photo replay ring. Player verbs arrive only as range-checked
## conversation hooks (talk/examine/collect/deliver/interview/report), the
## trusted phone photo context (photo) or the bounded tick (visit/follow/flee/
## await_incident). Rewards pay once through progression.reward_case.
## Contract: .work/pacifist-foundation/cases-contract.md

const Schema := preload("res://scripts/city/city_case_schema.gd")
const Library := preload("res://scripts/city/city_case_library.gd")
const Evidence := preload("res://scripts/city/city_case_evidence.gd")
const VERSION := 1
const TICK := 0.25
const SEEN_LIMIT := 64
## Game minutes a phone context may lag the live clock (2 min = 4 s at 0.5 min/s):
## the phone emits after the PNG is stored, a frame or two after the shutter.
const PHOTO_MAX_AGE := 2.0
const INCIDENT_LIMIT := 16
const VISIT_HEIGHT := 2.5
const SECTION_KEYS := ["version", "active", "closed", "records", "seen_photos"]
const ACTIVE_KEYS := ["id", "def_version", "stage", "done", "progress", "topics", "evidence", "started_minute", "bindings", "photos", "carrying", "delivered", "incident_id"]
const EVIDENCE_KEYS := ["id", "kind", "objective", "source", "minute", "subject", "photo_id", "photos", "witness", "topics", "distance", "position"]
## Incident states (incidents-contract §3) in which a witnessed scene is still happening.
const ACTIVE_INCIDENT_STATES := ["active"]
const EVIDENCE_TO_INCIDENT := {"photo": "photo", "testimony": "statement", "observation": "object", "item": "object"}
const BLOCK_RANK := {"ok": 0, "absent": 1, "custody": 2, "dead": 3}
## Speaker names the original case conversations use for their contacts.
const NAMES := {"resident": "Resident", "lookout": "Dumbarton witness", "officer": "Officer", "gardener": "Gardener", "organizer": "Organizer",
	"caretaker": "Caretaker", "ambient_mailman": "Mail carrier"}
const SOURCES := {"talk": "conversation", "examine": "examine", "collect": "collect", "deliver": "conversation", "interview": "interview",
	"report": "report", "photo": "photo", "visit": "visit", "follow": "follow", "flee": "flee", "await_incident": "incident"}

var missions
var definitions: Dictionary = {}
var order: Array[String] = []
var library_result: Dictionary = {}
var load_errors := PackedStringArray()
var load_warnings := PackedStringArray()
## Fixtures and authoring tools may start draft cases directly.
var allow_drafts := false
var active: Dictionary = {}
var closed: Dictionary = {}
var records: Dictionary = {}
var seen_photos: Array[String] = []
var incidents: Dictionary = {}
var revision := 0
var last_photo: Dictionary = {}
var _tick_clock := 0.0
var _props: Dictionary = {}
var _carried: Dictionary = {}
var _restore_record: Dictionary = {}
var _follow: Dictionary = {}
var _phone: Object = null
# Derived from the canonical incident after restore; never durable progress.
var _retry_report: Dictionary = {}

func setup(owner) -> void:
	missions = owner
	use_library(Library.load_index(context()))

## Definitions from the shipped library or a fixture's Library.load_definitions.
func use_library(result: Dictionary) -> void:
	library_result = result
	definitions.clear()
	order.clear()
	load_errors = PackedStringArray(result.get("errors", PackedStringArray()))
	load_warnings = PackedStringArray(result.get("warnings", PackedStringArray()))
	var known := {}
	if missions != null:
		for entry in missions.CASES:
			known[str(entry.id)] = true
		for id in missions.narrative.schema():
			known[str(id)] = true
	for id in result.get("order", []):
		known[str(id)] = true
	for id in result.get("order", []):
		var case_def: Dictionary = result.cases[id]
		var unknown := ""
		for other in case_def.discovery.requires_completed:
			if not known.has(str(other)):
				unknown = str(other)
		if not unknown.is_empty():
			load_errors.append("case %s: requires_completed names unknown case \"%s\"" % [str(id), unknown])
			continue
		definitions[str(id)] = case_def
		order.append(str(id))

## Validation context: original case slots, reserved story ids, role tokens.
func context() -> Dictionary:
	var legacy := {}
	var reserved: Array = []
	var roles := {}
	if missions != null:
		for entry in missions.CASES:
			legacy[str(entry.id)] = {"title": str(entry.title), "reward": int(entry.reward), "stages": missions.legacy_steps(str(entry.id)).size()}
		reserved = missions.narrative.schema().keys()
		roles = missions.narrative.ROLES.duplicate(true)
	return {"legacy": legacy, "reserved": reserved, "roles": roles}

func owns(id: String) -> bool:
	return definitions.has(id)

func definition(id: String) -> Dictionary:
	return definitions.get(id, {})

func is_draft(id: String) -> bool:
	return str(definition(id).get("status", "ready")) == "draft"

## Ready data cases outside the six original slots (ledger rows and totals).
func extra_ids() -> Array[String]:
	var result: Array[String] = []
	for id in order:
		if not bool(definitions[id].legacy_slot) and not is_draft(id):
			result.append(id)
	return result

## Checkpoint schema for data cases outside the original slots (drafts included,
## so a fixture-started draft still saves).
func schema() -> Dictionary:
	var result := {}
	for id in order:
		if not bool(definitions[id].legacy_slot):
			result[id] = {"reward": int(definitions[id].reward.points), "stages": definitions[id].stages.size(), "kind": "case"}
	return result

func title(id: String) -> String:
	return str(definition(id).get("title", ""))

# --- Authored steps (missions.case_steps) -----------------------------------------------

## One entry per stage in the original step shape; the target is the stage focus.
func steps(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var case_def := definition(id)
	for stage in case_def.get("stages", []):
		var focus := _first_required(stage)
		result.append({"target": _static_target(case_def, focus), "objective": str(stage.objective), "prompt": str(focus.get("prompt", "")),
			"dialogue": str(focus.get("dialogue", "")), "stage_id": str(stage.id)})
	return result

func _first_required(stage: Dictionary) -> Dictionary:
	for objective in stage.objectives:
		if not bool(objective.optional):
			return objective
	return stage.objectives[0]

func _static_target(case_def: Dictionary, objective: Dictionary) -> String:
	var ref := _primary_ref(objective)
	if ref.begins_with("participant:"):
		var actors: Array = case_def.participants[ref.trim_prefix("participant:")].actors
		if not actors.is_empty() and not str(actors[0]).begins_with("incident:"):
			return str(actors[0])
	if ref.begins_with("actor:"):
		return ref.trim_prefix("actor:")
	return "clue"

static func _primary_ref(objective: Dictionary) -> String:
	for key in ["target", "subject", "location"]:
		if not str(objective.get(key, "")).is_empty():
			return str(objective[key])
	return ""

# --- People ------------------------------------------------------------------------------

func _npcs():
	return missions.npcs if missions != null else null

func _level():
	return missions.level if missions != null else null

func _actor(actor_id: String):
	var npcs = _npcs()
	return npcs.get_actor(actor_id) if npcs != null and not actor_id.is_empty() and not actor_id.begins_with("incident:") else null

func _person_state(actor_id: String) -> Dictionary:
	var service = _incident_service()
	if actor_id != "player" and service != null and service.has_method("person_state"):
		return service.person_state(actor_id)
	return {}

func _person_position(actor_id: String) -> Vector3:
	if actor_id.is_empty() or actor_id == "player":
		return Vector3.INF
	var state := _person_state(actor_id)
	if not state.is_empty():
		return state.get("position", Vector3.INF)
	return _npcs().actor_position(actor_id) if _npcs() != null else Vector3.INF

func is_dead(actor_id: String) -> bool:
	var level = _level()
	var combat = level.get("combat") if level != null else null
	if combat != null and is_instance_valid(combat) and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(actor_id)):
		return true
	var state := _person_state(actor_id)
	if not state.is_empty():
		return str(state.get("state", "")) == "dead"
	var actor = _actor(actor_id)
	return actor != null and bool(actor.get_meta("city_dead", false))

func in_custody(actor_id: String) -> bool:
	var state := _person_state(actor_id)
	if not state.is_empty():
		return str(state.get("state", "")) == "custody"
	var actor = _actor(actor_id)
	return actor != null and not is_dead(actor_id) and (bool(actor.get_meta("police_custody", false)) or bool(actor.get_meta("police_custody_completed", false)))

## Alive, free, not mid-fight and somewhere the step can reach.
func is_present(actor_id: String) -> bool:
	if actor_id.is_empty() or actor_id == "player" or is_dead(actor_id):
		return false
	var state := _person_state(actor_id)
	if not state.is_empty():
		return str(state.get("state", "")) == "ok"
	var actor = _actor(actor_id)
	if actor == null or in_custody(actor_id) or actor.get("combat_override") == true:
		return false
	return _person_position(actor_id).is_finite()

## Candidate actor ids for a role; incident roles resolve through the bound incident.
func _candidates(case_def: Dictionary, role: String, record: Dictionary) -> Array:
	var result: Array = []
	for entry in case_def.participants[role].actors:
		var text := str(entry)
		if not text.begins_with("incident:"):
			result.append(text)
			continue
		var summary: Dictionary = incidents.get(str(record.get("incident_id", "")), {})
		var key := text.trim_prefix("incident:")
		if key == "witness":
			result.append_array(summary.get("witnesses", []))
		elif not str(summary.get("participants", {}).get(key, "")).is_empty():
			result.append(str(summary.participants[key]))
	return result.filter(func(person): return not str(person).is_empty() and str(person) != "player")

func _live_record(case_id: String) -> Dictionary:
	return active if not active.is_empty() and str(active.get("id", "")) == case_id else {}

## People who may take the role: the bound person for a "case" role, else the list.
func _people(case_def: Dictionary, role: String, record: Dictionary) -> Array:
	var bindings: Dictionary = record.get("bindings", {})
	if case_def.participants[role].bind == "case" and bindings.has(role):
		return [str(bindings[role])]
	return _candidates(case_def, role, record)

## Actor taking the role right now ("" = nobody can at the moment).
func resolve(case_def: Dictionary, role: String) -> String:
	if not case_def.participants.has(role):
		return ""
	for person in _people(case_def, role, _live_record(str(case_def.id))):
		if is_present(str(person)):
			return str(person)
	return ""

## {"state": ok|absent|custody|dead, "actor", "label", "role"}. Live mode (dead
## empty): dead only once every existing candidate is confirmed dead; absent
## while someone alive may still turn up. Pure mode (a saved death registry):
## dead when every candidate is in it.
func role_state(case_def: Dictionary, role: String, record: Dictionary, dead: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = case_def.participants[role]
	var result := {"state": "absent", "actor": "", "label": str(spec.label), "role": role}
	var people := _people(case_def, role, record)
	if people.is_empty():
		return result
	if not dead.is_empty():
		result.state = "dead"
		for person in people:
			if not dead.has(str(person)):
				result.state = "ok"
		return result
	var living := false
	var confirmed := false
	var detained := ""
	for person in people:
		var actor_id := str(person)
		if is_dead(actor_id):
			confirmed = true
			continue
		# Unknown/unloaded is not proof of death.
		living = true
		if is_present(actor_id):
			result.state = "ok"
			result.actor = actor_id
			return result
		if detained.is_empty() and in_custody(actor_id):
			detained = actor_id
	if living:
		result.state = "custody" if not detained.is_empty() else "absent"
		result.actor = detained
	elif confirmed:
		result.state = "dead"
	return result

func _objective_state(case_def: Dictionary, objective: Dictionary, record: Dictionary, dead: Dictionary) -> Dictionary:
	var worst := {"state": "ok", "actor": "", "label": "", "role": ""}
	for key in ["target", "subject", "location"]:
		var ref := str(objective.get(key, ""))
		if not ref.begins_with("participant:"):
			continue
		var state := role_state(case_def, ref.trim_prefix("participant:"), record, dead)
		if int(BLOCK_RANK[state.state]) > int(BLOCK_RANK[worst.state]):
			worst = state
	return worst

## First blocker from `from_stage` on. An "all" stage is blocked by any required
## objective; an "any" stage only when every alternative is blocked.
func blocker(id: String, from_stage: int, record: Dictionary = {}, dead: Dictionary = {}) -> Dictionary:
	var case_def := definition(id)
	var absent := {}
	var done: Dictionary = record.get("done", {})
	for stage in case_def.get("stages", []):
		if int(stage.index) < from_stage:
			continue
		if stage.complete == "any":
			var satisfied := false
			var reachable := false
			var waiting := {}
			var worst := {}
			for objective in stage.objectives:
				if done.has(objective.id):
					satisfied = true
					break
				var state := _objective_state(case_def, objective, record, dead)
				if state.state == "ok":
					reachable = true
				elif state.state == "absent":
					if waiting.is_empty():
						waiting = state
				elif worst.is_empty():
					worst = state
			if satisfied or reachable:
				continue
			if not waiting.is_empty():
				if absent.is_empty():
					absent = waiting
				continue
			if not worst.is_empty():
				return worst
			continue
		for objective in stage.objectives:
			if done.has(objective.id) or bool(objective.optional):
				continue
			var state := _objective_state(case_def, objective, record, dead)
			if state.state in ["dead", "custody"]:
				return state
			if state.state == "absent" and absent.is_empty():
				absent = state
	return absent if not absent.is_empty() else {"state": "ok", "actor": "", "label": "", "role": ""}

func custody_blocker(id: String, from_stage: int) -> String:
	var found := blocker(id, from_stage, _live_record(id))
	return str(found.label) if found.state == "custody" else ""

func has_dead_contact(id: String, from_stage: int) -> bool:
	return blocker(id, from_stage, _live_record(id)).state == "dead"

func speaker_for(case_def: Dictionary, role: String, actor_id: String) -> String:
	var spec: Dictionary = case_def.participants.get(role, {})
	var actors: Array = spec.get("actors", [])
	if not actors.is_empty() and str(actors[0]) == actor_id:
		if not str(spec.get("speaker", "")).is_empty():
			return str(spec.speaker)
		if NAMES.has(actor_id):
			return str(NAMES[actor_id])
	return missions.narrative.name_for(actor_id)

# --- Discovery ---------------------------------------------------------------------------

func requirements_met(case_def: Dictionary) -> bool:
	for other in case_def.discovery.requires_completed:
		if not missions.completed_ids.has(str(other)):
			return false
	return true

func locked_reason(case_def: Dictionary) -> String:
	if not str(case_def.discovery.locked_reason).is_empty():
		return str(case_def.discovery.locked_reason)
	for other in case_def.discovery.requires_completed:
		if not missions.completed_ids.has(str(other)):
			return "Resolve %s first." % missions.case_title(str(other))
	return "Not available yet."

## Offers in the original shape {id, title, actor_id, position} plus pitch/accept/decline.
func offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if missions == null or _npcs() == null:
		return result
	for id in order:
		var case_def: Dictionary = definitions[id]
		if is_draft(id) or case_def.discovery.trigger != "offer" or missions.completed_ids.has(id) or closed.has(id) or str(missions.active_id) == id:
			continue
		if not requirements_met(case_def) or blocker(id, 0).state in ["dead", "custody"]:
			continue
		for giver in case_def.discovery.givers:
			var actor_id := resolve(case_def, str(giver))
			if actor_id.is_empty():
				continue
			result.append({"id": id, "title": str(case_def.title), "actor_id": actor_id, "position": _person_position(actor_id),
				"pitch": str(case_def.discovery.pitch), "accept": str(case_def.discovery.accept), "decline": str(case_def.discovery.decline)})
			break
	return result

## Start/resume gate; restoring skips discovery rules (they held when it started).
func can_start(id: String, from_stage: int, restoring: bool) -> bool:
	var case_def := definition(id)
	if case_def.is_empty() or missions.completed_ids.has(id) or (closed.has(id) and not restoring):
		return false
	if is_draft(id) and not (allow_drafts or restoring):
		return false
	if from_stage < 0 or from_stage >= case_def.stages.size():
		return false
	if not restoring and not requirements_met(case_def):
		return false
	var record := usable_record(id, from_stage, _restore_record) if restoring else {}
	return not blocker(id, from_stage, record).state in ["dead", "custody"]

# --- Props -------------------------------------------------------------------------------

## Objectives an older checkpoint (no record) had finished before `from_stage`.
func _migrated_done(case_def: Dictionary, from_stage: int) -> Array:
	var chosen: Array = []
	for stage in case_def.stages:
		if int(stage.index) >= from_stage:
			break
		if stage.complete == "any":
			chosen.append(stage.objectives[0])
			continue
		for objective in stage.objectives:
			if not bool(objective.optional):
				chosen.append(objective)
	return chosen

## Props that must stand in the world: every declared prop not collected yet.
func _needed_props(case_def: Dictionary, from_stage: int, record: Dictionary) -> Array[String]:
	var taken: Array = []
	if record.is_empty():
		for objective in _migrated_done(case_def, from_stage):
			if objective.verb == "collect":
				taken.append(str(objective.target).trim_prefix("prop:"))
	else:
		taken.append_array(record.get("carrying", []))
		taken.append_array(record.get("delivered", []))
	var needed: Array[String] = []
	for stage in case_def.stages:
		for objective in stage.objectives:
			for key in ["target", "subject", "location", "item"]:
				var ref := str(objective.get(key, ""))
				var prop := ref.trim_prefix("prop:")
				if ref.begins_with("prop:") and not prop in needed and not prop in taken:
					needed.append(prop)
			var near := str(objective.get("area", {}).get("near", ""))
			if near.begins_with("prop:") and not near.trim_prefix("prop:") in needed and not near.trim_prefix("prop:") in taken:
				needed.append(near.trim_prefix("prop:"))
	return needed

## Read-only placement for a start or restore. {} when anything cannot be placed.
func prepare(id: String, from_stage: int, record: Dictionary = {}) -> Dictionary:
	var case_def := definition(id)
	if case_def.is_empty() or missions == null or missions.level == null or _npcs() == null:
		return {}
	var spots := {}
	var first := Vector3.INF
	for prop in _needed_props(case_def, from_stage, record):
		var spec: Dictionary = case_def.props[prop]
		var placement: Dictionary = missions.place_on_route(float(spec.placement.route_metres), float(spec.placement.radius), float(spec.placement.tolerance))
		if placement.is_empty():
			return {}
		spots[prop] = placement.position
		if not first.is_finite():
			first = placement.position
	if not first.is_finite():
		for giver in case_def.discovery.givers:
			var actor_id := resolve(case_def, str(giver))
			if not actor_id.is_empty():
				first = _person_position(actor_id)
				break
	if not first.is_finite():
		first = missions.level.player.global_position
	return {"ok": true, "position": first, "props": spots}

func _build_props(case_def: Dictionary, spots: Dictionary) -> void:
	for prop in spots:
		var spec: Dictionary = case_def.props[prop]
		var root := Node3D.new()
		root.name = "CaseProp_" + str(prop)
		missions._case_root.add_child(root)
		root.position = spots[prop]
		var shape: Dictionary = missions.build_case_prop(str(spec.builder), root)
		var body := StaticBody3D.new()
		body.name = "CasePropBody"
		# Passable unless authored solid, like the original loose-rubbish clues.
		body.collision_layer = 2 if bool(spec.solid) else 0
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = shape.size
		collision.shape = box
		collision.position = shape.center
		body.add_child(collision)
		root.add_child(body)
		var photo := Node3D.new()
		photo.name = "PhotoPoint"
		photo.position = Vector3(0, float(spec.photo_height), 0)
		root.add_child(photo)
		photo.set_meta("photo_subject_id", subject_id(str(case_def.id), str(prop)))
		photo.set_meta("photo_subject_kind", "case_clue")
		photo.set_meta("photo_subject_label", str(spec.title).capitalize())
		photo.set_meta("photo_subject_radius", float(spec.photo_radius))
		photo.set_meta("photo_subject_tags", ["case:" + str(case_def.id)])
		photo.add_to_group("photo_subjects")
		var tag: Label3D = missions._tag(root, str(spec.title), float(spec.tag_height))
		_props[str(prop)] = {"root": root, "body": body, "photo": photo, "tag": tag}

static func subject_id(case_id: String, prop: String) -> String:
	return "case:%s:%s" % [case_id, prop]

func prop_rids() -> Array[RID]:
	var result: Array[RID] = []
	for entry in _props.values():
		if is_instance_valid(entry.body):
			result.append(entry.body.get_rid())
	return result

func _hide_prop(prop: String) -> void:
	var entry: Dictionary = _props.get(prop, {})
	if entry.is_empty():
		return
	if is_instance_valid(entry.root):
		entry.root.hide()
	if is_instance_valid(entry.body):
		entry.body.collision_layer = 0
	if is_instance_valid(entry.photo):
		entry.photo.remove_from_group("photo_subjects")

func _carry(case_def: Dictionary, prop: String) -> void:
	if _carried.has(prop) or not is_instance_valid(missions._case_root) or not case_def.props.has(prop):
		return
	var node := Node3D.new()
	node.name = "CarriedCaseProp_" + prop
	missions._case_root.add_child(node)
	missions.build_case_prop(str(case_def.props[prop].builder), node)
	node.scale = Vector3.ONE * 0.65
	_carried[prop] = node
	_update_carried()

func _drop_carried(prop: String) -> void:
	if _carried.has(prop):
		if is_instance_valid(_carried[prop]):
			_carried[prop].queue_free()
		_carried.erase(prop)

func _update_carried() -> void:
	if _carried.is_empty() or missions.level == null or missions.level.get("player") == null:
		return
	var player = missions.level.player
	var index := 0
	for prop in _carried:
		var node = _carried[prop]
		if is_instance_valid(node) and node.is_inside_tree():
			# The original carried pose; extra items stack slightly higher.
			node.global_position = player.global_position + Vector3(0, 0.9 + 0.2 * index, -0.12).rotated(Vector3.UP, float(player.yaw))
			node.rotation.y = float(player.yaw)
		index += 1

func _update_tags() -> void:
	var seeking := {}
	var stage := current_stage()
	for objective in stage.get("objectives", []):
		if _objective_done(objective):
			continue
		for key in ["target", "subject", "location"]:
			var ref := str(objective.get(key, ""))
			if ref.begins_with("prop:"):
				seeking[ref.trim_prefix("prop:")] = true
	for prop in _props:
		var tag = _props[prop].tag
		if is_instance_valid(tag):
			tag.visible = seeking.has(prop)

# --- Lifecycle ---------------------------------------------------------------------------

func _now() -> float:
	var level = _level()
	var clock = level.get("world_time") if level != null else null
	if clock != null and is_instance_valid(clock) and Schema._number(clock.get("total_minutes"), 0.0, 1.0e12):
		return snappedf(float(clock.total_minutes), 0.01)
	return 0.0

func _has_clock() -> bool:
	var level = _level()
	var clock = level.get("world_time") if level != null else null
	return clock != null and is_instance_valid(clock)

func _fresh_record(case_def: Dictionary) -> Dictionary:
	return {"id": str(case_def.id), "def_version": int(case_def.version), "stage": 0, "done": {}, "progress": {}, "topics": {}, "evidence": [],
		"started_minute": _now(), "bindings": {}, "photos": {}, "carrying": [], "delivered": [], "incident_id": ""}

## missions._start_case_at calls this after cancel_case() and once the case root exists.
func begin(id: String, from_stage: int, placement: Dictionary, restoring: bool, incident_id: String = "") -> void:
	_retry_report.clear()
	var case_def := definition(id)
	active = _fresh_record(case_def)
	active.incident_id = incident_id
	var saved := usable_record(id, from_stage, _restore_record) if restoring else {}
	var resumed := false
	if not saved.is_empty():
		active = _sanitize_record(case_def, saved, from_stage)
		resumed = true
	elif from_stage > 0:
		_migrate_into(case_def, from_stage)
	active.stage = from_stage
	missions.stage = from_stage
	_build_props(case_def, placement.get("props", {}))
	for each in case_def.stages:
		for objective in each.objectives:
			if not _objective_done(objective):
				continue
			if objective.verb == "examine" and bool(objective.hide_after):
				_hide_prop(str(objective.target).trim_prefix("prop:"))
			for ref in objective.hide_props:
				_hide_prop(str(ref).trim_prefix("prop:"))
	for prop in active.carrying:
		_carry(case_def, str(prop))
	if not resumed:
		for giver in case_def.discovery.givers:
			var actor_id := resolve(case_def, str(giver))
			if not actor_id.is_empty() and case_def.participants[str(giver)].bind == "case":
				active.bindings[str(giver)] = actor_id
	_follow.clear()
	_tick_clock = 0.0
	revision += 1
	_update_tags()

## A checkpoint without a record (written before the engine owned this case):
## every stage before the saved one is done; its evidence is re-created as migrated.
func _migrate_into(case_def: Dictionary, from_stage: int) -> void:
	for objective in _migrated_done(case_def, from_stage):
		active.done[objective.id] = true
		if objective.verb == "collect":
			var prop := str(objective.target).trim_prefix("prop:")
			if not prop in active.carrying:
				active.carrying.append(prop)
		elif objective.verb == "deliver":
			var item := str(objective.item).trim_prefix("prop:")
			active.carrying.erase(item)
			if not item in active.delivered:
				active.delivered.append(item)
		for evidence_id in objective.grants:
			_add_evidence(case_def, {"id": evidence_id, "objective": objective.id, "source": "migrated"}, false)

func on_cancelled() -> void:
	_retry_report.clear()
	active = {}
	_props.clear()
	_carried.clear()
	_follow.clear()
	revision += 1

func current_stage() -> Dictionary:
	if active.is_empty() or missions == null or str(active.id) != str(missions.active_id) or not owns(str(active.id)):
		return {}
	var stages: Array = definitions[active.id].stages
	var index := int(missions.stage)
	if index < 0 or index >= stages.size():
		return {}
	if not _retry_report.is_empty():
		var retry: Dictionary = stages[index].duplicate(true)
		retry.objectives = [_retry_report]
		return retry
	return stages[index]

func _objective_done(objective: Dictionary) -> bool:
	return active.done.has(objective.id) and str(_retry_report.get("id", "")) != str(objective.id)

func _objective_in_stage(objective_id: String) -> Dictionary:
	for objective in current_stage().get("objectives", []):
		if str(objective.id) == objective_id:
			return objective
	return {}

## "" when the objective may be taken now: "order", "evidence" or "item" otherwise.
func _requirements(objective: Dictionary) -> String:
	for other in objective.requires:
		if not active.done.has(str(other)):
			return "order"
	for alternatives in objective.requires_evidence:
		if not _holds_any(alternatives):
			return "evidence"
	if objective.verb == "deliver" and not str(objective.item).trim_prefix("prop:") in active.carrying:
		return "item"
	return ""

func _holds_any(alternatives: Array) -> bool:
	for entry in active.get("evidence", []):
		if str(entry.id) in alternatives:
			return true
	return false

func holds(evidence_id: String) -> bool:
	return _holds_any([evidence_id])

## First pending required objective whose requirements are met, else the first pending.
func focus_objective() -> Dictionary:
	var fallback: Dictionary = {}
	for objective in current_stage().get("objectives", []):
		if _objective_done(objective):
			continue
		if fallback.is_empty():
			fallback = objective
		if not bool(objective.optional) and _requirements(objective).is_empty():
			return objective
	return fallback

func objective_position(objective: Dictionary) -> Vector3:
	if objective.verb == "flee":
		return _escape_point(objective)
	return ref_position(_primary_ref(objective))

func ref_position(ref: String) -> Vector3:
	var case_def := definition(str(active.get("id", "")))
	if case_def.is_empty() or ref.is_empty():
		return Vector3.INF
	if ref.begins_with("participant:"):
		var actor_id := resolve(case_def, ref.trim_prefix("participant:"))
		return _person_position(actor_id) if not actor_id.is_empty() else Vector3.INF
	if ref.begins_with("prop:"):
		var entry: Dictionary = _props.get(ref.trim_prefix("prop:"), {})
		if entry.is_empty() or not is_instance_valid(entry.root) or not entry.root.is_inside_tree():
			return Vector3.INF
		return entry.root.global_position
	if ref.begins_with("actor:"):
		return _person_position(ref.trim_prefix("actor:"))
	if ref.begins_with("incident:"):
		var summary: Dictionary = incidents.get(str(active.get("incident_id", "")), {})
		var key := ref.trim_prefix("incident:")
		if key == "location":
			return summary.get("position", Vector3.INF)
		var actor_id := ""
		if key == "witness":
			var witnesses: Array = summary.get("witnesses", [])
			actor_id = str(witnesses[0]) if not witnesses.is_empty() else ""
		else:
			actor_id = str(summary.get("participants", {}).get(key, ""))
		return _person_position(actor_id) if not actor_id.is_empty() else Vector3.INF
	if ref.begins_with("route:"):
		return missions._route_point(ref.trim_prefix("route:").to_float())
	if ref.begins_with("pos:"):
		var parts := ref.trim_prefix("pos:").split(",")
		return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	return Vector3.INF

func _escape_point(objective: Dictionary) -> Vector3:
	var threat := ref_position(str(objective.subject))
	var here := _player_position()
	if not threat.is_finite():
		return here
	var away := Vector3(here.x - threat.x, 0, here.z - threat.z)
	if away.length() < 0.1:
		away = Vector3.FORWARD
	return threat + away.normalized() * float(objective.distance)

func target_position() -> Vector3:
	var objective := focus_objective()
	return objective_position(objective) if not objective.is_empty() else Vector3.INF

func objective_text() -> String:
	var stage := current_stage()
	if stage.is_empty():
		return ""
	var text := str(stage.objective)
	var objective := focus_objective()
	if objective.is_empty():
		return text
	match str(objective.verb):
		"photo":
			if int(objective.count) > 1:
				text += " (%d/%d)" % [_photo_count(objective), int(objective.count)]
		"follow":
			text += " · %d/%d s" % [int(float(active.progress.get(objective.id, 0.0))), int(objective.seconds)]
		"interview":
			var required := 0
			var asked := 0
			for topic in objective.topics:
				if bool(topic.required):
					required += 1
					asked += int(str(topic.id) in active.topics.get(objective.id, []))
			if required > 1:
				text += " (%d/%d)" % [asked, required]
	var role := str(objective.get("target", "")).trim_prefix("participant:")
	var case_def := definition(str(active.id))
	if objective.verb in Schema.PARTICIPANT_VERBS and case_def.participants.has(role) and resolve(case_def, role).is_empty():
		text += " · %s is not around right now" % str(case_def.participants[role].label)
	return text

func prompt() -> String:
	return str(_interactable_objective().get("prompt", ""))

## First pending E objective in range whose order/item requirements are met.
## Reports stay reachable without evidence so the officer can say what's missing.
func _interactable_objective() -> Dictionary:
	for objective in current_stage().get("objectives", []):
		if _objective_done(objective) or not objective.verb in Schema.E_VERBS:
			continue
		var unmet := _requirements(objective)
		if unmet == "order" or unmet == "item":
			continue
		var at := objective_position(objective)
		if at.is_finite() and missions._can_interact(at):
			return objective
	return {}

# --- Conversations -----------------------------------------------------------------------

func offer_conversation(offer: Dictionary) -> Dictionary:
	var case_def := definition(str(offer.id))
	var giver := str(case_def.discovery.givers[0]) if not case_def.discovery.givers.is_empty() else ""
	var pitch := str(offer.get("pitch", ""))
	var accept := str(offer.get("accept", ""))
	return {"actor_id": str(offer.actor_id), "start": "start", "nodes": {"start": {"speaker": speaker_for(case_def, giver, str(offer.actor_id)),
		"lines": [pitch if not pitch.is_empty() else "Could you help with something on the block?"],
		"choices": [{"text": accept if not accept.is_empty() else "Tell me about " + str(offer.title).to_lower() + ".", "hook": {"kind": "start_case", "id": str(offer.id)}},
			{"text": str(offer.get("decline", "Maybe later."))}]}}}

## Pure: building a conversation never changes case state.
func conversation_preview() -> Dictionary:
	var objective := _interactable_objective()
	if objective.is_empty():
		return {}
	var case_def := definition(str(active.id))
	var role := str(objective.get("target", "")).trim_prefix("participant:")
	var actor_id := resolve(case_def, role) if objective.verb in Schema.PARTICIPANT_VERBS else "clue"
	if actor_id.is_empty():
		return {}
	var speaker := "2-Pack" if actor_id == "clue" else (str(objective.speaker) if not str(objective.speaker).is_empty() else speaker_for(case_def, role, actor_id))
	var lines: Array = []
	if actor_id != "clue":
		var spec: Dictionary = case_def.participants[role]
		var listed: Array = _candidates(case_def, role, active)
		if not str(spec.stand_in_line).is_empty() and not listed.is_empty() and str(listed[0]) != actor_id:
			lines.append(str(spec.stand_in_line))
	match str(objective.verb):
		"interview":
			return _interview_graph(objective, actor_id, speaker, lines)
		"report":
			return _report_graph(objective, actor_id, speaker, lines)
	lines.append(str(objective.dialogue) if not str(objective.dialogue).is_empty() else str(objective.objective))
	var hook := {"kind": "case_step", "id": str(active.id), "stage": int(missions.stage), "objective": str(objective.id)}
	return {"actor_id": actor_id, "start": "start", "reactions": false, "nodes": {"start": {"speaker": speaker, "lines": lines,
		"choices": [{"text": str(objective.prompt).trim_prefix("E  "), "hook": hook}, {"text": "I'll come back."}]}}}

func _question(objective: Dictionary, topic: Dictionary, actor_id: String) -> Dictionary:
	return {"text": str(topic.ask), "next": "topic_" + str(topic.id), "hook": {"kind": "case_interview", "id": str(active.id),
		"stage": int(missions.stage), "objective": str(objective.id), "topic": str(topic.id), "witness": actor_id}}

## Witness greeting → questions → answers; every question is a trusted hook.
func _interview_graph(objective: Dictionary, actor_id: String, speaker: String, lines: Array) -> Dictionary:
	var asked: Array = active.topics.get(objective.id, [])
	var greeting := str(objective.greeting) if not str(objective.greeting).is_empty() else str(objective.dialogue)
	lines.append(greeting if not greeting.is_empty() else str(objective.objective))
	var nodes := {}
	var open: Array = []
	for topic in objective.topics:
		if _topic_ready(topic, asked):
			open.append(_question(objective, topic, actor_id))
	nodes["start"] = {"speaker": speaker, "lines": lines, "choices": open + [{"text": str(objective.farewell)}]}
	for topic in objective.topics:
		var heard: Array = asked.duplicate()
		if not str(topic.id) in heard:
			heard.append(str(topic.id))
		var next: Array = []
		for other in objective.topics:
			if str(other.id) != str(topic.id) and _topic_ready(other, heard):
				next.append(_question(objective, other, actor_id))
		nodes["topic_" + str(topic.id)] = {"speaker": speaker, "lines": [str(topic.answer)], "choices": next + [{"text": str(objective.farewell)}]}
	return {"actor_id": actor_id, "start": "start", "reactions": false, "nodes": nodes}

static func _topic_ready(topic: Dictionary, asked: Array) -> bool:
	for other in topic.after:
		if not str(other) in asked:
			return false
	return true

func _report_graph(objective: Dictionary, actor_id: String, speaker: String, lines: Array) -> Dictionary:
	var missing := missing_evidence(objective)
	if not missing.is_empty():
		var text := str(objective.missing)
		if text.is_empty():
			text = "I can't take a report on that yet. Bring me: %s." % ", ".join(missing)
		lines.append(text)
		return {"actor_id": actor_id, "start": "start", "reactions": false, "nodes": {"start": {"speaker": speaker, "lines": lines,
			"choices": [{"text": "I'll come back."}]}}}
	lines.append(str(objective.greeting) if not str(objective.greeting).is_empty() else str(objective.objective))
	var response := str(objective.dialogue) if not str(objective.dialogue).is_empty() else "Report received."
	var hook := {"kind": "case_report", "id": str(active.id), "stage": int(missions.stage), "objective": str(objective.id)}
	return {"actor_id": actor_id, "start": "start", "reactions": false, "nodes": {
		"start": {"speaker": speaker, "lines": lines, "choices": [{"text": str(objective.prompt).trim_prefix("E  "), "next": "filed", "hook": hook}, {"text": "I'll come back."}]},
		"filed": {"speaker": speaker, "lines": [response]}}}

## Labels of required evidence not yet held ("a or b" for alternatives).
func missing_evidence(objective: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var case_def := definition(str(active.get("id", "")))
	for alternatives in objective.get("requires_evidence", []):
		if _holds_any(alternatives):
			continue
		var labels := PackedStringArray()
		for evidence_id in alternatives:
			labels.append(str(case_def.evidence[evidence_id].label).to_lower())
		result.append(" or ".join(labels))
	return result

## Range, identity, stage and requirements re-checked: stale, duplicate or
## out-of-context callbacks change nothing.
func commit(action: Dictionary) -> bool:
	if missions == null or current_stage().is_empty():
		return false
	if str(action.get("id", "")) != str(missions.active_id) or int(action.get("stage", -1)) != int(missions.stage):
		return false
	if not str(action.get("choice", "")).is_empty():
		return false
	var kind := str(action.get("kind", ""))
	var objective := _objective_in_stage(str(action.get("objective", "")))
	if objective.is_empty() and kind == "case_step" and not action.has("objective"):
		objective = _interactable_objective()
	if objective.is_empty():
		return false
	var verb := str(objective.verb)
	var expected := {"case_step": ["talk", "examine", "collect", "deliver"], "case_interview": ["interview"], "case_report": ["report"]}
	if not verb in expected.get(kind, []):
		return false
	var unmet := _requirements(objective)
	if not unmet.is_empty():
		if unmet == "evidence":
			missions.notice.emit("You need more evidence first: %s." % ", ".join(missing_evidence(objective)))
		return false
	var case_def := definition(str(active.id))
	var role := str(objective.get("target", "")).trim_prefix("participant:")
	var actor_id := resolve(case_def, role) if verb in Schema.PARTICIPANT_VERBS else "clue"
	if actor_id.is_empty():
		return false
	var at := objective_position(objective)
	if not at.is_finite() or not missions._can_interact(at):
		return false
	if verb == "interview":
		return _commit_topic(case_def, objective, actor_id, str(action.get("topic", "")), str(action.get("witness", "")), at)
	if _objective_done(objective):
		return false
	if verb == "report":
		return _commit_report(case_def, objective, actor_id, at)
	if actor_id != "clue":
		missions.npcs.speak(actor_id, str(objective.dialogue), 6.0)
	if not str(objective.dialogue).is_empty():
		missions.notice.emit(str(objective.dialogue))
	_complete_objective(case_def, objective, actor_id, at, {})
	return true

## Plain E (no conversation) for talk/examine/collect/deliver only.
func interact() -> bool:
	var objective := _interactable_objective()
	if objective.is_empty() or not objective.verb in ["talk", "examine", "collect", "deliver"]:
		return false
	return commit({"kind": "case_step", "id": str(active.id), "stage": int(missions.stage), "objective": str(objective.id)})

## One topic per trusted reply, recorded once for the bound witness. Hearing an
## answer again is allowed (true) and records nothing.
func _commit_topic(case_def: Dictionary, objective: Dictionary, actor_id: String, topic_id: String, witness: String, at: Vector3) -> bool:
	if witness.is_empty() or witness != actor_id:
		return false
	var topic: Dictionary = {}
	for entry in objective.topics:
		if str(entry.id) == topic_id:
			topic = entry
	if topic.is_empty():
		return false
	var asked: Array = active.topics.get(objective.id, []).duplicate()
	if not _topic_ready(topic, asked):
		return false
	if _objective_done(objective) or topic_id in asked:
		return true
	asked.append(topic_id)
	active.topics[objective.id] = asked
	var role := str(objective.target).trim_prefix("participant:")
	if case_def.participants[role].bind == "case":
		active.bindings[role] = actor_id
	missions.npcs.speak(actor_id, str(topic.answer), 6.0)
	revision += 1
	var finished := true
	for entry in objective.topics:
		finished = finished and (not bool(entry.required) or str(entry.id) in asked)
	if finished:
		_complete_objective(case_def, objective, actor_id, at, {"witness": actor_id, "topics": asked.duplicate()})
	else:
		missions.changed.emit()
	return true

func _commit_report(case_def: Dictionary, objective: Dictionary, actor_id: String, at: Vector3) -> bool:
	var report := {"case_id": str(active.id), "objective": str(objective.id), "reporter": "player", "officer_actor_id": actor_id, "minute": _now(),
		"incident_id": str(active.incident_id), "evidence": evidence_list(str(active.id))}
	if bool(objective.incident) and not str(active.incident_id).is_empty():
		# The incident service decides (witnessed? expired? duplicate?); its
		# reason is authoritative and a refusal leaves the case unchanged.
		var service = _incident_service()
		var answer = null
		if service != null and service.has_method("report_incident"):
			answer = service.report_incident(str(active.incident_id), "player", {"channel": "case", "case_id": str(active.id), "officer_id": actor_id})
		elif service != null and service.has_method("file_report"):
			answer = service.file_report(str(active.incident_id), report.duplicate(true))
		if not answer is Dictionary or not bool(answer.get("ok", false)):
			var reason := str(answer.get("reason", "")) if answer is Dictionary else "the incident service is unavailable"
			missions.notice.emit("The report wasn't taken: %s." % (reason.replace("_", " ") if not reason.is_empty() else "try again later"))
			return false
		report.incident_result = {"status": str(answer.get("status", "")), "police_incident_id": str(answer.get("police_incident_id", "")), "duplicate": bool(answer.get("duplicate", false))}
	missions.npcs.speak(actor_id, str(objective.dialogue), 6.0)
	missions.report_filed.emit(str(active.id), report)
	if str(_retry_report.get("id", "")) == str(objective.id):
		_retry_report.clear()
		revision += 1
		_update_tags()
		missions.changed.emit()
	else:
		_complete_objective(case_def, objective, actor_id, at, {})
	return true

func _complete_objective(case_def: Dictionary, objective: Dictionary, actor_id: String, at: Vector3, extra: Dictionary) -> void:
	active.done[objective.id] = true
	var role := str(objective.get("target", "")).trim_prefix("participant:")
	if objective.verb in Schema.PARTICIPANT_VERBS and case_def.participants.has(role) and case_def.participants[role].bind == "case":
		active.bindings[role] = actor_id
	match str(objective.verb):
		"examine":
			if bool(objective.hide_after):
				_hide_prop(str(objective.target).trim_prefix("prop:"))
		"collect":
			var prop := str(objective.target).trim_prefix("prop:")
			_hide_prop(prop)
			if not prop in active.carrying:
				active.carrying.append(prop)
			_carry(case_def, prop)
		"deliver":
			var item := str(objective.item).trim_prefix("prop:")
			active.carrying.erase(item)
			if not item in active.delivered:
				active.delivered.append(item)
			_drop_carried(item)
	for ref in objective.hide_props:
		_hide_prop(str(ref).trim_prefix("prop:"))
	for evidence_id in objective.grants:
		var entry := {"id": evidence_id, "objective": str(objective.id), "source": str(SOURCES.get(objective.verb, "case"))}
		if actor_id != "clue" and not actor_id.is_empty():
			entry.subject = actor_id
		entry.merge(extra, true)
		_add_evidence(case_def, entry, true)
	if not str(objective.notice).is_empty():
		missions.notice.emit(str(objective.notice))
	revision += 1
	if not str(objective.ends_case).is_empty():
		finish(str(objective.ends_case), at)
		return
	_advance_if_complete(at)

func _add_evidence(case_def: Dictionary, entry: Dictionary, announce: bool) -> void:
	var evidence_id := str(entry.id)
	if holds(evidence_id) or not case_def.evidence.has(evidence_id):
		return
	var record := {"id": evidence_id, "kind": str(case_def.evidence[evidence_id].kind), "objective": str(entry.get("objective", "")),
		"source": str(entry.get("source", "case")), "minute": snappedf(float(entry.get("minute", _now())), 0.01)}
	for key in ["subject", "photo_id", "witness"]:
		if entry.has(key):
			record[key] = str(entry[key])
	for key in ["topics", "photos"]:
		if entry.has(key) and entry[key] is Array:
			var items: Array = []
			for item in entry[key]:
				items.append(str(item))
			record[key] = items
	if entry.has("distance"):
		record.distance = snappedf(float(entry.distance), 0.01)
	if entry.get("position") is Vector3 and Vector3(entry.position).is_finite():
		var at: Vector3 = entry.position
		record.position = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
	active.evidence.append(record)
	if not announce:
		return
	missions.evidence_recorded.emit(str(active.id), record.duplicate(true))
	# An incident-bound case shares verified evidence with the incident service.
	var service = _incident_service() if not str(active.get("incident_id", "")).is_empty() else null
	if service != null and service.has_method("attach_evidence"):
		var where: Vector3 = entry.position if entry.get("position") is Vector3 else _player_position()
		service.attach_evidence(str(active.incident_id), {"kind": str(EVIDENCE_TO_INCIDENT.get(record.kind, "object")), "by": "player",
			"subject_id": str(record.get("witness", record.get("subject", ""))), "at": where, "verified": true, "ref": str(record.get("photo_id", record.id))})

func _advance_if_complete(at: Vector3) -> void:
	var stage := current_stage()
	if stage.is_empty():
		return
	var finished: bool = stage.complete == "all"
	for objective in stage.objectives:
		var done: bool = _objective_done(objective)
		if stage.complete == "any" and done:
			finished = true
			break
		if stage.complete == "all" and not done and not bool(objective.optional):
			finished = false
			break
	if not finished:
		missions.changed.emit()
		return
	var count: int = definitions[active.id].stages.size()
	missions.stage = int(missions.stage) + 1
	active.stage = int(missions.stage)
	_follow.clear()
	if int(missions.stage) >= count:
		finish(str(definitions[active.id].completion.outcome), at)
		return
	_update_tags()
	missions.changed.emit()

## Ends the active attempt with an outcome. A rewarded outcome joins
## completed_ids and pays once (progression.reward_case refuses repeats); an
## unrewarded terminal one closes the case for good; anything else may retry.
func finish(outcome_id: String, at: Vector3) -> void:
	var id := str(missions.active_id)
	var case_def := definition(id)
	if case_def.is_empty():
		return
	var outcome: Dictionary = case_def.outcomes.get(outcome_id, {"rewarded": false, "terminal": false, "banner": "CASE CLOSED", "notice": ""})
	var evidence_ids: Array = []
	for entry in active.get("evidence", []):
		evidence_ids.append(str(entry.id))
	var already: bool = missions.completed_ids.has(id)
	var points := int(case_def.reward.points) if bool(outcome.rewarded) and not already else 0
	var money := 0
	if bool(outcome.rewarded) and not already:
		missions.completed_ids[id] = true
		missions.score += points
		var progression = missions.level.get("progression") if missions.level != null else null
		if progression != null and is_instance_valid(progression):
			money = int(progression.case_money(id, points)) if progression.has_method("case_money") else points
			if not bool(progression.reward_case(id, money)):
				money = 0
	if bool(outcome.terminal) and not bool(outcome.rewarded):
		closed[id] = outcome_id
	if bool(outcome.terminal):
		records[id] = {"outcome": outcome_id, "evidence": evidence_ids, "minute": _now()}
	var banner := str(outcome.banner) + ("\n+%d community points" % points if points > 0 else "")
	if at.is_finite():
		missions._celebrate(at, banner)
	var info := {"id": id, "outcome": outcome_id, "rewarded": points > 0 or (bool(outcome.rewarded) and not already), "points": points, "money": money, "evidence": evidence_ids.duplicate()}
	missions.cancel_case()
	var message := str(outcome.notice)
	if message.is_empty():
		var hint := "All neighborhood cases resolved. Keep exploring Baltimore." if missions.all_cases_complete() else "Keep an eye out for neighbors who need a hand."
		if points > 0:
			message = "%s. +%d community points%s. %s" % [str(outcome.banner).capitalize(), points, " · +$%d" % money if money > 0 else "", hint]
		else:
			message = "%s. %s" % [str(outcome.banner).capitalize(), hint]
	missions.notice.emit(message)
	missions.case_resolved.emit(id, info)

# --- Tick: contacts and continuous verbs ------------------------------------------------

func tick(delta: float) -> void:
	if missions == null or not is_finite(delta) or delta <= 0.0:
		return
	_ensure_photo_provider()
	if current_stage().is_empty():
		return
	_update_carried()
	_tick_clock += delta
	if _tick_clock < TICK:
		return
	var step := minf(_tick_clock, 1.0)
	_tick_clock = 0.0
	if _recover_incident_wait() or _check_contacts(""):
		return
	var case_id := str(active.id)
	var stage_index := int(missions.stage)
	for objective in current_stage().get("objectives", []):
		# A completion may advance or end the case: never judge a later stage
		# with this stage's objectives.
		if current_stage().is_empty() or str(active.get("id", "")) != case_id or int(missions.stage) != stage_index:
			return
		if _objective_done(objective) or not _requirements(objective).is_empty():
			continue
		match str(objective.verb):
			"visit":
				_tick_visit(objective, step)
			"follow":
				_tick_follow(objective, step)
			"flee":
				_tick_flee(objective, step)
			"await_incident":
				var summary: Dictionary = incidents.get(str(active.incident_id), {})
				if str(summary.get("state", "")) in objective.states:
					_complete_objective(definition(case_id), objective, "", _player_position(), {})
	if not current_stage().is_empty():
		_update_tags()

## A saved police response may be dropped on restore. Offer its report again
## at the wait stage without undoing testimony, prior objectives or rewards.
## The retry is derived, so saving before/after this poll has identical semantics.
func _recover_incident_wait() -> bool:
	if active.is_empty() or str(active.get("incident_id", "")).is_empty():
		_retry_report.clear()
		return false
	var id := str(active.incident_id)
	var service = _incident_service()
	if service != null and service.has_method("get_incident"):
		var latest = service.get_incident(id)
		if latest is Dictionary and not latest.is_empty():
			incidents[id] = incident_view(latest)
	var summary: Dictionary = incidents.get(id, {})
	var state := str(summary.get("state", ""))
	var case_def := definition(str(active.id))
	var stage: Dictionary = case_def.stages[int(missions.stage)]
	var waiting := false
	for objective in stage.objectives:
		if objective.verb != "await_incident" or active.done.has(objective.id):
			continue
		if state in objective.states:
			_retry_report.clear()
			return false
		waiting = true
	if not waiting:
		_retry_report.clear()
		return false
	if state in ["expired", "cancelled", "resolved"]:
		missions.cancel_case()
		missions.notice.emit("Case closed without a reward: the incident ended before the required response.")
		return true
	if state != "ended" or not summary.get("report", {}).is_empty():
		_retry_report.clear()
		return false
	if not _retry_report.is_empty():
		return false
	for index in range(int(missions.stage), -1, -1):
		for objective in case_def.stages[index].objectives:
			if objective.verb == "report" and bool(objective.incident) and active.done.has(objective.id):
				_retry_report = objective.duplicate(true)
				revision += 1
				missions.notice.emit("The earlier response was interrupted. Give the officer your report again.")
				missions.changed.emit()
				return false
	return false

## Stand-ins first; a role nobody can ever take ends the attempt without a
## reward (the original cases' wording). True when the attempt was cancelled.
func _check_contacts(dead_id: String) -> bool:
	var id := str(missions.active_id)
	var case_def := definition(id)
	var found := blocker(id, int(missions.stage), active)
	if found.state == "dead":
		missions.cancel_case()
		missions.notice.emit("Case closed without a reward: a required contact has died.")
		return true
	if found.state == "custody":
		missions.cancel_case()
		missions.notice.emit("Case paused without a reward: %s is in police custody. Other cases remain available." % str(found.label))
		return true
	if not dead_id.is_empty():
		var objective := focus_objective()
		var role := str(objective.get("target", "")).trim_prefix("participant:")
		if case_def.participants.has(role) and dead_id in _candidates(case_def, role, active):
			var stand_in := resolve(case_def, role)
			if not stand_in.is_empty() and stand_in != dead_id:
				missions.notice.emit("%s can't help anymore. %s will take it from here." % [missions.narrative.name_for(dead_id), missions.narrative.name_for(stand_in)])
				missions.changed.emit()
	return false

func on_actor_died(actor_id: String) -> void:
	if not current_stage().is_empty():
		_check_contacts(actor_id)

func _player_position() -> Vector3:
	return missions.level.player.global_position

func _tick_visit(objective: Dictionary, step: float) -> void:
	var at := objective_position(objective)
	var here := _player_position()
	if not at.is_finite() or Vector2(here.x - at.x, here.z - at.z).length() > float(objective.radius) or absf(here.y - at.y) > VISIT_HEIGHT:
		active.progress[objective.id] = 0.0
		return
	var stayed := float(active.progress.get(objective.id, 0.0)) + step
	active.progress[objective.id] = snappedf(stayed, 0.01)
	if stayed >= float(objective.dwell):
		_complete_objective(definition(str(active.id)), objective, "", at, {"position": at})

## Keep inside the distance band for `seconds`; with "unseen" the subject
## noticing you resets the count (the original mail-carrier tail rule).
func _tick_follow(objective: Dictionary, step: float) -> void:
	var subject_ref := str(objective.subject)
	var at := ref_position(subject_ref)
	var here := _player_position()
	var state: Dictionary = _follow.get(objective.id, {"lost": 0.0, "cooldown": 0.0})
	_follow[objective.id] = state
	state.cooldown = maxf(0.0, float(state.cooldown) - step)
	if not at.is_finite():
		return
	var distance := Vector2(here.x - at.x, here.z - at.z).length()
	if distance > float(objective.max_distance):
		state.lost = float(state.lost) + step
		if float(state.lost) >= float(objective.lose_after):
			state.lost = 0.0
			_fail(objective, "You lost track of them. Pick up the trail again.")
		return
	state.lost = 0.0
	if bool(objective.unseen) and _sees_player(subject_ref, at, here, objective):
		# Never any tail time while they are looking; the notice is throttled.
		active.progress[objective.id] = 0.0
		if float(state.cooldown) <= 0.0:
			state.cooldown = 3.0
			missions.notice.emit("They noticed you. Hang back and keep your distance.")
			missions.changed.emit()
		return
	if distance < float(objective.min_distance):
		return
	var held := float(active.progress.get(objective.id, 0.0)) + step
	active.progress[objective.id] = snappedf(held, 0.01)
	if held >= float(objective.seconds):
		_complete_objective(definition(str(active.id)), objective, "", at, {"position": at})

func _sees_player(subject_ref: String, at: Vector3, here: Vector3, objective: Dictionary) -> bool:
	var offset := Vector3(here.x - at.x, 0, here.z - at.z)
	if offset.length() > float(objective.view_range) or offset.length() < 0.01:
		return false
	var actor = null
	if subject_ref.begins_with("participant:"):
		actor = _actor(resolve(definition(str(active.id)), subject_ref.trim_prefix("participant:")))
	elif subject_ref.begins_with("actor:"):
		actor = _actor(subject_ref.trim_prefix("actor:"))
	var facing := Vector3.FORWARD
	if actor != null and actor.get("yaw") != null:
		facing = Vector3(sin(float(actor.yaw)), 0, cos(float(actor.yaw)))
	elif actor is Node3D:
		facing = Vector3(actor.global_basis.z.x, 0, actor.global_basis.z.z).normalized()
	if facing.dot(offset.normalized()) < cos(deg_to_rad(float(objective.view_cone) * 0.5)):
		return false
	var space = missions.get_world_3d().direct_space_state if missions.is_inside_tree() else null
	var exclude: Array[RID] = []
	return Evidence.line_of_sight(space, at + Vector3.UP * 1.5, here + Vector3.UP * 1.4, exclude)

func _tick_flee(objective: Dictionary, step: float) -> void:
	var threat := ref_position(str(objective.subject))
	var here := _player_position()
	var elapsed := float(active.progress.get(objective.id, 0.0)) + step
	active.progress[objective.id] = snappedf(elapsed, 0.01)
	if threat.is_finite() and Vector2(here.x - threat.x, here.z - threat.z).length() >= float(objective.distance):
		_complete_objective(definition(str(active.id)), objective, "", here, {"position": here})
		return
	if float(objective.within) > 0.0 and elapsed >= float(objective.within):
		_fail(objective, "Too slow. Get clear of there.")

func _fail(objective: Dictionary, message: String) -> void:
	var mode := str(objective.get("on_fail", "reset"))
	active.progress[objective.id] = 0.0
	if mode == "reset":
		missions.notice.emit(message)
		missions.changed.emit()
		return
	finish(mode, _player_position())

# --- Photos ------------------------------------------------------------------------------

## Root bridges phone.photo_captured here. Evaluated once per photo id against
## the live world; the gallery image/JSON is never read.
func on_photo_captured(context) -> Dictionary:
	var result := {"ok": false, "recorded": [], "objectives": [], "reason": ""}
	var ctx := Evidence.normalize_context(context)
	if not bool(ctx.ok):
		result.reason = str(ctx.reason)
		last_photo = result.duplicate(true)
		return result
	if str(ctx.photo_id) in seen_photos:
		result.reason = "photo already evaluated"
		last_photo = result.duplicate(true)
		return result
	_remember_photo(str(ctx.photo_id))
	result.ok = true
	var stage := current_stage()
	if stage.is_empty():
		result.reason = "no data case is active"
		last_photo = result.duplicate(true)
		return result
	var now := _now()
	if _has_clock() and (float(ctx.minute) > now + 0.05 or now - float(ctx.minute) > PHOTO_MAX_AGE):
		result.reason = "photo context is stale"
		last_photo = result.duplicate(true)
		return result
	if float(ctx.minute) + 0.05 < float(active.started_minute):
		result.reason = "photo predates the case"
		last_photo = result.duplicate(true)
		return result
	var case_def := definition(str(active.id))
	var stage_index := int(missions.stage)
	var space = missions.get_world_3d().direct_space_state if missions.is_inside_tree() else null
	var misses := PackedStringArray()
	var exclude: Array[RID] = prop_rids()
	var player = missions.level.get("player")
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	for objective in stage.objectives:
		if objective.verb != "photo" or _objective_done(objective) or not _requirements(objective).is_empty():
			continue
		if not Evidence.in_window(float(ctx.minute_of_day), objective.time_window):
			misses.append("wrong_time")
			continue
		var candidate := _photo_candidate(case_def, objective)
		var check := Evidence.evaluate(ctx, candidate, objective, space, exclude)
		if not bool(check.ok):
			misses.append(str(check.reason))
			continue
		var taken: Array = active.photos.get(objective.id, []).duplicate()
		if not taken.is_empty() and float(ctx.minute) - float(active.progress.get(objective.id, -1.0e9)) < float(objective.min_interval_minutes):
			misses.append("too_soon")
			continue
		taken.append(str(ctx.photo_id))
		active.photos[objective.id] = taken
		active.progress[objective.id] = snappedf(float(ctx.minute), 0.01)
		result.objectives.append(str(objective.id))
		revision += 1
		if taken.size() < int(objective.count):
			missions.notice.emit("Photo %d of %d recorded for the case." % [taken.size(), int(objective.count)])
			missions.changed.emit()
			continue
		result.recorded.append_array(objective.grants)
		_complete_objective(case_def, objective, "", check.point, {"photo_id": str(ctx.photo_id), "photos": taken, "subject": str(candidate.id),
			"distance": float(check.distance), "position": check.point, "minute": float(ctx.minute)})
		if current_stage().is_empty() or str(active.get("id", "")) != str(case_def.id) or int(missions.stage) != stage_index:
			break
	if result.objectives.is_empty() and not misses.is_empty():
		result.reason = misses[0]
		var objective := focus_objective()
		if not objective.is_empty() and objective.verb == "photo" and misses[0] != "not_in_photo":
			var subject := str(objective.subject)
			var label := str(case_def.props.get(subject.trim_prefix("prop:"), {}).get("title", "subject")).to_lower() if subject.begins_with("prop:") else "subject"
			var why := "was just photographed" if misses[0] == "too_soon" else ("isn't there at this time of day" if misses[0] == "wrong_time" else Evidence.reason_text(misses[0]))
			missions.notice.emit("Photo saved, but the %s %s." % [label, why])
	last_photo = result.duplicate(true)
	return result

func _photo_candidate(case_def: Dictionary, objective: Dictionary) -> Dictionary:
	var subject := str(objective.subject)
	var candidate := {"id": "", "position": Vector3.INF, "lift": 0.0, "colliders": [], "area_center": Vector3.INF, "area_radius": 10.0}
	if subject.begins_with("prop:"):
		var prop := subject.trim_prefix("prop:")
		candidate.id = subject_id(str(case_def.id), prop)
		candidate.lift = 0.15
		var entry: Dictionary = _props.get(prop, {})
		if not entry.is_empty() and is_instance_valid(entry.photo) and entry.photo.is_inside_tree() and entry.root.visible:
			candidate.position = entry.photo.global_position
			candidate.colliders = [entry.body.get_rid()]
	elif subject.begins_with("route:") or subject.begins_with("pos:"):
		candidate.id = "case:%s:%s" % [str(case_def.id), str(objective.id)]
		var at := ref_position(subject)
		candidate.position = at + Vector3.UP if at.is_finite() else Vector3.INF
	else:
		var actor_id := ""
		if subject.begins_with("participant:"):
			actor_id = resolve(case_def, subject.trim_prefix("participant:"))
		elif subject.begins_with("actor:"):
			actor_id = subject.trim_prefix("actor:")
		elif subject.begins_with("incident:"):
			var summary: Dictionary = incidents.get(str(active.incident_id), {})
			var people = summary.get("participants", {})
			actor_id = str(people.get(subject.trim_prefix("incident:"), "")) if people is Dictionary else ""
		candidate.id = actor_id
		if not actor_id.is_empty():
			var body = _actor(actor_id)
			var at: Vector3 = _person_position(actor_id)
			# Ambient incident stand-ins are not registered named NPCs. Resolve
			# their live body through the service, then apply the same full-context
			# evidence checks as every other objective (never a summary shortcut).
			if subject.begins_with("incident:"):
				var service = _incident_service()
				if service != null and service.has_method("performer_actor"):
					var performer = service.performer_actor(actor_id)
					if is_instance_valid(performer) and performer is Node3D and performer.is_inside_tree():
						body = performer
						at = performer.global_position
			if at.is_finite():
				# The phone tests actors at origin + 1.2 m; the head is a second chance.
				candidate.position = at + Vector3.UP * 1.2
				candidate.lift = 0.4
				if body is CollisionObject3D:
					candidate.colliders = [body.get_rid()]
	if not objective.area.is_empty():
		candidate.area_center = ref_position(str(objective.area.near))
		candidate.area_radius = float(objective.area.radius)
	return candidate

func _photo_count(objective: Dictionary) -> int:
	var taken = active.photos.get(objective.id, [])
	return taken.size() if taken is Array else 0

func _remember_photo(photo_id: String) -> void:
	seen_photos.append(photo_id)
	while seen_photos.size() > SEEN_LIMIT:
		seen_photos.pop_front()

## Phone subject provider (phone-map-contract §1.4): the places a pending photo
## objective needs. Props (group photo_subjects) and people are already listed.
func photo_subjects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in current_stage().get("objectives", []):
		if objective.verb != "photo" or _objective_done(objective):
			continue
		var subject := str(objective.subject)
		if subject.begins_with("route:") or subject.begins_with("pos:"):
			var at := ref_position(subject)
			if at.is_finite():
				# A small radius: a place is framed, never "seen" through a wall.
				result.append({"id": "case:%s:%s" % [str(active.id), str(objective.id)], "kind": "case_place", "label": str(objective.objective),
					"position": at + Vector3.UP, "radius": 0.5, "tags": ["case:" + str(active.id)]})
	return result

func _ensure_photo_provider() -> void:
	var level = _level()
	var player = level.get("player") if level != null else null
	var phone = player.get("phone") if player != null and is_instance_valid(player) else null
	if phone == null or not is_instance_valid(phone) or phone == _phone or not phone.has_method("register_photo_subject_provider"):
		return
	phone.register_photo_subject_provider(Callable(missions, "photo_subjects_for_phone"))
	_phone = phone

func release_phone() -> void:
	if _phone != null and is_instance_valid(_phone) and _phone.has_method("unregister_photo_subject_provider"):
		_phone.unregister_photo_subject_provider(Callable(missions, "photo_subjects_for_phone"))
	_phone = null

# --- Incidents ---------------------------------------------------------------------------

func _incident_service():
	var level = _level()
	var service = level.get("incidents") if level != null else null
	return service if service != null and is_instance_valid(service) else null

## The parts of an incident record (incidents-contract §3) cases read:
## {id, template, state, position: Vector3, participants: {role: id},
## witnesses: [ids], case_id, report, resolution}. Older/other shapes with
## "position" and a role map are accepted too.
static func incident_view(summary: Dictionary) -> Dictionary:
	var view := {"id": str(summary.get("id", "")), "template": str(summary.get("template", summary.get("kind", ""))), "state": str(summary.get("state", "")),
		"position": Evidence._vector(summary.get("at", summary.get("position"))), "participants": {}, "witnesses": [], "case_id": str(summary.get("case_id", "")),
		"report": summary.get("report", {}) if summary.get("report") is Dictionary else {},
		"resolution": summary.get("resolution", {}) if summary.get("resolution") is Dictionary else {}}
	var people = summary.get("participants", [])
	if people is Array:
		for entry in people:
			if entry is Dictionary and not str(entry.get("role", "")).is_empty() and not view.participants.has(str(entry.role)):
				view.participants[str(entry.role)] = str(entry.get("id", ""))
	elif people is Dictionary:
		for role in people:
			view.participants[str(role)] = str(people[role])
	var witnesses = summary.get("witnesses", [])
	if witnesses is Array:
		for entry in witnesses:
			var witness := str(entry.get("id", "")) if entry is Dictionary else str(entry)
			if not witness.is_empty() and witness != "player" and not witness in view.witnesses and witness != str(view.participants.get("offender", "")):
				view.witnesses.append(witness)
	# Incident evidence summaries omit lens pose, framing, distance and tags.
	# They can inform case state, but only on_photo_captured may award photos.
	return view

## incident_changed(summary) bridge. Bounded; an incident-triggered case may
## start when the player is near a matching incident and no case is active.
func on_incident_event(summary) -> void:
	if not summary is Dictionary or str(summary.get("id", "")).is_empty() or str(summary.id).length() > 96:
		return
	var incident_id := str(summary.id)
	summary = incident_view(summary)
	incidents[incident_id] = summary
	while incidents.size() > INCIDENT_LIMIT:
		var oldest := ""
		for key in incidents:
			if str(key) != str(active.get("incident_id", "")):
				oldest = str(key)
				break
		if oldest.is_empty():
			break
		incidents.erase(oldest)
	if missions == null:
		return
	if not str(missions.active_id).is_empty() or not str(summary.get("state", "")) in ACTIVE_INCIDENT_STATES:
		return
	var at := Evidence._vector(summary.get("position"))
	var level = _level()
	var player = level.get("player") if level != null else null
	if player == null or not at.is_finite():
		return
	for id in order:
		var case_def: Dictionary = definitions[id]
		if case_def.discovery.trigger != "incident" or is_draft(id) or missions.completed_ids.has(id) or closed.has(id) or not requirements_met(case_def):
			continue
		if not str(summary.get("template", summary.get("kind", ""))) in case_def.incident.templates:
			continue
		if Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() > float(case_def.incident.radius):
			continue
		missions.start_incident_case(id, incident_id)
		return

# --- Ledger, details ---------------------------------------------------------------------

## Original ledger row {id, title, completed, state, reason}, original wording.
func ledger_row(id: String) -> Dictionary:
	var case_def := definition(id)
	var completed: bool = missions.completed_ids.has(id)
	var row := {"id": id, "title": str(case_def.title), "completed": completed, "state": "available", "reason": "Talk to the first contact to begin."}
	if completed:
		row.state = "completed"
		row.reason = "Resolved. Community points awarded."
		return row
	if closed.has(id):
		row.state = "closed"
		var outcome: Dictionary = case_def.outcomes.get(str(closed[id]), {})
		row.reason = str(outcome.get("notice", "")) if not str(outcome.get("notice", "")).is_empty() else "Closed without a reward."
		return row
	var is_active: bool = str(missions.active_id) == id
	var from_stage := int(missions.stage) if is_active else 0
	var found := blocker(id, from_stage, _live_record(id) if is_active else {})
	match str(found.state):
		"dead":
			row.state = "unavailable"
			row.reason = "Required contact %s has died." % str(found.label)
			return row
		"custody":
			row.state = "unavailable"
			row.reason = "Required contact %s is in police custody." % str(found.label)
			return row
		"absent":
			row.state = "unavailable"
			row.reason = "Required contact %s is not currently present." % str(found.label)
			return row
	if is_active:
		var stages: Array = case_def.stages
		row.state = "active"
		row.reason = "Step %d of %d: %s" % [from_stage + 1, stages.size(), str(stages[from_stage].objective)] if from_stage < stages.size() else "Case in progress."
	elif not requirements_met(case_def):
		row.state = "locked"
		row.reason = locked_reason(case_def)
	elif not str(missions.active_id).is_empty():
		row.reason = "Finish the current case, then speak to the first contact."
	return row

## Read-only detail for the phone Cases app and fixtures.
func case_detail(id: String = "") -> Dictionary:
	var case_id := id if not id.is_empty() else str(missions.active_id)
	var case_def := definition(case_id)
	if case_def.is_empty():
		return {}
	var live := not current_stage().is_empty() and str(active.id) == case_id
	var finished: bool = missions.completed_ids.has(case_id)
	var stages: Array = []
	for stage in case_def.stages:
		var objectives: Array = []
		for objective in stage.objectives:
			var entry := {"id": str(objective.id), "verb": str(objective.verb), "objective": str(objective.objective), "optional": bool(objective.optional),
				"done": finished or (live and _objective_done(objective))}
			if live and objective.verb == "photo":
				entry.progress = "%d/%d" % [_photo_count(objective), int(objective.count)]
			elif live and objective.verb == "follow":
				entry.progress = "%d/%d s" % [int(float(active.progress.get(objective.id, 0.0))), int(objective.seconds)]
			elif live and objective.verb == "report":
				entry.missing = Array(missing_evidence(objective))
				entry.ready = (entry.missing as Array).is_empty()
			objectives.append(entry)
		stages.append({"id": str(stage.id), "objective": str(stage.objective), "complete": str(stage.complete), "objectives": objectives})
	var evidence: Array = []
	for evidence_id in case_def.evidence:
		var held: bool = holds(str(evidence_id)) if live else (records.has(case_id) and str(evidence_id) in records[case_id].evidence)
		evidence.append({"id": str(evidence_id), "kind": str(case_def.evidence[evidence_id].kind), "label": str(case_def.evidence[evidence_id].label), "held": held})
	return {"id": case_id, "title": str(case_def.title), "version": int(case_def.version), "status": str(case_def.status), "active": live,
		"stage": int(missions.stage) if live else -1, "stage_count": case_def.stages.size(), "stages": stages, "evidence": evidence,
		"record": records.get(case_id, {}).duplicate(true), "closed": str(closed.get(case_id, "")), "incident_id": str(active.incident_id) if live else ""}

func evidence_list(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not active.is_empty() and str(active.id) == id:
		for entry in active.evidence:
			result.append(entry.duplicate(true))
	return result

# --- Persistence -------------------------------------------------------------------------

## JSON-safe and canonical (sorted maps, snapped minutes, no vectors), so
## snapshot → JSON → restore → snapshot is identical.
func snapshot() -> Dictionary:
	var state := {"version": VERSION, "active": {}, "closed": _sorted(closed), "records": {}, "seen_photos": Array(seen_photos)}
	for id in _sorted_keys(records):
		var record: Dictionary = records[id]
		state.records[str(id)] = {"outcome": str(record.outcome), "evidence": record.evidence.duplicate(), "minute": snappedf(float(record.minute), 0.01)}
	if current_stage().is_empty():
		return state
	var done := {}
	for key in _sorted_keys(active.done):
		done[str(key)] = true
	var progress := {}
	for key in _sorted_keys(active.progress):
		progress[str(key)] = snappedf(float(active.progress[key]), 0.01)
	var topics := {}
	for key in _sorted_keys(active.topics):
		topics[str(key)] = active.topics[key].duplicate()
	var photos := {}
	for key in _sorted_keys(active.photos):
		photos[str(key)] = active.photos[key].duplicate()
	var bindings := {}
	for key in _sorted_keys(active.bindings):
		bindings[str(key)] = str(active.bindings[key])
	var evidence: Array = []
	for entry in active.evidence:
		evidence.append(entry.duplicate(true))
	state.active = {"id": str(active.id), "def_version": int(active.def_version), "stage": int(missions.stage), "done": done, "progress": progress,
		"topics": topics, "evidence": evidence, "started_minute": snappedf(float(active.started_minute), 0.01), "bindings": bindings, "photos": photos,
		"carrying": active.carrying.duplicate(), "delivered": active.delivered.duplicate(), "incident_id": str(active.incident_id)}
	return state

## Pure: "" when the case_engine part of a missions section is consistent with
## it, the completed set and (optionally) the saved death registry.
func validate(section: Dictionary, completed: Dictionary, dead: Dictionary) -> String:
	var active_id := str(section.get("active_id", ""))
	var stage := int(section.get("stage", 0))
	if not section.has("case_engine"):
		return _contacts_error(active_id, stage, {}, dead)
	var data = section.case_engine
	if not data is Dictionary or not Schema._integer(data.get("version"), 1, 1000000000):
		return "invalid case engine"
	if int(data.version) > VERSION:
		return "case engine from a newer build"
	for key in data:
		if not str(key) in SECTION_KEYS:
			return "unknown case engine field"
	var closed_value = data.get("closed", {})
	var records_value = data.get("records", {})
	var seen = data.get("seen_photos", [])
	if not closed_value is Dictionary or not records_value is Dictionary or not seen is Array or seen.size() > SEEN_LIMIT:
		return "invalid case engine"
	for photo_id in seen:
		if not photo_id is String or str(photo_id).is_empty() or str(photo_id).length() > 96:
			return "invalid photo ledger"
	for id in closed_value:
		var case_def := definition(str(id))
		if case_def.is_empty() or completed.has(str(id)) or not closed_value[id] is String or active_id == str(id):
			return "invalid closed case"
		var outcome: Dictionary = case_def.outcomes.get(str(closed_value[id]), {})
		if outcome.is_empty() or bool(outcome.rewarded) or not bool(outcome.terminal):
			return "invalid closed case"
	for id in records_value:
		var case_def := definition(str(id))
		var record = records_value[id]
		if case_def.is_empty() or not record is Dictionary or not record.get("evidence") is Array or not record.get("outcome") is String \
				or not Schema._number(record.get("minute"), 0.0, 1.0e12):
			return "invalid case record"
		var outcome: Dictionary = case_def.outcomes.get(str(record.outcome), {})
		if outcome.is_empty() or not bool(outcome.terminal) or bool(outcome.rewarded) != completed.has(str(id)):
			return "case record mismatch"
		if not bool(outcome.rewarded) and str(closed_value.get(id, "")) != str(record.outcome):
			return "case record mismatch"
		for evidence_id in record.evidence:
			if not case_def.evidence.has(str(evidence_id)):
				return "unknown case evidence"
	var record = data.get("active", {})
	if not record is Dictionary:
		return "invalid active case"
	if record.is_empty():
		return _contacts_error(active_id, stage, {}, dead)
	if not owns(active_id) or str(record.get("id", "")) != active_id:
		return "active case record mismatch"
	var case_def := definition(active_id)
	if not Schema._integer(record.get("def_version"), 1, 1000000):
		return "invalid active case"
	if int(record.def_version) > int(case_def.version):
		return "active case definition from a newer build"
	if int(record.def_version) < int(case_def.version):
		# An older layout resumes by stage (begin() migrates it); only the
		# saved deaths can still make it impossible.
		return _contacts_error(active_id, stage, {}, dead)
	var problem := _record_error(case_def, record, stage)
	if not problem.is_empty():
		return problem
	return _contacts_error(active_id, stage, record, dead)

## The saved record when it fits this definition at `stage`, else {} (resume by
## stage instead: earlier stages count as done).
func usable_record(id: String, stage: int, record) -> Dictionary:
	if not record is Dictionary or record.is_empty() or str(record.get("id", "")) != id or not owns(id):
		return {}
	return record if _record_error(definition(id), record, stage).is_empty() else {}

func _contacts_error(active_id: String, stage: int, record: Dictionary, dead: Dictionary) -> String:
	if not owns(active_id) or dead.is_empty():
		return ""
	return "case requires deceased contact" if blocker(active_id, stage, record, dead).state == "dead" else ""

func _record_error(case_def: Dictionary, record: Dictionary, stage: int) -> String:
	for key in record:
		if not str(key) in ACTIVE_KEYS:
			return "unknown active case field"
	if not Schema._integer(record.get("def_version"), 1, 1000000) or int(record.def_version) > int(case_def.version):
		return "active case definition from a newer build"
	if not Schema._integer(record.get("stage"), 0, case_def.stages.size() - 1) or int(record.stage) != stage:
		return "active case stage mismatch"
	if not Schema._number(record.get("started_minute"), 0.0, 1.0e12) or not record.get("incident_id", "") is String:
		return "invalid active case"
	for key in ["done", "progress", "topics", "bindings", "photos"]:
		if not record.get(key) is Dictionary:
			return "invalid active case"
	for key in ["evidence", "carrying", "delivered"]:
		if not record.get(key) is Array:
			return "invalid active case"
	var objectives := {}
	for each in case_def.stages:
		for objective in each.objectives:
			objectives[objective.id] = objective
	for objective_id in record.done:
		if not objectives.has(objective_id) or int(objectives[objective_id].stage) > stage or record.done[objective_id] != true:
			return "invalid objective progress"
	for objective_id in record.progress:
		if not objectives.has(objective_id) or not Schema._number(record.progress[objective_id], -1.0e9, 1.0e12):
			return "invalid objective progress"
	for objective_id in record.topics:
		if not objectives.has(objective_id) or objectives[objective_id].verb != "interview" or not record.topics[objective_id] is Array:
			return "invalid interview progress"
		var known := {}
		for topic in objectives[objective_id].topics:
			known[str(topic.id)] = true
		var seen := {}
		for topic_id in record.topics[objective_id]:
			if not known.has(str(topic_id)) or seen.has(str(topic_id)):
				return "invalid interview progress"
			seen[str(topic_id)] = true
	for objective_id in record.photos:
		if not objectives.has(objective_id) or objectives[objective_id].verb != "photo" or not record.photos[objective_id] is Array \
				or record.photos[objective_id].size() > int(objectives[objective_id].count):
			return "invalid photo progress"
	for role in record.bindings:
		if not case_def.participants.has(str(role)) or not record.bindings[role] is String or not Schema._matches(str(record.bindings[role]), Schema.ACTOR_PATTERN):
			return "invalid case binding"
	var granted := {}
	for entry in record.evidence:
		if not entry is Dictionary or not case_def.evidence.has(str(entry.get("id", ""))) or granted.has(str(entry.get("id", ""))):
			return "invalid case evidence"
		for key in entry:
			if not str(key) in EVIDENCE_KEYS:
				return "invalid case evidence"
		if not Schema._number(entry.get("minute"), 0.0, 1.0e12) or not entry.get("source") is String:
			return "invalid case evidence"
		var objective_id := str(entry.get("objective", ""))
		if str(entry.source) != "migrated" and (not objectives.has(objective_id) or not record.done.has(objective_id) or not str(entry.id) in objectives[objective_id].grants):
			return "evidence without its objective"
		granted[str(entry.id)] = true
	for key in ["carrying", "delivered"]:
		for prop in record[key]:
			if not case_def.props.has(str(prop)):
				return "invalid carried item"
	return ""

## Restores the ledgers and holds the saved active record for begin(). False
## (and nothing kept) when the section is malformed.
func restore_ledgers(data) -> bool:
	closed.clear()
	records.clear()
	seen_photos.clear()
	_restore_record = {}
	if data == null:
		return true
	if not data is Dictionary:
		return false
	var clean := true
	var closed_value = data.get("closed", {})
	if closed_value is Dictionary:
		for id in closed_value:
			if owns(str(id)) and closed_value[id] is String and definition(str(id)).outcomes.has(str(closed_value[id])):
				closed[str(id)] = str(closed_value[id])
			else:
				clean = false
	else:
		clean = false
	var records_value = data.get("records", {})
	if records_value is Dictionary:
		for id in records_value:
			var record = records_value[id]
			if owns(str(id)) and record is Dictionary and record.get("evidence") is Array and Schema._number(record.get("minute"), 0.0, 1.0e12):
				var evidence: Array = []
				for evidence_id in record.evidence:
					evidence.append(str(evidence_id))
				records[str(id)] = {"outcome": str(record.get("outcome", "")), "evidence": evidence, "minute": snappedf(float(record.minute), 0.01)}
			else:
				clean = false
	else:
		clean = false
	var seen = data.get("seen_photos", [])
	if seen is Array:
		for photo_id in seen:
			if photo_id is String and not str(photo_id).is_empty() and str(photo_id).length() <= 96 and seen_photos.size() < SEEN_LIMIT:
				seen_photos.append(str(photo_id))
	var record = data.get("active", {})
	if record is Dictionary and not record.is_empty():
		_restore_record = record.duplicate(true)
	return clean

func restore_record() -> Dictionary:
	return _restore_record

func clear_restore() -> void:
	_restore_record = {}

## Typed copy of a validated saved record (JSON numbers → int/float, no vectors).
func _sanitize_record(case_def: Dictionary, saved: Dictionary, stage: int) -> Dictionary:
	var record := _fresh_record(case_def)
	record.def_version = int(case_def.version)
	record.stage = stage
	for key in saved.done:
		record.done[str(key)] = true
	for key in saved.progress:
		record.progress[str(key)] = snappedf(float(saved.progress[key]), 0.01)
	for key in saved.topics:
		var topics: Array = []
		for topic in saved.topics[key]:
			topics.append(str(topic))
		record.topics[str(key)] = topics
	for key in saved.photos:
		var photos: Array = []
		for photo in saved.photos[key]:
			photos.append(str(photo))
		record.photos[str(key)] = photos
	for key in saved.bindings:
		record.bindings[str(key)] = str(saved.bindings[key])
	for entry in saved.evidence:
		var copy := {}
		for key in entry:
			var value = entry[key]
			match str(key):
				"minute", "distance":
					copy[str(key)] = snappedf(float(value), 0.01)
				"position":
					if value is Array and value.size() == 3:
						copy[str(key)] = [snappedf(float(value[0]), 0.01), snappedf(float(value[1]), 0.01), snappedf(float(value[2]), 0.01)]
				"topics", "photos":
					var items: Array = []
					if value is Array:
						for item in value:
							items.append(str(item))
					copy[str(key)] = items
				_:
					copy[str(key)] = str(value)
		record.evidence.append(copy)
	for prop in saved.carrying:
		record.carrying.append(str(prop))
	for prop in saved.delivered:
		record.delivered.append(str(prop))
	record.started_minute = snappedf(float(saved.started_minute), 0.01)
	record.incident_id = str(saved.get("incident_id", ""))
	return record

## World-save death cross-check: candidate ids whose deaths make the saved case
## impossible (every one of them is in `dead`), else [].
func required_contacts(active_id: String, stage: int, record: Dictionary, dead: Array) -> Array:
	var result: Array = []
	if not owns(active_id) or dead.is_empty():
		return result
	var gone := {}
	for id in dead:
		gone[str(id)] = true
	var found := blocker(active_id, stage, record, gone)
	if found.state != "dead" or str(found.role).is_empty():
		return result
	for person in _people(definition(active_id), str(found.role), record):
		result.append(str(person))
	return result

static func _sorted_keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return keys

static func _sorted(source: Dictionary) -> Dictionary:
	var result := {}
	for key in _sorted_keys(source):
		result[str(key)] = source[key]
	return result
