extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_police_emergency_junction_smoke_runner.gd").new())
