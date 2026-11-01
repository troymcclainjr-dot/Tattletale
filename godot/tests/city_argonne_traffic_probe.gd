extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_argonne_traffic_probe_runner.gd").new())
