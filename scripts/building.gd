extends Node3D
## The whole place, front to back, in a row away from the camera:
##
##   street  |  front room  |  control room  |  vocal booth
##
## which is how a small studio in a narrow rented unit is laid out: the public
## room at the front, and you walk through the control room to reach the booth.
## Between each pair is a wall with a door in it.
##
## The camera always looks from the street side. To see the room someone is in,
## everything nearer the camera than that room is hidden: `show_from(n)` shows
## room n and the rooms beyond it. The wall just in front of room n becomes a low
## strip on the floor, and its door a low slice, so you can still see where the
## doorway is and whether the door is open. A wall can also leave a see-through
## copy of itself behind (the booth's window wall does).
##
## It also knows the floor plan: `walk_areas()` is everywhere someone's middle
## may be (the doorways only while their doors are open), and `obstacles` is the
## furniture.

const StreetSet := preload("res://scripts/street_set.gd")
const FrontSet := preload("res://scripts/front_set.gd")
const StudioSet := preload("res://scripts/studio_set.gd")
const Door := preload("res://scripts/door.gd")

const RADIUS := 0.26                 # paper_actor.gd's: how close a middle may come to a wall in front of him or behind
const REACH := 0.4                   # and to a wall beside him: his hands and feet reach that far
const CONTROL_DOOR := [0.3, 1.2]     # the doorway from the front room to the control room, x from .. to
const EDGE := Color(0.07, 0.06, 0.12)
const GHOST_WALL := 0.1              # how solid a see-through wall is (0 clear .. 1 solid)

var street: Node3D
var front: Node3D
var control: Node3D
## Front to back. "node": what to show or hide; "area": its floor (x, z);
## "cam_max_x": how far right the camera may go before the room's right wall
## would hide it; "cam_near": how close the camera comes (1 is the usual step);
## "cam_y": how high it sits (under the ceiling indoors); "look_y": how high it aims.
var rooms: Array = []
## walls[i] stands between rooms[i] and rooms[i + 1]. "node": the wall; "stub":
## the low strip shown when it is cut away; "door"; "z": its middle; "ghost"
## (optional): a see-through copy of the wall, shown instead of nothing while
## someone is in the room just behind it.
var walls: Array = []
var doors: Array = []
var obstacles: Array = []
var portals: Array = []              # none here; a Place may have some (stairs)
var active := -1
var title := "THE BACK ROOM"
var arrive := Vector3(1.97, 0, 7.35)     # on the pavement, in front of the street door


func build() -> void:
	street = StreetSet.new()
	street.name = "Street"
	add_child(street)
	street.build()
	front = FrontSet.new()
	front.name = "FrontRoom"
	add_child(front)
	front.build()
	control = StudioSet.new()
	control.name = "ControlRoom"
	add_child(control)
	control.build()

	rooms = [
		{"name": "street", "node": street, "area": street.AREA, "cam_max_x": 99.0, "cam_near": 1.45, "cam_y": 2.9, "look_y": 1.35},
		{"name": "front room", "node": front, "area": front.AREA, "cam_max_x": front.X1 - 1.7, "cam_near": 0.9, "cam_y": 2.2, "look_y": 0.8},
		{"name": "control room", "node": control, "area": control.AREA, "cam_max_x": control.X1 - 1.7, "cam_near": 1.0, "cam_y": 2.2, "look_y": 0.8},
		{"name": "booth", "node": control.booth, "area": control.BOOTH_AREA, "cam_max_x": control.BOOTH_X1 - 1.7, "cam_near": 0.85, "cam_y": 2.2, "look_y": 0.8},
	]
	var wall_c := _control_wall()
	walls = [
		_wall(street.facade, street.door, street.WALL_Z0, street.WALL_Z1, street.SHOP_X0, street.SHOP_X1, street.DOOR),
		_wall(wall_c[0], wall_c[1], control.Z1, front.Z0, control.X0 - control.T, control.X1 + control.T, CONTROL_DOOR),
		_wall(control.wall_to_booth, control.booth_door, control.Z0 - control.T, control.Z0, control.X0 - control.T, control.X1 + control.T, control.BOOTH_DOOR),
	]
	for wall: Dictionary in walls:
		doors.append(wall["door"])
	# From inside the booth the wall with the window in it is worth seeing: the
	# mic stands at the glass.
	walls[2]["ghost"] = _ghost_of(control.wall_to_booth)
	obstacles = []
	obstacles.append_array(street.OBSTACLES)
	obstacles.append_array(front.OBSTACLES)
	obstacles.append_array(control.OBSTACLES)


## The wall between the front room and the control room, and its padded door.
func _control_wall() -> Array:
	var node := Kit.group(self, Vector3.ZERO, Vector3.ZERO, "WallToControl")
	var look := Kit.tex("stucco", 2.0, Color(0.86, 0.74, 0.68))
	var z0: float = control.Z1
	var z1: float = front.Z0
	var zc := (z0 + z1) * 0.5
	var h: float = control.H
	for seg in [
		[control.X0 - control.T, CONTROL_DOOR[0], 0.0, h],
		[CONTROL_DOOR[0], CONTROL_DOOR[1], 2.05, h],
		[CONTROL_DOOR[1], control.X1 + control.T, 0.0, h],
	]:
		Kit.box(node, Vector3(seg[1] - seg[0], seg[3] - seg[2], z1 - z0), Vector3((seg[0] + seg[1]) * 0.5, (seg[2] + seg[3]) * 0.5, zc), look)
	# The frame stands 15 mm into the opening: a frame face lying exactly on the
	# cut end of the wall flickers (two surfaces in one place).
	for x in [CONTROL_DOOR[0] - 0.02, CONTROL_DOOR[1] + 0.02]:
		Kit.box(node, Vector3(0.07, 2.1, z1 - z0 + 0.06), Vector3(x, 1.05, zc), Color(0.23, 0.16, 0.11))
	Kit.box(node, Vector3(CONTROL_DOOR[1] - CONTROL_DOOR[0] + 0.11, 0.07, z1 - z0 + 0.06), Vector3((CONTROL_DOOR[0] + CONTROL_DOOR[1]) * 0.5, 2.07, zc), Color(0.23, 0.16, 0.11))
	# Skirting board, left and right of the door.
	for run in [[front.X0, CONTROL_DOOR[0] - 0.055], [CONTROL_DOOR[1] + 0.055, front.X1]]:
		Kit.box(node, Vector3(run[1] - run[0], 0.12, 0.03), Vector3((run[0] + run[1]) * 0.5, 0.06, z1 + 0.015), Color(0.23, 0.16, 0.11))
	var door: Node3D = Door.new()
	door.name = "ControlDoor"
	door.position = Vector3(CONTROL_DOOR[1] - 0.01, 0, zc)
	add_child(door)
	door.build_leaf(CONTROL_DOOR[1] - CONTROL_DOOR[0] - 0.02, 2.02, Color(0.45, 0.16, 0.14))    # padded red vinyl
	for y in [0.45, 1.0, 1.55]:     # its studs
		for x in [-0.22, -0.44, -0.66]:
			Kit.ball(door.leaf, 0.022, Vector3(x, y, 0.03), Color(0.85, 0.68, 0.25), 5)
	return [node, door]


func _wall(node: Node3D, door: Node3D, z0: float, z1: float, x0: float, x1: float, gap: Array) -> Dictionary:
	var stub := Kit.group(self, Vector3.ZERO, Vector3.ZERO, node.name + "Stub")
	var zc := (z0 + z1) * 0.5
	for seg in [[x0, gap[0]], [gap[1], x1]]:
		Kit.box(stub, Vector3(seg[1] - seg[0], 0.14, z1 - z0), Vector3((seg[0] + seg[1]) * 0.5, 0.07, zc), EDGE)
	stub.visible = false
	# Where a middle may be while going through: a strip down the doorway that reaches into both rooms.
	# It is narrow, so his hands stay clear of the frame; he slides along the wall into it (paper_actor.gd).
	var keep := minf(REACH - 0.02, (gap[1] - gap[0]) * 0.5 - 0.05)
	door.passage = Rect2(gap[0] + keep, z0 - RADIUS - 0.04, gap[1] - gap[0] - keep * 2.0, z1 - z0 + RADIUS * 2.0 + 0.08)
	return {"node": node, "stub": stub, "door": door, "z": zc}


## A see-through copy of a wall, to show in its place when it is cut away. The
## set says what each part is with set_meta("ghost", ...): "wall" parts turn
## faint, "keep" parts stay as they are (window and door frames, glass, the
## skirting board), and everything else on the wall is left out.
func _ghost_of(wall: Node3D) -> Node3D:
	var ghost := wall.duplicate() as Node3D
	ghost.name = String(wall.name) + "Ghost"
	add_child(ghost)
	_fade(ghost)
	ghost.visible = false
	return ghost


func _fade(node: Node) -> void:
	for child in node.get_children():
		var part: String = child.get_meta("ghost", "")
		if part == "wall" and child is MeshInstance3D:
			var mat := (child.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = GHOST_WALL
			child.material_override = mat
		elif part != "keep" and (child is VisualInstance3D):
			child.visible = false
		_fade(child)


# What main.gd asks of any place (place.gd answers the same):

func room_at_pos(pos: Vector3, _was := 0) -> int:
	return room_at(pos.z)


func cut_of(n: int) -> int:
	return n


func show_room(n: int) -> void:
	show_from(n)


func usables() -> Array:
	return doors.duplicate()


## Which room a spot is in, by how far back it is.
func room_at(z: float) -> int:
	for i in walls.size():
		if z > walls[i]["z"]:
			return i
	return walls.size()


## Show room n and everything beyond it; hide what is nearer the camera.
func show_from(n: int) -> void:
	active = n
	for i in rooms.size():
		rooms[i]["node"].visible = i >= n
	for i in walls.size():
		var cut: bool = i < n                      # this wall is between the camera and room n
		walls[i]["node"].visible = not cut
		walls[i]["stub"].visible = i == n - 1      # the wall he has just come through
		walls[i]["door"].visible = i >= n - 1
		walls[i]["door"].cut_away(cut)
		if walls[i].has("ghost"):
			walls[i]["ghost"].visible = i == n - 1


## Everywhere someone's middle may be: each room's floor, in from the walls, and
## each doorway whose door is open.
func walk_areas() -> Array:
	var out: Array = []
	for room: Dictionary in rooms:
		out.append((room["area"] as Rect2).grow_individual(-REACH, -RADIUS, -REACH, -RADIUS))
	for door: Node3D in doors:
		if door.is_open:
			out.append(door.passage)
	return out
