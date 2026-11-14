extends Node3D
## A spot that takes whoever uses it somewhere else in the same place: the foot
## of a staircase, say. It is usable like a door (`use_name`, `use_spot`,
## `use_reach`, `label_spot`, `use`); the scene does the move when `used` fires.

signal used(to: Vector3)

var label := "GO"
var to := Vector3.ZERO         # where it leads, on the floor
var use_reach := 1.0
var label_height := 1.5


func use_name() -> String:
	return label


func use_spot() -> Vector3:
	return global_position


func label_spot() -> Vector3:
	return global_position + Vector3(0, label_height, 0)


func use(_by: Node3D = null) -> void:
	used.emit(to)
