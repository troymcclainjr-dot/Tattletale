extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/city_capture_driver.gd").new())
