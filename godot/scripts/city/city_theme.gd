extends RefCounted
## Pen Lucy uses the original block's font resolver, palette and case-file boxes.
const T := preload("res://scripts/ui/hud_theme.gd")

static func theme() -> Theme:
	var result: Theme = T.theme().duplicate()
	result.default_font = T.body(600)
	result.default_font_size = 20
	result.set_color("font_color", "Label", T.INK)
	for type in ["Button", "OptionButton", "CheckButton"]:
		result.set_font("font", type, T.body(700))
		result.set_font_size("font_size", type, 20)
		for state in ["normal", "hover", "pressed", "disabled"]:
			result.set_stylebox(state, type, T.box(T.TICKET if state == "hover" else T.PAPER, [8, 14, 8, 14], 3, 2, T.INK))
		result.set_stylebox("focus", type, T.focus_ring())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(state, type, T.INK)
	for type in ["TabContainer", "TabBar"]:
		result.set_font("font", type, T.body(700))
		result.set_font_size("font_size", type, 21)
		result.set_stylebox("tab_selected", type, T.box(T.TICKET, [8, 18, 8, 18], 3))
		result.set_stylebox("tab_unselected", type, T.box(T.INK, [8, 18, 8, 18], 3))
		result.set_color("font_selected_color", type, T.INK)
		result.set_color("font_unselected_color", type, T.PAPER)
	result.set_stylebox("panel", "TabContainer", T.box(T.PAPER, [18, 20, 18, 20], 3))
	return result

static func case_file() -> StyleBox:
	return T.striped(T.PAPER, [14, 18, 14, 20], 3, T.SIREN, 5, Vector2(3, 3), T.a(T.BLACK, 0.35))

static func settings_theme() -> Theme:
	var result := theme()
	result.set_color("font_color", "Label", T.PAPER)
	for type in ["Button", "OptionButton", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			result.set_stylebox(state, type, T.box(T.INK if state in ["hover", "pressed"] else T.BLACK, [8, 14, 8, 14], 3, 1, T.TICKET if state == "hover" else T.DIM))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(state, type, T.PAPER)
	for type in ["TabContainer", "TabBar"]:
		result.set_stylebox("tab_unselected", type, T.box(T.BLACK, [8, 18, 8, 18], 3))
		result.set_color("font_unselected_color", type, T.PAPER)
	result.set_stylebox("panel", "TabContainer", T.box(T.BLACK, [18, 20, 18, 20], 3, 1, T.DIM))
	# HSlider sizes its rail from the StyleBox minimum height. A zero-padding
	# box produces a zero-height rail, leaving only the grabber visible.
	result.set_stylebox("slider", "HSlider", T.box(T.DIM, [3, 0, 3, 0], 3))
	result.set_stylebox("grabber_area", "HSlider", T.box(T.TICKET, [3, 0, 3, 0], 3))
	result.set_stylebox("grabber_area_highlight", "HSlider", T.box(T.TICKET, [3, 0, 3, 0], 3))
	return result

static func text(label: Label, kind: String, size: int, color: Color = T.INK) -> void:
	label.label_settings = T.ls(T.font(kind), size, color)
