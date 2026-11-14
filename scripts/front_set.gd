extends Node3D
## The front room: where you come in off the street. A reception counter, a soda
## machine, two waiting chairs and whatever the owner has pinned to the walls.
## Small studios in rented units put the public room at the front and make you
## walk through it, and then through the control room, to reach the booth.
##
## Layout (metres): x -3..3.5, z 2.65 (the wall to the control room) .. 6.2 (the
## shopfront). This node is the room; both of those walls belong to building.gd,
## but what hangs on the control-room wall is built here, since it is this
## room's decoration and hides with it.

const Props := preload("res://scripts/props.gd")

const X0 := -3.0
const X1 := 3.5
const Z0 := 2.65
const Z1 := 6.2
const H := 2.9
const T := 0.15
const DOOR_X := [0.3, 1.2]            # building.gd's CONTROL_DOOR, the doorway in the back wall
const RESTROOM_Z := [3.71, 4.59]      # the restroom door's frame on the left wall

const AREA := Rect2(X0, Z0, X1 - X0, Z1 - Z0)
const OBSTACLES: Array[Rect2] = [
	Rect2(-2.8, 3.3, 1.7, 0.5),       # reception counter
	Rect2(-2.45, 2.7, 0.5, 0.5),      # chair behind it
	Rect2(-3.0, 4.75, 0.72, 0.85),    # soda machine
	Rect2(2.85, 3.25, 0.65, 0.6),     # waiting chair
	Rect2(2.85, 4.1, 0.65, 0.6),      # waiting chair
	Rect2(2.95, 4.9, 0.55, 0.5),      # side table
	Rect2(2.85, 5.55, 0.6, 0.6),      # plant
]

const WOOD := Color(0.42, 0.29, 0.17)
const WOOD_DARK := Color(0.23, 0.16, 0.11)
const BLACK := Color(0.08, 0.08, 0.09)
const STEEL := Color(0.62, 0.64, 0.67)
const CREAM := Color(0.93, 0.9, 0.8)
const EDGE := Color(0.07, 0.06, 0.12)
const WAINSCOT := Color(0.4, 0.26, 0.56)      # purple boards to the dado rail
const RAIL := Color(0.98, 0.76, 0.2)          # and a mustard rail on top
const PAPER := "kit_memphis"                   # confetti wallpaper above it

var ceiling: Node3D


func build() -> void:
	_shell()
	_counter()
	_waiting()
	_soda_machine()
	_walls()


func _shell() -> void:
	var w := X1 - X0
	var d := Z1 - Z0
	var cx := (X0 + X1) * 0.5
	var cz := (Z0 + Z1) * 0.5
	var paper := Kit.tex(PAPER, 1.5, Color(0.95, 0.92, 0.85))
	Kit.box(self, Vector3(w + T * 2, 0.3, d), Vector3(cx, -0.15, cz), Kit.tex("lino", 1.6, Color(0.62, 0.72, 0.66)))
	Kit.box(self, Vector3(w + T * 2 + 0.04, 0.34, 0.05), Vector3(cx, -0.15, Z1 + 0.025), EDGE)
	for x in [X0 - T * 0.5, X1 + T * 0.5]:
		Kit.box(self, Vector3(T, H, d), Vector3(x, H * 0.5, cz), paper)
		Kit.box(self, Vector3(T + 0.04, H + 0.1, 0.05), Vector3(x, H * 0.5 + 0.05, Z1 + 0.025), EDGE)
	# A dark skirting board along both side walls, boards above it to a rail.
	Kit.box(self, Vector3(0.03, 0.12, d), Vector3(X0 + 0.015, 0.06, cz), WOOD_DARK)
	Kit.box(self, Vector3(0.03, 0.12, d), Vector3(X1 - 0.015, 0.06, cz), WOOD_DARK)
	for run in [[Z0, RESTROOM_Z[0] - 0.02], [RESTROOM_Z[1] + 0.02, Z1]]:
		_dado(Vector3(X0, 0, run[0]), Vector3(X0, 0, run[1]), 1.0)
	_dado(Vector3(X1, 0, Z0), Vector3(X1, 0, Z1), -1.0)

	# Drop ceiling and one buzzing strip light.
	ceiling = Kit.group(self, Vector3.ZERO, Vector3.ZERO, "Ceiling")
	Kit.box(ceiling, Vector3(w + T * 2, 0.1, d), Vector3(cx, H + 0.05, cz), Kit.tex("ceiling_tile", 0.6, Color(0.95, 0.94, 0.9)))
	Kit.box(ceiling, Vector3(w + T * 2 + 0.04, 0.14, 0.05), Vector3(cx, H + 0.05, Z1 + 0.025), EDGE)
	Kit.box(ceiling, Vector3(1.2, 0.02, 0.3), Vector3(0.3, H - 0.008, 4.4), Kit.flat(Color(0.95, 1.0, 0.95), 1.5))
	Kit.omni(self, Vector3(0.3, H - 0.4, 4.4), Color(0.92, 1.0, 0.94), 1.0, 7.0)

	# Doormat inside the street door.
	Kit.box(self, Vector3(0.9, 0.014, 0.5), Vector3(1.97, 0.007, 5.85), Color(0.3, 0.22, 0.16))
	Kit.box(self, Vector3(0.7, 0.016, 0.3), Vector3(1.97, 0.008, 5.85), Color(0.42, 0.32, 0.22))


## Boards from the skirting up to a rail, along a wall from a to b (on the
## wall's face); `into` is which way the room is from it, along x for a side
## wall (+1 or -1) or 0 for the back wall, which faces +z.
func _dado(a: Vector3, b: Vector3, into: float) -> void:
	var mid := (a + b) * 0.5
	if into == 0.0:
		var run := b.x - a.x
		Kit.box(self, Vector3(run, 0.83, 0.02), Vector3(mid.x, 0.535, a.z + 0.01), WAINSCOT)
		Kit.box(self, Vector3(run, 0.05, 0.035), Vector3(mid.x, 0.975, a.z + 0.0175), RAIL)
	else:
		var run := b.z - a.z
		Kit.box(self, Vector3(0.02, 0.83, run), Vector3(a.x + into * 0.01, 0.535, mid.z), WAINSCOT)
		Kit.box(self, Vector3(0.035, 0.05, run), Vector3(a.x + into * 0.0175, 0.975, mid.z), RAIL)


func _counter() -> void:
	# A reception counter, taller on the public side: teal panels in a dark
	# frame under a butterscotch top.
	var c := Kit.group(self, Vector3(-1.95, 0, 3.55), Vector3.ZERO, "Counter")
	Props.counter_on(c, 1.7, 0.5, 1.05, Color(0.16, 0.5, 0.54), Color(0.97, 0.74, 0.32))
	# On it: a phone, a bell, the appointment book, a cup of pens, demo tapes.
	Kit.bevel_block(c, Vector3(0.22, 0.07, 0.16), Vector3(-0.55, 1.05, 0), CREAM, 0.02)
	Kit.bevel(c, Vector3(0.25, 0.045, 0.065), Vector3(-0.55, 1.14, -0.04), CREAM.darkened(0.08), 0.015)
	Kit.cyl(c, 0.045, 0.012, Vector3(-0.55, 1.126, 0.04), BLACK, Vector3.ZERO, 10)
	Kit.cyl(c, 0.055, 0.014, Vector3(0.1, 1.057, 0.12), BLACK, Vector3.ZERO, 12)
	Kit.ball(c, 0.045, Vector3(0.1, 1.064, 0.12), Color(0.85, 0.68, 0.25), 10)
	Kit.cyl(c, 0.009, 0.03, Vector3(0.1, 1.118, 0.12), Color(0.85, 0.68, 0.25), Vector3.ZERO, 6)
	Kit.box(c, Vector3(0.34, 0.03, 0.24), Vector3(0.5, 1.065, 0.0), Color(0.16, 0.2, 0.4), Vector3(0, 9, 0))
	Kit.box(c, Vector3(0.3, 0.006, 0.2), Vector3(0.5, 1.083, 0.0), Color(0.96, 0.95, 0.88), Vector3(0, 9, 0))
	Kit.cyl(c, 0.04, 0.1, Vector3(-0.15, 1.1, -0.1), Color(0.2, 0.45, 0.75), Vector3.ZERO, 8)
	for k in 3:
		Kit.tube(c, Vector3(-0.165 + k * 0.015, 1.11, -0.1), Vector3(-0.19 + k * 0.03, 1.24, -0.1 + 0.01 * k), 0.006, [Color(0.95, 0.2, 0.2), BLACK, Color(0.2, 0.4, 0.9)][k], 4)
	for k in 3:
		Kit.box(c, Vector3(0.11, 0.018, 0.07), Vector3(0.2, 1.059 + k * 0.018, -0.14), [Color(0.95, 0.85, 0.2), Color(0.9, 0.3, 0.5), Color(0.3, 0.75, 0.8)][k], Vector3(0, 8.0 - k * 9.0, 0))
	# The chair behind it.
	Props.chair_on(Kit.group(self, Vector3(-2.2, 0, 2.95), Vector3(0, 12, 0), "DeskChair"), Color(0.18, 0.3, 0.26))


func _waiting() -> void:
	# Two moulded plastic chairs that do not match, on chrome sled legs, backs
	# to the right wall.
	for i in 2:
		var chair := Kit.group(self, Vector3(3.15, 0, 3.55 + i * 0.85), Vector3(0, -90, 0), "WaitingChair")
		var colour: Color = [Color(0.95, 0.5, 0.15), Color(0.2, 0.55, 0.66)][i]
		for x: float in [-0.2, 0.2]:
			Kit.tube(chair, Vector3(x, 0.014, 0.2), Vector3(x, 0.014, -0.19), 0.014, STEEL, 6)
			Kit.tube(chair, Vector3(x, 0.014, 0.2), Vector3(x, 0.44, 0.16), 0.014, STEEL, 6)
			Kit.tube(chair, Vector3(x, 0.014, -0.19), Vector3(x, 0.44, -0.16), 0.014, STEEL, 6)
			Kit.tube(chair, Vector3(x, 0.44, -0.16), Vector3(x, 0.86, -0.235), 0.014, STEEL, 6)
		Kit.bevel(chair, Vector3(0.48, 0.06, 0.46), Vector3(0, 0.47, 0.0), colour, 0.025)
		Kit.bevel(chair, Vector3(0.48, 0.34, 0.05), Vector3(0, 0.77, -0.225), colour, 0.02, Vector3(-10, 0, 0))
	# A side table with old magazines, and a fake ficus by the window.
	var table := Kit.group(self, Vector3(3.2, 0, 5.15), Vector3.ZERO, "SideTable")
	Kit.cyl(table, 0.18, 0.025, Vector3(0, 0.0125, 0), WOOD_DARK, Vector3.ZERO, 12)
	Kit.cyl(table, 0.035, 0.42, Vector3(0, 0.23, 0), WOOD_DARK, Vector3.ZERO, 8)
	Kit.cyl(table, 0.25, 0.02, Vector3(0, 0.43, 0), WOOD_DARK, Vector3.ZERO, 14)
	Kit.cyl(table, 0.24, 0.03, Vector3(0, 0.455, 0), Color(0.62, 0.44, 0.26), Vector3.ZERO, 14)
	Kit.box(table, Vector3(0.22, 0.012, 0.3), Vector3(-0.03, 0.476, 0.0), Color(0.8, 0.2, 0.2), Vector3(0, 20, 0))
	Kit.box(table, Vector3(0.22, 0.012, 0.3), Vector3(0.03, 0.488, 0.03), Color(0.95, 0.85, 0.3), Vector3(0, -12, 0))
	var plant := Kit.group(self, Vector3(3.12, 0, 5.85), Vector3.ZERO, "Ficus")
	Kit.cyl(plant, 0.15, 0.3, Vector3(0, 0.15, 0), Color(0.82, 0.42, 0.22), Vector3.ZERO, 10, 0.18)
	Kit.cyl(plant, 0.2, 0.05, Vector3(0, 0.3, 0), Color(0.72, 0.36, 0.18), Vector3.ZERO, 10)
	Kit.cyl(plant, 0.17, 0.012, Vector3(0, 0.322, 0), Color(0.25, 0.17, 0.12), Vector3.ZERO, 10)
	Kit.tube(plant, Vector3(0, 0.3, 0), Vector3(-0.04, 1.05, 0.03), 0.022, Color(0.42, 0.3, 0.18), 5)
	Kit.tube(plant, Vector3(0.01, 0.3, 0), Vector3(0.06, 1.2, -0.02), 0.02, Color(0.42, 0.3, 0.18), 5)
	var leaves := [Color(0.2, 0.5, 0.26), Color(0.3, 0.62, 0.3)]
	for k in 6:
		var at: Vector3 = [Vector3(0, 1.35, 0), Vector3(-0.16, 1.15, 0.08), Vector3(0.14, 1.2, -0.06), Vector3(0.02, 1.0, 0.14), Vector3(-0.08, 1.5, -0.05), Vector3(0.12, 1.42, 0.08)][k]
		Kit.ball(plant, 0.24 if k < 4 else 0.16, at, leaves[k % 2], 6)


func _soda_machine() -> void:
	# Against the left wall, facing into the room, lit from inside.
	var m := Kit.group(self, Vector3(X0 + 0.36, 0, 5.17), Vector3(0, 90, 0), "SodaMachine")   # local +z faces the room
	Props.soda_on(m, 0.8, 0.68, 1.8, Color(0.78, 0.12, 0.14), true)


func _walls() -> void:
	# On the wall to the control room (it faces the camera): boards to a rail,
	# the rate card, two "gold" records, and the light over the studio door.
	var z := Z0 + 0.012
	_dado(Vector3(X0 + 0.035, 0, Z0), Vector3(DOOR_X[0] - 0.065, 0, Z0), 0.0)
	_dado(Vector3(DOOR_X[1] + 0.065, 0, Z0), Vector3(X1 - 0.035, 0, Z0), 0.0)
	var card := Kit.group(self, Vector3(-1.95, 1.95, z), Vector3(0, 0, -1.5), "RateCard")
	Kit.box(card, Vector3(1.1, 0.8, 0.02), Vector3.ZERO, Color(0.95, 0.94, 0.88))
	Kit.box(card, Vector3(1.16, 0.86, 0.012), Vector3(0, 0, -0.006), WOOD_DARK)
	Kit.label(card, "RATES", Vector3(0, 0.27, 0.012), 0.12, Color(0.75, 0.12, 0.12))
	Kit.label(card, "DEMO  $25 / HR", Vector3(0, 0.08, 0.012), 0.085, BLACK)
	Kit.label(card, "TAPE NOT INCLUDED", Vector3(0, -0.08, 0.012), 0.07, BLACK)
	Kit.label(card, "CASH ONLY", Vector3(0, -0.25, 0.012), 0.085, Color(0.75, 0.12, 0.12))
	for i in 2:
		var rec := Kit.group(self, Vector3(-0.75 + i * 2.75, 1.85, z), Vector3(0, 0, [3.0, -2.0][i]), "GoldRecord")
		Kit.box(rec, Vector3(0.52, 0.62, 0.02), Vector3.ZERO, Color(0.12, 0.1, 0.1))
		Kit.box(rec, Vector3(0.46, 0.56, 0.006), Vector3(0, 0, 0.012), Color(0.3, 0.1, 0.12))
		Kit.disc(rec, 0.17, Vector3(0, 0.06, 0.018), Color(0.92, 0.75, 0.25), 0.006, 14)
		Kit.disc(rec, 0.055, Vector3(0, 0.06, 0.023), Color(0.75, 0.15, 0.15), 0.004, 10)
		Kit.box(rec, Vector3(0.24, 0.06, 0.004), Vector3(0, -0.2, 0.018), Color(0.92, 0.75, 0.25))
	Kit.box(self, Vector3(0.78, 0.2, 0.08), Vector3(0.75, 2.36, Z0 + 0.04), BLACK)
	Kit.box(self, Vector3(0.72, 0.15, 0.02), Vector3(0.75, 2.36, Z0 + 0.085), Kit.flat(Color(0.98, 0.75, 0.15), 1.5))
	Kit.label(self, "QUIET PLEASE", Vector3(0.75, 2.36, Z0 + 0.1), 0.075, Color(0.15, 0.1, 0.05))

	# On the left wall: the restroom door (it does not open), panelled, with a
	# kick plate.
	var left := Kit.group(self, Vector3(X0, 0, 0), Vector3(0, 90, 0), "LeftWall")   # local +z points into the room; local x runs towards the back
	Kit.block(left, Vector3(0.8, 2.0, 0.04), Vector3(-4.15, 0, 0.02), Color(0.5, 0.56, 0.5))
	Kit.box(left, Vector3(0.88, 2.06, 0.03), Vector3(-4.15, 1.03, 0.012), WOOD_DARK)
	for r: Array in [[1.25, 0.5], [0.5, 0.62]]:
		Kit.box(left, Vector3(0.5, r[1], 0.01), Vector3(-4.18, r[0], 0.045), Color(0.57, 0.63, 0.57))
	Kit.box(left, Vector3(0.7, 0.16, 0.006), Vector3(-4.15, 0.1, 0.043), STEEL)
	Kit.ball(left, 0.04, Vector3(-3.85, 1.0, 0.06), Color(0.85, 0.68, 0.25))
	Kit.box(left, Vector3(0.4, 0.12, 0.012), Vector3(-4.15, 1.7, 0.046), CREAM)
	Kit.label(left, "RESTROOM", Vector3(-4.15, 1.7, 0.054), 0.06, BLACK)

	# On the right wall: a cork board of flyers in a frame, and a row of coat
	# hooks with somebody's jacket on one.
	var right := Kit.group(self, Vector3(X1, 0, 0), Vector3(0, -90, 0), "RightWall")   # local x runs towards the street
	Kit.box(right, Vector3(1.4, 0.9, 0.02), Vector3(3.9, 1.75, 0.01), WOOD_DARK)
	Kit.box(right, Vector3(1.3, 0.8, 0.024), Vector3(3.9, 1.75, 0.018), Color(0.72, 0.55, 0.36))     # its back 6 mm off the frame's
	var flyers := [Color(0.95, 0.9, 0.3), Color(0.95, 0.5, 0.55), Color(0.5, 0.8, 0.9), Color(0.96, 0.95, 0.9), Color(0.6, 0.85, 0.5)]
	for i in 7:
		Kit.box(right, Vector3(0.2, 0.27, 0.006), Vector3(3.4 + (i % 4) * 0.33, 1.92 - (i / 4) * 0.34, 0.034), flyers[i % flyers.size()], Vector3(0, 0, [4, -6, 2, -3, 7, -2, 5][i]))
	Kit.box(right, Vector3(0.8, 0.06, 0.03), Vector3(5.7, 1.7, 0.015), WOOD_DARK)
	for i in 4:
		Kit.cyl(right, 0.012, 0.09, Vector3(5.4 + i * 0.2, 1.68, 0.06), STEEL, Vector3(90, 0, 0), 5)
	var jacket := Color(0.62, 0.14, 0.18)
	Kit.bevel(right, Vector3(0.34, 0.56, 0.07), Vector3(5.6, 1.34, 0.075), jacket, 0.025)
	for s: float in [-1.0, 1.0]:
		Kit.box(right, Vector3(0.08, 0.46, 0.06), Vector3(5.6 + s * 0.19, 1.31, 0.075), jacket.darkened(0.15), Vector3(0, 0, s * 4.0))
	Kit.bevel(right, Vector3(0.2, 0.06, 0.05), Vector3(5.6, 1.6, 0.1), CREAM, 0.015)
