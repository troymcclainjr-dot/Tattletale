extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_current_ui_render_runner.gd").new())
