extends SceneTree
## Graphical active-play benchmark; pair with the fixed-view rendering benchmark.
func _initialize() -> void:
	var driver = load("res://tools/city_life_benchmark_driver.gd")
	if not driver is Script or not driver.can_instantiate():
		push_error("[city_life_benchmark] Driver failed to load; fix parser errors before benchmarking")
		quit(1)
		return
	root.add_child.call_deferred(driver.new())
