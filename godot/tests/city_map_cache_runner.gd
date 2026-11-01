extends SceneTree
## Focused map regression fixture; no neighborhood scene or desktop input.
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
var failures := 0

class MapPlayer extends Node3D:
	var camera_yaw := PI
	var yaw := 0.0

class MapDistrict extends RefCounted:
	var map_buildings: Array = [{"polygon": [[10, 10], [20, 10], [20, 20], [10, 20], [10, 10]]}]
	var map_pois: Array = [{"id": "police", "label": "Police station", "position": Vector3(15, 0, 15), "service": "police"}]

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

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[city_map_cache] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func settle() -> void:
	for i in 3:
		await process_frame

func _run() -> void:
	var level := MapLevel.new()
	level.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	level.player = MapPlayer.new()
	level.add_child(level.player)
	root.add_child(level)
	var canvas := MapCanvas.new()
	canvas.level = level
	canvas.full_map = true
	canvas.size = Vector2(1400, 760)
	root.add_child(canvas)
	await settle()
	check(canvas.geography.buildings.size() == 967, "fallback includes every exported building")
	check(canvas.geography.courts.size() == 22, "existing court footprints are retained")
	check(canvas.zoom == 1.0 and canvas.map_center.is_equal_approx(canvas._bounds.get_center()), "default full map fits the neighborhood")
	var inside := true
	for vertex in level.level_data.site_boundary:
		inside = inside and Rect2(Vector2.ZERO, canvas.size).has_point(canvas._map(level.vector(vertex)))
	check(inside, "all surveyed boundary vertices fit")
	check(canvas._street_labels.size() > 5, "whole-neighborhood view labels actual streets")
	var geometry_builds: int = canvas.geography.build_count
	var label_builds: int = canvas.label_build_count
	level.player.position += Vector3(30, 0, 20)
	level.player.camera_yaw += 1.0
	await settle()
	check(canvas.geography.build_count == geometry_builds, "player movement leaves cached geography intact")
	check(canvas.label_build_count == label_builds, "player movement does not rescan full-map roads")
	canvas.zoom_by(1.25)
	await settle()
	check(canvas.geography.build_count == geometry_builds, "zoom only changes cached geometry transform")
	check(canvas.label_build_count > label_builds, "zoom refreshes screen-space street labels")
	var point := Vector3(10, 0, 15)
	check((canvas.geography.transform * Vector2(point.x, point.z)).is_equal_approx(canvas._map(point)), "static geometry and dynamic markers use the same full-map transform")
	canvas.center_player()
	await settle()
	check(canvas._map(level.player.position).is_equal_approx(canvas.size * 0.5), "Find me centers the player")
	level.civic_district = MapDistrict.new()
	var district_map := MapCanvas.new()
	district_map.level = level
	district_map.full_map = true
	district_map.size = Vector2(1400, 760)
	root.add_child(district_map)
	await settle()
	check(district_map.geography.buildings.size() == 1, "district footprints replace rather than duplicate original buildings")
	check(district_map._civic_pois.size() == 1, "built civic places populate the map")
	var mini := MapCanvas.new()
	mini.level = level
	mini.size = Vector2(208, 208)
	root.add_child(mini)
	await settle()
	check(not mini.full_map and mini.geography.buildings.is_empty(), "circular minimap retains lightweight geography")
	check((mini.geography.transform * Vector2(point.x, point.z)).is_equal_approx(mini._map(point)), "minimap geometry and markers rotate together")
	check(mini._marker(Vector2(10000, 10000), true).distance_to(mini.size * 0.5) <= 89.01, "offscreen mission marker stays at the circular edge")
	print("[city_map_cache] failures=%d" % failures)
	root.remove_child(canvas)
	canvas.free()
	root.remove_child(district_map)
	district_map.free()
	root.remove_child(mini)
	mini.free()
	root.remove_child(level)
	level.free()
	quit(0 if failures == 0 else 1)
