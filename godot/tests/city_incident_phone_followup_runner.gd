extends Node
## Real incident report gate + actual level phone callbacks, bounded dispatch
## spy. No world boot, desktop interaction, fabricated photo or police physics.
const Incidents := preload("res://scripts/city/city_incidents.gd")

class LevelProbe:
	extends "res://scripts/city/pen_lucy_level.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _input(_event: InputEvent) -> void: pass
	func _unhandled_input(_event: InputEvent) -> void: pass
	func _notification(_what: int) -> void: pass
	func _exit_tree() -> void: pass

class PhoneProbe:
	extends Node3D
	var messages: Array[String] = []
	func set_report_status(message: String) -> void:
		messages.append(message)

class PlayerProbe:
	extends CharacterBody3D
	var phone: Node3D

class DispatchProbe:
	extends Node
	var incident_handler: Node
	var calls: Array[Dictionary] = []
	var fallback_calls := 0
	func report_incident(event: Dictionary) -> Dictionary:
		calls.append(event.duplicate(true))
		var id := "dispatch_%d" % calls.size()
		incident_handler.on_police_progress(str(event.incident_ref), "report_received", {"police_incident_id": id, "text": "Dispatch received"})
		return {"ok": true, "incident_id": id, "message": "Dispatch received"}
	func request_help(_at: Vector3) -> Dictionary:
		fallback_calls += 1
		return {"ok": false, "message": "Unexpected fallback"}
	func advance(ref: String, status: String, text: String) -> void:
		incident_handler.on_police_progress(ref, status, {"text": text, "outcome": "warned" if status == "resolved" else ""})

var failures := 0
var emitted: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[incident_phone_followup] %s %s" % ["PASS" if ok else "FAIL", label])

func _new_incident(service: Node, at: Vector3) -> String:
	var opened: Dictionary = service.open_incident({"template": "case", "source": "external:followup_fixture", "offender_id": "crowd_1", "at": at})
	check(bool(opened.get("ok", false)), "external incident opens through public API")
	return str(opened.get("incident_id", ""))

func _run() -> void:
	var level := LevelProbe.new()
	add_child(level)
	level.player = PlayerProbe.new()
	level.add_child(level.player)
	var phone := PhoneProbe.new()
	level.player.add_child(phone)
	level.player.phone = phone
	var dispatch := DispatchProbe.new()
	level.add_child(dispatch)
	level.police_assistance = dispatch
	var service := Incidents.new()
	level.add_child(service)
	level.incidents = service
	service.setup(level)
	service.set_spawning_enabled(false)
	service.report_status_changed.connect(level._on_incident_report_status)
	service.report_status_changed.connect(func(status: Dictionary): emitted.append(status.duplicate(true)))
	var at := Vector3(4, 0, 2)
	var id := _new_incident(service, at)
	check(service.note_observation(id, "lookout", {"at": at}), "NPC trusted observation registered")
	var first: Dictionary = service.report_incident(id, "lookout", {"channel": "witness_call", "phone": false})
	check(bool(first.ok) and dispatch.calls.size() == 1 and phone.messages.is_empty(), "NPC first report dispatches once without a player notification")
	var original: Dictionary = service.get_incident(id).report.duplicate(true)
	var rejected: Dictionary = service.report_incident(id, "player", {"channel": "phone", "phone": true})
	dispatch.advance(id, "report_received", "NPC receipt only")
	check(not bool(rejected.ok) and rejected.reason == "not_witnessed" and phone.messages.is_empty(), "unwitnessed caller is refused and never subscribed")
	check(service.note_observation(id, "player", {"at": at}), "player observation registered through public witness API")
	level._request_police_help(at)
	var corroborated: Dictionary = service.get_incident(id).report
	check(phone.messages.size() == 1 and phone.messages.back().begins_with("Already reported."), "actual root phone callback shows corroboration response")
	check(corroborated.by == original.by and corroborated.channel == original.channel and corroborated.phone == original.phone
		and corroborated.police_incident_id == original.police_incident_id and corroborated.minutes == original.minutes,
		"corroboration preserves original reporter, channel, phone flag, dispatch ID and report time")
	level._request_police_help(at)
	check(dispatch.calls.size() == 1 and dispatch.fallback_calls == 0 and service.get_incident(id).report.corroborating == ["player"],
		"repeat player corroboration neither redispatches nor duplicates identity")
	phone.messages.clear()
	emitted.clear()
	for status in ["responding", "on_scene", "resolved"]:
		dispatch.advance(id, status, "Update: " + status)
	check(phone.messages == ["Update: responding", "Update: on_scene", "Update: resolved"], "subscribed phone receives subsequent response, arrival and closure")
	var attributed := emitted.size() == 3
	for status in emitted:
		attributed = attributed and bool(status.phone) and status.by == "lookout" and status.police_incident_id == original.police_incident_id
	check(attributed and dispatch.calls.size() == 1, "status fan-out keeps NPC attribution and original dispatch")
	var saved: Dictionary = service.snapshot_state()
	check(int(saved.version) == 1 and service.validate_state(saved).is_empty()
		and service.get_incident(id).report.keys().size() == original.keys().size(), "subscription adds no durable report fields or schema version")
	var restored: Dictionary = service.restore_state(JSON.parse_string(JSON.stringify(saved)))
	check(bool(restored.ok) and JSON.parse_string(JSON.stringify(service.snapshot_state())) == JSON.parse_string(JSON.stringify(saved)),
		"existing version-1 snapshot restores faithfully")
	phone.messages.clear()
	var other := _new_incident(service, at)
	service.note_observation(other, "lookout", {"at": at})
	service.note_observation(other, "player", {"at": at})
	service.report_incident(other, "lookout", {"channel": "witness_call", "phone": false})
	service.report_incident(other, "player", {"channel": "case", "phone": false})
	dispatch.advance(other, "responding", "Non-phone corroboration")
	check(phone.messages.is_empty(), "non-phone corroboration does not subscribe a player phone")
	level._request_police_help(at)
	phone.messages.clear()
	var future: Dictionary = service.snapshot_state()
	future.version = 2
	check(not bool(service.restore_state(future).ok), "future incident version still refused")
	dispatch.advance(other, "on_scene", "Live subscription survived refusal")
	check(phone.messages == ["Live subscription survived refusal"], "failed restore cannot discard a live phone subscription")
	# Accepted restore ends session-only subscriptions; original phone attribution
	# stays durable. No hidden schema field or subscription leaks into another load.
	var current: Dictionary = service.snapshot_state()
	check(bool(service.restore_state(current).ok), "accepted restore replaces current session state")
	phone.messages.clear()
	dispatch.advance(other, "on_scene", "No inherited subscription")
	check(phone.messages.is_empty(), "restored NPC report has no stale transient phone subscription")
	level.remove_child(service)
	service.free()
	level.queue_free()
	await get_tree().process_frame
	print("[incident_phone_followup] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
