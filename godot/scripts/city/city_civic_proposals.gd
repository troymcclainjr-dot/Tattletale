extends Control
## Optional planning overlay only. Never registers mission/landmark destinations.
const DATA := "res://assets/data/pen_lucy_civic_proposals.json"
const COLORS := {"police": Color("82bdff"), "fire": Color("ff967d"), "hospital": Color("d7a6ff")}
var map: Control
var proposals: Array = []
var service_filter := "police"

func setup(map_canvas: Control) -> void:
	map = map_canvas
	name = "ProposedCivicSites"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if FileAccess.file_exists(DATA):
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if data is Dictionary:
			proposals = data.get("proposals", [])
	# Follow the full-map's existing redraw cadence; no independent process loop.
	map.draw.connect(queue_redraw)
	hide()

func _draw() -> void:
	if map == null:
		return
	var font := ThemeDB.fallback_font
	var list_at := Vector2(maxf(10, size.x - 310), 12)
	draw_rect(Rect2(list_at, Vector2(298, 83)), Color("18252e"))
	draw_string(font, list_at + Vector2(9, 18), service_filter.to_upper() + " / PROPOSED OPTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f1e7da"))
	var option_line := 0
	for proposal in proposals:
		if str(proposal.service) != service_filter:
			continue
		var color: Color = COLORS.get(str(proposal.service), Color.WHITE)
		draw_string(font, list_at + Vector2(9, 36 + option_line * 18), str(proposal.id) + (" *  " if proposal.recommended else "    ") + str(proposal.street), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		option_line += 1
		var polygon := PackedVector2Array()
		for point in proposal.polygon:
			polygon.append(map._map(Vector3(float(point[0]), 0, float(point[1]))))
		if polygon.size() < 3:
			continue
		draw_colored_polygon(polygon, Color(color, 0.20 if proposal.recommended else 0.08))
		draw_polyline(polygon, color, 2.5 if proposal.recommended else 1.0, true)
		var value: Array = proposal.position
		var at: Vector2 = map._map(Vector3(value[0], value[1], value[2]))
		if not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		var title := str(proposal.id) + (" *" if proposal.recommended else "")
		var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var label_position := at + Vector2(-text_size.x * 0.5, -9)
		draw_rect(Rect2(label_position - Vector2(4, 15), text_size + Vector2(8, 5)), Color("18252e"))
		draw_string(font, label_position, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	draw_rect(Rect2(Vector2(10, size.y - 53), Vector2(minf(size.x - 20, 790), 43)), Color("18252e"))
	draw_string(font, Vector2(18, size.y - 33), "PROPOSED ONLY  /  P: police   F: fire   H: hospital   * preferred option", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f1e7da"))
	draw_string(font, Vector2(18, size.y - 15), "Alternatives, not destinations. Existing homes and courts stay. Sites require approval before building.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("bdc9ce"))
