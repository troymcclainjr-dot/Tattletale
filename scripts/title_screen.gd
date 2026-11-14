extends CanvasLayer
## The title screen: the game's name over the darkened street, and three
## things to pick: NEW GAME, CONTINUE (greyed out until there is a game to go
## back to) and SETTINGS. Settings has one switch so far, FULLSCREEN, and BACK.
##
## Pick with the mouse, or Up / Down and Enter. Esc backs out of settings; on
## the title itself it quits.
##
##   var title: CanvasLayer = TitleScreen.new()
##   add_child(title)
##   title.open(can_continue, fullscreen_now)
##   title.new_game.connect(...)   title.continue_game.connect(...)   title.fullscreen_set.connect(func(on): ...)

signal new_game
signal continue_game
signal fullscreen_set(on: bool)

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
	_settings.add_child(_button("BACK", _show_settings.bind(false)))
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
