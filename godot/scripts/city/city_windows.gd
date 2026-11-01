extends RefCounted
## Recover actual pane cuboids from the imported glass surface, including hidden
## optimizer sources. Security grilles are two-triangle, distance-culled cutouts.
const GLASS := preload("res://assets/materials/city_glass.gdshader")
const BARS := preload("res://assets/materials/city_window_bars.gdshader")
const GLASS_NAME := "gloss_1a2230_r25"
const CELL := 45.0
const HOMES := "res://assets/data/pen_lucy_window_homes.json"

static func glass_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.resource_name = GLASS_NAME
	return material

func build(level: Node3D, city: Node3D) -> Dictionary:
	var began := Time.get_ticks_msec()
	var groups := {}
	var homes_by_mesh := _load_homes()
	var home_counts := {}
	var first_floor := 0
	var unowned := 0
	var panes := 0
	var eligible := 0
	var barred := 0
	var root := Node3D.new()
	root.name = "WindowSecurityGrilles"
	level.add_child(root)
	var sources := city.find_children("*", "MeshInstance3D", true, false)
	for source in sources:
		var label := str(source.name)
		if not (label.begins_with("Row_") or label.begins_with("Bldg_")) or source.mesh == null:
			continue
		var homes: Array = homes_by_mesh.get(label, [])
		for surface in source.mesh.get_surface_count():
			var material: Material = source.mesh.surface_get_material(surface)
			if material == null or material.resource_name != GLASS_NAME:
				continue
			for component in _components(source, surface):
				panes += 1
				var pane := _pane(component)
				if pane.is_empty():
					continue
				var center: Vector3 = pane.center
				var home := _home_for_pane(center, homes)
				if home.is_empty():
					unowned += 1
					continue
				if not home.residential:
					continue
				var home_id: String = home.id
				var seed_value := home_seed(home_id)
				if not home_counts.has(home_id):
					home_counts[home_id] = {"windows": 0, "barred": 0, "selected": seed_value % 10 < 8}
				home_counts[home_id].windows += 1
				eligible += 1
				var ground: Dictionary = level.ground_at(center)
				if not ground.is_empty():
					var bottom: float = center.y - float(pane.height) * 0.5 - float(ground.position.y)
					if bottom >= 0.35 and bottom <= 2.60 and bottom + float(pane.height) <= 4.35:
						first_floor += 1
				# One decision and finish for the entire home, including upper floors,
				# side/rear windows and bays; joined row objects contain several homes.
				if not home_counts[home_id].selected:
					continue
				home_counts[home_id].barred += 1
				var normal: Vector3 = pane.normal
				var probe := center + Vector3.UP * float(pane.height) * 0.18
				var space := level.get_world_3d().direct_space_state
				var positive := _backing_hit(space, probe, normal)
				var negative := _backing_hit(space, probe, -normal)
				if positive and not negative:
					normal = -normal
				elif positive == negative:
					var building_center: Vector3 = source.global_transform * source.mesh.get_aabb().get_center()
					if normal.dot(center - building_center) < 0.0:
						normal = -normal
				var right := Vector3.UP.cross(normal).normalized()
				# Front of the measured pane, 3cm out: just beyond the existing sash.
				var pose := Transform3D(Basis(right * float(pane.width), Vector3.UP * float(pane.height), normal), center + normal * (float(pane.depth) * 0.5 + 0.032))
				var cell := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
				if not groups.has(cell):
					groups[cell] = []
				groups[cell].append({"pose": pose, "style": Color(float(seed_value) / 10000.0, float(pane.width), float(pane.height), 1.0)})
				barred += 1
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var bars_material := ShaderMaterial.new()
	bars_material.shader = BARS
	quad.material = bars_material
	for cell in groups:
		var records: Array = groups[cell]
		var origin := Vector3((float(cell.x) + 0.5) * CELL, 0, (float(cell.y) + 0.5) * CELL)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = quad
		multi.instance_count = records.size()
		for i in records.size():
			var pose: Transform3D = records[i].pose
			pose.origin -= origin
			multi.set_instance_transform(i, pose)
			multi.set_instance_custom_data(i, records[i].style)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Grilles_%d_%d" % [cell.x, cell.y]
		instance.position = origin
		instance.multimesh = multi
		instance.visibility_range_end = 105.0
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	return {"glass_panes": panes, "first_floor_windows": first_floor, "eligible_house_windows": eligible, "window_homes": home_counts, "unowned_windows": unowned, "barred_windows": barred, "window_bar_triangles": barred * 2, "window_bar_batches": groups.size(), "window_setup_ms": Time.get_ticks_msec() - began}

static func home_seed(home_id: String) -> int:
	# Stable across meshes, window positions, load order and future city rebuilds.
	return posmod(home_id.hash(), 10000)

func _load_homes() -> Dictionary:
	var grouped := {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(HOMES))
	if not data is Dictionary:
		return grouped
	for entry in data.get("homes", []):
		var home: Dictionary = entry.duplicate()
		var polygon := PackedVector2Array()
		for point in entry.polygon:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		home.polygon = polygon
		home.center = Vector2(float(entry.center[0]), float(entry.center[1]))
		if not grouped.has(home.source_mesh):
			grouped[home.source_mesh] = []
		grouped[home.source_mesh].append(home)
	return grouped

func _home_for_pane(center: Vector3, homes: Array) -> Dictionary:
	var point := Vector2(center.x, center.z)
	var nearest := {}
	var best_distance := INF
	var best_center := INF
	for home in homes:
		var polygon: PackedVector2Array = home.polygon
		var distance := 0.0 if Geometry2D.is_point_in_polygon(point, polygon) else INF
		for index in polygon.size() - 1:
			distance = minf(distance, point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[index + 1])))
		var center_distance := point.distance_squared_to(home.center)
		if distance < best_distance - 0.0001 or (absf(distance - best_distance) <= 0.0001 and center_distance < best_center):
			nearest = home
			best_distance = distance
			best_center = center_distance
	return nearest

func _backing_hit(space: PhysicsDirectSpaceState3D, center: Vector3, direction: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(center + direction * 0.035, center + direction * 0.30, 2)
	ray.hit_back_faces = true
	return not space.intersect_ray(ray).is_empty()

func _find(parents: Array[int], index: int) -> int:
	var root := index
	while parents[root] != root:
		root = parents[root]
	while parents[index] != index:
		var next := parents[index]
		parents[index] = root
		index = next
	return root

func _components(source: MeshInstance3D, surface: int) -> Array:
	var arrays := source.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in vertices.size():
			indices.append(i)
	# Imported flat/smoothed faces may duplicate vertices. Weld positions before
	# joining triangle components so all six faces of each pane stay together.
	var welded := {}
	var parents: Array[int] = []
	var points := PackedVector3Array()
	var remap := PackedInt32Array()
	for vertex in vertices:
		var key := Vector3i(roundi(vertex.x * 10000.0), roundi(vertex.y * 10000.0), roundi(vertex.z * 10000.0))
		if not welded.has(key):
			welded[key] = points.size()
			parents.append(points.size())
			points.append(source.global_transform * vertex)
		remap.append(welded[key])
	for i in range(0, indices.size(), 3):
		var first := _find(parents, remap[indices[i]])
		parents[_find(parents, remap[indices[i + 1]])] = first
		parents[_find(parents, remap[indices[i + 2]])] = first
	var groups := {}
	for i in points.size():
		var id := _find(parents, i)
		if not groups.has(id):
			groups[id] = {"points": PackedVector3Array(), "normal": Vector3.ZERO, "area": 0.0}
		groups[id].points.append(points[i])
	for i in range(0, indices.size(), 3):
		var a: int = remap[indices[i]]
		var b: int = remap[indices[i + 1]]
		var c: int = remap[indices[i + 2]]
		var cross := (points[b] - points[a]).cross(points[c] - points[a])
		var id := _find(parents, a)
		if cross.length_squared() > float(groups[id].area):
			groups[id].area = cross.length_squared()
			groups[id].normal = cross.normalized()
	return groups.values()

func _pane(component: Dictionary) -> Dictionary:
	var normal: Vector3 = component.normal
	if absf(normal.y) > 0.05 or normal.length_squared() < 0.9:
		return {}
	normal.y = 0.0
	normal = normal.normalized()
	var right := Vector3.UP.cross(normal).normalized()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point in component.points:
		var projected := Vector3(point.dot(right), point.y, point.dot(normal))
		low = low.min(projected)
		high = high.max(projected)
	var size := high - low
	if size.x < 0.4 or size.x > 3.4 or size.y < 0.65 or size.y > 2.6 or size.z > 0.08:
		return {}
	var middle := (low + high) * 0.5
	return {"center": right * middle.x + Vector3.UP * middle.y + normal * middle.z, "normal": normal, "width": size.x, "height": size.y, "depth": size.z}
