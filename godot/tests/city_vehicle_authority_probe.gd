extends SceneTree
## Diagnostic runner: the owner's assertions and simulation are unchanged.
func _initialize() -> void:
	var runner = load("res://tests/city_vehicle_authority_probe_runner.gd")
	root.add_child.call_deferred(runner.new())
