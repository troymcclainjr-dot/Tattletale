class_name CityMissions
extends Node3D
## Fictional, local cases. No original-block crime state or coordinates are used.
## The six cases below are unchanged. city_narrative.gd adds the short
## "Petal Pushers" chain and repeatable errands through the same active-case,
## conversation, ledger and checkpoint paths. city_case_engine.gd runs data
## cases (res://assets/data/cases/) through those paths too; a data file with an
## original id (parcel_report) replaces that case's authored steps below, which
## stay as the fallback when the data does not validate.

const Narrative := preload("res://scripts/city/city_narrative.gd")
const CaseEngine := preload("res://scripts/city/city_case_engine.gd")

signal changed
signal notice(text: String)
## Data cases (cases-contract.md §2). Evidence and reports are emitted once each.
signal evidence_recorded(case_id: String, evidence: Dictionary)
signal report_filed(case_id: String, report: Dictionary)
signal case_resolved(case_id: String, outcome: Dictionary)

const CASES := [
	{"id": "lost_satchel", "title": "Lost satchel", "reward": 100},
	{"id": "parcel_report", "title": "The opened parcel", "reward": 150},
	{"id": "dumping", "title": "Keep the sidewalk clear", "reward": 175},
	{"id": "missing_tools", "title": "The missing garden tools", "reward": 125},
	{"id": "torn_notice", "title": "The torn watch notice", "reward": 140},
	{"id": "porch_light", "title": "A light out on the block", "reward": 160},
]
const EXTRA_CONTACTS := {"gardener": "missing_tools", "organizer": "torn_notice", "caretaker": "porch_light"}
const INTERACT_RADIUS := 2.4

var level: Node3D
var npcs: Node3D
var active_id := ""
var stage := 0
var score := 0
var completed_ids: Dictionary = {}
var _steps: Array[Dictionary] = []
var _clue_position := Vector3.ZERO
var _clue: Node3D
var _clue_body: StaticBody3D
var _case_root: Node3D
var _carried: Node3D
var _clue_tag: Label3D
var _cleanup_tag: Label3D
var _effects: Array[Dictionary] = []
var narrative: Narrative = Narrative.new()
var cases: CaseEngine = CaseEngine.new()
var _last_target := Vector3.ZERO
var _restoring := false
var _start_incident := ""

func _init() -> void:
	narrative.setup(self)
	cases.setup(self)

func _exit_tree() -> void:
	cases.release_phone()

func setup(owner_level: Node3D, actors: Node3D) -> void:
	level = owner_level
	npcs = actors
	name = "NeighborhoodCases"

func _available_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if npcs == null:
		return offers
	for contact in ["resident", "lookout", "gardener", "organizer", "caretaker"]:
		var id: String = str(EXTRA_CONTACTS.get(contact, "dumping" if contact == "lookout" else ("lost_satchel" if not completed_ids.has("lost_satchel") else "parcel_report")))
		# A migrated original is offered by the data engine (same id, same hook).
		if completed_ids.has(id) or npcs.get_actor(contact) == null or cases.owns(id):
			continue
		if _has_dead_contact(id) or not _custody_contact(id).is_empty():
			continue
		for entry in CASES:
			if entry.id == id:
				offers.append({"id": id, "title": entry.title, "actor_id": contact, "position": npcs.actor_position(contact)})
	offers.append_array(cases.offers())
	return offers

func _has_dead_contact(id: String, from_stage := 0) -> bool:
	if cases.owns(id):
		return cases.has_dead_contact(id, from_stage)
	var steps := case_steps(id)
	for index in range(from_stage, steps.size()):
		var target := str(steps[index].target)
		if target == "clue":
			continue
		var actor = npcs.get_actor(target)
		if actor != null and actor.get_meta("city_dead", false):
			return true
	return false

func _custody_contact(id: String, from_stage := 0) -> String:
	if cases.owns(id):
		return cases.custody_blocker(id, from_stage)
	if narrative.owns(id):
		return narrative.custody_blocker(id, from_stage)
	var steps := case_steps(id)
	for index in range(maxi(0, from_stage), steps.size()):
		var target := str(steps[index].target)
		if target != "clue" and narrative.is_contact_in_custody(target):
			return narrative.name_for(target)
	return ""

func on_actor_died(id: String) -> void:
	# Story/errand contacts get a living stand-in, a pause or a closed chain.
	narrative.on_actor_died(id)
	# Data cases: a listed stand-in takes over, else the attempt ends unpaid.
	cases.on_actor_died(id)
	if active_id.is_empty() or narrative.owns(active_id) or cases.owns(active_id):
		return
	for index in range(stage, _steps.size()):
		if str(_steps[index].target) == id:
			cancel_case()
			notice.emit("Case closed without a reward: a required contact has died.")
			return

func nearby_offer() -> Dictionary:
	if not active_id.is_empty():
		return {}
	var nearest: Dictionary = {}
	var distance := INF
	for offer in _available_offers():
		var at: Vector3 = offer.position
		var metres: float = level.player.global_position.distance_to(at)
		if metres < distance and _can_interact(at):
			nearest = offer
			distance = metres
	return nearest


func start_case(id: String) -> bool:
	return _start_case_at(id, 0)

func _start_case_at(id: String, resume_stage: int) -> bool:
	if level == null or npcs == null or completed_ids.has(id):
		return false
	if not _custody_contact(id, resume_stage).is_empty():
		return false
	# Story order, errand cooldown and stand-in availability (offers, auto-start
	# and checkpoint restore all pass through this gate).
	if narrative.owns(id) and not narrative.can_start(id, resume_stage, _restoring):
		return false
	if cases.owns(id):
		return _start_data_case(id, resume_stage)
	var placement := _prepare_case(id, resume_stage)
	if placement.is_empty():
		notice.emit("A contact or clear sidewalk location for this case is unavailable. Try another case or keep exploring.")
		return false
	cancel_case()
	active_id = id
	_clue_position = placement.position
	_case_root = Node3D.new()
	_case_root.name = "FictionalCase_" + id
	add_child(_case_root)
	_clue = Node3D.new()
	_clue.position = _clue_position
	_case_root.add_child(_clue)
	_steps = case_steps(id)
	match id:
		"lost_satchel":
			_satchel(_clue)
			_make_body(Vector3(0.48, 0.43, 0.3), Vector3(0, 0.215, 0))
		"parcel_report":
			_parcel(_clue)
			_make_body(Vector3(0.7, 0.38, 0.44), Vector3(0, 0.19, 0))
		"dumping":
			_dumped_bags(_clue)
			_make_body(Vector3(0.9, 0.7, 0.6), Vector3(0, 0.35, 0))
		"missing_tools":
			_tool_caddy(_clue)
			_make_body(Vector3(0.5, 0.6, 0.32), Vector3(0, 0.3, 0))
		"torn_notice":
			_torn_notice(_clue)
			_make_body(Vector3(0.75, 0.05, 0.5), Vector3(0, 0.025, 0))
		"porch_light":
			_lantern(_clue)
			_make_body(Vector3(0.38, 0.42, 0.35), Vector3(0, 0.21, 0))
	if narrative.owns(id):
		_build_story_props(id, resume_stage)
	var clue_titles := {"lost_satchel": "BLUE SATCHEL", "parcel_report": "OPENED PARCEL", "dumping": "DUMPED BAGS", "missing_tools": "GARDEN TOOL CADDY", "torn_notice": "TORN WATCH NOTICE", "porch_light": "DAMAGED LANTERN"}
	if not narrative.owns(id) or narrative.has_clue(id, resume_stage):
		_clue_tag = _tag(_clue, str(clue_titles.get(id, narrative.clue_title(id))), 0.95)
	_update_clue_tags()
	narrative.on_case_started(id)
	changed.emit()
	notice.emit(narrative.start_notice(id) if narrative.owns(id) else "New case: " + _title() + ". Follow the case marker; press E at each step.")
	return true

## Same gates and order as the original path: refuse before changing anything,
## then replace the live case. Restores hand the saved record to the engine.
func _start_data_case(id: String, resume_stage: int) -> bool:
	if not cases.can_start(id, resume_stage, _restoring):
		return false
	var placement: Dictionary = cases.prepare(id, resume_stage, cases.usable_record(id, resume_stage, cases.restore_record()) if _restoring else {})
	if placement.is_empty():
		notice.emit("A contact or clear sidewalk location for this case is unavailable. Try another case or keep exploring.")
		return false
	var incident_id := _start_incident
	cancel_case()
	active_id = id
	_clue_position = placement.position
	_last_target = placement.position
	_case_root = Node3D.new()
	_case_root.name = "FictionalCase_" + id
	add_child(_case_root)
	cases.begin(id, resume_stage, placement, _restoring, incident_id)
	_steps = case_steps(id)
	narrative.on_case_started(id)
	changed.emit()
	var start_text := str(cases.definition(id).discovery.start_notice)
	notice.emit(start_text if not start_text.is_empty() else "New case: " + _title() + ". Follow the case marker; press E at each step.")
	return true

## Clue props for story/errand ids (solid unless flat), plus anything carried
## from the start. Uses the same clay helpers as the original cases.
func _build_story_props(id: String, resume_stage: int) -> void:
	if narrative.has_clue(id, resume_stage):
		match narrative.prop_kind(id):
			"checkpoint":
				_box(_clue, Vector3(0.44, 0.02, 0.44), Vector3(0, 0.01, 0), "#2f4f6e")
				_box(_clue, Vector3(0.3, 0.024, 0.3), Vector3(0, 0.012, 0), "#d7c6a0")
				_make_body(Vector3(0.44, 0.03, 0.44), Vector3(0, 0.015, 0))
			"crate":
				_soda_crate(_clue)
				_make_body(Vector3(0.48, 0.36, 0.34), Vector3(0, 0.18, 0))
	if narrative.carries_from_start(id):
		_carry(narrative.prop_kind(id))

func _carry(kind: String) -> void:
	if is_instance_valid(_carried) or not is_instance_valid(_case_root):
		return
	_carried = Node3D.new()
	_case_root.add_child(_carried)
	match kind:
		"parcel":
			_box(_carried, Vector3(0.36, 0.26, 0.3), Vector3(0, 0.13, 0), "#b8925a")
			_box(_carried, Vector3(0.37, 0.03, 0.08), Vector3(0, 0.25, 0), "#c8b080")
		"bouquet":
			_box(_carried, Vector3(0.16, 0.34, 0.12), Vector3(0, 0.17, 0), "#4f7a3a")
			for bloom in [Vector3(-0.06, 0.38, 0), Vector3(0.06, 0.4, 0.02), Vector3(0, 0.44, -0.03)]:
				Prim.M(Prim.sph(0.07, 10, 8), ClayLib.clay("#e3b52f"), bloom.x, bloom.y, bloom.z, _carried)
		_:
			_soda_crate(_carried)
	_carried.scale = Vector3.ONE * 0.65
	_update_carried()

func _soda_crate(parent: Node3D) -> void:
	_box(parent, Vector3(0.46, 0.2, 0.32), Vector3(0, 0.1, 0), "#b03a2e")
	for x in [-0.15, -0.05, 0.05, 0.15]:
		for z in [-0.08, 0.08]:
			Prim.M(Prim.cyl(0.03, 0.03, 0.14, 8), ClayLib.clay("#d9dcd6"), x, 0.27, z, parent)

func _torn_notice(parent: Node3D) -> void:
	_box(parent, Vector3(0.55, 0.035, 0.4), Vector3(0, 0.025, 0), "#d7c6a0")
	_box(parent, Vector3(0.24, 0.045, 0.3), Vector3(0.3, 0.03, 0.08), "#e5d7b5")
	_box(parent, Vector3(0.3, 0.008, 0.04), Vector3(0, 0.049, 0), "#496372")

func _lantern(parent: Node3D) -> void:
	_box(parent, Vector3(0.32, 0.08, 0.3), Vector3(0, 0.04, 0), "#343d40")
	_box(parent, Vector3(0.22, 0.3, 0.2), Vector3(0, 0.23, 0), "#b3aa85")
	_box(parent, Vector3(0.025, 0.27, 0.22), Vector3(0.03, 0.23, 0), "#3b3831")

## Data-case props reuse the original clue models. Returns the solid footprint
## the original case gave that model: {"size", "center"}.
func build_case_prop(builder: String, parent: Node3D) -> Dictionary:
	match builder:
		"satchel":
			_satchel(parent)
			return {"size": Vector3(0.48, 0.43, 0.3), "center": Vector3(0, 0.215, 0)}
		"parcel":
			_parcel(parent)
			return {"size": Vector3(0.7, 0.38, 0.44), "center": Vector3(0, 0.19, 0)}
		"dumped_bags":
			_dumped_bags(parent)
			return {"size": Vector3(0.9, 0.7, 0.6), "center": Vector3(0, 0.35, 0)}
		"tool_caddy":
			_tool_caddy(parent)
			return {"size": Vector3(0.5, 0.6, 0.32), "center": Vector3(0, 0.3, 0)}
		"torn_notice":
			_torn_notice(parent)
			return {"size": Vector3(0.75, 0.05, 0.5), "center": Vector3(0, 0.025, 0)}
		"lantern":
			_lantern(parent)
			return {"size": Vector3(0.38, 0.42, 0.35), "center": Vector3(0, 0.21, 0)}
		"checkpoint":
			_box(parent, Vector3(0.44, 0.02, 0.44), Vector3(0, 0.01, 0), "#2f4f6e")
			_box(parent, Vector3(0.3, 0.024, 0.3), Vector3(0, 0.012, 0), "#d7c6a0")
			return {"size": Vector3(0.44, 0.03, 0.44), "center": Vector3(0, 0.015, 0)}
		"crate":
			_soda_crate(parent)
			return {"size": Vector3(0.48, 0.36, 0.34), "center": Vector3(0, 0.18, 0)}
	# "marker": a flat ring for places that matter without an object.
	_ring(parent, Color("70e0da"))
	return {"size": Vector3(0.3, 0.05, 0.3), "center": Vector3(0, 0.025, 0)}


## Read-only placement check; callers can refuse a restore before any state changes.
func preflight_restore(state: Dictionary) -> bool:
	var id := str(state.get("active_id", ""))
	# A durable arrest may postdate this checkpoint. Restore its earned progress
	# but drop the unavailable active attempt instead of refusing the whole save.
	if not _custody_contact(id, int(state.get("stage", 0))).is_empty():
		return true
	if cases.owns(id):
		var from_stage := int(state.get("stage", 0))
		return not cases.prepare(id, from_stage, cases.usable_record(id, from_stage, _saved_record(state))).is_empty()
	return id.is_empty() or not _prepare_case(id, int(state.get("stage", 0))).is_empty()

## The saved data-case record of a missions section, {} when absent.
func _saved_record(state: Dictionary) -> Dictionary:
	var engine = state.get("case_engine", {})
	var record = engine.get("active", {}) if engine is Dictionary else {}
	return record if record is Dictionary and str(record.get("id", "")) == str(state.get("active_id", "")) else {}

func _prepare_case(id: String, from_stage := 0) -> Dictionary:
	if level == null or npcs == null:
		return {}
	if cases.owns(id):
		return cases.prepare(id, from_stage)
	var known := narrative.owns(id)
	for entry in CASES:
		known = known or entry.id == id
	if not known:
		return {}
	var required: Array[String] = []
	var steps := case_steps(id)
	for index in range(from_stage, steps.size()):
		# Story tokens resolve to their first living stand-in; case ids are unchanged.
		var target := narrative.resolve(str(steps[index].target), id)
		if target.is_empty():
			return {}
		if target != "clue" and target not in required:
			required.append(target)
	for actor_id in required:
		var actor_location: Vector3 = npcs.actor_position(str(actor_id))
		if not actor_location.is_finite():
			return {}
	if narrative.owns(id) and not narrative.has_clue(id, from_stage):
		# Nothing to place; anchor the empty clue node at the first contact.
		var anchor: Vector3 = npcs.actor_position(required[0]) if not required.is_empty() else Vector3.ZERO
		return {"ok": true, "position": anchor}
	# Find space before replacing a live case, so a placement failure loses no progress.
	var distance := 35.0 if id == "lost_satchel" else (55.0 if id == "parcel_report" else 155.0)
	if id == "missing_tools":
		distance = 88.0
	elif id == "torn_notice":
		distance = 137.0
	elif id == "porch_light":
		distance = 181.0
	elif narrative.owns(id):
		distance = narrative.placement_distance(id)
	var radius := 0.55 if id == "dumping" else (0.42 if id == "parcel_report" else 0.32)
	return place_on_route(distance, radius)

## Read-only clue placement `metres` along the walk. Dense porch approaches and
## police beats can fill a whole short block, so it searches farther along the
## walk before giving up, keeping exactly the same capsule, pavement, route and
## stair-clearance requirements at every spot. {} when nothing is clear.
func place_on_route(metres: float, radius: float, tolerance := 2.2) -> Dictionary:
	if level == null or npcs == null:
		return {}
	for offset in [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0, 32.0, -32.0, 48.0, -48.0, 64.0, -64.0, 96.0, -96.0]:
		var placement: Dictionary = npcs.find_safe_position(_route_point(metres + offset), radius)
		if bool(placement.get("ok", false)) and _route_distance(placement.position) <= tolerance:
			return placement
	return {}

## Single authored source for gameplay steps and persistence stage limits. A
## data case (cases.owns) supplies one entry per stage.
func case_steps(id: String) -> Array[Dictionary]:
	if cases.owns(id):
		return cases.steps(id)
	var authored := legacy_steps(id)
	if not authored.is_empty():
		return authored
	if narrative.owns(id):
		return narrative.steps(id)
	return []

## The six original cases exactly as authored (also the data-migration fallback).
func legacy_steps(id: String) -> Array[Dictionary]:
	match id:
		"lost_satchel":
			return [
				_step("resident", "Ask the resident about the missing satchel", "E  Ask about the satchel", "That blue satchel is mine. Look for a brass clasp, then bring it back to me."),
				_step("clue", "Find the blue satchel along Old York Road", "E  Pick up the blue satchel", "Blue fabric, brass clasp. This matches the resident's description."),
				_step("resident", "Return the satchel to its owner", "E  Return the satchel", "That's it! Everything is still inside. Thank you for bringing it back."),
			]
		"parcel_report":
			return [
				_step("resident", "Ask the resident about an opened delivery", "E  Ask about the delivery", "My delivery is missing. There may be some packing material farther up Old York. Please check before reporting anything."),
				_step("clue", "Inspect the opened parcel on Old York Road", "E  Inspect the packing label", "The empty carton has the resident's delivery label. Record the location; leave the evidence here."),
				_step("lookout", "Ask the witness at Dumbarton what happened", "E  Ask the witness", "I saw someone remove a parcel from that doorstep. I couldn't identify them. Tell the officer exactly that."),
				_step("officer", "Report the evidence to the officer near Wyanoke", "E  File the parcel report", "I'll record the missing delivery and the witness account. We will investigate; a report is not proof of who took it."),
			]
		"dumping":
			return [
				_step("lookout", "Ask the Dumbarton witness about dumped waste", "E  Ask about the waste", "Someone left bags beside the sidewalk toward Rose Hill. Please record where they are and tell the officer."),
				_step("clue", "Inspect the dumped bags near Rose Hill", "E  Record the dumped waste", "Three dumped bags, beside the walking route. Location and description recorded. Do not open them."),
				_step("officer", "Report the dumped waste to the officer", "E  Request a cleanup", "The location is logged. A cleanup team will remove the bags. Please check that the spot is clear afterward."),
				_step("clue", "Return to Rose Hill and confirm the cleanup", "E  Confirm the cleared site", "The bags are gone and the sidewalk is clear. Cleanup confirmed."),
			]
		"missing_tools":
			return [
				_step("gardener", "Ask the gardener about the missing tools", "E  Ask about the garden tools", "Our green tool caddy vanished after the planting day. The mail carrier passed here; could you ask what they saw?"),
				_step("ambient_mailman", "Ask the mail carrier where the caddy went", "E  Ask about the green caddy", "A volunteer set a green caddy farther along Old York while carrying a planter. I saw no theft. Check beside the walk."),
				_step("clue", "Recover the green garden caddy along Old York", "E  Recover the garden tools", "The caddy still holds the hand tools, marked for the community garden. Bring it back."),
				_step("gardener", "Return the tools and clear up the misunderstanding", "E  Return the garden tools", "All accounted for! I'm glad we checked instead of accusing somebody. We can finish planting now."),
			]
		"torn_notice":
			return [
				_step("organizer", "Ask the organizer about the damaged watch notice", "E  Ask about the torn notice", "Our neighborhood watch meeting notice was torn down. Please inspect the pieces, then ask the witness before we report vandalism."),
				_step("clue", "Inspect the torn notice beside the sidewalk", "E  Inspect the notice pieces", "The paper is rain-soaked and split around a rusty fastening. Nothing here identifies a person."),
				_step("lookout", "Ask the Dumbarton witness what happened to the notice", "E  Ask about the fallen notice", "The wind pulled it loose in the rain. I saw it happen. Nobody tore it down."),
				_step("organizer", "Share the evidence and arrange a weatherproof replacement", "E  Resolve the notice report", "Weather damage, then. I'll put up a covered notice. Thanks for checking the facts and keeping the meeting on track."),
			]
		"porch_light":
			return [
				_step("caretaker", "Ask the caretaker about the damaged porch light", "E  Ask about the porch light", "I found our porch lantern cracked. I've disconnected it and set it beside the walk. Could you record the damage? The dark entrance worries our neighbors."),
				_step("clue", "Inspect the disconnected lantern near Cator", "E  Record the damaged lantern", "The disconnected lantern has a cracked shade. Record the damage and the dark entrance; the cause is unknown. Leave it for the caretaker."),
				_step("officer", "Report the damage without naming a suspect", "E  Report the damaged light", "I'll record the damage, with the cause unknown. Ask the caretaker to restore the light so the entrance is visible again."),
				_step("caretaker", "Confirm the porch light repair is arranged", "E  Confirm the repair", "The replacement is ready and the repair is scheduled before dark. Thank you for looking out for the block."),
			]
	return []

## The six original cases first and in order, then story parts and errands,
## then data cases outside the original slots. Errands may be active but never
## completed (they repeat).
func save_schema() -> Dictionary:
	var schema := {}
	for entry in CASES:
		schema[entry.id] = {"reward": int(entry.reward), "stages": case_steps(str(entry.id)).size(), "kind": "case"}
	schema.merge(narrative.schema())
	schema.merge(cases.schema())
	return schema

func _completed_case_count() -> int:
	var count := 0
	for entry in CASES:
		count += int(completed_ids.has(entry.id))
	for id in cases.extra_ids():
		count += int(completed_ids.has(id))
	return count

## Every original case and ready data case is resolved.
func all_cases_complete() -> bool:
	return _completed_case_count() == CASES.size() + cases.extra_ids().size()

func case_title(id: String) -> String:
	for entry in CASES:
		if entry.id == id:
			return str(entry.title)
	if cases.owns(id):
		return cases.title(id)
	return narrative.title(id) if narrative.owns(id) else id


func cancel_case() -> void:
	cases.on_cancelled()
	if is_instance_valid(_case_root):
		# Disable collision immediately; queue_free completes at the frame boundary.
		if is_instance_valid(_clue_body):
			_clue_body.collision_layer = 0
		_case_root.queue_free()
	_case_root = null
	_clue = null
	_clue_body = null
	_carried = null
	_clue_tag = null
	_cleanup_tag = null
	_steps.clear()
	active_id = ""
	stage = 0
	changed.emit()


func _step(target: String, objective: String, prompt: String, dialogue: String) -> Dictionary:
	return {"target": target, "objective": objective, "prompt": prompt, "dialogue": dialogue}


## Derived from the current checkpoint only; no invented cancelled/lost history.
func case_ledger() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	var names := {"resident": "Resident", "lookout": "Dumbarton witness", "officer": "Officer", "gardener": "Gardener", "organizer": "Organizer", "caretaker": "Caretaker", "ambient_mailman": "Mail carrier"}
	var combat: Node = level.get("combat") if level != null else null
	for entry in CASES:
		var id := str(entry.id)
		if cases.owns(id):
			var row := cases.ledger_row(id)
			row.title = entry.title
			catalog.append(row)
			continue
		var completed := completed_ids.has(id)
		var state := "completed" if completed else ("active" if active_id == id else "available")
		var reason := "Resolved. Community points awarded." if completed else "Talk to the first contact to begin."
		if not completed:
			var steps := case_steps(id)
			var start := stage if active_id == id else 0
			var missing := ""
			for index in range(start, steps.size()):
				var target := str(steps[index].target)
				if target == "clue":
					continue
				var actor: Node = npcs.get_actor(target) if npcs != null else null
				if narrative.is_contact_in_custody(target):
					state = "unavailable"
					reason = "Required contact %s is in police custody." % str(names.get(target, target))
					break
				var dead: bool = combat != null and combat.is_actor_dead(target)
				if dead or (actor != null and actor.get_meta("city_dead", false)):
					state = "unavailable"
					reason = "Required contact %s has died." % str(names.get(target, target))
					break
				if actor == null and missing.is_empty():
					missing = str(names.get(target, target))
			if state != "unavailable" and not missing.is_empty():
				state = "unavailable"
				reason = "Required contact %s is not currently present." % missing
			elif state == "active":
				reason = "Step %d of %d: %s" % [stage + 1, steps.size(), str(steps[stage].objective)] if stage < steps.size() else "Case in progress."
			elif state == "available" and id == "parcel_report" and not completed_ids.has("lost_satchel"):
				state = "locked"
				reason = "Resolve Lost satchel first."
			elif state == "available" and not active_id.is_empty():
				reason = "Finish the current case, then speak to the first contact."
		catalog.append({"id": id, "title": entry.title, "completed": completed, "state": state, "reason": reason})
	for id in cases.extra_ids():
		catalog.append(cases.ledger_row(id))
	return catalog


## cases/offers/completed/total/all_complete describe the six original cases
## (plus any ready data case outside their slots); story parts and errands
## report through story/errand/story_offer. A data case adds case_detail.
func get_status() -> Dictionary:
	var catalog := case_ledger()
	var finished := _completed_case_count()
	var total := CASES.size() + cases.extra_ids().size()
	var status := {"active_id": active_id, "title": _title(), "objective": "Walk the neighborhood. Talk to people who need a hand.", "prompt": "", "target_position": Vector3.ZERO, "stage": stage, "stage_count": _steps.size(), "completed": finished, "total": total, "score": score, "cases": catalog, "offers": _available_offers()}
	status.all_complete = finished == total
	if status.all_complete:
		status.objective = "All neighborhood cases resolved. Keep exploring Baltimore."
	if not active_id.is_empty() and stage < _steps.size() and cases.owns(active_id):
		var focus := cases.target_position()
		# An absent contact keeps the marker on the last real destination.
		if focus.is_finite():
			_last_target = focus
		status.target_position = _last_target
		status.objective = cases.objective_text()
		status.prompt = cases.prompt()
		status.case_detail = cases.case_detail(active_id)
	elif not active_id.is_empty() and stage < _steps.size():
		var target := _target_position()
		var owned := narrative.owns(active_id)
		status.objective = narrative.objective(active_id, _steps[stage]) if owned else _steps[stage].objective
		if owned:
			# A stand-in may take a moment to resolve after a restored death; keep
			# the marker on the last real destination instead of infinity.
			if target.is_finite():
				_last_target = target
			status.target_position = _last_target
		else:
			status.target_position = target
		status.prompt = _steps[stage].prompt if _can_interact(target) else ""
	else:
		var offer := nearby_offer()
		status.nearby_offer = offer
		if not offer.is_empty():
			status.prompt = "E  Talk about " + str(offer.title).to_lower()
		else:
			var extra := narrative.nearest_offer()
			status.story_offer = extra
			if not extra.is_empty():
				status.prompt = "E  Talk about " + str(extra.title).to_lower()
	status.story = narrative.ledger()
	status.errand = narrative.errand_summary()
	return status


## Pure preview: opening/closing a conversation never starts a case or awards progress.
func conversation_preview() -> Dictionary:
	var names := {"resident": "Resident", "lookout": "Dumbarton witness", "officer": "Officer", "gardener": "Gardener", "organizer": "Organizer", "caretaker": "Caretaker", "ambient_mailman": "Mail carrier", "clue": "2-Pack"}
	if active_id.is_empty():
		var offer := nearby_offer()
		if offer.is_empty():
			# Story and errand offers only where no original case is offered.
			return narrative.offer_conversation()
		if cases.owns(str(offer.id)):
			return cases.offer_conversation(offer)
		return {"actor_id": str(offer.actor_id), "start": "start", "nodes": {"start": {"speaker": names.get(str(offer.actor_id), "Neighbor"), "lines": ["Could you help with something on the block?"], "choices": [{"text": "Tell me about " + str(offer.title).to_lower() + ".", "hook": {"kind": "start_case", "id": str(offer.id)}}, {"text": "Maybe later."}]}}}
	if cases.owns(active_id):
		return cases.conversation_preview()
	if stage >= _steps.size() or not _can_interact(_target_position()):
		return {}
	var action: Dictionary = _steps[stage]
	if narrative.owns(active_id):
		return narrative.step_conversation(active_id, stage, action)
	return {"actor_id": str(action.target), "start": "start", "nodes": {"start": {"speaker": names.get(str(action.target), "Neighbor"), "lines": [str(action.dialogue)], "choices": [{"text": str(action.prompt).trim_prefix("E  "), "hook": {"kind": "case_step", "id": active_id, "stage": stage}}, {"text": "I'll come back."}]}}}

## Recheck both range and revision so stale/duplicate choice callbacks cannot grant rewards.
func commit_dialogue_action(action: Dictionary) -> bool:
	match str(action.get("kind", "")):
		"start_case":
			var offer := nearby_offer()
			return not offer.is_empty() and str(offer.id) == str(action.get("id", "")) and start_case(str(offer.id))
		"case_step", "case_interview", "case_report":
			if active_id != str(action.get("id", "")) or stage != int(action.get("stage", -1)):
				return false
			if cases.owns(active_id):
				return cases.commit(action)
			if str(action.kind) != "case_step":
				return false
			return _commit_step(str(action.get("choice", "")))
		"story_start", "errand_start":
			return active_id.is_empty() and nearby_offer().is_empty() and narrative.commit_offer(action)
	return false

func interact() -> bool:
	return _commit_step("")

## One range-checked step. A story decision step needs `choice`, committed to
## progression before the stage moves; any refusal leaves everything unchanged.
func _commit_step(choice: String) -> bool:
	if active_id.is_empty():
		return false
	if cases.owns(active_id):
		return choice.is_empty() and cases.interact()
	if stage >= _steps.size():
		return false
	var target := _target_position()
	if not _can_interact(target):
		return false
	var action: Dictionary = _steps[stage]
	var line := str(action.dialogue)
	if narrative.owns(active_id):
		var accepted := narrative.accept_step(active_id, action, choice)
		if not bool(accepted.ok):
			return false
		if not str(accepted.line).is_empty():
			line = str(accepted.line)
	elif not choice.is_empty():
		return false
	if str(action.target) != "clue":
		npcs.speak(narrative.resolve(str(action.target), active_id), line, 6.0)
	notice.emit(line)
	_apply_step_visuals(stage)
	stage += 1
	_update_clue_tags()
	if stage >= _steps.size():
		_complete(target)
	else:
		changed.emit()
	return true


## "case_engine" (data cases: active record, outcome ledgers, photo replay ring)
## is optional on restore: older sections without it migrate.
func snapshot_state() -> Dictionary:
	return {"active_id": active_id, "stage": stage, "completed_ids": completed_ids.keys(), "score": score, "case_engine": cases.snapshot()}

## Restore state without replaying dialogue actions, signals or reward commits.
## The world-save provider validates IDs, stage and derived score first.
## Progression must already be restored: story parts are checked against its
## durable choices, and an inconsistent story is dropped and reported (false)
## so the provider keeps the checkpoint instead of overwriting it.
func restore_state(state: Dictionary) -> bool:
	set_block_signals(true)
	cancel_case()
	completed_ids.clear()
	score = 0
	var restored := true
	var saved = state.get("completed_ids", [])
	var schema := save_schema()
	for id in schema:
		if not saved is Array or not id in saved:
			continue
		if str(schema[id].get("kind", "case")) == "errand":
			restored = false
			continue
		completed_ids[id] = true
		score += int(schema[id].reward)
	var progression = level.get("progression") if level != null else null
	var choices: Dictionary = {}
	if is_instance_valid(progression) and progression.get("choices") is Dictionary:
		choices = progression.choices
	if not narrative.validate(completed_ids.keys(), "", 0, choices, {}).is_empty():
		for id in narrative.schema():
			if completed_ids.has(id):
				completed_ids.erase(id)
				score -= int(narrative.schema()[id].reward)
		restored = false
	# Data-case ledgers first: the active record below resumes from them.
	restored = cases.restore_ledgers(state.get("case_engine")) and restored
	var saved_id := str(state.get("active_id", ""))
	if not saved_id.is_empty() and _custody_contact(saved_id, int(state.get("stage", 0))).is_empty():
		_restoring = true
		var started := _start_case_at(saved_id, int(state.get("stage", 0)))
		_restoring = false
		restored = started and restored
		if started and not cases.owns(saved_id):
			stage = clampi(int(state.get("stage", 0)), 0, _steps.size() - 1)
			for committed_step in stage:
				_apply_step_visuals(committed_step)
			_update_clue_tags()
	cases.clear_restore()
	set_block_signals(false)
	changed.emit()
	return restored

## Persistence API (pure): "" when a saved missions section is valid on its own
## and against the same snapshot's progression choices and death registry.
## The world-save provider may call it from validate_snapshot.
func validate_state(section, snapshot: Dictionary = {}) -> String:
	if not section is Dictionary:
		return "invalid cases"
	var data: Dictionary = section
	var completed = data.get("completed_ids")
	var active = data.get("active_id")
	if not completed is Array or not active is String:
		return "invalid cases"
	var schema := save_schema()
	var unique := {}
	var total := 0
	for id in completed:
		if not id is String or not schema.has(id) or unique.has(id):
			return "invalid completed case"
		if str(schema[id].get("kind", "case")) == "errand":
			return "errand recorded as completed"
		unique[id] = true
		total += int(schema[id].reward)
	var points = data.get("score")
	if not (points is int or points is float) or not is_finite(float(points)) or float(points) != float(total):
		return "case reward mismatch"
	var saved_stage = data.get("stage")
	var stages := int(schema.get(active, {"stages": 1}).stages)
	var whole: bool = (saved_stage is int or saved_stage is float) and is_finite(float(saved_stage)) and float(saved_stage) == floorf(float(saved_stage))
	if not whole or float(saved_stage) < 0.0 or float(saved_stage) > float(stages - 1):
		return "invalid case progress"
	if not str(active).is_empty() and (not schema.has(active) or unique.has(active)):
		return "invalid case progress"
	var choices: Dictionary = {}
	var progress = snapshot.get("progression")
	if progress is Dictionary and progress.get("choices") is Dictionary:
		choices = progress.choices
	var dead := {}
	var deaths = snapshot.get("deaths")
	if deaths is Dictionary and deaths.get("dead") is Array:
		for id in deaths.dead:
			dead[str(id)] = true
	var engine_error := cases.validate(data, unique, dead)
	if not engine_error.is_empty():
		return engine_error
	return narrative.validate(unique.keys(), str(active), int(saved_stage), choices, dead)

func _apply_step_visuals(committed_step: int) -> void:
	if narrative.owns(active_id):
		if committed_step < _steps.size() and str(_steps[committed_step].target) == "clue":
			if is_instance_valid(_clue):
				_clue.hide()
			if is_instance_valid(_clue_body):
				_clue_body.collision_layer = 0
			if committed_step == narrative.carry_after(active_id):
				_carry(narrative.prop_kind(active_id))
		return
	if (active_id == "lost_satchel" and committed_step == 1) or (active_id == "missing_tools" and committed_step == 2):
		_clue.hide()
		_clue_body.collision_layer = 0
		_carried = Node3D.new()
		_case_root.add_child(_carried)
		if active_id == "missing_tools":
			_tool_caddy(_carried)
		else:
			_satchel(_carried)
		_carried.scale = Vector3.ONE * 0.65
		_update_carried()
	elif active_id == "dumping" and committed_step == 2:
		_clue.hide()
		_clue_body.collision_layer = 0
		var cleared := Node3D.new()
		cleared.position = _clue_position
		_case_root.add_child(cleared)
		_cleanup_tag = _tag(cleared, "CLEANUP COMPLETE\nCHECK THIS SPOT", 0.85)
		_ring(cleared, Color("81c8a0"))


func _complete(at: Vector3) -> void:
	var finished := active_id
	if narrative.is_errand(finished):
		# Repeatable: paid once per run through progression, never recorded complete.
		_celebrate(at, narrative.complete_errand(finished))
		cancel_case()
		return
	if completed_ids.has(finished):
		return
	var reward := 0
	for entry in CASES:
		if entry.id == finished:
			reward = int(entry.reward)
	if narrative.is_story(finished):
		reward = int(narrative.schema()[finished].reward)
	completed_ids[finished] = true
	score += reward
	if level.get("progression") != null:
		level.progression.reward_case(finished, reward)
	if narrative.is_story(finished):
		_celebrate(at, narrative.completion_banner(finished) + ("\n+%d community points" % reward if reward > 0 else ""))
		cancel_case()
		narrative.after_story(finished)
		return
	var message := "PROPERTY RETURNED" if finished == "lost_satchel" else ("REPORT FILED" if finished == "parcel_report" else "SIDEWALK CLEAR")
	if finished == "missing_tools":
		message = "TOOLS RETURNED"
	elif finished == "torn_notice":
		message = "NOTICE MYSTERY RESOLVED"
	elif finished == "porch_light":
		message = "DAMAGE REPORTED · REPAIR ARRANGED"
	_celebrate(at, "%s\n+%d community points" % [message, reward])
	cancel_case()
	# Dialogue was emitted above; include the resolution without replacing it with a bare score.
	var next_hint := "All neighborhood cases resolved. Keep exploring Baltimore." if all_cases_complete() else "Keep an eye out for neighbors who need a hand."
	notice.emit("%s. +%d community points%s. %s" % [message.capitalize(), reward, " · +$%d" % reward if level.get("progression") != null else "", next_hint])

func _celebrate(at: Vector3, text: String) -> void:
	var effect := Node3D.new()
	effect.position = at
	add_child(effect)
	_tag(effect, text, 2.0)
	_ring(effect, Color("81c8a0"))
	_effects.append({"node": effect, "remaining": 5.0})


func tick(delta: float) -> void:
	narrative.tick(delta)
	# Data cases check their own contacts (stand-ins, custody) at a bounded rate.
	cases.tick(delta)
	if not active_id.is_empty() and not narrative.owns(active_id) and not cases.owns(active_id):
		var detained := _custody_contact(active_id, stage)
		if not detained.is_empty():
			cancel_case()
			notice.emit("Case paused without a reward: %s is in police custody. Other cases remain available." % detained)
	_update_carried()
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i].remaining = float(_effects[i].remaining) - delta
		if float(_effects[i].remaining) <= 0.0:
			_effects[i].node.queue_free()
			_effects.remove_at(i)


func _update_clue_tags() -> void:
	var seeking_clue := not active_id.is_empty() and stage < _steps.size() and str(_steps[stage].target) == "clue"
	if is_instance_valid(_clue_tag):
		_clue_tag.visible = seeking_clue
	if is_instance_valid(_cleanup_tag):
		_cleanup_tag.visible = seeking_clue


func _update_carried() -> void:
	if not is_instance_valid(_carried):
		return
	# Small carried bag remains within the player's existing capsule footprint.
	_carried.global_position = level.player.global_position + Vector3(0, 0.9, -0.12).rotated(Vector3.UP, level.player.yaw)
	_carried.rotation.y = level.player.yaw


func _title() -> String:
	for entry in CASES:
		if entry.id == active_id:
			return str(entry.title)
	if cases.owns(active_id):
		return cases.title(active_id)
	if narrative.owns(active_id):
		return narrative.title(active_id)
	return "Neighborhood cases"


func _target_position() -> Vector3:
	if cases.owns(active_id):
		return cases.target_position()
	var who: String = str(_steps[stage].target)
	if who == "clue":
		return _clue_position
	if narrative.owns(active_id):
		# Infinite when nobody can take the step, so it cannot be committed.
		var stand_in := narrative.resolve(who, active_id)
		return npcs.actor_position(stand_in) if not stand_in.is_empty() else Vector3.INF
	return npcs.actor_position(who)


func _can_interact(target: Vector3) -> bool:
	if not target.is_finite():
		return false
	var here: Vector3 = level.player.global_position
	if Vector2(here.x - target.x, here.z - target.z).length() > INTERACT_RADIUS or absf(here.y - target.y) > 1.5:
		return false
	var exclusions: Array[RID] = [level.player.get_rid()]
	if is_instance_valid(_clue_body):
		exclusions.append(_clue_body.get_rid())
	# A solid data-case prop never blocks the ray to itself.
	exclusions.append_array(cases.prop_rids())
	var end := target + Vector3.UP * 0.85
	var query := PhysicsRayQueryParameters3D.create(here + Vector3.UP * 1.2, end, 2, exclusions)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	# Actors use layer 8. Only obstacles on layer 2 block this ray; no wall tolerance.
	return hit.is_empty()


func _route_point(metres: float) -> Vector3:
	var route: Dictionary = level.level_data.get("route", {})
	var points: Array = route.get("points", [])
	if points.is_empty():
		return level.player.global_position
	var previous: Vector3 = level.vector(points[0])
	var remaining := maxf(0.0, metres)
	for i in range(1, points.size()):
		var next: Vector3 = level.vector(points[i])
		var length := Vector2(next.x - previous.x, next.z - previous.z).length()
		if length > 0.001 and remaining <= length:
			return previous.lerp(next, remaining / length)
		remaining -= length
		previous = next
	return previous


func _route_distance(point: Vector3) -> float:
	var route: Dictionary = level.level_data.get("route", {})
	var points: Array = route.get("points", [])
	var closest := INF
	for i in range(1, points.size()):
		var a: Vector3 = level.vector(points[i - 1])
		var b: Vector3 = level.vector(points[i])
		var flat := Vector2(point.x, point.z)
		closest = minf(closest, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))))
	return closest

# --- Data cases: evidence, incidents and read-only views (cases-contract.md) -------

## phone.photo_captured bridge. {ok, recorded, objectives, reason}; the
## evidence comes from the live world at shutter time, never the gallery file.
func on_photo_captured(context: Dictionary) -> Dictionary:
	return cases.on_photo_captured(context)

## incidents.incident_changed bridge.
func on_incident_event(summary: Dictionary) -> void:
	cases.on_incident_event(summary)

## Phone subject provider: places a pending photo objective needs.
func photo_subjects_for_phone() -> Array[Dictionary]:
	return cases.photo_subjects()

## Starts an incident-triggered data case bound to `incident_id`.
func start_incident_case(id: String, incident_id: String) -> bool:
	_start_incident = incident_id
	var started := start_case(id)
	_start_incident = ""
	return started

func case_detail(case_id := "") -> Dictionary:
	return cases.case_detail(case_id)

func evidence_list(case_id: String) -> Array[Dictionary]:
	return cases.evidence_list(case_id)

## Library diagnostics: rejected files/fields and authoring warnings.
func case_library_report() -> Dictionary:
	var drafts: Array = []
	for id in cases.order:
		if cases.is_draft(id):
			drafts.append(id)
	return {"cases": cases.order.duplicate(), "drafts": drafts, "errors": Array(cases.load_errors), "warnings": Array(cases.load_warnings),
		"templates": cases.library_result.get("templates", []).duplicate(), "sources": cases.library_result.get("sources", {}).duplicate()}

func case_library_errors() -> PackedStringArray:
	return cases.load_errors

## World-save death cross-check: ids whose saved deaths make the saved active
## case impossible. Data cases name a role only when every person who could
## take it is dead; other cases list their remaining step targets as before.
func required_contacts(section: Dictionary, dead: Array) -> Array:
	var id := str(section.get("active_id", ""))
	var from_stage := int(section.get("stage", 0)) if section.get("stage") is int or section.get("stage") is float else 0
	if cases.owns(id):
		return cases.required_contacts(id, from_stage, cases.usable_record(id, from_stage, _saved_record(section)), dead)
	var result: Array = []
	var steps := case_steps(id)
	for index in range(maxi(0, from_stage), steps.size()):
		var target := str(steps[index].target)
		if target != "clue":
			result.append(target)
	return result

## Phone Cases app cards {title, state, detail, active} (phone-map-contract §2):
## the active case with its objective and evidence, then every ledger row.
func get_phone_cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var status := get_status()
	if not active_id.is_empty():
		var lines := PackedStringArray([str(status.get("objective", ""))])
		var detail: Dictionary = status.get("case_detail", {})
		var held := PackedStringArray()
		for entry in detail.get("evidence", []):
			if bool(entry.held):
				held.append(str(entry.label))
		if not held.is_empty():
			lines.append("Evidence: " + ", ".join(held))
		cards.append({"id": active_id, "title": str(status.get("title", "Case")), "state": "active", "detail": "\n".join(lines), "active": true})
	for entry in status.get("cases", []):
		if str(entry.id) == active_id:
			continue
		cards.append({"id": str(entry.id), "title": str(entry.title), "state": str(entry.state), "detail": str(entry.reason), "active": false})
	for entry in status.get("story", []):
		if entry is Dictionary and str(entry.get("id", "")) != active_id:
			cards.append({"id": str(entry.get("id", "")), "title": str(entry.get("title", "Story")), "state": str(entry.get("state", "")),
				"detail": str(entry.get("reason", "")), "active": false})
	return cards


func _make_body(size_: Vector3, center: Vector3) -> void:
	_clue_body = StaticBody3D.new()
	_clue_body.name = "SolidCaseClue"
	# Loose rubbish stays inspectable without catching feet, even during a case.
	_clue_body.collision_layer = 0 if active_id in ["parcel_report", "dumping", "torn_notice"] or narrative.clue_passable(active_id) else 2
	_clue_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	collision.position = center
	_clue_body.add_child(collision)
	_clue.add_child(_clue_body)


func _box(parent: Node3D, dimensions: Vector3, center: Vector3, color: String) -> MeshInstance3D:
	return Prim.M(Prim.box(dimensions.x, dimensions.y, dimensions.z), ClayLib.clay(color), center.x, center.y, center.z, parent)


func _satchel(parent: Node3D) -> void:
	_box(parent, Vector3(0.44, 0.3, 0.25), Vector3(0, 0.16, 0), "#36568a")
	_box(parent, Vector3(0.46, 0.07, 0.28), Vector3(0, 0.3, 0), "#2a3a6a")
	_box(parent, Vector3(0.075, 0.07, 0.025), Vector3(0, 0.25, 0.15), "#c8a060")
	var handle := Prim.T(0.10, 0.018, ClayLib.clay("#5a3a24"), 0, 0.34, 0, parent, 5, 12)
	handle.scale = Vector3(1.3, 0.65, 1)

func _tool_caddy(parent: Node3D) -> void:
	_box(parent, Vector3(0.46, 0.28, 0.3), Vector3(0, 0.14, 0), "#507746")
	_box(parent, Vector3(0.36, 0.04, 0.08), Vector3(0, 0.43, 0), "#b49b68")
	for x in [-0.14, 0.14]:
		_box(parent, Vector3(0.035, 0.33, 0.035), Vector3(x, 0.35, 0), "#b49b68")
	_box(parent, Vector3(0.1, 0.15, 0.035), Vector3(0.14, 0.54, 0), "#777d7e")


func _parcel(parent: Node3D) -> void:
	_box(parent, Vector3(0.5, 0.27, 0.4), Vector3(0, 0.135, 0), "#b8925a")
	_box(parent, Vector3(0.45, 0.018, 0.35), Vector3(0, 0.279, 0), "#4a3424")
	var flap := _box(parent, Vector3(0.25, 0.025, 0.4), Vector3(-0.22, 0.31, 0), "#c8b080")
	flap.rotation.z = 0.4
	_box(parent, Vector3(0.17, 0.1, 0.013), Vector3(0.07, 0.16, 0.21), "#f4f0e6")
	for y in [0.14, 0.17, 0.19]:
		_box(parent, Vector3(0.12, 0.008, 0.007), Vector3(0.07, y, 0.221), "#3a3a3e")


func _dumped_bags(parent: Node3D) -> void:
	for entry in [Vector3(-0.23, 0.26, 0.04), Vector3(0.21, 0.24, 0.02), Vector3(0, 0.32, -0.14)]:
		var bag := Prim.M(Prim.sph(0.26, 12, 8), ClayLib.clay("#3a4a2a"), entry.x, entry.y, entry.z, parent)
		bag.scale = Vector3(0.95, 1.15, 0.8)
		Prim.M(Prim.cyl(0.035, 0.07, 0.1, 6), ClayLib.clay("#2f4f34"), entry.x, entry.y + 0.3, entry.z, parent)


func _tag(parent: Node3D, text: String, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = Prim.font("mono")
	label.font_size = 28
	label.pixel_size = 0.0035
	label.modulate = Color("f4f0e6")
	label.position.y = height
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.outline_size = 6
	label.outline_modulate = Color("182a2a")
	label.visibility_range_begin = 4.0
	label.visibility_range_end = 22.0
	parent.add_child(label)
	return label


func _ring(parent: Node3D, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.75
	mesh.outer_radius = 0.8
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Prim.M(mesh, material, 0, 0.025, 0, parent, false)
