extends Node
## "Petal Pushers" chain, durable choices/relationships and bounded errands,
## driven through the real CityMissions, city_progression and
## city_dialogue_state. Small fakes stand in for the world (contacts, combat
## deaths, clock, shop counter). Every player verb goes through the mission
## conversation and a reply choice, routed exactly like the level's
## conversation_condition/conversation_hook; direct commits appear only where a
## stale or duplicated callback is the behavior under test.
const Progression := preload("res://scripts/city/city_progression.gd")
const Missions := preload("res://scripts/city/city_missions.gd")
const DialogueState := preload("res://scripts/city/city_dialogue_state.gd")
const VENDOR := "daily_ines_morales"
const BRANCHES := ["report", "protect", "negotiate", "intimidate"]
const POLICE := ["officer", "patrol_officer_0", "patrol_officer_1", "patrol_officer_2", "patrol_officer_3", "patrol_officer_4", "patrol_officer_5"]
const SPOTS := {
	VENDOR: Vector3(0, 0, 0), "lookout": Vector3(20, 0, 0), "officer": Vector3(40, 0, 0), "organizer": Vector3(60, 0, 0),
	"patrol_officer_0": Vector3(80, 0, 0), "patrol_officer_1": Vector3(100, 0, 0), "ambient_neighbor": Vector3(120, 0, 0),
	"ambient_granny": Vector3(140, 0, 0), "ambient_mailman": Vector3(0, 0, 40), "resident": Vector3(20, 0, 40),
	"gardener": Vector3(40, 0, 40), "caretaker": Vector3(60, 0, 40), "daily_nadine_brooks": Vector3(80, 0, 40),
	"daily_celia_grant": Vector3(100, 0, 40), "daily_ruth_daniels": Vector3(120, 0, 40), "daily_theo_washington": Vector3(140, 0, 40),
	"daily_june_harris": Vector3(160, 0, 40), "daily_pearl_sutton": Vector3(180, 0, 40), "daily_aisha_bell": Vector3(200, 0, 40),
}
const LABELS := {VENDOR: "Ines Morales", "lookout": "Malik · Witness", "officer": "Officer Dan", "organizer": "Block organizer",
	"patrol_officer_0": "Patrol officer", "patrol_officer_1": "Patrol officer", "ambient_mailman": "Mail carrier",
	"resident": "Ms. Lena · Resident", "gardener": "Community gardener", "caretaker": "Porch caretaker"}

class FakeActor extends Node3D:
	var actor_id := ""
	var display_name := "Neighbor"
	var enabled := true
	var dead := false
	var last_line := ""
	var lines_spoken := 0
	func speak(text: String, _seconds := 4.0) -> void:
		last_line = text
		lines_spoken += 1

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
		return actor.global_position if actor != null and not actor.get_meta("city_dead", false) else Vector3.INF
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
	var health := 100.0
	var downed := 0.0
	var weapon := "fists"
	var equipment := {"fists": {"owned": true, "ammo": 0, "reserve": 0}, "pistol": {"owned": true, "ammo": 12, "reserve": 0},
		"uzi": {"owned": false, "ammo": 0, "reserve": 0}, "ak47": {"owned": false, "ammo": 0, "reserve": 0}}
	func is_actor_dead(id: String) -> bool:
		return dead.has(id)
	## announce=false mimics restore_deaths, which marks actors without a signal.
	func kill(id: String, announce := true) -> void:
		dead[id] = true
		var actor = npcs.get_actor(id)
		if actor != null:
			actor.dead = true
			actor.enabled = false
			actor.set_meta("city_dead", true)
		if announce:
			actor_died.emit(id)
	func grant_weapon(id: String) -> bool:
		if not equipment.has(id) or bool(equipment[id].owned):
			return false
		equipment[id].owned = true
		equipment[id].ammo = 12
		return true
	func add_ammo(id: String, count: int) -> int:
		if id == "fists" or not equipment.has(id) or count <= 0:
			return 0
		equipment[id].reserve = int(equipment[id].reserve) + count
		return count
	func equipment_snapshot() -> Dictionary:
		return {"version": 1, "equipped": weapon, "weapons": equipment.duplicate(true)}
	func validate_equipment(data: Dictionary) -> bool:
		return data.get("weapons") is Dictionary
	func restore_equipment(data: Dictionary) -> bool:
		equipment = data.weapons.duplicate(true)
		return true
	func get_status() -> Dictionary:
		return {"aggro_count": 0, "active_count": 0, "downed": downed, "health": health}

class FakeClock extends Node:
	var total_minutes := 540.0
	var elapsed_seconds := 1000.0

class FakeShops extends Node:
	func is_open() -> bool:
		return true

class FakeResidents extends Node:
	var routes: Dictionary = {}

class FakePlayer extends CharacterBody3D:
	var yaw := 0.0

class FakeLevel extends Node3D:
	var paused := false
	var player: CharacterBody3D
	var combat: Node
	var progression: Node
	var missions: Node3D
	var npcs: Node3D
	var residents: Node
	var world_time: Node
	var shops: Node
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

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(120.0, true, false, true).timeout
	if not _finished:
		check(false, "watchdog: narrative tests did not finish within 120 seconds")
		_finish()

func check(ok: bool, label: String) -> bool:
	print("[city_narrative] %s %s" % ["PASS" if ok else "FAIL", label])
	if ok:
		passes += 1
	else:
		failures += 1
	return ok

func _run() -> void:
	await get_tree().physics_frame
	_test_contract()
	_test_discovery()
	_test_branches()
	_test_persistence()
	_test_duplicates()
	_test_deaths()
	_test_errands()
	_test_reactions()
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[city_narrative] passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

# --- Fixture -------------------------------------------------------------------------

func _world() -> FakeLevel:
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
	var shops := FakeShops.new()
	world.add_child(shops)
	world.shops = shops
	var residents := FakeResidents.new()
	residents.routes = {VENDOR: {"points": [Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(6, 0, 0)], "anchors": {"home": 0, "work": 2, "leisure": 1}}}
	world.add_child(residents)
	world.residents = residents
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
	return world

func _round_trip(value: Dictionary) -> Dictionary:
	var parsed = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}

## The two sections a checkpoint carries for this feature, through JSON.
func _snapshot(world: FakeLevel) -> Dictionary:
	return _round_trip({"missions": world.missions.snapshot_state(), "progression": world.progression.snapshot_state(),
		"deaths": {"version": 1, "dead": world.combat.dead.keys()}})

## Same order as the world-save provider: clock, progression, then missions.
func _reload(saved: Dictionary, elapsed: float = 1000.0) -> FakeLevel:
	var world := _world()
	world.world_time.elapsed_seconds = elapsed
	var progress_ok: bool = world.progression.restore_state(saved.progression)
	var missions_ok: bool = world.missions.restore_state(saved.missions)
	check(progress_ok and missions_ok, "reload restores progression then missions")
	return world

# --- Player verbs (conversation + reply, as the level routes E) ------------------------

func _place_near(world: FakeLevel, target: Vector3) -> void:
	world.player.global_position = target + Vector3(1.2, 0, 0)

func _talk(world: FakeLevel):
	var graph: Dictionary = world.missions.conversation_preview()
	if graph.is_empty():
		return null
	var role: String = world.progression.role_for_actor(str(graph.get("actor_id", "")))
	var state = DialogueState.new()
	if not state.open(world.progression.decorate_conversation(graph, role), Callable(world, "conversation_condition"), Callable(world, "conversation_hook")):
		return null
	return state

func _pick(state, wanted: Callable) -> bool:
	if state == null:
		return false
	for _i in 8:
		if not state.choices().is_empty():
			break
		state.advance()
	var replies: Array = state.choices()
	for index in replies.size():
		if bool(wanted.call(replies[index])):
			state.choose(index)
			return true
	return false

func _hook(kind: String, id: String = "") -> Callable:
	return func(reply: Dictionary) -> bool:
		var hook: Dictionary = reply.get("hook", {})
		return str(hook.get("kind", "")) == kind and (id.is_empty() or str(hook.get("id", "")) == id)

func _option(option: String) -> Callable:
	return func(reply: Dictionary) -> bool:
		var hook: Dictionary = reply.get("hook", {})
		return str(hook.get("choice", "")) == option

func _texts(state) -> Array:
	var texts: Array = []
	if state == null:
		return texts
	for _i in 8:
		if not state.choices().is_empty():
			break
		state.advance()
	for reply in state.choices():
		texts.append(str(reply.get("text", "")))
	return texts

## Walk to the current destination, press E, pick the step (or decision) reply.
func _step(world: FakeLevel, option: String = "") -> bool:
	var missions = world.missions
	var status: Dictionary = missions.get_status()
	var before_id := str(status.active_id)
	var before_stage := int(status.stage)
	if before_id.is_empty():
		return false
	_place_near(world, status.target_position)
	var state = _talk(world)
	var chosen := _pick(state, _option(option) if not option.is_empty() else _hook("case_step"))
	return chosen and (str(missions.active_id) != before_id or int(missions.stage) == before_stage + 1)

func _accept(world: FakeLevel, actor_id: String, kind: String, id: String) -> bool:
	_place_near(world, world.npcs.actor_position(actor_id))
	var state = _talk(world)
	return _pick(state, _hook(kind, id)) and str(world.missions.active_id) == id

func _finish_part(world: FakeLevel, option: String = "") -> bool:
	var id := str(world.missions.active_id)
	for _i in 6:
		if str(world.missions.active_id) != id:
			return true
		var current: Dictionary = world.missions._steps[int(world.missions.stage)]
		if not _step(world, option if current.has("decision") else ""):
			return false
	return str(world.missions.active_id) != id

func _part_one(world: FakeLevel, branch: String) -> bool:
	return _accept(world, VENDOR, "story_start", "petals_word") and _step(world) and _step(world) and _step(world, branch)

func _row(world: FakeLevel, id: String) -> Dictionary:
	for entry in world.missions.get_status().story:
		if str(entry.id) == id:
			return entry
	return {}

func _ines_chat(world: FakeLevel) -> Array:
	var chat := {"actor_id": VENDOR, "start": "hello", "nodes": {"hello": {"speaker": "Ines Morales",
		"lines": ["I save the sunflowers for the people who need a bright spot."], "choices": [{"text": "See you around."}]}}}
	return world.progression.decorate_conversation(chat, world.progression.role_for_actor(VENDOR)).nodes.hello.lines

# --- Tests ---------------------------------------------------------------------------

func _test_contract() -> void:
	var world := _world()
	var p = world.progression
	var m = world.missions
	check(p.enabled and p.config_errors.is_empty(), "shipped config with relationships, decisions, errands and reactions validates %s" % str(p.config_errors))
	var schema: Dictionary = m.save_schema()
	check(schema.keys().slice(0, 6) == ["lost_satchel", "parcel_report", "dumping", "missing_tools", "torn_notice", "porch_light"],
		"save schema keeps the six original cases first and in order")
	check(str(schema.petals_word.kind) == "story" and str(schema.errand_delivery.kind) == "errand" and str(schema.lost_satchel.kind) == "case",
		"story parts and errands are checkpoint ids with kinds")
	var status: Dictionary = m.get_status()
	check(int(status.total) == 6 and status.cases.size() == 6 and not bool(status.all_complete) and int(status.completed) == 0,
		"the original six-case ledger and counts are unchanged")
	_place_near(world, world.npcs.actor_position("resident"))
	var offer: Dictionary = m.conversation_preview()
	var replies: Array = offer.get("nodes", {}).get("start", {}).get("choices", [])
	check(replies.size() == 2 and str(replies[0].get("hook", {}).get("id", "")) == "lost_satchel" and str(replies[1].text) == "Maybe later.",
		"an original case offer keeps exactly [accept, Maybe later]")
	var old_active: bool = m.restore_state({"active_id": "parcel_report", "stage": 2, "completed_ids": ["lost_satchel"], "score": 100})
	check(old_active and m.active_id == "parcel_report" and m.stage == 2 and m.score == 100, "an old active case still restores at its saved stage")
	world.free()

func _test_discovery() -> void:
	var world := _world()
	var m = world.missions
	check(m.conversation_preview().is_empty() and str(m.get_status().prompt).is_empty(), "far from every contact nothing is offered")
	_place_near(world, world.npcs.actor_position(VENDOR))
	check(m.nearby_offer().is_empty() and str(m.get_status().prompt) == "E  Talk about the flower cart complaint",
		"walking up to Ines shows the story prompt through mission status")
	var state = _talk(world)
	check(state != null and str(state.current().speaker) == "Ines Morales" and m.active_id.is_empty(), "E opens Ines's offer without starting anything")
	if state != null:
		state.close()
	check(m.active_id.is_empty() and m.completed_ids.is_empty(), "leaving the offer starts nothing")
	_place_near(world, world.npcs.actor_position("lookout"))
	check(str(m.get_status().prompt) == "E  Talk about keep the sidewalk clear", "an original case offer keeps priority at a shared contact")
	m.completed_ids["dumping"] = true
	check(str(m.get_status().prompt) == "E  Talk about the flower cart complaint", "once Malik's case is done he points at the cart complaint too")
	m.completed_ids.erase("dumping")
	check(_accept(world, VENDOR, "story_start", "petals_word") and m.stage == 0, "accepting the reply starts part 1 at its first step")
	var status: Dictionary = m.get_status()
	check(str(status.title).begins_with("Petal Pushers 1/3") and Vector3(status.target_position).distance_to(world.npcs.actor_position(VENDOR)) < 0.01,
		"HUD title and destination follow the active part")
	check(str(_row(world, "petals_word").state) == "active" and str(_row(world, "petals_word").reason).begins_with("Step 1 of 3"), "the story ledger reports the active step")
	world.free()

func _test_branches() -> void:
	var outcomes := {}
	var endings := {"report": "report_firm", "protect": "protect_firm", "negotiate": "negotiate_amends", "intimidate": "intimidate_firm"}
	for branch in BRANCHES:
		var world := _world()
		var p = world.progression
		var m = world.missions
		var cash: int = p.money
		var fresh_chat: String = str(_ines_chat(world)[0])
		var decided := _part_one(world, branch)
		check(decided and p.choice_of("petals_call") == branch and str(m.active_id) == "petals_" + branch,
			"%s: the decision is durable and part 2 starts on its own branch" % branch)
		var refused := true
		for other in BRANCHES:
			if other != branch:
				refused = refused and not m.start_case("petals_" + str(other))
		check(refused and str(m.active_id) == "petals_" + branch, "%s: other branches cannot start and do not disturb the active part" % branch)
		var decision_cash: int = p.money - cash
		var decided_chat: String = str(_ines_chat(world)[0])
		check(_finish_part(world), "%s: part 2 completes through its contacts" % branch)
		_place_near(world, world.npcs.actor_position(VENDOR))
		check(str(m.get_status().prompt) != "" and _accept(world, VENDOR, "story_start", "petals_end_" + branch), "%s: Ines offers part 3 afterwards" % branch)
		check(_finish_part(world, str(endings[branch])), "%s: the final decision ends the story" % branch)
		check(p.choice_of("petals_final") == str(endings[branch]) and m.completed_ids.has("petals_end_" + branch) and m.active_id.is_empty(),
			"%s: the ending is recorded" % branch)
		m.tick(1.1)
		var chat: Array = _ines_chat(world)
		check(chat[-1] == "I save the sunflowers for the people who need a bright spot." and str(chat[0]) != decided_chat and decided_chat != fresh_chat,
			"%s: Ines's own conversation changes after the decision and again after the ending, authored line intact" % branch)
		outcomes[branch] = {"snitch": p.reputation_value("snitch"), "gangsta": p.reputation_value("gangsta"), "ines": p.relationship_value("ines"),
			"dan": p.relationship_value("dan"), "cash": p.money - cash, "decision_cash": decision_cash, "score": m.score,
			"line": str(chat[0]), "sign": m.narrative.sign_text(), "ending": str(_row(world, "petals_ending").get("title", ""))}
		world.free()
	var report: Dictionary = outcomes.report
	var protect: Dictionary = outcomes.protect
	var negotiate: Dictionary = outcomes.negotiate
	var intimidate: Dictionary = outcomes.intimidate
	check(int(report.snitch) > 0 and int(report.gangsta) == 0 and int(protect.gangsta) > 0 and int(protect.snitch) == 0,
		"reporting builds only Snitch and protecting builds only Gangsta")
	check(int(negotiate.snitch) > 0 and int(negotiate.gangsta) > 0 and int(intimidate.gangsta) > int(protect.gangsta),
		"negotiating moves both tracks a little; intimidating builds the most Gangsta")
	check(int(report.dan) > 0 and int(report.ines) < 0 and int(protect.ines) > 0 and int(protect.dan) < 0,
		"report and protect move Officer Dan and Ines in opposite directions")
	check(int(negotiate.ines) > 0 and int(negotiate.dan) > 0 and int(intimidate.ines) < 0, "negotiation keeps both sides; intimidation costs Ines's trust")
	check(int(intimidate.decision_cash) > 0 and int(report.decision_cash) == 0 and int(intimidate.cash) > int(protect.cash),
		"only the shakedown pays at the decision, and it pays the most overall")
	check(int(report.score) > 0 and int(negotiate.score) > 0 and int(protect.score) == 0 and int(intimidate.score) == 0,
		"only community-minded branches add community points")
	var lines := {}
	var signs := {}
	var titles := {}
	for branch in BRANCHES:
		lines[str(outcomes[branch].line)] = true
		signs[str(outcomes[branch].sign)] = true
		titles[str(outcomes[branch].ending)] = true
	check(lines.size() == 4 and signs.size() == 4 and titles.size() == 4, "each ending leaves a distinct Ines line, cart sign and ledger ending")

func _test_persistence() -> void:
	var world := _world()
	_part_one(world, "negotiate")
	check(_step(world), "negotiate: the organizer hands over the permit form")
	var saved := _snapshot(world)
	check(world.missions.validate_state(saved.missions, saved).is_empty(), "a mid-part checkpoint validates against its own progression and deaths")
	var reloaded := _reload(saved)
	var r = reloaded.progression
	check(reloaded.missions.active_id == "petals_negotiate" and reloaded.missions.stage == 1 and r.choice_of("petals_call") == "negotiate",
		"branch, part and stage survive a reload")
	check(r.relationship_value("ines") == world.progression.relationship_value("ines") and r.relationship_value("dan") > 0,
		"relationships survive a reload")
	check(JSON.stringify(r.snapshot_state()) == JSON.stringify(world.progression.snapshot_state()), "restored progression reproduces the same snapshot")
	var before: int = r.money
	var score_before: int = reloaded.missions.score
	check(_finish_part(reloaded), "the reloaded part finishes from its saved stage")
	var paid: int = r.money - before
	check(paid > 0 and reloaded.missions.score > score_before and not r.reward_case("petals_negotiate", 60) and r.money == before + paid,
		"the reloaded part pays once and its reward cannot replay")
	var finished := _snapshot(reloaded)
	var again := _reload(finished)
	check(not again.missions.start_case("petals_negotiate") and again.progression.money == r.money, "a checkpoint after the part never pays or restarts it")
	_place_near(again, again.npcs.actor_position(VENDOR))
	check(_accept(again, VENDOR, "story_start", "petals_end_negotiate"), "after reload Ines offers the matching part 3")
	again.free()
	# Version 1 progression snapshots (before relationships existed) still load.
	var v1: Dictionary = _round_trip(world.progression.snapshot_state())
	for key in ["relationships", "choices", "errands"]:
		v1.erase(key)
	v1.version = 1
	var legacy := _world()
	var lp = legacy.progression
	check(lp.validate_state(v1).is_empty() and lp.restore_state(v1), "a version 1 progression snapshot still validates and restores")
	check(lp.relationship_value("ines") == 0 and lp.choice_of("petals_call").is_empty() and bool(lp.errand_status().ready) and int(lp.snapshot_state().version) == 2,
		"version 1 gets neutral relationships, no choices, a ready errand and is rewritten as version 2")
	legacy.free()
	# Strict v2 schema: every corruption is refused without touching state.
	var good: Dictionary = _round_trip(world.progression.snapshot_state())
	var guard := _world()
	var q = guard.progression
	var baseline := JSON.stringify(q.snapshot_state())
	for kind in ["unknown contact", "relationship above max", "fractional relationship", "unknown decision", "unknown option",
			"ending without its first choice", "ending from another branch", "errand record missing a field", "negative errand ready time",
			"errand earnings not whole", "v2 fields under version 1", "future version"]:
		var broken: Dictionary = good.duplicate(true)
		_corrupt(broken, kind)
		var reason: String = q.validate_state(broken)
		check(not reason.is_empty() and not q.restore_state(broken) and JSON.stringify(q.snapshot_state()) == baseline,
			"rejects %s (%s) without changing state" % [kind, reason])
	guard.free()
	# Cross-section checks a world-save provider can run before applying anything.
	var m = world.missions
	var base := _snapshot(world)
	var cases := {"a decided part without its saved choice": "no_choice", "another branch's part recorded": "crossed",
		"an errand recorded as completed": "farmed", "part 3 active before part 2": "skipped", "every police stand-in dead": "no_police",
		"Ines dead with her steps remaining": "no_vendor"}
	for label in cases:
		var bad: Dictionary = base.duplicate(true)
		match str(cases[label]):
			"no_choice":
				bad.progression.choices = {}
			"crossed":
				bad.missions.completed_ids.append("petals_protect")
			"farmed":
				bad.missions.completed_ids.append("errand_delivery")
			"skipped":
				bad.missions.active_id = "petals_end_negotiate"
				bad.missions.stage = 0
			"no_police":
				bad.deaths.dead = POLICE.duplicate()
			"no_vendor":
				bad.deaths.dead = [VENDOR]
		check(not m.validate_state(bad.missions, bad).is_empty(), "mission validation rejects " + str(label))
	var stand_in: Dictionary = base.duplicate(true)
	stand_in.deaths.dead = ["officer"]
	check(m.validate_state(stand_in.missions, stand_in).is_empty(), "a dead Officer Dan alone is fine: a stand-in can take his steps")
	var orphan := _world()
	var dropped: bool = orphan.missions.restore_state({"active_id": "", "stage": 0, "completed_ids": ["lost_satchel", "petals_word"], "score": 100})
	check(not dropped and orphan.missions.completed_ids.has("lost_satchel") and not orphan.missions.completed_ids.has("petals_word") and orphan.missions.score == 100,
		"a story part without its saved choice is dropped and reported; old cases are kept")
	orphan.free()
	reloaded.free()
	world.free()

func _corrupt(state: Dictionary, kind: String) -> void:
	match kind:
		"unknown contact":
			state.relationships["karma"] = 5
		"relationship above max":
			state.relationships["ines"] = 101
		"fractional relationship":
			state.relationships["dan"] = 2.5
		"unknown decision":
			state.choices["petals_bonus"] = "report"
		"unknown option":
			state.choices["petals_call"] = "bribe"
		"ending without its first choice":
			state.choices.erase("petals_call")
			state.choices["petals_final"] = "report_firm"
		"ending from another branch":
			state.choices["petals_final"] = "report_firm"
		"errand record missing a field":
			state.errands.erase("earned")
		"negative errand ready time":
			state.errands.ready_at = -5
		"errand earnings not whole":
			state.errands.earned = 4.5
		"v2 fields under version 1":
			state.version = 1
		"future version":
			state.version = 3

func _test_duplicates() -> void:
	var world := _world()
	var p = world.progression
	var m = world.missions
	_accept(world, VENDOR, "story_start", "petals_word")
	_step(world)
	_step(world)
	var at_decision: int = m.stage
	_place_near(world, world.npcs.actor_position(VENDOR))
	check(not m.interact() and m.stage == at_decision and p.choice_of("petals_call").is_empty(), "a plain E/interact cannot skip a decision step")
	var state = _talk(world)
	var offered := _texts(state)
	check(offered.size() == 5 and "I need to think it over." in offered, "the decision offers four concrete moves plus walking away")
	state = _talk(world)
	_pick(state, func(reply: Dictionary) -> bool: return not reply.has("hook"))
	check(m.stage == at_decision and p.choice_of("petals_call").is_empty(), "walking away from the decision commits nothing")
	check(_step(world, "report"), "the report reply commits")
	var cash: int = p.money
	var snitch: int = p.reputation_value("snitch")
	var switched := {"kind": "case_step", "id": "petals_word", "stage": 2, "choice": "protect"}
	check(not m.commit_dialogue_action(switched) and p.choice_of("petals_call") == "report" and p.money == cash and p.reputation_value("snitch") == snitch,
		"a replayed or switched decision callback changes nothing")
	check(not bool(p.commit_choice("petals_call", "protect").ok) and p.choice_of("petals_call") == "report", "progression refuses a second option for a settled decision")
	check(not m.start_case("petals_word") and str(m.active_id) == "petals_report", "a finished part cannot start again")
	check(_finish_part(world), "the report part finishes")
	var after: int = p.money
	check(not p.reward_case("petals_report", 90) and p.money == after, "a story part reward pays once")
	check(not m.commit_dialogue_action({"kind": "case_step", "id": "petals_report", "stage": 1}) and p.money == after, "a stale step callback after completion is refused")
	check(not m.commit_dialogue_action({"kind": "story_start", "id": "petals_report"}) and m.active_id.is_empty(), "a stale start reply for a finished part is refused")
	world.free()

func _test_deaths() -> void:
	# Officer Dan dies mid-report: the first living patrol officer takes it.
	var world := _world()
	var m = world.missions
	_part_one(world, "report")
	world.combat.kill("officer")
	var target: Vector3 = m.get_status().target_position
	check(m.active_id == "petals_report" and target.distance_to(world.npcs.actor_position("patrol_officer_0")) < 0.01,
		"a patrol officer takes the report after Officer Dan dies")
	check(bool(world.npcs.get_actor("officer").dead) and not world.npcs.actor_position("officer").is_finite(), "Officer Dan stays dead")
	_place_near(world, target)
	var state = _talk(world)
	check(state != null and str(state.current().text) == "Officer Dan's not on this beat anymore. I'll take it from here." and str(state.current().speaker) == "Patrol officer",
		"the stand-in explains the handover in its own voice")
	if state != null:
		state.close()
	check(_finish_part(world) and m.completed_ids.has("petals_report"), "the report finishes with the stand-in")
	world.free()
	# Malik dies before the story: the corner still talks through a neighbor.
	var corner := _world()
	corner.combat.kill("lookout")
	_accept(corner, VENDOR, "story_start", "petals_word")
	_step(corner)
	check(Vector3(corner.missions.get_status().target_position).distance_to(corner.npcs.actor_position("ambient_neighbor")) < 0.01,
		"with Malik gone the corner step goes to a neighbor")
	corner.free()
	# No police identity left alive: the part closes the chain, unpaid.
	var empty := _world()
	_part_one(empty, "report")
	var score: int = empty.missions.score
	for id in POLICE:
		empty.combat.kill(str(id))
	check(empty.missions.active_id.is_empty() and empty.progression.meets("flag:petals_closed") and empty.missions.score == score
		and not empty.missions.completed_ids.has("petals_report"), "with every officer dead the chain closes without a reward")
	check(str(_row(empty, "petals_report").state) == "closed", "the ledger explains the closed chain")
	empty.free()
	# Absent (not dead) stand-ins put the part on hold; it restarts later.
	var hold := _world()
	_part_one(hold, "report")
	for id in ["officer", "patrol_officer_0", "patrol_officer_1"]:
		hold.combat.kill(id)
	check(hold.missions.active_id.is_empty() and not hold.progression.meets("flag:petals_closed") and str(_row(hold, "petals_report").state) == "unavailable",
		"with the remaining officers merely absent the part waits instead of closing")
	hold.npcs.add("patrol_officer_2", "Patrol officer", Vector3(220, 0, 0))
	_place_near(hold, hold.npcs.actor_position(VENDOR))
	check(_accept(hold, VENDOR, "story_start", "petals_report") and hold.missions.stage == 0, "when an officer is around again Ines restarts the part")
	hold.free()
	# Ines dies before the story starts: closed quietly, nobody revived.
	var gone := _world()
	gone.combat.kill(VENDOR)
	gone.missions.tick(1.1)
	_place_near(gone, SPOTS[VENDOR])
	check(gone.progression.meets("flag:petals_closed") and gone.missions.conversation_preview().is_empty() and str(_row(gone, "petals_word").state) == "closed",
		"with Ines dead the story is closed and nothing is offered")
	check(gone.missions.narrative.sign_text().ends_with("CLOSED") and not bool(gone.npcs.get_actor(VENDOR).enabled) and bool(gone.npcs.get_actor(VENDOR).dead),
		"the cart sign shows closed and Ines is never revived")
	check(not bool(gone.progression.errand_status("flowers").unlocked), "Ines's flower deliveries never unlock after her death")
	gone.free()
	# Deaths restored after the mission state (restore order) resolve on tick.
	var before := _world()
	_part_one(before, "report")
	var saved := _snapshot(before)
	before.free()
	var later := _reload(saved)
	later.combat.kill("officer", false)
	later.missions.tick(1.1)
	check(later.missions.active_id == "petals_report" and Vector3(later.missions.get_status().target_position).distance_to(later.npcs.actor_position("patrol_officer_0")) < 0.01,
		"a death restored after the missions section hands the step to a stand-in")
	later.free()

func _deliver(world: FakeLevel) -> int:
	var carrier: String = world.missions.narrative.resolve("@carrier")
	if not _accept(world, carrier, "errand_start", "errand_delivery"):
		return 0
	var before: int = world.progression.money
	if not _step(world):
		return 0
	return world.progression.money - before

func _test_errands() -> void:
	var world := _world()
	var p = world.progression
	var m = world.missions
	p.debit(p.money, "fixture: broke")
	world.combat.equipment.pistol.owned = false
	check(p.money == 0 and not p.purchase("pistol").ok, "a broke player cannot buy a weapon")
	var cap: int = int(p.config.errands.max_payout)
	var runs := 0
	var bounded := true
	while p.money < 280 and runs < 12:
		var paid := _deliver(world)
		if paid <= 0:
			break
		bounded = bounded and paid <= cap
		runs += 1
		_place_near(world, world.npcs.actor_position(m.narrative.resolve("@carrier")))
		check(str(m.get_status().prompt).is_empty() and not bool(p.pay_errand("delivery", p.errand_runs).ok), "run %d: the cooldown hides the offer and refuses an early payout" % runs)
		world.world_time.elapsed_seconds += float(p.config.errands.cooldown) + 1.0
	check(p.money >= 280 and bounded and runs > 1, "repeatable deliveries lift a broke player to a pistol and ammo (%d runs, never above the payout cap)" % runs)
	check(p.purchase("pistol").ok and p.purchase("ammo_pistol").ok, "errand money buys the pistol and its ammunition")
	check(not m.completed_ids.has("errand_delivery") and not "errand_delivery" in m.snapshot_state().completed_ids and int(p.errand_runs) == runs,
		"errands repeat and are never recorded as completed cases")
	check(not bool(p.pay_errand("delivery", p.errand_runs - 1).ok), "a stale run number never pays")
	# Save mid-errand, reload, deliver: paid exactly once.
	var carrier: String = m.narrative.resolve("@carrier")
	_accept(world, carrier, "errand_start", "errand_delivery")
	var saved := _snapshot(world)
	var reloaded := _reload(saved, float(world.world_time.elapsed_seconds))
	check(reloaded.missions.active_id == "errand_delivery", "an active errand survives a reload")
	var before: int = reloaded.progression.money
	check(_step(reloaded) and reloaded.progression.money > before and reloaded.missions.active_id.is_empty(), "the reloaded errand pays on delivery")
	var paid_once: int = reloaded.progression.money
	check(not reloaded.missions.commit_dialogue_action({"kind": "case_step", "id": "errand_delivery", "stage": 0}) and reloaded.progression.money == paid_once,
		"a replayed delivery callback pays nothing")
	# The cooldown is durable and never longer than one cooldown.
	var cooling := _snapshot(reloaded)
	var resumed := _reload(cooling, float(reloaded.world_time.elapsed_seconds))
	check(not bool(resumed.progression.errand_status().ready), "the errand cooldown survives a reload")
	var skewed := _reload(cooling, 0.0)
	skewed.progression.tick(0.1)
	var wait: int = int(skewed.progression.errand_status().seconds_left)
	skewed.world_time.elapsed_seconds = float(wait) + 1.0
	check(wait <= int(skewed.progression.config.errands.cooldown) and bool(skewed.progression.errand_status().ready),
		"a clock that went backwards waits at most one cooldown")
	resumed.free()
	skewed.free()
	reloaded.free()
	world.free()
	# Story outcomes open better-paying errands with the people they helped.
	var friend := _world()
	_part_one(friend, "protect")
	_finish_part(friend)
	var fp = friend.progression
	check(bool(fp.errand_status("flowers").unlocked) and bool(fp.errand_status("corner").unlocked) and not bool(fp.errand_status("watch").unlocked),
		"protecting Ines opens her flower deliveries and Malik's soda runs, not Officer Dan's watch walk")
	check(int(fp.errand_status("flowers").payout) > int(fp.errand_status("delivery").payout), "the unlocked job pays more than the base delivery")
	var cash: int = fp.money
	check(_accept(friend, VENDOR, "errand_start", "errand_flowers") and _step(friend) and fp.money - cash == int(fp.errand_status("flowers").payout),
		"Ines's flower delivery is offered beside part 3 and pays its own rate")
	# Ines dies with a bouquet in hand: the chain closes, the delivery does not,
	# and a checkpoint taken now still restores and pays once.
	friend.world_time.elapsed_seconds += float(fp.config.errands.cooldown) + 1.0
	_accept(friend, VENDOR, "errand_start", "errand_flowers")
	friend.combat.kill(VENDOR)
	check(friend.missions.active_id == "errand_flowers" and fp.meets("flag:petals_closed"), "Ines's death closes the chain but not the delivery already started")
	var mid := _snapshot(friend)
	check(friend.missions.validate_state(mid.missions, mid).is_empty(), "that checkpoint validates with Ines in the death registry")
	var carried := _reload(mid, float(friend.world_time.elapsed_seconds))
	carried.combat.kill(VENDOR, false)
	var carried_cash: int = carried.progression.money
	check(carried.missions.active_id == "errand_flowers" and _step(carried) and carried.progression.money > carried_cash and carried.missions.active_id.is_empty(),
		"the started delivery restores although its unlock lapsed, and pays once")
	carried.free()
	friend.free()
	var snitch := _world()
	_part_one(snitch, "report")
	_finish_part(snitch)
	var sp = snitch.progression
	check(bool(sp.errand_status("watch").unlocked) and not bool(sp.errand_status("flowers").unlocked), "reporting opens the watch walk and closes Ines's jobs")
	var watch_cash: int = sp.money
	var officer: String = snitch.missions.narrative.resolve("@police")
	check(_accept(snitch, officer, "errand_start", "errand_watch") and _step(snitch) and _step(snitch) and sp.money > watch_cash,
		"the watch walk sends 2-Pack to a checkpoint and back for its stipend")
	snitch.free()

func _test_reactions() -> void:
	var world := _world()
	var m = world.missions
	var malik: FakeActor = world.npcs.get_actor("lookout")
	world.player.global_position = malik.global_position + Vector3(4.0, 0, 0)
	m.tick(0.6)
	check(malik.last_line == world.progression.reaction_line("lookout") and "flower cart" in malik.last_line, "walking past Malik he mentions Ines's cart")
	var spoken := malik.lines_spoken
	m.tick(0.6)
	check(malik.lines_spoken == spoken, "reactions are throttled instead of repeating")
	m.tick(1.1)
	check(m.narrative.sign_text().begins_with("INES' FLOWERS"), "Ines's cart has a sign at her real work anchor")
	world.free()
