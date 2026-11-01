extends SceneTree
## Launch with a real renderer and -- --offscreen-validation. Never show a window.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var runner = load("res://tests/city_living_world_render_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
