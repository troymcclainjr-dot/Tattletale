extends Node3D
## Neighborhood incidents: sparse infractions real neighbors commit on their own,
## whether or not the player is watching, plus the witness record that makes a
## report trustworthy and the police outcome that closes it.
##
## World: at most MAX_LIVE incidents have performers at once, a new one is tried
## every SPAWN_MIN..SPAWN_MAX seconds, only SPAWN_NEAR..SPAWN_FAR metres from the
## player and only with free crowd neighbors (never named contacts, police or
## anyone combat, custody, a case or the bicycle is handling). Templates come
## from the original crime list and the Pen Lucy cases (city_incident_templates).
## Performers walk forward-only, collision-swept steps; nobody is teleported.
##
## Witnesses: while the act lasts, at most MAX_RAYS_PER_PASS sight rays every
## OBSERVE_INTERVAL check the player (range, view, line of sight) and nearby
## people (cell-indexed crowd plus named/daily actors). Only recorded witnesses or
## verified evidence may report; a second report never dispatches twice.
##
## Police: city_police_assistance.report_incident() sends real officers; its
## progress (report_received, responding, on_scene, resolved, unavailable)
## updates the record and is re-emitted as report_status_changed, carrying the
## police dispatch stage/handling (city_police_status.gd) for the phone. A record
## closed here while police still answer it stands that call down. Infractions
## end with a warning, theft and violence with custody. A report never removes
## anyone by itself. Contract: .work/pacifist-foundation/incidents-contract.md
## and .work/five-priorities-20261101/police-contract.md.

signal incident_opened(summary: Dictionary)
signal incident_changed(summary: Dictionary)
signal incident_closed(summary: Dictionary)
signal report_status_changed(status: Dictionary)

const Templates := preload("res://scripts/city/city_incident_templates.gd")
const Actors := preload("res://scripts/city/city_incident_actors.gd")
const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const PoliceStatus := preload("res://scripts/city/city_police_status.gd")

const STATE_VERSION := 1
const MAX_LIVE := 2
const MAX_RECORDS := 32
const MAX_WITNESSES := 8
const MAX_EVIDENCE := 8
const MAX_PARTICIPANTS := 6
const MAX_CORROBORATING := 6
const MAX_PROPS := 3
const FIRST_SPAWN := 45.0
const SPAWN_MIN := 120.0
const SPAWN_MAX := 240.0
const RETRY_SPAWN := 12.0
const SPAWN_NEAR := 30.0
const SPAWN_FAR := 90.0
const ABANDON_DISTANCE := 160.0
const OBSERVE_INTERVAL := 0.5
const MAX_RAYS_PER_PASS := 6
const MAX_CROWD_CANDIDATES := 24
const MAX_PLAN_CANDIDATES := 12
const NPC_WITNESS_RADIUS := 22.0
const PLAYER_WITNESS_RADIUS := 40.0
const NOTICE_RADIUS := 3.0
const VIEW_DOT := -0.2
const PLAYER_VIEW_DOT := 0.2
const SIGHT_MASK := 1 | 2 | 16
## Game minutes (world_time runs 0.5 min per second): a report must follow the act.
const REPORT_WINDOW_MINUTES := 120.0
const PHONE_REPORT_RADIUS := 120.0
const LINGER_SECONDS := 90.0
const REPORTED_LINGER_SECONDS := 150.0
const STOPPED_LIMIT := 20.0
const CITED_RELEASE := 1.5
## Police close every call within their own 240 s limit; this only frees a slot.
const INCIDENT_HOLD_LIMIT := 300.0
const STEP_BLOCKED_SECONDS := 8.0
const LEAVE_BLOCKED_SECONDS := 4.0
const FIGHT_SECONDS := 16.0
const FIGHT_TIMEOUT := 30.0
const ROAD_GRID := 30.0
const CROSSING_CLEARANCE := 10.0
const ROAD_END_CLEARANCE := 12.0
const STATES := ["active", "ended", "reported", "responding", "resolved", "expired", "cancelled"]
const CLOSED_STATES := ["resolved", "expired", "cancelled"]
const OUTCOMES := ["warned", "arrested", "suspect_left", "no_threat", "unanswered", "expired", "cancelled",
	"case_resolved", "suspect_killed", "timeout", "interrupted"]
const ROLES := ["offender", "victim", "reporter"]
const PEOPLE_KINDS := ["crowd", "resident", "contact", "officer", "player"]

var level: Node
var spawning_enabled := true
var actors := Actors.new()
var records: Array[Dictionary] = []
var next_sequence := 1
var last_spawn_reason := ""
var rays := 0
var counters := {"spawned": 0, "spawn_attempts": 0, "external": 0, "cancelled": 0, "ended": 0, "unwitnessed": 0,
	"witnesses": 0, "player_witnessed": 0, "report_attempts": 0, "reports": 0, "duplicates": 0, "rejected_reports": 0,
	"npc_reports": 0, "phone_fallbacks": 0, "resolved": 0, "expired": 0, "lost_performers": 0, "handoffs": 0,
	"photos_checked": 0, "photos_verified": 0}
var outcomes: Dictionary = {}
## Bumps whenever a record changes (the phone's refresh key).
var revision := 0
var _live: Dictionary = {}
# UI subscriptions belong to this live session, not the original reporter's
# attribution or the version-1 durable record. Only accepted player phone
# corroboration adds one; closure/removal/restore releases it.
var _phone_followups: Dictionary = {}
var _clock := 0.0
var _spawn_left := FIRST_SPAWN
var _observe_left := 0.0
var _rng := RandomNumberGenerator.new()
var _roads: Array[Dictionary] = []
var _road_grid: Dictionary = {}
var _mailboxes: Array = []
var _mailboxes_indexed := false
var _props: Array[Dictionary] = []
var _ray := PhysicsRayQueryParameters3D.new()
var _prop_material: StandardMaterial3D
var _photo_provider_registered := false

# --------------------------------------------------------------- public API

func setup(owner_level: Node) -> void:
	level = owner_level
	name = "NeighborhoodIncidents"
	actors.setup(level, self)
	_rng.seed = 7100311
	_ray.collision_mask = SIGHT_MASK
	_ray.hit_from_inside = false
	_index_roads()
	_connect_services(true)

## Police find performers and report progress through us; the phone lists our
## live participants as photo subjects. Idempotent (retried at 2 Hz without
## taking over from another live service; setup claims the police link).
func _connect_services(claim := false) -> void:
	var police = _police()
	if police != null:
		var current = police.get("incident_handler")
		if claim or current == null or not is_instance_valid(current):
			police.set("incident_handler", self)
	if _photo_provider_registered:
		return
	var player = level.get("player") if level != null else null
	var phone = player.get("phone") if player != null else null
	if phone != null and phone.has_method("register_photo_subject_provider"):
		phone.register_photo_subject_provider(_photo_subjects)
		_photo_provider_registered = true

func tick(delta: float) -> void:
	if level == null or delta <= 0.0 or _world_paused():
		return
	delta = minf(delta, 0.1)
	_clock += delta
	actors.tactics.space = _space()
	for id in _live.keys():
		if _live.has(id):
			_tick_live(str(id), delta)
	_observe_left -= delta
	if _observe_left <= 0.0:
		_observe_left = OBSERVE_INTERVAL
		_observe_pass()
		_housekeeping()
	if spawning_enabled:
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			_spawn_left = RETRY_SPAWN
			if bool(_try_spawn().get("ok", false)):
				_spawn_left = _rng.randf_range(SPAWN_MIN, SPAWN_MAX)

func set_spawning_enabled(value: bool) -> void:
	spawning_enabled = value

## Deep copy of one record ({} when unknown); vectors are [x, y, z].
func get_incident(id: String) -> Dictionary:
	var rec := _record(id)
	return _serialize(rec) if not rec.is_empty() else {}

## filter keys (all optional): state (String or Array), template, source, case_id.
func list_incidents(filter := {}) -> Array:
	var result: Array = []
	for rec in records:
		if filter.has("state"):
			var wanted = filter.state
			if (wanted is Array and not str(rec.state) in wanted) or (wanted is String and str(rec.state) != wanted):
				continue
		var matched := true
		for key in ["template", "source", "case_id"]:
			if filter.has(key) and str(rec.get(key, "")) != str(filter[key]):
				matched = false
		if matched:
			result.append(_serialize(rec))
	return result

## Incidents `reporter_id` saw (or documented) that can still be reported now.
func reportable_for(reporter_id := "player") -> Array:
	var result: Array = []
	for rec in records:
		if str(rec.state) in ["active", "ended"] and _may_report(rec, reporter_id) and _in_window(rec) and not _is_offender(rec, reporter_id):
			result.append(_serialize(rec))
	return result

## The authoritative report gate. reasons: unknown_incident, already_resolved,
## expired, reporter_is_offender, not_witnessed, police_unavailable; a repeat
## returns ok with duplicate = true and never dispatches again.
func report_incident(id: String, reporter_id := "player", context := {}) -> Dictionary:
	counters.report_attempts = int(counters.report_attempts) + 1
	var result := {"ok": false, "incident_id": id, "status": "", "reason": "", "duplicate": false,
		"police_incident_id": "", "message": ""}
	var rec := _record(id)
	if rec.is_empty():
		return _refuse(result, "unknown_incident", "There is no record of that incident.")
	if str(rec.state) == "resolved":
		return _refuse(result, "already_resolved", "That incident has already been dealt with.")
	if str(rec.state) in ["expired", "cancelled"]:
		return _refuse(result, "expired", "That happened too long ago to report.")
	if _is_offender(rec, reporter_id):
		return _refuse(result, "reporter_is_offender", "Police will not take a report from the person involved.")
	if not _may_report(rec, reporter_id):
		return _refuse(result, "not_witnessed", "Police need a witness. You did not see that happen.")
	if not _in_window(rec):
		_resolve(rec, "expired", "Nobody reported it in time.", "system")
		return _refuse(result, "expired", "That happened too long ago to report.")
	var channel := str(context.get("channel", "phone" if reporter_id == "player" else "witness_call"))
	var phone := bool(context.get("phone", reporter_id == "player" and channel == "phone"))
	var report: Dictionary = rec.report
	if not report.is_empty():
		counters.duplicates = int(counters.duplicates) + 1
		if reporter_id == "player" and phone:
			_phone_followups[str(rec.id)] = true
		var corroborating: Array = report.corroborating
		if reporter_id != str(report.by) and not reporter_id in corroborating and corroborating.size() < MAX_CORROBORATING:
			corroborating.append(reporter_id)
			_changed(rec)
		result.ok = true
		result.duplicate = true
		result.status = str(report.status)
		result.police_incident_id = str(report.police_incident_id)
		result.message = "Already reported. " + _status_text(str(report.status))
		return result
	var filed := _file_report(rec, reporter_id, channel, phone)
	result.ok = bool(filed.ok)
	result.reason = str(filed.get("reason", ""))
	result.message = str(filed.get("message", ""))
	result.status = str((rec.report as Dictionary).get("status", ""))
	result.police_incident_id = str((rec.report as Dictionary).get("police_incident_id", ""))
	return result

## Phone "Report" button: the freshest incident the player witnessed near `at`.
## With none, the legacy neighborhood call goes out (police check the spot and
## act only on violence actually there), so the old button keeps working.
func report_from_phone(at: Vector3) -> Dictionary:
	var best := _phone_choice(at)
	if not best.is_empty():
		var result := report_incident(str(best.id), "player", {"channel": "phone", "phone": true})
		result.fallback = false
		return result
	counters.phone_fallbacks = int(counters.phone_fallbacks) + 1
	var police = _police()
	if police == null or not police.has_method("request_help"):
		return {"ok": false, "incident_id": "", "fallback": true, "reason": "police_unavailable", "duplicate": false,
			"message": "Police dispatch is unavailable.", "status": "", "police_incident_id": ""}
	var reply: Dictionary = police.request_help(at)
	return {"ok": bool(reply.get("ok", false)), "incident_id": "", "fallback": true, "reason": "", "duplicate": false,
		"message": str(reply.get("message", "")), "status": "report_received" if bool(reply.get("ok", false)) else "rejected",
		"police_incident_id": str(reply.get("incident_id", ""))}

## The freshest incident the player witnessed near `at` that may still be
## reported (or corroborated); {} when the phone would make an area call.
func _phone_choice(at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var newest := -INF
	for rec in records:
		if not str(rec.state) in ["active", "ended", "reported", "responding"] or not _may_report(rec, "player") or not _in_window(rec):
			continue
		if at.is_finite() and Tactics.flat(_vec(rec.at), at) > PHONE_REPORT_RADIUS:
			continue
		var seen := _witness_minutes(rec, "player")
		if seen > newest:
			newest = seen
			best = rec
	return best

## Read-only: exactly what report_from_phone(at) would do now, so the phone can
## name it before the player presses anything. {kind: "incident" | "area_check",
## incident_id, title, street, state, already_reported, yours}.
func phone_report_preview(at: Vector3) -> Dictionary:
	var rec := _phone_choice(at)
	if rec.is_empty():
		return {"kind": "area_check", "incident_id": "", "title": "", "street": "", "state": "", "already_reported": false, "yours": false}
	var report: Dictionary = rec.report
	var yours := str(report.get("by", "")) == "player" or "player" in (report.get("corroborating", []) as Array)
	return {"kind": "incident", "incident_id": str(rec.id), "title": str(rec.title), "street": str(rec.street), "state": str(rec.state),
		"already_reported": not report.is_empty(), "yours": yours}

## Bounded: deep copies of the records `person_id` reported or corroborated.
## Reports police are still answering come first however old they are (at most
## PoliceStatus.MAX_LIVE_CALLS), then the `limit` newest others, newest first.
## Nobody else's reports are included. Durable (saved with the records), so the
## phone rebuilds its report history from these after a reload.
func reports_for(person_id := "player", limit := 4) -> Array:
	var police = _police()
	var answering: bool = police != null and police.has_method("has_open_ref")
	var live: Array = []
	var recent: Array = []
	for i in range(records.size() - 1, -1, -1):
		var report: Dictionary = records[i].report
		if report.is_empty():
			continue
		if not (str(report.get("by", "")) == person_id or person_id in (report.get("corroborating", []) as Array)):
			continue
		if answering and live.size() < PoliceStatus.MAX_LIVE_CALLS and not str(records[i].state) in CLOSED_STATES \
				and bool(police.has_open_ref(str(records[i].id))):
			live.append(_serialize(records[i]))
		elif recent.size() < limit:
			recent.append(_serialize(records[i]))
	return live + recent

## Case/traffic incidents without an ambient performance. spec: {template, at,
## offender_id, victim_id, source ("case:<id>" | "external:<tag>"), case_id,
## title}. Witnesses are added later through note_observation/evaluate_photo.
func open_incident(spec: Dictionary) -> Dictionary:
	var template := str(spec.get("template", "case"))
	var at: Vector3 = spec.get("at") if spec.get("at") is Vector3 else Vector3.INF
	var source := str(spec.get("source", "external:unknown"))
	if not Templates.has(template):
		return {"ok": false, "incident_id": "", "reason": "unknown_template"}
	if not at.is_finite():
		return {"ok": false, "incident_id": "", "reason": "no_location"}
	if not (source.begins_with("case:") or source.begins_with("external:")) or source.length() > 64:
		return {"ok": false, "incident_id": "", "reason": "invalid_source"}
	var offender := str(spec.get("offender_id", ""))
	if offender.is_empty() or offender == "player":
		return {"ok": false, "incident_id": "", "reason": "invalid_offender"}
	var rec := _new_record(template, at, source, str(spec.get("case_id", "")), offender, str(spec.get("victim_id", "")))
	if not str(spec.get("title", "")).is_empty():
		rec.title = str(spec.title).left(64)
	rec.state = "ended"
	rec.ended_minutes = _minutes()
	_commit(rec)
	counters.external = int(counters.external) + 1
	return {"ok": true, "incident_id": str(rec.id), "reason": ""}

## A trusted observation established by another system (e.g. a case objective
## that already verified line of sight). Adds `witness_id` as a witness.
func note_observation(id: String, witness_id: String, info := {}) -> bool:
	var rec := _record(id)
	if rec.is_empty() or witness_id.is_empty() or str(rec.state) in CLOSED_STATES or _is_offender(rec, witness_id):
		return false
	var at: Vector3 = info.get("at") if info.get("at") is Vector3 else _vec(rec.at)
	return _add_witness(rec, witness_id, _kind_of(witness_id), float(info.get("distance", 0.0)), at, str(info.get("via", "case")))

## {kind: photo|statement|object, by, subject_id, at, verified, ref}. A verified
## photo also makes its photographer a witness (they may then report).
func attach_evidence(id: String, evidence: Dictionary) -> bool:
	var rec := _record(id)
	var kind := str(evidence.get("kind", ""))
	if rec.is_empty() or not kind in ["photo", "statement", "object"] or str(rec.state) in ["expired", "cancelled"]:
		return false
	var entry := {"kind": kind, "by": str(evidence.get("by", "")).left(64), "subject_id": str(evidence.get("subject_id", "")).left(64),
		"minutes": _minutes(), "at": evidence.get("at") if evidence.get("at") is Vector3 else _vec(rec.at),
		"verified": bool(evidence.get("verified", false)), "ref": str(evidence.get("ref", "")).left(96)}
	var by := str(entry.by)
	var subject := str(entry.subject_id)
	if not _add_evidence(rec, entry):
		return false
	if by.is_empty() or _is_offender(rec, by) or not bool(entry.verified):
		return true
	if kind == "photo" and _is_offender(rec, subject):
		# Only a verified photo of the offender makes its photographer a witness.
		_add_witness(rec, by, _kind_of(by), 0.0, entry.at, "photo")
	elif kind == "statement" and subject != by and _has_witness(rec, subject) and not _is_offender(rec, subject):
		# Verified testimony from someone who actually saw it (a case interview)
		# gives the listener report context: they report on that witness's word.
		_add_witness(rec, by, _kind_of(by), 0.0, entry.at, "case")
	return true

## The phone's trusted capture context (phone-map-contract §1, version 2:
## {source "phone_camera", trusted, photo_id, time.total_minutes, camera.position,
## subjects [{id, distance, position, line_of_sight}]}; the older flat
## {by, position, minutes, ref, visible [{id, los, distance}]} is also read). A
## photo counts only when an offender was listed with line of sight, close
## enough, during the act (small grace after), and — while their body is still
## live — one static-geometry ray from the camera to them is clear right now.
func evaluate_photo(id: String, context: Dictionary) -> Dictionary:
	counters.photos_checked = int(counters.photos_checked) + 1
	var rec := _record(id)
	if rec.is_empty():
		return {"ok": false, "subject_visible": false, "in_window": false, "reason": "unknown_incident"}
	var v2 := context.get("subjects") is Array
	if v2 and (str(context.get("source", "")) != "phone_camera" or context.get("trusted") != true or str(context.get("photo_id", "")).is_empty()):
		return {"ok": false, "subject_visible": false, "in_window": false, "reason": "untrusted_context"}
	var clock = context.get("time")
	var minutes := float(clock.get("total_minutes", _minutes())) if v2 and clock is Dictionary else float(context.get("minutes", _minutes()))
	var camera = context.get("camera")
	var eye: Vector3 = camera.get("position") if v2 and camera is Dictionary and camera.get("position") is Vector3 \
		else (context.get("position") if context.get("position") is Vector3 else Vector3.INF)
	var ended := float(rec.ended_minutes) if float(rec.ended_minutes) >= 0.0 else _minutes()
	var in_window := minutes >= float(rec.created_minutes) - 0.5 and minutes <= ended + 2.0
	var visible := false
	var subject := ""
	for entry in context.get("subjects" if v2 else "visible", []):
		if not entry is Dictionary or not _is_offender(rec, str(entry.get("id", ""))):
			continue
		var sighted := bool(entry.get("line_of_sight", false)) if v2 else bool(entry.get("los", false))
		if not sighted or float(entry.get("distance", INF)) > PLAYER_WITNESS_RADIUS:
			continue
		if not _photo_line_holds(str(entry.id), eye, entry.get("position")):
			continue
		visible = true
		subject = str(entry.id)
		break
	var ok := visible and in_window
	if ok:
		counters.photos_verified = int(counters.photos_verified) + 1
		attach_evidence(id, {"kind": "photo", "by": str(context.get("by", "player")), "subject_id": subject,
			"at": eye if eye.is_finite() else _vec(rec.at), "verified": true,
			"ref": str(context.get("photo_id", context.get("ref", "")))})
	var reason := ""
	if not visible:
		reason = "subject_not_visible"
	elif not in_window:
		reason = "outside_window"
	return {"ok": ok, "subject_visible": visible, "in_window": in_window, "reason": reason}

## While the offender's body is live (a performer or fighter), the listing must
## match it (within 2.5 m) and one ray from the camera through terrain, buildings
## and cars must reach it now: a wall is never forgiven by a target radius.
func _photo_line_holds(subject_id: String, eye: Vector3, listed) -> bool:
	var body = performer_actor(subject_id)
	if body == null:
		for live in _live.values():
			if str(live.offender) == subject_id and str(live.phase) == "fight":
				body = _subject_body(live)
	if not is_instance_valid(body) or not body is CollisionObject3D:
		return true # No live body to check against: the phone's strict listing stands.
	if not eye.is_finite():
		return false
	var chest: Vector3 = (body as Node3D).global_position + Vector3.UP * 1.2
	if listed is Vector3 and (listed as Vector3).distance_to(chest) > 2.5:
		return false
	var skip: Array[RID] = [(body as CollisionObject3D).get_rid()]
	var player = level.get("player") if level != null else null
	if player is CollisionObject3D:
		skip.append((player as CollisionObject3D).get_rid())
	return _clear_line(eye, chest, skip)

## Bounded photo subjects for the phone (crowd stand-ins are in no actor list):
## live offenders/victims and dumped-bag evidence, tagged for the case engine.
func _photo_subjects() -> Array:
	var subjects: Array = []
	for id in _live:
		var live: Dictionary = _live[id]
		var rec := _record(str(id))
		if rec.is_empty():
			continue
		var tags := ["incident:%s" % id, "incident_state:%s" % str(rec.state)]
		var offender = _subject_body(live)
		if is_instance_valid(offender) and offender is CollisionObject3D:
			subjects.append({"id": str(live.offender), "kind": "actor", "label": "Neighbor", "max_distance": 60.0,
				"position": (offender as Node3D).global_position + Vector3.UP * 1.2, "collider": offender,
				"tags": tags + ["incident_role:offender"]})
		var victim := str(live.get("victim", ""))
		var victim_at := _person_position(victim) if not victim.is_empty() else Vector3.INF
		if victim_at.is_finite():
			var subject := {"id": victim, "kind": "actor", "label": "Neighbor", "max_distance": 60.0,
				"position": victim_at + Vector3.UP * 1.1, "tags": tags + ["incident_role:victim"]}
			var collider = _person_collider(victim)
			if collider != null:
				subject.collider = collider
			subjects.append(subject)
	for prop in _props:
		if is_instance_valid(prop.node):
			var rec := _record(str(prop.incident))
			subjects.append({"id": "incident:%s:dumped_bag" % str(prop.incident), "kind": "object", "label": "Dumped bag",
				"position": (prop.node as Node3D).global_position, "max_distance": 30.0,
				"tags": ["incident:%s" % str(prop.incident), "incident_state:%s" % str(rec.get("state", "")), "incident_role:evidence"]})
	return subjects

## cases-contract §6 spelling of report_incident (the case engine's fallback).
func file_report(incident_id: String, report: Dictionary) -> Dictionary:
	return report_incident(incident_id, str(report.get("reporter", "player")),
		{"channel": "case", "case_id": str(report.get("case_id", "")), "phone": false})

## Case-driven closure (the case worker's outcome is authoritative for its own).
func resolve_incident(id: String, outcome: String, text := "") -> bool:
	var rec := _record(id)
	if rec.is_empty() or str(rec.state) in CLOSED_STATES:
		return false
	_resolve(rec, outcome if outcome in OUTCOMES else "case_resolved", text, "case")
	return true

## Records are plain data and always saveable; performers are never saved.
func blocks_checkpoint() -> bool:
	return false

func snapshot_state() -> Dictionary:
	var list: Array = []
	for rec in records:
		list.append(_serialize(rec))
	return {"version": STATE_VERSION, "next_sequence": next_sequence, "incidents": list}

## "" when `value` is a valid incidents section; never mutates anything.
func validate_state(value) -> String:
	if not value is Dictionary:
		return "incidents state must be an object"
	var state: Dictionary = value
	if not _number(state.get("version")) or float(state.version) != float(STATE_VERSION):
		return "unsupported incidents version"
	if not _number(state.get("next_sequence")) or float(state.next_sequence) < 1.0 or float(state.next_sequence) > 99999999.0 \
			or float(state.next_sequence) != floorf(float(state.next_sequence)):
		return "invalid incident sequence"
	var list = state.get("incidents")
	if not list is Array or list.size() > MAX_RECORDS:
		return "invalid incident list"
	var seen: Dictionary = {}
	for entry in list:
		var why := _validate_record(entry)
		if not why.is_empty():
			return why
		if seen.has(entry.id):
			return "duplicate incident id"
		seen[entry.id] = true
		if int(str(entry.id).substr(4)) >= int(state.next_sequence):
			return "incident id beyond sequence"
	return ""

## Replaces the record set from a checkpoint, faithfully: snapshot_state() right
## after equals `value` (the world save's rollback check relies on it). Acts in
## this session stop first (performers go back to normal life where they stand).
## Records that were mid-act or mid-response settle on the next tick (_settle).
func restore_state(value) -> Dictionary:
	var reason := validate_state(value)
	if not reason.is_empty():
		return {"ok": false, "restored": 0, "reason": reason}
	for id in _live.keys().duplicate():
		_drop_live(str(id))
	actors.release_all()
	records.clear()
	_phone_followups.clear()
	_clear_props("")
	for entry in value.incidents:
		records.append(_deserialize(entry))
	next_sequence = int(value.next_sequence)
	_observe_left = 0.0
	revision += 1
	return {"ok": true, "restored": records.size(), "reason": ""}

## Stops every act now: performers go back to normal life where they stand.
## Records stay; an act cut short keeps what was witnessed.
func reset_state() -> void:
	for id in _live.keys().duplicate():
		var rec := _record(str(id))
		if not rec.is_empty() and str(rec.state) == "active":
			_cut_short(rec)
		_drop_live(str(id))
	actors.release_all()

func get_status() -> Dictionary:
	var states: Dictionary = {}
	for rec in records:
		states[str(rec.state)] = int(states.get(str(rec.state), 0)) + 1
	var live: Array = []
	for id in _live:
		live.append({"id": str(id), "phase": str(_live[id].phase), "offender": str(_live[id].offender),
			"acting": bool(_live[id].get("acting", false))})
	return {"records": records.size(), "max_records": MAX_RECORDS, "live": live, "max_live": MAX_LIVE,
		"states": states, "next_sequence": next_sequence, "spawning_enabled": spawning_enabled,
		"spawn_in": maxf(0.0, _spawn_left), "last_spawn_reason": last_spawn_reason, "counters": counters.duplicate(),
		"outcomes": outcomes.duplicate(), "rays": rays, "props": _props.size(), "roads": _roads.size(),
		"actors": actors.get_status()}

## Ambient spawn or fixture: template id plus optional {offender, victim, route,
## stops} to pin people and geometry. Returns {ok, incident_id, reason}.
func spawn_template_now(template_id: String, options := {}) -> Dictionary:
	if not Templates.has(template_id) or int(Templates.template(template_id).weight) <= 0:
		return {"ok": false, "incident_id": "", "reason": "unknown_template"}
	if _live.size() >= MAX_LIVE:
		return {"ok": false, "incident_id": "", "reason": "live_cap"}
	var plan := _plan(template_id, options)
	if plan.is_empty():
		return {"ok": false, "incident_id": "", "reason": last_spawn_reason}
	return _start(template_id, plan)

# --------------------------------------------------------------- police and custody hooks

## city_police_assistance progress for a linked call (incident_handler contract).
func on_police_progress(ref: String, event: String, data: Dictionary) -> void:
	var rec := _record(ref)
	if rec.is_empty():
		return
	var live: Dictionary = _live.get(ref, {})
	match event:
		"report_received", "responding", "on_scene":
			if str(rec.state) in CLOSED_STATES:
				return # A late step from a call this closed record no longer waits on.
			# One relay per police transition. The record itself only changes
			# (and is re-announced) when its coarse status, dispatch id or state
			# does; a new handling step within "on_scene" is a status, not a change.
			var report: Dictionary = rec.report
			var changed := false
			if not report.is_empty():
				changed = str(report.get("status", "")) != event
				report.status = event
				var police_id := str(data.get("police_incident_id", ""))
				if not police_id.is_empty() and str(report.get("police_incident_id", "")) != police_id:
					report.police_incident_id = police_id
					changed = true
			if event != "report_received" and str(rec.state) == "reported":
				rec.state = "responding"
				changed = true
			_emit_status(rec, event, str(data.get("text", "")), "", false, data)
			if changed:
				_changed(rec)
		"contact":
			if not live.is_empty() and str(data.get("suspect_id", "")) == str(live.offender) and actors.owns(str(live.offender)):
				live.phase = "stopped"
				live.stop_officer = str(data.get("officer_id", ""))
				live.stopped_at = _clock
				live.cited_at = -1.0
		"cited":
			_add_evidence(rec, {"kind": "statement", "by": str(data.get("officer_id", "")), "subject_id": str(data.get("suspect_id", "")),
				"minutes": _minutes(), "at": _vec(rec.at), "verified": true, "ref": "police_warning"})
			if not live.is_empty() and str(data.get("suspect_id", "")) == str(live.offender):
				live.cited_at = _clock
		"resolved", "unavailable":
			var outcome := _outcome_from_police(str(data.get("outcome", "")), event)
			_resolve(rec, outcome, str(data.get("text", "")), "police")

## Police are about to take custody of a performer: let go so custody can hold
## the same person on the same spot (a crowd stand-in hands back its slot first).
func release_for_custody(id: String) -> bool:
	if not actors.owns(id):
		return false
	for live in _live.values():
		if str(live.offender) == id:
			live.phase = "custody"
			live.custody_since = _clock
	var released := actors.release(id)
	counters.handoffs = int(counters.handoffs) + int(released)
	return released

## Police lookup for a performer body (crowd stand-ins are in no actor registry).
func performer_actor(id: String):
	return actors.actor_of(id) if actors.owns(id) else null

## Read-only case adapter. Missing/unplaced people are absent, never inferred
## dead; crowd slots are durable identities even when their cell has no body.
func person_state(id: String) -> Dictionary:
	var result := {"state": "absent", "position": Vector3.INF}
	if id.is_empty() or id == "player":
		return result
	var combat = _combat()
	if combat != null and combat.has_method("is_actor_dead") and combat.is_actor_dead(id):
		result.state = "dead"
		return result
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd == null or index < 0 or index >= crowd.residents.size():
			return result
		var resident: Dictionary = crowd.residents[index]
		if bool(resident.get("dead", false)):
			result.state = "dead"
		elif bool(resident.get("police_custody", false)) or bool(resident.get("police_custody_completed", false)):
			result.state = "custody"
		elif not bool(resident.get("identity_unplaced", false)) and not bool(resident.get("combat_controlled", false)) and not bool(resident.get("panic", false)):
			result.position = crowd.resident_position(index)
			if Vector3(result.position).is_finite():
				result.state = "ok"
		return result
	var actor = actors.named_actor(id)
	if not is_instance_valid(actor):
		return result
	if actor.get("dead") == true or bool(actor.get_meta("city_dead", false)):
		result.state = "dead"
	elif bool(actor.get_meta("police_custody", false)) or bool(actor.get_meta("police_custody_completed", false)):
		result.state = "custody"
	elif actor.get("enabled") != false and actor.get("combat_override") != true:
		result.position = actor.global_position
		if Vector3(result.position).is_finite():
			result.state = "ok"
	return result

## Exact subject body for LOS exclusion; never substitute a different person.
func _person_collider(id: String):
	var body = performer_actor(id)
	if body is CollisionObject3D and is_instance_valid(body):
		return body
	body = actors.named_actor(id)
	if body is CollisionObject3D and is_instance_valid(body):
		return body
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd != null and index >= 0 and index < crowd.residents.size():
			body = crowd.residents[index].get("body")
			if body is CollisionObject3D and is_instance_valid(body):
				return body
	return null

# --------------------------------------------------------------- live acts

func _tick_live(id: String, delta: float) -> void:
	var live: Dictionary = _live[id]
	var rec := _record(id)
	if rec.is_empty():
		_drop_live(id)
		return
	var phase := str(live.phase)
	if phase == "custody":
		return
	if phase == "fight":
		_tick_fight(rec, live, delta)
		return
	var offender := str(live.offender)
	if not actors.owns(offender) or not actors.still_ours(offender):
		_performer_lost(rec, live)
		return
	var body: Node3D = actors.actor_of(offender)
	var reported := str(rec.state) in ["reported", "responding"]
	if not reported and _player_distance(body.global_position) > ABANDON_DISTANCE:
		if str(rec.state) == "active":
			_cut_short(rec)
		actors.release(offender)
		_drop_live(id)
		return
	match phase:
		"perform":
			_tick_steps(rec, live, delta)
		"linger":
			actors.hold(offender, Vector3.INF, delta, "idle", _clock)
			var until := float(live.linger_until)
			if reported:
				until = maxf(until, float(live.get("reported_at", _clock)) + REPORTED_LINGER_SECONDS)
			if _clock >= until:
				_begin_leave(live, body)
		"stopped":
			var officer = _officer_body(str(live.get("stop_officer", "")))
			actors.hold(offender, officer.global_position if officer != null else Vector3.INF, delta, "stopped", _clock)
			if float(live.get("cited_at", -1.0)) >= 0.0 and _clock - float(live.cited_at) >= CITED_RELEASE:
				actors.release(offender)
				live.phase = "custody" # Handled; wait for the police to close the call.
				live.custody_since = _clock
			elif _clock - float(live.get("stopped_at", _clock)) > STOPPED_LIMIT:
				live.phase = "linger"
		"leaving":
			var result := actors.walk(offender, live.leave_to, delta, 1.3)
			if result == Tactics.MOVE_BLOCKED:
				live.blocked = float(live.blocked) + delta
			if result == Tactics.MOVE_ARRIVED or float(live.blocked) >= LEAVE_BLOCKED_SECONDS:
				actors.release(offender)
				_drop_live(id)

func _tick_steps(rec: Dictionary, live: Dictionary, delta: float) -> void:
	var steps: Array = live.steps
	var index := int(live.step)
	if index >= steps.size():
		_finish_act(rec, live)
		return
	var step: Dictionary = steps[index]
	var offender := str(live.offender)
	live.acting = bool(step.get("act", false))
	match str(step.op):
		"walk":
			var result := actors.walk(offender, step.to, delta, float(step.speed))
			var body: Node3D = actors.actor_of(offender)
			var near_enough: bool = step.has("within") and body != null and Tactics.flat(body.global_position, step.near) <= float(step.within)
			if result == Tactics.MOVE_ARRIVED or near_enough:
				_next_step(live)
			elif result == Tactics.MOVE_BLOCKED:
				live.blocked = float(live.blocked) + delta
				if float(live.blocked) >= STEP_BLOCKED_SECONDS:
					_give_up_walk(rec, live)
			elif result == Tactics.MOVE_MOVED:
				live.blocked = maxf(0.0, float(live.blocked) - delta)
		"act":
			live.timer = float(live.timer) + delta
			actors.hold(offender, step.get("face", Vector3.INF), delta, str(step.pose), float(live.timer))
			if not bool(step.get("done", false)) and float(live.timer) >= float(step.get("effect_at", 0.0)):
				step.done = true
				_apply_effect(rec, live, str(step.get("effect", "")))
			if float(live.timer) >= float(step.seconds):
				_next_step(live)

func _next_step(live: Dictionary) -> void:
	live.step = int(live.step) + 1
	live.timer = 0.0
	live.blocked = 0.0
	var body: Node3D = actors.actor_of(str(live.offender))
	if body != null:
		live.step_start = body.global_position

## A leg stayed blocked (a car parked in the way): the act is cut short and the
## performer walks back to where that leg began, never through the obstacle.
func _give_up_walk(rec: Dictionary, live: Dictionary) -> void:
	var back: Vector3 = live.get("step_start", Vector3.INF)
	var body: Node3D = actors.actor_of(str(live.offender))
	live.acting = false
	if str(rec.state) == "active":
		_cut_short(rec)
	if body != null and back.is_finite() and Tactics.flat(body.global_position, back) > 0.5:
		live.phase = "leaving"
		live.leave_to = back
		live.blocked = 0.0
	else:
		actors.release(str(live.offender))
		_drop_live(str(rec.id))

func _finish_act(rec: Dictionary, live: Dictionary) -> void:
	live.acting = false
	if str(rec.state) == "active":
		rec.state = "ended"
		counters.ended = int(counters.ended) + 1
		if (rec.witnesses as Array).is_empty():
			counters.unwitnessed = int(counters.unwitnessed) + 1
	if float(rec.ended_minutes) < 0.0:
		rec.ended_minutes = _minutes()
	live.phase = "linger"
	live.linger_until = _clock + LINGER_SECONDS
	_changed(rec)

func _cut_short(rec: Dictionary) -> void:
	if (rec.witnesses as Array).is_empty():
		_resolve(rec, "cancelled", "", "system")
		return
	rec.state = "ended"
	rec.ended_minutes = _minutes()
	counters.ended = int(counters.ended) + 1
	_changed(rec)

func _performer_lost(rec: Dictionary, live: Dictionary) -> void:
	counters.lost_performers = int(counters.lost_performers) + 1
	if str(rec.state) == "active":
		_cut_short(rec)
	actors.forget(str(live.offender))
	_drop_live(str(rec.id))

func _begin_leave(live: Dictionary, body: Node3D) -> void:
	var heading := Vector3(sin(float(body.get("yaw"))), 0.0, cos(float(body.get("yaw"))))
	for turn in [0.0, 0.8, -0.8, 1.6, -1.6, PI]:
		var dest := body.global_position + heading.rotated(Vector3.UP, float(turn)) * 8.0
		var spot := actors.tactics.walkable(dest)
		if not spot.is_empty() and actors.tactics.link_clear(body.global_position, spot.position):
			live.phase = "leaving"
			live.leave_to = spot.position
			live.blocked = 0.0
			return
	actors.release(str(live.offender))
	_drop_live(str(live.id))

## Combat owns both bodies during a neighbor fight. Afterwards this service keeps
## the attacker at the scene (held where combat let go) for the police.
func _tick_fight(rec: Dictionary, live: Dictionary, delta: float) -> void:
	live.timer = float(live.timer) + delta
	live.acting = true
	var combat = _combat()
	var offender := str(live.offender)
	var status: Dictionary = combat.npc_fight_status(offender) if combat != null else {}
	if bool(status.get("fighting", false)) and float(live.timer) < FIGHT_TIMEOUT:
		return
	_finish_act(rec, live)
	var body = status.get("actor")
	if combat != null and is_instance_valid(body) and str(combat.actor_mode(body)) in ["aggro", "return"]:
		combat.disengage_actor(body)
	if str(rec.state) in CLOSED_STATES or actors.borrow(offender, str(rec.id)) == null:
		_drop_live(str(rec.id)) # Taken by police, knocked down or gone: the record stays.
		return
	live.phase = "linger"
	live.linger_until = _clock + LINGER_SECONDS

func _apply_effect(rec: Dictionary, live: Dictionary, effect: String) -> void:
	var body: Node3D = actors.actor_of(str(live.offender))
	if body == null:
		return
	match effect:
		"drop":
			var forward := Vector3(sin(float(body.get("yaw"))), 0.0, cos(float(body.get("yaw"))))
			var at := body.global_position + forward * 0.55
			_spawn_prop(str(rec.id), at)
			_add_evidence(rec, {"kind": "object", "by": "", "subject_id": str(live.offender), "minutes": _minutes(),
				"at": at, "verified": true, "ref": "dumped_bag"})
		"snatch":
			var victim := str(live.get("victim", ""))
			if victim.is_empty():
				return
			var victim_at := _person_position(victim)
			_add_witness(rec, victim, _kind_of(victim), Tactics.flat(victim_at, body.global_position) if victim_at.is_finite() else 0.0,
				victim_at if victim_at.is_finite() else body.global_position, "victim")
			_add_evidence(rec, {"kind": "statement", "by": victim, "subject_id": str(live.offender), "minutes": _minutes(),
				"at": body.global_position, "verified": true, "ref": "victim"})
			_scare(victim, body.global_position)
			var delay: Array = Templates.template(str(rec.template)).get("report_delay", [5.0, 9.0])
			live.report_due = _clock + _rng.randf_range(float(delay[0]), float(delay[1]))
			live.report_by = victim

func _scare(id: String, origin: Vector3) -> void:
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		if crowd != null and crowd.has_method("panic_resident"):
			crowd.panic_resident(int(id.substr(6)), origin)
		return
	var actor = actors.named_actor(id)
	var combat = _combat()
	if actor != null and combat != null and combat.has_method("_panic_actor"):
		combat._panic_actor(actor, origin, "flee")

func _drop_live(id: String) -> void:
	_live.erase(id)

# --------------------------------------------------------------- witnesses

func _observe_pass() -> void:
	var budget := MAX_RAYS_PER_PASS
	for id in _live.keys():
		var live: Dictionary = _live[id]
		var rec := _record(str(id))
		if rec.is_empty() or not bool(live.get("acting", false)) or str(rec.state) in CLOSED_STATES:
			continue
		budget = _observe(rec, live, budget)
		if budget <= 0:
			break

## The player first, then nearby people round-robin. Each check is range, view
## cone and one sight ray (terrain, buildings and cars occlude; people do not).
func _observe(rec: Dictionary, live: Dictionary, budget: int) -> int:
	var subject = _subject_body(live)
	if subject == null or not subject is CollisionObject3D:
		return budget
	var at: Vector3 = subject.global_position
	var chest := at + Vector3.UP * 1.2
	var skip_subject: RID = subject.get_rid()
	var player = level.get("player")
	if player is Node3D and not _has_witness(rec, "player") and budget > 0:
		var distance := Tactics.flat((player as Node3D).global_position, at)
		if distance <= PLAYER_WITNESS_RADIUS and _player_facing(player, at, distance):
			budget -= 1
			var skip: Array[RID] = [skip_subject]
			if player is CollisionObject3D:
				skip.append((player as CollisionObject3D).get_rid())
			if _clear_line((player as Node3D).global_position + Vector3.UP * 1.5, chest, skip):
				if _add_witness(rec, "player", "player", distance, (player as Node3D).global_position, "sight"):
					counters.player_witnessed = int(counters.player_witnessed) + 1
	if (rec.witnesses as Array).size() >= MAX_WITNESSES or budget <= 0:
		return budget
	var candidates := _witness_candidates(rec, at)
	var count := candidates.size()
	if count == 0:
		return budget
	var start := int(live.get("witness_cursor", 0)) % count
	for k in count:
		if budget <= 0 or (rec.witnesses as Array).size() >= MAX_WITNESSES:
			break
		var candidate: Dictionary = candidates[(start + k) % count]
		live.witness_cursor = (start + k + 1) % count
		if _has_witness(rec, str(candidate.id)):
			continue
		budget -= 1
		var skip: Array[RID] = [skip_subject, candidate.rid]
		if _clear_line(candidate.eye, chest, skip):
			_add_witness(rec, str(candidate.id), str(candidate.kind), float(candidate.distance), candidate.position, "sight")
			if str(rec.policy) == "detain" and str(candidate.kind) == "officer" and (rec.report as Dictionary).is_empty():
				live.report_due = _clock # An officer who sees a theft or a fight calls it in.
				live.report_by = str(candidate.id)
			elif str(Templates.template(str(rec.template)).get("npc_reports", "none")) == "witness" and float(live.get("report_due", -1.0)) < 0.0:
				var delay: Array = Templates.template(str(rec.template)).get("report_delay", [4.0, 8.0])
				live.report_due = _clock + _rng.randf_range(float(delay[0]), float(delay[1]))
				live.report_by = str(candidate.id)
	return budget

## People who could see the act: named contacts, patrols and daily residents in
## range, plus crowd neighbors from the cells around it (nearest first, capped).
func _witness_candidates(rec: Dictionary, at: Vector3) -> Array:
	var result: Array = []
	for provider_name in ["npcs", "residents"]:
		var provider = level.get(provider_name)
		var list = provider.get("actors") if provider != null else null
		if not list is Dictionary:
			continue
		for actor in (list as Dictionary).values():
			if not is_instance_valid(actor) or actor.get("dead") == true or actor.get("enabled") != true:
				continue
			var id := str(actor.get("actor_id"))
			if _is_participant(rec, id):
				continue
			var position: Vector3 = actor.global_position
			var distance := Tactics.flat(position, at)
			if distance > NPC_WITNESS_RADIUS or not _facing(float(actor.get("yaw")), position, at, distance):
				continue
			var police := str(actor.get("cast_id")).begins_with("cop_") or id == "officer" or id.begins_with("patrol_officer_")
			result.append({"id": id, "kind": "officer" if police else ("resident" if provider_name == "residents" else "contact"),
				"position": position, "eye": position + Vector3.UP * 1.5, "rid": actor.get_rid(), "distance": distance})
	var crowd = _crowd()
	var cells = crowd.get("_cells") if crowd != null else null
	if cells is Dictionary:
		var size := float(crowd.CELL)
		var reach := NPC_WITNESS_RADIUS
		var crowd_found: Array = []
		for x in range(floori((at.x - reach) / size), floori((at.x + reach) / size) + 1):
			for z in range(floori((at.z - reach) / size), floori((at.z + reach) / size) + 1):
				var cell = (cells as Dictionary).get(Vector2i(x, z))
				if cell == null or (cell.nodes as Array).is_empty():
					continue
				for index in cell.resident_indices:
					var resident: Dictionary = crowd.residents[index]
					if resident.get("dead", false) or resident.get("combat_controlled", false) or not is_instance_valid(resident.get("body")):
						continue
					var id := "crowd_%d" % int(index)
					if _is_participant(rec, id):
						continue
					var position: Vector3 = resident.position
					var distance := Tactics.flat(position, at)
					if distance > NPC_WITNESS_RADIUS or not _facing(float(resident.yaw), position, at, distance):
						continue
					crowd_found.append({"id": id, "kind": "crowd", "position": position,
						"eye": position + Vector3.UP * (1.5 if int(resident.get("pose", 0)) == 0 else 1.1),
						"rid": resident.body.get_rid(), "distance": distance})
		crowd_found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
		result.append_array(crowd_found.slice(0, MAX_CROWD_CANDIDATES))
	return result

func _facing(yaw: float, from: Vector3, to: Vector3, distance: float) -> bool:
	if distance <= NOTICE_RADIUS:
		return true
	var toward := Vector3(to.x - from.x, 0.0, to.z - from.z) / maxf(distance, 0.001)
	return Vector3(sin(yaw), 0.0, cos(yaw)).dot(toward) >= VIEW_DOT

## The view follows the camera's heading (camera_yaw), not the body's facing.
func _player_facing(player: Node3D, at: Vector3, distance: float) -> bool:
	if distance <= NOTICE_RADIUS:
		return true
	var yaw = player.get("camera_yaw")
	if yaw == null:
		yaw = player.get("yaw")
	var toward := Vector3(at.x - player.global_position.x, 0.0, at.z - player.global_position.z) / maxf(distance, 0.001)
	return Vector3(sin(float(yaw)), 0.0, cos(float(yaw))).dot(toward) >= PLAYER_VIEW_DOT

func _clear_line(from: Vector3, to: Vector3, skip: Array[RID]) -> bool:
	var space := _space()
	if space == null or not from.is_finite() or not to.is_finite():
		return false
	rays += 1
	_ray.from = from
	_ray.to = to
	_ray.exclude = skip
	return space.intersect_ray(_ray).is_empty()

func _subject_body(live: Dictionary) -> Node3D:
	var offender := str(live.offender)
	if str(live.phase) == "fight":
		var combat = _combat()
		var body = combat.npc_fight_status(offender).get("actor") if combat != null else null
		return body if is_instance_valid(body) else null
	return actors.actor_of(offender)

# --------------------------------------------------------------- reports

func _file_report(rec: Dictionary, reporter_id: String, channel: String, phone: bool) -> Dictionary:
	var police = _police()
	if police == null or not police.has_method("report_incident"):
		_emit_status(rec, "rejected", "Police dispatch is unavailable.", reporter_id, phone)
		return {"ok": false, "reason": "police_unavailable", "message": "Police dispatch is unavailable."}
	var previous := str(rec.state)
	rec.report = {"by": reporter_id, "channel": channel, "minutes": _minutes(), "police_incident_id": "",
		"status": "report_received", "corroborating": [], "phone": phone}
	rec.state = "reported"
	var live: Dictionary = _live.get(str(rec.id), {})
	if not live.is_empty():
		live.reported_at = _clock
	var suspects: Array = []
	for person in rec.participants:
		if str(person.role) == "offender":
			suspects.append(str(person.id))
	var at := _vec(rec.at)
	var body = performer_actor(suspects[0]) if not suspects.is_empty() else null
	if is_instance_valid(body):
		at = body.global_position
	var reply: Dictionary = police.report_incident({"incident_ref": str(rec.id), "policy": str(rec.policy), "kind": str(rec.category),
		"suspects": suspects, "at": at, "reporter_id": reporter_id, "phone": phone})
	if not bool(reply.get("ok", false)):
		rec.report = {}
		rec.state = previous
		var text := str(reply.get("message", "Police could not take the report."))
		_emit_status(rec, "rejected", text, reporter_id, phone)
		counters.rejected_reports = int(counters.rejected_reports) + 1
		return {"ok": false, "reason": "police_unavailable", "message": text}
	rec.report.police_incident_id = str(reply.get("incident_id", ""))
	_add_participant(rec, reporter_id, "reporter")
	counters.reports = int(counters.reports) + 1
	if reporter_id != "player":
		counters.npc_reports = int(counters.npc_reports) + 1
	_changed(rec)
	return {"ok": true, "reason": "", "message": str(reply.get("message", ""))}

## Neighbors who call it in themselves (victims of theft, witnesses of a fight,
## officers who saw it): only after a short delay and only while able to.
func _npc_reports() -> void:
	for id in _live.keys():
		var live: Dictionary = _live[id]
		var rec := _record(str(id))
		if rec.is_empty() or not (rec.report as Dictionary).is_empty() or str(rec.state) in CLOSED_STATES:
			continue
		var due := float(live.get("report_due", -1.0))
		if due < 0.0 or _clock < due:
			continue
		live.report_due = -1.0
		var by := str(live.get("report_by", ""))
		if by.is_empty() or not _reporter_able(by) or not _may_report(rec, by):
			continue
		report_incident(str(rec.id), by, {"channel": "officer" if by.begins_with("patrol_officer_") else "witness_call", "phone": false})

func _reporter_able(id: String) -> bool:
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		return crowd != null and not crowd.is_dead(int(id.substr(6)))
	var actor = actors.named_actor(id)
	return is_instance_valid(actor) and actor.get("dead") != true

func _may_report(rec: Dictionary, reporter_id: String) -> bool:
	if reporter_id.is_empty():
		return false
	if _has_witness(rec, reporter_id):
		return true
	for entry in rec.evidence:
		if str(entry.by) == reporter_id and bool(entry.verified) and str(entry.kind) == "photo" and _is_offender(rec, str(entry.subject_id)):
			return true
	return false

func _in_window(rec: Dictionary) -> bool:
	var since := float(rec.ended_minutes) if float(rec.ended_minutes) >= 0.0 else float(rec.created_minutes)
	return _minutes() - since <= REPORT_WINDOW_MINUTES

func _refuse(result: Dictionary, reason: String, message: String) -> Dictionary:
	counters.rejected_reports = int(counters.rejected_reports) + 1
	result.ok = false
	result.reason = reason
	result.message = message
	return result

## `police` is the relayed police payload (or {"stage": ...}): its dispatch
## stage/handling ride along so the phone can tell dispatch from incident state.
func _emit_status(rec: Dictionary, status: String, text: String, by := "", phone := false, police := {}) -> void:
	var report: Dictionary = rec.report
	report_status_changed.emit({"incident_id": str(rec.id), "police_incident_id": str(report.get("police_incident_id", "")),
		"status": status, "outcome": str((rec.resolution as Dictionary).get("outcome", "")),
		"text": text if not text.is_empty() else _status_text(status), "by": str(report.get("by", by)),
		"phone": bool(report.get("phone", phone)) or _phone_followups.has(str(rec.id)), "minutes": _minutes(), "title": str(rec.title),
		"stage": str(police.get("stage", "")), "handling": str(police.get("handling", "")), "street": str(rec.get("street", ""))})

static func _status_text(status: String) -> String:
	match status:
		"report_received":
			return "Dispatch has the report."
		"responding":
			return "Officers are on the way."
		"on_scene":
			return "An officer is at the scene."
		"resolved":
			return "The report has been dealt with."
		"unavailable":
			return "No officers could respond."
	return ""

static func _outcome_from_police(outcome: String, event: String) -> String:
	if event == "unavailable" or outcome == "unavailable":
		return "unanswered"
	if outcome in OUTCOMES:
		return outcome
	return "no_threat"

# --------------------------------------------------------------- lifecycle

func _resolve(rec: Dictionary, outcome: String, text: String, by: String) -> void:
	if str(rec.state) in CLOSED_STATES:
		return
	var reported := not (rec.report as Dictionary).is_empty()
	rec.state = "expired" if outcome == "expired" else ("cancelled" if outcome == "cancelled" else "resolved")
	rec.resolution = {"outcome": outcome, "minutes": _minutes(), "text": text.left(160), "by": by}
	outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
	match str(rec.state):
		"expired":
			counters.expired = int(counters.expired) + 1
		"cancelled":
			counters.cancelled = int(counters.cancelled) + 1
		_:
			counters.resolved = int(counters.resolved) + 1
	if reported:
		rec.report.status = "unavailable" if outcome == "unanswered" else "resolved"
		_emit_status(rec, str(rec.report.status), text, "", false, {"stage": PoliceStatus.record_stage(outcome)})
	_phone_followups.erase(str(rec.id))
	var live: Dictionary = _live.get(str(rec.id), {})
	if not live.is_empty():
		if actors.owns(str(live.offender)):
			actors.release(str(live.offender))
		_drop_live(str(rec.id))
	_clear_props(str(rec.id))
	_changed(rec)
	incident_closed.emit(_serialize(rec))
	if by != "police":
		# Closed here (a case settled it) while officers may still be on the way:
		# the call stands down instead of answering an incident that is over.
		# The record is already closed, so the police closure relay is a no-op.
		var police = _police()
		if police != null and police.has_method("cancel_ref") and police.has_method("has_open_ref") and bool(police.has_open_ref(str(rec.id))):
			police.cancel_ref(str(rec.id), "This was settled, so officers are standing down.")

func _housekeeping() -> void:
	_connect_services()
	_npc_reports()
	_settle()
	for rec in records:
		if str(rec.state) in ["active", "ended"] and not _in_window(rec):
			_resolve(rec, "expired", "Nobody reported it in time.", "system")
	for id in _live.keys():
		var live: Dictionary = _live[id]
		if str(live.phase) == "custody" and _clock - float(live.get("custody_since", _clock)) > INCIDENT_HOLD_LIMIT:
			_drop_live(str(id)) # The police never closed the call: free the slot.
	while records.size() > MAX_RECORDS:
		var dropped := false
		for i in records.size():
			if str(records[i].state) in CLOSED_STATES:
				_phone_followups.erase(str(records[i].id))
				records.remove_at(i)
				revision += 1
				dropped = true
				break
		if not dropped:
			break

## Records whose live part is gone (a reload, a reset): an act nobody performs
## any more has ended; a report with no open police call was interrupted (a
## case report reopens so the case can file it again).
func _settle() -> void:
	var police = _police()
	for rec in records:
		var state := str(rec.state)
		if state == "active" and not _live.has(str(rec.id)):
			if (rec.witnesses as Array).is_empty():
				_resolve(rec, "cancelled", "", "system")
			else:
				rec.state = "ended"
				if float(rec.ended_minutes) < 0.0:
					rec.ended_minutes = float(rec.updated_minutes) # When it was last seen, not now.
				_changed(rec)
		elif state in ["reported", "responding"]:
			var open: bool = police != null and police.has_method("has_open_ref") and bool(police.has_open_ref(str(rec.id)))
			if open:
				continue
			if str(rec.source).begins_with("case:"):
				rec.state = "ended"
				rec.report = {}
				_phone_followups.erase(str(rec.id))
				_changed(rec)
			else:
				# Officer responses are never saved: say what is known, not how it went.
				_resolve(rec, "interrupted", "The response stopped before officers finished, so its result is unknown.", "system")

func _new_record(template: String, at: Vector3, source: String, case_id: String, offender: String, victim: String) -> Dictionary:
	var t := Templates.template(template)
	var now := _minutes()
	var rec := {"id": "inc_%06d" % next_sequence, "template": template, "title": str(t.get("title", template)),
		"origin": str(t.get("origin", "")), "category": str(t.get("category", "infraction")),
		"policy": str(t.get("policy", "warn")), "state": "active", "source": source, "case_id": case_id.left(64),
		"at": at, "street": _street(at), "created_minutes": now, "ended_minutes": -1.0, "updated_minutes": now,
		"participants": [], "witnesses": [], "evidence": [], "report": {}, "resolution": {}}
	_add_participant(rec, offender, "offender")
	if not victim.is_empty():
		_add_participant(rec, victim, "victim")
	return rec

func _commit(rec: Dictionary) -> void:
	next_sequence += 1
	records.append(rec)
	revision += 1
	var summary := _serialize(rec)
	incident_opened.emit(summary)
	# Listeners of incident_changed alone (the case engine) see new incidents too.
	incident_changed.emit(summary.duplicate(true))

func _changed(rec: Dictionary) -> void:
	rec.updated_minutes = _minutes()
	revision += 1
	incident_changed.emit(_serialize(rec))

func _add_participant(rec: Dictionary, id: String, role: String) -> void:
	if id.is_empty() or (rec.participants as Array).size() >= MAX_PARTICIPANTS:
		return
	for person in rec.participants:
		if str(person.id) == id and str(person.role) == role:
			return
	rec.participants.append({"id": id, "role": role, "kind": _kind_of(id)})

func _add_witness(rec: Dictionary, id: String, kind: String, distance: float, at: Vector3, via: String) -> bool:
	if id.is_empty() or _has_witness(rec, id) or (rec.witnesses as Array).size() >= MAX_WITNESSES:
		return false
	rec.witnesses.append({"id": id, "kind": kind if kind in PEOPLE_KINDS else _kind_of(id), "minutes": _minutes(),
		"distance": snappedf(distance, 0.01), "at": at, "via": via})
	counters.witnesses = int(counters.witnesses) + 1
	_changed(rec)
	return true

func _add_evidence(rec: Dictionary, entry: Dictionary) -> bool:
	# The case bridge and the incident photo verifier can submit the same
	# capture. Idempotence precedes the cap; distinct statements remain distinct.
	if str(entry.get("kind", "")) == "photo" and not str(entry.get("ref", "")).is_empty():
		for existing in rec.evidence:
			if str(existing.get("kind", "")) == "photo" and str(existing.get("ref", "")) == str(entry.ref) \
					and str(existing.get("by", "")) == str(entry.get("by", "")) and str(existing.get("subject_id", "")) == str(entry.get("subject_id", "")):
				# A later trusted verification may strengthen the same capture.
				if bool(entry.get("verified", false)) and not bool(existing.get("verified", false)):
					existing.verified = true
					_changed(rec)
				return true
	if (rec.evidence as Array).size() >= MAX_EVIDENCE:
		return false
	rec.evidence.append(entry)
	_changed(rec)
	return true

func _has_witness(rec: Dictionary, id: String) -> bool:
	for entry in rec.witnesses:
		if str(entry.id) == id:
			return true
	return false

func _witness_minutes(rec: Dictionary, id: String) -> float:
	for entry in rec.witnesses:
		if str(entry.id) == id:
			return float(entry.minutes)
	return -INF

func _is_offender(rec: Dictionary, id: String) -> bool:
	for person in rec.participants:
		if str(person.id) == id and str(person.role) == "offender":
			return true
	return false

func _is_participant(rec: Dictionary, id: String) -> bool:
	for person in rec.participants:
		if str(person.id) == id and str(person.role) in ["offender", "victim"]:
			return true
	return false

func _kind_of(id: String) -> String:
	if id == "player":
		return "player"
	if id.begins_with("crowd_"):
		return "crowd"
	if id == "officer" or id.begins_with("patrol_officer_"):
		return "officer"
	var residents = level.get("residents") if level != null else null
	if residents != null and residents.get("actors") is Dictionary and (residents.actors as Dictionary).has(id):
		return "resident"
	return "contact"

func _record(id: String) -> Dictionary:
	for rec in records:
		if str(rec.id) == id:
			return rec
	return {}

# --------------------------------------------------------------- spawning

func _try_spawn() -> Dictionary:
	counters.spawn_attempts = int(counters.spawn_attempts) + 1
	if _live.size() >= MAX_LIVE:
		return _no_spawn("live_cap")
	var player = level.get("player")
	if not player is Node3D:
		return _no_spawn("no_player")
	var law = level.get("law")
	if law != null and (int(law.get("wanted") if law.get("wanted") != null else 0) > 0 or law.get("recovering") == true):
		return _no_spawn("player_busy")
	var police = _police()
	if police != null and (police.get("incidents") as Array).size() >= 2:
		return _no_spawn("police_busy")
	var allowed: Array = []
	for id in Templates.ambient_ids():
		var taken := false
		for live in _live.values():
			taken = taken or str(_record(str(live.id)).get("template", "")) == id
		if not taken:
			allowed.append(id)
	var template := Templates.pick(_rng, allowed)
	if template.is_empty():
		return _no_spawn("no_template")
	var plan := _plan(template, {})
	if plan.is_empty():
		return {"ok": false, "incident_id": "", "reason": last_spawn_reason}
	return _start(template, plan)

func _no_spawn(reason: String) -> Dictionary:
	last_spawn_reason = reason
	return {"ok": false, "incident_id": "", "reason": reason}

## {offender, victim, steps, at, fight} or {} (last_spawn_reason says why).
func _plan(template: String, options: Dictionary) -> Dictionary:
	var pinned := str(options.get("offender", ""))
	var candidates: Array = []
	if not pinned.is_empty():
		var at := _person_position(pinned)
		if not at.is_finite():
			last_spawn_reason = "offender_unavailable"
			return {}
		candidates.append({"id": pinned, "position": at, "yaw": _person_yaw(pinned), "group": ""})
	else:
		var player = level.get("player")
		if not player is Node3D:
			last_spawn_reason = "no_player"
			return {}
		candidates = _crowd_candidates((player as Node3D).global_position, SPAWN_NEAR, SPAWN_FAR, MAX_PLAN_CANDIDATES)
		if candidates.is_empty():
			last_spawn_reason = "no_free_neighbors"
			return {}
	for candidate in candidates:
		var plan := _plan_for(template, candidate, options)
		if not plan.is_empty():
			return plan
	if last_spawn_reason.is_empty():
		last_spawn_reason = "no_valid_plan"
	return {}

func _plan_for(template: String, who: Dictionary, options: Dictionary) -> Dictionary:
	var from: Vector3 = who.position
	var route: Array = options.get("route", [])
	last_spawn_reason = ""
	match template:
		"jaywalking":
			var to := Vector3.INF
			if not route.is_empty():
				to = route[-1]
			else:
				var crossing := _crossing_for(from)
				if crossing.is_empty():
					last_spawn_reason = "no_crossing"
					return {}
				to = crossing.to
			var steps: Array = []
			for point in (route if not route.is_empty() else [to]):
				steps.append({"op": "walk", "to": point, "speed": 1.15, "act": true})
			return {"offender": str(who.id), "victim": "", "steps": steps, "at": from.lerp(to, 0.5), "fight": false}
		"mail_tampering":
			var stops: Array = options.get("stops", [])
			if stops.is_empty():
				stops = _mail_stops(from)
			if stops.is_empty():
				last_spawn_reason = "no_mailbox"
				return {}
			var steps: Array = []
			for stop in stops:
				steps.append({"op": "walk", "to": stop.stand, "speed": 1.2, "act": false})
				steps.append({"op": "act", "pose": "bend", "seconds": 4.5, "face": stop.face, "act": true})
			return {"offender": str(who.id), "victim": "", "steps": steps, "at": stops[0].face, "fight": false}
		"sidewalk_dumping":
			var spots: Array = route if route.size() >= 2 else _dumping_spots(from)
			if spots.size() < 2:
				last_spawn_reason = "no_dumping_spot"
				return {}
			var face: Vector3 = spots[0] + (spots[1] - spots[0]).normalized()
			return {"offender": str(who.id), "victim": "", "at": spots[0], "fight": false, "steps": [
				{"op": "walk", "to": spots[0], "speed": 1.2, "act": false},
				{"op": "act", "pose": "drop", "seconds": 1.8, "face": face, "effect": "drop", "effect_at": 1.0, "act": true},
				{"op": "walk", "to": spots[1], "speed": 1.4, "act": true}]}
		"bag_snatch":
			var victim := _pick_victim(who, options, 2.0, 8.0)
			if victim.is_empty():
				last_spawn_reason = "no_victim"
				return {}
			var victim_at: Vector3 = victim.position
			var away := Vector3(from.x - victim_at.x, 0.0, from.z - victim_at.z).normalized()
			var getaway: Vector3 = route[-1] if not route.is_empty() else _getaway(victim_at, away)
			if not getaway.is_finite():
				last_spawn_reason = "no_getaway"
				return {}
			var reach := victim_at + away * 0.9
			return {"offender": str(who.id), "victim": str(victim.id), "at": victim_at, "fight": false, "steps": [
				{"op": "walk", "to": reach, "speed": 1.3, "act": false, "near": victim_at, "within": 1.3},
				{"op": "act", "pose": "snatch", "seconds": 0.8, "face": victim_at, "effect": "snatch", "effect_at": 0.4, "act": true},
				{"op": "walk", "to": getaway, "speed": 2.6, "act": true}]}
		"street_fight":
			# A neighbor's own stable disposition decides whether they would start one.
			if Combat.default_reaction(str(who.id)) == "flee":
				last_spawn_reason = "peaceful_disposition"
				return {}
			var victim := _pick_victim(who, options, 1.0, 7.0)
			if victim.is_empty():
				last_spawn_reason = "no_victim"
				return {}
			return {"offender": str(who.id), "victim": str(victim.id), "at": from.lerp(victim.position, 0.5), "fight": true, "steps": []}
	last_spawn_reason = "unknown_template"
	return {}

func _start(template: String, plan: Dictionary) -> Dictionary:
	var id := "inc_%06d" % next_sequence
	var offender := str(plan.offender)
	var victim := str(plan.get("victim", ""))
	var live := {"id": id, "offender": offender, "victim": victim, "steps": plan.steps, "step": 0, "timer": 0.0,
		"blocked": 0.0, "phase": "perform", "acting": false, "report_due": -1.0, "report_by": "", "witness_cursor": 0}
	if bool(plan.get("fight", false)):
		var combat = _combat()
		if combat == null or not combat.has_method("start_npc_fight"):
			return _no_spawn("no_combat")
		var started: Dictionary = combat.start_npc_fight(offender, victim, {"seconds": FIGHT_SECONDS, "incident_id": id})
		if not bool(started.get("ok", false)):
			return _no_spawn("fight_" + str(started.get("reason", "refused")))
		live.phase = "fight"
		live.acting = true
	else:
		var body := actors.borrow(offender, id)
		if body == null:
			return _no_spawn("offender_unavailable")
		live.step_start = body.global_position
	var rec := _new_record(template, plan.at, "world", "", offender, victim)
	_commit(rec)
	_live[id] = live
	if bool(plan.get("fight", false)):
		# The person being hit knows who hit them; bystanders still need sight.
		var victim_at := _person_position(victim)
		_add_witness(rec, victim, _kind_of(victim), 0.0, victim_at if victim_at.is_finite() else Vector3(plan.at), "victim")
	counters.spawned = int(counters.spawned) + 1
	last_spawn_reason = ""
	return {"ok": true, "incident_id": id, "reason": ""}

func _crowd_candidates(center: Vector3, near: float, far: float, limit: int) -> Array:
	var crowd = _crowd()
	var cells = crowd.get("_cells") if crowd != null else null
	if not cells is Dictionary:
		return []
	var size := float(crowd.CELL)
	var found: Array = []
	for x in range(floori((center.x - far) / size), floori((center.x + far) / size) + 1):
		for z in range(floori((center.z - far) / size), floori((center.z + far) / size) + 1):
			var cell = (cells as Dictionary).get(Vector2i(x, z))
			if cell == null or (cell.nodes as Array).is_empty():
				continue
			for index in cell.resident_indices:
				var resident: Dictionary = crowd.residents[index]
				if not _crowd_free(resident):
					continue
				var distance := Tactics.flat(resident.position, center)
				if distance < near or distance > far:
					continue
				found.append({"id": "crowd_%d" % int(index), "index": int(index), "position": resident.position,
					"yaw": float(resident.yaw), "group": str(resident.get("social_group_id", ""))})
	# Deterministic shuffle: varied neighbors, reproducible fixtures.
	for i in range(found.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap = found[i]
		found[i] = found[j]
		found[j] = swap
	return found.slice(0, limit)

func _crowd_free(resident: Dictionary) -> bool:
	if resident.get("dead", false) or resident.get("combat_controlled", false) or resident.get("panic", false):
		return false
	if resident.get("police_custody", false) or resident.get("identity_unplaced", false) or resident.get("bicycle_avoiding", false):
		return false
	if resident.has("bicycle_rejoin") or int(resident.get("pose", 0)) != 0 or str(resident.get("activity", "")) == "porch":
		return false
	return is_instance_valid(resident.get("body"))

func _pick_victim(who: Dictionary, options: Dictionary, near: float, far: float) -> Dictionary:
	var pinned := str(options.get("victim", ""))
	if not pinned.is_empty():
		var at := _person_position(pinned)
		return {"id": pinned, "position": at} if at.is_finite() and pinned != str(who.id) else {}
	var from: Vector3 = who.position
	var best: Dictionary = {}
	for candidate in _crowd_candidates(from, near, far, MAX_CROWD_CANDIDATES):
		if str(candidate.id) == str(who.id) or not actors.tactics.link_clear(from, candidate.position):
			continue
		# A companion from the same group first; otherwise the nearest clear one.
		if not str(who.get("group", "")).is_empty() and str(candidate.group) == str(who.group):
			return candidate
		if best.is_empty() or Tactics.flat(candidate.position, from) < Tactics.flat(best.position, from):
			best = candidate
	return best

func _getaway(from: Vector3, away: Vector3) -> Vector3:
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0]:
		var dest := from + away.rotated(Vector3.UP, float(turn)) * 12.0
		var spot := actors.tactics.walkable(dest)
		if not spot.is_empty() and actors.tactics.link_clear(from + away * 1.2, spot.position):
			return spot.position
	return Vector3.INF

## Mid-block, away from crosswalks and intersections: across the nearest road
## from the sidewalk the neighbor already stands on, along swept clear links.
func _crossing_for(at: Vector3) -> Dictionary:
	var near := _nearest_road(at)
	if near.is_empty():
		return {}
	var seg: Dictionary = near.seg
	var half := float(seg.half)
	var distance := float(near.distance)
	if distance < half + 0.3 or distance > half + 4.5:
		return {}
	var station := float(near.station)
	if station < ROAD_END_CLEARANCE or station > float(seg.road_length) - ROAD_END_CLEARANCE:
		return {}
	var across: Vector3 = seg.across
	var center: Vector3 = near.closest
	var side := signf(Vector3(at.x - center.x, 0.0, at.z - center.z).dot(across))
	var target := center - across * side * (half + 1.4)
	if _near_crosswalk(center) or _in_intersection(center, seg) or _in_intersection(target, seg):
		return {}
	var spot := actors.tactics.walkable(target)
	if spot.is_empty():
		return {}
	var mid := actors.tactics.walkable(center)
	if mid.is_empty() or not actors.tactics.link_clear(at, mid.position) or not actors.tactics.link_clear(mid.position, spot.position):
		return {}
	return {"from": at, "to": spot.position, "center": mid.position}

func _dumping_spots(from: Vector3) -> Array:
	var near := _nearest_road(from)
	if near.is_empty():
		return []
	var seg: Dictionary = near.seg
	for sign in [1.0, -1.0]:
		var along: Vector3 = seg.tangent * sign
		for metres in [5.0, 6.5, 4.0]:
			var spot := actors.tactics.walkable(from + along * metres)
			if spot.is_empty() or not actors.tactics.link_clear(from, spot.position) or not _on_sidewalk(spot.position):
				continue
			var leave := actors.tactics.walkable(spot.position + along * 6.0)
			if leave.is_empty() or not actors.tactics.link_clear(spot.position, leave.position) or not _on_sidewalk(leave.position):
				continue
			return [spot.position, leave.position]
	return []

func _on_sidewalk(point: Vector3) -> bool:
	var near := _nearest_road(point)
	return not near.is_empty() and float(near.distance) >= float(near.seg.half) + 0.3 and float(near.distance) <= float(near.seg.half) + 5.0

func _mail_stops(from: Vector3) -> Array:
	_index_mailboxes()
	var nearby: Array = []
	for box in _mailboxes:
		var distance := Tactics.flat(box.position, from)
		if distance <= 25.0:
			nearby.append({"box": box, "distance": distance})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var stops: Array = []
	var previous := from
	for entry in nearby:
		if stops.size() >= 2:
			break
		var box: Dictionary = entry.box
		var spot := actors.tactics.walkable(box.position + box.normal * 0.8)
		if spot.is_empty() or not actors.tactics.link_clear(previous, spot.position):
			continue
		stops.append({"stand": spot.position, "face": box.position})
		previous = spot.position
	return stops

func _index_mailboxes() -> void:
	if _mailboxes_indexed:
		return
	_mailboxes_indexed = true
	var details = level.get("neighborhood_details") if level != null else null
	var list = details.get("records") if details != null else null
	if not list is Array:
		return
	for record in list:
		if record is Dictionary and str(record.get("kind", "")) in ["mailbox", "postal_drop"] and record.get("position") is Vector3:
			var normal: Vector3 = record.get("normal", Vector3.FORWARD) if record.get("normal") is Vector3 else Vector3.FORWARD
			_mailboxes.append({"position": record.position, "normal": Vector3(normal.x, 0.0, normal.z).normalized()})

func _near_crosswalk(point: Vector3) -> bool:
	var details = level.get("neighborhood_details") if level != null else null
	var crossings = details.get("_crossings") if details != null else null
	if crossings is Array:
		for crossing in crossings:
			if crossing is Vector3 and Tactics.flat(crossing, point) < CROSSING_CLEARANCE:
				return true
	return false

func _in_intersection(point: Vector3, seg: Dictionary) -> bool:
	for other in _segments_near(point):
		if int(other.road) == int(seg.road):
			continue
		var closest := Geometry3D.get_closest_point_to_segment(Vector3(point.x, 0.0, point.z),
			Vector3(other.a.x, 0.0, other.a.z), Vector3(other.b.x, 0.0, other.b.z))
		if closest.distance_to(Vector3(point.x, 0.0, point.z)) <= float(other.half) + 3.0:
			return true
	return false

func _nearest_road(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var flat_point := Vector3(point.x, 0.0, point.z)
	for seg in _segments_near(point):
		var a := Vector3(seg.a.x, 0.0, seg.a.z)
		var b := Vector3(seg.b.x, 0.0, seg.b.z)
		var closest := Geometry3D.get_closest_point_to_segment(flat_point, a, b)
		var distance := closest.distance_to(flat_point)
		if best.is_empty() or distance < float(best.distance):
			var t := clampf((closest - a).length() / maxf(float(seg.length), 0.001), 0.0, 1.0)
			best = {"seg": seg, "distance": distance, "station": float(seg.start) + float(seg.length) * t,
				"closest": Vector3(closest.x, Vector3(seg.a).lerp(seg.b, t).y, closest.z)}
	return best

func _segments_near(point: Vector3) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var cell := Vector2i(floori(point.x / ROAD_GRID), floori(point.z / ROAD_GRID))
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			for index in _road_grid.get(Vector2i(x, z), []):
				if not seen.has(index):
					seen[index] = true
					result.append(_roads[index])
	return result

func _index_roads() -> void:
	_roads.clear()
	_road_grid.clear()
	var data = level.get("level_data") if level != null else null
	if not data is Dictionary:
		return
	var road_index := 0
	for road in (data as Dictionary).get("roads", []):
		if not road is Dictionary:
			continue
		var points: Array = road.get("points", [])
		var half := float(road.get("width", 9.5)) * 0.5
		var total := 0.0
		var first := _roads.size()
		for i in range(1, points.size()):
			var a := _vec(points[i - 1])
			var b := _vec(points[i])
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			if length < 0.5:
				total += length
				continue
			var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z) / length
			_roads.append({"a": a, "b": b, "half": half, "length": length, "start": total, "tangent": tangent,
				"across": Vector3(-tangent.z, 0.0, tangent.x), "road": road_index, "road_length": 0.0})
			total += length
		for index in range(first, _roads.size()):
			var seg: Dictionary = _roads[index]
			seg.road_length = total
			var pad := half + 6.0
			var low := Vector2i(floori((minf(seg.a.x, seg.b.x) - pad) / ROAD_GRID), floori((minf(seg.a.z, seg.b.z) - pad) / ROAD_GRID))
			var high := Vector2i(floori((maxf(seg.a.x, seg.b.x) + pad) / ROAD_GRID), floori((maxf(seg.a.z, seg.b.z) + pad) / ROAD_GRID))
			for x in range(low.x, high.x + 1):
				for z in range(low.y, high.y + 1):
					var key := Vector2i(x, z)
					if not _road_grid.has(key):
						_road_grid[key] = []
					_road_grid[key].append(index)
		road_index += 1

# --------------------------------------------------------------- props

func _spawn_prop(incident_id: String, at: Vector3) -> void:
	while _props.size() >= MAX_PROPS:
		var oldest: Dictionary = _props.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.queue_free()
	var space := _space()
	var ground := at
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at - Vector3.UP * 2.0, 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			ground = hit.position
	if _prop_material == null:
		_prop_material = StandardMaterial3D.new()
		_prop_material.albedo_color = Color("2c3a30")
		_prop_material.roughness = 0.85
	var mesh := MeshInstance3D.new()
	mesh.name = "DumpedBag"
	var box := BoxMesh.new()
	box.size = Vector3(0.46, 0.34, 0.36)
	mesh.mesh = box
	mesh.material_override = _prop_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = ground + Vector3.UP * 0.17
	_props.append({"node": mesh, "incident": incident_id})

func _clear_props(incident_id: String) -> void:
	for prop in _props.duplicate():
		if incident_id.is_empty() or str(prop.incident) == incident_id:
			if is_instance_valid(prop.node):
				prop.node.queue_free()
			_props.erase(prop)

# --------------------------------------------------------------- serialization

func _serialize(rec: Dictionary) -> Dictionary:
	var copy: Dictionary = rec.duplicate(true)
	copy.at = _array(_vec(rec.at))
	for list_name in ["witnesses", "evidence"]:
		for entry in copy[list_name]:
			entry.at = _array(_vec(entry.at))
	return copy

func _deserialize(entry: Dictionary) -> Dictionary:
	var rec: Dictionary = entry.duplicate(true)
	rec.at = _vec(entry.at)
	for list_name in ["witnesses", "evidence"]:
		for item in rec[list_name]:
			item.at = _vec(item.at)
	return rec

func _validate_record(entry) -> String:
	if not entry is Dictionary:
		return "incident must be an object"
	var rec: Dictionary = entry
	var id := str(rec.get("id", ""))
	if not rec.get("id") is String or id.length() != 10 or not id.begins_with("inc_") or not id.substr(4).is_valid_int() or int(id.substr(4)) < 1:
		return "invalid incident id"
	if not Templates.has(str(rec.get("template", ""))):
		return "unknown incident template"
	if not str(rec.get("state", "")) in STATES:
		return "invalid incident state"
	for key in ["title", "origin", "category", "policy", "source", "case_id", "street"]:
		if not rec.get(key) is String or str(rec[key]).length() > 160:
			return "invalid incident field: " + key
	if not str(rec.policy) in ["warn", "detain"]:
		return "invalid incident policy"
	if not (str(rec.source) == "world" or str(rec.source).begins_with("case:") or str(rec.source).begins_with("external:")):
		return "invalid incident source"
	if not _point(rec.get("at")):
		return "invalid incident position"
	for key in ["created_minutes", "ended_minutes", "updated_minutes"]:
		if not _number(rec.get(key)) or float(rec[key]) < -1.0 or float(rec[key]) > 1.0e9:
			return "invalid incident time"
	var people = rec.get("participants")
	if not people is Array or people.size() > MAX_PARTICIPANTS:
		return "invalid incident participants"
	for person in people:
		if not person is Dictionary or not person.get("id") is String or str(person.id).is_empty() or str(person.id).length() > 64 \
				or not str(person.get("role", "")) in ROLES or not str(person.get("kind", "")) in PEOPLE_KINDS:
			return "invalid incident participant"
	var witnesses = rec.get("witnesses")
	if not witnesses is Array or witnesses.size() > MAX_WITNESSES:
		return "invalid incident witnesses"
	for witness in witnesses:
		if not witness is Dictionary or not witness.get("id") is String or str(witness.id).is_empty() or str(witness.id).length() > 64 \
				or not str(witness.get("kind", "")) in PEOPLE_KINDS or not _number(witness.get("minutes")) \
				or not _number(witness.get("distance")) or not _point(witness.get("at")) or not str(witness.get("via", "")) in ["sight", "photo", "case", "victim"]:
			return "invalid incident witness"
	var evidence = rec.get("evidence")
	if not evidence is Array or evidence.size() > MAX_EVIDENCE:
		return "invalid incident evidence"
	for item in evidence:
		if not item is Dictionary or not str(item.get("kind", "")) in ["photo", "statement", "object"] or not item.get("by") is String \
				or not item.get("subject_id") is String or not _number(item.get("minutes")) or not _point(item.get("at")) \
				or not item.get("verified") is bool or not item.get("ref") is String:
			return "invalid incident evidence item"
	var report = rec.get("report")
	if not report is Dictionary:
		return "invalid incident report"
	if not (report as Dictionary).is_empty():
		if not report.get("by") is String or not report.get("channel") is String or not _number(report.get("minutes")) \
				or not report.get("police_incident_id") is String or not report.get("status") is String \
				or not report.get("corroborating") is Array or report.corroborating.size() > MAX_CORROBORATING:
			return "invalid incident report fields"
	var resolution = rec.get("resolution")
	if not resolution is Dictionary:
		return "invalid incident resolution"
	if not (resolution as Dictionary).is_empty() and (not str(resolution.get("outcome", "")) in OUTCOMES or not _number(resolution.get("minutes"))):
		return "invalid incident resolution fields"
	return ""

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _point(value) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for part in value:
		if not _number(part) or absf(float(part)) > 100000.0:
			return false
	return true

static func _array(point: Vector3) -> Array:
	return [snappedf(point.x, 0.001), snappedf(point.y, 0.001), snappedf(point.z, 0.001)]

static func _vec(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

# --------------------------------------------------------------- lookups

func _person_position(id: String) -> Vector3:
	var body: Node3D = performer_actor(id)
	if is_instance_valid(body):
		return body.global_position
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd == null or index < 0 or index >= crowd.residents.size() or crowd.is_dead(index):
			return Vector3.INF
		return crowd.resident_position(index)
	var actor = actors.named_actor(id)
	return actor.global_position if is_instance_valid(actor) and actor.get("dead") != true else Vector3.INF

func _person_yaw(id: String) -> float:
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd != null and index >= 0 and index < crowd.residents.size():
			return float(crowd.residents[index].yaw)
		return 0.0
	var actor = actors.named_actor(id)
	return float(actor.get("yaw")) if is_instance_valid(actor) else 0.0

func _officer_body(id: String) -> Node3D:
	if id.is_empty():
		return null
	var actor = actors.named_actor(id)
	return actor if actor is Node3D else null

func _street(at: Vector3) -> String:
	if level != null and level.has_method("_nearest_street"):
		return str(level.call("_nearest_street", at)).left(64)
	return ""

func _player_distance(at: Vector3) -> float:
	var player = level.get("player") if level != null else null
	return Tactics.flat((player as Node3D).global_position, at) if player is Node3D else 0.0

func _minutes() -> float:
	var clock = level.get("world_time") if level != null else null
	if clock != null and clock.get("total_minutes") != null:
		return float(clock.total_minutes)
	return 540.0 + _clock * 0.5

func _police():
	return level.get("police_assistance") if level != null else null

func _combat():
	return level.get("combat") if level != null else null

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

func _space() -> PhysicsDirectSpaceState3D:
	if is_inside_tree():
		var world := get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func _world_paused() -> bool:
	if level == null or level.get("paused") == true:
		return true
	var inspector = level.get("inspector")
	if inspector != null and inspector.get("active") == true:
		return true
	return is_inside_tree() and get_tree().paused

func _exit_tree() -> void:
	var police = _police()
	if police != null and police.get("incident_handler") == self:
		police.set("incident_handler", null)
	var player = level.get("player") if level != null else null
	var phone = player.get("phone") if is_instance_valid(player) else null
	if _photo_provider_registered and is_instance_valid(phone) and phone.has_method("unregister_photo_subject_provider"):
		phone.unregister_photo_subject_provider(_photo_subjects)
	_photo_provider_registered = false
