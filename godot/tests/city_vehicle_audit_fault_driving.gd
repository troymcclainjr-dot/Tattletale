extends "res://scripts/city/city_driving.gd"
## Test seam only: deterministically fail a requested replacement allocation.
var fail_on_spawn := 0
var spawn_attempts := 0

func _spawn_remembered(id: String, pose: Transform3D, paint: int, kind: String) -> Node3D:
	if fail_on_spawn > 0:
		spawn_attempts += 1
		if spawn_attempts == fail_on_spawn:
			return null
	return super._spawn_remembered(id, pose, paint, kind)
