extends SceneTree
## Boot only after autoload registration, matching the established world fixture.
func _initialize() -> void:
	var script := load("res://tests/city_priorities_session_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
