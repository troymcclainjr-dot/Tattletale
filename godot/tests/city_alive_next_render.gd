extends SceneTree
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var script = load("res://tests/city_alive_next_render_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
