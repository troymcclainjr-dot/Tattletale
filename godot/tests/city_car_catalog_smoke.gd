extends SceneTree
## Headless-safe: python godot/tools/godot_run.py --timeout 180 -- --headless --script res://tests/city_car_catalog_smoke.gd

func _initialize() -> void:
	var script = load("res://tests/city_car_catalog_smoke_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
