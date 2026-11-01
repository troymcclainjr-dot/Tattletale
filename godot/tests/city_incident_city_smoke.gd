extends SceneTree
## No production resource is loaded until the private profile guard passes.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var private_root := ProjectSettings.globalize_path("res://../.work").replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var profile := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	if not profile.begins_with(private_root) or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("City incident fixture requires a private project .work profile and --offscreen-validation")
		quit(2)
		return
	var runner := load("res://tests/city_incident_city_smoke_runner.gd") as Script
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
