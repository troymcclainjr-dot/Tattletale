extends Control
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
const C := preload("res://scripts/city/city_theme.gd")
const T := C.T
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
const Icons := preload("res://scripts/city/city_ui_icons.gd")
## Map key: the same vector symbols the map and radar draw.
const KEY := [["police", "Police"], ["fire", "Fire"], ["hospital", "Hospital"], ["court", "Courthouse"],
	["shop", "Shop"], ["food", "Food"], ["service", "Service"], ["studio", "Studio"], ["park", "Park"],
	["landmark", "Landmark"], ["contact", "Neighbor"], ["you", "You"], ["bicycle", "Your bicycle"],
	["destination", "Destination"], ["route", "Case route"], ["sports_court", "Sports court"], ["building", "Building"]]
var level: Node3D
var map: Control
var key: HFlowContainer
var _close_button: Button

class KeySymbol extends Control:
	var kind := ""
	func _init(symbol: String) -> void:
		kind = symbol
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var at := size * 0.5
		match kind:
			"you":
				draw_circle(at, 11, T.INK)
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(6, 6), at + Vector2(-6, 6)]), Icons.COLORS.you)
			"contact":
				draw_circle(at, 6.5, Icons.INK)
				draw_circle(at, 5.0, Icons.COLORS.contact)
			"bicycle":
				draw_circle(at, 10, T.INK)
				Icons.draw_glyph(self, "bicycle", at, 8.0, Icons.COLORS.bicycle)
			"destination":
				draw_circle(at, 10, T.INK)
				draw_arc(at, 8, 0, TAU, 24, T.TICKET, 3.0, true)
				draw_circle(at, 3, T.TICKET)
			"route":
				draw_line(at - Vector2(11, 0), at + Vector2(11, 0), T.INK, 8.0, true)
				draw_line(at - Vector2(11, 0), at + Vector2(11, 0), T.TICKET, 4.5, true)
			"sports_court":
				draw_rect(Rect2(at - Vector2(10, 7), Vector2(20, 14)), Icons.SPORTS_COURT)
				draw_rect(Rect2(at - Vector2(10, 7), Vector2(20, 14)), Icons.SPORTS_COURT_EDGE, false, 1.5)
			"building":
				draw_rect(Rect2(at - Vector2(9, 8), Vector2(18, 16)), Color("877d71"))
				draw_rect(Rect2(at - Vector2(9, 8), Vector2(18, 16)), Color("b4a691"), false, 1.0)
			_:
				Icons.draw_badge(self, kind, at, 9.0)

func setup(owner_level: Node3D, close_action: Callable = Callable()) -> void:
	level = owner_level
	theme = C.theme()
	name = "NeighborhoodMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = T.INK
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "PEN LUCY  /  NEIGHBORHOOD MAP"
	C.text(title, "display", 26, T.TICKET)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	map = MapCanvas.new()
	map.level = level
	map.full_map = true
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	column.add_child(row)
	var close_callback: Callable = close_action if close_action.is_valid() else level.resume_exploring
	for definition in [["−", func(): map.zoom_by(0.8)], ["+", func(): map.zoom_by(1.25)], ["Whole neighborhood", func(): map.fit_neighborhood()], ["Find me", func(): map.center_player()], ["Close map", close_callback]]:
		var button := Button.new()
		button.text = definition[0]
		button.custom_minimum_size = Vector2(52, 42)
		button.pressed.connect(definition[1])
		row.add_child(button)
		if definition[0] == "Close map":
			_close_button = button
	visibility_changed.connect(func():
		if visible and _close_button != null:
			_close_button.text = "Close map  ·  " + Bindings.label("city_map"))
	key = HFlowContainer.new()
	key.name = "MapKey"
	key.add_theme_constant_override("h_separation", 16)
	key.add_theme_constant_override("v_separation", 4)
	column.add_child(key)
	for entry in KEY:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(KeySymbol.new(str(entry[0])))
		var label := Label.new()
		label.text = str(entry[1])
		C.text(label, "mono", 15, T.PAPER)
		item.add_child(label)
		key.add_child(item)
	var hint := Label.new()
	hint.text = "Wheel or +/− zoom  ·  drag to pan  ·  point at or click a symbol for its name"
	C.text(hint, "mono", 14, T.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	hide()
