extends Node3D
## Continuous neighborhood traffic. Directed lanes share exclusive junction
## reservations; distant cars retain cheap simulation without physics queries.

## Deduplicated contact events from externally driven (police) cars; same
## schema as city_driving.vehicle_collision with driver == "external".
signal external_collision(contact: Dictionary)

const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Signals := preload("res://scripts/city/city_street_signals.gd")
const ParkedCars := preload("res://scripts/city/city_parked_cars.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const TARGET_CARS := 90
# A leader lies within a 45m by 1.85m forward corridor. Its maximum radial
# distance is <48m, so only the current and eight adjacent cells can contain it.
const LEADER_CELL_SIZE := 48.0
const FAR_DAMAGE_INTERVAL := .15
const MAX_FAR_DAMAGE_UPDATES := 8
# Cars and parked colliders near an externally driven car keep physics
# presence even far from the explorer, so a cruiser never passes through them.
const EXTERNAL_PRESENCE_RADIUS := 40.0
const MAX_EMERGENCY_VEHICLES := 4
const MAX_EMERGENCY_JUNCTIONS_PER_BODY := 2
# Separate physical obstacles, never AI traffic identities or player-owned cars.
var emergency_vehicles: Array[Node3D] = []
var _emergency_half_extents: Dictionary = {}
# Node name -> body instance ID; at most eight shared junction leases.
var _emergency_junctions: Dictionary = {}
var _external_presence := false
var external_claims := 0
var external_releases := 0
var _far_damage_cursor := 0
var far_damage_updates := 0
var far_damage_peak_updates := 0
var leader_candidate_checks := 0
var leader_full_pair_checks := 0
var spawn_street_counts: Dictionary = {}
var network: Network
var reservations: Dictionary = {}
var junction_transfers := 0
var _control_clock := 0.0
var _presence_clock := 0.0
var signals: Node3D
var parked: Node3D
var street_details: Dictionary = {}
var vehicles: Array[Node3D] = []
## Driving-owned bodies outside the AI fleet (the starter car). Shots, presence,
## leader and junction-exit checks include them; AI ticks, status totals and
## recycling never do. Fleet cars the player takes stay in vehicles instead.
var player_fleet: Array[Node3D] = []
var level: Node3D
var road_points: Array[Vector3] = []
var road_width := 9.5
var road_length := 0.0
var _distances: Array[float] = []
var skipped_spawns := 0
var _recycle_check := 0.0

## Combat compares this vehicle result with its world/NPC ray result. A body
## result has no tire_index; it shields deeper wheels/NPCs even beyond the 55m
## physics radius. All candidate work is shot-only, without extra physics bodies.
func raycast_tires(from: Vector3, to: Vector3) -> Dictionary:
	var nearest: Dictionary = parked.raycast_tires(from, to) if is_instance_valid(parked) else {}
	for car in vehicles + player_fleet:
		if not is_instance_valid(car):
			continue
		if Geometry3D.get_closest_point_to_segment(car.global_position, from, to).distance_squared_to(car.global_position) > 9.0:
			continue
		var hit: Dictionary = car.raycast_tires(from, to)
		if not hit.is_empty() and (nearest.is_empty() or float(hit.distance) < float(nearest.distance)):
			nearest = hit
	return nearest

func receive_gunshot(hit: Dictionary, origin: Vector3) -> Dictionary:
	var body = hit.get("collider")
	if not is_instance_valid(body):
		return {}
	if body.has_meta("traffic_vehicle") and body.has_method("receive_gunshot"):
		return body.receive_gunshot(hit, origin)
	if body.has_meta("parked_vehicle") and is_instance_valid(parked):
		return parked.receive_gunshot(hit, origin)
	return {}

func notify_gunshot(from: Vector3, to: Vector3) -> int:
	# Event-driven, at most 90 inexpensive segment distances per shot. A nearby
	# miss is frightening too. The caller truncates the segment at the first hit.
	var count := 0
	for car in vehicles:
		if not is_instance_valid(car):
			continue
		var closest := Geometry3D.get_closest_point_to_segment(car.global_position, from, to)
		if closest.distance_squared_to(car.global_position) <= 12.0 * 12.0:
			car.react_to_gunfire(from)
			count += 1
	return count

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "NeighborhoodTraffic"
	signals = Signals.new()
	add_child(signals)
	signals.setup(level)
	var longest := 0.0
	for road in level.level_data.get("roads", []):
		if str(road.get("name", "")) != "Old York Road":
			continue
		var candidates: Array[Vector3] = []
		var length := 0.0
		for value in road.get("points", []):
			var p := Vector3(float(value[0]), float(value[1]), float(value[2]))
			if not candidates.is_empty():
				length += Vector2(p.x - candidates[-1].x, p.z - candidates[-1].z).length()
			candidates.append(p)
		if length > longest:
			longest = length
			road_points = candidates
			road_width = float(road.get("width", 9.5))
	if road_points.size() < 2 or road_width < 7.0:
		push_error("Traffic bootstrap failed: Old York Road requires at least two points and width >= 7m")
		return
	# A consistent south-to-north centerline; lane offsets then follow US traffic.
	if road_points[0].z < road_points[-1].z:
		road_points.reverse()
	_distances.append(0.0)
	for i in range(1, road_points.size()):
		road_length += Vector2(road_points[i].x - road_points[i - 1].x, road_points[i].z - road_points[i - 1].z).length()
		_distances.append(road_length)
	if road_length < 120.0:
		push_error("Traffic bootstrap failed: Old York Road length %.2fm is below 120m" % road_length)
		return
	network = Network.new()
	network.setup(level)
	street_details = CityDressing.build_street_network(level, network)
	_spawn_network()
	parked = ParkedCars.new()
	add_child(parked)
	parked.setup(level, self)
	_update_presence()
	_update_leaders()

func _spawn_network() -> void:
	var pools: Dictionary = {}
	var weights: Dictionary = {}
	for lane in network.lanes:
		if float(lane.length) < 27.0 or not bool(lane.enabled):
			continue
		var street: String = str(lane.street)
		if not pools.has(street):
			pools[street] = []
			weights[street] = 0.0
		weights[street] = float(weights[street]) + float(lane.length)
		var points: Array[Vector3] = lane.points
		# The lane already stops before the junction. Add another 12m buffer
		# and seed several positions on long blocks, at least30m apart.
		var along := minf(14.0, float(lane.length) / 3.0)
		while along <= float(lane.length) - 12.0:
			pools[street].append({"lane": int(lane.id), "along": along,
				"position": network.point_at(points, along)})
			along += 30.0
	# First cover each usable street, then retain a busy introductory arterial.
	for street in pools:
		_spawn_from_pool(str(street), pools[street])
	if pools.has("Old York Road"):
		while int(spawn_street_counts.get("Old York Road", 0)) < 8:
			if not _spawn_from_pool("Old York Road", pools["Old York Road"]):
				break
	# Remaining capacity is proportional to usable lane length. Exhausted or
	# obstructed streets simply yield their quota to another supported road.
	while vehicles.size() < TARGET_CARS:
		var selected := ""
		var best := -1.0
		for street in pools:
			if pools[street].is_empty():
				continue
			var score := float(weights[street]) / float(int(spawn_street_counts.get(street, 0)) + 1)
			if score > best:
				best = score
				selected = str(street)
		if selected.is_empty():
			break
		_spawn_from_pool(selected, pools[selected])

func _spawn_from_pool(street: String, pool: Array) -> bool:
	while not pool.is_empty():
		# Spread a street's first cars among blocks; later cars fill the gaps.
		var selected := 0
		var best := -INF
		for i in pool.size():
			var point: Vector3 = pool[i].position
			var score := INF
			for car in vehicles:
				if str(network.lanes[car.lane_id].street) == street:
					score = minf(score, point.distance_squared_to(car.global_position))
			if not is_finite(score):
				score = -point.length_squared()
			if score > best:
				best = score
				selected = i
		var candidate: Dictionary = pool[selected]
		pool.remove_at(selected)
		var occupied := false
		for existing in vehicles:
			if existing.global_position.distance_to(candidate.position) < 18.0:
				occupied = true
		if occupied:
			continue
		var lane_id: int = int(candidate.lane)
		var source: Array[Vector3] = network.lanes[lane_id].points
		var path: Array[Vector3] = [candidate.position]
		var distance := 0.0
		for i in range(1, source.size()):
			distance += Vector2(source[i].x - source[i - 1].x, source[i].z - source[i - 1].z).length()
			if distance > float(candidate.along) + 0.01:
				path.append(source[i])
		var car = Vehicle.new()
		var number := vehicles.size()
		car.name = "NeighborhoodCar_%02d" % number
		# Register the body at its spawn, never briefly at the parent's origin.
		# A player already there must not be displaced on the next physics sync.
		car.position = to_local(candidate.position)
		add_child(car)
		var police := number in [5, 24, 43, 62]
		var profile: Dictionary = Vehicle.driver_profile(number, police)
		if car.setup(self, path, "neighborhood_%02d" % number, float(profile.speed), number, police):
			car.driver_style = str(profile.style)
			car.lane_id = lane_id
			car.route_sequence = number
			vehicles.append(car)
			spawn_street_counts[street] = int(spawn_street_counts.get(street, 0)) + 1
			return true
		skipped_spawns += 1
		car.free()
	return false

func _profile_add(key: String, began: int) -> void:
	Vehicle.profile_totals[key] = int(Vehicle.profile_totals.get(key, 0)) + Time.get_ticks_usec() - began

func _update_presence() -> void:
	var began := Time.get_ticks_usec() if Vehicle.profile_queries else 0
	_update_presence_impl()
	if Vehicle.profile_queries:
		_profile_add("presence_usec", began)

func _update_presence_impl(prospective: Node3D = null) -> void:
	if not is_instance_valid(level.player):
		return
	var center: Vector3 = level.player.global_position
	var external := PackedVector3Array()
	for car in vehicles:
		if is_instance_valid(car) and (not car.external_owner.is_empty() or car == prospective):
			external.append(car.global_position)
	_prune_emergency_vehicles()
	for body in emergency_vehicles:
		external.append(body.global_position)
	if external.is_empty():
		for car in vehicles:
			car.set_presence(center)
		for car in player_fleet:
			if is_instance_valid(car):
				car.set_presence(center)
	else:
		for car in vehicles:
			car.set_presence(_presence_center(car.global_position, center, external))
		for car in player_fleet:
			if is_instance_valid(car):
				car.set_presence(_presence_center(car.global_position, center, external))
	if is_instance_valid(parked) and parked.has_method("set_external_centers") and (_external_presence or not external.is_empty()):
		parked.set_external_centers(external, EXTERNAL_PRESENCE_RADIUS)
	_external_presence = not external.is_empty()

## The explorer, or an externally driven car within its presence radius,
## whichever is nearer. Vehicle.set_presence applies the usual hysteresis.
func _presence_center(at: Vector3, center: Vector3, external: PackedVector3Array) -> Vector3:
	var best := center
	var best_distance := at.distance_squared_to(center)
	for point in external:
		var distance := at.distance_squared_to(point)
		if distance < best_distance and distance <= EXTERNAL_PRESENCE_RADIUS * EXTERNAL_PRESENCE_RADIUS:
			best = point
			best_distance = distance
	return best

func _update_leaders() -> void:
	var began := Time.get_ticks_usec() if Vehicle.profile_queries else 0
	_update_leaders_impl()
	if Vehicle.profile_queries:
		_profile_add("leaders_usec", began)

func _update_leaders_impl() -> void:
	# Only the narrow forward lane corridor matters. Sidewalk residents and
	# opposing traffic do not create phantom braking envelopes. Snapshot headings
	# once, then prune only impossible candidates; the exact corridor is unchanged.
	var cells: Dictionary = {}
	var positions := PackedVector3Array()
	var headings := PackedVector3Array()
	# Player-driven, player-parked and driving-owned cars block a lane from any
	# heading: followers queue behind them even in the cheap distant tier.
	var fleet: Array[Node3D] = vehicles.duplicate()
	for car in player_fleet:
		if is_instance_valid(car) and not vehicles.has(car):
			fleet.append(car)
	var omni := PackedByteArray()
	var damaged := PackedByteArray()
	for i in fleet.size():
		var car := fleet[i] as Vehicle
		var point := car.global_position
		positions.append(point)
		damaged.append(int(not car.flat_tires.is_empty()))
		# A punctured car's body can yaw across its lane. Following priority is
		# still based on lane travel, not the temporary steering/skid direction.
		var heading: float = car._route_heading if not car.flat_tires.is_empty() else car.yaw
		headings.append(Vector3(sin(heading), 0, cos(heading)))
		# Player/police-driven, released and disabled cars may sit at any angle.
		omni.append(int(i >= vehicles.size() or car.player_controlled or car.player_released
			or not car.external_owner.is_empty() or car.external_released or car.disabled))
		var cell := Vector2i(floori(point.x / LEADER_CELL_SIZE), floori(point.z / LEADER_CELL_SIZE))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)
	leader_candidate_checks = 0
	leader_full_pair_checks = vehicles.size() * maxi(0, vehicles.size() - 1)
	for i in vehicles.size():
		var car := vehicles[i] as Vehicle
		car.leader_distance = INF
		if not car.external_owner.is_empty():
			continue # Police steer their own claimed car; it still leads others.
		var point := positions[i]
		var forward := headings[i]
		var right := forward.cross(Vector3.UP)
		var cell := Vector2i(floori(point.x / LEADER_CELL_SIZE), floori(point.z / LEADER_CELL_SIZE))
		for x in range(cell.x - 1, cell.x + 2):
			for z in range(cell.y - 1, cell.y + 2):
				var key := Vector2i(x, z)
				if not cells.has(key):
					continue
				for j in cells[key]:
					if j == i:
						continue
					leader_candidate_checks += 1
					var delta: Vector3 = positions[j] - point
					delta.y = 0
					var along := delta.dot(forward)
					if along <= 0 or along > 45.0:
						continue
					var corridor := 2.95 if damaged[i] != 0 or damaged[j] != 0 else 1.85
					if (forward.dot(headings[j]) < 0.60 and omni[j] == 0) or absf(delta.dot(right)) > corridor:
						continue
					car.leader_distance = minf(car.leader_distance, maxf(0, along - Vehicle.BODY_SIZE.z - 1.8))
	_update_emergency_leaders()

## A bounded external body registry, independent of fleet population/ownership.
## The hull is measured once; re-register after changing collision geometry.
func register_emergency_vehicle(body: Node3D) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or vehicles.has(body) or player_fleet.has(body):
		return false
	_prune_emergency_vehicles()
	if not emergency_vehicles.has(body) and emergency_vehicles.size() >= MAX_EMERGENCY_VEHICLES:
		return false
	var half := _emergency_bounds(body)
	if not half.is_finite() or half.x <= 0.0 or half.z <= 0.0:
		return false
	if not emergency_vehicles.has(body):
		emergency_vehicles.append(body)
	_emergency_half_extents[body.get_instance_id()] = half
	if is_instance_valid(level):
		_update_presence()
	_update_leaders()
	return true

func unregister_emergency_vehicle(body: Node3D) -> bool:
	if not is_instance_valid(body) or not emergency_vehicles.has(body):
		return false
	for node in _emergency_junctions.keys():
		if int(_emergency_junctions[node]) == body.get_instance_id():
			release_emergency_junction(body, str(node))
	emergency_vehicles.erase(body)
	_emergency_half_extents.erase(body.get_instance_id())
	if is_instance_valid(level):
		_update_presence()
	_update_leaders()
	return true

## The driver owns approach eligibility and rear clearance. These leases use
## ordinary traffic's existing admission check and never expire under a body.
func claim_emergency_junction(body: Node3D, node: String) -> bool:
	_prune_emergency_vehicles()
	if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion() \
		or not emergency_vehicles.has(body) or node.is_empty() or network == null or not network.nodes.has(node):
		return false
	var holder = reservations.get(node)
	if is_instance_valid(holder) and holder != body:
		return false
	var identity := body.get_instance_id()
	var owned := 0
	for key in _emergency_junctions:
		if int(_emergency_junctions[key]) == identity:
			if str(key) == node:
				return holder == body
			owned += 1
	if owned >= MAX_EMERGENCY_JUNCTIONS_PER_BODY:
		return false
	reservations[node] = body
	_emergency_junctions[node] = identity
	return true

func release_emergency_junction(body: Node3D, node: String) -> bool:
	if not is_instance_valid(body) or int(_emergency_junctions.get(node, 0)) != body.get_instance_id():
		return false
	_emergency_junctions.erase(node)
	if reservations.get(node) != body:
		return false
	reservations.erase(node)
	return true

func _prune_emergency_vehicles() -> void:
	for index in range(emergency_vehicles.size() - 1, -1, -1):
		if not is_instance_valid(emergency_vehicles[index]):
			emergency_vehicles.remove_at(index)
	# At most four entries: remove cached bounds for freed bodies as well.
	for identity in _emergency_half_extents.keys():
		if not is_instance_id_valid(int(identity)):
			_emergency_half_extents.erase(identity)
	for node in _emergency_junctions.keys():
		var identity := int(_emergency_junctions[node])
		var body = instance_from_id(identity) if is_instance_id_valid(identity) else null
		var holder = reservations.get(node)
		if not is_instance_valid(body) or not body.is_inside_tree() or not emergency_vehicles.has(body):
			if not is_instance_valid(holder) or holder == body:
				reservations.erase(node)
			_emergency_junctions.erase(node)
		elif holder != body:
			# Defensive cleanup must never remove a replacement ordinary holder.
			_emergency_junctions.erase(node)

func _emergency_bounds(body: Node3D) -> Vector3:
	var half := Vector3.ZERO
	var supplied: Variant = body.get_meta("traffic_obstacle_half_extents", Vector2.ZERO)
	if supplied is Vector2 and supplied.is_finite() and supplied.x > 0.0 and supplied.y > 0.0:
		half = Vector3(supplied.x, 0.0, supplied.y)
	var inverse := body.global_transform.affine_inverse()
	for child in body.find_children("*", "CollisionShape3D", true, false):
		var collider := child as CollisionShape3D
		if collider.shape == null or collider.disabled:
			continue
		var owner_body := collider.get_parent()
		while owner_body != null and not owner_body is CollisionObject3D:
			owner_body = owner_body.get_parent()
		if owner_body != body:
			continue # A separately owned passenger/child body is not this hull.
		var bounds := collider.shape.get_debug_mesh().get_aabb()
		var relative := inverse * collider.global_transform
		for corner in 8:
			var point: Vector3 = relative * bounds.get_endpoint(corner)
			half.x = maxf(half.x, absf(point.x))
			half.y = maxf(half.y, absf(point.y))
			half.z = maxf(half.z, absf(point.z))
	return half

func _emergency_projection(body: Node3D, axis: Vector3) -> float:
	var half: Vector3 = _emergency_half_extents[body.get_instance_id()]
	return absf(body.global_basis.x.dot(axis)) * half.x + absf(body.global_basis.y.dot(axis)) * half.y + absf(body.global_basis.z.dot(axis)) * half.z

func _update_emergency_leaders() -> void:
	if emergency_vehicles.is_empty():
		return
	_prune_emergency_vehicles()
	for entry in vehicles:
		var car := entry as Vehicle
		if not is_instance_valid(car) or not car.external_owner.is_empty():
			continue
		var heading := car._route_heading if not car.flat_tires.is_empty() else car.yaw
		var forward := Vector3(sin(heading), 0.0, cos(heading))
		var right := forward.cross(Vector3.UP)
		for body in emergency_vehicles:
			var delta := body.global_position - car.global_position
			var along := delta.dot(forward)
			var other_length := _emergency_projection(body, forward)
			var clearance := along - Vehicle.BODY_SIZE.z * .5 - other_length - 1.8
			if along + other_length <= -Vehicle.BODY_SIZE.z * .5 or clearance > 45.0:
				continue
			var corridor := Vehicle.BODY_SIZE.x * .5 + _emergency_projection(body, right) + .12
			if absf(delta.dot(right)) <= corridor:
				car.leader_distance = minf(car.leader_distance, maxf(0.0, clearance))

func _emergency_exit_clear(origin: Vector3, direction: Vector3, right: Vector3, car_half_width := Vehicle.BODY_SIZE.x * 0.5) -> bool:
	_prune_emergency_vehicles()
	for body in emergency_vehicles:
		var delta := body.global_position - origin
		var along := delta.dot(direction)
		var half_length := _emergency_projection(body, direction)
		if along + half_length > -5.0 and along - half_length < 13.0 \
			and absf(delta.dot(right)) < car_half_width + _emergency_projection(body, right) + 0.12:
			return false
	return true

func release_reservation(car: Node3D) -> void:
	if car.reservation_id != "" and reservations.get(car.reservation_id) == car:
		reservations.erase(car.reservation_id)
	car.reservation_id = ""
	car.connector_end_index = -1
	# Keep only the current lane, rather than accumulating an unbounded trip.
	if car.route_index > 1 and car.route_index < car.route.size():
		var compact: Array[Vector3] = []
		compact.assign(car.route.slice(car.route_index - 1))
		car.route = compact
		car.route_index = 1

func _exit_clear(car: Node3D, outgoing: int) -> bool:
	var points: Array[Vector3] = network.lanes[outgoing].points
	var direction := (points[1] - points[0]).normalized()
	var right := direction.cross(Vector3.UP)
	# The outgoing car will align with this lane. Use its cached prototype hull,
	# not the old combined fleet corridor plus another ambulance half-width.
	var half_width := Vehicle.BODY_SIZE.x * 0.5
	if car is Vehicle:
		var vehicle := car as Vehicle
		if vehicle._clearance_shape != null:
			half_width = vehicle._clearance_shape.size.x * 0.5 + absf(vehicle._clearance_center.x)
	# Keep the live fleet order (including overlaps), without copying either list.
	return _exit_fleet_clear(vehicles, car, points[0], direction, right) and _exit_fleet_clear(player_fleet, car, points[0], direction, right) \
		and (emergency_vehicles.is_empty() or _emergency_exit_clear(points[0], direction, right, half_width))

func _exit_fleet_clear(fleet: Array[Node3D], car: Node3D, origin: Vector3, direction: Vector3, right: Vector3) -> bool:
	for other in fleet:
		if other == car or not is_instance_valid(other):
			continue
		var delta: Vector3 = other.global_position - origin
		var along := delta.dot(direction)
		if along > -5 and along < 13 and absf(delta.dot(right)) < 2.0:
			return false
	return true

## Driving takes a stopped civilian car (or a player_fleet body) out of AI
## control: its junction reservation is released before the player moves it,
## and tick() no longer moves, coarse-ticks or recycles it.
func claim_vehicle(car: Node3D) -> bool:
	if not is_instance_valid(car) or car.get("player_controlled") == true:
		return false
	var owner_id = car.get("external_owner")
	if owner_id is String and not (owner_id as String).is_empty():
		return false # Police hold this car; the player cannot take it over.
	if vehicles.has(car):
		release_reservation(car)
		car.home_lane = car.lane_id
	car.begin_player_control()
	return true

## The player got out. The car stays parked where it stopped; AI cars queue
## behind it. A fleet car gets a fresh route from its home lane, so recycling
## (only once the player is >80m away and it is out of view) returns it as a
## new arrival. player_fleet bodies stay parked and are never recycled.
func release_vehicle(car: Node3D) -> void:
	if not is_instance_valid(car):
		return
	car.end_player_control()
	if not vehicles.has(car):
		return
	_reroute_home(car)

## Why `car` cannot be granted to an external owner ("" when it can). Only AI
## fleet cars qualify: never player, player-left, remembered or starter cars.
func can_claim_external(car, owner_id: String) -> String:
	if owner_id.is_empty():
		return "owner"
	if not is_instance_valid(car) or not car is Vehicle or not car.is_inside_tree():
		return "invalid"
	if not vehicles.has(car):
		return "not_fleet"
	if car.player_controlled:
		return "player"
	if car.player_released:
		return "player_released"
	if car.disabled:
		return "disabled"
	if not car.external_owner.is_empty():
		return "" if car.external_owner == owner_id else "owned"
	# A culled collider must not switch on inside a person, car or prop.
	if not car.near_physics and not car._hull_clear(car.global_transform, 0.0):
		return "clearance"
	return ""

## Police authority over one fleet car. Its junction reservation is released;
## AI ticks, coarse ticks and recycling stop; other cars still queue behind it
## and sweep against it. Idempotent for the same owner.
func claim_external_vehicle(car, owner_id: String) -> bool:
	if not can_claim_external(car, owner_id).is_empty():
		return false
	if car.external_owner == owner_id:
		return true
	# Neighbouring AI and parked colliders turn physical now, before the first
	# external sweep; a car that would then overlap one is refused instead.
	_update_presence_impl(car)
	if not car._hull_clear(car.global_transform, 0.0):
		_update_presence_impl()
		return false
	release_reservation(car)
	car.home_lane = car.lane_id
	car.begin_external_control(owner_id)
	_update_presence_impl()
	_presence_clock = 0.0
	external_claims += 1
	return true

## The owner lets go: the car parks exactly where it stopped and later returns
## to traffic through ordinary out-of-view recycling. Wrong owner → false.
func release_external_vehicle(car, owner_id: String) -> bool:
	if owner_id.is_empty() or not is_instance_valid(car) or not car is Vehicle or car.external_owner != owner_id:
		return false
	car.end_external_control()
	if vehicles.has(car):
		_reroute_home(car)
	external_releases += 1
	return true

func release_all_external_vehicles(owner_id: String) -> int:
	var released := 0
	for car in external_vehicles(owner_id):
		released += int(release_external_vehicle(car, owner_id))
	return released

func external_vehicles(owner_id := "") -> Array:
	var found: Array = []
	for car in vehicles:
		if is_instance_valid(car) and not car.external_owner.is_empty() and (owner_id.is_empty() or car.external_owner == owner_id):
			found.append(car)
	return found

func _reroute_home(car: Node3D) -> void:
	var lane: int = car.home_lane
	if network != null and lane >= 0 and lane < network.lanes.size() and bool(network.lanes[lane].enabled):
		var points: Array[Vector3] = network.lanes[lane].points
		var along := minf(14.0, float(network.lanes[lane].length) / 3.0)
		var path: Array[Vector3] = [network.point_at(points, along)]
		var distance := 0.0
		for i in range(1, points.size()):
			distance += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
			if distance > along + 0.01:
				path.append(points[i])
		if path.size() >= 2:
			car.route = path
			car.route_index = 1
			car.lane_id = lane
	car.next_lane_id = -1
	car.connector_end_index = -1
	car.stop_dwell = 0.0

func register_player_vehicle(car: Node3D) -> void:
	if is_instance_valid(car) and not player_fleet.has(car):
		player_fleet.append(car)
		car.set_presence(level.player.global_position if level != null and is_instance_valid(level.player) else car.global_position)

func unregister_player_vehicle(car: Node3D) -> void:
	player_fleet.erase(car)

## Called by each car before movement. Extending a route before its last point
## lets it flow through green/empty junctions without stopping at every node.
func control_distance(car: Node3D, dt: float) -> float:
	var began := Time.get_ticks_usec() if Vehicle.profile_queries else 0
	var result := _control_distance_impl(car as Vehicle, dt)
	if Vehicle.profile_queries:
		_profile_add("control_usec", began)
	return result

func _control_distance_impl(car: Vehicle, dt: float) -> float:
	if car.lane_id < 0:
		car.control_reason = "Waiting at traffic signal"
		var heading: float = car._route_heading if not car.flat_tires.is_empty() else car.yaw
		return signals.stopping_distance(car.route_position(), Vector3(sin(heading), 0, cos(heading)), Vehicle.BODY_SIZE.z * 0.5) if signals else INF
	if car.reservation_id != "":
		if car.route_index > car.connector_end_index:
			release_reservation(car)
		else:
			return INF
	var remaining: float = car.remaining_route_distance()
	var braking_horizon: float = car.speed * car.speed / (2.0 * car.effective_braking()) + car.speed * dt + 2.0
	if remaining > maxf(22.0, braking_horizon):
		return INF
	var lane: Dictionary = network.lanes[car.lane_id]
	var junction: Dictionary = network.nodes[lane.to]
	car.control_reason = "Yielding at junction"
	if bool(junction.signal) and signals.phase(str(lane.axis)) != "Green":
		car.control_reason = "Waiting at traffic signal"
		return remaining
	if bool(lane.stop) and car.stop_dwell < 0.8:
		car.control_reason = "Waiting at stop sign"
		if remaining < 0.12 and car.speed < 0.1:
			car.stop_dwell += dt
		return remaining
	# A follower must never acquire the zone from behind a waiting leader:
	# that leader would then wait on a reservation its owner cannot reach.
	# leader_distance is bumper clearance less the following buffer, so this
	# comparison includes the entire leading vehicle before the stop point.
	if car.leader_distance < remaining + 2.0:
		car.control_reason = "Following traffic to junction"
		return remaining
	if reservations.has(lane.to) and reservations[lane.to] != car:
		car.control_reason = "Yielding to junction reservation"
		return remaining
	if car.next_lane_id < 0:
		for option in network.choices(car.lane_id, car.route_sequence):
			var candidate: Array[Vector3] = network.connector(car.lane_id, option)
			if not candidate.is_empty():
				car.next_lane_id = option
				break
	if car.next_lane_id < 0:
		car.control_reason = "No supported connecting road"
		return remaining
	if not _exit_clear(car, car.next_lane_id):
		car.control_reason = "Waiting for outgoing lane"
		return remaining
	# Reserve only near the stop line; distant approaches cannot monopolize it.
	if remaining > maxf(7.0, car.speed * 1.2):
		return INF
	reservations[lane.to] = car
	car.reservation_id = str(lane.to)
	var connector: Array[Vector3] = network.connector(car.lane_id, car.next_lane_id)
	var extended: Array[Vector3] = car.route
	for i in range(1, connector.size()):
		extended.append(connector[i])
	var outgoing: Array[Vector3] = network.lanes[car.next_lane_id].points
	# Release when the rear bumper clears the connector, independent of curve
	# sample density. The first outgoing sample may now be less than a car away.
	car.connector_end_index = extended.size() - 1
	var exit_distance := 0.0
	var release_distance := Vehicle.BODY_SIZE.z * 0.5 + 0.5
	for i in range(1, outgoing.size()):
		extended.append(outgoing[i])
		if exit_distance < release_distance:
			car.connector_end_index = extended.size() - 1
			exit_distance += Vector2(outgoing[i].x - outgoing[i - 1].x, outgoing[i].z - outgoing[i - 1].z).length()
	car.lane_id = car.next_lane_id
	car.next_lane_id = -1
	car.route_sequence += 1
	car.stop_dwell = 0.0
	junction_transfers += 1
	return INF

func _center_at(distance: float) -> Vector3:
	var clamped := clampf(distance, 0.0, road_length)
	for i in range(1, _distances.size()):
		if clamped <= _distances[i]:
			var fraction := (clamped - _distances[i - 1]) / maxf(0.001, _distances[i] - _distances[i - 1])
			return road_points[i - 1].lerp(road_points[i], fraction)
	return road_points[-1]

func _lane_path(start: float, finish: float) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var direction := signf(finish - start)
	var count := maxi(2, int(ceil(absf(finish - start) / 7.0)))
	var offset := minf(2.1, road_width * 0.23)
	for i in range(count + 1):
		var along := lerpf(start, finish, float(i) / count)
		var point := _center_at(along)
		var ahead := _center_at(along + direction)
		var behind := _center_at(along - direction)
		var forward := Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()
		# Geographic right, east for northbound and west for southbound.
		var lane_right := forward.cross(Vector3.UP)
		path.append(point + lane_right * offset)
	return path

func on_road(point: Vector3, margin := 0.12) -> bool:
	if network:
		return network.on_road(point, margin)
	var p := Vector2(point.x, point.z)
	for i in range(1, road_points.size()):
		var a := Vector2(road_points[i - 1].x, road_points[i - 1].z)
		var b := Vector2(road_points[i].x, road_points[i].z)
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < road_width * 0.5 - margin:
			return true
	return false

func tick(dt: float) -> void:
	if signals:
		signals.tick(dt)
	_recycle_check += dt
	_control_clock += dt
	_presence_clock += dt
	if _control_clock >= 0.1:
		_update_leaders()
		_control_clock = 0.0
	if _presence_clock >= 0.25:
		_update_presence()
		_presence_clock = 0.0
	var coarse: Array[Node3D] = []
	far_damage_updates = 0
	for entry in vehicles:
		if is_instance_valid(entry):
			# Keep the public fleet compatible with scene/save APIs, but resolve
			# the script type once before the per-tick property/method accesses.
			var car := entry as Vehicle
			# The player's or police car: no AI motion, coarse damage ticks or recycling.
			if car.player_controlled or not car.external_owner.is_empty():
				car.far_damage_elapsed = 0.0
				continue
			if car.can_tick_damage_coarsely():
				car.far_damage_elapsed += dt
				coarse.append(car)
			else:
				car.far_damage_elapsed = 0.0
				car.tick(dt)
			if _recycle_check >= 2.0 and car.state in ["parked","blocked","disabled"]:
				car.try_recycle()
	if not coarse.is_empty():
		var start := _far_damage_cursor % coarse.size()
		for offset in coarse.size():
			var index := (start+offset)%coarse.size()
			var car := coarse[index] as Vehicle
			if float(car.far_damage_elapsed)<FAR_DAMAGE_INTERVAL:
				continue
			var elapsed := minf(float(car.far_damage_elapsed),.25)
			car.far_damage_elapsed -= elapsed
			car.tick(elapsed,true)
			far_damage_updates += 1
			_far_damage_cursor = index+1
			if far_damage_updates>=MAX_FAR_DAMAGE_UPDATES:
				break
	far_damage_peak_updates = maxi(far_damage_peak_updates,far_damage_updates)
	if _recycle_check >= 2.0:
		_recycle_check = 0.0

func get_status() -> Dictionary:
	var emergency_count := 0
	for body in emergency_vehicles:
		emergency_count += int(is_instance_valid(body))
	var driving := 0
	var stopped := 0
	var parked_count := 0
	var travelled := 0.0
	var honks := 0
	var recycled := 0
	var details: Array = []
	var streets: Dictionary = {}
	var police_count := 0
	var physics_count := 0
	var aggressive_count := 0
	var player_hits := 0
	var player_controlled := 0
	var external_controlled := 0
	var external_owners: Dictionary = {}
	var disabled := 0
	for car in vehicles:
		var status: Dictionary = car.get_status()
		details.append(status)
		if car.lane_id >= 0:
			streets[network.lanes[car.lane_id].street] = true
		player_controlled += int(car.player_controlled)
		disabled += int(car.disabled)
		if not car.external_owner.is_empty():
			external_controlled += 1
			external_owners[car.external_owner] = int(external_owners.get(car.external_owner, 0)) + 1
		police_count += int(car.is_police)
		physics_count += int(car.near_physics)
		aggressive_count += int(car.driver_style == "aggressive")
		player_hits += int(car.player_hits)
		travelled += float(status.distance_travelled)
		honks += int(status.honks)
		recycled += int(status.recycled)
		if str(status.state) == "parked":
			parked_count += 1
		elif str(status.state) == "driving":
			driving += 1
		else:
			stopped += 1
	return {"total": vehicles.size(), "driving": driving, "stopped": stopped, "parked": parked_count,
		"distance_travelled": travelled, "honks": honks, "recycled": recycled, "skipped_spawns": skipped_spawns,
		"street": "Neighborhood network", "streets": streets.size(), "police": police_count,
		"aggressive": aggressive_count, "cautious": vehicles.size() - aggressive_count, "player_hits": player_hits,
		"physics_cars": physics_count, "spawn_streets": spawn_street_counts, "junction_transfers": junction_transfers, "reservations": reservations.size(),
		"leader_candidate_checks": leader_candidate_checks, "leader_full_pair_checks": leader_full_pair_checks,
		"far_damage_updates": far_damage_updates, "far_damage_peak_updates": far_damage_peak_updates,
		"player_controlled": player_controlled, "player_fleet": player_fleet.size(),
		"external_controlled": external_controlled, "external_owners": external_owners, "disabled": disabled,
		"external_claims": external_claims, "external_releases": external_releases,
		"emergency_obstacles": emergency_count, "max_emergency_obstacles": MAX_EMERGENCY_VEHICLES,
		"network": network.get_status() if network else {}, "vehicles": details, "street_details": street_details,
		"signals": signals.get_status() if signals else {}, "parked_cars": parked.get_status() if parked else {}}
