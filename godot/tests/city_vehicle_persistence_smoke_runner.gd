extends "res://tests/city_vehicle_contract_fixture.gd"
## Ordinary parked-car promotion, damage continuity, the bounded remembered
## registry and driving persistence (snapshot/validate/preflight/restore/reset)
## on a real parked batch. Root runs engines:
## python godot/tools/godot_run.py --timeout 300 -- --headless --script res://tests/city_vehicle_persistence_smoke.gd
const PROMOTED := 3
var promoted: Node3D
var saved: Dictionary = {}

func _init() -> void:
	tag = "vehicle_persistence"

func run_sections() -> void:
	await _promotion_section()
	if failures > 0:
		return
	await _registry_section()
	await _persistence_section()
	if saved.is_empty():
		return
	await _fallback_section()
	await _occupied_section()
	_invalid_section()

func _record(index: int) -> Dictionary:
	return parked.records[index]

## No collider and no visible damage model. Batch submission is checked
## separately through per-kind count deltas (batch_total).
func _hidden(index: int) -> bool:
	var record := _record(index)
	var model_visible: bool = record.has("damage_model") and is_instance_valid(record.damage_model) and record.damage_model.visible
	return (record.body as StaticBody3D).collision_layer == 0 and not model_visible

## Batch count for `index`'s kind with presence centred on that record.
func _kind_total_at(index: int) -> int:
	var pose: Transform3D = _record(index).pose
	parked.set_presence(pose.origin)
	var total := batch_total(str(_record(index).kind))
	parked.set_presence(player.global_position)
	return total

func _fleet_car(id: String) -> Node3D:
	for car in traffic.player_fleet:
		if is_instance_valid(car) and car.is_inside_tree() and str(car.vehicle_id) == id:
			return car
	return null

func _has_fallback(result: Dictionary, id: String, reason: String, action := "") -> bool:
	for fallback in result.get("fallbacks", []):
		if str(fallback.id) == id and str(fallback.reason) == reason and (action.is_empty() or str(fallback.action) == action):
			return true
	return false

func _snapshot_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for entry in state.vehicles:
		ids.append(str(entry.id))
	return ids

func _at(entry: Dictionary) -> Vector3:
	return Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2]))

## A well-formed remembered entry for parked record `index` at `at`.
func _parked_entry(index: int, at: Vector3, heading: float, last_used: int) -> Dictionary:
	var record := _record(index)
	return {"id": str(record.source_id), "source": "parked", "source_id": str(record.source_id),
		"source_key": (record.source_key as Dictionary).duplicate(true), "prototype": str(record.kind),
		"paint": int(record.paint), "position": [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)],
		"yaw": Driving.canonical_yaw(heading), "health": 100.0, "disabled": false, "flat_tires": [], "last_used": last_used}

func _promotion_section() -> void:
	var record := _record(PROMOTED)
	var pose: Transform3D = record.pose
	var body: StaticBody3D = record.body
	var source := str(record.source_id)
	check(source == "parked_003" and str(record.source_key.kind) == str(record.kind) and str(record.source_key.street) == "Parked Lane",
		"parked records carry a stable source id and fingerprint (%s)" % source)
	await stand(record_door(PROMOTED, 2.2))
	var wheel_hit: Dictionary = parked.receive_gunshot({"collider": body, "tire_index": 1}, player.global_position)
	var body_hit: Dictionary = parked.receive_gunshot({"collider": body}, player.global_position)
	check(bool(wheel_hit.punctured) and record.flat_tires == [1] and is_equal_approx(float(body_hit.body_damage), ParkedCars.SHOT_BODY_DAMAGE)
		and is_equal_approx(float(record.health), ParkedCars.MAX_HEALTH - ParkedCars.SHOT_BODY_DAMAGE),
		"an unpromoted record keeps a flat tire and a body dent")
	var starter: Node3D = driving.starter
	if check(await board(starter), "board the starter to ram the parked car"):
		var events: Array[Dictionary] = []
		var listener := func(contact: Dictionary) -> void: events.append(contact)
		driving.vehicle_collision.connect(listener)
		place(starter, Vector3(LANE_X - 2.0, 0.0, pose.origin.z), PI * 0.5, 6.0)
		parked.set_presence(starter.global_position)
		var dented := float(record.health)
		await drive(90, 0.4)
		driving.vehicle_collision.disconnect(listener)
		var rams: Array[Dictionary] = []
		for event in events:
			if str(event.other_vehicle_id) == source:
				rams.append(event)
		check(rams.size() == 1 and str(rams[0].kind) == "vehicle" and float(rams[0].other_damage) > 0.0
			and is_equal_approx(float(record.health), dented - float(rams[0].other_damage)),
			"ramming the parked car is one event that dents its record (%d events)" % events.size())
		check(not _hidden(PROMOTED) and str(record.get("promoted", "")).is_empty(), "a rammed record stays an ordinary batch car")
		check(await leave(), "leave the starter beside the parked car")
	await stand(record_door(PROMOTED))
	driving.tick(0.1)
	var status: Dictionary = driving.get_status()
	check(str(status.candidate_id) == source and str(status.prompt) == "F  Drive this car",
		"beside an ordinary parked car the prompt offers F (%s, %s)" % [status.candidate_id, status.prompt])
	var fleet_before: int = traffic.player_fleet.size()
	var traffic_before: int = traffic.vehicles.size()
	var health_before := float(record.health)
	# The shot record already left its batch for a damage model.
	var kind_before := _kind_total_at(PROMOTED)
	check(driving.handle_input(key(KEY_F)) and driving.active, "F boards the ordinary parked car")
	promoted = driving.vehicle
	if not check(is_instance_valid(promoted) and promoted is Vehicle and promoted != starter, "the parked car became a live body"):
		return
	check(str(promoted.vehicle_id) == source and str(promoted.registry_id) == source and str(promoted.source_id) == source,
		"the live body keeps the record's stable identity")
	check(str(promoted.prototype_kind) == str(record.kind) and int(promoted.paint_index) == int(record.paint)
		and promoted.global_position.distance_to(pose.origin) < 0.002 and absf(angle_difference(promoted.yaw, atan2(pose.basis.z.x, pose.basis.z.z))) < 0.001,
		"same prototype, paint and pose as the batch car")
	check(promoted.flat_tires == [ParkedCars.to_vehicle_wheel(1)] and promoted.flat_tires == [2] and is_equal_approx(promoted.health, health_before),
		"the flat (batch RL = vehicle index 2) and the dents carry over exactly")
	check(_hidden(PROMOTED) and str(record.promoted) == source and _kind_total_at(PROMOTED) == kind_before,
		"the record's collider and damage model are hidden and it is not resubmitted to its batch (%d vs %d)" % [_kind_total_at(PROMOTED), kind_before])
	var hit: Dictionary = traffic.raycast_tires(pose.origin + Vector3(6.0, 0.7, 0.0), pose.origin + Vector3(0.0, 0.7, 0.0))
	check(not hit.is_empty() and hit.collider == promoted, "shots at that spot hit the live body, never a ghost record")
	check(traffic.player_fleet.size() == fleet_before + 1 and fleet_count(source) == 1 and traffic.vehicles.size() == traffic_before,
		"one live body joins the player fleet; the 90-car style fleet is untouched")
	parked.set_presence(pose.origin + Vector3(0.0, 0.0, 400.0))
	parked.set_presence(pose.origin + Vector3(0.0, 0.0, 120.0))
	parked.set_presence(pose.origin)
	check(_hidden(PROMOTED) and _kind_total_at(PROMOTED) == kind_before, "presence and LOD refreshes never resubmit the promoted original")
	place(promoted, Vector3(LANE_X - 1.0, 0.0, pose.origin.z - 20.0), PI, 0.0)
	await drive(30, 0.5)
	check(await leave(), "exit the promoted car")
	check(not promoted.player_controlled and promoted.state == "parked" and driving.remembered.has(promoted), "it stays parked and remembered")
	var promotions: int = driving.promotions
	await stand(door_point(promoted, 1.0))
	driving.tick(0.1)
	check(driving.handle_input(key(KEY_F)) and driving.vehicle == promoted and driving.promotions == promotions
		and traffic.player_fleet.size() == fleet_before + 1 and fleet_count(source) == 1, "re-entry reuses the same live body")
	check(_hidden(PROMOTED) and _kind_total_at(PROMOTED) == kind_before, "re-entry never re-promotes or reveals the original")
	check(await leave(), "exit again")
	var before: Variant = canonical(driving.snapshot_state())
	promoted.receive_gunshot({}, promoted.global_position + Vector3(3.0, 1.0, 0.0))
	check(canonical(driving.snapshot_state()) != before, "a shot on the live body changes its durable state")

func _registry_section() -> void:
	# Starter and record 3 are remembered; six more fill the registry to eight.
	for index in [5, 7, 9, 11, 13, 15]:
		if not check(await board_record(index), "promote parked record %d" % index):
			return
		check(await leave(), "leave promoted record %d at its curb" % index)
	check(driving.remembered.size() == Driving.MAX_REMEMBERED and driving.forgotten.is_empty() and traffic.player_fleet.size() == 8,
		"eight remembered cars including the starter (%d)" % driving.remembered.size())
	var lru := promoted
	check(await board_record(17), "a ninth car can still be promoted")
	var newest: Node3D = driving.vehicle
	check(driving.remembered.size() == Driving.MAX_REMEMBERED and driving.forgotten.size() == 1 and driving.forgotten[0] == lru
		and traffic.player_fleet.size() == 9, "the least recently used car is forgotten, keeping the fleet at nine bodies")
	check(driving.remembered.has(driving.starter) and driving.remembered.has(newest), "the starter and the occupied car are never forgotten")
	check(lru.is_inside_tree() and str(_record(PROMOTED).promoted) == "parked_003", "a forgotten car stays in the world: no visible disappearance")
	check(not "parked_003" in _snapshot_ids(driving.snapshot_state()), "forgotten cars are not persisted")
	check(await leave(), "leave the newest car")
	# Record 1 is within 80m of the pending forgotten car, so it cannot revert yet.
	check(not await board_record(1) and not driving.active and "leave one behind" in str(driving.get_status().prompt)
		and str(_record(1).get("promoted", "")).is_empty() and lru.is_inside_tree(),
		"while one forgotten car is pending nearby, a full registry refuses with a reason")
	var spot: Transform3D = _record(PROMOTED).pose
	var hidden_total := _kind_total_at(PROMOTED)
	await look_away(Vector3(LANE_X - 150.0, 0.0, spot.origin.z), spot.origin)
	check(lru._outside_view(lru.global_position, player.camera) and lru._outside_view(spot.origin, player.camera),
		"fixture precondition: the explorer is far away and facing away")
	# Someone loitering in the vacated curb spot: the original must not turn solid around them.
	person(spot.origin, "fixture_loiterer")
	await frames(2)
	driving.tick(Driving.CLEANUP_INTERVAL + 0.1)
	check(not lru.is_inside_tree() and driving.forgotten.is_empty() and str(_record(PROMOTED).promoted).is_empty()
		and traffic.player_fleet.size() == 8, "unseen and far, the forgotten car reverts to its record")
	check(bool(_record(PROMOTED).get("settling", false)) and _hidden(PROMOTED) and _kind_total_at(PROMOTED) == hidden_total,
		"while a person stands in its spot the returned original stays hidden and non-solid")
	clear_obstacles()
	await frames(2)
	await stand(record_door(PROMOTED))
	var returned_total := _kind_total_at(PROMOTED)
	check((_record(PROMOTED).body as StaticBody3D).collision_layer == (2 | 16) and returned_total == hidden_total + 1
		and _record(PROMOTED).flat_tires.is_empty() and float(_record(PROMOTED).health) == ParkedCars.MAX_HEALTH,
		"the original returns once, with its collider, as a fresh batch car (layer %d, batch %d -> %d)"
		% [(_record(PROMOTED).body as StaticBody3D).collision_layer, hidden_total, returned_total])
	check(await board_record(1), "with the pending car resolved, promotion works again")
	check(await leave(), "leave record 1")

func _persistence_section() -> void:
	var starter: Node3D = driving.starter
	# Publish the preceding door exit to PhysicsServer before reset checks
	# whether the original curb hull would enclose the explorer.
	await frames(2)
	check(driving.reset_persistent_state(), "reset applies while no car is occupied")
	await frames(2)
	check(driving.remembered.size() == 1 and driving.remembered[0] == starter and driving.forgotten.is_empty() and traffic.player_fleet.size() == 1,
		"reset reverts every promoted and forgotten car")
	check(starter.global_transform.is_equal_approx(driving.starter_home) and starter.health == Vehicle.MAX_HEALTH and starter.flat_tires.is_empty(),
		"reset returns the starter home repaired")
	var any_promoted := false
	for record in parked.records:
		any_promoted = any_promoted or not str(record.get("promoted", "")).is_empty()
	check(not any_promoted and parked.damage_snapshot().is_empty(), "every original is back and parked damage is cleared")
	if not check(await board(starter), "board the starter to move it"):
		return
	place(starter, Vector3(-2.6, 0.0, -20.0), PI, 0.0)
	await drive(10, 0.0, 1.0)
	starter.apply_body_damage(12.5)
	starter.receive_gunshot({"tire_index": 3}, starter.global_position + Vector3(3.0, 0.5, 0.0))
	check(await leave(), "park the damaged starter elsewhere")
	if not check(await board_record(6), "promote record 6"):
		return
	var moved: Node3D = driving.vehicle
	var spot: Transform3D = _record(6).pose
	place(moved, Vector3(LANE_X - 1.2, 0.0, spot.origin.z), PI, 0.0)
	await drive(10, 0.0, 1.0)
	moved.apply_body_damage(20.0)
	moved.receive_gunshot({"tire_index": 0}, moved.global_position + Vector3(-3.0, 0.5, 0.0))
	check(await leave(), "park the damaged promoted car on the road")
	var body10: StaticBody3D = _record(10).body
	parked.receive_gunshot({"collider": body10, "tire_index": 2}, player.global_position)
	parked.receive_gunshot({"collider": body10}, player.global_position)
	var snap: Dictionary = driving.snapshot_state()
	check(driving.validate_state(snap).is_empty(), "the live snapshot validates (%s)" % driving.validate_state(snap))
	var parsed = JSON.parse_string(JSON.stringify(snap))
	check(parsed is Dictionary and driving.validate_state(parsed).is_empty() and canonical(snap) == canonical(parsed),
		"it survives a JSON round trip (integral floats accepted)")
	if not parsed is Dictionary or not driving.validate_state(parsed).is_empty():
		return
	check(_snapshot_ids(parsed) == ["parked_006", "player_starter"] and (parsed.parked_damage as Array).size() == 1,
		"two remembered cars in stable order plus one damaged batch record")
	var moved_entry: Dictionary = parsed.vehicles[0]
	var starter_entry: Dictionary = parsed.vehicles[1]
	var damage_entry: Dictionary = parsed.parked_damage[0]
	check(str(moved_entry.source) == "parked" and str(moved_entry.source_id) == "parked_006" and str(moved_entry.prototype) == str(_record(6).kind)
		and moved_entry.flat_tires == [0.0] and is_equal_approx(float(moved_entry.health), 80.0) and _at(moved_entry).distance_to(moved.global_position) < 0.002,
		"the promoted car records identity, pose, flats and health")
	check(str(starter_entry.source) == "starter" and starter_entry.flat_tires == [3.0] and is_equal_approx(float(starter_entry.health), 87.5)
		and _at(starter_entry).distance_to(starter.global_position) < 0.002, "the starter records its moved pose and damage")
	check(str(damage_entry.source_id) == "parked_010" and damage_entry.flat_tires == [float(ParkedCars.to_vehicle_wheel(2))]
		and is_equal_approx(float(damage_entry.health), 97.5), "an unpromoted damaged record persists in vehicle wheel order")
	var before: Variant = canonical(driving.snapshot_state())
	var predicted: Dictionary = driving.preflight_state(parsed)
	check(bool(predicted.ok) and (predicted.fallbacks as Array).is_empty() and canonical(driving.snapshot_state()) == before,
		"preflight on a matching scene predicts no fallbacks and mutates nothing")
	var old_body := moved
	var result: Dictionary = driving.restore_state(parsed)
	check(bool(result.ok) and int(result.restored) == 2 and (result.fallbacks as Array).is_empty(), "restore applies both cars (%s)" % str(result))
	check(canonical(driving.snapshot_state()) == canonical(snap), "restore reproduces the exact durable snapshot")
	check(not old_body.is_inside_tree() and fleet_count("parked_006") == 1 and traffic.player_fleet.size() == 2 and _hidden(6),
		"the old body is replaced by exactly one live car and the original stays hidden")
	check(_record(10).flat_tires == [2] and is_equal_approx(float(_record(10).health), 97.5), "batch damage is restored onto its record")
	result = driving.restore_state(parsed)
	await frames(2)
	check(bool(result.ok) and canonical(driving.snapshot_state()) == canonical(snap) and fleet_count("parked_006") == 1
		and traffic.player_fleet.size() == 2 and _hidden(6), "a repeated restore never duplicates a car or reveals its original")
	driving.reset_persistent_state()
	result = driving.restore_state(parsed)
	check(bool(result.ok) and canonical(driving.snapshot_state()) == canonical(snap), "a restore from a reset scene reproduces the snapshot")
	saved = parsed

func _fallback_section() -> void:
	var starter: Node3D = driving.starter
	var moved_entry: Dictionary = saved.vehicles[0]
	var starter_entry: Dictionary = saved.vehicles[1]
	driving.reset_persistent_state()
	await stand(record_door(6))
	box("RestoreBlocker", _at(moved_entry) + Vector3.UP * 1.0, Vector3(1.0, 2.0, 1.0), 2)
	await frames(2)
	var predicted: Dictionary = driving.preflight_state(saved)
	check(bool(predicted.ok) and "parked_006:pose_blocked" in predicted.fallbacks, "preflight predicts a blocked restore pose (%s)" % str(predicted))
	var result: Dictionary = driving.restore_state(saved)
	check(bool(result.ok) and int(result.restored) == 1 and _has_fallback(result, "parked_006", "pose_blocked", "returned_to_source"),
		"a blocked pose falls back explicitly (%s)" % str(result))
	check(fleet_count("parked_006") == 0 and str(_record(6).get("promoted", "")).is_empty() and not _hidden(6)
		and is_equal_approx(float(_record(6).health), float(moved_entry.health)) and _record(6).flat_tires == [ParkedCars.to_parked_wheel(0)],
		"the blocked car stays at its curb with its saved damage; nothing is duplicated")
	clear_obstacles()
	await frames(2)
	driving.reset_persistent_state()
	box("StarterBlocker", _at(starter_entry) + Vector3.UP * 1.0, Vector3(1.0, 2.0, 1.0), 2)
	await frames(2)
	result = driving.restore_state(saved)
	check(bool(result.ok) and _has_fallback(result, "player_starter", "pose_blocked", "kept_spawn")
		and starter.global_transform.is_equal_approx(driving.starter_home) and is_equal_approx(starter.health, float(starter_entry.health))
		and starter.flat_tires == [3], "a blocked starter pose keeps the spawn spot but restores its damage")
	clear_obstacles()
	await frames(2)
	driving.reset_persistent_state()
	await stand(SPAWN)
	var other: Transform3D = _record(12).pose
	var crafted: Dictionary = saved.duplicate(true)
	crafted.vehicles[0].position = [snappedf(other.origin.x - 0.4, 0.001), snappedf(other.origin.y, 0.001), snappedf(other.origin.z, 0.001)]
	check((_record(12).body as StaticBody3D).collision_layer == 0, "fixture precondition: record 12's collider is culled")
	result = driving.restore_state(crafted)
	check(bool(result.ok) and _has_fallback(result, "parked_006", "pose_blocked") and fleet_count("parked_006") == 0,
		"a pose overlapping a culled parked car is refused by footprint, not physics presence")
	crafted = saved.duplicate(true)
	crafted.vehicles[0].id = "parked_900"
	crafted.vehicles[0].source_id = "parked_900"
	crafted.vehicles[0].source_key.origin = [float(moved_entry.source_key.origin[0]), float(moved_entry.source_key.origin[1]),
		float(moved_entry.source_key.origin[2]) + 40.0]
	check(driving.validate_state(crafted).is_empty(), "fixture precondition: the geometry-changed payload is well formed")
	result = driving.restore_state(crafted)
	check(bool(result.ok) and _has_fallback(result, "parked_900", "source_missing", "dropped") and fleet_count("parked_900") == 0
		and fleet_count("parked_006") == 0, "a vanished source drops the car instead of inventing one")
	crafted = saved.duplicate(true)
	crafted.vehicles[0].id = "parked_901"
	crafted.vehicles[0].source_id = "parked_901"
	result = driving.restore_state(crafted)
	check(bool(result.ok) and _has_fallback(result, "parked_901", "source_reassigned", "restored_as_parked_006")
		and fleet_count("parked_006") == 1 and _hidden(6), "a renumbered record is matched by its fingerprint and reported")
	# A swap: car 8 was parked in car 14's original curb spot, car 14 on the road.
	driving.reset_persistent_state()
	await stand(record_door(11))
	var b_pose: Transform3D = _record(14).pose
	var road := Vector3(LANE_X - 1.2, b_pose.origin.y, b_pose.origin.z - 10.0)
	var swap := {"version": 1, "sequence": 3, "parked_damage": [], "vehicles": [(saved.vehicles[1] as Dictionary).duplicate(true),
		_parked_entry(8, b_pose.origin, atan2(b_pose.basis.z.x, b_pose.basis.z.z), 1), _parked_entry(14, road, PI, 2)]}
	check(driving.validate_state(swap).is_empty(), "fixture precondition: the swap payload is well formed (%s)" % driving.validate_state(swap))
	result = driving.restore_state(swap)
	var car_eight := _fleet_car("parked_008")
	check(bool(result.ok) and (result.fallbacks as Array).is_empty() and fleet_count("parked_008") == 1 and fleet_count("parked_014") == 1
		and car_eight != null and car_eight.global_position.distance_to(b_pose.origin) < 0.002 and _hidden(8) and _hidden(14),
		"every restored source is reserved first, so a car saved in another's original spot restores (%s)" % str(result.fallbacks))
	driving.reset_persistent_state()
	box("SwapBlocker", road + Vector3.UP, Vector3(1.0, 2.0, 1.0), 2)
	await frames(2)
	result = driving.restore_state(swap)
	check(bool(result.ok) and _has_fallback(result, "parked_014", "pose_blocked", "returned_to_source")
		and _has_fallback(result, "parked_008", "pose_blocked", "returned_to_source") and fleet_count("parked_008") == 0
		and fleet_count("parked_014") == 0 and not _hidden(8) and not _hidden(14),
		"when one half of a swap is blocked, its source returns and the other car cannot land on it (%s)" % str(result.fallbacks))
	clear_obstacles()
	await frames(2)
	await _people_section()
	driving.reset_persistent_state()
	result = driving.restore_state(saved)
	check(bool(result.ok) and (result.fallbacks as Array).is_empty(), "the original payload still restores cleanly afterwards")

## People are never enclosed by a restored car or a returning original.
func _people_section() -> void:
	driving.reset_persistent_state()
	if check(await board_record(18), "promote record 18"):
		var moved: Node3D = driving.vehicle
		var spot: Transform3D = _record(18).pose
		place(moved, Vector3(LANE_X - 1.2, 0.0, spot.origin.z - 4.0), PI, 0.0)
		check(await leave(), "leave car 18 on the road")
		var hidden_total := _kind_total_at(18)
		person(spot.origin, "fixture_curb_sitter")
		await frames(2)
		var before_reset: Variant = canonical(driving.snapshot_state())
		var predicted: Dictionary = driving.preflight_state({"version": 1, "sequence": 0, "vehicles": [], "parked_damage": []})
		check(not bool(predicted.ok) and "returned source" in str(predicted.reason) and not driving.reset_persistent_state()
			and moved.is_inside_tree() and str(_record(18).promoted) == "parked_018" and _hidden(18)
			and canonical(driving.snapshot_state()) == before_reset,
			"an original never returns onto a person in its curb spot: reset refuses atomically (%s)" % str(predicted.reason))
		clear_obstacles()
		await frames(2)
		check(driving.reset_persistent_state() and not moved.is_inside_tree() and str(_record(18).get("promoted", "")).is_empty()
			and (_record(18).body as StaticBody3D).collision_layer == (2 | 16) and _kind_total_at(18) == hidden_total + 1,
			"once the spot is clear, reset returns the original solid, exactly once")
	driving.reset_persistent_state()
	person(_at(saved.vehicles[0]), "fixture_bystander")
	await frames(2)
	var result: Dictionary = driving.restore_state(saved)
	check(bool(result.ok) and _has_fallback(result, "parked_006", "pose_blocked", "returned_to_source") and fleet_count("parked_006") == 0,
		"a person at a saved destination sends that car back to its curb instead of enclosing them")
	clear_obstacles()
	await frames(2)
	driving.reset_persistent_state()
	var before: Variant = canonical(driving.snapshot_state())
	var fleet: int = traffic.player_fleet.size()
	person(_at(saved.vehicles[1]), "fixture_saved_blocker")
	person(driving.starter_home.origin, "fixture_home_blocker")
	await frames(2)
	result = driving.restore_state(saved)
	check(not bool(result.ok) and str(result.reason) == "no safe starter placement" and canonical(driving.snapshot_state()) == before
		and traffic.player_fleet.size() == fleet, "with saved, home and current starter spots all occupied, restore refuses without mutation")
	check(not bool(driving.preflight_state(saved).ok) and not driving.reset_persistent_state() and canonical(driving.snapshot_state()) == before,
		"preflight predicts that refusal and reset refuses atomically too")
	clear_obstacles()
	await frames(2)

func _occupied_section() -> void:
	var starter: Node3D = driving.starter
	if not check(await board(starter), "board the restored starter"):
		return
	var occupied: Dictionary = driving.snapshot_state()
	check(driving.validate_state(occupied).is_empty() and not "player_starter" in _snapshot_ids(occupied),
		"a snapshot while driving validates and excludes the occupied car")
	var predicted: Dictionary = driving.preflight_state(saved)
	check(not bool(predicted.ok) and str(predicted.reason) == "vehicle occupied", "preflight refuses while a car is occupied")
	var before: Variant = canonical(driving.snapshot_state())
	var fleet: int = traffic.player_fleet.size()
	check(not bool(driving.restore_state(saved).ok) and canonical(driving.snapshot_state()) == before and driving.vehicle == starter
		and traffic.player_fleet.size() == fleet, "restore refuses while occupied and changes nothing")
	check(not driving.reset_persistent_state() and canonical(driving.snapshot_state()) == before and driving.vehicle == starter
		and traffic.player_fleet.size() == fleet, "reset refuses while occupied and changes nothing")
	check(await leave(), "leave the starter")

func _mutated(change: Callable) -> Dictionary:
	var copy: Dictionary = saved.duplicate(true)
	change.call(copy)
	return copy

func _nine_cars(state: Dictionary) -> void:
	var many: Array = []
	for i in 9:
		many.append(state.vehicles[0].duplicate(true))
	state.vehicles = many

func _foreign_prototype(state: Dictionary) -> void:
	state.vehicles[0].prototype = "pickup" if str(state.vehicles[0].prototype) != "pickup" else "compact"

func _spaced_id(state: Dictionary) -> void:
	state.vehicles[0].id = "Parked 6"
	state.vehicles[0].source_id = "Parked 6"

func _invalid_section() -> void:
	var cases: Array = [
		["version 2", _mutated(func(s: Dictionary) -> void: s.version = 2)],
		["string version", _mutated(func(s: Dictionary) -> void: s.version = "1")],
		["negative sequence", _mutated(func(s: Dictionary) -> void: s.sequence = -1)],
		["unknown top-level field", _mutated(func(s: Dictionary) -> void: s.extra = true)],
		["vehicles not a list", _mutated(func(s: Dictionary) -> void: s.vehicles = {})],
		["nine remembered cars", _mutated(_nine_cars)],
		["duplicate vehicle id", _mutated(func(s: Dictionary) -> void: s.vehicles.append(s.vehicles[0].duplicate(true)))],
		["starter with a foreign id", _mutated(func(s: Dictionary) -> void: s.vehicles[1].id = "starter_two")],
		["non-finite position", _mutated(func(s: Dictionary) -> void: s.vehicles[0].position = [NAN, 0.0, 0.0])],
		["position out of bounds", _mutated(func(s: Dictionary) -> void: s.vehicles[0].position[1] = 5000.0)],
		["yaw out of range", _mutated(func(s: Dictionary) -> void: s.vehicles[0].yaw = 4.0)],
		["health above maximum", _mutated(func(s: Dictionary) -> void: s.vehicles[0].health = 120.0)],
		["dead car not disabled", _mutated(func(s: Dictionary) -> void: s.vehicles[0].health = 0.0)],
		["tire index four", _mutated(func(s: Dictionary) -> void: s.vehicles[0].flat_tires = [4])],
		["repeated tire", _mutated(func(s: Dictionary) -> void: s.vehicles[0].flat_tires = [1, 1])],
		["paint out of palette", _mutated(func(s: Dictionary) -> void: s.vehicles[0].paint = 6)],
		["fractional paint", _mutated(func(s: Dictionary) -> void: s.vehicles[0].paint = 2.5)],
		["unknown prototype", _mutated(func(s: Dictionary) -> void: s.vehicles[0].prototype = "tank")],
		["prototype differs from source", _mutated(_foreign_prototype)],
		["unknown vehicle field", _mutated(func(s: Dictionary) -> void: s.vehicles[0].color = "red")],
		["missing vehicle field", _mutated(func(s: Dictionary) -> void: s.vehicles[0].erase("last_used"))],
		["last use after sequence", _mutated(func(s: Dictionary) -> void: s.vehicles[0].last_used = float(s.sequence) + 1.0)],
		["source in both lists", _mutated(func(s: Dictionary) -> void: s.parked_damage[0].source_id = "parked_006")],
		["damage tire seven", _mutated(func(s: Dictionary) -> void: s.parked_damage[0].flat_tires = [7])],
		["id with spaces", _mutated(_spaced_id)],
		["source key extra field", _mutated(func(s: Dictionary) -> void: s.vehicles[0].source_key.lane = 2)],
		["not a dictionary", []],
	]
	var before: Variant = canonical(driving.snapshot_state())
	var fleet: int = traffic.player_fleet.size()
	for case in cases:
		var value = case[1]
		var reason: String = driving.validate_state(value)
		var predicted: Dictionary = driving.preflight_state(value)
		var result: Dictionary = driving.restore_state(value)
		check(not reason.is_empty() and not bool(predicted.ok) and not bool(result.ok) and canonical(driving.snapshot_state()) == before
			and traffic.player_fleet.size() == fleet, "invalid payload refused without mutation: %s (%s)" % [case[0], reason])
