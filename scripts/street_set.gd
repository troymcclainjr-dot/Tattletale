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
const Props := preload("res://scripts/props.gd")
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
	Rect2(2.75, 6.42, 0.42, 0.42),    # bin
	Rect2(-3.05, 6.4, 0.5, 0.45),     # newspaper box
	Rect2(4.35, 6.35, 0.5, 0.3),      # pay phone
	Rect2(-3.75, 8.25, 0.3, 0.3),     # lamp post
	Rect2(5.05, 8.05, 0.3, 0.3),      # hydrant
	Rect2(0.2, 8.35, 0.2, 0.2),       # parking meter
	Rect2(3.2, 8.35, 0.2, 0.2),       # parking meter
]

const BLACK := Color(0.08, 0.08, 0.09)
const STEEL := Color(0.62, 0.64, 0.67)
const ALUMINIUM := Color(0.78, 0.8, 0.82)
const STONE := Color(0.84, 0.82, 0.76)
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
	# The same pavement, kerb, gutter and road as every other street (outdoor.gd's
	# textures, with the old ones to fall back on).
	var outdoor = load("res://scripts/outdoor.gd")
	var walk: Variant = outdoor.pavement() if outdoor else Kit.tex("sidewalk", 2.4, Color(0.66, 0.64, 0.6))
	var tar: Variant = outdoor.road() if outdoor else Kit.tex("asphalt", 3.0, Color(0.2, 0.22, 0.27))
	Kit.box(self, Vector3(22.0, 0.3, KERB_Z - WALL_Z1), Vector3(0.5, -0.15, (WALL_Z1 + KERB_Z) * 0.5), walk)
	Kit.box(self, Vector3(22.0, 0.32, 0.2), Vector3(0.5, -0.14, KERB_Z + 0.1), Color(0.84, 0.82, 0.77))
	Kit.box(self, Vector3(22.0, 0.3, 7.0), Vector3(0.5, -0.29, KERB_Z + 3.7), tar)
	Kit.box(self, Vector3(21.98, 0.012, 0.36), Vector3(0.5, -0.136, KERB_Z + 0.38), Color(0.42, 0.43, 0.46))
	for i in 6:     # a worn centre line
		Kit.box(self, Vector3(1.4, 0.01, 0.12), Vector3(-8.0 + i * 3.4, -0.135, KERB_Z + 3.4), Color(0.85, 0.8, 0.55))


## A cornice along the top of a shopfront, x0..x1, its underside at h: a frieze
## `frieze` deep below it, brackets, an overhanging slab and a cap. An end that
## meets a taller neighbour stops flush with it (`butt_left`, `butt_right`)
## instead of overhanging into its wall.
func _cornice(parent: Node3D, x0: float, x1: float, h: float, look: Color, frieze := 0.42, butt_left := false, butt_right := false) -> void:
	var w := x1 - x0
	Kit.box(parent, Vector3(w, frieze, 0.05), Vector3((x0 + x1) * 0.5, h - frieze * 0.5, WALL_Z1 + 0.025), look.darkened(0.18))
	var n := maxi(int(w / 0.9) + 1, 2)
	var bh := minf(0.36, frieze - 0.04)
	for i in n:
		Kit.prism(parent, Vector3(0.18, bh, 0.12), Vector3(x0 + 0.15 + i * (w - 0.3) / float(n - 1), h - bh * 0.5, WALL_Z1 + 0.14), look, Vector3(0, 90, 180), 0.0)
	for layer: Array in [[0.05, h + 0.1, 0.2, 0.4, look], [0.07, h + 0.23, 0.06, 0.44, look.darkened(0.18)]]:
		var a: float = x0 - (0.0 if butt_left else float(layer[0]))
		var b: float = x1 + (0.0 if butt_right else float(layer[0]))
		Kit.box(parent, Vector3(b - a, layer[2], layer[3]), Vector3((a + b) * 0.5, layer[1], WALL_Z0 + float(layer[3]) * 0.5), layer[4])


func _facade() -> void:
	var brick := Kit.tex("kit_brick", 1.0, Color(0.6, 0.27, 0.2))
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
	# A stone foot either side of the door, and the cornice on its brackets.
	for run in [[SHOP_X0, DOOR[0] - 0.06], [DOOR[1] + 0.06, SHOP_X1]]:
		Kit.box(facade, Vector3(run[1] - run[0], 0.42, 0.04), Vector3((run[0] + run[1]) * 0.5, 0.21, WALL_Z1 + 0.02), STONE.darkened(0.25))
	_cornice(facade, SHOP_X0, SHOP_X1, SHOP_H, Color(0.18, 0.4, 0.42), 0.42, false, true)

	# Window: frame, glass, half-shut blinds, and the room's light behind it; a
	# stone sill under it and a dark soldier course over it.
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
	Kit.bevel(facade, Vector3(ww + 0.32, 0.08, 0.16), Vector3(wx, WINDOW[2] - 0.095, WALL_Z1 + 0.04), STONE, 0.02)
	Kit.box(facade, Vector3(ww + 0.24, 0.16, 0.035), Vector3(wx, WINDOW[3] + 0.135, WALL_Z1 + 0.0175), Color(0.4, 0.17, 0.13))

	# Door frame, the door with its kick plate and push plate, and a buzzer.
	for x in [DOOR[0] - 0.02, DOOR[1] + 0.02]:
		Kit.box(facade, Vector3(0.07, 2.14, t + 0.06), Vector3(x, 1.07, zc), WOOD_DARK)
	Kit.box(facade, Vector3(DOOR[1] - DOOR[0] + 0.11, 0.07, t + 0.06), Vector3((DOOR[0] + DOOR[1]) * 0.5, 2.12, zc), WOOD_DARK)
	door = Door.new()
	door.name = "StreetDoor"
	door.position = Vector3(DOOR[1] - 0.01, 0, zc)
	get_parent().add_child(door)
	door.build_leaf(DOOR[1] - DOOR[0] - 0.02, 2.086, Color(0.2, 0.3, 0.26), true, 0.1)
	Kit.box(door.leaf, Vector3(0.36, 0.5, 0.12), Vector3(-0.47, 1.55, 0), Color(0.75, 0.85, 0.7, 0.35))    # a small pane
	Kit.box(door.leaf, Vector3(0.8, 0.22, 0.106), Vector3(-0.47, 0.13, 0), STEEL)                          # kick plate
	Kit.box(door.leaf, Vector3(0.1, 0.3, 0.114), Vector3(-0.8, 1.05, 0), STEEL)                            # push plate
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
	# Left: a coin laundry, still lit: its window of machines in an aluminium
	# frame on a tiled riser, a glass door, a striped awning, a cornice.
	var lx := (SHOP_X0 - 10.5) * 0.5
	var lw := SHOP_X0 + 10.5
	Kit.box(self, Vector3(lw, 3.4, t), Vector3(lx, 1.7, zc), Kit.tex("stucco", 2.0, Color(0.86, 0.74, 0.68)))
	_cornice(self, -10.5, SHOP_X0, 3.4, Color(0.22, 0.56, 0.6), 0.3, false, true)
	var lit := Kit.flat(Color(1.0, 0.95, 0.75), 1.1)
	Kit.box(self, Vector3(4.2, 1.5, 0.03), Vector3(-6.6, 1.6, WALL_Z1 + 0.012), lit)
	for i in 5:
		Kit.disc(self, 0.26, Vector3(-8.25 + i * 0.85, 1.25, WALL_Z1 + 0.03), Color(0.75, 0.78, 0.8), 0.008, 14)
		Kit.disc(self, 0.18, Vector3(-8.25 + i * 0.85, 1.25, WALL_Z1 + 0.036), Color(0.35, 0.5, 0.62), 0.008, 14)
	for y: float in [0.815, 2.385]:
		Kit.box(self, Vector3(4.34, 0.07, 0.05), Vector3(-6.6, y, WALL_Z1 + 0.025), ALUMINIUM)
	for x: float in [-8.735, -4.465]:
		Kit.box(self, Vector3(0.07, 1.64, 0.05), Vector3(x, 1.6, WALL_Z1 + 0.025), ALUMINIUM)
	for x: float in [-7.82, -5.27]:
		Kit.box(self, Vector3(0.05, 1.52, 0.04), Vector3(x, 1.6, WALL_Z1 + 0.02), ALUMINIUM)    # ends inside the rails, not on the glass's edge
	Kit.box(self, Vector3(4.34, 0.78, 0.04), Vector3(-6.6, 0.39, WALL_Z1 + 0.02), Color(0.16, 0.42, 0.45))
	Kit.box(self, Vector3(0.75, 2.0, 0.03), Vector3(-3.825, 1.0, WALL_Z1 + 0.012), lit)
	for x: float in [-4.22, -3.43]:
		Kit.box(self, Vector3(0.06, 2.12, 0.05), Vector3(x, 1.06, WALL_Z1 + 0.025), ALUMINIUM)
	Kit.box(self, Vector3(0.73, 0.06, 0.05), Vector3(-3.825, 2.09, WALL_Z1 + 0.025), ALUMINIUM)
	Kit.box(self, Vector3(0.73, 0.2, 0.04), Vector3(-3.825, 0.1, WALL_Z1 + 0.02), ALUMINIUM)
	Kit.box(self, Vector3(0.56, 0.04, 0.04), Vector3(-3.825, 1.0, WALL_Z1 + 0.06), STEEL)
	Kit.awning(self, 4.6, 0.9, 0.45, Vector3(-6.6, 2.62, WALL_Z1 + 0.01), Color(0.2, 0.62, 0.68), Color(0.95, 0.95, 0.9), 0.32)
	var wash := Kit.label(self, "COIN LAUNDRY", Vector3(-6.4, 2.85, WALL_Z1 + 0.02), 0.3, Color(0.25, 0.55, 0.85))
	wash.font = FONT
	# Right: a pawn shop with its shutter down in its guides, under the shutter
	# box and a sign board, and a cornice.
	var rx := (SHOP_X1 + 11.5) * 0.5
	var rw := 11.5 - SHOP_X1
	Kit.box(self, Vector3(rw, 3.9, t), Vector3(rx, 1.95, zc), Kit.tex("kit_brick", 1.0, Color(0.4, 0.22, 0.2), true, Color(0.6, 0.6, 0.74)))
	_cornice(self, SHOP_X1, 11.5, 3.9, Color(0.32, 0.3, 0.3), 0.42, true)
	Kit.box(self, Vector3(3.6, 2.2, 0.04), Vector3(7.4, 1.1, WALL_Z1 + 0.02), Color(0.5, 0.52, 0.55))
	for i in 10:
		Kit.box(self, Vector3(3.56, 0.02, 0.05), Vector3(7.4, 0.15 + i * 0.22, WALL_Z1 + 0.025), Color(0.36, 0.38, 0.42))    # 2 cm short of the shutter each end, or the ends flicker
	for x: float in [5.565, 9.235]:
		Kit.box(self, Vector3(0.07, 2.2, 0.07), Vector3(x, 1.1, WALL_Z1 + 0.035), Color(0.3, 0.32, 0.36))
	Kit.bevel(self, Vector3(3.9, 0.32, 0.26), Vector3(7.4, 2.36, WALL_Z1 + 0.13), Color(0.4, 0.42, 0.46), 0.03)
	Kit.box(self, Vector3(0.09, 0.11, 0.04), Vector3(7.4, 0.13, WALL_Z1 + 0.065), Color(0.88, 0.72, 0.25))
	Kit.ring(self, 0.035, 0.012, Vector3(7.4, 0.21, WALL_Z1 + 0.065), STEEL)
	Kit.box(self, Vector3(3.9, 0.56, 0.1), Vector3(7.4, 2.9, WALL_Z1 + 0.05), Color(0.12, 0.12, 0.2))
	for y: float in [2.65, 3.15]:
		Kit.box(self, Vector3(3.8, 0.03, 0.012), Vector3(7.4, y, WALL_Z1 + 0.104), Color(0.95, 0.75, 0.2))
	var pawn := Kit.label(self, "PAWN  -  LOANS", Vector3(7.4, 2.9, WALL_Z1 + 0.115), 0.3, Color(0.95, 0.75, 0.2))
	pawn.font = FONT


func _street_furniture() -> void:
	# A lamp post at the kerb, lit (the same lamp as every street's: props.gd).
	Props.street_lamp_on(Kit.group(self, Vector3(-3.6, 0, 8.4), Vector3.ZERO, "LampPost"))
	# Two parking meters (one run out) and a hydrant along the kerb.
	for i in 2:
		var meter := Kit.group(self, Vector3([0.3, 3.3][i], 0, 8.45), Vector3.ZERO, "Meter")
		var head := Color(0.26, 0.42, 0.52)
		Kit.cyl(meter, 0.03, 1.05, Vector3(0, 0.525, 0), Color(0.3, 0.32, 0.36), Vector3.ZERO, 6)
		Kit.bevel(meter, Vector3(0.17, 0.24, 0.13), Vector3(0, 1.17, 0), head, 0.03)
		Kit.cyl(meter, 0.085, 0.08, Vector3(0, 1.32, 0), head, Vector3.ZERO, 10, 0.05)
		for s: float in [-1.0, 1.0]:
			Kit.box(meter, Vector3(0.11, 0.08, 0.012), Vector3(0, 1.21, s * 0.066), Color(0.92, 0.92, 0.86))
			if i == 1:
				Kit.box(meter, Vector3(0.06, 0.035, 0.008), Vector3(0.015, 1.2, s * 0.074), Color(0.9, 0.15, 0.1))     # EXPIRED
			else:
				Kit.box(meter, Vector3(0.008, 0.05, 0.008), Vector3(-0.01, 1.21, s * 0.074), BLACK, Vector3(0, 0, -25))
	Props.hydrant_on(Kit.group(self, Vector3(5.2, 0, 8.2), Vector3.ZERO, "Hydrant"))
	# Against the shopfronts: a bin, a newspaper box, a pay phone.
	Props.bin_on(Kit.group(self, Vector3(2.96, 0, 6.63), Vector3.ZERO, "Bin"))
	var news := Kit.group(self, Vector3(-2.8, 0, 6.62), Vector3.ZERO, "NewsBox")
	var blue := Color(0.2, 0.42, 0.78)
	for x: float in [-0.16, 0.16]:
		Kit.box(news, Vector3(0.05, 0.42, 0.3), Vector3(x, 0.21, 0), blue.darkened(0.35))
	Kit.bevel_block(news, Vector3(0.48, 0.58, 0.4), Vector3(0, 0.42, 0), blue, 0.04)
	Kit.box(news, Vector3(0.38, 0.3, 0.012), Vector3(0, 0.76, 0.2), Color(0.12, 0.16, 0.24))
	Kit.box(news, Vector3(0.32, 0.24, 0.008), Vector3(0, 0.75, 0.208), Color(0.95, 0.94, 0.88))
	Kit.box(news, Vector3(0.26, 0.045, 0.006), Vector3(0, 0.83, 0.214), BLACK)
	Kit.box(news, Vector3(0.18, 0.02, 0.006), Vector3(-0.04, 0.775, 0.214), BLACK)
	Kit.box(news, Vector3(0.12, 0.08, 0.006), Vector3(0.07, 0.7, 0.214), Color(0.55, 0.62, 0.7))
	Kit.box(news, Vector3(0.18, 0.035, 0.03), Vector3(0, 0.56, 0.215), STEEL)
	Kit.bevel(news, Vector3(0.16, 0.09, 0.13), Vector3(0.1, 1.04, -0.06), STEEL, 0.02)
	Props.payphone_on(Kit.group(self, Vector3(4.6, 0, WALL_Z1), Vector3.ZERO, "PayPhone"))
