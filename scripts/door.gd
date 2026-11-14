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
## whose hinge is on the right of its opening needs no turning. For a door in a
## wall that runs the other way, set `shut_angle` (and the node's own turn to
## match) before building the leaf. A double door is two of these: give the one
## that is used the other as its `mate` and they swing together.
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
## `cut_away(true)`: the door stays where it is but is see-through, and how
## see-through depends on how near the player is (`show_near`, called every
## frame by the scene). From across the room it cannot be seen at all; walking
## up to it, it comes into view, so he can find it and see whether it is open
## without it ever covering the room. This is the rule for every door in every
## place.

signal swung(is_open: bool)

const GHOST := 0.42            # how solid a cut-away door looks with the player right at it (1 is solid)
const GHOST_NEAR := 1.2        # metres from the doorway: this close it is as solid as it gets
const GHOST_FAR := 3.4         # and from here on it cannot be seen

var open_angle := -100.0       # degrees about Y when fully open
var shut_angle := 0.0
var open_time := 0.75          # seconds; opening overshoots a little and settles
var shut_time := 0.55          # closing speeds up into the frame
var label_height := 1.45
var use_reach := 1.25          # metres from the middle of the doorway
var is_open := false
var passage := Rect2()         # floor space (x, z) that opens up when the door does
var mate: Node3D               # the other leaf of a double door: it swings when this one does
var open_name := "OPEN DOOR"   # what it is called over the door while it is shut
var shut_name := "CLOSE DOOR"  # and while it is open
var leaf: Node3D               # the door itself
var stub: Node3D               # unused now (a low slice once stood in for a cut-away door); kept so old sets still load

var _middle := Vector3.ZERO    # middle of the doorway, in the parent's space
var _cut := false              # its wall is cut away
var _ghosts := {}              # this door's see-through copy of each material it is made of
var _ghost_now := -1.0         # how solid those copies are now
var _swing: Tween


func _init() -> void:
	leaf = Node3D.new()
	add_child(leaf)
	stub = Node3D.new()
	stub.visible = false
	add_child(stub)


## A plain door: a slab with a raised panel and a knob. `width`, `height` and
## `thick` in metres.
func build_leaf(width: float, height: float, colour: Color, to_left := true, thick := 0.05) -> void:
	var way := -1.0 if to_left else 1.0
	Kit.block(leaf, Vector3(width, height, thick), Vector3(way * width * 0.5, 0.004, 0), colour)
	Kit.block(leaf, Vector3(width * 0.68, height * 0.35, thick + 0.01), Vector3(way * width * 0.5, height * 0.54, 0), colour.darkened(0.14))
	Kit.ball(leaf, 0.04, Vector3(way * (width - 0.08), 1.0, thick * 0.5 + 0.025), Color(0.85, 0.68, 0.25))
	Kit.ball(leaf, 0.04, Vector3(way * (width - 0.08), 1.0, -thick * 0.5 - 0.025), Color(0.85, 0.68, 0.25))
	_middle = position + Vector3(way * width * 0.5, 0, 0).rotated(Vector3.UP, deg_to_rad(shut_angle))


## A barred door (a cell, a cage): upright bars in a steel frame.
func build_bars(width: float, height: float, to_left := true) -> void:
	var way := -1.0 if to_left else 1.0
	var steel := Color(0.3, 0.32, 0.36)
	for y in [0.03, height * 0.5, height - 0.03]:
		Kit.box(leaf, Vector3(width, 0.06, 0.05), Vector3(way * width * 0.5, y, 0), steel)
	var n := maxi(int(width / 0.12), 2)
	for i in n + 1:
		Kit.cyl(leaf, 0.013, height, Vector3(way * width * float(i) / float(n), height * 0.5, 0), steel, Vector3.ZERO, 5)
	Kit.box(leaf, Vector3(0.12, 0.2, 0.08), Vector3(way * (width - 0.1), 1.0, 0), Color(0.2, 0.21, 0.24))    # the lock
	_middle = position + Vector3(way * width * 0.5, 0, 0).rotated(Vector3.UP, deg_to_rad(shut_angle))


## Say where the middle of the doorway is (a double door's is between its leaves).
func set_middle(at: Vector3) -> void:
	_middle = at


func cut_away(on: bool) -> void:
	stub.visible = false
	if on == _cut:
		return
	_cut = on
	_ghost(leaf, on)
	if on:
		_ghost_now = -1.0
		_set_ghost(0.0)          # unseen until the scene says how near the player is
	else:
		leaf.visible = true


## Say where the player is, every frame. A cut-away door shows by how near he
## is to the doorway: not at all from GHOST_FAR, as solid as GHOST at GHOST_NEAR.
func show_near(at: Vector3) -> void:
	if _cut:
		var gap := Vector2(at.x - _middle.x, at.z - _middle.z).length()
		_set_ghost(GHOST * (1.0 - smoothstep(GHOST_NEAR, GHOST_FAR, gap)))


func _set_ghost(solid: float) -> void:
	if absf(solid - _ghost_now) < 0.004:
		return
	_ghost_now = solid
	leaf.visible = solid > 0.004
	for made: StandardMaterial3D in _ghosts:
		(_ghosts[made] as StandardMaterial3D).albedo_color.a = made.albedo_color.a * solid


## Give every part under `node` its see-through copy, or the material it was made with.
func _ghost(node: Node, on: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			if not child.has_meta("solid"):
				child.set_meta("solid", child.material_override)
			var solid: StandardMaterial3D = child.get_meta("solid")
			if on and not _ghosts.has(solid):
				var faint := solid.duplicate() as StandardMaterial3D
				faint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_ghosts[solid] = faint
			child.material_override = _ghosts[solid] if on else solid
		_ghost(child, on)


func use_name() -> String:
	return shut_name if is_open else open_name


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
	if mate and mate.is_open != want:
		mate.set_open(want, instant)
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
