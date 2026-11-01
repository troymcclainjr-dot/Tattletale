extends Node
## Actual canvas draw calls for the full map and radar with every place
## symbol, street name, route and caption over the real surveyed data.
## Graphical offscreen fixture; root runs it. No world, gameplay or input.
const MapCanvas := preload("res://scripts/city/city_minimap.gd")
const Geometry := preload("res://scripts/city/city_map_geometry.gd")
const Radar := preload("res://scripts/city/city_radar.gd")
const SIZE := Vector2i(1600, 900)
## Retained geography measured 28 draws after batching (3928 before). Symbols
## must stay one batch, so their presence may add only a few draws in total.
const FULL_BUDGET := 120
const RADAR_BUDGET := 40
const SYMBOL_ALLOWANCE := 3
const CAPTION_ALLOWANCE := 4
var failures := 0
var checks: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var output := ""
var viewport: SubViewport

class MapPlayer extends Node3D:
	var camera_yaw := PI
	var yaw := 0.0

class Navigation extends RefCounted:
	var active_id := "fixture_route"
	var route: Array[Vector3] = []
	var target := Vector3.ZERO

class MapLevel extends Node3D:
	var level_data: Dictionary = {}
	var player: Node3D
	var civic_district: Node3D
	var mission_navigation: RefCounted
	var landmarks: Array = []
	var visited: Dictionary = {}
	var npcs: Node
	var traffic: Node
	var inspector: Node
	func vector(value: Array) -> Vector3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _ready() -> void:
	var window := get_tree().root
	window.unfocusable = true
	for singleton in ["G", "Hud"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CanvasItem or node is CanvasLayer:
				node.hide()
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Map draw budget requires a graphical renderer and --offscreen-validation.")
		get_tree().quit(2)
		return
	output = ProjectSettings.globalize_path("res://../.work/pacifist-foundation/phone-map-review/map-draws")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=").path_join("map-draws")
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var level := MapLevel.new()
	level.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	level.player = MapPlayer.new()
	level.add_child(level.player)
	add_child(level)
	level.civic_district = _civic_metadata(level)
	level.add_child(level.civic_district)
	level.landmarks = level.level_data.get("landmarks", [])
	var navigation := Navigation.new()
	for vertex in level.level_data.get("route", {}).get("points", []).slice(0, 40):
		navigation.route.append(level.vector(vertex))
	if not navigation.route.is_empty():
		navigation.target = navigation.route[-1]
		level.player.position = navigation.route[0]
	level.mission_navigation = navigation
	# 1. Retained geography alone, at the full-map fit.
	var geo: Node2D = Geometry.new()
	viewport.add_child(geo)
	geo.setup(level, 0.75, true)
	var bounds := Rect2(geo.boundary[0], Vector2.ZERO) if geo.boundary.size() > 1 else Rect2(-220, -320, 800, 600)
	for point in geo.boundary:
		bounds = bounds.expand(point)
	var fit := minf((SIZE.x - 80.0) / bounds.size.x, (SIZE.y - 80.0) / bounds.size.y)
	geo.scale = Vector2.ONE * fit
	geo.position = Vector2(SIZE) * 0.5 - bounds.get_center() * fit
	var geography: int = await _measure("geography-only")
	geo.free()
	# 2. The whole full map, as the player sees it.
	var full := MapCanvas.new()
	full.level = level
	full.full_map = true
	full.size = Vector2(SIZE)
	viewport.add_child(full)
	await _frames(3)
	var fitted: int = await _measure("full-fit", full)
	var symbols: int = full.last_draw_stats.get("icons", 0)
	_check(symbols > 30, "full map draws every visible place as a symbol (%d)" % symbols)
	_check(fitted <= FULL_BUDGET, "full map within %d draws (%d; geography %d)" % [FULL_BUDGET, fitted, geography])
	var first: Dictionary = full.poi_entries()[0]
	full.hovered_poi = str(first.id)
	full.queue_redraw()
	var hovered: int = await _measure("full-hover", full)
	_check(hovered - fitted <= CAPTION_ALLOWANCE and full.last_draw_stats.captions == 1, "one hover name adds at most %d draws (%d)" % [CAPTION_ALLOWANCE, hovered - fitted])
	full.hovered_poi = ""
	var places: Array[Dictionary] = full._pois.duplicate()
	full._pois.clear()
	full.queue_redraw()
	var bare: int = await _measure("full-no-symbols", full)
	_check(fitted - bare <= SYMBOL_ALLOWANCE, "all %d symbols cost at most %d draws (%d)" % [symbols, SYMBOL_ALLOWANCE, fitted - bare])
	full._pois = places
	full.center_player()
	full.zoom_by(2.0)
	await _frames(3)
	var zoomed: int = await _measure("full-zoom", full)
	_check(zoomed <= FULL_BUDGET, "zoomed full map within %d draws (%d)" % [FULL_BUDGET, zoomed])
	full.free()
	# 3. The radar, clipped to its circle as in the HUD.
	var radar := Radar.new()
	radar.setup(level)
	radar.position = Vector2(40, 40)
	viewport.add_child(radar)
	await _frames(3)
	var radar_draws: int = await _measure("radar", radar.map)
	_check(radar_draws <= RADAR_BUDGET, "radar within %d draws (%d)" % [RADAR_BUDGET, radar_draws])
	var radar_places: Array[Dictionary] = radar.map._pois.duplicate()
	var radar_landmarks: Array = level.landmarks
	radar.map._pois.clear()
	level.landmarks = []
	var radar_bare: int = await _measure("radar-no-symbols", radar.map)
	_check(radar_draws - radar_bare <= SYMBOL_ALLOWANCE, "radar symbols stay batched (%d)" % (radar_draws - radar_bare))
	radar.map._pois = radar_places
	level.landmarks = radar_landmarks
	radar.free()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks, "measurements": measurements,
		"budgets": {"full": FULL_BUDGET, "radar": RADAR_BUDGET, "symbols": SYMBOL_ALLOWANCE, "caption": CAPTION_ALLOWANCE}}, "\t"))
	file.close()
	print("[map_draw_budget] ", JSON.stringify(measurements))
	print("[map_draw_budget] ", checks.size() - failures, " passed, ", failures, " failed; ", output)
	get_tree().quit(0 if failures == 0 else 1)

func _measure(label: String, canvas: Control = null) -> int:
	if canvas != null:
		canvas.queue_redraw()
	await _frames(3)
	var draws: Array[int] = []
	for frame in 8:
		await RenderingServer.frame_post_draw
		draws.append(viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	draws.sort()
	var capture := viewport.get_texture().get_image()
	_check(not capture.is_empty() and draws[4] > 0, label + " rendered real canvas draws")
	_check(capture.save_png(output.path_join(label + ".png")) == OK, label + " capture saved")
	var stats: Dictionary = canvas.last_draw_stats.duplicate() if canvas != null and canvas.get("last_draw_stats") != null else {}
	measurements.append({"label": label, "draw_calls_median": draws[4], "draw_calls_min": draws[0], "draw_calls_max": draws[-1], "stats": stats})
	return draws[4]

func _civic_metadata(level: MapLevel) -> Node3D:
	# Same metadata preparation as city_map_batch_probe_runner.gd: footprints and
	# map POIs without constructing the district's world.
	var district: Node3D = load("res://scripts/city/city_civic_district.gd").new()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(district.PLAN))
	district.sites = plan.get("sites", [])
	var shops = JSON.parse_string(FileAccess.get_file_as_string(district.SHOPS))
	district.businesses = shops.get("businesses", shops.get("records", [])) if shops is Dictionary else shops
	for site in district.sites:
		for id in site.get("demolition_ids", []):
			district.removed_building_ids.append(str(id))
		for mesh_name in site.get("demolition_meshes", []):
			district.removed_meshes.append(str(mesh_name))
	for business in district.businesses:
		for id in business.get("building_ids", []):
			district.removed_building_ids.append(str(id))
		if not str(business.get("source_mesh", "")).is_empty():
			district.removed_meshes.append(str(business.source_mesh))
	district._prepare_map()
	return district

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _check(ok: bool, description: String) -> void:
	checks.append({"ok": ok, "description": description})
	print("[map_draw_budget] %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		failures += 1
