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
const WalkLight := preload("res://scripts/walk_light.gd")

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
## A steel tanker desk: a lino top on a dark edge, a pedestal of drawers (two on
## a wide desk), each on a dark kick plate, and a modesty panel at the back.
## Its top is at 0.765.
static func desk(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := OFFICE, stuff := 1, with_chair := true, w := 1.5, d := 0.75) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var trim := look.darkened(0.42)
	var fronts := look.lightened(0.1)
	Kit.bevel(g, Vector3(w, 0.05, d), Vector3(0, 0.74, 0), look.lightened(0.26), 0.012)
	Kit.box(g, Vector3(w - 0.03, 0.03, d - 0.03), Vector3(0, 0.7, 0), trim)
	var ped := 0.44
	var px := w * 0.5 - ped * 0.5 - 0.02
	var both := w >= 1.45
	var zf := (d - 0.06) * 0.5            # the pedestals' fronts
	for x: float in ([px, -px] if both else [px]):
		Kit.box(g, Vector3(ped - 0.06, 0.07, d - 0.14), Vector3(x, 0.035, 0), trim)
		Kit.bevel_block(g, Vector3(ped, 0.62, d - 0.06), Vector3(x, 0.065, 0), look, 0.02)
		var rows: Array = [[0.08, 0.36], [0.38, 0.53], [0.55, 0.67]] if x > 0.0 else [[0.08, 0.53], [0.55, 0.67]]
		for r: Array in rows:
			var y0: float = r[0]
			var y1: float = r[1]
			Kit.bevel(g, Vector3(ped - 0.06, y1 - y0 - 0.02, 0.025), Vector3(x, (y0 + y1) * 0.5, zf + 0.009), fronts, 0.008)
			Kit.bevel(g, Vector3(0.16, 0.032, 0.03), Vector3(x, y1 - 0.06, zf + 0.03), STEEL, 0.008)
			if y1 - y0 > 0.3:      # a file drawer: a card in a holder
				Kit.box(g, Vector3(0.1, 0.05, 0.008), Vector3(x, y1 - 0.13, zf + 0.025), PAPER)
	if not both:
		Kit.bevel_block(g, Vector3(0.05, 0.685, d - 0.06), Vector3(-w * 0.5 + 0.045, 0, 0), look, 0.015)
	var x0 := -px + ped * 0.5 if both else -w * 0.5 + 0.07
	var x1 := px - ped * 0.5
	Kit.box(g, Vector3(x1 - x0, 0.4, 0.025), Vector3((x0 + x1) * 0.5, 0.485, -zf + 0.02), look.darkened(0.1))
	var top := 0.766
	var s := d / 0.75                     # things on top keep in from the edges of a shallow desk
	if stuff == 1:
		var body := Color(0.18, 0.44, 0.42)
		Kit.bevel_block(g, Vector3(0.38, 0.1, 0.3), Vector3(-0.22, top, -0.03 * s), body, 0.025)
		Kit.box(g, Vector3(0.3, 0.025, 0.1), Vector3(-0.22, top + 0.1, 0.07 * s), DARK, Vector3(14, 0, 0))
		Kit.cyl(g, 0.035, 0.44, Vector3(-0.22, top + 0.13, -0.15 * s), DARK, Vector3(0, 0, 90), 8)
		Kit.box(g, Vector3(0.25, 0.2, 0.008), Vector3(-0.22, top + 0.24, -0.17 * s), PAPER, Vector3(-14, 0, 0))
		_phone(g, Vector3(0.45, top, -0.14 * s), [DARK, Color(0.85, 0.2, 0.15), CREAM][int(rnd(u * 3.1 + v) * 3.0) % 3])
		Kit.box(g, Vector3(0.24, 0.012, 0.32), Vector3(0.16, top + 0.006, 0.13 * s), PAPER, Vector3(0, 14, 0))
		_pencils(g, Vector3(0.58, top, 0.14 * s))
	elif stuff == 2:
		var brass := Color(0.82, 0.62, 0.22)
		Kit.cyl(g, 0.08, 0.025, Vector3(-0.5, top + 0.0125, -0.18 * s), brass, Vector3.ZERO, 10)
		Kit.cyl(g, 0.014, 0.26, Vector3(-0.5, top + 0.15, -0.18 * s), brass, Vector3.ZERO, 6)
		Kit.prism(g, Vector3(0.15, 0.09, 0.34), Vector3(-0.5, top + 0.3, -0.16 * s), Kit.flat(Color(0.12, 0.58, 0.32), 0.4), Vector3(0, 90, 0))
		Kit.box(g, Vector3(0.3, 0.01, 0.11), Vector3(-0.5, top + 0.25, -0.16 * s), Kit.flat(Color(1.0, 0.92, 0.6), 1.2))
		Kit.box(g, Vector3(0.3, 0.025, 0.4), Vector3(0.0, top + 0.0125, 0.05 * s), PAPER, Vector3(0, -8, 0))
		Kit.box(g, Vector3(0.28, 0.03, 0.36), Vector3(0.42, top + 0.015, -0.04 * s), Color(0.92, 0.72, 0.3), Vector3(0, 10, 0))
		Kit.cyl(g, 0.042, 0.1, Vector3(0.18, top + 0.05, -0.22 * s), Color(0.95, 0.94, 0.9), Vector3.ZERO, 8)
		Kit.cyl(g, 0.043, 0.025, Vector3(0.18, top + 0.07, -0.22 * s), Color(0.85, 0.2, 0.15), Vector3.ZERO, 8)
	elif stuff == 3:
		var mz := -d * 0.5 + 0.29
		Kit.bevel_block(g, Vector3(0.4, 0.34, 0.36), Vector3(-0.25, top, mz), CREAM, 0.03)
		Kit.bevel_block(g, Vector3(0.3, 0.24, 0.16), Vector3(-0.25, top + 0.04, mz - 0.21), CREAM.darkened(0.08), 0.03)
		Kit.box(g, Vector3(0.3, 0.24, 0.01), Vector3(-0.25, top + 0.18, mz + 0.182), Kit.flat(Color(0.06, 0.2, 0.12), 0.4))
		for k in 3:
			Kit.box(g, Vector3(0.2 - 0.05 * k, 0.02, 0.004), Vector3(-0.29 + 0.025 * k, top + 0.25 - k * 0.045, mz + 0.189), Kit.flat(Color(0.4, 1.0, 0.5), 1.0))
		Kit.bevel_block(g, Vector3(0.44, 0.035, 0.16), Vector3(-0.25, top, d * 0.5 - 0.12), CREAM.darkened(0.06), 0.012)
		Kit.box(g, Vector3(0.38, 0.01, 0.1), Vector3(-0.25, top + 0.036, d * 0.5 - 0.12), Color(0.55, 0.55, 0.52))
		Kit.box(g, Vector3(0.24, 0.012, 0.32), Vector3(0.3, top + 0.006, 0.05 * s), PAPER, Vector3(0, -10, 0))
		_pencils(g, Vector3(0.52, top, -0.2 * s))
	if with_chair:
		var at := Vector2(u, v) + ahead(yaw, d * 0.5 + 0.32)
		chair(p, b, at.x, at.y, yaw + 180.0)
	return g


## A desk telephone: a body, the handset on its rest, a dial.
static func _phone(parent: Node3D, pos: Vector3, look: Color) -> void:
	Kit.bevel_block(parent, Vector3(0.2, 0.07, 0.17), pos, look, 0.02)
	Kit.bevel(parent, Vector3(0.24, 0.045, 0.06), pos + Vector3(0, 0.09, -0.04), look.darkened(0.15), 0.015)
	for x: float in [-0.1, 0.1]:
		Kit.cyl(parent, 0.032, 0.03, pos + Vector3(x, 0.075, -0.04), look.darkened(0.15), Vector3.ZERO, 8)
	Kit.cyl(parent, 0.045, 0.012, pos + Vector3(0, 0.073, 0.04), PAPER, Vector3.ZERO, 10)


## A mug of pencils.
static func _pencils(parent: Node3D, pos: Vector3) -> void:
	Kit.cyl(parent, 0.04, 0.1, pos + Vector3(0, 0.05, 0), Color(0.2, 0.4, 0.8), Vector3.ZERO, 8)
	for k in 3:
		Kit.tube(parent, pos + Vector3(-0.015 + k * 0.015, 0.06, 0.0), pos + Vector3(-0.04 + k * 0.04, 0.2, 0.01 * k), 0.007, Color(0.98, 0.78, 0.15), 4)


## A swivel chair on a five-star base: a fat seat cushion, a padded back on a stem.
static func chair(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.22, 0.32, 0.55), solid := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.44, 0.44, solid)
	chair_on(g, look)
	return g


## The swivel chair's parts, built in g (a set that is not a Place uses this).
static func chair_on(g: Node3D, look: Color) -> void:
	var dark := Color(0.12, 0.12, 0.14)
	for k in 5:
		var a := deg_to_rad(18.0 + k * 72.0)
		var tip := Vector3(sin(a), 0.0, cos(a)) * 0.19
		Kit.tube(g, Vector3(0, 0.08, 0), tip + Vector3(0, 0.05, 0), 0.02, dark, 5)
		Kit.ball(g, 0.032, tip + Vector3(0, 0.032, 0), dark, 6)
	Kit.cyl(g, 0.028, 0.34, Vector3(0, 0.25, 0), STEEL, Vector3.ZERO, 8)
	Kit.cyl(g, 0.06, 0.05, Vector3(0, 0.405, 0), dark, Vector3.ZERO, 8)
	Kit.bevel(g, Vector3(0.44, 0.09, 0.42), Vector3(0, 0.475, 0.01), look, 0.035)
	Kit.box(g, Vector3(0.07, 0.28, 0.03), Vector3(0, 0.62, -0.185), dark)
	Kit.bevel(g, Vector3(0.4, 0.36, 0.08), Vector3(0, 0.84, -0.19), look, 0.035, Vector3(-6, 0, 0))


## A bench of three slats on black iron ends (a third pair under a long one).
## back: two slats on posts behind the seat; arms: then armrests on the ends;
## frame: the ends' colour, when not black iron. The seat is at 0.47.
static func bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, look := WOOD, back := false, d := 0.5, arms := true, frame: Variant = null) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var iron: Color = frame if frame is Color else Color(0.16, 0.16, 0.19)
	var pitch := (d - 0.04) / 3.0
	for i in 3:
		Kit.bevel(g, Vector3(w, 0.05, pitch - 0.03), Vector3(0, 0.445, -d * 0.5 + 0.02 + (i + 0.5) * pitch), look, 0.012)
	var ends: Array[float] = [-w * 0.5 + 0.15, w * 0.5 - 0.15]
	if w > 2.4:
		ends.append(0.0)
	for x: float in ends:
		Kit.box(g, Vector3(0.06, 0.05, d - 0.06), Vector3(x, 0.395, 0), iron)
		Kit.box(g, Vector3(0.08, 0.04, d - 0.02), Vector3(x, 0.02, 0), iron)
		for z: float in [-d * 0.5 + 0.07, d * 0.5 - 0.07]:
			Kit.box(g, Vector3(0.05, 0.36, 0.05), Vector3(x, 0.2, z), iron)
		if back:
			Kit.tube(g, Vector3(x, 0.4, -d * 0.5 + 0.07), Vector3(x, 0.95, -d * 0.5 + 0.03), 0.028, iron, 4)
			if arms and x != 0.0:
				Kit.box(g, Vector3(0.05, 0.27, 0.05), Vector3(x, 0.555, d * 0.5 - 0.07), iron)
				Kit.bevel(g, Vector3(0.08, 0.05, d - 0.06), Vector3(x, 0.69, 0), look, 0.015)
	if back:
		for k in 2:
			Kit.bevel(g, Vector3(w, 0.13, 0.04), Vector3(0, 0.62 + k * 0.2, -d * 0.5 + 0.065 - k * 0.022), look, 0.012, Vector3(-10, 0, 0))
	return g


## A church-style bench: a slatted seat on wooden ends, a solid back with a
## capping rail, and closed ends with a rounded top at the back.
static func pew(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 4.0, look := WOOD_DARK) -> Node3D:
	var g := bench(p, b, u, v, yaw, w, look, false, 0.55, false, look.darkened(0.3))
	Kit.bevel(g, Vector3(w - 0.02, 0.46, 0.05), Vector3(0, 0.72, -0.215), look, 0.015, Vector3(-8, 0, 0))
	Kit.bevel(g, Vector3(w - 0.02, 0.05, 0.1), Vector3(0, 0.955, -0.2), look.lightened(0.1), 0.015)
	for x in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:      # the ends stand a little proud all round
		Kit.bevel_block(g, Vector3(0.07, 0.9, 0.59), Vector3(x, 0, 0), look.darkened(0.15), 0.02)
		Kit.cyl(g, 0.13, 0.07, Vector3(x, 0.9, -0.165), look.darkened(0.15), Vector3(0, 0, 90), 12)
	return g


## n filing cabinets side by side.
## n filing cabinets side by side: rounded steel cases, four drawers each with a
## pull and a card in a holder.
static func files(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 2, look := OFFICE, h := 1.32) -> Node3D:
	var w := 0.46 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	for i in n:
		var x := -w * 0.5 + 0.23 + i * 0.46
		Kit.bevel_block(g, Vector3(0.45, h, 0.6), Vector3(x, 0, 0), look.darkened(0.07 * (i % 2)), 0.02)
		for k in 4:
			var y := h / 8.0 + k * h / 4.0
			Kit.bevel(g, Vector3(0.39, h / 4.0 - 0.05, 0.02), Vector3(x, y, 0.305), look.lightened(0.1), 0.008)
			Kit.bevel(g, Vector3(0.14, 0.03, 0.03), Vector3(x, y + 0.04, 0.322), STEEL, 0.01)
			if h / 4.0 - 0.05 > 0.22:
				Kit.box(g, Vector3(0.08, 0.04, 0.006), Vector3(x, y + 0.1, 0.318), PAPER)
	return g


## Open shelving: steel corner posts, braced across the back and down the sides,
## five boards each with a lip along the front. stuff: "boxes", "books", "none",
## or shop stock: "goods", "bottles", "cans".
static func shelves(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, stuff := "boxes", look := IRON, h := 1.9, d := 0.45) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	for x in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		for z in [-d * 0.5 + 0.02, d * 0.5 - 0.02]:
			Kit.block(g, Vector3(0.04, h, 0.04), Vector3(x, 0, z), look)
		Kit.box(g, Vector3(0.012, sqrt(h * h + (d - 0.08) * (d - 0.08)) - 0.06, 0.025), Vector3(x, h * 0.5, 0), look.darkened(0.2), Vector3(rad_to_deg(atan2(d - 0.08, h)), 0, 0))
	var brace := rad_to_deg(atan2(h - 0.14, w - 0.08))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(sqrt((w - 0.08) * (w - 0.08) + (h - 0.14) * (h - 0.14)) - 0.06, 0.025, 0.01), Vector3(0, h * 0.5, -d * 0.5 + 0.012), look.darkened(0.2), Vector3(0, 0, s * brace))
	var rows := 5
	for i in rows:
		var y := 0.1 + i * (h - 0.14) / float(rows - 1)
		Kit.box(g, Vector3(w - 0.08, 0.03, d - 0.02), Vector3(0, y, 0), look.lightened(0.1))
		Kit.box(g, Vector3(w - 0.08, 0.035, 0.012), Vector3(0, y - 0.0075, d * 0.5 - 0.01), look.darkened(0.15))
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


## A shop or office counter: a bevelled top 6 cm thick, 3 cm over all round, on
## a framed body (posts and rails flush with the floor space, the panels between
## them 2 cm in) over a dark toe kick. The top is at h, the frame's front at d/2.
static func counter(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, d := 0.6, h := 1.05, look := WOOD, top := Color(0.82, 0.8, 0.74)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	counter_on(g, w, d, h, look, top)
	return g


## The counter's parts, built in g (a set that is not a Place uses this).
static func counter_on(g: Node3D, w: float, d: float, h: float, look: Color, top: Color) -> void:
	var y1 := h - 0.06                    # the underside of the top
	var frame := look.darkened(0.2)
	var post := 0.08
	var rail := 0.1
	Kit.box(g, Vector3(w - 0.1, 0.1, d - 0.1), Vector3(0, 0.05, 0), look.darkened(0.6))
	Kit.box(g, Vector3(w - 0.04, y1 - 0.12, d - 0.04), Vector3(0, 0.1 + (y1 - 0.12) * 0.5, 0), look)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(post, y1 - 0.1, post), Vector3(sx * (w - post) * 0.5, (0.1 + y1) * 0.5, sz * (d - post) * 0.5), frame)
		for y: float in [0.1 + rail * 0.5, y1 - rail * 0.5]:      # rails along the front and back, and across the ends
			Kit.box(g, Vector3(w - 2.0 * post, rail, 0.03), Vector3(0, y, sx * (d * 0.5 - 0.015)), frame)
			Kit.box(g, Vector3(0.03, rail, d - 2.0 * post), Vector3(sx * (w * 0.5 - 0.015), y, 0), frame)
	var n := maxi(int(round((w - 2.0 * post) / 0.9)), 1)
	var pw := (w - 2.0 * post) / n
	for i in range(1, n):
		for sz: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.06, y1 - 0.1 - 2.0 * rail, 0.03), Vector3(-w * 0.5 + post + i * pw, (0.1 + y1) * 0.5, sz * (d * 0.5 - 0.015)), frame)
	Kit.bevel(g, Vector3(w + 0.06, 0.06, d + 0.06), Vector3(0, h - 0.03, 0), top, 0.02)


## A table: a bevelled top exactly w x d with its top at h, a dark apron under
## it, and four square legs that taper to the floor.
static func table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, d := 0.8, look := WOOD, h := 0.74) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	table_on(g, w, d, look, h)
	return g


## The table's parts, built in g (a set that is not a Place uses this).
static func table_on(g: Node3D, w: float, d: float, look: Color, h: float) -> void:
	Kit.bevel(g, Vector3(w, 0.05, d), Vector3(0, h - 0.025, 0), look, 0.015)
	var dark := look.darkened(0.22)
	var leg := clampf(minf(w, d) * 0.09, 0.04, 0.07)      # the legs' width at the top
	var lx := w * 0.5 - leg * 0.5 - 0.05
	var lz := d * 0.5 - leg * 0.5 - 0.05
	var ap := clampf(h * 0.12, 0.05, 0.09)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(2.0 * lx, ap, 0.02), Vector3(0, h - 0.05 - ap * 0.5, s * lz), dark)
		Kit.box(g, Vector3(0.02, ap, 2.0 * lz), Vector3(s * lx, h - 0.05 - ap * 0.5, 0), dark)
	for x: float in [-lx, lx]:
		for z: float in [-lz, lz]:
			Kit.cyl(g, leg * 0.45, h - 0.05, Vector3(x, (h - 0.05) * 0.5, z), dark, Vector3(0, 45, 0), 4, leg * 0.72)


## A row of n steel lockers on a dark plinth: rounded doors with vents top and
## bottom and a lift handle; one or two padlocked.
static func lockers(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 4, look := Color(0.4, 0.46, 0.5)) -> Node3D:
	var w := 0.38 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.5)
	Kit.box(g, Vector3(w - 0.04, 0.08, 0.46), Vector3(0, 0.04, -0.01), DARK)
	for i in n:
		var x := -w * 0.5 + 0.19 + i * 0.38
		Kit.bevel_block(g, Vector3(0.375, 1.73, 0.5), Vector3(x, 0.08, 0), look.darkened(0.06 * (i % 2)), 0.015)
		Kit.bevel(g, Vector3(0.33, 1.62, 0.015), Vector3(x, 0.94, 0.255), look.lightened(0.08), 0.008)
		for k in 3:
			for y: float in [1.56, 0.3]:
				Kit.box(g, Vector3(0.18, 0.015, 0.01), Vector3(x, y + k * 0.05, 0.266), DARK)
		Kit.bevel(g, Vector3(0.035, 0.12, 0.03), Vector3(x + 0.12, 1.0, 0.272), STEEL, 0.01)
		if rnd(u * 3.7 + v * 1.3 + i * 5.1) < 0.35:
			Kit.box(g, Vector3(0.04, 0.045, 0.02), Vector3(x + 0.12, 0.91, 0.29), Color(0.85, 0.68, 0.25))
			Kit.ring(g, 0.016, 0.006, Vector3(x + 0.12, 0.945, 0.29), STEEL)
	Kit.bevel(g, Vector3(w + 0.02, 0.04, 0.52), Vector3(0, 1.83, 0), look.darkened(0.15), 0.01)     # its top at 1.85, as before
	return g


## A water cooler: a rounded cream cabinet, a dark recess with a red tap and a
## blue one over a drip tray, a tube of paper cups on its side, and the big blue
## bottle upside down on top.
static func cooler(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	Kit.bevel_block(g, Vector3(0.28, 0.95, 0.32), Vector3.ZERO, CREAM.lightened(0.2), 0.03)
	Kit.box(g, Vector3(0.18, 0.22, 0.008), Vector3(0, 0.7, 0.164), Color(0.3, 0.3, 0.33))
	Kit.box(g, Vector3(0.16, 0.025, 0.02), Vector3(0, 0.6, 0.17), STEEL)
	for t: Array in [[-0.04, Color(0.85, 0.18, 0.15)], [0.04, Color(0.2, 0.45, 0.9)]]:
		Kit.box(g, Vector3(0.03, 0.04, 0.02), Vector3(t[0], 0.76, 0.174), t[1])
	Kit.cyl(g, 0.025, 0.26, Vector3(0.155, 0.62, 0.06), PAPER, Vector3.ZERO, 8)
	Kit.cyl(g, 0.032, 0.03, Vector3(0.155, 0.475, 0.06), PAPER.darkened(0.08), Vector3.ZERO, 8, 0.026)
	var water := Color(0.45, 0.72, 0.98, 0.55)
	Kit.cyl(g, 0.05, 0.06, Vector3(0, 0.98, 0), water, Vector3.ZERO, 10)
	Kit.cyl(g, 0.13, 0.36, Vector3(0, 1.19, 0), water, Vector3.ZERO, 12)
	for y: float in [1.1, 1.28]:
		Kit.cyl(g, 0.136, 0.018, Vector3(0, y, 0), Color(0.35, 0.6, 0.92, 0.7), Vector3.ZERO, 12)
	return g


## A table with a coffee urn (lid, knob, handles, a tap and a sight glass), paper
## cups of coffee, and an open pink box of iced doughnuts.
static func coffee(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g := table(p, b, u, v, yaw, 1.2, 0.6, Color(0.6, 0.58, 0.52))
	Kit.cyl(g, 0.14, 0.04, Vector3(-0.32, 0.76, 0), DARK, Vector3.ZERO, 12)
	Kit.cyl(g, 0.12, 0.38, Vector3(-0.32, 0.97, 0), STEEL, Vector3.ZERO, 12)
	Kit.cyl(g, 0.126, 0.03, Vector3(-0.32, 1.165, 0), STEEL.darkened(0.2), Vector3.ZERO, 12)
	Kit.ball(g, 0.03, Vector3(-0.32, 1.19, 0), DARK, 8)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.03, 0.08, 0.03), Vector3(-0.32 + s * 0.135, 1.06, 0), DARK)
	Kit.box(g, Vector3(0.03, 0.22, 0.012), Vector3(-0.32, 1.0, 0.123), Color(0.4, 0.24, 0.12))
	Kit.box(g, Vector3(0.05, 0.04, 0.06), Vector3(-0.32, 0.84, 0.14), DARK)
	for i in 3:
		Kit.cyl(g, 0.04, 0.09, Vector3(0.0 + i * 0.11, 0.785, 0.12), PAPER, Vector3.ZERO, 8, 0.046)
		Kit.cyl(g, 0.04, 0.004, Vector3(0.0 + i * 0.11, 0.826, 0.12), Color(0.4, 0.22, 0.1), Vector3.ZERO, 8)
	Kit.cyl(g, 0.04, 0.2, Vector3(-0.08, 0.84, -0.17), PAPER, Vector3.ZERO, 8, 0.046)
	Kit.block(g, Vector3(0.36, 0.05, 0.26), Vector3(0.36, 0.74, -0.08), Color(0.95, 0.6, 0.7))
	Kit.box(g, Vector3(0.36, 0.26, 0.012), Vector3(0.36, 0.916, -0.244), Color(0.98, 0.7, 0.78), Vector3(-15, 0, 0))
	var icing := [Color(0.98, 0.5, 0.68), Color(0.42, 0.24, 0.13), Color(0.94, 0.74, 0.4), PAPER, Color(0.98, 0.85, 0.3), Color(0.42, 0.24, 0.13)]
	for r in 2:
		for c in 3:
			Kit.ring(g, 0.045, 0.02, Vector3(0.24 + c * 0.12, 0.8, -0.13 + r * 0.1), icing[r * 3 + c], Vector3(-90, 0, 0))
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


## Cardboard boxes, two side by side and more stacked on them: each taped
## across the top, some with a label.
static func boxes(p: Node3D, b: int, u: float, v: float, n := 4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 1.0, 0.6)
	for i in n:
		var col: Color = [Color(0.62, 0.48, 0.3), Color(0.7, 0.58, 0.38), Color(0.55, 0.42, 0.28)][i % 3]
		var x := -0.28 + 0.52 * (i % 2)
		var box := Kit.group(g, Vector3(x + 0.03 * (i / 2), 0.31 * (i / 2), 0), Vector3(0, 4.0 * i - 6.0, 0))
		Kit.bevel_block(box, Vector3(0.44, 0.3, 0.5), Vector3.ZERO, col, 0.012)
		Kit.box(box, Vector3(0.08, 0.004, 0.5), Vector3(0, 0.302, 0), Color(0.8, 0.7, 0.45))
		Kit.box(box, Vector3(0.08, 0.1, 0.004), Vector3(0, 0.25, 0.252), Color(0.8, 0.7, 0.45))
		if rnd(u * 2.3 + v + i * 4.1) < 0.6:
			Kit.box(box, Vector3(0.16, 0.09, 0.004), Vector3(0.12, 0.13, 0.252), PAPER)
			Kit.box(box, Vector3(0.11, 0.015, 0.003), Vector3(0.12, 0.14, 0.2545), DARK)
	return g


## A yellow mop bucket on castors, a wringer on its lip, the mop stood in it,
## and a puddle beside it.
static func bucket(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	var yellow := Color(0.95, 0.76, 0.12)
	for x: float in [-0.11, 0.11]:
		for z: float in [-0.11, 0.11]:
			Kit.ball(g, 0.025, Vector3(x, 0.025, z), DARK, 6)
	Kit.cyl(g, 0.15, 0.3, Vector3(0, 0.2, 0), yellow, Vector3.ZERO, 12, 0.18)
	Kit.cyl(g, 0.185, 0.025, Vector3(0, 0.345, 0), yellow.darkened(0.15), Vector3.ZERO, 12)
	Kit.cyl(g, 0.16, 0.01, Vector3(0, 0.33, 0), Color(0.45, 0.55, 0.5), Vector3.ZERO, 12)
	Kit.box(g, Vector3(0.14, 0.1, 0.12), Vector3(0.08, 0.39, 0), Color(0.3, 0.32, 0.36))
	var mop := Kit.group(g, Vector3(-0.05, 0.3, 0.0), Vector3(0, 0, 6))
	Kit.cyl(mop, 0.014, 1.0, Vector3(0, 0.5, 0), Color(0.55, 0.38, 0.2), Vector3.ZERO, 6)
	Kit.cyl(mop, 0.06, 0.12, Vector3(0, 0.0, 0), Color(0.82, 0.8, 0.74), Vector3.ZERO, 8, 0.03)
	Kit.cyl(g, 0.42, 0.006, Vector3(0.15, 0.004, 0.1), Color(0.2, 0.22, 0.24, 0.5), Vector3.ZERO, 12)
	return g


## A dying pot plant: a terracotta pot with a rim on a saucer, dry soil, limp
## stalks with yellowing leaves hanging off them, one leaf already on the floor.
static func plant(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.4, 0.4)
	var clay := Color(0.78, 0.42, 0.24)
	Kit.cyl(g, 0.19, 0.03, Vector3(0, 0.015, 0), clay.darkened(0.15), Vector3.ZERO, 12)
	Kit.cyl(g, 0.14, 0.3, Vector3(0, 0.18, 0), clay, Vector3.ZERO, 12, 0.17)
	Kit.cyl(g, 0.185, 0.06, Vector3(0, 0.33, 0), clay.lightened(0.08), Vector3.ZERO, 12)
	Kit.cyl(g, 0.165, 0.01, Vector3(0, 0.36, 0), Color(0.32, 0.22, 0.14), Vector3.ZERO, 12)
	for i in 5:
		var sh := 0.5 + 0.14 * rnd(i * 3.3)
		Kit.box(g, Vector3(0.03, sh, 0.03), Vector3(0.05 * (i - 2), 0.36 + sh * 0.45, 0.03 * (i % 2)), Color(0.45, 0.45, 0.2), Vector3(12.0 * (i - 2), 0, 9.0 * (i - 2)))
	var leaf := [Color(0.62, 0.62, 0.22), Color(0.72, 0.62, 0.25), Color(0.55, 0.55, 0.2), Color(0.66, 0.5, 0.22)]
	for i in 4:
		Kit.box(g, Vector3(0.18, 0.02, 0.08), Vector3(0.11 * (i - 1.5), 0.72 + 0.07 * (i % 2), 0.02), leaf[i], Vector3(0, 30.0 * i, 28))
	Kit.box(g, Vector3(0.14, 0.008, 0.07), Vector3(0.12, 0.004, 0.15), leaf[3].darkened(0.1), Vector3(0, 40, 0))
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
			else:      # a few lines of writing
				for r in 3:
					Kit.box(g, Vector3(pw * (0.7 - 0.15 * (r % 2)), 0.012, 0.003), at + Vector3(0, ph * (0.2 - r * 0.16), 0.0035), Color(0.35, 0.36, 0.42), tilt)
			Kit.ball(g, 0.014, at + Vector3(0, ph * 0.42, 0.008), [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2)][int(rnd(key + 7.0) * 3.0) % 3], 5)
	return g


## A poster or framed picture on a wall.
## A poster on a wall: its colour, a bold picture in a lighter panel (a sun
## over a stripe, three bars, or a diamond, by where it hangs), its words
## under it, masking tape on the top corners.
static func poster(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.6, h := 0.85, look := Color(0.8, 0.3, 0.25), text := "", y := 1.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.05, false)
	Kit.box(g, Vector3(w, h, 0.012), Vector3(0, y, 0.012), look)
	var py := y + h * 0.12
	var ph := h * 0.5
	var pw := w * 0.8
	Kit.box(g, Vector3(pw, ph, 0.004), Vector3(0, py, 0.02), look.lightened(0.35))
	var ink := look.darkened(0.45)
	var bright := Color(0.98, 0.82, 0.2) if look.h > 0.4 and look.h < 0.9 else Color(0.2, 0.32, 0.62)
	match int(rnd(u * 3.1 + v * 1.7) * 3.0) % 3:
		0:
			Kit.disc(g, minf(pw, ph) * 0.3, Vector3(0, py + ph * 0.1, 0.024), bright, 0.004, 14)
			Kit.box(g, Vector3(pw, ph * 0.18, 0.004), Vector3(0, py - ph * 0.32, 0.024), ink)
		1:
			for i in 3:
				Kit.box(g, Vector3(pw * 0.8, ph * 0.14, 0.004), Vector3(0, py + ph * 0.28 - i * ph * 0.28, 0.024), [ink, bright, ink][i])
		2:
			Kit.box(g, Vector3(minf(pw, ph) * 0.55, minf(pw, ph) * 0.55, 0.004), Vector3(0, py, 0.024), bright, Vector3(0, 0, 45))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.08, 0.03, 0.004), Vector3(s * w * 0.46, y + h * 0.47, 0.02), Color(0.92, 0.88, 0.68), Vector3(0, 0, -s * 40.0))
	if text != "":
		words(g, text, Vector3(0, y - h * 0.3, 0.024), minf(0.09, w / maxf(text.length(), 1.0) * 1.1), PAPER)
	return g


static func payphone(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.3, false)
	payphone_on(g)
	return g


## The pay phone's parts, built in g on a wall that faces +z: a blue shroud with
## a steel hood, the phone with its keypad and coin slot, the handset on its
## hook and its cord. (A set that is not a Place uses this.)
static func payphone_on(g: Node3D) -> void:
	var blue := Color(0.18, 0.36, 0.66)
	var body := Color(0.34, 0.36, 0.4)
	Kit.box(g, Vector3(0.48, 0.78, 0.03), Vector3(0, 1.34, 0.015), blue)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.03, 0.78, 0.28), Vector3(s * 0.225, 1.34, 0.14), blue)
	Kit.bevel(g, Vector3(0.54, 0.07, 0.32), Vector3(0, 1.765, 0.16), STEEL, 0.02)
	Kit.bevel(g, Vector3(0.26, 0.46, 0.12), Vector3(0.02, 1.3, 0.09), body, 0.03)
	for r in 4:
		for c in 3:
			Kit.box(g, Vector3(0.035, 0.03, 0.012), Vector3(-0.03 + c * 0.05, 1.42 - r * 0.045, 0.155), PAPER)
	Kit.box(g, Vector3(0.05, 0.012, 0.012), Vector3(0.1, 1.49, 0.155), DARK)
	Kit.box(g, Vector3(0.08, 0.05, 0.02), Vector3(0.05, 1.13, 0.155), DARK)
	Kit.bevel(g, Vector3(0.065, 0.26, 0.075), Vector3(-0.15, 1.36, 0.11), DARK, 0.025)
	Kit.tube(g, Vector3(-0.15, 1.23, 0.11), Vector3(-0.06, 1.1, 0.1), 0.01, DARK, 4)


## A schoolroom clock on a wall: a black rim, a white face with the hours
## marked, two hands and a red second hand.
static func clock(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 2.35) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.4, 0.05, false)
	Kit.disc(g, 0.2, Vector3(0, y, 0.015), DARK, 0.02, 16)
	Kit.disc(g, 0.17, Vector3(0, y, 0.022), PAPER, 0.02, 16)
	for k in 12:
		var a := k * TAU / 12.0
		var tick := Vector3(0.012, 0.035 if k % 3 == 0 else 0.018, 0.004)
		Kit.box(g, tick, Vector3(sin(a) * 0.145, y + cos(a) * 0.145, 0.034), DARK, Vector3(0, 0, -rad_to_deg(a)))
	Kit.box(g, Vector3(0.015, 0.13, 0.004), Vector3(0, y + 0.06, 0.036), DARK)
	Kit.box(g, Vector3(0.1, 0.015, 0.004), Vector3(0.045, y, 0.036), DARK)
	Kit.box(g, Vector3(0.006, 0.15, 0.003), Vector3(-0.03, y - 0.065, 0.0395), Color(0.85, 0.15, 0.12), Vector3(0, 0, -25))
	Kit.cyl(g, 0.014, 0.012, Vector3(0, y, 0.04), Color(0.85, 0.15, 0.12), Vector3(90, 0, 0), 8)
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

## The police station's drinks machine: switched off, with a note taped over it.
static func vending(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.95, 0.8)
	soda_on(g, 0.95, 0.8, 1.85, Color(0.55, 0.2, 0.18), false)
	Kit.box(g, Vector3(0.44, 0.26, 0.008), Vector3(-0.12, 1.2, 0.462), PAPER, Vector3(0, 0, 5))
	words(g, "OUT OF ORDER", Vector3(-0.12, 1.2, 0.468), 0.042, Color(0.7, 0.1, 0.1), 0.0).rotation_degrees.z = 5.0
	return g


## A drinks machine w x d, h tall, its front at +z: a big picture of a can on
## the left (lit from inside when `lit`; dark when switched off), a column of
## selection buttons over the coin slot and bill reader on the right, and the
## dispensing flap along the bottom. Built in g (a set that is not a Place uses
## this too). Its picture's front is d/2 + 0.052 out.
static func soda_on(g: Node3D, w: float, d: float, h: float, look: Color, lit := true) -> void:
	var zf := d * 0.5
	Kit.box(g, Vector3(w - 0.1, 0.08, d - 0.1), Vector3(0, 0.04, 0), DARK)
	Kit.bevel_block(g, Vector3(w, h - 0.08, d), Vector3(0, 0.08, 0), look, 0.05)
	var cw := 0.2                                   # the right-hand column
	var pw := w - cw - 0.16                         # the picture
	var px := -w * 0.5 + 0.06 + pw * 0.5
	var cx := w * 0.5 - 0.06 - cw * 0.5
	var y0 := 0.62
	var y1 := h - 0.14
	var py := (y0 + y1) * 0.5
	var ph := y1 - y0
	Kit.box(g, Vector3(pw + 0.06, ph + 0.06, 0.02), Vector3(px, py, zf + 0.01), DARK)
	Kit.box(g, Vector3(pw, ph, 0.02), Vector3(px, py, zf + 0.016), Kit.flat(Color(1.0, 0.88, 0.5), 1.1) if lit else Color(0.24, 0.2, 0.2))
	# The can: a fat body with steel rims, a white wave and a yellow one round it, bubbles.
	var can := look.lightened(0.08) if lit else look.darkened(0.35)
	var cwd := pw * 0.56
	var ch := ph * 0.66
	var cy := py - ph * 0.03
	Kit.box(g, Vector3(cwd, ch, 0.02), Vector3(px, cy, zf + 0.036), can)
	Kit.box(g, Vector3(cwd - 0.04, 0.045, 0.024), Vector3(px, cy + ch * 0.5 + 0.0225, zf + 0.036), STEEL if lit else IRON)
	Kit.box(g, Vector3(cwd - 0.04, 0.035, 0.024), Vector3(px, cy - ch * 0.5 - 0.0175, zf + 0.036), STEEL if lit else IRON)
	Kit.box(g, Vector3(cwd - 0.035, 0.08, 0.006), Vector3(px, cy + ch * 0.06, zf + 0.049), PAPER if lit else PAPER.darkened(0.5), Vector3(0, 0, 14))
	Kit.box(g, Vector3(cwd - 0.04, 0.026, 0.006), Vector3(px, cy - ch * 0.12, zf + 0.049), Color(1.0, 0.8, 0.15) if lit else Color(0.4, 0.33, 0.12), Vector3(0, 0, 14))
	if lit:
		for k in 4:
			var at := Vector2([-0.42, 0.4, -0.38, 0.44][k] * pw, [0.3, 0.22, -0.18, -0.3][k] * ph)
			Kit.disc(g, [0.03, 0.022, 0.018, 0.026][k], Vector3(px + at.x, py + at.y, zf + 0.03), PAPER, 0.006, 10)
	# The column: selection buttons, the coin slot, the bill reader, coin return.
	Kit.box(g, Vector3(cw, ph + 0.06, 0.016), Vector3(cx, py, zf + 0.008), look.darkened(0.3))
	var tints := [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.35, 0.8, 0.4), Color(1.0, 0.55, 0.15), Color(0.35, 0.5, 0.95)]
	for i in 5:
		var tint: Color = tints[i]
		Kit.box(g, Vector3(cw - 0.08, 0.075, 0.016), Vector3(cx, y1 - 0.08 - i * 0.115, zf + 0.024), Kit.flat(tint, 0.9) if lit else tint.darkened(0.55))
	Kit.bevel(g, Vector3(0.1, 0.14, 0.03), Vector3(cx, y0 + 0.3, zf + 0.02), STEEL, 0.01)
	Kit.box(g, Vector3(0.012, 0.06, 0.006), Vector3(cx, y0 + 0.3, zf + 0.037), DARK)
	Kit.box(g, Vector3(cw - 0.06, 0.06, 0.03), Vector3(cx, y0 + 0.13, zf + 0.023), DARK)
	Kit.box(g, Vector3(cw - 0.1, 0.012, 0.006), Vector3(cx, y0 + 0.13, zf + 0.041), Kit.flat(Color(0.3, 1.0, 0.45), 1.2) if lit else IRON)
	Kit.box(g, Vector3(0.09, 0.07, 0.02), Vector3(cx, 0.48, zf + 0.01), DARK)
	# The flap you reach in under.
	Kit.box(g, Vector3(pw, 0.24, 0.012), Vector3(px, 0.33, zf + 0.006), DARK)
	Kit.box(g, Vector3(pw - 0.06, 0.18, 0.02), Vector3(px, 0.34, zf + 0.026), STEEL, Vector3(-12, 0, 0))
	if lit:
		Kit.omni(g, Vector3(0, 1.2, zf + 0.26), Color(1.0, 0.85, 0.7), 0.5, 2.5)


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
	var red := Kit.flat(Color(0.95, 0.15, 0.12), 0.7)
	if van:
		Kit.bevel_block(g, Vector3(w, 1.55, l), Vector3(0, 0.32, 0), paint, 0.12)
		Kit.pane(Kit.box(g, Vector3(w - 0.3, 0.55, 0.02), Vector3(0, 1.45, l * 0.5 + 0.005), glass))
		_band(g, w, l, 0.75, 0.2, 0.13, Color(0.9, 0.45, 0.1) if amb else Color(0.9, 0.9, 0.86))
		Kit.box(g, Vector3(w * 0.42, 0.14, 0.02), Vector3(0, 0.52, l * 0.5 + 0.008), DARK)
		for side in [-1.0, 1.0]:
			words(g, "AMBULANCE" if amb else "POLICE", Vector3(side * (w * 0.5 + 0.012), 1.3, -0.3), 0.2 if amb else 0.3, Color(0.75, 0.12, 0.1) if amb else Color(0.92, 0.9, 0.8), 90.0 * side)
			Kit.pane(Kit.box(g, Vector3(0.02, 0.4, 0.7), Vector3(side * (w * 0.5 + 0.005), 1.42, 1.5), glass))
			Kit.box(g, Vector3(0.012, 1.0, 0.02), Vector3(side * (w * 0.5 + 0.004), 1.0, 0.95), paint.darkened(0.4))      # the side door's seam
		if amb:       # the light bars, and the back doors with their windows
			for z: float in [l * 0.5 - 0.5, -l * 0.5 + 0.3]:
				Kit.bevel(g, Vector3(w - 0.3, 0.12, 0.24), Vector3(0, 1.93, z), red, 0.04)
			for x: float in [-0.42, 0.42]:
				Kit.pane(Kit.box(g, Vector3(0.6, 0.45, 0.02), Vector3(x, 1.42, -l * 0.5 - 0.004), glass))
			Kit.box(g, Vector3(0.02, 1.3, 0.02), Vector3(0, 1.1, -l * 0.5 - 0.004), IRON)
			words(g, "AMBULANCE", Vector3(0, 1.0, -l * 0.5 - 0.02), 0.16, Color(0.75, 0.12, 0.1), 180.0)
		else:         # the police van's light bar
			Kit.bevel(g, Vector3(1.1, 0.05, 0.26), Vector3(0, 1.895, l * 0.5 - 0.6), IRON, 0.015)
			Kit.bevel(g, Vector3(0.5, 0.1, 0.24), Vector3(-0.27, 1.965, l * 0.5 - 0.6), red, 0.035)
			Kit.bevel(g, Vector3(0.5, 0.1, 0.24), Vector3(0.27, 1.965, l * 0.5 - 0.6), Kit.flat(Color(0.15, 0.3, 0.95), 0.7), 0.035)
	else:
		# A rounded body, a glasshouse with a raked windscreen and back window, a
		# roof over it, the stripe, and the light bar.
		var gz := -0.2
		var gw := w - 0.24
		Kit.bevel_block(g, Vector3(w, 0.56, l), Vector3(0, 0.28, 0), paint, 0.09)
		Kit.pane(Kit.box(g, Vector3(gw, 0.44, 1.2), Vector3(0, 1.06, gz), glass))
		Kit.pane(Kit.prism(g, Vector3(0.62, 0.44, gw), Vector3(0, 1.06, gz + 0.91), glass, Vector3(0, 90, 0), 1.0))
		Kit.pane(Kit.prism(g, Vector3(0.5, 0.44, gw), Vector3(0, 1.06, gz - 0.85), glass, Vector3(0, 90, 0), 0.0))
		Kit.bevel(g, Vector3(w - 0.2, 0.07, 1.3), Vector3(0, 1.31, gz), paint, 0.025)
		for side in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.02, 0.44, 0.12), Vector3(side * (gw * 0.5 + 0.008), 1.06, gz), paint)
		_band(g, w, l, 0.62, 0.16, 0.1, Color(0.16, 0.25, 0.5))
		Kit.box(g, Vector3(w * 0.4, 0.1, 0.02), Vector3(0, 0.47, l * 0.5 + 0.008), DARK)
		Kit.bevel(g, Vector3(1.2, 0.06, 0.28), Vector3(0, 1.375, gz), IRON, 0.02)
		Kit.bevel(g, Vector3(0.55, 0.13, 0.26), Vector3(-0.29, 1.47, gz), red, 0.04)
		Kit.bevel(g, Vector3(0.55, 0.13, 0.26), Vector3(0.29, 1.47, gz), Kit.flat(Color(0.15, 0.3, 0.95), 0.7), 0.04)
		for side in [-1.0, 1.0]:
			words(g, "POLICE", Vector3(side * (w * 0.5 + 0.022), 0.62, 0.2), 0.12, Color(0.95, 0.93, 0.85), 90.0 * side)
	for x in [-w * 0.5 + 0.06, w * 0.5 - 0.06]:
		for z in [-l * 0.5 + 0.85, l * 0.5 - 0.85]:
			Kit.cyl(g, 0.33, 0.24, Vector3(x, 0.33, z), Color(0.08, 0.08, 0.09), Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.17, 0.25, Vector3(x, 0.33, z), STEEL, Vector3(0, 0, 90), 8)
			Kit.cyl(g, 0.06, 0.26, Vector3(x, 0.33, z), IRON, Vector3(0, 0, 90), 6)
	for x in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		Kit.box(g, Vector3(0.3, 0.12, 0.02), Vector3(x, 0.68, l * 0.5 + 0.012), Kit.flat(Color(1.0, 0.95, 0.75), 0.8))
		Kit.box(g, Vector3(0.3, 0.12, 0.02), Vector3(x, 0.68, -l * 0.5 - 0.012), Kit.flat(Color(0.8, 0.12, 0.1), 0.5))
	Kit.bevel(g, Vector3(w + 0.06, 0.14, 0.1), Vector3(0, 0.4, l * 0.5 + 0.03), IRON, 0.035)
	Kit.bevel(g, Vector3(w + 0.06, 0.14, 0.1), Vector3(0, 0.4, -l * 0.5 - 0.03), IRON, 0.035)
	return g


## A painted band round a vehicle's rounded body at height y, `tall` high: a
## strip on each face that stops short of the corners by `corner`.
static func _band(g: Node3D, w: float, l: float, y: float, tall: float, corner: float, look: Color) -> void:
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.02, tall, l - 2.0 * corner), Vector3(s * (w * 0.5 + 0.005), y, 0), look)
		Kit.box(g, Vector3(w - 2.0 * corner, tall, 0.02), Vector3(0, y, s * (l * 0.5 + 0.005)), look)


# ------------------------------------------------------------------ courtroom

## A wooden front w wide from y0 to y1 with its face at z: a backing, pilasters
## at `xs`, and a raised panel between each pair (courtroom woodwork).
static func _panelled(g: Node3D, xs: Array, y0: float, y1: float, z: float, look: Color) -> void:
	for i in xs.size():
		var x: float = xs[i]
		Kit.box(g, Vector3(0.14, y1 - y0, 0.05), Vector3(x, (y0 + y1) * 0.5, z - 0.025), look.darkened(0.12))
		if i > 0:
			var x0: float = xs[i - 1] + 0.11
			var x1: float = x - 0.11
			Kit.box(g, Vector3(x1 - x0, (y1 - y0) * 0.6, 0.02), Vector3((x0 + x1) * 0.5, y0 + (y1 - y0) * 0.47, z - 0.03), look.lightened(0.08))


## The judge's bench: a raised platform; a panelled front with the seal on it,
## higher in the middle where the judge sits, under a moulded top; the high
## leather chair behind; gavel and lamp on the top; a flag at each end.
static func judge_bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 4.8, d := 1.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var zf := d * 0.5
	var gold := Color(0.78, 0.63, 0.25)
	var leather := Color(0.42, 0.12, 0.1)
	Kit.bevel_block(g, Vector3(w, 0.3, d), Vector3.ZERO, WOOD_DARK, 0.03)
	Kit.box(g, Vector3(w - 0.04, 1.1, 0.1), Vector3(0, 0.85, zf - 0.09), WOOD)       # its top inside the moulded top, not level with the pilasters'
	Kit.box(g, Vector3(1.8, 0.24, 0.1), Vector3(0, 1.5, zf - 0.09), WOOD)
	var xs: Array = [-w * 0.5 + 0.07, -0.97, 0.97, w * 0.5 - 0.07]
	if w * 0.5 - 1.04 > 1.0:
		xs.insert(1, -(w * 0.5 + 0.9) * 0.5)
		xs.insert(4, (w * 0.5 + 0.9) * 0.5)
	_panelled(g, xs, 0.3, 1.38, zf, WOOD)
	for x: float in [-0.97, 0.97]:
		Kit.box(g, Vector3(0.14, 0.24, 0.05), Vector3(x, 1.5, zf - 0.025), WOOD.darkened(0.12))
	Kit.bevel(g, Vector3(w + 0.06, 0.06, 0.6), Vector3(0, 1.41, zf - 0.28), WOOD_DARK, 0.02)
	Kit.bevel(g, Vector3(2.12, 0.06, 0.26), Vector3(0, 1.65, zf - 0.11), WOOD_DARK, 0.02)
	Kit.disc(g, 0.26, Vector3(0, 0.86, zf - 0.01), gold, 0.02, 16)
	Kit.disc(g, 0.19, Vector3(0, 0.86, zf - 0.004), Color(0.2, 0.25, 0.45), 0.02, 16)
	Kit.disc(g, 0.07, Vector3(0, 0.86, zf + 0.002), gold, 0.02, 10)
	Kit.box(g, Vector3(0.5, 0.1, 0.03), Vector3(0, 1.5, zf - 0.025), gold)
	# The chair: a tall buttoned back, arms, a pedestal.
	var cz := -zf + 0.5
	Kit.cyl(g, 0.2, 0.04, Vector3(0, 0.32, cz), DARK, Vector3.ZERO, 10)
	Kit.cyl(g, 0.04, 0.4, Vector3(0, 0.54, cz), STEEL, Vector3.ZERO, 8)
	Kit.bevel(g, Vector3(0.62, 0.13, 0.55), Vector3(0, 0.8, cz), leather, 0.04)
	Kit.bevel(g, Vector3(0.7, 1.05, 0.16), Vector3(0, 1.32, cz - 0.3), leather, 0.06, Vector3(-6, 0, 0))
	for r in 3:
		for c in 3:
			Kit.ball(g, 0.018, Vector3(-0.2 + c * 0.2, 1.08 + r * 0.25, cz - 0.222 - (r - 1) * 0.026), gold, 5)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(g, Vector3(0.1, 0.24, 0.48), Vector3(s * 0.36, 0.96, cz + 0.02), leather.darkened(0.15), 0.03)
	# On the top, either side of the raised middle: the gavel on its block, a
	# green-shaded lamp, a pile of files.
	var top := 1.44
	Kit.cyl(g, 0.08, 0.035, Vector3(1.25, top + 0.0175, zf - 0.3), WOOD_DARK, Vector3.ZERO, 10)
	Kit.cyl(g, 0.035, 0.15, Vector3(1.25, top + 0.075, zf - 0.28), WOOD, Vector3(0, 0, 90), 8)
	Kit.tube(g, Vector3(1.25, top + 0.075, zf - 0.28), Vector3(1.08, top + 0.03, zf - 0.17), 0.012, WOOD, 5)
	Kit.cyl(g, 0.07, 0.025, Vector3(-1.3, top + 0.0125, zf - 0.38), gold, Vector3.ZERO, 10)
	Kit.cyl(g, 0.012, 0.22, Vector3(-1.3, top + 0.12, zf - 0.38), gold, Vector3.ZERO, 6)
	Kit.prism(g, Vector3(0.14, 0.08, 0.32), Vector3(-1.3, top + 0.26, zf - 0.36), Kit.flat(Color(0.12, 0.58, 0.32), 0.4), Vector3(0, 90, 0))
	Kit.box(g, Vector3(0.28, 0.01, 0.1), Vector3(-1.3, top + 0.215, zf - 0.36), Kit.flat(Color(1.0, 0.92, 0.6), 1.2))
	for k in 3:
		Kit.box(g, Vector3(0.32, 0.03, 0.24), Vector3(1.75, top + 0.015 + k * 0.03, zf - 0.32), [Color(0.92, 0.72, 0.3), PAPER, Color(0.7, 0.75, 0.82)][k], Vector3(0, k * 7.0 - 5.0, 0))
	# The two flags stand on the platform, one at each end, behind the front.
	flag_on(g, Vector3(-w * 0.5 + 0.3, 0.3, -d * 0.5 + 0.3), Color(0.16, 0.2, 0.45), true, 5.0)
	flag_on(g, Vector3(w * 0.5 - 0.3, 0.3, -d * 0.5 + 0.3), Color(0.75, 0.6, 0.2), false, -5.0)
	return g


## The witness box: a low platform, a panelled front and sides under a capping
## rail, a padded seat, a microphone on a gooseneck and a glass of water.
static func witness_stand(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 1.0)
	Kit.bevel_block(g, Vector3(1.2, 0.15, 1.0), Vector3.ZERO, WOOD_DARK, 0.025)
	Kit.box(g, Vector3(1.04, 0.9, 0.06), Vector3(0, 0.6, 0.42), WOOD)
	_panelled(g, [-0.53, 0.53], 0.15, 1.05, 0.5, WOOD)
	for x: float in [-0.56, 0.56]:
		Kit.box(g, Vector3(0.08, 0.9, 0.91), Vector3(x, 0.6, -0.005), WOOD)
		Kit.bevel(g, Vector3(0.12, 0.05, 0.9), Vector3(x, 1.075, -0.04), WOOD_DARK, 0.015)
	Kit.bevel(g, Vector3(1.24, 0.06, 0.16), Vector3(0, 1.08, 0.42), WOOD_DARK, 0.02)
	Kit.bevel(g, Vector3(0.46, 0.08, 0.44), Vector3(0, 0.6, -0.15), VINYL, 0.03)
	Kit.bevel(g, Vector3(0.46, 0.5, 0.08), Vector3(0, 0.9, -0.38), VINYL, 0.03, Vector3(-6, 0, 0))
	Kit.cyl(g, 0.04, 0.02, Vector3(0.25, 1.12, 0.42), IRON, Vector3.ZERO, 8)
	Kit.tube(g, Vector3(0.25, 1.12, 0.42), Vector3(0.25, 1.3, 0.3), 0.009, IRON, 5)
	Kit.ball(g, 0.03, Vector3(0.25, 1.31, 0.28), DARK, 6)
	Kit.cyl(g, 0.03, 0.1, Vector3(-0.3, 1.16, 0.42), GLASS, Vector3.ZERO, 8)
	Kit.cyl(g, 0.026, 0.06, Vector3(-0.3, 1.14, 0.42), Color(0.55, 0.75, 0.9, 0.5), Vector3.ZERO, 8)
	return g


## Two rows of three seats behind a panelled rail; the back row sits higher.
static func jury_box(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.6, d := 1.55) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.bevel_block(g, Vector3(w, 0.15, d), Vector3.ZERO, WOOD_DARK, 0.025)
	Kit.bevel_block(g, Vector3(w - 0.02, 0.32, d * 0.5 - 0.02), Vector3(0, 0, -d * 0.25), WOOD_DARK.lightened(0.05), 0.025)
	Kit.box(g, Vector3(w - 0.16, 0.85, 0.06), Vector3(0, 0.575, d * 0.5 - 0.08), WOOD)
	var xs: Array = []
	var n := maxi(int(round((w - 0.14) / 0.9)), 1)
	for i in n + 1:
		xs.append(-w * 0.5 + 0.07 + i * (w - 0.14) / n)
	_panelled(g, xs, 0.15, 1.0, d * 0.5, WOOD)
	Kit.bevel(g, Vector3(w + 0.04, 0.06, 0.14), Vector3(0, 1.03, d * 0.5 - 0.06), WOOD_DARK, 0.02)
	for x in [-w * 0.5 + 0.04, w * 0.5 - 0.04]:
		Kit.box(g, Vector3(0.08, 0.85, d - 0.07), Vector3(x, 0.575, -0.015), WOOD)
		Kit.bevel(g, Vector3(0.12, 0.05, d - 0.06), Vector3(x, 1.025, -0.03), WOOD_DARK, 0.015)
	for row in 2:
		for i in 3:
			var base := Vector3(-w * 0.5 + 0.5 + i * (w - 1.0) * 0.5, 0.15 + 0.17 * row, 0.3 - 0.72 * row)
			Kit.bevel(g, Vector3(0.48, 0.09, 0.44), base + Vector3(0, 0.4, 0), VINYL, 0.03)
			Kit.bevel(g, Vector3(0.48, 0.5, 0.08), base + Vector3(0, 0.68, -0.2), VINYL, 0.03, Vector3(-6, 0, 0))
			Kit.cyl(g, 0.035, 0.36, base + Vector3(0, 0.18, -0.02), IRON, Vector3.ZERO, 6)
	return g


## A lectern: a panelled body on a dark plinth, a sloping top with a lip, and
## somebody's notes on it.
static func lectern(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.55, 0.45)
	Kit.bevel_block(g, Vector3(0.55, 0.1, 0.45), Vector3.ZERO, WOOD_DARK, 0.02)
	Kit.bevel_block(g, Vector3(0.48, 0.95, 0.38), Vector3(0, 0.1, 0), WOOD, 0.025)
	Kit.box(g, Vector3(0.32, 0.62, 0.02), Vector3(0, 0.55, 0.195), WOOD.lightened(0.08))
	var top := Kit.group(g, Vector3(0, 1.08, 0), Vector3(14, 0, 0))
	Kit.bevel(top, Vector3(0.56, 0.05, 0.46), Vector3.ZERO, WOOD_DARK, 0.015)
	Kit.box(top, Vector3(0.5, 0.04, 0.025), Vector3(0, 0.04, 0.2), WOOD_DARK)
	Kit.box(top, Vector3(0.22, 0.008, 0.3), Vector3(0.03, 0.03, -0.02), PAPER, Vector3(0, -6, 0))
	return g


## A walk-through metal detector: two posts and a beam. He walks between them,
## and the lamps on the posts, plain until then, blink green (walk_light.gd).
static func detector(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 1.3, 0.55, false)
	var grey := Color(0.72, 0.72, 0.7)
	var lamps: Node3D = WalkLight.new()
	lamps.zone = p.rect(u - 0.5, v - 0.3, u + 0.5, v + 0.3)
	g.add_child(lamps)
	p.watchers.append(lamps)
	for side in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.14, 2.05, 0.55), Vector3(side * 0.57, 0, 0), grey)
		lamps.add_lamp(Vector3(0.04, 0.3, 0.02), Vector3(side * 0.57, 1.5, 0.285))
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

## A fat sofa: a plinth on stubby feet, a cushion for each seat with a back
## cushion over it, and rolled arms. Seat at 0.49, arms 0.66, back 0.86.
static func couch(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.1, look := Color(0.45, 0.32, 0.2), d := 0.85) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	couch_on(g, w, look, d)
	return g


## The sofa's parts, built in g (a set that is not a Place uses this). `soft`
## colours the cushions when given.
static func couch_on(g: Node3D, w: float, look: Color, d: float, soft: Variant = null) -> void:
	var arm := clampf(w * 0.085, 0.15, 0.2)
	var pad: Color = soft if soft is Color else look.lightened(0.1)
	for x: float in [-w * 0.5 + 0.12, w * 0.5 - 0.12]:
		for z: float in [-d * 0.5 + 0.12, d * 0.5 - 0.12]:
			Kit.cyl(g, 0.03, 0.08, Vector3(x, 0.04, z), WOOD_DARK, Vector3.ZERO, 6, 0.042)
	Kit.bevel_block(g, Vector3(w - 0.06, 0.26, d - 0.04), Vector3(0, 0.08, 0), look.darkened(0.2), 0.04)
	Kit.bevel_block(g, Vector3(w - 2.0 * arm + 0.04, 0.6, 0.22), Vector3(0, 0.26, -d * 0.5 + 0.12), look, 0.06)
	for s: float in [-1.0, 1.0]:
		var x := s * (w - arm) * 0.5
		Kit.bevel_block(g, Vector3(arm, 0.5, d), Vector3(x, 0.08, 0), look, 0.05)
		Kit.cyl(g, arm * 0.58, d - 0.06, Vector3(x, 0.56, 0), look, Vector3(90, 0, 0), 10)
	var inner := w - 2.0 * arm
	var n := maxi(int(round(inner / 0.66)), 1)
	var cw := inner / n
	for i in n:
		var x := -inner * 0.5 + (i + 0.5) * cw
		Kit.bevel(g, Vector3(cw - 0.02, 0.15, d - 0.24), Vector3(x, 0.415, 0.11), pad, 0.05)
		Kit.bevel(g, Vector3(cw - 0.03, 0.38, 0.16), Vector3(x, 0.66, -d * 0.5 + 0.3), pad, 0.07, Vector3(-9, 0, 0))


## An old television on a stand.
## An old television on a stand: a cabinet with two doors, and the set on it in
## a fat wooden case, a dark bezel round the glowing screen, two knobs over a
## speaker grille, rabbit ears.
static func tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.9, 0.5)
	Kit.bevel_block(g, Vector3(0.9, 0.5, 0.45), Vector3.ZERO, WOOD_DARK, 0.02)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(g, Vector3(0.4, 0.36, 0.02), Vector3(s * 0.215, 0.26, 0.228), WOOD_DARK.lightened(0.1), 0.01)
		Kit.ball(g, 0.018, Vector3(s * 0.04, 0.3, 0.245), Color(0.8, 0.65, 0.3), 5)
	Kit.bevel_block(g, Vector3(0.72, 0.56, 0.46), Vector3(0, 0.5, 0), Color(0.36, 0.26, 0.18), 0.06)
	Kit.bevel(g, Vector3(0.54, 0.46, 0.02), Vector3(-0.08, 0.8, 0.228), DARK, 0.03)
	Kit.box(g, Vector3(0.46, 0.38, 0.01), Vector3(-0.08, 0.8, 0.24), Kit.flat(Color(0.5, 0.68, 0.8), 0.9))
	Kit.box(g, Vector3(0.1, 0.05, 0.004), Vector3(-0.2, 0.92, 0.247), Kit.flat(Color(0.85, 0.95, 1.0), 1.2))
	for y in [0.88, 0.76]:
		Kit.cyl(g, 0.035, 0.03, Vector3(0.26, y, 0.24), STEEL, Vector3(90, 0, 0), 8)
	for k in 4:
		Kit.box(g, Vector3(0.1, 0.012, 0.006), Vector3(0.26, 0.6 + k * 0.025, 0.232), DARK)
	Kit.ball(g, 0.04, Vector3(0, 1.06, -0.05), STEEL, 8)
	Kit.cyl(g, 0.006, 0.5, Vector3(-0.1, 1.3, -0.05), STEEL, Vector3(0, 0, 28), 4)
	Kit.cyl(g, 0.006, 0.5, Vector3(0.1, 1.3, -0.05), STEEL, Vector3(0, 0, -28), 4)
	return g


static func radiator(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.22)
	var n := maxi(int(w / 0.1), 2)
	for i in n:
		Kit.box(g, Vector3(0.07, 0.62, 0.18), Vector3(-w * 0.5 + (i + 0.5) * w / n, 0.4, 0), CREAM)
	Kit.box(g, Vector3(w, 0.04, 0.1), Vector3(0, 0.12, 0), CREAM.darkened(0.2))
	return g


## An electric range: an enamel body on a dark kick with its top at 0.9, four
## rings, a back panel with the knobs, an oven door with a window and a bar.
static func stove(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.76, 0.66)
	var enamel := Color(0.9, 0.88, 0.82)
	Kit.box(g, Vector3(0.7, 0.08, 0.6), Vector3(0, 0.04, 0), DARK)
	Kit.bevel_block(g, Vector3(0.76, 0.82, 0.66), Vector3(0, 0.08, 0), enamel, 0.025)
	Kit.bevel(g, Vector3(0.76, 0.2, 0.06), Vector3(0, 1.0, -0.3), enamel, 0.02)
	for k in 4:
		Kit.cyl(g, 0.022, 0.03, Vector3(-0.27 + k * 0.18, 1.0, -0.26), DARK, Vector3(90, 0, 0), 8)
	for x in [-0.19, 0.19]:
		for z in [-0.12, 0.17]:
			Kit.cyl(g, 0.09, 0.012, Vector3(x, 0.906, z), DARK, Vector3.ZERO, 12)
			Kit.cyl(g, 0.055, 0.014, Vector3(x, 0.907, z), Color(0.42, 0.38, 0.38), Vector3.ZERO, 10)
	Kit.bevel(g, Vector3(0.66, 0.5, 0.02), Vector3(0, 0.41, 0.335), enamel.darkened(0.06), 0.015)
	Kit.box(g, Vector3(0.42, 0.22, 0.01), Vector3(0, 0.4, 0.347), Color(0.16, 0.15, 0.15))
	Kit.tube(g, Vector3(-0.25, 0.6, 0.372), Vector3(0.25, 0.6, 0.372), 0.014, STEEL, 6)
	for x: float in [-0.25, 0.25]:
		Kit.box(g, Vector3(0.02, 0.02, 0.03), Vector3(x, 0.6, 0.357), STEEL)
	return g


## A fridge-freezer, its body's front at 0.35: rounded corners, the freezer door
## over the fridge door, long handles, a grille at the foot, a note on the door.
static func fridge(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.8, 0.72)
	var almond := Color(0.86, 0.83, 0.72)
	Kit.bevel_block(g, Vector3(0.8, 1.7, 0.7), Vector3.ZERO, almond, 0.05)
	Kit.box(g, Vector3(0.74, 0.015, 0.01), Vector3(0, 1.22, 0.354), DARK)
	Kit.box(g, Vector3(0.66, 0.07, 0.01), Vector3(0, 0.07, 0.354), DARK)
	for k in 3:
		Kit.box(g, Vector3(0.6, 0.008, 0.006), Vector3(0, 0.05 + k * 0.02, 0.36), almond.darkened(0.3))
	for y in [0.95, 1.45]:
		Kit.bevel(g, Vector3(0.035, 0.3, 0.045), Vector3(-0.32, y, 0.372), STEEL, 0.012)
	Kit.box(g, Vector3(0.16, 0.2, 0.006), Vector3(0.15, 0.9, 0.355), PAPER, Vector3(0, 0, 6))
	Kit.box(g, Vector3(0.04, 0.04, 0.008), Vector3(0.15, 0.99, 0.361), Color(0.9, 0.2, 0.2))
	Kit.box(g, Vector3(0.05, 0.035, 0.008), Vector3(0.2, 1.45, 0.356), Color(0.2, 0.6, 0.9))
	return g


## A kitchen worktop (its top at 0.9) with a steel sink in it, a gooseneck tap
## and a hot and a cold tap.
static func sink_unit(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6) -> Node3D:
	var g := counter(p, b, u, v, yaw, w, 0.62, 0.9, Color(0.72, 0.66, 0.52), Color(0.8, 0.8, 0.78))
	Kit.box(g, Vector3(0.56, 0.008, 0.44), Vector3(0, 0.904, 0.02), STEEL)
	Kit.box(g, Vector3(0.48, 0.008, 0.36), Vector3(0, 0.906, 0.02), IRON)
	Kit.cyl(g, 0.03, 0.012, Vector3(0, 0.911, 0.06), DARK, Vector3.ZERO, 8)
	Kit.cyl(g, 0.022, 0.06, Vector3(0, 0.93, -0.22), STEEL, Vector3.ZERO, 8)
	Kit.tube(g, Vector3(0, 0.96, -0.22), Vector3(0, 1.12, -0.2), 0.014, STEEL, 6)
	Kit.tube(g, Vector3(0, 1.12, -0.2), Vector3(0, 1.07, -0.08), 0.014, STEEL, 6)
	for x: float in [-0.13, 0.13]:
		Kit.cyl(g, 0.018, 0.05, Vector3(x, 0.925, -0.22), STEEL, Vector3.ZERO, 6)
		Kit.box(g, Vector3(0.06, 0.014, 0.014), Vector3(x, 0.955, -0.22), Color(0.85, 0.2, 0.15) if x > 0.0 else Color(0.2, 0.4, 0.85))
	return g


## The head is at the back of its floor space, the foot at the front: a wooden
## frame, a mattress, a quilt with the sheet turned down over it, a fat pillow,
## a panelled headboard between two posts.
static func bed(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, l := 2.0, cover := Color(0.25, 0.35, 0.6)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var head := WOOD_DARK.lightened(0.08)
	Kit.bevel_block(g, Vector3(w, 0.3, l), Vector3.ZERO, WOOD_DARK, 0.03)
	Kit.bevel(g, Vector3(w - 0.06, 0.2, l - 0.06), Vector3(0, 0.4, 0), Color(0.9, 0.89, 0.85), 0.05)
	var cz := l * 0.5 - l * 0.31 - 0.01
	Kit.bevel(g, Vector3(w - 0.02, 0.22, l * 0.62), Vector3(0, 0.41, cz), cover, 0.05)
	Kit.bevel(g, Vector3(w - 0.03, 0.05, 0.16), Vector3(0, 0.51, cz - l * 0.31 + 0.08), Color(0.95, 0.94, 0.9), 0.02)
	Kit.bevel(g, Vector3(w * 0.7, 0.14, 0.38), Vector3(0, 0.56, -l * 0.5 + 0.3), Color(0.93, 0.92, 0.88), 0.06)
	Kit.bevel_block(g, Vector3(w - 0.1, 0.85, 0.05), Vector3(0, 0.1, -l * 0.5 + 0.025), head, 0.015)
	Kit.box(g, Vector3(w - 0.36, 0.4, 0.02), Vector3(0, 0.66, -l * 0.5 + 0.055), head.lightened(0.08))
	for s: float in [-1.0, 1.0]:
		Kit.bevel_block(g, Vector3(0.09, 1.0, 0.09), Vector3(s * (w * 0.5 - 0.035), 0, -l * 0.5 + 0.045), WOOD_DARK, 0.02)
		Kit.ball(g, 0.055, Vector3(s * (w * 0.5 - 0.035), 1.03, -l * 0.5 + 0.045), head, 8)
	return g


## A chest of drawers w x d with its top at h: a dark plinth, two columns of
## three drawers with brass knobs, a top that overhangs a little.
static func dresser(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2, look := WOOD, h := 0.9, d := 0.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	Kit.box(g, Vector3(w - 0.06, 0.08, d - 0.06), Vector3(0, 0.04, 0), look.darkened(0.35))
	Kit.bevel_block(g, Vector3(w, h - 0.11, d), Vector3(0, 0.08, 0), look, 0.02)
	Kit.bevel(g, Vector3(w + 0.03, 0.03, d + 0.02), Vector3(0, h - 0.015, 0), look.darkened(0.12), 0.01)
	for row in 3:
		for col in 2:
			var at := Vector3((col - 0.5) * w * 0.5, 0.1 + (row + 0.5) * (h - 0.14) / 3.0, d * 0.5 + 0.01)
			Kit.bevel(g, Vector3(w * 0.5 - 0.06, (h - 0.14) / 3.0 - 0.05, 0.02), at, look.lightened(0.1), 0.01)
			Kit.ball(g, 0.022, at + Vector3(0, 0, 0.02), Color(0.8, 0.65, 0.3), 5)
	return g


## A dresser with a glass-fronted top for the good plates: two shelves of them
## behind the glass, a cornice over it.
static func cabinet(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6) -> Node3D:
	var g := dresser(p, b, u, v, yaw, w, WOOD_DARK, 0.85, 0.45)
	var inside := WOOD_DARK.lightened(0.12)
	Kit.box(g, Vector3(w - 0.08, 1.0, 0.03), Vector3(0, 1.35, -0.205), inside)
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.box(g, Vector3(0.04, 1.0, 0.34), Vector3(x, 1.35, -0.05), WOOD_DARK)
	for y: float in [1.12, 1.5]:
		Kit.box(g, Vector3(w - 0.08, 0.025, 0.28), Vector3(0, y, -0.06), inside)
	Kit.bevel(g, Vector3(w + 0.06, 0.08, 0.4), Vector3(0, 1.88, -0.04), WOOD_DARK.darkened(0.15), 0.02)
	for k in 2:
		for i in 3:
			Kit.disc(g, 0.11, Vector3(-w * 0.3 + i * w * 0.3, 1.25 + k * 0.38, -0.17), PAPER, 0.01, 10)
			Kit.disc(g, 0.07, Vector3(-w * 0.3 + i * w * 0.3, 1.25 + k * 0.38, -0.163), Color(0.35, 0.5, 0.75), 0.004, 10)
	Kit.box(g, Vector3(w - 0.08, 0.95, 0.01), Vector3(0, 1.345, 0.115), Color(0.75, 0.85, 0.88, 0.35))
	for x: float in [-w * 0.25, 0.0, w * 0.25]:
		Kit.box(g, Vector3(0.03, 0.95, 0.012), Vector3(x, 1.345, 0.126), WOOD_DARK)
	for y: float in [0.885, 1.81]:
		Kit.box(g, Vector3(w - 0.08, 0.05, 0.02), Vector3(0, y, 0.124), WOOD_DARK)
	return g


static func tub(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.72, 1.7)
	Kit.bevel_block(g, Vector3(0.72, 0.55, 1.7), Vector3.ZERO, Color(0.92, 0.92, 0.9), 0.05)
	Kit.box(g, Vector3(0.56, 0.02, 1.5), Vector3(0, 0.555, 0), Color(0.6, 0.75, 0.8))
	Kit.cyl(g, 0.015, 0.2, Vector3(0, 0.66, -0.78), STEEL, Vector3.ZERO, 6)
	Kit.tube(g, Vector3(0, 0.76, -0.78), Vector3(0, 0.73, -0.68), 0.015, STEEL, 6)
	for x: float in [-0.12, 0.12]:
		Kit.cyl(g, 0.025, 0.04, Vector3(x, 0.585, -0.79), STEEL, Vector3.ZERO, 8)
	return g


## The tank's top is at 0.75 (things stand on it), the closed lid at 0.43.
static func toilet(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.45, 0.66)
	var china := Color(0.93, 0.93, 0.9)
	Kit.bevel_block(g, Vector3(0.42, 0.75, 0.2), Vector3(0, 0, -0.22), china, 0.015)
	Kit.cyl(g, 0.19, 0.4, Vector3(0, 0.2, 0.08), china, Vector3.ZERO, 12, 0.21)
	Kit.cyl(g, 0.21, 0.025, Vector3(0, 0.4125, 0.08), china.darkened(0.08), Vector3.ZERO, 12)
	Kit.cyl(g, 0.195, 0.02, Vector3(0, 0.42, 0.085), china, Vector3.ZERO, 12)
	Kit.bevel(g, Vector3(0.08, 0.025, 0.03), Vector3(-0.13, 0.66, -0.105), STEEL, 0.008)
	return g


## A basin on a pedestal, a tap, and a mirror in a frame over it.
static func basin(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.44)
	var china := Color(0.93, 0.93, 0.9)
	Kit.cyl(g, 0.12, 0.04, Vector3(0, 0.02, -0.02), china, Vector3.ZERO, 10)
	Kit.cyl(g, 0.08, 0.75, Vector3(0, 0.375, -0.02), china, Vector3.ZERO, 10, 0.06)
	Kit.bevel(g, Vector3(0.55, 0.14, 0.42), Vector3(0, 0.82, 0), china, 0.04)
	Kit.box(g, Vector3(0.38, 0.02, 0.26), Vector3(0, 0.895, 0.03), Color(0.7, 0.8, 0.84))
	Kit.cyl(g, 0.02, 0.06, Vector3(0, 0.92, -0.15), STEEL, Vector3.ZERO, 6)
	Kit.tube(g, Vector3(0, 0.95, -0.15), Vector3(0, 0.94, -0.07), 0.012, STEEL, 5)
	Kit.box(g, Vector3(0.52, 0.66, 0.02), Vector3(0, 1.5, -0.21), Color(0.82, 0.68, 0.3))
	Kit.box(g, Vector3(0.46, 0.6, 0.012), Vector3(0, 1.5, -0.195), Color(0.7, 0.82, 0.88))
	Kit.box(g, Vector3(0.06, 0.4, 0.004), Vector3(-0.1, 1.52, -0.187), Color(0.92, 0.97, 1.0), Vector3(0, 0, -30))
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
## Galvanised dustbins with ribs, handles and domed lids, one lid knocked askew.
static func cans(p: Node3D, b: int, u: float, v: float, n := 2) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.52 * n, 0.5)
	var tin := Color(0.6, 0.64, 0.67)
	for i in n:
		var x := -0.26 * (n - 1) + i * 0.52
		Kit.cyl(g, 0.2, 0.7, Vector3(x, 0.35, 0), tin, Vector3.ZERO, 12, 0.225)
		for y: float in [0.2, 0.48]:
			Kit.cyl(g, 0.212 + 0.035 * y, 0.035, Vector3(x, y, 0), tin.darkened(0.2), Vector3.ZERO, 12)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.04, 0.035, 0.12), Vector3(x + s * 0.225, 0.6, 0), tin.darkened(0.35))
		var lid := Kit.group(g, Vector3(x, 0.72, 0), Vector3(9.0 if i % 2 == 1 else 0.0, 0, -7.0 if i % 2 == 1 else 0.0))
		Kit.cyl(lid, 0.245, 0.04, Vector3(0, 0, 0), tin.darkened(0.12), Vector3.ZERO, 12)
		Kit.cyl(lid, 0.235, 0.07, Vector3(0, 0.055, 0), tin.darkened(0.05), Vector3.ZERO, 12, 0.1)
		Kit.box(lid, Vector3(0.14, 0.035, 0.035), Vector3(0, 0.11, 0), tin.darkened(0.4))
	return g


## A boombox, to stand on something: give the group it stands in and where.
static func boombox(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.bevel_block(g, Vector3(0.62, 0.26, 0.16), Vector3.ZERO, Color(0.16, 0.16, 0.18), 0.03)
	Kit.box(g, Vector3(0.56, 0.2, 0.006), Vector3(0, 0.125, 0.083), Color(0.62, 0.64, 0.68))
	for x: float in [-0.185, 0.185]:
		Kit.disc(g, 0.09, Vector3(x, 0.12, 0.088), STEEL.lightened(0.2), 0.006, 16)
		Kit.disc(g, 0.075, Vector3(x, 0.12, 0.092), DARK, 0.006, 16)
		Kit.ball(g, 0.025, Vector3(x, 0.12, 0.094), Color(0.3, 0.3, 0.33), 8)
	Kit.box(g, Vector3(0.15, 0.09, 0.006), Vector3(0, 0.155, 0.088), DARK)
	for x: float in [-0.035, 0.035]:
		Kit.disc(g, 0.018, Vector3(x, 0.155, 0.093), PAPER, 0.004, 8)
	var levels := [Color(0.3, 0.9, 0.45), Color(0.3, 0.9, 0.45), Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.2)]
	for i in 5:
		var lh := 0.012 + 0.006 * i
		Kit.box(g, Vector3(0.018, lh, 0.004), Vector3(-0.05 + i * 0.025, 0.065 + lh * 0.5, 0.088), Kit.flat(levels[i], 0.9))
	var knobs := [Color(0.86, 0.2, 0.18), Color(0.98, 0.8, 0.2), Color(0.25, 0.65, 0.35), Color(0.2, 0.4, 0.85), PAPER]
	for i in 5:
		Kit.box(g, Vector3(0.035, 0.015, 0.03), Vector3(-0.1 + i * 0.05, 0.2675, 0.03), knobs[i])
	for x: float in [-0.22, 0.22]:
		Kit.box(g, Vector3(0.025, 0.06, 0.025), Vector3(x, 0.29, -0.03), STEEL)
	Kit.box(g, Vector3(0.47, 0.025, 0.03), Vector3(0, 0.325, -0.03), STEEL)
	Kit.tube(g, Vector3(0.24, 0.27, -0.065), Vector3(-0.18, 0.272, -0.07), 0.005, STEEL)
	Kit.ball(g, 0.008, Vector3(-0.18, 0.272, -0.07), STEEL, 6)
	return g


## A flat rug. People walk on it.
static func rug(p: Node3D, b: int, u: float, v: float, w := 2.0, d := 1.4, look := Color(0.5, 0.2, 0.2)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, w, d, false)
	Kit.box(g, Vector3(w, 0.012, d), Vector3(0, 0.007, 0), look)
	Kit.box(g, Vector3(w - 0.16, 0.012, d - 0.16), Vector3(0, 0.009, 0), look.darkened(0.3))
	Kit.box(g, Vector3(w - 0.3, 0.012, d - 0.3), Vector3(0, 0.011, 0), look.lightened(0.14))
	var m := minf(w, d) * 0.32
	Kit.box(g, Vector3(m, 0.012, m), Vector3(0, 0.0125, 0), look.darkened(0.12), Vector3(0, 45, 0))
	Kit.box(g, Vector3(m * 0.45, 0.012, m * 0.45), Vector3(0, 0.0135, 0), Color(0.92, 0.84, 0.6), Vector3(0, 45, 0))
	for s: float in [-1.0, 1.0]:      # the fringe on the ends
		Kit.box(g, Vector3(0.05, 0.008, d - 0.1), Vector3(s * (w * 0.5 + 0.02), 0.004, 0), Color(0.92, 0.88, 0.76))
	return g


# --------------------------------------------------------------------- street

## A cobra-head street lamp: a fluted foot, a tapering pole, an arm that curves
## out over the pavement to the right, the head with its glowing lens under it.
static func street_lamp(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3, 0.3)
	street_lamp_on(g)
	return g


## The street lamp's parts, built in g (a set that is not a Place uses this).
static func street_lamp_on(g: Node3D) -> void:
	var green := Color(0.14, 0.3, 0.24)
	Kit.cyl(g, 0.15, 0.08, Vector3(0, 0.04, 0), green.darkened(0.3), Vector3.ZERO, 8)
	Kit.cyl(g, 0.13, 0.6, Vector3(0, 0.38, 0), green, Vector3.ZERO, 8, 0.085)
	Kit.cyl(g, 0.1, 0.06, Vector3(0, 0.71, 0), green.darkened(0.3), Vector3.ZERO, 8)
	Kit.cyl(g, 0.065, 3.3, Vector3(0, 2.39, 0), green, Vector3.ZERO, 8, 0.045)
	Kit.tube(g, Vector3(0, 3.95, 0), Vector3(0.22, 4.2, 0), 0.045, green, 6)
	Kit.tube(g, Vector3(0.2, 4.19, 0), Vector3(0.72, 4.27, 0), 0.04, green, 6)
	Kit.bevel(g, Vector3(0.62, 0.15, 0.3), Vector3(0.92, 4.24, 0), green, 0.06, Vector3(0, 0, -6))
	Kit.bevel(g, Vector3(0.48, 0.05, 0.22), Vector3(0.94, 4.15, 0), Kit.flat(Color(1.0, 0.88, 0.55), 2.4), 0.02, Vector3(0, 0, -6))
	Kit.omni(g, Vector3(0.9, 3.6, 0), Color(1.0, 0.82, 0.5), 1.6, 9.0)


## A city litter bin: a green barrel with ribs, an open top with the rubbish
## showing, a dark foot.
static func bin(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.44, 0.44)
	bin_on(g)
	return g


## The litter bin's parts, built in g (a set that is not a Place uses this).
static func bin_on(g: Node3D) -> void:
	var green := Color(0.17, 0.4, 0.3)
	Kit.cyl(g, 0.17, 0.06, Vector3(0, 0.03, 0), DARK, Vector3.ZERO, 12)
	Kit.cyl(g, 0.19, 0.7, Vector3(0, 0.41, 0), green, Vector3.ZERO, 12, 0.215)
	for y: float in [0.24, 0.52]:
		Kit.cyl(g, 0.205 + 0.025 * y, 0.04, Vector3(0, y, 0), green.darkened(0.3), Vector3.ZERO, 12)
	Kit.cyl(g, 0.232, 0.06, Vector3(0, 0.77, 0), green.darkened(0.3), Vector3.ZERO, 12)
	Kit.cyl(g, 0.19, 0.01, Vector3(0, 0.79, 0), DARK, Vector3.ZERO, 12)
	Kit.ball(g, 0.075, Vector3(0.06, 0.8, 0.04), PAPER, 5)
	Kit.cyl(g, 0.04, 0.12, Vector3(-0.07, 0.83, -0.03), Color(0.9, 0.25, 0.2), Vector3(18, 0, 10), 8)


## A fire hydrant: a flanged foot, a fat barrel, a collar and a domed bonnet
## with its nut, a hose nozzle each side and the big pumper nozzle in front.
static func hydrant(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.3, 0.3)
	hydrant_on(g)
	return g


## The hydrant's parts, built in g (a set that is not a Place uses this).
static func hydrant_on(g: Node3D) -> void:
	var red := Color(0.88, 0.18, 0.13)
	var cap := Color(0.95, 0.78, 0.2)
	Kit.cyl(g, 0.145, 0.06, Vector3(0, 0.03, 0), red.darkened(0.25), Vector3.ZERO, 10)
	Kit.cyl(g, 0.105, 0.5, Vector3(0, 0.31, 0), red, Vector3.ZERO, 10, 0.095)
	Kit.cyl(g, 0.125, 0.05, Vector3(0, 0.575, 0), red.darkened(0.25), Vector3.ZERO, 10)
	Kit.cyl(g, 0.11, 0.1, Vector3(0, 0.65, 0), cap, Vector3.ZERO, 10, 0.055)
	Kit.cyl(g, 0.03, 0.05, Vector3(0, 0.72, 0), cap.darkened(0.2), Vector3.ZERO, 5)
	for s: float in [-1.0, 1.0]:
		Kit.cyl(g, 0.045, 0.07, Vector3(s * 0.12, 0.42, 0), red, Vector3(0, 0, 90), 8)
		Kit.cyl(g, 0.055, 0.025, Vector3(s * 0.16, 0.42, 0), cap, Vector3(0, 0, 90), 6)
	Kit.cyl(g, 0.06, 0.05, Vector3(0, 0.38, 0.115), red, Vector3(90, 0, 0), 8)
	Kit.cyl(g, 0.07, 0.03, Vector3(0, 0.38, 0.145), cap, Vector3(90, 0, 0), 6)


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


## Two-sided shop shelving, stocked on both faces. `w` is its length. Each end is
## an upright in the shop's colour with a sale star on a cream panel; the shelf
## edges carry yellow price strips; a capped spine runs along the top; the kick
## is set back in a darker shade.
static func gondola(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.6, kind := "goods", h := 1.3, d := 0.7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var metal := Color(0.9, 0.88, 0.8)
	var key := rnd(u * 2.3 + v * 1.1)
	var accent: Color = [Color(0.82, 0.18, 0.16), Color(0.13, 0.42, 0.66), Color(0.16, 0.52, 0.34)][int(key * 3.0) % 3]
	var strip := Color(0.99, 0.8, 0.16)
	Kit.block(g, Vector3(w - 0.12, 0.095, d - 0.12), Vector3.ZERO, accent.darkened(0.35))
	Kit.block(g, Vector3(w - 0.06, 0.025, d - 0.04), Vector3(0, 0.095, 0), metal)
	Kit.block(g, Vector3(w - 0.08, h - 0.19, 0.04), Vector3(0, 0.12, 0), metal.darkened(0.12))
	Kit.bevel_block(g, Vector3(w - 0.12, 0.07, 0.14), Vector3(0, h - 0.07, 0), accent, 0.02)
	for s: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.04, h, d - 0.02), Vector3(s * (w * 0.5 - 0.04), 0, 0), accent)
		var end := Kit.group(g, Vector3(s * (w * 0.5 - 0.02), 0, 0), Vector3(0, 90.0 * s, 0))
		Kit.box(end, Vector3(d - 0.16, h - 0.4, 0.004), Vector3(0, (h + 0.12) * 0.5, 0.002), metal)
		var sy := h * 0.62
		for turn: float in [0.0, 45.0]:
			Kit.box(end, Vector3(0.26, 0.26, 0.003), Vector3(0, sy, 0.0055 + turn * 0.00002), strip, Vector3(0, 0, turn))
		Kit.disc(end, 0.1, Vector3(0, sy, 0.01), Color(0.86, 0.14, 0.14), 0.004, 12)
		words(end, "SALE", Vector3(0, sy, 0.0135), 0.06, PAPER)
	var rows := 3
	var gap := (h - 0.16) / float(rows)
	for i in rows:
		var y := 0.12 + i * gap
		if i > 0:
			Kit.box(g, Vector3(w - 0.06, 0.025, d - 0.04), Vector3(0, y - 0.0125, 0), metal.lightened(0.04))
		for face: float in [1.0, -1.0]:
			Kit.box(g, Vector3(w - 0.12, 0.045, 0.012), Vector3(0, y - 0.02, face * (d * 0.5 - 0.014)), strip)
			stock(g, kind, -w * 0.5 + 0.06, w * 0.5 - 0.06, y, face * (d * 0.5 - 0.04), d * 0.5 - 0.08, u * 7.3 + v * 3.1 + i * 11.7 + face * 2.9, gap, face)
	return g


## n glass-door coolers in a row, lit inside and stocked ("cans" or "bottles").
static func fridge_case(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 3, kind := "cans", label := "COLD DRINKS", ink := Color(0.15, 0.3, 0.7)) -> Node3D:
	var w := 0.75 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.7)
	var shell := Color(0.9, 0.9, 0.88)
	var frame := Color(0.2, 0.21, 0.24)
	Kit.block(g, Vector3(w, 0.25, 0.7), Vector3.ZERO, DARK)
	Kit.box(g, Vector3(w - 0.4, 0.12, 0.008), Vector3(0, 0.125, 0.354), IRON)          # a grille in the kick
	for k in 3:
		Kit.box(g, Vector3(w - 0.48, 0.014, 0.004), Vector3(0, 0.09 + k * 0.035, 0.36), DARK)
	Kit.box(g, Vector3(w - 0.08, 1.48, 0.04), Vector3(0, 1.0, -0.33), Kit.flat(Color(0.82, 0.93, 1.0), 0.7))
	Kit.box(g, Vector3(w, 0.3, 0.7), Vector3(0, 1.9, 0), shell)
	Kit.box(g, Vector3(w - 0.06, 0.26, 0.008), Vector3(0, 1.9, 0.354), ink)            # the sign band: a rule in the ink colour
	Kit.box(g, Vector3(w - 0.16, 0.2, 0.008), Vector3(0, 1.9, 0.36), Kit.flat(Color(1.0, 0.98, 0.9), 0.55))
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.box(g, Vector3(0.04, 1.5, 0.7), Vector3(x, 1.0, 0), shell)
	for i in n:
		var x := -w * 0.5 + 0.375 + i * 0.75
		for k in 4:
			var y := 0.3 + k * 0.36
			Kit.box(g, Vector3(0.68, 0.02, 0.56), Vector3(x, y - 0.01, -0.03), STEEL)
			stock(g, kind, x - 0.32, x + 0.32, y, 0.24, 0.3, u * 5.3 + v * 2.1 + i * 13.1 + k * 3.7, 0.35)
		Kit.box(g, Vector3(0.68, 1.44, 0.02), Vector3(x, 1.0, 0.335), Color(0.7, 0.88, 0.95, 0.16))
		# The door: a dark frame, a chrome pull, a shine across the glass.
		for y: float in [0.305, 1.69]:
			Kit.box(g, Vector3(0.7, 0.07, 0.03), Vector3(x, y, 0.345), frame)
		for sx: float in [-0.32, 0.32]:
			Kit.box(g, Vector3(0.06, 1.315, 0.03), Vector3(x + sx, 0.9975, 0.345), frame)
		Kit.box(g, Vector3(0.03, 0.46, 0.02), Vector3(x + 0.32, 1.0, 0.37), STEEL)
		Kit.box(g, Vector3(0.07, 0.9, 0.004), Vector3(x - 0.08, 1.08, 0.349), Color(1, 1, 1, 0.3), Vector3(0, 0, -28))
		Kit.box(g, Vector3(0.025, 0.55, 0.004), Vector3(x + 0.06, 1.0, 0.349), Color(1, 1, 1, 0.3), Vector3(0, 0, -28))
		if i > 0:
			Kit.box(g, Vector3(0.04, 1.5, 0.05), Vector3(x - 0.375, 1.0, 0.33), shell)
	words(g, label, Vector3(0, 1.9, 0.368), 0.13, ink)
	return g


## A plexiglass screen standing on a counter: `w` long, from y0 up to y1, at z
## in the counter's group, with a slot in the middle to pass things through.
static func screen(g: Node3D, w: float, z: float, y0 := 1.05, y1 := 2.2, slot := 0.5) -> void:
	Kit.pane(Kit.box(g, Vector3(w, y1 - y0 - 0.26, 0.03), Vector3(0, (y0 + 0.26 + y1) * 0.5, z), PLEXI))      # combat: a shot breaks it
	var side := (w - slot) * 0.5
	for x: float in [-(slot + side) * 0.5, (slot + side) * 0.5]:
		Kit.pane(Kit.box(g, Vector3(side, 0.26, 0.03), Vector3(x, y0 + 0.13, z), PLEXI))
	var n := maxi(int(w / 1.2), 1)
	for i in n + 1:
		var x := -w * 0.5 + w * float(i) / float(n)
		if absf(x) > slot * 0.5 + 0.03:
			Kit.box(g, Vector3(0.04, y1 - y0 - 0.006, 0.05), Vector3(x, (y0 + y1) * 0.5 - 0.003, z), STEEL)
	Kit.box(g, Vector3(w + 0.04, 0.05, 0.06), Vector3(0, y1 + 0.015, z), STEEL)


## A cash register, to stand on a counter: give the group and where. A cash
## drawer, a sloped keyboard of fat keys facing the clerk (+z), a green read-out
## on a stalk for the customer, a roll of receipt paper.
static func till(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	var body := Color(0.32, 0.33, 0.37)
	var lit := Kit.flat(Color(0.3, 0.95, 0.5), 0.8)
	Kit.bevel_block(g, Vector3(0.4, 0.11, 0.38), Vector3.ZERO, DARK.lightened(0.1), 0.02)
	Kit.box(g, Vector3(0.24, 0.014, 0.01), Vector3(0, 0.06, 0.193), STEEL)
	var top := Kit.group(g, Vector3(0, 0.08, 0.03), Vector3(12, 0, 0))
	Kit.bevel_block(top, Vector3(0.38, 0.08, 0.3), Vector3.ZERO, body, 0.02)
	for r in 3:
		for c in 4:
			var tint := PAPER
			if c == 3:
				tint = [Color(0.86, 0.2, 0.18), Color(0.98, 0.8, 0.2), Color(0.25, 0.65, 0.35)][r]
			Kit.box(top, Vector3(0.055, 0.02, 0.055), Vector3(-0.105 + c * 0.07, 0.09, 0.08 - r * 0.07), tint)
	Kit.cyl(g, 0.018, 0.22, Vector3(0, 0.22, -0.15), body, Vector3.ZERO, 8)
	Kit.bevel(g, Vector3(0.2, 0.08, 0.05), Vector3(0, 0.37, -0.15), body, 0.015)
	for z: float in [-0.178, -0.122]:
		Kit.box(g, Vector3(0.16, 0.045, 0.006), Vector3(0, 0.37, z), lit)
	Kit.cyl(g, 0.035, 0.07, Vector3(0.14, 0.235, -0.1), PAPER, Vector3(0, 0, 90), 10)
	return g


## The lottery machine, to stand on a counter: a rounded blue box with a lit
## screen in a bezel and a slot for the slips, its sign on a red board on top,
## and a little stand of play slips beside it.
static func lotto(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.bevel_block(g, Vector3(0.3, 0.3, 0.26), Vector3.ZERO, Color(0.2, 0.3, 0.62), 0.03)
	Kit.box(g, Vector3(0.24, 0.17, 0.012), Vector3(0, 0.18, 0.131), DARK)
	Kit.box(g, Vector3(0.2, 0.13, 0.008), Vector3(0, 0.18, 0.139), Kit.flat(Color(0.5, 0.85, 1.0), 0.8))
	Kit.box(g, Vector3(0.18, 0.02, 0.016), Vector3(0, 0.06, 0.133), DARK)
	for x: float in [-0.12, 0.12]:
		Kit.block(g, Vector3(0.02, 0.06, 0.02), Vector3(x, 0.295, -0.02), STEEL)
	Kit.bevel(g, Vector3(0.36, 0.1, 0.03), Vector3(0, 0.4, -0.02), Color(0.8, 0.14, 0.14), 0.012)
	words(g, "LOTTERY", Vector3(0, 0.4, 0), 0.06, Color(0.98, 0.85, 0.3))
	words(g, "LOTTERY", Vector3(0, 0.4, -0.04), 0.06, Color(0.98, 0.85, 0.3), 180.0)
	Kit.block(g, Vector3(0.09, 0.08, 0.07), Vector3(0.23, 0, 0.06), Color(0.75, 0.88, 0.95, 0.5))
	var slips := [Color(0.98, 0.6, 0.72), Color(0.55, 0.78, 0.98), Color(0.98, 0.9, 0.45)]
	for i in 3:
		Kit.box(g, Vector3(0.07, 0.11, 0.004), Vector3(0.23, 0.07, 0.035 + i * 0.022), slips[i], Vector3(-8, 0, 0))
	return g


## A chest freezer with sliding glass lids: white walls round a frosty well of
## tubs and lollies that show through the glass, a steel rim, a coloured band
## with its words on the front, a dark kick.
static func chest_freezer(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.3, text := "ICE CREAM", band := Color(0.85, 0.2, 0.3)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.7)
	var white := Color(0.94, 0.94, 0.92)
	Kit.block(g, Vector3(w - 0.08, 0.08, 0.62), Vector3.ZERO, DARK)
	Kit.block(g, Vector3(w, 0.52, 0.7), Vector3(0, 0.08, 0), white)
	for z: float in [-0.32, 0.32]:
		Kit.block(g, Vector3(w, 0.18, 0.06), Vector3(0, 0.6, z), white)
		Kit.bevel(g, Vector3(w, 0.025, 0.06), Vector3(0, 0.7925, z), STEEL, 0.008)
	for x: float in [-w * 0.5 + 0.03, w * 0.5 - 0.03]:
		Kit.block(g, Vector3(0.06, 0.18, 0.58), Vector3(x, 0.6, 0), white)
		Kit.bevel(g, Vector3(0.06, 0.025, 0.58), Vector3(x, 0.7925, 0), STEEL, 0.008)
	Kit.block(g, Vector3(w - 0.12, 0.01, 0.58), Vector3(0, 0.6, 0), Color(0.78, 0.9, 0.98))
	var treats := [Color(0.98, 0.6, 0.72), Color(0.98, 0.86, 0.3), Color(0.6, 0.9, 0.75), Color(0.45, 0.28, 0.18), PAPER, Color(0.4, 0.62, 0.95)]
	var cols := int((w - 0.16) / 0.19)
	for r in 2:
		for c in cols:
			var k := rnd(u * 3.3 + v * 1.9 + r * 5.1 + c * 1.7)
			var x := -(cols - 1) * 0.095 + c * 0.19
			Kit.block(g, Vector3(0.16, 0.06 + 0.06 * rnd(k + 2.0), 0.22), Vector3(x, 0.61, -0.13 + r * 0.26), treats[int(k * 6.0) % 6])
	var glass := Color(0.7, 0.88, 0.96, 0.3)
	Kit.block(g, Vector3(w * 0.5 + 0.01, 0.015, 0.62), Vector3(-w * 0.25 + 0.045, 0.805, 0), glass)
	Kit.block(g, Vector3(w * 0.5 + 0.01, 0.015, 0.62), Vector3(w * 0.25 - 0.045, 0.82, 0), glass)
	Kit.block(g, Vector3(0.03, 0.015, 0.24), Vector3(-0.08, 0.82, 0), DARK)
	Kit.block(g, Vector3(0.03, 0.015, 0.24), Vector3(0.08, 0.835, 0), DARK)
	Kit.box(g, Vector3(w, 0.22, 0.012), Vector3(0, 0.55, 0.357), band)
	words(g, text, Vector3(0, 0.55, 0.366), 0.11, PAPER)
	return g


## The ice cabinet that stands outside a shop: a frosty white chest on a dark
## plinth, two panelled doors with chrome pulls, and a sky-blue sign ruled in
## dark blue with icicles hanging off it.
static func ice_box(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 0.7)
	var white := Color(0.93, 0.95, 0.97)
	var blue := Color(0.15, 0.35, 0.75)
	Kit.block(g, Vector3(1.14, 0.1, 0.64), Vector3.ZERO, DARK)
	Kit.bevel_block(g, Vector3(1.2, 1.5, 0.7), Vector3(0, 0.1, 0), white, 0.05)
	Kit.box(g, Vector3(1.04, 0.4, 0.01), Vector3(0, 1.34, 0.355), blue)
	Kit.box(g, Vector3(0.96, 0.32, 0.01), Vector3(0, 1.34, 0.362), Color(0.74, 0.89, 1.0))
	words(g, "ICE", Vector3(0, 1.32, 0.37), 0.34, blue)
	for i in 8:
		var ih := 0.06 + 0.07 * rnd(u + i * 2.7)
		Kit.prism(g, Vector3(0.07, ih, 0.02), Vector3(-0.455 + i * 0.13, 1.14 - ih * 0.5, 0.362), Color(0.8, 0.93, 1.0), Vector3(0, 0, 180))
	for x: float in [-0.29, 0.29]:
		Kit.box(g, Vector3(0.54, 0.83, 0.02), Vector3(x, 0.565, 0.36), Color(0.8, 0.85, 0.9))
		Kit.box(g, Vector3(0.44, 0.7, 0.006), Vector3(x, 0.565, 0.373), white)
		Kit.box(g, Vector3(0.04, 0.26, 0.025), Vector3(x * 0.28, 0.62, 0.3825), STEEL)
		for y: float in [0.25, 0.88]:
			Kit.box(g, Vector3(0.05, 0.08, 0.012), Vector3(x * 1.86, y, 0.376), STEEL)
	return g


## A cash machine: a rounded dark-blue cabinet on a plinth, a steel face with a
## lit screen in a bezel, a sloped keypad of fat keys, the card and cash slots,
## and its sign lit on a red panel at the top.
static func atm(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.5)
	Kit.block(g, Vector3(0.46, 0.08, 0.46), Vector3.ZERO, DARK)
	Kit.bevel_block(g, Vector3(0.5, 1.42, 0.5), Vector3(0, 0.08, 0), Color(0.18, 0.26, 0.42), 0.04)
	Kit.box(g, Vector3(0.4, 0.16, 0.012), Vector3(0, 1.38, 0.256), Kit.flat(Color(0.78, 0.15, 0.14), 0.3))
	words(g, "ATM", Vector3(0, 1.38, 0.264), 0.12, Color(0.98, 0.9, 0.4))
	Kit.box(g, Vector3(0.4, 0.64, 0.01), Vector3(0, 0.95, 0.255), STEEL)
	Kit.box(g, Vector3(0.32, 0.25, 0.01), Vector3(0, 1.12, 0.265), DARK)
	Kit.box(g, Vector3(0.26, 0.19, 0.006), Vector3(0, 1.12, 0.273), Kit.flat(Color(0.4, 0.8, 0.95), 0.8))
	var pad := Kit.group(g, Vector3(0, 0.86, 0.27), Vector3(-35, 0, 0))
	Kit.box(pad, Vector3(0.3, 0.16, 0.03), Vector3.ZERO, IRON)
	for r in 3:
		for c in 4:
			var tint := PAPER
			if c == 3:
				tint = [Color(0.86, 0.2, 0.18), Color(0.98, 0.8, 0.2), Color(0.25, 0.65, 0.35)][r]
			Kit.box(pad, Vector3(0.05, 0.032, 0.012), Vector3(-0.1 + c * 0.065, 0.045 - r * 0.045, 0.019), tint)
	Kit.box(g, Vector3(0.09, 0.04, 0.02), Vector3(0.14, 0.97, 0.27), DARK)
	Kit.box(g, Vector3(0.05, 0.008, 0.004), Vector3(0.14, 0.97, 0.282), Kit.flat(Color(0.3, 0.95, 0.5), 0.8))
	Kit.box(g, Vector3(0.24, 0.03, 0.012), Vector3(0, 0.7, 0.264), DARK)
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
			Kit.box(g, Vector3(0.4, 0.045, 0.006), Vector3(x, r * 0.255 + 0.2, 0.324), PAPER.darkened(0.04))     # a band across the top of the case
			for sx: float in [-1.0, 1.0]:
				Kit.box(g, Vector3(0.006, 0.04, 0.12), Vector3(x + sx * 0.203, r * 0.255 + 0.185, 0.165), DARK)   # its hand holes
	return g


# ------------------------------------------------------------------- hospital

## A hospital trolley bed. The head is at the back of its floor space.
static func gurney(p: Node3D, b: int, u: float, v: float, yaw := 0.0, sheet := Color(0.82, 0.9, 0.92), rails := true, w := 0.85, l := 2.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	for x: float in [-w * 0.5 + 0.07, w * 0.5 - 0.07]:
		for z: float in [-l * 0.5 + 0.18, l * 0.5 - 0.18]:
			Kit.cyl(g, 0.022, 0.42, Vector3(x, 0.33, z), STEEL, Vector3.ZERO, 8)
			Kit.box(g, Vector3(0.05, 0.05, 0.05), Vector3(x, 0.125, z), STEEL.darkened(0.2))
			Kit.cyl(g, 0.06, 0.04, Vector3(x, 0.06, z), DARK, Vector3(0, 0, 90), 10)
	Kit.box(g, Vector3(w - 0.1, 0.03, l - 0.4), Vector3(0, 0.215, 0), STEEL)
	Kit.box(g, Vector3(w, 0.05, l), Vector3(0, 0.565, 0), STEEL)
	Kit.bevel(g, Vector3(w - 0.06, 0.1, l - 0.06), Vector3(0, 0.64, 0), Color(0.22, 0.48, 0.6), 0.035)
	Kit.box(g, Vector3(w - 0.04, 0.03, l * 0.6), Vector3(0, 0.705, l * 0.2 - 0.04), sheet)
	Kit.box(g, Vector3(w - 0.035, 0.036, 0.1), Vector3(0, 0.708, -l * 0.1 + 0.01), PAPER)
	Kit.bevel(g, Vector3(w * 0.6, 0.09, 0.32), Vector3(0, 0.735, -l * 0.5 + 0.25), PAPER, 0.04)
	for x: float in [-w * 0.5 + 0.07, w * 0.5 - 0.07]:
		Kit.box(g, Vector3(0.03, 0.36, 0.03), Vector3(x, 0.77, -l * 0.5 + 0.02), STEEL)
	Kit.box(g, Vector3(w - 0.1, 0.03, 0.03), Vector3(0, 0.95, -l * 0.5 + 0.02), STEEL)
	if rails:
		for x: float in [-w * 0.5 + 0.016, w * 0.5 - 0.016]:
			Kit.box(g, Vector3(0.03, 0.035, l * 0.5), Vector3(x, 0.93, -l * 0.1), STEEL)
			for z: float in [-l * 0.35 + 0.01, l * 0.15 - 0.01]:
				Kit.box(g, Vector3(0.025, 0.33, 0.025), Vector3(x, 0.755, z), STEEL)
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
	for k in 5:
		var a := deg_to_rad(k * 72.0)
		var tip := Vector3(sin(a), 0, cos(a)) * 0.16
		Kit.tube(g, Vector3(0, 0.06, 0), tip + Vector3(0, 0.05, 0), 0.016, IRON)
		Kit.ball(g, 0.025, tip + Vector3(0, 0.025, 0), DARK, 6)
	Kit.cyl(g, 0.04, 0.04, Vector3(0, 0.06, 0), IRON, Vector3.ZERO, 8)
	Kit.cyl(g, 0.02, 1.16, Vector3(0, 0.64, 0), STEEL, Vector3.ZERO, 6)
	Kit.bevel_block(g, Vector3(0.36, 0.28, 0.24), Vector3(0, 1.22, 0), CREAM.lightened(0.15), 0.03)
	Kit.box(g, Vector3(0.3, 0.22, 0.008), Vector3(0, 1.37, 0.124), Color(0.2, 0.2, 0.22))
	Kit.box(g, Vector3(0.26, 0.17, 0.006), Vector3(0, 1.37, 0.13), Color(0.04, 0.1, 0.08))
	var trace := Kit.flat(Color(0.3, 1.0, 0.45), 1.2)
	var beat := [Vector2(-0.11, 0.0), Vector2(-0.04, 0.0), Vector2(-0.025, 0.055), Vector2(-0.005, -0.05), Vector2(0.012, 0.02), Vector2(0.025, 0.0), Vector2(0.11, 0.0)]
	for i in beat.size() - 1:
		Kit.tube(g, Vector3(beat[i].x, 1.37 + beat[i].y, 0.134), Vector3(beat[i + 1].x, 1.37 + beat[i + 1].y, 0.134), 0.004, trace, 4)
	Kit.box(g, Vector3(0.2, 0.025, 0.03), Vector3(0, 1.515, -0.04), STEEL)
	for x: float in [-0.09, 0.09]:
		Kit.box(g, Vector3(0.025, 0.02, 0.025), Vector3(x, 1.5, -0.04), STEEL)
	Kit.ball(g, 0.025, Vector3(0.12, 1.5, 0.06), Kit.flat(Color(1.0, 0.25, 0.2), 0.9), 8)
	return g


## A wheelchair: big wheels with chrome push rims, small castors in front, a
## blue padded seat and back, armrest pads, push handles with black grips, and
## footrests.
static func wheelchair(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.62, 0.8)
	var cloth := Color(0.18, 0.32, 0.62)
	Kit.bevel(g, Vector3(0.46, 0.06, 0.42), Vector3(0, 0.5, 0), cloth, 0.025)
	Kit.bevel(g, Vector3(0.46, 0.42, 0.05), Vector3(0, 0.75, -0.2), cloth, 0.025, Vector3(-6, 0, 0))
	for s: float in [-1.0, 1.0]:
		var x := s * 0.27
		Kit.cyl(g, 0.3, 0.04, Vector3(x, 0.3, -0.08), DARK, Vector3(0, 0, 90), 16)
		Kit.cyl(g, 0.24, 0.045, Vector3(x, 0.3, -0.08), STEEL, Vector3(0, 0, 90), 14)
		Kit.ball(g, 0.035, Vector3(x, 0.3, -0.08), STEEL.lightened(0.2), 8)
		Kit.ring(g, 0.26, 0.012, Vector3(s * 0.298, 0.3, -0.08), STEEL.lightened(0.25), Vector3(0, 90, 0))
		Kit.cyl(g, 0.08, 0.03, Vector3(x * 0.85, 0.08, 0.3), DARK, Vector3(0, 0, 90), 10)
		Kit.box(g, Vector3(0.025, 0.06, 0.05), Vector3(x * 0.85, 0.17, 0.3), STEEL)
		Kit.box(g, Vector3(0.03, 0.03, 0.46), Vector3(x * 0.9, 0.68, -0.01), STEEL)
		Kit.bevel(g, Vector3(0.05, 0.03, 0.3), Vector3(x * 0.9, 0.71, -0.01), DARK, 0.012)
		Kit.box(g, Vector3(0.03, 0.5, 0.03), Vector3(x * 0.85, 0.33, 0.22), STEEL)
		Kit.box(g, Vector3(0.16, 0.02, 0.12), Vector3(s * 0.1, 0.1, 0.34), IRON)
		Kit.box(g, Vector3(0.03, 0.03, 0.1), Vector3(s * 0.22, 0.98, -0.27), STEEL)
		Kit.box(g, Vector3(0.036, 0.036, 0.07), Vector3(s * 0.22, 0.98, -0.345), DARK)
	Kit.box(g, Vector3(0.5, 0.03, 0.03), Vector3(0, 0.98, -0.24), STEEL)
	return g


## n plastic seats joined on a beam, as in a waiting room.
static func seats(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 4, look := Color(0.2, 0.45, 0.6)) -> Node3D:
	var w := 0.52 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.55)
	Kit.box(g, Vector3(w - 0.04, 0.05, 0.08), Vector3(0, 0.37, 0), STEEL)
	for x: float in [-w * 0.5 + 0.12, w * 0.5 - 0.12]:
		Kit.box(g, Vector3(0.05, 0.32, 0.05), Vector3(x, 0.185, 0), STEEL)
		Kit.box(g, Vector3(0.07, 0.025, 0.5), Vector3(x, 0.0125, 0), IRON)
	for i in n:
		var x := -w * 0.5 + 0.26 + i * 0.52
		Kit.bevel(g, Vector3(0.46, 0.06, 0.44), Vector3(x, 0.43, 0.03), look, 0.025)
		Kit.bevel(g, Vector3(0.46, 0.4, 0.05), Vector3(x, 0.7, -0.2), look, 0.02, Vector3(-8, 0, 0))
		Kit.box(g, Vector3(0.06, 0.04, 0.3), Vector3(x, 0.4, -0.02), IRON)
		if i > 0:      # a steel arm between each pair
			var ax := x - 0.26
			Kit.box(g, Vector3(0.025, 0.22, 0.025), Vector3(ax, 0.51, 0.12), STEEL)
			Kit.bevel(g, Vector3(0.05, 0.03, 0.3), Vector3(ax, 0.63, 0.04), DARK, 0.01)
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
		var green := Color(0.18, 0.55, 0.32)
		Kit.cyl(g, 0.125, 0.04, Vector3(x, 0.02, 0), DARK, Vector3.ZERO, 12)
		Kit.cyl(g, 0.11, 1.08, Vector3(x, 0.58, 0), green, Vector3.ZERO, 12)
		Kit.ball(g, 0.11, Vector3(x, 1.12, 0), green, 12)
		Kit.cyl(g, 0.114, 0.16, Vector3(x, 0.72, 0), PAPER, Vector3.ZERO, 12)
		Kit.cyl(g, 0.035, 0.1, Vector3(x, 1.26, 0), STEEL, Vector3.ZERO, 8)
		Kit.disc(g, 0.04, Vector3(x, 1.27, 0.045), STEEL, 0.015, 10)
		Kit.disc(g, 0.032, Vector3(x, 1.27, 0.054), PAPER, 0.004, 10)
		Kit.box(g, Vector3(0.004, 0.026, 0.002), Vector3(x + 0.006, 1.275, 0.057), Color(0.8, 0.15, 0.12), Vector3(0, 0, -30))
	return g


## A television on a bracket high on a wall.
static func wall_tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 2.15) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.4, false)
	Kit.box(g, Vector3(0.2, 0.2, 0.02), Vector3(0, y, 0.01), IRON)
	Kit.box(g, Vector3(0.06, 0.06, 0.3), Vector3(0, y, 0.15), IRON)
	Kit.bevel(g, Vector3(0.66, 0.5, 0.4), Vector3(0, y, 0.42), Color(0.2, 0.2, 0.22), 0.05)
	Kit.bevel(g, Vector3(0.56, 0.42, 0.02), Vector3(0, y + 0.01, 0.618), Color(0.12, 0.12, 0.13), 0.02)
	Kit.box(g, Vector3(0.5, 0.36, 0.01), Vector3(0, y + 0.01, 0.63), Kit.flat(Color(0.5, 0.68, 0.8), 0.9))
	Kit.box(g, Vector3(0.1, 0.05, 0.004), Vector3(-0.14, y + 0.13, 0.637), Kit.flat(Color(0.85, 0.95, 1.0), 1.2))
	Kit.box(g, Vector3(0.012, 0.012, 0.006), Vector3(0.24, y - 0.21, 0.623), Kit.flat(Color(1.0, 0.3, 0.2), 1.5))
	return g


# ------------------------------------------------------------ more of the home

## A dining chair on four legs.
static func seat(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := WOOD, pad := VINYL) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.44, 0.44)
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.18, 0.18]:
			Kit.cyl(g, 0.024, 0.44, Vector3(x, 0.22, z), look, Vector3.ZERO, 6, 0.02)
		Kit.box(g, Vector3(0.04, 0.5, 0.04), Vector3(x, 0.74, -0.18), look)
		Kit.box(g, Vector3(0.02, 0.03, 0.34), Vector3(x, 0.16, 0), look.darkened(0.2))
	Kit.box(g, Vector3(0.4, 0.06, 0.4), Vector3(0, 0.41, 0), look.darkened(0.15))
	Kit.bevel(g, Vector3(0.43, 0.06, 0.42), Vector3(0, 0.465, 0.005), pad, 0.025)
	Kit.bevel(g, Vector3(0.42, 0.14, 0.04), Vector3(0, 0.88, -0.18), look, 0.015)
	Kit.box(g, Vector3(0.32, 0.03, 0.025), Vector3(0, 0.66, -0.18), look)
	return g


## A big projection television with a video recorder on top.
static func big_tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 0.6)
	Kit.bevel_block(g, Vector3(1.5, 1.25, 0.6), Vector3.ZERO, Color(0.12, 0.12, 0.14), 0.04)
	Kit.bevel(g, Vector3(1.38, 0.94, 0.02), Vector3(0, 0.74, 0.303), Color(0.06, 0.06, 0.07), 0.02)
	Kit.box(g, Vector3(1.3, 0.86, 0.02), Vector3(0, 0.74, 0.315), Kit.flat(Color(0.45, 0.62, 0.85), 0.9))
	Kit.box(g, Vector3(0.3, 0.12, 0.004), Vector3(-0.42, 1.0, 0.327), Kit.flat(Color(0.8, 0.92, 1.0), 1.1), Vector3(0, 0, 8))
	Kit.box(g, Vector3(1.3, 0.14, 0.02), Vector3(0, 0.16, 0.305), Color(0.22, 0.22, 0.25))
	for k in 5:
		Kit.box(g, Vector3(1.2, 0.012, 0.006), Vector3(0, 0.11 + k * 0.025, 0.317), Color(0.08, 0.08, 0.09))
	Kit.box(g, Vector3(0.02, 0.02, 0.006), Vector3(0.62, 0.16, 0.318), Kit.flat(Color(1.0, 0.3, 0.2), 1.5))
	Kit.block(g, Vector3(0.44, 0.09, 0.3), Vector3(-0.3, 1.25, 0), Color(0.25, 0.25, 0.28))
	Kit.box(g, Vector3(0.1, 0.02, 0.01), Vector3(-0.3, 1.3, 0.154), Kit.flat(Color(0.3, 0.95, 0.5), 1.0))
	for k in 3:
		Kit.block(g, Vector3(0.2, 0.03, 0.12), Vector3(0.35, 1.25 + k * 0.031, 0.02 * k), Color(0.15, 0.15, 0.17).lightened(0.12 * k))
	return g


## A loudspeaker cabinet: rounded, a lighter baffle, a big woofer in a chrome
## ring with a dust cap, a tweeter over it, a port slot at the foot.
static func speaker(p: Node3D, b: int, u: float, v: float, yaw := 0.0, h := 1.1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.45, 0.4)
	Kit.bevel_block(g, Vector3(0.45, h, 0.4), Vector3.ZERO, Color(0.14, 0.13, 0.13), 0.03)
	Kit.box(g, Vector3(0.39, h - 0.08, 0.01), Vector3(0, h * 0.5, 0.205), Color(0.22, 0.21, 0.23))
	for drv: Array in [[0.18, h * 0.34], [0.075, h * 0.74]]:
		var r: float = drv[0]
		var y: float = drv[1]
		Kit.disc(g, r, Vector3(0, y, 0.214), STEEL, 0.008, 16)
		Kit.disc(g, r * 0.84, Vector3(0, y, 0.219), DARK, 0.006, 16)
		Kit.ball(g, r * 0.3, Vector3(0, y, 0.222), Color(0.3, 0.3, 0.33), 8)
	Kit.box(g, Vector3(0.24, 0.04, 0.006), Vector3(0, 0.07, 0.213), DARK)
	return g


## An electric keyboard on its X stand: a rounded black case with a red stripe,
## three octaves of keys (the black ones in twos and threes), a panel of lit
## buttons, a green read-out and two knobs.
static func keyboard(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.3, 0.4)
	for x: float in [-0.45, 0.45]:
		Kit.box(g, Vector3(0.03, 0.92, 0.03), Vector3(x, 0.42, 0), IRON, Vector3(24, 0, 0))
		Kit.box(g, Vector3(0.03, 0.92, 0.03), Vector3(x, 0.42, 0), IRON, Vector3(-24, 0, 0))
		for z: float in [-0.18, 0.18]:
			Kit.block(g, Vector3(0.05, 0.03, 0.04), Vector3(x, 0, z), DARK)
	Kit.bevel(g, Vector3(1.3, 0.08, 0.36), Vector3(0, 0.86, 0), Color(0.12, 0.12, 0.14), 0.025)
	Kit.box(g, Vector3(1.24, 0.016, 0.006), Vector3(0, 0.855, 0.181), Color(0.85, 0.16, 0.14))
	Kit.box(g, Vector3(1.2, 0.014, 0.16), Vector3(0, 0.907, 0.08), PAPER)
	var ww := 1.2 / 21.0
	for o in 3:
		for i: int in [0, 1, 3, 4, 5]:
			Kit.box(g, Vector3(0.03, 0.016, 0.09), Vector3(-0.6 + (o * 7 + i + 1) * ww, 0.92, 0.045), DARK)
	Kit.box(g, Vector3(0.6, 0.008, 0.1), Vector3(-0.25, 0.904, -0.1), Color(0.2, 0.38, 0.5))
	for i in 5:
		Kit.box(g, Vector3(0.05, 0.014, 0.035), Vector3(-0.47 + i * 0.075, 0.913, -0.1), Kit.flat([Color(1.0, 0.3, 0.2), Color(1.0, 0.8, 0.2), Color(0.3, 0.9, 0.5)][i % 3], 0.9))
	Kit.box(g, Vector3(0.2, 0.01, 0.07), Vector3(0.18, 0.905, -0.1), Kit.flat(Color(0.5, 0.95, 0.6), 0.8))
	for x: float in [0.4, 0.5]:
		Kit.cyl(g, 0.025, 0.03, Vector3(x, 0.915, -0.1), STEEL, Vector3.ZERO, 10)
	return g


## n milk crates of records in a row: each crate has a lip and rows of hand
## holes, the sleeves lean this way and that, and a record peeks out of each.
static func crates(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 2) -> Node3D:
	var w := 0.38 * n
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.36)
	for i in n:
		var x := -w * 0.5 + 0.19 + i * 0.38
		var look: Color = [Color(0.7, 0.15, 0.15), Color(0.15, 0.3, 0.65), Color(0.2, 0.5, 0.3), Color(0.85, 0.5, 0.1)][i % 4]
		var hole := look.darkened(0.5)
		Kit.block(g, Vector3(0.36, 0.3, 0.34), Vector3(x, 0, 0), look)
		Kit.block(g, Vector3(0.364, 0.035, 0.344), Vector3(x, 0.27, 0), look.lightened(0.12))
		for y: float in [0.09, 0.2]:
			for hx: float in [-0.1, 0.0, 0.1]:
				for s: float in [-1.0, 1.0]:
					Kit.box(g, Vector3(0.07, 0.07, 0.006), Vector3(x + hx, y, s * 0.173), hole)
			for s: float in [-1.0, 1.0]:
				if (s < 0.0 and i == 0) or (s > 0.0 and i == n - 1):
					for hz: float in [-0.09, 0.0, 0.09]:
						Kit.box(g, Vector3(0.006, 0.07, 0.07), Vector3(x + s * 0.183, y, hz), hole)
		for k in 9:
			var lean := (rnd(u + i * 3.1 + k * 1.3) - 0.5) * 10.0
			var sh := 0.29 + 0.04 * rnd(v + i * 2.3 + k * 1.7)
			Kit.box(g, Vector3(0.028, sh, 0.3), Vector3(x - 0.14 + k * 0.035, 0.05 + sh * 0.5, 0), GOODS[(k + i * 3) % GOODS.size()], Vector3(0, 0, lean))
		Kit.cyl(g, 0.12, 0.008, Vector3(x + 0.0175, 0.25, 0), DARK, Vector3(0, 0, 90), 14)
	return g


## A framed gold record, on a wall: a gold frame round a black field, the disc
## with a groove ring and a red label, a gold plaque under it.
static func gold_record(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 1.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.05, false)
	var gold := Color(0.95, 0.75, 0.22)
	Kit.bevel(g, Vector3(0.48, 0.58, 0.03), Vector3(0, y, 0.015), Color(0.75, 0.58, 0.18), 0.012)
	Kit.box(g, Vector3(0.4, 0.5, 0.006), Vector3(0, y, 0.033), Color(0.08, 0.08, 0.1))
	Kit.disc(g, 0.17, Vector3(0, y + 0.06, 0.04), gold, 0.008, 18)
	Kit.ring(g, 0.115, 0.008, Vector3(0, y + 0.06, 0.045), gold.darkened(0.25))
	Kit.disc(g, 0.055, Vector3(0, y + 0.06, 0.046), Color(0.8, 0.15, 0.12), 0.006, 12)
	Kit.disc(g, 0.01, Vector3(0, y + 0.06, 0.05), PAPER, 0.004, 6)
	Kit.box(g, Vector3(0.22, 0.06, 0.008), Vector3(0, y - 0.19, 0.041), gold)
	Kit.box(g, Vector3(0.16, 0.012, 0.004), Vector3(0, y - 0.19, 0.046), Color(0.3, 0.22, 0.08))
	return g


## A fish tank on a cupboard: dark rims and corner posts, bright gravel, weed, a
## castle, orange fish and a string of bubbles, lit from the hood.
static func aquarium(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.45)
	Kit.bevel_block(g, Vector3(w, 0.7, 0.45), Vector3.ZERO, WOOD_DARK, 0.02)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w * 0.5 - 0.08, 0.5, 0.012), Vector3(s * w * 0.25, 0.35, 0.231), WOOD_DARK.lightened(0.1))
		Kit.ball(g, 0.02, Vector3(s * 0.06, 0.4, 0.25), Color(0.85, 0.66, 0.28), 6)
	Kit.block(g, Vector3(w, 0.04, 0.42), Vector3(0, 0.7, 0), DARK)
	Kit.block(g, Vector3(w - 0.06, 0.05, 0.38), Vector3(0, 0.74, 0), Color(0.95, 0.55, 0.7))
	Kit.box(g, Vector3(w - 0.04, 0.4, 0.4), Vector3(0, 0.94, 0), Color(0.3, 0.62, 0.85, 0.35))
	Kit.box(g, Vector3(w - 0.06, 0.02, 0.38), Vector3(0, 1.15, 0), Kit.flat(Color(0.7, 0.95, 1.0), 1.0))
	Kit.block(g, Vector3(w, 0.04, 0.42), Vector3(0, 1.16, 0), DARK)
	Kit.bevel_block(g, Vector3(w, 0.06, 0.45), Vector3(0, 1.2, 0), DARK, 0.02)
	for x: float in [-w * 0.5 + 0.015, w * 0.5 - 0.015]:
		for z: float in [-0.195, 0.195]:
			Kit.block(g, Vector3(0.03, 0.42, 0.03), Vector3(x, 0.74, z), DARK)
	var pebbles := [Color(0.3, 0.55, 0.95), Color(0.98, 0.86, 0.3), PAPER]
	for i in 6:
		Kit.ball(g, 0.022, Vector3(-w * 0.4 + i * w * 0.16, 0.79, 0.12 - 0.07 * (i % 3)), pebbles[i % 3], 6)
	for i in 5:
		var wh := 0.18 + 0.12 * rnd(u + i * 1.9)
		Kit.prism(g, Vector3(0.07, wh, 0.02), Vector3(-w * 0.42 + i * w * 0.19, 0.79 + wh * 0.5, -0.12 + 0.05 * (i % 2)), Color(0.2, 0.7, 0.3).lightened(0.1 * (i % 2)), Vector3(0, 35.0 * i, 0))
	var cx := w * 0.25
	Kit.block(g, Vector3(0.14, 0.12, 0.1), Vector3(cx, 0.79, -0.05), Color(0.6, 0.6, 0.66))
	Kit.block(g, Vector3(0.06, 0.22, 0.06), Vector3(cx + 0.05, 0.79, -0.05), Color(0.66, 0.66, 0.72))
	Kit.box(g, Vector3(0.04, 0.06, 0.006), Vector3(cx - 0.02, 0.82, 0.003), DARK)
	var fish := [[-w * 0.3, 0.9, 0.05, 1.0], [-w * 0.05, 1.02, -0.06, -1.0], [w * 0.1, 0.94, 0.09, -1.0], [w * 0.36, 1.06, 0.0, 1.0]]
	for i in fish.size():
		var f: Array = fish[i]
		var tint := Kit.flat(Color(1.0, 0.55, 0.1) if i % 2 == 0 else Color(1.0, 0.85, 0.2), 0.6)
		Kit.box(g, Vector3(0.08, 0.045, 0.025), Vector3(f[0], f[1], f[2]), tint)
		Kit.prism(g, Vector3(0.05, 0.035, 0.02), Vector3(f[0] - f[3] * 0.055, f[1], f[2]), tint, Vector3(0, 0, 90.0 * f[3]))
	for i in 5:
		Kit.ball(g, 0.012 + 0.003 * i, Vector3(-w * 0.38 + 0.01 * (i % 2), 0.83 + i * 0.065, -0.1), Color(0.9, 0.97, 1.0, 0.6), 6)
	return g


## A wardrobe: a dark plinth, a rounded carcass under a cornice, two doors with
## raised panels and brass knobs.
static func wardrobe(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.2, look := WOOD_DARK) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.6)
	Kit.block(g, Vector3(w - 0.04, 0.08, 0.56), Vector3.ZERO, look.darkened(0.3))
	Kit.bevel_block(g, Vector3(w, 1.86, 0.6), Vector3(0, 0.08, 0), look, 0.02)
	Kit.bevel_block(g, Vector3(w, 0.06, 0.6), Vector3(0, 1.94, 0), look.darkened(0.15), 0.02)
	for s: float in [-1.0, 1.0]:
		var x := s * w * 0.25
		Kit.box(g, Vector3(w * 0.5 - 0.04, 1.72, 0.02), Vector3(x, 1.02, 0.31), look.lightened(0.06))
		for py: Array in [[1.4, 0.8], [0.52, 0.56]]:
			Kit.box(g, Vector3(w * 0.5 - 0.16, py[1], 0.012), Vector3(x, py[0], 0.326), look.lightened(0.14))
		Kit.ball(g, 0.025, Vector3(s * 0.05, 1.0, 0.335), Color(0.85, 0.66, 0.28), 6)
	return g


## A bank of letter boxes, on a wall: a dark frame of brass doors, each with a
## slot, a lock and a blank name card.
static func mailboxes(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.2, 0.1, false)
	var brass := Color(0.86, 0.68, 0.3)
	Kit.bevel(g, Vector3(1.24, 0.66, 0.08), Vector3(0, 1.35, 0.04), IRON, 0.015)
	for r in 2:
		for c in 5:
			var x := -0.48 + c * 0.24
			var y := 1.2 + r * 0.3
			Kit.box(g, Vector3(0.21, 0.27, 0.012), Vector3(x, y, 0.086), brass)
			Kit.box(g, Vector3(0.12, 0.018, 0.006), Vector3(x, y + 0.07, 0.095), DARK)
			Kit.box(g, Vector3(0.09, 0.04, 0.004), Vector3(x, y - 0.06, 0.094), PAPER)
			Kit.ball(g, 0.012, Vector3(x + 0.07, y - 0.02, 0.096), DARK, 5)
	return g


## A safe: dark green on stubby feet, its door picked out with a gold pinstripe,
## a big chrome dial and a three-spoked handle, hinges down the left.
static func safe(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.6, 0.55)
	var green := Color(0.16, 0.3, 0.22)
	var gold := Color(0.92, 0.74, 0.28)
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.21, 0.21]:
			Kit.block(g, Vector3(0.08, 0.05, 0.08), Vector3(x, 0, z), DARK)
	Kit.bevel_block(g, Vector3(0.6, 0.7, 0.55), Vector3(0, 0.05, 0), green, 0.04)
	Kit.box(g, Vector3(0.48, 0.56, 0.012), Vector3(0, 0.4, 0.281), green.lightened(0.08))
	for y: float in [0.16, 0.64]:
		Kit.box(g, Vector3(0.4, 0.012, 0.004), Vector3(0, y, 0.289), gold)
	for x: float in [-0.2, 0.2]:
		Kit.box(g, Vector3(0.012, 0.468, 0.004), Vector3(x, 0.4, 0.289), gold)
	for y: float in [0.25, 0.55]:
		Kit.box(g, Vector3(0.03, 0.08, 0.02), Vector3(-0.25, y, 0.285), STEEL)
	Kit.disc(g, 0.085, Vector3(-0.05, 0.44, 0.295), STEEL, 0.016, 16)
	Kit.disc(g, 0.065, Vector3(-0.05, 0.44, 0.306), PAPER, 0.006, 16)
	Kit.box(g, Vector3(0.012, 0.03, 0.004), Vector3(-0.05, 0.49, 0.311), Color(0.8, 0.15, 0.12))
	Kit.ball(g, 0.025, Vector3(-0.05, 0.44, 0.31), DARK, 8)
	var hub := Vector3(0.15, 0.4, 0.31)
	Kit.disc(g, 0.03, Vector3(0.15, 0.4, 0.3), STEEL, 0.03, 10)
	for k in 3:
		var a := deg_to_rad(90.0 + k * 120.0)
		var tip := hub + Vector3(cos(a), sin(a), 0) * 0.09
		Kit.tube(g, hub, tip, 0.011, STEEL)
		Kit.ball(g, 0.018, tip, STEEL, 8)
	return g


## A weights bench: a padded red bench on T feet, uprights with hooks, and a
## loaded bar on its rests (big black plates with red ones inside them, collars).
static func weights(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.5, 1.3)
	var red := Color(0.78, 0.16, 0.14)
	Kit.bevel(g, Vector3(0.3, 0.09, 1.2), Vector3(0, 0.445, 0.05), red, 0.03)
	for z: float in [-0.45, 0.55]:
		Kit.block(g, Vector3(0.06, 0.4, 0.06), Vector3(0, 0, z), IRON)
		Kit.block(g, Vector3(0.4, 0.04, 0.08), Vector3(0, 0, z), IRON)
	Kit.block(g, Vector3(0.05, 0.05, 1.0), Vector3(0, 0.12, 0.05), IRON)
	for x: float in [-0.45, 0.45]:
		Kit.block(g, Vector3(0.05, 1.0, 0.05), Vector3(x, 0, -0.45), IRON)
		Kit.block(g, Vector3(0.12, 0.04, 0.3), Vector3(x, 0, -0.45), IRON)
		Kit.box(g, Vector3(0.05, 0.08, 0.04), Vector3(x, 0.98, -0.405), STEEL)
		Kit.cyl(g, 0.2, 0.05, Vector3(x * 1.4, 1.0, -0.45), DARK, Vector3(0, 0, 90), 14)
		Kit.cyl(g, 0.14, 0.04, Vector3(x * 1.4 - signf(x) * 0.045, 1.0, -0.45), red, Vector3(0, 0, 90), 12)
		Kit.cyl(g, 0.03, 0.05, Vector3(x * 1.4 - signf(x) * 0.09, 1.0, -0.45), STEEL, Vector3(0, 0, 90), 8)
	Kit.cyl(g, 0.015, 1.5, Vector3(0, 1.0, -0.45), STEEL, Vector3(0, 0, 90), 6)
	return g



## A neighbouring rowhouse, its front on the building line at v, built by the
## shared house kit (houses.gd) as one of the old Pen Lucy's stoop-front row
## houses: `look` the wall, two storeys and a flat roof, the door up two marble
## steps under a transom, sashes with lintels on some, a box oriel or tin
## awnings upstairs on some, a cornice in one of the old game's profiles, a
## chimney on some; `boarded` a vacant (plywood over its door and windows),
## `lit` some windows glowing. The trim, door and the rest are picked from u0
## and v, the same each time. Doors pair up as the old game's do: counting out
## from the place, the first house's door is on its far side, the next one's
## beside it, and so on. `n` is the node to build it in (the street's); u0 is
## its left edge; h the height of its front (the cornice's cap stands 0.3 over
## it). The box runs 3 m back behind the line; the steps reach about 0.75 m out
## in front and take that floor.
static func rowhouse(p: Node3D, n: Node3D, u0: float, v: float, look: Variant, boarded := false, lit := false, w := 5.0, h := 6.6) -> void:
	var houses: Variant = load("res://scripts/" + "houses.gd")      # (looked up when called: houses.gd preloads this script)
	var key := rnd(u0 * 1.37 + v * 0.71)
	var o: Dictionary = houses.style(key * 11.0 + 0.3)
	var wide: float = p.width
	var right_side := u0 >= wide - 0.01
	var nth := roundi(((u0 - wide) if right_side else (-u0 - w)) / w)
	var away := nth % 2 == 0
	o["wall"] = look
	o["door_left"] = (not right_side) if away else right_side
	o["f0"] = 0.36
	o["height"] = h + 0.3
	o["deep"] = 3.0
	o["boarded"] = boarded
	o["profile"] = houses.profile_for((7.0 if right_side else 0.0) + v * 1.3, false)      # one cornice for each side's row
	o["lit"] = houses.lit_pattern(key * 5.0, 6, 0.5) if lit else ""
	o["transom"] = lit
	if boarded:
		o["door"] = WOOD.darkened(0.25)
	var g := Kit.group(n, p.pt(u0, v + 0.075))
	var made: Dictionary = houses.stoop_front(g, w, o)
	var ds: float = made["door"]
	if float(made["stoop"]) > 0.0:
		p.block(u0 + ds - 0.7, v + 0.075, u0 + ds + 0.7, v + 0.075 + float(made["stoop"]))
