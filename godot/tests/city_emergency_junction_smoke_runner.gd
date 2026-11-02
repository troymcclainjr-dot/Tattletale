extends Node
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const AmbulanceDriver := preload("res://scripts/city/city_ambulance_driver.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
class JunctionWorld extends Node3D:
	var level_data: Dictionary
	var traffic: Node3D
	func vector(value) -> Vector3: return Vector3(value[0], 0, value[2])
class WaitingCar extends Node3D:
	var yaw := -3.1221074927671
	var speed := 0.0
	var prototype_kind := ""
var passes := 0
var failures := 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[ems_junction] ", "PASS " if ok else "FAIL ", label)
func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var world := JunctionWorld.new()
	add_child(world)
	world.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(1200, 1, 1200)
	collider.shape = floor_shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	floor_body.position.y = -0.5
	await get_tree().physics_frame
	var network := Network.new()
	network.setup(world)
	var connector: Array[Vector3] = network.connector(0, 77)
	check(connector.size() > 3, "actual Wilsby to Dumbarton connector exists on physical test support")
	if connector.size() < 4:
		get_tree().quit(1)
		return
	var forward := (connector[1] - connector[0]).normalized()
	var points := PackedVector3Array([connector[0] - forward * 10.0])
	points.append_array(PackedVector3Array(connector))
	points = Lanes.resample(points, 1.0)
	var sums := Lanes.cumulative(points)
	var entry := {"s": 10.0, "exit_s": sums[-1], "node": "2634_-942", "center": Vector3(263.381, 0, -94.194), "radius": 8.75, "signal": false}
	var ambulance := AnimatableBody3D.new()
	ambulance.sync_to_physics = false # Match the production driver's explicit physics pose authority.
	world.add_child(ambulance)
	Collision.attach(ambulance, "minivan")


	var unit_body := ambulance
	unit_body.global_transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), connector[0] - forward)
	var traffic := Traffic.new()
	traffic.process_mode = Node.PROCESS_MODE_DISABLED
	traffic.network = network
	world.add_child(traffic)
	world.traffic = traffic
	traffic.register_emergency_vehicle(unit_body)
	var waiting := WaitingCar.new()
	world.add_child(waiting)
	waiting.prototype_kind = Catalog.traffic_kind(80)
	waiting.global_transform = Transform3D(Basis(Vector3.UP, waiting.yaw), Vector3(265.7643, 0.025, -89.82655))
	traffic.vehicles.append(waiting)
	var driver := AmbulanceDriver.new()
	driver.setup(world, traffic, null, unit_body)
	driver.set_leg(points, "return", 8.0, false, {"sums": sums, "junctions": [entry]})
	await get_tree().physics_frame
	check(driver._stationary_connector_conflict(entry, waiting), "actual waiting Car80 envelope blocks the actual Wilsby/Dumbarton turn")
	check(bool(driver._junction_state().get("yield", false)), "ambulance yields before entering occupied connector")
	var queries := int(driver.counters.rays)
	for i in 60:
		check_yield(driver, entry)
	check(int(driver.counters.rays) == queries, "connector grounding is cached across repeated stationary-car checks")
	check(bool(driver._junction_state().get("yield", false)), "six seconds of waiting never grants unsafe entry")
	waiting.position = Vector3(256, 0.025, -94)
	check(not driver._stationary_connector_conflict(entry, waiting), "stationary car beside the junction but outside swept turn does not block")
	check(not bool(driver._junction_state().get("yield", false)), "entry becomes available after conflicting car clears")
	# Verify the actual aligned hold pose leaves the opposing straight departure
	# corridor open through traffic's real emergency-obstacle query.
	var manager := Traffic.new()
	world.add_child(manager)
	manager.emergency_vehicles.append(unit_body)
	manager._emergency_half_extents[unit_body.get_instance_id()] = manager._emergency_bounds(unit_body)
	var outgoing_clear := false
	var outgoing_pose: Dictionary = {}
	var other_forward := Vector3(sin(waiting.yaw), 0, cos(waiting.yaw))
	for lane in network.lanes:
		if str(lane.from) != "2634_-942" or not bool(lane.enabled):
			continue
		var lane_points: Array = lane.points
		var lane_direction: Vector3 = (lane_points[1] - lane_points[0]).normalized()
		if lane_direction.dot(other_forward) < 0.8:
			continue
		outgoing_clear = manager._emergency_exit_clear(lane_points[0], lane_direction, lane_direction.cross(Vector3.UP))
		outgoing_pose = {"lane": lane.id, "start": lane_points[0], "waiting_ambulance": unit_body.global_transform, "clear": outgoing_clear}
		break
	print("[ems_junction] opposing departure ", JSON.stringify(outgoing_pose))
	check(outgoing_clear, "ordinary opposing traffic can depart while ambulance waits aligned before connector")
	_test_leases(driver, traffic, unit_body, waiting, points, sums, entry)
	var service := Emergency.new()
	world.add_child(service)
	service.level = world
	service.ambulance = unit_body
	service.driver = driver
	service._apply_route({"points": points, "sums": sums}, "respond", 11.0)
	check(driver.emergency, "response leg enables emergency mode")
	service._apply_route({"points": points, "sums": sums}, "return", 8.0)
	check(not driver.emergency, "return leg clears emergency lights and signal exemption")
	print("[ems_junction] COMPLETE ", passes, " passed; ", failures, " failed")
	get_tree().quit(1 if failures else 0)

func check_yield(driver, entry: Dictionary) -> void:
	if not driver._stationary_connector_conflict(entry, driver.traffic.vehicles[0]):
		failures += 1
		push_error("waiting collider stopped blocking without moving")
	driver._junction_state()

func _test_leases(driver, traffic, unit_body: Node3D, other: Node3D, points: PackedVector3Array, sums: PackedFloat64Array, entry: Dictionary) -> void:
	var node := str(entry.node)
	var initial := unit_body.global_transform
	driver.release_junctions()
	traffic.vehicles.clear()
	traffic.reservations[node] = other
	# A matching heading must not grant entry while a real car owns the node.
	other.rotation = unit_body.rotation
	driver.set_leg(points, "return", 8.0, false, {"sums": sums, "junctions": [entry]})
	check(bool(driver._junction_state().get("yield", false)) and traffic.reservations[node] == other,
		"ordinary holder denies ambulance entry without being overwritten")
	traffic.reservations.erase(node)
	check(not bool(driver._junction_state().get("yield", true)) and traffic.reservations.get(node) == unit_body,
		"clear approach claims the same traffic reservation before entry")
	check(not driver._crossing_traffic(entry), "ambulance does not mistake its own junction lease for crossing traffic")
	var lease: Dictionary = driver._junction_leases[node]
	var exit: Vector3 = lease.exit
	var outgoing: Vector3 = lease.outward
	unit_body.global_transform = Transform3D(Basis(Vector3.UP, atan2(outgoing.x, outgoing.z)), exit)
	driver._update_junction_leases()
	check(traffic.reservations.get(node) == unit_body, "center at connector end retains reservation for the rear overhang")
	driver.set_leg(PackedVector3Array([exit, exit + outgoing * 12.0]), "return", 8.0)
	check(traffic.reservations.get(node) == unit_body, "replanning inside an occupied junction keeps the shared owner")
	driver.clear_leg()
	check(traffic.reservations.get(node) == unit_body, "stopping inside junction does not release the occupied crossing")
	unit_body.global_position = exit + outgoing * (driver.half_length + 0.3)
	driver._update_junction_leases()
	check(traffic.reservations.get(node) == unit_body, "rear clearance includes body margin and half-metre separation")
	unit_body.global_position = exit + outgoing * (driver.half_length + 0.8)
	driver._update_junction_leases()
	check(not traffic.reservations.has(node), "physical rear clearance releases the matching owner")
	# A canceled approach whose nose has not entered can be released immediately.
	var inward: Vector3 = lease.inward
	unit_body.global_transform = Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), (lease.entry as Vector3) - inward * 6.0)
	driver.set_leg(points, "return", 8.0, false, {"sums": sums, "junctions": [entry]})
	driver._junction_state()
	check(traffic.reservations.get(node) == unit_body, "reservation is acquired on the clear six-metre approach")
	driver.clear_leg()
	check(not traffic.reservations.has(node), "canceling before the nose enters releases unused approach ownership")
	unit_body.global_transform = initial
	driver.set_leg(points, "return", 8.0, false, {"sums": sums, "junctions": [entry]})
	driver._junction_state()
	unit_body.global_position = entry.center
	driver._update_junction_leases()
	driver.clear_leg()
	check(traffic.reservations.get(node) == unit_body, "alternate-exit replan retains ownership while inside the crossing")
	unit_body.global_position = (entry.center as Vector3) - outgoing * (float(entry.radius) + driver.half_length + 1.2)
	driver._update_junction_leases()
	check(not traffic.reservations.has(node), "body fully beyond another junction boundary releases the old route lease")
	unit_body.global_transform = initial
	driver.set_leg(points, "return", 8.0, false, {"sums": sums, "junctions": [entry]})
	driver._junction_state()
	traffic.reservations["other_junction"] = other
	driver.release_junctions()
	check(not traffic.reservations.has(node) and traffic.reservations.get("other_junction") == other,
		"explicit reset release leaves unrelated ordinary ownership untouched")
	traffic.reservations.erase("other_junction")
