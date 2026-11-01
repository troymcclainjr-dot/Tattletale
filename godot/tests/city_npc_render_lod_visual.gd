extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_npc_render_lod_visual_runner.gd").new())
