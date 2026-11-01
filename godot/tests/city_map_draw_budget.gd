extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_map_draw_budget_runner.gd").new())
