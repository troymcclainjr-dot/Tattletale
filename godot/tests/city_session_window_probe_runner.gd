extends "res://tests/city_priorities_session_fixture.gd"
## No world, gameplay input, capture or focus mutations. Uses fixture placement
## and samples native Windows focus independently from Godot's cached flags.
func _watchdog() -> void:
	pass

func _run() -> void:
	print("[session_window_probe] initial ", JSON.stringify(_window_safety_evidence()))
	var evidence := await _settle_window_safety()
	print("[session_window_probe] settled ", JSON.stringify(evidence))
	var safe := _window_off_desktop() and get_tree().root.unfocusable and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	print("[session_window_probe] safe=", safe)
	get_tree().quit(0 if safe else 1)
