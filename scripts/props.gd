extends RefCounted
## Furniture and fittings for the places built from floor plans (place.gd).
##
##   const Props := preload("res://scripts/props.gd")
##   Props.desk(p, band, u, v, yaw)
##
## `p` is the Place, `band` the band the thing stands in (it is hidden with that
## band), (u, v) the middle of its floor space on the plan, and `yaw` which way
## its front faces: 0 the street, 90 right, 180 the back, 270 left. Each takes
## up floor nobody can walk on, unless it says otherwise. Things on a wall
## (boards, posters, phones) are put ON the wall's face: give the point on the
## wall, and the yaw the wall faces.

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")

const STEEL := Color(0.62, 0.64, 0.67)
const IRON := Color(0.3, 0.32, 0.36)
const DARK := Color(0.13, 0.13, 0.15)
const WOOD := Color(0.52, 0.36, 0.22)
const WOOD_DARK := Color(0.3, 0.2, 0.13)
const PAPER := Color(0.93, 0.91, 0.84)
const CREAM := Color(0.88, 0.84, 0.72)
const OFFICE := Color(0.5, 0.53, 0.5)      # government-issue grey-green
const VINYL := Color(0.45, 0.2, 0.16)
const GLASS := Color(0.62, 0.8, 0.88, 0.25)


## A step of `dist` metres on the plan in the direction `yaw` faces.
static func ahead(yaw: float, dist: float) -> Vector2:
	return Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw))) * dist


## A steady "random" number 0..1 from any number, so a place looks the same every run.
static func rnd(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


static func words(parent: Node3D, text: String, pos: Vector3, height: float, colour: Color, yaw := 0.0, bold := true) -> Label3D:
	var l := Kit.label(parent, text, pos, height, colour, Vector3(0, yaw, 0))
	if bold:
		l.font = FONT
	return l


# -------------------------------------------------------------------- office

## stuff: 0 bare, 1 typewriter and phone, 2 lamp and papers, 3 an old computer.
static func desk(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := OFFICE, stuff := 1, with_chair := true, w := 1.5, d := 0.75) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.box(g, Vector3(w, 0.05, d), Vector3(0, 0.74, 0), look.lightened(0.18))
	Kit.block(g, Vector3(0.42, 0.7, d - 0.08), Vector3(w * 0.5 - 0.24, 0, 0), look)
	Kit.block(g, Vector3(0.04, 0.7, d - 0.08), Vector3(-w * 0.5 + 0.05, 0, 0), look)
	Kit.box(g, Vector3(w - 0.12, 0.45, 0.03), Vector3(0, 0.47, -d * 0.5 + 0.06), look.darkened(0.1))
	for y in [0.2, 0.5]:
		Kit.box(g, Vector3(0.3, 0.03, 0.02), Vector3(w * 0.5 - 0.24, y, d * 0.5 - 0.035), look.darkened(0.35))
	var top := 0.766
	if stuff == 1:
		Kit.block(g, Vector3(0.36, 0.1, 0.3), Vector3(-0.22, top, -0.05), Color(0.25, 0.3, 0.28))
		Kit.box(g, Vector3(0.24, 0.16, 0.01), Vector3(-0.22, top + 0.17, -0.14), PAPER, Vector3(-12, 0, 0))
		Kit.block(g, Vector3(0.2, 0.06, 0.16), Vector3(0.42, top, -0.12), DARK)
		Kit.box(g, Vector3(0.22, 0.04, 0.06), Vector3(0.42, top + 0.08, -0.12), DARK)
		Kit.box(g, Vector3(0.24, 0.012, 0.32), Vector3(0.2, top + 0.006, 0.12), PAPER, Vector3(0, 14, 0))
	elif stuff == 2:
		Kit.cyl(g, 0.07, 0.02, Vector3(-0.5, top + 0.01, -0.18), Color(0.7, 0.55, 0.2), Vector3.ZERO, 8)
		Kit.cyl(g, 0.012, 0.3, Vector3(-0.5, top + 0.16, -0.18), Color(0.7, 0.55, 0.2), Vector3.ZERO, 5)
		Kit.box(g, Vector3(0.3, 0.07, 0.12), Vector3(-0.5, top + 0.33, -0.14), Kit.flat(Color(0.2, 0.55, 0.3), 0.5))
		Kit.box(g, Vector3(0.3, 0.02, 0.4), Vector3(0.0, top + 0.01, 0.05), PAPER, Vector3(0, -8, 0))
		Kit.box(g, Vector3(0.26, 0.03, 0.34), Vector3(0.4, top + 0.015, -0.05), Color(0.75, 0.68, 0.45), Vector3(0, 10, 0))
	elif stuff == 3:
		Kit.block(g, Vector3(0.4, 0.34, 0.38), Vector3(-0.25, top, -0.12), CREAM)
		Kit.box(g, Vector3(0.3, 0.24, 0.01), Vector3(-0.25, top + 0.18, 0.075), Kit.flat(Color(0.2, 0.5, 0.3), 0.5))
		Kit.block(g, Vector3(0.42, 0.03, 0.16), Vector3(-0.25, top, 0.2), CREAM.darkened(0.1))
		Kit.box(g, Vector3(0.24, 0.012, 0.32), Vector3(0.3, top + 0.006, 0.05), PAPER, Vector3(0, -10, 0))
	if with_chair:
		var at := Vector2(u, v) + ahead(yaw, d * 0.5 + 0.32)
		chair(p, b, at.x, at.y, yaw + 180.0)
	return g


static func chair(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.2, 0.24, 0.3), solid := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.44, 0.44, solid)
	Kit.box(g, Vector3(0.42, 0.06, 0.42), Vector3(0, 0.45, 0), look)
	Kit.box(g, Vector3(0.42, 0.42, 0.05), Vector3(0, 0.74, -0.2), look)
	Kit.cyl(g, 0.03, 0.42, Vector3(0, 0.21, 0), STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.44, 0.03, 0.06), Vector3(0, 0.02, 0), STEEL)
	Kit.box(g, Vector3(0.06, 0.028, 0.44), Vector3(0, 0.02, 0), STEEL)
	return g


static func bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, look := WOOD, back := false, d := 0.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.box(g, Vector3(w, 0.06, d), Vector3(0, 0.44, 0), look)
	for x in [-w * 0.5 + 0.15, w * 0.5 - 0.15]:
		Kit.block(g, Vector3(0.06, 0.41, d - 0.08), Vector3(x, 0, 0), look.darkened(0.25))
	if back:
		Kit.box(g, Vector3(w, 0.42, 0.05), Vector3(0, 0.74, -d * 0.5 + 0.03), look)
	return g


## A church-style bench with a back and closed ends.
static func pew(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 4.0, look := WOOD_DARK) -> Node3D:
	var g := bench(p, b, u, v, yaw, w, look, true, 0.55)
	for x in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:      # the ends stand a little proud all round, or their faces flicker against the seat
		Kit.block(g, Vector3(0.06, 0.99, 0.59), Vector3(x, 0, 0), look.darkened(0.15))
	return g


## n filing cabinets side by side.
static func files(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 2, look := OFFICE, h := 1.32) -> Node3D:
	var w := 0.46 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	for i in n:
		var x := -w * 0.5 + 0.23 + i * 0.46
		Kit.block(g, Vector3(0.45, h, 0.6), Vector3(x, 0, 0), look.darkened(0.07 * (i % 2)))
		for k in 4:
			Kit.box(g, Vector3(0.39, h / 4.0 - 0.05, 0.02), Vector3(x, h / 8.0 + k * h / 4.0, 0.305), look.lightened(0.1))
			Kit.box(g, Vector3(0.12, 0.025, 0.02), Vector3(x, h / 8.0 + k * h / 4.0 + 0.06, 0.322), STEEL)
	return g


## Open shelving. stuff: "boxes", "books" or "none".
static func shelves(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, stuff := "boxes", look := IRON, h := 1.9, d := 0.45) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	for x in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.block(g, Vector3(0.04, h, d), Vector3(x, 0, 0), look)
	var rows := 5
	for i in rows:
		var y := 0.1 + i * (h - 0.14) / float(rows - 1)
		Kit.box(g, Vector3(w - 0.08, 0.03, d - 0.02), Vector3(0, y, 0), look.lightened(0.1))
		if stuff == "none" or i == rows - 1:
			continue
		var x := -w * 0.5 + 0.1
		var n := 0
		while x < w * 0.5 - 0.32:
			var key := u * 7.3 + v * 3.1 + i * 11.7 + n * 1.93
			n += 1
			var bw := 0.2 + 0.26 * rnd(key)
			var bh := 0.14 + 0.18 * rnd(key + 5.0)
			var tint: Color
			if stuff == "books":
				tint = [Color(0.45, 0.16, 0.14), Color(0.5, 0.4, 0.25), Color(0.16, 0.3, 0.22), Color(0.2, 0.22, 0.36)][int(rnd(key + 2.0) * 4.0) % 4]
				bh = 0.24 + 0.05 * rnd(key + 5.0)
			else:
				tint = [Color(0.62, 0.48, 0.3), Color(0.7, 0.58, 0.38), Color(0.5, 0.4, 0.28), Color(0.78, 0.76, 0.7)][int(rnd(key + 2.0) * 4.0) % 4]
			Kit.block(g, Vector3(bw, bh, d - 0.14), Vector3(x + bw * 0.5, y + 0.015, 0), tint)
			if stuff == "books":
				Kit.box(g, Vector3(bw, 0.02, 0.01), Vector3(x + bw * 0.5, y + bh * 0.7, d * 0.5 - 0.066), Color(0.8, 0.65, 0.25))
			else:
				Kit.box(g, Vector3(bw * 0.5, 0.06, 0.01), Vector3(x + bw * 0.5, y + bh * 0.5, d * 0.5 - 0.066), PAPER)
			x += bw + 0.04 + 0.12 * rnd(key + 9.0)
	return g


static func counter(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, d := 0.6, h := 1.05, look := WOOD, top := Color(0.82, 0.8, 0.74)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.block(g, Vector3(w, h - 0.05, d), Vector3.ZERO, look)
	Kit.box(g, Vector3(w + 0.06, 0.05, d + 0.06), Vector3(0, h - 0.025, 0), top)
	return g


static func table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, d := 0.8, look := WOOD, h := 0.74) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.box(g, Vector3(w, 0.05, d), Vector3(0, h - 0.025, 0), look)
	for x in [-w * 0.5 + 0.07, w * 0.5 - 0.07]:
		for z in [-d * 0.5 + 0.07, d * 0.5 - 0.07]:
			Kit.block(g, Vector3(0.06, h - 0.05, 0.06), Vector3(x, 0, z), look.darkened(0.2))
	return g


static func lockers(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 4, look := Color(0.4, 0.46, 0.5)) -> Node3D:
	var w := 0.38 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.5)
	for i in n:
		var x := -w * 0.5 + 0.19 + i * 0.38
		Kit.block(g, Vector3(0.375, 1.85, 0.5), Vector3(x, 0, 0), look.darkened(0.06 * (i % 2)))
		Kit.box(g, Vector3(0.33, 1.7, 0.015), Vector3(x, 0.93, 0.255), look.lightened(0.08))
		for k in 3:
			Kit.box(g, Vector3(0.18, 0.015, 0.01), Vector3(x, 1.55 + k * 0.05, 0.266), DARK)
		Kit.box(g, Vector3(0.03, 0.1, 0.02), Vector3(x + 0.12, 1.0, 0.27), STEEL)
	return g


static func cooler(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	Kit.block(g, Vector3(0.32, 0.95, 0.32), Vector3.ZERO, CREAM)
	Kit.cyl(g, 0.13, 0.4, Vector3(0, 1.16, 0), Color(0.5, 0.75, 0.9, 0.6), Vector3.ZERO, 10)
	return g


## A table with a coffee urn, cups and a box of doughnuts.
static func coffee(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g := table(p, b, u, v, yaw, 1.2, 0.6, Color(0.6, 0.58, 0.52))
	Kit.cyl(g, 0.12, 0.4, Vector3(-0.32, 0.94, 0), STEEL, Vector3.ZERO, 10)
	Kit.cyl(g, 0.14, 0.04, Vector3(-0.32, 0.76, 0), DARK, Vector3.ZERO, 10)
	for i in 3:
		Kit.cyl(g, 0.04, 0.09, Vector3(0.0 + i * 0.11, 0.785, 0.12), PAPER, Vector3.ZERO, 8)
	Kit.block(g, Vector3(0.36, 0.06, 0.26), Vector3(0.36, 0.74, -0.08), Color(0.95, 0.6, 0.7))
	return g


static func flag(p: Node3D, b: int, u: float, v: float, cloth := Color(0.16, 0.2, 0.45), yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.3, 0.3)
	var brass := Color(0.75, 0.6, 0.25)
	Kit.cyl(g, 0.14, 0.04, Vector3(0, 0.02, 0), brass, Vector3.ZERO, 10)
	Kit.cyl(g, 0.018, 2.3, Vector3(0, 1.15, 0), brass, Vector3.ZERO, 6)
	Kit.ball(g, 0.04, Vector3(0, 2.32, 0), brass, 6)
	Kit.box(g, Vector3(0.5, 0.95, 0.04), Vector3(0.24, 1.7, 0), cloth, Vector3(0, 0, -6))
	return g


static func boxes(p: Node3D, b: int, u: float, v: float, n := 4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 1.0, 0.6)
	for i in n:
		var col: Color = [Color(0.62, 0.48, 0.3), Color(0.7, 0.58, 0.38), Color(0.55, 0.42, 0.28)][i % 3]
		var x := -0.28 + 0.52 * (i % 2)
		Kit.block(g, Vector3(0.44, 0.3, 0.5), Vector3(x + 0.03 * (i / 2), 0.31 * (i / 2), 0), col, Vector3(0, 4.0 * i - 6.0, 0))
	return g


static func bucket(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	Kit.cyl(g, 0.15, 0.3, Vector3(0, 0.15, 0), Color(0.85, 0.7, 0.15), Vector3.ZERO, 10, 0.19)
	Kit.cyl(g, 0.17, 0.01, Vector3(0, 0.27, 0), Color(0.35, 0.45, 0.5), Vector3.ZERO, 10)
	Kit.cyl(g, 0.42, 0.006, Vector3(0.15, 0.004, 0.1), Color(0.2, 0.22, 0.24, 0.5), Vector3.ZERO, 12)
	return g


## A dying pot plant.
static func plant(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.4, 0.4)
	Kit.cyl(g, 0.15, 0.34, Vector3(0, 0.17, 0), Color(0.6, 0.35, 0.25), Vector3.ZERO, 8, 0.19)
	for i in 5:
		Kit.box(g, Vector3(0.03, 0.6 + 0.12 * rnd(i * 3.3), 0.03), Vector3(0.05 * (i - 2), 0.62, 0.03 * (i % 2)), Color(0.42, 0.4, 0.2), Vector3(12.0 * (i - 2), 0, 9.0 * (i - 2)))
	for i in 4:
		Kit.box(g, Vector3(0.16, 0.02, 0.07), Vector3(0.11 * (i - 1.5), 0.78 + 0.07 * (i % 2), 0.02), Color(0.5, 0.5, 0.22), Vector3(0, 30.0 * i, 24))
	return g


# ------------------------------------------------------------------ on walls

## A pin board, on a wall. kind: "notices" or "wanted".
static func board(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6, kind := "notices", h := 1.0, y := 1.55) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.1, false)
	Kit.box(g, Vector3(w + 0.08, h + 0.08, 0.02), Vector3(0, y, 0.012), WOOD_DARK)
	Kit.box(g, Vector3(w, h, 0.02), Vector3(0, y, 0.022), Color(0.62, 0.47, 0.3))
	var cols := maxi(int(w / 0.3), 1)
	for i in cols:
		for k in 2:
			var key := u * 5.1 + v * 2.3 + i * 3.7 + k * 9.1
			if rnd(key) < 0.18:
				continue
			var pw := 0.17 + 0.06 * rnd(key + 1.0)
			var ph := 0.22 + 0.08 * rnd(key + 2.0)
			var at := Vector3(-w * 0.5 + (i + 0.5) * w / cols + 0.03 * (rnd(key + 3.0) - 0.5), y + (k - 0.5) * h * 0.46, 0.034)
			var tilt := Vector3(0, 0, 10.0 * (rnd(key + 4.0) - 0.5))
			Kit.box(g, Vector3(pw, ph, 0.004), at, PAPER if rnd(key + 6.0) > 0.3 else Color(0.95, 0.88, 0.55), tilt)
			if kind == "wanted":
				Kit.box(g, Vector3(pw * 0.6, ph * 0.42, 0.004), at + Vector3(0, ph * 0.12, 0.004), Color(0.25, 0.24, 0.26), tilt)
	return g


## A poster or framed picture on a wall.
static func poster(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.6, h := 0.85, look := Color(0.8, 0.3, 0.25), text := "", y := 1.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.05, false)
	Kit.box(g, Vector3(w, h, 0.012), Vector3(0, y, 0.012), look)
	Kit.box(g, Vector3(w * 0.8, h * 0.5, 0.004), Vector3(0, y + h * 0.12, 0.02), look.lightened(0.35))
	if text != "":
		words(g, text, Vector3(0, y - h * 0.3, 0.024), minf(0.09, w / maxf(text.length(), 1.0) * 1.1), PAPER)
	return g


static func payphone(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.3, false)
	Kit.box(g, Vector3(0.46, 0.7, 0.22), Vector3(0, 1.35, 0.12), Color(0.2, 0.35, 0.6))
	Kit.box(g, Vector3(0.28, 0.36, 0.05), Vector3(0, 1.32, 0.25), DARK)
	Kit.box(g, Vector3(0.07, 0.26, 0.07), Vector3(-0.1, 1.36, 0.3), Color(0.08, 0.08, 0.09))
	Kit.box(g, Vector3(0.5, 0.05, 0.28), Vector3(0, 1.72, 0.14), STEEL)
	return g


static func clock(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 2.35) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.4, 0.05, false)
	Kit.disc(g, 0.2, Vector3(0, y, 0.015), DARK, 0.02, 14)
	Kit.disc(g, 0.17, Vector3(0, y, 0.022), PAPER, 0.02, 14)
	Kit.box(g, Vector3(0.015, 0.13, 0.004), Vector3(0, y + 0.06, 0.036), DARK)
	Kit.box(g, Vector3(0.1, 0.015, 0.004), Vector3(0.045, y, 0.036), DARK)
	return g


## A drinking fountain, on a wall.
static func fountain(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.45, 0.36)
	Kit.box(g, Vector3(0.42, 0.34, 0.34), Vector3(0, 0.88, 0.0), STEEL)
	Kit.box(g, Vector3(0.34, 0.02, 0.26), Vector3(0, 1.055, 0.0), IRON)
	Kit.cyl(g, 0.012, 0.08, Vector3(0.12, 1.1, -0.08), STEEL, Vector3.ZERO, 5)
	return g


## The mugshot wall: a height chart.
static func height_chart(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 0.05, false)
	Kit.box(g, Vector3(1.5, 2.05, 0.012), Vector3(0, 1.1, 0.012), PAPER)
	for i in 9:
		Kit.box(g, Vector3(1.5, 0.014 if i % 2 == 0 else 0.007, 0.004), Vector3(0, 0.6 + i * 0.1524, 0.02), DARK)
	for row: Array in [["5'0\"", 1.524], ["6'0\"", 1.829]]:
		words(g, row[0], Vector3(-0.58, float(row[1]) + 0.06, 0.022), 0.08, DARK, 0.0, false)
	return g


# -------------------------------------------------------------- police, cells

static func vending(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.95, 0.8)
	Kit.block(g, Vector3(0.95, 1.85, 0.8), Vector3.ZERO, Color(0.55, 0.2, 0.18))
	Kit.box(g, Vector3(0.6, 1.2, 0.02), Vector3(-0.12, 1.12, 0.405), Color(0.16, 0.12, 0.12))
	Kit.box(g, Vector3(0.16, 0.9, 0.02), Vector3(0.33, 1.2, 0.405), Color(0.7, 0.68, 0.62))
	Kit.box(g, Vector3(0.5, 0.14, 0.02), Vector3(-0.12, 0.3, 0.405), DARK)
	Kit.box(g, Vector3(0.44, 0.26, 0.008), Vector3(-0.12, 1.2, 0.42), PAPER, Vector3(0, 0, 5))
	words(g, "OUT OF ORDER", Vector3(-0.12, 1.2, 0.428), 0.042, Color(0.7, 0.1, 0.1), 0.0).rotation_degrees.z = 5.0
	return g


static func bunk(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.9, 0.8)
	Kit.box(g, Vector3(1.9, 0.06, 0.8), Vector3(0, 0.42, 0), IRON)
	for x in [-0.85, 0.85]:
		Kit.block(g, Vector3(0.06, 0.39, 0.7), Vector3(x, 0, 0), IRON)
	Kit.box(g, Vector3(1.8, 0.09, 0.7), Vector3(0, 0.495, 0), Color(0.6, 0.62, 0.55))
	Kit.box(g, Vector3(0.4, 0.08, 0.5), Vector3(-0.66, 0.58, 0), Color(0.8, 0.8, 0.74))
	Kit.box(g, Vector3(0.8, 0.03, 0.72), Vector3(0.4, 0.555, 0), Color(0.4, 0.42, 0.36))
	return g


## The steel toilet-and-sink of a cell.
static func cell_toilet(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.56)
	Kit.block(g, Vector3(0.4, 0.42, 0.5), Vector3.ZERO, STEEL)
	Kit.cyl(g, 0.15, 0.02, Vector3(0, 0.43, 0.05), IRON, Vector3.ZERO, 10)
	Kit.box(g, Vector3(0.4, 0.14, 0.24), Vector3(0, 0.95, -0.13), STEEL)
	return g


## The radio desk: a console with a sloping panel of lights and a microphone.
static func radio(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.6, 0.7)
	Kit.block(g, Vector3(1.6, 0.74, 0.7), Vector3.ZERO, Color(0.3, 0.32, 0.34))
	var panel := Kit.group(g, Vector3(0, 0.92, -0.14), Vector3(-28, 0, 0))
	Kit.box(panel, Vector3(1.5, 0.4, 0.2), Vector3.ZERO, Color(0.2, 0.21, 0.23))
	for i in 10:
		var col: Color = [Color(0.3, 0.95, 0.4), Color(1.0, 0.75, 0.2), Color(1.0, 0.25, 0.2)][int(rnd(i * 2.7) * 3.0) % 3]
		Kit.box(panel, Vector3(0.05, 0.05, 0.01), Vector3(-0.63 + i * 0.14, 0.1, 0.105), Kit.flat(col, 1.2))
		Kit.box(panel, Vector3(0.07, 0.04, 0.02), Vector3(-0.63 + i * 0.14, -0.06, 0.105), STEEL)
	Kit.cyl(g, 0.012, 0.3, Vector3(0.5, 0.9, 0.2), IRON, Vector3(0, 0, -25), 5)
	Kit.ball(g, 0.035, Vector3(0.57, 1.04, 0.2), DARK, 6)
	return g


## The mugshot camera on its tripod.
static func tripod(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.5)
	for a in [0.0, 120.0, 240.0]:
		var leg := Kit.group(g, Vector3(0, 1.25, 0), Vector3(0, a, 0))
		Kit.cyl(leg, 0.013, 1.32, Vector3(0, -0.63, 0.14), IRON, Vector3(12.5, 0, 0), 5)
	Kit.box(g, Vector3(0.22, 0.18, 0.3), Vector3(0, 1.36, 0), DARK)
	Kit.cyl(g, 0.06, 0.12, Vector3(0, 1.36, 0.2), Color(0.25, 0.25, 0.28), Vector3(90, 0, 0), 8)
	Kit.box(g, Vector3(0.12, 0.1, 0.08), Vector3(0, 1.52, 0.06), STEEL)
	return g


## kind: "cruiser" or "van". The length runs front to back; the front is the front.
static func car(p: Node3D, b: int, u: float, v: float, yaw := 0.0, kind := "cruiser", solid := true) -> Node3D:
	var van := kind == "van"
	var w := 1.95 if van else 1.82
	var l := 4.3 if van else 4.5
	var g: Node3D = p.prop(b, u, v, yaw, w, l, solid)
	var paint := Color(0.2, 0.26, 0.42) if van else Color(0.9, 0.9, 0.86)
	var glass := Color(0.14, 0.19, 0.25)
	if van:
		Kit.block(g, Vector3(w, 1.55, l), Vector3(0, 0.32, 0), paint)
		Kit.box(g, Vector3(w - 0.2, 0.55, 0.02), Vector3(0, 1.45, l * 0.5 + 0.005), glass)
		Kit.box(g, Vector3(w + 0.02, 0.2, l + 0.02), Vector3(0, 0.75, 0), Color(0.9, 0.9, 0.86))
		for side in [-1.0, 1.0]:
			words(g, "POLICE", Vector3(side * (w * 0.5 + 0.012), 1.3, -0.3), 0.3, Color(0.92, 0.9, 0.8), 90.0 * side)
			Kit.box(g, Vector3(0.02, 0.4, 0.7), Vector3(side * (w * 0.5 + 0.005), 1.42, 1.5), glass)
	else:
		Kit.block(g, Vector3(w, 0.58, l), Vector3(0, 0.3, 0), paint)
		Kit.block(g, Vector3(w - 0.22, 0.46, 2.1), Vector3(0, 0.88, -0.15), glass)
		Kit.box(g, Vector3(w - 0.2, 0.06, 2.0), Vector3(0, 1.37, -0.15), paint)
		Kit.box(g, Vector3(w + 0.02, 0.16, l + 0.02), Vector3(0, 0.62, 0), Color(0.16, 0.25, 0.5))
		Kit.box(g, Vector3(0.5, 0.12, 0.26), Vector3(-0.3, 1.46, -0.15), Kit.flat(Color(0.9, 0.15, 0.12), 0.6))
		Kit.box(g, Vector3(0.5, 0.12, 0.26), Vector3(0.3, 1.46, -0.15), Kit.flat(Color(0.15, 0.3, 0.95), 0.6))
		for side in [-1.0, 1.0]:
			words(g, "POLICE", Vector3(side * (w * 0.5 + 0.022), 0.62, 0.2), 0.12, Color(0.95, 0.93, 0.85), 90.0 * side)
	for x in [-w * 0.5 + 0.06, w * 0.5 - 0.06]:
		for z in [-l * 0.5 + 0.85, l * 0.5 - 0.85]:
			Kit.cyl(g, 0.33, 0.24, Vector3(x, 0.33, z), Color(0.08, 0.08, 0.09), Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.17, 0.25, Vector3(x, 0.33, z), STEEL, Vector3(0, 0, 90), 8)
	for x in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		Kit.box(g, Vector3(0.3, 0.14, 0.02), Vector3(x, 0.7, l * 0.5 + 0.012), Kit.flat(Color(1.0, 0.95, 0.75), 0.8))
		Kit.box(g, Vector3(0.3, 0.12, 0.02), Vector3(x, 0.7, -l * 0.5 - 0.012), Kit.flat(Color(0.8, 0.12, 0.1), 0.5))
	Kit.box(g, Vector3(w + 0.06, 0.14, 0.1), Vector3(0, 0.4, l * 0.5 + 0.03), IRON)
	Kit.box(g, Vector3(w + 0.06, 0.14, 0.1), Vector3(0, 0.4, -l * 0.5 - 0.03), IRON)
	return g


# ------------------------------------------------------------------ courtroom

## The judge's bench: a raised platform, a tall front, and the chair behind it.
static func judge_bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 4.8, d := 1.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.block(g, Vector3(w, 0.3, d), Vector3.ZERO, WOOD_DARK)
	Kit.box(g, Vector3(w, 1.1, 0.12), Vector3(0, 0.85, d * 0.5 - 0.06), WOOD)
	Kit.box(g, Vector3(w + 0.06, 0.05, 0.55), Vector3(0, 1.42, d * 0.5 - 0.27), WOOD_DARK)
	Kit.box(g, Vector3(1.6, 0.18, 0.14), Vector3(0, 1.5, d * 0.5 - 0.06), WOOD)
	Kit.disc(g, 0.26, Vector3(0, 0.9, d * 0.5 + 0.008), Color(0.78, 0.63, 0.25), 0.02, 14)
	Kit.disc(g, 0.19, Vector3(0, 0.9, d * 0.5 + 0.014), Color(0.2, 0.25, 0.45), 0.02, 14)
	Kit.box(g, Vector3(0.62, 1.25, 0.1), Vector3(0, 1.15, -d * 0.5 + 0.28), Color(0.2, 0.1, 0.08))
	Kit.box(g, Vector3(0.6, 0.1, 0.55), Vector3(0, 0.8, -d * 0.5 + 0.55), Color(0.2, 0.1, 0.08))
	Kit.block(g, Vector3(0.1, 0.05, 0.22), Vector3(0.5, 1.445, d * 0.5 - 0.3), WOOD_DARK)
	Kit.box(g, Vector3(0.36, 0.08, 0.04), Vector3(0, 1.49, d * 0.5 - 0.02), Color(0.78, 0.63, 0.25))
	return g


static func witness_stand(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 1.0)
	Kit.block(g, Vector3(1.2, 0.15, 1.0), Vector3.ZERO, WOOD_DARK)
	Kit.box(g, Vector3(1.2, 0.9, 0.08), Vector3(0, 0.6, 0.46), WOOD)
	for x in [-0.56, 0.56]:
		Kit.box(g, Vector3(0.08, 0.9, 0.84), Vector3(x, 0.6, 0.0), WOOD)
	Kit.box(g, Vector3(0.44, 0.06, 0.44), Vector3(0, 0.6, -0.15), VINYL)
	Kit.box(g, Vector3(0.44, 0.5, 0.05), Vector3(0, 0.9, -0.38), VINYL)
	Kit.cyl(g, 0.01, 0.25, Vector3(0.25, 1.15, 0.4), IRON, Vector3(20, 0, 0), 5)
	return g


## Two rows of three seats behind a rail; the back row sits higher.
static func jury_box(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.6, d := 1.55) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.block(g, Vector3(w, 0.15, d), Vector3.ZERO, WOOD_DARK)
	Kit.block(g, Vector3(w - 0.02, 0.32, d * 0.5 - 0.02), Vector3(0, 0, -d * 0.25), WOOD_DARK.lightened(0.05))
	Kit.box(g, Vector3(w, 0.85, 0.08), Vector3(0, 0.575, d * 0.5 - 0.04), WOOD)
	for x in [-w * 0.5 + 0.04, w * 0.5 - 0.04]:
		Kit.box(g, Vector3(0.08, 0.85, d - 0.1), Vector3(x, 0.575, -0.03), WOOD)
	for row in 2:
		for i in 3:
			var base := Vector3(-w * 0.5 + 0.5 + i * (w - 1.0) * 0.5, 0.15 + 0.17 * row, 0.3 - 0.72 * row)
			Kit.box(g, Vector3(0.48, 0.08, 0.44), base + Vector3(0, 0.4, 0), VINYL)
			Kit.box(g, Vector3(0.48, 0.5, 0.06), base + Vector3(0, 0.68, -0.2), VINYL)
	return g


static func lectern(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.55, 0.45)
	Kit.block(g, Vector3(0.5, 1.05, 0.4), Vector3.ZERO, WOOD)
	Kit.box(g, Vector3(0.56, 0.04, 0.46), Vector3(0, 1.1, 0.0), WOOD_DARK, Vector3(14, 0, 0))
	return g


## A walk-through metal detector: two posts and a beam. He walks between them.
static func detector(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 1.3, 0.55, false)
	var grey := Color(0.72, 0.72, 0.7)
	for side in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.14, 2.05, 0.55), Vector3(side * 0.57, 0, 0), grey)
		Kit.box(g, Vector3(0.04, 0.3, 0.02), Vector3(side * 0.57, 1.5, 0.285), Kit.flat(Color(0.3, 0.95, 0.4), 1.0))
		p.block(u + side * 0.57 - 0.07, v - 0.275, u + side * 0.57 + 0.07, v + 0.275)
	Kit.box(g, Vector3(1.28, 0.16, 0.55), Vector3(0, 2.13, 0), grey)
	return g


## The X-ray machine: a belt running through a hooded tunnel.
static func xray(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.85, 2.1)
	Kit.block(g, Vector3(0.85, 0.75, 2.1), Vector3.ZERO, Color(0.6, 0.62, 0.62))
	Kit.box(g, Vector3(0.62, 0.02, 2.12), Vector3(0, 0.76, 0), DARK)
	Kit.box(g, Vector3(0.85, 0.62, 0.9), Vector3(0, 1.08, 0), Color(0.78, 0.76, 0.7))
	Kit.box(g, Vector3(0.56, 0.36, 0.92), Vector3(0, 0.955, 0), Color(0.1, 0.1, 0.12))
	Kit.box(g, Vector3(0.3, 0.24, 0.26), Vector3(0.2, 1.52, 0), CREAM)
	Kit.box(g, Vector3(0.22, 0.16, 0.01), Vector3(0.2, 1.53, 0.135), Kit.flat(Color(0.3, 0.75, 0.9), 0.7))
	return g


## A coat stand with a judge's robe on it.
static func robe(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.45, 0.45)
	Kit.cyl(g, 0.16, 0.04, Vector3(0, 0.02, 0), WOOD_DARK, Vector3.ZERO, 8)
	Kit.cyl(g, 0.02, 1.8, Vector3(0, 0.9, 0), WOOD_DARK, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.44, 0.04, 0.04), Vector3(0, 1.72, 0), WOOD_DARK)
	Kit.box(g, Vector3(0.42, 1.15, 0.12), Vector3(0, 1.1, 0.06), Color(0.08, 0.08, 0.1))
	return g


# ----------------------------------------------------------------------- home

static func couch(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.1, look := Color(0.45, 0.32, 0.2), d := 0.85) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.block(g, Vector3(w - 0.02, 0.38, d - 0.02), Vector3.ZERO, look.darkened(0.12))     # a little smaller than the arms, or the faces flicker
	Kit.box(g, Vector3(w, 0.5, 0.22), Vector3(0, 0.62, -d * 0.5 + 0.11), look)
	for x in [-w * 0.5 + 0.09, w * 0.5 - 0.09]:
		Kit.block(g, Vector3(0.18, 0.58, d), Vector3(x, 0, 0), look)
	var n := maxi(int(round((w - 0.36) / 0.7)), 1)
	var cw := (w - 0.36) / n
	for i in n:
		Kit.box(g, Vector3(cw - 0.03, 0.12, d - 0.3), Vector3(-w * 0.5 + 0.18 + (i + 0.5) * cw, 0.44, 0.09), look.lightened(0.1))
	return g


## An old television on a stand.
static func tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.9, 0.5)
	Kit.block(g, Vector3(0.9, 0.5, 0.45), Vector3.ZERO, WOOD_DARK)
	Kit.box(g, Vector3(0.72, 0.56, 0.46), Vector3(0, 0.79, 0), Color(0.36, 0.26, 0.18))
	Kit.box(g, Vector3(0.48, 0.4, 0.02), Vector3(-0.08, 0.8, 0.235), Kit.flat(Color(0.5, 0.68, 0.8), 0.9))
	for y in [0.72, 0.88]:
		Kit.cyl(g, 0.035, 0.03, Vector3(0.26, y, 0.24), STEEL, Vector3(90, 0, 0), 8)
	Kit.cyl(g, 0.006, 0.5, Vector3(-0.1, 1.3, 0), STEEL, Vector3(0, 0, 28), 4)
	Kit.cyl(g, 0.006, 0.5, Vector3(0.1, 1.3, 0), STEEL, Vector3(0, 0, -28), 4)
	return g


static func radiator(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.22)
	var n := maxi(int(w / 0.1), 2)
	for i in n:
		Kit.box(g, Vector3(0.07, 0.62, 0.18), Vector3(-w * 0.5 + (i + 0.5) * w / n, 0.4, 0), CREAM)
	Kit.box(g, Vector3(w, 0.04, 0.1), Vector3(0, 0.12, 0), CREAM.darkened(0.2))
	return g


static func stove(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.76, 0.66)
	var enamel := Color(0.9, 0.88, 0.82)
	Kit.block(g, Vector3(0.76, 0.9, 0.66), Vector3.ZERO, enamel)
	Kit.box(g, Vector3(0.76, 0.2, 0.05), Vector3(0, 1.0, -0.3), enamel)
	for x in [-0.19, 0.19]:
		for z in [-0.12, 0.17]:
			Kit.cyl(g, 0.09, 0.015, Vector3(x, 0.908, z), DARK, Vector3.ZERO, 10)
	Kit.box(g, Vector3(0.6, 0.42, 0.02), Vector3(0, 0.4, 0.335), Color(0.25, 0.24, 0.24))
	Kit.box(g, Vector3(0.5, 0.03, 0.04), Vector3(0, 0.68, 0.35), STEEL)
	return g


static func fridge(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.8, 0.72)
	var almond := Color(0.86, 0.83, 0.72)
	Kit.block(g, Vector3(0.8, 1.7, 0.7), Vector3.ZERO, almond)
	Kit.box(g, Vector3(0.8, 0.015, 0.01), Vector3(0, 1.22, 0.354), DARK)
	for y in [0.95, 1.45]:
		Kit.box(g, Vector3(0.03, 0.3, 0.04), Vector3(-0.32, y, 0.37), STEEL)
	Kit.box(g, Vector3(0.16, 0.2, 0.006), Vector3(0.15, 0.9, 0.355), PAPER, Vector3(0, 0, 6))
	return g


## A kitchen worktop with a sink in it.
static func sink_unit(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6) -> Node3D:
	var g := counter(p, b, u, v, yaw, w, 0.62, 0.9, Color(0.72, 0.66, 0.52), Color(0.8, 0.8, 0.78))
	Kit.box(g, Vector3(0.5, 0.02, 0.4), Vector3(0, 0.905, 0.02), IRON)
	Kit.cyl(g, 0.015, 0.22, Vector3(0, 1.0, -0.22), STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.03, 0.03, 0.16), Vector3(0, 1.1, -0.15), STEEL)
	return g


## The head is at the back of its floor space, the foot at the front.
static func bed(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, l := 2.0, cover := Color(0.25, 0.35, 0.6)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	Kit.block(g, Vector3(w, 0.3, l), Vector3.ZERO, WOOD_DARK)
	Kit.box(g, Vector3(w - 0.06, 0.2, l - 0.06), Vector3(0, 0.4, 0), Color(0.9, 0.89, 0.85))
	Kit.box(g, Vector3(w - 0.02, 0.22, l * 0.62), Vector3(0, 0.41, l * 0.5 - l * 0.31 - 0.01), cover)
	Kit.box(g, Vector3(w * 0.7, 0.1, 0.38), Vector3(0, 0.55, -l * 0.5 + 0.3), Color(0.93, 0.92, 0.88))
	Kit.box(g, Vector3(w, 0.95, 0.06), Vector3(0, 0.475, -l * 0.5 + 0.03), WOOD_DARK.lightened(0.08))
	return g


static func dresser(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2, look := WOOD, h := 0.9, d := 0.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.block(g, Vector3(w, h, d), Vector3.ZERO, look)
	for row in 3:
		for col in 2:
			var at := Vector3((col - 0.5) * w * 0.5, 0.1 + (row + 0.5) * (h - 0.14) / 3.0, d * 0.5 + 0.01)
			Kit.box(g, Vector3(w * 0.5 - 0.06, (h - 0.14) / 3.0 - 0.05, 0.02), at, look.lightened(0.1))
			Kit.ball(g, 0.022, at + Vector3(0, 0, 0.02), Color(0.8, 0.65, 0.3), 5)
	return g


## A dresser with a glass-fronted top for the good plates.
static func cabinet(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6) -> Node3D:
	var g := dresser(p, b, u, v, yaw, w, WOOD_DARK, 0.85, 0.45)
	Kit.box(g, Vector3(w, 1.05, 0.34), Vector3(0, 1.375, -0.05), WOOD_DARK)
	Kit.box(g, Vector3(w - 0.12, 0.9, 0.01), Vector3(0, 1.375, 0.126), Color(0.75, 0.85, 0.88, 0.45))
	for i in 3:
		Kit.disc(g, 0.11, Vector3(-w * 0.3 + i * w * 0.3, 1.25, 0.135), PAPER, 0.01, 10)
	return g


static func tub(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.72, 1.7)
	Kit.block(g, Vector3(0.72, 0.55, 1.7), Vector3.ZERO, Color(0.92, 0.92, 0.9))
	Kit.box(g, Vector3(0.56, 0.02, 1.5), Vector3(0, 0.555, 0), Color(0.6, 0.75, 0.8))
	Kit.cyl(g, 0.015, 0.2, Vector3(0, 0.66, -0.78), STEEL, Vector3.ZERO, 6)
	return g


static func toilet(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.45, 0.66)
	var china := Color(0.93, 0.93, 0.9)
	Kit.block(g, Vector3(0.42, 0.75, 0.2), Vector3(0, 0, -0.22), china)
	Kit.cyl(g, 0.19, 0.4, Vector3(0, 0.2, 0.08), china, Vector3.ZERO, 10, 0.21)
	Kit.cyl(g, 0.2, 0.03, Vector3(0, 0.415, 0.08), china.darkened(0.1), Vector3.ZERO, 10)
	return g


## A basin on a pedestal with a mirror over it.
static func basin(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.44)
	var china := Color(0.93, 0.93, 0.9)
	Kit.cyl(g, 0.08, 0.75, Vector3(0, 0.375, -0.02), china, Vector3.ZERO, 8)
	Kit.box(g, Vector3(0.55, 0.14, 0.42), Vector3(0, 0.82, 0), china)
	Kit.box(g, Vector3(0.38, 0.02, 0.26), Vector3(0, 0.895, 0.03), Color(0.7, 0.8, 0.84))
	Kit.box(g, Vector3(0.46, 0.6, 0.02), Vector3(0, 1.5, -0.205), Color(0.7, 0.82, 0.88))
	return g


## A flight of stairs climbing towards the back of its floor space.
static func stairs(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, l := 3.4, rise := 2.9, look := WOOD) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var n := 12
	for i in n:
		var h := rise * float(i + 1) / float(n)
		Kit.block(g, Vector3(w, h, l / n), Vector3(0, 0, l * 0.5 - (i + 0.5) * l / n), look.darkened(0.04 * (i % 2)))
	return g


## The top of a flight of stairs: a dark hole in the floor with a rail on three sides.
static func stairwell(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, l := 3.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	Kit.box(g, Vector3(w, 0.012, l), Vector3(0, 0.007, 0), Color(0.05, 0.04, 0.06))
	for i in 6:
		Kit.box(g, Vector3(w, 0.012, 0.05), Vector3(0, 0.016, l * 0.5 - 0.3 - i * 0.5), Color(0.25, 0.17, 0.11))
	var wood := WOOD_DARK
	Kit.box(g, Vector3(0.06, 0.06, l), Vector3(w * 0.5 - 0.03, 0.92, 0), wood)
	Kit.box(g, Vector3(w, 0.06, 0.06), Vector3(0, 0.92, -l * 0.5 + 0.03), wood)
	for i in 9:
		Kit.box(g, Vector3(0.04, 0.9, 0.04), Vector3(w * 0.5 - 0.03, 0.45, -l * 0.5 + 0.03 + i * (l - 0.06) / 8.0), wood)
	return g


## n dustbins in a row.
static func cans(p: Node3D, b: int, u: float, v: float, n := 2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.52 * n, 0.5)
	for i in n:
		var x := -0.26 * (n - 1) + i * 0.52
		Kit.cyl(g, 0.2, 0.72, Vector3(x, 0.36, 0), Color(0.45, 0.48, 0.5), Vector3.ZERO, 10, 0.23)
		Kit.cyl(g, 0.245, 0.05, Vector3(x, 0.745, 0), Color(0.36, 0.38, 0.4), Vector3(4.0 * i, 0, 3.0), 10)
	return g


## A boombox, to stand on something: give the group it stands in and where.
static func boombox(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.block(g, Vector3(0.62, 0.26, 0.16), Vector3.ZERO, Color(0.16, 0.16, 0.18))
	for x in [-0.2, 0.2]:
		Kit.disc(g, 0.09, Vector3(x, 0.12, 0.085), STEEL, 0.01, 12)
		Kit.disc(g, 0.06, Vector3(x, 0.12, 0.09), DARK, 0.01, 12)
	Kit.box(g, Vector3(0.14, 0.08, 0.01), Vector3(0, 0.15, 0.085), Color(0.55, 0.56, 0.6))
	Kit.box(g, Vector3(0.5, 0.02, 0.02), Vector3(0, 0.31, 0), STEEL)
	return g


## A flat rug. People walk on it.
static func rug(p: Node3D, b: int, u: float, v: float, w := 2.0, d := 1.4, look := Color(0.5, 0.2, 0.2)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, w, d, false)
	Kit.box(g, Vector3(w, 0.012, d), Vector3(0, 0.007, 0), look)
	Kit.box(g, Vector3(w - 0.3, 0.012, d - 0.3), Vector3(0, 0.01, 0), look.lightened(0.14))
	return g


# --------------------------------------------------------------------- street

static func street_lamp(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3, 0.3)
	var green := Color(0.2, 0.24, 0.24)
	Kit.cyl(g, 0.1, 0.5, Vector3(0, 0.25, 0), green, Vector3.ZERO, 8, 0.07)
	Kit.cyl(g, 0.05, 4.2, Vector3(0, 2.1, 0), green, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.9, 0.06, 0.06), Vector3(0.4, 4.15, 0), green)
	Kit.box(g, Vector3(0.4, 0.1, 0.22), Vector3(0.8, 4.08, 0), Kit.flat(Color(1.0, 0.86, 0.55), 2.2))
	Kit.omni(g, Vector3(0.8, 3.6, 0), Color(1.0, 0.82, 0.5), 1.6, 9.0)
	return g


static func bin(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.44, 0.44)
	Kit.cyl(g, 0.2, 0.75, Vector3(0, 0.375, 0), Color(0.3, 0.36, 0.34), Vector3.ZERO, 10, 0.23)
	Kit.cyl(g, 0.24, 0.05, Vector3(0, 0.77, 0), Color(0.2, 0.24, 0.23), Vector3.ZERO, 10)
	return g


static func hydrant(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3, 0.3)
	var red := Color(0.85, 0.2, 0.15)
	Kit.cyl(g, 0.11, 0.5, Vector3(0, 0.25, 0), red, Vector3.ZERO, 8)
	Kit.ball(g, 0.12, Vector3(0, 0.52, 0), red, 8)
	Kit.cyl(g, 0.05, 0.34, Vector3(0, 0.32, 0), red.darkened(0.12), Vector3(0, 0, 90), 6)
	return g


## A lamp on a bracket with a glowing globe (the blue lamps of a station house).
static func globe_lamp(parent: Node3D, pos: Vector3, glow := Color(0.25, 0.45, 1.0)) -> void:
	Kit.box(parent, Vector3(0.05, 0.05, 0.34), pos + Vector3(0, 0, 0.17), IRON)
	Kit.cyl(parent, 0.02, 0.2, pos + Vector3(0, 0.1, 0.32), IRON, Vector3.ZERO, 5)
	Kit.ball(parent, 0.17, pos + Vector3(0, 0.36, 0.32), Kit.flat(glow, 1.6), 10)
	Kit.omni(parent, pos + Vector3(0, 0.36, 0.6), glow, 0.7, 4.0)
