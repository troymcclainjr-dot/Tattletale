extends SceneTree
## Root-run only: isolated APPDATA, --windowed --position -10000,-10000,
## --resolution 1280x720 --script res://tools/city_ui_capture.gd -- --offscreen-validation
func _initialize() -> void:
	var script = load("res://tools/city_ui_capture_driver.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
