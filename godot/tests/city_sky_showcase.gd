extends SceneTree
## Load after autoload registration; do not preload the production dependency tree.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Sky showcase requires the isolated offscreen renderer")
		quit(2)
		return
	var runner = load("res://tests/city_sky_showcase_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
