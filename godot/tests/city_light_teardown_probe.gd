extends SceneTree

func _initialize() -> void:
	var script := load("res://tests/city_light_teardown_probe_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
