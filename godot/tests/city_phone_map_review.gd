extends SceneTree
## UI review capture entry; the runner is a Node so project autoloads exist.
func _initialize() -> void:
	var script = load("res://tests/city_phone_map_review_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
