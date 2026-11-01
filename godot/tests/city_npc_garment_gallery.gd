extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/city_npc_garment_gallery_runner.gd").new())
