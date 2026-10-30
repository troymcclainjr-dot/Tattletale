extends Node3D
## Continuous neighborhood traffic. Directed lanes share exclusive junction
## reservations; distant cars retain cheap simulation without physics queries.

const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Signals := preload("res://scripts/city/city_street_signals.gd")
const ParkedCars := preload("res://scripts/city/city_parked_cars.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const TARGET_CARS := 72
var spawn_street_counts: Dictionary = {}
var network: RefCounted
var reservations: Dictionary = {}
var junction_transfers := 0
var _control_clock := 0.0
var _presence_clock := 0.0
var signals: Node3D
var parked: Node3D
var street_details: Dictionary = {}
var vehicles: Array[Node3D] = []
var level: Node3D
var road_points: Array[Vector3] = []
var road_width := 9.5
var road_length := 0.0
var _distances: Array[float] = []
var skipped_spawns := 0
var _recycle_check := 0.0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "NeighborhoodTraffic"
	street_details = CityDressing.build_street_network(level)
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
		return
	# A consistent south-to-north centerline; lane offsets then follow US traffic.
	if road_points[0].z < road_points[-1].z:
		road_points.reverse()
	_distances.append(0.0)
	for i in range(1, road_points.size()):
		road_length += Vector2(road_points[i].x - road_points[i - 1].x, road_points[i].z - road_points[i - 1].z).length()
		_distances.append(road_length)
	if road_length < 120.0:
		return
	network = Network.new()
	network.setup(level)
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
		add_child(car)
		var police := number in [5, 24, 43, 62]
		if car.setup(self, path, "neighborhood_%02d" % number, 8.0 + float(number % 6) * 0.5, number, police):
			car.lane_id = lane_id
			car.route_sequence = number
			vehicles.append(car)
			spawn_street_counts[street] = int(spawn_street_counts.get(street, 0)) + 1
			return true
		skipped_spawns += 1
		car.free()
	return false

func _update_presence() -> void:
	if not is_instance_valid(level.player):
		return
	for car in vehicles:
		car.set_presence(level.player.global_position)

func _update_leaders() -> void:
	# Only the narrow forward lane corridor matters. Sidewalk residents and
	# opposing traffic do not create phantom braking envelopes.
	for car in vehicles:
		car.leader_distance = INF
		var forward := Vector3(sin(car.yaw), 0, cos(car.yaw))
		for other in vehicles:
			if other == car:
				continue
			var delta: Vector3 = other.global_position - car.global_position
			delta.y = 0
			var along := delta.dot(forward)
			if along <= 0 or along > 45.0:
				continue
			var other_forward := Vector3(sin(other.yaw), 0, cos(other.yaw))
			if forward.dot(other_forward) < 0.60 or absf(delta.dot(forward.cross(Vector3.UP))) > 1.85:
				continue
			car.leader_distance = minf(car.leader_distance, maxf(0, along - Vehicle.BODY_SIZE.z - 1.8))

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
	for other in vehicles:
		if other == car:
			continue
		var delta: Vector3 = other.global_position - points[0]
		var along := delta.dot(direction)
		if along > -5 and along < 13 and absf(delta.dot(direction.cross(Vector3.UP))) < 2.0:
			return false
	return true

## Called by each car before movement. Extending a route before its last point
## lets it flow through green/empty junctions without stopping at every node.
func control_distance(car: Node3D, dt: float) -> float:
	if car.lane_id < 0:
		car.control_reason = "Waiting at traffic signal"
		return signals.stopping_distance(car.global_position, Vector3(sin(car.yaw), 0, cos(car.yaw)), Vehicle.BODY_SIZE.z * 0.5) if signals else INF
	if car.reservation_id != "":
		if car.route_index > car.connector_end_index:
			release_reservation(car)
		else:
			return INF
	var remaining: float = car.remaining_route_distance()
	if remaining > 22.0:
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
	car.connector_end_index = extended.size()
	var outgoing: Array[Vector3] = network.lanes[car.next_lane_id].points
	for i in range(1, outgoing.size()):
		extended.append(outgoing[i])
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
	if parked:
		parked.tick(dt)
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
	for car in vehicles:
		if is_instance_valid(car):
			car.tick(dt)
			if _recycle_check >= 2.0 and car.state == "parked":
				car.try_recycle()
	if _recycle_check >= 2.0:
		_recycle_check = 0.0

func get_status() -> Dictionary:
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
	for car in vehicles:
		var status: Dictionary = car.get_status()
		details.append(status)
		if car.lane_id >= 0:
			streets[network.lanes[car.lane_id].street] = true
		police_count += int(car.is_police)
		physics_count += int(car.near_physics)
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
		"physics_cars": physics_count, "spawn_streets": spawn_street_counts, "junction_transfers": junction_transfers, "reservations": reservations.size(),
		"network": network.get_status() if network else {}, "vehicles": details, "street_details": street_details,
		"signals": signals.get_status() if signals else {}, "parked_cars": parked.get_status() if parked else {}}
