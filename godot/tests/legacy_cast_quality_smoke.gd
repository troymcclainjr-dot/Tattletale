extends SceneTree
## python godot/tools/godot_run.py --timeout 120 -- --headless --script res://tests/legacy_cast_quality_smoke.gd

func _initialize() -> void:
	var script = load("res://tests/legacy_cast_quality_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
