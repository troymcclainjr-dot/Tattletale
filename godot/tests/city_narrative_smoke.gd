extends SceneTree
## Loads the runner after autoload registration (dynamic SceneTree -> Node).
func _initialize() -> void:
	var script = load("res://tests/city_narrative_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		print("[city_narrative] FAIL runner script did not load")
		quit(1)
		return
	root.add_child.call_deferred(script.new())
