extends "res://tests/city_vehicle_contract_fixture.gd"
## Independent regressions for owner source planning plus safety/staging fixes.
## Run after root reviews .work/priorities-five/vehicle-safety-rebased.patch.
const FaultDriving := preload("res://tests/city_vehicle_audit_fault_driving.gd")

func build_world() -> void:
	await super.build_world()
	# Keep the production setup, changing only the allocation failure seam.
	traffic.unregister_player_vehicle(driving.starter)
	driving.free()
	driving = FaultDriving.new()
	level.add_child(driving)
	driving.setup(level)
	await frames(2)

func run_sections() -> void:
	tag = "vehicle_audit"
	await _source_swap_and_failed_dependency()
	await _npc_restore_clearance()
	await _starter_fallback_and_refusal()
	await _returned_source_clearance()
	await _allocation_failure_atomicity()
	await _external_claim_presence()

func _promote(index: int) -> Node3D:
	await stand(record_door(index))
	var car: Node3D = driving._promote_parked(parked.records[index].body)
	check(is_instance_valid(car), "promote source %d for audit fixture" % index)
	return car

func _entry(payload: Dictionary, id: String) -> Dictionary:
	for entry in payload.vehicles:
		if str(entry.id) == id:
			return entry
	return {}

func _remembered(id: String) -> Node3D:
	for car in driving.remembered:
		if is_instance_valid(car) and str(car.vehicle_id) == id:
			return car
	return null

func _set_saved_position(entry: Dictionary, at: Vector3, heading := 0.0) -> void:
	entry.position = [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)]
	entry.yaw = heading

## This independent gate runs with a real renderer and checks exact source
## poses. Keep its helper local: the shared headless fixture only exposes totals.
func _batch_instances_at(pose: Transform3D) -> int:
	var found := 0
	for batch in parked._batches.values():
		for index in maxi(0, batch.multimesh.visible_instance_count):
			var transform: Transform3D = batch.multimesh.get_instance_transform(index)
			found += int(transform.origin.distance_to(pose.origin) < 0.01)
	return found

func _source_swap_and_failed_dependency() -> void:
	var a_index := 0
	var b_index := 4
	var a_pose: Transform3D = parked.records[a_index].pose
	var b_pose: Transform3D = parked.records[b_index].pose
	var a_id := str(parked.records[a_index].source_id)
	var b_id := str(parked.records[b_index].source_id)
	var a := await _promote(a_index)
	if not is_instance_valid(a):
		return
	place(a, OPEN, 0.0)
	var b := await _promote(b_index)
	if not is_instance_valid(b):
		return
	place(b, a_pose.origin, atan2(a_pose.basis.z.x, a_pose.basis.z.z))
	place(a, b_pose.origin, atan2(b_pose.basis.z.x, b_pose.basis.z.z))
	await stand(SPAWN)
	var saved: Dictionary = driving.snapshot_state()
	check(driving.validate_state(saved).is_empty(), "swapped parked-source snapshot is valid")
	var preview: Dictionary = driving.preflight_state(saved)
	check(bool(preview.ok) and preview.fallbacks.is_empty(), "preflight reserves both swapped sources without false blockage")
	for repeat in 2:
		var restored: Dictionary = driving.restore_state(saved)
		check(bool(restored.ok) and restored.fallbacks.is_empty(), "source swap restores without order-dependent fallback %d" % repeat)
		a = _remembered(a_id)
		b = _remembered(b_id)
		check(is_instance_valid(a) and is_instance_valid(b) and a.global_position.distance_to(b_pose.origin) < 0.01
			and b.global_position.distance_to(a_pose.origin) < 0.01, "both swapped positions survive restore %d" % repeat)
		check(fleet_count(a_id) == 1 and fleet_count(b_id) == 1 and str(parked.records[a_index].promoted) == a_id
			and str(parked.records[b_index].promoted) == b_id, "swap has exactly one live body per reserved source %d" % repeat)
	# A depends on B's source being vacated, but B's saved destination is now
	# blocked. Returning B must force A to return too, never overlap B's source.
	var dependent := saved.duplicate(true)
	var blocked_at := Vector3(OPEN.x, 0.025, OPEN.z)
	_set_saved_position(_entry(dependent, b_id), blocked_at)
	box("BlockedSavedB", blocked_at + Vector3.UP * 0.8, Vector3(1.0, 1.6, 1.0), 2)
	await frames(2)
	var result: Dictionary = driving.restore_state(dependent)
	check(bool(result.ok) and result.fallbacks.size() == 2, "failed destination reactivates source and cascades dependency fallback")
	check(_remembered(a_id) == null and _remembered(b_id) == null and fleet_count(a_id) == 0 and fleet_count(b_id) == 0,
		"failed dependency leaves no live duplicate at either returned source")
	check(str(parked.records[a_index].promoted).is_empty() and str(parked.records[b_index].promoted).is_empty(), "both fallback originals are owned by parked batches again")
	parked.set_presence(a_pose.origin)
	check(_batch_instances_at(a_pose) == 1 and _batch_instances_at(b_pose) == 1, "fallback sources each submit exactly one original batch instance")
	clear_obstacles()
	driving.reset_persistent_state()
	await frames(2)

func _npc_restore_clearance() -> void:
	var index := 0
	var id := str(parked.records[index].source_id)
	var car := await _promote(index)
	if not is_instance_valid(car):
		return
	place(car, OPEN, 0.0)
	var saved: Dictionary = driving.snapshot_state()
	await stand(SPAWN)
	var resident := person(OPEN, "audit_restore_resident")
	await frames(2)
	var before := resident.global_position
	var result: Dictionary = driving.restore_state(saved)
	check(bool(result.ok) and result.fallbacks.size() == 1 and result.fallbacks[0].action == "returned_to_source", "NPC occupying saved hull causes explicit source fallback")
	check(fleet_count(id) == 0 and str(parked.records[index].promoted).is_empty() and resident.global_position == before,
		"restore neither overlaps nor teleports the NPC")
	clear_obstacles()
	driving.reset_persistent_state()
	await frames(2)

func _starter_fallback_and_refusal() -> void:
	var starter: Node3D = driving.starter
	var home: Transform3D = driving.starter_home
	var current := OPEN + Vector3(20, 0, 0)
	var blocked := OPEN + Vector3(40, 0, 0)
	place(starter, current, 0.0)
	await stand(SPAWN + Vector3(12, 0, 0))
	var home_blocker := make_ai_car(home.origin, float(driving.starter_home_yaw), "audit_home_blocker", 0.0)
	box("BlockedSavedStarter", blocked + Vector3.UP * 0.8, Vector3(1.0, 1.6, 1.0), 2)
	await frames(2)
	var saved: Dictionary = driving.snapshot_state()
	_set_saved_position(_entry(saved, str(starter.vehicle_id)), Vector3(blocked.x, 0.025, blocked.z))
	var before_home := home_blocker.global_position
	var result: Dictionary = driving.restore_state(saved)
	check(bool(result.ok) and result.fallbacks.size() == 1 and result.fallbacks[0].action == "kept_current", "blocked saved pose and occupied home retain a checked current starter pose")
	check(starter.global_position.distance_to(Vector3(current.x, 0.025, current.z)) < 0.01 and hull_clear(starter)
		and home_blocker.global_position == before_home, "starter fallback does not overlap or move the home blocker")
	box("BlockedCurrentStarter", starter.global_position + Vector3.UP * 0.8, Vector3(1.0, 1.6, 1.0), 2)
	await frames(2)
	var before: Dictionary = canonical(driving.snapshot_state())
	check(not bool(driving.preflight_state(saved).ok), "preflight refuses when saved/home/current starter poses are all blocked")
	result = driving.restore_state(saved)
	check(not bool(result.ok) and canonical(driving.snapshot_state()) == before, "unsafe starter restore refuses without changing persistent scene")
	check(not bool(driving.reset_persistent_state()) and canonical(driving.snapshot_state()) == before, "unsafe reset also refuses before removing cars or moving starter")
	clear_obstacles()
	remove_ai_car(home_blocker)
	check(bool(driving.reset_persistent_state()), "reset succeeds once a checked home is free")
	await frames(2)

func _external_claim_presence() -> void:
	await stand(SPAWN)
	var index := 0
	var record: Dictionary = parked.records[index]
	var pose: Transform3D = record.pose
	var inward := Vector3(-signf(pose.origin.x - LANE_X), 0, 0)
	var at := pose.origin + inward * 4.3
	var heading := atan2(-inward.x, -inward.z)
	var cruiser := make_ai_car(at, heading, "audit_external", 0.0, true)
	var neighbor := make_ai_car(at + Vector3(0, 0, 12), 0.0, "audit_neighbor", 0.0)
	traffic._update_presence()
	parked.set_presence(player.global_position)
	check(not cruiser.near_physics and not neighbor.near_physics and record.body.collision_layer == 0, "far claim fixture begins with culled neighboring physics")
	cruiser.speed = 12.0
	check(traffic.claim_external_vehicle(cruiser, "audit"), "claim a distant cruiser with clear initial hull")
	check((int(record.body.collision_layer) & 16) != 0 and neighbor.near_physics and (int(neighbor.collision_layer) & 16) != 0,
		"claim synchronously activates parked and AI obstacle hulls before any traffic tick")
	check(not cruiser.player_controlled and cruiser.external_owner == "audit" and not traffic.player_fleet.has(cruiser), "external activation retains exclusive fleet authority")
	traffic.release_external_vehicle(cruiser, "audit")
	traffic._update_presence()
	parked.set_presence(player.global_position)
	# A culled parked collider must also participate in claim-time clearance.
	place(cruiser, pose.origin, atan2(pose.basis.z.x, pose.basis.z.z))
	cruiser.set_presence(player.global_position)
	var claims := int(traffic.external_claims)
	check(not traffic.claim_external_vehicle(cruiser, "audit_overlap") and cruiser.external_owner.is_empty()
		and int(traffic.external_claims) == claims, "claim refuses overlap revealed by synchronous parked activation")
	remove_ai_car(cruiser)
	remove_ai_car(neighbor)
	traffic._update_presence()

func _returned_source_clearance() -> void:
	var index := 0
	var record: Dictionary = parked.records[index]
	var pose: Transform3D = record.pose
	var id := str(record.source_id)
	var empty := {"version": 1, "sequence": 0, "vehicles": [], "parked_damage": []}
	for occupant in ["resident", "explorer", "traffic"]:
		var car := await _promote(index)
		if not is_instance_valid(car):
			return
		place(car, OPEN, 0.0)
		# Promotion disables the original and place() teleports the live body in
		# the same frame. Let physics publish both before a ground ray or new AI
		# spawn queries the old source; otherwise stand() can land on the old roof.
		await frames(2)
		var blocker: Node3D = null
		if occupant == "resident":
			blocker = person(pose.origin, "audit_return_resident")
		elif occupant == "explorer":
			await stand(pose.origin)
		else:
			blocker = make_ai_car(pose.origin, atan2(pose.basis.z.x, pose.basis.z.z), "audit_source_blocker", 0.0)
		await frames(2)
		var source_exclude: Array[RID] = []
		var occupant_mask := 8 if occupant == "resident" else (4 if occupant == "explorer" else 16)
		var actually_occupied: bool = not driving._hull_clear_of(str(record.kind), pose, occupant_mask, source_exclude)
		print("[vehicle_audit_fixture] returned_source ", JSON.stringify({"occupant": occupant, "source": str(pose.origin),
			"player": str(player.global_position), "player_layer": player.collision_layer, "old_car": str(car.global_position),
			"source_layer": record.body.collision_layer, "ground_y": ground_y(pose.origin), "occupied": actually_occupied}))
		check(actually_occupied and int(record.body.collision_layer) == 0,
			"fixture has a physical " + occupant + " inside the vacated source before restore")
		var before: Dictionary = canonical(driving.snapshot_state())
		var old_id := car.get_instance_id()
		var preview: Dictionary = driving.preflight_state(empty)
		check(not bool(preview.ok) and "returned source" in str(preview.reason), "preflight refuses original curb return occupied by " + occupant)
		var result: Dictionary = driving.restore_state(empty)
		check(not bool(result.ok) and canonical(driving.snapshot_state()) == before and car.get_instance_id() == old_id,
			"blocked original return leaves existing remembered body and snapshot intact: " + occupant)
		check(not driving.reset_persistent_state() and canonical(driving.snapshot_state()) == before
			and str(record.promoted) == id and int(record.body.collision_layer) == 0,
			"unsafe reset never enables the original inside " + occupant)
		if occupant == "explorer":
			await stand(record_door(index))
		elif occupant == "traffic":
			remove_ai_car(blocker)
		else:
			clear_obstacles()
		await frames(2)
		check(driving.reset_persistent_state(), "curb return succeeds after " + occupant + " vacates")
		await frames(2)
		check(str(record.promoted).is_empty() and fleet_count(id) == 0, "safe original return relinquishes exactly one live owner: " + occupant)

func _allocation_failure_atomicity() -> void:
	var a := await _promote(0)
	if not is_instance_valid(a):
		return
	place(a, OPEN, 0.0)
	var b := await _promote(4)
	if not is_instance_valid(b):
		return
	place(b, OPEN + Vector3(12, 0, 0), 0.0)
	await stand(SPAWN)
	var saved: Dictionary = driving.snapshot_state()
	var before: Dictionary = canonical(saved)
	var a_instance := a.get_instance_id()
	var b_instance := b.get_instance_id()
	var fleet_size: int = traffic.player_fleet.size()
	var render_size: int = renderer.vehicles.size() if is_instance_valid(renderer) else 0
	for fail_at in [1, 2]:
		driving.fail_on_spawn = fail_at
		driving.spawn_attempts = 0
		var result: Dictionary = driving.restore_state(saved)
		check(not bool(result.ok) and int(result.restored) == 0 and "staging failed" in str(result.reason),
			"allocation failure %d is reported as refusal with no claimed restores" % fail_at)
		check(canonical(driving.snapshot_state()) == before and is_instance_valid(a) and is_instance_valid(b)
			and a.get_instance_id() == a_instance and b.get_instance_id() == b_instance,
			"allocation failure %d preserves exact current bodies and persistent state" % fail_at)
		check(traffic.player_fleet.size() == fleet_size and (not is_instance_valid(renderer) or renderer.vehicles.size() == render_size),
			"allocation failure %d releases every staged fleet/LOD registration" % fail_at)
		check(str(parked.records[0].promoted) == str(a.source_id) and str(parked.records[4].promoted) == str(b.source_id)
			and int(parked.records[0].body.collision_layer) == 0 and int(parked.records[4].body.collision_layer) == 0,
			"allocation failure %d never returns either source" % fail_at)
	driving.fail_on_spawn = 0
	driving.spawn_attempts = 0
	var restored: Dictionary = driving.restore_state(saved)
	check(bool(restored.ok) and restored.fallbacks.is_empty() and canonical(driving.snapshot_state()) == before,
		"the same snapshot restores exactly once allocations succeed")
	check(driving.reset_persistent_state(), "cleanup succeeds after allocation failure recovery")
	await frames(2)
