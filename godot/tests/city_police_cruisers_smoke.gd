extends SceneTree
## Dynamic load is intentional: autoload classes (G, Hud, Cast) must exist first.
func _initialize() -> void:
	var script := load("res://tests/city_police_cruisers_smoke_runner.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
