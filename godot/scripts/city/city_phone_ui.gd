extends RefCounted
## Handset chrome for the in-world phone: bezel, status bar, app tiles,
## navigation and the camera viewfinder. Original design in the HUD fonts and
## shared vector symbols; no image assets, emoji or OS integration.
const T := preload("res://scripts/ui/hud_theme.gd")
const Icons := preload("res://scripts/city/city_ui_icons.gd")
const CASE := Color("1b2126")
const CASE_EDGE := Color("46525a")
const SCREEN := Color("0f1c22")
const CARD := Color("1c2f36")
const CARD_HOVER := Color("27424b")
const TEXT := Color("eff2e8")
const MUTED := Color("a3b4ae")
const ACCENT := T.TICKET
const ASPECT := 0.49 # width / height of the whole handset
const BEZEL := Vector4(12, 30, 12, 24) # left, top, right, bottom
const APPS := [
	{"page": "contacts", "title": "Contacts", "key": "1", "color": Color("70e0da")},
	{"page": "camera", "title": "Camera", "key": "2", "color": Color("f2d24a")},
	{"page": "photos", "title": "Photos", "key": "3", "color": Color("e4b47c")},
	{"page": "cases", "title": "Cases", "key": "4", "color": Color("dda6d1")},
	{"page": "police", "title": "Police", "key": "5", "color": Color("7cbcff")},
]

## Portrait handset placement for a logical viewport. Always fully on screen.
static func handset_rect(view: Vector2) -> Rect2:
	var height := clampf(view.y * 0.9, 360.0, 820.0)
	var width := height * ASPECT
	if width > view.x - 32.0:
		width = maxf(160.0, view.x - 32.0)
		height = minf(height, width / ASPECT)
	var x := clampf(view.x * 0.64 - width * 0.5, 16.0, maxf(16.0, view.x - width - 16.0))
	return Rect2(Vector2(x, (view.y - height) * 0.5), Vector2(width, height))

static func screen_rect(handset: Rect2) -> Rect2:
	return Rect2(handset.position + Vector2(BEZEL.x, BEZEL.y), handset.size - Vector2(BEZEL.x + BEZEL.z, BEZEL.y + BEZEL.w))

static func flat(color: Color, radius: int, border := 0, border_color := Color.TRANSPARENT, pad := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border)
	box.border_color = border_color
	box.set_content_margin_all(pad)
	box.anti_aliasing_size = 0.8
	return box

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = T.body(600)
	result.default_font_size = 19
	result.set_color("font_color", "Label", TEXT)
	for state in ["normal", "disabled"]:
		result.set_stylebox(state, "Button", flat(CARD, 12, 0, Color.TRANSPARENT, 10))
	for state in ["hover", "pressed", "hover_pressed"]:
		result.set_stylebox(state, "Button", flat(CARD_HOVER, 12, 0, Color.TRANSPARENT, 10))
	var focus := flat(Color.TRANSPARENT, 12, 3, ACCENT)
	focus.draw_center = false
	result.set_stylebox("focus", "Button", focus)
	result.set_font("font", "Button", T.body(700))
	result.set_font_size("font_size", "Button", 19)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		result.set_color(state, "Button", TEXT)
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	return result

static func text(value: String, size := 19, color := TEXT, kind := "body600") -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.label_settings = T.ls(T.font(kind), size, color)
	return label

static func card(child: Control, accent := Color.TRANSPARENT) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := flat(CARD, 12, 0, Color.TRANSPARENT, 12)
	if accent.a > 0.0:
		box.border_width_left = 4
		box.border_color = accent
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(child)
	return panel

## Physical handset: bezel, earpiece, side keys and a rounded screen.
class Handset extends Control:
	var screen: PanelContainer
	func _init() -> void:
		name = "Handset"
		mouse_filter = Control.MOUSE_FILTER_STOP # Clicks on the bezel never reach the world.
		for side_key in [[-3.0, 0.18, 0.07], [-3.0, 0.27, 0.07], [1.0, 0.22, 0.10]]:
			var key := Panel.new()
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			key.add_theme_stylebox_override("panel", T.flat(CASE_EDGE, 2))
			key.set_meta("side", side_key)
			add_child(key)
		screen = PanelContainer.new()
		screen.name = "Screen"
		screen.add_theme_stylebox_override("panel", T.flat(SCREEN, 26))
		screen.clip_contents = true
		add_child(screen)
	func arrange() -> void:
		screen.position = Vector2(BEZEL.x, BEZEL.y)
		screen.size = size - Vector2(BEZEL.x + BEZEL.z, BEZEL.y + BEZEL.w)
		for child in get_children():
			if child.has_meta("side"):
				var side: Array = child.get_meta("side")
				child.position = Vector2(float(side[0]) if float(side[0]) < 0.0 else size.x - 1.0, size.y * float(side[1]))
				child.size = Vector2(4, size.y * float(side[2]))
		queue_redraw()
	func _draw() -> void:
		var whole := Rect2(Vector2.ZERO, size)
		draw_style_box(T.flat(Color(0, 0, 0, 0.35), 40), whole.grow(6).grow_individual(0, 0, 4, 6))
		draw_style_box(T.flat(CASE, 38, 3, CASE_EDGE), whole)
		var slot := Rect2(Vector2(size.x * 0.5 - 26, 12), Vector2(52, 5))
		draw_style_box(T.flat(Color("0b1013"), 3), slot)
		draw_circle(Vector2(size.x * 0.5 + 44, 14.5), 4.0, Color("0b1013"))
		draw_circle(Vector2(size.x * 0.5 + 44, 14.5), 1.6, Color("2b3f52"))

## One app on the home screen: rounded tile, vector symbol, name and key.
class AppTile extends BaseButton:
	var kind := ""
	var title := ""
	var color := Color.WHITE
	var key_hint := ""
	var badge := ""
	func _init(app_kind: String, app_title: String, app_color: Color, hint: String) -> void:
		kind = app_kind
		title = app_title
		color = app_color
		key_hint = hint
		name = "App_" + app_kind
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(76, 92)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tooltip_text = "%s  (%s)" % [title, key_hint]
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
			queue_redraw()
	func _draw() -> void:
		var side := minf(size.x - 14.0, 60.0)
		var tile := Rect2(Vector2((size.x - side) * 0.5, 4), Vector2(side, side))
		var hot := is_hovered() or has_focus()
		var down := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
		draw_style_box(T.flat(color.darkened(0.2) if down else color, 16, 3 if hot else 0, ACCENT if has_focus() else TEXT), tile)
		Icons.draw_glyph(self, kind, tile.get_center(), side * 0.3, CASE)
		var font := T.body(700)
		draw_string(font, Vector2(0, tile.end.y + 20), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, TEXT)
		var mono := T.mono(true)
		var key_at := tile.position + Vector2(-4, -2)
		draw_circle(key_at + Vector2(8, 8), 9.0, CASE, true, -1.0, true)
		draw_string(mono, key_at + Vector2(8 - 4.5, 13), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
		if not badge.is_empty():
			var at := Vector2(tile.end.x - 4, tile.position.y + 4)
			var width := maxf(18.0, mono.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0)
			draw_style_box(T.flat(T.SIREN, 9), Rect2(at - Vector2(width * 0.5, 9), Vector2(width, 18)))
			draw_string(mono, at + Vector2(-width * 0.5, 5), badge, HORIZONTAL_ALIGNMENT_CENTER, width, 13, TEXT)

## Back / Home / Put-away soft keys along the bottom of the screen.
class NavKey extends BaseButton:
	var glyph := ""
	var title := ""
	func _init(kind: String, label: String) -> void:
		glyph = kind
		title = label
		name = "Nav_" + kind
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(64, 46)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tooltip_text = label
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
			queue_redraw()
	func _draw() -> void:
		var hot := is_hovered() or has_focus()
		if hot:
			draw_style_box(T.flat(CARD_HOVER, 12, 2 if has_focus() else 0, ACCENT), Rect2(Vector2(3, 2), size - Vector2(6, 4)))
		Icons.draw_glyph(self, glyph, Vector2(size.x * 0.5, 15), 8.0, TEXT if hot else MUTED)
		draw_string(T.body(600), Vector2(0, size.y - 8), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, TEXT if hot else MUTED)

## Small round symbol used for contact avatars and app headers.
class Glyph extends Control:
	var kind := ""
	var color := Color.WHITE
	var initials := ""
	func _init(glyph_kind: String, glyph_color: Color, diameter := 40.0, letters := "") -> void:
		kind = glyph_kind
		color = glyph_color
		initials = letters
		custom_minimum_size = Vector2(diameter, diameter)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, radius, color, true, -1.0, true)
		if initials.is_empty():
			Icons.draw_glyph(self, kind, size * 0.5, radius * 0.55, CASE)
		else:
			draw_string(T.body(700), Vector2(0, size.y * 0.5 + 7), initials, HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, CASE)

## Full-screen camera framing. The saved exposure never includes this layer.
class Viewfinder extends Control:
	var zoom_text := ""
	var notice := ""
	var flash := 0.0
	func _init() -> void:
		name = "Viewfinder"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var inset := size * 0.06
		var arm := minf(size.x, size.y) * 0.07
		var color := Color(1, 1, 1, 0.85)
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var at: Vector2 = inset + (size - inset * 2.0) * corner
			var sx := 1.0 if corner.x == 0.0 else -1.0
			var sy := 1.0 if corner.y == 0.0 else -1.0
			draw_polyline(PackedVector2Array([at + Vector2(sx * arm, 0), at, at + Vector2(0, sy * arm)]), color, 3.0, true)
		var centre := size * 0.5
		draw_arc(centre, 18.0, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.5, true)
		draw_line(centre - Vector2(6, 0), centre + Vector2(6, 0), color, 1.5, true)
		draw_line(centre - Vector2(0, 6), centre + Vector2(0, 6), color, 1.5, true)
		var font := T.mono(true)
		draw_string_outline(font, inset + Vector2(4, 34), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color("111b24"))
		draw_string(font, inset + Vector2(4, 34), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT)
		if not notice.is_empty():
			draw_string_outline(font, inset + Vector2(4, 64), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color("111b24"))
			draw_string(font, inset + Vector2(4, 64), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ACCENT)
		if flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash * 0.6))
