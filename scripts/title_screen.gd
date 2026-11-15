extends CanvasLayer
## The title screen: the game's name over the darkened street, and three
## things to pick: NEW GAME, CONTINUE (greyed out until there is a game to go
## back to) and SETTINGS. Settings has FULLSCREEN, MUSIC (how loud the beats
## and the voice are: Enter or a click goes up a tenth and round to 0%, Left /
## Right a tenth down or up) and BACK.
##
## Pick with the mouse, or Up / Down and Enter. Esc backs out of settings; on
## the title itself it quits.
##
##   var title: CanvasLayer = TitleScreen.new()
##   add_child(title)
##   title.open(can_continue, fullscreen_now)
##   title.set_music(level)        # 0 .. 1, what the MUSIC row shows
##   title.new_game.connect(...)   title.continue_game.connect(...)   title.fullscreen_set.connect(func(on): ...)
##   title.music_set.connect(func(level): ...)

signal new_game
signal continue_game
signal fullscreen_set(on: bool)
signal music_set(level: float)

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const FAINT := Color(0.96, 0.94, 0.89, 0.3)

var _menu: VBoxContainer
var _settings: VBoxContainer
var _new: Button
var _continue: Button
var _full: Button
var _fullscreen := false
var _music: Button
var _level := 0.8


func _init() -> void:
	layer = 18          # under main.gd's fade, over everything else
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	centre.add_child(column)

	var title := _label("TATTLETALE", 124, TICKET)
	title.add_theme_constant_override("outline_size", 18)
	column.add_child(title)
	column.add_child(_label("A POP-UP PROTOTYPE", 20, PAPER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 46)
	column.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	column.add_child(_menu)
	_new = _button("NEW GAME", func() -> void: new_game.emit())
	_menu.add_child(_new)
	_continue = _button("CONTINUE", func() -> void: continue_game.emit())
	_menu.add_child(_continue)
	_menu.add_child(_button("SETTINGS", _show_settings.bind(true)))

	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 4)
	column.add_child(_settings)
	_full = _button("", _toggle_fullscreen)
	_settings.add_child(_full)
	_music = _button("", _step_music.bind(0.1, true))
	_music.gui_input.connect(_music_keys)
	_settings.add_child(_music)
	_settings.add_child(_button("BACK", _show_settings.bind(false)))
	set_music(_level)
	visible = false


func is_open() -> bool:
	return visible


func open(can_continue: bool, fullscreen := false) -> void:
	_continue.disabled = not can_continue
	_continue.focus_mode = Control.FOCUS_ALL if can_continue else Control.FOCUS_NONE
	_continue.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_continue else Control.CURSOR_ARROW
	_fullscreen = fullscreen
	visible = true
	_show_settings(false)


func close() -> void:
	visible = false


func _show_settings(on: bool) -> void:
	_menu.visible = not on
	_settings.visible = on
	_full.text = "FULLSCREEN    %s" % ("ON" if _fullscreen else "OFF")
	(_full if on else _new).grab_focus.call_deferred()


func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	_full.text = "FULLSCREEN    %s" % ("ON" if _fullscreen else "OFF")
	fullscreen_set.emit(_fullscreen)


## What the MUSIC row shows (main.gd's setting), 0 .. 1.
func set_music(level: float) -> void:
	_level = clampf(snappedf(level, 0.1), 0.0, 1.0)
	_music.text = "MUSIC    %d%%" % roundi(_level * 100.0)


## A tenth up or down; `round_to_zero`: past 100% it goes back to 0%.
func _step_music(by: float, round_to_zero := false) -> void:
	var to := snappedf(_level + by, 0.1)
	if round_to_zero and to > 1.0001:
		to = 0.0
	set_music(to)
	music_set.emit(_level)


## Left / Right on the MUSIC row.
func _music_keys(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and (key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_RIGHT):
		_step_music(0.1 if key.physical_keycode == KEY_RIGHT else -0.1)
		_music.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo or event.physical_keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _settings.visible:
		_show_settings(false)
	else:
		get_tree().quit()


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	return label


## A line of the menu: plain words that turn yellow under the mouse or the
## keyboard's choice, and grey when they cannot be picked.
func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", TICKET)
	b.add_theme_color_override("font_focus_color", TICKET)
	b.add_theme_color_override("font_pressed_color", TICKET)
	b.add_theme_color_override("font_hover_pressed_color", TICKET)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	b.pressed.connect(pressed)
	return b
