extends SceneTree
## Dynamic load permits production autoload dependencies to register first.
func _initialize() -> void:
	var script = load("res://tests/city_case_incident_audit_runner.gd")
	if script == null or not script.can_instantiate():
		print("[case_incident_audit] FAIL runner script did not load")
		quit(1)
		return
	root.add_child.call_deferred(script.new())
