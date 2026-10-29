extends SceneTree
## Headless smoke test: python godot/tools/godot_run.py -- --headless --script res://tests/smoke.gd
## The work is in smoke_runner.gd, loaded at runtime so it compiles after the autoloads exist.
## Exit code = number of failed checks.


func _initialize() -> void:
	var r: Node = load("res://tests/smoke_runner.gd").new()
	r.name = "Smoke"
	root.add_child.call_deferred(r)
