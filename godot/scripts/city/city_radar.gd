extends Control
## Small camera-relative radar; native canvas masking keeps it truly circular.
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
var map: Control

func setup(level: Node3D) -> void:
	name = "CircularMinimap"
	custom_minimum_size = Vector2(208, 208)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	map = MapCanvas.new()
	map.level = level
	map.full_map = false
	map.scale_metres = 1.65
	add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, Color("101d20"), true, -1.0, true)
