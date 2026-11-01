extends Node
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
const Driving := preload("res://scripts/city/city_driving.gd")
class MapPlayer extends Node3D:
	var yaw := 0.0
	var camera_yaw := 0.0
class MapDistrict extends Node:
	var map_buildings: Array = []
	var map_pois: Array = []
class MapWorld extends Node3D:
	var player: Node3D
	var driving: Node3D
	var civic_district: Node
	var inspector: Node
	var npcs: Node
	var traffic: Node
	var landmarks: Array = []
	var visited: Dictionary = {}
	var level_data := {"roads": [], "parks": [], "landmarks": [], "businesses": [], "site_boundary": [[-100,0,-100],[100,0,-100],[100,0,100],[-100,0,100]]}
	func vector(value: Variant) -> Vector3:
		return value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))
var failures := 0
var finished := false
func _ready() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await get_tree().create_timer(35.0, true, false, true).timeout
	if not finished:
		check(false, "watchdog")
		get_tree().quit(1)
func check(ok: bool, label: String) -> void:
	print("[car_map] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func _run() -> void:
	var world := MapWorld.new()
	add_child(world)
	world.player = MapPlayer.new()
	world.add_child(world.player)
	world.civic_district = MapDistrict.new()
	world.add_child(world.civic_district)
	var full := MapCanvas.new()
	full.full_map = true
	full.level = world
	full.size = Vector2(800, 600)
	add_child(full)
	var radar := MapCanvas.new()
	radar.level = world
	radar.size = Vector2(208, 208)
	add_child(radar)
	await get_tree().process_frame
	check(full.live_vehicle_markers().is_empty() and radar.live_vehicle_markers().is_empty(), "optional absent driving manager is harmless")
	world.driving = Node3D.new()
	world.add_child(world.driving)
	check(full.live_vehicle_markers().is_empty(), "older manager without POI API is harmless")
	world.driving.queue_free()
	var driver := Driving.new()
	world.driving = driver
	world.add_child(driver)
	var starter := Node3D.new()
	world.add_child(starter)
	starter.position = Vector3(20, 0, 30)
	driver.starter = starter
	for frame in 3:
		await get_tree().process_frame
	var full_markers: Array = full.live_vehicle_markers()
	var radar_markers: Array = radar.live_vehicle_markers()
	check(full_markers.size() == 1 and radar_markers.size() == 1 and full_markers[0].label == "Your car", "real driving POI appears on both map and radar")
	check(full_markers[0].position == starter.global_position and full_markers[0].screen == full._map(starter.global_position), "full map projects authoritative live car position")
	var before: Vector2 = radar_markers[0].screen
	var full_cache: Node2D = full.geography
	var radar_cache: Node2D = radar.geography
	var full_builds: int = full_cache.build_count
	var radar_builds: int = radar_cache.build_count
	var labels: int = full.label_build_count
	starter.position += Vector3(8, 0, -4)
	check(radar.live_vehicle_markers()[0].screen != before, "moving starter updates radar marker without player motion")
	for frame in 5:
		full._process(0.04)
		radar._process(0.04)
		await get_tree().process_frame
	check(full.geography == full_cache and radar.geography == radar_cache and full_cache.build_count == full_builds and radar_cache.build_count == radar_builds and full.label_build_count == labels,
		"moving car leaves static geography and street-label caches unchanged")
	driver.active = true
	driver.vehicle = starter
	check(full.live_vehicle_markers().is_empty() and radar.live_vehicle_markers().is_empty(), "occupied starter marker hides through real driving API")
	driver.active = false
	driver.vehicle = null
	starter.position = Vector3(6, 0, 0)
	var nearby: Dictionary = radar.live_vehicle_markers()[0]
	check(is_equal_approx(nearby.screen.distance_to(radar.size * 0.5), 24.0) and nearby.anchor == radar._map(starter.global_position), "nearby starter icon clears player arrow and retains true-position leader")
	starter.position = Vector3(900, 0, 900)
	var edge: Vector2 = radar.live_vehicle_markers()[0].screen
	check(is_equal_approx(edge.distance_to(radar.size * 0.5), 89.0), "distant owned car remains a bounded circular radar edge cue")
	world.player.camera_yaw = PI * 0.5
	check(not radar.live_vehicle_markers()[0].screen.is_equal_approx(edge), "radar car direction follows camera heading")
	check(full.live_vehicle_markers()[0].screen == full._map(starter.global_position), "full-map marker stays north-up")
	starter.free()
	check(full.live_vehicle_markers().is_empty() and radar.live_vehicle_markers().is_empty(), "removed starter leaves no stale marker")
	world.queue_free()
	full.queue_free()
	radar.queue_free()
	finished = true
	print("[car_map] failures=", failures)
	get_tree().quit(1 if failures else 0)
