extends SceneTree
## Launch with APPDATA redirected beneath project/.work and a real renderer.
## Reject a real profile before dynamically loading any production dependency.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var private_root := ProjectSettings.globalize_path("res://../.work").replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var profile := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	if not profile.begins_with(private_root) or DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Full-city sky fixture requires an isolated project .work profile and explicit real offscreen renderer")
		quit(2)
		return
	var runner := load("res://tests/city_foundation_sky_perf_runner.gd") as Script
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
