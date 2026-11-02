extends Control
## Per-user neighborhood settings; all controls change the running game immediately.
const C := preload("res://scripts/city/city_theme.gd")
const T := C.T
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
const SAVE_PATH := "user://pen_lucy_settings.cfg"
var level: Node3D
var values: Dictionary = {"display": "Maximized", "quality": "Balanced", "clouds": "Volumetric", "vsync": true, "fps_cap": 120, "render_scale": 1.0, "master": 100.0, "music": 65.0, "sfx": 85.0, "sensitivity": 1.0, "invert_y": false, "fov": 68.0, "ui_scale": 1.0}
var _save_feedback: Label
var _recover_button: Button
var _recover_confirmation: ConfirmationDialog
var _cases: AcceptDialog
var _case_text: RichTextLabel
var _credits: AcceptDialog
var resume_button: Button
var _binding_buttons: Dictionary = {}
var _binding_feedback: Label
var _waiting_action := ""
var _load_confirmation: ConfirmationDialog
var _fresh_confirmation: ConfirmationDialog
var _load_button: Button

func setup(owner_level: Node3D) -> void:
	level = owner_level
	Bindings.load_bindings()
	theme = C.settings_theme()
	name = "Settings"
	visibility_changed.connect(func():
		if not visible:
			_waiting_action = "")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for key in values:
			values[key] = config.get_value("settings", key, values[key])
	_sanitize()
	var shade := ColorRect.new()
	shade.name = "SettingsBackground"
	shade.color = T.BLACK
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margins := MarginContainer.new()
	add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 28)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margins.add_child(column)
	_heading(column, "SETTINGS", 30)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var video := _tab(tabs, "Video")
	_choice(video, "Display mode", "display", ["Windowed", "Maximized", "Fullscreen"])
	_choice(video, "Graphics quality", "quality", ["Low", "Balanced", "High"])
	_choice(video, "Clouds", "clouds", ["Off", "Simple", "Volumetric"])
	_toggle(video, "Vertical sync", "vsync")
	_choice(video, "Frame limit", "fps_cap", [30, 60, 90, 120, 144, 165, 240, 0])
	_slider(video, "Render scale", "render_scale", 0.5, 1.0, 0.05, true)
	_slider(video, "Camera field of view", "fov", 55.0, 90.0, 1.0)
	_choice(video, "Text size", "ui_scale", [1.0, 1.1, 1.25])
	var sound := _tab(tabs, "Audio")
	_slider(sound, "Master volume", "master", 0, 100, 1)
	_slider(sound, "Music volume", "music", 0, 100, 1)
	_slider(sound, "Sound effects", "sfx", 0, 100, 1)
	var controls := _tab(tabs, "Controls")
	_slider(controls, "Mouse sensitivity", "sensitivity", 0.25, 3.0, 0.05)
	_toggle(controls, "Invert vertical look", "invert_y")
	_heading(controls, "Choose an action, then press a key. Esc cancels. Duplicate keys are refused. Mouse aiming and menu navigation remain available.", 18)
	_binding_feedback = _heading(controls, "", 16)
	for action in Bindings.DEFAULTS:
		var binding_row := _row(controls, str(Bindings.TITLES[action]))
		var bind_button := _button(binding_row, Bindings.label(action), _begin_rebind.bind(str(action)))
		bind_button.custom_minimum_size.x = 180
		_binding_buttons[action] = bind_button
	_button(controls, "Reset controls", _reset_bindings)
	_heading(controls, "Hold right mouse to orbit. Bicycle steering follows the bicycle, independent of the camera.\nPhone: 1–5 pages; Enter confirms; Esc back. Conversations: Enter continues; arrows choose.\nMap: wheel or + / − zoom; drag to pan. F6 inspector; F7 copy; F8 screenshot.", 18)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	column.add_child(row)
	resume_button = _button(row, "Resume", level.resume_exploring)
	_button(row, "Return to starting corner", func(): level.spawn_player(); level.resume_exploring())
	_button(row, "Save progress", func(): refresh_checkpoint_status(str(level.save_progress())))
	_load_button = _button(row, "Load checkpoint", _confirm_load)
	_button(row, "Start fresh…", _confirm_fresh)
	_recover_button = _button(row, "Recover saving…", _confirm_recovery)
	_recover_button.hide()
	_button(row, "Main menu", level.return_to_original)
	_button(row, "Cases", _show_cases)
	_button(row, "Credits", _show_credits)
	_save_feedback = Label.new()
	_save_feedback.text = "Settings save immediately. Progress autosaves every 30 seconds when safe, including on a stopped bicycle. Pending saves wait until it is safe."
	_save_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	C.text(_save_feedback, "body600", 14, T.PAPER)
	column.add_child(_save_feedback)
	hide()

func refresh_checkpoint_status(feedback := "") -> void:
	var save: Node = level.get("world_save")
	var blocked: bool = save != null and bool(save.get_status().write_blocked)
	_recover_button.visible = blocked
	_load_button.disabled = save == null or not save.enabled or not save.has_checkpoint_candidates()
	# Operation feedback must survive refreshing button availability in this
	# same open menu (first save, temporary recovery, or a refused operation).
	if not feedback.is_empty():
		_save_feedback.text = feedback
		return
	if blocked:
		_save_feedback.text = "Saving is paused: %s. Your previous checkpoint is preserved." % save.last_result
	elif save != null and save.enabled:
		var age := float(save.get_status().age_seconds)
		var last := "No checkpoint saved yet." if age < 0.0 else "Last checkpoint: %d minute(s) ago." % floori(age / 60.0)
		_save_feedback.text = last + (" Ready to save." if save.can_checkpoint() else " Saving waits for a safe stop on solid ground.")

func _show_cases() -> void:
	if _cases == null:
		_cases = AcceptDialog.new()
		_cases.title = "Neighborhood cases"
		_case_text = RichTextLabel.new()
		_case_text.custom_minimum_size = Vector2(660, 420)
		_cases.add_child(_case_text)
		add_child(_cases)
	var missions: Node = level.get("missions")
	var lines: Array[String] = ["Current case status. Contact availability reflects this world; cancelled attempts are not recorded.", ""]
	if missions != null:
		var status: Dictionary = missions.get_status()
		lines.append("%d / %d completed · %d community points" % [int(status.completed), int(status.total), int(status.score)])
		for entry in status.cases:
			lines.append("\n%s — %s\n%s" % [str(entry.title), str(entry.state).capitalize(), str(entry.reason)])
		for entry in status.get("story", []):
			lines.append("\n%s — %s\n%s" % [str(entry.title), str(entry.state).capitalize(), str(entry.reason)])
	else:
		lines.append("Cases are not available in this scene.")
	_case_text.text = "\n".join(lines)
	apply_text_scale()
	_cases.popup_centered()

func _show_credits() -> void:
	if _credits == null:
		_credits = AcceptDialog.new()
		_credits.title = "Credits and notices"
		var text := RichTextLabel.new()
		text.custom_minimum_size = Vector2(660, 420)
		text.text = FileAccess.get_file_as_string("res://assets/data/release_notices.txt") if FileAccess.file_exists("res://assets/data/release_notices.txt") else "Map data © OpenStreetMap contributors\nhttps://www.openstreetmap.org/copyright\n\nBuilt with Godot Engine."
		_credits.add_child(text)
		add_child(_credits)
	apply_text_scale()
	_credits.popup_centered()

func _confirm_recovery() -> void:
	if _recover_confirmation == null:
		_recover_confirmation = ConfirmationDialog.new()
		_recover_confirmation.title = "Use this world as the new checkpoint?"
		_recover_confirmation.dialog_text = "The old checkpoint will be kept as a recovery copy. The world you are playing now will become your new saved progress."
		_recover_confirmation.ok_button_text = "Preserve old save and continue"
		_recover_confirmation.confirmed.connect(func():
			var result: Error = level.world_save.recover_saving()
			refresh_checkpoint_status("Stop on solid ground before recovering saving." if result == ERR_BUSY else str(level.world_save.last_result)))
		add_child(_recover_confirmation)
	_prepare_confirmation(_recover_confirmation)
	_recover_confirmation.popup_centered(Vector2i(580, 180))

func _sanitize() -> void:
	if values.display not in ["Windowed", "Maximized", "Fullscreen"]:
		values.display = "Maximized"
	if values.quality not in ["Low", "Balanced", "High"]:
		values.quality = "Balanced"
	if values.clouds not in ["Off", "Simple", "Volumetric"]:
		values.clouds = "Volumetric"
	values.render_scale = clampf(float(values.render_scale), 0.5, 1.0)
	values.ui_scale = clampf(float(values.ui_scale), 1.0, 1.25)
	values.fov = clampf(float(values.fov), 55.0, 90.0)
	values.sensitivity = clampf(float(values.sensitivity), 0.25, 3.0)
	values.fps_cap = clampi(int(values.fps_cap), 0, 360)
	for key in ["master", "music", "sfx"]:
		values[key] = clampf(float(values[key]), 0, 100)

func apply_settings(initial := false, changed_key := "") -> void:
	_sanitize()
	if changed_key.is_empty() or changed_key == "ui_scale":
		apply_text_scale()
	var capture_run := DisplayServer.get_name() == "headless"
	for argument in OS.get_cmdline_args():
		if argument == "--resolution" or argument.begins_with("--resolution=") or argument == "--headless":
			capture_run = true
	if not level.offscreen_validation and (changed_key.is_empty() or changed_key == "display") and DisplayServer.get_name() != "headless" and not (initial and capture_run):
		match str(values.display):
			"Fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"Maximized": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			_: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.get_name() != "headless" and (changed_key.is_empty() or changed_key == "vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.vsync) else DisplayServer.VSYNC_DISABLED)
	if changed_key.is_empty() or changed_key == "fps_cap":
		Engine.max_fps = int(values.fps_cap)
	if level.render_optimizer != null and (changed_key.is_empty() or changed_key == "quality"):
		level.render_optimizer.set_quality(str(values.quality).to_lower())
	if level.get("day_night") != null and (changed_key.is_empty() or changed_key == "clouds"):
		level.day_night.set_cloud_quality(["Off", "Simple", "Volumetric"].find(values.clouds))
	if changed_key.is_empty() or changed_key == "render_scale":
		level.get_viewport().scaling_3d_scale = float(values.render_scale)
	if changed_key.is_empty() or changed_key in ["master", "music", "sfx"]:
		_bus("Master", float(values.master))
		_bus("Music", float(values.music))
		_bus("SFX", float(values.sfx))
		Audio.set_music(float(values.music) > 0)
		G.S.music_on = float(values.music) > 0
		if (initial or changed_key == "music") and float(values.music) > 0:
			Audio.start()
	if level.player != null and (changed_key.is_empty() or changed_key in ["sensitivity", "invert_y"]):
		level.player.mouse_sensitivity = 0.0024 * float(values.sensitivity)
		level.player.invert_y = bool(values.invert_y)
	if level.player != null and (changed_key.is_empty() or changed_key == "fov"):
		level.player.camera_fov = float(values.fov)
		level.player.update_camera()

func _bus(bus_name: String, percent: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		var mix_gain := 0.3 if bus_name == "Music" else (0.7 if bus_name == "SFX" else 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(percent * 0.01 * mix_gain, 0.0001)))
		AudioServer.set_bus_mute(index, percent <= 0)

func _change(key: String, value) -> void:
	values[key] = value
	apply_settings(false, key)
	var config := ConfigFile.new()
	for setting in values:
		config.set_value("settings", setting, values[setting])
	if config.save(SAVE_PATH) != OK:
		level.show_notice("Settings work for this visit, but could not be saved.")

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 20)
	scroll.add_child(box)
	return box

func _heading(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	C.text(label, "display" if font_size >= 30 else "body600", font_size, T.PAPER)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var label := _heading(row, title, 20)
	label.custom_minimum_size.x = 180
	return row

func _choice(parent: Node, title: String, key: String, options: Array) -> void:
	var row := _row(parent, title)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(240, 40)
	row.add_child(choice)
	for i in options.size():
		choice.add_item(("%d%%" % roundi(float(options[i]) * 100)) if key == "ui_scale" else ("Unlimited" if key == "fps_cap" and int(options[i]) == 0 else str(options[i])))
		if options[i] == values[key]:
			choice.select(i)
	choice.item_selected.connect(func(index: int): _change(key, options[index]))

func _toggle(parent: Node, title: String, key: String) -> void:
	var row := _row(parent, title)
	var check := CheckButton.new()
	check.button_pressed = bool(values[key])
	row.add_child(check)
	check.toggled.connect(func(on: bool): _change(key, on))

func _slider(parent: Node, title: String, key: String, low: float, high: float, step: float, percent := false) -> void:
	var row := _row(parent, title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(values[key])
	slider.name = "SettingSlider_" + key
	slider.custom_minimum_size.x = 120
	# The previous slider expanded across the whole remaining row. Give its
	# track half that space, including half the old 240px minimum, on every tab.
	var track := Control.new()
	track.custom_minimum_size = Vector2(240, 40)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(track)
	track.add_child(slider)
	slider.anchor_right = 0.5
	slider.anchor_top = 0.5
	slider.anchor_bottom = 0.5
	slider.offset_left = 0
	slider.offset_right = 0
	slider.offset_top = -12
	slider.offset_bottom = 12
	var number := _heading(track, "%d%%" % roundi(slider.value * 100) if percent else str(snappedf(slider.value, 0.01)), 18)
	number.name = "SliderValue"
	number.custom_minimum_size.x = 70
	number.anchor_left = 0.5
	number.anchor_right = 0.5
	number.anchor_top = 0.5
	number.anchor_bottom = 0.5
	number.offset_left = 12
	number.offset_right = 82
	number.offset_top = -14
	number.offset_bottom = 14
	slider.value_changed.connect(func(value: float):
		number.text = "%d%%" % roundi(value * 100) if percent else str(snappedf(value, 0.01))
		_change(key, value))

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _begin_rebind(action: String) -> void:
	_waiting_action = action
	_binding_feedback.text = "Press a key for %s; Esc cancels." % Bindings.TITLES[action]
	_binding_buttons[action].release_focus()

## Called before the level's Escape/map routing, including while paused.
func capture_binding(event: InputEvent) -> bool:
	if not visible or _waiting_action.is_empty():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_binding_feedback.text = "Binding cancelled."
			return true
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		_finish_rebind(code)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _waiting_action == "city_ball_shoot":
			_finish_rebind(-MOUSE_BUTTON_LEFT)
	return true

func _finish_rebind(code: int) -> void:
	var message := Bindings.rebind(_waiting_action, code)
	_binding_feedback.text = "Bound %s to %s." % [Bindings.TITLES[_waiting_action], Bindings.label(_waiting_action)] if message.is_empty() else message
	_refresh_bindings()
	_waiting_action = ""

func _refresh_bindings() -> void:
	for action in _binding_buttons:
		_binding_buttons[action].text = Bindings.label(action)

func _reset_bindings() -> void:
	_waiting_action = ""
	var result := Bindings.reset()
	_refresh_bindings()
	_binding_feedback.text = "Default controls restored." if result == OK else "Defaults restored for this visit, but could not be saved."

func _confirm_load() -> void:
	if _load_confirmation == null:
		_load_confirmation = ConfirmationDialog.new()
		_load_confirmation.title = "Load your checkpoint?"
		_load_confirmation.dialog_text = "Unsaved progress from this visit will be replaced. The checkpoint is validated before it is loaded."
		_load_confirmation.ok_button_text = "Load checkpoint"
		_load_confirmation.confirmed.connect(func():
			if level.has_method("load_checkpoint"):
				refresh_checkpoint_status(str(level.load_checkpoint())))
		add_child(_load_confirmation)
	_prepare_confirmation(_load_confirmation)
	_load_confirmation.popup_centered(Vector2i(580, 180))

func _confirm_fresh() -> void:
	if _fresh_confirmation == null:
		_fresh_confirmation = ConfirmationDialog.new()
		_fresh_confirmation.title = "Start a fresh neighborhood?"
		_fresh_confirmation.dialog_text = "Your existing checkpoint will be preserved as a recovery copy. A new visit starts at the starting corner with fresh progress."
		_fresh_confirmation.ok_button_text = "Preserve checkpoint and start fresh"
		_fresh_confirmation.confirmed.connect(func():
			if level.has_method("start_fresh_world"):
				refresh_checkpoint_status(str(level.start_fresh_world())))
		add_child(_fresh_confirmation)
	_prepare_confirmation(_fresh_confirmation)
	_fresh_confirmation.popup_centered(Vector2i(580, 180))

func _prepare_confirmation(dialog: ConfirmationDialog) -> void:
	# Dialog text/buttons are internal children, outside the ordinary UI walk.
	# Wrap long explanations so larger text grows vertically within the viewport.
	dialog.dialog_autowrap = true
	apply_text_scale_to(dialog.get_label())
	apply_text_scale_to(dialog.get_ok_button())
	apply_text_scale_to(dialog.get_cancel_button())

## Scale fonts, not the viewport: anchors, hit targets and scroll bounds stay put.
## Cache original sizes so repeated changes never compound.
func apply_text_scale() -> void:
	_scale_text_tree(get_parent(), float(values.ui_scale))

func apply_text_scale_to(node: Node) -> void:
	if node != null:
		_scale_text_tree(node, float(values.ui_scale))

func _scale_text_tree(node: Node, factor: float) -> void:
	if node is Label and node.label_settings != null:
		if not node.has_meta("city_base_font_size"):
			node.set_meta("city_base_font_size", node.label_settings.font_size)
			node.label_settings = node.label_settings.duplicate()
		node.label_settings.font_size = roundi(float(node.get_meta("city_base_font_size")) * factor)
	elif node is Label or node is Button or node is TabBar:
		if not node.has_meta("city_base_font_size"):
			node.set_meta("city_base_font_size", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("city_base_font_size")) * factor))
	elif node is RichTextLabel:
		for slot in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
			if not node.has_meta("city_base_" + slot):
				node.set_meta("city_base_" + slot, node.get_theme_font_size(slot))
			node.add_theme_font_size_override(slot, roundi(float(node.get_meta("city_base_" + slot)) * factor))
	for child in node.get_children():
		_scale_text_tree(child, factor)
