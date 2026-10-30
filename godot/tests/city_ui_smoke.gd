extends SceneTree
## Run with APPDATA under <project>/.work/test-profile; runner rejects real profiles.
func _initialize() -> void:
	var script = load("res://tests/city_ui_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
