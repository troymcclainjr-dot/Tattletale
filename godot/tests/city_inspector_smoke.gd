extends SceneTree
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.add_child.call_deferred(load("res://tests/city_inspector_smoke_runner.gd").new())
