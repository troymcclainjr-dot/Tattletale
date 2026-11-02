extends SceneTree
## Load after autoload registration: save dependencies include G/Hud scripts.
func _initialize() -> void:
	var script := load("res://tests/city_save_story_context_audit_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
