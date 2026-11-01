extends SceneTree
## Headless: python tools/godot_run.py -- --headless --script res://tests/city_perf_tools_smoke.gd

func _initialize() -> void:
	var script = load("res://tests/city_perf_tools_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
