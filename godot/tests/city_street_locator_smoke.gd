extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_street_locator_smoke_runner.gd").new())
