extends RefCounted
## Shared physical-key bindings. Menus keep Escape and their own navigation keys.
const PATH := "user://pen_lucy_controls.cfg"
const DEFAULTS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"turn_left": KEY_LEFT, "turn_right": KEY_RIGHT, "run": KEY_SHIFT,
	"city_jump": KEY_SPACE, "city_interact": KEY_E, "city_bicycle": KEY_F,
	"city_phone": KEY_P, "city_map": KEY_M, "city_view": KEY_V,
	"city_basketball_challenge": KEY_T, "city_ball_return": KEY_R, "city_ball_shoot": -MOUSE_BUTTON_LEFT, "city_save": KEY_F5}
const TITLES := {
	"move_forward": "Forward / pedal", "move_back": "Back / brake", "move_left": "Left / steer left", "move_right": "Right / steer right",
	"turn_left": "Turn left", "turn_right": "Turn right", "run": "Run / hard pedal",
	"city_jump": "Jump / bicycle hop", "city_interact": "Interact / pick up ball", "city_bicycle": "Mount / dismount",
	"city_phone": "Phone", "city_map": "Map", "city_view": "Camera view",
	"city_basketball_challenge": "Court challenge", "city_ball_return": "Return basketball", "city_ball_shoot": "Charge / shoot ball", "city_save": "Save progress"}
static var bindings: Dictionary = {}

static func ensure() -> void:
	if bindings.is_empty():
		load_bindings()

static func load_bindings(path := PATH) -> void:
	bindings = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var candidate := DEFAULTS.duplicate()
		var valid := true
		var used := {}
		for action in DEFAULTS:
			var value = config.get_value("bindings", action, DEFAULTS[action])
			if not value is int or not allowed(value) or (value < 0 and action != "city_ball_shoot") or used.has(value):
				valid = false
				break
			used[value] = true
			candidate[action] = value
		# A damaged/conflicting file falls back as a unit: never disable an action.
		if valid:
			bindings = candidate
	apply()

static func allowed(code: int) -> bool:
	return code == -MOUSE_BUTTON_LEFT or (code > 0 and code < KEY_UNKNOWN and code not in [KEY_ESCAPE, KEY_F6, KEY_F7, KEY_F8, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_BACKSPACE])

static func apply() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		# A released old key no longer matches after rebinding; clear its held
		# action now so changing/resetting a binding cannot leave movement stuck.
		Input.action_release(action)
		InputMap.action_erase_events(action)
		var code := int(bindings.get(action, DEFAULTS[action]))
		var event: InputEvent
		if code < 0:
			event = InputEventMouseButton.new()
			event.button_index = -code
		else:
			event = InputEventKey.new()
			event.physical_keycode = code
		InputMap.action_add_event(action, event)
		# Keep familiar forward/back arrows only while those actions use defaults.
		if action in ["move_forward", "move_back"] and code == DEFAULTS[action]:
			var alternate := KEY_UP if action == "move_forward" else KEY_DOWN
			if not bindings.values().has(alternate):
				var arrow := InputEventKey.new()
				arrow.physical_keycode = alternate
				InputMap.action_add_event(action, arrow)

static func rebind(action: String, code: int, path := PATH) -> String:
	ensure()
	if not DEFAULTS.has(action) or not allowed(code):
		return "That key is reserved for menus or the inspector. Choose another key."
	if code < 0 and action != "city_ball_shoot":
		return "Left mouse is available only for basketball shooting. Choose a keyboard key."
	for other in bindings:
		if other != action and int(bindings[other]) == code:
			return "%s is already used by %s. Change that binding first." % [key_label(code), TITLES[other]]
	bindings[action] = code
	apply()
	return "" if save_bindings(path) == OK else "Binding works this visit, but could not be saved."

static func save_bindings(path := PATH) -> Error:
	var config := ConfigFile.new()
	for action in bindings:
		config.set_value("bindings", action, bindings[action])
	return config.save(path)

static func reset(path := PATH) -> Error:
	bindings = DEFAULTS.duplicate()
	apply()
	return save_bindings(path)

static func key_label(code: int) -> String:
	return "Left mouse" if code == -MOUSE_BUTTON_LEFT else OS.get_keycode_string(code)

static func label(action: String) -> String:
	ensure()
	return key_label(int(bindings.get(action, 0)))

static func matches(event: InputEvent, action: String, down := true) -> bool:
	ensure()
	if not DEFAULTS.has(action) or event.is_pressed() != down or (event is InputEventKey and event.echo):
		return false
	var code := int(bindings[action])
	if event is InputEventMouseButton:
		return code < 0 and event.button_index == -code
	if event is InputEventKey:
		var physical: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return physical == code
	return event is InputEventAction and event.action == action

static func pressed(action: String) -> bool:
	ensure()
	return Input.is_action_pressed(action)
