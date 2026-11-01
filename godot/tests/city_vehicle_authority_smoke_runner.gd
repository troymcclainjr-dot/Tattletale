extends "res://tests/city_vehicle_contract_fixture.gd"
## External (police) authority, deduplicated contacts and disabled cars on
## production bodies over static collision. Root runs engines:
## python godot/tools/godot_run.py --timeout 240 -- --headless --script res://tests/city_vehicle_authority_smoke.gd
const OWNER := "police"
var patrol: Node3D
var collision_events: Array[Dictionary] = []
var external_events: Array[Dictionary] = []
var impacts_seen := 0

func _init() -> void:
	tag = "vehicle_authority"

func run_sections() -> void:
	driving.vehicle_collision.connect(func(contact: Dictionary) -> void: collision_events.append(contact))
	traffic.external_collision.connect(func(contact: Dictionary) -> void: external_events.append(contact))
	driving.vehicle_impact.connect(func(_kind: String, _at: Vector3, _speed: float) -> void: impacts_seen += 1)
	await _claim_section()
	await _external_drive_section()
	await _neighbor_section()
	await _release_section()
	await _player_contact_section()
	await _disabled_section()

func _capsule_clear_of(mask: int) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._capsule.shape
	query.transform = player.global_transform * player._capsule.transform
	query.collision_mask = mask
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _of_kind(events: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if str(event.kind) == kind:
			found.append(event)
	return found

func _claim_section() -> void:
	patrol = make_ai_car(OPEN, 0.0, "fixture_patrol", 9.0, true)
	patrol.state = "parked"
	var civilian := make_ai_car(OPEN + Vector3(10.0, 0.0, 0.0), 0.0, "fixture_civilian")
	civilian.state = "parked"
	await frames(2)
	check(traffic.can_claim_external(patrol, "") == "owner" and not traffic.claim_external_vehicle(patrol, ""),
		"an empty owner id cannot claim a car")
	check(traffic.can_claim_external(driving.starter, OWNER) == "not_fleet" and not traffic.claim_external_vehicle(driving.starter, OWNER),
		"police can never claim the player's starter car")
	var refused_pose: Transform3D = patrol.global_transform
	var refused: Dictionary = patrol.external_step(DT, 1.0, 0.0, 0.0, false)
	check(not bool(refused.ok) and float(refused.moved) == 0.0 and patrol.global_transform.is_equal_approx(refused_pose),
		"external_step refuses a car nobody was granted")
	traffic.reservations["fixture_junction"] = civilian
	civilian.reservation_id = "fixture_junction"
	check(traffic.claim_external_vehicle(civilian, OWNER) and civilian.external_owner == OWNER, "police claim a stopped fleet car")
	check(not traffic.reservations.has("fixture_junction") and civilian.reservation_id == "", "the claim releases the car's junction reservation")
	check(civilian.state == "external" and civilian.force_detailed and not civilian.player_controlled and not traffic.player_fleet.has(civilian),
		"a police-held car is never player-controlled or in the player fleet, and keeps exact detail")
	check(not traffic.claim_external_vehicle(civilian, "rival") and traffic.can_claim_external(civilian, "rival") == "owned",
		"a second owner is refused")
	check(traffic.claim_external_vehicle(civilian, OWNER) and int(traffic.external_claims) == 1, "re-claiming by the same owner is idempotent")
	var status: Dictionary = traffic.get_status()
	check(int(status.external_controlled) == 1 and int(status.player_controlled) == 0 and int(status.external_owners.get(OWNER, 0)) == 1
		and int(status.total) == traffic.vehicles.size(), "status counts police apart from the player without changing fleet totals")
	await stand(door_point(civilian, -1.0))
	driving.tick(0.1)
	check(driving.get_status().candidate_id != "fixture_civilian" and not driving.enter_vehicle(civilian) and not traffic.claim_vehicle(civilian),
		"the explorer can neither board nor claim a police-held car")
	var pose: Transform3D = civilian.global_transform
	for i in 30:
		traffic.tick(DT)
		civilian.tick(DT)
	check(civilian.global_transform.is_equal_approx(pose) and civilian.state == "external", "neither traffic nor a direct AI tick moves a police-held car")
	check(not civilian.try_recycle() and not civilian.can_tick_damage_coarsely(), "a police-held car is never recycled or coarse-ticked")
	check(float(civilian.player_step(DT, 1.0, 0.0, 0.0, false).moved) == 0.0 and civilian.global_transform.is_equal_approx(pose),
		"player_step cannot drive a car the player does not hold")
	traffic.release_external_vehicle(civilian, OWNER)
	remove_ai_car(civilian)
	check(traffic.claim_external_vehicle(patrol, OWNER) and patrol.is_police, "police claim their own patrol car")

func _external_drive_section() -> void:
	place(patrol, OPEN, 0.0, 0.0)
	await frames(2)
	var start: Vector3 = patrol.global_position
	var result: Dictionary = {}
	for i in 120:
		result = patrol.external_step(DT, 1.0, 0.0, 0.0, false)
		await get_tree().physics_frame
	check(bool(result.ok) and patrol.global_position.z > start.z + 8.0 and absf(patrol.global_position.x - start.x) < 0.3 and float(result.speed) > 5.0,
		"external throttle drives the claimed car forward (%.1fm)" % (patrol.global_position.z - start.z))
	var reported: Vector3 = result.position
	check(not patrol.player_controlled and not driving.active and reported.is_equal_approx(patrol.global_position) and is_equal_approx(float(result.yaw), patrol.yaw),
		"external driving never takes player control and its report mirrors the body")
	var before_yaw: float = patrol.yaw
	for i in 20:
		patrol.external_step(DT, 0.4, 0.0, 1.0, false)
	check(angle_difference(before_yaw, patrol.yaw) < -0.05, "positive external steer turns right (decreasing yaw)")
	place(patrol, OPEN, 0.0, 10.0)
	for i in 240:
		patrol.external_step(DT, 0.0, 1.0, 0.0, false)
	check(patrol.speed < -2.0 and patrol.speed >= -Vehicle.DRIVE_MAX_REVERSE - 0.01,
		"the brake stops the car, then reverses at a bounded speed (%.1f m/s)" % patrol.speed)
	check(not bool(patrol.external_step(NAN, 1.0, 0.0, 0.0, false).ok), "a non-finite delta is refused")
	var nan_pose: Transform3D = patrol.global_transform
	patrol.external_step(DT, NAN, NAN, NAN, false)
	check(patrol.global_transform.origin.is_finite() and patrol.global_transform.origin.distance_to(nan_pose.origin) < 0.5,
		"non-finite controls are neutralized instead of corrupting the pose")
	var wall_z := OPEN.z + 14.0
	box("PatrolWall", Vector3(OPEN.x, 1.5, wall_z), Vector3(10, 3, 0.2), 2)
	await frames(2)
	place(patrol, OPEN, 0.0, 15.0)
	external_events.clear()
	var returned := 0
	var clear := true
	for i in 120:
		var step: Dictionary = patrol.external_step(DT, 1.0, 0.0, 0.0, false)
		returned += (step.events as Array).size()
		clear = clear and hull_clear(patrol)
		await get_tree().physics_frame
	check(clear and patrol.global_position.z < wall_z - 2.0 and absf(patrol.speed) < 0.6,
		"a 15 m/s external sweep stops at the wall face without entering it")
	check(returned == 1 and external_events.size() == 1,
		"one wall contact plus two seconds of pushing yields exactly one event (%d returned, %d signalled)" % [returned, external_events.size()])
	if external_events.size() == 1:
		var event: Dictionary = external_events[0]
		check(str(event.kind) == "structure" and str(event.driver) == "external" and str(event.external_owner) == OWNER
			and str(event.vehicle_id) == "fixture_patrol", "the event identifies the external driver, owner and contact kind")
		check(float(event.relative_speed) > 12.0 and str(event.severity) == "crash"
			and is_equal_approx(float(event.body_damage), Vehicle.crash_damage(float(event.relative_speed)))
			and is_equal_approx(float(event.body_damage), Vehicle.MAX_HEALTH - patrol.health),
			"crash damage is bounded and applied exactly once (%.1f at %.1f m/s)" % [float(event.body_damage), float(event.relative_speed)])
	clear_obstacles()
	await frames(2)
	# The on-foot explorer is solid to a police car and stumbles once if struck.
	place(patrol, OPEN, 0.0, 8.0)
	await frames(2)
	# Clear the old crash position before standing here; otherwise the player
	# starts inside that old hull and retains a roof/floor contact after teleport.
	await stand(OPEN + Vector3(0.0, 0.0, 12.0))
	external_events.clear()
	var hits: int = player.vehicle_hits
	var struck := false
	var overlapped := false
	for i in 120:
		var step: Dictionary = patrol.external_step(DT, 0.0 if struck else 0.5, 1.0 if struck else 0.0, 0.0, false)
		for event in step.events:
			struck = struck or str(event.kind) == "player"
		await get_tree().physics_frame
		overlapped = overlapped or not _capsule_clear_of(16)
	check(struck and player.vehicle_hits == hits + 1, "a police car stops at the on-foot explorer, who stumbles exactly once")
	check(not overlapped and _of_kind(external_events, "player").size() == 1, "the police hull never enters the explorer's capsule")

func _neighbor_section() -> void:
	await stand(OPEN + Vector3(8.0, 0.0, -20.0))
	place(patrol, OPEN, 0.0, 0.0)
	var follower := make_ai_car(OPEN - Vector3(0.0, 0.0, 14.0), 0.0, "fixture_follower")
	follower.state = "parked"
	await frames(2)
	traffic._update_leaders()
	check(is_finite(follower.leader_distance) and follower.leader_distance < 12.0,
		"AI followers queue behind a police-held car (%.1fm)" % follower.leader_distance)
	place(patrol, OPEN, PI * 0.5, 0.0)
	traffic._update_leaders()
	check(is_finite(follower.leader_distance), "a police car turned across the lane still blocks it")
	place(patrol, OPEN, 0.0, 0.0)
	remove_ai_car(follower)
	var approaching := make_ai_car(OPEN - Vector3(0.0, 0.0, 30.0), 0.0, "fixture_approach", 9.0)
	await frames(2)
	var overlapped := false
	for i in 480:
		traffic.tick(DT)
		await get_tree().physics_frame
		overlapped = overlapped or not hull_clear(approaching)
	var gap: float = patrol.global_position.z - approaching.global_position.z
	check(not overlapped and gap > 4.0 and approaching.speed < 0.5 and approaching.distance_travelled > 5.0,
		"an approaching AI car sweeps against the police body and stops short (%.1fm)" % gap)
	remove_ai_car(approaching)
	var near_cruiser := make_ai_car(OPEN + Vector3(12.0, 0.0, 0.0), 0.0, "fixture_near_cruiser")
	near_cruiser.state = "parked"
	var lonely := make_ai_car(OPEN + Vector3(-150.0, 0.0, 0.0), 0.0, "fixture_lonely")
	lonely.state = "parked"
	await stand(OPEN + Vector3(0.0, 0.0, 250.0))
	traffic._update_presence()
	check(near_cruiser.collision_layer == 16 and near_cruiser.near_physics,
		"a car within 40m of a police car keeps its collider while the explorer is 250m away")
	check(lonely.collision_layer == 0 and not lonely.near_physics, "cars far from both the explorer and the police still cull")
	var index := 8
	var record: Dictionary = parked.records[index]
	var record_pose: Transform3D = record.pose
	place(patrol, Vector3(LANE_X - 1.5, 0.0, record_pose.origin.z + 12.0), PI)
	traffic._update_presence()
	check(int(record.presence) < 2 and (record.body as StaticBody3D).collision_layer == (2 | 16),
		"a parked collider near a police car is physical beyond the explorer's presence radius")
	place(patrol, OPEN, 0.0, 0.0)
	traffic._update_presence()
	check((record.body as StaticBody3D).collision_layer == 0, "and culls again once the police car has left")
	remove_ai_car(near_cruiser)
	remove_ai_car(lonely)

func _release_section() -> void:
	await stand(OPEN + Vector3(6.0, 0.0, -6.0))
	place(patrol, OPEN, 0.0, 0.0)
	await frames(2)
	var follower := make_ai_car(OPEN - Vector3(0.0, 0.0, 14.0), 0.0, "fixture_follower2")
	follower.state = "parked"
	var pose: Transform3D = patrol.global_transform
	check(not traffic.release_external_vehicle(patrol, "rival") and patrol.external_owner == OWNER, "only the owner can release a police-held car")
	check(traffic.release_external_vehicle(patrol, OWNER), "the owner releases its car")
	check(patrol.global_transform.is_equal_approx(pose) and patrol.state == "parked" and patrol.external_owner.is_empty()
		and patrol.external_released and not patrol.force_detailed, "release parks the car exactly where it stopped, never teleported")
	check(not traffic.release_external_vehicle(patrol, OWNER), "a second release is refused")
	traffic._update_leaders()
	check(is_finite(follower.leader_distance), "a released police car still blocks its lane from any heading")
	for i in 30:
		traffic.tick(DT)
	check(patrol.global_transform.is_equal_approx(pose) and not patrol.try_recycle(), "near the explorer it neither moves nor recycles")
	await look_away(patrol.global_position + Vector3(0.0, 0.0, 160.0), patrol.global_position)
	var start: Vector3 = patrol.route[0]
	check(patrol._outside_view(patrol.global_position, player.camera) and patrol._outside_view(start, player.camera),
		"fixture precondition: the explorer is far away and facing away")
	check(patrol.try_recycle() and not patrol.external_released and patrol.state == "waiting",
		"far and unseen it returns to traffic as a fresh arrival")
	remove_ai_car(follower)
	remove_ai_car(patrol)
	await stand(OPEN + Vector3(25.0, 0.0, -6.0))
	var first := make_ai_car(OPEN + Vector3(20.0, 0.0, 0.0), 0.0, "fixture_first")
	var second := make_ai_car(OPEN + Vector3(30.0, 0.0, 0.0), 0.0, "fixture_second")
	await frames(2)
	check(traffic.claim_external_vehicle(first, OWNER) and traffic.claim_external_vehicle(second, OWNER)
		and traffic.external_vehicles(OWNER).size() == 2, "one owner may hold two cars")
	check(traffic.release_all_external_vehicles(OWNER) == 2 and traffic.external_vehicles().is_empty()
		and int(traffic.get_status().external_controlled) == 0, "release_all frees every car an owner holds")
	remove_ai_car(first)
	remove_ai_car(second)
	var taxi := make_ai_car(OPEN + Vector3(40.0, 0.0, 0.0), 0.0, "fixture_taxi")
	taxi.state = "parked"
	await frames(2)
	if check(await board(taxi), "board a civilian car"):
		check(traffic.can_claim_external(taxi, OWNER) == "player" and not traffic.claim_external_vehicle(taxi, OWNER),
			"police cannot take the car the player is driving")
		check(await leave(), "exit the civilian car")
		check(taxi.player_released and traffic.can_claim_external(taxi, OWNER) == "player_released",
			"nor a car the player has just left")
	remove_ai_car(taxi)

func _player_contact_section() -> void:
	var car := make_ai_car(OPEN + Vector3(60.0, 0.0, 0.0), 0.0, "fixture_ride")
	car.state = "parked"
	await frames(2)
	if not check(await board(car), "board a civilian car for contact checks"):
		remove_ai_car(car)
		return
	var wall_z := OPEN.z + 14.0
	box("HeadOnWall", Vector3(OPEN.x, 1.5, wall_z), Vector3(10, 3, 0.2), 2)
	await frames(2)
	place(car, OPEN, 0.0, 20.0)
	collision_events.clear()
	var impacts := impacts_seen
	await drive(90, 1.0)
	check(collision_events.size() == 1,
		"a 20 m/s wall crash plus 1.5s of pushing emits exactly one vehicle_collision (%d)" % collision_events.size())
	check(impacts_seen == impacts + 1, "the retained vehicle_impact signal still reports the crash once")
	if collision_events.size() == 1:
		var event: Dictionary = collision_events[0]
		check(str(event.driver) == "player" and str(event.kind) == "structure" and str(event.vehicle_id) == "fixture_ride"
			and str(event.actor_id).is_empty() and str(event.other_vehicle_id).is_empty(), "the crash event names driver, car and kind")
		check(float(event.relative_speed) > 15.0 and str(event.severity) == "crash"
			and is_equal_approx(float(event.body_damage), Vehicle.MAX_HEALTH - car.health) and float(event.body_damage) <= Vehicle.CRASH_DAMAGE_CAP,
			"relative speed and bounded body damage are reported (%.1f at %.1f m/s)" % [float(event.body_damage), float(event.relative_speed)])
		var point: Vector3 = event.point
		var normal: Vector3 = event.normal
		check(absf(point.z - (wall_z - 0.1)) < 0.4 and normal.dot(Vector3(0.0, 0.0, -1.0)) > 0.9,
			"the contact point lies on the wall face and the normal points back at the car (%s, %s)" % [point, normal])
	var dented: float = car.health
	await drive(70, 0.0, 1.0)
	collision_events.clear()
	await drive(120, 1.0)
	check(collision_events.size() == 1 and car.health < dented, "after separating, a second crash is a new episode")
	clear_obstacles()
	await frames(2)
	var resident := person(OPEN + Vector3(0.0, 0.0, 12.0), "fixture_resident")
	await frames(2)
	var resident_at: Vector3 = resident.global_position
	place(car, OPEN, 0.0, 10.0)
	collision_events.clear()
	var before: float = car.health
	await drive(90, 0.6)
	var people := _of_kind(collision_events, "person")
	check(people.size() == 1 and str(people[0].actor_id) == "fixture_resident" and float(people[0].body_damage) == 0.0 and car.health == before,
		"a pedestrian contact is one person event with the resident's actor_id and no car damage")
	check(hull_clear(car) and resident.global_position.is_equal_approx(resident_at), "the car stops before the pedestrian; nobody is entered or pushed")
	clear_obstacles()
	await frames(2)
	person(OPEN + Vector3(0.0, 0.0, 12.0), "", 7)
	await frames(2)
	place(car, OPEN, 0.0, 10.0)
	collision_events.clear()
	await drive(90, 0.6)
	people = _of_kind(collision_events, "person")
	check(people.size() == 1 and str(people[0].actor_id) == "crowd_7", "a crowd body is identified as crowd_<index>, like combat")
	clear_obstacles()
	await frames(2)
	var oncoming := make_ai_car(OPEN + Vector3(0.0, 0.0, 16.0), PI, "fixture_oncoming")
	oncoming.state = "parked"
	await frames(2)
	oncoming.velocity = Vector3(0.0, 0.0, -5.0)
	var oncoming_health: float = oncoming.health
	place(car, OPEN, 0.0, 8.0)
	collision_events.clear()
	await drive(120, 0.5)
	var vehicles := _of_kind(collision_events, "vehicle")
	check(vehicles.size() == 1 and str(vehicles[0].other_vehicle_id) == "fixture_oncoming", "a car contact names the other vehicle once")
	if vehicles.size() == 1:
		check(float(vehicles[0].relative_speed) > float(vehicles[0].car_speed) + 3.0,
			"relative speed includes the other car's motion (%.1f vs own %.1f)" % [float(vehicles[0].relative_speed), float(vehicles[0].car_speed)])
		check(float(vehicles[0].other_damage) > 0.0 and is_equal_approx(oncoming.health, oncoming_health - float(vehicles[0].other_damage)),
			"the struck car takes the same bounded damage")
	remove_ai_car(oncoming)
	box("GlancingWall", OPEN + Vector3(2.5, 1.5, 14.0), Vector3(0.3, 3, 40), 2, deg_to_rad(20.0))
	await frames(2)
	place(car, OPEN, 0.0, 15.0)
	collision_events.clear()
	var contacts: int = car.drive_contacts
	await drive(90, 1.0)
	check(car.drive_contacts > contacts + 10 and collision_events.size() <= 2 and car.speed > 3.0,
		"grinding along a glancing wall still slides and stays one bounded episode (%d events)" % collision_events.size())
	clear_obstacles()
	await frames(2)
	var origin: Vector3 = car.global_position + Vector3.LEFT * 3.0
	before = car.health
	var shot: Dictionary = car.receive_gunshot({}, origin)
	check(is_equal_approx(car.health, before - Vehicle.SHOT_BODY_DAMAGE) and is_equal_approx(float(shot.body_damage), Vehicle.SHOT_BODY_DAMAGE)
		and car.flat_tires.is_empty(), "a body round dents the car by the default amount")
	before = car.health
	car.receive_gunshot({"body_damage": 10.0}, origin)
	check(is_equal_approx(car.health, before - 10.0), "root may supply its own per-round body damage")
	before = car.health
	shot = car.receive_gunshot({"tire_index": 1}, origin)
	check(car.health == before and bool(shot.punctured) and car.flat_tires == [1], "a tire round punctures without denting the body")
	car.receive_gunshot({"body_damage": "lots"}, origin)
	check(car.health == before, "non-numeric body damage is ignored")
	await leave()
	remove_ai_car(car)

func _disabled_section() -> void:
	var wreck := make_ai_car(OPEN + Vector3(80.0, 0.0, 0.0), 0.0, "fixture_wreck")
	wreck.state = "parked"
	await frames(2)
	check(not wreck.apply_body_damage(-5.0) and not wreck.apply_body_damage(0.0) and not wreck.apply_body_damage(NAN)
		and not wreck.apply_body_damage(INF) and wreck.health == Vehicle.MAX_HEALTH, "negative, zero and non-finite damage are refused")
	check(wreck.apply_body_damage(30.0) and is_equal_approx(wreck.health, 70.0) and wreck.damage_stage() == "damaged", "damage lowers health")
	check(wreck.apply_body_damage(40.0) and wreck.damage_stage() == "smoking", "low health reports the smoking stage")
	check(wreck.apply_body_damage(1000.0) and wreck.health == 0.0 and wreck.disabled and wreck.damage_stage() == "disabled",
		"health clamps at zero and disables the car")
	check(not wreck.apply_body_damage(5.0) and wreck.health == 0.0, "a wreck takes no further damage")
	check(traffic.can_claim_external(wreck, OWNER) == "disabled" and not traffic.claim_external_vehicle(wreck, OWNER), "police cannot claim a wreck")
	var status: Dictionary = wreck.get_damage_status()
	check(bool(status.disabled) and str(status.seat) == "empty" and int(traffic.get_status().disabled) >= 1, "damage status reports the wreck")
	await stand(door_point(wreck, 1.0))
	driving.tick(0.1)
	check(driving.get_status().prompt == "Wrecked · won't start", "a wreck explains why it cannot be driven (%s)" % driving.get_status().prompt)
	check(driving.handle_input(key(KEY_F)) and not driving.active and "won't start" in str(driving.get_status().prompt),
		"F beside a wreck explains instead of boarding")
	check(not driving.enter_vehicle(wreck), "enter_vehicle refuses a wreck")
	remove_ai_car(wreck)
	var ride := make_ai_car(OPEN + Vector3(100.0, 0.0, 0.0), 0.0, "fixture_doomed")
	ride.state = "parked"
	await frames(2)
	if check(await board(ride), "board a healthy car that will be wrecked"):
		place(ride, OPEN, 0.0, 0.0)
		await frames(2)
		ride.apply_body_damage(1000.0)
		var at: Vector3 = ride.global_position
		await drive(60, 1.0)
		check(ride.global_position.distance_to(at) < 0.01 and absf(ride.speed) < 0.01, "a dead engine does not move under full throttle")
		await drive(60, 0.0, 1.0)
		check(ride.global_position.distance_to(at) < 0.01, "nor reverse under the brake key")
		place(ride, OPEN, 0.0, 10.0)
		var yaw_before: float = ride.yaw
		await drive(20, 0.0, 0.0, 1.0)
		check(angle_difference(yaw_before, ride.yaw) < -0.05, "a rolling wreck still steers")
		var rolled: Vector3 = ride.global_position
		await drive(150, 0.0, 1.0)
		check(absf(ride.speed) < 0.05 and ride.global_position.distance_to(rolled) < 12.0, "and its brakes still stop it")
		driving._message_time = 0.0
		driving._exit_clock = 0.0
		driving.tick(DT)
		check(driving.get_status().prompt == "Engine dead · F  Get out" and bool(driving.get_status().vehicle_disabled),
			"a stopped wreck offers the normal exit (%s)" % driving.get_status().prompt)
		check(driving.handle_input(key(KEY_F)) and not driving.active, "F gets out of the wreck")
	remove_ai_car(ride)
	await stand(OPEN + Vector3(126.0, 0.0, -10.0))
	var jam := make_ai_car(OPEN + Vector3(120.0, 0.0, 0.0), 0.0, "fixture_jam", 9.0)
	await frames(2)
	for i in 60:
		jam.tick(DT)
	var moving: float = jam.speed
	traffic.reservations["fixture_node"] = jam
	jam.reservation_id = "fixture_node"
	jam.apply_body_damage(1000.0)
	check(not traffic.reservations.has("fixture_node") and jam.reservation_id == "", "a wreck releases its junction reservation")
	var stopped: Vector3 = jam.global_position
	var honks: int = jam.honks
	for i in 120:
		jam.tick(DT)
	check(moving > 1.0 and jam.state == "disabled" and jam.speed == 0.0 and jam.global_position.distance_to(stopped) < 0.01 and jam.honks == honks,
		"a disabled AI car stops dead without creeping or honking")
	var behind := make_ai_car(stopped - Vector3(0.0, 0.0, 14.0), 0.0, "fixture_behind")
	behind.state = "parked"
	traffic._update_leaders()
	check(is_finite(behind.leader_distance), "followers queue behind the wreck")
	check(not jam.try_recycle(), "a wreck near the explorer is not removed")
	await look_away(stopped + Vector3(0.0, 0.0, 170.0), stopped)
	check(jam.try_recycle() and not jam.disabled and jam.health == Vehicle.MAX_HEALTH and jam.state == "waiting",
		"far and unseen the wreck recycles as a healthy arrival")
	remove_ai_car(behind)
	remove_ai_car(jam)
