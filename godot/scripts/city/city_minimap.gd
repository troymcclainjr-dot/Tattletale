extends Control
## North-up geographic map. Full-map mode fits the neighborhood, supports zoom/pan.
var level: Node3D
var full_map := false
var scale_metres := 0.75
var zoom := 1.0
var map_center := Vector2.ZERO
var _bounds := Rect2(-220, -320, 800, 600)
var _dragging := false
var _refresh_time := 0.0
var _roads: Array[Dictionary] = []
var _last_heading := INF
var _last_position := Vector3.INF
var redraw_count := 0

func _ready() -> void:
	clip_contents = full_map
	mouse_filter = Control.MOUSE_FILTER_STOP if full_map else Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 200) if full_map else Vector2(208, 208)
	visibility_changed.connect(func(): _dragging = false)
	# Geographic geometry is immutable. Convert it once, not on every camera turn.
	for road in level.level_data.get("roads", []):
		var points := PackedVector3Array()
		for value in road.get("points", []):
			points.append(level.vector(value))
		_roads.append({"points": points, "name": str(road.get("name", "")), "width": float(road.get("width", 6.0))})
	if full_map:
		var boundary: Array = level.level_data.get("site_boundary", [])
		if not boundary.is_empty():
			var first: Vector3 = level.vector(boundary[0])
			_bounds = Rect2(Vector2(first.x, first.z), Vector2.ONE)
			for entry in boundary:
				var p: Vector3 = level.vector(entry)
				_bounds = _bounds.expand(Vector2(p.x, p.z))
		fit_neighborhood()

func _process(delta: float) -> void:
	_refresh_time += delta
	if not is_visible_in_tree() or level == null or level.player == null:
		return
	# Orientation/translation follow every rendered frame. The slower refresh is
	# only for traffic and mission markers while the camera and player are idle.
	var moved: bool = level.player.position != _last_position
	var turned: bool = not is_equal_approx(level.player.camera_yaw, _last_heading)
	if moved or turned or _refresh_time >= 0.033:
		_refresh_time = 0.0
		_last_position = level.player.position
		_last_heading = level.player.camera_yaw
		redraw_count += 1
		queue_redraw()

func fit_neighborhood() -> void:
	zoom = 1.0
	map_center = _bounds.get_center()
	queue_redraw()

func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, 0.75, 8.0)
	queue_redraw()

func center_player() -> void:
	map_center = Vector2(level.player.position.x, level.player.position.z)
	zoom = maxf(zoom, 2.0)
	queue_redraw()

func _scale() -> float:
	if not full_map:
		return scale_metres
	return maxf(0.05, minf((size.x - 80) / _bounds.size.x, (size.y - 80) / _bounds.size.y)) * zoom

func _map(point: Vector3) -> Vector2:
	var center := map_center if full_map else Vector2(level.player.position.x, level.player.position.z)
	var offset := (Vector2(point.x, point.z) - center) * _scale()
	if not full_map:
		offset = offset.rotated(level.player.camera_yaw - PI)
	return size * 0.5 + offset

func _marker(point: Vector2, edge := false) -> Vector2:
	if full_map:
		return point
	var delta := point - size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 15.0
	if edge:
		return size * 0.5 + delta.limit_length(radius)
	return point if delta.length() < radius else Vector2(INF, INF)

func _gui_input(event: InputEvent) -> void:
	if not full_map:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(0.8)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		map_center -= event.relative / _scale()
		queue_redraw()
		accept_event()

func _draw() -> void:
	if level == null or level.player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("13282c"))
	var occupied: Array[Rect2] = []
	for park in level.level_data.get("parks", []):
		var polygon := PackedVector2Array()
		for vertex in park.get("polygon", []):
			polygon.append(_map(level.vector(vertex)))
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, Color("284b3c"))
		for ring in park.get("holes", []):
			var hole := PackedVector2Array()
			for vertex in ring:
				hole.append(_map(level.vector(vertex)))
			if hole.size() >= 3:
				draw_colored_polygon(hole, Color("13282c"))
	for road in _roads:
		var points: PackedVector3Array = road.points
		for i in range(1, points.size()):
			var a := _map(points[i - 1])
			var b := _map(points[i])
			var segment := Rect2(a, Vector2.ZERO).expand(b).grow(float(road.width) * _scale())
			if segment.intersects(Rect2(Vector2.ZERO, size)):
				draw_line(a, b, Color("50686b"), maxf(2, float(road.width) * _scale()), true)
	if full_map:
		_draw_street_names()
	var trail: Array = level.level_data.get("route", {}).get("points", [])
	for i in range(1, trail.size()):
		draw_line(_map(level.vector(trail[i - 1])), _map(level.vector(trail[i])), Color("a58b56"), 1.5, true)
	var all_landmarks: Array = level.level_data.get("landmarks", []) if full_map else level.landmarks
	for mark in all_landmarks:
		var point := _marker(_map(level.vector(mark.get("position", [0, 0, 0]))))
		if not point.is_finite():
			continue
		var color := Color("81d6b1") if level.visited.has(str(mark.get("id", ""))) else Color("f6cc79")
		draw_circle(point, 5.0, color)
		# Walk-route intersections remain symbols, not competing place labels.
		if full_map and bool(mark.get("poi", false)):
			_caption(str(mark.get("label", "")), point + Vector2(9, -7), color, occupied, true)
	if full_map:
		for business in level.level_data.get("businesses", []):
			var point := _map(level.vector(business.get("door_position", business.get("front_position", [0, 0, 0]))))
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color("e4b47c"))
			_caption(str(business.get("name", "Shop")), point + Vector2(8, -6), Color("e4b47c"), occupied, false)
		for park in level.level_data.get("parks", []):
			var polygon: Array = park.get("polygon", [])
			if polygon.is_empty():
				continue
			var center := Vector3.ZERO
			for vertex in polygon:
				center += level.vector(vertex)
			center /= polygon.size()
			_caption(str(park.get("name", "Neighborhood park")), _map(center), Color("81d6b1"), occupied, false)
	if level.npcs:
		for id in ["resident", "lookout", "officer", "gardener", "organizer", "caretaker"]:
			var position_: Vector3 = level.npcs.actor_position(id)
			if not position_.is_finite():
				continue
			var point := _marker(_map(position_))
			if not point.is_finite():
				continue
			draw_circle(point, 5.0, Color("70e0da"))
	if not full_map and level.traffic:
		for vehicle in level.traffic.vehicles:
			var point := _marker(_map(vehicle.position))
			if point.is_finite():
				draw_rect(Rect2(point - Vector2(2, 3), Vector2(4, 6)), Color("b0bac0"))
	if level.missions:
		var status: Dictionary = level.missions.get_status()
		if not str(status.get("active_id", "")).is_empty():
			var point := _marker(_map(level.vector(status.get("target_position"))), true)
			draw_arc(point, 11, 0, TAU, 24, Color("70e0da"), 2.5, true)
			if full_map:
				_caption("CASE", point + Vector2(13, -12), Color("70e0da"), occupied, true)
	var player_at := _map(level.player.position)
	var heading := Vector2(sin(level.player.yaw), cos(level.player.yaw))
	if not full_map:
		heading = heading.rotated(level.player.camera_yaw - PI)
	var right := Vector2(-heading.y, heading.x)
	draw_circle(player_at, 13, Color("13282c"))
	draw_colored_polygon(PackedVector2Array([player_at + heading * 11, player_at - heading * 7 + right * 6, player_at - heading * 7 - right * 6]), Color("fff6df"))
	if full_map:
		draw_string(ThemeDB.fallback_font, Vector2(18, 30), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("fff6df"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("718a86"), false, 1)
	else:
		var radius := minf(size.x, size.y) * 0.5
		var north := size * 0.5 + Vector2(0, -1).rotated(level.player.camera_yaw - PI) * (radius - 12)
		draw_circle(north, 9, Color("101d20"))
		draw_string(ThemeDB.fallback_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f5e3b8"))
		draw_arc(size * 0.5, radius - 3, 0, TAU, 96, Color("a1afa8"), 3, true)

func _draw_street_names() -> void:
	var named: Dictionary = {}
	var font := ThemeDB.fallback_font
	var viewport := Rect2(Vector2(18, 18), size - Vector2(36, 36))
	# Text sits on, and rotates with, a sufficiently straight visible road span.
	# No floating label boxes or screen-space relocation for street names.
	for road in _roads:
		var title: String = road.name
		var points: PackedVector3Array = road.points
		if title.is_empty() or named.has(title) or points.size() < 2:
			continue
		var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		for middle in range(1, points.size() - 1):
			# Surveyed ways have uneven point spacing. Grow a physical screen
			# span to fit the name instead of assuming eight samples are enough.
			var span := 1
			var left := maxi(0, middle - span)
			var right := mini(points.size() - 1, middle + span)
			var a := _map(points[left])
			var b := _map(points[right])
			while a.distance_to(b) < width + 16.0 and (left > 0 or right < points.size() - 1):
				span *= 2
				left = maxi(0, middle - span)
				right = mini(points.size() - 1, middle + span)
				a = _map(points[left])
				b = _map(points[right])
			var center := _map(points[middle])
			if a.distance_to(b) < width + 16.0 or not viewport.has_point(center) or not viewport.has_point(a) or not viewport.has_point(b):
				continue
			var tangent := (b - a).normalized()
			if minf(center.distance_to(a), center.distance_to(b)) < width * 0.5 + 4.0:
				continue
			var straight := true
			for sample in range(left + 1, right):
				var point := _map(points[sample])
				if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) > 3.0:
					straight = false
					break
			if not straight:
				continue
			var angle := tangent.angle()
			if absf(angle) > PI * 0.5:
				angle = wrapf(angle + PI, -PI, PI)
			draw_set_transform(center, angle)
			draw_string_outline(font, Vector2(-width * 0.5, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color("233e41"))
			draw_string(font, Vector2(-width * 0.5, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e5e7db"))
			draw_set_transform(Vector2.ZERO)
			named[title] = true
			break

func _caption(text: String, point: Vector2, color: Color, occupied: Array[Rect2], priority: bool) -> void:
	if not Rect2(Vector2(8, 18), size - Vector2(16, 30)).has_point(point):
		return
	var font := ThemeDB.fallback_font
	var box := Rect2(point - Vector2(2, 15), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(6, 5))
	for earlier in occupied:
		if earlier.intersects(box):
			if not priority:
				return
			point.y += 19
			box.position.y += 19
	occupied.append(box)
	if box.end.y > size.y - 8 or box.end.x > size.x - 8:
		return
	draw_rect(box, Color(0.06, 0.12, 0.14, 0.9))
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
