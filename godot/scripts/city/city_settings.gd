extends Control
## Per-user neighborhood settings; all controls change the running game immediately.
const SAVE_PATH := "user://pen_lucy_settings.cfg"
var level: Node3D
var values: Dictionary = {"display": "Maximized", "quality": "Balanced", "vsync": true, "fps_cap": 120, "render_scale": 1.0, "master": 100.0, "music": 65.0, "sfx": 85.0, "sensitivity": 1.0, "invert_y": false}
var resume_button: Button

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "Settings"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for key in values:
			values[key] = config.get_value("settings", key, values[key])
	_sanitize()
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.045, 0.92)
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
	_toggle(video, "Vertical sync", "vsync")
	_choice(video, "Frame limit", "fps_cap", [30, 60, 90, 120, 144, 165, 240, 0])
	_slider(video, "Render scale", "render_scale", 0.5, 1.0, 0.05, true)
	var sound := _tab(tabs, "Audio")
	_slider(sound, "Master volume", "master", 0, 100, 1)
	_slider(sound, "Music volume", "music", 0, 100, 1)
	_slider(sound, "Sound effects", "sfx", 0, 100, 1)
	var controls := _tab(tabs, "Controls")
	_slider(controls, "Mouse sensitivity", "sensitivity", 0.25, 3.0, 0.05)
	_toggle(controls, "Invert vertical look", "invert_y")
	_heading(controls, "WASD  Move     Shift  Run\nMouse  Look     Hold right mouse  Orbit\nE  Interact     V  First / third person\nM  Map     Left / right arrows  Turn\nEsc  Settings / Resume\nMap: wheel or + / − to zoom; drag to pan", 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	resume_button = _button(row, "Resume", level.resume_exploring)
	_button(row, "Return to starting corner", func(): level.spawn_player(); level.resume_exploring())
	_button(row, "Main menu", func(): G.open_original_block())
	_heading(column, "Changes are applied immediately and saved for this user.", 14)
	hide()

func _sanitize() -> void:
	if values.display not in ["Windowed", "Maximized", "Fullscreen"]:
		values.display = "Maximized"
	if values.quality not in ["Low", "Balanced", "High"]:
		values.quality = "Balanced"
	values.render_scale = clampf(float(values.render_scale), 0.5, 1.0)
	values.sensitivity = clampf(float(values.sensitivity), 0.25, 3.0)
	values.fps_cap = clampi(int(values.fps_cap), 0, 360)
	for key in ["master", "music", "sfx"]:
		values[key] = clampf(float(values[key]), 0, 100)

func apply_settings(initial := false, changed_key := "") -> void:
	_sanitize()
	var capture_run := DisplayServer.get_name() == "headless"
	for argument in OS.get_cmdline_args():
		if argument == "--resolution" or argument.begins_with("--resolution=") or argument == "--headless":
			capture_run = true
	if (changed_key.is_empty() or changed_key == "display") and DisplayServer.get_name() != "headless" and not (initial and capture_run):
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
	if changed_key.is_empty() or changed_key == "render_scale":
		level.get_viewport().scaling_3d_scale = float(values.render_scale)
	if changed_key.is_empty() or changed_key in ["master", "music", "sfx"]:
		_bus("Master", float(values.master))
		_bus("Music", float(values.music))
		_bus("SFX", float(values.sfx))
		Audio.set_music(float(values.music) > 0)
		G.S.music_on = float(values.music) > 0
		if changed_key == "music" and float(values.music) > 0:
			Audio.start()
	if level.player != null and (changed_key.is_empty() or changed_key in ["sensitivity", "invert_y"]):
		level.player.mouse_sensitivity = 0.0024 * float(values.sensitivity)
		level.player.invert_y = bool(values.invert_y)

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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee9d9"))
	parent.add_child(label)
	return label

func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var label := _heading(row, title, 20)
	label.custom_minimum_size.x = 240
	return row

func _choice(parent: Node, title: String, key: String, options: Array) -> void:
	var row := _row(parent, title)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(240, 40)
	row.add_child(choice)
	for i in options.size():
		choice.add_item("Unlimited" if key == "fps_cap" and int(options[i]) == 0 else str(options[i]))
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
	slider.custom_minimum_size.x = 240
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var number := _heading(row, "%d%%" % roundi(slider.value * 100) if percent else str(snappedf(slider.value, 0.01)), 18)
	number.custom_minimum_size.x = 70
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
