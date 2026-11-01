extends "res://tests/city_living_world_render_runner.gd"
## Six captures from production UI in a private viewport. No desktop screenshots.
func button(parent: Node, text: String) -> Button:
	if parent is Button and parent.text == text:
		return parent
	for child in parent.get_children():
		var found := button(child, text)
		if found != null:
			return found
	return null

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event, true)
	await frames(1)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	viewport.push_input(event, true)
	await frames(2)

func attribution_visible(label_name: String) -> void:
	var label: Label = level.find_child(label_name, true, false) as Label
	if label == null:
		check(false, label_name + " exists")
		return
	# Newly built containers settle their minimum size/layout on deferred frames.
	await frames(2)
	var bounds := label.get_global_rect()
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	check(label.is_visible_in_tree() and screen.encloses(bounds), label_name + " is visible and within capture bounds")
	if label_name == "RadarAttribution":
		check(not level._radar.is_ancestor_of(label), "radar credit is outside circular clipping ancestry")
	await frames(2)
	await RenderingServer.frame_post_draw
	var shown := viewport.get_texture().get_image()
	label.hide()
	await frames(2)
	await RenderingServer.frame_post_draw
	var hidden := viewport.get_texture().get_image()
	label.show()
	var changed := 0
	var region := bounds.intersection(screen)
	for y in range(maxi(0, floori(region.position.y)), mini(viewport.size.y, ceili(region.end.y))):
		for x in range(maxi(0, floori(region.position.x)), mini(viewport.size.x, ceili(region.end.x))):
			var difference := shown.get_pixel(x, y) - hidden.get_pixel(x, y)
			if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.08:
				changed += 1
	check(changed > 25, label_name + " contributes visible rendered text pixels (%d)" % changed)

func _run() -> void:
	OUTPUT = "res://../artifacts/alive-next/ui"
	if not "--offscreen-validation" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		check(false, "graphical renderer with --offscreen-validation required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateCurrentUICapture"
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	level = load("res://scenes/city/pen_lucy.tscn").instantiate()
	viewport.add_child(level)
	for index in 1800:
		await frames(1)
		if level.level_ready:
			break
	check(level.level_ready, "current neighborhood initialized")
	if not level.level_ready:
		get_tree().quit(1)
		return
	level.world_time.frozen = true
	level.world_time.set_time(600)
	level.resume_exploring()
	await settle_streaming()
	check(level._ui.find_child("RadarAttribution", true, false) == null, "gameplay has no persistent attribution overlay")
	level._build_loading_screen()
	check(level._loading.find_child("StartupMapAttribution", true, false) == null, "loading screen has no map attribution text")
	await capture("loading-screen")
	level._loading.queue_free()
	level._loading = null
	await frames(2)
	await capture("gameplay-minimap")
	await key(KEY_M)
	check(level._map_overlay.visible, "M opens current full map")
	check(level._map_overlay.find_child("MapAttribution", true, false) == null, "map attribution remains in Credits")
	await capture("full-map")
	await key(KEY_M)
	await key(KEY_ESCAPE)
	check(level.paused and level._settings.visible, "Escape opens current Settings")
	await capture("settings-video")
	var tabs: TabContainer
	# Find the actual tab control without relying on auto-generated node names.
	var pending: Array[Node] = [level._settings]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is TabContainer:
			tabs = node
			break
		for child in node.get_children():
			pending.append(child)
	if tabs != null:
		tabs.current_tab = 2
		await capture("settings-controls")
	else:
		check(false, "Settings Controls tab exists")
	for action in ["Cases", "Credits"]:
		var trigger := button(level._settings, action)
		check(trigger != null, action + " button exists")
		if trigger == null:
			continue
		trigger.pressed.emit()
		await frames(2)
		var dialog: AcceptDialog = level._settings._cases if action == "Cases" else level._settings._credits
		check(dialog.visible and dialog.get_parent() == level._settings, action + " production dialog is visible")
		if action == "Credits":
			var credit_text := ""
			for child in dialog.get_children():
				if child is RichTextLabel:
					credit_text += child.text
			check(credit_text.contains("OpenStreetMap") and credit_text.contains("openstreetmap.org/copyright"), "Credits retains map source and licence information")
		await capture(action.to_lower())
		dialog.hide()
	var result := {"captures": captures, "failures": failures, "viewport": [1600, 900], "source": "production Pen Lucy UI, embedded subwindows, private offscreen viewport"}
	var file := FileAccess.open(OUTPUT.path_join("capture-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
	get_tree().quit(1 if failures else 0)
