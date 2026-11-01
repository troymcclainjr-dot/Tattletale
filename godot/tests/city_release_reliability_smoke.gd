extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_release_reliability_runner.gd").new())
