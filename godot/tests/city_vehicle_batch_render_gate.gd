extends SceneTree
## Exact owner assertions with a real RenderingServer, hidden root and private
## viewport. Dummy rendering cannot read MultiMesh transforms and is refused.
## --script res://tests/city_vehicle_batch_render_gate.gd -- --offscreen-validation
## Add --audit-fixture to run the independent restore/authority audit instead.
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--offscreen-validation"):
		printerr("[vehicle_batch_render] Requires real renderer and --offscreen-validation; no visible window is used.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.name = "PrivateVehicleBatchValidation"
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var path := "res://tests/city_vehicle_persistence_smoke_runner.gd"
	if OS.get_cmdline_user_args().has("--audit-fixture"):
		path = "res://tests/city_vehicle_audit_smoke_runner.gd"
	var runner = load(path)
	if runner == null or not runner.can_instantiate():
		quit(1)
		return
	print("[vehicle_batch_render] Private real-renderer gate: ", path)
	viewport.add_child.call_deferred(runner.new())
