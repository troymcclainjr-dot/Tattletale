extends SceneTree
func _initialize() -> void:
	var runner = load("res://tests/city_vehicle_eviction_probe_runner.gd")
	root.add_child.call_deferred(runner.new())
