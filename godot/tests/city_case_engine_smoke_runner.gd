extends Node
## Data case engine (city_case_engine.gd + schema/library/evidence) driven
## through the real CityMissions, city_progression and city_dialogue_state.
## Small fakes stand in for the world (contacts, deaths, clock, incidents).
## Player verbs go through the mission conversation and a reply choice routed
## like pen_lucy_level conversation_hook; photos go through the phone's v2
## context shape (phone-map-contract §1). Direct commits appear only where a
## stale, forged or duplicated callback is the behavior under test.
const Missions := preload("res://scripts/city/city_missions.gd")
const Progression := preload("res://scripts/city/city_progression.gd")
const DialogueState := preload("res://scripts/city/city_dialogue_state.gd")
const Navigation := preload("res://scripts/city/city_mission_navigation.gd")
const Schema := preload("res://scripts/city/city_case_schema.gd")
const Library := preload("res://scripts/city/city_case_library.gd")
const Evidence := preload("res://scripts/city/city_case_evidence.gd")
const PhotoContext := preload("res://scripts/city/city_photo_context.gd")
const CASE := "parcel_report"
const POLICE := ["officer", "patrol_officer_0", "patrol_officer_1", "patrol_officer_2", "patrol_officer_3", "patrol_officer_4", "patrol_officer_5"]
const SPOTS := {
	"resident": Vector3(0, 0, 0), "lookout": Vector3(20, 0, 0), "officer": Vector3(40, 0, 0), "gardener": Vector3(60, 0, 0),
	"organizer": Vector3(80, 0, 0), "caretaker": Vector3(100, 0, 0), "ambient_mailman": Vector3(120, 0, 20),
	"ambient_neighbor": Vector3(140, 0, 0), "ambient_granny": Vector3(160, 0, 0), "daily_ines_morales": Vector3(180, 0, 0),
	"patrol_officer_0": Vector3(0, 0, 60), "patrol_officer_1": Vector3(20, 0, 60), "patrol_officer_2": Vector3(40, 0, 60),
	"patrol_officer_3": Vector3(60, 0, 60), "patrol_officer_4": Vector3(80, 0, 60), "patrol_officer_5": Vector3(100, 0, 60),
	"daily_aisha_bell": Vector3(200, 0, 0),
}
const LABELS := {"resident": "Ms. Lena · Resident", "lookout": "Malik · Witness", "officer": "Officer Dan", "ambient_mailman": "Mail carrier"}

class FakeActor extends Node3D:
	var actor_id := ""
	var display_name := "Neighbor"
	var enabled := true
	var combat_override := false
	var yaw := 0.0
	var last_line := ""
	func speak(text: String, _seconds := 4.0) -> void:
		last_line = text

class FakeNpcs extends Node3D:
	var actors: Dictionary = {}
	func add(id: String, label: String, at: Vector3) -> Node3D:
		var actor := FakeActor.new()
		actor.actor_id = id
		actor.display_name = label
		actor.name = id
		add_child(actor)
		actor.global_position = at
		actors[id] = actor
		return actor
	func get_actor(id: String) -> Node3D:
		return actors.get(id)
	func actor_position(id: String) -> Vector3:
		var actor: Node3D = actors.get(id)
		if actor == null or actor.get_meta("city_dead", false) or actor.get_meta("police_custody", false) or actor.get_meta("police_custody_completed", false):
			return Vector3.INF
		return actor.global_position
	func speak(id: String, text: String, duration := 4.0) -> void:
		var actor = actors.get(id)
		if actor != null:
			actor.speak(text, duration)
	func find_safe_position(desired: Vector3, _radius := 0.45) -> Dictionary:
		return {"ok": true, "position": desired}

class FakeCombat extends Node:
	signal actor_died(id: String)
	var npcs: Node3D
	var dead: Dictionary = {}
	func is_actor_dead(id: String) -> bool:
		return dead.has(id)
	func kill(id: String, announce := true) -> void:
		dead[id] = true
		var actor = npcs.get_actor(id)
		if actor != null:
			actor.enabled = false
			actor.set_meta("city_dead", true)
		if announce:
			actor_died.emit(id)
	func get_status() -> Dictionary:
		return {"aggro_count": 0, "active_count": 0, "downed": 0.0, "health": 100.0}

class FakeClock extends Node:
	var total_minutes := 540.0
	var elapsed_seconds := 1000.0

class FakePlayer extends CharacterBody3D:
	var yaw := 0.0
	var phone = null

class FakeIncidents extends Node:
	var performers: Dictionary = {}
	func performer_actor(id: String):
		return performers.get(id)
	var reports: Array = []
	var attached: Array = []
	var answer := {"ok": true, "status": "report_received", "police_incident_id": "pol_000001", "duplicate": false}
	func report_incident(id: String, reporter_id := "player", context := {}) -> Dictionary:
		reports.append({"id": id, "reporter": reporter_id, "context": context.duplicate(true)})
		var result: Dictionary = answer.duplicate(true)
		result["incident_id"] = id
		return result
	func attach_evidence(id: String, evidence: Dictionary) -> bool:
		attached.append({"id": id, "evidence": evidence.duplicate(true)})
		return true

class FakeLevel extends Node3D:
	var paused := false
	var player: CharacterBody3D
	var combat: Node
	var progression: Node
	var missions: Node3D
	var npcs: Node3D
	var world_time: Node
	var incidents: Node
	var level_data: Dictionary = {}
	func vector(value) -> Vector3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	# Same routing as pen_lucy_level.gd conversation_condition/conversation_hook.
	func conversation_condition(key) -> bool:
		if progression != null and progression.handles_condition(key):
			return progression.meets(key)
		return false
	func conversation_hook(action: Dictionary) -> bool:
		if str(action.get("kind", "")) == "progression":
			return progression != null and progression.commit_dialogue_action(action)
		return missions != null and missions.commit_dialogue_action(action)

var failures := 0
var passes := 0
var _finished := false
var _signals := {"evidence": [], "report": [], "resolved": []}

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(180.0, true, false, true).timeout
	if not _finished:
		check(false, "watchdog: case engine tests did not finish within 180 seconds")
		_finish()

func check(ok: bool, label: String) -> bool:
	print("[case_engine] %s %s" % ["PASS" if ok else "FAIL", label])
	if ok:
		passes += 1
	else:
		failures += 1
	return ok

func _run() -> void:
	await get_tree().physics_frame
	_test_library()
	_test_schema_refusals()
	_test_parcel_loop()
	await _test_photo_evidence()
	_test_interview_trust()
	_test_report_gate()
	_test_persistence()
	_test_contacts()
	await _test_verbs()
	_test_incident_bridge()
	_test_incident_photo_gate()
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[case_engine] passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

# --- Fixture -------------------------------------------------------------------------

func _world(with_incidents := false) -> FakeLevel:
	var world := FakeLevel.new()
	add_child(world)
	world.level_data = {"route": {"points": [[-10.0, 0.0, -30.0], [400.0, 0.0, -30.0]]}}
	var npcs := FakeNpcs.new()
	world.add_child(npcs)
	world.npcs = npcs
	for id in SPOTS:
		npcs.add(str(id), str(LABELS.get(id, "Neighbor")), SPOTS[id])
	var combat := FakeCombat.new()
	combat.npcs = npcs
	world.add_child(combat)
	world.combat = combat
	var clock := FakeClock.new()
	world.add_child(clock)
	world.world_time = clock
	if with_incidents:
		var incidents := FakeIncidents.new()
		world.add_child(incidents)
		world.incidents = incidents
	var player := FakePlayer.new()
	world.add_child(player)
	world.player = player
	player.global_position = Vector3(-200, 0, -200)
	var missions = Missions.new()
	world.add_child(missions)
	missions.setup(world, npcs)
	world.missions = missions
	var progression = Progression.new()
	world.add_child(progression)
	progression.setup(world)
	world.progression = progression
	combat.actor_died.connect(missions.on_actor_died)
	missions.evidence_recorded.connect(func(id: String, evidence: Dictionary): _signals.evidence.append([id, evidence]))
	missions.report_filed.connect(func(id: String, report: Dictionary): _signals.report.append([id, report]))
	missions.case_resolved.connect(func(id: String, outcome: Dictionary): _signals.resolved.append([id, outcome]))
	return world

func _reset_signals() -> void:
	_signals = {"evidence": [], "report": [], "resolved": []}

func _round_trip(value):
	return JSON.parse_string(JSON.stringify(value))

func _snapshot(world: FakeLevel) -> Dictionary:
	return _round_trip({"missions": world.missions.snapshot_state(), "progression": world.progression.snapshot_state(),
		"deaths": {"version": 1, "dead": world.combat.dead.keys()}})

## Same order as the world-save provider: progression, then missions.
func _reload(saved: Dictionary) -> FakeLevel:
	var world := _world()
	world.progression.restore_state(saved.progression)
	var ok: bool = world.missions.restore_state(saved.missions)
	check(ok, "reload restores the saved missions section")
	return world

## A world whose satchel case is already done (legitimate prerequisite state).
func _parcel_world(with_incidents := false) -> FakeLevel:
	var world := _world(with_incidents)
	world.missions.restore_state({"active_id": "", "stage": 0, "completed_ids": ["lost_satchel"], "score": 100})
	world.progression.reconcile_cases(["lost_satchel"])
	return world

func _place_near(world: FakeLevel, target: Vector3) -> void:
	world.player.global_position = target + Vector3(1.2, 0, 0)

func _talk(world: FakeLevel):
	var graph: Dictionary = world.missions.conversation_preview()
	if graph.is_empty():
		return null
	var state = DialogueState.new()
	if not state.open(graph, Callable(world, "conversation_condition"), Callable(world, "conversation_hook")):
		return null
	return state

func _choices(state) -> Array:
	if state == null:
		return []
	for _i in 8:
		if not state.choices().is_empty():
			break
		state.advance()
	return state.choices()

func _pick(state, kind: String) -> bool:
	var replies := _choices(state)
	for index in replies.size():
		if str(replies[index].get("hook", {}).get("kind", "")) == kind:
			state.choose(index)
			return true
	return false

## Walk to the case marker, press E, pick the case reply.
func _step(world: FakeLevel, kind: String) -> bool:
	var status: Dictionary = world.missions.get_status()
	var before := int(status.stage)
	if str(status.active_id).is_empty():
		return false
	_place_near(world, status.target_position)
	var state = _talk(world)
	return _pick(state, kind) and (world.missions.active_id != CASE or int(world.missions.stage) == before + 1)

func _accept_parcel(world: FakeLevel) -> bool:
	_place_near(world, world.npcs.actor_position("resident"))
	var state = _talk(world)
	return _pick(state, "start_case") and world.missions.active_id == CASE

func _evidence_ids(world: FakeLevel) -> Array:
	var ids: Array = []
	for entry in world.missions.evidence_list(CASE):
		ids.append(str(entry.id))
	return ids

func _prop_point(world: FakeLevel) -> Vector3:
	return world.missions.cases._props["scene"].photo.global_position

func _photo(world: FakeLevel, photo_id: String, eye: Vector3, look: Vector3, subjects: Array, minute := -1.0) -> Dictionary:
	var at := float(world.world_time.total_minutes) if minute < 0.0 else minute
	return {"version": 2, "source": "phone_camera", "trusted": true, "photo_id": photo_id, "image_path": "user://phone_gallery/%s.png" % photo_id,
		"time": {"total_minutes": at, "day_index": 0, "minute_of_day": fposmod(at, 1440.0), "label": "DAY 1"},
		"camera": {"position": eye, "forward": (look - eye).normalized(), "fov": 58.0, "aspect": 16.0 / 9.0, "far": 4000.0},
		"player_position": eye - Vector3.UP * 1.5, "street": "Old York Road", "subjects": subjects, "subjects_considered": subjects.size(), "rays_cast": subjects.size()}

func _listed(id: String, at: Vector3, eye: Vector3) -> Dictionary:
	return {"id": id, "kind": "case_clue", "label": "", "position": at, "distance": eye.distance_to(at), "screen": Vector2(0.5, 0.5), "centrality": 1.0,
		"line_of_sight": true, "tags": []}

func _wall(world: FakeLevel, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = at
	return body

func _templates() -> Dictionary:
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cases/index.json"))
	var result := {}
	for relative in index.templates:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cases/" + str(relative)))
		result[str(data.template)] = data.case
	return result

## Shipped library plus fixture definitions, installed into one world.
func _install(world: FakeLevel, raws: Array) -> Dictionary:
	var engine = world.missions.cases
	var context: Dictionary = engine.context()
	var extra: Dictionary = Library.load_definitions(raws, _templates(), context)
	var merged: Dictionary = Library.load_index(context).duplicate(true)
	for id in extra.order:
		merged.cases[id] = extra.cases[id]
		merged.order.append(id)
	merged.errors.append_array(extra.errors)
	engine.use_library(merged)
	return extra

# --- Library and schema ------------------------------------------------------------

func _test_library() -> void:
	var world := _world()
	var m = world.missions
	var report: Dictionary = m.case_library_report()
	check(report.errors.is_empty(), "shipped case library loads without errors %s" % str(report.errors))
	check(m.cases.owns(CASE) and str(m.cases.definition(CASE).template) == "report_with_witness", "parcel_report is owned by the data engine through its template")
	check(report.templates.size() == 7, "seven templates load (%d)" % report.templates.size())
	var parcel_warnings := 0
	for warning in report.warnings:
		parcel_warnings += int(str(warning).contains("parcel_report"))
	check(parcel_warnings == 0, "the migrated parcel case has no draft text or default prompts left")
	check(m.save_schema().keys().slice(0, 6) == ["lost_satchel", "parcel_report", "dumping", "missing_tools", "torn_notice", "porch_light"],
		"save schema keeps the six original cases first and in order")
	check(int(m.save_schema().parcel_report.reward) == 150 and int(m.save_schema().parcel_report.stages) == 4, "migrated slot keeps reward 150 and four stages")
	var status: Dictionary = m.get_status()
	check(int(status.total) == 6 and status.cases.size() == 6, "ledger and totals still describe exactly six cases")
	var steps: Array = m.case_steps(CASE)
	check(steps.size() == 4 and str(steps[0].target) == "resident" and str(steps[1].target) == "clue" and str(steps[2].target) == "lookout"
		and str(steps[3].target) == "officer", "case_steps keeps the original contact order resident/clue/lookout/officer")
	check(m.legacy_steps(CASE).size() == 4, "the original authored steps stay available as the fallback")
	# Every template instantiates into a valid case with ordinary params.
	var context: Dictionary = m.cases.context()
	var params := {
		"report_with_witness": {"owner": "caretaker", "owner_label": "Caretaker", "witness": "lookout", "witness_label": "Witness", "prop_builder": "lantern",
			"prop_title": "LANTERN", "route_metres": 181.0, "prop_radius": 0.32},
		"return_property": {"owner": "resident", "owner_label": "Resident", "item_builder": "satchel", "item_title": "SATCHEL", "route_metres": 35.0, "item_radius": 0.32},
		"return_property_with_pointer": {"owner": "gardener", "owner_label": "Gardener", "pointer": "ambient_mailman", "pointer_label": "Mail carrier",
			"item_builder": "tool_caddy", "item_title": "CADDY", "route_metres": 88.0, "item_radius": 0.32},
		"photograph_and_report": {"tipster": "lookout", "tipster_label": "Witness", "subject": "ambient_mailman", "subject_label": "Mail carrier", "photo_count": 2, "photo_interval": 1.0},
		"tail_and_photograph": {"tipster": "lookout", "tipster_label": "Witness", "subject": "ambient_mailman", "subject_label": "Mail carrier", "tail_seconds": 20.0},
		"report_and_confirm": {"reporter": "lookout", "reporter_label": "Witness", "prop_builder": "dumped_bags", "prop_title": "BAGS", "route_metres": 155.0, "prop_radius": 0.55},
		"incident_report": {"incident_template": "jaywalking", "points": 0},
	}
	var templates := _templates()
	for template in templates:
		var raw := {"schema": 1, "id": "fixture_" + str(template), "version": 1, "title": "Fixture " + str(template), "status": "draft", "template": str(template),
			"params": params.get(template, {})}
		var result: Dictionary = Library.load_definitions([raw], templates, context)
		var drafts := 0
		for warning in result.warnings:
			drafts += int(str(warning).contains("[draft]"))
		check(result.errors.is_empty() and result.cases.has(raw.id) and drafts > 0, "template %s instantiates, and its untouched text is reported as draft (%s)" % [template, str(result.errors)])
	# The compact authoring example stays valid.
	var example = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cases/examples/rapid_authoring.example.json"))
	var loaded: Dictionary = Library.load_definitions([example], templates, context)
	check(loaded.errors.is_empty() and loaded.cases.has("example_lost_tools") and str(loaded.cases.example_lost_tools.status) == "draft",
		"the rapid authoring example validates as a draft %s" % str(loaded.errors))
	# The editor JSON schema lists the same verbs and builders as the validator.
	var schema_doc = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cases/case_schema.json"))
	var verbs: Array = schema_doc["$defs"]["objective"]["properties"]["verb"]["enum"]
	var builders: Array = schema_doc["properties"]["props"]["additionalProperties"]["properties"]["builder"]["enum"]
	check(verbs == Schema.VERBS and builders == Schema.BUILDERS, "case_schema.json verbs and builders match city_case_schema.gd")
	world.free()

func _base_case() -> Dictionary:
	return {"schema": 1, "id": "fixture_bad", "version": 1, "title": "Fixture", "status": "draft",
		"participants": {"owner": {"actors": ["resident"], "label": "Resident"}, "officer": {"actors": ["@police"], "label": "Officer", "bind": "step"}},
		"props": {"thing": {"builder": "crate", "placement": {"route_metres": 40.0}}},
		"evidence": {"seen": {"kind": "observation", "label": "Seen"}, "said": {"kind": "testimony", "label": "Said"}},
		"discovery": {"givers": ["owner"]},
		"stages": [
			{"id": "one", "objectives": [{"id": "look", "verb": "examine", "target": "prop:thing", "objective": "Look", "prompt": "E  Look", "dialogue": "Seen.", "grants": ["seen"]}]},
			{"id": "two", "objectives": [{"id": "ask", "verb": "interview", "target": "owner", "objective": "Ask", "prompt": "E  Ask",
				"topics": [{"id": "what", "ask": "What?", "answer": "That."}], "grants": ["said"]}]},
			{"id": "three", "objectives": [{"id": "tell", "verb": "report", "target": "officer", "objective": "Tell", "prompt": "E  Tell", "requires_evidence": ["seen", "said"]}]}
		]}

func _refused(world: FakeLevel, raw: Dictionary, label: String, fragment: String) -> void:
	var result: Dictionary = Library.load_definitions([raw], _templates(), world.missions.cases.context())
	var joined := " | ".join(PackedStringArray(result.errors))
	check(not result.cases.has(str(raw.get("id", ""))) and joined.contains(fragment), "schema refuses %s (%s)" % [label, joined.left(160)])

func _test_schema_refusals() -> void:
	var world := _world()
	var good: Dictionary = Library.load_definitions([_base_case()], _templates(), world.missions.cases.context())
	check(good.errors.is_empty() and good.cases.has("fixture_bad"), "the fixture base case is valid %s" % str(good.errors))
	var raw := _base_case()
	raw["colour"] = "blue"
	_refused(world, raw, "an unknown field", "unknown field \"colour\"")
	raw = _base_case()
	raw.stages[0].objectives[0].verb = "punch"
	_refused(world, raw, "a verb outside the nonviolent set", "verb")
	raw = _base_case()
	raw.stages[1].objectives[0].target = "landlord"
	_refused(world, raw, "an unknown participant", "unknown participant role")
	raw = _base_case()
	raw.stages[2].objectives[0].requires_evidence = ["said", "photo_of_nothing"]
	_refused(world, raw, "report evidence nobody grants", "unknown evidence")
	raw = _base_case()
	raw.stages[0].objectives[0].grants = []
	_refused(world, raw, "evidence never granted before its report", "never granted before this stage")
	raw = _base_case()
	raw.id = "petals_word"
	_refused(world, raw, "a story part id", "reserved")
	raw = _base_case()
	raw.id = "parcel_report"
	raw.legacy_slot = true
	_refused(world, raw, "a migrated original that changes its reward or stages", "keeps its title, reward")
	raw = _base_case()
	raw.id = "dumping"
	_refused(world, raw, "an original id without legacy_slot", "belongs to an original case")
	raw = _base_case()
	raw.stages[1].objectives[0].id = "look"
	_refused(world, raw, "a duplicated objective id", "used twice")
	raw = _base_case()
	raw.stages[0].objectives = [{"id": "give", "verb": "deliver", "target": "owner", "item": "prop:thing", "objective": "Give"}]
	_refused(world, raw, "a delivery before the pickup", "not collected before")
	raw = _base_case()
	raw.participants.officer.actors = ["@army"]
	_refused(world, raw, "an unknown role token", "unknown role token")
	var templated := {"schema": 1, "id": "fixture_param", "version": 1, "title": "Fixture", "template": "report_with_witness", "params": {"owner": "resident"}}
	_refused(world, templated, "a template with missing params", "unresolved template parameter")
	_refused(world, {"schema": 1, "id": "fixture_t", "version": 1, "title": "T", "template": "nope"}, "an unknown template", "unknown template")
	var photo_case := _incident_photo_case()
	var tags: Array = []
	for index in PhotoContext.MAX_TAGS:
		tags.append(("tag_%d_" % index) + "x".repeat(PhotoContext.MAX_TAG_LENGTH - 6))
	photo_case.stages[0].objectives[0].require_tags = tags
	var tag_result: Dictionary = Library.load_definitions([photo_case], _templates(), world.missions.cases.context())
	check(tag_result.errors.is_empty() and PhotoContext._tags(tags) == tags, "eight unique 96-character requirements survive both schema and capture exactly")
	photo_case.stages[0].objectives[0].require_tags = tags + ["ninth"]
	_refused(world, photo_case, "nine required photo tags", "require_tags")
	photo_case.stages[0].objectives[0].require_tags = ["same", "same"]
	_refused(world, photo_case, "duplicate required photo tags", "unique tags")
	photo_case.stages[0].objectives[0].require_tags = ["x".repeat(97)]
	_refused(world, photo_case, "97-character required photo tag", "require_tags")
	photo_case.id = "a".repeat(40)
	var long_tag: String = "case:" + str(photo_case.id)
	photo_case.stages[0].objectives[0].require_tags = [long_tag]
	tag_result = Library.load_definitions([photo_case], _templates(), world.missions.cases.context())
	check(tag_result.errors.is_empty() and PhotoContext._tags([long_tag]) == [long_tag], "a 40-character case ID retains its full 45-character photo tag")
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cases/case_schema.json"))
	var tag_schema: Dictionary = doc["$defs"].objective.properties.require_tags
	check(int(tag_schema.maxItems) == PhotoContext.MAX_TAGS and int(tag_schema.items.maxLength) == PhotoContext.MAX_TAG_LENGTH
		and tag_schema.uniqueItems == true, "editor tag limits agree with runtime schema and capture")
	world.free()

# --- The migrated parcel case, played ------------------------------------------------

func _test_parcel_loop() -> void:
	var world := _parcel_world()
	var m = world.missions
	var p = world.progression
	_reset_signals()
	var row: Dictionary = {}
	for entry in m.get_status().cases:
		if str(entry.id) == CASE:
			row = entry
	check(str(row.get("state", "")) == "available", "after the satchel the parcel case is available in the original ledger row")
	_place_near(world, world.npcs.actor_position("resident"))
	var offer: Dictionary = m.conversation_preview()
	var replies: Array = offer.get("nodes", {}).get("start", {}).get("choices", [])
	check(replies.size() == 2 and str(replies[0].get("hook", {}).get("kind", "")) == "start_case" and str(replies[0].hook.id) == CASE
		and str(replies[1].text) == "Maybe later." and str(offer.nodes.start.speaker) == "Resident", "the resident's offer keeps the original [accept, Maybe later] shape and hook")
	check(m.active_id.is_empty(), "opening the offer starts nothing")
	var money: int = p.money
	check(_accept_parcel(world) and m.stage == 0, "accepting the reply starts the data case at stage 0")
	var status: Dictionary = m.get_status()
	check(str(status.title) == "The opened parcel" and Vector3(status.target_position).distance_to(world.npcs.actor_position("resident")) < 0.01
		and str(status.objective) == "Ask the resident about an opened delivery", "HUD title, objective and marker come from the data stage")
	var nav := Navigation.new()
	nav.setup(world.level_data)
	nav.update(status, world.player.global_position, 0.0, true)
	check(nav.active_id == CASE and nav.stage == 0 and nav.target.distance_to(status.target_position) < 0.01, "mission navigation follows the data case target and stage")
	check(_step(world, "case_step") and m.stage == 1, "talking to the resident completes the brief")
	var parcel: Vector3 = m.cases.ref_position("prop:scene")
	check(parcel.is_finite() and absf(parcel.x - 45.0) < 0.01 and absf(parcel.z + 30.0) < 0.01, "the opened parcel stands 55 m along the walk, like the original")
	check(Vector3(m.get_status().target_position).distance_to(parcel) < 0.01, "the marker moves to the parcel")
	check(_step(world, "case_step") and m.stage == 2 and "scene_record" in _evidence_ids(world), "inspecting the label records observation evidence")
	check(_step(world, "case_interview") and m.stage == 3 and "witness_account" in _evidence_ids(world), "the witness interview records testimony through a conversation reply")
	var testimony: Dictionary = {}
	for entry in m.evidence_list(CASE):
		if str(entry.id) == "witness_account":
			testimony = entry
	check(str(testimony.get("witness", "")) == "lookout" and testimony.get("topics", []) == ["account"], "testimony names the actual witness and topic")
	check(_step(world, "case_report"), "the officer files the report with the evidence")
	check(m.active_id.is_empty() and m.completed_ids.has(CASE) and m.score == 250, "the case completes once with its 150 points")
	check(p.money == money + int(p.case_money(CASE, 150)), "money is paid through the existing case reward at the configured rate")
	check(_signals.evidence.size() == 2 and _signals.report.size() == 1 and _signals.resolved.size() == 1, "two evidence, one report and one resolution signal")
	var filed: Dictionary = _signals.report[0][1]
	check(filed.evidence.size() == 2 and str(filed.officer_actor_id) == "officer", "the report carries the gathered evidence and the officer who took it")
	check(not p.reward_case(CASE, 150) and p.money == money + int(p.case_money(CASE, 150)), "a second reward request pays nothing")
	var engine_state: Dictionary = m.snapshot_state().case_engine
	check(engine_state.records.has(CASE) and str(engine_state.records[CASE].outcome) == "resolved", "the resolution is recorded by the data engine")
	check(not m.commit_dialogue_action({"kind": "case_report", "id": CASE, "stage": 3, "objective": "file_report"}) and m.score == 250,
		"a replayed report hook after completion changes nothing")
	check(not m.start_case(CASE), "a completed data case cannot start again")
	world.free()

# --- Photo evidence ------------------------------------------------------------------

func _parcel_at_scene(world: FakeLevel) -> bool:
	return _accept_parcel(world) and _step(world, "case_step") and world.missions.stage == 1

func _test_photo_evidence() -> void:
	var world := _parcel_world()
	var m = world.missions
	check(_parcel_at_scene(world), "photo fixture reaches the scene stage")
	var point := _prop_point(world)
	var subject: String = m.cases.subject_id(CASE, "scene")
	var eye := point + Vector3(-5.0, 1.4, 0.4)
	world.player.global_position = eye - Vector3.UP * 1.5
	var listed := [_listed(subject, point, eye)]
	var result: Dictionary = m.on_photo_captured({"photo_id": "photo_gallery_only", "image_path": "user://phone_gallery/photo_gallery_only.png"})
	check(not bool(result.ok) and m.stage == 1, "a gallery image without a trusted pose is not evidence")
	var forged := _photo(world, "photo_forged", eye, point, listed)
	forged.source = "gallery"
	check(not bool(m.on_photo_captured(forged).ok) and m.stage == 1, "a context that is not from the phone camera is refused")
	result = m.on_photo_captured(_photo(world, "photo_unlisted", eye, point, []))
	check(str(result.reason) == "not_in_photo" and m.stage == 1, "the phone did not see the parcel: no evidence")
	result = m.on_photo_captured(_photo(world, "photo_away", eye, eye + Vector3(-5, 0, 0), listed))
	check(str(result.reason) == "out_of_frame" and m.stage == 1, "a listed subject outside the recorded frame is refused")
	var far := point + Vector3(-40.0, 1.4, 0.0)
	result = m.on_photo_captured(_photo(world, "photo_far", far, point, [_listed(subject, point, far)]))
	check(str(result.reason) == "too_far" and m.stage == 1, "a parcel 40 m away is too far to count")
	var moved := [_listed(subject, point + Vector3(0, 0, 6), eye)]
	result = m.on_photo_captured(_photo(world, "photo_moved", eye, point + Vector3(0, 0, 6), moved))
	check(str(result.reason) == "subject_moved" and m.stage == 1, "a listing that disagrees with where the parcel really is is refused")
	result = m.on_photo_captured(_photo(world, "photo_stale", eye, point, listed, 530.0))
	check(str(result.reason) == "photo context is stale" and m.stage == 1, "a context ten game minutes old is stale")
	world.world_time.total_minutes = 541.0
	result = m.on_photo_captured(_photo(world, "photo_early", eye, point, listed, 539.5))
	check(str(result.reason) == "photo predates the case" and m.stage == 1, "a photo taken before the case started is refused")
	world.world_time.total_minutes = 540.0
	var wall := _wall(world, (eye + point) * 0.5, Vector3(0.2, 4.0, 4.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	result = m.on_photo_captured(_photo(world, "photo_wall", eye, point, listed))
	check(str(result.reason) == "blocked" and m.stage == 1, "a wall between the lens and the parcel blocks the photo")
	wall.global_position = point + Vector3(-0.3, 0.5, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	result = m.on_photo_captured(_photo(world, "photo_close_wall", eye, point, listed))
	check(str(result.reason) == "blocked" and m.stage == 1, "a wall 0.3 m in front of the parcel still blocks it (no radius tolerance)")
	wall.collision_layer = 0
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not m.cases.holds("scene_photo") and m.stage == 1, "no refused photo left evidence behind")
	result = m.on_photo_captured(_photo(world, "photo_good", eye, point, listed))
	check(bool(result.ok) and "scene_photo" in result.recorded and m.stage == 2, "a framed, unobstructed, current photo of the parcel completes the scene stage")
	var record: Dictionary = {}
	for entry in m.evidence_list(CASE):
		if str(entry.id) == "scene_photo":
			record = entry
	check(str(record.get("photo_id", "")) == "photo_good" and str(record.get("subject", "")) == subject and float(record.get("distance", 0.0)) > 4.0,
		"photo evidence records the photo id, the subject and the measured distance")
	check(str(m.on_photo_captured(_photo(world, "photo_good", eye, point, listed)).reason) == "photo already evaluated", "the same photo is never evaluated twice")
	world.free()
	# Gallery metadata version 1 (no subject list): the engine checks the pose itself.
	var legacy := _parcel_world()
	check(_parcel_at_scene(legacy), "second photo fixture reaches the scene stage")
	var at := _prop_point(legacy)
	var lens := at + Vector3(0.0, 1.5, -6.0)
	var forward := (at - lens).normalized()
	var v1 := {"version": 1, "capture_id": "photo_v1", "clean_capture": true, "camera_position": [lens.x, lens.y, lens.z],
		"camera_forward": [forward.x, forward.y, forward.z], "camera_fov": 58.0, "width": 1280, "height": 720, "world_total_minutes": 540.0}
	check("scene_photo" in legacy.missions.on_photo_captured(v1).recorded and legacy.missions.stage == 2, "a version 1 pose is evaluated against the live parcel")
	legacy.free()

# --- Interviews ----------------------------------------------------------------------

func _test_interview_trust() -> void:
	var world := _parcel_world()
	var m = world.missions
	check(_parcel_at_scene(world) and _step(world, "case_step") and m.stage == 2, "interview fixture reaches the witness stage")
	_place_near(world, world.npcs.actor_position("lookout"))
	var graph: Dictionary = m.conversation_preview()
	var hook: Dictionary = {}
	for choice in graph.get("nodes", {}).get("start", {}).get("choices", []):
		if str(choice.get("hook", {}).get("kind", "")) == "case_interview":
			hook = choice.hook
	check(str(hook.get("witness", "")) == "lookout" and str(hook.get("topic", "")) == "account", "the interview reply names its witness and topic")
	check(not m.interact(), "a bare E press cannot record testimony")
	var wrong: Dictionary = hook.duplicate()
	wrong.witness = "officer"
	check(not m.commit_dialogue_action(wrong), "a hook naming another witness is refused")
	wrong = hook.duplicate()
	wrong.stage = 1
	check(not m.commit_dialogue_action(wrong), "a hook from another stage is refused")
	wrong = hook.duplicate()
	wrong.topic = "rumours"
	check(not m.commit_dialogue_action(wrong), "an unknown topic is refused")
	wrong = hook.duplicate()
	wrong.kind = "case_step"
	check(not m.commit_dialogue_action(wrong), "a plain step hook cannot complete an interview")
	world.player.global_position = world.npcs.actor_position("lookout") + Vector3(9, 0, 0)
	check(not m.commit_dialogue_action(hook) and m.stage == 2, "a reply from out of range is refused")
	check(not m.cases.holds("witness_account"), "no testimony after refused replies")
	_place_near(world, world.npcs.actor_position("lookout"))
	check(m.commit_dialogue_action(hook) and m.stage == 3 and m.cases.holds("witness_account"), "the trusted reply records the account once")
	check(not m.commit_dialogue_action(hook) and m.stage == 3, "replaying it after the stage moved on does nothing")
	world.free()
	# Two topics, the second unlocked by the first: each is its own trusted event.
	var multi := _world()
	var raw := _base_case()
	raw.id = "fixture_topics"
	raw.stages = [{"id": "two", "objectives": [{"id": "ask", "verb": "interview", "target": "owner", "objective": "Ask", "prompt": "E  Ask", "greeting": "Yes?",
		"topics": [{"id": "what", "ask": "What happened?", "answer": "A box was opened."}, {"id": "who", "ask": "Who?", "answer": "I could not see.", "after": ["what"]}],
		"grants": ["said"]}]}]
	raw.props = {}
	raw.evidence = {"said": {"kind": "testimony", "label": "Said"}}
	_install(multi, [raw])
	multi.missions.cases.allow_drafts = true
	check(multi.missions.start_case("fixture_topics"), "two-topic fixture starts")
	_place_near(multi, multi.npcs.actor_position("resident"))
	var base := {"kind": "case_interview", "id": "fixture_topics", "stage": 0, "objective": "ask", "witness": "resident"}
	var later := base.duplicate()
	later.topic = "who"
	check(not multi.missions.commit_dialogue_action(later), "a follow-up question cannot be asked before its lead-in")
	var first := base.duplicate()
	first.topic = "what"
	check(multi.missions.commit_dialogue_action(first) and not multi.missions.cases.holds("said"), "one answered topic is not yet the whole account")
	check(multi.missions.commit_dialogue_action(first) and multi.missions.cases.active.topics.ask == ["what"], "hearing an answer again records nothing new")
	check(multi.missions.commit_dialogue_action(later) and multi.missions.completed_ids.has("fixture_topics"), "the second topic completes the interview")
	multi.free()

# --- Report gate ---------------------------------------------------------------------

func _test_report_gate() -> void:
	var world := _parcel_world()
	var m = world.missions
	var record := {"id": CASE, "def_version": 1, "stage": 3, "done": {"brief_owner": true, "record_scene": true, "interview_witness": true}, "progress": {},
		"topics": {"interview_witness": ["account"]}, "evidence": [], "started_minute": 540.0, "bindings": {"owner": "resident", "witness": "lookout"},
		"photos": {}, "carrying": [], "delivered": [], "incident_id": ""}
	var section := {"active_id": CASE, "stage": 3, "completed_ids": ["lost_satchel"], "score": 100,
		"case_engine": {"version": 1, "active": record, "closed": {}, "records": {}, "seen_photos": []}}
	check(m.validate_state(section, {}).is_empty() and m.restore_state(section) and m.stage == 3, "a record at the report stage without evidence restores")
	_place_near(world, world.npcs.actor_position("officer"))
	var graph: Dictionary = m.conversation_preview()
	var start: Dictionary = graph.get("nodes", {}).get("start", {})
	var hooks := 0
	for choice in start.get("choices", []):
		hooks += int(choice.has("hook"))
	check(hooks == 0 and str(start.get("lines", [""])[-1]).begins_with("Bring me what you recorded"), "without evidence the officer explains what is missing and offers no report")
	check(not m.commit_dialogue_action({"kind": "case_report", "id": CASE, "stage": 3, "objective": "file_report"}) and m.stage == 3 and m.active_id == CASE,
		"a forged report hook without evidence is refused")
	world.free()

# --- Persistence ---------------------------------------------------------------------

func _test_persistence() -> void:
	var world := _parcel_world()
	var m = world.missions
	check(_parcel_at_scene(world), "persistence fixture reaches the scene stage")
	var point := _prop_point(world)
	var eye := point + Vector3(-5.0, 1.4, 0.0)
	var photo := _photo(world, "photo_saved", eye, point, [_listed(m.cases.subject_id(CASE, "scene"), point, eye)])
	check("scene_photo" in m.on_photo_captured(photo).recorded and m.stage == 2, "photo evidence before the checkpoint")
	var saved := _snapshot(world)
	check(m.validate_state(saved.missions, saved).is_empty(), "the mid-case checkpoint validates")
	var reloaded := _reload(saved)
	var again := _snapshot(reloaded)
	check(JSON.stringify(again.missions) == JSON.stringify(saved.missions), "snapshot → JSON → restore → snapshot is identical")
	check(reloaded.missions.restore_state(saved.missions) and JSON.stringify(_snapshot(reloaded).missions) == JSON.stringify(saved.missions),
		"restoring the same checkpoint twice is idempotent")
	check(reloaded.missions.active_id == CASE and reloaded.missions.stage == 2 and reloaded.missions.cases.holds("scene_photo"), "stage and evidence survive")
	var replay := _photo(reloaded, "photo_saved", eye, point, [_listed(reloaded.missions.cases.subject_id(CASE, "scene"), point, eye)])
	check(str(reloaded.missions.on_photo_captured(replay).reason) == "photo already evaluated", "the photo replay ring survives a reload")
	var money: int = reloaded.progression.money
	check(_step(reloaded, "case_interview") and _step(reloaded, "case_report") and reloaded.missions.completed_ids.has(CASE), "the reloaded case finishes")
	check(reloaded.progression.money == money + int(reloaded.progression.case_money(CASE, 150)) and reloaded.missions.score == 250, "it pays exactly once after the reload")
	var finished := _snapshot(reloaded)
	var after := _reload(finished)
	check(after.missions.completed_ids.has(CASE) and after.missions.active_id.is_empty() and after.missions.score == 250 and not after.progression.reward_case(CASE, 150),
		"a checkpoint after completion neither replays nor re-pays")
	check(JSON.stringify(_snapshot(after).missions) == JSON.stringify(finished.missions), "the completed record round-trips unchanged")
	after.free()
	reloaded.free()
	# A checkpoint written before the engine owned the case (no case_engine).
	var old := _world()
	check(old.missions.restore_state({"active_id": CASE, "stage": 2, "completed_ids": ["lost_satchel"], "score": 100}) and old.missions.stage == 2,
		"an old checkpoint at stage 2 resumes")
	var migrated: Dictionary = {}
	for entry in old.missions.evidence_list(CASE):
		if str(entry.id) == "scene_record":
			migrated = entry
	check(str(migrated.get("source", "")) == "migrated" and not old.missions.cases.holds("witness_account"), "earlier stages' evidence is migrated, later evidence is not invented")
	check(_step(old, "case_interview") and _step(old, "case_report") and old.missions.completed_ids.has(CASE), "the migrated case finishes through the remaining replies")
	old.free()
	# Corruptions are refused by validate_state without touching the world.
	var base: Dictionary = saved.duplicate(true)
	for kind in ["an unknown engine field", "a future engine version", "a record stage that disagrees with the section", "evidence without its objective",
			"an unknown evidence id", "a closed entry for a case the engine does not own", "a photo ring over its limit", "a bad witness binding",
			"a record for another case", "every officer dead with the report pending"]:
		var broken: Dictionary = base.duplicate(true)
		_corrupt(broken, str(kind))
		var reason: String = m.validate_state(broken.missions, broken)
		check(not reason.is_empty(), "validate_state refuses %s (%s)" % [kind, reason])
	var one_dead: Dictionary = base.duplicate(true)
	one_dead.deaths.dead = ["officer"]
	check(m.validate_state(one_dead.missions, one_dead).is_empty() and m.required_contacts(one_dead.missions, ["officer"]).is_empty(),
		"Officer Dan alone dead is fine: another officer can take the report")
	var everyone: Array = m.required_contacts(base.missions, POLICE.duplicate())
	check(everyone.size() == POLICE.size() and "patrol_officer_5" in everyone, "required_contacts names the whole police role when all of it is dead")
	world.free()

func _corrupt(state: Dictionary, kind: String) -> void:
	var engine: Dictionary = state.missions.case_engine
	match kind:
		"an unknown engine field":
			engine["cheat"] = true
		"a future engine version":
			engine.version = 2
		"a record stage that disagrees with the section":
			engine.active.stage = 1
		"evidence without its objective":
			engine.active.done.erase("photograph_scene")
		"an unknown evidence id":
			engine.active.evidence[0].id = "confession"
		"a closed entry for a case the engine does not own":
			engine.closed["lost_satchel"] = "resolved"
		"a photo ring over its limit":
			for index in 70:
				engine.seen_photos.append("photo_%d" % index)
		"a bad witness binding":
			engine.active.bindings["witness"] = "Malik!"
		"a record for another case":
			engine.active.id = "dumping"
		"every officer dead with the report pending":
			state.deaths.dead = POLICE.duplicate()

# --- Contacts ------------------------------------------------------------------------

func _test_contacts() -> void:
	# Officer Dan dies before the report: a patrol officer takes it.
	var world := _world()
	world.missions.restore_state({"active_id": CASE, "stage": 3, "completed_ids": ["lost_satchel"], "score": 100})
	world.combat.kill("officer")
	var target: Vector3 = world.missions.get_status().target_position
	check(world.missions.active_id == CASE and target.distance_to(world.npcs.actor_position("patrol_officer_0")) < 0.01, "a patrol officer stands in for Officer Dan")
	_place_near(world, target)
	var state = _talk(world)
	check(state != null and str(state.current().text) == "Officer Dan's not on this beat anymore. I'll take it from here.", "the stand-in explains the handover")
	if state != null:
		state.close()
	check(_step(world, "case_report") and world.missions.completed_ids.has(CASE), "the stand-in files the report")
	world.free()
	# Every officer dead: the attempt ends without a reward and the ledger says why.
	var empty := _world()
	empty.missions.restore_state({"active_id": CASE, "stage": 3, "completed_ids": ["lost_satchel"], "score": 100})
	for id in POLICE:
		empty.combat.kill(str(id))
	var row: Dictionary = {}
	for entry in empty.missions.get_status().cases:
		if str(entry.id) == CASE:
			row = entry
	check(empty.missions.active_id.is_empty() and empty.missions.score == 100 and not empty.missions.completed_ids.has(CASE), "with no officer left the case ends unpaid")
	check(str(row.get("state", "")) == "unavailable" and str(row.get("reason", "")) == "Required contact Officer has died.", "the ledger explains the death in the original words")
	empty.free()
	# The witness is away (not dead): the case waits; custody pauses it.
	var away := _world()
	away.missions.restore_state({"active_id": CASE, "stage": 2, "completed_ids": ["lost_satchel"], "score": 100})
	var malik: Node3D = away.npcs.actors["lookout"]
	away.npcs.actors.erase("lookout")
	for _i in 3:
		away.missions.tick(0.3)
	check(away.missions.active_id == CASE and str(away.missions.get_status().objective).contains("not around right now"), "an absent witness pauses the step, not the case")
	away.npcs.actors["lookout"] = malik
	malik.set_meta("police_custody", true)
	for _i in 2:
		away.missions.tick(0.3)
	check(away.missions.active_id.is_empty() and away.missions.score == 100, "a witness taken into custody pauses the case without a reward")
	malik.set_meta("police_custody", false)
	_place_near(away, away.npcs.actor_position("resident"))
	check(_accept_parcel(away), "once the witness is free the case can be taken again")
	away.free()

# --- Continuous verbs ----------------------------------------------------------------

func _test_verbs() -> void:
	var world := _world()
	var raw := {"schema": 1, "id": "fixture_verbs", "version": 1, "status": "draft", "title": "Fixture verbs",
		"participants": {"subject": {"actors": ["ambient_mailman"], "label": "Mail carrier"}, "tipster": {"actors": ["gardener"], "label": "Gardener"}},
		"evidence": {"tail_photos": {"kind": "photo", "label": "Two photos"}},
		"discovery": {"givers": ["tipster"]},
		"stages": [
			{"id": "tail", "objectives": [{"id": "keep_distance", "verb": "follow", "subject": "subject", "min_distance": 3.0, "max_distance": 12.0, "seconds": 3.0,
				"unseen": true, "view_range": 7.5, "lose_after": 2.0, "objective": "Tail"}]},
			{"id": "photos", "objectives": [{"id": "two_photos", "verb": "photo", "subject": "subject", "count": 2, "min_interval_minutes": 1.0, "max_distance": 25.0,
				"objective": "Two photos", "grants": ["tail_photos"]}]},
			{"id": "go", "objectives": [{"id": "reach", "verb": "visit", "location": "route:30", "radius": 3.0, "dwell": 0.5, "objective": "Go"}]},
			{"id": "away", "objectives": [{"id": "get_clear", "verb": "flee", "from": "participant:subject", "distance": 20.0, "objective": "Get clear"}]}],
		"outcomes": {"resolved": {"rewarded": true, "banner": "FIXTURE"}}}
	var extra := _install(world, [raw])
	check(extra.errors.is_empty(), "verb fixture validates %s" % str(extra.errors))
	var m = world.missions
	m.cases.allow_drafts = true
	check(m.get_status().cases.size() == 6 and m.cases.offers().is_empty(), "a draft case is neither listed nor offered")
	check(m.start_case("fixture_verbs"), "draft fixture starts for tests")
	var mailman: Node3D = world.npcs.actors["ambient_mailman"]
	mailman.yaw = PI * 0.5
	# Flush newly built/freed fixture bodies before querying static sight.
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.player.global_position = mailman.global_position + Vector3(5, 0, 0)
	for _i in 2:
		m.tick(0.3)
	var follow: Dictionary = m.cases.focus_objective()
	var watched: bool = m.cases._sees_player(str(follow.subject), mailman.global_position, world.player.global_position, follow)
	check(watched and float(m.cases.active.progress.get("keep_distance", 0.0)) == 0.0 and m.stage == 0,
		"being seen in front earns no tail time (seen=%s progress=%s stage=%s yaw=%s ref=%s)" % [str(watched), str(m.cases.active.progress), str(m.stage), str(mailman.yaw), str(follow.subject)])
	world.player.global_position = mailman.global_position + Vector3(-6, 0, 0)
	for _i in 11:
		m.tick(0.3)
	check(m.stage == 1, "staying behind, unseen and in range completes the tail")
	var head: Vector3 = mailman.global_position + Vector3.UP * 1.2
	var eye := head + Vector3(-8, 0.3, 0)
	world.player.global_position = eye - Vector3.UP * 1.5
	check(not m.on_photo_captured(_photo(world, "photo_t1", eye, head, [_listed("ambient_mailman", head, eye)])).recorded.has("tail_photos") and m.stage == 1,
		"the first of two photos counts but does not finish")
	world.world_time.total_minutes = 540.5
	check(str(m.on_photo_captured(_photo(world, "photo_t2", eye, head, [_listed("ambient_mailman", head, eye)])).reason) == "too_soon", "a second photo half a minute later is too soon")
	world.world_time.total_minutes = 541.2
	check("tail_photos" in m.on_photo_captured(_photo(world, "photo_t3", eye, head, [_listed("ambient_mailman", head, eye)])).recorded and m.stage == 2,
		"two photos a minute apart complete the photo stage")
	world.player.global_position = Vector3(20, 0, -30)
	m.tick(0.3)
	check(m.stage == 2, "visit dwell is not satisfied before half a second")
	m.tick(0.3)
	check(m.stage == 3, "standing at the route point completes the visit")
	# Do not tick the later flee stage while already far away at the route.
	world.player.global_position = mailman.global_position + Vector3(5, 0, 0)
	m.tick(0.3)
	check(m.stage == 3, "being close to the subject does not satisfy flee")
	world.player.global_position = mailman.global_position + Vector3(25, 0, 0)
	for _i in 2:
		m.tick(0.3)
	check(m.active_id.is_empty() and m.completed_ids.has("fixture_verbs"), "getting clear of the subject finishes the case")
	world.free()

# --- Incidents -----------------------------------------------------------------------

func _test_incident_bridge() -> void:
	var world := _world(true)
	var raw := {"schema": 1, "id": "fixture_incident", "version": 1, "status": "ready", "title": "Fixture incident", "template": "incident_report",
		"params": {"incident_template": "jaywalking", "points": 0}}
	var extra := _install(world, [raw])
	check(extra.errors.is_empty(), "incident template fixture validates %s" % str(extra.errors))
	var m = world.missions
	var service: FakeIncidents = world.incidents
	world.player.global_position = Vector3(30, 0, 5)
	var record := {"id": "inc_000001", "template": "jaywalking", "state": "active", "at": [30.0, 0.0, 0.0],
		"participants": [{"id": "ambient_granny", "role": "offender", "kind": "contact"}],
		"witnesses": [{"id": "player", "kind": "player"}, {"id": "lookout", "kind": "contact", "via": "sight"}], "evidence": [], "report": {}, "resolution": {}}
	m.on_incident_event(record)
	check(m.active_id == "fixture_incident" and str(m.cases.active.incident_id) == "inc_000001", "a nearby matching incident starts the case bound to it")
	_place_near(world, world.npcs.actor_position("lookout"))
	var state = _talk(world)
	check(_pick(state, "case_interview") and m.stage == 1, "the incident's own witness gives the account")
	check(service.attached.size() == 1 and str(service.attached[0].evidence.kind) == "statement", "the testimony is shared with the incident service")
	service.answer = {"ok": false, "reason": "not_witnessed"}
	_place_near(world, world.npcs.actor_position("officer"))
	state = _talk(world)
	var offered := _pick(state, "case_report")
	check(offered and m.stage == 1 and service.reports.size() == 1 and str(service.reports[0].context.channel) == "case",
		"the service refuses the report (not_witnessed): the case stays at the report stage")
	check(state != null and state.active and state.node_id == "start", "a refused report keeps the conversation on its question")
	service.answer = {"ok": true, "status": "report_received", "police_incident_id": "pol_000001"}
	state = _talk(world)
	check(_pick(state, "case_report") and m.stage == 2 and _signals.report.size() > 0, "an accepted report advances to the outcome")
	record.state = "responding"
	m.on_incident_event(record)
	m.tick(0.3)
	check(m.stage == 2 and m.active_id == "fixture_incident", "the case waits while police respond")
	record.state = "resolved"
	record.resolution = {"outcome": "warned", "by": "police"}
	m.on_incident_event(record)
	m.tick(0.3)
	check(m.active_id.is_empty() and m.completed_ids.has("fixture_incident"), "the incident's resolution closes the case")
	world.free()

# A service-verified summary proves less than an authored case objective.
# Exercise the same order as the root: full photo first, incident event second.
func _incident_photo_case() -> Dictionary:
	return {"schema": 1, "id": "fixture_incident_photos", "version": 1, "status": "ready", "title": "Fixture incident photos",
		"incident": {"templates": ["jaywalking"], "radius": 60.0}, "discovery": {"trigger": "incident", "givers": []},
		"evidence": {"strict_photo": {"kind": "photo", "label": "Two checked photos"}},
		"stages": [{"id": "photos", "objectives": [{"id": "strict", "verb": "photo", "subject": "incident:offender",
			"objective": "Photograph the incident twice", "count": 2, "min_interval_minutes": 1.0,
			"min_distance": 3.0, "max_distance": 10.0, "min_centrality": 0.8, "require_tags": ["incident:inc_000077"],
			"time_window": {"from": 540.0, "to": 550.0}, "area": {"near": "pos:160,0,0", "radius": 2.0}, "grants": ["strict_photo"]}]},
			{"id": "wait", "objectives": [{"id": "resolved", "verb": "await_incident", "states": ["resolved"], "objective": "Wait"}]}]}

func _test_incident_photo_gate() -> void:
	var world := _world(true)
	var raw := _incident_photo_case()
	var extra := _install(world, [raw])
	check(extra.errors.is_empty(), "strict incident photo fixture validates %s" % str(extra.errors))
	var m = world.missions
	var service: FakeIncidents = world.incidents
	# Real ambient incident performers have no entry in the named NPC registry.
	var performer := FakeActor.new()
	world.add_child(performer)
	performer.global_position = Vector3(160, 0, 0)
	service.performers["crowd_77"] = performer
	world.player.global_position = Vector3(154, 0, 0)
	var record := {"id": "inc_000077", "template": "jaywalking", "state": "active", "at": [160.0, 0.0, 0.0],
		"participants": [{"id": "crowd_77", "role": "offender", "kind": "crowd"}], "witnesses": [], "evidence": [], "report": {}, "resolution": {}}
	m.on_incident_event(record)
	check(m.active_id == raw.id and not world.npcs.actors.has("crowd_77"), "incident photo case binds a live performer absent from the named registry")
	for reason in ["too_far", "too_close", "off_center", "missing_tags", "wrong_time", "wrong_place"]:
		performer.global_position = Vector3(170, 0, 0) if reason == "wrong_place" else Vector3(160, 0, 0)
		world.world_time.total_minutes = 551.0 if reason == "wrong_time" else 540.0
		var point: Vector3 = performer.global_position + Vector3.UP * 1.2
		var distance := 30.0 if reason == "too_far" else (1.0 if reason == "too_close" else 6.0)
		var eye := point - Vector3.RIGHT * distance
		var look := point + Vector3(0, 0, 4) if reason == "off_center" else point
		var listed := _listed("crowd_77", point, eye)
		listed.tags = [] if reason == "missing_tags" else ["incident:inc_000077"]
		var photo_id := "strict_" + str(reason)
		var result: Dictionary = m.on_photo_captured(_photo(world, photo_id, eye, look, [listed]))
		check(str(result.reason) == reason and m.stage == 0 and m.cases.active.photos.is_empty(), "full context rejects incident photo: " + str(reason))
		record.evidence.append({"kind": "photo", "by": "player", "subject_id": "crowd_77", "verified": true,
			"ref": photo_id, "minutes": float(world.world_time.total_minutes)})
		m.on_incident_event(record)
		check(m.stage == 0 and m.cases.active.photos.is_empty() and not m.cases.holds("strict_photo"), "verified summary cannot override " + str(reason))
	performer.global_position = Vector3(160, 0, 0)
	world.world_time.total_minutes = 540.0
	var point := performer.global_position + Vector3.UP * 1.2
	var eye := point - Vector3.RIGHT * 6.0
	var listed := _listed("crowd_77", point, eye)
	listed.tags = ["incident:inc_000077"]
	var first: Dictionary = m.on_photo_captured(_photo(world, "strict_first", eye, point, [listed]))
	check(first.objectives == ["strict"] and first.recorded.is_empty() and m.cases.active.photos.strict == ["strict_first"],
		"full valid context of a live crowd performer counts exactly once")
	world.world_time.total_minutes = 540.5
	var soon: Dictionary = m.on_photo_captured(_photo(world, "strict_soon", eye, point, [listed]))
	check(str(soon.reason) == "too_soon" and m.cases.active.photos.strict == ["strict_first"], "direct incident photo respects the authored interval")
	record.evidence = [{"kind": "photo", "by": "player", "subject_id": "crowd_77", "verified": true, "ref": "strict_first", "minutes": 540.0},
		{"kind": "photo", "by": "player", "subject_id": "crowd_77", "verified": true, "ref": "strict_soon", "minutes": 540.5}]
	for _i in 2:
		m.on_incident_event(record)
	check(m.stage == 0 and m.cases.active.photos.strict == ["strict_first"] and not m.cases.holds("strict_photo"),
		"repeated incident summaries cannot credit an immediate second photo or duplicate the first")
	world.world_time.total_minutes = 541.2
	var final_photo: Dictionary = m.on_photo_captured(_photo(world, "strict_final", eye, point, [listed]))
	check("strict_photo" in final_photo.recorded and m.stage == 1 and m.cases.active.photos.strict == ["strict_first", "strict_final"],
		"two fully checked captures a minute apart complete the incident photo objective")
	world.free()
