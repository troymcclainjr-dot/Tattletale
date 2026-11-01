extends Node
## Private canvas-only GPU comparison. No world, gameplay input or mouse capture.
const CURRENT := preload("res://scripts/city/city_map_geometry.gd")
const SIZE := Vector2i(1440, 900)
const BASELINE := "res://../.work/priorities-five/baseline/godot/scripts/city/city_map_geometry.gd"
var failures := 0
var checks: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var output := ""
var viewport: SubViewport

class MapLevel extends Node3D:
	var level_data: Dictionary = {}
	var civic_district: Node3D
	func vector(value: Array) -> Vector3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _ready() -> void:
	var window := get_tree().root
	window.unfocusable = true
	var at := Vector2i(-10000, -10000)
	for screen in DisplayServer.get_screen_count():
		at.x = mini(at.x, DisplayServer.screen_get_position(screen).x - window.size.x - 256)
	window.position = at
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for singleton in ["G", "Hud"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CanvasItem:
				node.hide()
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Map GPU probe requires a graphical renderer and --offscreen-validation.")
		get_tree().quit(2)
		return
	output = ProjectSettings.globalize_path("res://../artifacts/priorities-five/map-batch")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-probe-out="):
			output = arg.trim_prefix("--map-probe-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var legacy := GDScript.new()
	legacy.source_code = FileAccess.get_file_as_string(BASELINE)
	if legacy.reload() != OK:
		get_tree().quit(2)
		return
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("15252c")
	background.size = SIZE
	viewport.add_child(background)
	var level := MapLevel.new()
	var batched := false
	level.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	add_child(level)
	for detailed in [false, true]:
		for civic in ([false, true] if detailed else [false]):
			if civic:
				level.civic_district = _civic_metadata(level)
				level.add_child(level.civic_district)
			var reference: Dictionary = {}
			for variant in ["legacy", "current"]:
				var geo: Node2D = (legacy if variant == "legacy" else CURRENT).new()
				viewport.add_child(geo)
				geo.setup(level, 0.75, detailed)
				var signature := _signature(geo)
				if variant == "legacy":
					reference = signature
				else:
					batched = geo.has_method("_batch_polygons")
					_check(signature == reference, "exact geometry, colors and road widths: detailed=%s civic=%s" % [detailed, civic])
					_check_meshes(geo)
				var bounds := Rect2(Vector2(-220, -320), Vector2(800, 600))
				if geo.boundary.size() > 1:
					bounds = Rect2(geo.boundary[0], Vector2.ZERO)
					for point in geo.boundary:
						bounds = bounds.expand(point)
				var fit := minf((SIZE.x - 80.0) / bounds.size.x, (SIZE.y - 80.0) / bounds.size.y)
				for zoom in [1.0, 4.0]:
					geo.scale = Vector2.ONE * fit * zoom
					geo.position = Vector2(SIZE) * 0.5 - (bounds.get_center() + Vector2(25, -10) * (zoom - 1)) * fit * zoom
					await _frames(4)
					var draws: Array[int] = []
					for frame in 8:
						await RenderingServer.frame_post_draw
						draws.append(viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
					draws.sort()
					var label := "%s-%s-%s-zoom%d" % [variant, "detailed" if detailed else "mini", "civic" if civic else "fallback", int(zoom)]
					var capture := viewport.get_texture().get_image()
					_check(not capture.is_empty() and draws[4] > 0, label + " rendered real canvas draws")
					_check(capture.save_png(output.path_join(label + ".png")) == OK, label + " capture saved")
					measurements.append({"label": label, "variant": variant, "detailed": detailed, "civic": civic,
						"zoom": zoom, "draw_calls_median": draws[4], "draw_calls_min": draws[0], "draw_calls_max": draws[-1],
						"buildings": geo.buildings.size(), "courts": geo.courts.size(), "build_count": geo.build_count})
				_check(geo.build_count == 1, variant + " pan/zoom reuses retained draw commands")
				geo.free()
			if is_instance_valid(level.civic_district):
				level.civic_district.free()
				level.civic_district = null
	if batched:
		_check_draw_reduction()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks, "measurements": measurements}, "\t"))
	print("[map_batch_probe] ", JSON.stringify(measurements))
	print("[map_batch_probe] ", checks.size() - failures, " passed, ", failures, " failed; ", output)
	get_tree().quit(0 if failures == 0 else 1)

func _civic_metadata(level: MapLevel) -> Node3D:
	# Reuse the district's metadata preparation, without constructing its world.
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
	# Match _build_site's scaled, rotated actual building rectangle, not its
	# larger reserved footprint. Only static footprint() runs; no models build.
	for site in district.sites:
		var script = load("res://scripts/city/city_civic_%s.gd" % site.id)
		var footprint: Vector2 = script.footprint()
		var dimensions := Vector3(minf(footprint.x, float(site.width_m)), 0, minf(footprint.y, float(site.depth_m)))
		var transform := Transform3D(Basis(Vector3.UP, float(site.yaw)), level.vector(site.position))
		var outline: Array = []
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
			var point: Vector3 = transform * (corner * dimensions * 0.5)
			outline.append([point.x, point.z])
		for building in district.map_buildings:
			if str(building.id) == str(site.id):
				building.polygon = outline
	return district

func _signature(geo: Node2D) -> Dictionary:
	return {"parks": geo.parks.duplicate(true), "roads": geo.roads.duplicate(true),
		"buildings": geo.buildings.duplicate(), "courts": geo.courts.duplicate(),
		"route": geo.route.duplicate(), "boundary": geo.boundary.duplicate(), "route_width": geo.get_meta("route_width")}

func _check_meshes(geo: Node2D) -> void:
	# Activated by the production batching change; legacy builds still probe.
	if not geo.has_method("_batch_polygons"):
		return
	for kind in ["buildings", "courts"]:
		var polygons: Array = geo.get(kind)
		var mesh: ArrayMesh = geo.get("_" + kind + "_mesh")
		var outlines: PackedVector2Array = geo.get("_" + kind + "_outlines")
		var count := 0
		var expected_area := 0.0
		var expected_vertices := PackedVector2Array()
		var expected_outlines := PackedVector2Array()
		for polygon in polygons:
			count += polygon.size()
			expected_area += _polygon_area(polygon)
			expected_vertices.append_array(polygon)
			for i in polygon.size():
				expected_outlines.append(polygon[i])
				expected_outlines.append(polygon[(i + 1) % polygon.size()])
		_check(outlines.size() == count * 2, kind + " every closed outline edge retained")
		_check(outlines == expected_outlines, kind + " exact closed outline endpoints")
		if polygons.is_empty():
			_check(mesh == null, kind + " empty layer has no mesh")
			continue
		_check(mesh != null and mesh.get_surface_count() == 1, kind + " one filled surface")
		if mesh == null or mesh.get_surface_count() != 1:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check(vertices == expected_vertices, kind + " exact world-space fill vertices")
		var actual_area := 0.0
		for i in range(0, indices.size(), 3):
			actual_area += absf((vertices[indices[i + 1]] - vertices[indices[i]]).cross(vertices[indices[i + 2]] - vertices[indices[i]])) * 0.5
		_check(absf(actual_area - expected_area) <= maxf(0.01, expected_area * 0.00001), kind + " triangles preserve full polygon area")
		_check(indices.size() == (count - polygons.size() * 2) * 3, kind + " all n-2 polygon triangles retained")

func _check_draw_reduction() -> void:
	for current in measurements:
		if current.variant != "current":
			continue
		for legacy in measurements:
			if legacy.variant != "legacy" or legacy.detailed != current.detailed or legacy.civic != current.civic or legacy.zoom != current.zoom:
				continue
			if current.detailed:
				_check(int(current.draw_calls_median) < int(legacy.draw_calls_median) / 10.0, current.label + " actual canvas draws reduced by over 90 percent")
			else:
				_check(current.draw_calls_median == legacy.draw_calls_median, current.label + " minimap draw count unchanged")

func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		total += points[i].cross(points[(i + 1) % points.size()])
	return absf(total) * 0.5

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _check(ok: bool, description: String) -> void:
	checks.append({"ok": ok, "description": description})
	if not ok:
		failures += 1
		print("FAIL: ", description)
