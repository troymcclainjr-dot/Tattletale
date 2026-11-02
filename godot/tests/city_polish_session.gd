extends SceneTree
## Rendered real-city session; every persistent write stays in a private profile.
func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var workspace := ProjectSettings.globalize_path("res://../.work/").replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var profile := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args() or not profile.begins_with(workspace):
		push_error("Polish session requires rendered offscreen validation and a private project .work profile")
		quit(2)
		return
	var runner := load("res://tests/city_polish_session_runner.gd") as Script
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
