extends Node
## Police cruisers in a controlled physics arena. Production law, cruiser
## manager, lane router, driver math, NPC actor, combat, player, vehicle and
## traffic network code run over a synthetic two-block street grid with real
## police and civilian cars. Only progression (a wallet), the driving seat state
## and the civic plan are stand-ins. Cruiser sections need the vehicle owner's
## external authority API (traffic.claim/release_external_vehicle,
## car.external_step/external_owner); without it they fail loudly, while the
## router, driver, crew-registry, seated-sight and offense sections still run.
## Run: python godot/tools/godot_run.py --timeout 420 -- --headless --script res://tests/city_police_cruisers_smoke.gd
const Law := preload("res://scripts/city/city_law.gd")
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const DT := 1.0 / 60.0
const ROAD_WIDTH := 14.0
## Interior of a closed room in the east block: hidden from every street.
const HIDEOUT := Vector3(45.0, 0.0, 30.0)
const SPAWN := Vector3(-45.0, 0.0, 30.0)
const CREW := ["patrol_officer_cruiser_1", "patrol_officer_cruiser_2"]

class ObservedTraffic:
	extends "res://scripts/city/city_traffic.gd"
	var release_events: Array[Dictionary] = []
	func release_external_vehicle(car, owner_id: String) -> bool:
		var released := super.release_external_vehicle(car, owner_id)
		if released:
			release_events.append({"vehicle": str(car.vehicle_id), "owner": owner_id})
			if release_events.size() > 64:
				release_events.pop_front()
		return released

class People:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func get_actor(id: String) -> Node3D:
		return actors.get(id)

class Wallet:
	extends Node
	var money := 900
	var debits: Array[Dictionary] = []
	func debit(amount: int, reason: String) -> int:
		var taken := clampi(amount, 0, money)
		money -= taken
		debits.append({"amount": amount, "taken": taken, "reason": reason})
		return taken

class Seat:
	extends Node
	var active := false
	var vehicle: Node3D
	func exit_vehicle(_force := false) -> bool:
		active = false
		return true

class Inspector:
	extends Node
	var active := false

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var combat: Node3D
	var law: Node
	var progression: Node
	var driving: Node
	var inspector: Node
	var traffic: Node3D
	var paused := false
	var level_data: Dictionary = {}
	var notices: Array[String] = []
	var _safe_position := Vector3.ZERO
	func vector(value) -> Vector3:
		if value is Vector3:
			return value
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	func ground_at(at: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at - Vector3.UP * 120.0, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)
	func show_notice(text: String) -> void:
		notices.append(text)

var arena: Arena
var player: CharacterBody3D
var npcs: People
var combat: Node3D
var law: Node
var wallet: Wallet
var seat: Seat
var traffic: Node3D
var network
var police: Array[Node3D] = []
var movers: Array[Node3D] = []
var extras: Array[Node] = []
var api := false
var failures := 0
var passes := 0
var finished := false
var frame := 0
var violations: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(600.0, true, false, true).timeout
	if not finished:
		check(false, "cruiser fixture completes within 600 s")
		_finish()

func check(ok: bool, label: String) -> bool:
	failures += int(not ok)
	passes += int(ok)
	print("[police] %s %s" % ["PASS" if ok else "FAIL", label])
	return ok

func note(text: String) -> void:
	print("[police] NOTE " + text)

func cruisers():
	return law.cruisers

func space() -> PhysicsDirectSpaceState3D:
	return arena.get_world_3d().direct_space_state

## One gameplay step in the root's order: combat, law (cruisers drive inside
## it), people, then the civilian cars this scenario moves.
func step(delta := DT) -> void:
	frame += 1
	if not arena.paused:
		combat.tick(delta)
	law.tick(delta)
	if not arena.paused:
		for actor in npcs.actors.values():
			if is_instance_valid(actor):
				actor.tick(delta)
		for car in movers:
			if is_instance_valid(car) and not owned(car):
				car.tick(delta)
		if frame % 5 == 0:
			_watch()
	await get_tree().physics_frame

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await step()

func advance_until(condition: Callable, limit: float) -> bool:
	for i in ceili(limit * 60.0):
		if bool(condition.call()):
			return true
		await step()
	return bool(condition.call())

## A car under external (police) authority. str(null) is "<null>", so test the field.
func owned(car) -> bool:
	var owner = car.get("external_owner") if is_instance_valid(car) else null
	return owner != null and not str(owner).is_empty()

## Invariants sampled during every scenario: claims, crew representation,
## carriageway, hull overlap. Each kind is reported once per section.
func _watch() -> void:
	var claimed := 0
	for car in police:
		if not owned(car):
			continue
		claimed += 1
		if not network.on_road(car.global_position, 0.0):
			if not violations.has("first_off_road_sample"):
				violations["first_off_road_sample"] = drive_sample(car)
			violations["off_road"] = "%s at %s" % [car.vehicle_id, car.global_position]
		for corner in Vehicle.ROAD_CORNERS:
			if not network.on_road(car.global_transform * corner, 0.0):
				if not violations.has("road_envelope"):
					violations["road_envelope"] = drive_sample(car)
				break
		if car.global_position.y > 0.12:
			violations["curb"] = "%s at height %.2f" % [car.vehicle_id, car.global_position.y]
		if hull_overlaps(car, 2 | 4 | 16):
			violations["overlap"] = "%s overlaps a wall, the player or a car at %s" % [car.vehicle_id, car.global_position]
	if claimed > Cruisers.MAX_CRUISERS:
		violations["claims"] = "%d police cars claimed" % claimed
	for id in CREW:
		var actor = npcs.actors.get(id)
		var entry := crew_entry(id)
		if not is_instance_valid(actor) or entry.is_empty():
			violations["crew_missing"] = id
			continue
		var state := str(entry.state)
		if state in ["seated", "station"] and (actor.enabled or actor.visible or actor.collision_layer != 0):
			violations["crew_double"] = "%s is %s but has a visible or physical body" % [id, state]
		if state == "foot" and (not actor.enabled or not actor.visible):
			violations["crew_ghost"] = "%s is on foot without a body" % id
		if state == "dead" and actor.enabled:
			violations["crew_resurrected"] = id
	var bodies := 0
	for child in npcs.get_children():
		bodies += int(str(child.name) == CREW[0] or str(child.name) == CREW[1])
	if bodies != 2:
		violations["crew_bodies"] = "%d crew bodies" % bodies

func section_clean(label: String) -> void:
	check(violations.is_empty(), "%s: claims, crew bodies, carriageway and hulls stay valid %s" % [label, str(violations)])
	violations.clear()

func crew_entry(id: String) -> Dictionary:
	for entry in cruisers().crew:
		if str(entry.id) == id:
			return entry
	return {}

func unit_of(car) -> Dictionary:
	for unit in cruisers().units.values():
		if unit.car == car:
			return unit
	return {}

## Bounded failure diagnostics only; never reads the hidden player's position.
func drive_sample(car: Node3D) -> Dictionary:
	var unit := unit_of(car)
	var contact: Dictionary = car.last_drive_contact
	var collider = contact.get("collider")
	var nearby: Array = []
	var path: PackedVector3Array = unit.get("path", PackedVector3Array())
	var cursor := int(unit.get("cursor", 0))
	for i in range(maxi(0, cursor - 3), mini(path.size(), cursor + 6)):
		nearby.append(path[i])
	return {"frame": frame, "position": car.global_position, "yaw": car.yaw, "speed": car.speed,
		"controls": car._drive_input.duplicate(), "mode": unit.get("mode", "released"),
		"s": unit.get("s", 0.0), "lateral": unit.get("lateral", 0.0), "remaining": unit.get("remaining", 0.0),
		"obstacle": unit.get("obstacle", INF), "obstacle_kind": unit.get("obstacle_kind", ""),
		"blocked_time": unit.get("blocked_time", 0.0), "pass_tried": unit.get("pass_tried", false),
		"reverse_left": unit.get("reverse_left", 0.0), "reverse_to_s": unit.get("reverse_to_s", 0.0),
		"reverse_moved": unit.get("reverse_moved", 0.0), "unstick": unit.get("unstick", 0),
		"replans": unit.get("replans", 0), "want_plan": unit.get("want_plan", false), "nearby_path": nearby,
		"blocked": unit.get("last_blocked", ""),
		"passes": cruisers().counters.passes, "contacts": cruisers().counters.contacts,
		"drive_contacts": car.drive_contacts, "contact_kind": contact.get("kind", ""),
		"contact_speed": contact.get("speed", 0.0), "contact_position": contact.get("position", Vector3.ZERO),
		"contact_body": str(collider.name) if is_instance_valid(collider) and collider is Node else "none"}

func first_unit() -> Dictionary:
	for unit in cruisers().units.values():
		return unit
	return {}

func hull_overlaps(car: Node3D, mask: int) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.margin = 0.0
	query.exclude = [car.get_rid()]
	for part in car.collision_parts:
		query.shape = part.shape
		query.transform = car.global_transform
		if not space().intersect_shape(query, 1).is_empty():
			return true
	return false

func capsule_clear(actor: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.capsule.shape
	query.transform = actor.global_transform * actor.capsule.transform
	query.collision_mask = 2 | 4 | 8 | 16
	query.exclude = [actor.get_rid()]
	return space().intersect_shape(query, 1).is_empty()

func box(at: Vector3, size: Vector3, layer := 2, heading := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	arena.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, heading), at)
	return body

func spawn(id: String, cast: String, at: Vector3, facing: Vector3) -> CharacterBody3D:
	var actor := Actor.new()
	npcs.add_child(actor)
	actor.build(arena, id, cast, "Neighbor")
	actor.global_position = at
	actor.yaw = atan2(facing.x, facing.z)
	actor.puppet.g.rotation.y = actor.yaw
	npcs.actors[id] = actor
	extras.append(actor)
	return actor

func dismiss() -> void:
	law.reset_state()
	for state in combat._active.values().duplicate():
		combat._release(state)
	for state in combat._panic.values().duplicate():
		combat._release(state)
	for node in extras:
		if is_instance_valid(node):
			if node.get("actor_id") != null:
				npcs.actors.erase(node.actor_id)
			if node is Node3D and traffic.vehicles.has(node):
				traffic.vehicles.erase(node)
			node.queue_free()
	extras.clear()
	movers.clear()
	seat.active = false
	seat.vehicle = null
	await advance(0.1)
	home_police()
	await advance(0.05)

func put_player(at: Vector3) -> void:
	if player.is_seated():
		player.leave_vehicle(at, 0.0)
	player.global_position = at + Vector3.UP * 0.02
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.enabled = true
	if combat != null:
		combat.downed = 0.0
		combat.health = 100.0

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

# --------------------------------------------------------------- lanes and cars

func lane_by(street: String, direction: Vector3, near := Vector3.INF) -> int:
	var best := -1
	var best_distance := INF
	for lane in network.lanes:
		if not bool(lane.enabled) or str(lane.street) != street:
			continue
		var points: Array = lane.points
		var heading := Vector3(points[-1].x - points[0].x, 0.0, points[-1].z - points[0].z).normalized()
		if heading.dot(direction) < 0.9:
			continue
		var middle: Vector3 = (points[0] as Vector3).lerp(points[-1], 0.5)
		var distance := 0.0 if not near.is_finite() else Lanes.flat(middle, near)
		if distance < best_distance:
			best_distance = distance
			best = int(lane.id)
	return best

func lane_point(lane: int, along: float) -> Vector3:
	var points: Array[Vector3] = network.lanes[lane].points
	return network.point_at(points, along)

func lane_route(lane: int, along: float) -> Array[Vector3]:
	var points: Array[Vector3] = network.lanes[lane].points
	var path: Array[Vector3] = [network.point_at(points, along)]
	var distance := 0.0
	for i in range(1, points.size()):
		distance += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
		if distance > along + 0.01:
			path.append(points[i])
	return path

func make_car(id: String, lane: int, along: float, is_police: bool, cruise := 8.0) -> Node3D:
	var path := lane_route(lane, along)
	var car := Vehicle.new()
	car.name = id
	car.position = traffic.to_local(path[0])
	traffic.add_child(car)
	if not car.setup(traffic, path, id, cruise, 4 if not is_police else 5, is_police):
		car.free()
		return null
	car.lane_id = lane
	car.honk_cooldown = 1000.0
	traffic.vehicles.append(car)
	car.set_presence(car.global_position)
	return car

## Test setup only (no claim held): put an idle car back on a lane, at rest.
func reset_car(car: Node3D, lane: int, along: float) -> void:
	var path := lane_route(lane, along)
	var at: Vector3 = path[0]
	var ahead := lane_point(lane, along + 1.0)
	var heading := atan2(ahead.x - at.x, ahead.z - at.z)
	car.global_transform = Transform3D(Basis(Vector3.UP, heading), at)
	car.yaw = heading
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.drive_velocity = Vector3.ZERO
	car.drive_steer = 0.0
	car.route = path
	car.route_index = 1
	car.lane_id = lane
	car._route_position = at
	car._route_heading = heading
	car.leader_distance = INF
	car._obstacle_distance = INF
	car._obstacle_clock = 0.0
	car._drive_heights = PackedFloat32Array()
	car.reset_physics_interpolation()

func along_of(lane: int, at: Vector3) -> float:
	return float(cruisers().lanes.project(lane, at).along)

## Idle police cars back to known spots (no claim is held between sections):
## A on Middle Avenue heading north, B and C far south on South Street.
func home_police() -> void:
	if police.size() < 3:
		return
	reset_car(police[0], lane_by("Middle Avenue", Vector3(0, 0, 1)), 15.0)
	reset_car(police[1], lane_by("South Street", Vector3(1, 0, 0), Vector3(-45, 0, -70)), 20.0)
	reset_car(police[2], lane_by("South Street", Vector3(-1, 0, 0), Vector3(45, 0, -70)), 20.0)

## Recovery tests intentionally start with one dispatchable car; after it is
## claimed, alternatives become eligible to exercise the fallback itself.
func limit_dispatch_to(car: Node3D) -> Dictionary:
	var previous := {}
	for other in police:
		if other == car:
			continue
		var id := str(other.vehicle_id)
		previous[id] = cruisers()._failed_cars.get(id)
		cruisers()._failed_cars[id] = INF
	return previous

func restore_dispatch_candidates(previous: Dictionary) -> void:
	for id in previous:
		if previous[id] == null:
			cruisers()._failed_cars.erase(id)
		else:
			cruisers()._failed_cars[id] = previous[id]

# --------------------------------------------------------------- run

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(420, 1, 420), 1)
	_build_hideout()
	arena.level_data = {"spawn": {"position": [SPAWN.x, SPAWN.y, SPAWN.z], "yaw": 0.0}, "roads": [
		{"name": "North Street", "width": ROAD_WIDTH, "points": [[-90, 0, 70], [0, 0, 70], [90, 0, 70]]},
		{"name": "South Street", "width": ROAD_WIDTH, "points": [[-90, 0, -70], [0, 0, -70], [90, 0, -70]]},
		{"name": "West Avenue", "width": ROAD_WIDTH, "points": [[-90, 0, -70], [-90, 0, 70]]},
		{"name": "Middle Avenue", "width": ROAD_WIDTH, "points": [[0, 0, -70], [0, 0, 70]]},
		{"name": "East Avenue", "width": ROAD_WIDTH, "points": [[90, 0, -70], [90, 0, 70]]}]}
	await get_tree().physics_frame
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	npcs = People.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	wallet = Wallet.new()
	arena.add_child(wallet)
	arena.progression = wallet
	seat = Seat.new()
	arena.add_child(seat)
	arena.driving = seat
	var inspector := Inspector.new()
	arena.add_child(inspector)
	arena.inspector = inspector
	traffic = ObservedTraffic.new()
	traffic.name = "StreetTraffic"
	arena.add_child(traffic)
	traffic.level = arena
	network = Network.new()
	network.setup(arena)
	traffic.network = network
	arena.traffic = traffic
	put_player(SPAWN)
	var lanes_ok := _network_section()
	if lanes_ok:
		for spec in [["police_a", "Middle Avenue", Vector3(0, 0, 1), Vector3(0, 0, 0), 15.0],
				["police_b", "South Street", Vector3(1, 0, 0), Vector3(-45, 0, -70), 20.0],
				["police_c", "South Street", Vector3(-1, 0, 0), Vector3(45, 0, -70), 20.0]]:
			var car := make_car(str(spec[0]), lane_by(str(spec[1]), spec[2], spec[3]), float(spec[4]), true)
			if car != null:
				police.append(car)
		check(police.size() == 3, "three real police cars stand on fixture lanes")
	var renderer := traffic.get_node_or_null("MovingVehicleRenderLOD")
	if renderer != null:
		renderer.set_process(false)
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	arena.combat = combat
	law = Law.new()
	arena.add_child(law)
	arena.law = law
	law.setup(arena)
	law.use_level_notices = false
	# Production timing scaled down so the fixture stays short; logic is unchanged.
	law.report_delay_min = 0.6
	law.report_delay_max = 1.0
	law.lost_sight_seconds = 1.5
	law.search_seconds = [2.5, 3.0, 3.0, 3.0]
	law.cooldown_seconds = [0.0, 2.0, 2.0, 2.0]
	law.return_speed = 3.0
	law.stage_seconds = {"down": 0.4, "hands_up": 0.4, "fade_out": 0.3, "fade_in": 0.3}
	combat.player_defeated.connect(law.on_player_defeated)
	await advance(0.2)
	var focused_section := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--police-section="):
			focused_section = argument.trim_prefix("--police-section=")
	if not focused_section.is_empty():
		if check(focused_section in ["structure", "follow", "close_queue", "boxed_dispatch", "mobile_dispatch"] and lanes_ok and police.size() == 3
			and bool(cruisers().get_status().available), "focused %s fixture is ready" % focused_section):
			if focused_section == "structure":
				await _structure_reroute_section()
			elif focused_section == "close_queue":
				await _close_queue_section()
			elif focused_section == "boxed_dispatch":
				await _boxed_dispatch_section()
			elif focused_section == "mobile_dispatch":
				await _boxed_dispatch_section(true)
			else:
				await _follow_and_pass_section()
		_finish()
		return
	_driver_section()
	await _steering_convention_section()
	if lanes_ok:
		_router_section()
	_crew_section()
	await _seated_sight_section()
	await _vehicle_offense_section()
	api = traffic.has_method("claim_external_vehicle") and traffic.has_method("release_external_vehicle") \
		and not police.is_empty() and police[0].has_method("external_step") and police[0].get("external_owner") != null
	if not check(api, "vehicle owner's external authority API is present (claim/release_external_vehicle, external_step, external_owner)"):
		note("cruiser behaviour sections skipped: %s" % str(cruisers().get_status().reason))
	elif not lanes_ok or police.size() < 3:
		check(false, "cruiser sections need the fixture network and three police cars")
	else:
		check(bool(cruisers().get_status().available), "cruiser manager reports itself available")
		await _dispatch_last_known_section()
		await _witnessed_dismount_arrest_section()
		await _follow_and_pass_section()
		await _close_queue_section()
		await _boxed_dispatch_section()
		await _boxed_dispatch_section(true)
		await _junction_yield_section()
		await _structure_reroute_section()
		await _seated_pursuit_section()
		await _two_cruiser_cap_section()
		await _dead_crew_section()
		await _disabled_car_section()
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	print("[police] %d passed; %d failed" % [passes, failures])
	if is_instance_valid(arena):
		arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _build_hideout() -> void:
	for spec in [[Vector3(0, 1.5, -3.6), Vector3(7.6, 3, 0.4)], [Vector3(0, 1.5, 3.6), Vector3(7.6, 3, 0.4)],
			[Vector3(-3.6, 1.5, 0), Vector3(0.4, 3, 7.6)], [Vector3(3.6, 1.5, 0), Vector3(0.4, 3, 7.6)],
			[Vector3(0, 3.2, 0), Vector3(7.6, 0.4, 7.6)]]:
		box(HIDEOUT + Vector3(spec[0]), spec[1])

# --------------------------------------------------------------- pure sections

func _network_section() -> bool:
	var status: Dictionary = network.get_status()
	return check(int(status.enabled_lanes) >= 10, "synthetic grid yields directed lanes (%d enabled of %d, %d rejected)" %
		[int(status.enabled_lanes), int(status.lanes), int(status.rejected_lanes)])

func _driver_section() -> void:
	# Facing +Z the car's left is +X: an aim there needs a left (negative) steer.
	check(Driver.steer_toward(Vector3.ZERO, 0.0, 8.0, Vector3(4, 0, 12)) < -0.05, "an aim to the left steers left")
	check(Driver.steer_toward(Vector3.ZERO, 0.0, 8.0, Vector3(-4, 0, 12)) > 0.05, "an aim to the right steers right")
	check(absf(Driver.steer_toward(Vector3.ZERO, 0.0, 8.0, Vector3(0, 0, 12))) < 0.01, "straight ahead needs no steer")
	var hold: Dictionary = Driver.pedals(0.0, 0.0)
	check(bool(hold.handbrake) and float(hold.brake) == 0.0 and float(hold.throttle) == 0.0,
		"a stopped car holds on the handbrake (brake at rest would reverse)")
	var slow: Dictionary = Driver.pedals(10.0, 3.0)
	check(float(slow.brake) > 0.0 and float(slow.throttle) == 0.0, "above the target speed it brakes")
	var go: Dictionary = Driver.pedals(0.0, 9.0)
	check(float(go.throttle) > 0.3 and float(go.brake) == 0.0, "below the target speed it accelerates")
	var rolling_back: Dictionary = Driver.pedals(-1.5, 6.0)
	check(float(rolling_back.throttle) > 0.0 and float(rolling_back.brake) == 0.0, "rolling backward is stopped with throttle, never more reverse")
	var straight := PackedVector3Array()
	var bend := PackedVector3Array()
	for i in 20:
		straight.append(Vector3(0, 0, i))
		var angle := float(i) / 6.0
		bend.append(Vector3(6.0 - 6.0 * cos(angle), 0, 6.0 * sin(angle)))
	var flat_limits := Driver.curve_limits(straight, 4.5, 14.0)
	var bend_limits := Driver.curve_limits(bend, 4.5, 14.0)
	var slowest := INF
	for value in bend_limits.slice(3, 16):
		slowest = minf(slowest, value)
	check(flat_limits[10] >= 13.99 and slowest < 6.0 and slowest > 4.0, "a 6 m bend caps speed near sqrt(4.5 x 6) (%.2f), a straight does not" % slowest)
	check(is_equal_approx(Driver.stop_speed(10.0, 5.0), 10.0) and Driver.stop_speed(-1.0, 5.0) == 0.0, "stopping profile v = sqrt(2 a d), never negative")

## The steering convention is checked against the production swept physics
## (player_step, which external_step shares by contract), not against itself.
func _steering_convention_section() -> void:
	var lane := lane_by("West Avenue", Vector3(0, 0, 1))
	if lane < 0:
		check(false, "steering convention needs a fixture lane")
		return
	var car := make_car("steer_probe", lane, 30.0, false)
	if not check(car != null, "steering probe car stands on West Avenue"):
		return
	extras.append(car)
	var yaw_before := float(car.yaw)
	var aim: Vector3 = car.global_position + Vector3(sin(yaw_before), 0, cos(yaw_before)) * 12.0 + Vector3(cos(yaw_before), 0, -sin(yaw_before)) * 5.0
	var steer := Driver.steer_toward(car.global_position, yaw_before, 0.0, aim)
	car.begin_player_control()
	for i in 45:
		car.player_step(DT, 0.6, 0.0, steer, false)
		await get_tree().physics_frame
	check(angle_difference(yaw_before, float(car.yaw)) > 0.02, "pure pursuit toward a point on the car's left turns the real car left (yaw %.3f -> %.3f)" % [yaw_before, float(car.yaw)])
	car.end_player_control()
	await dismiss()

func _router_section() -> void:
	var router = cruisers().lanes
	var status: Dictionary = network.get_status()
	check(router.lane_count() == int(status.enabled_lanes), "the cruiser router indexes every enabled lane once")
	var start_lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	var start := lane_point(start_lane, 5.0)
	var goal := Vector3(98.0, 0.0, 0.0)
	var plan: Dictionary = router.plan(start, Vector3(0, 0, 1), goal, start_lane, 5.0)
	if not check(bool(plan.ok), "a lane route reaches another street (%s)" % str(plan.get("reason", ""))):
		return
	var points: PackedVector3Array = plan.points
	var on_road := true
	var wrong_way := 0
	for i in points.size():
		on_road = on_road and network.on_road(points[i], 0.4)
	for i in range(0, points.size() - 2, 2):
		var travel := Vector3(points[i + 2].x - points[i].x, 0, points[i + 2].z - points[i].z)
		var lane := _nearest_lane_direction(points[i])
		if float(lane.distance) < 0.6 and travel.length() > 0.5 and travel.normalized().dot(lane.direction) < 0.5:
			wrong_way += 1
	check(on_road, "every path sample stays on the carriageway")
	check(wrong_way == 0, "on every lane the path runs in that lane's direction of travel (%d wrong-way samples)" % wrong_way)
	check(Lanes.flat(points[points.size() - 1], goal) < 10.0, "the path stops on the lane beside the goal (%.1f m)" % Lanes.flat(points[points.size() - 1], goal))
	check(not (plan.junctions as Array).is_empty(), "turning onto another street passes recorded junctions")
	var spacing_ok := true
	for i in range(1, points.size() - 1):
		spacing_ok = spacing_ok and absf(Lanes.flat(points[i - 1], points[i]) - Lanes.SPACING) < 0.06
	check(spacing_ok, "paths are resampled at a uniform 1 m spacing")
	# Avoiding a blocked street: the same request takes a different, longer way.
	var used := -1
	for segment in plan.segments:
		if str(segment.kind) == "lane" and int(segment.lane) != start_lane:
			used = int(segment.lane)
			break
	if used >= 0:
		router.block(used, 0.0)
		var detour: Dictionary = router.plan(start, Vector3(0, 0, 1), goal, start_lane, 5.0, PackedVector3Array(), 1000.0, 1.0)
		var avoided := bool(detour.ok)
		for segment in detour.get("segments", []):
			avoided = avoided and int(segment.lane) != used
		check(avoided and float(detour.length) > float(plan.length), "a blocked street is avoided by a longer valid route (%.0f m vs %.0f m)" % [float(detour.get("length", 0.0)), float(plan.length)])
		var later: Dictionary = router.plan(start, Vector3(0, 0, 1), goal, start_lane, 5.0, PackedVector3Array(), 1000.0, 100.0)
		check(bool(later.ok) and absf(float(later.length) - float(plan.length)) < 1.0, "the block expires and the short route returns")
	var nowhere: Dictionary = router.plan(Vector3(150, 0, 150), Vector3(0, 0, 1), goal)
	check(not bool(nowhere.ok), "a car far off the network gets no guessed route")
	var far: Dictionary = router.plan(start, Vector3(0, 0, 1), goal, start_lane, 5.0, PackedVector3Array(), 20.0)
	check(not bool(far.ok), "a route longer than its limit is refused")

func _nearest_lane_direction(point: Vector3) -> Dictionary:
	var best := {"distance": INF, "direction": Vector3.ZERO}
	for lane in network.lanes:
		if not bool(lane.enabled):
			continue
		var points: Array = lane.points
		for i in range(1, points.size()):
			var a: Vector3 = points[i - 1]
			var b: Vector3 = points[i]
			var closest := Geometry3D.get_closest_point_to_segment(Vector3(point.x, 0, point.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
			var distance := Vector2(closest.x - point.x, closest.z - point.z).length()
			if distance < float(best.distance):
				best = {"distance": distance, "direction": Vector3(b.x - a.x, 0, b.z - a.z).normalized()}
	return best

func _crew_section() -> void:
	var status: Dictionary = law.get_status().cruisers
	var ids: Array = []
	for entry in status.get("crew", []):
		ids.append(str(entry.id))
	check(ids == CREW, "two dedicated crew identities are registered (%s)" % str(ids))
	for id in CREW:
		var actor = npcs.actors.get(id)
		check(is_instance_valid(actor) and not actor.enabled and not actor.visible and actor.collision_layer == 0 and not actor.dead,
			"%s waits seated out of sight: disabled, invisible, no collider" % id)
	var dispatchable := 0
	for actor in law._police():
		dispatchable += int(str(actor.actor_id).begins_with(Cruisers.CREW_PREFIX))
	check(dispatchable == 0 and int(law.get_status().responder_count) == 0, "seated crews are neither witnesses nor foot responders")
	var count := npcs.actors.size()
	var again := Cruisers.new()
	again.setup(law, arena)
	check(npcs.actors.size() == count and again.crew.size() == 2 and again.crew[0].actor == npcs.actors[CREW[0]],
		"setting up again reuses the same identities instead of duplicating officers")

func _seated_sight_section() -> void:
	var lane := lane_by("West Avenue", Vector3(0, 0, 1))
	var back := lane_by("West Avenue", Vector3(0, 0, -1))
	if not check(lane >= 0 and back >= 0, "seated-sight lanes exist on West Avenue"):
		return
	var car := make_car("player_ride", lane, 50.0, false)
	var other := make_car("parked_between", back, 50.0, false)
	if not check(car != null and other != null, "seated-sight cars stand on West Avenue"):
		return
	extras.append(car)
	extras.append(other)
	# Move the second car out of the line first; it becomes the occluder later.
	var aside: Vector3 = other.global_position
	other.global_position = aside + Vector3(0, 0, 40)
	var officer_at: Vector3 = car.global_position + Vector3(14.0, 0.0, 0.0)
	var officer := spawn("patrol_officer_7", "cop_dan", officer_at, car.global_position - officer_at)
	await advance(0.1)
	seat.active = true
	seat.vehicle = car
	player.enter_vehicle(car)
	var eye: Vector3 = officer.global_position + Vector3.UP * Law.EYE_HEIGHT
	var occupant: Vector3 = car.global_transform * Law.OCCUPANT_LOCAL
	var only_officer: Array[RID] = [officer.get_rid()]
	var raw := PhysicsRayQueryParameters3D.create(eye, occupant, Law.SIGHT_MASK, only_officer)
	var first := space().intersect_ray(raw)
	check(not first.is_empty() and first.collider == car, "a plain ray to the driver's seat is stopped by the player's own car")
	check(law._sees_player(eye, officer.get_rid()), "excluding only that car, the officer sees the seated player")
	var middle: Vector3 = car.global_position.lerp(officer_at, 0.5)
	var wall := box(Vector3(middle.x, 1.5, middle.z), Vector3(0.4, 3.0, 8.0))
	await advance(0.05)
	check(not law._sees_player(eye, officer.get_rid()), "a wall between still hides the seated player")
	wall.free()
	other.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(middle.x, car.global_position.y, middle.z))
	await advance(0.05)
	check(not law._sees_player(eye, officer.get_rid()), "another car between still hides the seated player")
	# The witness scan uses the same rule: a crash seen by police identifies the
	# driver; behind the other car it is unobserved.
	var scans: int = law.witness_scans
	law.on_offense("vehicle_collision", car.global_position + Vector3(0, 0, 3), "civilian_bumper")
	await advance_until(func(): return law.witness_scans > scans, 0.6)
	check(law.wanted == 0 and str(law.last_scan.get("outcome", "")) == "unobserved", "a crash behind another car is unobserved: no heat (%s)" % str(law.last_scan.get("outcome", "")))
	other.global_transform = Transform3D(Basis(Vector3.UP, other.yaw), aside + Vector3(0, 0, 40))
	await advance(0.05)
	scans = law.witness_scans
	law.on_offense("vehicle_collision", car.global_position + Vector3(0, 0, 3), "civilian_bumper")
	await advance_until(func(): return law.witness_scans > scans, 0.6)
	check(law.wanted == 1 and absf(law.heat - Law.SEVERITY.vehicle_collision) < 0.01 and (law.last_scan.observed as Array).has("patrol_officer_7"),
		"a police witness of a seated driver's crash identifies them at collision severity (heat %.1f)" % law.heat)
	check(law.last_seen_seated, "the sighting records that the suspect was driving")
	player.leave_vehicle(car.global_position + Vector3(-3.5, 0, 0), 0.0)
	seat.active = false
	seat.vehicle = null
	await dismiss()

func _vehicle_offense_section() -> void:
	var at := Vector3(-60.0, 0.0, 20.0)
	put_player(at)
	var victim := spawn("civ_struck", "mama", at + Vector3(0, 0, 2.0), Vector3(0, 0, -1))
	var bystander := spawn("civ_bystander", "granny", at + Vector3(6, 0, 4), Vector3(-6, 0, -4))
	await advance(0.1)
	law.on_offense("vehicle_assault", victim.global_position, "civ_struck")
	check(law.wanted == 0, "a struck pedestrian's call is not instant police knowledge")
	var filed: bool = await advance_until(func(): return law.wanted > 0, 2.5)
	check(filed and absf(law.heat - Law.SEVERITY.vehicle_assault) < 0.01 and law.wanted == 1,
		"a witnessed vehicle assault is reported at its severity (heat %.1f, wanted %d)" % [law.heat, law.wanted])
	await dismiss()
	put_player(at)
	victim = spawn("civ_watcher", "mama", at + Vector3(4, 0, 4), Vector3(-4, 0, -4))
	await advance(0.1)
	law.on_offense("vehicle_collision", at + Vector3(0, 0, 2.5), "neighborhood_99")
	await advance(1.0)
	check(str(law.last_scan.get("outcome", "")) == "civilian_ignored" and law.wanted == 0 and int(law.get_status().pending_reports) == 0,
		"a single crash seen by a bystander is not phoned in (%s)" % str(law.last_scan.get("outcome", "")))
	# Separate crashes (each scanned on its own) within ten seconds: a rampage.
	law.on_offense("vehicle_collision", at + Vector3(0, 0, 3.5), "neighborhood_91")
	await advance(1.0)
	check(law.wanted == 0 and str(law.last_scan.get("outcome", "")) == "civilian_ignored", "a second crash is still not a rampage")
	law.on_offense("vehicle_collision", at + Vector3(0, 0, 4.5), "neighborhood_93")
	var reported: bool = await advance_until(func(): return law.wanted > 0, 2.5)
	check(reported, "a third crash within ten seconds is phoned in as a rampage")
	await dismiss()
	put_player(Vector3(-55, 0, 0))
	await advance(0.1)
	var unseen: int = law.unobserved_offenses
	law.on_offense("vehicle_collision", Vector3(-55, 0, 2), "neighborhood_98")
	await advance(0.6)
	check(law.unobserved_offenses == unseen + 1 and law.heat == 0.0, "an unwitnessed crash adds no heat")
	if not police.is_empty():
		check(law._offense_severity("vehicle_collision", str(police[0].vehicle_id)) == Law.POLICE_RAM_SEVERITY and
			law._offense_severity("vehicle_collision", "neighborhood_98") == Law.SEVERITY.vehicle_collision,
			"ramming a police car is graded above denting a neighbor's")
	await dismiss()

# --------------------------------------------------------------- cruiser sections

## A civilian's report sends the nearest cruiser to where the offender was;
## the hidden player is never tracked. The officer searches on foot, the
## incident cools down, the officer walks back, gets in and the car is released.
func _dispatch_last_known_section() -> void:
	var a: Node3D = police[0]
	home_police()
	var scene := Vector3(9.5, 0.0, 12.0)
	put_player(scene)
	spawn("civ_caller", "mama", scene + Vector3(3, 0, 3), Vector3(-3, 0, -3))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var claimed: bool = await advance_until(func(): return not first_unit().is_empty(), 3.0)
	if not check(claimed and law.wanted == 1, "a filed report claims a cruiser under external authority"):
		await dismiss()
		return
	var unit := first_unit()
	check(unit.car == a and str(a.external_owner) == "law_cruiser_1" and bool(a.get_meta("police_emergency", false)),
		"the nearest police car is claimed with emergency lights (%s)" % str(a.vehicle_id))
	check(str(police[1].external_owner).is_empty() and str(police[2].external_owner).is_empty(), "tier 1 claims exactly one cruiser")
	check(str(crew_entry(CREW[0]).state) == "seated" and not npcs.actors[CREW[0]].visible, "its officer rides seated and unseen")
	var known: Vector3 = law.last_known_position
	check(Lanes.flat(known, scene) < 2.0, "the goal is the report position")
	# Lambdas capture locals by value: accumulate into a shared dictionary.
	var seen := {"leaked": false, "nearest": INF}
	var out_to_search := func() -> bool:
		var current := first_unit()
		if current.is_empty():
			return false
		seen.leaked = bool(seen.leaked) or Lanes.flat(Vector3(current.goal), HIDEOUT) < 8.0 or Lanes.flat(law.last_known_position, HIDEOUT) < 8.0
		seen.nearest = minf(float(seen.nearest), Lanes.flat(a.global_position, scene))
		return str(current.mode) == "dismounted"
	var dismounted: bool = await advance_until(out_to_search, 30.0)
	check(not bool(seen.leaked), "neither the cruiser goal nor law's last known position ever follows the hidden player")
	check(dismounted and float(seen.nearest) < 14.0, "the cruiser reaches the reported spot (%.1f m) and the officer gets out to search" % float(seen.nearest))
	var officer: CharacterBody3D = npcs.actors[CREW[0]]
	if dismounted:
		check(officer.enabled and officer.visible and capsule_clear(officer) and Lanes.flat(officer.global_position, a.global_position) < 3.6,
			"the officer stands beside the stopped car in a clear capsule-checked spot")
		var state: Dictionary = law._responders.get(CREW[0], {})
		check(bool(state.get("crew", false)) and str(state.get("purpose", "")) == "wanted", "the officer is a normal law responder now")
		check(absf(float(a.speed)) < 0.3, "the cruiser waits stopped while its officer is out")
	var escaped: bool = await advance_until(func(): return law.wanted == 0, 30.0)
	check(escaped, "with nobody seeing the player the incident cools down")
	var released: bool = await advance_until(func(): return str(a.external_owner).is_empty(), 45.0)
	check(released and str(crew_entry(CREW[0]).state) == "station" and not officer.enabled,
		"the officer walks back, gets in, the car drives off and is released (%s)" % str(cruisers().counters))
	check(int(cruisers().counters.remounts) >= 1 and int(cruisers().counters.releases) >= 1, "remount and release were counted")
	check(not law.get_status().busy, "checkpoints are allowed again once every claim is released")
	section_clean("dispatch and last known")
	await dismiss()

## The cruiser crew itself witnesses an assault: it pursues at once, stops
## near the visible player and its officer gets out into a clear slot (the
## wall on the driver's side forces the passenger door). Surrender (G) to that
## officer arrests the player and every claim is released behind the fade.
func _witnessed_dismount_arrest_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 30.0)
	var scene := Vector3(9.5, 0.0, a.global_position.z + 14.0)
	put_player(scene)
	var victim := spawn("civ_hit", "granny", scene + Vector3(0, 0, 1.2), Vector3(0, 0, -1))
	await advance(0.1)
	var police_reports: int = int(law.report_sources.police)
	law.on_offense("assault", victim.global_position, "civ_hit")
	var seen: bool = await advance_until(func(): return not first_unit().is_empty() and law.wanted > 0, 1.5)
	check(seen and int(law.report_sources.police) == police_reports + 1 and int(cruisers().counters.witnessed) >= 1,
		"a crew that watched the assault identifies the offender and pursues")
	var dismounted: bool = await advance_until(func(): return str(first_unit().get("mode", "")) == "dismounted", 15.0)
	var officer: CharacterBody3D = npcs.actors[CREW[0]]
	check(dismounted and Lanes.flat(a.global_position, scene) <= Cruisers.DISMOUNT_RANGE + 2.0, "the cruiser stops near the visible suspect and the officer gets out")
	if dismounted:
		check(capsule_clear(officer), "the officer stands in a clear slot")
	var ready: bool = await advance_until(func(): return bool(law.get_status().surrender_available), 6.0)
	if not check(ready, "the officer on foot can take a surrender"):
		await dismiss()
		return
	var arrests: int = law.arrests
	check(law.handle_input(key(KEY_G)) and law.recovering, "G surrenders to the cruiser officer")
	var done: bool = await advance_until(func(): return not law.recovering, 5.0)
	check(done and law.arrests == arrests + 1, "the arrest completes once")
	check(cruisers().claimed_count() == 0 and str(a.external_owner).is_empty() and not officer.enabled,
		"relocation behind the fade releases every claim and re-seats the officer")
	section_clean("witnessed dismount and arrest")
	await dismiss()

## A stopped car in the lane: the cruiser stops behind it, then passes along
## the clear opposing side, never touching it.
func _follow_and_pass_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 5.0)
	var stalled := make_car("stalled_civilian", lane, 45.0, false)
	if not check(stalled != null, "a stalled civilian car blocks the cruiser's lane"):
		return
	extras.append(stalled)
	var scene := Vector3(9.5, 0.0, 50.0)
	put_player(scene)
	spawn("civ_caller_north", "mama", scene + Vector3(3, 0, -3), Vector3(-3, 0, 3))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var contacts_before := int(cruisers().counters.contacts)
	var passes_before := int(cruisers().counters.passes)
	var track := {"closest": INF, "waited": false, "hull_overlap": false, "closest_sample": {}, "samples": [], "last_frame": -60}
	var past := func() -> bool:
		track.hull_overlap = bool(track.hull_overlap) or hull_overlaps(a, 2 | 4 | 16)
		if frame - int(track.last_frame) >= 60 and track.samples.size() < 40:
			track.samples.append(drive_sample(a))
			track.last_frame = frame
		# Longitudinal following clearance applies before the pass is planned.
		# During the diagonal transition a projected fleet-envelope gap can be
		# negative while the real hulls remain safely separated laterally.
		var gap := along_of(lane, stalled.global_position) - along_of(lane, a.global_position) - Vehicle.BODY_SIZE.z
		if int(cruisers().counters.passes) == passes_before and absf(a.global_position.x - stalled.global_position.x) < 1.5 and gap > -Vehicle.BODY_SIZE.z:
			if gap < float(track.closest):
				track.closest_sample = drive_sample(a)
			track.closest = minf(float(track.closest), gap)
			track.waited = bool(track.waited) or (gap < 6.0 and absf(float(a.speed)) < 0.3)
		return along_of(lane, a.global_position) > along_of(lane, stalled.global_position) + 6.0
	var passed: bool = await advance_until(past, 35.0)
	var safe_stop := bool(track.waited) and float(track.closest) > 0.4
	var clear_manoeuvre := int(cruisers().counters.contacts) == contacts_before and not bool(track.hull_overlap)
	check(safe_stop, "the cruiser stopped behind the stalled car without touching it (closest gap %.2f m)" % float(track.closest))
	check(passed and int(cruisers().counters.passes) > passes_before, "then passed it along the clear opposing side")
	check(clear_manoeuvre, "the entire approach and pass has no contacts or hull overlaps")
	if not safe_stop or not passed or not clear_manoeuvre:
		note("follow/pass diagnostic: %s" % str(track))
	section_clean("follow and pass")
	await dismiss()

## A newly claimed cruiser is already closer than the pass ramp permits.
## Real external physics must back out safely before passing; waiting at a
## zero target speed forever or counting an artificial teleport cannot pass.
func _close_queue_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 20.0)
	# Placement queries must see the reset pose, not its previous 15 m pose
	# (which coincides with the intended rear blocker's 14.3 m position).
	await advance(0.05)
	var stalled := make_car("close_queue_civilian", lane, 20.0 + Cruisers.CAR_LENGTH + 1.86, false)
	if not check(stalled != null, "close queue has a real stalled car at 1.86 m initial clearance"):
		return
	extras.append(stalled)
	var rear := make_car("close_queue_rear", lane, 20.0 - Cruisers.CAR_LENGTH - 1.0, false)
	if not check(rear != null, "close queue initially has real traffic one metre behind"):
		return
	extras.append(rear)
	var scene := Vector3(9.5, 0.0, 50.0)
	put_player(scene)
	spawn("civ_caller_close_queue", "mama", scene + Vector3(3, 0, -3), Vector3(-3, 0, 3))
	await advance(0.1)
	var candidates := limit_dispatch_to(a)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	await advance_until(func(): return owned(a), 3.0)
	restore_dispatch_candidates(candidates)
	var contacts_before := int(cruisers().counters.contacts)
	var passes_before := int(cruisers().counters.passes)
	var start := a.global_position
	var track := {"backed": false, "closest": INF, "hull_overlap": false, "samples": [], "last_frame": -60}
	var observe := func() -> void:
		track.hull_overlap = bool(track.hull_overlap) or hull_overlaps(a, 2 | 4 | 16)
		if frame - int(track.last_frame) >= 60 and track.samples.size() < 48:
			track.samples.append(drive_sample(a))
			track.last_frame = frame
		var unit := unit_of(a)
		if not unit.is_empty() and float(unit.odometer) > .25 and along_of(lane, a.global_position) < along_of(lane, start) - .25:
			track.backed = true
		if int(cruisers().counters.passes) == passes_before:
			var gap := along_of(lane, stalled.global_position) - along_of(lane, a.global_position) - Vehicle.BODY_SIZE.z
			track.closest = minf(float(track.closest), gap)
	var recovered := func() -> bool:
		observe.call()
		return bool(track.backed)
	# Trigger the production watchdog with both directions physically blocked.
	# Its reverse sweep must hold rather than touching the traffic behind.
	for index in int((Cruisers.PASS_WAIT + 4.0) / DT):
		await step()
		observe.call()
	var blocked_unit := unit_of(a)
	check(not blocked_unit.is_empty() and int(blocked_unit.unstick) > 0
		and a.global_position.distance_to(start) < .1 and not bool(track.hull_overlap)
		and int(cruisers().counters.contacts) == contacts_before,
		"close queue watchdog holds safely when rear traffic prevents reversal")
	traffic.vehicles.erase(rear)
	extras.erase(rear)
	rear.queue_free()
	await step()
	check(await advance_until(recovered, 7.0), "close queue starts a real safe reverse within seven seconds")
	var passed := func() -> bool:
		observe.call()
		return along_of(lane, a.global_position) > along_of(lane, stalled.global_position) + 6.0
	var completed: bool = await advance_until(passed, 40.0)
	check(completed and int(cruisers().counters.passes) > passes_before,
		"close queue recovery creates room and passes the stationary car")
	check(float(track.closest) >= .4 and not bool(track.hull_overlap) and int(cruisers().counters.contacts) == contacts_before,
		"close queue preserves at least 0.4 m approach clearance and no contact or hull overlap")
	if not bool(track.backed) or not completed or bool(track.hull_overlap):
		note("close queue diagnostic: %s" % str(track))
	section_clean("close queue recovery")
	await dismiss()

## A permanently boxed cruiser must release its dispatch to a real alternative.
func _boxed_dispatch_section(prefer_mobile := false) -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 20.0)
	# Keep the alternative farther from the report so the boxed car is selected
	# first, but give it an unobstructed northbound street to make real progress.
	reset_car(police[1], lane_by("West Avenue", Vector3(0, 0, 1)), 15.0)
	await advance(0.05)
	var front := make_car("boxed_dispatch_front", lane, 20.0 + Cruisers.CAR_LENGTH + 1.86, false)
	var rear := make_car("boxed_dispatch_rear", lane, 20.0 - Cruisers.CAR_LENGTH - 1.0, false)
	if not check(front != null and rear != null, "boxed dispatch has real front and rear blockers"):
		return
	extras.append(front)
	extras.append(rear)
	# Across the map: outside FOOT_RANGE, requiring a vehicle replacement.
	var scene := Vector3(9.5, 0.0, 65.0)
	put_player(scene)
	spawn("civ_caller_boxed", "mama", scene + Vector3(3, 0, -3), Vector3(-3, 0, 3))
	await advance(0.1)
	var claims_before := int(cruisers().counters.claims)
	var fallbacks_before := int(cruisers().counters.blocked_dispatches)
	var contacts_before := int(cruisers().counters.contacts)
	var candidates := {} if prefer_mobile else limit_dispatch_to(a)
	traffic._update_leaders()
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var claimed: bool = await advance_until(func(): return not first_unit().is_empty(), 3.0)
	check(claimed and (not owned(a) if prefer_mobile else owned(a)),
		"farther clear car is selected before the nearest boxed car" if prefer_mobile else "boxed car is the original real dispatch")
	restore_dispatch_candidates(candidates)
	var start := a.global_position
	var progress := {"replacement": "", "distance": 0.0, "original_moved": 0.0}
	var replaced := func() -> bool:
		progress.original_moved = maxf(float(progress.original_moved), a.global_position.distance_to(start))
		for unit in cruisers().units.values():
			if unit.car != a and owned(unit.car) and float(unit.odometer) > 1.0:
				progress.replacement = str(unit.vehicle_id)
				progress.distance = float(unit.odometer)
		return not str(progress.replacement).is_empty() and not owned(a)
	var responded: bool = await advance_until(replaced, Cruisers.PASS_WAIT + Cruisers.REVERSE_SECONDS + 5.0)
	check(responded and int(cruisers().counters.claims) >= claims_before + (1 if prefer_mobile else 2)
		and int(cruisers().counters.blocked_dispatches) == fallbacks_before + (0 if prefer_mobile else 1),
		"mobile dispatch physically responds without a failed boxed-car recovery" if prefer_mobile else
		"boxed dispatch safely releases and another real cruiser physically responds within the recovery bound")
	check(float(progress.original_moved) < .1 and int(cruisers().counters.contacts) == contacts_before,
		"boxed original never moves into either blocker or records a collision")
	var reclaimed := false
	for index in 600:
		await step()
		reclaimed = reclaimed or owned(a)
	check(not reclaimed and (prefer_mobile or not cruisers()._eligible(a)),
		"boxed car is not needlessly claimed while a mobile unit responds" if prefer_mobile else
		"boxed car cooldown prevents immediate reclaim or dispatch oscillation")
	if not responded:
		note("boxed dispatch diagnostic: %s %s" % [str(progress), str(cruisers().get_status())])
	section_clean("boxed dispatch fallback")
	await dismiss()

## Crossing traffic: the cruiser yields at the junction to a car driving
## through it and enters after it has gone.
func _junction_yield_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 55.0)
	var scene := Vector3(40.0, 0.0, 79.0)
	put_player(scene)
	spawn("civ_caller_corner", "mama", scene + Vector3(-3, 0, -2), Vector3(3, 0, 2))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var claimed: bool = await advance_until(func(): return not first_unit().is_empty(), 3.0)
	if not check(claimed, "a cruiser responds toward the junction"):
		await dismiss()
		return
	var yields_before := int(cruisers().counters.yields)
	var scene_state := {"crossing": null, "closest": INF}
	var cleared := func() -> bool:
		var unit := first_unit()
		if unit.is_empty():
			return false
		if scene_state.crossing == null:
			var entry := INF
			for junction in unit.junctions:
				entry = minf(entry, float(junction.s))
			if entry - float(unit.s) < 24.0:
				scene_state.crossing = _crossing_car()
		var crossing = scene_state.crossing
		if is_instance_valid(crossing):
			scene_state.closest = minf(float(scene_state.closest), crossing.global_position.distance_to(a.global_position))
		return a.global_position.z > 66.0 and is_instance_valid(crossing) and crossing.global_position.x < -10.0
	var through: bool = await advance_until(cleared, 25.0)
	check(scene_state.crossing != null and int(cruisers().counters.yields) > yields_before, "the cruiser yielded to the car crossing its junction")
	check(through and float(scene_state.closest) > 2.5, "both cars cleared the junction without contact (closest %.1f m)" % float(scene_state.closest))
	section_clean("junction yield")
	await dismiss()

## A civilian car on a manual straight route along North Street's westbound
## side, through the junction the cruiser is about to enter.
func _crossing_car() -> Node3D:
	var start := Vector3(18.0, 0.0, 70.0 - 2.235)
	var route: Array[Vector3] = [start, Vector3(-40.0, 0.0, 70.0 - 2.235)]
	var car := Vehicle.new()
	car.name = "cross_traffic"
	car.position = traffic.to_local(start)
	traffic.add_child(car)
	if not car.setup(traffic, route, "cross_traffic", 7.0, 2, false):
		car.free()
		return null
	car.lane_id = -1
	car.honk_cooldown = 1000.0
	car.speed = 6.5
	traffic.vehicles.append(car)
	car.set_presence(car.global_position)
	extras.append(car)
	movers.append(car)
	return car

## A wall across the street the route turns into: the cruiser sees it, stops
## short, backs out of the turn and takes another street, never touching it.
func _structure_reroute_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 40.0)
	var wall := box(Vector3(30.0, 1.5, 70.0), Vector3(0.6, 3.0, ROAD_WIDTH))
	extras.append(wall)
	var scene := Vector3(60.0, 0.0, 79.0)
	put_player(scene)
	spawn("civ_caller_far", "mama", scene + Vector3(-3, 0, -2), Vector3(3, 0, 2))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var contacts_before := int(cruisers().counters.contacts)
	var unsticks_before := int(cruisers().counters.unsticks)
	var replans_at_unstick := {"value": -1}
	var trace := {"samples": [], "events": [], "last_frame": -60, "last_state": "", "wall_contact": false}
	var away := func() -> bool:
		var sample := drive_sample(a)
		trace.wall_contact = bool(trace.wall_contact) or a.last_drive_contact.get("collider") == wall
		if frame - int(trace.last_frame) >= 60 and trace.samples.size() < 65:
			trace.samples.append(sample)
			trace.last_frame = frame
		var state := "%s/%s/%s/%s/%s/%s" % [str(sample.mode), str(float(sample.reverse_left) > 0.0),
			str(sample.replans), str(sample.drive_contacts), str(sample.unstick), str(sample.blocked)]
		if state != str(trace.last_state) and trace.events.size() < 48:
			trace.events.append(sample)
			trace.last_state = state
		var current := first_unit()
		if current.is_empty():
			return false
		if int(replans_at_unstick.value) < 0 and int(cruisers().counters.unsticks) > unsticks_before:
			replans_at_unstick.value = int(current.replans)
		return int(replans_at_unstick.value) >= 0 and int(current.replans) > int(replans_at_unstick.value) and float(current.s) > 15.0
	var rerouted: bool = await advance_until(away, 60.0)
	check(rerouted, "the blocked turn is backed out of and a new street is taken")
	check(int(cruisers().counters.contacts) == contacts_before, "the cruiser stopped short of the wall instead of hitting it")
	if not rerouted or int(cruisers().counters.contacts) != contacts_before:
		note("structure trajectory diagnostic: %s" % str(trace))
	var unit := first_unit()
	if not unit.is_empty():
		var crosses := false
		for point in unit.path:
			crosses = crosses or (absf(point.x - 30.0) < 1.5 and absf(point.z - 70.0) < ROAD_WIDTH * 0.5)
		check(not crosses, "the new path does not pass the wall")
	section_clean("structure reroute")
	await dismiss()

## The player drives off: the cruiser sees the occupant through its own and
## the player's windows (other cars still hide them), follows on the lane,
## stops behind the stopped car and the officer gets out.
func _seated_pursuit_section() -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 5.0)
	var ride := make_car("getaway", lane, 40.0, false)
	if not check(ride != null, "the player's getaway car stands ahead of the cruiser"):
		return
	extras.append(ride)
	var scene: Vector3 = ride.global_position + Vector3(6.0, 0, 2.0)
	put_player(scene)
	spawn("civ_caller_car", "mama", scene + Vector3(3, 0, 3), Vector3(-3, 0, -3))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	seat.active = true
	seat.vehicle = ride
	ride.begin_player_control()
	player.enter_vehicle(ride)
	var chase := {"gap": INF, "frames": 0}
	# The test drives the getaway car along its lane (the player's own physics),
	# then stops it; the cruiser only knows what its crew sees.
	var stopped_behind := func() -> bool:
		chase.frames = int(chase.frames) + 1
		var driving := int(chase.frames) < 200
		var aim := lane_point(lane, along_of(lane, ride.global_position) + 8.0)
		var rolling := absf(float(ride.speed)) > 0.4
		ride.player_step(DT, 0.45 if driving else 0.0, 0.6 if not driving and rolling else 0.0,
			Driver.steer_toward(ride.global_position, float(ride.yaw), float(ride.speed), aim), not driving and not rolling)
		player.follow_vehicle()
		if not first_unit().is_empty():
			chase.gap = minf(float(chase.gap), ride.global_position.distance_to(a.global_position) - Vehicle.BODY_SIZE.z)
		return str(first_unit().get("mode", "")) == "dismounted"
	var followed: bool = await advance_until(stopped_behind, 30.0)
	var unit_seen := int(cruisers().counters.sightings) > 0
	check(unit_seen and law.last_seen_seated, "the crew saw the driver and law knows the suspect was driving")
	check(followed and float(chase.gap) > 0.4, "the cruiser followed, stopped behind the getaway car (closest %.2f m) and its officer got out" % float(chase.gap))
	ride.end_player_control()
	player.leave_vehicle(ride.global_position + Vector3(4.0, 0, 0), 0.0)
	seat.active = false
	seat.vehicle = null
	section_clean("seated pursuit")
	await dismiss()

## Tier 3 wants two cruisers: exactly two of three are claimed, never more.
func _two_cruiser_cap_section() -> void:
	home_police()
	var scene := Vector3(9.5, 0.0, 0.0)
	put_player(scene)
	spawn("civ_caller_mass", "mama", scene + Vector3(3, 0, 3), Vector3(-3, 0, -3))
	spawn("civ_victim_mass", "granny", scene + Vector3(0, 0, 1.0), Vector3(0, 0, -1))
	await advance(0.1)
	law.on_offense("stomp", scene + Vector3(0, 0, 1), "civ_victim_mass")
	await advance(0.2)
	law.on_offense("shooting", scene + Vector3(0, 1.3, 0), "")
	put_player(HIDEOUT)
	var peak := {"value": 0}
	var both := func() -> bool:
		peak.value = maxi(int(peak.value), cruisers().claimed_count())
		return law.wanted == 3 and cruisers().claimed_count() == 2
	var two: bool = await advance_until(both, 6.0)
	for i in 120:
		peak.value = maxi(int(peak.value), cruisers().claimed_count())
		await step()
	check(two and int(peak.value) == 2, "tier 3 claims exactly two cruisers out of three (peak %d)" % int(peak.value))
	var rays_per_tick: int = int(cruisers().counters.los_rays)
	await advance(1.0)
	rays_per_tick = (int(cruisers().counters.los_rays) - rays_per_tick) / 4
	check(rays_per_tick <= 3, "cruiser sight stays bounded (%d rays per perception tick)" % rays_per_tick)
	law.reset_state()
	await advance(0.1)
	var free := true
	for car in police:
		free = free and str(car.external_owner).is_empty()
	check(free and cruisers().claimed_count() == 0, "reset releases every claim at once")
	section_clean("two cruiser cap")
	await dismiss()

## A crew officer killed on foot stays dead: the cruiser is abandoned and
## released, the next incident uses the other crew, nobody is resurrected.
func _dead_crew_section() -> void:
	var a: Node3D = police[0]
	reset_car(a, lane_by("Middle Avenue", Vector3(0, 0, 1)), 15.0)
	var scene := Vector3(9.5, 0.0, 12.0)
	put_player(scene)
	spawn("civ_caller_dead", "mama", scene + Vector3(3, 0, 3), Vector3(-3, 0, -3))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var out: bool = await advance_until(func(): return str(crew_entry(CREW[0]).state) == "foot", 30.0)
	if not check(out, "an officer is out on foot"):
		await dismiss()
		return
	var officer: CharacterBody3D = npcs.actors[CREW[0]]
	var release_count_before: int = traffic.release_events.size()
	var original_owner := str(a.external_owner)
	check(combat._damage_target(officer, 1000.0, "pistol", officer.global_position + Vector3(0, 1.2, 4), false) and officer.dead,
		"combat kills the officer through its normal damage path")
	var fully_released := func() -> bool:
		var observed := false
		for event in traffic.release_events.slice(release_count_before):
			observed = observed or (str(event.vehicle) == str(a.vehicle_id) and str(event.owner) == original_owner)
		return observed and str(crew_entry(CREW[0]).state) == "dead" and not law._responders.has(CREW[0])
	# Release and foot-responder cleanup run at different cadences; a surviving
	# crew can also claim this car again before an externally observed empty tick.
	var released: bool = await advance_until(fully_released, 4.0)
	check(released,
		"the dead officer's cruiser is abandoned and released")
	if not released:
		note("dead crew diagnostic: releases=%s crew=%s responder=%s car=%s" % [str(traffic.release_events.slice(release_count_before)),
			str(crew_entry(CREW[0])), str(law._responders.has(CREW[0])), str(drive_sample(a))])
	law.reset_state()
	await advance(0.2)
	home_police()
	put_player(scene)
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var second: bool = await advance_until(func(): return not first_unit().is_empty(), 3.0)
	check(second and int(first_unit().crew) == 1 and str(crew_entry(CREW[1]).state) == "seated",
		"the next cruiser carries the surviving crew")
	check(officer.dead and not officer.enabled and str(crew_entry(CREW[0]).state) == "dead", "the dead officer is never re-seated or re-enabled")
	section_clean("dead crew")
	await dismiss()

## A disabled car (vehicle owner's damage state): its officer bails out and
## the response continues on foot.
func _disabled_car_section() -> void:
	if police[0].get("disabled") == null and not police[0].has_method("is_disabled"):
		note("vehicle exposes no 'disabled' state yet; disabled-car fallback not exercised")
		return
	if police[0].get("disabled") == null:
		note("vehicle reports disabled only through is_disabled(); this fixture cannot set it")
		return
	home_police()
	var scene := Vector3(9.5, 0.0, 12.0)
	put_player(scene)
	spawn("civ_caller_disabled", "mama", scene + Vector3(3, 0, 3), Vector3(-3, 0, -3))
	await advance(0.1)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var claimed: bool = await advance_until(func(): return not first_unit().is_empty(), 3.0)
	if not check(claimed, "a cruiser responds before its car is disabled"):
		await dismiss()
		return
	await advance(1.0)
	var car: Node3D = first_unit().car
	var crew_id: String = CREW[int(first_unit().crew)]
	car.set("disabled", true)
	var bailed_out := func() -> bool:
		return str(crew_entry(crew_id).state) == "foot" or str(car.external_owner).is_empty()
	var bailed: bool = await advance_until(bailed_out, 6.0)
	check(bailed, "the crew of a disabled cruiser continues on foot, or the car is released")
	check(unit_of(car).is_empty() or str(unit_of(car).mode) in ["hold", "dismounted", "abandoned"], "a disabled cruiser never drives on")
	law.reset_state()
	await advance(0.1)
	car.set("disabled", false)
	section_clean("disabled car")
	await dismiss()
