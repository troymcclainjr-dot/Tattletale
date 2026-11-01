extends SceneTree
## Loads the runner only after the tree exists, so no preload chain is resolved
## before project autoloads are available.

func _initialize() -> void:
	var runner = load("res://tests/city_material_fidelity_smoke_runner.gd")
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
