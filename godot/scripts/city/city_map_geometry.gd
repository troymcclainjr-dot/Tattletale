extends Node2D
## Retained geographic draw commands: panning, zooming and player motion only
## change this node's transform. Footprints are never rebuilt per frame.
const BACKGROUND := Color("15252c")
const Icons := preload("res://scripts/city/city_ui_icons.gd")
var parks: Array[Dictionary] = []
var buildings: Array[PackedVector2Array] = []
var courts: Array[PackedVector2Array] = []
var roads: Dictionary = {}
var route := PackedVector2Array()
var boundary := PackedVector2Array()
var build_count := 0
var _buildings_mesh: ArrayMesh
var _courts_mesh: ArrayMesh
var _buildings_outlines := PackedVector2Array()
var _courts_outlines := PackedVector2Array()

func setup(level: Node3D, metres_scale: float, detailed := false) -> void:
	show_behind_parent = true
	for park in level.level_data.get("parks", []):
		var rings: Array = [park.get("polygon", [])]
		rings.append_array(park.get("holes", []))
		for i in rings.size():
			var points := PackedVector2Array()
			for vertex in rings[i]:
				var p: Vector3 = level.vector(vertex)
				points.append(Vector2(p.x, p.z))
			parks.append({"points": points, "color": Color("314e3b") if i == 0 else BACKGROUND})
	for road in level.level_data.get("roads", []):
		var width := maxf(2.0 / metres_scale, float(road.get("width", 6.0)))
		var segments: PackedVector2Array = roads.get(width, PackedVector2Array())
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			segments.append(Vector2(a.x, a.z))
			segments.append(Vector2(b.x, b.z))
		roads[width] = segments
	if detailed:
		var district = level.get("civic_district")
		var footprints: Array = []
		if district != null:
			footprints = district.map_buildings
		else:
			var source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_window_homes.json"))
			if source is Dictionary:
				footprints = source.get("homes", [])
		for building in footprints:
			var points := _polygon(building.get("polygon", []))
			if points.size() >= 3:
				buildings.append(points)
		var court_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_courts.json"))
		if court_data is Dictionary:
			for court in court_data.get("courts", []):
				var points := _polygon(court.get("footprint", []))
				if points.size() >= 3:
					courts.append(points)
		for vertex in level.level_data.get("site_boundary", []):
			var p: Vector3 = level.vector(vertex)
			boundary.append(Vector2(p.x, p.z))
	for vertex in level.level_data.get("route", {}).get("points", []):
		var p: Vector3 = level.vector(vertex)
		route.append(Vector2(p.x, p.z))
	set_meta("route_width", 1.5 / metres_scale)
	_buildings_mesh = _batch_polygons(buildings)
	_courts_mesh = _batch_polygons(courts)
	_buildings_outlines = _outline_segments(buildings)
	_courts_outlines = _outline_segments(courts)
	queue_redraw()

func _polygon(vertices: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for vertex in vertices:
		points.append(Vector2(float(vertex[0]), float(vertex[1])))
	# Exported rings repeat the first vertex; Godot polygons need an open ring.
	if points.size() > 1 and points[0].is_equal_approx(points[-1]):
		points.resize(points.size() - 1)
	return points

func _draw() -> void:
	build_count += 1
	for park in parks:
		if park.points.size() >= 3:
			draw_colored_polygon(park.points, park.color)
	for width in roads:
		draw_multiline(roads[width], Color("52666d"), width, true)
	_draw_batch(_buildings_mesh, buildings, Color("877d71"))
	if not _buildings_outlines.is_empty():
		draw_multiline(_buildings_outlines, Color("b4a691"), 0.22, true)
	# Sports courts are muted blue-green: yellow belongs to the mission route.
	_draw_batch(_courts_mesh, courts, Icons.SPORTS_COURT)
	if not _courts_outlines.is_empty():
		draw_multiline(_courts_outlines, Icons.SPORTS_COURT_EDGE, 0.55, true)
	if boundary.size() >= 2:
		draw_polyline(boundary, Color("516a72"), 0.7, true)
	if route.size() >= 2:
		draw_polyline(route, Color("a58b56"), float(get_meta("route_width")), true)

func _batch_polygons(polygons: Array[PackedVector2Array]) -> ArrayMesh:
	# Keep world-space vector vertices: zooming scales retained geometry, never
	# a raster map. Separate surfaces preserve the building/court layer colors.
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	for points in polygons:
		var triangles := Geometry2D.triangulate_polygon(points)
		if triangles.is_empty():
			# Preserve the legacy fill path for an untriangulatable future layer.
			return null
		var offset := vertices.size()
		vertices.append_array(points)
		for index in triangles:
			indices.append(offset + index)
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _outline_segments(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var segments := PackedVector2Array()
	for points in polygons:
		for i in points.size():
			segments.append(points[i])
			segments.append(points[(i + 1) % points.size()])
	return segments

func _draw_batch(mesh: ArrayMesh, polygons: Array[PackedVector2Array], color: Color) -> void:
	if mesh != null:
		draw_mesh(mesh, null, Transform2D.IDENTITY, color)
	else:
		for points in polygons:
			draw_colored_polygon(points, color)
