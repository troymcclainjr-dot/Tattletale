extends SceneTree
## Actual menu/provider with private files. Root launches serially.
func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	root.gui_embed_subwindows = true # Confirmations stay inside the off-desktop surface.
	var runner := load("res://tests/city_settings_checkpoint_session_runner.gd") as Script
	if root.get_node_or_null("G") == null or runner == null or not runner.can_instantiate():
		quit(1)
		return
	root.add_child(runner.new())
