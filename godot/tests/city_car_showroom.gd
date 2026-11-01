extends SceneTree
## Graphical, private viewport only:
## python godot/tools/godot_run.py --timeout 300 -- --script res://tests/city_car_showroom.gd -- --offscreen-validation
## Optional: --capture-outdir <dir> (default artifacts/alive-next/vehicle-showroom).

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	var script = load("res://tests/city_car_showroom_runner.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(script.new())
