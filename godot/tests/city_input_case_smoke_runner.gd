extends Node
## Player verbs use actual input events: offer, cancel, accept, evidence, return,
## Settings and Save progress. Only travel/reload and isolated slot selection
## are fixture setup. Never invoke mission commits or button signals directly.
var level: Node
var passes := 0
var failures: Array[String] = []
var fixture := ""
var _finished := false
var inputs: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(300.0, true, false, true).timeout
	if not _finished:
		check(false, "normal-input case fixture exceeded watchdog")
		_finish()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> bool:
	print("[input_case] %s %s" % ["PASS" if ok else "FAIL", label])
	if ok:
		passes += 1
	else:
		failures.append(label)
	return ok

func key(code: int) -> void:
	inputs.append({"kind": "key", "code": code})
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func click(button: Button) -> void:
	# GUI input uses viewport coordinates, not OS-window/stretch coordinates.
	# Headless Window canvas scaling can differ from its requested pixel size.
	var viewport := button.get_viewport()
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	inputs.append({"kind": "mouse", "button": button.text, "position": [point.x, point.y], "viewport_size": [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y], "canvas_transform": str(button.get_global_transform_with_canvas())})
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
	if not check(level != null and level.get("level_ready") == true, "fresh complete world initialized"):
		return false
	if not check(not level.world_save.enabled, "validation never opens the user's normal checkpoint"):
		return false
	# The normal startup calls this provider too; override only its destination
	# because validation deliberately disables the real user slot.
	level.world_save.setup(level, fixture)
	return check(level.world_save.enabled and level.world_save.path == fixture, "all persistence uses unique project-owned fixture")

func approach(target: Vector3) -> bool:
	# Only travel is abbreviated. The production range/line-of-sight checks and
	# the normal UI/input handlers still decide every case action.
	for angle in [0.0, PI * .5, PI, PI * 1.5, PI * .25, PI * .75, PI * 1.25, PI * 1.75]:
		var desired := target + Vector3(sin(angle), 0, cos(angle)) * 1.65
		var safe: Dictionary = level.npcs.find_safe_position(desired, .4)
		if not bool(safe.get("ok", false)):
			continue
		level._place_player(safe.position, angle + PI)
		await frames(4)
		if level.missions._can_interact(target):
			return true
	return check(false, "fixture found a supported unobstructed interaction approach")

func save_with_ui() -> bool:
	for i in 240:
		if level.world_save.can_checkpoint():
			break
		await frames(1)
	if not check(level.world_save.can_checkpoint(), "grounded session can checkpoint before opening Settings"):
		return false
	await key(KEY_ESCAPE)
	if not check(level.paused and level._menu.visible, "Escape opens Settings"):
		return false
	var save_button: Button
	for node in level._settings.find_children("*", "Button", true, false):
		if node.text == "Save progress":
			save_button = node
			break
	if not check(save_button != null and save_button.is_visible_in_tree(), "visible Save progress control found"):
		return false
	var before: int = level.world_save.save_count
	await click(save_button)
	if not check(level.world_save.save_count == before + 1, "mouse input activates exactly one checkpoint write"):
		return false
	check(level._settings._save_feedback.text == "Progress saved.", "Settings confirms successful save")
	var read: Dictionary = level.world_save.read_snapshot()
	if not check(bool(read.get("ok", false)), "UI-written checkpoint parses"):
		return false
	return check(read.state.missions.completed_ids == ["lost_satchel"] and int(read.state.missions.score) == 100, "checkpoint contains one completed case and exactly its reward")

func _run() -> void:
	if DisplayServer.get_name() != "headless" and not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires headless or private offscreen validation")
		_finish()
		return
	fixture = ProjectSettings.globalize_path("res://../.work/alive-next/input-case-%d-%d/world.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	if not await boot():
		_finish()
		return
	check(level.missions.active_id.is_empty() and level.missions.completed_ids.is_empty() and level.missions.score == 0, "isolated session begins without earned case progress")
	if level.paused:
		await key(KEY_ESCAPE)
	if not check(not level.paused and level.player.enabled, "keyboard input resumes normal play"):
		_finish()
		return
	if not await approach(level.npcs.actor_position("resident")):
		_finish()
		return
	await key(KEY_E)
	if not check(level._dialogue.state.active and level.missions.active_id.is_empty(), "E previews nearby offer without accepting"):
		_finish()
		return
	check(level.paused and not level.player.enabled, "conversation holds world/player input")
	await key(KEY_ESCAPE)
	check(not level._dialogue.state.active and level.missions.active_id.is_empty() and level.missions.score == 0, "canceling offer changes neither case nor score")
	await key(KEY_E)
	await key(KEY_ENTER)
	if not check(level.missions.active_id == "lost_satchel" and level.missions.stage == 0, "Enter explicitly accepts lost satchel through dialogue"):
		_finish()
		return
	var step_count: int = level.missions.case_steps("lost_satchel").size()
	for step in step_count:
		var state: Dictionary = level.missions.get_status()
		if not check(state.active_id == "lost_satchel" and int(state.stage) == step, "ordered case stage %d" % step):
			break
		if not await approach(state.target_position):
			break
		await key(KEY_E)
		if not check(level._dialogue.state.active and level.missions.stage == step, "opening stage %d text does not advance" % step):
			break
		check(str(level._dialogue.state.current().text) == str(level.missions._steps[step].dialogue), "stage %d displays authored case line" % step)
		var jumps_before: int = level.player.jumps_started
		await key(KEY_SPACE)
		check(level.player.jumps_started == jumps_before, "dialogue Space never also jumps")
		check(not level._dialogue.state.active and not level.paused, "confirming stage %d returns to play" % step)
		if step + 1 < step_count:
			check(level.missions.stage == step + 1 and level.missions.score == 0, "one confirmation advances one stage without early reward")
	if not check(level.missions.completed_ids.has("lost_satchel") and level.missions.active_id.is_empty() and level.missions.score == 100, "satchel returned through input earns exactly one reward"):
		_finish()
		return
	if not await save_with_ui():
		_finish()
		return
	# Destroy and reload the scene: no surviving mission object can satisfy the
	# restore assertions. Load the same isolated slot through its normal provider.
	if not await boot():
		_finish()
		return
	check(level.missions.score == 0 and level.missions.completed_ids.is_empty(), "reload first creates an independent empty mission runtime")
	var restored: Dictionary = level.world_save.load_state()
	if not check(bool(restored.get("ok", false)), "fresh world restores the isolated checkpoint"):
		_finish()
		return
	check(level.missions.completed_ids.has("lost_satchel") and level.missions.completed_ids.size() == 1 and level.missions.score == 100 and level.missions.active_id.is_empty(), "reload preserves completion and score without replaying rewards")
	check(level.npcs.crowd.residents.size() == 1200 and level.residents.actors.size() == 40, "reload keeps canonical crowd and daily roster sizes")
	if level.paused:
		await key(KEY_ESCAPE)
	if await approach(level.npcs.actor_position("resident")):
		await key(KEY_E)
		check(level._dialogue.state.active, "restored session can use normal conversation input")
		var next_offer := false
		for choice in level._dialogue.state.choices():
			var hook: Dictionary = choice.get("hook", {})
			next_offer = next_offer or str(hook.get("id", "")) == "parcel_report"
		check(next_offer, "completed satchel is replaced by the next authored offer")
		await key(KEY_ESCAPE)
		check(level.missions.score == 100 and level.missions.active_id.is_empty(), "preview after reload cannot duplicate the completed reward")
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {"passes": passes, "failures": failures, "checkpoint": fixture, "input_events": inputs,
		"scope": "actual input for dialogue, case actions and Save progress; fixture travel and fresh-scene isolated-slot bootstrap"}
	var path := ProjectSettings.globalize_path("res://../artifacts/alive-next/input-case-report.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("INPUT_CASE_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
