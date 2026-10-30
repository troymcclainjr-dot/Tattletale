extends SceneTree

func _initialize() -> void:
	var driver = load("res://tools/car_style_capture_driver.gd")
	if driver == null or not driver.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(driver.new())
