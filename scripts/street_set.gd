extends Node3D
## The street in front of the studio, at night: a strip of pavement you can walk
## along, the kerb, the road, and the shopfronts either side. You arrive here
## from the map, in front of the studio door.
##
## Layout (metres): the shopfront wall runs along z 6.2..6.35; the pavement is
## z 6.35..8.6; the road is beyond it. This node is the street. The studio's
## own shopfront is a separate node beside it (`facade`), because it is cut
## away when the camera has to see into the front room.

const Door := preload("res://scripts/door.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")

const WALL_Z0 := 6.2          # shopfront wall, inner face
const WALL_Z1 := 6.35         # and outer face (the pavement starts here)
const KERB_Z := 8.6
const SHOP_X0 := -3.15        # the studio's own frontage
const SHOP_X1 := 3.65
const SHOP_H := 3.7
const DOOR := [1.5, 2.45]     # the street door, x from .. to
const WINDOW := [-2.4, 0.6, 0.9, 2.1]   # x from, x to, y from, y to

## The pavement in front of the building: not much of it.
const AREA := Rect2(-5.5, WALL_Z1, 11.5, KERB_Z - WALL_Z1 - 0.1)
const OBSTACLES: Array[Rect2] = [
	Rect2(2.75, 6.4, 0.42, 0.42),     # bin
	Rect2(-3.05, 6.4, 0.5, 0.45),     # newspaper box
	Rect2(4.35, 6.35, 0.5, 0.3),      # pay phone
	Rect2(-3.75, 8.25, 0.3, 0.3),     # lamp post
	Rect2(5.05, 8.05, 0.3, 0.3),      # hydrant
]

const BLACK := Color(0.08, 0.08, 0.09)
const STEEL := Color(0.62, 0.64, 0.67)
const EDGE := Color(0.07, 0.06, 0.12)
const WOOD_DARK := Color(0.23, 0.16, 0.11)

var facade: Node3D            # the studio's shopfront wall, with its window and sign
var door: Node3D              # the street door (a Door)


func build() -> void:
	facade = Kit.group(get_parent(), Vector3.ZERO, Vector3.ZERO, "Shopfront")
	_ground()
	_facade()
	_neighbours()
	_street_furniture()


func _ground() -> void:
	Kit.box(self, Vector3(22.0, 0.3, KERB_Z - WALL_Z1), Vector3(0.5, -0.15, (WALL_Z1 + KERB_Z) * 0.5), Kit.tex("sidewalk", 2.4, Color(0.66, 0.64, 0.6)))
	Kit.box(self, Vector3(22.0, 0.3, 0.2), Vector3(0.5, -0.15, KERB_Z + 0.1), Color(0.78, 0.76, 0.72))
	Kit.box(self, Vector3(22.0, 0.3, 7.0), Vector3(0.5, -0.29, KERB_Z + 3.7), Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27)))
	for i in 6:     # a worn centre line
		Kit.box(self, Vector3(1.4, 0.01, 0.12), Vector3(-8.0 + i * 3.4, -0.135, KERB_Z + 3.4), Color(0.85, 0.8, 0.55))


func _facade() -> void:
	var brick := Kit.tex("brick", 1.5, Color(0.55, 0.27, 0.2))
	var zc := (WALL_Z0 + WALL_Z1) * 0.5
	var t := WALL_Z1 - WALL_Z0
	# The wall, built round the window and the door.
	for seg in [
		[SHOP_X0, WINDOW[0], 0.0, SHOP_H],            # left of the window
		[WINDOW[0], WINDOW[1], 0.0, WINDOW[2]],       # under it
		[WINDOW[0], WINDOW[1], WINDOW[3], SHOP_H],    # over it
		[WINDOW[1], DOOR[0], 0.0, SHOP_H],            # between window and door
		[DOOR[0], DOOR[1], 2.1, SHOP_H],              # over the door
		[DOOR[1], SHOP_X1, 0.0, SHOP_H],              # right of the door
	]:
		Kit.box(facade, Vector3(seg[1] - seg[0], seg[3] - seg[2], t), Vector3((seg[0] + seg[1]) * 0.5, (seg[2] + seg[3]) * 0.5, zc), brick)
	Kit.box(facade, Vector3(SHOP_X1 - SHOP_X0 + 0.1, 0.16, t + 0.1), Vector3((SHOP_X0 + SHOP_X1) * 0.5, SHOP_H + 0.08, zc), Color(0.3, 0.28, 0.27))

	# Window: frame, glass, half-shut blinds, and the room's light behind it.
	var wx := (WINDOW[0] + WINDOW[1]) * 0.5
	var ww: float = WINDOW[1] - WINDOW[0]
	var wy := (WINDOW[2] + WINDOW[3]) * 0.5
	var wh: float = WINDOW[3] - WINDOW[2]
	# Frames stand 15 mm into their openings: a frame face lying exactly on the
	# cut end of the wall flickers.
	for y in [WINDOW[2] - 0.02, WINDOW[3] + 0.02]:
		Kit.box(facade, Vector3(ww + 0.11, 0.07, t + 0.06), Vector3(wx, y, zc), WOOD_DARK)
	for x in [WINDOW[0] - 0.02, WINDOW[1] + 0.02, wx]:
		Kit.box(facade, Vector3(0.07, wh + 0.11, t + 0.06), Vector3(x, wy, zc), WOOD_DARK)
	Kit.box(facade, Vector3(ww, wh, 0.02), Vector3(wx, wy, zc), Color(0.75, 0.85, 0.7, 0.2))
	for i in 9:
		Kit.box(facade, Vector3(ww, 0.05, 0.012), Vector3(wx, WINDOW[3] - 0.06 - i * 0.075, zc - 0.03), Color(0.9, 0.88, 0.8))
	Kit.box(facade, Vector3(0.16, wh + 0.3, 0.005), Vector3(wx - 0.6, wy, zc + 0.02), Color(1, 1, 1, 0.18), Vector3(0, 0, -30))

	# Door frame, the door, and a buzzer.
	for x in [DOOR[0] - 0.02, DOOR[1] + 0.02]:
		Kit.box(facade, Vector3(0.07, 2.14, t + 0.06), Vector3(x, 1.07, zc), WOOD_DARK)
	Kit.box(facade, Vector3(DOOR[1] - DOOR[0] + 0.11, 0.07, t + 0.06), Vector3((DOOR[0] + DOOR[1]) * 0.5, 2.12, zc), WOOD_DARK)
	door = Door.new()
	door.name = "StreetDoor"
	door.position = Vector3(DOOR[1] - 0.01, 0, zc)
	get_parent().add_child(door)
	door.build_leaf(DOOR[1] - DOOR[0] - 0.02, 2.06, Color(0.2, 0.3, 0.26))
	Kit.box(door.leaf, Vector3(0.36, 0.5, 0.07), Vector3(-0.47, 1.55, 0), Color(0.75, 0.85, 0.7, 0.35))    # a small pane
	Kit.block(facade, Vector3(0.1, 0.16, 0.03), Vector3(DOOR[1] + 0.22, 1.25, WALL_Z1 + 0.015), STEEL)
	Kit.box(facade, Vector3(0.03, 0.03, 0.012), Vector3(DOOR[1] + 0.22, 1.36, WALL_Z1 + 0.035), Kit.flat(Color(1.0, 0.3, 0.15), 1.5))

	# The sign board over the window, and a small lit sign over the door.
	var board := Kit.group(facade, Vector3(wx, 2.72, WALL_Z1 + 0.05), Vector3.ZERO, "Sign")
	Kit.box(board, Vector3(ww + 0.5, 0.78, 0.08), Vector3.ZERO, Color(0.1, 0.09, 0.12))
	Kit.box(board, Vector3(ww + 0.36, 0.04, 0.02), Vector3(0, -0.3, 0.045), Kit.flat(Color(1.0, 0.25, 0.5), 1.8))
	var title := Kit.label(board, "THE BACK ROOM", Vector3(0, 0.07, 0.045), 0.3, Color(0.98, 0.85, 0.3))
	title.font = FONT
	Kit.label(board, "RECORDING  -  DEMOS  -  REHEARSAL", Vector3(0, -0.2, 0.045), 0.08, Color(0.95, 0.93, 0.85))
	Kit.box(facade, Vector3(0.8, 0.2, 0.08), Vector3((DOOR[0] + DOOR[1]) * 0.5, 2.45, WALL_Z1 + 0.04), BLACK)
	Kit.box(facade, Vector3(0.74, 0.15, 0.02), Vector3((DOOR[0] + DOOR[1]) * 0.5, 2.45, WALL_Z1 + 0.085), Kit.flat(Color(0.3, 0.95, 0.5), 1.5))
	Kit.label(facade, "OPEN LATE", Vector3((DOOR[0] + DOOR[1]) * 0.5, 2.45, WALL_Z1 + 0.1), 0.08, Color(0.05, 0.15, 0.08))
	Kit.omni(facade, Vector3(wx, 2.4, WALL_Z1 + 0.9), Color(1.0, 0.5, 0.6), 0.6, 4.0)


func _neighbours() -> void:
	var zc := (WALL_Z0 + WALL_Z1) * 0.5
	var t := WALL_Z1 - WALL_Z0
	# Left: a coin laundry, still lit.
	var lx := (SHOP_X0 - 10.5) * 0.5
	var lw := SHOP_X0 + 10.5
	Kit.box(self, Vector3(lw, 3.4, t), Vector3(lx, 1.7, zc), Kit.tex("stucco", 2.0, Color(0.86, 0.74, 0.68)))
	Kit.box(self, Vector3(lw + 0.1, 0.16, t + 0.1), Vector3(lx, 3.48, zc), Color(0.3, 0.28, 0.27))
	Kit.box(self, Vector3(4.6, 1.5, 0.03), Vector3(-6.4, 1.6, WALL_Z1 + 0.012), Kit.flat(Color(1.0, 0.95, 0.75), 1.1))
	Kit.box(self, Vector3(4.76, 1.66, 0.02), Vector3(-6.4, 1.6, WALL_Z1 + 0.005), Color(0.85, 0.85, 0.82))
	for i in 5:
		Kit.disc(self, 0.26, Vector3(-8.2 + i * 0.9, 1.25, WALL_Z1 + 0.03), Color(0.75, 0.78, 0.8), 0.008, 14)
		Kit.disc(self, 0.18, Vector3(-8.2 + i * 0.9, 1.25, WALL_Z1 + 0.036), Color(0.35, 0.5, 0.62), 0.008, 14)
	var wash := Kit.label(self, "COIN LAUNDRY", Vector3(-6.4, 2.85, WALL_Z1 + 0.02), 0.3, Color(0.25, 0.55, 0.85))
	wash.font = FONT
	# Right: a pawn shop with its shutter down.
	var rx := (SHOP_X1 + 11.5) * 0.5
	var rw := 11.5 - SHOP_X1
	Kit.box(self, Vector3(rw, 3.9, t), Vector3(rx, 1.95, zc), Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74)))
	Kit.box(self, Vector3(rw + 0.1, 0.16, t + 0.1), Vector3(rx, 3.98, zc), Color(0.3, 0.28, 0.27))
	Kit.box(self, Vector3(3.6, 2.2, 0.04), Vector3(7.4, 1.1, WALL_Z1 + 0.02), Color(0.5, 0.52, 0.55))
	for i in 10:
		Kit.box(self, Vector3(3.56, 0.02, 0.05), Vector3(7.4, 0.15 + i * 0.22, WALL_Z1 + 0.025), Color(0.36, 0.38, 0.42))    # 2 cm short of the shutter each end, or the ends flicker
	var pawn := Kit.label(self, "PAWN  -  LOANS", Vector3(7.4, 2.9, WALL_Z1 + 0.02), 0.3, Color(0.95, 0.75, 0.2))
	pawn.font = FONT


func _street_furniture() -> void:
	# A lamp post at the kerb, lit.
	var lamp := Kit.group(self, Vector3(-3.6, 0, 8.4), Vector3.ZERO, "LampPost")
	Kit.cyl(lamp, 0.1, 0.5, Vector3(0, 0.25, 0), Color(0.2, 0.24, 0.24), Vector3.ZERO, 8, 0.07)
	Kit.cyl(lamp, 0.05, 4.2, Vector3(0, 2.1, 0), Color(0.2, 0.24, 0.24), Vector3.ZERO, 6)
	Kit.box(lamp, Vector3(0.9, 0.06, 0.06), Vector3(0.4, 4.15, 0), Color(0.2, 0.24, 0.24))
	Kit.box(lamp, Vector3(0.4, 0.1, 0.22), Vector3(0.8, 4.08, 0), Kit.flat(Color(1.0, 0.86, 0.55), 2.2))
	Kit.omni(lamp, Vector3(0.8, 3.6, 0), Color(1.0, 0.82, 0.5), 1.6, 9.0)
	# Two parking meters and a hydrant along the kerb.
	for x in [0.3, 3.3]:
		var meter := Kit.group(self, Vector3(x, 0, 8.45), Vector3.ZERO, "Meter")
		Kit.cyl(meter, 0.025, 1.1, Vector3(0, 0.55, 0), STEEL, Vector3.ZERO, 6)
		Kit.box(meter, Vector3(0.14, 0.22, 0.1), Vector3(0, 1.2, 0), Color(0.35, 0.37, 0.4))
		Kit.box(meter, Vector3(0.1, 0.06, 0.012), Vector3(0, 1.24, -0.055), Color(0.9, 0.9, 0.85))
	var hydrant := Kit.group(self, Vector3(5.2, 0, 8.2), Vector3.ZERO, "Hydrant")
	Kit.cyl(hydrant, 0.11, 0.5, Vector3(0, 0.25, 0), Color(0.85, 0.2, 0.15), Vector3.ZERO, 8)
	Kit.ball(hydrant, 0.12, Vector3(0, 0.52, 0), Color(0.85, 0.2, 0.15), 8)
	Kit.cyl(hydrant, 0.05, 0.34, Vector3(0, 0.32, 0), Color(0.75, 0.16, 0.12), Vector3(0, 0, 90), 6)
	# Against the shopfronts: a bin, a newspaper box, a pay phone.
	Kit.cyl(self, 0.2, 0.75, Vector3(2.96, 0.375, 6.61), Color(0.3, 0.36, 0.34), Vector3.ZERO, 10, 0.23)
	Kit.cyl(self, 0.24, 0.05, Vector3(2.96, 0.77, 6.61), Color(0.2, 0.24, 0.23), Vector3.ZERO, 10)
	var news := Kit.group(self, Vector3(-2.8, 0, 6.62), Vector3.ZERO, "NewsBox")
	Kit.block(news, Vector3(0.46, 0.5, 0.38), Vector3(0, 0.45, 0), Color(0.2, 0.4, 0.75))
	Kit.cyl(news, 0.04, 0.45, Vector3(0, 0.225, 0), Color(0.15, 0.3, 0.6), Vector3.ZERO, 6)
	Kit.box(news, Vector3(0.36, 0.28, 0.012), Vector3(0, 0.72, 0.195), Color(0.95, 0.94, 0.88))
	var phone := Kit.group(self, Vector3(4.6, 0, 6.38), Vector3.ZERO, "PayPhone")
	Kit.box(phone, Vector3(0.46, 0.7, 0.24), Vector3(0, 1.35, 0.12), Color(0.2, 0.35, 0.6))
	Kit.box(phone, Vector3(0.28, 0.36, 0.06), Vector3(0, 1.32, 0.26), Color(0.12, 0.12, 0.14))
	Kit.box(phone, Vector3(0.07, 0.26, 0.07), Vector3(-0.1, 1.36, 0.31), BLACK)
	Kit.box(phone, Vector3(0.5, 0.05, 0.3), Vector3(0, 1.72, 0.15), STEEL)
