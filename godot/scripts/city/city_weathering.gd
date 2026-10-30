extends RefCounted
## City-only surface finishes and compact batches of decorative, non-blocking litter.
const SURFACE := preload("res://assets/materials/city_surface.gdshader")
const Windows := preload("res://scripts/city/city_windows.gd")
const BRICK := ["6e3a30", "9a5a44", "a8644a", "8a4a3a"]
const CONCRETE := ["9a968c", "eeeae0", "8a8a90", "c8c4b8", "a8a49a", "b4a68a", "d8d0c0"]

static func apply_materials(city: Node3D) -> Dictionary:
	var shared := {}
	var count := 0
	var glass := Windows.glass_material()
	var glass_surfaces := 0
	for node in city.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		var name_: String = str(node.name)
		# Leaves, metal, glass and roofs retain their original clean material response.
		if name_.begins_with("Trees"):
			continue
		for index in node.mesh.get_surface_count():
			var current: Material = node.mesh.surface_get_material(index)
			if current == null:
				continue
			if current.resource_name == Windows.GLASS_NAME:
				node.set_surface_override_material(index, glass)
				glass_surfaces += 1
				continue
			var parts := current.resource_name.split("_")
			if parts.size() < 3 or parts[0] != "clay":
				continue
			var hex: String = parts[1]
			var kind := 4
			if hex in ["f4f0e6", "e2d4b4", "3f5a44", "5a3a28", "8a2a24"]:
				kind = 6
			elif hex in BRICK:
				kind = 1
			elif hex in CONCRETE:
				kind = 2
			elif hex == "3a3a40":
				kind = 3
			elif hex in ["6a8a3a", "7d7a70", "6e5a3c"]:
				kind = 5
			elif hex in ["3e3e44", "a8a8ae", "5a3a28", "6a5846", "5a5a62"]:
				continue
			var key: String = current.resource_name
			if not shared.has(key):
				var material := ShaderMaterial.new()
				material.shader = SURFACE
				material.resource_name = key
				material.set_shader_parameter("albedo", Color.html("#" + hex))
				material.set_shader_parameter("roughness", clampf(float(parts[2].substr(1)) / 100.0, 0.0, 1.0))
				material.set_shader_parameter("surface_kind", kind)
				shared[key] = material
			# Per-instance overrides keep the optimizer's persisted base mesh clean.
			node.set_surface_override_material(index, shared[key])
			count += 1
	return {"weathered_surfaces": count, "shared_finishes": shared.size(), "rough_glass_surfaces": glass_surfaces}

func build_litter(level: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "RoadsideLitter"
	level.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 429017
	var groups := {}
	var placed: Array[Vector3] = []
	var route: Array = level.level_data.get("route", {}).get("points", [])
	if route.size() < 3:
		return {"litter": 0, "draw_batches": 0}
	var kinds := [
		{"id": "paper", "size": Vector3(0.23, 0.009, 0.16), "color": "b8ad92"},
		{"id": "wrapper", "size": Vector3(0.13, 0.015, 0.09), "color": "a99453"},
		{"id": "cardboard", "size": Vector3(0.38, 0.025, 0.29), "color": "785438"},
		{"id": "can", "size": Vector3(0.065, 0.10, 0.065), "color": "506477"},
		{"id": "cup", "size": Vector3(0.075, 0.075, 0.075), "color": "b1aa91"},
	]
	for attempt in 650:
		if placed.size() >= 145:
			break
		var index := rng.randi_range(1, route.size() - 2)
		var at: Vector3 = level.vector(route[index])
		var tangent: Vector3 = (level.vector(route[index + 1]) - level.vector(route[index - 1])).normalized()
		tangent.y = 0
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0, tangent.x)
		at += side * rng.randf_range(-1.6, 1.6) + tangent * rng.randf_range(-2.2, 2.2)
		if not _clear_spot(level, at, placed):
			continue
		var hit: Dictionary = level.ground_at(at)
		if hit.is_empty() or hit.normal.y < 0.92:
			continue
		at.y = hit.position.y + 0.006
		var kind: Dictionary = kinds[rng.randi_range(0, kinds.size() - 1)]
		var dimensions: Vector3 = kind.size
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI))
		var position_: Vector3 = at + Vector3.UP * (dimensions.y * 0.5)
		var pose := Transform3D(basis, position_)
		var cell := "%d_%d" % [floori(at.x / 25), floori(at.z / 25)]
		var key: String = cell + "_" + str(kind.id)
		if not groups.has(key):
			groups[key] = {"kind": kind, "poses": []}
		groups[key].poses.append(pose)
		# Decorative litter deliberately has no physics body: paper and cans must
		# never catch the player's capsule, walkers, vehicles or chase camera.
		placed.append(at)
	for key in groups:
		var group: Dictionary = groups[key]
		var kind: Dictionary = group.kind
		var mesh: Mesh
		if str(kind.id) in ["can", "cup"]:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(kind.size.x) * 0.45
			cylinder.bottom_radius = float(kind.size.x) * 0.5
			cylinder.height = kind.size.y
			cylinder.radial_segments = 7
			mesh = cylinder
		else:
			var box := BoxMesh.new()
			box.size = kind.size
			mesh = box
		mesh.surface_set_material(0, ClayLib.clay("#" + str(kind.color), 0.93))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = group.poses.size()
		var first_pose: Transform3D = group.poses[0]
		var batch_origin := Vector3(floorf(first_pose.origin.x / 25.0) * 25.0 + 12.5, first_pose.origin.y, floorf(first_pose.origin.z / 25.0) * 25.0 + 12.5)
		for i in group.poses.size():
			var local_pose: Transform3D = group.poses[i]
			local_pose.origin -= batch_origin
			multimesh.set_instance_transform(i, local_pose)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Litter_" + str(key)
		instance.multimesh = multimesh
		instance.position = batch_origin
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 90.0
		root.add_child(instance)
	return {"litter": placed.size(), "draw_batches": groups.size(), "collision_groups": 0}

func _clear_spot(level: Node3D, point: Vector3, placed: Array[Vector3]) -> bool:
	var street: Dictionary = level.npcs._street_info(point)
	var half: float = float(street.get("width", 9.5)) * 0.5
	var distance: float = float(street.get("distance", 0.0))
	if distance < half + 0.15 or distance > half + 2.5:
		return false
	if level.npcs._route_distance(point) < 0.88:
		return false
	for other in placed:
		if Vector2(point.x - other.x, point.z - other.z).length() < 0.38:
			return false
	for actor in level.npcs.actors.values():
		if Vector2(point.x - actor.position.x, point.z - actor.position.z).length() < 2.0:
			return false
		for destination in actor.patrol_points:
			var near := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(actor.position.x, actor.position.z), Vector2(destination.x, destination.z))
			if near.distance_to(Vector2(point.x, point.z)) < 0.7:
				return false
	var ground: Dictionary = level.ground_at(point)
	if ground.is_empty():
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = Vector3(point.x, ground.position.y + 0.3, point.z)
	query.collision_mask = 2 | 4 | 8 | 16
	return level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
