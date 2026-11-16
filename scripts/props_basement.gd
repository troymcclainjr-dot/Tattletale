extends RefCounted
## Fittings for the hospital's basement (plans/hospital_basement.gd; the civic
## worker's): the morgue's cold store and its steel table, a body under a sheet
## with a tag on its toe, the boiler, the laundry's machines, the chute the
## dirty linen comes down and shelves of clean, the service lift's doors, name
## plates.
##
## As in props.gd: `p` is the Place, `b` the band a thing stands in, (u, v) the
## middle of the floor it takes, `yaw` the way its front faces (0 the street, 90
## right, 180 the back, 270 left). Things on a wall take `n`, the node to build
## in, and `face`, the plane of a wall facing +v (towards the camera).

const Props := preload("res://scripts/props.gd")

const STAINLESS := Color(0.7, 0.72, 0.74)
const SHEET := Color(0.9, 0.91, 0.89)
const TAG := Color(0.86, 0.74, 0.5)             # a manila tag
const ENAMEL := Color(0.88, 0.89, 0.87)         # the machines' white
const LAMP := Color(1.0, 0.62, 0.22)            # a lit button, a floor lamp, a display


## The morgue's cold store against a back wall: a steel cabinet, cols x rows
## square doors, each with its lever and a card in its holder; the cooling's
## display on the band over them; a tag hung on one lever.
static func drawers(p: Node3D, b: int, u: float, v: float, cols := 4, rows := 3) -> Node3D:
	var cell := 0.72
	var hi := 0.62
	var foot := 0.14
	var w := cols * cell + 0.12
	var d := 0.5
	var h := foot + rows * hi + 0.32
	var g: Node3D = p.prop(b, u, v, 0.0, w, d)
	var front := d * 0.5
	Kit.block(g, Vector3(w, h, d), Vector3.ZERO, STAINLESS.darkened(0.14))
	Kit.block(g, Vector3(w - 0.04, foot - 0.04, 0.02), Vector3(0, 0.01, front + 0.01), Color(0.24, 0.25, 0.27))      # the kick plate
	for c in cols:
		for r in rows:
			var x := -w * 0.5 + 0.06 + (c + 0.5) * cell
			var y := foot + (r + 0.5) * hi
			Kit.box(g, Vector3(cell - 0.06, hi - 0.06, 0.024), Vector3(x, y, front + 0.012), STAINLESS)
			Kit.box(g, Vector3(0.05, 0.2, 0.05), Vector3(x + cell * 0.5 - 0.12, y, front + 0.05), Color(0.38, 0.4, 0.43))      # the lever
			Kit.box(g, Vector3(0.15, 0.09, 0.006), Vector3(x - cell * 0.5 + 0.14, y + hi * 0.5 - 0.11, front + 0.027), Color(0.5, 0.52, 0.55))
			Kit.box(g, Vector3(0.12, 0.062, 0.004), Vector3(x - cell * 0.5 + 0.14, y + hi * 0.5 - 0.11, front + 0.032), Props.PAPER)
	# The display, red figures on dark, on the band over the doors.
	var top := foot + rows * hi
	Kit.box(g, Vector3(0.26, 0.12, 0.02), Vector3(w * 0.5 - 0.3, top + 0.16, front + 0.01), Color(0.14, 0.15, 0.17))
	Kit.box(g, Vector3(0.18, 0.06, 0.004), Vector3(w * 0.5 - 0.3, top + 0.16, front + 0.022), Kit.flat(Color(1.0, 0.3, 0.2), 1.2))
	# A tag on its string from the lever of the second door along, in the middle row.
	var tx := -w * 0.5 + 0.06 + 1.5 * cell + cell * 0.5 - 0.12
	var ty := foot + 1.5 * hi
	Kit.box(g, Vector3(0.004, 0.1, 0.004), Vector3(tx, ty - 0.14, front + 0.078), Color(0.92, 0.9, 0.84), Vector3(0, 0, 6))
	Kit.box(g, Vector3(0.07, 0.11, 0.004), Vector3(tx - 0.006, ty - 0.24, front + 0.08), TAG, Vector3(0, 0, 9))
	return g


## The post-mortem table: a stainless top with a lip all round and a drain
## hole at its foot (+x of its own), on one fat pedestal; a tap arched over its
## head and the block the head rests on. Long along its own x.
static func steel_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var l := 2.1
	var w := 0.76
	var y := 0.88
	var g: Node3D = p.prop(b, u, v, yaw, l + 0.1, w)
	Kit.cyl(g, 0.3, 0.05, Vector3(0, 0.025, 0), STAINLESS.darkened(0.3), Vector3.ZERO, 12)
	Kit.cyl(g, 0.13, y - 0.1, Vector3(0, 0.05 + (y - 0.1) * 0.5, 0), STAINLESS.darkened(0.15), Vector3.ZERO, 12)
	Kit.box(g, Vector3(l, 0.05, w), Vector3(0, y - 0.025, 0), STAINLESS)
	for s: float in [-1.0, 1.0]:          # the lip, on top of it
		Kit.box(g, Vector3(l, 0.045, 0.03), Vector3(0, y + 0.0225, s * (w * 0.5 - 0.015)), STAINLESS)
		Kit.box(g, Vector3(0.03, 0.045, w - 0.06), Vector3(s * (l * 0.5 - 0.015), y + 0.0225, 0), STAINLESS)
	Kit.cyl(g, 0.045, 0.006, Vector3(l * 0.5 - 0.15, y + 0.003, 0), Color(0.22, 0.23, 0.25), Vector3.ZERO, 12)       # the drain hole
	Kit.bevel(g, Vector3(0.14, 0.08, 0.22), Vector3(-l * 0.5 + 0.3, y + 0.04, 0), Color(0.3, 0.32, 0.36), 0.03)    # the head block
	var tap := Vector3(-l * 0.5 - 0.02, y, -w * 0.5 + 0.08)
	Kit.tube(g, tap, tap + Vector3(0, 0.46, 0), 0.016, STAINLESS.darkened(0.1))
	Kit.tube(g, tap + Vector3(0, 0.46, 0), tap + Vector3(0.24, 0.46, 0.0), 0.016, STAINLESS.darkened(0.1))
	Kit.cyl(g, 0.03, 0.06, tap + Vector3(0.24, 0.43, 0.0), STAINLESS.darkened(0.25), Vector3.ZERO, 8)
	return g


## A body under a sheet on a trolley (Props.gurney: its head at the back of its
## floor space), a manila tag on a string from a toe at the foot.
static func covered(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = Props.gurney(p, b, u, v, yaw, SHEET, false)
	# The shape under the sheet: the chest, the legs, the head on the pillow, the feet up.
	Kit.bevel(g, Vector3(0.5, 0.18, 0.75), Vector3(0, 0.82, -0.32), SHEET, 0.08)
	Kit.bevel(g, Vector3(0.42, 0.13, 0.7), Vector3(0, 0.79, 0.4), SHEET.darkened(0.03), 0.06)
	Kit.ball(g, 0.14, Vector3(0, 0.86, -0.78), SHEET, 10)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(g, Vector3(0.1, 0.16, 0.08), Vector3(s * 0.09, 0.86, 0.78), SHEET, 0.035)
	# The sheet falls over the sides and the foot.
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.012, 0.22, 1.8), Vector3(s * 0.436, 0.62, 0.0), SHEET.darkened(0.07))
	Kit.box(g, Vector3(0.86, 0.2, 0.012), Vector3(0, 0.63, 0.906), SHEET.darkened(0.05))
	# The tag, on a string from a toe.
	Kit.box(g, Vector3(0.004, 0.12, 0.004), Vector3(0.09, 0.8, 0.83), Color(0.92, 0.9, 0.84))
	Kit.box(g, Vector3(0.07, 0.11, 0.004), Vector3(0.09, 0.7, 0.92), TAG, Vector3(0, 0, 8))
	return g


## The boiler: a long steel shell lying on a brick plinth, painted and banded
## at its seams; the burner on its front end (+x of its own), red, the flame
## showing in its little window; the flue up from the back end and two pipes
## up from the top into the ceiling; the gauge on a stub at the front. About
## 4 m by 1.7 of floor.
static func boiler(p: Node3D, b: int, u: float, v: float, yaw := 0.0, ceil := 2.9) -> Node3D:
	var l := 3.0
	var r := 0.68
	var g: Node3D = p.prop(b, u, v, yaw, l + 1.0, 1.7)
	var shell := Color(0.3, 0.38, 0.36)
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.26, 0.2), false, Color(0.7, 0.5, 0.42))
	var x0 := -0.35                        # the shell's middle (the burner takes the front)
	var cy := 0.4 + r
	Kit.block(g, Vector3(l + 0.2, 0.4, 1.1), Vector3(x0, 0, 0), brick)
	Kit.cyl(g, r, l, Vector3(x0, cy, 0), shell, Vector3(0, 0, 90), 18)
	for k in 5:                            # the seams
		Kit.cyl(g, r + 0.018, 0.06, Vector3(x0 - l * 0.5 + 0.3 + k * (l - 0.6) / 4.0, cy, 0), shell.darkened(0.25), Vector3(0, 0, 90), 18)
	for s: float in [-1.0, 1.0]:           # the end plates
		Kit.cyl(g, r + 0.03, 0.05, Vector3(x0 + s * (l * 0.5 + 0.025), cy, 0), shell.darkened(0.35), Vector3(0, 0, 90), 18)
	# The burner.
	var fx := x0 + l * 0.5 + 0.05
	var red := Color(0.64, 0.17, 0.12)
	Kit.box(g, Vector3(0.52, 0.58, 0.62), Vector3(fx + 0.26, cy - 0.1, 0), red)
	Kit.cyl(g, 0.18, 0.2, Vector3(fx + 0.62, cy - 0.1, 0), red.darkened(0.25), Vector3(0, 0, 90), 14)
	Kit.cyl(g, 0.12, 0.03, Vector3(fx + 0.735, cy - 0.1, 0), Color(0.3, 0.3, 0.32), Vector3(0, 0, 90), 12)
	Kit.cyl(g, 0.075, 0.016, Vector3(fx + 0.26, cy + 0.02, 0.318), Kit.flat(Color(1.0, 0.55, 0.15), 1.8), Vector3(90, 0, 0), 12)
	Kit.cyl(g, 0.09, 0.012, Vector3(fx + 0.26, cy + 0.02, 0.312), Color(0.3, 0.3, 0.32), Vector3(90, 0, 0), 12)
	Kit.box(g, Vector3(0.18, 0.1, 0.012), Vector3(fx + 0.26, cy - 0.24, 0.316), Color(0.2, 0.2, 0.22))        # its switches
	Kit.box(g, Vector3(0.04, 0.04, 0.008), Vector3(fx + 0.21, cy - 0.24, 0.325), Kit.flat(Color(0.3, 1.0, 0.4), 1.2))
	# The flue from the back end, and two pipes from the top, into the ceiling.
	var top := cy + r
	var fl := x0 - l * 0.5 + 0.45
	Kit.cyl(g, 0.22, ceil - top + 0.1, Vector3(fl, (top - 0.1 + ceil) * 0.5, 0), Props.IRON, Vector3.ZERO, 12)
	Kit.cyl(g, 0.25, 0.08, Vector3(fl, top + 0.2, 0), Props.IRON.lightened(0.1), Vector3.ZERO, 12)
	for px: float in [x0 + 0.2, x0 + 0.75]:
		Kit.cyl(g, 0.06, ceil - top + 0.05, Vector3(px, (top - 0.05 + ceil) * 0.5, -0.1), Props.STEEL, Vector3.ZERO, 8)
		Kit.cyl(g, 0.085, 0.06, Vector3(px, top + 0.12, -0.1), Props.STEEL.darkened(0.2), Vector3.ZERO, 8)
	# The safety valve on top; the gauge on a stub, its face to the front.
	Kit.cyl(g, 0.05, 0.22, Vector3(x0 - 0.6, top + 0.08, 0), Color(0.7, 0.58, 0.3), Vector3.ZERO, 8)
	Kit.tube(g, Vector3(x0 + 1.1, top - 0.08, 0.2), Vector3(x0 + 1.1, top + 0.22, 0.32), 0.02, Props.STEEL)
	Kit.cyl(g, 0.11, 0.05, Vector3(x0 + 1.1, top + 0.3, 0.34), Props.IRON, Vector3(90, 0, 0), 14)
	Kit.cyl(g, 0.09, 0.012, Vector3(x0 + 1.1, top + 0.3, 0.37), Color(0.95, 0.94, 0.88), Vector3(90, 0, 0), 14)
	Kit.box(g, Vector3(0.012, 0.075, 0.004), Vector3(x0 + 1.1 + 0.02, top + 0.32, 0.38), Color(0.75, 0.12, 0.1), Vector3(0, 0, -40))
	return g


## A laundry machine on the floor: an enamel box, the round door in its front
## (a sheet going round behind the grey-blue glass of a washer, a drier's drum
## lighter), the dials and a little display on a strip along the top.
static func machine(p: Node3D, b: int, u: float, v: float, yaw := 0.0, dryer := false) -> Node3D:
	var w := 0.96
	var d := 0.85
	var h := 1.38
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var front := d * 0.5
	Kit.bevel_block(g, Vector3(w, h, d), Vector3.ZERO, ENAMEL, 0.03)
	Kit.box(g, Vector3(w - 0.1, 0.2, 0.02), Vector3(0, h - 0.17, front + 0.004), Color(0.34, 0.36, 0.4))
	for k in 3:
		Kit.cyl(g, 0.035, 0.03, Vector3(-0.3 + k * 0.13, h - 0.17, front + 0.026), STAINLESS, Vector3(90, 0, 0), 10)
	Kit.box(g, Vector3(0.16, 0.06, 0.006), Vector3(0.26, h - 0.17, front + 0.017), Kit.flat(LAMP, 1.0))
	var dy := 0.66
	Kit.ring(g, 0.28, 0.05, Vector3(0, dy, front + 0.03), STAINLESS)
	if dryer:
		Kit.disc(g, 0.235, Vector3(0, dy, front + 0.012), Color(0.62, 0.64, 0.66), 0.012, 20)
		for k in 4:            # the drum's ribs, through the glass
			Kit.box(g, Vector3(0.3, 0.018, 0.004), Vector3(0, dy - 0.12 + k * 0.08, front + 0.021), Color(0.5, 0.52, 0.54))
	else:
		Kit.disc(g, 0.235, Vector3(0, dy, front + 0.012), Color(0.44, 0.52, 0.6), 0.012, 20)
		Kit.box(g, Vector3(0.26, 0.12, 0.004), Vector3(0.02, dy - 0.07, front + 0.021), SHEET.darkened(0.1), Vector3(0, 0, -18))
	Kit.box(g, Vector3(0.05, 0.12, 0.03), Vector3(0.31, dy, front + 0.04), STAINLESS.darkened(0.2))      # the door's handle
	Kit.box(g, Vector3(w - 0.1, 0.07, 0.006), Vector3(0, 0.12, front + 0.003), Color(0.62, 0.63, 0.62))       # the kick plate
	return g


## The foot of the linen chute on a wall facing +v (face at v = `face`): a
## steel duct down from the floor above to a hooded mouth `mouth` up, a sheet
## hanging out of it. Put a cart under it.
static func chute(p: Node3D, n: Node3D, u: float, face: float, mouth := 1.45, ceil := 2.9) -> void:
	var g := Kit.group(n, p.pt(u, face))
	var w := 0.62
	Kit.box(g, Vector3(w, ceil - mouth, 0.5), Vector3(0, (ceil + mouth) * 0.5, 0.25), STAINLESS.darkened(0.12))
	Kit.box(g, Vector3(w + 0.06, 0.06, 0.53), Vector3(0, mouth + 0.03, 0.265), STAINLESS.darkened(0.3))
	Kit.box(g, Vector3(w - 0.1, 0.012, 0.4), Vector3(0, mouth - 0.004, 0.24), Color(0.24, 0.25, 0.27))
	for k in 3:                 # the duct's joints
		Kit.box(g, Vector3(w + 0.02, 0.04, 0.52), Vector3(0, mouth + 0.35 + k * 0.38, 0.26), STAINLESS.darkened(0.22))
	Kit.box(g, Vector3(0.34, 0.36, 0.02), Vector3(0.04, mouth - 0.17, 0.4), SHEET, Vector3(10, 0, 7))


## Steel shelving of clean linen: folded sheets and towels in stacks, white,
## pale blue and pale yellow (no green: green and white read as cash).
static func linen(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.8) -> Node3D:
	var h := 1.9
	var d := 0.45
	var g: Node3D = Props.shelves(p, b, u, v, yaw, w, "none", Props.STEEL, h, d)
	var tints := [SHEET, Color(0.72, 0.82, 0.92), Color(0.94, 0.9, 0.7)]
	for i in 4:
		var y := 0.1 + i * (h - 0.14) / 4.0 + 0.016
		var x := -w * 0.5 + 0.06
		var k := 0
		while x < w * 0.5 - 0.36:
			var key := u * 3.1 + v * 1.7 + i * 5.3 + k * 2.9
			var tint: Color = tints[int(Props.rnd(key) * 3.0) % 3]
			var stack := 2 + int(Props.rnd(key + 4.0) * 3.0)
			for s in stack:
				Kit.bevel_block(g, Vector3(0.3, 0.07, d - 0.12), Vector3(x + 0.16, y + s * 0.072, 0), tint.darkened(0.05 * (s % 2)), 0.02)
			x += 0.36
			k += 1
	return g


## Folded linen in stacks on a table's top (the group Props.table returns, its
## top `top` up), from x0 to x1 along it.
static func folded(g: Node3D, top: float, x0: float, x1: float, key := 0.0) -> void:
	var tints := [SHEET, Color(0.72, 0.82, 0.92), Color(0.94, 0.9, 0.7)]
	var x := x0
	var k := 0
	while x < x1 - 0.32:
		var tint: Color = tints[int(Props.rnd(key + k * 1.7) * 3.0) % 3]
		var stack := 1 + int(Props.rnd(key + k * 2.3 + 3.0) * 4.0)
		for s in stack:
			Kit.bevel_block(g, Vector3(0.32, 0.07, 0.34), Vector3(x + 0.16, top + 0.002 + s * 0.072, -0.05 + 0.04 * (k % 2)), tint.darkened(0.05 * (s % 2)), 0.02)
		x += 0.4
		k += 1


## The service lift's doors on a wall facing +v (face at v = `face`), centred
## at u, 1.1 wide: a steel plate round them standing off the wall, two brushed
## leaves meeting in the middle, the sill on the floor; over it the two floor
## lamps (`lit` 0 the lower, 1 the upper); at its right the call buttons.
static func lift(p: Node3D, n: Node3D, u: float, face: float, lit := 0) -> Node3D:
	var g := Kit.group(n, p.pt(u, face))
	var w := 1.1
	var h := 2.1
	var frame := Color(0.5, 0.52, 0.55)
	Kit.box(g, Vector3(w + 0.24, h + 0.12, 0.04), Vector3(0, (h + 0.12) * 0.5, 0.02), frame)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w * 0.5 - 0.008, h, 0.03), Vector3(s * (w * 0.25 + 0.004), h * 0.5, 0.055), STAINLESS)
		Kit.box(g, Vector3(0.012, h - 0.3, 0.004), Vector3(s * (w * 0.25 + 0.004) - 0.18, h * 0.5, 0.072), STAINLESS.lightened(0.12))     # a gleam down each
	Kit.box(g, Vector3(w + 0.1, 0.012, 0.16), Vector3(0, 0.006, 0.08), STAINLESS.darkened(0.25))
	# The floor lamps over it, on a dark strip.
	Kit.box(g, Vector3(0.42, 0.14, 0.03), Vector3(0, h + 0.32, 0.015), Props.IRON)
	for k in 2:
		Kit.disc(g, 0.035, Vector3(-0.09 + k * 0.18, h + 0.32, 0.034), Kit.flat(LAMP, 1.4) if k == lit else Color(0.36, 0.3, 0.24), 0.008, 12)
	# The call buttons (3 cm deep: off a wall's rail, under it or over it).
	var cx := w * 0.5 + 0.3
	Kit.box(g, Vector3(0.13, 0.28, 0.03), Vector3(cx, 1.2, 0.015), STAINLESS)
	Kit.disc(g, 0.026, Vector3(cx, 1.26, 0.032), Kit.flat(LAMP, 1.2), 0.008, 12)
	Kit.disc(g, 0.026, Vector3(cx, 1.14, 0.032), Color(0.32, 0.33, 0.35), 0.008, 12)
	return g


## A name plate on a wall facing +v: dark letters on a cream plate.
static func plate(p: Node3D, n: Node3D, text: String, u: float, face: float, y: float, w := 0.9) -> void:
	Kit.box(n, Vector3(w, 0.2, 0.012), p.pt(u, face + 0.006, y), Color(0.93, 0.92, 0.86))
	Props.words(n, text, p.pt(u, face + 0.014, y), 0.11, Color(0.18, 0.22, 0.3))
