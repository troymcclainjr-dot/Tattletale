extends Node3D
## A hinged door that swings open and shut. Use it for any door:
##
##   var door: Node3D = Door.new()     # const Door := preload("res://scripts/door.gd")
##   door.position = <the hinge, on the floor>
##   door.open_angle = -100.0          # degrees about the hinge; the sign picks which way it opens
##   parent.add_child(door)
##   door.build_leaf(0.9, 2.02, Color(0.33, 0.47, 0.5))   # or add your own parts to door.leaf
##
## The leaf runs from the hinge towards -x (build_leaf's `to_left`), so a door
## whose hinge is on the right of its opening needs no turning.
##
## It is something the player can use: it has `use_name()`, `use_spot()`,
## `use_reach`, `label_spot()` and `use(by)`, which is all the scene asks of
## anything usable. It is used from where it stands, so it works from both sides.
##
## A door also knows the gap it leaves in the floor plan: `passage` is where
## someone's middle may be while walking through. The scene lets people into it
## only while `is_open`.
##
## When the wall a door is in is cut away so the camera can see past it, call
## `cut_away(true)`: the leaf hides and a low slice of it shows instead, so the
## player can still see where the door is and whether it is open.

signal swung(is_open: bool)

var open_angle := -100.0       # degrees about Y when fully open
var shut_angle := 0.0
var open_time := 0.75          # seconds; opening overshoots a little and settles
var shut_time := 0.55          # closing speeds up into the frame
var label_height := 1.45
var use_reach := 1.25          # metres from the middle of the doorway
var is_open := false
var passage := Rect2()         # floor space (x, z) that opens up when the door does
var leaf: Node3D               # the door itself
var stub: Node3D               # a low slice of it, shown when its wall is cut away

var _middle := Vector3.ZERO    # middle of the doorway, in the parent's space
var _swing: Tween


func _init() -> void:
	leaf = Node3D.new()
	add_child(leaf)
	stub = Node3D.new()
	stub.visible = false
	add_child(stub)


## A plain door: a slab with a raised panel and a knob, and the low slice for
## cut-away walls. `width` and `height` in metres.
func build_leaf(width: float, height: float, colour: Color, to_left := true) -> void:
	var way := -1.0 if to_left else 1.0
	Kit.block(leaf, Vector3(width, height, 0.05), Vector3(way * width * 0.5, 0.01, 0), colour)
	Kit.block(leaf, Vector3(width * 0.68, height * 0.35, 0.06), Vector3(way * width * 0.5, height * 0.54, 0), colour.darkened(0.14))
	Kit.ball(leaf, 0.04, Vector3(way * (width - 0.08), 1.0, 0.05), Color(0.85, 0.68, 0.25))
	Kit.ball(leaf, 0.04, Vector3(way * (width - 0.08), 1.0, -0.05), Color(0.85, 0.68, 0.25))
	Kit.block(stub, Vector3(width, 0.14, 0.05), Vector3(way * width * 0.5, 0.0, 0), colour)
	_middle = position + Vector3(way * width * 0.5, 0, 0)


func cut_away(on: bool) -> void:
	leaf.visible = not on
	stub.visible = on


func use_name() -> String:
	return "CLOSE DOOR" if is_open else "OPEN DOOR"


func use_spot() -> Vector3:
	return _middle


func label_spot() -> Vector3:
	return _middle + Vector3(0, label_height, 0)


func use(_by: Node3D = null) -> void:
	set_open(not is_open)


## Swing to open or shut from wherever the door is now, so using it again
## part-way through a swing turns it round without a jump.
func set_open(want: bool, instant := false) -> void:
	is_open = want
	if _swing:
		_swing.kill()
	var goal := deg_to_rad(open_angle if want else shut_angle)
	if instant:
		rotation.y = goal
		swung.emit(is_open)
		return
	_swing = create_tween()
	if want:
		_swing.tween_property(self, "rotation:y", goal, open_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_swing.tween_property(self, "rotation:y", goal, shut_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing.tween_callback(func() -> void: swung.emit(is_open))
