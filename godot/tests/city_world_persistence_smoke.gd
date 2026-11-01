extends SceneTree
## Dynamic wrapper: the runner is loaded once autoloads exist, so it never needs
## parse-time G/Hud identifiers.

func _initialize() -> void:
	if "--offscreen-validation" in OS.get_cmdline_user_args():
		root.hide()
	var script = load("res://tests/city_world_persistence_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
