extends SceneTree
func _initialize() -> void:
	var runner: Script = load("res://tests/city_vehicle_render_lod_smoke_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
