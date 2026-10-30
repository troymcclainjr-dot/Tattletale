extends Node3D
## Primitive residents share one colored mesh per pose and a draw batch per block.
## Deck footing is measured on imported building collision, never guessed from terrain.

const TARGET := 1200
const STREET_TARGET := 1040
const PORCH_TARGET := 200
const WALKER_TARGET := 128
const CELL := 45.0
const UPDATE_INTERVAL := 0.25
const ACTIVE_RADIUS := 32.0
var level: Node3D
var npcs: Node3D
var residents: Array[Dictionary] = []
var _batches: Dictionary = {}
var _clock := 0.0
var _accumulator := 0.0
var _near_updates := 0
var _meshes: Array[ArrayMesh] = []
var _shape: CapsuleShape3D
var _cells: Dictionary = {}
var _circle_groups: Array[Dictionary] = []
var _presence_radius := 160.0
var _animation_radius := ACTIVE_RADIUS
var _spacing_grid: Dictionary = {}
var _walkers: Array[int] = []
var _walk_accumulator := 0.0
var _walk_updates := 0
var _park_count := 0
var _porch_total := 0
var _seated_total := 0
var _coverage: Dictionary = {}
var _park_population: Dictionary = {}

func setup(owner_level: Node3D, owner_npcs: Node3D) -> void:
	level = owner_level
	npcs = owner_npcs
	name = "PorchAndStreetResidents"
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.24
	_shape.height = 1.65
	_meshes = [_person_mesh(false), _person_mesh(true)]
	var samples := _street_samples(5.0)
	# A round-robin traversal of geographic cells prevents the first few roads
	# consuming the population budget before the rest of the neighborhood exists.
	for sample in samples:
		if _porch_count() >= PORCH_TARGET:
			break
		for side in [-1.0, 1.0]:
			for offset in [3.2, 4.2, 5.2, 6.2, 7.2]:
				var at: Vector3 = sample.center + sample.across * side * (float(sample.half) + offset)
				var found := _deck_position(at)
				if not found.is_empty():
					_add_resident(found.position, atan2(-sample.across.x * side, -sample.across.z * side), "porch", residents.size() % 2 == 0)
					break
			if _porch_count() >= PORCH_TARGET:
				break
	# Moving residents get clear, short sidewalk corridors before groups fill in.
	for sample in samples:
		if _walkers.size() >= WALKER_TARGET:
			break
		for side in [-1.0, 1.0]:
			if _try_walker(sample, side):
				break
	for sample in samples:
		if residents.size() >= STREET_TARGET - 3:
			break
		for side in [-1.0, 1.0]:
			var center: Vector3 = sample.center + sample.across * side * (float(sample.half) + 1.3)
			_try_circle(center, sample.across, str(sample.street))
	# Narrow sidewalks can still accommodate a pair where a whole circle cannot fit.
	for sample in samples:
		if residents.size() >= STREET_TARGET:
			break
		for side in [-1.0, 1.0]:
			var desired: Vector3 = sample.center + sample.across * side * (float(sample.half) + 1.6)
			var found: Dictionary = npcs._safe_candidate(desired, 0.26)
			if found.is_empty() or not _spaced(found.position, 1.3):
				continue
			var tangent := Vector3(sample.across.z, 0, -sample.across.x)
			_add_resident(found.position, atan2(tangent.x, tangent.z), "social", false)
			var companion: Dictionary = npcs._safe_candidate(desired + tangent * 1.5, 0.26)
			if residents.size() < STREET_TARGET and not companion.is_empty() and _spaced(companion.position, 1.2):
				_add_resident(companion.position, atan2(-tangent.x, -tangent.z), "social", false)
			if residents.size() >= STREET_TARGET:
				break
	_populate_parks()
	_build_batches()

func _street_samples(spacing := 12.0) -> Array[Dictionary]:
	var cells: Dictionary = {}
	for road in level.level_data.get("roads", []):
		var points: Array = road.get("points", [])
		var travelled := 0.0
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var length := a.distance_to(b)
			var along := fposmod(-travelled, spacing)
			while along < length:
				var center := a.lerp(b, along / maxf(length, 0.001))
				var cell := Vector2i(floori(center.x / 70.0), floori(center.z / 70.0))
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append({"center": center, "across": Vector3(-tangent.z, 0, tangent.x), "half": float(road.get("width", 9.5)) * 0.5, "street": str(road.get("name", "Street"))})
				along += spacing
			travelled += length
	var samples: Array[Dictionary] = []
	var depth := 0
	var added := true
	while added:
		added = false
		for cell in cells:
			if depth < cells[cell].size():
				samples.append(cells[cell][depth])
				added = true
		depth += 1
	return samples

func _try_circle(center: Vector3, across: Vector3, street: String) -> bool:
	var candidates: Array[Vector3] = []
	var tangent := Vector3(across.z, 0, -across.x)
	var count := 3 if _circle_groups.size() % 2 == 0 else 4
	if residents.size() + count > STREET_TARGET:
		return false
	for i in count:
		var angle := TAU * float(i) / count
		var at := center + (across * sin(angle) + tangent * cos(angle)) * 0.7
		var found: Dictionary = npcs._safe_candidate(at, 0.26)
		if found.is_empty() or not _spaced(found.position, 1.2):
			return false
		candidates.append(found.position)
	var indices: Array[int] = []
	for at in candidates:
		var facing := center - at
		indices.append(residents.size())
		_add_resident(at, atan2(facing.x, facing.z), "circle", false)
	_circle_groups.append({"center": center, "indices": indices, "street": street})
	return true

func _spaced(at: Vector3, gap: float) -> bool:
	var grid := Vector2i(floori(at.x / 4.0), floori(at.z / 4.0))
	var reach := ceili((gap + 3.0) / 4.0)
	for x in range(grid.x - reach, grid.x + reach + 1):
		for z in range(grid.y - reach, grid.y + reach + 1):
			for index in _spacing_grid.get(Vector2i(x, z), []):
				var resident: Dictionary = residents[index]
				if resident.has("walk_a"):
					var closest := Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(resident.walk_a.x, resident.walk_a.z), Vector2(resident.walk_b.x, resident.walk_b.z))
					if closest.distance_to(Vector2(at.x, at.z)) < gap:
						return false
				elif at.distance_to(resident.position) < gap:
					return false
	for actor in npcs.actors.values():
		if at.distance_to(actor.global_position) < 1.2:
			return false
		for i in range(1, actor.patrol_points.size()):
			var a: Vector3 = actor.patrol_points[i - 1]
			var b: Vector3 = actor.patrol_points[i]
			if Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(Vector2(at.x, at.z)) < 0.95:
				return false
	return true

func _deck_position(at: Vector3) -> Dictionary:
	if not npcs.stair_approach_clear(at, 0.95):
		return {}
	if not _spaced(at, 2.2) or npcs._route_distance(at) < 1.0:
		return {}
	if level.vegetation != null and level.vegetation.has_method("is_trunk_clear") and not level.vegetation.is_trunk_clear(at, 0.4):
		return {}
	var ground: Dictionary = level.ground_at(at)
	if ground.is_empty():
		return {}
	var foot: Vector3 = ground.position
	# Start below the canopy. A hit must be an elevated building deck, not a roof.
	var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 1.9, foot + Vector3.UP * 0.18, 2)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.95:
		return {}
	var source: Node = hit.collider.get_parent()
	if not (str(source.name).begins_with("Row_") or str(source.name).begins_with("Bldg_")):
		return {}
	foot = hit.position + Vector3.UP * 0.015
	if foot.y - ground.position.y > 1.65 or not _spaced(foot, 2.2):
		return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.9)
	query.collision_mask = 2 | 4 | 8 | 16
	query.margin = 0.03
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {}
	# Four support rays reject narrow rail tops, stairs and deck edges.
	for offset in [Vector3(0.25, 0, 0), Vector3(-0.25, 0, 0), Vector3(0, 0, 0.25), Vector3(0, 0, -0.25)]:
		var support := PhysicsRayQueryParameters3D.create(foot + offset + Vector3.UP * 0.08, foot + offset - Vector3.UP * 0.12, 2)
		var floor_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(support)
		if floor_hit.is_empty() or floor_hit.normal.y < 0.95:
			return {}
	return {"position": foot}

func _add_resident(at: Vector3, yaw: float, activity: String, seated: bool) -> void:
	_porch_total += int(activity == "porch")
	_seated_total += int(seated)
	var body := StaticBody3D.new()
	body.name = "SeatedResident" if seated else "StandingResident"
	body.position = at
	body.collision_layer = 8
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	collision.position.y = 0.9
	body.add_child(collision)
	add_child(body)
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _cells.has(cell):
		_cells[cell] = {"cell": cell, "center": Vector3((cell.x + 0.5) * CELL, 0, (cell.y + 0.5) * CELL), "nodes": [], "bodies": [], "resident_indices": []}
	_cells[cell].bodies.append(body)
	_cells[cell].resident_indices.append(residents.size())
	residents.append({"position": at, "yaw": yaw, "activity": activity, "pose": 1 if seated else 0, "body": body, "cell": cell})
	var grid := Vector2i(floori(at.x / 4.0), floori(at.z / 4.0))
	if not _spacing_grid.has(grid):
		_spacing_grid[grid] = []
	_spacing_grid[grid].append(residents.size() - 1)

func _person_mesh(seated: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := -0.38 if seated else 0.0
	var parts := [
		[Vector3(0.43, 0.55, 0.26), Vector3(0, 1.03 + lift, 0), Color("ece2cf")],
		[Vector3(0.27, 0.29, 0.27), Vector3(0, 1.46 + lift, 0), Color("a87958")],
		[Vector3(0.29, 0.10, 0.28), Vector3(0, 1.61 + lift, 0), Color("302a28")],
		[Vector3(0.12, 0.5, 0.14), Vector3(-0.28, 1.0 + lift, 0.03), Color("a87958")],
		[Vector3(0.12, 0.5, 0.14), Vector3(0.28, 1.0 + lift, 0.03), Color("a87958")],
	]
	for x in [-0.12, 0.12]:
		parts.append([Vector3(0.16, 0.69 if not seated else 0.36, 0.18), Vector3(x, 0.395 if not seated else 0.22, 0.0 if not seated else 0.32), Color("354454")])
		parts.append([Vector3(0.18, 0.12, 0.3), Vector3(x, 0.06, 0.06 if not seated else 0.38), Color("302c2c")])
		if seated:
			parts.append([Vector3(0.16, 0.17, 0.42), Vector3(x, 0.44, 0.13), Color("354454")])
	if seated:
		parts.append([Vector3(0.53, 0.10, 0.52), Vector3(0, 0.36, 0), Color("77624a")])
		parts.append([Vector3(0.53, 0.59, 0.08), Vector3(0, 0.68, -0.22), Color("77624a")])
		for x in [-0.2, 0.2]:
			for z in [-0.18, 0.18]:
				parts.append([Vector3(0.07, 0.32, 0.07), Vector3(x, 0.16, z), Color("77624a")])
	for part in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			surface.set_color(part[2])
			surface.set_normal(normals[index])
			surface.add_vertex(vertices[index] + part[1])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	surface.set_material(material)
	return surface.commit()

func _build_batches() -> void:
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	var far_route := 0
	for i in residents.size():
		var resident: Dictionary = residents[i]
		var at: Vector3 = resident.position
		minimum = minimum.min(at)
		maximum = maximum.max(at)
		far_route += int(npcs._route_distance(at) > 100.0)
		var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
		var key := "%d_%d_%d" % [cell.x, cell.y, resident.pose]
		if not _batches.has(key):
			_batches[key] = {"indices": [], "origin": Vector3(cell.x * CELL, 0, cell.y * CELL), "pose": resident.pose}
		_batches[key].indices.append(i)
	_coverage = {"span_x": maximum.x - minimum.x, "span_z": maximum.z - minimum.z, "far_route": far_route}
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _meshes[int(batch.pose)]
		multi.instance_count = batch.indices.size()
		var mesh := MultiMeshInstance3D.new()
		mesh.multimesh = multi
		mesh.position = batch.origin
		mesh.visibility_range_end = _presence_radius
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		batch.node = mesh
		batch.multimesh = multi
		var cell: Vector2i = residents[int(batch.indices[0])].cell
		_cells[cell].nodes.append(mesh)
		for slot in batch.indices.size():
			var i: int = batch.indices[slot]
			residents[i].batch = key
			residents[i].slot = slot
			var colors := [Color("f0bc8b"), Color("91b7bc"), Color("bd9dbc"), Color("adbc87"), Color("d7b96e"), Color("c8ccd1")]
			multi.set_instance_color(slot, colors[i % colors.size()])
			multi.set_instance_transform(slot, Transform3D(Basis(Vector3.UP, residents[i].yaw), residents[i].position - batch.origin))

func tick(delta: float) -> void:
	_clock += delta
	_walk_accumulator += delta
	if _walk_accumulator >= 0.05:
		_tick_walkers(_walk_accumulator)
		_walk_accumulator = 0.0
	_accumulator += delta
	if _accumulator < UPDATE_INTERVAL:
		return
	_accumulator = 0.0
	_near_updates = 0
	for resident in residents:
		if resident.activity == "walking":
			continue
		var at: Vector3 = resident.position
		if at.distance_squared_to(level.player.global_position) > _animation_radius * _animation_radius:
			continue
		var batch: Dictionary = _batches[resident.batch]
		if not is_instance_valid(batch.node):
			continue
		var yaw: float = resident.yaw + sin(_clock * 0.65 + float(resident.slot)) * 0.045
		batch.node.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, yaw), at - batch.origin))
		_near_updates += 1

func _try_walker(sample: Dictionary, side: float) -> bool:
	var across: Vector3 = sample.across
	var tangent := Vector3(across.z, 0, -across.x)
	var center: Vector3 = sample.center + across * side * (float(sample.half) + 1.15)
	var path: Array[Vector3] = []
	for step in range(-6, 7):
		var found: Dictionary = npcs._safe_candidate(center + tangent * float(step) * 0.5, 0.25)
		if found.is_empty() or not _spaced(found.position, 1.1):
			return false
		if not path.is_empty() and absf(found.position.y - path[-1].y) > 0.18:
			return false
		path.append(found.position)
	var at: Vector3 = path[path.size() / 2]
	var index := residents.size()
	_add_resident(at, atan2(tangent.x, tangent.z), "walking", false)
	residents[index].walk_a = path[0]
	residents[index].walk_b = path[-1]
	residents[index].walk_path = path
	residents[index].walk_progress = 0.5
	residents[index].walk_direction = 1.0
	residents[index].walk_speed = 0.95 + float(index % 7) * 0.07
	_walkers.append(index)
	return true

func _tick_walkers(delta: float) -> void:
	_walk_updates = 0
	for index in _walkers:
		var resident: Dictionary = residents[index]
		var batch: Dictionary = _batches[resident.batch]
		if not is_instance_valid(batch.node) or resident.position.distance_squared_to(level.player.global_position) > 100.0 * 100.0:
			continue
		var path: Array = resident.walk_path
		var progress: float = resident.walk_progress + resident.walk_direction * resident.walk_speed * delta / 6.0
		if progress > 1.0 or progress < 0.0:
			resident.walk_direction *= -1.0
			progress = clampf(progress, 0.0, 1.0)
		var segment := minf(progress * (path.size() - 1), path.size() - 1.001)
		var next: Vector3 = path[int(segment)].lerp(path[int(segment) + 1], fposmod(segment, 1.0))
		# Yield to the player; short prevalidated corridors never enter the road.
		if Vector2(next.x - level.player.global_position.x, next.z - level.player.global_position.z).length() < 0.8:
			continue
		# Patrols and mission actors can enter a corridor after startup. Sweep the
		# real resident capsule before moving its body, then check the end pose.
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _shape
		query.transform = Transform3D(Basis.IDENTITY, resident.position + Vector3.UP * 0.9)
		query.motion = next - resident.position
		query.collision_mask = 2 | 8 | 16
		query.margin = 0.015
		if is_instance_valid(resident.body):
			query.exclude = [resident.body.get_rid()]
		var space := get_world_3d().direct_space_state
		var sweep := space.cast_motion(query)
		if not sweep.is_empty() and sweep[0] < 0.999:
			continue
		query.transform.origin = next + Vector3.UP * 0.9
		query.motion = Vector3.ZERO
		if not space.intersect_shape(query, 1).is_empty():
			continue
		resident.walk_progress = progress
		resident.position = next
		var heading: Vector3 = (resident.walk_b - resident.walk_a) * resident.walk_direction
		resident.yaw = lerp_angle(float(resident.yaw), atan2(heading.x, heading.z), 1.0 - exp(-delta * 8.0))
		if is_instance_valid(resident.body):
			resident.body.position = next
		var sway := Basis(Vector3.FORWARD, sin(_clock * 7.0 + index) * 0.025)
		batch.node.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, resident.yaw) * sway, next - batch.origin + Vector3.UP * absf(sin(_clock * 7.0 + index)) * 0.025))
		_walk_updates += 1

func _populate_parks() -> void:
	var parks: Array = level.level_data.get("parks", [])
	var candidates: Array[Dictionary] = []
	for park in parks:
		var polygon := PackedVector2Array()
		for vertex in park.get("polygon", []):
			var p: Vector3 = level.vector(vertex)
			polygon.append(Vector2(p.x, p.z))
		if polygon.size() < 3:
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		var holes: Array[PackedVector2Array] = []
		for ring in park.get("holes", []):
			var hole := PackedVector2Array()
			for vertex in ring:
				var p: Vector3 = level.vector(vertex)
				hole.append(Vector2(p.x, p.z))
			holes.append(hole)
		var points: Array[Vector3] = []
		for x in range(ceili(bounds.position.x + 2.0), floori(bounds.end.x - 2.0), 4):
			for z in range(ceili(bounds.position.y + 2.0), floori(bounds.end.y - 2.0), 4):
				var candidate := Vector2(x + sin(float(z) * 0.7) * 0.55, z + cos(float(x) * 0.9) * 0.55)
				if not Geometry2D.is_point_in_polygon(candidate, polygon):
					continue
				var inside_hole := false
				for hole in holes:
					inside_hole = inside_hole or Geometry2D.is_point_in_polygon(candidate, hole)
				if not inside_hole:
					points.append(Vector3(candidate.x, 0, candidate.y))
		candidates.append({"points": points, "name": park.get("name", "Park")})
	# Round-robin park allocation so the largest polygon cannot take every person.
	var depth := 0
	var remaining := true
	while remaining and residents.size() < TARGET:
		remaining = false
		for park in candidates:
			if depth >= park.points.size():
				continue
			remaining = true
			var at: Vector3 = park.points[depth]
			if not _spaced(at, 1.2) or npcs._route_distance(at) < 1.0:
				continue
			if not npcs.stair_approach_clear(at, 0.95):
				continue
			var street: Dictionary = npcs._street_info(at)
			if float(street.get("distance", INF)) < float(street.get("width", 9.5)) * 0.5 + 1.0:
				continue
			var hit: Dictionary = level.ground_at(at)
			if hit.is_empty() or hit.normal.y < 0.94:
				continue
			at = hit.position + Vector3.UP * 0.012
			if not _spaced(at, 1.2):
				continue
			if level.vegetation != null and not level.vegetation.is_trunk_clear(at, 0.7):
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _shape
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
			query.collision_mask = 2 | 8 | 16
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
			_add_resident(at, float(_park_count % 11) * 0.6, "park", _park_count % 3 == 0)
			residents[-1].park_name = str(park.name)
			_park_population[str(park.name)] = int(_park_population.get(str(park.name), 0)) + 1
			_park_count += 1
			if residents.size() >= TARGET:
				break
		depth += 1

func _porch_count() -> int:
	return _porch_total

func get_streaming_cells() -> Array:
	return _cells.values()

func set_presence(center: Vector3, near_radius := 40.0, far_radius := 160.0) -> void:
	_animation_radius = clampf(near_radius, 8.0, 80.0)
	_presence_radius = maxf(far_radius, _animation_radius + CELL)
	for cell in _cells.values():
		var distance := Vector2(center.x - cell.center.x, center.z - cell.center.z).length()
		if distance > _presence_radius + CELL * 1.5 and not cell.nodes.is_empty():
			for node in cell.nodes:
				node.queue_free()
			for body in cell.bodies:
				body.collision_layer = 0
				body.queue_free()
			for index in cell.resident_indices:
				residents[index].body = null
				_batches[residents[index].batch].node = null
			cell.nodes.clear()
			cell.bodies.clear()
		elif distance < _presence_radius + CELL and cell.nodes.is_empty():
			for index in cell.resident_indices:
				var resident: Dictionary = residents[index]
				var body := StaticBody3D.new()
				body.position = resident.position
				body.collision_layer = 8
				body.collision_mask = 0
				var collision := CollisionShape3D.new()
				collision.shape = _shape
				collision.position.y = 0.9
				body.add_child(collision)
				add_child(body)
				resident.body = body
				cell.bodies.append(body)
				var batch: Dictionary = _batches[resident.batch]
				if not is_instance_valid(batch.node):
					var mesh := MultiMeshInstance3D.new()
					mesh.multimesh = batch.multimesh
					mesh.position = batch.origin
					mesh.visibility_range_end = _presence_radius
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mesh)
					batch.node = mesh
					cell.nodes.append(mesh)

func get_status() -> Dictionary:
	var active_cells := 0
	for cell in _cells.values():
		active_cells += int(not cell.nodes.is_empty())
	return {"total": residents.size(), "porch": _porch_total, "social": residents.size() - _porch_total, "park": _park_count, "park_population": _park_population.duplicate(), "walkers": _walkers.size(), "walking_updates": _walk_updates, "seated": _seated_total, "circle_groups": _circle_groups.size(), "occupied_cells": _cells.size(), "active_cells": active_cells, "far_from_intro_route": _coverage.get("far_route", 0), "span_x": _coverage.get("span_x", 0), "span_z": _coverage.get("span_z", 0), "draw_batches": _batches.size(), "shared_meshes": _meshes.size(), "near_updates": _near_updates, "update_interval": UPDATE_INTERVAL, "name_labels": 0}
