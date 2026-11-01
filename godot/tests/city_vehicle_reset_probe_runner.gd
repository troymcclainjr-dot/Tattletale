extends "res://tests/city_vehicle_persistence_smoke_runner.gd"
## Diagnostic only: sample the reset boundary before/after physics publishes
## the preceding exit. All owner's assertions and reset logic stay unchanged.
func _persistence_section() -> void:
	_print_reset_boundary("immediate_after_exit")
	await frames(2)
	_print_reset_boundary("after_two_frames")
	await super._persistence_section()

func _print_reset_boundary(phase: String) -> void:
	var empty := {"version": 1, "sequence": 0, "vehicles": [], "parked_damage": []}
	var ignored: Array = driving.remembered.duplicate()
	ignored.append_array(driving.forgotten)
	var sources: Array[Dictionary] = []
	for index in parked.records.size():
		var record: Dictionary = parked.records[index]
		if str(record.get("promoted", "")).is_empty():
			continue
		var pose: Transform3D = record.pose
		var exclude: Array[RID] = []
		var clear: bool = driving._hull_clear_of(str(record.kind), pose, 4 | 8, exclude)
		var cars: bool = driving._pose_conflicts(str(record.kind), pose, ignored, index, [], true)
		sources.append({"id": record.source_id, "pose": str(pose.origin), "people_clear": clear, "car_conflict": cars})
	var body_pose: Transform3D = PhysicsServer3D.body_get_state(player.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	print("[vehicle_reset_probe] ", JSON.stringify({"phase": phase, "preflight": driving.preflight_state(empty),
		"last_restore": driving.last_restore, "active": driving.active, "player_node": str(player.global_position),
		"player_physics": str(body_pose.origin), "player_layer": player.collision_layer, "player_velocity": str(player.velocity),
		"starter": str(driving.starter.global_position), "starter_home": str(driving.starter_home.origin), "sources": sources}))
