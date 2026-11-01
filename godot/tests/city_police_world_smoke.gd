extends SceneTree
## Dynamic load is intentional: autoload classes must exist before the world test.
func _initialize() -> void:
	var script := load("res://tests/city_police_world_smoke_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
