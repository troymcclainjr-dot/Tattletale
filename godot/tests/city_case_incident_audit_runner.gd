extends "res://tests/city_case_engine_smoke_runner.gd"
## Focused audit regression: real case engine + incident records; dispatch is
## bounded to an acknowledgement stub except the real police notice relay.
const Incidents := preload("res://scripts/city/city_incidents.gd")
const Police := preload("res://scripts/city/city_police_assistance.gd")
const AUDIT_CASE := "fixture_audit_incident"

class Crowd extends Node:
	var residents: Array = []
	func is_dead(index: int) -> bool:
		return index >= 0 and index < residents.size() and bool(residents[index].get("dead", false))
	func resident_position(index: int) -> Vector3:
		return residents[index].position if index >= 0 and index < residents.size() and not residents[index].get("identity_unplaced", false) else Vector3.INF

class Dispatch extends Node:
	var incident_handler
	var open := false
	var calls := 0
	func has_open_ref(_id: String) -> bool:
		return open
	func report_incident(request: Dictionary) -> Dictionary:
		calls += 1
		open = true
		incident_handler.on_police_progress(str(request.incident_ref), "responding", {"police_incident_id": "pol_audit", "text": "Officers are on the way."})
		return {"ok": true, "incident_id": "pol_audit", "message": "Officers are on the way."}

class Service extends Incidents:
	var test_crowd
	var test_police
	func _crowd():
		return test_crowd
	func _police():
		return test_police

class Phone extends Node:
	var messages: Array = []
	func set_report_status(text: String) -> void:
		messages.append(text)

func _run() -> void:
	await get_tree().physics_frame
	_test_crowd_contact()
	_test_reload_recovery()
	_test_terminal_wait()
	_test_victim_and_dedup()
	_test_notice_relay()
	_finish()

func _audit_world() -> FakeLevel:
	var world := _world()
	var service := Service.new()
	world.add_child(service)
	world.incidents = service
	service.level = world
	service.actors.setup(world, service)
	service.spawning_enabled = false
	var crowd := Crowd.new()
	world.add_child(crowd)
	service.test_crowd = crowd
	for i in 13:
		crowd.residents.append({"position": Vector3(30 + i, 0, 0), "dead": false})
	var dispatch := Dispatch.new()
	world.add_child(dispatch)
	service.test_police = dispatch
	dispatch.incident_handler = service
	service.incident_changed.connect(world.missions.on_incident_event)
	var extra := _install(world, [{"schema": 1, "id": AUDIT_CASE, "version": 1, "status": "ready", "title": "Audit incident", "template": "incident_report",
		"params": {"incident_template": "jaywalking", "points": 10}}])
	check(extra.errors.is_empty(), "audit template validates")
	return world

func _open(world: FakeLevel) -> String:
	var service: Service = world.incidents
	var result := service.open_incident({"template": "jaywalking", "at": Vector3(30, 0, 0), "source": "case:audit", "case_id": AUDIT_CASE, "offender_id": "ambient_granny"})
	var id := str(result.incident_id)
	# Trusted fixture input represents the existing witness record, not a new
	# live act. Runtime LOS/spawn behavior has its own production fixture.
	service.note_observation(id, "crowd_12", {"at": Vector3(42, 0, 0), "via": "sight"})
	check(world.missions.start_incident_case(AUDIT_CASE, id), "case begins with recorded crowd witness")
	return id

func _test_crowd_contact() -> void:
	var world := _audit_world()
	_open(world)
	var engine = world.missions.cases
	var definition: Dictionary = engine.definition(AUDIT_CASE)
	check(engine.resolve(definition, "witness") == "crowd_12", "crowd witness resolves outside named NPC registry")
	check(engine.ref_position("participant:witness") == Vector3(42, 0, 0), "crowd witness marker uses durable slot position")
	_place_near(world, Vector3(42, 0, 0))
	check(_pick(_talk(world), "case_interview") and world.missions.stage == 1, "real dialogue hook commits crowd interview")
	var record: Dictionary = engine.active.duplicate(true)
	world.incidents.test_crowd.residents[12].identity_unplaced = true
	check(engine.role_state(definition, "witness", record).state == "absent", "unplaced living crowd witness is absent")
	world.incidents.test_crowd.residents[12].dead = true
	check(engine.role_state(definition, "witness", record).state == "dead", "confirmed crowd death is terminal")
	world.incidents.test_crowd.residents[12].dead = false
	world.incidents.test_crowd.residents[12].police_custody = true
	check(engine.role_state(definition, "witness", record).state == "custody", "crowd custody stays distinct from death")
	var other := definition.duplicate(true)
	other.participants.witness.bind = "step"
	other.participants.witness.actors = ["crowd_12", "crowd_999", "player"]
	world.incidents.test_crowd.residents[12].dead = true
	check(engine.role_state(other, "witness", record).state == "absent", "dead plus unknown candidate is not all dead")
	check(not "player" in engine._candidates(other, "witness", record) and not engine.is_present("player"), "player never fills a case participant role")
	world.free()

func _at_wait(world: FakeLevel) -> String:
	var id := _open(world)
	_place_near(world, Vector3(42, 0, 0))
	check(_pick(_talk(world), "case_interview"), "record witness account before report")
	_place_near(world, world.npcs.actor_position("officer"))
	check(_pick(_talk(world), "case_report") and world.missions.stage == 2, "report accepted and case awaits police")
	return id

func _test_reload_recovery() -> void:
	var world := _audit_world()
	var id := _at_wait(world)
	var saved := _snapshot(world)
	var incident_saved: Dictionary = _round_trip(world.incidents.snapshot_state())
	var evidence_before: Array = world.missions.cases.active.evidence.duplicate(true)
	world.free()
	var restored := _audit_world()
	restored.progression.restore_state(saved.progression)
	check(restored.missions.restore_state(saved.missions), "waiting case restores before incident service")
	check(restored.incidents.restore_state(incident_saved).ok, "reported incident restores without a live response")
	restored.incidents._settle()
	restored.missions.tick(0.3)
	check(restored.incidents.get_incident(id).state == "ended" and restored.missions.cases.focus_objective().verb == "report", "orphaned response offers report retry at wait stage")
	check(restored.missions.cases.active.evidence == evidence_before and restored.missions.stage == 2, "retry preserves evidence and authored stage")
	var retry_save := _snapshot(restored)
	check(restored.missions.cases._record_error(restored.missions.cases.definition(AUDIT_CASE), retry_save.missions.case_engine.active, 2).is_empty(), "retry checkpoint keeps schema-valid objective/evidence provenance")
	_place_near(restored, restored.npcs.actor_position("officer"))
	check(_pick(_talk(restored), "case_report") and restored.incidents.test_police.calls == 1, "restored testimony permits exactly one renewed dispatch")
	check(restored.missions.stage == 2 and restored.missions.cases.focus_objective().verb == "await_incident", "retry returns to outcome wait without advancing twice")
	restored.incidents.resolve_incident(id, "warned", "Warning issued.")
	restored.missions.tick(0.3)
	check(restored.missions.completed_ids.has(AUDIT_CASE), "renewed response completes the case")
	var score := int(restored.missions.score)
	var completed := _snapshot(restored)
	restored.missions.on_incident_event(restored.incidents.get_incident(id))
	restored.missions.tick(0.3)
	check(int(restored.missions.score) == score and score == 10, "duplicate outcome awards points once")
	check(restored.progression.restore_state(completed.progression) and restored.missions.restore_state(completed.missions), "completed case and reward restore")
	restored.missions.on_incident_event(restored.incidents.get_incident(id))
	restored.missions.tick(0.3)
	check(restored.missions.score == score, "reloaded outcome cannot pay again")
	restored.free()

func _test_terminal_wait() -> void:
	for outcome in ["expired", "cancelled"]:
		var world := _audit_world()
		var id := _at_wait(world)
		world.incidents.resolve_incident(id, outcome, "No response possible.")
		world.missions.tick(0.3)
		check(world.missions.active_id.is_empty() and not world.missions.completed_ids.has(AUDIT_CASE) and world.missions.score == 0,
			"terminal %s ends unsatisfiable wait without a reward" % outcome)
		world.free()

func _test_victim_and_dedup() -> void:
	var world := _audit_world()
	var service: Service = world.incidents
	var id := _open(world)
	var body := StaticBody3D.new()
	world.add_child(body)
	body.position = Vector3(42, 0, 0)
	service.test_crowd.residents[12].body = body
	service._live[id] = {"offender": "ambient_granny", "victim": "crowd_12", "phase": "acting"}
	var subjects := service._photo_subjects()
	check(subjects.size() == 1 and subjects[0].collider == body and subjects[0].position == body.position + Vector3.UP * 1.1,
		"crowd victim provider preserves its exact collider and position")
	service._live.clear()
	var photo := {"kind": "photo", "by": "player", "subject_id": "ambient_granny", "verified": true, "ref": "photo_audit"}
	check(service.attach_evidence(id, photo) and service.attach_evidence(id, photo), "same photo attachment succeeds idempotently")
	check(service.get_incident(id).evidence.size() == 1, "duplicate photo uses one evidence slot")
	var statement := {"kind": "statement", "by": "player", "subject_id": "crowd_12", "verified": true, "ref": "statement_audit"}
	service.attach_evidence(id, statement)
	service.attach_evidence(id, statement)
	check(service.get_incident(id).evidence.size() == 3, "statements are not suppressed by photo dedup")
	for i in 5:
		photo.ref = "other_%d" % i
		service.attach_evidence(id, photo)
	photo.ref = "photo_audit"
	check(service.attach_evidence(id, photo) and service.get_incident(id).evidence.size() == 8, "duplicate remains idempotent at evidence cap")
	photo.ref = "overflow"
	check(not service.attach_evidence(id, photo), "distinct ninth evidence still respects cap")
	world.free()

func _test_notice_relay() -> void:
	var world := _audit_world()
	var service: Service = world.incidents
	var id := _open(world)
	var phone := Phone.new()
	world.add_child(phone)
	world.player.phone = phone
	var record := service._record(id)
	record.state = "reported"
	record.report = {"by": "player", "phone": true, "police_incident_id": "pol_audit"}
	service.report_status_changed.connect(func(status: Dictionary):
		if bool(status.phone):
			phone.set_report_status(str(status.text)))
	var police := Police.new()
	world.add_child(police)
	police.level = world
	police.incident_handler = service
	var call := {"id": "pol_audit", "ref": id, "phone": true, "message": "", "phase": "on_scene", "outcome": "", "at": Vector3.ZERO,
		"source": "phone", "suspects": {}, "units": [], "officers": [], "rounds": 0, "created": 0.0}
	police._tell(call, "Officer arrived.", true)
	police._status(call, "on_scene", "Officer arrived.")
	check(phone.messages == ["Officer arrived."], "linked arrival reaches phone once through real incident relay")
	police._tell(call, "Officer is talking.")
	check(phone.messages.size() == 2, "intermediate message without structured status remains visible")
	call.outcome = "warned"
	police._tell(call, "Warning issued.", true)
	police._status(call, "resolved", "Warning issued.")
	check(phone.messages.size() == 3 and phone.messages[-1] == "Warning issued.", "linked closure reaches phone once")
	call.ref = ""
	police._tell(call, "Unlinked response ended.", true)
	check(phone.messages.size() == 4, "unlinked status keeps direct phone fallback")
	world.free()
