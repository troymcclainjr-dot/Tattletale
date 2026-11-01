extends SceneTree
## Map symbols, hover/selection names and court colors. Headless; uses the
## real surveyed level data, no neighborhood scene or desktop input.
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
const MapOverlay := preload("res://scripts/city/city_map_overlay.gd")
const Icons := preload("res://scripts/city/city_ui_icons.gd")
var failures := 0

class MapPlayer extends Node3D:
	var camera_yaw := PI
	var yaw := 0.0

class MapDistrict extends RefCounted:
	var map_buildings: Array = [{"polygon": [[10, 10], [20, 10], [20, 20], [10, 20], [10, 10]]}]
	var map_pois: Array = [
		{"id": "police", "label": "Pen Lucy Neighborhood Police District Station", "position": Vector3(15, 0, 15), "service": "police"},
		{"id": "courthouse", "label": "District Courthouse", "position": Vector3(60, 0, -40), "service": "courthouse"},
		{"id": "corner", "label": "Corner Store", "position": Vector3(-30, 0, 25), "service": "corner_store"}]

class MapLevel extends Node3D:
	var level_data: Dictionary
	var player: Node3D
	var civic_district: RefCounted
	var mission_navigation: RefCounted
	var landmarks: Array = []
	var visited: Dictionary = {}
	var npcs: Node
	var traffic: Node
	func vector(value) -> Vector3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	func resume_exploring() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[map_icons] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func settle() -> void:
	for i in 3:
		await process_frame

func motion(canvas: Control, at: Vector2, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	canvas._gui_input(event)

func button(canvas: Control, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	canvas._gui_input(event)

func _run() -> void:
	check(Icons.category_for("courthouse") == "court" and Icons.category_for("liquor") == "shop" and Icons.category_for("takeout") == "food"
		and Icons.category_for("barber") == "service" and Icons.category_for("police") == "police" and Icons.category_for("gun_store") == "shop",
		"service and business types map to the shared categories")
	var short := Icons.short_name("Pen Lucy Neighborhood Police District Station")
	check(short.length() <= 23 and not short.begins_with("Pen Lucy"), "verbose place names shorten for the single caption")
	check(Icons.short_name("Hilltop Foods") == "Hilltop Foods", "short names stay intact")
	var court := Icons.SPORTS_COURT
	check(court.h > 0.38 and court.h < 0.58 and court.s < 0.5 and court.v < 0.6, "sports courts are a muted blue-green, not route yellow")
	var geometry_source := FileAccess.get_file_as_string("res://scripts/city/city_map_geometry.gd")
	check("Icons.SPORTS_COURT" in geometry_source and "a18745" not in geometry_source, "court fill uses the muted court color")
	var level := MapLevel.new()
	level.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	level.player = MapPlayer.new()
	level.add_child(level.player)
	level.civic_district = MapDistrict.new()
	root.add_child(level)
	var canvas := MapCanvas.new()
	canvas.level = level
	canvas.full_map = true
	canvas.size = Vector2(1400, 760)
	root.add_child(canvas)
	await settle()
	var entries: Array[Dictionary] = canvas.poi_entries()
	var expected: int = 3 + level.level_data.get("businesses", []).size() + level.level_data.get("landmarks", []).size()
	for park in level.level_data.get("parks", []):
		expected += int(not park.get("polygon", []).is_empty())
	check(entries.size() == expected, "every civic place, business, park and landmark becomes one symbol (%d)" % entries.size())
	var categorized := true
	for entry in entries:
		categorized = categorized and str(entry.category) in Icons.CATEGORIES and not str(entry.short).is_empty() and str(entry.short).length() <= 23
	check(categorized, "every symbol has a known category and a short name")
	check(canvas.last_draw_stats.get("captions", -1) == 0 and canvas.last_draw_stats.get("icons", 0) > 10, "no place captions are drawn by default")
	check(canvas.last_draw_stats.get("street_labels", 0) > 5, "street names still run along visible roads")
	var builds: int = canvas.geography.build_count
	var labels: int = canvas.label_build_count
	var police_at: Vector2 = canvas._map(Vector3(15, 0, 15))
	motion(canvas, police_at + Vector2(1, -1))
	await settle()
	check(canvas.hovered_poi == "police" and canvas.last_draw_stats.captions == 1, "pointing at a symbol shows exactly one short name")
	motion(canvas, Vector2(4, 4))
	await settle()
	check(canvas.hovered_poi.is_empty() and canvas.last_draw_stats.captions == 0, "moving away removes the name")
	button(canvas, police_at, true)
	button(canvas, police_at, false)
	await settle()
	check(canvas.selected_poi == "police" and canvas.last_draw_stats.captions == 1, "clicking a symbol selects it")
	var center := canvas.map_center
	button(canvas, Vector2(700, 380), true)
	motion(canvas, Vector2(740, 380), Vector2(40, 0))
	button(canvas, Vector2(740, 380), false)
	await settle()
	check(canvas.selected_poi == "police" and not canvas.map_center.is_equal_approx(center), "dragging pans without changing the selection")
	var empty := Vector2(6, 700)
	button(canvas, empty, true)
	button(canvas, empty, false)
	await settle()
	check(canvas.poi_at(empty).is_empty() and canvas.selected_poi.is_empty(), "clicking empty map clears the selection")
	motion(canvas, canvas._map(Vector3(15, 0, 15)))
	canvas.notification(Control.NOTIFICATION_MOUSE_EXIT)
	check(canvas.hovered_poi.is_empty(), "leaving the map clears the hover name")
	check(canvas.geography.build_count == builds, "hover, selection and pan never rebuild batched geometry")
	check(canvas.label_build_count > labels, "pan refreshes street labels for the new view")
	var mini := MapCanvas.new()
	mini.level = level
	mini.size = Vector2(208, 208)
	root.add_child(mini)
	await settle()
	check(mini.poi_entries().size() == 3, "radar keeps only built civic places")
	mini.queue_redraw()
	await settle()
	check(mini.last_draw_stats.get("captions", -1) == 0, "radar draws no text captions")
	var radar_source := FileAccess.get_file_as_string("res://scripts/city/city_minimap.gd")
	check("fallback_font" not in radar_source and "↑" not in radar_source, "map north markers are vector shapes, not font glyphs")
	var overlay := MapOverlay.new()
	root.add_child(overlay)
	overlay.setup(level, func(): pass)
	overlay.show()
	await settle()
	var key_items: int = overlay.key.get_child_count()
	check(key_items == MapOverlay.KEY.size() and key_items >= 15, "map key lists the shared symbols")
	var key_text := ""
	for label in overlay.key.find_children("*", "Label", true, false):
		key_text += label.text + " "
	check("Ochre" not in key_text and "Sports court" in key_text and "Case route" in key_text, "key describes courts and the route without color names")
	print("[map_icons] failures=%d" % failures)
	for node in [overlay, canvas, mini, level]:
		root.remove_child(node)
		node.free()
	quit(0 if failures == 0 else 1)
