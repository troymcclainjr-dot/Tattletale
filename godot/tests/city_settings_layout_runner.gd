extends SceneTree
class SettingsHost extends Node3D:
	func resume_exploring() -> void: pass
	func spawn_player() -> void: pass
	func save_progress() -> String: return "fixture"
	func return_to_original() -> void: pass
var fails := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var host := SettingsHost.new()
	viewport.add_child(host)
	var settings = load("res://scripts/city/city_settings.gd").new()
	viewport.add_child(settings)
	settings.setup(host)
	settings.show()
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		viewport.size = dimensions
		for tab_index in 3:
			var tabs: TabContainer = settings.find_children("*", "TabContainer", true, false)[0]
			tabs.current_tab = tab_index
			for frame in 8:
				await process_frame
			var okay := true
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			for action in settings.find_children("*", "Button", true, false):
				if action.is_visible_in_tree() and action.text in ["Resume", "Save progress", "Main menu", "Cases", "Credits"]:
					okay = okay and bounds.encloses(action.get_global_rect())
					print("[settings_layout] button ", dimensions, " tab ", tab_index, " ", action.text, " ", action.get_global_rect())
			print("[settings_layout] %s %s tab %d actions fit viewport" % ["PASS" if okay else "FAIL", dimensions, tab_index])
			if not okay:
				fails += 1
				_dump(settings, 0)
	viewport.free()
	quit(1 if fails else 0)
func _dump(node: Node, depth: int) -> void:
	if node is Control and node.is_visible_in_tree():
		print("[settings_layout] ", " ".repeat(depth), node.get_class(), " ", node.name, " rect=", node.get_global_rect(), " min=", node.get_combined_minimum_size())
	for child in node.get_children():
		_dump(child, depth + 1)
