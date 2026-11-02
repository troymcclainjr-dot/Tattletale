extends Node3D
## Police response clarity and reliability (.work/five-priorities-20261101/
## police-contract.md). Real police assistance, real incident service and real
## patrol bodies walking on real physics in a small arena; combat is a bounded
## fixture because no fight is under test. Checks: one structured status per
## dispatch transition and evidence-based "en route"; a queued call dispatched
## later; a route blocked mid-way (never the same officer again, bounded retries,
## one notice); an officer who disappears mid-response (honest wording, handed
## back to normal life); duplicates; a neighbor's report the player corroborates
## from the phone (one dispatch, later steps heard once each, warning-only
## handling); a checkpoint reload mid-response (never shown as "on the way"); an
## incident settled while officers are on the way; a suspect who died before
## police arrived (no credit to police, no securing from afar); securing that
## loses its only officer (never closed as secured with nobody there; starts
## over when a replacement is at the scene) while a completed warning still
## settles its call; refusals and bounded cards; the player's oldest report
## still answered behind four newer closed ones (listed first; a neighbor's
## own report never shown); and the real phone page (cards, button, notice
## dedupe, HUD).
const Assistance := preload("res://scripts/city/city_police_assistance.gd")
const Incidents := preload("res://scripts/city/city_incidents.gd")
const Status := preload("res://scripts/city/city_police_status.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Explorer := preload("res://scripts/city/city_player.gd")
const Phone := preload("res://scripts/city/city_player_phone.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const WorldTime := preload("res://scripts/city/city_world_time.gd")
## Nothing on a status card may predict an arrival or show fake progress.
const FORBIDDEN_PROGRESS := ["%", "ETA", "minutes away", "seconds", "progress"]

class People extends Node3D:
	var actors: Dictionary = {}
	var crowd: Node3D

## Bounded combat stand-in: nobody fights in these scenarios.
class CombatFixture extends Node3D:
	var dead: Dictionary = {}
	func fighter_snapshot() -> Array:
		return []
	func is_actor_dead(id: String) -> bool:
		return dead.has(id)
	func actor_mode(actor) -> String:
		if not is_instance_valid(actor):
			return "gone"
		if actor.dead:
			return "dead"
		return "unknown" if actor.combat_override else ""
	func disengage_actor(actor) -> void:
		actor.combat_override = false

class PhoneProbe extends Node3D:
	var messages: Array[String] = []
	func set_report_status(message: String) -> void:
		messages.append(message)

class PlayerProbe extends CharacterBody3D:
	var phone: Node3D

class Arena extends Node3D:
	var player: Node3D
	var npcs: Node3D
	var residents: Node3D
	var combat: Node3D
	var law: Node
	var inspector: Node
	var police_assistance: Node
	var incidents: Node
	var paused := false

class PoliceStub extends Node:
	var revision := 1
	var generation := 0
	var view: Dictionary = {}
	func dispatch_view() -> Dictionary:
		return view.duplicate(true)

class IncidentsStub extends Node:
	var revision := 1
	var records: Array = []
	var preview: Dictionary = {"kind": "area_check"}
	func reports_for(_person := "player", limit := 4) -> Array:
		return records.slice(0, limit)
	func phone_report_preview(_at: Vector3) -> Dictionary:
		return preview.duplicate(true)

class PhoneLevel extends Node3D:
	var player: CharacterBody3D
	var combat: Node3D
	var ready_to_play := true
	var paused := false
	var offscreen_validation := true
	var inspector: Node
	var world_time: Node
	var missions: Node
	var bicycle: Node
	var npcs: Node
	var police_assistance: Node
	var incidents: Node
	var _ui: CanvasLayer
	var hud_notices: Array[String] = []
	func save_progress() -> String:
		return "Progress saved."
	func _nearest_street(_at: Vector3) -> String:
		return "Fixture Street"
	func show_notice(message: String) -> void:
		hud_notices.append(message)

var failures := 0
var arena: Arena
var police: Node3D
var incidents: Node3D
var combat: CombatFixture
var phone: PhoneProbe
var officer: CharacterBody3D
## A second patrol, out of the world except in the replacement scenario.
var second: CharacterBody3D
var events: Array[Dictionary] = []
var relayed: Array[Dictionary] = []
var max_step := 0.0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[police_status] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	_pure_cards()
	await _build_arena()
	await _transitions()
	await _queued_then_dispatched()
	await _blocked_route()
	await _replacement_after_block()
	await _missing_officer()
	await _duplicates()
	await _npc_first_then_player()
	await _reload()
	await _settled_while_en_route()
	await _died_before_arrival()
	await _securing_needs_an_officer()
	await _warning_stands_without_officer()
	await _suspect_gone()
	await _refusals_and_bounds()
	await _oldest_live_report()
	await _phone_page()
	print("[police_status] transitions=%d replacements=%d route_failures=%d officers_lost=%d" % [int(police.counters.transitions),
		int(police.counters.replacements), int(police.counters.route_failures), int(police.counters.officers_lost)])
	arena.queue_free()
	await get_tree().process_frame
	print("POLICE_STATUS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

# --------------------------------------------------------------- arena helpers

func _build_arena() -> void:
	arena = Arena.new()
	add_child(arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(240.0, 1.0, 240.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	arena.add_child(floor_body)
	var caller := PlayerProbe.new()
	arena.add_child(caller)
	caller.global_position = Vector3(0.0, 0.012, 0.0)
	phone = PhoneProbe.new()
	caller.add_child(phone)
	caller.phone = phone
	arena.player = caller
	arena.npcs = People.new()
	arena.add_child(arena.npcs)
	arena.residents = People.new()
	arena.add_child(arena.residents)
	combat = CombatFixture.new()
	arena.add_child(combat)
	arena.combat = combat
	officer = person("patrol_officer_0", "cop_dan", Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	second = person("patrol_officer_1", "cop_steve", Vector3(30.0, 0.012, 12.0), -PI * 0.5)
	second.set_enabled(false)
	police = Assistance.new()
	arena.add_child(police)
	arena.police_assistance = police
	police.setup(arena)
	police.search_seconds = 3.0
	police.secure_seconds = 1.0
	police.report_status_changed.connect(func(status: Dictionary): events.append(status.duplicate(true)))
	incidents = Incidents.new()
	arena.add_child(incidents)
	arena.incidents = incidents
	incidents.setup(arena)
	incidents.set_spawning_enabled(false)
	# Exactly what pen_lucy_level._on_incident_report_status does with statuses.
	incidents.report_status_changed.connect(func(status: Dictionary):
		relayed.append(status.duplicate(true))
		if bool(status.get("phone", false)):
			phone.set_report_status(str(status.get("text", "Report updated."))))
	await get_tree().physics_frame
	police.tactics.space = arena.get_world_3d().direct_space_state
	check(bool(police.available) and police.incident_handler == incidents, "police assistance has a real patrol and the incident relay")

func person(id: String, cast: String, at: Vector3, yaw := 0.0) -> CharacterBody3D:
	var actor := Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, cast, id)
	arena.npcs.actors[id] = actor
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	return actor

## Fixture placement between scenarios only, never of a body a call is using.
func place_officer(at: Vector3, yaw: float) -> void:
	officer.global_position = at
	officer.yaw = yaw
	officer.puppet.g.rotation.y = yaw
	max_step = 0.0

func box(at: Vector3, size_: Vector3, layer := 2) -> StaticBody3D:
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

func tick_once() -> void:
	var before := officer.global_position
	police.tick(1.0 / 60.0)
	incidents.tick(1.0 / 60.0)
	if officer.enabled:
		max_step = maxf(max_step, Vector2(officer.global_position.x - before.x, officer.global_position.z - before.z).length())
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

func calm() -> void:
	police.reset_state()
	incidents.reset_state()
	await step(0.3)
	events.clear()
	relayed.clear()
	phone.messages.clear()
	max_step = 0.0

func stage_of(id: String) -> String:
	return str(police.call_status(id).get("stage", ""))

## The structured police statuses of one call: "stage" or "stage/handling".
func stages_for(id: String) -> Array:
	var names: Array = []
	for event in events:
		if str(event.get("police_incident_id", "")) == id:
			var handling := str(event.get("handling", ""))
			names.append(str(event.get("stage", "")) + ("/" + handling if not handling.is_empty() else ""))
	return names

func timeline_stages(id: String) -> Array:
	var names: Array = []
	for entry in police.call_status(id).get("timeline", []):
		names.append(str(entry.get("stage", "")))
	return names

func card_for(cards: Array, key: String) -> Dictionary:
	for card in cards:
		if str(card.get("key", "")) == key:
			return card
	return {}

## An external incident a neighbor and the player both witnessed (trusted
## observations, as a case objective would record them).
func witnessed(offender_id: String, at: Vector3) -> String:
	var opened: Dictionary = incidents.open_incident({"template": "jaywalking", "at": at, "source": "external:police_status",
		"offender_id": offender_id})
	var id := str(opened.get("incident_id", ""))
	incidents.note_observation(id, "neighbor_w", {"at": at + Vector3(0.0, 0.0, 6.0)})
	incidents.note_observation(id, "player", {"at": arena.player.global_position})
	return id

func progress_free(cards: Array) -> bool:
	for card in cards:
		var texts: Array = [card.label, card.text, card.next, card.incident, card.responders, card.where]
		for entry in card.timeline:
			texts.append(entry.label)
		for text in texts:
			for forbidden in FORBIDDEN_PROGRESS:
				if str(text).contains(forbidden):
					return false
	return true

# --------------------------------------------------------------- pure status vocabulary and cards

func _pure_cards() -> void:
	var labelled := true
	for stage in Status.STAGES:
		labelled = labelled and not Status.label(stage).is_empty() and not Status.next_action(stage).is_empty()
	check(labelled, "every dispatch stage has a label and a next step")
	check(Status.coarse_status("queued") == "report_received" and Status.coarse_status("en_route") == "responding"
		and Status.coarse_status("handling") == "on_scene" and Status.coarse_status("failed", "unavailable") == "unavailable"
		and Status.coarse_status("failed", "timeout") == "resolved" and Status.coarse_status("cancelled", "interrupted") == "resolved",
		"coarse statuses keep their existing meaning for current consumers")
	var own_call := {"id": "incident_7", "ref": "", "phone": true, "stage": "en_route", "handling": "", "outcome": "",
		"message": "Dispatch got your call. Sending an officer on foot (about 40 m away).", "street": "Maple Avenue", "threat": "none",
		"responders": {"foot": 1, "cars": 0}, "suspects": [], "opened_minutes": 600.0, "updated_minutes": 601.0,
		"timeline": [{"stage": "received", "minutes": 600.0}, {"stage": "dispatched", "minutes": 600.0}, {"stage": "en_route", "minutes": 601.0}]}
	var linked_call := {"id": "incident_8", "ref": "inc_000004", "phone": false, "stage": "handling", "handling": "warning", "outcome": "",
		"message": "The officer issued a warning.", "street": "Old York Road", "threat": "infraction", "responders": {"foot": 1, "cars": 0},
		"suspects": [{"id": "crowd_4", "state": "cited"}], "opened_minutes": 590.0, "updated_minutes": 602.0, "timeline": []}
	var ambient := {"id": "incident_9", "ref": "", "phone": false, "stage": "en_route", "handling": "", "outcome": "", "message": "",
		"street": "", "threat": "violent", "responders": {"foot": 1, "cars": 0}, "suspects": [], "opened_minutes": 603.0, "updated_minutes": 603.0}
	var corroborated := {"id": "inc_000004", "title": "Jaywalking", "street": "Old York Road", "state": "responding", "source": "world",
		"report": {"by": "neighbor_w", "minutes": 590.0, "corroborating": ["player"], "status": "on_scene"}, "resolution": {}, "updated_minutes": 602.0}
	var restored := {"id": "inc_000003", "title": "Lost satchel", "street": "", "state": "responding", "source": "world",
		"report": {"by": "player", "minutes": 560.0, "corroborating": []}, "resolution": {}, "updated_minutes": 561.0}
	var closed := {"id": "inc_000002", "title": "Bending the mail", "street": "41st Street", "state": "resolved",
		"source": "case:parcel_report", "case_id": "parcel_report", "report": {"by": "player", "minutes": 500.0},
		"resolution": {"outcome": "warned", "minutes": 520.0, "text": "The officer stopped the person and issued a warning."}}
	var view := {"live": [own_call, linked_call, ambient], "history": [],
		"refusals": [{"id": "refusal_1", "text": "All officers are already on calls. Try again shortly.", "street": "", "minutes": 530.0}]}
	var cards: Array = Status.cards(view, [corroborated, restored, closed])
	check(cards.size() == Status.MAX_CARDS and bool(cards[0].live) and bool(cards[1].live) and not bool(cards[2].live),
		"cards are bounded to %d and live calls come first" % Status.MAX_CARDS)
	var linked := card_for(cards, "incident:inc_000004")
	check(not linked.is_empty() and str(linked.stage) == "handling" and str(linked.label) == "Warning issued" and card_for(cards, "call:incident_8").is_empty(),
		"a linked call and its record are one card showing the live dispatch stage")
	check(str(linked.incident) == "A neighbor reported it at 09:50; you confirmed it. Person involved: warned by an officer",
		"incident state (who reported, what officers know) is shown apart from dispatch: %s" % str(linked.incident))
	check(card_for(cards, "call:incident_9").is_empty(), "a neighbor's own report is never shown as the player's call")
	var own := card_for(cards, "call:incident_7")
	check(str(own.label) == "Officer on the way" and str(own.responders) == "1 officer on foot" and str(own.where) == "Near Maple Avenue"
		and str(own.time) == "10:00", "the player's call shows its stage, real responders, real street and game time")
	var wide: Array = Status.cards(view, [corroborated, restored, closed], 8)
	var reload := card_for(wide, "incident:inc_000003")
	check(str(reload.stage) == "cancelled" and not bool(reload.live) and str(reload.text) == Status.NOT_LIVE_TEXT and str(reload.where).is_empty(),
		"a restored report with no live call is never shown as answered, and no street is invented")
	var done := card_for(wide, "incident:inc_000002")
	check(str(done.label) == "Resolved: warning issued" and str(done.next) == "Check Cases for what happens next." and str(done.timeline[-1].time) == "08:40",
		"a closed case report reads from its durable resolution")
	var refusal := card_for(wide, "refusal:refusal_1")
	check(str(refusal.label) == "Call not taken" and str(refusal.next).contains("Try again shortly"), "a refused call reads as not taken, never as on the way")
	check(progress_free(wide), "no card text predicts an arrival or shows a progress figure")
	var area := Status.report_action({"kind": "area_check"})
	var file := Status.report_action({"kind": "incident", "title": "Jaywalking", "street": "Old York Road", "already_reported": false})
	var confirm := Status.report_action({"kind": "incident", "title": "Jaywalking", "already_reported": true})
	check(str(area.button) == "Ask officers to check here" and str(file.button) == "Report what you saw: Jaywalking"
		and str(file.hint).contains("near Old York Road") and str(confirm.button) == "Confirm the report: Jaywalking",
		"the report button names exactly what pressing it does")

# --------------------------------------------------------------- dispatch transitions

func _transitions() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var reply: Dictionary = police.request_help(arena.player.global_position)
	var id := str(reply.incident_id)
	check(bool(reply.ok) and int(reply.dispatched) == 1 and str(reply.message).contains("on foot"),
		"a quiet call is accepted and one real patrol is dispatched: %s" % str(reply.message))
	check(stages_for(id) == ["received", "dispatched"], "intake announces received then dispatched, once each: %s" % str(stages_for(id)))
	check(phone.messages.is_empty(), "the intake text belongs to the caller's reply, not to a second phone notice")
	var live: Dictionary = police.call_status(id)
	check(str(live.stage) == "dispatched" and int(live.responders.foot) == 1 and str(live.street).is_empty(),
		"the live call is 'dispatched' with one officer on foot and no invented street")
	var moving: bool = await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	check(moving and stages_for(id).size() == 2 and phone.messages.is_empty(),
		"'en route' follows real movement and is card-only: no extra status or notice")
	var done: bool = await advance_until(func(): return stage_of(id) == "resolved", 40.0)
	check(done and stages_for(id) == ["received", "dispatched", "on_scene", "resolved"],
		"exactly one structured status per announced transition: %s" % str(stages_for(id)))
	check(phone.messages == ["An officer has arrived and is checking the area.", "Officers checked the area. Nobody there needed help."],
		"the caller's phone hears the arrival and the outcome once each: %s" % str(phone.messages))
	check(timeline_stages(id) == ["received", "dispatched", "en_route", "on_scene", "resolved"],
		"the bounded timeline keeps every stage in order: %s" % str(timeline_stages(id)))
	check(max_step <= Assistance.JOG_SPEED / 60.0 + 0.01, "the officer only ever walked (largest frame step %.3f m)" % max_step)
	await calm()

func _queued_then_dispatched() -> void:
	# No surveyed street graph in this arena: beyond 36 m a free officer has no route.
	place_officer(Vector3(70.0, 0.012, 0.0), -PI * 0.5)
	var reply: Dictionary = police.request_help(arena.player.global_position)
	var id := str(reply.incident_id)
	check(bool(reply.ok) and int(reply.dispatched) == 0 and stage_of(id) == "queued" and stages_for(id) == ["queued"],
		"with no officer able to come yet the call is accepted as queued and announced once")
	check(str(reply.message).contains("No officer can get there yet; dispatch will keep trying"),
		"a free officer who cannot get there is not described as nobody free: %s" % str(reply.message))
	var waiting := card_for(Status.cards(police.dispatch_view(), []), "call:" + id)
	check(str(waiting.get("label", "")) == "Waiting for a response", "the queued card's label does not claim why no officer has come yet")
	place_officer(Vector3(12.0, 0.012, 0.0), -PI * 0.5) # Fixture: an officer this call is not using gets within reach.
	var sent: bool = await advance_until(func(): return stage_of(id) in ["dispatched", "en_route"], 6.0)
	check(sent and phone.messages.size() == 1 and phone.messages[0].begins_with("Dispatch sent an officer on foot (about "),
		"a later real dispatch is announced once and honestly: %s" % str(phone.messages))
	check(stages_for(id) == ["queued", "dispatched"], "queued, then dispatched only when a unit was really sent: %s" % str(stages_for(id)))
	await calm()

func _blocked_route() -> void:
	var call_at := Vector3(0.0, 0.012, 12.0)
	arena.player.global_position = call_at
	place_officer(Vector3(0.0, 0.012, -12.0), 0.0)
	var dispatched_before := int(police.counters.foot_dispatches)
	var reply: Dictionary = police.request_help(call_at)
	var id := str(reply.incident_id)
	check(bool(reply.ok) and int(reply.dispatched) == 1, "the only nearby patrol is sent along a clear street")
	var wall := box(Vector3(0.0, 1.5, 0.0), Vector3(40.0, 3.0, 0.4)) # Something now blocks the whole street.
	var stopped: bool = await advance_until(func(): return stage_of(id) in ["queued", "failed"], 30.0)
	check(stopped and phone.messages == ["An officer could not get through to the scene. Dispatch is looking for another officer."],
		"a blocked officer stops counting at once and the caller is told the truth: %s" % str(phone.messages))
	var o: Dictionary = police._officers.get(officer.actor_id, {})
	check(not o.is_empty() and str(o.state) == "return" and not is_finite(float(police._incident_by_id(id).arrived)),
		"the officer walks back; a failed route is not an arrival")
	var closed: bool = await advance_until(func(): return stage_of(id) == "failed", 45.0)
	var summary: Dictionary = police.call_status(id)
	check(closed and str(summary.outcome) == "unavailable" and int(police.counters.foot_dispatches) == dispatched_before + 1,
		"the blocked officer is never sent again; bounded retries close the call (%d dispatch)" % (int(police.counters.foot_dispatches) - dispatched_before))
	check(phone.messages.size() == 2 and phone.messages[1] == "No officer could get through to the scene, so dispatch closed the call.",
		"one blocked-route notice and one honest closing notice: %s" % str(phone.messages))
	check(stages_for(id) == ["received", "dispatched", "queued", "failed"], "stage stream: %s" % str(stages_for(id)))
	check(max_step <= Assistance.JOG_SPEED / 60.0 + 0.01, "nobody passed through the wall or was teleported (%.3f m)" % max_step)
	wall.queue_free()
	arena.player.global_position = Vector3(0.0, 0.012, 0.0)
	await calm()

func _replacement_after_block() -> void:
	var call_at := Vector3(0.0, 0.012, 12.0)
	arena.player.global_position = call_at
	place_officer(Vector3(0.0, 0.012, -12.0), 0.0)
	second.set_enabled(true) # Fixture: a second free patrol on a street the wall will not block.
	second.global_position = Vector3(30.0, 0.012, 12.0)
	second.yaw = -PI * 0.5
	second.puppet.g.rotation.y = -PI * 0.5
	var dispatched_before := int(police.counters.foot_dispatches)
	var replacements_before := int(police.counters.replacements)
	var reply: Dictionary = police.request_help(call_at)
	var id := str(reply.incident_id)
	check(int(reply.dispatched) == 1 and police._officers.has(officer.actor_id) and not police._officers.has(second.actor_id),
		"only the nearer patrol is sent at first")
	var wall := box(Vector3(0.0, 1.5, 0.0), Vector3(40.0, 3.0, 0.4)) # Blocks the first officer's street only.
	var replaced: bool = await advance_until(func(): return police._officers.has(second.actor_id), 30.0)
	check(replaced and phone.messages == ["An officer could not get through to the scene. Dispatch is looking for another officer.",
		"Dispatch sent another officer on foot (about 30 m away)."] and int(police.counters.replacements) == replacements_before + 1,
		"a replacement is announced only once one is actually sent: %s" % str(phone.messages))
	var done: bool = await advance_until(func(): return stage_of(id) == "resolved", 40.0)
	check(done and stages_for(id) == ["received", "dispatched", "queued", "dispatched", "on_scene", "resolved"]
		and int(police.counters.foot_dispatches) == dispatched_before + 2,
		"the replacement reaches the scene and the blocked officer is never re-sent: %s" % str(stages_for(id)))
	check(phone.messages.size() == 4 and phone.messages[2] == "An officer has arrived and is checking the area.",
		"arrival and outcome follow once each: %s" % str(phone.messages))
	wall.queue_free()
	await calm()
	second.set_enabled(false)
	arena.player.global_position = Vector3(0.0, 0.012, 0.0)

func _missing_officer() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var reply: Dictionary = police.request_help(arena.player.global_position)
	var id := str(reply.incident_id)
	await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	officer.set_enabled(false) # A schedule or mission takes this body out of the world mid-response.
	var lost: bool = await advance_until(func(): return stage_of(id) == "queued", 2.0)
	check(lost and phone.messages == ["An officer is no longer available for this call. Dispatch is looking for another officer."],
		"losing the only officer is reported honestly, without promising help: %s" % str(phone.messages))
	check(not officer.combat_override and not officer.has_meta("police_assist") and not officer.has_meta("law_responder"),
		"a disabled officer is handed back to normal life, not left frozen under the service's hold")
	var closed: bool = await advance_until(func(): return stage_of(id) == "failed", 25.0)
	check(closed and phone.messages.size() == 2 and phone.messages[1] == "No other officer could take over, so dispatch closed the call.",
		"with no replacement the call closes after bounded retries: %s" % str(phone.messages))
	officer.set_enabled(true)
	check(police._free_officer(officer), "re-enabled, the same patrol can answer the next call")
	await calm()

func _duplicates() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var event := {"incident_ref": "fixture_duplicate", "policy": "warn", "kind": "infraction", "suspects": [],
		"at": Vector3(2.0, 0.012, 2.0), "reporter_id": "neighbor_a", "phone": false}
	var first: Dictionary = police.report_incident(event)
	var dispatches := int(police.counters.foot_dispatches)
	var streamed := events.size()
	var again: Dictionary = police.report_incident(event)
	check(bool(first.ok) and bool(again.ok) and bool(again.duplicate) and str(again.incident_id) == str(first.incident_id),
		"a second report of the same reference is the same call")
	check(int(police.counters.foot_dispatches) == dispatches and events.size() == streamed,
		"a duplicate neither dispatches nor re-announces any stage")
	var call: Dictionary = police.request_help(Vector3(4.0, 0.012, 1.0))
	check(bool(call.merged) and str(call.incident_id) == str(first.incident_id) and int(police.counters.foot_dispatches) == dispatches
		and events.size() == streamed, "a phone call at the same spot joins the open call: no second dispatch, no repeated status")
	await calm()

# --------------------------------------------------------------- the incident relay

func _npc_first_then_player() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var offender := person("offender_npc", "granny", Vector3(4.0, 0.012, 6.0), PI)
	var id := witnessed("offender_npc", offender.global_position)
	var preview: Dictionary = incidents.phone_report_preview(arena.player.global_position)
	check(str(preview.kind) == "incident" and str(preview.incident_id) == id and not bool(preview.already_reported),
		"the phone names the witnessed incident before anything is filed")
	var rounds_before := int(police.counters.rounds)
	var npc: Dictionary = incidents.report_incident(id, "neighbor_w", {"channel": "witness_call", "phone": false})
	var dispatches := int(police.counters.foot_dispatches)
	var police_id := str(incidents.get_incident(id).report.police_incident_id)
	check(bool(npc.ok) and not police_id.is_empty() and phone.messages.is_empty(), "the neighbor's report dispatches without notifying the player's phone")
	preview = incidents.phone_report_preview(arena.player.global_position)
	check(bool(preview.already_reported) and not bool(preview.yours) and str(Status.report_action(preview).button).begins_with("Confirm the report"),
		"the phone offers to confirm the neighbor's report, not to file it again")
	var mine: Dictionary = incidents.report_from_phone(arena.player.global_position)
	check(bool(mine.ok) and bool(mine.duplicate) and str(mine.message).begins_with("Already reported.") and int(police.counters.foot_dispatches) == dispatches,
		"the player's corroboration never dispatches twice: %s" % str(mine.message))
	var report: Dictionary = incidents.get_incident(id).report
	check(str(report.by) == "neighbor_w" and report.corroborating == ["player"] and str(report.police_incident_id) == police_id,
		"the neighbor stays the reporter and keeps the original dispatch; the player is added as corroboration")
	preview = incidents.phone_report_preview(arena.player.global_position)
	check(bool(preview.yours) and str(Status.report_action(preview).button) == "Check on your report: Jaywalking",
		"after confirming, the button only checks on the report")
	var cards: Array = Status.cards(police.dispatch_view(), incidents.reports_for("player"))
	var card := card_for(cards, "incident:" + id)
	check(not card.is_empty() and bool(card.live) and str(card.incident).contains("you confirmed it") and card_for(cards, "call:" + police_id).is_empty(),
		"one live card for the confirmed report, merged with its police call")
	var resolved: bool = await advance_until(func(): return str(incidents.get_incident(id).state) == "resolved", 45.0)
	check(resolved and phone.messages == ["An officer has arrived and is checking the area.", "An officer stopped the person to talk.",
		"The officer issued a warning.", "The officer stopped the person and issued a warning."],
		"after confirming, the player's phone hears each later step exactly once: %s" % str(phone.messages))
	var handled: Array = []
	for event in events:
		if str(event.get("police_incident_id", "")) == police_id and str(event.get("stage", "")) == "handling":
			handled.append(str(event.handling))
	check(handled == ["contact", "warning"] and int(police.counters.rounds) == rounds_before and not police.custody.has("offender_npc"),
		"an infraction is a stop and a warning only: no commands, custody or force (%s)" % str(handled))
	card = card_for(Status.cards(police.dispatch_view(), incidents.reports_for("player")), "incident:" + id)
	check(str(card.stage) == "resolved" and str(card.label) == "Resolved: warning issued" and not bool(card.live),
		"the card closes from the record's own outcome")
	offender.set_enabled(false)
	await calm()

func _reload() -> void:
	# A call the player is waiting on still refuses a load, like the save guard.
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	police.request_help(arena.player.global_position)
	check(police.blocks_checkpoint() and not bool(police.restore_state({"version": 1, "custody_ids": []}).get("ok", true)),
		"a phone call in progress still refuses a checkpoint load")
	await calm()
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var offender := person("offender_reload", "granny", Vector3(-4.0, 0.012, 8.0), PI)
	var id := witnessed("offender_reload", offender.global_position)
	incidents.report_incident(id, "neighbor_w", {"channel": "witness_call", "phone": false})
	incidents.report_incident(id, "player", {"channel": "phone", "phone": true})
	await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	var saved = JSON.parse_string(JSON.stringify(incidents.snapshot_state()))
	check(saved is Dictionary and str(incidents.get_incident(id).state) == "responding" and not police.blocks_checkpoint(),
		"a neighbor's report the player confirmed can be saved mid-response")
	var generation := int(police.generation)
	var custody: Dictionary = police.restore_state({"version": 1, "custody_ids": []})
	check(bool(custody.ok) and int(police.generation) == generation + 1 and (police.dispatch_view().history as Array).is_empty()
		and not police.has_open_ref(id), "loading stands the live response down and drops the abandoned session's calls")
	phone.messages.clear()
	check(bool(incidents.restore_state(saved).ok) and str(incidents.get_incident(id).state) == "responding", "the record restores exactly as saved")
	var card := card_for(Status.cards(police.dispatch_view(), incidents.reports_for("player")), "incident:" + id)
	check(not card.is_empty() and str(card.stage) == "cancelled" and not bool(card.live) and str(card.text) == Status.NOT_LIVE_TEXT,
		"before upkeep, the restored report is shown as no longer active, never as officers on the way")
	await step(0.6)
	var record: Dictionary = incidents.get_incident(id)
	check(str(record.state) == "resolved" and str(record.resolution.outcome) == "interrupted" and str(record.resolution.text).contains("result is unknown"),
		"upkeep closes it honestly: interrupted, result unknown")
	card = card_for(Status.cards(police.dispatch_view(), incidents.reports_for("player")), "incident:" + id)
	check(str(card.label) == "Response interrupted" and str(card.next).contains("call again") and phone.messages.is_empty(),
		"the rebuilt card offers a useful next step; no notice claims progress that was never restored")
	offender.set_enabled(false)
	await calm()

func _settled_while_en_route() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var offender := person("offender_settled", "granny", Vector3(-6.0, 0.012, -6.0), 0.0)
	var id := witnessed("offender_settled", offender.global_position)
	incidents.report_incident(id, "neighbor_w", {"channel": "witness_call", "phone": false})
	await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	var cancelled_before := int(police.counters.cancelled_refs)
	check(incidents.resolve_incident(id, "case_resolved", "Settled by the case."), "the case settles the incident while officers are on the way")
	var summary: Dictionary = police.call_status(id)
	check(not police.has_open_ref(id) and str(summary.stage) == "cancelled" and str(summary.outcome) == "cancelled"
		and int(police.counters.cancelled_refs) == cancelled_before + 1, "the police call stands down cleanly")
	check(str(incidents.get_incident(id).resolution.outcome) == "case_resolved", "the incident keeps the case's outcome")
	var o: Dictionary = police._officers.get(officer.actor_id, {})
	check(o.is_empty() or str(o.state) == "return", "the officer turns back instead of continuing to a settled scene")
	var statuses := relayed.size()
	await step(3.0)
	check(relayed.size() == statuses, "no late police step reaches the settled record")
	offender.set_enabled(false)
	await calm()

func _died_before_arrival() -> void:
	place_officer(Vector3(24.0, 0.012, 0.0), -PI * 0.5)
	var suspect := person("suspect_down", "ricky", Vector3(0.0, 0.012, 4.0), 0.0)
	var rounds_before := int(police.counters.rounds)
	var reply: Dictionary = police.report_incident({"incident_ref": "fixture_died", "policy": "detain", "kind": "violence",
		"suspects": ["suspect_down"], "at": suspect.global_position, "reporter_id": "neighbor_w", "phone": false})
	var id := str(reply.incident_id)
	check(bool(reply.ok) and int(reply.suspects) == 1, "a reported violent suspect is named on the call")
	await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	combat.dead["suspect_down"] = true
	suspect.mark_dead() # Fixture: died by another cause; police never fired.
	await step(1.0)
	var incident: Dictionary = police._incident_by_id(id)
	var o: Dictionary = police._officers.get(officer.actor_id, {})
	check(not is_finite(float(incident.arrived)) and not is_finite(float(incident.secure_until)) and not o.is_empty() and str(o.state) == "respond",
		"officers keep going to the scene; nobody 'secures' it from down the street")
	var closed: bool = await advance_until(func(): return stage_of(id) == "resolved", 30.0)
	var call: Dictionary = police.call_status(id)
	var timeline := timeline_stages(id)
	check(closed and str(call.outcome) == "suspect_killed" and not str(call.message).contains("Police stopped")
		and str(call.message).contains("police did not fire") and int(police.counters.rounds) == rounds_before,
		"the close never credits police with a death they did not cause: %s" % str(call.message))
	check(timeline.find("on_scene") >= 0 and timeline.find("on_scene") < timeline.find("resolved"), "the scene was reached before it was called secure")
	await calm()

func _securing_needs_an_officer() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var suspect := person("suspect_unattended", "ricky", Vector3(6.0, 0.012, -6.0), 0.0)
	var reply: Dictionary = police.report_incident({"incident_ref": "fixture_secure", "policy": "detain", "kind": "violence",
		"suspects": ["suspect_unattended"], "at": suspect.global_position, "reporter_id": "neighbor_w", "phone": false})
	var id := str(reply.incident_id)
	combat.dead["suspect_unattended"] = true
	suspect.mark_dead() # Fixture: died by another cause before officers got there.
	var securing: bool = await advance_until(func(): return is_finite(float(police._incident_by_id(id).get("secure_until", -INF))), 30.0)
	var o: Dictionary = police._officers.get(officer.actor_id, {})
	check(securing and not o.is_empty() and str(o.state) == "secure" and int(police._present(police._incident_by_id(id))) == 1,
		"the only officer at the scene starts securing it")
	officer.set_enabled(false) # Taken out of the world mid-securing.
	await step(float(police.secure_seconds) + 0.5) # Past the moment the first securing would have ended.
	var incident: Dictionary = police._incident_by_id(id)
	check(stage_of(id) == "queued" and str(incident.get("outcome", "?")).is_empty() and not is_finite(float(incident.get("secure_until", 0.0))),
		"with nobody left at the scene the securing stops; the call is not closed as secured (%s)" % str(police.call_status(id).get("message", "")))
	check(stages_for(id) == ["received", "dispatched", "on_scene", "queued"], "the call waits for another officer: %s" % str(stages_for(id)))
	var replacements_before := int(police.counters.replacements)
	second.set_enabled(true) # Fixture: a free patrol within reach of the scene.
	second.global_position = Vector3(30.0, 0.012, 12.0)
	second.yaw = -PI * 0.5
	second.puppet.g.rotation.y = -PI * 0.5
	var present_at_close: Array = []
	var probe := func(status: Dictionary):
		if str(status.get("police_incident_id", "")) == id and not Status.is_live(str(status.get("stage", ""))):
			present_at_close.append(int(police._present(police._incident_by_id(id))))
	police.report_status_changed.connect(probe)
	var closed: bool = await advance_until(func(): return stage_of(id) == "resolved", 40.0)
	police.report_status_changed.disconnect(probe)
	var call: Dictionary = police.call_status(id)
	check(closed and str(call.outcome) == "suspect_killed" and str(call.message) == "Officers secured the scene. The person involved died; police did not fire."
		and present_at_close == [1] and int(police.counters.replacements) == replacements_before + 1,
		"securing starts over once a replacement is at the scene; the call closes with an officer there (%s)" % str(present_at_close))
	check(stages_for(id) == ["received", "dispatched", "on_scene", "queued", "dispatched", "on_scene", "resolved"],
		"stage stream: %s" % str(stages_for(id)))
	await calm()
	second.set_enabled(false)
	officer.set_enabled(true)

func _warning_stands_without_officer() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var offender := person("offender_warned", "granny", Vector3(4.0, 0.012, 6.0), PI)
	var id := witnessed("offender_warned", offender.global_position)
	incidents.report_incident(id, "neighbor_w", {"channel": "witness_call", "phone": false})
	var warned: bool = await advance_until(func(): return str(police.call_status(id).get("handling", "")) == "warning", 45.0)
	officer.set_enabled(false) # Leaves right after issuing the warning.
	var closed: bool = await advance_until(func(): return str(incidents.get_incident(id).state) == "resolved", 10.0)
	var call: Dictionary = police.call_status(id)
	check(warned and closed and str(call.outcome) == "warned" and str(incidents.get_incident(id).resolution.outcome) == "warned",
		"a completed warning still settles the call after its officer is gone (%s)" % str(call.message))
	offender.set_enabled(false)
	await calm()
	officer.set_enabled(true)

func _suspect_gone() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var suspect := person("suspect_gone", "ricky", Vector3(-10.0, 0.012, 0.0), 0.0)
	var rounds_before := int(police.counters.rounds)
	var reply: Dictionary = police.report_incident({"incident_ref": "fixture_gone", "policy": "detain", "kind": "theft",
		"suspects": ["suspect_gone"], "at": suspect.global_position, "reporter_id": "neighbor_w", "phone": false})
	var id := str(reply.incident_id)
	check(str(reply.message).begins_with("Theft reported."), "a reported theft is described as theft, not violence: %s" % str(reply.message))
	await advance_until(func(): return stage_of(id) == "en_route", 4.0)
	arena.npcs.actors.erase("suspect_gone")
	suspect.queue_free() # The person leaves the block before officers get there.
	var closed: bool = await advance_until(func(): return stage_of(id) == "resolved", 30.0)
	var call: Dictionary = police.call_status(id)
	var timeline := timeline_stages(id)
	check(closed and str(call.outcome) == "suspect_left" and timeline.find("on_scene") >= 0 and timeline.find("on_scene") < timeline.find("resolved")
		and int(police.counters.rounds) == rounds_before, "a suspect who left is searched for at the scene, then closed honestly (%s)" % str(call.message))
	await calm()

func _refusals_and_bounds() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	for at in [Vector3(-60.0, 0.012, -60.0), Vector3(60.0, 0.012, -60.0), Vector3(-60.0, 0.012, 60.0)]:
		police.request_help(at)
	var refused: Dictionary = police.request_help(Vector3(60.0, 0.012, 60.0))
	var view: Dictionary = police.dispatch_view()
	check(not bool(refused.ok) and str(refused.message).contains("already on calls") and (view.refusals as Array).size() == 1
		and str(view.refusals[0].stage) == "unavailable", "a call over the limit is refused, and the refusal stays visible as not taken")
	var cards: Array = Status.cards(view, incidents.reports_for("player"))
	check(cards.size() == Status.MAX_CARDS and bool(cards[0].live) and bool(cards[1].live) and bool(cards[2].live)
		and not card_for(cards, "refusal:" + str(view.refusals[0].id)).is_empty(), "four bounded cards: three live calls first, then the refusal")
	check(progress_free(cards), "live cards carry no ETA or progress figure")
	await calm()

func _oldest_live_report() -> void:
	place_officer(Vector3(16.0, 0.012, 2.0), -PI * 0.5)
	var oldest := witnessed("offender_oldest", Vector3(-4.0, 0.012, 8.0))
	var filed := bool(incidents.report_incident(oldest, "player", {"channel": "phone", "phone": true}).ok)
	var opened: Dictionary = incidents.open_incident({"template": "jaywalking", "at": Vector3(-24.0, 0.012, -24.0),
		"source": "external:police_status", "offender_id": "offender_neighbors"})
	var neighbors := str(opened.get("incident_id", ""))
	incidents.note_observation(neighbors, "neighbor_w", {"at": Vector3(-24.0, 0.012, -18.0)})
	filed = filed and bool(incidents.report_incident(neighbors, "neighbor_w", {"channel": "witness_call", "phone": false}).ok)
	var newer: Array[String] = []
	for i in 4:
		var id := witnessed("offender_newer_%d" % i, Vector3(30.0, 0.012, -10.0 - 10.0 * i))
		var reported: Dictionary = incidents.report_incident(id, "player", {"channel": "phone", "phone": true})
		var settled: bool = incidents.resolve_incident(id, "case_resolved", "Settled by the case.")
		filed = filed and bool(reported.ok) and settled
		newer.append(id)
		await step(0.3) # The stood-down call leaves dispatch before the next report.
	var mine: Array = incidents.reports_for("player", Status.MAX_CARDS) # Exactly what the Police page asks for.
	var ids: Array = []
	for rec in mine:
		ids.append(str(rec.id))
	check(filed and police.has_open_ref(oldest) and police.has_open_ref(neighbors) and ids.size() == Status.MAX_CARDS + 1
		and ids[0] == oldest and ids.slice(1) == [newer[3], newer[2], newer[1], newer[0]],
		"the player's oldest report, still being answered, is listed ahead of their four newer closed ones: %s" % str(ids))
	check(not neighbors in ids, "a neighbor's own live report is never listed as the player's")
	var cards: Array = Status.cards(police.dispatch_view(), mine)
	var neighbor_call := str(incidents.get_incident(neighbors).report.police_incident_id)
	check(cards.size() == Status.MAX_CARDS and str(cards[0].key) == "incident:" + oldest and bool(cards[0].live)
		and not bool(cards[1].live) and not bool(cards[2].live) and not bool(cards[3].live),
		"the live report keeps the first card; the most recent closed ones follow")
	check(card_for(cards, "incident:" + neighbors).is_empty() and card_for(cards, "call:" + neighbor_call).is_empty(),
		"the neighbor's live call gets no card on the player's phone")
	await calm()

# --------------------------------------------------------------- the real phone page

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func report_button(handset: Node) -> Button:
	for child in handset._content.find_children("*", "Button", true, false):
		if child.has_meta("police_report_kind"):
			return child
	return null

func _phone_page() -> void:
	var level := PhoneLevel.new()
	add_child(level)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 1.0, 30.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	level.add_child(floor_body)
	level._ui = CanvasLayer.new()
	level.add_child(level._ui)
	level.player = Explorer.new()
	level.add_child(level.player)
	level.player.enabled = true
	level.player.position = Vector3(0.0, 0.05, 0.0)
	level.combat = Combat.new()
	level.add_child(level.combat)
	level.combat.setup(level)
	level.world_time = WorldTime.new()
	level.add_child(level.world_time)
	level.world_time.set_time(9 * 60 + 5, 1)
	var dispatch := PoliceStub.new()
	level.add_child(dispatch)
	level.police_assistance = dispatch
	var records := IncidentsStub.new()
	level.add_child(records)
	level.incidents = records
	var handset := Phone.new()
	level.add_child(handset)
	handset.setup(level, level.player)
	handset.storage_directory = "user://phone_gallery_test_police_%d" % Time.get_ticks_usec()
	await frames(3)
	check(handset.open(), "the real phone opens")
	handset.show_page("police")
	await frames(1)
	var button := report_button(handset)
	check((handset.get_status().police_cards as Array).is_empty() and button != null and button.text == "Ask officers to check here",
		"with nothing reported, the button says it asks officers to check this spot")
	var live_call := {"id": "incident_1", "ref": "inc_000001", "phone": false, "stage": "handling", "handling": "warning", "outcome": "",
		"message": "The officer issued a warning.", "street": "Fixture Street", "threat": "infraction", "responders": {"foot": 1, "cars": 0},
		"suspects": [{"id": "crowd_3", "state": "cited"}], "opened_minutes": 545.0, "updated_minutes": 547.0, "closing": false,
		"timeline": [{"stage": "received", "minutes": 545.0}, {"stage": "dispatched", "minutes": 545.0}, {"stage": "en_route", "minutes": 545.5},
			{"stage": "on_scene", "minutes": 546.0}, {"stage": "handling", "handling": "contact", "minutes": 546.5},
			{"stage": "handling", "handling": "warning", "minutes": 547.0}]}
	dispatch.view = {"generation": 0, "revision": 2, "live": [live_call], "history": [], "refusals": []}
	dispatch.revision = 2
	records.records = [{"id": "inc_000001", "title": "Jaywalking", "street": "Fixture Street", "state": "responding", "source": "world",
		"report": {"by": "player", "minutes": 545.0, "corroborating": [], "status": "on_scene"}, "resolution": {}, "updated_minutes": 547.0}]
	records.preview = {"kind": "incident", "incident_id": "inc_000001", "title": "Jaywalking", "street": "Fixture Street",
		"already_reported": true, "yours": true}
	records.revision = 2
	await frames(45) # The open Police page polls its sources twice a second.
	var cards: Array = handset.get_status().police_cards
	check(cards.size() == 1 and str(cards[0].stage) == "handling" and (cards[0].timeline as Array).size() == Status.CARD_TIMELINE,
		"the open Police page refreshes itself when dispatch changes; its timeline is bounded")
	button = report_button(handset)
	check(button != null and button.text == "Check on your report: Jaywalking", "the button never offers to file the same report twice")
	var shown := false
	var labels_clean := true
	for panel in handset._content.find_children("*", "PanelContainer", true, false):
		shown = shown or str(panel.get_meta("police_card", "")) == "incident:inc_000001"
	for label in handset._content.find_children("*", "Label", true, false):
		for forbidden in FORBIDDEN_PROGRESS:
			labels_clean = labels_clean and not str(label.text).contains(forbidden)
	check(shown and labels_clean, "the card is rendered on the page with no ETA or progress figure")
	var before := int(handset.get_status().notices)
	for i in 3:
		handset.set_report_status("An officer has arrived and is checking the area.")
	check(int(handset.get_status().notices) == before + 1, "one step delivered three times in a frame is announced once")
	handset.set_report_status("The officer issued a warning.")
	check(int(handset.get_status().notices) == before + 2, "a new step is announced")
	handset.close()
	level.hud_notices.clear()
	handset.set_report_status("The officer stopped the person and issued a warning.")
	handset.set_report_status("The officer stopped the person and issued a warning.")
	check(level.hud_notices == ["Dispatch: The officer stopped the person and issued a warning."],
		"while the phone is put away, a police step reaches the HUD once: %s" % str(level.hud_notices))
	handset.open()
	handset.set_report_status("Officers are dealing with the suspect now.")
	dispatch.generation = 1 # A checkpoint was loaded: this session's calls are gone.
	check(handset._current_report_status() == Phone.DEFAULT_REPORT_STATUS and handset.get_status().report_status == "Officers are dealing with the suspect now.",
		"after a load, the last notice from the abandoned session is not shown as current")
	handset.suspend()
	DirAccess.remove_absolute(handset.storage_directory)
	level.queue_free()
	await frames(1)
