extends Control
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
var level: Node3D
var map: Control

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "NeighborhoodMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("0c1d20")
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "PEN LUCY  /  NEIGHBORHOOD MAP"
	title.add_theme_font_size_override("font_size", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	map = MapCanvas.new()
	map.level = level
	map.full_map = true
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for definition in [["−", func(): map.zoom_by(0.8)], ["+", func(): map.zoom_by(1.25)], ["Whole neighborhood", func(): map.fit_neighborhood()], ["Find me", func(): map.center_player()], ["Close map  ·  M", level.resume_exploring]]:
		var button := Button.new()
		button.text = definition[0]
		button.custom_minimum_size = Vector2(52, 42)
		button.pressed.connect(definition[1])
		row.add_child(button)
	var legend := Label.new()
	legend.text = "White arrow: you   ·   Gold: walk stops   ·   Teal: contacts / current case   ·   Wheel to zoom, drag to pan"
	legend.add_theme_font_size_override("font_size", 15)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(legend)
	hide()
