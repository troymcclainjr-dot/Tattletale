extends SceneTree
## Private fixture renderer; root must explicitly request offscreen validation.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var runner := load("res://tests/city_architecture_gallery_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
