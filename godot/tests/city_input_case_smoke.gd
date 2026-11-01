extends SceneTree
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.size = Vector2i(1600, 900)
	var script = load("res://tests/city_input_case_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
