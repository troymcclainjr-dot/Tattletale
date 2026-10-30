extends SceneTree
## Run with --headless --path godot --script res://tests/city_movement_smoke.gd.
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_movement_smoke_runner.gd").new())
