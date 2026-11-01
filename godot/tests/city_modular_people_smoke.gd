extends SceneTree

func _initialize() -> void:
	var runner = load("res://tests/city_modular_people_runner.gd").new()
	root.add_child.call_deferred(runner)
