extends Node3D
## "The back room": a cheap early-90s recording studio in a rented unit.
## Control room in front, vocal booth behind the glass. Built from boxes and
## cylinders so every piece can be moved by editing a number.
##
## Layout (metres): control room x -4..3.5, z -2.5 (back wall) .. 2.5 (front wall,
## built by building.gd). The booth sits behind the back wall, z -5..-2.65.
##
## This node is the control room. The back wall and the booth are separate
## nodes beside it (`wall_to_booth`, `booth`), so each can be hidden on its own
## when the camera has to see past it.

const X0 := -4.0
const X1 := 3.5
const Z0 := -2.5
const Z1 := 2.5
const H := 2.9
const T := 0.15
const BOOTH_X0 := -2.4
const BOOTH_X1 := 3.1
const BOOTH_Z0 := -5.0

## The floor of each room (x, z, width, depth), and the props standing on them
## that must be walked round. The props are boxes drawn to the numbers in the
## build functions below: move a prop there, move it here too. Cables, the power
## strip and the paper balls are loose and can be walked over.
const AREA := Rect2(X0, Z0, X1 - X0, Z1 - Z0)
const BOOTH_AREA := Rect2(BOOTH_X0, BOOTH_Z0, BOOTH_X1 - BOOTH_X0, Z0 - T - BOOTH_Z0)
const BOOTH_DOOR := [1.8, 2.7]            # the doorway in the back wall, x from .. to
const OBSTACLES: Array[Rect2] = [
	Rect2(-1.7, -2.5, 2.8, 1.0),      # console desk
	Rect2(-0.75, -1.25, 0.6, 0.6),    # engineer chair
	Rect2(-3.11, -2.5, 0.72, 0.58),   # tape machine
	Rect2(-2.24, -2.5, 0.58, 0.2),    # foam panel leaning on the wall
	Rect2(-4.0, -1.64, 0.58, 0.58),   # gear rack
	Rect2(-4.0, -0.92, 0.82, 0.6),    # sampler on its tray
	Rect2(-4.0, -0.29, 0.8, 1.28),    # keyboard on its stand
	Rect2(-3.8, 1.28, 1.7, 0.94),     # DJ table
	Rect2(2.6, -0.4, 0.9, 1.9),       # couch
	Rect2(1.75, 0.0, 0.6, 1.1),       # coffee table
	Rect2(2.82, -2.5, 0.68, 0.68),    # fridge and TV
	Rect2(3.02, -1.31, 0.32, 0.32),   # floor lamp
	Rect2(1.3, -2.05, 0.3, 0.3),      # bin
	Rect2(-0.6, -3.62, 0.72, 0.82),   # booth: mic stand, its boom and the pop filter
	Rect2(0.2, -3.3, 0.5, 0.42),      # booth: music stand
	Rect2(-1.95, -5.0, 1.0, 0.45),    # booth: mattress
	Rect2(2.6, -4.86, 0.36, 0.36),    # booth: stool
]

const WOOD_DARK := Color(0.23, 0.16, 0.11)
const WOOD_MID := Color(0.45, 0.31, 0.18)
const BLACK := Color(0.08, 0.08, 0.09)
const CHARCOAL := Color(0.17, 0.17, 0.19)
const STEEL := Color(0.62, 0.64, 0.67)
const CREAM := Color(0.9, 0.87, 0.78)
const EDGE := Color(0.07, 0.06, 0.12)

const Door := preload("res://scripts/door.gd")

var ceiling: Node3D
var wall_to_booth: Node3D   # the back wall: window, door frame, and what hangs on it
var booth: Node3D           # the vocal booth
var booth_door: Node3D      # a Door (door.gd); starts shut
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 1993
	wall_to_booth = Kit.group(get_parent(), Vector3.ZERO, Vector3.ZERO, "WallToBooth")
	booth = Kit.group(get_parent(), Vector3.ZERO, Vector3.ZERO, "Booth")
	_shell()
	_booth()
	_console()
	_tape_and_rack()
	_keys_corner()
	_dj_table()
	_lounge()
	_dressing()


# ---------------------------------------------------------------- room shell

func _shell() -> void:
	var carpet := Kit.tex("carpet", 2.0, Color(0.5, 0.14, 0.2))
	var block := Kit.tex("painted_block", 1.2, Color(0.95, 0.88, 0.58))
	var panel := Kit.tex("wood_panel", 1.2, Color(0.85, 0.45, 0.15))
	var w := X1 - X0
	var d := Z1 - Z0
	var cx := (X0 + X1) * 0.5

	Kit.box(self, Vector3(w + T * 2, 0.3, d + T), Vector3(cx, -0.15, (Z0 - T + Z1) * 0.5), carpet)
	Kit.box(self, Vector3(w + T * 2 + 0.04, 0.34, 0.05), Vector3(cx, -0.15, Z1 + 0.025), EDGE)

	Kit.box(self, Vector3(T, H, d), Vector3(X0 - T * 0.5, H * 0.5, 0), block)
	Kit.box(self, Vector3(T, H, d), Vector3(X1 + T * 0.5, H * 0.5, 0), block)
	for x in [X0 - T * 0.5, X1 + T * 0.5]:
		Kit.box(self, Vector3(T + 0.04, H + 0.1, 0.05), Vector3(x, H * 0.5 + 0.05, Z1 + 0.025), EDGE)

	# Back wall, built around the booth window and the booth door.
	var zc := Z0 - T * 0.5
	for seg in [
		[X0 - T, -1.6, 0.0, H],     # left of the window
		[-1.6, 1.0, 0.0, 1.0],      # under the window
		[-1.6, 1.0, 2.0, H],        # over the window
		[1.0, 1.8, 0.0, H],         # between window and door
		[1.8, 2.7, 2.05, H],        # over the door
		[2.7, X1 + T, 0.0, H],      # right of the door
	]:
		Kit.box(wall_to_booth, Vector3(seg[1] - seg[0], seg[3] - seg[2], T),
			Vector3((seg[0] + seg[1]) * 0.5, (seg[2] + seg[3]) * 0.5, zc), panel).set_meta("ghost", "wall")
	# From inside the booth this wall is shown see-through (building.gd): the
	# parts marked "wall" turn faint, the parts marked "keep" stay, and whatever
	# else hangs on it is left out.
	var keep: Array = []
	# Skirting board, left and right of the door.
	keep.append(Kit.box(wall_to_booth, Vector3(1.8 - X0, 0.1, 0.03), Vector3((X0 + 1.8) * 0.5, 0.05, Z0 + 0.015), WOOD_DARK))
	keep.append(Kit.box(wall_to_booth, Vector3(X1 - 2.7, 0.1, 0.03), Vector3((X1 + 2.7) * 0.5, 0.05, Z0 + 0.015), WOOD_DARK))

	# Window frame, glass and a cartoon glare streak.
	for f in [[-0.3, 0.97, 2.72, 0.07], [-0.3, 2.03, 2.72, 0.07]]:
		keep.append(Kit.box(wall_to_booth, Vector3(f[2], f[3], T + 0.06), Vector3(f[0], f[1], zc), WOOD_DARK))
	for x in [-1.63, 1.03]:
		keep.append(Kit.box(wall_to_booth, Vector3(0.07, 1.1, T + 0.06), Vector3(x, 1.5, zc), WOOD_DARK))
	keep.append(Kit.box(wall_to_booth, Vector3(2.6, 1.0, 0.02), Vector3(-0.3, 1.5, zc), Color(0.6, 0.8, 0.9, 0.16)))
	keep.append(Kit.box(wall_to_booth, Vector3(0.16, 1.3, 0.005), Vector3(-1.0, 1.5, zc + 0.02), Color(1, 1, 1, 0.22), Vector3(0, 0, -32)))
	keep.append(Kit.box(wall_to_booth, Vector3(0.06, 1.3, 0.005), Vector3(-0.78, 1.5, zc + 0.02), Color(1, 1, 1, 0.22), Vector3(0, 0, -32)))

	# Booth door: frame, a leaf that swings into the booth (door.gd), and the warning light.
	for x in [1.78, 2.72]:
		keep.append(Kit.box(wall_to_booth, Vector3(0.07, 2.1, T + 0.06), Vector3(x, 1.05, zc), WOOD_DARK))
	keep.append(Kit.box(wall_to_booth, Vector3(1.01, 0.07, T + 0.06), Vector3(2.25, 2.07, zc), WOOD_DARK))
	for part: Node in keep:
		part.set_meta("ghost", "keep")
	var hinge: Node3D = Door.new()
	hinge.name = "BoothDoor"
	hinge.position = Vector3(BOOTH_DOOR[1] - 0.01, 0, zc)
	get_parent().add_child(hinge)
	hinge.build_leaf(BOOTH_DOOR[1] - BOOTH_DOOR[0] - 0.02, 2.036, Color(0.33, 0.47, 0.5), true, 0.1)
	booth_door = hinge
	Kit.box(wall_to_booth, Vector3(0.78, 0.2, 0.08), Vector3(2.25, 2.36, Z0 + 0.04), BLACK)
	Kit.box(wall_to_booth, Vector3(0.72, 0.15, 0.02), Vector3(2.25, 2.36, Z0 + 0.085), Kit.flat(Color(0.95, 0.12, 0.1), 1.6))
	Kit.label(wall_to_booth, "RECORDING", Vector3(2.25, 2.36, Z0 + 0.1), 0.085, Color(1, 0.93, 0.85))

	# Drop ceiling with two strip lights (one dead), a water stain and a missing tile.
	ceiling = Kit.group(self, Vector3.ZERO, Vector3.ZERO, "Ceiling")
	Kit.box(ceiling, Vector3(w + T * 2, 0.1, d + T), Vector3(cx, H + 0.05, (Z0 - T + Z1) * 0.5),
		Kit.tex("ceiling_tile", 0.6, Color(0.95, 0.94, 0.9)))
	Kit.box(ceiling, Vector3(w + T * 2 + 0.04, 0.14, 0.05), Vector3(cx, H + 0.05, Z1 + 0.025), EDGE)
	Kit.box(ceiling, Vector3(1.2, 0.02, 0.6), Vector3(-1.2, H - 0.008, -0.3), Kit.flat(Color(1.0, 0.98, 0.9), 1.4))
	Kit.box(ceiling, Vector3(1.2, 0.02, 0.6), Vector3(1.8, H - 0.008, 0.9), Color(0.55, 0.55, 0.5))
	Kit.box(ceiling, Vector3(0.6, 0.012, 0.6), Vector3(0.9, H - 0.004, -1.5), Color(0.05, 0.04, 0.06))
	Kit.box(ceiling, Vector3(0.012, 0.35, 0.012), Vector3(0.95, H - 0.17, -1.45), BLACK, Vector3(0, 0, 8))
	Kit.cyl(ceiling, 0.42, 0.006, Vector3(-2.7, H - 0.002, 1.0), Color(0.7, 0.58, 0.36, 0.55), Vector3.ZERO, 9)
	Kit.cyl(ceiling, 0.24, 0.006, Vector3(-2.4, H - 0.0015, 1.3), Color(0.62, 0.5, 0.3, 0.55), Vector3.ZERO, 7)

	var strip := Kit.omni(self, Vector3(-1.2, H - 0.3, -0.3), Color(1.0, 0.97, 0.88), 0.9, 7.0)
	strip.name = "StripLight"


# --------------------------------------------------------------- vocal booth

func _booth() -> void:
	var bw := BOOTH_X1 - BOOTH_X0
	var bd := (Z0 - T) - BOOTH_Z0
	var bcx := (BOOTH_X0 + BOOTH_X1) * 0.5
	var bcz := (BOOTH_Z0 + Z0 - T) * 0.5
	var foam := Kit.tex("foam", 0.6, Color(0.2, 0.2, 0.22))
	var eggs := Kit.tex("egg_carton", 0.6, Color(0.62, 0.55, 0.45))

	Kit.box(booth, Vector3(bw + T * 2, 0.3, bd + T), Vector3(bcx, -0.15, bcz - T * 0.5),
		Kit.tex("carpet", 2.0, Color(0.3, 0.12, 0.2), true, Color(0.62, 0.6, 0.78)))
	Kit.box(booth, Vector3(bw + T * 2, H, T), Vector3(bcx, H * 0.5, BOOTH_Z0 - T * 0.5), eggs)
	Kit.box(booth, Vector3(T, H, bd), Vector3(BOOTH_X0 - T * 0.5, H * 0.5, bcz), foam)
	Kit.box(booth, Vector3(T, H, bd), Vector3(BOOTH_X1 + T * 0.5, H * 0.5, bcz), foam)
	Kit.box(booth, Vector3(bw + T * 2, 0.1, bd + T), Vector3(bcx, H + 0.05, bcz - T * 0.5), CHARCOAL)

	# Bare bulb on a cord.
	Kit.box(booth, Vector3(0.012, 0.45, 0.012), Vector3(0.6, H - 0.22, -3.9), BLACK)
	Kit.ball(booth, 0.07, Vector3(0.6, H - 0.5, -3.9), Kit.flat(Color(1.0, 0.86, 0.5), 2.2))
	Kit.omni(booth, Vector3(0.6, H - 0.6, -3.8), Color(1.0, 0.8, 0.5), 1.5, 5.0)

	# Mic on a boom stand at the window, with a coat-hanger-and-tights pop
	# filter. The stand is by the glass and the boom reaches back into the room
	# (the group is turned half round), so whoever is at the mic faces the
	# control room. It is set low: the lead's mouth is a metre off the floor.
	var mic := Kit.group(booth, Vector3(-0.1, 0, -3.0), Vector3(0, 180, 0), "Mic")
	Kit.cyl(mic, 0.19, 0.03, Vector3(0, 0.015, 0), BLACK, Vector3.ZERO, 8)
	Kit.cyl(mic, 0.014, 0.92, Vector3(0, 0.46, 0), STEEL, Vector3.ZERO, 6)
	Kit.cyl(mic, 0.012, 0.7, Vector3(0.12, 0.98, 0.1), STEEL, Vector3(62, 50, 0), 6)
	Kit.cyl(mic, 0.034, 0.2, Vector3(0.32, 1.0, 0.27), Color(0.75, 0.76, 0.78), Vector3(90, 0, 0), 8)
	Kit.cyl(mic, 0.042, 0.07, Vector3(0.32, 1.0, 0.4), CHARCOAL, Vector3(90, 0, 0), 8)
	Kit.ring(mic, 0.11, 0.012, Vector3(0.32, 1.0, 0.52), Color(0.55, 0.4, 0.2))
	Kit.disc(mic, 0.098, Vector3(0.32, 1.0, 0.52), Color(0.72, 0.6, 0.5, 0.5), 0.004)
	# Headphones hooked over the stand.
	Kit.ring(mic, 0.09, 0.012, Vector3(-0.02, 0.72, 0.03), BLACK, Vector3(0, 20, 0))
	Kit.cyl(mic, 0.05, 0.04, Vector3(-0.11, 0.67, 0.0), CHARCOAL, Vector3(0, 0, 90), 8)
	Kit.cyl(mic, 0.05, 0.04, Vector3(0.07, 0.67, 0.06), CHARCOAL, Vector3(0, 0, 90), 8)

	# Music stand with a lyric sheet, beside the mic and turned to face whoever
	# is singing (so from the control room you see the back of it).
	var stand := Kit.group(booth, Vector3(0.45, 0, -3.1), Vector3(0, 205, 0), "MusicStand")
	Kit.cyl(stand, 0.16, 0.025, Vector3(0, 0.012, 0), BLACK, Vector3.ZERO, 6)
	Kit.cyl(stand, 0.012, 0.9, Vector3(0, 0.45, 0), BLACK, Vector3.ZERO, 6)
	Kit.box(stand, Vector3(0.46, 0.32, 0.015), Vector3(0, 0.97, 0.03), BLACK, Vector3(-18, 0, 0))
	Kit.box(stand, Vector3(0.24, 0.3, 0.006), Vector3(-0.04, 0.985, 0.045), Color(0.96, 0.95, 0.88), Vector3(-18, 0, 4))

	# A mattress propped on the back wall and a moving blanket: budget soundproofing.
	var mattress := Kit.group(booth, Vector3(-1.45, 0, -4.78), Vector3(-7, 0, 0), "Mattress")
	Kit.block(mattress, Vector3(1.0, 1.9, 0.2), Vector3.ZERO, Color(0.86, 0.85, 0.8))
	for i in 6:
		Kit.box(mattress, Vector3(0.05, 1.9, 0.005), Vector3(-0.4 + i * 0.16, 0.95, 0.102), Color(0.42, 0.52, 0.72))
	Kit.box(booth, Vector3(1.3, 1.5, 0.04), Vector3(1.9, 1.75, BOOTH_Z0 + 0.03), Color(0.2, 0.26, 0.45), Vector3(0, 0, 2))
	for i in 3:
		Kit.box(booth, Vector3(1.3, 0.02, 0.045), Vector3(1.9, 1.3 + i * 0.42, BOOTH_Z0 + 0.03), Color(0.14, 0.18, 0.33), Vector3(0, 0, 2))

	# Stool in the corner, clear of the door.
	Kit.cyl(booth, 0.17, 0.05, Vector3(2.78, 0.6, -4.68), Color(0.6, 0.15, 0.13), Vector3.ZERO, 8)
	for a in 3:
		var ang := a * TAU / 3.0
		Kit.cyl(booth, 0.014, 0.6, Vector3(2.78 + cos(ang) * 0.11, 0.3, -4.68 + sin(ang) * 0.11), STEEL, Vector3.ZERO, 5)


# ------------------------------------------------------------------- console

func _console() -> void:
	var desk := Kit.group(self, Vector3(-0.3, 0, -1.98), Vector3.ZERO, "ConsoleDesk")
	Kit.box(desk, Vector3(2.8, 0.05, 0.95), Vector3(0, 0.715, 0), WOOD_MID)
	Kit.block(desk, Vector3(0.5, 0.69, 0.85), Vector3(-1.13, 0, 0), WOOD_DARK)
	Kit.block(desk, Vector3(0.5, 0.69, 0.85), Vector3(1.13, 0, 0), WOOD_DARK)
	Kit.box(desk, Vector3(1.76, 0.5, 0.03), Vector3(0, 0.44, -0.4), WOOD_DARK)
	for y in [0.2, 0.45]:
		Kit.box(desk, Vector3(0.42, 0.2, 0.02), Vector3(1.13, y, 0.43), Color(0.3, 0.21, 0.14))
		Kit.box(desk, Vector3(0.1, 0.02, 0.03), Vector3(1.13, y, 0.45), STEEL)

	# The board: a modest 12-channel mixer, raked up towards the glass.
	var board := Kit.group(desk, Vector3(-0.1, 0.83, 0.02), Vector3(12, 0, 0), "Mixer")
	Kit.box(board, Vector3(1.7, 0.1, 0.72), Vector3(0, 0, 0), Color(0.2, 0.23, 0.3))
	for x in [-0.87, 0.87]:
		Kit.box(board, Vector3(0.04, 0.15, 0.78), Vector3(x, 0, 0), WOOD_MID)
	var knob_rows := [Color(0.85, 0.2, 0.18), Color(0.2, 0.5, 0.85), Color(0.92, 0.8, 0.25)]
	for i in 12:
		var x := -0.76 + i * 0.1
		for r in 3:
			Kit.cyl(board, 0.017, 0.03, Vector3(x, 0.062, -0.29 + r * 0.075), knob_rows[r], Vector3.ZERO, 6)
		var lit := _rng.randf() < 0.35
		Kit.box(board, Vector3(0.034, 0.012, 0.024), Vector3(x, 0.055, -0.07),
			Kit.flat(Color(0.95, 0.25, 0.15), 1.2) if lit else Color(0.35, 0.1, 0.1))
		Kit.box(board, Vector3(0.012, 0.004, 0.27), Vector3(x, 0.052, 0.17), BLACK)
		Kit.box(board, Vector3(0.042, 0.028, 0.03), Vector3(x, 0.064, 0.17 + _rng.randf_range(-0.11, 0.11)), CREAM)
	# Master section: two red master faders, big knobs, a pair of VU meters.
	for i in 2:
		var x := 0.55 + i * 0.12
		Kit.box(board, Vector3(0.012, 0.004, 0.27), Vector3(x, 0.052, 0.17), BLACK)
		Kit.box(board, Vector3(0.05, 0.03, 0.034), Vector3(x, 0.065, 0.11 - i * 0.03), Color(0.85, 0.15, 0.12))
		Kit.cyl(board, 0.03, 0.035, Vector3(x, 0.065, -0.07), CHARCOAL, Vector3.ZERO, 8)
		Kit.box(board, Vector3(0.1, 0.01, 0.075), Vector3(x, 0.055, -0.25), Kit.flat(Color(0.98, 0.9, 0.62), 0.7))
		Kit.box(board, Vector3(0.004, 0.012, 0.06), Vector3(x + 0.01, 0.058, -0.25), BLACK, Vector3(0, 25 - i * 45, 0))
	Kit.box(board, Vector3(0.012, 0.012, 0.012), Vector3(0.78, 0.058, -0.3), Kit.flat(Color(0.3, 1.0, 0.35), 1.5))

	# White-cone nearfields on the desk corners, toed in at the engineer's chair.
	for side in [-1.0, 1.0]:
		var spk := Kit.group(desk, Vector3(side * 1.18, 0.74, -0.14), Vector3(0, -side * 16, 0), "Nearfield")
		Kit.block(spk, Vector3(0.25, 0.42, 0.22), Vector3.ZERO, BLACK)
		Kit.disc(spk, 0.092, Vector3(0, 0.15, 0.112), Color(0.94, 0.94, 0.9))
		Kit.disc(spk, 0.03, Vector3(0, 0.15, 0.118), Color(0.8, 0.8, 0.76))
		Kit.disc(spk, 0.03, Vector3(0, 0.33, 0.112), CHARCOAL)

	# Desk clutter: phone, mug, legal pad with a pen.
	Kit.block(desk, Vector3(0.2, 0.06, 0.16), Vector3(-0.98, 0.74, 0.3), Color(0.82, 0.76, 0.62), Vector3(0, 15, 0))
	Kit.box(desk, Vector3(0.21, 0.04, 0.05), Vector3(-0.98, 0.81, 0.27), Color(0.76, 0.7, 0.56), Vector3(0, 15, 0))
	Kit.cyl(desk, 0.04, 0.09, Vector3(0.98, 0.785, 0.34), Color(0.2, 0.4, 0.75), Vector3.ZERO, 8)
	Kit.block(desk, Vector3(0.2, 0.012, 0.28), Vector3(0.98, 0.74, 0.02), Color(0.96, 0.86, 0.3), Vector3(0, -12, 0))
	Kit.box(desk, Vector3(0.012, 0.012, 0.15), Vector3(1.0, 0.76, 0.02), Color(0.15, 0.25, 0.7), Vector3(0, 30, 0))

	# The engineer's chair: swivel base, torn red seat.
	var chair := Kit.group(self, Vector3(-0.45, 0, -0.95), Vector3(0, 22, 0), "EngineerChair")
	Kit.box(chair, Vector3(0.56, 0.04, 0.07), Vector3(0, 0.05, 0), BLACK)
	Kit.box(chair, Vector3(0.07, 0.04, 0.56), Vector3(0, 0.05, 0), BLACK)
	Kit.cyl(chair, 0.03, 0.4, Vector3(0, 0.26, 0), STEEL, Vector3.ZERO, 6)
	Kit.box(chair, Vector3(0.46, 0.09, 0.46), Vector3(0, 0.5, 0), Color(0.5, 0.14, 0.13))
	Kit.box(chair, Vector3(0.04, 0.3, 0.04), Vector3(0, 0.68, 0.24), BLACK)
	Kit.box(chair, Vector3(0.44, 0.46, 0.07), Vector3(0, 0.98, 0.25), Color(0.5, 0.14, 0.13), Vector3(8, 0, 0))
	Kit.box(chair, Vector3(0.14, 0.05, 0.005), Vector3(0.08, 1.02, 0.292), Color(0.6, 0.6, 0.62), Vector3(8, 0, 20))


# ------------------------------------------------------- tape machine & rack

func _tape_and_rack() -> void:
	# Half-inch reel-to-reel on a cart, left of the window.
	var tape := Kit.group(self, Vector3(-2.75, 0, -2.18), Vector3.ZERO, "TapeMachine")
	Kit.block(tape, Vector3(0.72, 0.48, 0.52), Vector3.ZERO, CHARCOAL)
	for x in [-0.3, 0.3]:
		Kit.cyl(tape, 0.035, 0.03, Vector3(x, 0.015, 0.2), BLACK, Vector3(0, 0, 90), 6)
	var deck := Kit.group(tape, Vector3(0, 0.48, -0.02), Vector3(-9, 0, 0))
	Kit.block(deck, Vector3(0.66, 0.82, 0.3), Vector3.ZERO, STEEL)
	for x in [-0.165, 0.165]:
		Kit.disc(deck, 0.15, Vector3(x, 0.59, 0.158), Color(0.8, 0.8, 0.83), 0.02, 14)
		Kit.disc(deck, 0.105, Vector3(x, 0.59, 0.17), Color(0.36, 0.22, 0.12), 0.005, 14)
		Kit.disc(deck, 0.045, Vector3(x, 0.59, 0.176), CHARCOAL, 0.008, 8)
	Kit.box(deck, Vector3(0.6, 0.3, 0.012), Vector3(0, 0.2, 0.152), BLACK)
	for i in 2:
		Kit.box(deck, Vector3(0.14, 0.09, 0.01), Vector3(-0.17 + i * 0.34, 0.27, 0.16), Kit.flat(Color(0.98, 0.9, 0.62), 0.7))
	for i in 6:
		Kit.cyl(deck, 0.02, 0.025, Vector3(-0.22 + i * 0.088, 0.12, 0.165), CREAM, Vector3(90, 0, 0), 6)

	# Outboard rack on the left wall, facing into the room.
	var rack := Kit.group(self, Vector3(-3.68, 0, -1.35), Vector3(0, 90, 0), "GearRack")
	Kit.block(rack, Vector3(0.58, 1.5, 0.52), Vector3.ZERO, BLACK)
	var faces := [Color(0.22, 0.22, 0.25), Color(0.56, 0.57, 0.6), Color(0.16, 0.2, 0.32), Color(0.3, 0.3, 0.32)]
	var leds := [Color(0.3, 1.0, 0.35), Color(1.0, 0.25, 0.15), Color(1.0, 0.75, 0.2)]
	for u in 8:
		var y := 0.17 + u * 0.165
		Kit.box(rack, Vector3(0.5, 0.14, 0.02), Vector3(0, y, 0.262), faces[u % faces.size()])
		if u == 5:   # cassette deck
			Kit.box(rack, Vector3(0.2, 0.09, 0.012), Vector3(-0.1, y, 0.275), BLACK)
			Kit.box(rack, Vector3(0.14, 0.04, 0.006), Vector3(-0.1, y, 0.283), Color(0.5, 0.6, 0.65))
		else:
			for k in 3:
				Kit.cyl(rack, 0.018, 0.02, Vector3(-0.19 + k * 0.07, y, 0.28), CREAM, Vector3(90, 0, 0), 6)
		for k in 4:
			if _rng.randf() < 0.7:
				Kit.box(rack, Vector3(0.018, 0.018, 0.01), Vector3(0.08 + k * 0.04, y + 0.03, 0.275),
					Kit.flat(leds[_rng.randi() % leds.size()], 1.5))
	# Tape boxes stacked on top.
	for i in 4:
		Kit.block(rack, Vector3(0.28, 0.045, 0.28), Vector3(-0.08, 1.5 + i * 0.045, 0.02),
			[CREAM, Color(0.75, 0.2, 0.18), CREAM, Color(0.2, 0.35, 0.6)][i], Vector3(0, _rng.randf_range(-14, 14), 0))


# ----------------------------------------------- keyboard & sampler corner

func _keys_corner() -> void:
	var keys := Kit.group(self, Vector3(-3.42, 0, 0.35), Vector3(0, 90, 0), "Keyboard")
	for a in [38.0, -38.0]:
		Kit.box(keys, Vector3(1.2, 0.04, 0.04), Vector3(0, 0.38, 0), STEEL, Vector3(0, 0, a))
	Kit.box(keys, Vector3(1.28, 0.09, 0.36), Vector3(0, 0.79, 0), CHARCOAL)
	Kit.box(keys, Vector3(1.16, 0.02, 0.15), Vector3(0, 0.84, 0.09), Color(0.95, 0.95, 0.92))
	var white_w := 1.16 / 35.0
	for k in 34:
		if k % 7 in [0, 1, 3, 4, 5]:
			Kit.box(keys, Vector3(0.018, 0.02, 0.09), Vector3(-0.58 + (k + 1) * white_w, 0.855, 0.06), BLACK)
	Kit.box(keys, Vector3(0.18, 0.01, 0.06), Vector3(-0.1, 0.838, -0.1), Kit.flat(Color(0.45, 0.8, 0.5), 0.8))
	for k in 6:
		Kit.box(keys, Vector3(0.03, 0.012, 0.03), Vector3(0.1 + k * 0.05, 0.838, -0.1), Color(0.8, 0.3, 0.2) if k == 0 else CREAM)
	Kit.cyl(keys, 0.03, 0.03, Vector3(-0.5, 0.845, -0.1), CREAM, Vector3.ZERO, 8)

	# Sampler on a wobbly TV tray.
	var tray := Kit.group(self, Vector3(-3.4, 0, -0.62), Vector3(0, 90, 0), "Sampler")
	Kit.box(tray, Vector3(0.6, 0.03, 0.44), Vector3(0, 0.62, 0), WOOD_MID)
	for a in [28.0, -28.0]:
		Kit.box(tray, Vector3(0.03, 0.72, 0.03), Vector3(0, 0.31, 0.18), STEEL, Vector3(0, 0, a))
		Kit.box(tray, Vector3(0.03, 0.72, 0.03), Vector3(0, 0.31, -0.18), STEEL, Vector3(0, 0, a))
	var box := Kit.group(tray, Vector3(0, 0.64, 0), Vector3(7, 0, 0))
	Kit.block(box, Vector3(0.46, 0.08, 0.38), Vector3.ZERO, Color(0.74, 0.73, 0.68))
	for px in 4:
		for pz in 4:
			Kit.box(box, Vector3(0.05, 0.012, 0.05), Vector3(0.0 + px * 0.062, 0.086, -0.04 + pz * 0.062), Color(0.3, 0.3, 0.33))
	Kit.box(box, Vector3(0.16, 0.01, 0.06), Vector3(-0.12, 0.085, -0.12), Kit.flat(Color(0.5, 0.82, 0.5), 0.8))
	Kit.cyl(box, 0.035, 0.03, Vector3(-0.16, 0.095, 0.02), CHARCOAL, Vector3.ZERO, 8)
	for k in 3:
		Kit.box(box, Vector3(0.035, 0.012, 0.025), Vector3(-0.18 + k * 0.05, 0.086, 0.12), Color(0.85, 0.2, 0.15) if k == 2 else CHARCOAL)


# ------------------------------------------------------------------ DJ table

func _dj_table() -> void:
	var dj := Kit.group(self, Vector3(-2.95, 0, 1.75), Vector3(0, 12, 0), "DJTable")
	Kit.box(dj, Vector3(1.6, 0.04, 0.62), Vector3(0, 0.74, 0), Color(0.6, 0.55, 0.48))
	for x in [-0.72, 0.72]:
		for z in [-0.25, 0.25]:
			Kit.cyl(dj, 0.018, 0.72, Vector3(x, 0.36, z), STEEL, Vector3.ZERO, 5)
	var labels := [Color(0.95, 0.5, 0.1), Color(0.15, 0.6, 0.65)]
	for i in 2:
		var deck := Kit.group(dj, Vector3(-0.52 + i * 1.04, 0.76, 0), Vector3.ZERO, "Turntable")
		Kit.block(deck, Vector3(0.46, 0.08, 0.38), Vector3.ZERO, Color(0.72, 0.72, 0.74))
		Kit.cyl(deck, 0.155, 0.02, Vector3(-0.04, 0.09, 0), BLACK, Vector3.ZERO, 14)
		Kit.cyl(deck, 0.05, 0.022, Vector3(-0.04, 0.091, 0), labels[i], Vector3.ZERO, 10)
		Kit.cyl(deck, 0.022, 0.05, Vector3(0.18, 0.1, -0.13), STEEL, Vector3.ZERO, 6)
		Kit.box(deck, Vector3(0.016, 0.014, 0.24), Vector3(0.14, 0.115, -0.03), STEEL, Vector3(0, -18, 0))
	var mx := Kit.group(dj, Vector3(0, 0.76, 0), Vector3.ZERO, "DJMixer")
	Kit.block(mx, Vector3(0.24, 0.09, 0.36), Vector3.ZERO, BLACK)
	for i in 2:
		Kit.box(mx, Vector3(0.03, 0.02, 0.03), Vector3(-0.06 + i * 0.12, 0.1, 0.03 + i * 0.05), CREAM)
		for k in 3:
			Kit.cyl(mx, 0.014, 0.02, Vector3(-0.06 + i * 0.12, 0.1, -0.14 + k * 0.045), Color(0.85, 0.2, 0.18), Vector3.ZERO, 6)
	Kit.box(mx, Vector3(0.05, 0.02, 0.025), Vector3(0.02, 0.1, 0.14), CREAM)

	# Milk crates of records under the table.
	var crate_cols := [Color(0.14, 0.3, 0.72), Color(0.78, 0.16, 0.14)]
	var sleeves := [Color(0.92, 0.85, 0.3), Color(0.9, 0.4, 0.15), Color(0.3, 0.6, 0.75), CREAM, Color(0.55, 0.25, 0.6), BLACK]
	for i in 2:
		var crate := Kit.group(dj, Vector3(-0.35 + i * 0.6, 0, 0.02), Vector3(0, -8 + i * 20, 0), "Crate")
		Kit.block(crate, Vector3(0.38, 0.3, 0.38), Vector3.ZERO, crate_cols[i])
		for k in 9:
			Kit.block(crate, Vector3(0.33, 0.33, 0.022), Vector3(0, 0.02, -0.14 + k * 0.035),
				sleeves[_rng.randi() % sleeves.size()], Vector3(_rng.randf_range(-6, 6), 0, 0))


# -------------------------------------------------------------------- lounge

func _lounge() -> void:
	# A sagging thrift-store couch against the right wall.
	var couch := Kit.group(self, Vector3(3.0, 0, 0.55), Vector3(0, -90, 0), "Couch")
	var cloth := Color(0.52, 0.36, 0.15)
	var cushion := Color(0.66, 0.47, 0.2)
	for x in [-0.85, 0.85]:
		for z in [-0.3, 0.3]:
			Kit.block(couch, Vector3(0.07, 0.1, 0.07), Vector3(x, 0, z), WOOD_DARK)
	Kit.block(couch, Vector3(1.95, 0.24, 0.86), Vector3(0, 0.1, 0), cloth)
	Kit.block(couch, Vector3(1.95, 0.52, 0.22), Vector3(0, 0.34, -0.32), cloth)
	for x in [-1.07, 1.07]:
		Kit.block(couch, Vector3(0.2, 0.34, 0.86), Vector3(x, 0.3, 0), cloth)
	Kit.block(couch, Vector3(0.93, 0.14, 0.62), Vector3(-0.47, 0.34, 0.1), cushion)
	Kit.block(couch, Vector3(0.93, 0.14, 0.62), Vector3(0.47, 0.31, 0.1), cushion, Vector3(-4, 0, 3))
	Kit.box(couch, Vector3(0.22, 0.004, 0.08), Vector3(0.5, 0.465, 0.2), Color(0.62, 0.62, 0.64), Vector3(-4, 28, 3))
	Kit.box(couch, Vector3(0.75, 0.34, 0.26), Vector3(-0.5, 0.75, -0.32), Color(0.78, 0.36, 0.14), Vector3(0, 0, -3))
	for i in 3:
		Kit.box(couch, Vector3(0.76, 0.03, 0.265), Vector3(-0.5, 0.65 + i * 0.1, -0.32), Color(0.35, 0.2, 0.1), Vector3(0, 0, -3))

	# Rug and coffee table with last night's pizza.
	Kit.box(self, Vector3(1.5, 0.012, 2.1), Vector3(2.05, 0.006, 0.55), Color(0.18, 0.27, 0.38))
	Kit.box(self, Vector3(1.2, 0.014, 1.8), Vector3(2.05, 0.007, 0.55), Color(0.76, 0.62, 0.34))
	Kit.box(self, Vector3(0.9, 0.016, 1.5), Vector3(2.05, 0.008, 0.55), Color(0.18, 0.27, 0.38))
	var table := Kit.group(self, Vector3(2.05, 0, 0.55), Vector3(0, 4, 0), "CoffeeTable")
	Kit.box(table, Vector3(0.56, 0.04, 1.05), Vector3(0, 0.38, 0), WOOD_MID)
	for x in [-0.23, 0.23]:
		for z in [-0.46, 0.46]:
			Kit.block(table, Vector3(0.05, 0.36, 0.05), Vector3(x, 0, z), WOOD_DARK)
	Kit.block(table, Vector3(0.38, 0.045, 0.38), Vector3(0.02, 0.4, 0.25), Color(0.9, 0.87, 0.78), Vector3(0, 18, 0))
	Kit.block(table, Vector3(0.2, 0.004, 0.2), Vector3(0.02, 0.445, 0.25), Color(0.82, 0.16, 0.12), Vector3(0, 18, 0))
	for c in [Vector3(-0.12, 0.45, -0.1), Vector3(0.1, 0.45, -0.22)]:
		Kit.cyl(table, 0.03, 0.1, c, Color(0.85, 0.12, 0.1), Vector3.ZERO, 8, 0.04)
	Kit.block(table, Vector3(0.2, 0.012, 0.28), Vector3(-0.08, 0.4, -0.38), Color(0.96, 0.86, 0.3), Vector3(0, 30, 0))

	# Mini fridge with a rabbit-ear TV on top.
	var fridge := Kit.group(self, Vector3(3.15, 0, -2.15), Vector3(0, -14, 0), "Fridge")
	Kit.block(fridge, Vector3(0.56, 0.86, 0.56), Vector3.ZERO, Color(0.9, 0.9, 0.85))
	Kit.box(fridge, Vector3(0.56, 0.012, 0.005), Vector3(0, 0.62, 0.282), Color(0.55, 0.55, 0.52))
	Kit.box(fridge, Vector3(0.03, 0.16, 0.03), Vector3(-0.22, 0.42, 0.295), STEEL)
	Kit.box(fridge, Vector3(0.07, 0.07, 0.006), Vector3(0.1, 0.74, 0.284), Color(0.95, 0.75, 0.1), Vector3(0, 0, 12))
	Kit.box(fridge, Vector3(0.05, 0.05, 0.006), Vector3(0.18, 0.5, 0.284), Color(0.85, 0.2, 0.2), Vector3(0, 0, -8))
	var tv := Kit.group(fridge, Vector3(0, 0.86, 0), Vector3(0, -8, 0), "TV")
	Kit.block(tv, Vector3(0.46, 0.38, 0.42), Vector3.ZERO, Color(0.28, 0.26, 0.26))
	Kit.box(tv, Vector3(0.3, 0.25, 0.01), Vector3(-0.05, 0.2, 0.212), Kit.flat(Color(0.45, 0.62, 0.72), 0.9))
	for k in 2:
		Kit.cyl(tv, 0.018, 0.012, Vector3(0.17, 0.26 - k * 0.09, 0.214), CREAM, Vector3(90, 0, 0), 6)
	for a in [28.0, -32.0]:
		Kit.cyl(tv, 0.006, 0.5, Vector3(sin(deg_to_rad(-a)) * 0.24, 0.38 + 0.22, -0.05), STEEL, Vector3(0, 0, a), 4)

	# Floor lamp between the couch and the fridge.
	var lamp := Kit.group(self, Vector3(3.18, 0, -1.15), Vector3.ZERO, "FloorLamp")
	Kit.cyl(lamp, 0.16, 0.03, Vector3(0, 0.015, 0), BLACK, Vector3.ZERO, 8)
	Kit.cyl(lamp, 0.015, 1.55, Vector3(0, 0.8, 0), Color(0.72, 0.6, 0.3), Vector3.ZERO, 6)
	Kit.cyl(lamp, 0.24, 0.3, Vector3(0, 1.66, 0), Kit.flat(Color(1.0, 0.86, 0.55), 1.1), Vector3.ZERO, 10, 0.13)
	Kit.omni(lamp, Vector3(-0.3, 1.5, 0.2), Color(1.0, 0.82, 0.55), 0.9, 4.5)


# ------------------------------------------------------------ wall dressing

func _foam_panel(pos: Vector3, tilt: float) -> void:
	Kit.box(wall_to_booth, Vector3(0.58, 0.58, 0.07), pos, Kit.tex("foam", 0.58, Color(0.2, 0.2, 0.22), false), Vector3(0, 0, tilt))


func _poster(parent: Node3D, pos: Vector3, rot: Vector3, w: float, h: float, bg: Color, a: Color, b: Color, style: int) -> void:
	var p := Kit.group(parent, pos, rot, "Poster")
	Kit.box(p, Vector3(w, h, 0.006), Vector3.ZERO, bg)
	match style:
		0:   # big sun and a ground stripe
			Kit.disc(p, w * 0.3, Vector3(0, h * 0.12, 0.005), a, 0.004, 14)
			Kit.box(p, Vector3(w, h * 0.16, 0.004), Vector3(0, -h * 0.34, 0.005), b)
		1:   # three bars
			for i in 3:
				Kit.box(p, Vector3(w * 0.8, h * 0.13, 0.004), Vector3(0, h * 0.2 - i * h * 0.2, 0.005), [a, b, a][i])
		2:   # diamond and a title block
			Kit.box(p, Vector3(w * 0.5, w * 0.5, 0.004), Vector3(0, h * 0.12, 0.005), a, Vector3(0, 0, 45))
			Kit.box(p, Vector3(w * 0.7, h * 0.1, 0.004), Vector3(0, -h * 0.36, 0.005), b)
	for c in [Vector2(-1, 1), Vector2(1, 1)]:   # masking tape on the top corners
		Kit.box(p, Vector3(0.09, 0.035, 0.004), Vector3(c.x * w * 0.46, c.y * h * 0.47, 0.007), Color(0.9, 0.85, 0.65), Vector3(0, 0, -c.x * 40))


func _dressing() -> void:
	# Foam squares stapled up around the glass, none of them straight.
	var wall_z := Z0 + 0.035
	for p in [
		[-2.05, 2.25, 3.0], [-2.08, 1.62, -2.0], [-1.1, 2.37, 1.5], [-0.48, 2.36, -1.0],
		[0.16, 2.38, 2.5], [1.4, 1.75, -3.0], [1.4, 1.13, 1.0],
	]:
		_foam_panel(Vector3(p[0], p[1], wall_z), p[2])
	# One has come unstuck and sits on the floor against the wall.
	Kit.box(self, Vector3(0.58, 0.58, 0.07), Vector3(-1.95, 0.285, -2.36), Kit.tex("foam", 0.58, Color(0.2, 0.2, 0.22), false), Vector3(-14, 8, 0))

	# Egg cartons and a shelf on the left wall.
	var left := Kit.group(self, Vector3(X0, 0, 0), Vector3(0, 90, 0), "LeftWall")   # local +z points into the room
	Kit.box(left, Vector3(1.2, 0.9, 0.05), Vector3(1.35, 2.1, 0.025), Kit.tex("egg_carton", 0.6, Color(0.62, 0.55, 0.45), false))
	Kit.box(left, Vector3(1.5, 0.03, 0.28), Vector3(-0.45, 1.5, 0.14), WOOD_MID)
	for x in [-1.05, 0.15]:
		Kit.box(left, Vector3(0.03, 0.2, 0.2), Vector3(x, 1.39, 0.1), STEEL)
	var boom := Kit.group(left, Vector3(-0.75, 1.515, 0.14), Vector3.ZERO, "Boombox")
	Kit.block(boom, Vector3(0.66, 0.26, 0.18), Vector3.ZERO, CHARCOAL)
	for x in [-0.22, 0.22]:
		Kit.disc(boom, 0.095, Vector3(x, 0.12, 0.092), STEEL)
		Kit.disc(boom, 0.065, Vector3(x, 0.12, 0.098), BLACK)
	Kit.box(boom, Vector3(0.14, 0.09, 0.01), Vector3(0, 0.11, 0.092), Color(0.5, 0.6, 0.65))
	Kit.box(boom, Vector3(0.5, 0.02, 0.02), Vector3(0, 0.3, 0), STEEL)
	var tape_cols := [CREAM, Color(0.85, 0.2, 0.18), Color(0.2, 0.4, 0.75), Color(0.95, 0.8, 0.25), BLACK, Color(0.9, 0.5, 0.15)]
	for i in 12:
		Kit.block(left, Vector3(0.022, 0.11, 0.07), Vector3(-0.3 + i * 0.027, 1.515, 0.12), tape_cols[_rng.randi() % tape_cols.size()])
	_poster(left, Vector3(-1.5, 1.95, 0.01), Vector3(0, 0, -3), 0.62, 0.86, Color(0.42, 0.2, 0.55), Color(0.98, 0.82, 0.2), Color(0.15, 0.1, 0.25), 0)

	# Posters and a clock on the back wall.
	_poster(wall_to_booth, Vector3(-3.25, 1.9, Z0 + 0.008), Vector3(0, 0, 2), 0.66, 0.92, Color(0.1, 0.1, 0.12), Color(0.9, 0.2, 0.15), Color(0.95, 0.8, 0.2), 1)
	_poster(wall_to_booth, Vector3(-3.3, 0.95, Z0 + 0.008), Vector3(0, 0, -4), 0.5, 0.36, Color(0.95, 0.93, 0.85), Color(0.2, 0.45, 0.8), Color(0.15, 0.15, 0.2), 1)
	var clock := Kit.group(wall_to_booth, Vector3(3.1, 2.15, Z0 + 0.02), Vector3.ZERO, "Clock")
	Kit.disc(clock, 0.2, Vector3.ZERO, BLACK, 0.03, 14)
	Kit.disc(clock, 0.17, Vector3(0, 0, 0.012), Color(0.96, 0.95, 0.9), 0.012, 14)
	Kit.box(clock, Vector3(0.016, 0.12, 0.004), Vector3(0.02, 0.05, 0.02), BLACK, Vector3(0, 0, -22))
	Kit.box(clock, Vector3(0.012, 0.15, 0.004), Vector3(-0.05, -0.03, 0.02), BLACK, Vector3(0, 0, -122))

	# Right wall: one more poster, hung low over the couch.
	var right := Kit.group(self, Vector3(X1, 0, 0), Vector3(0, -90, 0), "RightWall")
	_poster(right, Vector3(0.55, 1.7, 0.01), Vector3(0, 0, 3), 0.9, 0.62, Color(0.92, 0.5, 0.12), Color(0.12, 0.3, 0.6), Color(0.98, 0.93, 0.8), 2)

	# Cables taped across the carpet, a power strip, an overflowing bin.
	var cable := Color(0.06, 0.06, 0.07)
	# Each run: centre, length, yaw. Desk to rack, desk to sampler, power strip to the DJ table.
	for c in [
		[Vector3(-2.55, 0.008, -1.35), 1.62, 7.0],
		[Vector3(-2.48, 0.008, -0.9), 1.66, 29.0],
		[Vector3(-2.25, 0.008, 0.1), 2.5, 74.0],
	]:
		Kit.box(self, Vector3(c[1], 0.016, 0.02), c[0], cable, Vector3(0, c[2], 0))
		Kit.box(self, Vector3(0.07, 0.004, 0.2), c[0] + Vector3(0, 0.009, 0), Color(0.6, 0.6, 0.62), Vector3(0, c[2], 0))
	Kit.block(self, Vector3(0.34, 0.04, 0.07), Vector3(-1.75, 0, -1.2), Color(0.88, 0.84, 0.72), Vector3(0, -20, 0))
	Kit.box(self, Vector3(0.03, 0.015, 0.03), Vector3(-1.88, 0.045, -1.25), Kit.flat(Color(1.0, 0.3, 0.15), 1.5))
	Kit.cyl(self, 0.12, 0.32, Vector3(1.45, 0.16, -1.9), Color(0.35, 0.36, 0.4), Vector3.ZERO, 8, 0.15)
	for b in [Vector3(1.45, 0.34, -1.9), Vector3(1.5, 0.36, -1.86), Vector3(1.72, 0.04, -1.7), Vector3(1.2, 0.04, -1.62)]:
		Kit.ball(self, 0.045, b, Color(0.95, 0.94, 0.88), 6)
