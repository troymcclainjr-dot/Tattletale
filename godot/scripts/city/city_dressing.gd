class_name CityDressing
extends RefCounted
## Small, human-scale street furniture for the Pen Lucy walking route.
## Only surveyed, clearance-checked anchors from level_data are used. These props
## are interpretive scenery, not a claim that an individual fixture exists on site.

const OBSTACLE_LAYER := 2
const IRON := "#3a3a3e"
const GREEN := "#2f4f34"
const CREAM := "#f4f0e6"
const WOOD := "#9a7444"
const RED := "#a83a2a"
# Measured from the first imported furniture.glb lamp's glow-material vertices,
# after source_lamp_mesh() subtracts its (-24, 0.16, -0.2) source origin.
const LAMP_LENS_LOCAL := Vector3(0.0, 4.758, 0.519)
static var _source_lamp: ArrayMesh
static var _source_stop: ArrayMesh
const Surfaces := preload("res://scripts/city/city_street_surfaces.gd")


static func build(parent: Node3D, level_data: Dictionary) -> Dictionary:
	var root := Prim.group(parent, 0, 0, 0, "PenLucyStreetDetails")
	var counts: Dictionary = {}
	var total := 0
	var skipped := 0
	var lamp_anchors: Array[Dictionary] = []
	for value in level_data.get("dressing", []):
		if not value is Dictionary:
			skipped += 1
			continue
		var anchor: Dictionary = value
		var coordinates: Array = anchor.get("position", [])
		var kind: String = str(anchor.get("kind", ""))
		if coordinates.size() != 3 or kind not in ["street_sign", "lamp", "hydrant", "bin", "bench", "bus_stop"]:
			skipped += 1
			continue
		var location := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		if not location.is_finite():
			skipped += 1
			continue
		if kind == "lamp":
			var checked := relocate_fixture(parent, location, 0.28, 5.0)
			if checked.is_empty():
				skipped += 1
				continue
			location = checked.position
			var lamp_yaw := float(anchor.get("yaw", 0.0))
			var lens := location + Basis(Vector3.UP, lamp_yaw) * LAMP_LENS_LOCAL
			lamp_anchors.append({"position": location, "head_position": lens, "yaw": lamp_yaw,
				"radius": 0.28, "source": "authored", "sidewalk_checked": true})
		var prop := Prim.group(root, location.x, location.y, location.z, "%s_%02d" % [kind, total])
		prop.rotation.y = float(anchor.get("yaw", 0.0))
		prop.set_meta("dressing_kind", kind)
		prop.set_meta("anchor_id", str(anchor.get("id", kind)))
		prop.set_meta("placement", str(anchor.get("description", "Interpretive neighborhood street furniture")))
		match kind:
			"street_sign":
				_street_sign(prop, anchor)
			"lamp":
				_lamp(prop)
			"hydrant":
				_hydrant(prop)
			"bin":
				_bin(prop)
			"bench":
				_bench(prop)
			"bus_stop":
				_bus_stop(prop, anchor)
		counts[kind] = int(counts.get(kind, 0)) + 1
		total += 1
	return {"root": root, "count": total, "counts": counts, "skipped": skipped, "lamp_anchors": lamp_anchors}


static func _box(parent: Node3D, size: Vector3, center: Vector3, color: String) -> MeshInstance3D:
	return Prim.M(Prim.box(size.x, size.y, size.z), ClayLib.clay(color), center.x, center.y, center.z, parent)


static func _cylinder(parent: Node3D, radius: float, height: float, center: Vector3, color: String, top_radius: float = -1.0) -> MeshInstance3D:
	return Prim.M(Prim.cyl(radius if top_radius < 0.0 else top_radius, radius, height, 12), ClayLib.clay(color), center.x, center.y, center.z, parent)


static func _body(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SolidStreetFixture"
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _solid_box(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


static func _solid_pole(body: StaticBody3D, radius: float, height: float, center: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


## Two separately oriented faces keep text readable from either approach.
static func _panel(parent: Node3D, text: String, width: float, height: float, center: Vector3, color: String, ink: String = CREAM) -> void:
	_box(parent, Vector3(width, height, 0.065), center, color)
	for side in [-1.0, 1.0]:
		var label := Prim.label(text, width - 0.1, height - 0.055, ink, "mono")
		label.position = center + Vector3(0, 0, side * 0.036)
		label.rotation.y = PI if side < 0.0 else 0.0
		parent.add_child(label)


static func _street_sign(parent: Node3D, anchor: Dictionary) -> void:
	var names: Array = anchor.get("street_names", [])
	_cylinder(parent, 0.055, 2.85, Vector3(0, 1.425, 0), IRON)
	_cylinder(parent, 0.12, 0.065, Vector3(0, 0.0325, 0), IRON)
	var body := _body(parent)
	_solid_pole(body, 0.12, 0.065, Vector3(0, 0.0325, 0))
	_solid_pole(body, 0.07, 2.85, Vector3(0, 1.425, 0))
	for i in mini(names.size(), 2):
		var board := Prim.group(parent)
		board.rotation.y = PI / 2.0 if i == 1 else 0.0
		var title: String = str(names[i])
		var width: float = clampf(title.length() * 0.085, 1.1, 2.1)
		_panel(board, title.to_upper(), width, 0.29, Vector3(0, 2.65 - i * 0.34, 0), GREEN)
		# Above head clearance; include signs in physics for camera/raised-player rays.
		var board_body := _body(board)
		_solid_box(board_body, Vector3(width, 0.29, 0.065), Vector3(0, 2.65 - i * 0.34, 0))


static func _lamp(parent: Node3D) -> void:
	var imported := source_lamp_mesh()
	if imported:
		var lamp := MeshInstance3D.new()
		lamp.mesh = imported
		parent.add_child(lamp)
		var solid := _body(parent)
		_solid_pole(solid, 0.16, 4.8, Vector3(0, 2.4, 0))
		return
	_cylinder(parent, 0.18, 0.2, Vector3(0, 0.1, 0), IRON)
	_cylinder(parent, 0.105, 4.3, Vector3(0, 2.25, 0), IRON, 0.065)
	_cylinder(parent, 0.15, 0.11, Vector3(0, 0.38, 0), IRON)
	# A modest roadway fixture, with a short arm over the curb rather than a tall floodlight.
	var arm := _cylinder(parent, 0.05, 0.8, Vector3(0, 4.23, 0.36), IRON)
	arm.rotation.x = PI * 0.43
	_box(parent, Vector3(0.32, 0.16, 0.58), Vector3(0, 4.28, 0.77), IRON)
	Prim.M(Prim.box(0.25, 0.025, 0.43), ClayLib.glow("#e8dcc0", 0.28), 0, 4.187, 0.77, parent, false)
	var body := _body(parent)
	_solid_pole(body, 0.18, 0.2, Vector3(0, 0.1, 0))
	_solid_pole(body, 0.105, 4.3, Vector3(0, 2.25, 0))
	_solid_pole(body, 0.15, 0.11, Vector3(0, 0.38, 0))
	_solid_box(body, Vector3(0.32, 0.25, 1.1), Vector3(0, 4.25, 0.4))


static func _hydrant(parent: Node3D) -> void:
	_cylinder(parent, 0.21, 0.08, Vector3(0, 0.04, 0), RED)
	_cylinder(parent, 0.145, 0.58, Vector3(0, 0.37, 0), RED)
	_cylinder(parent, 0.18, 0.075, Vector3(0, 0.65, 0), RED)
	Prim.M(Prim.sph(0.165, 12, 6), ClayLib.clay(RED), 0, 0.69, 0, parent)
	_cylinder(parent, 0.052, 0.09, Vector3(0, 0.85, 0), IRON)
	for side in [-1.0, 1.0]:
		var outlet := _cylinder(parent, 0.085, 0.16, Vector3(side * 0.19, 0.51, 0), RED)
		outlet.rotation.z = PI / 2.0
		var cap := _cylinder(parent, 0.1, 0.05, Vector3(side * 0.29, 0.51, 0), IRON)
		cap.rotation.z = PI / 2.0
	var front := _cylinder(parent, 0.105, 0.15, Vector3(0, 0.37, 0.16), IRON)
	front.rotation.x = PI / 2.0
	var body := _body(parent)
	_solid_pole(body, 0.21, 0.9, Vector3(0, 0.45, 0))
	_solid_box(body, Vector3(0.64, 0.22, 0.24), Vector3(0, 0.51, 0))


static func _bin(parent: Node3D) -> void:
	_cylinder(parent, 0.28, 0.8, Vector3(0, 0.44, 0), GREEN, 0.31)
	_cylinder(parent, 0.33, 0.065, Vector3(0, 0.87, 0), IRON)
	_cylinder(parent, 0.29, 0.07, Vector3(0, 0.075, 0), IRON)
	# Thin vertical ribs and a visible top opening give the can a useful silhouette.
	for i in 10:
		var angle := float(i) * TAU / 10.0
		_cylinder(parent, 0.018, 0.72, Vector3(sin(angle) * 0.305, 0.46, cos(angle) * 0.305), IRON)
	_cylinder(parent, 0.235, 0.012, Vector3(0, 0.908, 0), "#1a1a1e")
	var body := _body(parent)
	_solid_pole(body, 0.34, 0.92, Vector3(0, 0.46, 0))


static func _bench(parent: Node3D) -> void:
	var body := _body(parent)
	for x in [-0.64, 0.64]:
		for z in [-0.21, 0.21]:
			_box(parent, Vector3(0.065, 0.44, 0.065), Vector3(x, 0.22, z), IRON)
		_box(parent, Vector3(0.07, 0.5, 0.06), Vector3(x, 0.68, -0.25), IRON)
		_solid_box(body, Vector3(0.08, 0.44, 0.5), Vector3(x, 0.22, 0))
	for z in [-0.18, -0.06, 0.06, 0.18]:
		_box(parent, Vector3(1.7, 0.065, 0.1), Vector3(0, 0.47, z), WOOD)
	for y in [0.66, 0.81]:
		_box(parent, Vector3(1.7, 0.12, 0.065), Vector3(0, y, -0.25), WOOD)
	_solid_box(body, Vector3(1.7, 0.075, 0.48), Vector3(0, 0.47, 0))
	_solid_box(body, Vector3(1.7, 0.44, 0.08), Vector3(0, 0.71, -0.25))


static func _bus_stop(parent: Node3D, anchor: Dictionary) -> void:
	# Only enabled by an explicit metadata anchor. No invented operator or route number.
	_cylinder(parent, 0.045, 2.75, Vector3(0, 1.375, 0), IRON)
	_panel(parent, "BUS", 0.45, 0.48, Vector3(0, 2.45, 0), "#2a4a7a")
	_panel(parent, str(anchor.get("label", "Argonne Dr")), 0.65, 0.21, Vector3(0, 2.07, 0), CREAM, IRON)
	_box(parent, Vector3(0.23, 0.34, 0.07), Vector3(0, 1.42, 0.035), IRON)
	_box(parent, Vector3(0.18, 0.27, 0.012), Vector3(0, 1.42, 0.077), CREAM)
	for y in [1.49, 1.43, 1.37]:
		_box(parent, Vector3(0.12, 0.012, 0.008), Vector3(0, y, 0.086), GREEN)
	var body := _body(parent)
	_solid_pole(body, 0.065, 2.75, Vector3(0, 1.375, 0))
	_solid_box(body, Vector3(0.23, 0.34, 0.1), Vector3(0, 1.42, 0.035))
	_solid_box(body, Vector3(0.65, 0.8, 0.07), Vector3(0, 2.35, 0))


## furniture.glb is world-space: its Lamps mesh contains six fixtures. Extract
## the complete first lamp (x=-24, ground=.16, z=-.2), preserving source materials.
## Cache once and instance it; never instantiate the whole original city block.
static func source_lamp_mesh() -> ArrayMesh:
	if _source_lamp:
		return _source_lamp
	var furniture := Assets.glb("furniture")
	if furniture == null:
		return null
	var source := Assets.find(furniture, "Lamps") as MeshInstance3D
	if source == null or source.mesh == null:
		furniture.free()
		return null
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(source.get_active_material(surface))
		var selected := 0
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for triangle in range(0, count, 3):
			var first := indices[triangle] if not indices.is_empty() else triangle
			if vertices[first].x < -25.0 or vertices[first].x > -23.0:
				continue
			for corner in 3:
				var index := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				if not normals.is_empty():
					builder.set_normal(normals[index])
				builder.add_vertex(vertices[index] - Vector3(-24, 0.16, -0.2))
			selected += 3
		if selected > 0:
			builder.commit(result)
	furniture.free()
	if result.get_surface_count() > 0:
		_source_lamp = result
	return _source_lamp


## Ground, building clearance and the full walking-route corridor are checked
## before adding a new fixture. Called after the terrain physics frame.
static func fixture_position(level: Node3D, at: Vector3, radius: float = 0.25, height: float = 5.0, diagnostic: Dictionary = {}) -> Dictionary:
	if not Surfaces.circle_clear("sidewalk", at, radius + 0.04):
		diagnostic["reason"] = "outside_sidewalk_footprint"
		return {}
	var vegetation = level.get("vegetation")
	if is_instance_valid(vegetation) and vegetation.has_method("is_trunk_clear") and not vegetation.is_trunk_clear(at, radius + 0.2):
		diagnostic["reason"] = "tree_trunk"
		return {}
	var yards = level.get("yard_details")
	if is_instance_valid(yards) and yards.has_method("is_clear") and not yards.is_clear(at, radius + 0.1):
		diagnostic["reason"] = "yard_fixture"
		return {}
	var points: Array = level.level_data.get("route", {}).get("points", [])
	var flat := Vector2(at.x, at.z)
	for i in range(1, points.size()):
		var a := Vector2(float(points[i - 1][0]), float(points[i - 1][2]))
		var b := Vector2(float(points[i][0]), float(points[i][2]))
		if Geometry2D.get_closest_point_to_segment(flat, a, b).distance_to(flat) < radius + 0.8:
			diagnostic["reason"] = "walking_route"
			return {}
	var space := level.get_world_3d().direct_space_state
	var low := INF
	var high := -INF
	for i in 13:
		var angle := float(i) * TAU / 12.0
		var sample := at + (Vector3.ZERO if i == 12 else Vector3(cos(angle), 0, sin(angle)) * radius)
		var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 4, sample - Vector3.UP * 4, 1)
		ray.hit_back_faces = false
		var ground := space.intersect_ray(ray)
		if ground.is_empty():
			diagnostic["reason"] = "unsupported_base"
			return {}
		if ground.normal.y < 0.9:
			diagnostic["reason"] = "steep_ground"
			return {}
		low = minf(low, ground.position.y)
		high = maxf(high, ground.position.y)
	if high - low > 0.065:
		diagnostic["reason"] = "uneven_base"
		return {}
	# Embed the base just below the lowest support sample; no edge hangs in air.
	at.y = low - 0.008
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * height * 0.5)
	query.collision_mask = 2 | 4 | 8 | 16
	var hits := space.intersect_shape(query, 1)
	if not hits.is_empty():
		diagnostic["reason"] = "occupied"
		var collider: Node = hits[0].collider
		diagnostic["collider"] = str(collider.get_parent().name) if collider.get_parent() else str(collider.name)
		return {}
	return {"position": at, "base_min_y": low, "base_max_y": high, "sidewalk_checked": true}


static func _curb_fixture(level: Node3D, center: Vector3, forward: Vector3, side: Vector3, half_width: float, radius: float, height: float, checks: Dictionary = {}, reserved: Array[Vector3] = [], along_offsets: Array = [0.0, 3.0, -3.0, 6.0, -6.0, 10.0, -10.0, 14.0, -14.0]) -> Dictionary:
	for along in along_offsets:
		for gap in [0.65, 0.9, 1.2, 1.5]:
			var at := center + forward * float(along) + side * (half_width + float(gap))
			var occupied := false
			for previous in reserved:
				if Vector2(at.x - previous.x, at.z - previous.z).length() < 1.2:
					occupied = true
					break
			if occupied:
				continue
			var diagnostic: Dictionary = {}
			var found := fixture_position(level, at, radius, height, diagnostic)
			checks["attempts"] = int(checks.get("attempts", 0)) + 1
			if not found.is_empty():
				return found
			var reasons: Dictionary = checks.get("reasons", {})
			var reason := str(diagnostic.get("reason", "unknown"))
			reasons[reason] = int(reasons.get(reason, 0)) + 1
			checks["reasons"] = reasons
	return {}


static func relocate_fixture(level: Node3D, desired: Vector3, radius: float, height: float) -> Dictionary:
	var direct := fixture_position(level, desired, radius, height)
	if not direct.is_empty():
		return direct
	var nearest: Dictionary = {}
	var best := INF
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var flat := Geometry2D.get_closest_point_to_segment(Vector2(desired.x, desired.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var distance := flat.distance_to(Vector2(desired.x, desired.z))
			if distance >= best:
				continue
			best = distance
			var forward := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var side := forward.cross(Vector3.UP)
			if (desired - Vector3(flat.x, desired.y, flat.y)).dot(side) < 0.0:
				side = -side
			nearest = {"center": Vector3(flat.x, desired.y, flat.y), "forward": forward, "side": side, "half": float(road.width) * 0.5}
	if nearest.is_empty():
		return {}
	return _curb_fixture(level, nearest.center, nearest.forward, nearest.side, nearest.half, radius, height)


static func build_street_network(level: Node3D, network: RefCounted = null) -> Dictionary:
	var root := Prim.group(level, 0, 0, 0, "NeighborhoodStreetNetwork")
	var mesh := source_lamp_mesh()
	var transforms: Array[Transform3D] = []
	var lamp_anchors: Array[Dictionary] = []
	var stop_transforms: Array[Transform3D] = []
	var sign_anchors: Dictionary = {}
	var sign_checks: Dictionary = {}
	var stop_lane_ids: Array[int] = []
	var reserved: Array[Vector3] = []
	var rejected := 0
	for road in level.level_data.get("roads", []):
		if str(road.get("name", "")) not in ["Old York Road", "Wyanoke Avenue"] or mesh == null:
			continue
		var points: Array = road.get("points", [])
		var travelled := 0.0
		var next_lamp := 24.0
		var ordinal := 0
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			while next_lamp <= travelled + length:
				var point := a.lerp(b, (next_lamp - travelled) / maxf(length, 0.001))
				var forward := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var side := forward.cross(Vector3.UP) * (1.0 if ordinal % 2 == 0 else -1.0)
				var anchor := _curb_fixture(level, point, forward, side, float(road.width) * 0.5, 0.28, 5.0, {}, reserved)
				if not anchor.is_empty():
					# The source cobra head reaches +Z: aim it back over the curb.
					var yaw := atan2(-side.x, -side.z)
					var pose := Transform3D(Basis(Vector3.UP, yaw), anchor.position)
					transforms.append(pose)
					reserved.append(anchor.position)
					lamp_anchors.append({"position": anchor.position, "head_position": pose * LAMP_LENS_LOCAL,
						"yaw": yaw, "radius": 0.28, "source": "network", "street": str(road.name), "sidewalk_checked": true})
					var body := _body(root)
					body.transform = pose
					_solid_pole(body, 0.16, 4.8, Vector3(0, 2.4, 0))
				else:
					rejected += 1
				next_lamp += 42.0
				ordinal += 1
			travelled += length
	if network != null:
		for lane in network.lanes:
			if not bool(lane.enabled) or not bool(lane.stop):
				continue
			var path: Array[Vector3] = lane.points
			var incoming := Vector3(path[-1].x - path[-2].x, 0, path[-1].z - path[-2].z).normalized()
			var right := incoming.cross(Vector3.UP)
			var center := path[-1] - right * float(lane.offset) + incoming * 2.35
			center += incoming * maxf(0.0, float(lane.get("legacy_stop_setback", 0.0)) - float(lane.get("stop_setback", 0.0)))
			var checks: Dictionary = {}
			# Keep the closer sign beside its waiting line; broad lamp relocation
			# could otherwise undo the requested reduction or cross the junction.
			var anchor := _curb_fixture(level, center, incoming, right, float(lane.width) * 0.5, 0.38, 2.8, checks, reserved, [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, -2.0, -3.0])
			sign_checks[str(lane.id)] = checks
			if anchor.is_empty():
				lane.stop = false
				rejected += 1
				continue
			var outward := -incoming
			var pose := Transform3D(Basis(Vector3.UP, atan2(outward.x, outward.z)), anchor.position)
			var prop := Prim.group(root, anchor.position.x, anchor.position.y, anchor.position.z, "ApproachStop_%d" % int(lane.id))
			prop.basis = pose.basis
			prop.set_meta("dressing_kind", "stop_sign")
			prop.set_meta("stop_lane_id", int(lane.id))
			prop.set_meta("placement", "Stop control on " + str(lane.street))
			_stop_sign(prop, false)
			stop_transforms.append(pose)
			reserved.append(anchor.position)
			stop_lane_ids.append(int(lane.id))
			sign_anchors[str(lane.id)] = {"position": anchor.position, "normal": outward, "incoming": incoming,
				"street": str(lane.street), "junction": str(lane.to), "lane": int(lane.id), "radius": 0.38, "sidewalk_checked": true,
				"legacy_setback": float(lane.get("legacy_stop_setback", 0.0)),
				"target_setback": float(lane.get("stop_setback", 0.0)),
				"actual_setback": (Vector3(lane.get("junction_point", center)) - Vector3(anchor.position)).dot(incoming)}
	var batches := 0
	for group in [{"mesh": mesh, "poses": transforms, "name": "OriginalStreetlampInstances"},
		{"mesh": _stop_sign_mesh(), "poses": stop_transforms, "name": "StopSignInstances"}]:
		if group.poses.is_empty() or group.mesh == null:
			continue
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = group.mesh
		instances.instance_count = group.poses.size()
		for i in group.poses.size():
			instances.set_instance_transform(i, group.poses[i])
		var batch := MultiMeshInstance3D.new()
		batch.name = group.name
		batch.multimesh = instances
		root.add_child(batch)
		batches += 1
	return {"street_lamps": transforms.size(), "lamp_anchors": lamp_anchors,
		"stop_signs": stop_transforms.size(), "stop_anchors": sign_anchors, "stop_lane_ids": stop_lane_ids,
		"stop_placement_checks": sign_checks, "fixture_batches": batches, "rejected_fixtures": rejected,
		"pavement": Surfaces.get_status()}


static func _stop_sign_mesh() -> ArrayMesh:
	if _source_stop:
		return _source_stop
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.045
	pole.height = 2.7
	pole.radial_segments = 10
	var parts := [[pole, Transform3D(Basis.IDENTITY, Vector3(0, 1.35, -0.10)), Color(IRON)]]
	# Solid galvanized back plate, with paint only on the approach-facing (+Z)
	# face. The rear-mounted pole never intersects the front lettering.
	var plate_rotation := Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI / 8)
	for layer in [[0.39, 0.05, 0.0, "#777f80"], [0.39, 0.004, 0.027, CREAM], [0.35, 0.004, 0.031, RED]]:
		var face := CylinderMesh.new()
		face.top_radius = float(layer[0])
		face.bottom_radius = face.top_radius
		face.height = float(layer[1])
		face.radial_segments = 8
		parts.append([face, Transform3D(plate_rotation, Vector3(0, 2.3, float(layer[2]))), Color(layer[3])])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var arrays: Array = part[0].get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pose: Transform3D = part[1]
		for index in arrays[Mesh.ARRAY_INDEX]:
			surface.set_color(part[2])
			surface.set_normal(pose.basis * normals[index])
			surface.add_vertex(pose * vertices[index])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	surface.set_material(material)
	_source_stop = surface.commit()
	return _source_stop


static func _stop_sign(parent: Node3D, visual := true) -> void:
	if visual:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _stop_sign_mesh()
		parent.add_child(mesh)
	var label := Prim.label("STOP", 0.55, 0.22, CREAM, "mono")
	label.position = Vector3(0, 2.3, 0.038)
	label.double_sided = false
	label.no_depth_test = false
	label.visibility_range_end = 55.0
	parent.add_child(label)
	var body := _body(parent)
	_solid_pole(body, 0.065, 2.7, Vector3(0, 1.35, -0.10))
	_solid_box(body, Vector3(0.78, 0.78, 0.06), Vector3(0, 2.3, 0))
