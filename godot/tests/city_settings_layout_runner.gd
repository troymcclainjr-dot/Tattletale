extends SceneTree
const OUTPUT := "res://../artifacts/next-five-20261101"
var captures: Array[String] = []
class SettingsHost extends Node3D:
	func resume_exploring() -> void: pass
	func spawn_player() -> void: pass
	func save_progress() -> String: return "fixture"
	func return_to_original() -> void: pass
var fails := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	if rendered and not "--offscreen-validation" in OS.get_cmdline_user_args():
		print("[settings_layout] FAIL rendered fixture requires --offscreen-validation")
		quit(1)
		return
	if rendered:
		root.unfocusable = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var host := SettingsHost.new()
	viewport.add_child(host)
	var settings = load("res://scripts/city/city_settings.gd").new()
	viewport.add_child(settings)
	settings.setup(host)
	settings.show()
	for text_scale in [1.0, 1.1, 1.25]:
		settings.values.ui_scale = text_scale
		settings.apply_text_scale()
		settings.apply_text_scale()
		var expected_size := roundi(14.0 * text_scale)
		var stable: bool = settings._save_feedback.label_settings.font_size == expected_size
		print("[settings_layout] %s repeated scale %.2f stays at %d px" % ["PASS" if stable else "FAIL", text_scale, expected_size])
		fails += int(not stable)
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
					if action.is_visible_in_tree() and action.text in ["Resume", "Return to starting corner", "Save progress", "Load checkpoint", "Start fresh…", "Main menu", "Cases", "Credits"]:
						okay = okay and bounds.encloses(action.get_global_rect())
						print("[settings_layout] button ", dimensions, " tab ", tab_index, " ", action.text, " ", action.get_global_rect())
				print("[settings_layout] %s %s tab %d actions fit viewport" % ["PASS" if okay else "FAIL", dimensions, tab_index])
				if not okay:
					fails += 1
					_dump(settings, 0)
	# Inspect every binding row by scrolling its complete row into view at the
	# smallest supported viewport and largest readable-text setting.
	viewport.size = Vector2i(1280, 720)
	settings.values.ui_scale = 1.25
	settings.apply_text_scale()
	var tabs: TabContainer = settings.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	var controls := tabs.get_tab_control(2) as ScrollContainer
	controls.scroll_vertical = 0
	await settle()
	if rendered:
		await capture(viewport, "settings-controls-125-top")
	var row_index := 0
	for action in settings._binding_buttons:
		var button: Button = settings._binding_buttons[action]
		var row: Control = button.get_parent()
		controls.ensure_control_visible(row)
		await settle()
		var view: Rect2 = controls.get_global_rect().grow(1.0)
		var reachable: bool = view.encloses(row.get_global_rect()) and button.size.y >= button.get_combined_minimum_size().y
		for child in row.get_children():
			if child is Label:
				reachable = reachable and view.encloses(child.get_global_rect()) and child.get_visible_line_count() >= child.get_line_count()
		record(reachable, "%s full label and button fit after scroll at 125%%" % action)
		if rendered and (row_index % 4 == 3 or row_index == settings._binding_buttons.size() - 1):
			await capture(viewport, "settings-controls-125-rows-%02d" % row_index)
		row_index += 1
	var reset: Button
	for candidate in settings.find_children("*", "Button", true, false):
		if candidate.text == "Reset controls":
			reset = candidate
	if reset != null:
		controls.ensure_control_visible(reset)
		await settle()
		record(controls.get_global_rect().grow(1.0).encloses(reset.get_global_rect()), "reset controls remains reachable at maximum text size")
		if rendered:
			await capture(viewport, "settings-controls-125-bottom")
	tabs.current_tab = 0
	var video := tabs.get_tab_control(0) as ScrollContainer
	video.scroll_vertical = 0
	await settle()
	if rendered:
		await capture(viewport, "settings-video-125-top")
	video.scroll_vertical = int(video.get_v_scroll_bar().max_value)
	await settle()
	if rendered:
		await capture(viewport, "settings-video-125-bottom")
	settings._confirm_fresh()
	await settle()
	var confirmation: ConfirmationDialog = settings._fresh_confirmation
	record(confirmation.visible and confirmation.is_embedded(), "fresh-start confirmation stays inside the private viewport")
	record(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(Rect2(Vector2(confirmation.position), Vector2(confirmation.size))), "fresh-start confirmation fits 1280x720")
	if rendered:
		await capture(viewport, "settings-fresh-start-125")
	confirmation.hide()
	if rendered:
		var manifest := FileAccess.open(OUTPUT.path_join("settings-layout-captures.json"), FileAccess.WRITE)
		if manifest != null:
			manifest.store_string(JSON.stringify({"viewport": [1280, 720], "text_scale": 1.25, "captures": captures, "failures": fails}, "\t"))
			manifest.close()
	viewport.free()
	quit(1 if fails else 0)
func _dump(node: Node, depth: int) -> void:
	if node is Control and node.is_visible_in_tree():
		print("[settings_layout] ", " ".repeat(depth), node.get_class(), " ", node.name, " rect=", node.get_global_rect(), " min=", node.get_combined_minimum_size())
	for child in node.get_children():
		_dump(child, depth + 1)

func record(ok: bool, message: String) -> void:
	print("[settings_layout] %s %s" % ["PASS" if ok else "FAIL", message])
	fails += int(not ok)

func settle() -> void:
	for frame in 5:
		await process_frame

func capture(viewport: SubViewport, name_: String) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if directory_error != OK:
		record(false, "create project capture directory")
		return
	await settle()
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		record(false, "rendered image available: " + name_)
		return
	record(picture.get_size() == Vector2i(1280, 720), name_ + " renders at exact 1280x720")
	var path := OUTPUT.path_join(name_ + ".png")
	var result := picture.save_png(path)
	record(result == OK, "write " + name_)
	if result == OK:
		captures.append(path)
