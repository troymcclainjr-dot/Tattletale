extends SceneTree
## Private render-only fixture. Does not start gameplay or capture pointer input.
func _initialize() -> void:
	root.unfocusable = true
	var script := load("res://tests/city_cast_motion_gallery_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
