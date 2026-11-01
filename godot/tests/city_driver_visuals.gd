extends SceneTree
## Real renderer, hidden root + private SubViewport. Root runs serialized:
## python godot/tools/godot_run.py --timeout 300 -- --script res://tests/city_driver_visuals.gd -- --offscreen-validation
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var runner = load("res://tests/city_driver_visuals_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
