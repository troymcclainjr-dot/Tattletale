extends RefCounted
## Props for the gun store (plans/gunstore.gd). As in props.gd, a prop takes the
## place, a band and its spot on the plan (u, v), turned `yaw` degrees (0 faces
## the street, 90 right, 180 the back, 270 left), and keeps its floor space clear
## of walkers.
##
## The weapons on show are the game's own pictures of the three it has
## (assets/weapons/<name>.png) cut out of card, like the people (`card`). Glass is
## Kit.pane(): a shot breaks it. A range target's paper is a picture drawn here
## in code (`target_image`); gun_shop.gd draws the holes into it (`mark_hole`) and
## scores them (`score_at`).

const Props := preload("res://scripts/props.gd")

const STEEL := Color(0.42, 0.44, 0.47)
const BLACK := Color(0.1, 0.1, 0.11)
const FELT := Color(0.44, 0.07, 0.09)
const TAG := Color(0.97, 0.95, 0.88)
const GLASS := Color(0.66, 0.84, 0.9, 0.22)
const WOOD := Color(0.36, 0.23, 0.14)
const AMMO := [Color(0.78, 0.14, 0.12), Color(0.2, 0.42, 0.24), Color(0.92, 0.7, 0.14), Color(0.18, 0.3, 0.6),
		Color(0.16, 0.16, 0.18), Color(0.88, 0.45, 0.12), Color(0.45, 0.47, 0.3)]

const PAPER_W := 0.56                    # a target's paper, in metres
const PAPER_H := 0.74
const TARGET_PX := Vector2i(336, 444)    # its picture, in pixels (600 to the metre)
const BULL := Vector2(168.0, 196.0)      # the middle of the rings, in pixels from the picture's top left
const RINGS := [28.0, 56.0, 84.0, 112.0, 140.0, 164.0]      # each ring's outer edge, in pixels: the 10, the 9 ... the 5
const PAPER := Color(0.95, 0.93, 0.86)
const INK := Color(0.1, 0.1, 0.11)
const RED := Color(0.84, 0.12, 0.1)

static var _cards := {}                  # "weapon tint": the material of that weapon's picture
static var _blank: Image                 # a fresh target paper


# ------------------------------------------------------------------ the stock

## A weapon's picture cut out of card, `length` metres along its longer side, in its parent's x-y plane (it faces
## +z) at `pos`, turned `rot` degrees. `tint` colours it (a black rifle, an olive one). Shots go through it.
static func card(parent: Node3D, weapon: String, pos: Vector3, rot := Vector3.ZERO, length := 0.5, tint := Color.WHITE) -> MeshInstance3D:
	var key := "%s %s" % [weapon, tint.to_html()]
	if not _cards.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/weapons/%s.png" % weapon)
		m.albedo_color = tint
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		m.metallic_specular = 0.0
		_cards[key] = m
	var mat: StandardMaterial3D = _cards[key]
	var size := Vector2(mat.albedo_texture.get_size()) if mat.albedo_texture else Vector2(2.0, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(length, length * size.y / size.x) if size.x >= size.y else Vector2(length * size.x / size.y, length)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A glass display case, counter height (0.98 m), its customer side to +z: a dark base, a red felt bed with
## `stock` laid back on little stands along it (a weapon name each; a price tag in front of each), glass on the
## front, the ends and the top between steel corner posts, a lit strip inside the top, and a dark panel with two
## sliding doors on the clerk's side.
static func glass_case(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.3, d := 0.6, stock: Array = ["pistol"]) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var h := 0.98
	var bed := 0.38                                  # the felt's top
	var hw := w * 0.5
	var hd := d * 0.5
	Kit.block(g, Vector3(w - 0.04, 0.07, d - 0.04), Vector3.ZERO, BLACK)                                   # the kick, set in
	Kit.block(g, Vector3(w, 0.29, d), Vector3(0, 0.07, 0), Color(0.22, 0.18, 0.15))                         # the base
	Kit.block(g, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, 0.36, 0), FELT)                              # the felt bed
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.03, h - 0.385, 0.03), Vector3(sx * (hw - 0.015), 0.36 + (h - 0.385) * 0.5, sz * (hd - 0.015)), STEEL)      # up to the rim
	var tall := h - 0.02 - bed
	Kit.pane(Kit.box(g, Vector3(w - 0.06, tall, 0.008), Vector3(0, bed + tall * 0.5, hd - 0.012), GLASS))          # the front
	for sx: float in [-1.0, 1.0]:                                                                                  # the ends
		Kit.pane(Kit.box(g, Vector3(0.008, tall, d - 0.06), Vector3(sx * (hw - 0.012), bed + tall * 0.5, 0), GLASS))
	Kit.pane(Kit.box(g, Vector3(w - 0.07, 0.008, d - 0.07), Vector3(0, h - 0.016, 0.005), GLASS))                  # the top
	for sz: float in [-1.0, 1.0]:                                                                                  # the top's rim
		Kit.box(g, Vector3(w, 0.025, 0.03), Vector3(0, h - 0.0125, sz * (hd - 0.015)), STEEL.lightened(0.15))
	for sx: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.03, 0.025, d - 0.06), Vector3(sx * (hw - 0.015), h - 0.0125, 0), STEEL.lightened(0.15))
	Kit.box(g, Vector3(w - 0.12, 0.018, 0.03), Vector3(0, h - 0.05, -hd + 0.06), Kit.flat(Color(1.0, 0.96, 0.84), 1.4))   # the light
	Kit.box(g, Vector3(w - 0.06, tall, 0.02), Vector3(0, bed + tall * 0.5, -hd + 0.025), WOOD)                     # the clerk's side
	for sx: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.012, tall - 0.08, 0.006), Vector3(sx * 0.02, bed + tall * 0.5, -hd + 0.012), WOOD.darkened(0.4))
		Kit.box(g, Vector3(0.05, 0.025, 0.02), Vector3(sx * 0.1, bed + tall * 0.55, -hd + 0.005), STEEL)
	# The stock, laid back so it shows through the top and the front.
	var n := stock.size()
	for i in n:
		var x := -hw + w * (i + 0.5) / n
		var weapon := String(stock[i])
		Kit.block(g, Vector3(0.1, 0.05, 0.05), Vector3(x, bed, -0.06), BLACK)                                  # a stand
		var long := 0.36 if weapon == "uzi" else (0.62 if weapon == "ak" else 0.3)
		card(g, weapon, Vector3(x, bed + 0.1, -0.02), Vector3(-58.0, 0.0, 0.0), long)
		Kit.box(g, Vector3(0.07, 0.004, 0.04), Vector3(x + 0.06, bed + 0.002, 0.15), TAG, Vector3(0, -12.0 + 9.0 * i, 0))   # its price tag
	return g


## The long guns behind the counter, on the wall: a low cabinet as deep as `d` (it keeps its floor space), a
## board over it from 0.95 to 2.4 m, `n` rifles standing in a row on its ledge with a rail across their tops
## and a price tag on each, and at the right end a column of three machine pistols on hooks.
static func rifle_rack(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 3.0, d := 0.34, n := 7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var hd := d * 0.5
	var back := -hd + 0.01                          # the board's back, just off the wall
	Kit.block(g, Vector3(w, 0.06, d - 0.03), Vector3(0, 0, -0.015), BLACK)
	Kit.block(g, Vector3(w, 0.8, d), Vector3(0, 0.06, 0), WOOD)
	for i in 4:                                     # its doors
		var x := -w * 0.5 + w * (i + 0.5) / 4.0
		Kit.box(g, Vector3(w / 4.0 - 0.06, 0.66, 0.012), Vector3(x, 0.47, hd + 0.006), WOOD.lightened(0.08))
		Kit.box(g, Vector3(0.12, 0.025, 0.02), Vector3(x, 0.7, hd + 0.022), STEEL)
	Kit.bevel(g, Vector3(w + 0.02, 0.04, d + 0.02), Vector3(0, 0.88, 0), WOOD.darkened(0.25), 0.012)
	var board := Kit.tex("carpet", 1.0, Color(0.16, 0.24, 0.18), false, Color(0.4, 0.62, 0.45))
	Kit.box(g, Vector3(w, 1.45, 0.02), Vector3(0, 0.95 + 0.725, back), board)
	Kit.box(g, Vector3(w + 0.04, 0.05, 0.05), Vector3(0, 2.425, back + 0.015), WOOD.darkened(0.25))        # its cap
	var rifles := w - 0.75                            # the machine pistols have the right-hand end
	var tints := [Color.WHITE, Color(0.42, 0.42, 0.46), Color(0.72, 0.8, 0.52), Color.WHITE, Color(1.0, 0.86, 0.66), Color(0.42, 0.42, 0.46), Color.WHITE]
	for i in n:
		var x := -w * 0.5 + rifles * (i + 0.5) / n
		card(g, "ak", Vector3(x, 0.92 + 0.5, back + 0.032 + 0.008 * (i % 2)), Vector3(0, 0, 90.0), 1.0, tints[i % tints.size()])
		Kit.box(g, Vector3(0.06, 0.08, 0.004), Vector3(x + 0.08, 1.12, back + 0.05), TAG)
	Kit.box(g, Vector3(rifles - 0.1, 0.05, 0.05), Vector3(-w * 0.5 + rifles * 0.5, 1.86, back + 0.07), WOOD.darkened(0.15))     # the rail over their tops
	var px := w * 0.5 - 0.38
	for k in 3:
		var y := 1.25 + k * 0.38
		Kit.box(g, Vector3(0.025, 0.025, 0.08), Vector3(px - 0.05, y + 0.12, back + 0.05), STEEL)                    # its hook
		card(g, "uzi", Vector3(px, y, back + 0.04), Vector3.ZERO, 0.42, Color.WHITE if k != 1 else Color(0.5, 0.5, 0.55))
		Kit.box(g, Vector3(0.05, 0.07, 0.004), Vector3(px + 0.16, y - 0.06, back + 0.05), TAG)
	return g


## Steel shelving full of boxes of rounds: each a small box in a maker's colour with a white or yellow band
## across its front (no names), in runs and stacks. `h` tall, `w` long, its front to +z.
static func ammo_shelves(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, h := 1.9, d := 0.42) -> Node3D:
	var g: Node3D = Props.shelves(p, b, u, v, yaw, w, "none", Props.IRON, h, d)
	var rows := 5
	for i in rows - 1:
		var y := 0.1 + i * (h - 0.14) / float(rows - 1) + 0.015
		var x := -w * 0.5 + 0.08
		var k := 0
		while x < w * 0.5 - 0.2:
			var key := u * 5.1 + v * 2.3 + i * 13.7 + k * 1.37
			k += 1
			var bw := 0.1 + 0.07 * Props.rnd(key)
			var bh := 0.07 + 0.04 * Props.rnd(key + 4.0)
			var look: Color = AMMO[int(Props.rnd(key + 2.0) * AMMO.size()) % AMMO.size()]
			var stack := 1 + int(Props.rnd(key + 6.0) * 2.4)
			for s in stack:
				Kit.block(g, Vector3(bw, bh, 0.15), Vector3(x + bw * 0.5, y + s * (bh + 0.004), d * 0.5 - 0.11), look)
				Kit.box(g, Vector3(bw * 0.86, bh * 0.28, 0.006), Vector3(x + bw * 0.5, y + s * (bh + 0.004) + bh * 0.55, d * 0.5 - 0.032),
						TAG if Props.rnd(key + 8.0) > 0.35 else Color(0.98, 0.84, 0.2))
			x += bw + 0.015 + 0.05 * Props.rnd(key + 9.0)
	return g


## The buzzer by the door, on the wall's face at `pos` (it faces +z): a steel box with a red button and a
## speaker grille, and a white plate under it.
static func buzzer(parent: Node3D, pos: Vector3, plate := "") -> Node3D:
	var g := Kit.group(parent, pos)
	Kit.box(g, Vector3(0.11, 0.17, 0.04), Vector3(0, 0, 0.02), STEEL)
	Kit.disc(g, 0.022, Vector3(0, -0.04, 0.045), Kit.flat(Color(0.9, 0.12, 0.1), 0.4), 0.012, 12)
	for k in 3:
		Kit.box(g, Vector3(0.06, 0.008, 0.004), Vector3(0, 0.025 + k * 0.016, 0.042), BLACK)
	if plate != "":
		Kit.box(g, Vector3(0.56, 0.11, 0.008), Vector3(0, -0.17, 0.004), TAG)
		Props.words(g, plate, Vector3(0, -0.17, 0.01), 0.05, INK, 0.0, true)
	return g


# ------------------------------------------------------------- the back rooms

## A gunsmith's bench, its front to +z: a thick wooden top on steel legs with a shelf under, a vise at the left
## end, a rifle in a padded cradle in the middle, a tray of small parts, a cleaning rod's box and a lamp at the
## right end on an arm.
static func workbench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.4, d := 0.75) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var top := 0.92
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Kit.block(g, Vector3(0.06, top - 0.06, 0.06), Vector3(sx * (w * 0.5 - 0.06), 0, sz * (d * 0.5 - 0.06)), STEEL.darkened(0.3))
	Kit.block(g, Vector3(w - 0.1, 0.03, d - 0.1), Vector3(0, 0.2, 0), STEEL.darkened(0.2))                   # the shelf
	for i in 3:
		Kit.block(g, Vector3(0.36, 0.2, 0.3), Vector3(-0.7 + i * 0.6, 0.23, -0.05), AMMO[i + 2].darkened(0.2))   # bins on it
	Kit.bevel_block(g, Vector3(w, 0.06, d), Vector3(0, top - 0.06, 0), Color(0.62, 0.44, 0.26), 0.012)
	# The vise at the left end.
	var vx := -w * 0.5 + 0.25
	Kit.block(g, Vector3(0.16, 0.08, 0.2), Vector3(vx, top, 0.1), STEEL.darkened(0.1))
	Kit.block(g, Vector3(0.2, 0.1, 0.06), Vector3(vx, top + 0.08, 0.04), STEEL)
	Kit.block(g, Vector3(0.2, 0.1, 0.06), Vector3(vx, top + 0.08, 0.16), STEEL)
	Kit.tube(g, Vector3(vx - 0.14, top + 0.12, 0.22), Vector3(vx + 0.14, top + 0.12, 0.22), 0.012, STEEL.lightened(0.2))
	# The rifle lying in its cradle, tipped up a little towards the room so it shows.
	for x: float in [-0.32, 0.3]:
		Kit.block(g, Vector3(0.1, 0.1, 0.16), Vector3(x, top, -0.08), Color(0.7, 0.16, 0.12))
	card(g, "ak", Vector3(0.0, top + 0.13, -0.08), Vector3(-78.0, 0.0, 0.0), 0.95)
	# A tray of parts, a box, the lamp.
	Kit.block(g, Vector3(0.34, 0.03, 0.22), Vector3(0.75, top, 0.12), STEEL)
	for k in 5:
		Kit.block(g, Vector3(0.04, 0.02, 0.03), Vector3(0.64 + k * 0.055, top + 0.03, 0.1 + 0.02 * (k % 2)), BLACK)
	Kit.block(g, Vector3(0.5, 0.06, 0.1), Vector3(0.5, top, -0.27), Color(0.2, 0.36, 0.22))
	var lamp := Vector3(w * 0.5 - 0.16, top, -0.25)
	Kit.cyl(g, 0.08, 0.03, lamp + Vector3(0, 0.015, 0), BLACK, Vector3.ZERO, 10)
	Kit.tube(g, lamp + Vector3(0, 0.03, 0), lamp + Vector3(-0.1, 0.32, 0.05), 0.014, BLACK)
	Kit.tube(g, lamp + Vector3(-0.1, 0.32, 0.05), lamp + Vector3(-0.3, 0.24, 0.18), 0.014, BLACK)
	Kit.cyl(g, 0.07, 0.12, lamp + Vector3(-0.3, 0.19, 0.18), Color(0.78, 0.16, 0.12), Vector3(0, 0, 0), 10, 0.035)
	Kit.cyl(g, 0.055, 0.01, lamp + Vector3(-0.3, 0.13, 0.18), Kit.flat(Color(1.0, 0.92, 0.7), 1.6), Vector3.ZERO, 10)
	return g


## A tall gun safe, its door to +z: dark steel on little feet, the door set in with a spoked handle, a dial and
## a brass name plate (blank), two hinge pins down the left.
static func gun_safe(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.9, 0.7)
	var body := Color(0.2, 0.21, 0.24)
	var brass := Color(0.84, 0.68, 0.3)
	for x: float in [-0.38, 0.38]:
		for z: float in [-0.28, 0.28]:
			Kit.block(g, Vector3(0.08, 0.04, 0.08), Vector3(x, 0, z), BLACK)
	Kit.bevel_block(g, Vector3(0.9, 1.78, 0.7), Vector3(0, 0.04, 0), body, 0.04)
	Kit.box(g, Vector3(0.74, 1.58, 0.02), Vector3(0, 0.94, 0.356), body.lightened(0.07))
	Kit.box(g, Vector3(0.2, 0.05, 0.006), Vector3(0, 1.58, 0.369), brass)
	Kit.disc(g, 0.07, Vector3(0.14, 1.12, 0.372), STEEL, 0.014, 16)
	Kit.disc(g, 0.05, Vector3(0.14, 1.12, 0.382), BLACK, 0.006, 16)
	var hub := Vector3(0.14, 0.86, 0.376)
	Kit.disc(g, 0.035, hub, STEEL.lightened(0.2), 0.03, 10)
	for k in 5:
		var a := deg_to_rad(90.0 + k * 72.0)
		var tip := hub + Vector3(cos(a), sin(a), 0.02) * 0.13
		Kit.tube(g, hub, tip, 0.012, STEEL.lightened(0.2))
		Kit.ball(g, 0.02, tip, BLACK, 8)
	for y: float in [0.45, 1.4]:
		Kit.cyl(g, 0.02, 0.16, Vector3(-0.38, y, 0.372), brass)
	return g


## A monitor on a desk showing four camera pictures (dark grey, a lighter shape in each): the shop floor, the
## door, the range, the back. Its screen faces +z.
static func cameras_screen(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.block(g, Vector3(0.2, 0.02, 0.14), Vector3.ZERO, BLACK)
	Kit.box(g, Vector3(0.04, 0.2, 0.03), Vector3(0, 0.12, -0.02), BLACK)
	Kit.box(g, Vector3(0.56, 0.36, 0.04), Vector3(0, 0.38, 0), BLACK)
	for k in 4:
		var c := Vector2(-0.13 + (k % 2) * 0.26, 0.46 - floori(k / 2.0) * 0.17)
		Kit.box(g, Vector3(0.245, 0.155, 0.004), Vector3(c.x, c.y, 0.021), Kit.flat(Color(0.2, 0.26, 0.24), 0.5))
		Kit.box(g, Vector3(0.06 + 0.04 * k, 0.05, 0.003), Vector3(c.x - 0.04 + 0.02 * k, c.y - 0.03, 0.0235), Kit.flat(Color(0.42, 0.5, 0.46), 0.5))
	return g


# ------------------------------------------------------------------ the range

## A booth partition, running front to back at u from v0 to v1: a steel frame round a padded panel, `h` tall.
static func partition(p: Node3D, b: int, u: float, v0: float, v1: float, h := 1.7) -> Node3D:
	var g: Node3D = p.prop(b, u, (v0 + v1) * 0.5, 0.0, 0.08, v1 - v0)
	var long := v1 - v0
	Kit.block(g, Vector3(0.08, h, long), Vector3.ZERO, STEEL.darkened(0.25))
	Kit.box(g, Vector3(0.1, h - 0.16, long - 0.12), Vector3(0, h * 0.5 + 0.02, 0), Kit.tex("in_acoustic", 0.6, Color(0.5, 0.5, 0.5), false, Color(0.62, 0.62, 0.64)))
	return g


## The shelf at the front of a booth, from u0 to u1 at v (its front edge, downrange), d deep, 0.77 high (his
## waist: any higher and a shot from a gun held over it can clip it): a steel shelf on a solid front, a control
## box with two buttons on it and a box of paper targets.
static func booth_shelf(p: Node3D, b: int, u0: float, u1: float, v: float, d := 0.36) -> Node3D:
	var w := u1 - u0
	var top := 0.72
	var g: Node3D = p.prop(b, (u0 + u1) * 0.5, v + d * 0.5, 0.0, w, d)
	Kit.block(g, Vector3(w, top, d - 0.04), Vector3(0, 0, -0.02), Color(0.3, 0.32, 0.34))
	Kit.bevel_block(g, Vector3(w, 0.05, d), Vector3(0, top, 0), STEEL.lightened(0.1), 0.01)
	Kit.block(g, Vector3(0.22, 0.12, 0.16), Vector3(-w * 0.5 + 0.22, top + 0.05, -0.02), Color(0.86, 0.84, 0.78))
	Kit.disc(g, 0.022, Vector3(-w * 0.5 + 0.17, top + 0.13, 0.065), Kit.flat(Color(0.2, 0.75, 0.3), 0.6), 0.012, 10)
	Kit.disc(g, 0.022, Vector3(-w * 0.5 + 0.27, top + 0.13, 0.065), Kit.flat(Color(0.9, 0.15, 0.12), 0.6), 0.012, 10)
	Kit.block(g, Vector3(0.3, 0.04, 0.24), Vector3(w * 0.5 - 0.25, top + 0.05, 0.0), PAPER)
	return g


## The backstop across the back of the range, from u0 to u1, its foot at v: steel plates sloping up to the back
## wall, a rubber trap along their foot, a hazard band along their top.
static func backstop(p: Node3D, b: int, u0: float, u1: float, v: float, h := 2.5) -> Node3D:
	var n: Node3D = p.node_of(b)
	var w := u1 - u0
	var g := Kit.group(n, p.pt((u0 + u1) * 0.5, v))
	var slope := atan2(v - 0.08, h)                  # from the foot up to the wall
	var long := sqrt(h * h + (v - 0.08) * (v - 0.08))
	var plate := Kit.tex("in_ribbed", 0.5, Color(0.3, 0.3, 0.32), false, Color(0.5, 0.5, 0.54))
	Kit.box(g, Vector3(w, long, 0.04), Vector3(0, h * 0.5, -(v - 0.08) * 0.5), plate, Vector3(-rad_to_deg(slope), 0, 0))
	Kit.block(g, Vector3(w, 0.32, 0.3), Vector3(0, 0, 0.05), Color(0.12, 0.12, 0.13))
	var up := Vector3(0, cos(slope), -sin(slope))      # along the plates, and out of their face
	var out := Vector3(0, sin(slope), cos(slope))
	Kit.box(g, Vector3(w, 0.12, 0.02), up * (long - 0.1) + out * 0.031, Kit.tex("in_hazard", 0.5, Color(0.9, 0.75, 0.1), false), Vector3(-rad_to_deg(slope), 0, 0))
	p.block(u0, 0.0, u1, v + 0.2)
	return g


## The track a target runs along, overhead at y, from v0 to v1 at u: a steel channel on two hangers.
static func track(p: Node3D, b: int, u: float, v0: float, v1: float, y := 2.5) -> void:
	var n: Node3D = p.node_of(b)
	p.slab(n, false, u, v0, v1, y, y + 0.07, 0.09, STEEL.darkened(0.2))
	for v: float in [v0 + 0.3, v1 - 0.3]:
		Kit.box(n, Vector3(0.05, p.wall_h - y - 0.07, 0.05), p.pt(u, v, (p.wall_h + y + 0.07) * 0.5), STEEL.darkened(0.35))


## A target on its carrier, hung from a track at y, its paper to +z (towards the booths): a trolley, an arm
## down, a clamp bar, a cardboard backer and the paper itself (a plain quad with `look` on it, the one mesh a
## shot is scored on; gun_shop.gd gives it its own picture). Returns {"carrier": the node that runs along the
## track, "paper": the paper's mesh}.
static func target(p: Node3D, b: int, u: float, v: float, look: Material = null, y := 2.5, name := "TargetPaper") -> Dictionary:
	var carrier := Kit.group(p.node_of(b), p.pt(u, v), Vector3.ZERO, name + "Carrier")
	Kit.box(carrier, Vector3(0.12, 0.1, 0.2), Vector3(0, y - 0.05, 0), Color(0.86, 0.6, 0.12))
	var mid := y - 0.1 - 0.38                          # the clamp's height
	Kit.box(carrier, Vector3(0.05, y - 0.1 - mid, 0.05), Vector3(0, (y - 0.1 + mid) * 0.5, 0), STEEL.darkened(0.3))
	Kit.box(carrier, Vector3(PAPER_W + 0.12, 0.05, 0.05), Vector3(0, mid, 0.01), STEEL.darkened(0.3))
	Kit.box(carrier, Vector3(PAPER_W + 0.06, PAPER_H + 0.06, 0.012), Vector3(0, mid - 0.02 - PAPER_H * 0.5, 0.0), Color(0.62, 0.48, 0.32))
	var quad := QuadMesh.new()
	quad.size = Vector2(PAPER_W, PAPER_H)
	var paper := MeshInstance3D.new()
	paper.name = name
	paper.mesh = quad
	paper.material_override = look
	paper.position = Vector3(0, mid - 0.025 - PAPER_H * 0.5, 0.009)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carrier.add_child(paper)
	return {"carrier": carrier, "paper": paper}


## A fresh target paper: cream, a bull's-eye of rings (the 5 to the 7 as lines on the paper, the 8 and the 9 on
## black, the 10 red), a grey band across the top where the clamp holds it. Every edge is smoothed across a
## pixel and the picture has its mipmaps, so the rings stay clean from the booth. A new copy each time.
static func target_image() -> Image:
	if _blank == null:
		var img := Image.create(TARGET_PX.x, TARGET_PX.y, false, Image.FORMAT_RGBA8)
		img.fill(PAPER)
		var reach := float(RINGS[5]) + 5.0
		for y in range(maxi(floori(BULL.y - reach), 0), mini(ceili(BULL.y + reach), TARGET_PX.y)):
			for x in range(maxi(floori(BULL.x - reach), 0), mini(ceili(BULL.x + reach), TARGET_PX.x)):
				var r := Vector2(x + 0.5, y + 0.5).distance_to(BULL)
				if r > reach:
					continue
				var c := PAPER.lerp(INK, _cover(RINGS[2] - r))                  # the black: the 8 and the 9
				c = c.lerp(PAPER, _cover(2.6 - absf(r - RINGS[1])))             # the line between them
				c = c.lerp(RED, _cover(RINGS[0] - r))                           # the 10
				for k: int in [3, 4, 5]:                                        # the 7, the 6 and the 5: lines
					c = c.lerp(INK, _cover((3.6 if k == 5 else 2.6) - absf(r - RINGS[k])))
				if c != PAPER:
					img.set_pixel(x, y, c)
		img.fill_rect(Rect2i(0, 0, TARGET_PX.x, 18), Color(0.72, 0.7, 0.64))
		img.fill_rect(Rect2i(0, TARGET_PX.y - 6, TARGET_PX.x, 6), Color(0.8, 0.78, 0.7))
		img.generate_mipmaps()
		_blank = img
	return _blank.duplicate()


## How much of a pixel lies inside an edge whose middle is `d` pixels away (d > 0: inside): 0 to 1, smooth across it.
static func _cover(d: float) -> float:
	return clampf(d + 0.5, 0.0, 1.0)


## A shot's hole in a target's picture at `at` (pixels): dark, about 3 cm across, in a ragged grey edge where the
## paper tore (the rags fall the same way for the same spot). Bigger than a real one, so it shows from the booth.
## The picture's mipmaps are made again after.
static func mark_hole(img: Image, at: Vector2) -> void:
	var core := 9.6
	var torn := 13.2
	var turns := Vector3(fmod(absf(at.x * 12.9898 + at.y * 78.233), TAU), fmod(absf(at.x * 39.346 + at.y * 11.135), TAU),
			fmod(absf(at.x * 73.156 + at.y * 52.235), TAU))      # three ripples round the rim, so no two tear alike
	for dy in range(-17, 18):
		for dx in range(-17, 18):
			var px := Vector2i(floori(at.x) + dx, floori(at.y) + dy)
			if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
				continue
			var off := Vector2(px) + Vector2(0.5, 0.5) - at
			var r := off.length()
			if r > torn * 1.2 + 1.0:
				continue
			var a := off.angle()
			var rag := torn * (1.0 + 0.09 * sin(3.0 * a + turns.x) + 0.06 * sin(7.0 * a + turns.y) + 0.04 * sin(11.0 * a + turns.z))
			var c := img.get_pixelv(px).lerp(Color(0.6, 0.55, 0.48), 0.55 * _cover(rag - r))
			img.set_pixelv(px, c.lerp(Color(0.1, 0.08, 0.07), _cover(core - r)))
	img.generate_mipmaps()


## What a hole at `at` (pixels) scores: 10 in the red, down to 5 in the outer ring, 0 elsewhere on the paper.
static func score_at(at: Vector2) -> int:
	var r := at.distance_to(BULL)
	for i in RINGS.size():
		if r <= float(RINGS[i]):
			return 10 - i
	return 0


## Where the middle of the rings is on the paper's mesh (its own x and y, metres).
static func bull_local() -> Vector3:
	return Vector3((BULL.x / TARGET_PX.x - 0.5) * PAPER_W, (0.5 - BULL.y / TARGET_PX.y) * PAPER_H, 0.0)


## Fresh targets for sale, pinned on a dark board on a wall's face (it faces +z after `yaw`), its middle at
## height y: n papers side by side, a price tag under each.
static func target_board(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 3, y := 1.65) -> Node3D:
	var g := Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))
	var w := n * (PAPER_W * 0.7 + 0.08) + 0.08
	Kit.box(g, Vector3(w, PAPER_H * 0.7 + 0.26, 0.025), Vector3(0, y, 0.0125), Color(0.22, 0.2, 0.19))
	var look := StandardMaterial3D.new()
	look.albedo_texture = ImageTexture.create_from_image(target_image())
	look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	look.roughness = 1.0
	look.metallic_specular = 0.0
	for i in n:
		var x := -w * 0.5 + 0.08 + (PAPER_W * 0.7 + 0.08) * (i + 0.5)
		var quad := QuadMesh.new()
		quad.size = Vector2(PAPER_W, PAPER_H) * 0.7
		var paper := MeshInstance3D.new()
		paper.mesh = quad
		paper.material_override = look
		paper.position = Vector3(x, y + 0.06, 0.028)
		paper.rotation_degrees = Vector3(0, 0, (i - 1) * 2.5)
		paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(paper)
		Kit.box(g, Vector3(0.1, 0.05, 0.004), Vector3(x, y - PAPER_H * 0.35 - 0.04, 0.027), TAG)
	return g
