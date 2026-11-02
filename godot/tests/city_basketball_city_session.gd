extends SceneTree
## Root-run only: -- --offscreen-validation --session-run-id=<unique>.
func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var runner := load("res://tests/city_basketball_city_session_runner.gd") as Script
	if root.get_node_or_null("G") == null or runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child(runner.new())
