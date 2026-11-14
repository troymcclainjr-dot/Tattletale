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


## Open shelving. stuff: "boxes", "books", "none", or shop stock: "goods", "bottles", "cans".
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
		if stuff in ["goods", "bottles", "cans"]:      # shop stock (see stock, below)
			stock(g, stuff, -w * 0.5 + 0.07, w * 0.5 - 0.07, y + 0.015, d * 0.5 - 0.05, d - 0.14, u * 7.3 + v * 3.1 + i * 11.7, (h - 0.14) / float(rows - 1))
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


## A flag on an indoor stand. `stripes` makes it the national one: a blue
## corner over red and white; otherwise it is one colour with a gold fringe.
static func flag(p: Node3D, b: int, u: float, v: float, cloth := Color(0.16, 0.2, 0.45), yaw := 0.0, stripes := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.3, 0.3)
	flag_on(g, Vector3.ZERO, cloth, stripes)
	return g


## The flag itself, built into any group (a judge's bench has two). The pole
## leans a little on a weighted base and the cloth hangs off it in folds:
## strips side by side, each a little shorter and set a little forward or back
## of the last, light and dark by turns.
static func flag_on(parent: Node3D, at: Vector3, cloth := Color(0.16, 0.2, 0.45), stripes := false, lean := -5.0) -> Node3D:
	var f := Kit.group(parent, at)
	var brass := Color(0.75, 0.6, 0.25)
	Kit.cyl(f, 0.17, 0.05, Vector3(0, 0.025, 0), brass.darkened(0.25), Vector3.ZERO, 12)
	Kit.cyl(f, 0.07, 0.1, Vector3(0, 0.1, 0), brass, Vector3.ZERO, 8, 0.03)
	var pole := Kit.group(f, Vector3(0, 0.05, 0), Vector3(0, 0, lean))
	Kit.cyl(pole, 0.016, 2.25, Vector3(0, 1.125, 0), brass.darkened(0.12), Vector3.ZERO, 6)
	Kit.ball(pole, 0.036, Vector3(0, 2.27, 0), brass, 6)
	Kit.cyl(pole, 0.024, 0.13, Vector3(0, 2.36, 0), brass, Vector3.ZERO, 6, 0.0)
	var way := 1.0 if lean <= 0.0 else -1.0                   # the side the cloth hangs on
	var top := 2.17                                            # where the cloth is tied to the pole
	var x0 := way * (sin(deg_to_rad(absf(lean))) * top + 0.01)    # the pole is here at that height
	var red := Color(0.7, 0.13, 0.15)
	var white := Color(0.92, 0.9, 0.84)
	# Hanging at rest the cloth is widest near the top and comes to a point low
	# down by the pole: each strip starts a little lower and ends a lot higher
	# than the one before it.
	var drops := [0.0, 0.02, 0.05, 0.1, 0.17, 0.27]
	var longs := [1.32, 1.26, 1.14, 0.96, 0.72, 0.42]
	for k in drops.size():
		var long: float = longs[k]
		var y1: float = top - drops[k]
		var x := x0 + way * (0.04 + 0.085 * k)
		var z := 0.016 if k % 2 == 0 else -0.016
		var look: Color = cloth.darkened(0.22) if k % 2 == 1 else cloth
		if stripes:
			look = white.darkened(0.06) if k % 2 == 1 else red
		Kit.box(f, Vector3(0.095, long, 0.03), Vector3(x, y1 - long * 0.5, z), look)
		if stripes and k < 3:                                 # the blue corner, at the top by the pole
			Kit.box(f, Vector3(0.097, 0.5, 0.034), Vector3(x, y1 - 0.25 + 0.01, z), Color(0.13, 0.17, 0.42).darkened(0.18 * (k % 2)))
		if not stripes:
			Kit.box(f, Vector3(0.097, 0.025, 0.034), Vector3(x, y1 - long - 0.008, z), brass)      # the fringe
	Kit.box(f, Vector3(0.03, 0.05, 0.03), Vector3(x0 + way * 0.012, top + 0.01, 0), brass)      # the tie
	return f


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


## kind: "cruiser", "van" (the police one) or "ambulance". The length runs front to back; the front is the front.
static func car(p: Node3D, b: int, u: float, v: float, yaw := 0.0, kind := "cruiser", solid := true) -> Node3D:
	var amb := kind == "ambulance"
	var van := kind == "van" or amb
	var w := 1.95 if van else 1.82
	var l := 4.3 if van else 4.5
	var g: Node3D = p.prop(b, u, v, yaw, w, l, solid)
	var paint := Color(0.2, 0.26, 0.42) if kind == "van" else Color(0.9, 0.9, 0.86)
	var glass := Color(0.14, 0.19, 0.25)
	if van:
		Kit.block(g, Vector3(w, 1.55, l), Vector3(0, 0.32, 0), paint)
		Kit.box(g, Vector3(w - 0.2, 0.55, 0.02), Vector3(0, 1.45, l * 0.5 + 0.005), glass)
		Kit.box(g, Vector3(w + 0.02, 0.2, l + 0.02), Vector3(0, 0.75, 0), Color(0.9, 0.45, 0.1) if amb else Color(0.9, 0.9, 0.86))
		for side in [-1.0, 1.0]:
			words(g, "AMBULANCE" if amb else "POLICE", Vector3(side * (w * 0.5 + 0.012), 1.3, -0.3), 0.2 if amb else 0.3, Color(0.75, 0.12, 0.1) if amb else Color(0.92, 0.9, 0.8), 90.0 * side)
			Kit.box(g, Vector3(0.02, 0.4, 0.7), Vector3(side * (w * 0.5 + 0.005), 1.42, 1.5), glass)
		if amb:       # the light bars, and the back doors with their windows
			for z: float in [l * 0.5 - 0.5, -l * 0.5 + 0.3]:
				Kit.box(g, Vector3(w - 0.3, 0.12, 0.24), Vector3(0, 1.93, z), Kit.flat(Color(0.9, 0.15, 0.12), 0.7))
			for x: float in [-0.42, 0.42]:
				Kit.box(g, Vector3(0.6, 0.45, 0.02), Vector3(x, 1.42, -l * 0.5 - 0.004), glass)
			Kit.box(g, Vector3(0.02, 1.3, 0.02), Vector3(0, 1.1, -l * 0.5 - 0.004), IRON)
			words(g, "AMBULANCE", Vector3(0, 1.0, -l * 0.5 - 0.02), 0.16, Color(0.75, 0.12, 0.1), 180.0)
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
	# The two flags stand on the platform, one at each end, behind the front.
	flag_on(g, Vector3(-w * 0.5 + 0.3, 0.3, -d * 0.5 + 0.3), Color(0.16, 0.2, 0.45), true, 5.0)
	flag_on(g, Vector3(w * 0.5 - 0.3, 0.3, -d * 0.5 + 0.3), Color(0.75, 0.6, 0.2), false, -5.0)
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
	Kit.box(g, Vector3(w + 0.02, 0.95, 0.06), Vector3(0, 0.475, -l * 0.5 + 0.02), WOOD_DARK.lightened(0.08))
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


## A flight of stairs. Its foot is at the street end of its floor space and it
## climbs towards the back, `rise` metres in all. A banister runs up its open
## side (the right, facing the foot), from a newel post at the foot to where it
## meets the ceiling (`ceiling` metres up).
static func stairs(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, l := 3.4, rise := 2.9, look := WOOD, ceiling := 2.9) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var n := 12
	for i in n:
		var h := rise * float(i + 1) / float(n)
		Kit.block(g, Vector3(w, h, l / n), Vector3(0, 0, l * 0.5 - (i + 0.5) * l / n), look.darkened(0.04 * (i % 2)))
	# The banister: a newel post, a baluster on each tread, the handrail over them.
	var dark := WOOD_DARK
	var x := w * 0.5 - 0.04
	var hand := 0.86                       # the handrail is this far above the treads
	Kit.block(g, Vector3(0.09, hand + 0.3, 0.09), Vector3(x, 0, l * 0.5 + 0.045), dark)
	Kit.ball(g, 0.065, Vector3(x, hand + 0.34, l * 0.5 + 0.045), dark, 6)
	var last := 0
	for i in n:
		var h := rise * float(i + 1) / float(n)
		if h + hand > ceiling - 0.04:
			break
		last = i
		Kit.block(g, Vector3(0.035, hand, 0.035), Vector3(x, h, l * 0.5 - (i + 0.5) * l / n), dark)
	# The handrail runs from the newel to the last baluster, along the slope.
	var z0 := l * 0.5 + 0.045
	var z1 := l * 0.5 - (last + 0.5) * l / n
	var y0 := hand + 0.22
	var y1 := rise * float(last + 1) / float(n) + hand
	var run := Vector2(z0 - z1, y1 - y0)
	Kit.box(g, Vector3(0.06, 0.05, run.length() + 0.04), Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), dark, Vector3(rad_to_deg(atan2(run.y, run.x)), 0, 0))
	return g


## The top of that flight, on the floor above: the same floor space, at the
## same spot. The floor of the room must have a hole there (place.gd's room,
## opts "hole"). The stairs come up at the BACK end, level with the floor, and
## drop away towards the street; a rail guards the open side and the street
## end, and the back end is where you step on.
static func stairwell(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, l := 3.4, rise := 2.9, look := WOOD, shaft := Color(0.3, 0.26, 0.2)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var n := 12
	for i in n:        # the same treads as below, seen from above: the top one is flush with this floor
		var h := rise * float(i + 1) / float(n)
		Kit.block(g, Vector3(w - 0.01, h, l / n), Vector3(0, -rise - 0.002, l * 0.5 - (i + 0.5) * l / n), look.darkened(0.04 * (i % 2) + 0.5 * (1.0 - float(i + 1) / float(n))))
	# The sides of the shaft under the floor.
	Kit.box(g, Vector3(0.04, rise, l), Vector3(-w * 0.5 - 0.02, -rise * 0.5 - 0.31, 0), shaft)
	Kit.box(g, Vector3(0.04, rise, l), Vector3(w * 0.5 + 0.02, -rise * 0.5 - 0.31, 0), shaft.darkened(0.2))
	Kit.box(g, Vector3(w + 0.08, rise, 0.04), Vector3(0, -rise * 0.5 - 0.31, l * 0.5 + 0.02), shaft.darkened(0.35))
	# The rail: along the open side and across the street end.
	var dark := WOOD_DARK
	var x := w * 0.5 - 0.035
	var z := l * 0.5 - 0.035
	Kit.box(g, Vector3(0.06, 0.05, l - 0.01), Vector3(x, 0.93, 0), dark)
	Kit.box(g, Vector3(w - 0.07, 0.05, 0.06), Vector3(-0.035, 0.925, z), dark)
	var posts := int(l / 0.14)
	for i in posts + 1:
		Kit.block(g, Vector3(0.035, 0.9, 0.035), Vector3(x, 0, -l * 0.5 + 0.045 + i * (l - 0.09) / float(posts)), dark)
	for i in range(1, int(w / 0.14)):
		Kit.block(g, Vector3(0.035, 0.9, 0.035), Vector3(x - i * 0.14, 0, z), dark)
	Kit.block(g, Vector3(0.09, 1.1, 0.09), Vector3(x, 0, -l * 0.5 + 0.045), dark)        # the newel at the top of the stairs
	Kit.ball(g, 0.065, Vector3(x, 1.14, -l * 0.5 + 0.045), dark, 6)
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



# ---------------------------------------------------------------------- shops

const GOODS := [Color(0.82, 0.2, 0.18), Color(0.95, 0.75, 0.15), Color(0.2, 0.45, 0.75), Color(0.25, 0.6, 0.3), Color(0.9, 0.5, 0.15), Color(0.88, 0.86, 0.8), Color(0.55, 0.25, 0.55)]
const BOTTLES := [Color(0.45, 0.25, 0.1), Color(0.16, 0.35, 0.2), Color(0.75, 0.6, 0.25), Color(0.8, 0.82, 0.8), Color(0.3, 0.12, 0.1), Color(0.15, 0.2, 0.4)]
const CANS := [Color(0.8, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.2, 0.55, 0.3), Color(0.9, 0.6, 0.1), Color(0.85, 0.85, 0.85), Color(0.5, 0.2, 0.5)]
const PLEXI := Color(0.72, 0.88, 0.84, 0.2)


## Stock one shelf: a row of packets ("goods"), "bottles" or "cans" standing at
## height y from x0 to x1, their fronts at z and `deep` from front to back.
## `key` seeds the steady random numbers; `room` is the height to the shelf
## above; `face` -1 stocks the far side of a two-sided unit.
static func stock(g: Node3D, kind: String, x0: float, x1: float, y: float, z: float, deep: float, key: float, room := 0.3, face := 1.0) -> void:
	var x := x0
	var n := 0
	while x < x1 - 0.05:
		var k := key + n * 1.93
		var run := key + floorf(n / 3.0) * 7.31         # bottles and cans stand three of a kind together
		n += 1
		var bw := 0.12 + 0.2 * rnd(k)
		var bh := 0.1 + 0.2 * rnd(k + 5.0)
		var tint: Color = GOODS[int(rnd(k + 2.0) * GOODS.size()) % GOODS.size()]
		if kind == "bottles":
			bw = 0.085
			bh = 0.24 + 0.09 * rnd(run + 5.0)
			tint = BOTTLES[int(rnd(run + 2.0) * BOTTLES.size()) % BOTTLES.size()]
		elif kind == "cans":
			bw = 0.075
			bh = 0.13 + 0.08 * rnd(run + 5.0)
			tint = CANS[int(rnd(run + 2.0) * CANS.size()) % CANS.size()]
		bh = minf(bh, room - (0.13 if kind == "bottles" else 0.05))
		if x + bw > x1:
			break
		var mid := Vector3(x + bw * 0.5, y, z - face * deep * 0.5)
		Kit.block(g, Vector3(bw, bh, deep), mid, tint)
		if kind == "bottles":
			Kit.block(g, Vector3(0.03, 0.07, 0.03), Vector3(mid.x, y + bh, z - face * 0.045), tint.darkened(0.3))
		if kind != "goods" or rnd(k + 7.0) > 0.4:
			Kit.box(g, Vector3(bw * 0.8, bh * 0.35, 0.006), Vector3(mid.x, y + bh * 0.5, z + face * 0.002), PAPER if rnd(run + 3.0) > 0.4 else Color(0.95, 0.85, 0.3))
		x += bw + (0.012 if kind != "goods" else 0.03 + 0.05 * rnd(k + 9.0))


## Two-sided shop shelving, stocked on both faces. `w` is its length.
static func gondola(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.6, kind := "goods", h := 1.3, d := 0.7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var metal := Color(0.82, 0.8, 0.72)
	Kit.block(g, Vector3(w, 0.12, d), Vector3.ZERO, metal)
	Kit.block(g, Vector3(w - 0.08, h, 0.04), Vector3.ZERO, metal.darkened(0.15))
	for x: float in [-w * 0.5 + 0.015, w * 0.5 - 0.015]:
		Kit.box(g, Vector3(0.03, h - 0.12, d - 0.02), Vector3(x, 0.12 + (h - 0.12) * 0.5, 0), metal)
	var rows := 3
	var gap := (h - 0.16) / float(rows)
	for i in rows:
		var y := 0.12 + i * gap
		if i > 0:
			Kit.box(g, Vector3(w - 0.06, 0.025, d - 0.04), Vector3(0, y - 0.0125, 0), metal.lightened(0.08))
		for face: float in [1.0, -1.0]:
			stock(g, kind, -w * 0.5 + 0.06, w * 0.5 - 0.06, y, face * (d * 0.5 - 0.04), d * 0.5 - 0.08, u * 7.3 + v * 3.1 + i * 11.7 + face * 2.9, gap, face)
	return g


## n glass-door coolers in a row, lit inside and stocked ("cans" or "bottles").
static func fridge_case(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 3, kind := "cans", label := "COLD DRINKS", ink := Color(0.15, 0.3, 0.7)) -> Node3D:
	var w := 0.75 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.7)
	var shell := Color(0.84, 0.84, 0.82)
	Kit.block(g, Vector3(w, 0.25, 0.7), Vector3.ZERO, DARK)
	Kit.box(g, Vector3(w - 0.08, 1.48, 0.04), Vector3(0, 1.0, -0.33), Kit.flat(Color(0.82, 0.93, 1.0), 0.7))
	Kit.box(g, Vector3(w, 0.3, 0.7), Vector3(0, 1.9, 0), shell)
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.box(g, Vector3(0.04, 1.5, 0.7), Vector3(x, 1.0, 0), shell)
	for i in n:
		var x := -w * 0.5 + 0.375 + i * 0.75
		for k in 4:
			var y := 0.3 + k * 0.36
			Kit.box(g, Vector3(0.68, 0.02, 0.56), Vector3(x, y - 0.01, -0.03), STEEL)
			stock(g, kind, x - 0.32, x + 0.32, y, 0.24, 0.3, u * 5.3 + v * 2.1 + i * 13.1 + k * 3.7, 0.35)
		Kit.box(g, Vector3(0.7, 1.46, 0.02), Vector3(x, 1.0, 0.335), Color(0.7, 0.88, 0.95, 0.16))
		Kit.box(g, Vector3(0.025, 0.4, 0.03), Vector3(x + 0.3, 1.05, 0.365), STEEL)
		if i > 0:
			Kit.box(g, Vector3(0.04, 1.5, 0.05), Vector3(x - 0.375, 1.0, 0.33), shell)
	words(g, label, Vector3(0, 1.9, 0.356), 0.13, ink)
	return g


## A plexiglass screen standing on a counter: `w` long, from y0 up to y1, at z
## in the counter's group, with a slot in the middle to pass things through.
static func screen(g: Node3D, w: float, z: float, y0 := 1.05, y1 := 2.2, slot := 0.5) -> void:
	Kit.box(g, Vector3(w, y1 - y0 - 0.26, 0.03), Vector3(0, (y0 + 0.26 + y1) * 0.5, z), PLEXI)
	var side := (w - slot) * 0.5
	for x: float in [-(slot + side) * 0.5, (slot + side) * 0.5]:
		Kit.box(g, Vector3(side, 0.26, 0.03), Vector3(x, y0 + 0.13, z), PLEXI)
	var n := maxi(int(w / 1.2), 1)
	for i in n + 1:
		var x := -w * 0.5 + w * float(i) / float(n)
		if absf(x) > slot * 0.5 + 0.03:
			Kit.box(g, Vector3(0.04, y1 - y0 - 0.006, 0.05), Vector3(x, (y0 + y1) * 0.5 - 0.003, z), STEEL)
	Kit.box(g, Vector3(w + 0.04, 0.05, 0.06), Vector3(0, y1 + 0.015, z), STEEL)


## A cash register, to stand on a counter: give the group and where.
static func till(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.block(g, Vector3(0.38, 0.12, 0.36), Vector3.ZERO, Color(0.3, 0.3, 0.32))
	Kit.box(g, Vector3(0.36, 0.14, 0.2), Vector3(0, 0.2, -0.06), Color(0.36, 0.36, 0.38), Vector3(-20, 0, 0))
	Kit.box(g, Vector3(0.2, 0.06, 0.02), Vector3(0, 0.32, -0.15), Kit.flat(Color(0.3, 0.95, 0.5), 0.8))
	return g


## The lottery machine, to stand on a counter.
static func lotto(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.block(g, Vector3(0.3, 0.34, 0.26), Vector3.ZERO, Color(0.2, 0.3, 0.6))
	Kit.box(g, Vector3(0.22, 0.16, 0.012), Vector3(0, 0.22, 0.134), Kit.flat(Color(0.5, 0.85, 1.0), 0.8))
	words(g, "LOTTERY", Vector3(0, 0.4, 0), 0.06, Color(0.98, 0.85, 0.3))
	return g


## A chest freezer with sliding glass lids.
static func chest_freezer(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.3, text := "ICE CREAM", band := Color(0.85, 0.2, 0.3)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.7)
	Kit.block(g, Vector3(w, 0.8, 0.7), Vector3.ZERO, Color(0.92, 0.92, 0.9))
	Kit.box(g, Vector3(w - 0.08, 0.04, 0.62), Vector3(0, 0.83, 0), Color(0.62, 0.8, 0.88, 0.45))
	Kit.box(g, Vector3(w, 0.22, 0.012), Vector3(0, 0.55, 0.357), band)
	words(g, text, Vector3(0, 0.55, 0.366), 0.11, PAPER)
	return g


## The ice cabinet that stands outside a shop.
static func ice_box(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 0.7)
	Kit.block(g, Vector3(1.2, 1.6, 0.7), Vector3.ZERO, Color(0.9, 0.92, 0.94))
	for x: float in [-0.29, 0.29]:
		Kit.box(g, Vector3(0.54, 0.95, 0.02), Vector3(x, 0.6, 0.355), Color(0.82, 0.85, 0.88))
		Kit.box(g, Vector3(0.03, 0.2, 0.03), Vector3(x * 0.3, 0.7, 0.375), STEEL)
	words(g, "ICE", Vector3(0, 1.32, 0.356), 0.34, Color(0.15, 0.35, 0.75))
	return g


static func atm(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.5)
	Kit.block(g, Vector3(0.5, 1.5, 0.5), Vector3.ZERO, Color(0.2, 0.26, 0.36))
	Kit.box(g, Vector3(0.3, 0.22, 0.012), Vector3(0, 1.15, 0.254), Kit.flat(Color(0.4, 0.8, 0.95), 0.8))
	Kit.box(g, Vector3(0.3, 0.14, 0.03), Vector3(0, 0.92, 0.26), STEEL, Vector3(-35, 0, 0))
	Kit.box(g, Vector3(0.24, 0.03, 0.012), Vector3(0, 0.76, 0.254), DARK)
	words(g, "ATM", Vector3(0, 1.38, 0.256), 0.12, Color(0.98, 0.9, 0.4))
	return g


## A wire rack of newspapers.
static func news_rack(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.55, 0.4)
	for x: float in [-0.26, 0.26]:
		Kit.block(g, Vector3(0.02, 0.9, 0.36), Vector3(x, 0, 0), IRON)
	for k in 3:
		Kit.box(g, Vector3(0.5, 0.02, 0.3), Vector3(0, 0.22 + k * 0.28, 0.0), IRON, Vector3(-20, 0, 0))
		Kit.box(g, Vector3(0.44, 0.05, 0.28), Vector3(0, 0.26 + k * 0.28, 0.0), PAPER.darkened(0.06 * k), Vector3(-20, 0, 0))
		Kit.box(g, Vector3(0.36, 0.052, 0.07), Vector3(0, 0.29 + k * 0.28, -0.08), DARK, Vector3(-20, 0, 0))
	return g


## Words that glow: a neon or lit sign in a window or on a wall.
static func neon(parent: Node3D, text: String, pos: Vector3, height: float, colour: Color, yaw := 0.0) -> Label3D:
	var l := words(parent, text, pos, height, colour, yaw)
	l.outline_size = 14
	l.outline_modulate = Color(colour.r, colour.g, colour.b, 0.28)
	l.render_priority = 1
	return l


## A lit sign box with words on its front.
static func sign_box(parent: Node3D, text: String, pos: Vector3, size: Vector2, look: Color, ink: Color, yaw := 0.0, glow := 0.7, letters := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(size.x, size.y, 0.12), Vector3.ZERO, Kit.flat(look, glow))
	Kit.box(g, Vector3(size.x + 0.06, size.y + 0.06, 0.1), Vector3.ZERO, IRON)
	words(g, text, Vector3(0, 0, 0.064), letters if letters > 0.0 else size.y * 0.6, ink)
	return g


## A stack of cases (beer, soda), each row one case shorter than the row under it.
static func case_stack(p: Node3D, b: int, u: float, v: float, yaw := 0.0, cols := 3, rows := 3, look := Color(0.75, 0.16, 0.14)) -> Node3D:
	var w := 0.42 * cols
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.66)
	for r in rows:
		for c in maxi(cols - r, 1):
			var x := -w * 0.5 + 0.21 + c * 0.42 + r * 0.21
			for z in 2:
				Kit.block(g, Vector3(0.4, 0.25, 0.31), Vector3(x, r * 0.255, -0.165 + z * 0.33), look.darkened(0.1 * ((c + r + z) % 2)))
			Kit.box(g, Vector3(0.24, 0.1, 0.006), Vector3(x, r * 0.255 + 0.125, 0.324), PAPER)
	return g


# ------------------------------------------------------------------- hospital

## A hospital trolley bed. The head is at the back of its floor space.
static func gurney(p: Node3D, b: int, u: float, v: float, yaw := 0.0, sheet := Color(0.82, 0.9, 0.92), rails := true, w := 0.85, l := 2.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	for x: float in [-w * 0.5 + 0.07, w * 0.5 - 0.07]:
		for z: float in [-l * 0.5 + 0.18, l * 0.5 - 0.18]:
			Kit.cyl(g, 0.02, 0.46, Vector3(x, 0.31, z), STEEL, Vector3.ZERO, 5)
			Kit.cyl(g, 0.06, 0.04, Vector3(x, 0.06, z), DARK, Vector3(0, 0, 90), 8)
	Kit.box(g, Vector3(w, 0.05, l), Vector3(0, 0.565, 0), STEEL)
	Kit.box(g, Vector3(w - 0.06, 0.1, l - 0.06), Vector3(0, 0.64, 0), Color(0.3, 0.42, 0.5))
	Kit.box(g, Vector3(w - 0.04, 0.03, l * 0.6), Vector3(0, 0.705, l * 0.2 - 0.04), sheet)
	Kit.box(g, Vector3(w * 0.6, 0.08, 0.32), Vector3(0, 0.73, -l * 0.5 + 0.25), PAPER)
	if rails:
		for x: float in [-w * 0.5 + 0.012, w * 0.5 - 0.012]:
			Kit.box(g, Vector3(0.02, 0.03, l * 0.5), Vector3(x, 0.93, -l * 0.1), STEEL)
			for z: float in [-l * 0.35 + 0.01, l * 0.15 - 0.01]:
				Kit.box(g, Vector3(0.02, 0.33, 0.02), Vector3(x, 0.755, z), STEEL)
	return g


## A cubicle curtain hanging from a rail, `w` long.
static func curtain(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, cloth := Color(0.56, 0.68, 0.82)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.06)
	Kit.box(g, Vector3(w, 0.03, 0.03), Vector3(0, 2.125, 0), STEEL)
	var n := maxi(int(w / 0.16), 2)
	for i in n:
		Kit.box(g, Vector3(w / n, 1.8, 0.02), Vector3(-w * 0.5 + (i + 0.5) * w / n, 1.2, 0.012 if i % 2 == 0 else -0.012), cloth.darkened(0.12 * (i % 2)))
	return g


## A drip on a wheeled pole.
static func iv_stand(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3, 0.3)
	Kit.cyl(g, 0.14, 0.03, Vector3(0, 0.03, 0), STEEL, Vector3.ZERO, 5)
	Kit.cyl(g, 0.012, 1.9, Vector3(0, 0.97, 0), STEEL, Vector3.ZERO, 5)
	Kit.box(g, Vector3(0.26, 0.015, 0.015), Vector3(0, 1.9, 0), STEEL)
	Kit.box(g, Vector3(0.11, 0.2, 0.03), Vector3(0.09, 1.77, 0), Color(0.85, 0.92, 0.95, 0.7))
	Kit.box(g, Vector3(0.006, 0.9, 0.006), Vector3(0.09, 1.22, 0), Color(0.85, 0.9, 0.92))
	return g


## A heart monitor on a wheeled stand.
static func monitor_stand(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.4, 0.4)
	Kit.cyl(g, 0.16, 0.04, Vector3(0, 0.04, 0), IRON, Vector3.ZERO, 5)
	Kit.cyl(g, 0.02, 1.2, Vector3(0, 0.64, 0), STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.36, 0.28, 0.24), Vector3(0, 1.36, 0), CREAM)
	Kit.box(g, Vector3(0.28, 0.2, 0.01), Vector3(0, 1.37, 0.124), Color(0.06, 0.12, 0.1))
	var trace := Kit.flat(Color(0.3, 1.0, 0.45), 1.2)
	Kit.box(g, Vector3(0.22, 0.012, 0.004), Vector3(0, 1.36, 0.131), trace)
	Kit.box(g, Vector3(0.02, 0.08, 0.004), Vector3(-0.03, 1.4, 0.131), trace)
	return g


static func wheelchair(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.62, 0.8)
	var cloth := Color(0.15, 0.2, 0.35)
	Kit.box(g, Vector3(0.46, 0.04, 0.42), Vector3(0, 0.5, 0), cloth)
	Kit.box(g, Vector3(0.46, 0.42, 0.04), Vector3(0, 0.75, -0.2), cloth)
	for x: float in [-0.27, 0.27]:
		Kit.cyl(g, 0.3, 0.04, Vector3(x, 0.3, -0.08), DARK, Vector3(0, 0, 90), 12)
		Kit.cyl(g, 0.22, 0.045, Vector3(x, 0.3, -0.08), STEEL, Vector3(0, 0, 90), 10)
		Kit.cyl(g, 0.08, 0.03, Vector3(x * 0.85, 0.08, 0.3), DARK, Vector3(0, 0, 90), 8)
		Kit.box(g, Vector3(0.03, 0.03, 0.46), Vector3(x * 0.9, 0.68, -0.01), STEEL)
		Kit.box(g, Vector3(0.03, 0.5, 0.03), Vector3(x * 0.85, 0.33, 0.22), STEEL)
	Kit.box(g, Vector3(0.4, 0.02, 0.14), Vector3(0, 0.1, 0.36), STEEL)
	Kit.box(g, Vector3(0.5, 0.03, 0.03), Vector3(0, 0.98, -0.24), STEEL)
	return g


## n plastic seats joined on a beam, as in a waiting room.
static func seats(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 4, look := Color(0.2, 0.45, 0.6)) -> Node3D:
	var w := 0.52 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.55)
	Kit.box(g, Vector3(w, 0.05, 0.08), Vector3(0, 0.37, 0), STEEL)
	for x: float in [-w * 0.5 + 0.12, w * 0.5 - 0.12]:
		Kit.block(g, Vector3(0.05, 0.345, 0.5), Vector3(x, 0, 0), STEEL)
	for i in n:
		var x := -w * 0.5 + 0.26 + i * 0.52
		Kit.box(g, Vector3(0.46, 0.05, 0.44), Vector3(x, 0.43, 0.03), look)
		Kit.box(g, Vector3(0.46, 0.4, 0.05), Vector3(x, 0.7, -0.2), look)
	return g


## The red emergency trolley with the defibrillator on top.
static func crash_cart(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.6, 0.45)
	Kit.block(g, Vector3(0.6, 0.85, 0.45), Vector3(0, 0.08, 0), Color(0.75, 0.15, 0.15))
	for k in 4:
		Kit.box(g, Vector3(0.52, 0.15, 0.02), Vector3(0, 0.22 + k * 0.19, 0.23), Color(0.85, 0.25, 0.22))
		Kit.box(g, Vector3(0.16, 0.02, 0.02), Vector3(0, 0.22 + k * 0.19, 0.246), STEEL)
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.16, 0.16]:
			Kit.cyl(g, 0.04, 0.03, Vector3(x, 0.04, z), DARK, Vector3(0, 0, 90), 8)
	Kit.block(g, Vector3(0.3, 0.16, 0.26), Vector3(-0.1, 0.93, 0), CREAM)
	Kit.box(g, Vector3(0.14, 0.09, 0.01), Vector3(-0.1, 1.02, 0.134), Kit.flat(Color(0.3, 1.0, 0.45), 0.8))
	return g


## A bright examination lamp on a wheeled stand, its head leaning over towards `yaw`.
static func exam_lamp(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.4, 0.4)
	Kit.cyl(g, 0.17, 0.04, Vector3(0, 0.04, 0), IRON, Vector3.ZERO, 5)
	Kit.cyl(g, 0.02, 1.9, Vector3(0, 0.99, 0), STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.04, 0.04, 0.7), Vector3(0, 1.95, 0.33), STEEL)
	Kit.cyl(g, 0.3, 0.09, Vector3(0, 1.9, 0.72), Color(0.82, 0.84, 0.86), Vector3.ZERO, 12)
	Kit.cyl(g, 0.25, 0.02, Vector3(0, 1.85, 0.72), Kit.flat(Color(1.0, 0.98, 0.9), 1.6), Vector3.ZERO, 12)
	Kit.omni(g, Vector3(0, 1.6, 0.72), Color(1.0, 0.98, 0.92), 0.7, 4.0)
	return g


## The lit box X-rays are read on, on a wall.
static func lightbox(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.0, 0.08, false)
	Kit.box(g, Vector3(1.0, 0.6, 0.06), Vector3(0, 1.6, 0.03), CREAM)
	Kit.box(g, Vector3(0.92, 0.52, 0.01), Vector3(0, 1.6, 0.064), Kit.flat(Color(0.92, 0.97, 1.0), 1.0))
	for x: float in [-0.23, 0.23]:
		Kit.box(g, Vector3(0.36, 0.44, 0.006), Vector3(x, 1.6, 0.073), Color(0.1, 0.13, 0.18))
		Kit.box(g, Vector3(0.05, 0.3, 0.004), Vector3(x, 1.6, 0.079), Color(0.78, 0.85, 0.92))
		Kit.box(g, Vector3(0.2, 0.04, 0.004), Vector3(x, 1.68, 0.079), Color(0.78, 0.85, 0.92))
	return g


## n oxygen cylinders standing in a row.
static func oxygen(p: Node3D, b: int, u: float, v: float, n := 2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3 * n, 0.3)
	for i in n:
		var x := -0.15 * (n - 1) + i * 0.3
		Kit.cyl(g, 0.11, 1.2, Vector3(x, 0.6, 0), Color(0.2, 0.5, 0.32), Vector3.ZERO, 8)
		Kit.cyl(g, 0.04, 0.12, Vector3(x, 1.26, 0), STEEL, Vector3.ZERO, 6)
	return g


## A television on a bracket high on a wall.
static func wall_tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 2.15) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.4, false)
	Kit.box(g, Vector3(0.06, 0.06, 0.3), Vector3(0, y, 0.15), IRON)
	Kit.box(g, Vector3(0.66, 0.5, 0.4), Vector3(0, y, 0.42), Color(0.2, 0.2, 0.22))
	Kit.box(g, Vector3(0.52, 0.38, 0.01), Vector3(0, y, 0.624), Kit.flat(Color(0.5, 0.68, 0.8), 0.9))
	return g


# ------------------------------------------------------------ more of the home

## A dining chair on four legs.
static func seat(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := WOOD, pad := VINYL) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.44, 0.44)
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.18, 0.18]:
			Kit.block(g, Vector3(0.04, 0.44, 0.04), Vector3(x, 0, z), look)
		Kit.box(g, Vector3(0.04, 0.5, 0.04), Vector3(x, 0.74, -0.18), look)
	Kit.box(g, Vector3(0.42, 0.05, 0.42), Vector3(0, 0.465, 0), pad)
	Kit.box(g, Vector3(0.4, 0.14, 0.03), Vector3(0, 0.88, -0.18), look)
	return g


## A big projection television with a video recorder on top.
static func big_tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 0.6)
	Kit.block(g, Vector3(1.5, 1.25, 0.6), Vector3.ZERO, Color(0.12, 0.12, 0.14))
	Kit.box(g, Vector3(1.3, 0.86, 0.02), Vector3(0, 0.74, 0.305), Kit.flat(Color(0.45, 0.62, 0.85), 0.9))
	Kit.box(g, Vector3(1.3, 0.14, 0.02), Vector3(0, 0.16, 0.305), Color(0.22, 0.22, 0.25))
	Kit.block(g, Vector3(0.44, 0.09, 0.3), Vector3(-0.3, 1.25, 0), Color(0.25, 0.25, 0.28))
	Kit.box(g, Vector3(0.1, 0.02, 0.01), Vector3(-0.3, 1.3, 0.154), Kit.flat(Color(0.3, 0.95, 0.5), 1.0))
	for k in 3:
		Kit.block(g, Vector3(0.2, 0.03, 0.12), Vector3(0.35, 1.25 + k * 0.031, 0.02 * k), Color(0.15, 0.15, 0.17).lightened(0.12 * k))
	return g


## A loudspeaker cabinet.
static func speaker(p: Node3D, b: int, u: float, v: float, yaw := 0.0, h := 1.1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.45, 0.4)
	Kit.block(g, Vector3(0.45, h, 0.4), Vector3.ZERO, Color(0.14, 0.13, 0.13))
	Kit.disc(g, 0.17, Vector3(0, h * 0.34, 0.203), Color(0.3, 0.3, 0.32), 0.012, 12)
	Kit.disc(g, 0.09, Vector3(0, h * 0.34, 0.21), DARK, 0.012, 10)
	Kit.disc(g, 0.08, Vector3(0, h * 0.74, 0.203), Color(0.3, 0.3, 0.32), 0.012, 10)
	return g


## An electric keyboard on its stand.
static func keyboard(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.3, 0.4)
	for x: float in [-0.45, 0.45]:
		Kit.box(g, Vector3(0.03, 0.92, 0.03), Vector3(x, 0.42, 0), IRON, Vector3(24, 0, 0))
		Kit.box(g, Vector3(0.03, 0.92, 0.03), Vector3(x, 0.42, 0), IRON, Vector3(-24, 0, 0))
	Kit.box(g, Vector3(1.3, 0.08, 0.36), Vector3(0, 0.86, 0), Color(0.12, 0.12, 0.14))
	Kit.box(g, Vector3(1.2, 0.012, 0.16), Vector3(0, 0.906, 0.08), PAPER)
	for i in 14:
		Kit.box(g, Vector3(0.03, 0.014, 0.09), Vector3(-0.56 + i * 0.086, 0.915, 0.045), DARK)
	Kit.box(g, Vector3(0.5, 0.01, 0.08), Vector3(-0.2, 0.905, -0.1), Color(0.25, 0.3, 0.4))
	for i in 4:
		Kit.box(g, Vector3(0.03, 0.012, 0.03), Vector3(0.2 + i * 0.09, 0.906, -0.1), Kit.flat(Color(1.0, 0.3, 0.2), 1.0))
	return g


## n milk crates of records in a row.
static func crates(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 2) -> Node3D:
	var w := 0.38 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.36)
	for i in n:
		var x := -w * 0.5 + 0.19 + i * 0.38
		Kit.block(g, Vector3(0.36, 0.3, 0.34), Vector3(x, 0, 0), [Color(0.7, 0.15, 0.15), Color(0.15, 0.3, 0.65), Color(0.2, 0.5, 0.3), Color(0.85, 0.5, 0.1)][i % 4])
		for k in 9:
			Kit.box(g, Vector3(0.03, 0.31, 0.3), Vector3(x - 0.14 + k * 0.035, 0.2, 0), (GOODS[(k + i * 3) % GOODS.size()] as Color).darkened(0.25))
	return g


## A framed gold record, on a wall.
static func gold_record(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 1.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.05, false)
	var gold := Color(0.9, 0.72, 0.2)
	Kit.box(g, Vector3(0.46, 0.56, 0.02), Vector3(0, y, 0.012), DARK)
	Kit.disc(g, 0.17, Vector3(0, y + 0.06, 0.03), gold, 0.012, 14)
	Kit.disc(g, 0.05, Vector3(0, y + 0.06, 0.036), Color(0.75, 0.15, 0.12), 0.012, 10)
	Kit.box(g, Vector3(0.22, 0.06, 0.008), Vector3(0, y - 0.2, 0.026), gold)
	return g


## A fish tank on a cupboard.
static func aquarium(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.45)
	Kit.block(g, Vector3(w, 0.7, 0.45), Vector3.ZERO, WOOD_DARK)
	Kit.box(g, Vector3(w - 0.08, 0.04, 0.36), Vector3(0, 0.73, 0), Color(0.75, 0.68, 0.5))
	Kit.box(g, Vector3(w - 0.04, 0.5, 0.4), Vector3(0, 0.96, 0), Color(0.3, 0.62, 0.82, 0.4))
	Kit.box(g, Vector3(w - 0.06, 0.02, 0.38), Vector3(0, 1.19, 0), Kit.flat(Color(0.7, 0.95, 1.0), 1.0))
	Kit.box(g, Vector3(w, 0.05, 0.45), Vector3(0, 1.235, 0), DARK)
	for i in 4:
		Kit.box(g, Vector3(0.08, 0.04, 0.02), Vector3(-w * 0.3 + i * w * 0.2, 0.85 + 0.08 * (i % 3), 0.05 * (i % 2)), Kit.flat(Color(1.0, 0.55, 0.1), 0.6))
	return g


static func wardrobe(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2, look := WOOD_DARK) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	Kit.block(g, Vector3(w, 2.0, 0.6), Vector3.ZERO, look)
	for x: float in [-w * 0.25, w * 0.25]:
		Kit.box(g, Vector3(w * 0.5 - 0.05, 1.8, 0.02), Vector3(x, 1.02, 0.305), look.lightened(0.08))
		Kit.ball(g, 0.025, Vector3(x * 0.16, 1.0, 0.33), Color(0.8, 0.65, 0.3), 5)
	return g


## A bank of letter boxes, on a wall.
static func mailboxes(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 0.1, false)
	Kit.box(g, Vector3(1.24, 0.66, 0.08), Vector3(0, 1.35, 0.04), IRON)
	for r in 2:
		for c in 5:
			Kit.box(g, Vector3(0.21, 0.27, 0.012), Vector3(-0.48 + c * 0.24, 1.2 + r * 0.3, 0.086), STEEL)
			Kit.box(g, Vector3(0.1, 0.015, 0.006), Vector3(-0.48 + c * 0.24, 1.26 + r * 0.3, 0.095), DARK)
	return g


static func safe(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.6, 0.55)
	var green := Color(0.16, 0.24, 0.2)
	Kit.block(g, Vector3(0.6, 0.75, 0.55), Vector3.ZERO, green)
	Kit.box(g, Vector3(0.5, 0.62, 0.02), Vector3(0, 0.38, 0.28), green.lightened(0.08))
	Kit.disc(g, 0.07, Vector3(-0.05, 0.42, 0.296), STEEL, 0.012, 12)
	Kit.box(g, Vector3(0.03, 0.14, 0.03), Vector3(0.16, 0.4, 0.3), STEEL)
	return g


## A weights bench with a loaded bar on its rests.
static func weights(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 1.3)
	Kit.box(g, Vector3(0.3, 0.08, 1.2), Vector3(0, 0.44, 0.05), VINYL)
	for z: float in [-0.45, 0.55]:
		Kit.block(g, Vector3(0.26, 0.4, 0.05), Vector3(0, 0, z), IRON)
	for x: float in [-0.45, 0.45]:
		Kit.block(g, Vector3(0.05, 1.0, 0.05), Vector3(x, 0, -0.45), IRON)
		Kit.cyl(g, 0.2, 0.05, Vector3(x * 1.4, 1.0, -0.45), DARK, Vector3(0, 0, 90), 12)
	Kit.cyl(g, 0.015, 1.5, Vector3(0, 1.0, -0.45), STEEL, Vector3(0, 0, 90), 6)
	return g



## The front of a neighbouring rowhouse, flat on the building line at v: the
## wall, a door, the windows, a cornice. `n` is the node to build it in (the
## street's). u0 is its left edge.
static func rowhouse(p: Node3D, n: Node3D, u0: float, v: float, look: Variant, boarded := false, lit := false, w := 5.0, h := 6.2) -> void:
	p.slab(n, true, v, u0, u0 + w, 0.0, h, 0.15, look)
	p.slab(n, true, v, u0, u0 + w, h, h + 0.3, 0.4, Color(0.3, 0.28, 0.27))
	var wood := Color(0.55, 0.42, 0.26)
	var glass: Variant = wood if boarded else Kit.flat(Color(0.95, 0.8, 0.5) if lit else Color(0.2, 0.24, 0.32), 0.45 if lit else 0.0)
	p.slab(n, true, v + 0.085, u0 + 0.55, u0 + 1.5, 0.0, 2.1, 0.03, wood.darkened(0.25) if boarded else Color(0.24, 0.3, 0.26))
	p.slab(n, true, v + 0.085, u0 + w - 2.4, u0 + w - 0.5, 0.9, 2.3, 0.03, glass)
	for uu: float in [u0 + 0.55, u0 + w - 1.95]:
		p.slab(n, true, v + 0.085, uu, uu + 1.4, 3.75, 5.05, 0.03, glass)
