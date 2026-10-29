extends SceneTree
## One-off: writes the game's input actions into project.godot.
##   Godot_console.exe --headless --path godot --script res://tools/setup_input.gd

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"turn_left": [KEY_LEFT],
	"turn_right": [KEY_RIGHT],
	"run": [KEY_SHIFT],
	"binoculars": [KEY_SPACE],
	"interact": [KEY_E],
	"toggle_music": [KEY_M],
	"pause": [KEY_P],
	"cancel": [KEY_ESCAPE],
}


func _initialize() -> void:
	for action in KEYS:
		var events := []
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			e.device = -1
			events.append(e)
		if action == "binoculars":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.device = -1
			events.append(mb)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	var err := ProjectSettings.save()
	print("input actions saved: ", err == OK)
	quit()
