extends Node3D
## Authored redevelopment applied before collision, population and map setup.
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
const PLAN := "res://assets/data/pen_lucy_civic_build.json"
const SHOPS := "res://assets/data/pen_lucy_new_businesses.json"
var level: Node3D
var sites: Array = []
var businesses: Array = []
var removed_meshes: Array[String] = []
var removed_building_ids: Array[String] = []
var map_buildings: Array[Dictionary] = []
var map_pois: Array[Dictionary] = []
var original_level_data: Dictionary = {}
var _clear_regions: Array[Dictionary] = []
var _buildings: Array[Node3D] = []
var _removed_actual: Array[String] = []
var _ground_faces := PackedVector3Array()
var _setup_ms := 0

func setup(owner_level: Node3D, city: Node3D) -> void:
	level = owner_level
	original_level_data = level.level_data.duplicate(false)
	name = "CivicDistrict"
	var began := Time.get_ticks_msec()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	sites = plan.get("sites", [])
	if FileAccess.file_exists(SHOPS):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SHOPS))
		businesses = data.get("businesses", data.get("records", [])) if data is Dictionary else data
	for site in sites:
		for id in site.get("demolition_ids", []):
			if not str(id) in removed_building_ids:
				removed_building_ids.append(str(id))
		for mesh_name in site.get("demolition_meshes", []):
			if not str(mesh_name) in removed_meshes:
				removed_meshes.append(str(mesh_name))
		_region(site.footprint_xz)
		if site.has("approach_center"):
			var start := _point(site.approach_center)
			var end := _point(site.position)
			var right := Vector3(end.z - start.z, 0, start.x - end.x).normalized() * 2.7
			_region([[start.x-right.x,start.z-right.z], [start.x+right.x,start.z+right.z], [end.x+right.x,end.z+right.z], [end.x-right.x,end.z-right.z]])
		for key in ["parking_lot_xz", "apron_xz"]:
			if site.has(key):
				_region(site[key])
		if site.id == "fire":
			var grounds_path := "res://assets/data/pen_lucy_fire_grounds.json"
			if FileAccess.file_exists(grounds_path):
				var grounds_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(grounds_path))
				_region(grounds_data.get("clearance_polygon_xz", []))
		if site.has("landscape_clear_zone"):
			_geo_regions(site.landscape_clear_zone)
	for entry in businesses:
		for id in entry.get("building_ids", []):
			if not str(id) in removed_building_ids:
				removed_building_ids.append(str(id))
		var mesh_name := str(entry.get("source_mesh", ""))
		if not mesh_name.is_empty() and not mesh_name in removed_meshes:
			removed_meshes.append(mesh_name)
		_region(entry.get("clearance_polygon", entry.get("polygon", [])))
	for mesh_name in removed_meshes:
		var old := city.find_child(mesh_name, true, false)
		if old != null:
			old.get_parent().remove_child(old)
			old.free()
			_removed_actual.append(mesh_name)
	_prepare_map()
	_filter_level_metadata()
	for site in sites:
		_build_site(site)
	for entry in businesses:
		_build_shop(entry)
	if not _ground_faces.is_empty():
		var support := StaticBody3D.new()
		support.name = "RedevelopedGround"
		support.collision_layer = 1
		support.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_ground_faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		support.add_child(collision)
		add_child(support)
	_setup_ms = Time.get_ticks_msec() - began

func _point(value) -> Vector3:
	return value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))

func _polygon(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in values:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result

func _region(values: Array, holes: Array = []) -> void:
	if values.size() < 3:
		return
	var excluded: Array[PackedVector2Array] = []
	for hole in holes:
		excluded.append(_polygon(hole))
	var outer := _polygon(values)
	var bounds := Rect2(outer[0], Vector2.ZERO)
	for point in outer:
		bounds = bounds.expand(point)
	_clear_regions.append({"outer": outer, "holes": excluded, "bounds": bounds.grow(0.001)})

func _geo_regions(geometry: Dictionary) -> void:
	var polygons: Array = geometry.coordinates if geometry.type == "MultiPolygon" else [geometry.coordinates]
	for polygon in polygons:
		_region(polygon[0], polygon.slice(1))

func is_cleared(at: Vector3) -> bool:
	var point := Vector2(at.x, at.z)
	for region in _clear_regions:
		if not region.bounds.has_point(point):
			continue
		if not Geometry2D.is_point_in_polygon(point, region.outer):
			continue
		var excluded := false
		for hole in region.holes:
			if Geometry2D.is_point_in_polygon(point, hole):
				excluded = true
				break
		if not excluded:
			return true
	return false

func _prepare_map() -> void:
	var homes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_window_homes.json"))
	for home in homes.homes:
		if str(home.id) in removed_building_ids or str(home.source_mesh) in removed_meshes:
			continue
		map_buildings.append({"id": home.id, "polygon": home.polygon})
	for site in sites:
		map_buildings.append({"id": site.id, "polygon": site.footprint_xz})
		map_pois.append({"id": site.id, "label": site.name, "position": _point(site.position), "service": site.id})
	for entry in businesses:
		map_buildings.append({"id": entry.id, "polygon": entry.polygon})
		map_pois.append({"id": entry.id, "label": entry.label, "position": _point(entry.position), "service": entry.service})

func _filter_level_metadata() -> void:
	for key in ["rear_doors", "porch_stairs", "facade_details", "businesses", "dressing"]:
		var kept: Array = []
		for entry in level.level_data.get(key, []):
			if str(entry.get("building_id", "")) in removed_building_ids or str(entry.get("source_mesh", "")) in removed_meshes:
				continue
			if entry.has("position") and is_cleared(_point(entry.position)):
				continue
			kept.append(entry)
		level.level_data[key] = kept

func _build_site(site: Dictionary) -> void:
	var script = load("res://scripts/city/city_civic_%s.gd" % site.id)
	if script == null or not script.can_instantiate():
		push_error("Civic building unavailable: " + str(site.id))
		return
	var model: Node3D = script.build()
	var footprint: Vector2 = script.footprint()
	model.scale = Vector3(minf(1.0, float(site.width_m) / footprint.x), 1, minf(1.0, float(site.depth_m) / footprint.y))
	model.position = _point(site.position)
	model.rotation.y = float(site.yaw)
	add_child(model)
	model.set_meta("civic_id", site.id)
	# Show the built footprint, not the larger reserved clearance envelope.
	var outline: Array = []
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var point: Vector3 = model.transform * (corner * Vector3(footprint.x, 0, footprint.y) * 0.5)
		outline.append([point.x, point.z])
	for building in map_buildings:
		if str(building.id) == str(site.id):
			building.polygon = outline
			break
	_buildings.append(model)
	_foundation(site, model.scale * Vector3(footprint.x, 1, footprint.y))
	if site.id == "hospital" and ResourceLoader.exists("res://scripts/city/city_civic_hospital_grounds.gd"):
		add_child(load("res://scripts/city/city_civic_hospital_grounds.gd").build(site))
		return
	if site.id == "fire" and ResourceLoader.exists("res://scripts/city/city_civic_fire_grounds.gd"):
		add_child(load("res://scripts/city/city_civic_fire_grounds.gd").build(site))
		return
	var paving := Kit.new(str(site.id) + "Paving")
	paving.material("paving", Color("535653"), 3)
	paving.material("walk", Color("a19b89"), 2)
	paving.material("paint", Color("d4c9a4"), 0)
	if site.has("parking_surround_triangles"):
		for tri in site.parking_surround_triangles:
			_ground_triangle(paving, _point(tri[0]), _point(tri[1]), _point(tri[2]), "paving")
	else:
		for patch in site.get("terrain_patches", []):
			for tri in patch.triangles:
				_ground_triangle(paving, _point(tri[0]), _point(tri[1]), _point(tri[2]), "paving")
	var access := site.duplicate()
	var actual_front := model.position + Vector3(sin(float(site.yaw)), 0, cos(float(site.yaw))) * (footprint.y * model.scale.z * 0.5)
	access.entry_world = [actual_front.x, actual_front.y, actual_front.z]
	_entry_approach(paving, access)
	if site.has("parking_lot_xz"):
		# A small marked precinct lot on the removed south building's terrain.
		for tri in site.get("parking_triangles", []):
			_ground_triangle(paving, _point(tri[0]), _point(tri[1]), _point(tri[2]), "paving")
		for stripe in site.get("parking_stripes", []):
			paving.box(_point(stripe.position), _point(stripe.size), "paint")
	if site.has("apron_xz"):
		_polygon_floor(paving, _polygon(site.apron_xz), float(site.floor_y), "walk")
	add_child(paving.finish())
	if site.id == "police":
		add_child(preload("res://scripts/city/city_police_lot.gd").build(site))

func _foundation(entry: Dictionary, footprint: Vector3) -> void:
	var kit := Kit.new(str(entry.get("id", "site")) + "Foundation")
	kit.material("stone", Color("77776d"), 2)
	var depth := float(entry.get("foundation_min_depth_m", entry.get("foundation_depth", 1.0)))
	var size := Vector3(footprint.x, depth, footprint.z)
	kit.box(Vector3(0, -depth * 0.5 - 0.015, 0), size, "stone")
	kit.solid_box(Vector3(0, -depth * 0.5 - 0.015, 0), size)
	var node := kit.finish()
	node.position = _point(entry.position)
	node.rotation.y = float(entry.yaw)
	add_child(node)

func _entry_approach(kit: RefCounted, site: Dictionary) -> void:
	if not site.has("approach_center"):
		return
	var start := _point(site.approach_center)
	var end := _point(site.entry_world)
	var right := Vector3(end.z - start.z, 0, start.x - end.x).normalized() * 2.5
	_ground_triangle(kit, start - right, start + right, end + right, "walk")
	_ground_triangle(kit, start - right, end + right, end - right, "walk")

func _polygon_floor(kit: RefCounted, polygon: PackedVector2Array, y: float, material: String) -> void:
	if polygon.size() > 3 and polygon[0].is_equal_approx(polygon[-1]):
		polygon = polygon.slice(0, polygon.size() - 1)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var points: Array[Vector3] = []
		for j in 3:
			var p := polygon[indices[i + j]]
			points.append(Vector3(p.x, y, p.y))
		_ground_triangle(kit, points[0], points[1], points[2], material)

func _ground_triangle(kit: RefCounted, a: Vector3, b: Vector3, c: Vector3, material: String) -> void:
	# Godot front faces are clockwise. Keep support and visible winding identical.
	if (c - a).cross(b - a).y < 0:
		var swap := b
		b = c
		c = swap
	kit.triangle(a, b, c, material)
	_ground_faces.append_array(PackedVector3Array([a, b, c]))

func _build_shop(entry: Dictionary) -> void:
	var script = load("res://scripts/city/city_civic_businesses.gd")
	if script == null:
		return
	var model: Node3D = script.build(entry)
	model.position = _point(entry.position)
	model.rotation.y = float(entry.yaw)
	add_child(model)
	_buildings.append(model)

func set_presence(center: Vector3, _near: float = 55.0, far: float = 180.0) -> void:
	for model in _buildings:
		model.visible = model.global_position.distance_squared_to(center) < pow(maxf(far + 220.0, 400.0), 2)

func get_status() -> Dictionary:
	return {"sites": sites.size(), "businesses": businesses.size(), "demolished_meshes": _removed_actual,
		"removed_building_ids": removed_building_ids, "map_footprints": map_buildings.size(), "map_pois": map_pois.size(),
		"ground_patch_triangles": _ground_faces.size() / 3, "setup_ms": _setup_ms}
