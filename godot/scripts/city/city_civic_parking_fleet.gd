extends RefCounted
## Static civic fleet. Call after lot/foundation physics is ready; world-space
## specs use +Z vehicle forward. Existing vehicle meshes and compound hulls recur.
const Models = preload("res://scripts/city/city_car_models.gd")
const Collision = preload("res://scripts/city/city_car_collision.gd")
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")
const VISUAL_CELL := 48.0


static func default_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	# Uneven occupancy leaves four of the hospital's ten marked stalls free.
	for bank in 2:
		var slots: Array = [0, 2, 4] if bank == 0 else [0, 1, 3]
		for slot in slots:
			var index := specs.size()
			specs.append({"id": "HospitalVisitor_%02d" % index, "site": "hospital",
				"kind": Models.KINDS[index % Models.KINDS.size()], "paint": index,
				"position": Vector3(410.5 if bank == 0 else 421.5, -7.95, -124.65 + float(slot) * 2.7),
				"yaw": PI / 2.0 if bank == 0 else -PI / 2.0})
	# One transport ambulance centered under the separate canopy, door route free.
	specs.append({"id": "HospitalAmbulance", "site": "hospital", "kind": "ambulance",
		"position": Vector3(410, -7.95, -141), "yaw": -PI / 2.0})
	for bank in 2:
		var slots: Array = [0, 1, 3, 4, 6] if bank == 0 else [0, 2, 3, 5]
		for slot in slots:
			specs.append({"id": "PrecinctCruiser_%d_%d" % [bank, int(slot)], "site": "police", "kind": "police",
				"position": Vector3(-34.7 + float(slot) * 2.8, 1.15, -67.2 if bank == 0 else -54.8),
				"yaw": 0.0 if bank == 0 else PI})
	return specs


static func build(level: Node3D, specs: Array[Dictionary] = []) -> Node3D:
	var root := Node3D.new()
	root.name = "CivicParkingFleet"
	var requested: Array[Dictionary] = default_specs() if specs.is_empty() else specs
	var counts: Dictionary = {}
	var rejected: Array[Dictionary] = []
	var poses: Array[Dictionary] = []
	for spec in requested:
		var kind := str(spec.get("kind", "compact"))
		var hull_kind := "minivan" if kind == "ambulance" else kind
		if hull_kind != "police" and not Models.KINDS.has(hull_kind):
			rejected.append({"id": spec.get("id", "unknown"), "reason": "unknown_model"})
			continue
		var grounded := _ground_pose(level, spec)
		if grounded.is_empty():
			rejected.append({"id": spec.id, "reason": "ground"})
			continue
		var pose: Transform3D = grounded.pose
		if not _clear(level, pose, hull_kind):
			rejected.append({"id": spec.id, "reason": "occupied"})
			continue
		var overlap := false
		for existing in poses:
			# Exact convex intersection below covers scene occupants. Planned fleet
			# nodes are not in the tree yet: compare oriented vehicle rectangles.
			if _overlap(pose, hull_kind, existing.pose, str(existing.kind)):
				overlap = true
				break
		if overlap:
			rejected.append({"id": spec.id, "reason": "fleet_overlap"})
			continue
		var body := StaticBody3D.new()
		body.name = str(spec.id)
		body.collision_layer = 2 | 16
		body.collision_mask = 0
		body.transform = pose
		Collision.attach(body, hull_kind)
		var model: Node3D
		if kind == "police":
			model = Assets.model("cop_car")
			model.rotation.y = -PI / 2.0
		else:
			model = Models.make(hull_kind, int(spec.get("paint", 1)))
		if kind == "ambulance":
			_ambulance_livery(model, body)
		body.add_child(model)
		body.set_meta("civic_vehicle", true)
		body.set_meta("vehicle_kind", kind)
		body.set_meta("site", str(spec.get("site", "")))
		body.set_meta("ground_checked", true)
		body.set_meta("precise_vehicle_hulls", true)
		root.add_child(body)
		_visibility(model)
		counts[kind] = int(counts.get(kind, 0)) + 1
		poses.append({"pose": pose, "kind": hull_kind})
	var visual_status := _batch_visuals(root)
	root.set_meta("fleet_status", {"requested": requested.size(), "total": poses.size(), "kinds": counts, "rejected": rejected, "visuals": visual_status})
	return root


static func _ground_pose(level: Node3D, spec: Dictionary) -> Dictionary:
	var value = spec.position
	var at: Vector3 = value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))
	var yaw := float(spec.get("yaw", 0.0))
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(forward.z, 0, -forward.x)
	var heights: Array[float] = []
	for offset in [Vector3.ZERO, forward * 1.4, -forward * 1.4, right * 0.78, -right * 0.78]:
		# Layer 2 includes the hospital canopy's raised pavement, but the ray
		# begins below its roof. Layer 1 covers the graded parking surfaces.
		var ray := PhysicsRayQueryParameters3D.create(at + offset + Vector3.UP * 1.2, at + offset - Vector3.UP * 3.0, 1 | 2)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.92:
			return {}
		heights.append(float(hit.position.y))
	forward.y = (heights[1] - heights[2]) / 2.8
	right.y = (heights[3] - heights[4]) / 1.56
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	at.y = (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025
	return {"pose": Transform3D(Basis(right, up, forward), at)}


static func _clear(level: Node3D, pose: Transform3D, kind: String) -> bool:
	for part in Collision.parts(kind):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = part.shape
		query.transform = pose
		query.collision_mask = 2 | 16
		query.margin = 0.02
		if not level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


static func _rectangle(pose: Transform3D, kind: String) -> PackedVector2Array:
	var size := Vector3(2.07, 2.06, 4.46) if kind == "police" else Models.dimensions(kind) + Vector3(0.09, 0, 0.06)
	var polygon := PackedVector2Array()
	for corner in [Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(1,0,1),Vector3(-1,0,1)]:
		var point: Vector3 = pose * (Vector3(corner) * size * 0.5)
		polygon.append(Vector2(point.x,point.z))
	return polygon


static func _overlap(a: Transform3D, a_kind: String, b: Transform3D, b_kind: String) -> bool:
	return not Geometry2D.intersect_polygons(_rectangle(a,a_kind), _rectangle(b,b_kind)).is_empty()


static func _visibility(node: Node) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = 210.0
	for child in node.get_children():
		_visibility(child)


static func _ambulance_livery(model: Node3D, body: StaticBody3D) -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("e2e0d4")
	white.roughness = 0.62
	(model.get_node("Body") as MeshInstance3D).set_surface_override_material(0, white)
	var k := Kit.new("AmbulanceMarkings")
	# Vehicle vinyl/lamp housings do not use the architectural peeling-wood
	# finish. Kind 0 keeps the same two batched surfaces without fleck noise.
	k.material("red", Color("9b302d"), 0, 0.62)
	k.material("metal", Color("4e5558"), 0, 0.62)
	# Transport van, with restrained reflective belt and separate lamp pods.
	# All additions reuse the original two marking materials for fleet batching.
	for side in [-1.0, 1.0]:
		# Flat vinyl skins on the planar door panels, ending before both wheel
		# openings. No thickness, wraparound frame or band bridging an arch.
		var x: float = float(side) * 0.982
		_ambulance_skin(k, [Vector3(x,0.64,-0.94), Vector3(x,0.80,-0.94), Vector3(x,0.80,0.94), Vector3(x,0.64,0.94)], "red", Vector3(float(side),0,0))
		_ambulance_skin(k, [Vector3(x,0.607,-0.94), Vector3(x,0.623,-0.94), Vector3(x,0.623,0.94), Vector3(x,0.607,0.94)], "metal", Vector3(float(side),0,0))
		k.label("AMBULANCE", Vector3(side * 0.994, 1.05, -0.3), 34, 0.009, Color("173e58"), side * PI / 2.0)
	_ambulance_skin(k, [Vector3(-0.58,0.64,-2.292), Vector3(-0.58,0.80,-2.292), Vector3(0.58,0.80,-2.292), Vector3(0.58,0.64,-2.292)], "red", Vector3(0,0,-1))
	k.box(Vector3(0,1.72,-0.3),Vector3(1.23,0.06,0.3),"metal")
	for side in [-1.0, 1.0]:
		k.box(Vector3(side * 0.45,1.82,-0.3),Vector3(0.35,0.18,0.35),"red")
		k.box(Vector3(side * 0.45,1.81,-0.479),Vector3(0.27,0.028,0.006),"metal")
		k.box(Vector3(side * 0.45,1.81,-0.121),Vector3(0.27,0.028,0.006),"metal")
		# Small liftgate details stay on the solid lower rear face.
		k.box(Vector3(side * 0.50,0.85,-2.291),Vector3(0.10,0.024,0.006),"metal")
	k.box(Vector3(0,1.79,-0.3),Vector3(0.50,0.11,0.27),"metal")
	# Fleet merger owns final material grouping and does not carry CUSTOM0.
	# Feed it the original finishes; preserve ambulance stripe/light colors.
	model.add_child(k.finish(false))
	var light_shape := BoxShape3D.new()
	light_shape.size = Vector3(1.25,0.24,0.35)
	var light_collision := CollisionShape3D.new()
	light_collision.name = "AmbulanceLightBar"
	light_collision.shape = light_shape
	light_collision.position = Vector3(0,1.79,-0.3)
	body.add_child(light_collision)

static func _ambulance_skin(k, points: Array, finish: String, outward: Vector3) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var d: Vector3 = points[3]
	# Civic kit triangles are clockwise viewed from outside.
	if (c - a).cross(b - a).dot(outward) > 0.0:
		k.triangle(a, b, c, finish)
		k.triangle(a, c, d, finish)
	else:
		k.triangle(a, c, b, finish)
		k.triangle(a, d, c, finish)

## Immutable fleet geometry is merged once, before the root enters the tree.
## Every named vehicle body, collider and local model hierarchy remains intact.
static func _batch_visuals(root: Node3D) -> Dictionary:
	var began := Time.get_ticks_msec()
	var chunks: Dictionary = {}
	var status := {"source_meshes": 0, "source_surfaces": 0, "batch_meshes": 0,
		"batch_surfaces": 0, "triangles": 0, "labels": 0, "unbatched_surfaces": 0}
	for body in root.get_children():
		if body is StaticBody3D and bool(body.get_meta("civic_vehicle", false)):
			_collect_static_visuals(body, body.transform, body, chunks, status)
	for chunk in chunks.values():
		var importer := ImporterMesh.new()
		for group in chunk.materials.values():
			var builder: SurfaceTool = group.builder
			builder.index()
			var arrays := builder.commit_to_arrays()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, group.material)
		# Preserve full-detail vertices/materials while restoring the native mesh
		# LOD benefit that the individually imported vehicle parts previously had.
		importer.generate_lods(45.0, 0.0, [])
		var mesh := importer.get_mesh()
		var instance := MeshInstance3D.new()
		instance.name = "FleetVisualBatch_%d" % int(status.batch_meshes)
		instance.mesh = mesh
		instance.layers = int(chunk.layers)
		instance.cast_shadow = int(chunk.shadow)
		instance.visibility_range_end = 210.0
		instance.set_meta("static_fleet_batch", true)
		# Keep direct root children exclusively the named vehicle bodies, as the
		# collision/identity fixtures require. No global transforms exist yet.
		var owner_body: StaticBody3D = chunk.owner_body
		owner_body.add_child(instance)
		instance.transform = owner_body.transform.affine_inverse() * Transform3D(Basis.IDENTITY, chunk.origin)
		status.batch_meshes += 1
		status.batch_surfaces += mesh.get_surface_count()
	status.setup_ms = Time.get_ticks_msec() - began
	status.surface_reduction = int(status.source_surfaces) - int(status.batch_surfaces) - int(status.unbatched_surfaces)
	return status

static func _collect_static_visuals(node: Node3D, pose: Transform3D, owner_body: StaticBody3D, chunks: Dictionary, status: Dictionary) -> void:
	if not node.visible:
		return
	if node is Label3D:
		status.labels += 1
	if node is MeshInstance3D and node.mesh != null:
		var source := node as MeshInstance3D
		status.source_meshes += 1
		status.source_surfaces += source.mesh.get_surface_count()
		# Unsupported deforming or overlaid meshes retain their original renderer.
		# Present fleet models are static, material-only triangle geometry.
		if source.skin != null or source.material_overlay != null or (source.mesh is ArrayMesh and source.mesh.get_blend_shape_count() > 0):
			status.unbatched_surfaces += source.mesh.get_surface_count()
		else:
			var center: Vector3 = owner_body.position
			var cell := Vector2i(floori(center.x / VISUAL_CELL), floori(center.z / VISUAL_CELL))
			var key := "%d_%d_%d_%d" % [cell.x, cell.y, source.layers, source.cast_shadow]
			if not chunks.has(key):
				chunks[key] = {"origin": Vector3((cell.x + 0.5) * VISUAL_CELL, 0, (cell.y + 0.5) * VISUAL_CELL),
					"layers": source.layers, "shadow": source.cast_shadow, "owner_body": owner_body, "materials": {}}
			var chunk: Dictionary = chunks[key]
			var relative := pose
			relative.origin -= Vector3(chunk.origin)
			for surface in source.mesh.get_surface_count():
				var material := source.get_active_material(surface)
				var material_id := material.get_instance_id() if material != null else 0
				if not chunk.materials.has(material_id):
					var builder := SurfaceTool.new()
					builder.begin(Mesh.PRIMITIVE_TRIANGLES)
					chunk.materials[material_id] = {"builder": builder, "material": material}
				status.triangles += _append_static_surface(chunk.materials[material_id].builder, source.mesh, surface, relative)
			# Clearing only the renderer's resource preserves children (including
			# ambulance labels), paths, pivots and per-vehicle ownership metadata.
			source.mesh = null
	for child in node.get_children():
		if child is Node3D:
			_collect_static_visuals(child, pose * child.transform, owner_body, chunks, status)

static func _append_static_surface(builder: SurfaceTool, mesh: Mesh, surface: int, pose: Transform3D) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var normal_basis := pose.basis.inverse().transposed()
	# Emit a consistent vertex layout so identical materials from different source
	# parts merge without losing their original UVs, vertex colors or tangents.
	for offset in count:
		var index := indices[offset] if not indices.is_empty() else offset
		builder.set_normal((normal_basis * normals[index]).normalized() if not normals.is_empty() else Vector3.UP)
		builder.set_uv(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
		builder.set_uv2(uv2s[index] if not uv2s.is_empty() else Vector2.ZERO)
		builder.set_color(colors[index] if not colors.is_empty() else Color.WHITE)
		var tangent := pose.basis * Vector3.RIGHT
		var handedness := 1.0
		if not tangents.is_empty():
			tangent = pose.basis * Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
			handedness = tangents[index * 4 + 3]
		tangent = tangent.normalized()
		builder.set_tangent(Plane(tangent.x, tangent.y, tangent.z, handedness))
		builder.add_vertex(pose * vertices[index])
	return count / 3
