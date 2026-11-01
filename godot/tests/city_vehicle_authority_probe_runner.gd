extends "res://tests/city_vehicle_authority_smoke_runner.gd"
## Observe failed conjuncts without changing controls, duration or assertions.
var _player_trace: Array[Dictionary] = []
var _approach_trace: Array[Dictionary] = []
var _player_hits_before := -1
var _approach_samples := 0
var _approach_overlaps := 0

func place(car: Node3D, at: Vector3, heading: float, speed := 0.0) -> void:
	super.place(car, at, heading, speed)
	if is_instance_valid(patrol) and car == patrol and at == OPEN and is_equal_approx(speed, 8.0):
		_player_hits_before = player.vehicle_hits
		_player_trace.clear()

func _car_state(car: Node3D) -> Dictionary:
	return {"id": car.vehicle_id, "position": str(car.global_position), "speed": car.speed,
		"velocity": str(car.velocity), "drive_velocity": str(car.drive_velocity),
		"state": car.state, "health": car.health, "disabled": car.disabled,
		"layer": car.collision_layer, "near_physics": car.near_physics,
		"owner": car.external_owner, "distance": car.distance_travelled,
		"leader_distance": car.leader_distance, "contacts": car.drive_contacts}

func _capsule_clear_of(mask: int) -> bool:
	var clear := super._capsule_clear_of(mask)
	if _player_hits_before >= 0 and _player_trace.size() < 125:
		_player_trace.append({"clear": clear, "player": str(player.global_position),
			"velocity": str(player.velocity), "hits": player.vehicle_hits,
			"impact_recovery": player.impact_recovery, "impact_cooldown": player.impact_cooldown,
			"enabled": player.enabled, "seated": player._seated, "layer": player.collision_layer,
			"car": _car_state(patrol), "events": external_events.duplicate(true)})
	return clear

func hull_clear(car: Node3D) -> bool:
	var clear := super.hull_clear(car)
	if str(car.vehicle_id) == "fixture_approach":
		_approach_samples += 1
		_approach_overlaps += int(not clear)
		if (_approach_samples % 30 == 0 or not clear) and _approach_trace.size() < 30:
			var sample := _car_state(car)
			sample["clear"] = clear
			sample["tick"] = _approach_samples
			sample["overlaps"] = _overlaps(car) if not clear else []
			_approach_trace.append(sample)
	return clear

func _overlaps(car: Node3D) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part in car.collision_parts:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = part.shape
		query.transform = car.global_transform
		query.collision_mask = 2 | 8 | 16
		query.margin = 0.0
		query.exclude = [car.get_rid()]
		for hit in car.get_world_3d().direct_space_state.intersect_shape(query, 8):
			var body: Node3D = hit.collider
			found.append({"name": str(body.name), "layer": body.collision_layer, "position": str(body.global_position)})
	return found

func check(ok: bool, label: String) -> bool:
	if label.begins_with("external throttle drives"):
		print("[authority_probe] throttle ", JSON.stringify(_car_state(patrol)))
	if label == "a police car stops at the on-foot explorer, who stumbles exactly once":
		print("[authority_probe] player ", JSON.stringify({"hits_before": _player_hits_before,
			"hits_after": player.vehicle_hits, "events": external_events, "trace": _player_trace}))
	if label.begins_with("an approaching AI car sweeps"):
		var final_state: Dictionary = {}
		for car in traffic.vehicles:
			if str(car.vehicle_id) == "fixture_approach":
				final_state = _car_state(car)
		print("[authority_probe] approach ", JSON.stringify({"car": final_state,
			"patrol": _car_state(patrol), "samples": _approach_samples,
			"overlap_samples": _approach_overlaps, "trace": _approach_trace}))
	return super.check(ok, label)
