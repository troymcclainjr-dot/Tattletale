extends SceneTree
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
var failures := 0
var fixture := "res://../.work/next-five-20261101/input-bindings.cfg"

func check(ok: bool, title: String) -> void:
	print("[input_bindings] %s %s" % ["PASS" if ok else "FAIL", title])
	failures += int(not ok)

func key(code: int, down := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	return event

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Let startup/window focus settle before injecting physical input.
	await process_frame
	await process_frame
	Input.use_accumulated_input = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture.get_base_dir()))
	Bindings.reset(fixture)
	check(Bindings.matches(key(KEY_SPACE), "city_jump"), "default hop/jump uses Space")
	check(not Bindings.rebind("city_jump", KEY_E, fixture).is_empty() and Bindings.label("city_jump") == "Space", "duplicate interaction key is refused without changing hop")
	check(not Bindings.rebind("city_jump", KEY_ESCAPE, fixture).is_empty(), "Escape stays available for menus")
	check(not Bindings.rebind("city_phone", -MOUSE_BUTTON_LEFT, fixture).is_empty(), "mouse binding is reserved for basketball lifecycle")
	check(Bindings.rebind("city_jump", KEY_J, fixture).is_empty(), "hop accepts a free physical key")
	check(Bindings.matches(key(KEY_J), "city_jump") and not Bindings.matches(key(KEY_SPACE), "city_jump"), "new hop key works and old key is released")
	check(Bindings.matches(key(KEY_J, false), "city_jump", false), "release edge uses the same remapped key")
	var repeat := key(KEY_J)
	repeat.echo = true
	check(not Bindings.matches(repeat, "city_jump"), "key repeat cannot trigger repeated actions")
	check(Bindings.rebind("move_forward", KEY_I, fixture).is_empty(), "forward mapping accepts I")
	check(InputMap.action_has_event("move_forward", key(KEY_I)), "InputMap stores the remapped physical forward event")
	Input.parse_input_event(key(KEY_I))
	await process_frame
	check(Input.get_action_strength("move_forward") > 0.0, "remapped forward reaches real InputMap movement")
	Input.parse_input_event(key(KEY_I, false))
	await process_frame
	check(is_zero_approx(Input.get_action_strength("move_forward")), "movement release clears held input")
	Input.parse_input_event(key(KEY_I))
	Bindings.rebind("move_forward", KEY_K, fixture)
	check(is_zero_approx(Input.get_action_strength("move_forward")), "rebinding clears held old movement before its release stops matching")
	Input.parse_input_event(key(KEY_I, false))
	Bindings.rebind("move_forward", KEY_I, fixture)
	Bindings.rebind("run", KEY_CTRL, fixture)
	Input.parse_input_event(key(KEY_CTRL))
	await process_frame
	check(Bindings.pressed("run"), "remapped sprint reaches held bicycle/player run input")
	Input.parse_input_event(key(KEY_CTRL, false))
	for action in ["city_interact", "city_bicycle", "city_phone", "city_map", "city_view", "city_ball_return", "city_basketball_challenge", "city_save"]:
		check(InputMap.has_action(action) and Bindings.matches(key(int(Bindings.bindings[action])), action), action + " resolves through the shared mapping")
	check(Bindings.rebind("city_ball_shoot", KEY_B, fixture).is_empty() and Bindings.matches(key(KEY_B, false), "city_ball_shoot", false), "keyboard basketball supports charge and release")
	Bindings.bindings = {}
	Bindings.load_bindings(fixture)
	check(Bindings.label("city_jump") == "J" and Bindings.label("city_ball_shoot") == "B" and Bindings.label("move_forward") == "I", "saved bindings survive reload")
	var config := ConfigFile.new()
	config.load(fixture)
	config.set_value("bindings", "city_jump", KEY_E)
	config.save(fixture)
	Bindings.load_bindings(fixture)
	check(Bindings.bindings == Bindings.DEFAULTS, "conflicting file safely restores all defaults")
	Bindings.rebind("city_phone", KEY_O, fixture)
	check(Bindings.reset(fixture) == OK and Bindings.matches(key(KEY_P), "city_phone"), "reset restores original bindings and persists them")
	Bindings.load_bindings(fixture)
	check(Bindings.bindings == Bindings.DEFAULTS, "reset survives reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	quit(0 if failures == 0 else 1)
