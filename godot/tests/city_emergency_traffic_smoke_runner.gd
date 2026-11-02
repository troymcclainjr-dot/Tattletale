extends Node
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
class Car:
	extends "res://scripts/city/city_vehicle.gd"
	func _activation_clear() -> bool:
		return true
class Level:
	extends Node3D
	var player: Node3D
class Parked:
	extends Node3D
	var centers := PackedVector3Array()
	func set_external_centers(value: PackedVector3Array, _radius: float) -> void:
		centers = value.duplicate()
	func get_status() -> Dictionary:
		return {}
var failures := 0
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[emergency_traffic] %s %s" % ["PASS" if ok else "FAIL", label])
func _body(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 16
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.6, 6.0)
	collider.shape = shape
	collider.position = Vector3(0, 1.3, .2)
	body.add_child(collider)
	add_child(body)
	return body
func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var level := Level.new()
	add_child(level)
	level.player = Node3D.new()
	level.add_child(level.player)
	var traffic := Traffic.new()
	level.add_child(traffic)
	traffic.level = level
	traffic.network = Network.new()
	traffic.parked = Parked.new()
	traffic.add_child(traffic.parked)
	for index in 90:
		var car := Car.new()
		traffic.add_child(car)
		car.traffic = traffic
		car.position = Vector3(1000 + index * 200, 0, 1000)
		car.model = Node3D.new()
		car.add_child(car.model)
		car.near_physics = false
		car.collision_layer = 0
		traffic.vehicles.append(car)
	var first: Car = traffic.vehicles[0]
	var ambulance := _body(first.position + Vector3(0, 0, 12))
	check(traffic.register_emergency_vehicle(ambulance), "register generic physical ambulance without Vehicle script")
	check(traffic.register_emergency_vehicle(ambulance) and traffic.emergency_vehicles.size() == 1, "duplicate registration is idempotent")
	check(traffic._emergency_half_extents[ambulance.get_instance_id()].is_equal_approx(Vector3(1.2, 2.6, 3.2)), "bounds include shifted compound-hull extent")
	check(is_equal_approx(first.leader_distance, 4.65), "far follower queues using ambulance hull length and normal buffer")
	check(first.near_physics and first.collision_layer == 16 and traffic.parked.centers.size() == 1, "ambulance activates live fleet and parked collision presence far from explorer")
	check(traffic.get_status().total == 90 and traffic.get_status().player_fleet == 0 and traffic.get_status().emergency_obstacles == 1, "emergency obstacle never contaminates90-car/player fleet population")
	ambulance.rotation.y = PI * .5
	ambulance.position = first.position + Vector3(3.5, 0, 10)
	traffic._update_leaders()
	check(is_finite(first.leader_distance), "sideways ambulance footprint blocks lane even when its center lies outside normal corridor")
	var outgoing: Array[Vector3] = [first.position + Vector3(0, 0, 10), first.position + Vector3(0, 0, 30)]
	traffic.network.lanes.assign([{"points": outgoing}])
	check(not traffic._exit_clear(first, 0), "live ambulance footprint blocks outgoing junction admission")
	ambulance.position.x += 20.0
	check(traffic._exit_clear(first, 0), "outgoing check observes ambulance motion immediately without waiting for leader refresh")
	# Narrow streets have opposing lane centres only 2.4 m apart. Aligned
	# envelopes fit; crossing or wider footprints must still block admission.
	first._attach_hull("compact")
	ambulance.rotation.y = 0.0
	ambulance.position = outgoing[0] + Vector3(2.4, 0, 0)
	check(traffic._exit_clear(first, 0), "opposing aligned centres 2.4 m apart remain clear when physical hulls fit")
	ambulance.rotation.y = PI * 0.5
	check(not traffic._exit_clear(first, 0), "same centres block when ambulance turns across the outgoing lane")
	ambulance.rotation.y = 0.0
	var wider := Car.new()
	traffic.add_child(wider)
	wider.position = first.position
	wider._attach_hull("minivan")
	var narrow_half: float = first._clearance_shape.size.x * 0.5 + absf(first._clearance_center.x)
	var wide_half: float = wider._clearance_shape.size.x * 0.5 + absf(wider._clearance_center.x)
	var actual_gap := wide_half + 1.2 + 0.12 - 0.02
	ambulance.position = outgoing[0] + Vector3(actual_gap, 0, 0)
	check(wide_half > narrow_half and traffic._exit_clear(first, 0) and not traffic._exit_clear(wider, 0), "requesting car uses actual compact/minivan collision width rather than one fleet constant")
	wider.free()
	var shape: BoxShape3D = ambulance.get_child(0).shape
	shape.size.x = 4.0
	traffic.register_emergency_vehicle(ambulance) # Geometry change refreshes cached bounds.
	ambulance.position = outgoing[0] + Vector3(2.4, 0, 0)
	check(not traffic._exit_clear(first, 0), "wide emergency hull still blocks aligned opposing lane when envelopes overlap")
	shape.size.x = 2.4
	traffic.register_emergency_vehicle(ambulance)
	check(traffic.vehicles.size() == 90 and traffic.player_fleet.is_empty(), "exit-width regression retains all 90 ordinary cars and separate emergency registry")
	ambulance.position = first.position + Vector3(0, 0, -10)
	traffic._update_leaders()
	check(is_inf(first.leader_distance), "ambulance wholly behind car does not create phantom leader")
	check(traffic.unregister_emergency_vehicle(ambulance), "explicit unregister succeeds")
	check(not first.near_physics and traffic.parked.centers.is_empty(), "unregister releases distant presence neighborhood immediately")
	check(not traffic.unregister_emergency_vehicle(ambulance), "second unregister is harmless")
	traffic.network.lanes.clear()
	var bodies: Array[Node3D] = []
	for index in Traffic.MAX_EMERGENCY_VEHICLES + 1:
		var body := _body(Vector3(3000 + index * 100, 0, 3000))
		bodies.append(body)
		var accepted := traffic.register_emergency_vehicle(body)
		check(accepted == (index < Traffic.MAX_EMERGENCY_VEHICLES), "registry capacity bound at entry%d" % index)
	bodies[0].free()
	traffic._update_leaders()
	traffic._update_presence()
	check(traffic.emergency_vehicles.size() == Traffic.MAX_EMERGENCY_VEHICLES - 1 and traffic._emergency_half_extents.size() == Traffic.MAX_EMERGENCY_VEHICLES - 1, "freed emergency body and cached bounds are pruned safely")
	check(traffic.register_emergency_vehicle(bodies[-1]), "freed capacity can be reused")
	check(not traffic.register_emergency_vehicle(first), "existing fleet identities cannot register a second time as emergency obstacles")
	for body in bodies:
		if is_instance_valid(body):
			traffic.unregister_emergency_vehicle(body)
			body.free()
	ambulance.free()
	check(traffic.emergency_vehicles.is_empty() and traffic._emergency_half_extents.is_empty(), "registry teardown leaves no retained identities")
	_junction_leases(traffic, first)
	level.free()
	print("[emergency_traffic] failures=%d" % failures)
	get_tree().quit(1 if failures else 0)

func _junction_leases(traffic: Traffic, car: Car) -> void:
	var incoming: Array[Vector3] = [Vector3(0, 0, -100), Vector3.ZERO]
	var outgoing: Array[Vector3] = [Vector3(0, 0, 10), Vector3(0, 0, 14), Vector3(0, 0, 100)]
	var connector: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 5), Vector3(0, 0, 10)]
	traffic.network.lanes.assign([
		{"points": incoming, "to": "junction", "axis": "old_york", "stop": false, "enabled": true},
		{"points": outgoing, "to": "exit", "axis": "old_york", "stop": false, "enabled": true}])
	traffic.network.nodes = {"junction": {"signal": false, "out": [1]},
		"exit": {"signal": false, "out": []}, "third": {"signal": false, "out": []}}
	traffic.network._connector_cache["0_1"] = connector
	car.position = Vector3(0, 0, -3)
	car.yaw = 0.0
	car.route = incoming.duplicate()
	car.route_index = 1
	car.lane_id = 0
	car.next_lane_id = -1
	car.reservation_id = ""
	car.connector_end_index = -1
	car.speed = 0.0
	car.stop_dwell = 0.0
	car.leader_distance = INF
	var ambulance := _body(Vector3(100, 0, 100))
	check(not traffic.claim_emergency_junction(ambulance, "junction"), "unregistered body cannot reserve a junction")
	traffic.register_emergency_vehicle(ambulance)
	check(not traffic.claim_emergency_junction(ambulance, "missing"), "emergency cannot reserve a nonexistent node")
	check(is_inf(traffic.control_distance(car, 1.0 / 60.0)) and traffic.reservations.get("junction") == car,
		"ordinary admission still acquires its normal junction reservation")
	check(not traffic.claim_emergency_junction(ambulance, "junction") and traffic.reservations.get("junction") == car,
		"emergency claim cannot steal a committed ordinary holder")
	traffic.release_reservation(car)
	car.route = incoming.duplicate()
	car.route_index = 1
	car.lane_id = 0
	car.next_lane_id = -1
	check(traffic.claim_emergency_junction(ambulance, "junction") and traffic.claim_emergency_junction(ambulance, "junction")
		and traffic._emergency_junctions.size() == 1, "registered emergency claim is exclusive and idempotent")
	traffic.network.lanes[0].stop = true
	check(is_finite(traffic.control_distance(car, 1.0 / 60.0)) and car.control_reason == "Waiting at stop sign",
		"shared emergency reservation preserves earlier stop-sign rule priority")
	traffic.network.lanes[0].stop = false
	car.leader_distance = 0.0
	check(is_finite(traffic.control_distance(car, 1.0 / 60.0)) and car.control_reason == "Following traffic to junction",
		"shared emergency reservation preserves earlier leader rule priority")
	car.leader_distance = INF
	check(is_finite(traffic.control_distance(car, 1.0 / 60.0)) and car.control_reason == "Yielding to junction reservation"
		and car.reservation_id.is_empty(), "ordinary controller yields to committed ambulance through existing reservation rule")
	check(traffic.claim_emergency_junction(ambulance, "exit") and not traffic.claim_emergency_junction(ambulance, "third"),
		"two close junctions can remain leased until rear clearance but a third is bounded")
	check(not traffic.release_emergency_junction(car, "junction") and traffic.reservations.get("junction") == ambulance,
		"another body cannot release the ambulance lease")
	ambulance.rotation.y = PI * 0.5
	car.yaw = PI
	check(Cruisers.forward_of(ambulance).is_equal_approx(Vector3.RIGHT) and Cruisers.forward_of(car).is_equal_approx(Vector3.FORWARD),
		"police reservation checks read generic body heading while retaining ordinary vehicle yaw")
	check(traffic.release_emergency_junction(ambulance, "junction") and not traffic.release_emergency_junction(ambulance, "junction"),
		"matching lease release is safe to repeat")
	car.yaw = 0.0
	check(is_inf(traffic.control_distance(car, 1.0 / 60.0)) and traffic.reservations.get("junction") == car,
		"ordinary traffic resumes admission after ambulance rear clearance")
	traffic.unregister_emergency_vehicle(ambulance)
	check(not traffic.reservations.has("exit") and traffic.reservations.get("junction") == car and traffic._emergency_junctions.is_empty(),
		"unregister removes emergency leases without disturbing an ordinary holder")
	traffic.release_reservation(car)
	traffic.register_emergency_vehicle(ambulance)
	traffic.claim_emergency_junction(ambulance, "junction")
	traffic.claim_emergency_junction(ambulance, "exit")
	# Defensive cleanup also preserves a valid replacement assigned by another owner.
	traffic.reservations["exit"] = car
	ambulance.free()
	traffic._prune_emergency_vehicles()
	check(not traffic.reservations.has("junction") and traffic.reservations.get("exit") == car and traffic._emergency_junctions.is_empty(),
		"freed emergency leases are pruned without erasing replacement ordinary ownership")
	traffic.reservations.erase("exit")
	check(traffic.vehicles.size() == 90 and traffic.player_fleet.is_empty(), "junction sharing preserves all 90 ordinary fleet identities")
