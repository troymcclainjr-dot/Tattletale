extends SceneTree
func _initialize() -> void:
	var runner := load("res://tests/city_bicycle_rider_fit_smoke_runner.gd") as Script
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
