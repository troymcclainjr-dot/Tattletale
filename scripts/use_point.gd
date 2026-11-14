extends Node3D
## A spot on the floor that E can be used at, for anything that is not a door, a
## person or a staircase: a rack of clothes, a bed, a basketball. It is usable
## like a door (`use_name`, `use_spot`, `use_reach`, `label_spot`, `use`); the
## scene decides what happens when `used` fires, from `id`.
##
##   var rack: Node3D = p.use_point(band, "TRY A HAT", u, v, "outfit:hat")     # place.gd

signal used(id: String, by: Node3D)

var id := ""
var label := "USE"
var use_reach := 1.1
var label_height := 1.5


func use_name() -> String:
	return label


func use_spot() -> Vector3:
	return global_position


func label_spot() -> Vector3:
	return global_position + Vector3(0, label_height, 0)


func use(by: Node3D = null) -> void:
	used.emit(id, by)
