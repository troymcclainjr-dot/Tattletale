extends Node3D
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const IdleLife := preload("res://scripts/city/city_crowd_idle_life.gd")
## Modular residents share one detailed mesh per pose and a draw batch per block.
## Deck footing is measured on imported building collision, never guessed from terrain.

const RECIPE_PATH := "res://assets/data/pen_lucy_crowd_recipe.json"
const TARGET := 1200
const STREET_TARGET := 1040
const PORCH_TARGET := 200
const WALKER_TARGET := 128
const CELL := 45.0
const UPDATE_INTERVAL := 0.25
const IDLE_GROUPS := 15
const IDLE_STEP := UPDATE_INTERVAL / IDLE_GROUPS
const IDLE_MAX_CATCHUP := 4
static var use_staggered_idle := true
static var profile_idle := false
static var profile_totals: Dictionary = {}
const ACTIVE_RADIUS := 32.0
const WALK_INTERVAL := 0.05
const WALK_GROUPS := 3
const WALK_TURN_RATE := 3.6
const WALK_ALIGNMENT := 0.01
## Gunfire panic is event driven: a shot scans only the cells around it, then
## a bounded set of movers runs on alternating physics frames until safe.
const PANIC_TOTAL := 160
const PANIC_MOVERS := 48
const PANIC_GROUPS := 2
const PANIC_SPEED := 2.7
const PANIC_TURN_RATE := 7.5
const PANIC_FLEE_DISTANCE := 8.0
const PANIC_SAFE := 12.0
const PANIC_MIN_TIME := 4.0
const PANIC_RETURN_LIMIT := 14.0
const NEAR_MISS := 1.4
var level: Node3D
var npcs: Node3D
var residents: Array[Dictionary] = []
var _batches: Dictionary = {}
var _clock := 0.0
var _accumulator := 0.0
var _idle_next := IDLE_STEP
var _idle_group := 0
var _idle_mode := true
var _idle_skipped_steps := 0
var _near_updates := 0
var _meshes: Array[ArrayMesh] = []
var _shape: CapsuleShape3D
var _cells: Dictionary = {}
var _circle_groups: Array[Dictionary] = []
var _social_groups: Dictionary = {}
var _social_membership: Dictionary = {}
var _presence_radius := 160.0
var _animation_radius := ACTIVE_RADIUS
var _spacing_grid: Dictionary = {}
var _walkers: Array[int] = []
var _walk_next_group: Array[float] = [WALK_INTERVAL / 3.0, WALK_INTERVAL * 2.0 / 3.0, WALK_INTERVAL]
var _walk_query: PhysicsShapeQueryParameters3D
var _walk_query_exclude: Array[RID] = []
var _walk_updates := 0
var _cell_activations := 0
var _park_count := 0
var _porch_total := 0
var _seated_total := 0
var _coverage: Dictionary = {}
var _park_population: Dictionary = {}
var _panic: Dictionary = {}
var _panic_movers := 0
var _panic_phase := 0
var _panic_accumulator := 0.0
var _panic_query: PhysicsShapeQueryParameters3D
var _panic_exclude: Array[RID] = []
var _panic_ray := PhysicsRayQueryParameters3D.new()
var _panic_updates := 0
var _panic_casts := 0
var _panic_started := 0
var _panic_cowered := 0
var _panic_restored := 0
var _panic_replans := 0
var _threat_scanned := 0
var _threat_cells := 0
var _dead_count := 0
# Settled residents outside their original batch cell. At most one entry per
# resident; shot/presence refreshes inspect these, never the per-frame idle loop.
var _displaced: Dictionary = {}
var _identity_source := "legacy_generation"
var _loading_recipe := false
var _recipe_reservations: Array[Vector3] = []
var _identity_relocated := 0
var _identity_failures: Array[int] = []
var _park_plan: Dictionary = {}
var _social_reserved: Array[Vector3] = []
var _neighborhood_groups: Array[Dictionary] = []
var _distribution_counts: Dictionary = {}
var _distribution_fallbacks := 0
var _population_parks: Array[Dictionary] = []
var _planned_park_counts: Dictionary = {}
var _physical_park_population: Dictionary = {}
var _destination_population: Dictionary = {}
var _idle_life := IdleLife.new()

func setup(owner_level: Node3D, owner_npcs: Node3D) -> void:
	level = owner_level
	npcs = owner_npcs
	name = "PorchAndStreetResidents"
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.24
	_shape.height = 1.65
	_meshes = [_person_mesh(false), _person_mesh(true), _person_mesh(true, false)]
	var exporting := "--export-crowd-recipe" in OS.get_cmdline_user_args()
	if exporting and level.get("civic_district") != null:
		_identity_source = "invalid_export"
		push_error("Crowd recipe export requires --no-civic-district")
		return
	if not exporting:
		if FileAccess.file_exists(RECIPE_PATH) and _instantiate_recipe():
			_index_social_groups()
			_build_batches()
		else:
			# Never silently regenerate ordinals against a changed world and attach
			# a player's saved death IDs to different neighbors.
			_identity_source = "canonical_recipe_unavailable"
			push_error("Canonical crowd recipe unavailable; refusing identity reassignment")
		return
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
	_index_social_groups()
	if exporting:
		_export_recipe()
	_build_batches()

func _index_social_groups() -> void:
	_social_groups.clear()
	_social_membership.clear()
	for group in _circle_groups:
		var indices: Array[int] = []
		for value in group.indices:
			var index := int(value)
			if index >= 0 and index < residents.size():
				indices.append(index)
		indices.sort()
		if indices.is_empty():
			continue
		# Stable birth ordinals, independent of a group's current center/order.
		var identity := "social_crowd_%d" % indices[0]
		_social_groups[identity] = indices
		for index in indices:
			_social_membership[index] = identity
			residents[index].social_group_id = identity

func social_group_id(index: int) -> String:
	return str(_social_membership.get(index, ""))

func social_group_members(index: int, limit := 9) -> Array[int]:
	var result: Array[int] = []
	var identity := social_group_id(index)
	if identity.is_empty():
		return result
	for value in _social_groups.get(identity, []):
		if result.size() >= clampi(limit, 0, 16):
			break
		result.append(int(value))
	return result

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
	if CivicClearance.blocked(level, at, 0.4):
		return {}
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
	# Never erase/drop an index after group/walker references have been assigned.
	if not _loading_recipe and CivicClearance.blocked(level, at, 0.35):
		var relocated := CivicClearance.sidewalk_relocation(level, npcs, at, 0.30)
		if not relocated.is_empty():
			at = relocated.position
			activity = "social"
			seated = false
	_porch_total += int(activity == "porch")
	_seated_total += int(seated)
	var body := StaticBody3D.new()
	body.set_meta("city_crowd_index", residents.size())
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

func _person_mesh(seated: bool, include_chair := true) -> ArrayMesh:
	return ModularPeople.crowd_mesh(seated, include_chair)

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
		multi.use_colors = false
		multi.use_custom_data = true
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
		if _cells[cell].nodes.is_empty():
			_cell_activations += 1
		_cells[cell].nodes.append(mesh)
		for slot in batch.indices.size():
			var i: int = batch.indices[slot]
			residents[i].batch = key
			residents[i].slot = slot
			var identity := str(residents[i].get("stable_id", "crowd_%d" % i))
			var appearance := Appearance.profile(identity)
			residents[i].appearance = appearance
			multi.set_instance_custom_data(slot, Color(float(appearance.roster_index), 0, 0, 0))
			multi.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO) if residents[i].get("identity_unplaced", false) else Basis(Vector3.UP, residents[i].yaw), residents[i].position - batch.origin))

func tick(delta: float) -> void:
	_clock += delta
	# One shared shader clock pauses with simulation; no per-person material work.
	ModularPeople.material().set_shader_parameter("crowd_clock", _clock)
	_idle_life.tick(self)
	_walk_updates = 0
	# At 60 physics Hz the three phases land on successive frames. Each
	# resident still receives a 0.05 s step, including after a long frame.
	for group in WALK_GROUPS:
		while _clock + 0.000001 >= _walk_next_group[group]:
			_tick_walkers(WALK_INTERVAL, group)
			_walk_next_group[group] += WALK_INTERVAL
	if not _panic.is_empty():
		_tick_panic(delta)
	_tick_idle(delta)

func _tick_idle(delta: float) -> void:
	_near_updates = 0
	if _idle_mode != use_staggered_idle:
		# Benchmark mode switches start a fresh cadence; never replay stale work.
		_idle_mode = use_staggered_idle
		_accumulator = 0.0
		_idle_next = _clock + IDLE_STEP
	if not use_staggered_idle:
		_accumulator += delta
		if _accumulator < UPDATE_INTERVAL:
			return
		_accumulator = 0.0
		_idle_pass(0, 1)
		return
	var due := maxi(0, floori((_clock + 0.000001 - _idle_next) / IDLE_STEP) + 1)
	if due == 0:
		return
	# Idle poses depend on absolute elapsed time, not integration. Skip obsolete
	# deadlines after a stall, but advance cohorts only for work actually done.
	# Round-robin fairness prevents sustained slow ticks starving the same people;
	# no unbounded backlog or simulation/identity state changes are introduced.
	if due > IDLE_MAX_CATCHUP:
		var skipped := due - IDLE_MAX_CATCHUP
		_idle_skipped_steps += skipped
		_idle_next += skipped * IDLE_STEP
		due = IDLE_MAX_CATCHUP
	for step in due:
		_idle_pass(_idle_group, IDLE_GROUPS)
		_idle_group = (_idle_group + 1) % IDLE_GROUPS
		_idle_next += IDLE_STEP

func _idle_pass(first: int, stride: int) -> void:
	var began: int = Time.get_ticks_usec() if profile_idle else 0
	var player_position: Vector3 = level.player.global_position
	var radius_squared := _animation_radius * _animation_radius
	var updated := 0
	var index := first
	# Strided fixed cohorts avoid allocating lists or scanning the other fourteen
	# groups. Canonical resident slots are never reordered or reassigned.
	while index < residents.size():
		var resident: Dictionary = residents[index]
		index += stride
		if resident.get("identity_unplaced", false) or resident.activity == "walking" or resident.get("combat_controlled", false) or resident.get("panic", false) or resident.get("dead", false) or resident.get("police_custody", false) or resident.get("bicycle_avoiding", false) or resident.has("bicycle_rejoin"):
			_set_idle_visual(index - stride, 0)
			continue
		if resident.get("idle_pacing", false):
			continue
		var at: Vector3 = resident.position
		if at.distance_squared_to(player_position) > radius_squared:
			continue
		var batch: Dictionary = _batches[resident.batch]
		if not is_instance_valid(batch.node):
			continue
		var yaw: float = resident.yaw + sin(_clock * 0.65 + float(resident.slot)) * 0.045
		batch.node.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, yaw), at - batch.origin))
		if IdleLife.owns_idle(resident):
			_set_idle_visual(index - stride, IdleLife.activity_for(index - stride))
			_idle_life.consider(self, index - stride)
		updated += 1
	_near_updates += updated
	if profile_idle:
		var scanned := maxi(0, ceili(float(residents.size() - first) / stride))
		profile_totals["idle_usec"] = int(profile_totals.get("idle_usec", 0)) + Time.get_ticks_usec() - began
		profile_totals["idle_scanned"] = int(profile_totals.get("idle_scanned", 0)) + scanned
		profile_totals["idle_updated"] = int(profile_totals.get("idle_updated", 0)) + updated
		profile_totals["idle_calls"] = int(profile_totals.get("idle_calls", 0)) + 1

func _set_idle_visual(index: int, mode: int) -> void:
	var resident: Dictionary = residents[index]
	if int(resident.get("idle_visual_mode", 0)) == mode or not resident.has("batch"):
		return
	resident.idle_visual_mode = mode
	var batch: Dictionary = _batches[resident.batch]
	var multi = batch.get("multimesh")
	if multi == null or not multi.has_method("set_instance_custom_data"):
		return
	var appearance: Dictionary = resident.get("appearance", {})
	multi.set_instance_custom_data(int(resident.slot), Color(float(appearance.get("roster_index", 0)), float(mode), IdleLife.phase_for(index), 0))

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

func _tick_walkers(delta: float, group := -1) -> void:
	if _walk_query == null:
		_walk_query = PhysicsShapeQueryParameters3D.new()
		_walk_query.collision_mask = 2 | 8 | 16
		_walk_query.margin = 0.015
	var space := get_world_3d().direct_space_state
	for index in _walkers:
		if group >= 0 and index % WALK_GROUPS != group:
			continue
		var resident: Dictionary = residents[index]
		if resident.get("combat_controlled", false) or resident.get("panic", false) or resident.get("bicycle_avoiding", false):
			continue
		var batch: Dictionary = _batches[resident.batch]
		if not is_instance_valid(batch.node) or resident.position.distance_squared_to(level.player.global_position) > 100.0 * 100.0:
			continue
		var path: Array = resident.walk_path
		# Finish the current leg before reversing. The previous update reversed
		# heading while still moving toward the endpoint, then slid backwards
		# on the return leg while its yaw caught up.
		if (resident.walk_direction > 0.0 and resident.walk_progress >= 1.0) or (resident.walk_direction < 0.0 and resident.walk_progress <= 0.0):
			resident.walk_direction *= -1.0
		var progress: float = clampf(resident.walk_progress + resident.walk_direction * resident.walk_speed * delta / 6.0, 0.0, 1.0)
		var segment: float = progress * (path.size() - 1)
		var segment_index := mini(int(segment), path.size() - 2)
		var next: Vector3 = path[segment_index].lerp(path[segment_index + 1], segment - segment_index)
		var bicycle_rejoin := resident.has("bicycle_rejoin")
		if bicycle_rejoin:
			# A parked bicycle may block the short return for several seconds.
			# Rejoin through the existing bounded walking cadence, never snapping
			# back onto the route or keeping the avoidance task budget occupied.
			progress = float(resident.walk_progress)
			next = resident.position.move_toward(resident.bicycle_rejoin, float(resident.walk_speed) * delta)
			var ground_ray := PhysicsRayQueryParameters3D.create(next + Vector3.UP * 0.45, next - Vector3.UP * 0.45, 1 | 2)
			var ground := space.intersect_ray(ground_ray)
			if ground.is_empty() or ground.normal.y < 0.75 or absf(float(ground.position.y) - float(resident.position.y)) > 0.22:
				continue
			next.y = float(ground.position.y) + 0.012
		var heading: Vector3 = next - resident.position
		heading.y = 0.0
		if heading.length_squared() > 0.000001:
			var target_yaw := atan2(heading.x, heading.z)
			var turn := wrapf(target_yaw - float(resident.yaw), -PI, PI)
			resident.yaw = wrapf(float(resident.yaw) + clampf(turn, -WALK_TURN_RATE * delta, WALK_TURN_RATE * delta), -PI, PI)
			if absf(turn) > WALK_ALIGNMENT:
				# Keep both the physical foot and rendered foot fixed during turns.
				batch.node.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, resident.yaw), resident.position - batch.origin))
				_walk_updates += 1
				continue
		# Yield to the player; short prevalidated corridors never enter the road.
		if Vector2(next.x - level.player.global_position.x, next.z - level.player.global_position.z).length() < 0.8:
			continue
		# Patrols and mission actors can enter a corridor after startup. Sweep the
		# real resident capsule before moving its body, then check the end pose.
		var query := _walk_query
		var body: StaticBody3D = resident.body
		var shape_offset: Vector3 = resident.get("body_shape_offset", Vector3.UP * 0.9)
		query.shape = resident.get("body_shape", _shape)
		_walk_query_exclude.clear()
		if is_instance_valid(body):
			_walk_query_exclude.append(body.get_rid())
		query.exclude = _walk_query_exclude
		query.transform = Transform3D(Basis.IDENTITY, resident.position + shape_offset)
		query.motion = next - resident.position
		var sweep := space.cast_motion(query)
		if not sweep.is_empty() and sweep[0] < 0.999:
			continue
		query.transform.origin = next + shape_offset
		query.motion = Vector3.ZERO
		if not space.intersect_shape(query, 1).is_empty():
			continue
		resident.walk_progress = progress
		if bicycle_rejoin:
			_relocate(index, resident.position, next, true)
			if next.distance_to(resident.bicycle_rejoin) < 0.04:
				resident.erase("bicycle_rejoin")
		else:
			resident.position = next
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
			if CivicClearance.blocked(level, at, 0.7):
				continue
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
			if level.get("yard_details") != null and not level.yard_details.is_clear(at, 0.7):
				continue
			if level.get("park_courts") != null and (not level.park_courts.is_clear(at, 0.7) or level.park_courts.is_court(at, 0.5)):
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

func set_capture_presence(center: Vector3, render_center: Vector3, near_radius := 55.0, far_radius := 180.0) -> void:
	# Camera-only captures add detail residency without evicting player colliders.
	set_presence(center, near_radius, far_radius, render_center)

func set_presence(center: Vector3, near_radius := 40.0, far_radius := 160.0, render_center := Vector3.INF) -> void:
	_animation_radius = clampf(near_radius, 8.0, 80.0)
	var new_presence_radius := maxf(far_radius, _animation_radius + CELL)
	var range_changed := not is_equal_approx(_presence_radius, new_presence_radius)
	_presence_radius = new_presence_radius
	var displaced_cells: Dictionary = {}
	# Active movers can cross a cell before _finish_panic commits a relocation.
	# The settled set covers cumulative movement across successive threats.
	for candidates in [_displaced, _panic]:
		for index in candidates:
			var resident: Dictionary = residents[index]
			var at: Vector3 = resident.position
			if Vector2(at.x - center.x, at.z - center.z).length_squared() <= pow(_presence_radius + CELL, 2):
				displaced_cells[resident.cell] = true
	for cell in _cells.values():
		# Keep a promoted resident's hidden slot alive until its proxy returns.
		var combat_present := false
		for resident_index in cell.resident_indices:
			if residents[resident_index].get("police_custody", false):
				continue # Completed custody must not pin streamed cells forever.
			if residents[resident_index].get("combat_controlled", false) or residents[resident_index].get("panic", false):
				combat_present = true
		var displaced_near := displaced_cells.has(cell.cell)
		var was_displaced_near := bool(cell.get("displaced_visible", false))
		cell.displaced_visible = displaced_near
		# A displaced slot retains its original batch origin. Distance culling
		# against that origin would hide it beside the player even if retained.
		var batch_range := 0.0 if displaced_near else _presence_radius
		if range_changed or displaced_near != was_displaced_near:
			for node in cell.nodes:
				if is_instance_valid(node):
					node.visibility_range_end = batch_range
		var distance := Vector2(center.x - cell.center.x, center.z - cell.center.z).length()
		if render_center.is_finite():
			distance = minf(distance, Vector2(render_center.x - cell.center.x, render_center.z - cell.center.z).length())
		if distance > _presence_radius + CELL * 1.5 and not cell.nodes.is_empty() and not combat_present and not displaced_near:
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
		elif (distance < _presence_radius + CELL or displaced_near) and cell.nodes.is_empty():
			for index in cell.resident_indices:
				var resident: Dictionary = residents[index]
				# Culling never resurrects: a dead identity regains no collider.
				if not resident.get("dead", false) and not resident.get("identity_unplaced", false) and not resident.get("police_custody", false):
					var body := StaticBody3D.new()
					body.set_meta("city_crowd_index", index)
					body.position = resident.position
					body.collision_layer = 8
					body.collision_mask = 0
					var collision := CollisionShape3D.new()
					collision.shape = resident.get("body_shape", _shape)
					collision.position = resident.get("body_shape_offset", Vector3.UP * 0.9)
					body.add_child(collision)
					add_child(body)
					resident.body = body
					cell.bodies.append(body)
				var batch: Dictionary = _batches[resident.batch]
				if not is_instance_valid(batch.node):
					var mesh := MultiMeshInstance3D.new()
					mesh.multimesh = batch.multimesh
					mesh.position = batch.origin
					mesh.visibility_range_end = batch_range
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mesh)
					batch.node = mesh
					cell.nodes.append(mesh)
			if not cell.nodes.is_empty():
				_cell_activations += 1

## Only the few residents actually struck gain a full combat actor. The static
## collider and shared render slot relinquish ownership together, preventing twins.
func begin_combat(index: int) -> Dictionary:
	if index < 0 or index >= residents.size():
		return {}
	var resident: Dictionary = residents[index]
	if resident.get("identity_unplaced", false) or resident.get("dead", false) or resident.get("combat_controlled", false) or not is_instance_valid(resident.body):
		return {}
	if _panic.has(index):
		# The full actor takes over from the resident's current fleeing spot.
		_finish_panic(index, false)
	resident.combat_controlled = true
	resident.body.collision_layer = 0
	var batch: Dictionary = _batches[resident.batch]
	batch.multimesh.set_instance_transform(resident.slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), resident.position - batch.origin))
	return {"position": resident.position, "yaw": resident.yaw}

func end_combat(index: int, current_position := Vector3.INF, current_yaw := INF, proxy_shape: CollisionShape3D = null) -> void:
	if index < 0 or index >= residents.size():
		return
	var resident: Dictionary = residents[index]
	if resident.get("police_custody", false):
		return
	resident.combat_controlled = false
	if resident.get("dead", false):
		return
	if current_position.is_finite():
		_relocate(index, resident.position, current_position)
	if is_finite(current_yaw):
		resident.yaw = current_yaw
	if proxy_shape != null:
		# Preserve the proxy's already-safe envelope, including short cast members,
		# instead of growing a different capsule into a low ceiling on demotion.
		resident.body_shape = proxy_shape.shape
		resident.body_shape_offset = proxy_shape.position
	if is_instance_valid(resident.body):
		resident.body.global_position = resident.position
		if proxy_shape != null:
			var collision: CollisionShape3D = resident.body.get_child(0)
			collision.shape = resident.body_shape
			collision.position = resident.body_shape_offset
		resident.body.collision_layer = 8
	var batch: Dictionary = _batches[resident.batch]
	batch.multimesh.set_instance_transform(resident.slot, Transform3D(Basis(Vector3.UP, resident.yaw), resident.position - batch.origin))

func _relocate(index: int, from_at: Vector3, to_at: Vector3, keep_walk := false) -> void:
	var resident: Dictionary = residents[index]
	var old_cell := Vector2i(floori(from_at.x / 4.0), floori(from_at.z / 4.0))
	var new_cell := Vector2i(floori(to_at.x / 4.0), floori(to_at.z / 4.0))
	if _spacing_grid.has(old_cell):
		_spacing_grid[old_cell].erase(index)
	if not _spacing_grid.has(new_cell):
		_spacing_grid[new_cell] = []
	_spacing_grid[new_cell].append(index)
	resident.position = to_at
	_track_displaced(index)
	# A displaced walker cannot resume its old absolute path without a snap.
	# It remains a quiet physical neighbor at the collision-checked endpoint.
	if resident.activity == "walking" and not keep_walk:
		resident.activity = "social"
		_walkers.erase(index)

func _track_displaced(index: int) -> void:
	var resident: Dictionary = residents[index]
	var at: Vector3 = resident.position
	var current_cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if current_cell == resident.cell:
		_displaced.erase(index)
	else:
		_displaced[index] = true

func _apply_transform(index: int, kind: String, facing := INF) -> void:
	_set_idle_visual(index, 0)
	var resident: Dictionary = residents[index]
	var batch: Dictionary = _batches[resident.batch]
	var basis := Basis(Vector3.UP, float(resident.yaw))
	var lift := Vector3.ZERO
	match kind:
		"cower":
			# Duck low and lean in; seated neighbors fold forward in the chair.
			basis = basis * Basis(Vector3.RIGHT, 0.30 if int(resident.pose) == 0 else 0.22) * Basis.from_scale(Vector3(1.0, 0.68 if int(resident.pose) == 0 else 0.86, 1.0))
		"run":
			basis = basis * Basis(Vector3.RIGHT, 0.14) * Basis(Vector3.FORWARD, sin(_clock * 11.0 + index) * 0.04)
			lift = Vector3.UP * absf(sin(_clock * 11.0 + index)) * 0.035
		"corpse":
			var yaw := float(resident.yaw) if not is_finite(facing) else facing
			if int(resident.pose) == 0:
				# Lies on its back, head away from the threat. No gore, no ragdoll.
				basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
				lift = Vector3.UP * 0.14
			else:
				basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.55) * Basis.from_scale(Vector3(1.0, 0.8, 1.0))
		"hidden":
			basis = Basis.from_scale(Vector3.ZERO)
	batch.multimesh.set_instance_transform(resident.slot, Transform3D(basis, resident.position - batch.origin + lift))

func is_dead(index: int) -> bool:
	return index >= 0 and index < residents.size() and residents[index].get("dead", false)

func resident_position(index: int) -> Vector3:
	return residents[index].position if index >= 0 and index < residents.size() and not residents[index].get("identity_unplaced", false) else Vector3.INF

## Cheap permanent death for overflow, save restore and promoted proxies. The
## body loses collision immediately; cell reloads never rebuild it.
func kill_resident(index: int, threat := Vector3.INF, corpse := true) -> bool:
	if index < 0 or index >= residents.size() or residents[index].get("dead", false):
		return false
	var resident: Dictionary = residents[index]
	if _panic.has(index):
		_set_mode(_panic[index], "done")
		_panic.erase(index)
	resident.panic = false
	resident.dead = true
	resident.combat_controlled = false
	_walkers.erase(index)
	if is_instance_valid(resident.body):
		resident.body.collision_layer = 0
	_dead_count += 1
	if corpse and not resident.get("identity_unplaced", false):
		_track_displaced(index)
		var facing := INF
		if threat.is_finite():
			var toward: Vector3 = threat - resident.position
			if Vector2(toward.x, toward.z).length() > 0.05:
				facing = atan2(toward.x, toward.z)
		_apply_transform(index, "corpse", facing)
	else:
		_displaced.erase(index)
		_apply_transform(index, "hidden")
	return true

func clear_corpse(index: int) -> void:
	if is_dead(index):
		_displaced.erase(index)
		_apply_transform(index, "hidden")

## One gunshot: scan only the cells overlapping its radius. Returns the indices
## whose chest lies within NEAR_MISS of the shot segment (direct threats).
func react_to_threat(origin: Vector3, radius: float, from: Vector3, to: Vector3, skip := -1) -> Array[int]:
	var direct: Array[int] = []
	var candidates: Dictionary = {}
	# Ordinary walkers can be 3m from their indexed corridor midpoint. Panic
	# displacement is unbounded and is handled separately by the sparse sets.
	var reach := radius + 4.0
	var shot_pad := NEAR_MISS + 4.0
	var low := Vector2i(floori(minf(origin.x - reach, minf(from.x, to.x) - shot_pad) / CELL),
		floori(minf(origin.z - reach, minf(from.z, to.z) - shot_pad) / CELL))
	var high := Vector2i(floori(maxf(origin.x + reach, maxf(from.x, to.x) + shot_pad) / CELL),
		floori(maxf(origin.z + reach, maxf(from.z, to.z) + shot_pad) / CELL))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var cell = _cells.get(Vector2i(x, z))
			if cell == null or cell.nodes.is_empty():
				continue
			_threat_cells += 1
			for index in cell.resident_indices:
				candidates[index] = true
	# Original cells remain the batch owners. Include displaced and currently
	# fleeing residents by actual position; no fixed displacement padding.
	for displaced in [_displaced, _panic]:
		for index in displaced:
			candidates[index] = true
	for index in candidates:
		var resident: Dictionary = residents[index]
		if index == skip or resident.get("dead", false) or resident.get("combat_controlled", false) or not is_instance_valid(resident.body):
			continue
		var at: Vector3 = resident.position
		var chest := at + Vector3.UP * 1.1
		var near_shot := Geometry3D.get_closest_point_to_segment(chest, from, to).distance_to(chest) < NEAR_MISS
		var heard := Vector2(at.x - origin.x, at.z - origin.z).length_squared() <= radius * radius
		if not heard and not near_shot:
			continue
		_threat_scanned += 1
		if near_shot:
			direct.append(index)
		panic_resident(index, from if near_shot else origin)
	return direct

func panic_resident(index: int, threat: Vector3) -> bool:
	if index < 0 or index >= residents.size():
		return false
	var resident: Dictionary = residents[index]
	if resident.get("identity_unplaced", false) or resident.get("dead", false) or resident.get("combat_controlled", false) or not is_instance_valid(resident.body):
		return false
	if _panic.has(index):
		var state: Dictionary = _panic[index]
		state.threat = threat
		state.last = _clock
		var near := Vector2(resident.position.x - threat.x, resident.position.z - threat.z).length() < 10.0
		if state.mode == "return" or (state.mode == "cower" and near and int(resident.pose) == 0 and str(resident.activity) != "porch" and int(state.replans) < 2):
			_set_mode(state, "plan")
		return true
	if _panic.size() >= PANIC_TOTAL:
		return false
	var fresh := {"threat": threat, "last": _clock, "began": _clock, "start": resident.position,
		"dest": resident.position, "mode": "", "stall": 0.0, "replans": 0, "bias": 0.0, "returning": 0.0}
	resident.panic = true
	_panic[index] = fresh
	_panic_started += 1
	# Porch and seated residents duck in place: no invented deck-edge descent.
	if int(resident.pose) == 0 and str(resident.activity) != "porch":
		_set_mode(fresh, "plan")
	else:
		_set_mode(fresh, "cower")
		_apply_transform(index, "cower")
		_panic_cowered += 1
	return true

func _set_mode(state: Dictionary, mode: String) -> void:
	var was_mover: bool = state.mode == "flee" or state.mode == "return"
	var is_mover: bool = mode == "flee" or mode == "return"
	_panic_movers += int(is_mover) - int(was_mover)
	state.mode = mode

func _panic_cast(index: int, from: Vector3, motion: Vector3, mask: int) -> float:
	if _panic_query == null:
		_panic_query = PhysicsShapeQueryParameters3D.new()
		_panic_query.margin = 0.02
	var resident: Dictionary = residents[index]
	_panic_query.shape = resident.get("body_shape", _shape)
	_panic_query.collision_mask = mask
	_panic_exclude.clear()
	if is_instance_valid(resident.body):
		_panic_exclude.append(resident.body.get_rid())
	_panic_query.exclude = _panic_exclude
	_panic_query.transform = Transform3D(Basis.IDENTITY, from + resident.get("body_shape_offset", Vector3.UP * 0.9))
	_panic_query.motion = motion
	_panic_casts += 1
	var sweep := get_world_3d().direct_space_state.cast_motion(_panic_query)
	return 1.0 if sweep.size() < 2 else float(sweep[0])

func _panic_ground(at: Vector3) -> Dictionary:
	if CivicClearance.blocked(level, at, 0.30):
		return {}
	_panic_ray.from = at + Vector3.UP * 1.0
	_panic_ray.to = at - Vector3.UP * 1.2
	_panic_ray.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(_panic_ray)

func _plan_flee(index: int, state: Dictionary) -> bool:
	var resident: Dictionary = residents[index]
	var at: Vector3 = resident.position
	var away: Vector3 = at - state.threat
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = -Vector3(sin(float(resident.yaw)), 0.0, cos(float(resident.yaw)))
	away = away.normalized().rotated(Vector3.UP, float(state.bias))
	var streets: bool = npcs != null and npcs.has_method("_street_info")
	var road_choice := Vector3.INF
	# Directly away first, then progressively wider; never back toward the shot.
	for angle in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var direction := away.rotated(Vector3.UP, angle)
		if streets:
			var street: Dictionary = npcs._street_info(at + direction * PANIC_FLEE_DISTANCE)
			if float(street.get("distance", INF)) < float(street.get("width", 9.5)) * 0.5:
				if not road_choice.is_finite():
					road_choice = direction
				continue
		if _try_flee(index, state, direction):
			return true
	return road_choice.is_finite() and _try_flee(index, state, road_choice)

func _try_flee(index: int, state: Dictionary, direction: Vector3) -> bool:
	var at: Vector3 = residents[index].position
	# Static scenery and vehicles plan the run; people are handled per step.
	var travel := _panic_cast(index, at, direction * PANIC_FLEE_DISTANCE, 2 | 16) * PANIC_FLEE_DISTANCE - 0.35
	for attempt in 2:
		if travel < 2.5:
			return false
		var dest := at + direction * travel
		var ground := _panic_ground(dest)
		if not ground.is_empty() and ground.normal.y >= 0.8 and absf(ground.position.y - at.y) < 1.0:
			dest.y = ground.position.y + 0.012
			state.dest = dest
			state.stall = 0.0
			_set_mode(state, "flee")
			return true
		travel *= 0.5
	return false

func _tick_panic(delta: float) -> void:
	_panic_updates = 0
	_panic_phase = (_panic_phase + 1) % PANIC_GROUPS
	_panic_accumulator += delta
	var slow := _panic_accumulator >= UPDATE_INTERVAL
	if slow:
		_panic_accumulator = 0.0
	var planned := 0
	for index in _panic.keys():
		if not _panic.has(index):
			continue
		var state: Dictionary = _panic[index]
		var resident: Dictionary = residents[index]
		if not is_instance_valid(resident.body):
			# The cell unloaded behind the player: settle where they stand.
			_finish_panic(index, false)
			continue
		var mode: String = state.mode
		if mode == "plan" and planned < 8:
			# Route planning is spread over frames: at most eight plans per tick.
			planned += 1
			if _panic_movers >= PANIC_MOVERS or not _plan_flee(index, state):
				_set_mode(state, "cower")
				_apply_transform(index, "cower")
				_panic_cowered += 1
		elif (mode == "flee" or mode == "return") and index % PANIC_GROUPS == _panic_phase:
			_step_panic(index, state, delta * PANIC_GROUPS)
		elif mode == "cower" and slow and _clock - float(state.last) >= PANIC_SAFE and _clock - float(state.began) >= PANIC_MIN_TIME:
			_begin_panic_return(index, state)

func _begin_panic_return(index: int, state: Dictionary) -> void:
	var resident: Dictionary = residents[index]
	var displaced: float = resident.position.distance_to(state.start)
	if displaced < 0.15 or int(resident.pose) != 0 or _panic_movers >= PANIC_MOVERS:
		_finish_panic(index, displaced < 0.15)
		return
	_set_mode(state, "return")
	state.stall = 0.0
	state.returning = _clock

func _step_panic(index: int, state: Dictionary, delta: float) -> void:
	var resident: Dictionary = residents[index]
	var returning: bool = state.mode == "return"
	if returning and _clock - float(state.returning) > PANIC_RETURN_LIMIT:
		_finish_panic(index, false)
		return
	var goal: Vector3 = state.start if returning else state.dest
	var heading: Vector3 = goal - resident.position
	heading.y = 0.0
	_panic_updates += 1
	if heading.length() < 0.08:
		if returning:
			_finish_panic(index, true)
		else:
			_set_mode(state, "cower")
			_apply_transform(index, "cower")
			_panic_cowered += 1
		return
	var wanted := atan2(heading.x, heading.z)
	var turn := wrapf(wanted - float(resident.yaw), -PI, PI)
	resident.yaw = wrapf(float(resident.yaw) + clampf(turn, -PANIC_TURN_RATE * delta, PANIC_TURN_RATE * delta), -PI, PI)
	if absf(turn) > 0.05:
		# Turn in place before any forward travel.
		_apply_transform(index, "stand")
		return
	var step := minf(PANIC_SPEED * (0.5 if returning else 1.0) * delta, heading.length())
	var next: Vector3 = resident.position + Vector3(sin(float(resident.yaw)), 0.0, cos(float(resident.yaw))) * step
	var ground := _panic_ground(next)
	if ground.is_empty() or ground.normal.y < 0.7 or absf(ground.position.y + 0.012 - resident.position.y) > 0.23:
		_panic_blocked(index, state, delta)
		return
	next.y = ground.position.y + 0.012
	if _panic_cast(index, resident.position, next - resident.position, 2 | 4 | 8 | 16) < 0.999:
		_panic_blocked(index, state, delta)
		return
	resident.position = next
	resident.body.position = next
	state.stall = 0.0
	_apply_transform(index, "stand" if returning else "run")

func _panic_blocked(index: int, state: Dictionary, delta: float) -> void:
	state.stall = float(state.stall) + delta
	if state.mode == "return":
		if state.stall >= 1.5:
			_finish_panic(index, false)
		return
	if state.stall < 0.6:
		return
	state.stall = 0.0
	state.replans = int(state.replans) + 1
	_panic_replans += 1
	if int(state.replans) <= 2:
		# Something stepped in the way: bias the next plan to the other side.
		state.bias = 0.8 if int(state.replans) == 1 else -0.8
		_set_mode(state, "plan")
	else:
		_set_mode(state, "cower")
		_apply_transform(index, "cower")
		_panic_cowered += 1

func _finish_panic(index: int, at_home: bool) -> void:
	var state: Dictionary = _panic[index]
	_set_mode(state, "done")
	_panic.erase(index)
	var resident: Dictionary = residents[index]
	resident.panic = false
	_panic_restored += 1
	if at_home:
		resident.position = state.start
		if is_instance_valid(resident.body):
			resident.body.position = state.start
	elif resident.position.distance_to(state.start) > 0.05:
		_relocate(index, state.start, resident.position)
	if not resident.get("dead", false) and not resident.get("combat_controlled", false):
		_apply_transform(index, "stand")

func get_panic_status() -> Dictionary:
	return {"panic": _panic.size(), "panic_movers": _panic_movers, "panic_updates": _panic_updates,
		"panic_casts": _panic_casts, "panic_started": _panic_started, "panic_cowered": _panic_cowered,
		"panic_restored": _panic_restored, "panic_replans": _panic_replans, "threat_scanned": _threat_scanned,
		"threat_cells": _threat_cells, "dead": _dead_count, "panic_budget": PANIC_TOTAL, "panic_mover_budget": PANIC_MOVERS}

func get_status() -> Dictionary:
	var active_cells := 0
	for cell in _cells.values():
		active_cells += int(not cell.nodes.is_empty())
	var result := {"total": residents.size(), "porch": _porch_total, "social": residents.size() - _porch_total, "park": _park_count, "park_population": _park_population.duplicate(), "walkers": _walkers.size(), "walking_updates": _walk_updates, "seated": _seated_total, "circle_groups": _circle_groups.size(), "occupied_cells": _cells.size(), "cell_activations": _cell_activations, "active_cells": active_cells, "far_from_intro_route": _coverage.get("far_route", 0), "span_x": _coverage.get("span_x", 0), "span_z": _coverage.get("span_z", 0), "draw_batches": _batches.size(), "shared_meshes": _meshes.size(), "near_updates": _near_updates, "update_interval": UPDATE_INTERVAL, "name_labels": 0}
	result.staggered_idle = use_staggered_idle
	result.idle_skipped_steps = _idle_skipped_steps
	result.idle_life = _idle_life.status()
	result.identity_source = _identity_source
	result.identity_relocated = _identity_relocated
	result.identity_failures = _identity_failures.duplicate()
	result.neighborhood_distribution = _distribution_counts.duplicate()
	result.distribution_fallbacks = _distribution_fallbacks
	result.new_group_sizes = _neighborhood_groups.map(func(group): return group.indices.size())
	result.actual_park_population = _physical_park_population.duplicate()
	result.destination_population = _destination_population.duplicate()
	result.merge(get_panic_status())
	return result

## Canonical legacy identities are captured once before redevelopment. Candidate
## acceptance after a demolition must never reassign crowd_N to a different home.
func _export_recipe() -> void:
	if level.get("civic_district") != null:
		push_error("Crowd recipe export requires --no-civic-district")
		return
	var entries: Array = []
	for index in residents.size():
		var resident: Dictionary = residents[index]
		var entry := {"id": "crowd_%d" % index, "birth_position": _recipe_vector(resident.position),
			"yaw": float(resident.yaw), "activity": str(resident.activity), "pose": int(resident.pose)}
		if resident.has("walk_path"):
			entry.walk_path = []
			for point in resident.walk_path:
				entry.walk_path.append(_recipe_vector(point))
			entry.walk_speed = float(resident.walk_speed)
		if resident.has("park_name"):
			entry.park_name = str(resident.park_name)
		entries.append(entry)
	var groups: Array = []
	for group in _circle_groups:
		groups.append({"center": _recipe_vector(group.center), "indices": group.indices, "street": str(group.street)})
	var file := FileAccess.open(RECIPE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write canonical crowd recipe")
		return
	file.store_string(JSON.stringify({"version": 1, "source": "legacy pre-civic acceptance order; captured before simulation tick",
		"level_sha256": FileAccess.get_sha256("res://assets/data/pen_lucy_level.json"),
		"residents": entries, "circle_groups": groups}, "  "))
	file.close()
	_identity_source = "exported_legacy_recipe"
	print("[crowd_recipe] exported ", entries.size(), " stable identities to ", RECIPE_PATH)

func _recipe_vector(at: Vector3) -> Array:
	return [at.x, at.y, at.z]

func identity_snapshot() -> Array:
	var result: Array = []
	for index in residents.size():
		var resident: Dictionary = residents[index]
		result.append({"id": "crowd_%d" % index, "birth_position": _recipe_vector(resident.get("birth_position", resident.position)),
			"birth_activity": resident.get("birth_activity", resident.activity), "relocated": resident.get("civic_relocated", false)})
	return result

func _instantiate_recipe() -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		push_error("Canonical crowd recipe is invalid")
		return false
	var entries: Array = parsed.get("residents", [])
	if entries.is_empty():
		return false
	# Validate every ordinal before creating any body. A partial recipe must not
	# fall through to legacy generation with a half-filled identity array.
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if str(entry.get("id", "")) != "crowd_%d" % index or not entry.get("birth_position") is Array or entry.birth_position.size() != 3:
			push_error("Canonical crowd ordinal/anchor is invalid at " + str(index))
			return false
		_recipe_reservations.append(level.vector(entry.birth_position))
		for point in entry.get("walk_path", []):
			_recipe_reservations.append(level.vector(point))
	_identity_source = "canonical_legacy_recipe"
	_loading_recipe = true
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var birth: Vector3 = level.vector(entry.birth_position)
		var activity := str(entry.activity)
		# Only current placement changes. The canonical recipe and ordinal never do.
		if activity in ["park", "circle", "social"] and _park_plan.is_empty() and _distribution_counts.is_empty():
			_prepare_park_distribution(entries)
		var planned: Dictionary = _park_plan.get(index, {})
		var seated := int(entry.pose) == 1 and activity == "porch"
		var yaw := float(entry.yaw)
		var found: Dictionary = {}
		if not planned.is_empty():
			found = {"position": planned.position}
			activity = str(planned.activity)
			seated = bool(planned.get("bench", false))
			yaw = float(planned.yaw)
		else:
			found = _deck_position(birth) if activity == "porch" else _recipe_standing(birth)
		var relocated := false
		if found.is_empty():
			found = CivicClearance.sidewalk_relocation(level, npcs, birth, 0.30, _recipe_reservations)
			relocated = true
			activity = "social"
			seated = false
		var path: Array[Vector3] = []
		if activity == "walking" and not found.is_empty():
			for value in entry.get("walk_path", []):
				var checked := _recipe_standing(level.vector(value))
				if checked.is_empty():
					path.clear()
					break
				path.append(checked.position)
			if path.size() < 2:
				activity = "social"
		# A failed placement keeps a dormant ordinal, never a floating actor or
		# another neighbor substituted for a saved-death ID. Fixtures require zero.
		var unplaced := found.is_empty()
		var at: Vector3 = birth if unplaced else found.position
		_add_resident(at, yaw, activity, seated)
		var resident: Dictionary = residents[index]
		resident.stable_id = str(entry.id)
		resident.birth_position = birth
		resident.birth_activity = str(entry.activity)
		resident.birth_pose = int(entry.pose)
		resident.civic_relocated = relocated
		resident.identity_unplaced = unplaced
		resident.neighborhood_relocated = not planned.is_empty()
		if bool(planned.get("bench", false)):
			resident.pose = 2
			resident.bench_id = int(planned.bench_id)
			resident.park_name = str(planned.park)
		if relocated:
			_identity_relocated += 1
		if unplaced:
			_identity_failures.append(index)
			resident.body.collision_layer = 0
			resident.body.visible = false
			continue
		if activity == "walking":
			resident.walk_a = path[0]
			resident.walk_b = path[-1]
			resident.walk_path = path
			resident.walk_progress = 0.5
			resident.walk_direction = 1.0
			resident.walk_speed = float(entry.get("walk_speed", 1.0))
			_walkers.append(index)
		if activity == "park":
			resident.park_name = str(planned.get("park", entry.get("park_name", "Park")))
			_park_count += 1
			_park_population[resident.park_name] = int(_park_population.get(resident.park_name, 0)) + 1
	for original in parsed.get("circle_groups", []):
		var indices: Array[int] = []
		var center := Vector3.ZERO
		for value in original.indices:
			var index := int(value)
			if index >= 0 and index < residents.size() and not _park_plan.has(index):
				indices.append(index)
				center += residents[index].position
		if not indices.is_empty():
			_circle_groups.append({"center": center / indices.size(), "indices": indices, "street": str(original.street)})
	_circle_groups.append_array(_neighborhood_groups)
	for resident in residents:
		var park := _population_park(resident.position)
		if not park.is_empty():
			_physical_park_population[park] = int(_physical_park_population.get(park, 0)) + 1
	_loading_recipe = false
	_recipe_reservations.clear()
	return true

func _recipe_standing(at: Vector3) -> Dictionary:
	if CivicClearance.blocked(level, at, 0.35):
		return {}
	if level.get("park_furniture") != null and not level.park_furniture.is_clear(at, 0.35):
		return {}
	var ground: Dictionary = level.ground_at(at)
	if ground.is_empty() or ground.normal.y < 0.80 or absf(ground.position.y + 0.012 - at.y) > 0.35:
		return {}
	var foot: Vector3 = ground.position + Vector3.UP * 0.012
	if not _spaced(foot, 0.58):
		return {}
	if level.get("vegetation") != null and not level.vegetation.is_trunk_clear(foot, 0.35):
		return {}
	if level.get("yard_details") != null and not level.yard_details.is_clear(foot, 0.35):
		return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.9)
	query.collision_mask = 2 | 4 | 8 | 16
	query.margin = 0.015
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": foot}

func _prepare_park_distribution(entries: Array) -> void:
	var pending: Array[int] = []
	for park in level.level_data.get("parks", []):
		var polygon := PackedVector2Array()
		for value in park.polygon:
			var point: Vector3 = level.vector(value)
			polygon.append(Vector2(point.x, point.z))
		_population_parks.append({"name": str(park.name), "polygon": polygon})
	for i in entries.size():
		if str(entries[i].activity) in ["park", "circle", "social"]:
			pending.append(i)
	var furniture = level.get("park_furniture")
	if furniture != null:
		for seat in furniture.bench_slots:
			if pending.is_empty():
				break
			var at: Vector3 = seat.position
			if not _spaced(at, 0.8) or not _social_spacing(at, 0.85):
				continue
			# Furniture setup validated the seat and headroom. Ignore its own bench
			# collider, while rejecting other architecture and people at the seat.
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _shape
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
			query.collision_mask = 2 | 8 | 16
			query.exclude = [seat.body.get_rid()]
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
			var index: int = pending.pop_front()
			_park_plan[index] = {"position": at, "yaw": seat.yaw, "activity": "park", "bench": true, "bench_id": seat.bench_id, "park": seat.park}
			_social_reserved.append(at)
			_distribution_counts.bench = int(_distribution_counts.get("bench", 0)) + 1
	var destinations := _social_destinations()
	var sequence := [2, 5, 3, 7, 4, 8, 6]
	for destination in destinations:
		if pending.size() < 2:
			break
		var count: int = mini(int(sequence[_neighborhood_groups.size() % sequence.size()]), pending.size())
		if pending.size() - count == 1 and count > 2:
			count -= 1
		var destination_key := str(destination.kind) + ":" + str(destination.label)
		if destination.kind == "court_edge" and int(_destination_population.get(destination_key, 0)) + count > 16:
			continue
		if destination.kind == "business" and (int(_destination_population.get(destination_key, 0)) + count > 14 or int(_distribution_counts.get("business", 0)) + count > 200):
			continue
		var proposed: Array[Vector3] = []
		var center: Vector3 = destination.position
		var tangent: Vector3 = destination.tangent
		var across := Vector3(-tangent.z, 0, tangent.x)
		for member in count:
			var desired: Vector3
			if destination.kind in ["business", "street"]:
				# A loose row along the frontage leaves the middle of the pavement open.
				desired = center + tangent * (float(member) - (count - 1) * 0.5) * 1.15 + across * (0.10 if member % 2 == 0 else -0.10)
			else:
				var angle := TAU * float(member) / count
				var radius := maxf(0.7, 0.62 / sin(PI / count))
				desired = center + (tangent * cos(angle) + across * sin(angle)) * radius
			var found := _social_position(desired)
			if found.is_empty():
				proposed.clear()
				break
			proposed.append(found.position)
		if proposed.size() != count:
			continue
		var indices: Array[int] = []
		for point in proposed:
			var index: int = pending.pop_front()
			var facing := center - point
			_park_plan[index] = {"position": point, "yaw": atan2(facing.x, facing.z), "activity": "circle"}
			indices.append(index)
			_social_reserved.append(point)
			var park := _population_park(point)
			if not park.is_empty():
				_planned_park_counts[park] = int(_planned_park_counts.get(park, 0)) + 1
		var kind := str(destination.kind)
		_distribution_counts[kind] = int(_distribution_counts.get(kind, 0)) + count
		_destination_population[destination_key] = int(_destination_population.get(destination_key, 0)) + count
		_neighborhood_groups.append({"center": center, "indices": indices, "street": str(destination.label), "destination": kind})
	# Rare partial group: a validated sidewalk is preferable to repopulating the
	# crowded edge green. Never drop an identity if the geometry has changed again.
	for index in pending:
		for destination in destinations:
			if destination.kind != "street":
				continue
			var found := _social_position(destination.position)
			if found.is_empty():
				continue
			_park_plan[index] = {"position": found.position, "yaw": float(entries[index].yaw), "activity": "social"}
			_social_reserved.append(found.position)
			var park := _population_park(found.position)
			if not park.is_empty():
				_planned_park_counts[park] = int(_planned_park_counts.get(park, 0)) + 1
			_distribution_counts.social = int(_distribution_counts.get("social", 0)) + 1
			break
		if not _park_plan.has(index):
			_distribution_fallbacks += 1
	_social_reserved.clear()

func _social_spacing(at: Vector3, gap := 1.1) -> bool:
	for point in _social_reserved:
		if Vector2(at.x - point.x, at.z - point.z).length_squared() < gap * gap:
			return false
	return true

func _social_position(wanted: Vector3) -> Dictionary:
	if not _social_spacing(wanted, 1.1):
		return {}
	var park := _population_park(wanted)
	if park == "Community green 2" or (not park.is_empty() and int(_planned_park_counts.get(park, 0)) >= 6):
		return {}
	var street: Dictionary = npcs._street_info(wanted)
	if float(street.get("distance", INF)) < float(street.get("width", 9.5)) * 0.5 + 0.6:
		return {}
	if npcs._route_distance(wanted) < 1.0 or not npcs.stair_approach_clear(wanted, 0.95):
		return {}
	if level.get("park_courts") != null and (level.park_courts.is_court(wanted, 1.3) or not level.park_courts.is_clear(wanted, 0.7)):
		return {}
	var ground: Dictionary = level.ground_at(wanted)
	if ground.is_empty() or ground.normal.y < 0.94:
		return {}
	var at: Vector3 = ground.position + Vector3.UP * 0.012
	if not _spaced(at, 1.0):
		return {}
	return _recipe_standing(at)

func _social_destinations() -> Array[Dictionary]:
	var shops: Array[Dictionary] = []
	var courts: Array[Dictionary] = []
	var businesses: Array = level.level_data.get("businesses", []).duplicate()
	var district = level.get("civic_district")
	if district != null:
		for business in district.businesses:
			var yaw := float(business.yaw)
			var normal := Vector3(sin(yaw), 0, cos(yaw))
			var door: Vector3 = level.vector(business.position) + normal * float(business.depth) * 0.5
			businesses.append({"name": business.label, "door_position": [door.x,door.y,door.z], "normal": [normal.x,0,normal.z]})
	for business in businesses:
		var door: Vector3 = level.vector(business.get("door_position", business.get("front_position", [0,0,0])))
		var info: Dictionary = npcs._street_info(door)
		var tangent: Vector3 = info.get("tangent", Vector3.RIGHT)
		var normal: Vector3 = level.vector(business.get("normal", [0,0,1]))
		for distance in [2.0, 1.25, 2.75]:
			for offset in [-6.0, 6.0, -11.0, 11.0, -16.0, 16.0]:
				shops.append({"position": door + normal * distance + tangent * offset, "tangent": tangent, "kind": "business", "label": str(business.get("name", "Local business"))})
	if level.get("park_courts") != null:
		for court in level.park_courts.records:
			# This northern edge park already had 54 residents. Give it bench users
			# and keep new standing groups at the other neighborhood destinations.
			if str(court.id) == "park_court_4":
				continue
			var polygon: PackedVector2Array = court.polygon
			for i in range(1, polygon.size()):
				var a := Vector3(polygon[i-1].x, 0, polygon[i-1].y)
				var b := Vector3(polygon[i].x, 0, polygon[i].y)
				var tangent := (b-a).normalized()
				if a.distance_to(b) < 6:
					continue
				var out := Vector3(-tangent.z, 0, tangent.x)
				var probe := (a+b)*0.5 + out
				if Geometry2D.is_point_in_polygon(Vector2(probe.x,probe.z), polygon):
					out = -out
				for fraction in [0.3, 0.7]:
					courts.append({"position": a.lerp(b,fraction) + out*3.8, "tangent": tangent, "kind": "court_edge", "label": str(court.id)})
	var result: Array[Dictionary] = []
	for i in maxi(shops.size(), courts.size()):
		if i < shops.size():
			result.append(shops[i])
		if i < courts.size():
			result.append(courts[i])
	# Spread the remainder across the entire real sidewalk network. Street groups
	# vary in size too; none of the old circle ordinals are regenerated/reordered.
	for sample in _street_samples(13.0):
		var tangent := Vector3(sample.across.z, 0, -sample.across.x)
		for side in [-1.0, 1.0]:
			result.append({"position": sample.center + sample.across * side * (float(sample.half) + 1.4), "tangent": tangent, "kind": "street", "label": str(sample.street)})
	return result

func _population_park(at: Vector3) -> String:
	var point := Vector2(at.x, at.z)
	for park in _population_parks:
		if Geometry2D.is_point_in_polygon(point, park.polygon):
			return str(park.name)
	return ""
