extends "res://tests/city_vehicle_persistence_smoke_runner.gd"
## Diagnostic only: retain all owner's assertions; expose each conjunct.
func _batch_instances_at(pose: Transform3D) -> int:
	var found := 0
	for batch in parked._batches.values():
		for index in maxi(0, batch.multimesh.visible_instance_count):
			var transform: Transform3D = batch.multimesh.get_instance_transform(index)
			found += int(transform.origin.distance_to(pose.origin) < 0.01)
	return found

func check(ok: bool, label: String) -> bool:
	if label == "the original returns once, with its collider, as a fresh batch car":
		var record: Dictionary = parked.records[PROMOTED]
		var pose: Transform3D = record.pose
		var batches: Array = []
		for key in parked._batches:
			var batch: MultiMeshInstance3D = parked._batches[key]
			if not str(key).begins_with(str(record.kind)):
				continue
			var poses: Array = []
			for index in maxi(0, batch.multimesh.visible_instance_count):
				poses.append(str(batch.multimesh.get_instance_transform(index).origin))
			batches.append({"key": str(key), "visible": batch.multimesh.visible_instance_count, "poses": poses})
		print("[eviction_probe] ", JSON.stringify({"layer": record.body.collision_layer, "presence": record.presence,
			"promoted": record.promoted, "health": record.health, "flats": record.flat_tires,
			"damage_model": record.has("damage_model"), "matches": _batch_instances_at(pose), "source": str(pose.origin),
			"player": str(player.global_position), "batches": batches}))
	return super.check(ok, label)
