extends Control
const T := preload("res://scripts/ui/hud_theme.gd")
const Icons := preload("res://scripts/city/city_ui_icons.gd")
## North-up geographic map. Full-map mode fits the neighborhood, supports zoom/pan.
## Places are category symbols; only the hovered or selected one is named.
var level: Node3D
var full_map := false
var scale_metres := 0.75
var zoom := 1.0
var map_center := Vector2.ZERO
var hovered_poi := ""
var selected_poi := ""
var last_draw_stats: Dictionary = {}
var _bounds := Rect2(-220, -320, 800, 600)
var _dragging := false
var _press_at := Vector2.INF
var _refresh_time := 0.0
var _roads: Array[Dictionary] = []
var _street_labels: Array[Dictionary] = []
var _park_labels: Array[Dictionary] = []
var _civic_pois: Array[Dictionary] = []
var _pois: Array[Dictionary] = []
var _last_view := Transform2D(0, Vector2.INF)
var label_build_count := 0
var _last_heading := INF
var _last_position := Vector3.INF
var redraw_count := 0
var geography: Node2D

func _ready() -> void:
	clip_contents = full_map
	mouse_filter = Control.MOUSE_FILTER_STOP if full_map else Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 200) if full_map else Vector2(208, 208)
	visibility_changed.connect(_reset_pointer)
	# Geographic geometry is immutable. Convert it once, not on every camera turn.
	for road in level.level_data.get("roads", []):
		var points := PackedVector3Array()
		for value in road.get("points", []):
			points.append(level.vector(value))
		_roads.append({"points": points, "name": str(road.get("name", "")), "width": float(road.get("width", 6.0))})
	if full_map:
		var background := ColorRect.new()
		background.color = Color("15252c")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.show_behind_parent = true
		add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for park in level.level_data.get("parks", []):
			var polygon: Array = park.get("polygon", [])
			if polygon.is_empty():
				continue
			var center := Vector3.ZERO
			for vertex in polygon:
				center += level.vector(vertex)
			_park_labels.append({"position": center / polygon.size(), "name": str(park.get("name", "Neighborhood park"))})
	var district = level.get("civic_district")
	if district != null:
		for poi in district.map_pois:
			_civic_pois.append(poi)
	_build_pois()
	geography = preload("res://scripts/city/city_map_geometry.gd").new()
	add_child(geography)
	geography.setup(level, scale_metres, full_map)
	if full_map:
		var boundary: Array = level.level_data.get("site_boundary", [])
		if not boundary.is_empty():
			var first: Vector3 = level.vector(boundary[0])
			_bounds = Rect2(Vector2(first.x, first.z), Vector2.ONE)
			for entry in boundary:
				var p: Vector3 = level.vector(entry)
				_bounds = _bounds.expand(Vector2(p.x, p.z))
		fit_neighborhood()
	_update_geography()

func _reset_pointer() -> void:
	_dragging = false
	hovered_poi = ""

## Static places, converted once. The radar keeps only built civic places.
func _build_pois() -> void:
	_pois.clear()
	for poi in _civic_pois:
		_add_poi(str(poi.get("id", "")), Icons.category_for(str(poi.get("service", ""))), str(poi.get("label", "Civic place")), poi.position)
	if not full_map:
		return
	for business in level.level_data.get("businesses", []):
		_add_poi(str(business.get("building_id", business.get("name", ""))), Icons.category_for(str(business.get("type", business.get("service", "")))),
			str(business.get("name", "Shop")), level.vector(business.get("door_position", business.get("front_position", [0, 0, 0]))))
	for park in _park_labels:
		_add_poi("park:" + str(park.name), "park", str(park.name), park.position)
	for mark in level.level_data.get("landmarks", []):
		_add_poi(str(mark.get("id", "")), "landmark", str(mark.get("label", "Landmark")), level.vector(mark.get("position", [0, 0, 0])))

func _add_poi(id: String, category: String, label: String, position_: Variant) -> void:
	if id.is_empty() or not position_ is Vector3 or not position_.is_finite():
		return
	_pois.append({"id": id, "category": category, "label": label, "short": Icons.short_name(label), "position": position_})

func poi_entries() -> Array[Dictionary]:
	return _pois.duplicate(true)

func select_poi(id: String) -> void:
	if id != selected_poi:
		selected_poi = id
		queue_redraw()

func _set_hover(id: String) -> void:
	if id != hovered_poi:
		hovered_poi = id
		queue_redraw()

## Nearest place symbol under a canvas point, within a finger-sized radius.
func poi_at(point: Vector2, reach := 12.0) -> String:
	var best := ""
	var best_distance := reach
	for poi in _pois:
		var at := _marker(_map(poi.position))
		if not at.is_finite():
			continue
		var distance := at.distance_to(point)
		if distance <= best_distance:
			best = str(poi.id)
			best_distance = distance
	return best

func _poi(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for poi in _pois:
		if str(poi.id) == id:
			return poi
	return {}

func _process(delta: float) -> void:
	_refresh_time += delta
	if not is_visible_in_tree() or level == null or level.player == null:
		return
	_update_geography()
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
	var at := observer_position()
	map_center = Vector2(at.x, at.z)
	zoom = maxf(zoom, 2.0)
	queue_redraw()

func observer_position() -> Vector3:
	if full_map and level.get("inspector") != null and level.inspector.active:
		return level.inspector.eye
	return level.player.position

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

## Dynamic ownership cue, deliberately separate from cached map geography.
## Each provider suppresses its parked POI while the player occupies it.
func live_vehicle_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level == null:
		return result
	for definition in [["bicycle", "player_bicycle", "Your bicycle"], ["driving", "player_car", "Your car"]]:
		var provider: Node = level.get(definition[0])
		if not is_instance_valid(provider) or not provider.has_method("get_map_pois"):
			continue
		for poi in provider.get_map_pois():
			if not poi is Dictionary or str(poi.get("id", "")) != str(definition[1]):
				continue
			var position_: Variant = poi.get("position")
			if not position_ is Vector3 or not position_.is_finite():
				continue
			var anchor := _marker(_map(position_), true)
			var screen := anchor
			if not full_map:
				var offset := anchor - size * 0.5
				if offset.length() < 24.0:
					# Keep the parked marker clear of the player's arrow disc.
					screen = size * 0.5 + (offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT) * 24.0
			result.append({"id": str(definition[1]), "label": str(poi.get("label", definition[2])),
				"position": position_, "screen": screen, "anchor": anchor})
			break # One owned marker per provider; never iterate ambient traffic.
	return result

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
			if event.pressed:
				_press_at = event.position
			elif _press_at.is_finite() and event.position.distance_to(_press_at) < 5.0:
				# A click (not a drag) selects the symbol under it, or clears.
				select_poi(poi_at(event.position))
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			map_center -= event.relative / _scale()
			queue_redraw()
		else:
			_set_hover(poi_at(event.position))
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and full_map:
		_set_hover("")

func _draw() -> void:
	if level == null or level.player == null:
		return
	var stats := {"icons": 0, "captions": 0, "street_labels": 0}
	var occupied: Array[Rect2] = []
	if full_map:
		_draw_street_names()
		stats.street_labels = _street_labels.size()
	# Mission geometry is a small separate overlay. Never invalidate geography's
	# cached draw when a destination or the player's route changes.
	var navigation = level.get("mission_navigation")
	var guiding: bool = navigation != null and not str(navigation.active_id).is_empty()
	if guiding:
		var guidance := PackedVector2Array()
		for vertex in navigation.route:
			guidance.append(_map(vertex))
		if guidance.size() >= 2:
			draw_polyline(guidance, T.INK, 8.0 if full_map else 7.0, true)
			draw_polyline(guidance, T.TICKET, 4.5 if full_map else 4.0, true)
	if not full_map and level.traffic:
		for vehicle in level.traffic.vehicles:
			var point := _marker(_map(vehicle.position))
			if point.is_finite():
				draw_rect(Rect2(point - Vector2(2, 3), Vector2(4, 6)), Color("b0bac0"))
	# Every symbol, marker and the player arrow share one triangle batch: one
	# draw call however many places are visible, no per-place text or glyphs.
	var shapes := Icons.Shapes.new()
	var radius := 7.0 if full_map else 6.0
	var visible_area := Rect2(Vector2.ZERO, size).grow(radius)
	for poi in _pois:
		var point := _marker(_map(poi.position))
		if not point.is_finite() or not visible_area.has_point(point):
			continue
		var fill := Color.TRANSPARENT
		if poi.category == "landmark" and level.visited.has(str(poi.id)):
			fill = Icons.COLORS.park
		shapes.append(Icons.badge(poi.category, radius, fill, poi.id == selected_poi or poi.id == hovered_poi), point)
		stats.icons += 1
	if not full_map:
		# Walk-route intersections remain small symbols on the radar.
		for mark in level.landmarks:
			var point := _marker(_map(level.vector(mark.get("position", [0, 0, 0]))))
			if not point.is_finite():
				continue
			shapes.append(Icons.glyph("landmark", 6.5, Icons.INK), point)
			shapes.append(Icons.glyph("landmark", 4.5, Icons.COLORS.park if level.visited.has(str(mark.get("id", ""))) else T.TICKET), point)
			stats.icons += 1
	if level.npcs:
		for id in ["resident", "lookout", "officer", "gardener", "organizer", "caretaker"]:
			var position_: Vector3 = level.npcs.actor_position(id)
			if not position_.is_finite():
				continue
			var point := _marker(_map(position_))
			if not point.is_finite():
				continue
			shapes.append(Icons.dot(4.0, Icons.COLORS.contact, Icons.INK), point)
			stats.icons += 1
	for marker in live_vehicle_markers():
		var point: Vector2 = marker.screen
		var kind := "bicycle" if str(marker.id) == "player_bicycle" else "car"
		var color: Color = Icons.COLORS[kind]
		if point.distance_to(marker.anchor) > 1.0:
			shapes.line(marker.anchor, point, color, 1.0)
		shapes.append(Icons.dot(9.0, T.INK), point)
		shapes.append(Icons.glyph(kind, 7.0, color), point)
		stats.icons += 1
	if guiding:
		shapes.append(Icons.target(T.TICKET), _marker(_map(navigation.target), true))
	var player_at := _map(observer_position())
	var heading := Vector2(sin(level.player.yaw), cos(level.player.yaw))
	var inspecting: bool = full_map and level.get("inspector") != null and level.inspector.active
	if inspecting:
		var view: Vector3 = level.inspector.forward()
		heading = Vector2(view.x, view.z).normalized()
		if heading.length_squared() < 0.01:
			heading = Vector2(sin(level.inspector.yaw), -cos(level.inspector.yaw))
		shapes.append(Icons.dot(4.0, Color("92a6aa")), _map(level.player.position))
	if not full_map:
		heading = heading.rotated(level.player.camera_yaw - PI)
	var right := Vector2(-heading.y, heading.x)
	shapes.append(Icons.dot(13.0, T.INK), player_at)
	shapes.polygon(PackedVector2Array([player_at + heading * 11, player_at - heading * 7 + right * 6, player_at - heading * 7 - right * 6]), Icons.COLORS.you)
	if full_map:
		shapes.append(Icons.dot(18.0, Color(0.06, 0.12, 0.14, 0.9)), Vector2(30, 34))
		shapes.append(Icons.glyph("north", 13.0, Color("fff6df")), Vector2(30, 32))
	else:
		var ring := minf(size.x, size.y) * 0.5
		var north := size * 0.5 + Vector2(0, -1).rotated(level.player.camera_yaw - PI) * (ring - 12)
		shapes.arc(size * 0.5, ring - 3, 0.0, TAU, Color("a1afa8"), 3.0)
		shapes.append(Icons.dot(9.0, Color("101d20")), north)
		Icons.letter_n_into(shapes, north, 4.5, Color("f5e3b8"), 1.8)
	stats.triangles = shapes.flush(self)
	if inspecting:
		_caption("CAMERA", player_at + Vector2(15, -12), Color("fff6df"), occupied, true)
		stats.captions += 1
	if full_map:
		# One short name, only for the place being pointed at or chosen.
		var focus := _poi(hovered_poi if not hovered_poi.is_empty() else selected_poi)
		if not focus.is_empty():
			var at := _map(focus.position)
			_caption("%s  ·  %s" % [focus.short, Icons.NAMES.get(focus.category, "Place")], at + Vector2(13, -11), Icons.color_for(focus.category), occupied, true)
			stats.captions += 1
		draw_rect(Rect2(Vector2.ZERO, size), Color("718a86"), false, 1)
	last_draw_stats = stats

func _rebuild_street_names() -> void:
	label_build_count += 1
	_street_labels.clear()
	var named: Dictionary = {}
	var font := T.mono()
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
			_street_labels.append({"center": center, "angle": angle, "width": width, "title": title})
			named[title] = true
			break

func _caption(text: String, point: Vector2, color: Color, occupied: Array[Rect2], priority: bool) -> void:
	if not Rect2(Vector2(8, 18), size - Vector2(16, 30)).has_point(point):
		return
	var font := T.mono()
	var box := Rect2(point - Vector2(2, 15), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(6, 5))
	# Keep a caption near the right/bottom edges on the map, not clipped away.
	if box.end.x > size.x - 8:
		var shift := box.end.x - (size.x - 8)
		point.x -= shift
		box.position.x -= shift
	for earlier in occupied:
		if earlier.intersects(box):
			if not priority:
				return
			point.y += 19
			box.position.y += 19
	occupied.append(box)
	if box.end.y > size.y - 8 or box.position.x < 4:
		return
	draw_rect(box, Color(0.06, 0.12, 0.14, 0.9))
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _update_geography() -> void:
	if geography == null or level == null or level.player == null:
		return
	var view_scale := _scale()
	var at := map_center if full_map else Vector2(level.player.position.x, level.player.position.z)
	var angle: float = 0.0 if full_map else level.player.camera_yaw - PI
	geography.rotation = angle
	geography.scale = Vector2.ONE * view_scale
	geography.position = size * 0.5 - (at * view_scale).rotated(angle)
	if full_map and not geography.transform.is_equal_approx(_last_view):
		_last_view = geography.transform
		_rebuild_street_names()
		queue_redraw()

func _draw_street_names() -> void:
	var font := T.mono()
	for label in _street_labels:
		draw_set_transform(label.center, label.angle)
		var text_at := Vector2(-float(label.width) * 0.5, 4)
		draw_string_outline(font, text_at, label.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color("15252c"))
		draw_string(font, text_at, label.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e2e2d8"))
		draw_set_transform(Vector2.ZERO)
