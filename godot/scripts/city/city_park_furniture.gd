extends Node3D
## Static furniture in surveyed greens. Setup after court/yard physics, before people.
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
const Clearance := preload("res://scripts/city/city_civic_clearance.gd")
const PLAYGROUND_PARKS := ["Community green 1", "Community green 2"]
var level: Node3D
var bench_slots: Array[Dictionary] = []
var playgrounds: Array[Dictionary] = []
var benches: Array[Dictionary] = []
var _reservations: Array[Dictionary] = []
var _visuals: Array[Dictionary] = []
var _setup_ms := 0
var _rejected := 0

func setup(owner_level: Node3D) -> Dictionary:
	level = owner_level
	name = "ParkFurniture"
	var began := Time.get_ticks_msec()
	for park in level.level_data.get("parks", []):
		if float(park.get("area_m2", 0)) < 1500.0:
			continue
		var polygon := PackedVector2Array()
		for value in park.polygon:
			var at: Vector3 = level.vector(value)
			polygon.append(Vector2(at.x, at.z))
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		var candidates: Array[Vector3] = []
		for x in range(ceili(bounds.position.x + 3), floori(bounds.end.x - 3), 2):
			for z in range(ceili(bounds.position.y + 3), floori(bounds.end.y - 3), 2):
				candidates.append(Vector3(x, 0, z))
		var center := Vector3(bounds.get_center().x, 0, bounds.get_center().y)
		candidates.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(center) < b.distance_squared_to(center))
		if str(park.name) in PLAYGROUND_PARKS:
			var compact := str(park.name) == "Community green 2"
			var placed := false
			# The terrain can reject a broad pad even when its plan-view rectangle
			# fits. A compact layout preserves trees and court buffers in that case.
			for play_size in ([Vector2(7,6)] if compact else [Vector2(9,8), Vector2(7,6)]):
				for candidate in candidates:
					var found := _placement(candidate, play_size, polygon, park.get("holes", []))
					if found.is_empty():
						continue
					_build_playground(found.position, str(park.name), 0.75 if play_size.x < 8 else 1.0, play_size)
					placed = true
					break
				if placed:
					break
		var count := 0
		for candidate in candidates:
			if count >= 6:
				break
			var found := _placement(candidate, Vector2(3, 2.5), polygon, park.get("holes", []))
			if found.is_empty():
				continue
			var at: Vector3 = found.position
			var forward := (center - at).normalized()
			_build_bench(at, atan2(forward.x, forward.z), str(park.name))
			count += 1
	if level.get("vegetation") != null:
		level.vegetation.clear_playground_shrubs(playgrounds)
	_setup_ms = Time.get_ticks_msec() - began
	set_process(false)
	return get_status()

func _placement(wanted: Vector3, size: Vector2, polygon: PackedVector2Array, holes: Array) -> Dictionary:
	var radius := size.length() * 0.5
	if Clearance.blocked(level, wanted, radius) or not is_clear(wanted, radius + 1.0):
		return {}
	var flat := Vector2(wanted.x, wanted.z)
	if not Geometry2D.is_point_in_polygon(flat, polygon):
		return {}
	for i in polygon.size():
		if Geometry2D.get_closest_point_to_segment(flat, polygon[i], polygon[(i + 1) % polygon.size()]).distance_to(flat) < radius + 1.0:
			return {}
	for ring in holes:
		var hole := PackedVector2Array()
		for value in ring:
			var point: Vector3 = level.vector(value)
			hole.append(Vector2(point.x, point.z))
		if Geometry2D.is_point_in_polygon(flat, hole):
			return {}
		for i in hole.size():
			if Geometry2D.get_closest_point_to_segment(flat, hole[i], hole[(i + 1) % hole.size()]).distance_to(flat) < radius + 1:
				return {}
	if level.get("park_courts") != null and level.park_courts.is_court(wanted, radius + 2.0):
		return {}
	if level.get("vegetation") != null and not level.vegetation.is_trunk_clear(wanted, radius + 0.5):
		return {}
	if level.get("yard_details") != null and not level.yard_details.is_clear(wanted, radius):
		return {}
	var hit: Dictionary = level.ground_at(wanted)
	if hit.is_empty() or hit.normal.y < 0.94:
		return {}
	var at: Vector3 = hit.position
	for corner in [Vector2(-1,-1), Vector2(-1,1), Vector2(1,-1), Vector2(1,1)]:
		var sample: Dictionary = level.ground_at(at + Vector3(corner.x * size.x * 0.5, 0, corner.y * size.y * 0.5))
		if sample.is_empty() or absf(sample.position.y - at.y) > (0.35 if size.x > 4 else 0.22):
			return {}
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 3.0, size.y)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.6)
	query.collision_mask = 2 | 8 | 16
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_rejected += 1
		return {}
	return {"position": at}

func _palette(title: String):
	var kit := Kit.new(title)
	kit.material("timber", Color("8b7050"), 6)
	kit.material("steel", Color("334e51"), 6)
	kit.material("rubber", Color("88684f"), 0)
	kit.material("color", Color("ba8647"), 6)
	return kit

func _finish(kit, at: Vector3, yaw := 0.0) -> Node3D:
	var node: Node3D = kit.finish()
	node.position = at
	node.rotation.y = yaw
	add_child(node)
	var visual := node.get_node("BatchedArchitecture") as MeshInstance3D
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.append({"node": visual, "position": at})
	return node

func _build_bench(at: Vector3, yaw: float, park: String) -> void:
	var kit = _palette("ParkBench_%d" % benches.size())
	for z in [-0.18, 0.0, 0.18]:
		kit.box(Vector3(0, 0.38, z), Vector3(2.2, 0.08, 0.14), "timber")
	for y in [0.63, 0.82]:
		kit.box(Vector3(0, y, -0.25), Vector3(2.2, 0.13, 0.09), "timber")
	for x in [-0.85, 0.85]:
		# Open steel trestles replace solid slabs, within the same solid seat.
		for z in [-0.17, 0.17]:
			kit.box(Vector3(x, 0.0, z), Vector3(0.09, 0.8, 0.08), "steel")
		kit.box(Vector3(x, 0.30, 0), Vector3(0.12, 0.08, 0.45), "steel")
		kit.box(Vector3(x, 0.58, -0.25), Vector3(0.08, 0.5, 0.08), "steel")
		for y in [0.63, 0.82]:
			kit.box(Vector3(x, y, -0.20), Vector3(0.035, 0.035, 0.018), "steel")
	kit.solid_box(Vector3(0, 0.22, 0), Vector3(2.2, 0.4, 0.52))
	kit.solid_box(Vector3(0, 0.7, -0.25), Vector3(2.2, 0.4, 0.12))
	var node := _finish(kit, at, yaw)
	var bench_id := benches.size()
	benches.append({"position": at, "park": park, "node": node})
	_reservations.append({"position": at, "radius": 1.5})
	for x in [-0.5, 0.5]:
		bench_slots.append({"position": at + Basis(Vector3.UP, yaw) * Vector3(x, 0, 0), "yaw": yaw, "park": park, "bench_id": bench_id, "body": kit.body})

func _build_playground(at: Vector3, park: String, horizontal_scale: float, size: Vector2) -> void:
	var kit = _palette("Playground_%d" % playgrounds.size())
	# Thin terrain-following rubber pad: it adds no raised collision lip.
	for x in range(-4, 4, 2):
		for z in range(-3, 3, 2):
			var points: Array[Vector3] = []
			for offset in [Vector3(x,0,z), Vector3(x+2,0,z), Vector3(x+2,0,z+2), Vector3(x,0,z+2)]:
				var hit: Dictionary = level.ground_at(at + offset * horizontal_scale)
				var y: float = hit.position.y - at.y if not hit.is_empty() else 0.0
				points.append(Vector3(offset.x, y + 0.025, offset.z))
			kit.triangle(points[0], points[1], points[2], "rubber")
			kit.triangle(points[0], points[2], points[3], "rubber")
	# Static swing frame; seats and chains are scenery, not dangling physics bodies.
	for x in [-3.2, -0.8]:
		for z in [-1.2, 1.2]:
			kit.cylinder(Vector3(x, 1.1, z), 0.07, 3.2, "steel", 6)
			kit.solid_box(Vector3(x, 1.1, z), Vector3(0.14, 3.2, 0.14))
		kit.box(Vector3(x, 2.7, 0), Vector3(0.14, 0.14, 2.5), "steel")
	kit.box(Vector3(-2, 2.7, 0), Vector3(2.6, 0.14, 0.14), "steel")
	for x in [-2.6, -1.4]:
		kit.box(Vector3(x, 0.48, 0), Vector3(0.65, 0.09, 0.32), "color")
		for side in [-0.26, 0.26]:
			kit.cylinder(Vector3(x + side, 1.57, 0), 0.018, 2.18, "steel", 5)
	# Low climbing deck and broad slide contained inside the pad.
	kit.box(Vector3(2, 0.9, -1), Vector3(1.6, 0.16, 1.6), "color")
	kit.solid_box(Vector3(2, 0.2, -1), Vector3(1.6, 1.4, 1.6))
	for x in [1.3, 2.7]:
		for z in [-1.7, -0.3]:
			kit.box(Vector3(x, 0.2, z), Vector3(0.12, 1.4, 0.12), "steel")
	for x in [1.3, 2.7]:
		kit.box(Vector3(x, 1.4, -1.7), Vector3(0.08, 1.0, 0.08), "steel")
	kit.box(Vector3(2, 1.85, -1.7), Vector3(1.5, 0.08, 0.08), "steel")
	var a := Vector3(1.4, 0.98, -0.2)
	var b := Vector3(2.6, 0.98, -0.2)
	var c := Vector3(2.6, 0.05, 2.5)
	var d := Vector3(1.4, 0.05, 2.5)
	for point in [c, d]:
		var hit: Dictionary = level.ground_at(at + Vector3(point.x * horizontal_scale, 0, point.z * horizontal_scale))
		if not hit.is_empty():
			if point.x > 2:
				c.y = hit.position.y - at.y + 0.05
			else:
				d.y = hit.position.y - at.y + 0.05
	kit.triangle(a, b, c, "color")
	kit.triangle(a, c, d, "color")
	# Give the slide its existing collision thickness instead of a paper edge.
	var underside := Vector3.DOWN * 0.12
	kit.triangle(a + underside, c + underside, b + underside, "steel")
	kit.triangle(a + underside, d + underside, c + underside, "steel")
	for edge in [[a, b], [b, c], [c, d], [d, a]]:
		kit.triangle(edge[0], edge[0] + underside, edge[1] + underside, "color")
		kit.triangle(edge[0], edge[1] + underside, edge[1], "color")
	kit.solid_convex(PackedVector3Array([a,b,c,d,a-Vector3.UP*0.12,b-Vector3.UP*0.12,c-Vector3.UP*0.12,d-Vector3.UP*0.12]))
	var node := _finish(kit, at)
	node.scale = Vector3(horizontal_scale, 1, horizontal_scale)
	playgrounds.append({"position": at, "park": park, "size": size})
	_reservations.append({"position": at, "radius": size.length() * 0.5})

func is_clear(point: Vector3, radius := 0.35) -> bool:
	for item in _reservations:
		if Vector2(point.x - item.position.x, point.z - item.position.z).length() < radius + float(item.radius):
			return false
	return true

func set_presence(center: Vector3, _near := 55.0, far := 180.0) -> void:
	for item in _visuals:
		item.node.visible = item.position.distance_squared_to(center) < pow(maxf(far, 180.0), 2)

func get_status() -> Dictionary:
	return {"benches": benches.size(), "bench_seats": bench_slots.size(), "playgrounds": playgrounds.size(), "playground_parks": playgrounds.map(func(p): return p.park), "draw_batches": _visuals.size(), "setup_ms": _setup_ms, "obstructed_candidates": _rejected}
