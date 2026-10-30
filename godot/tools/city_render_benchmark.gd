extends SceneTree
## Run graphically, twice: --no-city-optimization baseline and optimized.
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/city_render_benchmark_driver.gd").new())
