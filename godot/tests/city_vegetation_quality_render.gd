extends SceneTree
## Run with a real offscreen renderer, never --headless (which has no images).
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var runner = load("res://tests/city_vegetation_quality_render_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
