extends Node3D
## Police help for neighbors: the phone's police_requested(world_position) and
## world violence reports open a bounded incident. The player never fights;
## police handle violence, and nothing here ever targets the player or caller.
##
## Who is a suspect: only someone actually being violent near the call — a
## combat fighter in "aggro" (fists) or "gun" mode, or the suspect named by a
## report_violence() event. A call with no such person is investigated at the
## call location; nobody is picked at random. Where a suspect is comes only
## from the call/report itself and later from an officer's own sight ray.
##
## Who responds: real bodies, physically moved. The nearest free foot patrol
## walks a surveyed street route (law.routes) with forward-only, collision-swept
## steps; a distant call claims a real traffic cruiser (law.cruisers
## request_assist), which drives the lane network and dismounts its crew
## through a checked door. Nobody is teleported toward a target.
##
## Escalation is proportionate: approach, warn, then detain (combat lets go via
## disengage_actor, custody holds them, cuffs, escort, taken in). Police fire
## only at an armed suspect who is aiming or has just fired (an imminent lethal
## threat), after a spoken warning and an aim telegraph, with every round gated
## by line of sight and bystander/caller clearance. Firing stops the moment the
## suspect is down, dead, complying or no longer an imminent threat.
##
## Budgets: <= 3 incidents, <= 4 suspects each, <= 4 officers in total, decisions
## at 4 Hz with <= 2 sight rays per officer, discovery at 1 Hz reading combat's
## fight set (<= 8). No crowd-wide scan ever runs.
##
## Witnessed neighborhood incidents (city_incidents.gd) arrive through
## report_incident() with their own reference and a proportionate policy:
## "warn" (an infraction: the officer walks up, stops the person and issues a
## warning, no custody) or "detain" (the warn → comply → custody path above).
## report_status_changed carries report_received / responding / on_scene /
## resolved / unavailable for every call, phone or incident. Contract:
## .work/pacifist-foundation/incidents-contract.md section 4.
##
## Every call also has a dispatch stage (city_police_status.gd): received →
## queued | dispatched → en_route → on_scene → handling (contact, warning,
## commands, detaining, arrest, force) → resolved | failed | cancelled. This
## service is its only writer: one structured status per real transition, a
## bounded timeline, and nothing predicted (no ETA; "en route" only once a unit
## physically moved). A unit that is blocked, hurt or whose car fails stops
## counting at once; the call waits for a real replacement (never the same
## blocked officer again) and closes honestly after bounded retries. Contract:
## .work/five-priorities-20261101/police-contract.md.

signal incident_changed(summary: Dictionary)
signal report_status_changed(status: Dictionary)

const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const Custody := preload("res://scripts/city/city_police_custody.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Status := preload("res://scripts/city/city_police_status.gd")

const MAX_INCIDENTS := 3
const MAX_SUSPECTS := 4
const MAX_OFFICERS := 4
const MAX_UNITS_PER_INCIDENT := 2
const MAX_REPORTS := 8
const MAX_EFFECTS := 8
const MAX_ROUTE_PLANS := 3
const MAX_ROUNDS_PER_INCIDENT := 18
const MAX_HISTORY := 6
const THINK_INTERVAL := 0.25
const DISCOVERY_INTERVAL := 1.0
const MERGE_RADIUS := 25.0
const SCAN_RADIUS := 45.0
const REPORT_TTL := 30.0
## An armed suspect counts as an imminent lethal threat while aiming or this
## long after their latest shot (or a report of active shooting).
const IMMINENT_SECONDS := 4.0
const FOOT_DISPATCH_RADIUS := 260.0
const FOOT_ROUTE_LIMIT := 420.0
## Beyond this a cruiser (when one is free) is preferred over walking.
const CRUISER_PREFERRED_DISTANCE := 110.0
const SIGHT_RANGE := 32.0
const VIEW_DOT := -0.5
const NOTICE_RADIUS := 3.0
const WARN_RANGE := 11.0
const FIRE_RANGE := 26.0
const CUFF_RANGE := 1.5
const COVER_DISTANCE := 3.0
const ARRIVE_RADIUS := 1.2
const JOG_SPEED := 3.1
const WALK_SPEED := 1.6
const ESCORT_SPEED := 1.3
const WARN_SECONDS := 1.6
const COMPLY_GRACE := 2.5
const AIM_SECONDS := 0.7
const ROUND_COOLDOWN := 1.15
const ROUND_DAMAGE := 30.0
const CUFF_SECONDS := 2.2
const SEARCH_RADIUS := 7.0
const STUCK_SECONDS := 2.5
const MAX_UNSTICK := 3
const REPLAN_SECONDS := 1.0
const RESPOND_GRACE := 40.0
const INCIDENT_LIMIT := 240.0
const ESCORT_LIMIT := 60.0
const ESCORT_LAG := 4.0
const HIDE_DISTANCE := 45.0
const LOST_SIGHT_SECONDS := 6.0
const TRAIL_SPACING := 1.5
const MAX_TRAIL := 200
const DISPATCH_RETRIES := 4
const RETRY_SECONDS := 4.0
## Units that failed to reach one call (blocked route, failed car) before it
## closes as unanswered instead of sending yet another.
const DISPATCH_FAILURE_LIMIT := 3
## A dispatched unit counts as "en route" only after moving this far.
const EN_ROUTE_EVIDENCE := 2.0
const MAX_REFUSALS := 3
const PATROL_PREFIX := "patrol_officer_"
const CREW_PREFIX := "patrol_officer_cruiser_"
const OPEN_STATES := ["at_large", "warned", "held", "down"]
## An infraction stop: walk up to this distance, then a warning after CITE_SECONDS.
const CITE_RANGE := 2.4
const CITE_SECONDS := 2.2

## Tunables. Fixtures shorten them; production keeps these defaults.
var search_seconds := 16.0
var secure_seconds := 6.0

var level: Node
var available := false
var reason := "not set up"
var incidents: Array[Dictionary] = []
var history: Array[Dictionary] = []
var custody := Custody.new()
var tactics := Tactics.new()
var counters := {"requests": 0, "violence_reports": 0, "merged": 0, "rejected": 0, "foot_dispatches": 0,
	"cruiser_dispatches": 0, "cruiser_failures": 0, "crew_dismounts": 0, "routes": 0, "route_failures": 0,
	"arrivals": 0, "sightings": 0, "warnings": 0, "telegraphs": 0, "compliances": 0, "custody_refusals": 0,
	"arrests": 0, "taken_in": 0, "rounds": 0, "hits": 0, "damage_applied": 0, "damage_unavailable": 0,
	"held_fire": 0, "police_kills": 0, "suspects_dead": 0, "suspects_downed": 0, "officers_lost": 0, "unsticks": 0,
	"releases": 0, "remounts": 0, "thinks": 0, "incident_reports": 0, "incident_duplicates": 0, "citations": 0,
	"handoffs": 0, "transitions": 0, "replacements": 0, "cancelled_refs": 0}
## Bumps on every dispatch-visible change (the phone's refresh key).
var revision := 0
## Bumps when restore_state() accepts a checkpoint: this session's timeline is gone.
var generation := 0
## The incident service (city_incidents.gd): resolves its performers by identity
## and hears on_police_progress(ref, event, data) for linked calls.
var incident_handler: Object = null
var hold_reasons: Dictionary = {}
var outcomes: Dictionary = {}
## How combat was reached: "public" hook, "internal_fallback" or "none".
var hooks := {"fighters": "none", "damage": "none", "gunfire": "none"}
var last_message := ""
var _officers: Dictionary = {}
var _reports: Array[Dictionary] = []
var _refusals: Array[Dictionary] = []
var _refusal_sequence := 0
var _effects: Array[Dictionary] = []
var _patrols: Array = []
var _station := Vector3.INF
var _clock := 0.0
var _think_left := 0.0
var _discover_left := 0.0
var _sequence := 0
var _materials: Dictionary = {}

# --------------------------------------------------------------- public API

func setup(owner_level: Node) -> void:
	level = owner_level
	name = "PoliceAssistance"
	custody.setup(level)
	_patrols = _scan_patrols()
	var cruisers = _cruisers()
	if cruisers != null:
		cruisers.set("assist_handler", self)
	var info: Dictionary = Facilities.candidates(level, "police") if level != null else {}
	var points: Array = info.get("points", [])
	_station = points[0] if not points.is_empty() and points[0] is Vector3 else Vector3.INF
	var cars_ready: bool = cruisers != null and bool(cruisers.get("available"))
	available = not _patrols.is_empty() or cars_ready
	reason = "" if available else "no patrol officers or police cars"

## Phone call from `at` (the caller's position). Returns {ok, incident_id,
## message, merged, dispatched, suspects, threat}. `message` is honest about
## what was actually dispatched; later progress goes to phone.set_report_status.
func request_help(at: Vector3) -> Dictionary:
	counters.requests = int(counters.requests) + 1
	if level == null:
		return _reply({}, false, "Police dispatch is unavailable.")
	if not at.is_finite():
		return _reply({}, false, "Dispatch could not place your call.")
	return _open(at, "phone", "")

## World violence (another worker's event, a scripted fight, a mission):
## {suspect_id, at, kind: assault|fight|shooting|armed_threat, armed, active,
## victim_id, dispatch (default true)}. The suspect must be a real, living,
## non-police person; the player is never accepted as a suspect.
func report_violence(event: Dictionary) -> Dictionary:
	counters.violence_reports = int(counters.violence_reports) + 1
	if level == null:
		return _reply({}, false, "Police dispatch is unavailable.")
	var kind := str(event.get("kind", "assault"))
	var suspect_id := str(event.get("suspect_id", ""))
	var at: Vector3 = event.get("at") if event.get("at") is Vector3 else Vector3.INF
	var suspect = null
	if not suspect_id.is_empty():
		suspect = _resolve(suspect_id)
		if not _eligible_suspect(suspect, suspect_id):
			return _reply({}, false, "Report ignored: no such suspect.")
		if not at.is_finite():
			at = suspect.global_position
	if not at.is_finite():
		return _reply({}, false, "Report ignored: no location.")
	var armed := bool(event.get("armed", kind in ["shooting", "armed_threat"]))
	var report := {"suspect_id": suspect_id, "at": at, "kind": kind, "armed": armed,
		"active": bool(event.get("active", true)), "victim_id": str(event.get("victim_id", "")),
		"clock": _clock, "sequence": int(counters.violence_reports)}
	# A newer observation supersedes the old lethal authorization immediately,
	# including between decision ticks and during an already-started aim telegraph.
	if not suspect_id.is_empty():
		for previous in _reports.duplicate():
			if str(previous.suspect_id) == suspect_id:
				_reports.erase(previous)
		for incident in incidents:
			if (incident.suspects as Dictionary).has(suspect_id):
				_apply_report_threat(incident.suspects[suspect_id], report)
	_reports.append(report)
	while _reports.size() > MAX_REPORTS:
		_reports.pop_front()
	if not bool(event.get("dispatch", true)):
		return {"ok": true, "queued": true, "incident_id": "", "message": "Report recorded."}
	return _open(at, "world", suspect_id)

## A witnessed incident from city_incidents.gd: {incident_ref, policy: warn|detain,
## kind, suspects: [ids], at, reporter_id, phone}. The incident service already
## proved who saw what; here a second report of the same reference never sends a
## second response, the reporter is never a suspect, and every suspect must be a
## real living non-police person. Returns the request_help() reply plus
## "duplicate"; later progress goes out through report_status_changed.
func report_incident(event: Dictionary) -> Dictionary:
	counters.incident_reports = int(counters.incident_reports) + 1
	if level == null:
		return _reply({}, false, "Police dispatch is unavailable.")
	var ref := str(event.get("incident_ref", ""))
	var at: Vector3 = event.get("at") if event.get("at") is Vector3 else Vector3.INF
	if ref.is_empty() or not at.is_finite():
		return _reply({}, false, "Report ignored: no incident to respond to.")
	var phone := bool(event.get("phone", false))
	var incident := _incident_for_ref(ref)
	if not incident.is_empty():
		counters.incident_duplicates = int(counters.incident_duplicates) + 1
		incident.phone = bool(incident.phone) or phone
		var again := _reply(incident, true, _progress_text(incident), true)
		again["duplicate"] = true
		return again
	var policy := "warn" if str(event.get("policy", "detain")) == "warn" else "detain"
	var reporter := str(event.get("reporter_id", ""))
	var kind := str(event.get("kind", "")).left(32)
	incident = _incident_near(at)
	var merged := not incident.is_empty() and str(incident.get("ref", "")).is_empty()
	if merged:
		counters.merged = int(counters.merged) + 1
		incident.ref = ref
		incident.policy = policy
		incident.kind = kind
		incident.phone = bool(incident.phone) or phone
		incident.updated = _clock
	else:
		if incidents.size() >= MAX_INCIDENTS:
			var refused := _refused("All officers are already on calls. Try again shortly.", at, phone, ref)
			refused["duplicate"] = false
			return refused
		incident = _new_incident(at, "report", phone, "", ref, policy, reporter, kind)
	incident.reporter = reporter
	for value in event.get("suspects", []):
		var id := str(value)
		if id.is_empty() or id == reporter or (incident.suspects as Dictionary).has(id):
			continue
		var actor = _resolve(id)
		if not _eligible_suspect(actor, id) or _tracked_elsewhere(id, incident):
			continue
		var s := _add_suspect(incident, id, actor, false, actor.global_position)
		if not s.is_empty():
			s.policy = policy
	_discover(incident, at)
	_dispatch(incident)
	var text := ""
	if merged:
		text = _progress_text(incident)
		incident.message = text
		last_message = text
		_relink(incident, text)
		incident_changed.emit(_summary(incident))
	else:
		text = _intake(incident)
	var reply := _reply(incident, true, text, merged)
	reply["duplicate"] = false
	return reply

## Checkpoint guard for the root: a call the player is waiting on, or a suspect
## physically held, cuffed or escorted. Ambient incident responses do not block.
func blocks_checkpoint() -> bool:
	for incident in incidents:
		if bool(incident.get("phone", false)) and not bool(incident.closing):
			return true
	for entry in custody.records.values():
		if str(entry.get("state", "")) != "in_custody":
			return true
	return false

func tick(delta: float) -> void:
	if level == null or delta <= 0.0 or _world_paused():
		return
	delta = minf(delta, 0.1)
	_clock += delta
	tactics.space = _space()
	_tick_effects(delta)
	for id in _officers.keys():
		if _officers.has(id):
			_move_officer(_officers[id], delta)
	_tick_custody(delta)
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_INTERVAL
		_think()

## Ends every incident now: officers return to their beats where they stand,
## held suspects are let go, assist cruisers depart (fixtures, debug, reloads).
func reset_state() -> void:
	for o in _officers.values().duplicate():
		_release_officer(o)
	custody.release_all()
	var cruisers = _cruisers()
	for incident in incidents:
		for unit in incident.units:
			if str(unit.state) == "driving" and cruisers != null:
				cruisers.cancel_assist(int(unit.slot), str(unit.tag))
		if not bool(incident.closing):
			incident.closing = true
			incident.outcome = "interrupted"
			incident.phase = "closed"
			_transition(incident, "cancelled", "The police response was called off.")
		history.append(_summary(incident))
	while history.size() > MAX_HISTORY:
		history.pop_front()
	incidents.clear()
	_reports.clear()
	revision += 1
	for effect in _effects:
		if is_instance_valid(effect.node):
			effect.node.queue_free()
	_effects.clear()

func is_busy() -> bool:
	return not incidents.is_empty() or not _officers.is_empty() or not custody.records.is_empty()

## Save only completed custody; transient response/cuff/escort state is not saved.
func snapshot_state() -> Dictionary:
	return custody.snapshot_state()

func validate_state(value) -> String:
	return custody.validate_state(value)

## A checkpoint may load while officers answer an ambient incident (that never
## blocks saving or loading): validate first, then stand the response down so
## the loaded world starts calm. A call the player waits on or a suspect in
## transit still refuses, exactly like the checkpoint guard.
func restore_state(value) -> Dictionary:
	var invalid := custody.validate_state(value)
	if not invalid.is_empty():
		return {"ok": false, "restored": 0, "skipped_dead": [], "reason": invalid}
	if blocks_checkpoint():
		return {"ok": false, "restored": 0, "skipped_dead": [], "reason": "police response in progress"}
	if is_busy():
		reset_state()
	var result: Dictionary = custody.restore_state(value)
	if bool(result.get("ok", false)):
		# The checkpoint replaces this session's timeline: calls that closed in
		# the abandoned timeline are not shown as if they happened in this one.
		history.clear()
		_refusals.clear()
		generation += 1
		revision += 1
	return result

## Whether a linked incident still has an open police call (incident upkeep).
func has_open_ref(ref: String) -> bool:
	return not _incident_for_ref(ref).is_empty()

## The linked incident was closed by its owner (a case settled it) while police
## were still answering: officers stand down where they are and walk back, a car
## still driving turns away, and nothing more is reported to that incident.
func cancel_ref(ref: String, text := "") -> bool:
	var incident := _incident_for_ref(ref)
	if incident.is_empty():
		return false
	counters.cancelled_refs = int(counters.cancelled_refs) + 1
	_close(incident, "cancelled", text if not text.is_empty() else "The incident was settled, so officers are standing down.")
	return true

## What the phone shows: live calls, this session's closed calls and refused
## phone calls, each with its dispatch stage and bounded timeline.
func dispatch_view() -> Dictionary:
	var live: Array = []
	for incident in incidents:
		live.append(_summary(incident))
	return {"generation": generation, "revision": revision, "available": available, "reason": reason,
		"live": live, "history": history.duplicate(true), "refusals": _refusals.duplicate(true), "minutes": _minutes()}

## One call by police incident id or linked incident ref: live first, then the
## newest closed one. {} when unknown.
func call_status(key: String) -> Dictionary:
	if key.is_empty():
		return {}
	for incident in incidents:
		if str(incident.id) == key or str(incident.get("ref", "")) == key:
			return _summary(incident)
	for i in range(history.size() - 1, -1, -1):
		if str(history[i].get("id", "")) == key or str(history[i].get("ref", "")) == key:
			return history[i].duplicate(true)
	return {}

## Cruiser callback (city_police_cruisers.gd): an assist car's officer just
## stepped out of a stopped car at `door`. True when this service takes them.
func on_assist_dismount(actor, tag: String, door: Vector3) -> bool:
	var incident := _incident_for_tag(tag)
	if incident.is_empty() or bool(incident.closing) or not _usable(actor):
		return false
	var slot := 0
	for unit in incident.units:
		if str(unit.tag) == tag:
			unit.state = "on_foot"
			slot = int(unit.slot)
	counters.crew_dismounts = int(counters.crew_dismounts) + 1
	var o := _adopt(actor, incident, "crew")
	o.slot = slot
	o.tag = tag
	o.door = door
	o.trail = [door, actor.global_position]
	_send(o, _goal(incident), JOG_SPEED, "respond")
	actor.speak("Dispatch, I'm on scene. Checking it out.", 1.8)
	return true

func get_status() -> Dictionary:
	var list: Array = []
	for incident in incidents:
		list.append(_summary(incident))
	var officers: Array = []
	for o in _officers.values():
		officers.append({"id": str(o.id), "incident": str(o.incident), "kind": str(o.kind), "state": str(o.state),
			"target": str(o.target), "position": o.actor.global_position if is_instance_valid(o.actor) else Vector3.INF,
			"rounds": int(o.rounds), "hold_reason": str(o.hold_reason), "drawn": is_instance_valid(o.gun)})
	return {"available": available, "reason": reason, "incidents": list, "history": history.duplicate(true),
		"officers": officers, "officer_count": _officers.size(), "max_officers": MAX_OFFICERS,
		"max_incidents": MAX_INCIDENTS, "busy": is_busy(), "message": last_message,
		"counters": counters.duplicate(), "hold_reasons": hold_reasons.duplicate(), "outcomes": outcomes.duplicate(),
		"hooks": hooks.duplicate(), "custody": custody.get_status(), "reports": _reports.size(),
		"refusals": _refusals.duplicate(true), "revision": revision, "generation": generation,
		"rays": tactics.rays, "shape_queries": tactics.shape_queries}

# --------------------------------------------------------------- incidents

func _open(at: Vector3, source: String, focus_id: String) -> Dictionary:
	var incident := _incident_near(at)
	if not incident.is_empty():
		counters.merged = int(counters.merged) + 1
		incident.updated = _clock
		if source == "phone":
			incident.phone = true
		_discover(incident, at)
		_dispatch(incident)
		return _reply(incident, true, _progress_text(incident), true)
	if incidents.size() >= MAX_INCIDENTS:
		return _refused("All officers are already on calls. Try again shortly.", at, source == "phone")
	incident = _new_incident(at, source, source == "phone", focus_id)
	_discover(incident, at)
	_dispatch(incident)
	var text := _intake(incident)
	return _reply(incident, true, text, false)

func _new_incident(at: Vector3, source: String, phone: bool, focus_id := "", ref := "", policy := "", reporter := "", kind := "") -> Dictionary:
	_sequence += 1
	var now := _minutes()
	var incident := {"id": "incident_%d" % _sequence, "at": at, "source": source, "phone": phone,
		"focus": focus_id, "phase": "dispatching", "created": _clock, "updated": _clock, "suspects": {},
		"units": [], "officers": [], "outcome": "", "retries": 0, "next_retry": 0.0, "arrived": -INF,
		"search_until": -INF, "secure_until": -INF, "rounds": 0, "message": "", "closing": false, "closed": -INF,
		"ref": ref, "policy": policy, "reporter": reporter, "kind": kind,
		# Dispatch state (city_police_status.gd); `excluded` holds officers whose
		# route to this call failed, `failures` every unit that could not get here.
		"stage": "received", "handling": "", "stage_key": "", "timeline": [], "street": _street(at),
		"opened_minutes": now, "updated_minutes": now, "excluded": {}, "failures": 0, "sent": 0, "route_blocked": false}
	incidents.append(incident)
	return incident

## A new call's first dispatch step. The caller's reply carries this text, so
## there is no direct phone notice here; a linked incident hears it (and the
## caller's phone through it) from the incident relay.
func _intake(incident: Dictionary) -> String:
	var text := _dispatch_text(incident)
	incident.message = text
	last_message = text
	if _assigned(incident) > 0:
		_transition(incident, "received", text, "", false)
		_transition(incident, "dispatched", text, "", false)
	else:
		_transition(incident, "queued", text, "", false)
	incident_changed.emit(_summary(incident))
	return text

## A report merged into an open call: the newly linked incident hears where that
## call stands (received, then its current status) without new timeline steps.
func _relink(incident: Dictionary, text: String) -> void:
	incident.last_status = ""
	_status(incident, "report_received", text)
	var current := Status.coarse_status(str(incident.get("stage", "received")), str(incident.get("outcome", "")))
	if current != "report_received":
		_status(incident, current, text)

## A refused call: nothing is dispatched. A phone caller's refusal stays on the
## phone (bounded) so "not taken" is never mistaken for "on the way".
func _refused(text: String, at: Vector3, phone: bool, ref := "") -> Dictionary:
	counters.rejected = int(counters.rejected) + 1
	if phone:
		_refusal_sequence += 1
		_refusals.append({"id": "refusal_%d" % _refusal_sequence, "stage": "unavailable", "text": text, "ref": ref,
			"phone": true, "at": at, "street": _street(at), "minutes": _minutes()})
		while _refusals.size() > MAX_REFUSALS:
			_refusals.pop_front()
		revision += 1
	return _reply({}, false, text)

func _reply(incident: Dictionary, ok: bool, text: String, merged := false) -> Dictionary:
	last_message = text
	return {"ok": ok, "incident_id": str(incident.get("id", "")), "message": text, "merged": merged,
		"dispatched": _assigned(incident) if not incident.is_empty() else 0,
		"suspects": (incident.get("suspects", {}) as Dictionary).size(),
		"threat": _threat_label(incident) if not incident.is_empty() else "none"}

func _incident_near(at: Vector3) -> Dictionary:
	for incident in incidents:
		if not bool(incident.closing) and Tactics.flat(Vector3(incident.at), at) <= MERGE_RADIUS:
			return incident
	return {}

func _incident_by_id(id: String) -> Dictionary:
	for incident in incidents:
		if str(incident.id) == id:
			return incident
	return {}

func _incident_for_tag(tag: String) -> Dictionary:
	for incident in incidents:
		for unit in incident.units:
			if str(unit.tag) == tag:
				return incident
	return {}

func _incident_for_ref(ref: String) -> Dictionary:
	if ref.is_empty():
		return {}
	for incident in incidents:
		if str(incident.get("ref", "")) == ref and not bool(incident.closing):
			return incident
	return {}

## One structured status per transition (phone and incident service). Linked
## incidents also hear it through incident_handler.on_police_progress.
func _status(incident: Dictionary, status: String, text := "") -> void:
	var key := "%s:%s:%s:%s" % [status, str(incident.get("stage", "")), str(incident.get("handling", "")), str(incident.get("outcome", ""))]
	if str(incident.get("last_status", "")) == key:
		return
	incident.last_status = key
	var payload := {"police_incident_id": str(incident.id), "incident_ref": str(incident.get("ref", "")), "status": status,
		"outcome": str(incident.get("outcome", "")), "text": text if not text.is_empty() else str(incident.get("message", "")),
		"phone": bool(incident.get("phone", false)), "policy": str(incident.get("policy", "")),
		"dispatched": _assigned(incident), "stage": str(incident.get("stage", "")), "handling": str(incident.get("handling", "")),
		"street": str(incident.get("street", "")), "minutes": _minutes(), "responders": _responders(incident)}
	report_status_changed.emit(payload)
	_notify_handler(incident, status, payload)

## One dispatch transition: stage bookkeeping and the bounded timeline, then
## exactly one structured status (the incident relay for a linked call) and,
## for an unlinked phone call, one direct phone notice. `direct` false leaves the
## notice to the caller's reply (intake). `notify` false is a card-only change
## (en route): no notice of any kind. Nothing live follows a closed call.
func _transition(incident: Dictionary, stage: String, text: String, handling := "", direct := true, notify := true) -> bool:
	var outcome := str(incident.get("outcome", ""))
	if bool(incident.get("closing", false)) and Status.is_live(stage):
		return false
	var key := "%s:%s:%s" % [stage, handling, outcome]
	if str(incident.get("stage_key", "")) == key:
		return false
	incident.stage_key = key
	incident.stage = stage
	incident.handling = handling
	incident.updated_minutes = _minutes()
	_timeline(incident, stage, handling, text)
	counters.transitions = int(counters.transitions) + 1
	revision += 1
	if not notify:
		incident_changed.emit(_summary(incident))
		return true
	if direct:
		_tell(incident, text, true)
	elif not text.is_empty():
		incident.message = text
		last_message = text
	_status(incident, Status.coarse_status(stage, outcome), text)
	return true

func _handling(incident: Dictionary, kind: String, text: String) -> void:
	_transition(incident, "handling", text, kind)

## Same-stage news (one of several units blocked or lost, a reinforcement):
## the timeline and one notice, but no stage change.
func _note(incident: Dictionary, text: String) -> void:
	if text.is_empty() or bool(incident.get("closing", false)) or str(incident.get("message", "")) == text:
		return
	_timeline(incident, str(incident.get("stage", "")), str(incident.get("handling", "")), text)
	revision += 1
	_tell(incident, text)

func _timeline(incident: Dictionary, stage: String, handling: String, text: String) -> void:
	if not incident.get("timeline") is Array:
		incident.timeline = []
	var timeline: Array = incident.timeline
	timeline.append({"stage": stage, "handling": handling, "outcome": str(incident.get("outcome", "")),
		"text": text.left(120), "minutes": _minutes()})
	while timeline.size() > Status.MAX_TIMELINE:
		timeline.remove_at(1) # Keep the first step (when the call came in).

## A unit stopped answering this call (blocked, hurt, its car failed). With
## others still responding it is news; with none left the call waits again, and
## only says help is coming once a replacement is actually sent. Out of
## retries or failed units, the call closes honestly instead.
func _unit_lost(incident: Dictionary, what: String) -> void:
	if bool(incident.get("closing", false)):
		return
	if _assigned(incident) > 0:
		_note(incident, what)
		return
	if int(incident.get("retries", 0)) >= DISPATCH_RETRIES or int(incident.get("failures", 0)) >= DISPATCH_FAILURE_LIMIT:
		_timeline(incident, str(incident.get("stage", "")), str(incident.get("handling", "")), what)
		_close(incident, "unavailable", _unavailable_text(incident))
		return
	var text := what + " Dispatch is looking for another officer."
	if not _transition(incident, "queued", text):
		_note(incident, text)

func _unavailable_text(incident: Dictionary) -> String:
	var sent := int(incident.get("sent", 0)) > 0
	var blocked := bool(incident.get("route_blocked", false))
	if sent and blocked:
		return "No officer could get through to the scene, so dispatch closed the call."
	if sent:
		return "No other officer could take over, so dispatch closed the call."
	if blocked:
		return "No officers could respond: none could get to the scene."
	return "No officers could respond to your call right now."

## Officers still answering this call: one walking back (route failed, call
## done) no longer counts as a response.
func _responding_officers(incident: Dictionary) -> int:
	var count := 0
	for id in incident.get("officers", []):
		var o: Dictionary = _officers.get(id, {})
		if not o.is_empty() and str(o.state) != "return":
			count += 1
	return count

func _responders(incident: Dictionary) -> Dictionary:
	return {"foot": _responding_officers(incident), "cars": _driving_units(incident)}

## Officers physically handling the scene now (not on the way, not walking back).
func _present(incident: Dictionary) -> int:
	var count := 0
	for id in incident.get("officers", []):
		var o: Dictionary = _officers.get(id, {})
		if not o.is_empty() and not str(o.state) in ["respond", "return"]:
			count += 1
	return count

## "En route" is evidence, not a promise: an assigned officer or car must have
## physically moved from where it was dispatched. Card-only (no notice).
func _check_en_route(incident: Dictionary) -> void:
	if str(incident.get("stage", "")) != "dispatched":
		return
	var moved := false
	for id in incident.officers:
		var o: Dictionary = _officers.get(id, {})
		if o.is_empty() or str(o.state) == "return" or not is_instance_valid(o.actor):
			continue
		var origin: Vector3 = o.get("origin", Vector3.INF)
		moved = moved or (origin.is_finite() and Tactics.flat(o.actor.global_position, origin) >= EN_ROUTE_EVIDENCE)
	var cruisers = _cruisers()
	for unit in incident.units:
		if moved or str(unit.state) != "driving" or cruisers == null:
			continue
		var at = cruisers.assist_status(int(unit.slot), str(unit.tag)).get("position", Vector3.INF)
		var origin: Vector3 = unit.get("origin", Vector3.INF)
		if not origin.is_finite() and at is Vector3:
			unit.origin = at
		elif at is Vector3 and (at as Vector3).is_finite() and Tactics.flat(at, origin) >= EN_ROUTE_EVIDENCE:
			moved = true
	if moved:
		_transition(incident, "en_route", "Officer on the way.", "", true, false)

## The officer's route ran out (blocked, or past its deadline) before reaching
## the scene: not an arrival and not a search. They walk back the way they
## came, and this call never sends them down that way again.
func _route_failed(o: Dictionary, incident: Dictionary) -> void:
	counters.route_failures = int(counters.route_failures) + 1
	if not incident.get("excluded") is Dictionary:
		incident.excluded = {}
	incident.excluded[str(o.id)] = true
	incident.failures = int(incident.get("failures", 0)) + 1
	incident.route_blocked = true
	incident.next_retry = _clock
	_finish_officer(o)
	_unit_lost(incident, "An officer could not get through to the scene.")

static func _car_failure_text(reason: String) -> String:
	match reason:
		"no route":
			return "The police car could not find a route to the scene."
		"boxed in without reverse clearance":
			return "The police car was boxed in on the way."
		"disabled":
			return "The police car was disabled on the way."
		"no clear door":
			return "The police car's officer could not get out safely."
		"crew lost":
			return "The police car's officer was hurt."
	return "The police car could not continue to the scene."

## "Dispatch sent ..." for units added after intake (after a wait or a loss).
func _sent_text(incident: Dictionary, foot: int, cars: int, replacement: bool) -> String:
	var parts: Array[String] = []
	if foot > 0:
		var nearest := INF
		for id in incident.officers:
			var o: Dictionary = _officers.get(id, {})
			if not o.is_empty() and str(o.state) != "return" and is_instance_valid(o.actor):
				nearest = minf(nearest, Tactics.flat(o.actor.global_position, Vector3(incident.at)))
		var who := ("another officer on foot" if replacement else "an officer on foot") if foot == 1 else "%d officers on foot" % foot
		parts.append(who + (" (about %d m away)" % int(round(nearest)) if foot == 1 and is_finite(nearest) else ""))
	if cars > 0:
		parts.append(("another police car" if replacement else "a police car") if cars == 1 else "%d police cars" % cars)
	return "Dispatch sent %s." % " and ".join(parts)

func _street(at: Vector3) -> String:
	if level != null and at.is_finite() and level.has_method("_nearest_street"):
		return str(level.call("_nearest_street", at)).left(64)
	return ""

## Game minutes (world_time), the clock the phone and incident records use.
func _minutes() -> float:
	var clock = level.get("world_time") if level != null else null
	if clock != null and clock.get("total_minutes") != null:
		return float(clock.get("total_minutes"))
	return 540.0 + _clock * 0.5

func _notify_handler(incident: Dictionary, event: String, data: Dictionary) -> void:
	var ref := str(incident.get("ref", ""))
	if ref.is_empty() or incident_handler == null or not is_instance_valid(incident_handler):
		return
	if incident_handler.has_method("on_police_progress"):
		incident_handler.on_police_progress(ref, event, data)

## Only actual violence near the call: combat's current fighters (<= 8) and
## recent reports. Nobody is a suspect for being nearby, armed or unknown.
func _discover(incident: Dictionary, center: Vector3) -> void:
	var suspects: Dictionary = incident.suspects
	for entry in _fighters():
		if suspects.size() >= MAX_SUSPECTS:
			break
		var actor = entry.get("actor")
		var id := str(entry.get("id", ""))
		if not str(entry.get("mode", "")) in ["aggro", "gun"] or not _eligible_suspect(actor, id) or _tracked_elsewhere(id, incident):
			continue
		# Hitting back at the rider who crashed into them is not a crime to report.
		if not str(entry.get("provoked", "")).is_empty() or id == str(incident.get("reporter", "")):
			continue
		if Tactics.flat(actor.global_position, center) > SCAN_RADIUS:
			continue
		var known := suspects.has(id)
		var s := _add_suspect(incident, id, actor, str(entry.mode) == "gun", actor.global_position)
		if not s.is_empty() and not known:
			s.shots_seen = int(entry.get("shots", 0))
	for report in _reports:
		if suspects.size() >= MAX_SUSPECTS and not suspects.has(str(report.suspect_id)):
			continue
		if _clock - float(report.clock) > REPORT_TTL or str(report.suspect_id).is_empty():
			continue
		if Tactics.flat(Vector3(report.at), center) > SCAN_RADIUS:
			continue
		var actor = _resolve(str(report.suspect_id))
		if not _eligible_suspect(actor, str(report.suspect_id)) or _tracked_elsewhere(str(report.suspect_id), incident):
			continue
		var s := _add_suspect(incident, str(report.suspect_id), actor, bool(report.armed), Vector3(report.at))
		if not s.is_empty():
			_apply_report_threat(s, report)

func _apply_report_threat(s: Dictionary, report: Dictionary) -> void:
	if int(report.sequence) <= int(s.get("threat_report_sequence", -1)):
		return
	s.threat_report_sequence = int(report.sequence)
	s.armed = bool(report.armed)
	s.threat_revoked = not bool(report.active) or not bool(report.armed)
	s.reported_active_until = -INF if bool(s.threat_revoked) else float(report.clock) + IMMINENT_SECONDS
	if bool(s.threat_revoked):
		s.last_shot = -INF
		var info := _fighter_info(s.actor)
		s.shots_seen = int(info.get("shots", 0))
		for o in _officers.values():
			if str(o.target) == str(s.id):
				o.aim = -1.0

## One incident commands each suspect (two overlapping calls never double up).
func _tracked_elsewhere(id: String, incident: Dictionary) -> bool:
	for other in incidents:
		if str(other.id) != str(incident.id) and not bool(other.closing) and (other.suspects as Dictionary).has(id):
			return true
	return false

func _add_suspect(incident: Dictionary, id: String, actor, armed: bool, seen_at: Vector3) -> Dictionary:
	var suspects: Dictionary = incident.suspects
	if suspects.has(id):
		var known: Dictionary = suspects[id]
		if not bool(known.get("threat_revoked", false)):
			known.armed = bool(known.armed) or armed
		if str(known.state) == "lost" and is_instance_valid(actor):
			known.actor = actor
			known.state = "at_large"
			known.last_seen = seen_at
		return known
	if suspects.size() >= MAX_SUSPECTS:
		return {}
	var s := {"id": id, "actor": actor, "armed": armed, "state": "at_large", "last_seen": seen_at, "seen_clock": -INF,
		"reported": _clock, "shots_seen": 0, "last_shot": -INF, "reported_active_until": -INF,
		"threat_report_sequence": -1, "threat_revoked": false,
		"warned_clock": -INF, "warned": false, "lethal_warned": false, "officer": "", "refusals": 0,
		# Violence found at any scene is detained; report_incident marks infractions "warn".
		"policy": "detain", "contacted": false, "contact_clock": -INF}
	suspects[id] = s
	return s

func _threat_label(incident: Dictionary) -> String:
	var label := "none"
	for s in (incident.get("suspects", {}) as Dictionary).values():
		if bool(s.armed):
			return "armed"
		if str(s.get("policy", "detain")) != "warn":
			label = "violent"
		elif label == "none":
			label = "infraction"
	return label

func _think() -> void:
	counters.thinks = int(counters.thinks) + 1
	_discover_left -= THINK_INTERVAL
	var discover := _discover_left <= 0.0
	if discover:
		_discover_left = DISCOVERY_INTERVAL
	for incident in incidents.duplicate():
		_think_incident(incident, discover)
	while not _reports.is_empty() and _clock - float(_reports[0].clock) > REPORT_TTL:
		_reports.pop_front()

func _think_incident(incident: Dictionary, discover: bool) -> void:
	_check_officers(incident)
	_poll_cruisers(incident)
	if bool(incident.closing):
		if (incident.officers as Array).is_empty() and _driving_units(incident) == 0:
			_archive(incident)
		else:
			for id in (incident.officers as Array).duplicate():
				if _officers.has(id):
					_decide(_officers[id], incident)
		return
	if discover:
		_discover(incident, Vector3(incident.at))
	_update_suspects(incident)
	_retry_dispatch(incident)
	_check_en_route(incident)
	for id in (incident.officers as Array).duplicate():
		if _officers.has(id):
			_decide(_officers[id], incident)
	_evaluate(incident)

func _update_suspects(incident: Dictionary) -> void:
	var combat = _combat()
	for s in (incident.suspects as Dictionary).values():
		var id := str(s.id)
		var state := str(s.state)
		if state in ["dead", "in_custody", "cited", "released"]:
			continue
		if custody.has(id):
			if str(custody.record(id).state) == "in_custody":
				s.state = "in_custody"
			elif not custody.still_held(id, combat):
				# Combat took the body back (hurt, panicked): no longer in hand.
				custody.drop(id)
				s.actor = _resolve(id)
				s.state = "at_large" if is_instance_valid(s.actor) else "lost"
			continue
		var actor = s.actor
		if _dead_id(id) or (is_instance_valid(actor) and actor.get("dead") == true):
			s.state = "dead" # By any cause; police_kills counts police rounds only.
			counters.suspects_dead = int(counters.suspects_dead) + 1
			continue
		if not is_instance_valid(actor):
			actor = _resolve(id)
			s.actor = actor
			if not is_instance_valid(actor):
				s.state = "lost"
				continue
		var mode := _combat_mode(actor)
		if mode == "downed":
			if state != "down":
				s.state = "down"
				counters.suspects_downed = int(counters.suspects_downed) + 1
			continue
		if state == "down":
			# Back on their feet from a knockdown: an arrest, not more force.
			s.state = "warned"
			s.warned = true
			s.warned_clock = _clock - COMPLY_GRACE
		elif state == "lost":
			s.state = "at_large"
		var info := _fighter_info(actor)
		if not info.is_empty() and str(info.get("mode", "")) == "gun":
			if not bool(s.get("threat_revoked", false)):
				s.armed = true
			var shots := int(info.get("shots", 0))
			if shots > int(s.shots_seen):
				s.shots_seen = shots
				s.last_shot = _clock
				s.threat_revoked = false # A new actual shot is fresh evidence.
				s.armed = true

## True only for an armed suspect aiming or firing now (or reported actively
## shooting within IMMINENT_SECONDS). Unarmed or inactive armed suspects: never.
func _imminent(s: Dictionary) -> bool:
	if not bool(s.armed) or bool(s.get("threat_revoked", false)) or not str(s.state) in ["at_large", "warned"]:
		return false
	var actor = s.actor
	if not is_instance_valid(actor):
		return false
	var info := _fighter_info(actor)
	if not info.is_empty():
		if str(info.get("mode", "")) != "gun":
			return false # Current authoritative behavior overrides an older report.
		if float(info.get("aim", -1.0)) >= 0.0 or _clock - float(s.last_shot) <= IMMINENT_SECONDS:
			return true
	return _clock <= float(s.reported_active_until)

func _evaluate(incident: Dictionary) -> void:
	if bool(incident.closing):
		return # Closed mid-think (a unit was lost): nothing more to decide.
	var open := 0
	var lost := 0
	var dead := 0
	var arrested := 0
	var cited := 0
	var engaged := false
	var violent := false
	var suspects: Dictionary = incident.suspects
	for s in suspects.values():
		match str(s.state):
			"at_large", "warned", "held", "down":
				open += 1
			"lost":
				lost += 1
			"dead":
				dead += 1
			"cuffed", "escort", "in_custody":
				arrested += 1
			"cited":
				cited += 1
	for id in incident.officers:
		if _officers.has(id) and str(_officers[id].state) in ["engage", "cuff"]:
			engaged = true
			var target: Dictionary = suspects.get(str(_officers[id].target), {})
			violent = violent or (not target.is_empty() and (str(target.get("policy", "detain")) != "warn" or bool(target.get("armed", false))))
	var age := _clock - float(incident.created)
	if _assigned(incident) == 0 and (int(incident.retries) >= DISPATCH_RETRIES or int(incident.get("failures", 0)) >= DISPATCH_FAILURE_LIMIT):
		_close(incident, "unavailable", _unavailable_text(incident))
		return
	if age > INCIDENT_LIMIT:
		_close(incident, "timeout", "Officers could not resolve the call and are standing down.")
		return
	if open > 0:
		incident.phase = "engaging" if engaged else ("on_scene" if is_finite(float(incident.arrived)) else str(incident.phase))
		# Commands are for violence or a weapon at the scene, never an infraction stop.
		if violent and is_finite(float(incident.arrived)) and not bool(incident.get("confronted", false)):
			incident.confronted = true
			_handling(incident, "commands", "Officers are confronting the suspect.")
		return
	var present := _present(incident)
	if dead == 0 and arrested == 0 and cited == 0:
		# Nobody (left) to deal with: close only after an officer at the scene
		# actually searched it (one who had to leave did not finish checking).
		if not is_finite(float(incident.arrived)) or _clock < float(incident.search_until) or present == 0:
			return
		if lost > 0:
			_close(incident, "suspect_left", "Officers searched, but the suspect had already left.")
		else:
			_close(incident, "no_threat", "Officers checked the area. Nobody there needed help.")
		return
	# Securing needs an officer at the scene until it is done; a completed arrest
	# or warning settles the call by itself. With nobody left there (hurt,
	# disabled), the securing stops and starts over once an officer is back.
	var covered := present > 0 or arrested > 0 or cited > 0
	if is_finite(float(incident.secure_until)) and not covered:
		incident.secure_until = -INF
		incident.phase = "on_scene"
	if not is_finite(float(incident.secure_until)):
		# Officers at the scene secure it; anyone still on the way keeps going. A
		# suspect who died before an officer got there waits for one to arrive.
		if not is_finite(float(incident.arrived)) or not covered:
			return
		incident.secure_until = _clock + secure_seconds
		incident.phase = "securing"
		for id in incident.officers:
			if _officers.has(id) and str(_officers[id].state) in ["search", "engage"]:
				_secure(_officers[id], incident)
		return
	if _clock < float(incident.secure_until):
		return
	if dead > 0:
		var by_police := false
		for s in suspects.values():
			by_police = by_police or (str(s.state) == "dead" and bool(s.get("killed_by_police", false)))
		var text := "Police stopped an armed attacker. The scene is secure."
		if not by_police:
			# Died by another cause: never credited to (or blamed on) police rounds.
			text = "Officers secured the scene. The person involved died." if int(incident.rounds) > 0 \
				else "Officers secured the scene. The person involved died; police did not fire."
		_close(incident, "suspect_killed", text)
	elif arrested > 0:
		_close(incident, "arrested", "The suspect was arrested. The scene is safe.")
	else:
		_close(incident, "warned", "The officer stopped the person and issued a warning.")

func _close(incident: Dictionary, outcome: String, text: String) -> void:
	if bool(incident.closing):
		return
	incident.closing = true
	incident.outcome = outcome
	incident.phase = "closed"
	incident.closed = _clock
	outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
	var abandoned := outcome in ["timeout", "unavailable", "suspect_left", "cancelled"]
	if abandoned:
		for s in (incident.suspects as Dictionary).values():
			if str(s.state) in ["held", "cuffed", "escort"]:
				custody.release(str(s.id))
				s.state = "released"
	_transition(incident, Status.terminal_stage(outcome), text)
	for id in (incident.officers as Array).duplicate():
		if _officers.has(id):
			var o: Dictionary = _officers[id]
			if abandoned:
				o.escort = ""
				o.target = ""
			if (abandoned and str(o.state) != "return") or not str(o.state) in ["escort", "cuff", "return"]:
				_finish_officer(o)
	var cruisers = _cruisers()
	for unit in incident.units:
		if str(unit.state) == "driving":
			unit.state = "cancelled"
			if cruisers != null:
				cruisers.cancel_assist(int(unit.slot), str(unit.tag))

func _archive(incident: Dictionary) -> void:
	if not incidents.has(incident):
		return
	incidents.erase(incident)
	history.append(_summary(incident))
	while history.size() > MAX_HISTORY:
		history.pop_front()

func _summary(incident: Dictionary) -> Dictionary:
	var suspects: Array = []
	for s in (incident.suspects as Dictionary).values():
		suspects.append({"id": str(s.id), "state": str(s.state), "armed": bool(s.armed), "last_seen": s.last_seen,
			"imminent": _imminent(s)})
	var units: Array = []
	for unit in incident.units:
		units.append({"tag": str(unit.tag), "slot": int(unit.slot), "vehicle_id": str(unit.vehicle_id), "state": str(unit.state),
			"reason": str(unit.get("reason", ""))})
	var timeline = incident.get("timeline", [])
	return {"id": str(incident.id), "phase": str(incident.phase), "outcome": str(incident.outcome), "at": incident.at,
		"source": str(incident.source), "suspects": suspects, "units": units, "officers": (incident.officers as Array).duplicate(),
		"message": str(incident.message), "rounds": int(incident.rounds), "age": _clock - float(incident.created),
		"ref": str(incident.get("ref", "")), "policy": str(incident.get("policy", "")), "reporter": str(incident.get("reporter", "")),
		"stage": str(incident.get("stage", "")), "handling": str(incident.get("handling", "")), "kind": str(incident.get("kind", "")),
		"street": str(incident.get("street", "")), "phone": bool(incident.get("phone", false)), "closing": bool(incident.get("closing", false)),
		"threat": _threat_label(incident), "responders": _responders(incident),
		"opened_minutes": float(incident.get("opened_minutes", -1.0)), "updated_minutes": float(incident.get("updated_minutes", -1.0)),
		"timeline": (timeline as Array).duplicate(true) if timeline is Array else []}

func _tell(incident: Dictionary, text: String, structured_status_follows := false) -> void:
	if text.is_empty() or str(incident.get("message", "")) == text:
		return
	incident.message = text
	last_message = text
	# Linked on-scene/closure transitions reach the phone through _status ->
	# incidents. Intermediate messages and unlinked callers keep this fallback.
	var relayed := structured_status_follows and not str(incident.get("ref", "")).is_empty() and is_instance_valid(incident_handler) and incident_handler.has_method("on_police_progress")
	if bool(incident.get("phone", false)) and not relayed:
		var player = level.get("player") if level != null else null
		var phone = player.get("phone") if is_instance_valid(player) else null
		if is_instance_valid(phone) and phone.has_method("set_report_status"):
			phone.set_report_status(text)
	incident_changed.emit(_summary(incident))

func _dispatch_text(incident: Dictionary) -> String:
	var lead := "Dispatch got your report." if str(incident.get("source", "")) == "report" else "Dispatch got your call."
	match _threat_label(incident):
		"armed":
			lead = "Armed suspect reported."
		"violent":
			# A detained theft is not described as violence.
			lead = "Theft reported." if str(incident.get("kind", "")) == "theft" else "Violence reported."
		"infraction":
			lead = "Dispatch got your report."
	var foot := 0
	var nearest := INF
	for id in incident.officers:
		if _officers.has(id) and str(_officers[id].state) != "return":
			foot += 1
			nearest = minf(nearest, Tactics.flat(_officers[id].actor.global_position, Vector3(incident.at)))
	var cars := _driving_units(incident)
	if foot == 0 and cars == 0:
		if bool(incident.get("route_blocked", false)):
			return lead + " No officer can get there yet; dispatch will keep trying."
		return lead + " No officer is free yet; dispatch will keep trying."
	var parts: Array[String] = []
	if foot > 0:
		parts.append("an officer on foot (about %d m away)" % int(round(nearest)) if foot == 1 else "%d officers on foot" % foot)
	if cars > 0:
		parts.append("a police car" if cars == 1 else "%d police cars" % cars)
	return "%s Sending %s." % [lead, " and ".join(parts)]

## A repeat or merged report hears where the existing call stands, by stage.
func _progress_text(incident: Dictionary) -> String:
	match str(incident.get("stage", "")):
		"received", "queued":
			return "Dispatch is still looking for a free officer."
		"dispatched", "en_route":
			return "Officers are already on the way to this location."
		"on_scene":
			return "Officers are already at this location."
		"handling":
			return "Officers are dealing with the suspect now."
	return str(incident.message)

# --------------------------------------------------------------- dispatch

func _officers_wanted(incident: Dictionary) -> int:
	var wanted := 1
	var open := 0
	for s in (incident.suspects as Dictionary).values():
		if str(s.state) in OPEN_STATES:
			open += 1
			if bool(s.armed):
				wanted = 2
	if open >= 2:
		wanted = 2
	return mini(wanted, MAX_UNITS_PER_INCIDENT)

func _assigned(incident: Dictionary) -> int:
	if incident.is_empty():
		return 0
	return _responding_officers(incident) + _driving_units(incident)

func _driving_units(incident: Dictionary) -> int:
	var count := 0
	for unit in incident.get("units", []):
		count += int(str(unit.state) == "driving")
	return count

func _committed() -> int:
	var count := _officers.size()
	for incident in incidents:
		count += _driving_units(incident)
	return count

func _goal(incident: Dictionary) -> Vector3:
	var best := Vector3(incident.at)
	var newest := -INF
	for s in (incident.suspects as Dictionary).values():
		if str(s.state) in ["at_large", "warned", "down"] and Vector3(s.last_seen).is_finite():
			var when := maxf(float(s.seen_clock), float(s.reported))
			if when > newest:
				newest = when
				best = s.last_seen
	return best

func _retry_dispatch(incident: Dictionary) -> void:
	if _assigned(incident) >= _officers_wanted(incident) or _clock < float(incident.next_retry):
		return
	if int(incident.retries) >= DISPATCH_RETRIES or int(incident.get("failures", 0)) >= DISPATCH_FAILURE_LIMIT:
		return
	var before := _assigned(incident)
	_dispatch(incident)
	if _assigned(incident) == before:
		incident.retries = int(incident.retries) + 1
		incident.next_retry = _clock + RETRY_SECONDS

## Closest real foot patrol first; a cruiser for distant or armed calls; then
## any other patrol in range. At most MAX_ROUTE_PLANS foot routes per call. An
## officer whose route to this call already failed is not sent again.
func _dispatch(incident: Dictionary) -> void:
	var needed := mini(_officers_wanted(incident) - _assigned(incident), MAX_OFFICERS - _committed())
	if needed <= 0:
		return
	var foot_before := _responding_officers(incident)
	var cars_before := _driving_units(incident)
	var excluded: Dictionary = incident.get("excluded", {}) if incident.get("excluded") is Dictionary else {}
	var goal := _goal(incident)
	var cruisers = _cruisers()
	var car_possible: bool = cruisers != null and bool(cruisers.get("available")) and cruisers.has_method("request_assist")
	var candidates := _foot_candidates(goal)
	var plans := 0
	for candidate in candidates:
		if needed <= 0 or plans >= MAX_ROUTE_PLANS:
			break
		if float(candidate.distance) > CRUISER_PREFERRED_DISTANCE and car_possible:
			break
		if excluded.has(str(candidate.actor.actor_id)):
			continue
		plans += 1
		if _send_foot(incident, candidate.actor, goal):
			needed -= 1
	if needed > 0 and car_possible and _committed() < MAX_OFFICERS:
		var tag := "%s:%d" % [incident.id, (incident.units as Array).size() + 1]
		var result: Dictionary = cruisers.request_assist(goal, tag)
		if bool(result.get("ok", false)):
			var claimed: Dictionary = cruisers.assist_status(int(result.slot), tag) if cruisers.has_method("assist_status") else {}
			incident.units.append({"tag": tag, "slot": int(result.slot), "vehicle_id": str(result.get("vehicle_id", "")),
				"state": "driving", "claimed": _clock, "reason": "", "origin": claimed.get("position", Vector3.INF)})
			counters.cruiser_dispatches = int(counters.cruiser_dispatches) + 1
			needed -= 1
		else:
			incident.cruiser_refusal = str(result.get("reason", ""))
	for candidate in candidates:
		if needed <= 0 or plans >= MAX_ROUTE_PLANS or _committed() >= MAX_OFFICERS:
			break
		if _officers.has(str(candidate.actor.actor_id)) or excluded.has(str(candidate.actor.actor_id)):
			continue
		plans += 1
		if _send_foot(incident, candidate.actor, goal):
			needed -= 1
	var foot_added := _responding_officers(incident) - foot_before
	var cars_added := _driving_units(incident) - cars_before
	if foot_added + cars_added > 0:
		var replacement := int(incident.get("sent", 0)) > 0
		incident.sent = int(incident.get("sent", 0)) + foot_added + cars_added
		if str(incident.phase) == "dispatching":
			incident.phase = "en_route"
		# Intake announces its own first dispatch; later units are news here.
		if not str(incident.get("stage_key", "")).is_empty():
			if replacement:
				counters.replacements = int(counters.replacements) + 1
			if foot_before + cars_before > 0:
				_note(incident, "Dispatch sent another officer to help.")
			else:
				_transition(incident, "dispatched", _sent_text(incident, foot_added, cars_added, replacement))
	if _assigned(incident) == 0:
		incident.next_retry = _clock + RETRY_SECONDS

func _foot_candidates(goal: Vector3) -> Array:
	var result: Array = []
	var stale := false
	for actor in _patrols:
		if not is_instance_valid(actor):
			stale = true
			continue
		if not _free_officer(actor):
			continue
		var distance := Tactics.flat(actor.global_position, goal)
		if distance <= FOOT_DISPATCH_RADIUS:
			result.append({"actor": actor, "distance": distance})
	if stale:
		_patrols = _scan_patrols()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return result

func _free_officer(actor) -> bool:
	if not _usable(actor):
		return false
	if actor.get("combat_override") == true:
		# Hearing a shot can alert a free patrol before the phone call arrives.
		# Such police may answer dispatch; fighters/downed/other owners may not.
		if not _is_police(actor) or not _combat_mode(actor) in ["panic:alert", "panic:return"]:
			return false
	if actor.has_meta("law_responder") or actor.has_meta("police_assist") or actor.has_meta("police_crew"):
		return false
	var law = _law()
	var responders = law.get("_responders") if law != null else null
	return not (responders is Dictionary and (responders as Dictionary).has(str(actor.actor_id)))

func _send_foot(incident: Dictionary, actor, goal: Vector3) -> bool:
	if not _free_officer(actor):
		return false
	var path := _route(actor.global_position, goal)
	if path.is_empty():
		incident.route_blocked = true # A free officer exists but cannot get there.
		return false
	if actor.get("combat_override") == true:
		var combat = _combat()
		if not _combat_mode(actor) in ["panic:alert", "panic:return"] or combat == null or not combat.has_method("disengage_actor"):
			return false
		combat.disengage_actor(actor)
		if not _usable(actor) or actor.get("combat_override") == true:
			return false
	var o := _adopt(actor, incident, "foot")
	_apply_path(o, path, goal, JOG_SPEED, "respond")
	counters.foot_dispatches = int(counters.foot_dispatches) + 1
	actor.speak("Dispatch, I'm on my way.", 2.0)
	return true

func _adopt(actor, incident: Dictionary, kind: String) -> Dictionary:
	var id := str(actor.actor_id)
	actor.combat_override = true
	actor.set_meta("police_assist", str(incident.id))
	# Combat's ambient gunfire hearing skips law responders (city_combat _react).
	actor.set_meta("law_responder", true)
	actor.has_target = false
	actor.velocity = Vector3.ZERO
	var o := {"actor": actor, "id": id, "incident": str(incident.id), "kind": kind, "slot": 0, "tag": "", "door": Vector3.INF,
		"state": "respond", "path": [], "index": 0, "goal": actor.global_position, "speed": JOG_SPEED, "deadline": INF,
		"trail": [actor.global_position], "trail_overflow": false, "stuck": 0.0, "unstick": 0, "replan_at": 0.0,
		"home_speed": float(actor.speed), "target": "", "escort": "", "face": Vector3.INF, "aim": -1.0, "cooldown": 0.0,
		"rounds": 0, "gun": null, "muzzle": null, "timer": 0.0, "search_points": [], "search_index": 0,
		"hold_reason": "", "escort_until": INF, "spoke_hold": false, "origin": actor.global_position}
	_officers[id] = o
	incident.officers.append(id)
	return o

## Street route for walking (law's surveyed graph; a short clear link otherwise).
func _route(from: Vector3, to: Vector3) -> Array:
	var path: Array = []
	if not from.is_finite() or not to.is_finite():
		return path
	if Tactics.flat(from, to) <= ARRIVE_RADIUS:
		path.append(to)
		return path
	counters.routes = int(counters.routes) + 1
	var law = _law()
	var routes = law.get("routes") if law != null else null
	if routes != null and routes.has_method("route"):
		var plan: Dictionary = routes.route(from, to, FOOT_ROUTE_LIMIT)
		for point in plan.get("points", PackedVector3Array()):
			path.append(point)
	elif Tactics.flat(from, to) <= 36.0 and tactics.link_clear(from, to):
		path.append(to)
	if path.is_empty():
		counters.route_failures = int(counters.route_failures) + 1
	return path

func _apply_path(o: Dictionary, path: Array, goal: Vector3, speed: float, state: String) -> void:
	o.path = path
	o.index = 0
	o.goal = goal
	o.speed = speed
	o.state = state
	o.stuck = 0.0
	o.face = Vector3.INF
	var length := 0.0
	var previous: Vector3 = o.actor.global_position
	for point in path:
		length += previous.distance_to(point)
		previous = point
	o.deadline = _clock + length / maxf(speed, 0.5) + RESPOND_GRACE

func _send(o: Dictionary, goal: Vector3, speed: float, state: String) -> void:
	var path := _route(o.actor.global_position, goal)
	_apply_path(o, path, goal, speed, state)

func _poll_cruisers(incident: Dictionary) -> void:
	var cruisers = _cruisers()
	for unit in incident.units:
		if str(unit.state) != "driving":
			continue
		var status: Dictionary = cruisers.assist_status(int(unit.slot), str(unit.tag)) if cruisers != null else {}
		var mode := str(status.get("mode", ""))
		if mode == "dismounted":
			# Stepped out without being adopted (call already closing, or the
			# officer could not take over): the cruiser's own crew upkeep walks
			# them back and drives off.
			unit.state = "unadopted"
			_unit_lost(incident, "An officer is no longer available for this call.")
			continue
		if status.is_empty() or mode in ["depart", "abandoned"]:
			# The car could not get its officer here (blocked, no door, no route).
			unit.state = "failed"
			unit.reason = str(status.get("abandon_reason", "released")) if not status.is_empty() else "released"
			counters.cruiser_failures = int(counters.cruiser_failures) + 1
			if cruisers != null and not status.is_empty():
				cruisers.cancel_assist(int(unit.slot), str(unit.tag))
			incident.next_retry = _clock
			incident.failures = int(incident.get("failures", 0)) + 1
			_unit_lost(incident, _car_failure_text(str(unit.reason)))

func _check_officers(incident: Dictionary) -> void:
	for id in (incident.officers as Array).duplicate():
		var o: Dictionary = _officers.get(id, {})
		if o.is_empty():
			incident.officers.erase(id)
			continue
		var actor = o.actor
		var mode := _combat_mode(actor) if is_instance_valid(actor) else "gone"
		if _usable(actor) and mode == "unknown":
			continue
		# Hurt, downed, killed or taken over by combat: no longer ours to move.
		# Those stay combat's; a body merely disabled or removed is handed back
		# to normal life rather than left frozen under this service's hold.
		var returning := str(o.state) == "return"
		var hurt: bool = mode in ["dead", "downed"] or (is_instance_valid(actor) and actor.get("dead") == true)
		counters.officers_lost = int(counters.officers_lost) + 1
		_release_officer(o)
		if not bool(incident.closing) and not returning:
			incident.next_retry = _clock
			_unit_lost(incident, "An officer was hurt." if hurt else "An officer is no longer available for this call.")

# --------------------------------------------------------------- officer decisions (4 Hz)

func _decide(o: Dictionary, incident: Dictionary) -> void:
	var actor = o.actor
	if float(o.stuck) >= STUCK_SECONDS:
		_unstick(o)
	match str(o.state):
		"respond":
			if not bool(incident.closing):
				_perceive(o, incident)
				if not str(o.target).is_empty():
					_engage(o, incident)
					return
			if Tactics.flat(actor.global_position, Vector3(o.goal)) <= 3.0:
				if bool(incident.closing):
					_finish_officer(o)
				else:
					_arrive_scene(o, incident)
			elif int(o.index) >= (o.path as Array).size() or _clock > float(o.deadline):
				if bool(incident.closing):
					_finish_officer(o)
				else:
					_route_failed(o, incident) # Not an arrival or a search of the scene.
		"search":
			_perceive(o, incident)
			if not str(o.target).is_empty():
				_engage(o, incident)
				return
			if int(o.index) >= (o.path as Array).size():
				var points: Array = o.search_points
				var next := int(o.search_index)
				if next < points.size():
					o.search_index = next + 1
					_send(o, points[next], WALK_SPEED, "search")
				else:
					o.face = Vector3(incident.at)
		"engage":
			_engage(o, incident)
		"cuff":
			if float(o.timer) >= CUFF_SECONDS:
				_cuffed(o, incident)
		"escort":
			_escort(o, incident)
		"secure":
			if bool(incident.closing):
				_finish_officer(o)
		"return":
			if int(o.index) >= (o.path as Array).size() or _clock > float(o.deadline):
				_release_officer(o)

func _arrive_scene(o: Dictionary, incident: Dictionary) -> void:
	if Tactics.flat(o.actor.global_position, Vector3(o.goal)) > 3.0:
		return
	_mark_arrived(incident)
	o.search_points = _search_points(_goal(incident), o.actor.global_position)
	o.search_index = 0
	_apply_path(o, [], o.actor.global_position, WALK_SPEED, "search")
	o.actor.speak("Police! Is everyone okay out here?", 2.0)

func _mark_arrived(incident: Dictionary) -> void:
	if not is_finite(float(incident.arrived)):
		incident.arrived = _clock
		incident.phase = "on_scene"
		counters.arrivals = int(counters.arrivals) + 1
		incident.search_until = _clock + search_seconds
		_transition(incident, "on_scene", "An officer has arrived and is checking the area.")
	elif str(incident.get("stage", "")) in Status.PRE_ARRIVAL:
		# A replacement reached a scene the first unit had to leave: it searches
		# afresh rather than inheriting an earlier, unfinished check.
		incident.search_until = maxf(float(incident.search_until), _clock + search_seconds)
		_transition(incident, "on_scene", "Another officer has arrived and is checking the area.")

func _search_points(center: Vector3, from: Vector3) -> Array:
	var result: Array = []
	if not center.is_finite():
		return result
	# The caller usually stands at the call location: look around them, never walk into them.
	var player = level.get("player") if level != null else null
	var caller: Vector3 = (player as Node3D).global_position if player is Node3D else Vector3.INF
	var previous := from
	if Tactics.flat(center, from) > 2.0 and _clear_of(caller, from, center, 2.0):
		result.append(center)
		previous = center
	var heading := Vector3(from.x - center.x, 0.0, from.z - center.z)
	heading = heading.normalized() if heading.length_squared() > 0.01 else Vector3.BACK
	# Either side of the scene, then its far side: each leg keeps clear of the caller.
	for angle in [1.4, -1.4, PI]:
		var spot := tactics.walkable(center + heading.rotated(Vector3.UP, float(angle)) * SEARCH_RADIUS)
		if spot.is_empty() or not tactics.link_clear(center, spot.position) or not _clear_of(caller, previous, spot.position, 1.4):
			continue
		result.append(spot.position)
		previous = spot.position
	return result

static func _clear_of(point: Vector3, a: Vector3, b: Vector3, radius: float) -> bool:
	if not point.is_finite():
		return true
	var flat_point := Vector3(point.x, 0.0, point.z)
	var closest := Geometry3D.get_closest_point_to_segment(flat_point, Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z))
	return closest.distance_to(flat_point) >= radius

## Up to two sight checks: the current target first, then other open suspects.
func _perceive(o: Dictionary, incident: Dictionary) -> void:
	var actor = o.actor
	var order: Array = []
	var suspects: Dictionary = incident.suspects
	if suspects.has(str(o.target)):
		order.append(suspects[str(o.target)])
	for id in suspects:
		if str(id) != str(o.target):
			order.append(suspects[id])
	var checked := 0
	for s in order:
		if checked >= 2:
			break
		if not str(s.state) in ["at_large", "warned", "down", "lost"] or not is_instance_valid(s.actor):
			continue
		var body: Node3D = s.actor
		var offset := Vector3(body.global_position.x - actor.global_position.x, 0.0, body.global_position.z - actor.global_position.z)
		var distance := offset.length()
		if distance > SIGHT_RANGE:
			continue
		if distance > NOTICE_RADIUS and Tactics.forward_of(actor).dot(offset / maxf(distance, 0.001)) < VIEW_DOT:
			continue
		checked += 1
		if _sees(o, s):
			if str(o.target) != str(s.id):
				counters.sightings = int(counters.sightings) + 1
			o.target = str(s.id)
			return

func _sees(o: Dictionary, s: Dictionary) -> bool:
	var body = s.actor
	if not is_instance_valid(body):
		return false
	var skip: Array[RID] = [o.actor.get_rid(), body.get_rid()]
	if tactics.sees(Tactics.eye_of(o.actor), Tactics.chest_of(body), skip):
		s.last_seen = body.global_position
		s.seen_clock = _clock
		return true
	return false

func _engage(o: Dictionary, incident: Dictionary) -> void:
	var actor = o.actor
	var suspects: Dictionary = incident.suspects
	var s: Dictionary = suspects.get(str(o.target), {})
	if s.is_empty() or not str(s.state) in ["at_large", "warned", "held", "down"]:
		_next_target(o, incident)
		return
	o.state = "engage"
	var body = s.actor
	if not is_instance_valid(body):
		_next_target(o, incident)
		return
	var state := str(s.state)
	if state in ["held", "down"] and Tactics.flat(actor.global_position, body.global_position) <= WARN_RANGE and _sees(o, s):
		_mark_arrived(incident)
	if state == "down":
		# Neutralized by force: cover them from close by; arrest if they recover.
		o.aim = -1.0
		_approach(o, body.global_position, COVER_DISTANCE, WALK_SPEED)
		return
	if state == "held":
		_holster(o)
		o.aim = -1.0
		if not str(s.officer).is_empty() and str(s.officer) != str(o.id) and _officers.has(str(s.officer)):
			_approach(o, body.global_position, COVER_DISTANCE, WALK_SPEED) # A partner cuffs; this one covers.
			return
		s.officer = str(o.id)
		if Tactics.flat(actor.global_position, body.global_position) <= CUFF_RANGE + 0.2:
			_stop(o)
			o.face = body.global_position
			o.state = "cuff"
			o.timer = 0.0
			actor.speak("Hands behind your back.", 1.8)
		else:
			_approach(o, body.global_position, CUFF_RANGE, WALK_SPEED)
		return
	var sees := _sees(o, s)
	if not sees:
		o.aim = -1.0
		if _clock - float(s.seen_clock) > LOST_SIGHT_SECONDS:
			o.target = ""
			o.search_points = _search_points(Vector3(s.last_seen), actor.global_position)
			o.search_index = 0
			_apply_path(o, [], actor.global_position, WALK_SPEED, "search")
			actor.speak("Lost sight of them. Checking around.", 1.8)
			return
		_approach(o, Vector3(s.last_seen), 2.0, JOG_SPEED)
		return
	var distance := Tactics.flat(actor.global_position, body.global_position)
	if distance <= (FIRE_RANGE if _imminent(s) else WARN_RANGE):
		# A visible encounter within action range is a physical on-scene response,
		# even when the officer found the suspect before reaching the call marker.
		_mark_arrived(incident)
	if str(s.get("policy", "detain")) == "warn" and not bool(s.armed):
		_stop_for_warning(o, incident, s, distance)
		return
	if _imminent(s):
		_draw(o)
		if distance > FIRE_RANGE:
			o.aim = -1.0
			_approach(o, body.global_position, FIRE_RANGE - 4.0, JOG_SPEED)
			return
		_stop(o)
		o.face = body.global_position
		if not bool(s.lethal_warned):
			# Always a spoken warning first; the aim telegraph follows next decision.
			s.lethal_warned = true
			if bool(s.warned):
				o.actor.speak("Police! Drop the weapon!", 2.0)
				counters.warnings = int(counters.warnings) + 1
			else:
				_warn(o, s, "Police! Drop the weapon!")
			return
		var wanted := Tactics.heading_to(actor.global_position, body.global_position, float(actor.yaw))
		if float(o.aim) < 0.0 and float(o.cooldown) <= 0.0 and absf(angle_difference(float(actor.yaw), wanted)) < 0.12:
			o.aim = 0.0
			counters.telegraphs = int(counters.telegraphs) + 1
		return
	# Not an imminent lethal threat: approach, warn, detain. Never fire.
	o.aim = -1.0
	if bool(s.armed):
		_draw(o)
	else:
		_holster(o)
	if distance > WARN_RANGE:
		_approach(o, body.global_position, WARN_RANGE - 2.0, JOG_SPEED)
		return
	_stop(o)
	o.face = body.global_position
	if not bool(s.warned):
		_warn(o, s, "Police! Put the weapon down, slowly!" if bool(s.armed) else "Police! Stop! Hands where I can see them!")
		return
	if _clock - float(s.warned_clock) >= (COMPLY_GRACE if bool(s.armed) else WARN_SECONDS):
		_comply(o, incident, s)

## An infraction (policy "warn"): walk up, stop the person (the incident service
## holds them facing the officer), then a warning. No force, cuffs or custody.
func _stop_for_warning(o: Dictionary, incident: Dictionary, s: Dictionary, distance: float) -> void:
	var body = s.actor
	_holster(o)
	o.aim = -1.0
	if distance > CITE_RANGE:
		o.citing = false
		_approach(o, body.global_position, CITE_RANGE - 0.4, JOG_SPEED if distance > 8.0 else WALK_SPEED)
		return
	_stop(o)
	o.face = body.global_position
	if not bool(s.contacted):
		s.contacted = true
		s.contact_clock = _clock
		s.officer = str(o.id)
		if str(s.state) == "at_large":
			s.state = "warned"
		o.citing = true
		_mark_arrived(incident)
		_notify_handler(incident, "contact", {"suspect_id": str(s.id), "officer_id": str(o.id)})
		_handling(incident, "contact", "An officer stopped the person to talk.")
		return
	if _clock - float(s.contact_clock) >= CITE_SECONDS:
		s.state = "cited"
		o.citing = false
		counters.citations = int(counters.citations) + 1
		_notify_handler(incident, "cited", {"suspect_id": str(s.id), "officer_id": str(o.id)})
		_handling(incident, "warning", "The officer issued a warning.")
		_next_target(o, incident)

func _warn(o: Dictionary, s: Dictionary, line: String) -> void:
	if bool(s.warned):
		return
	s.warned = true
	s.warned_clock = _clock
	s.officer = str(o.id)
	if str(s.state) == "at_large":
		s.state = "warned"
	counters.warnings = int(counters.warnings) + 1
	o.actor.speak(line, 2.0)

## The warned suspect complies: combat lets go of them, custody holds them.
func _comply(o: Dictionary, incident: Dictionary, s: Dictionary) -> void:
	var body = s.actor
	var mode := _combat_mode(body)
	var combat = _combat()
	if mode in ["aggro", "gun", "return"] or mode.begins_with("panic:"):
		if combat != null and combat.has_method("disengage_actor"):
			combat.disengage_actor(body)
	elif mode == "unknown" and is_instance_valid(body) and body.has_meta("incident_performer") \
			and incident_handler != null and incident_handler.has_method("release_for_custody"):
		# The incident service lets go of its performer (a crowd stand-in returns
		# to its slot) so custody can hold the same person in the same spot.
		if bool(incident_handler.release_for_custody(str(s.id))):
			counters.handoffs = int(counters.handoffs) + 1
	var held = custody.take(body, str(s.id), self, _clock)
	if held == null:
		s.refusals = int(s.refusals) + 1
		counters.custody_refusals = int(counters.custody_refusals) + 1
		if int(s.refusals) >= 3:
			s.state = "lost" # Another system owns this person; do not keep pressing.
		return
	s.actor = held
	s.state = "held"
	s.officer = str(o.id)
	counters.compliances = int(counters.compliances) + 1
	held.speak("Okay, okay! I'm not doing anything!", 2.0)
	_handling(incident, "detaining", "Officers are detaining a suspect.")

func _cuffed(o: Dictionary, incident: Dictionary) -> void:
	var s: Dictionary = (incident.suspects as Dictionary).get(str(o.target), {})
	if s.is_empty() or str(s.state) != "held":
		_next_target(o, incident)
		return
	if not is_instance_valid(s.actor) or Tactics.flat(o.actor.global_position, s.actor.global_position) > CUFF_RANGE + 0.2 or not _sees(o, s):
		o.state = "engage"
		o.timer = 0.0
		return # Cuffing needs sustained physical proximity, not just elapsed time.
	s.state = "cuffed"
	custody.set_state(str(s.id), "cuffed")
	counters.arrests = int(counters.arrests) + 1
	o.actor.speak("You're under arrest.", 2.0)
	_handling(incident, "arrest", "The suspect has been arrested.")
	_begin_escort(o, s)

func _begin_escort(o: Dictionary, s: Dictionary) -> void:
	s.state = "escort"
	custody.set_state(str(s.id), "escort")
	o.escort = str(s.id)
	o.target = ""
	o.escort_until = _clock + ESCORT_LIMIT
	var goal := Vector3.INF
	if str(o.kind) == "crew" and Vector3(o.door).is_finite() and _crew_car_waiting(o):
		goal = o.door
	elif _station.is_finite():
		goal = _station
	if goal.is_finite():
		_send(o, goal, ESCORT_SPEED, "escort")
	else:
		_apply_path(o, [], o.actor.global_position, ESCORT_SPEED, "escort")

func _crew_car_waiting(o: Dictionary) -> bool:
	var cruisers = _cruisers()
	if cruisers == null or str(o.tag).is_empty():
		return false
	return str(cruisers.assist_status(int(o.slot), str(o.tag)).get("mode", "")) == "dismounted"

func _escort(o: Dictionary, incident: Dictionary) -> void:
	var id := str(o.escort)
	var s: Dictionary = (incident.suspects as Dictionary).get(id, {})
	var body = custody.body_of(id)
	if s.is_empty() or body == null or str(s.state) != "escort":
		o.escort = ""
		_finish_officer(o)
		return
	var actor = o.actor
	var placed := false
	if str(o.kind) == "crew" and Vector3(o.door).is_finite() and _crew_car_waiting(o):
		placed = Tactics.flat(actor.global_position, Vector3(o.door)) <= 2.5 and Tactics.flat(body.global_position, Vector3(o.door)) <= 4.0
	if not placed and _station.is_finite() and Tactics.flat(Vector3(o.goal), _station) < 0.25:
		placed = Tactics.flat(actor.global_position, _station) <= 2.5 and Tactics.flat(body.global_position, _station) <= 4.0 \
			and tactics.link_clear(body.global_position, _station)
	if not placed and _unseen(actor) and _unseen(body):
		placed = true # Walked out of view toward the precinct.
	if placed:
		custody.take_in(id)
		s.state = "in_custody"
		counters.taken_in = int(counters.taken_in) + 1
		o.escort = ""
		_finish_officer(o)
		return
	if _clock > float(o.escort_until) and int(o.index) < (o.path as Array).size():
		_stop(o) # Long walk: wait with the suspect until nobody is watching.

func _secure(o: Dictionary, incident: Dictionary) -> void:
	o.target = ""
	o.aim = -1.0
	_stop(o)
	o.state = "secure"
	o.face = Vector3(incident.at)

func _next_target(o: Dictionary, incident: Dictionary) -> void:
	o.target = ""
	o.aim = -1.0
	for s in (incident.suspects as Dictionary).values():
		if str(s.state) in ["at_large", "warned", "held", "down"]:
			_apply_path(o, [], o.actor.global_position, WALK_SPEED, "search")
			o.search_points = _search_points(Vector3(s.last_seen), o.actor.global_position)
			o.search_index = 0
			return
	if not is_finite(float(incident.arrived)) and not bool(incident.closing):
		# Nobody left to confront, but no officer has reached the scene: keep
		# going there instead of "securing" a spot down the street.
		_send(o, Vector3(incident.at), JOG_SPEED, "respond")
		return
	_secure(o, incident)

## Close in until `stop` metres away: a straight swept link when clear, else a route.
func _approach(o: Dictionary, point: Vector3, stop: float, speed: float) -> void:
	var actor = o.actor
	var at: Vector3 = actor.global_position
	var offset := Vector3(point.x - at.x, 0.0, point.z - at.z)
	if offset.length() <= stop:
		_stop(o)
		o.face = point
		return
	var goal := point - offset.normalized() * stop
	var path: Array = o.path
	if int(o.index) < path.size() and Tactics.flat(Vector3(o.goal), goal) <= (0.25 if str(o.state) == "engage" else 2.5):
		return
	if _clock < float(o.replan_at):
		return
	o.replan_at = _clock + REPLAN_SECONDS
	var state := str(o.state)
	if tactics.link_clear(at, goal):
		_apply_path(o, [goal], goal, speed, state)
	else:
		_apply_path(o, _route(at, goal), goal, speed, state)

func _stop(o: Dictionary) -> void:
	o.path = []
	o.index = 0
	o.stuck = 0.0

## Bounded recovery from a blocked step: sidestep, replan once, skip a
## waypoint, then stop pushing. Never moves anyone through geometry.
func _unstick(o: Dictionary) -> void:
	o.stuck = 0.0
	o.unstick = int(o.unstick) + 1
	counters.unsticks = int(counters.unsticks) + 1
	var actor = o.actor
	var path: Array = o.path
	var index := int(o.index)
	if int(o.unstick) > MAX_UNSTICK or index >= path.size():
		_stop(o)
		if str(o.state) == "return":
			_release_officer(o)
		return
	var at: Vector3 = actor.global_position
	var point: Vector3 = path[index]
	if int(o.unstick) == 2:
		var fresh := _route(at, Vector3(o.goal))
		if not fresh.is_empty():
			o.path = fresh
			o.index = 0
			return
	var forward := Vector3(point.x - at.x, 0.0, point.z - at.z).normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * (1.0 if int(o.unstick) % 2 == 1 else -1.0)
	for offset in [side, -side]:
		var spot := tactics.walkable(at + offset * 1.4 + forward * 0.4)
		if not spot.is_empty() and tactics.link_clear(at, spot.position):
			path.insert(index, spot.position)
			return
	if index + 1 < path.size():
		o.index = index + 1

## Done with this incident: holster and walk back (crew to the car door, foot
## patrols retrace the ground they covered), then rejoin normal life.
func _finish_officer(o: Dictionary) -> void:
	_holster(o)
	o.target = ""
	o.aim = -1.0
	var actor = o.actor
	var path: Array = []
	if str(o.kind) == "crew" and Vector3(o.door).is_finite():
		path = _route(actor.global_position, Vector3(o.door))
	if path.is_empty():
		var trail: Array = o.trail
		var last: Vector3 = actor.global_position
		for i in range(trail.size() - 1, -1, -1):
			var point: Vector3 = trail[i]
			if Tactics.flat(point, last) >= 1.0:
				path.append(point)
				last = point
	var home: Vector3 = o.door if str(o.kind) == "crew" and Vector3(o.door).is_finite() else Vector3(o.trail[0])
	if path.is_empty() and Tactics.flat(actor.global_position, home) > ARRIVE_RADIUS:
		path.append(home)
	_apply_path(o, path, home, WALK_SPEED, "return")
	o.deadline = _clock + float(o.deadline - _clock - RESPOND_GRACE) + 20.0

func _release_officer(o: Dictionary) -> void:
	var id := str(o.id)
	_officers.erase(id)
	var incident := _incident_by_id(str(o.incident))
	if not incident.is_empty():
		incident.officers.erase(id)
		if bool(incident.closing) and (incident.officers as Array).is_empty() and _driving_units(incident) == 0:
			_archive(incident)
	_holster(o)
	var actor = o.actor
	if not is_instance_valid(actor):
		return
	var ours := _combat_mode(actor) == "unknown"
	for key in ["police_assist", "law_responder"]:
		if actor.has_meta(key):
			actor.remove_meta(key)
	if actor.get("dead") == true or not ours:
		return
	actor.combat_override = false
	actor.speed = float(o.home_speed)
	actor.manual_target = false
	actor.has_target = false
	actor.blocked = false
	actor.blocked_seconds = 0.0
	var points: Array = actor.patrol_points
	if not points.is_empty():
		var nearest := 0
		var best := INF
		for i in points.size():
			var distance: float = actor.global_position.distance_squared_to(points[i])
			if distance < best:
				best = distance
				nearest = i
		actor.patrol_index = nearest
	if actor.puppet != null:
		actor.puppet.pose({"walk": 0.0})
	counters.releases = int(counters.releases) + 1
	if str(o.kind) == "crew":
		var cruisers = _cruisers()
		if cruisers != null and cruisers.has_method("assist_remount") and bool(cruisers.assist_remount(actor)):
			counters.remounts = int(counters.remounts) + 1
		# Otherwise the cruiser's crew upkeep walks them back to the car (law return leg).

# --------------------------------------------------------------- per-frame motion

func _move_officer(o: Dictionary, delta: float) -> void:
	var actor = o.actor
	if not _usable(actor) or actor.get("combat_override") != true:
		return
	Tactics.tick_body(actor, delta)
	o.cooldown = maxf(0.0, float(o.cooldown) - delta)
	if str(o.state) == "cuff":
		o.timer = float(o.timer) + delta
	var path: Array = o.path
	var index := int(o.index)
	var waiting := str(o.state) == "escort" and _escort_lag(o) > ESCORT_LAG
	if index < path.size() and not waiting and float(o.aim) < 0.0:
		var point: Vector3 = path[index]
		# A broad street waypoint tolerance is unsuitable for a cuffing approach:
		# stopping 1.2m short of the 1.5m stand-off leaves cuffs forever out of reach.
		var tolerance := 0.12 if index == path.size() - 1 and str(o.state) == "engage" else ARRIVE_RADIUS
		if Tactics.flat(actor.global_position, point) <= tolerance:
			o.index = index + 1
			o.stuck = 0.0
		else:
			var result := Tactics.walk(actor, point, delta, float(o.speed))
			if result == Tactics.MOVE_BLOCKED:
				o.stuck = float(o.stuck) + delta
			elif result == Tactics.MOVE_MOVED:
				o.stuck = maxf(0.0, float(o.stuck) - delta)
	elif Vector3(o.face).is_finite():
		Tactics.face(actor, Tactics.heading_to(actor.global_position, Vector3(o.face), float(actor.yaw)), delta, 0.02)
	if float(o.aim) >= 0.0:
		_track_target(o, delta)
		o.aim = float(o.aim) + delta
		if float(o.aim) >= AIM_SECONDS:
			o.aim = -1.0
			o.cooldown = ROUND_COOLDOWN
			_fire(o)
	_record_trail(o)
	_pose_officer(o)

func _track_target(o: Dictionary, delta: float) -> void:
	var incident := _incident_by_id(str(o.incident))
	var s: Dictionary = (incident.get("suspects", {}) as Dictionary).get(str(o.target), {})
	if not s.is_empty() and is_instance_valid(s.actor):
		o.face = s.actor.global_position
		Tactics.face(o.actor, Tactics.heading_to(o.actor.global_position, o.face, float(o.actor.yaw)), delta, 0.02)

func _escort_lag(o: Dictionary) -> float:
	var body = custody.body_of(str(o.escort))
	return Tactics.flat(o.actor.global_position, body.global_position) if body != null else 0.0

func _record_trail(o: Dictionary) -> void:
	if str(o.state) == "return" or bool(o.trail_overflow):
		return
	var at: Vector3 = o.actor.global_position
	var trail: Array = o.trail
	if trail.is_empty() or Tactics.flat(at, trail[-1]) >= TRAIL_SPACING:
		if trail.size() >= MAX_TRAIL:
			o.trail_overflow = true
			return
		trail.append(at)

func _pose_officer(o: Dictionary) -> void:
	var actor = o.actor
	if actor.puppet == null:
		return
	var walk: float = (0.7 if float(o.speed) > 2.5 else 0.45) if actor.moving else 0.0
	if is_instance_valid(o.gun):
		var raise := 0.0
		if float(o.aim) >= 0.0:
			raise = clampf(float(o.aim) / AIM_SECONDS, 0.0, 1.0)
		elif float(o.cooldown) > ROUND_COOLDOWN - 0.35:
			raise = 1.0
		actor.puppet.pose({"walk": walk, "armR": [-0.9 - 0.55 * raise, 0.04], "armL": [-0.9 - 0.3 * raise, 0.22]})
	elif str(o.state) == "cuff":
		actor.puppet.pose({"walk": 0.0, "armR": [-0.75, 0.1], "armL": [-0.75, 0.1], "lean": 0.08})
	elif bool(o.get("citing", false)) and str(o.state) == "engage" and not actor.moving:
		# Writing it up: notebook hand forward, pen hand over it, head down.
		actor.puppet.pose({"walk": 0.0, "armL": [-0.95, 0.25], "armR": [-0.8, -0.05], "nod": 0.25})
	elif str(o.state) == "engage" and not actor.moving:
		actor.puppet.pose({"walk": 0.0, "armR": [-1.35, 0.05]})
	else:
		actor.puppet.pose({"walk": walk, "mouth": 0.4 if float(actor._speech_remaining) > 0.0 else 0.0})

## Held suspects face the officer; escorted ones follow behind them.
func _tick_custody(delta: float) -> void:
	for id in custody.records.keys():
		var entry: Dictionary = custody.records[id]
		var state := str(entry.state)
		var body = entry.get("actor")
		if state == "in_custody" or not is_instance_valid(body) or body.get("combat_override") != true or body.get("dead") == true:
			continue
		Tactics.tick_body(body, delta)
		var officer: Dictionary = {}
		for o in _officers.values():
			if str(o.target) == str(id) or str(o.escort) == str(id):
				officer = o
				break
		var walking := false
		if not officer.is_empty() and is_instance_valid(officer.actor):
			var at: Vector3 = officer.actor.global_position
			if state == "escort" and Tactics.flat(body.global_position, at) > 1.8:
				var behind: Vector3 = at - Tactics.forward_of(officer.actor) * 1.3
				walking = Tactics.walk(body, behind, delta, ESCORT_SPEED + 0.3) == Tactics.MOVE_MOVED
			else:
				Tactics.face(body, Tactics.heading_to(body.global_position, at, float(body.yaw)), delta, 0.05)
		if body.puppet == null:
			continue
		if state == "held":
			body.puppet.pose({"walk": 0.0, "armR": [-2.7, 0.25], "armL": [-2.7, 0.25]})
		else:
			body.puppet.pose({"walk": 0.4 if walking else 0.0, "armR": [0.45, 0.12], "armL": [0.45, 0.12], "lean": 0.05})

# --------------------------------------------------------------- force

## One round at an imminent lethal threat, re-checked at the trigger: still
## imminent, alive, in range, aimed, clear line, nobody near the target, the
## miss line or behind it, and the caller/officers clear of the whole line.
func _fire(o: Dictionary) -> void:
	var incident := _incident_by_id(str(o.incident))
	if incident.is_empty():
		return
	var s: Dictionary = (incident.suspects as Dictionary).get(str(o.target), {})
	var actor = o.actor
	if s.is_empty() or not is_instance_valid(s.actor):
		_hold(o, "no_target")
		return
	var body = s.actor
	if int(incident.rounds) >= MAX_ROUNDS_PER_INCIDENT:
		_hold(o, "round_limit")
		return
	if not _imminent(s) or _combat_mode(body) in ["dead", "downed", "gone"]:
		_hold(o, "no_imminent_threat")
		return
	var distance := Tactics.flat(actor.global_position, body.global_position)
	if distance > FIRE_RANGE:
		_hold(o, "out_of_range")
		return
	var wanted := Tactics.heading_to(actor.global_position, body.global_position, float(actor.yaw))
	if absf(angle_difference(float(actor.yaw), wanted)) > 0.2:
		_hold(o, "not_aligned")
		return
	var aim := Tactics.chest_of(body)
	var muzzle: Vector3 = o.muzzle.global_position if is_instance_valid(o.muzzle) else Tactics.chest_of(actor) + Vector3.UP * 0.15 + Tactics.forward_of(actor) * 0.45
	var line := aim - muzzle
	var across := Vector3(-line.z, 0.0, line.x).normalized()
	var side := 1.0 if int(o.rounds) % 2 == 0 else -1.0
	var miss: Vector3 = body.global_position + across * 0.8 * side - Vector3.UP * 0.3
	var why := tactics.fire_clearance(muzzle, aim, miss, body, actor, _protected_points(o))
	if not why.is_empty():
		_hold(o, why)
		if why in ["person_in_line", "bystander_near_target", "person_in_miss_line", "person_beyond_target", "protected_near_line"] and not bool(o.spoke_hold):
			o.spoke_hold = true
			actor.speak("Get down! Clear the line!", 1.6)
		return
	o.rounds = int(o.rounds) + 1
	incident.rounds = int(incident.rounds) + 1
	counters.rounds = int(counters.rounds) + 1
	var accuracy := clampf(0.92 - distance * 0.014, 0.55, 0.9)
	var roll := float(posmod(hash("%s:%d" % [o.id, o.rounds]), 1000)) / 1000.0
	var hit_line := roll < accuracy
	var end: Vector3 = aim + line.normalized() * 0.6 if hit_line else miss
	var skip: Array[RID] = [actor.get_rid()]
	var shot := tactics.trace(muzzle, end, skip)
	var hit: Dictionary = shot.hit
	var struck: Object = null
	if not hit.is_empty() and hit.collider == body:
		struck = body
		counters.hits = int(counters.hits) + 1
		if _apply_round(body, muzzle, str(o.id)):
			counters.damage_applied = int(counters.damage_applied) + 1
			if _dead_id(str(s.id)) or body.get("dead") == true:
				counters.police_kills = int(counters.police_kills) + 1
				s.killed_by_police = true
		else:
			counters.damage_unavailable = int(counters.damage_unavailable) + 1
	_flash(muzzle)
	_tracer(muzzle, shot.endpoint)
	_gunfire_event(muzzle, shot.endpoint, struck)
	if int(incident.rounds) == 1:
		_handling(incident, "force", "Police fired at an armed attacker.")

func _hold(o: Dictionary, why: String) -> void:
	o.hold_reason = why
	counters.held_fire = int(counters.held_fire) + 1
	hold_reasons[why] = int(hold_reasons.get(why, 0)) + 1

func _protected_points(o: Dictionary) -> Array:
	var points: Array = []
	var player = level.get("player") if level != null else null
	if player is Node3D:
		points.append((player as Node3D).global_position + Vector3.UP * 1.1)
	for other in _officers.values():
		if str(other.id) != str(o.id) and is_instance_valid(other.actor):
			points.append(Tactics.chest_of(other.actor))
	# A neighbor who reported the incident is protected like the phone caller.
	var incident := _incident_by_id(str(o.incident))
	var reporter := str(incident.get("reporter", ""))
	if not reporter.is_empty() and reporter != "player":
		var witness = _resolve(reporter)
		if witness is Node3D:
			points.append(Tactics.chest_of(witness))
	return points

## Damage goes through combat so wounds, deaths and the persisted registry stay
## combat's. Prefers a public hook; falls back to combat's existing internal
## damage entry point with by_player = false (no player offense is recorded).
func _apply_round(body, origin: Vector3, officer_id: String) -> bool:
	var combat = _combat()
	if combat == null:
		hooks.damage = "none"
		return false
	if combat.has_method("receive_police_round"):
		hooks.damage = "public"
		return bool(combat.receive_police_round(body, ROUND_DAMAGE, origin, officer_id))
	if combat.has_method("_damage_target"):
		hooks.damage = "internal_fallback"
		return bool(combat._damage_target(body, ROUND_DAMAGE, "police", origin, false))
	hooks.damage = "none"
	return false

## Lets combat's existing per-round hearing/traffic reaction run (bystanders
## take cover, cars brake) and plays the shot. Never a player offense.
func _gunfire_event(muzzle: Vector3, endpoint: Vector3, struck: Object) -> void:
	var combat = _combat()
	if combat == null:
		return
	if combat.has_method("receive_police_gunfire"):
		hooks.gunfire = "public"
		combat.receive_police_gunfire(muzzle, endpoint, struck)
		return
	if combat.has_method("_gunshot_event"):
		hooks.gunfire = "internal_fallback"
		combat._gunshot_event(muzzle, muzzle, endpoint, false, struck)
	if combat.has_method("_world_sound"):
		combat._world_sound("shot", muzzle)

func _draw(o: Dictionary) -> void:
	if is_instance_valid(o.gun):
		return
	var actor = o.actor
	if actor.puppet == null or actor.puppet.hands.is_empty():
		return
	var gun := Node3D.new()
	gun.name = "PolicePistol"
	actor.puppet.hands[0].add_child(gun)
	gun.rotation.x = PI * 0.5
	_box(gun, Vector3(0.085, 0.10, 0.28), Vector3(0, 0.035, 0.065), Color("2a2f36"))
	_box(gun, Vector3(0.065, 0.16, 0.08), Vector3(0, -0.075, -0.025), Color("14181e"))
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0, 0.035, 0.22)
	gun.add_child(muzzle)
	o.gun = gun
	o.muzzle = muzzle

func _holster(o: Dictionary) -> void:
	if is_instance_valid(o.get("gun")):
		o.gun.queue_free()
	o.gun = null
	o.muzzle = null
	o.aim = -1.0

func _box(parent: Node3D, size_: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_
	mesh.mesh = box
	mesh.material_override = _material(color, false)
	mesh.position = at
	parent.add_child(mesh)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var key := "%s:%s" % [color.to_html(), glowing]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
	_materials[key] = material
	return material

func _flash(at: Vector3) -> void:
	if _effects.size() >= MAX_EFFECTS:
		return
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07
	ball.height = 0.14
	mesh.mesh = ball
	mesh.material_override = _material(Color("ffcf67"), true)
	add_child(mesh)
	mesh.global_position = at
	_effects.append({"node": mesh, "time": 0.08})

func _tracer(from: Vector3, to: Vector3) -> void:
	if _effects.size() >= MAX_EFFECTS or from.distance_to(to) < 0.05:
		return
	var mesh := MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, from.distance_to(to))
	mesh.mesh = line
	mesh.material_override = _material(Color("ffe4ac"), true)
	add_child(mesh)
	mesh.global_position = from.lerp(to, 0.5)
	mesh.look_at(to, Vector3.RIGHT if absf((to - from).normalized().y) > 0.98 else Vector3.UP)
	_effects.append({"node": mesh, "time": 0.065})

func _tick_effects(delta: float) -> void:
	for effect in _effects.duplicate():
		effect.time = float(effect.time) - delta
		if float(effect.time) <= 0.0:
			if is_instance_valid(effect.node):
				effect.node.queue_free()
			_effects.erase(effect)

# --------------------------------------------------------------- lookups

func _scan_patrols() -> Array:
	var result: Array = []
	var npcs = level.get("npcs") if level != null else null
	var actors = npcs.get("actors") if npcs != null else null
	if not actors is Dictionary:
		return result
	for actor in (actors as Dictionary).values():
		var id := str(actor.get("actor_id")) if is_instance_valid(actor) else ""
		if id.begins_with(PATROL_PREFIX) and not id.begins_with(CREW_PREFIX):
			result.append(actor)
	return result

## A person by identity: named contacts, daily residents, or combat's fighters
## (which include promoted crowd residents).
func _resolve(id: String):
	if id.is_empty() or level == null:
		return null
	var npcs = level.get("npcs")
	var actors = npcs.get("actors") if npcs != null else null
	if actors is Dictionary and (actors as Dictionary).has(id) and is_instance_valid(actors[id]):
		return actors[id]
	var residents = level.get("residents")
	if residents != null and residents.has_method("get_actor"):
		var found = residents.get_actor(id)
		if is_instance_valid(found):
			return found
	for entry in _fighters():
		if str(entry.get("id", "")) == id and is_instance_valid(entry.get("actor")):
			return entry.actor
	if incident_handler != null and is_instance_valid(incident_handler) and incident_handler.has_method("performer_actor"):
		var performer = incident_handler.performer_actor(id)
		if is_instance_valid(performer):
			return performer
	return null

func _eligible_suspect(actor, id: String) -> bool:
	if not _usable(actor) or id.is_empty() or _dead_id(id):
		return false
	if actor == level.get("player") or _officers.has(id) or _is_police(actor):
		return false
	return actor.has_method("walking_ground_at")

func _is_police(actor) -> bool:
	var id := str(actor.get("actor_id"))
	return str(actor.get("cast_id")).begins_with("cop_") or id == "officer" or id.begins_with(PATROL_PREFIX)

func _usable(actor) -> bool:
	return is_instance_valid(actor) and actor.get("dead") != true and actor.get("enabled") == true

## combat.actor_mode(): "" free, "unknown" held outside combat (this service or
## custody), "aggro"/"gun"/"return", "panic:*", "downed", "dead", "gone".
func _combat_mode(actor) -> String:
	if not is_instance_valid(actor):
		return "gone"
	if actor.get("dead") == true:
		return "dead"
	var combat = _combat()
	if combat != null and combat.has_method("actor_mode"):
		return str(combat.actor_mode(actor))
	return "unknown" if actor.get("combat_override") == true else ""

func _dead_id(id: String) -> bool:
	var combat = _combat()
	return combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id))

## Combat's current fighters, read-only: a public snapshot when combat offers
## one, else its fight set (bounded by combat's MAX_ACTIVE).
func _fighters() -> Array:
	var combat = _combat()
	if combat == null:
		return []
	if combat.has_method("fighter_snapshot"):
		hooks.fighters = "public"
		return combat.fighter_snapshot()
	var active = combat.get("_active")
	if not active is Dictionary:
		return []
	hooks.fighters = "internal_read"
	var list: Array = []
	for state in (active as Dictionary).values():
		if state is Dictionary:
			list.append({"actor": state.get("actor"), "id": str(state.get("id", "")), "mode": str(state.get("mode", "")),
				"aim": float(state.get("aim", -1.0)), "shots": int(state.get("shots", 0))})
	return list

func _fighter_info(actor) -> Dictionary:
	if not is_instance_valid(actor):
		return {}
	var combat = _combat()
	if combat == null:
		return {}
	if combat.has_method("fighter_snapshot"):
		for entry in combat.fighter_snapshot():
			if entry.get("actor") == actor:
				return entry
		return {}
	var active = combat.get("_active")
	if active is Dictionary:
		var state = (active as Dictionary).get(actor.get_instance_id())
		if state is Dictionary:
			return {"mode": str(state.get("mode", "")), "aim": float(state.get("aim", -1.0)), "shots": int(state.get("shots", 0))}
	return {}

func _unseen(body: Node3D) -> bool:
	var player = level.get("player") if level != null else null
	if not player is Node3D:
		return true
	var at := body.global_position + Vector3.UP * 1.0
	var distance := Tactics.flat(at, (player as Node3D).global_position)
	if distance < HIDE_DISTANCE:
		return false
	var camera = player.get("camera")
	if camera is Camera3D and (camera as Camera3D).is_inside_tree() and distance < 160.0 and (camera as Camera3D).is_position_in_frustum(at):
		return false
	return true

func _combat():
	return level.get("combat") if level != null else null

func _law():
	return level.get("law") if level != null else null

func _cruisers():
	var law = _law()
	return law.get("cruisers") if law != null else null

func _space() -> PhysicsDirectSpaceState3D:
	if is_inside_tree():
		var world := get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func _world_paused() -> bool:
	if level == null:
		return true
	if level.get("paused") == true:
		return true
	var inspector = level.get("inspector")
	if inspector != null and inspector.get("active") == true:
		return true
	return is_inside_tree() and get_tree().paused

func _exit_tree() -> void:
	var cruisers = _cruisers()
	if cruisers != null and cruisers.get("assist_handler") == self:
		cruisers.set("assist_handler", null)
