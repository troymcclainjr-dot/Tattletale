extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_steady_endurance_runner.gd").new())
