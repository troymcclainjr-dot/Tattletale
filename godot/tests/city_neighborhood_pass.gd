extends SceneTree
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.add_child.call_deferred(load("res://tests/city_neighborhood_pass_runner.gd").new())
