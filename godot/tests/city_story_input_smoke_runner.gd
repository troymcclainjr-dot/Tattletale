extends Node
## Real level, real input: discover "Petal Pushers" at Ines Morales's cart,
## take every step and the decision with E / arrow keys / Enter, see Ines's own
## conversation change, save through Settings, reload the same isolated slot in
## a fresh scene, finish part 2 and confirm it pays exactly once across a second
## reload. Only travel is abbreviated (placement beside the current contact).
const VENDOR := "daily_ines_morales"
var level: Node
var passes := 0
var failures: Array[String] = []
var fixture := ""
var _finished := false

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(420.0, true, false, true).timeout
	if not _finished:
		check(false, "story input fixture exceeded its watchdog")
		_finish()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> bool:
	print("[story_input] %s %s" % ["PASS" if ok else "FAIL", label])
	if ok:
		passes += 1
	else:
		failures.append(label)
	return ok

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func click(button: Button) -> void:
	var viewport := button.get_viewport()
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await frames(1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		viewport.push_input(event, true)
		await frames(2)

func boot() -> bool:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	level = null
	for i in 2400:
		await frames(1)
		level = get_tree().current_scene
		if level != null and level.get("level_ready") == true:
			break
	if not check(level != null and level.get("level_ready") == true, "complete world initialized"):
		return false
	if not check(not level.world_save.enabled, "validation never opens the user's checkpoint"):
		return false
	level.world_save.setup(level, fixture)
	if level.paused:
		await key(KEY_ESCAPE)
	return check(level.world_save.enabled and level.world_save.path == fixture and not level.paused, "isolated fixture slot and normal play")

## Stand beside the live destination with clear line of sight and no original
## case offer competing for E. Re-reads moving residents every attempt.
func approach(actor_id: String = "", ordinary := false) -> bool:
	if level.paused or level._dialogue.state.active:
		_trace_dialogue("approach blocked by existing modal", actor_id)
		return check(false, "travel begins in normal play with no stale dialogue")
	for attempt in 3:
		var target: Vector3 = level.npcs.actor_position(actor_id) if not actor_id.is_empty() else level.vector(level.missions.get_status().target_position)
		if not target.is_finite():
			break
		for angle in [0.0, PI * .5, PI, PI * 1.5, PI * .25, PI * .75, PI * 1.25, PI * 1.75]:
			var safe: Dictionary = level.npcs.find_safe_position(target + Vector3(sin(angle), 0, cos(angle)) * 1.6, .4)
			if not bool(safe.get("ok", false)):
				continue
			level._place_player(safe.position, angle + PI)
			await frames(12 if ordinary else 4)
			var now: Vector3 = level.npcs.actor_position(actor_id) if not actor_id.is_empty() else level.vector(level.missions.get_status().target_position)
			if level.missions._can_interact(now) and level.missions.nearby_offer().is_empty():
				if ordinary:
					# Ordinary E uses the nearest enabled conversation actor only
					# after active-case preview and shop handling have declined it.
					if not level.missions.conversation_preview().is_empty() or level.nearby_talker() != actor_id \
						or not str(level.shops.counter_at(level.player.global_position)).is_empty():
						continue
				return true
	_trace_dialogue("no eligible interaction position", actor_id)
	return check(false, "found a clear interaction spot beside " + (actor_id if not actor_id.is_empty() else "the case destination"))

func _trace_dialogue(label: String, actor_id := "") -> void:
	var actor = level.npcs.get_actor(actor_id) if not actor_id.is_empty() else null
	var state = level._dialogue.state
	print("[story_input] DIALOGUE " + JSON.stringify({"label": label, "expected_actor": actor_id,
		"registered_conversation": level.conversations.has(actor_id),
		"actor_enabled": actor.get("enabled") if actor != null else null,
		"actor_physical": actor.get("physical") if actor != null else null,
		"actor_combat_override": actor.get("combat_override") if actor != null else null,
		"paused": level.paused, "dialogue_active": state.active, "dialogue_actor": state.graph.get("actor_id", ""),
		"current": state.current(), "nearby_talker": level.nearby_talker(),
		"mission_preview": level.missions.conversation_preview(), "active_id": level.missions.active_id,
		"stage": level.missions.stage, "shop_open": level.shops.is_open()}))

## Enter through extra lines, arrow keys to the wanted reply, Enter to pick it.
func choose_reply(wanted: Callable) -> bool:
	var state = level._dialogue.state
	for _i in 6:
		if not state.active or not state.choices().is_empty():
			break
		await key(KEY_ENTER)
	if not state.active:
		return false
	var replies: Array = state.choices()
	var index := -1
	for i in replies.size():
		if bool(wanted.call(replies[i])):
			index = i
			break
	if index < 0:
		return false
	for _j in replies.size():
		if int(state.selected) == index:
			break
		await key(KEY_DOWN)
	await key(KEY_ENTER)
	return true

func _hook(kind: String, id: String = "") -> Callable:
	return func(reply: Dictionary) -> bool:
		var hook: Dictionary = reply.get("hook", {})
		return str(hook.get("kind", "")) == kind and (id.is_empty() or str(hook.get("id", "")) == id)

func _option(option: String) -> Callable:
	return func(reply: Dictionary) -> bool:
		var hook: Dictionary = reply.get("hook", {})
		return str(hook.get("choice", "")) == option

func play_step(option: String = "") -> bool:
	var before_id := str(level.missions.active_id)
	var before_stage := int(level.missions.stage)
	if before_id.is_empty():
		return false
	if not await approach():
		return false
	await key(KEY_E)
	if not check(level._dialogue.state.active and level.missions.stage == before_stage and str(level.missions.active_id) == before_id,
			"E opens %s step %d without advancing" % [before_id, before_stage]):
		_trace_dialogue("step E did not open expected modal")
		return false
	var picked: bool = await choose_reply(_option(option) if not option.is_empty() else _hook("case_step"))
	await frames(2)
	return check(picked and not level._dialogue.state.active and (str(level.missions.active_id) != before_id or level.missions.stage == before_stage + 1),
		"reply input commits %s step %d%s" % [before_id, before_stage, (" as " + option) if not option.is_empty() else ""])

func save_with_ui() -> Dictionary:
	for i in 240:
		if level.world_save.can_checkpoint():
			break
		await frames(1)
	if not check(level.world_save.can_checkpoint(), "grounded session can checkpoint"):
		return {}
	await key(KEY_ESCAPE)
	var save_button: Button
	for node in level._settings.find_children("*", "Button", true, false):
		if node.text == "Save progress":
			save_button = node
			break
	if not check(save_button != null and save_button.is_visible_in_tree(), "Settings shows Save progress"):
		return {}
	var before: int = level.world_save.save_count
	await click(save_button)
	check(level.world_save.save_count == before + 1, "one mouse click writes one checkpoint")
	await key(KEY_ESCAPE)
	var read: Dictionary = level.world_save.read_snapshot()
	return read.state if bool(read.get("ok", false)) else {}

func reload() -> bool:
	if not await boot():
		return false
	var restored: Dictionary = level.world_save.load_state()
	return check(bool(restored.get("ok", false)), "fresh scene restores the isolated checkpoint: " + str(restored.get("reason", "")))

func _run() -> void:
	if DisplayServer.get_name() != "headless" and not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires headless or private offscreen validation")
		_finish()
		return
	fixture = ProjectSettings.globalize_path("res://../.work/priorities-five/story-input/%d-%d/world.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	if not await boot():
		_finish()
		return
	var p: Node = level.progression
	check(level.npcs.get_actor(VENDOR) != null and level.residents.actors.size() == 40, "Ines Morales is one of the forty daily residents")
	if not await approach(VENDOR):
		_finish()
		return
	check(str(level.missions.get_status().prompt) == "E  Talk about the flower cart complaint", "the HUD prompt names the cart complaint beside Ines")
	await key(KEY_E)
	check(level._dialogue.state.active and level.missions.active_id.is_empty() and str(level._dialogue.state.current().speaker) == "Ines Morales",
		"E previews Ines's offer without starting it")
	var accepted: bool = await choose_reply(_hook("story_start", "petals_word"))
	if not check(accepted and level.missions.active_id == "petals_word", "Enter accepts part 1"):
		_finish()
		return
	for option in ["", "", "negotiate"]:
		if not await play_step(str(option)):
			_finish()
			return
	check(p.choice_of("petals_call") == "negotiate" and level.missions.active_id == "petals_negotiate" and p.relationship_value("ines") > 0,
		"the negotiate reply is durable, starts part 2 and earns Ines's trust")
	# Part 2 starts at the organizer. Select a position where the normal E
	# dispatcher actually chooses Ines, rather than assuming proximity is enough.
	if await approach(VENDOR, true):
		await key(KEY_E)
		var reaction: String = p.reaction_line(VENDOR)
		var state = level._dialogue.state
		var saw_reaction := false
		for _line in 8:
			if not state.active or str(state.graph.get("actor_id", "")) != VENDOR:
				break
			if not reaction.is_empty() and str(state.current().get("text", "")) == reaction:
				saw_reaction = true
				break
			# A reputation greeting may precede her reaction. Read only visible
			# lines, and never press Enter on an unrelated reply list.
			if not state.choices().is_empty():
				break
			await key(KEY_ENTER)
		check(saw_reaction and level.missions.active_id == "petals_negotiate" and level.missions.stage == 0,
			"Ines's everyday conversation visibly includes her reaction without advancing part 2")
		if not saw_reaction:
			_trace_dialogue("missing visible Ines reaction", VENDOR)
		if state.active:
			await key(KEY_ESCAPE)
		check(not state.active and not level.paused, "leaving Ines's conversation resumes play without opening Settings")
	if not failures.is_empty():
		_finish()
		return
	if not await play_step():
		_finish()
		return
	var saved: Dictionary = await save_with_ui()
	check(not saved.is_empty() and str(saved.missions.active_id) == "petals_negotiate" and int(saved.missions.stage) == 1 and str(saved.progression.choices.get("petals_call", "")) == "negotiate",
		"the checkpoint carries the active part, stage and durable choice")
	var trust: int = p.relationship_value("ines")
	if not await reload():
		_finish()
		return
	p = level.progression
	check(level.missions.active_id == "petals_negotiate" and level.missions.stage == 1 and p.choice_of("petals_call") == "negotiate" and p.relationship_value("ines") == trust,
		"reload resumes the same branch, part, stage and relationship")
	var cash: int = p.money
	var score: int = level.missions.score
	for _remaining in 2:
		if not await play_step():
			_finish()
			return
	var paid: int = p.money - cash
	check(level.missions.completed_ids.has("petals_negotiate") and paid > 0 and level.missions.score > score, "finishing part 2 after reload pays once")
	var second: Dictionary = await save_with_ui()
	check(not second.is_empty() and "petals_negotiate" in second.missions.completed_ids, "the finished part is checkpointed")
	var settled: int = p.money
	if not await reload():
		_finish()
		return
	p = level.progression
	check(p.money == settled and not p.reward_case("petals_negotiate", 60) and not level.missions.start_case("petals_negotiate"),
		"a second reload neither repays nor restarts part 2")
	if await approach(VENDOR):
		await key(KEY_E)
		# Enter only moves past pitch lines; it is never pressed on a reply list.
		for _i in 4:
			if not level._dialogue.state.active or not level._dialogue.state.choices().is_empty():
				break
			await key(KEY_ENTER)
		var offered := false
		if level._dialogue.state.active:
			for reply in level._dialogue.state.choices():
				offered = offered or str(reply.get("hook", {}).get("id", "")) == "petals_end_negotiate"
		check(offered and level.missions.active_id.is_empty(), "later, Ines offers the matching part 3 through normal conversation")
		await key(KEY_ESCAPE)
	check(level.npcs.crowd.residents.size() == 1200 and level.residents.actors.size() == 40, "population and daily roster sizes are unchanged")
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {"passes": passes, "failures": failures, "checkpoint": fixture,
		"scope": "real level and input for story discovery, steps, decision, Settings save and fresh-scene reloads; travel abbreviated"}
	var path := ProjectSettings.globalize_path("res://../.work/priorities-five/story-input-report.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("STORY_INPUT_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
