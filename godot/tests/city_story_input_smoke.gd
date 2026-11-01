extends SceneTree
## Loads the real-level runner after autoload registration (G/Hud).
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.size = Vector2i(1600, 900)
	var script = load("res://tests/city_story_input_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		print("[story_input] FAIL runner script did not load")
		quit(1)
		return
	root.add_child.call_deferred(script.new())
